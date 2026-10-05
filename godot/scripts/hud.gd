class_name Hud
extends CanvasLayer
## In-match HUD, drawn in the style of mobile battle royales.

var world: Node
var font: Font
var bold: FontVariation
var draw_layer: Control
var touch: TouchUI
var feed: VBoxContainer
var banner: Label
var results: PanelContainer
var pause_panel: PanelContainer
var map_open := false
var bag_open := false
var hit_t := 0.0
var hit_head := false
var dmg_dirs: Array = []     # [{dir: Vector3, t}]
var _banner_t := 0.0

func _ready() -> void:
	layer = 5
	# Keep reading keys while the game is paused (Esc resumes).
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = load("res://assets/fonts/Cairo.ttf")
	bold = FontVariation.new()
	bold.base_font = font
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}

	draw_layer = Control.new()
	draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_layer.draw.connect(_draw_hud)
	add_child(draw_layer)

	feed = VBoxContainer.new()
	feed.position = Vector2(14, 60)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feed)

	banner = Label.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.position.y = 120
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 26)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	banner.add_theme_constant_override("outline_size", 6)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(banner)

	touch = TouchUI.new()
	touch.hud = self
	add_child(touch)
	touch.visible = Game.settings.controls == "touch"

	var p: Player = world.player
	p.hit_confirmed.connect(func(head, _killed, _pos): hit_t = 0.22; hit_head = head)
	p.damaged.connect(func(dir): dmg_dirs.append({"dir": dir, "t": 1.2}))
	p.message.connect(show_banner)
	show_banner("مرحباً في منطقة الصفر — اقفز من الطائرة فوق الجزيرة")
	Game.cursor_free = false
	if Game.settings.controls == "kbm":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Tweens die with their node, so nothing fires after leaving the match.
		create_tween().tween_callback(show_banner.bind("اضغط Ctrl لإظهار الماوس أو إخفائه")).set_delay(3.2)

func show_banner(text: String) -> void:
	banner.text = text
	banner.modulate.a = 1.0
	_banner_t = 3.0

func kill_feed(killer: String, victim: String, mine: bool, by_zone := false) -> void:
	var l := Label.new()
	if by_zone:
		l.text = "%s مات بالمنطقة الزرقاء" % victim
	elif killer != "":
		l.text = "%s ⟵ %s" % [victim, killer]
	else:
		l.text = "%s سقط" % victim
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color("ffd34d") if mine else Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	feed.add_child(l)
	if feed.get_child_count() > 5:
		feed.get_child(0).queue_free()
	l.create_tween().tween_callback(l.queue_free).set_delay(6.0)

func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	for d in dmg_dirs: d.t -= delta
	dmg_dirs = dmg_dirs.filter(func(d): return d.t > 0.0)
	if _banner_t > 0.0:
		_banner_t -= delta
		banner.modulate.a = clampf(_banner_t, 0.0, 1.0)
	draw_layer.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_M or event.physical_keycode == KEY_TAB:
			toggle_map()
		elif event.physical_keycode == KEY_B or event.physical_keycode == KEY_I:
			toggle_bag()
		elif event.keycode == KEY_CTRL or event.physical_keycode == KEY_CTRL:
			toggle_cursor()
		elif event.physical_keycode == KEY_ESCAPE:
			if results:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				toggle_pause()

func toggle_map() -> void:
	map_open = not map_open

## Ctrl: show the cursor (camera and shooting stop) or hide it again.
func toggle_cursor() -> void:
	if pause_panel or results: return
	if Game.settings.controls != "kbm":
		# Ctrl on a PC switches from on-screen buttons to keyboard + mouse.
		Game.settings.controls = "kbm"
		Game.save_data()
		touch.visible = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Game.cursor_free = true
		world.player.firing = false
		world.player.aiming = false
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.cursor_free = false

func toggle_bag() -> void:
	bag_open = not bag_open

func toggle_pause() -> void:
	if results: return
	if pause_panel:
		pause_panel.queue_free()
		pause_panel = null
		get_tree().paused = false
		if Game.settings.controls == "kbm":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Game.cursor_free = false
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_panel = _panel("إيقاف مؤقت", [["متابعة", toggle_pause], ["القائمة الرئيسية", _to_lobby]])
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS

func show_results(won: bool, rank: int, kills: int, reward: Dictionary = {}) -> void:
	var title := "فوز! أنت الناجي الأخير 🏆" if won else "الترتيب #%d" % rank
	var sub := "الإقصاءات: %d" % kills
	if not reward.is_empty():
		sub += "\n+%d ذهب    +%d خبرة موسم" % [reward.gold, reward.xp]
	results = _panel(title, [["العودة إلى اللوبي", _to_lobby]], sub)

func _to_lobby() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _panel(title: String, buttons: Array, sub: String = "") -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.92)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(28)
	pc.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", bold)
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", Color("ffd34d"))
	vb.add_child(t)
	if sub != "":
		var s := Label.new()
		s.text = sub
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(s)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(280, 52)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(b[1])
		vb.add_child(btn)
	add_child(pc)
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	return pc

# ---------- Drawing ----------
func _text(c: Control, pos: Vector2, s: String, size: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER, f: Font = null, width := -1.0) -> void:
	var fnt := f if f else font
	var w := width if width > 0.0 else 400.0
	var x := pos.x - w * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else (pos.x - w if align == HORIZONTAL_ALIGNMENT_RIGHT else pos.x)
	c.draw_string_outline(fnt, Vector2(x, pos.y), s, align, w, size, 4, Color(0, 0, 0, 0.6))
	c.draw_string(fnt, Vector2(x, pos.y), s, align, w, size, col)

func _draw_hud() -> void:
	var c := draw_layer
	var sz := c.size
	var p: Player = world.player
	if p == null: return
	_draw_town_labels(c, p)
	_draw_counters(c)
	_draw_compass(c, sz, p)
	_draw_minimap(c, sz, p)
	if p.state == "ground":
		_draw_bottom(c, sz, p)
		if p.scoped():
			_draw_scope(c, sz)
		_draw_crosshair(c, sz, p)
		_draw_prompt(c, sz, p)
	elif p.state in ["fall", "chute"]:
		_draw_gauges(c, sz, p)
	elif p.state == "plane":
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.68), "اضغط F للقفز" if world.plane_over_land() else "الطائرة تقترب من الجزيرة…", 20)
	for d in dmg_dirs:
		var rel: float = atan2(d.dir.x, -d.dir.z) + p.yaw
		var center := sz * 0.5
		var a := -rel - PI / 2.0
		c.draw_arc(center, 120.0, a - 0.3, a + 0.3, 12, Color(1, 0.2, 0.2, minf(1.0, d.t)), 6.0)
	if p.state == "ground" and world.zone.state != "idle" and world.zone.is_outside(p.global_position):
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.1, 0.3, 1.0, 0.13))
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.3), "أنت خارج المنطقة الآمنة!", 22, Color("9fd0ff"), HORIZONTAL_ALIGNMENT_CENTER, bold)
	if p.health < 30.0 and p.state != "dead":
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.7, 0, 0, 0.12 + 0.05 * sin(world.time * 6.0)))
	if bag_open and not map_open:
		_draw_bag(c, sz, p)
	if map_open:
		_draw_full_map(c, sz, p)

func _draw_counters(c: Control) -> void:
	# Mobile-BR style pills: "17 متبقي" and "0 الإقصاءات".
	var x := 14.0
	for b in [[str(world.alive_count()), "متبقي"], [str(world.player.kills), "الإقصاءات"]]:
		var w: float = 52.0 + String(b[1]).length() * 9.0
		c.draw_rect(Rect2(x, 12, w, 30), Color(0, 0, 0, 0.42))
		c.draw_rect(Rect2(x, 12, 40, 30), Color(0, 0, 0, 0.55))
		_text(c, Vector2(x + 20, 35), b[0], 19, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 40)
		_text(c, Vector2(x + 46, 34), b[1], 14, Color(0.92, 0.94, 0.96), HORIZONTAL_ALIGNMENT_LEFT, null, w - 46)
		x += w + 6

func _draw_compass(c: Control, sz: Vector2, p: Player) -> void:
	var bearing := fposmod(rad_to_deg(-p.yaw), 360.0)
	var w := minf(560.0, sz.x * 0.42)
	var cx := sz.x * 0.5
	var px_per_deg := w / 120.0
	var names := {0: "ش", 45: "ش.ق", 90: "ق", 135: "ج.ق", 180: "ج", 225: "ج.غ", 270: "غ", 315: "ش.غ"}
	var start := int(floor((bearing - 60.0) / 15.0)) * 15
	for d in range(start, int(bearing + 61.0), 15):
		var dd := posmod(d, 360)
		var x := cx + (d - bearing) * px_per_deg
		if absf(x - cx) > w * 0.5: continue
		var alpha := 1.0 - absf(d - bearing) / 70.0
		var major := dd % 45 == 0
		c.draw_rect(Rect2(x - 0.5, 8, 1, 9 if major else 5), Color(1, 1, 1, alpha))
		_text(c, Vector2(x, 36), names.get(dd, str(dd)), 16 if major else 12, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER, bold if major else null, 80)
	c.draw_colored_polygon(PackedVector2Array([Vector2(cx - 6, 46), Vector2(cx + 6, 46), Vector2(cx, 40)]), Color("ffd34d"))

func _draw_minimap(c: Control, sz: Vector2, p: Player) -> void:
	var size := 200.0
	var r := Rect2(sz.x - size - 12, 12, size, size)
	c.draw_rect(r, Color(0.1, 0.25, 0.32))
	var S: float = world.island.size
	var range_m := 500.0
	var pos := p.global_position
	if world.map_texture:
		var tex: Texture2D = world.map_texture
		var k := tex.get_width() / S
		var src := Rect2((pos.x - range_m * 0.5) * k, (pos.z - range_m * 0.5) * k, range_m * k, range_m * k)
		c.draw_texture_rect_region(tex, r, src)
	# Grid lines (map squares)
	var cell := S / Game.GRID
	var s := size / range_m
	for i in range(1, Game.GRID):
		var gx := r.position.x + size * 0.5 + (i * cell - pos.x) * s
		var gy := r.position.y + size * 0.5 + (i * cell - pos.z) * s
		if gx > r.position.x and gx < r.end.x: c.draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), Color(1, 1, 1, 0.25))
		if gy > r.position.y and gy < r.end.y: c.draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), Color(1, 1, 1, 0.25))
	_draw_zone(c, r, pos, s)
	_arrow(c, r.get_center(), -p.yaw, Color("ffd34d"), 9.0)
	c.draw_rect(r, Color(1, 1, 1, 0.4), false, 1.5)
	# Match clock and connection, under the minimap.
	var tm := int(world.time)
	var y := r.end.y + 4
	c.draw_rect(Rect2(r.position.x, y, size, 22), Color(0, 0, 0, 0.4))
	_text(c, Vector2(r.position.x + 8, y + 17), "⏱ %02d:%02d" % [tm / 60, tm % 60], 13, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, null, 90)
	# Zone timer and distance to safety.
	var zy := y + 26
	c.draw_rect(Rect2(r.position.x, zy, size, 22), Color(0.05, 0.2, 0.55, 0.55))
	_text(c, Vector2(r.position.x + size * 0.5, zy + 17), world.zone.label(), 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, null, size)
	var dist: float = world.zone.distance_to_safe(p.global_position)
	if dist > 0.0 and world.zone.state != "idle":
		_text(c, Vector2(r.position.x + size * 0.5, zy + 40), "🏃 %d م للمنطقة الآمنة" % int(dist), 13, Color("9fd0ff"), HORIZONTAL_ALIGNMENT_CENTER, null, size)
	_text(c, Vector2(r.end.x - 8, y + 17), "%d ms 📶" % (18 + int(world.time * 3.7) % 9), 12, Color("8ef08e"), HORIZONTAL_ALIGNMENT_RIGHT, null, 90)

func _arrow(c: Control, at: Vector2, ang: float, col: Color, s: float) -> void:
	var f := Vector2(sin(ang), -cos(ang))
	var rgt := Vector2(-f.y, f.x)
	c.draw_colored_polygon(PackedVector2Array([at + f * s, at - f * s * 0.6 + rgt * s * 0.6, at - f * s * 0.2, at - f * s * 0.6 - rgt * s * 0.6]), col)

## Weapon card rectangles (also used by the touch UI as tap areas).
static func slot_rect(i: int, sz: Vector2) -> Rect2:
	var w: float = [150.0, 150.0, 92.0][i]
	var x: float = sz.x * 0.5 + [-160.0, 2.0, 164.0][i]
	return Rect2(x, sz.y - 98.0, w, 62.0)

func _draw_bottom(c: Control, sz: Vector2, p: Player) -> void:
	# Health bar.
	var w := 360.0
	var x0 := sz.x * 0.5 - w * 0.5
	var y := sz.y - 26.0
	c.draw_rect(Rect2(x0, y, w, 8), Color(0, 0, 0, 0.5))
	var hp := clampf(p.health / 100.0, 0.0, 1.0)
	c.draw_rect(Rect2(x0, y, w * hp, 8), Color.WHITE if hp > 0.6 else (Color("ffcf5a") if hp > 0.3 else Color("ff3d4a")))
	c.draw_rect(Rect2(x0, y, w, 8), Color(1, 1, 1, 0.35), false, 1.0)
	# Boost: four segments above the health bar.
	if p.boost > 0.0:
		var seg := (w - 6.0) / 4.0
		for i in 4:
			var fill := clampf((p.boost - i * 25.0) / 25.0, 0.0, 1.0)
			c.draw_rect(Rect2(x0 + i * (seg + 2.0), y - 6, seg, 3), Color(0, 0, 0, 0.4))
			c.draw_rect(Rect2(x0 + i * (seg + 2.0), y - 6, seg * fill, 3), Color("ffae2b"))
	# Vest, helmet and backpack levels on the left of the health bar.
	var gx := x0 - 34.0
	for g in [["helmet", Items.HELMET], ["vest", Items.VEST], ["pack", null]]:
		var lvl: int = p.gear[g[0]]
		if lvl <= 0: continue
		var col := Color.WHITE
		if g[1] != null:
			var f: float = float(p.gear[g[0] + "_dur"]) / float(g[1][lvl].dur)
			col = Color.WHITE if f > 0.6 else (Color("ffcf5a") if f > 0.3 else Color("ff5a5a"))
		_gear_icon(c, Vector2(gx, y - 8), g[0], lvl, col)
		gx -= 34.0
	# Weapon cards with silhouettes and ammo.
	for i in 3:
		var rr := slot_rect(i, sz)
		var active := p.active == i
		var s = p.slots[i]
		c.draw_rect(rr, Color(0, 0, 0, 0.5) if active else Color(0, 0, 0, 0.3))
		c.draw_rect(rr, Color("ffd34d") if active else Color(1, 1, 1, 0.18), false, 1.5 if active else 1.0)
		if s == null:
			_text(c, Vector2(rr.get_center().x, rr.position.y + 38), str(i + 1), 18, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_CENTER, bold, rr.size.x)
			continue
		var wd: Dictionary = Game.WEAPONS[s.id]
		_gun_icon(c, Rect2(rr.position + Vector2(8, 6), Vector2(rr.size.x - 16, 30)), wd.cls, Color.WHITE if active else Color(1, 1, 1, 0.75))
		var ammo_txt := "%d/%d" % [s.mag, p.ammo[wd.ammo]]
		_text(c, Vector2(rr.position.x + 6, rr.end.y - 7), ammo_txt, 14, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, bold, rr.size.x)
		_text(c, Vector2(rr.end.x - 6, rr.end.y - 7), wd.name, 11, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, null, rr.size.x)
		if active:
			c.draw_colored_polygon(PackedVector2Array([Vector2(rr.get_center().x - 6, rr.position.y - 8), Vector2(rr.get_center().x + 6, rr.position.y - 8), Vector2(rr.get_center().x, rr.position.y - 2)]), Color("ffd34d"))
	if p.reload_t > 0.0:
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.62), "إعادة تلقيم…", 18, Color("ffcf5a"))

## Small icon for worn gear with its level number.
func _gear_icon(c: Control, at: Vector2, kind: String, lvl: int, col: Color) -> void:
	c.draw_rect(Rect2(at - Vector2(14, 14), Vector2(28, 28)), Color(0, 0, 0, 0.45))
	match kind:
		"helmet": c.draw_arc(at + Vector2(0, 4), 9.0, PI, TAU, 12, col, 4.0)
		"vest":
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-8, -8), at + Vector2(-3, -8), at + Vector2(0, -4), at + Vector2(3, -8), at + Vector2(8, -8), at + Vector2(8, 9), at + Vector2(-8, 9)]), col)
		_:
			c.draw_rect(Rect2(at - Vector2(7, 6), Vector2(14, 15)), col)
			c.draw_arc(at + Vector2(0, -6), 4.0, PI, TAU, 8, col, 2.0)
	_text(c, at + Vector2(9, 14), str(lvl), 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 14)

## Side-view gun silhouette for the weapon cards.
func _gun_icon(c: Control, r: Rect2, cls: String, col: Color) -> void:
	var shapes := {
		# Normalised polygons (x 0..1 left = stock, y 0..1).
		"ar": [[0.0, 0.35], [0.22, 0.3], [0.3, 0.2], [0.62, 0.2], [0.66, 0.32], [1.0, 0.32], [1.0, 0.42], [0.66, 0.44], [0.6, 0.55], [0.5, 0.55], [0.47, 0.95], [0.4, 0.95], [0.4, 0.55], [0.32, 0.55], [0.3, 0.8], [0.24, 0.8], [0.22, 0.55], [0.0, 0.6]],
		"smg": [[0.08, 0.35], [0.25, 0.3], [0.3, 0.2], [0.75, 0.2], [0.78, 0.32], [0.95, 0.32], [0.95, 0.42], [0.75, 0.46], [0.6, 0.5], [0.56, 0.95], [0.48, 0.95], [0.48, 0.5], [0.36, 0.5], [0.34, 0.78], [0.27, 0.78], [0.25, 0.55], [0.08, 0.55]],
		"shotgun": [[0.0, 0.4], [0.28, 0.32], [0.34, 0.25], [1.0, 0.25], [1.0, 0.36], [0.6, 0.4], [0.6, 0.5], [0.36, 0.52], [0.34, 0.75], [0.27, 0.75], [0.26, 0.52], [0.0, 0.66]],
		"sr": [[0.0, 0.42], [0.25, 0.36], [0.3, 0.3], [0.38, 0.3], [0.38, 0.12], [0.6, 0.12], [0.6, 0.3], [1.0, 0.33], [1.0, 0.39], [0.55, 0.44], [0.4, 0.5], [0.33, 0.72], [0.27, 0.72], [0.26, 0.52], [0.0, 0.62]],
		"pistol": [[0.25, 0.2], [0.85, 0.2], [0.85, 0.4], [0.55, 0.42], [0.5, 0.9], [0.32, 0.9], [0.36, 0.42], [0.25, 0.4]],
	}
	var pts := PackedVector2Array()
	for q in shapes.get(cls, shapes.ar):
		pts.append(r.position + Vector2(q[0] * r.size.x, q[1] * r.size.y))
	c.draw_colored_polygon(pts, col)

func _draw_crosshair(c: Control, sz: Vector2, p: Player) -> void:
	var ctr := sz * 0.5
	if not p.scoped():
		var w := p.weapon()
		var gap := 6.0 + (float(w.get("spread", 2.0)) * (0.4 if p.aiming else 1.0) * 5.0 if not w.is_empty() else 4.0)
		var col := Color("ffcf5a") if p.reload_t > 0.0 else Color(1, 1, 1, 0.9)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			c.draw_line(ctr + d * gap, ctr + d * (gap + 9.0), col, 2.0)
	c.draw_rect(Rect2(ctr - Vector2(1.5, 1.5), Vector2(3, 3)), Color("ff3d4a"))
	if hit_t > 0.0:
		var hc := Color("ff4040") if hit_head else Color.WHITE
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			c.draw_line(ctr + d * 7.0, ctr + d * 15.0, hc, 2.5)

func _draw_scope(c: Control, sz: Vector2) -> void:
	var ctr := sz * 0.5
	var r := minf(sz.x, sz.y) * 0.44
	# Black mask around a round scope.
	var pts := PackedVector2Array()
	for i in 65:
		pts.append(ctr + Vector2(r, 0).rotated(i * TAU / 64.0))
	c.draw_rect(Rect2(0, 0, ctr.x - r, sz.y), Color.BLACK)
	c.draw_rect(Rect2(ctr.x + r, 0, sz.x - ctr.x - r, sz.y), Color.BLACK)
	for i in 64:
		var a := pts[i]
		var b := pts[i + 1]
		var top_y := 0.0
		c.draw_colored_polygon(PackedVector2Array([a, b, Vector2(b.x, top_y if b.y < ctr.y else sz.y), Vector2(a.x, top_y if a.y < ctr.y else sz.y)]), Color.BLACK)
	c.draw_line(Vector2(ctr.x - r, ctr.y), Vector2(ctr.x + r, ctr.y), Color(0, 0, 0, 0.85), 1.5)
	c.draw_line(Vector2(ctr.x, ctr.y - r), Vector2(ctr.x, ctr.y + r), Color(0, 0, 0, 0.85), 1.5)

func _draw_prompt(c: Control, sz: Vector2, p: Player) -> void:
	if p.heal_id != "":
		_draw_heal(c, sz, p)
		return
	var it = world.nearest_pickup(p.global_position, 2.4)
	if it == null: return
	var label: String = world.pickup_name(it.get_meta("data"))
	var key := "[F] " if Game.settings.controls == "kbm" else ""
	_text(c, Vector2(sz.x * 0.5, sz.y * 0.64), key + "التقاط: " + label, 19, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold)

func _draw_heal(c: Control, sz: Vector2, p: Player) -> void:
	var h: Dictionary = Items.HEALS[p.heal_id]
	var ctr := Vector2(sz.x * 0.5, sz.y * 0.62)
	var k := 1.0 - p.heal_t / float(h.time)
	c.draw_arc(ctr, 26.0, 0, TAU, 40, Color(0, 0, 0, 0.5), 6.0)
	c.draw_arc(ctr, 26.0, -PI / 2, -PI / 2 + TAU * k, 40, Color("7dff8a"), 6.0)
	_text(c, ctr + Vector2(0, 7), "%.1f" % p.heal_t, 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 60)
	_text(c, ctr + Vector2(0, 52), "جاري استخدام " + h.name + " — الإطلاق يلغيه", 15, Color.WHITE)

func _draw_gauges(c: Control, sz: Vector2, p: Player) -> void:
	var h := minf(360.0, sz.y * 0.48)
	var top := sz.y * 0.5 - h * 0.5
	var alt: float = p.global_position.y - world.ground_height(p.global_position)
	for g in [[sz.x * 0.5 - 180.0, alt, Player.PLANE_ALT, "الارتفاع", "متر", -1.0], [sz.x * 0.5 + 180.0, minf(234.0, p.air_speed), 250.0, "السرعة", "كم/س", 1.0]]:
		var x: float = g[0]
		c.draw_line(Vector2(x, top), Vector2(x, top + h), Color(1, 1, 1, 0.8), 2.0)
		for i in 11:
			var yy := top + h * i / 10.0
			c.draw_line(Vector2(x, yy), Vector2(x + g[5] * (12.0 if i % 5 == 0 else 6.0), yy), Color(1, 1, 1, 0.8), 2.0)
		var yv := top + h * (1.0 - clampf(g[1] / g[2], 0.0, 1.0))
		var bx: float = x + g[5] * 50.0
		c.draw_rect(Rect2(bx - 36, yv - 20, 72, 40), Color(0, 0, 0, 0.5))
		_text(c, Vector2(bx, yv + 4), str(int(g[1])), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 72)
		_text(c, Vector2(bx, yv + 17), g[4], 11, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER, null, 72)
		_text(c, Vector2(x, top + h + 22), g[3], 14)

func _draw_town_labels(c: Control, p: Player) -> void:
	var airborne: bool = p.state == "plane" or (p.state in ["fall", "chute"] and p.global_position.y - world.ground_height(p.global_position) > 80.0)
	if not airborne: return
	var cam := p.camera
	for t in world.island.towns:
		var wp := Vector3(t.pos.x, world.island.height_at(t.pos.x, t.pos.y) + 20.0, t.pos.y)
		if cam.is_position_behind(wp): continue
		var sp := cam.unproject_position(wp)
		var d := cam.global_position.distance_to(wp)
		var fs := int(clampf(16000.0 / d, 14.0, 34.0))
		_text(c, sp, t.name, fs, Color("ffe08a") if t.military else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold)

func _draw_full_map(c: Control, sz: Vector2, p: Player) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.65))
	var size := minf(sz.x, sz.y) - 70.0
	var r := Rect2((sz.x - size) * 0.5, (sz.y - size) * 0.5, size, size)
	if world.map_texture:
		c.draw_texture_rect(world.map_texture, r, false)
	var S: float = world.island.size
	var k := size / S
	for i in range(1, Game.GRID):
		var o := size * i / Game.GRID
		c.draw_line(Vector2(r.position.x + o, r.position.y), Vector2(r.position.x + o, r.end.y), Color(1, 1, 1, 0.25))
		c.draw_line(Vector2(r.position.x, r.position.y + o), Vector2(r.end.x, r.position.y + o), Color(1, 1, 1, 0.25))
	var letters := "ABCDEFGH"
	for i in Game.GRID:
		var o := size * (i + 0.5) / Game.GRID
		_text(c, Vector2(r.position.x + o, r.position.y + 18), letters[i], 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 30)
		_text(c, Vector2(r.position.x + 12, r.position.y + o + 5), str(i + 1), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 30)
	for t in world.island.towns:
		_text(c, r.position + t.pos * k, t.name, 14, Color("ffe08a") if t.military else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold)
	if world.plane_active:
		c.draw_dashed_line(r.position + Vector2(world.plane_from.x, world.plane_from.z) * k, r.position + Vector2(world.plane_to.x, world.plane_to.z) * k, Color(1, 1, 1, 0.7), 2.0, 8.0)
	var z: Zone = world.zone
	if z.state != "idle":
		_clipped_circle(c, r, r.position + z.center * k, z.radius * k, Color(0.25, 0.5, 1.0, 0.95), 2.5)
		_clipped_circle(c, r, r.position + z.next_center * k, z.next_radius * k, Color.WHITE, 2.0)
	_arrow(c, r.position + Vector2(p.global_position.x, p.global_position.z) * k, -p.yaw, Color("ffd34d"), 10.0)
	c.draw_rect(r, Color(1, 1, 1, 0.5), false, 2.0)
	_text(c, Vector2(sz.x * 0.5, r.end.y + 26), "كل مربع = %d م — اضغط M للإغلاق" % int(S / Game.GRID), 14)

func _draw_bag(c: Control, sz: Vector2, p: Player) -> void:
	var rows := []
	for i in 3:
		var sl = p.slots[i]
		rows.append([["السلاح 1", "السلاح 2", "المسدس"][i], "—" if sl == null else Game.WEAPONS[sl.id].name])
	for g in ["helmet", "vest", "pack"]:
		var lvl: int = p.gear[g]
		var label := {"helmet": "الخوذة", "vest": "السترة", "pack": "الحقيبة"}[g] as String
		var val := "—" if lvl == 0 else ("مستوى %d" % lvl + ("" if g == "pack" else "  (%d%%)" % int(100.0 * float(p.gear[g + "_dur"]) / float((Items.HELMET if g == "helmet" else Items.VEST)[lvl].dur))))
		rows.append([label, val])
	for at in p.ammo:
		if p.ammo[at] > 0: rows.append(["ذخيرة " + Game.AMMO_NAMES[at], str(p.ammo[at])])
	for hid in Items.HEAL_ORDER:
		if p.heals[hid] > 0: rows.append([Items.HEALS[hid].name, "×%d" % p.heals[hid]])
	var r := Rect2(16, 70, 320, 84 + 26 * rows.size())
	c.draw_rect(r, Color(0.03, 0.05, 0.08, 0.84))
	c.draw_rect(r, Color(1, 1, 1, 0.15), false, 1.0)
	_text(c, Vector2(r.position.x + 14, r.position.y + 30), "الحقيبة", 20, Color("ffd34d"), HORIZONTAL_ALIGNMENT_LEFT, bold, 200)
	_text(c, Vector2(r.end.x - 14, r.position.y + 30), "السعة %d / %d" % [int(p.used_space()), int(p.capacity())], 14, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, null, 160)
	var y := r.position.y + 60
	for row in rows:
		_text(c, Vector2(r.position.x + 14, y), row[0], 15, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, null, 170)
		_text(c, Vector2(r.end.x - 14, y), row[1], 15, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, bold, 150)
		y += 26
	if Game.settings.controls == "kbm":
		_text(c, Vector2(r.position.x + 14, r.end.y - 8), "H علاج • G منشّط • 4-8 أداة محددة", 12, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_LEFT, null, 300)

## Blue zone and next safe circle on the minimap (world -> minimap: centre + (q - pos) * s).
func _draw_zone(c: Control, r: Rect2, pos: Vector3, s: float) -> void:
	var z: Zone = world.zone
	if z.state == "idle": return
	var me := Vector2(pos.x, pos.z)
	var ctr := r.get_center()
	var cur := ctr + (z.center - me) * s
	var nxt := ctr + (z.next_center - me) * s
	_clipped_circle(c, r, cur, z.radius * s, Color(0.25, 0.5, 1.0, 0.95), 2.5)
	_clipped_circle(c, r, nxt, z.next_radius * s, Color.WHITE, 1.8)
	# Line to the safe zone when outside it.
	if z.distance_to_safe(pos) > 0.0:
		var dir := (z.next_center - me).normalized()
		c.draw_line(ctr, ctr + dir * (r.size.x * 0.48), Color(1, 1, 1, 0.8), 1.5)

## Draws only the part of a circle that lies inside rect r.
func _clipped_circle(c: Control, r: Rect2, at: Vector2, radius: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var segs := 192
	for i in segs + 1:
		var q: Vector2 = at + Vector2(radius, 0).rotated(i * TAU / segs)
		if r.has_point(q):
			pts.append(q)
		else:
			if pts.size() > 1: c.draw_polyline(pts, col, width)
			pts = PackedVector2Array()
	if pts.size() > 1: c.draw_polyline(pts, col, width)
