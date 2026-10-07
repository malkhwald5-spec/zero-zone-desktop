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
var flash_t := 0.0                  # flashbang: seconds of white-out left
var flash_len := 1.0
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
	var wtext: String = {"rain": "الطقس: مطر — الرؤية أقل والأصوات أوطى", "sunset": "الطقس: غروب"}.get(world.weather, "")
	if wtext != "":
		create_tween().tween_callback(show_banner.bind(wtext)).set_delay(6.6)

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

## Someone knocked down (team match).
func knock_feed(by: String, victim: String, mine: bool) -> void:
	var l := Label.new()
	l.text = ("%s أسقط %s" % [by, victim]) if by != "" else ("%s انسقط" % victim)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color("ffd34d") if mine else Color("ffb0a0"))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	feed.add_child(l)
	if feed.get_child_count() > 5:
		feed.get_child(0).queue_free()
	l.create_tween().tween_callback(l.queue_free).set_delay(6.0)

## You died but your team plays on: after the killcam, watch a teammate.
func team_still_alive() -> void:
	show_banner("فريقك لسا بيقاتل — بتتفرج عليهم")
	get_tree().create_timer(KILLCAM_TIME).timeout.connect(func():
		if not results and not spectating and world.player.state == "dead" and world.team_alive(world.player.team):
			start_spectate())

## You and your teammates, in slot order.
func _team() -> Array:
	var t: Array = [world.player]
	t.append_array(world.teammates(world.player))
	t.sort_custom(func(a, b): return a.slot < b.slot)
	return t

## Left side: each teammate's number, name and health (red while knocked).
func _draw_team(c: Control) -> void:
	if world.team_size <= 1: return
	feed.position.y = 60.0 + world.team_size * 30.0 + 8.0     # kill feed goes under the team list
	var y := 52.0
	for m in _team():
		var col: Color = world.TEAM_COLORS[m.slot % 4]
		var gone: bool = world.is_gone(m)
		var down: bool = world.is_down(m)
		c.draw_rect(Rect2(14, y, 200, 26), Color(0, 0, 0, 0.35))
		c.draw_rect(Rect2(14, y, 24, 26), col if not gone else Color(0.4, 0.4, 0.4))
		_text(c, Vector2(26, y + 19), str(m.slot + 1), 14, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER, bold, 24)
		var nm: String = "أنت" if m == world.player else m.display_name
		_text(c, Vector2(44, y + 13), nm, 12, Color(1, 1, 1, 0.5 if gone else 0.95), HORIZONTAL_ALIGNMENT_LEFT, null, 165)
		var hp := 0.0 if gone else clampf(float(m.health) / 100.0, 0.0, 1.0)
		c.draw_rect(Rect2(44, y + 17, 162, 5), Color(1, 1, 1, 0.15))
		c.draw_rect(Rect2(44, y + 17, 162 * hp, 5), Color("ff4a3a") if down else Color.WHITE)
		if gone:
			_text(c, Vector2(200, y + 14), "✕", 13, Color(1, 0.4, 0.4), HORIZONTAL_ALIGNMENT_CENTER, bold, 20)
		elif down:
			_text(c, Vector2(196, y + 13), "مُسقط", 11, Color("ff8a7a"), HORIZONTAL_ALIGNMENT_CENTER, bold, 50)
		y += 30.0

## Teammates' names over their heads (coloured), with a + when knocked.
func _draw_team_tags(c: Control, p: Player) -> void:
	if world.team_size <= 1: return
	var cam := get_viewport().get_camera_3d()
	if cam == null: return
	for m in world.teammates(p):
		if world.is_gone(m) or not m.visible: continue
		var wp: Vector3 = m.global_position + Vector3(0, 2.15 if not world.is_down(m) else 0.9, 0)
		if cam.is_position_behind(wp): continue
		var sp := cam.unproject_position(wp)
		var d: float = cam.global_position.distance_to(wp)
		var col: Color = world.TEAM_COLORS[m.slot % 4]
		if world.is_down(m):
			c.draw_circle(sp + Vector2(0, -16), 9.0, Color("e03a2a"))
			c.draw_rect(Rect2(sp + Vector2(-2, -22), Vector2(4, 12)), Color.WHITE)
			c.draw_rect(Rect2(sp + Vector2(-6, -18), Vector2(12, 4)), Color.WHITE)
		_text(c, sp, "%s  %dم" % [m.display_name, int(d)] if d > 30.0 else m.display_name, 13, col, HORIZONTAL_ALIGNMENT_CENTER, bold, 220)

## Knocked: red edges, bleed bar; next to a knocked mate: revive prompt/progress.
func _draw_revive(c: Control, sz: Vector2, p: Player) -> void:
	if p.knocked:
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.6, 0.0, 0.0, 0.16))
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.3), "انسقطت! ازحف لعند زميلك ليرفعك", 22, Color("ff9a8a"), HORIZONTAL_ALIGNMENT_CENTER, bold, 600)
		var w := 300.0
		var r := Rect2(sz.x * 0.5 - w * 0.5, sz.y * 0.3 + 14, w, 8)
		c.draw_rect(r, Color(0, 0, 0, 0.5))
		c.draw_rect(Rect2(r.position, Vector2(w * clampf(p.health / 100.0, 0.0, 1.0), 8)), Color("ff3a2a"))
		if p.revived_by_t > 0.0:
			_progress(c, Vector2(sz.x * 0.5, sz.y * 0.62), p.revived_by_t, "زميلك عم يرفعك…")
			p.revived_by_t = maxf(0.0, p.revived_by_t - get_process_delta_time() * 0.5)   # decays unless refreshed
		return
	if p.revive_target:
		_progress(c, Vector2(sz.x * 0.5, sz.y * 0.62), p.revive_t / Player.REVIVE_TIME, "عم ترفع " + p.revive_target.display_name + "… خليك ثابت")
		return
	var mate := p.downed_mate_near()
	if mate:
		var key := "[%s] " % Game.key_label(Game.key("interact")) if Game.settings.controls == "kbm" else ""
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.64), key + "اضغط مطوّل لترفع " + mate.display_name, 19, Color("7dff8a"), HORIZONTAL_ALIGNMENT_CENTER, bold, 600)

func _progress(c: Control, ctr: Vector2, k: float, label: String) -> void:
	c.draw_arc(ctr, 26.0, 0, TAU, 40, Color(0, 0, 0, 0.5), 6.0)
	c.draw_arc(ctr, 26.0, -PI / 2, -PI / 2 + TAU * clampf(k, 0.0, 1.0), 40, Color("7dff8a"), 6.0)
	c.draw_rect(Rect2(ctr + Vector2(-3, -11), Vector2(6, 22)), Color("7dff8a"))
	c.draw_rect(Rect2(ctr + Vector2(-11, -3), Vector2(22, 6)), Color("7dff8a"))
	_text(c, ctr + Vector2(0, 52), label, 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, null, 500)

## Flashbang hit you: white screen and muffled sound for `secs` seconds.
func flash(amount: float, secs: float) -> void:
	flash_len = maxf(secs, 0.1)
	flash_t = maxf(flash_t, secs)
	AudioServer.set_bus_volume_db(0, -18.0 * amount)

func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	if flash_t > 0.0:
		flash_t = maxf(0.0, flash_t - delta)
		var vol := AudioServer.get_bus_volume_db(0)
		AudioServer.set_bus_volume_db(0, 0.0 if flash_t <= 0.0 else move_toward(vol, 0.0, delta * 18.0 / flash_len))
	for d in dmg_dirs: d.t -= delta
	dmg_dirs = dmg_dirs.filter(func(d): return d.t > 0.0)
	if _banner_t > 0.0:
		_banner_t -= delta
		banner.modulate.a = clampf(_banner_t, 0.0, 1.0)
	banner.visible = not map_open and not bag_open
	draw_layer.queue_redraw()

func _input(event: InputEvent) -> void:
	if map_open and Game.settings.controls == "kbm" and _map_input(event):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var act := Game.action_for(event.physical_keycode)
		if act == "map" or (event.physical_keycode == KEY_TAB and Game.action_for(KEY_TAB) == ""):
			toggle_map()
		elif act == "bag" or (event.physical_keycode == KEY_I and Game.action_for(KEY_I) == ""):
			toggle_bag()
		elif act == "cursor":
			toggle_cursor()
		elif event.physical_keycode == KEY_ESCAPE and bag_open:
			toggle_bag()
		elif event.physical_keycode == KEY_ESCAPE and map_open:
			toggle_map()
		elif event.physical_keycode == KEY_ESCAPE:
			if results:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				toggle_pause()

func toggle_map() -> void:
	if pause_panel or results: return
	map_open = not map_open
	_map_drag = false
	if map_open:
		if bag_open: toggle_bag()
		map_zoom = 1.0
		map_focus = Vector2.ONE * world.island.size * 0.5
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Game.cursor_free = true
		world.player.firing = false
		world.player.aiming = false
	elif Game.settings.controls == "kbm":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.cursor_free = false

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

var inventory: InventoryPanel

## B / I: the bag screen with the mouse free; closing gives the mouse back.
func toggle_bag() -> void:
	if pause_panel or results: return
	bag_open = not bag_open
	if bag_open:
		if map_open: toggle_map()
		inventory = InventoryPanel.new(world.player, world)
		add_child(inventory)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Game.cursor_free = true
		world.player.firing = false
		world.player.aiming = false
	else:
		if inventory:
			inventory.queue_free()
			inventory = null
		if Game.settings.controls == "kbm":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Game.cursor_free = false

func toggle_pause() -> void:
	if results: return
	if pause_panel:
		Game.save_data()
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
	# Look and aim speed can be changed without leaving the match.
	var vb: VBoxContainer = pause_panel.get_child(0)
	for opt in [["حساسية النظر", "sensitivity", 0.3, 3.0, 1.0], ["حساسية التصويب والسكوب", "aim_sens", 0.15, 1.2, 0.45]]:
		var l := Label.new()
		l.text = opt[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
		var sl := HSlider.new()
		sl.min_value = opt[2]
		sl.max_value = opt[3]
		sl.step = 0.05
		sl.value = float(Game.settings.get(opt[1], opt[4]))
		sl.custom_minimum_size = Vector2(280, 28)
		var key: String = opt[1]
		sl.value_changed.connect(func(v):
			Game.settings[key] = v
			world.player.sens = float(Game.settings.sensitivity))
		vb.add_child(sl)

func show_results(won: bool, rank: int, kills: int, reward: Dictionary = {}) -> void:
	if spectating:
		spectating = false
		if _spec_panel:
			_spec_panel.queue_free()
			_spec_panel = null
	var title := ("فوز! أنت الناجي الأخير 🏆" if world.team_size <= 1 else "فوز! فريقك آخر فريق 🏆") if won else "الترتيب #%d" % rank
	var sub := "الإقصاءات: %d" % kills
	if not reward.is_empty():
		sub += "\n+%d ذهب    +%d خبرة موسم" % [reward.gold, reward.xp]
	_results_args = [title, sub]
	var p: Player = world.player
	if not won and p.state == "dead" and is_instance_valid(p.killer) and p.dead_t < KILLCAM_TIME:
		# Killcam first: the results come up after a few seconds.
		get_tree().create_timer(KILLCAM_TIME - p.dead_t).timeout.connect(_show_results_panel)
	else:
		_show_results_panel()

const KILLCAM_TIME := 4.0
var _results_args := ["", ""]
var spectating := false

func _show_results_panel() -> void:
	if results or spectating: return
	var buttons := []
	if world.player.state == "dead" and world.alive_count() > 0:
		buttons.append(["مشاهدة اللاعبين", start_spectate])
	buttons.append(["العودة إلى اللوبي", _to_lobby])
	results = _panel(_results_args[0], buttons, _results_args[1])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Watch the match go on: your killer first, then whoever is still alive.
func start_spectate() -> void:
	var p: Player = world.player
	var first: Node3D = p.killer if p.killer is Bot and not p.killer.dead and not world.team_alive(p.team) else _next_alive(null)
	if first == null: return
	if results:
		results.queue_free()
		results = null
	spectating = true
	p.spectate = first
	_spec_bar()

func stop_spectate() -> void:
	spectating = false
	world.player.spectate = null
	if _spec_panel:
		_spec_panel.queue_free()
		_spec_panel = null
	_show_results_panel()

## The next player still alive after `cur` (in list order).
func _next_alive(cur: Node3D) -> Node3D:
	var alive: Array = world.bots.filter(func(b): return not b.dead)
	# While your team lives you watch your teammates only.
	var mates: Array = alive.filter(func(b): return b.team == world.player.team)
	if world.team_size > 1 and not mates.is_empty(): alive = mates
	if alive.is_empty(): return null
	var i: int = alive.find(cur)
	return alive[(i + 1) % alive.size()]

func spectate_next() -> void:
	var nxt := _next_alive(world.player.spectate)
	if nxt: world.player.spectate = nxt

var _spec_panel: Control
var _spec_switch_t := 0.0

func _spec_bar() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.add_child(UiKit.button("اللاعب التالي", spectate_next, Vector2(170, 44), UiKit.style(Color(0, 0, 0, 0.55), 8), 16))
	hb.add_child(UiKit.button("النتيجة", stop_spectate, Vector2(120, 44), UiKit.style(Color(0, 0, 0, 0.55), 8), 16))
	hb.add_child(UiKit.button("اللوبي", _to_lobby, Vector2(110, 44), UiKit.style(Color(0, 0, 0, 0.55), 8), 16))
	add_child(hb)
	hb.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hb.offset_top = -70
	hb.offset_bottom = -20
	_spec_panel = hb

## While dead: killcam text, then who you are watching.
func _draw_dead(c: Control, sz: Vector2, p: Player) -> void:
	if spectating and is_instance_valid(p.spectate):
		var s: Bot = p.spectate
		# The one you watch died: move on to whoever killed them, or the next.
		if s.dead:
			_spec_switch_t += get_process_delta_time()
			if _spec_switch_t > 2.0:
				_spec_switch_t = 0.0
				p.spectate = _next_alive(s)
		var top := Rect2(sz.x * 0.5 - 200, 70, 400, 58)
		c.draw_rect(top, Color(0, 0, 0, 0.5))
		_text(c, Vector2(sz.x * 0.5, 96), "تشاهد: " + s.display_name, 20, Color("ffd34d"), HORIZONTAL_ALIGNMENT_CENTER, bold, 400)
		var wname: String = Game.WEAPONS[s.weapon_id].name if s.armed() else "بدون سلاح"
		_text(c, Vector2(sz.x * 0.5, 120), "%s • الصحة %d • الإقصاءات %d" % [wname, int(maxf(s.health, 0.0)), s.kills], 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, null, 400)
		if world.alive_count() <= 1 and not s.dead:
			_text(c, Vector2(sz.x * 0.5, sz.y * 0.3), "الفائز: " + s.display_name + " 🏆", 30, Color("ffd34d"), HORIZONTAL_ALIGNMENT_CENTER, bold, 600)
		return
	if is_instance_valid(p.killer) and p.dead_t < KILLCAM_TIME + 0.5 and results == null:
		var k: Node3D = p.killer
		var kname: String = k.display_name if "display_name" in k else ""
		var how := ""
		if k is Bot and k.armed(): how = " بـ " + Game.WEAPONS[k.weapon_id].name
		var d := int(k.global_position.distance_to(p.global_position))
		c.draw_rect(Rect2(0, sz.y * 0.72, sz.x, 74), Color(0, 0, 0, 0.55))
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.72 + 32), "قتلك " + kname + how + " من %d م" % d, 24, Color("ff6a5a"), HORIZONTAL_ALIGNMENT_CENTER, bold, 800)
		if k is Bot:
			_text(c, Vector2(sz.x * 0.5, sz.y * 0.72 + 58), "صحته المتبقية %d" % int(maxf(k.health, 0.0)), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, null, 400)

func _to_lobby() -> void:
	get_tree().paused = false
	AudioServer.set_bus_volume_db(0, 0.0)
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
	_draw_team(c)
	_draw_team_tags(c, p)
	_draw_compass(c, sz, p)
	_draw_minimap(c, sz, p)
	if p.state == "ground":
		_draw_bottom(c, sz, p)
		if p.scoped():
			_draw_scope(c, sz, p.weapon())
		else:
			_draw_crosshair(c, sz, p)
		_draw_revive(c, sz, p)
		if not p.knocked and p.revive_target == null and p.downed_mate_near() == null: _draw_prompt(c, sz, p)
		if p.throw_ready: _draw_throw_arc(c, p)
		_draw_throw_card(c, sz, p)
	elif p.state == "vehicle":
		_draw_vehicle(c, sz, p)
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
	if p.state == "dead":
		_draw_dead(c, sz, p)
	if flash_t > 0.0:
		# Blinded: pure white, then it fades out over the last part.
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, clampf(flash_t / (flash_len * 0.6), 0.0, 1.0)))
	if map_open:
		_draw_full_map(c, sz, p)

func _draw_counters(c: Control) -> void:
	# Mobile-BR style pills: "17 متبقي" and "0 الإقصاءات".
	var x := 14.0
	var pills := [[str(world.alive_count()), "متبقي"], [str(world.player.kills), "الإقصاءات"]]
	if world.team_size > 1: pills.insert(1, [str(world.teams_alive()), "فرق"])
	for b in pills:
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
	# Your map marker on the compass, with its distance.
	if marker != Vector2.INF:
		var to := marker - Vector2(p.global_position.x, p.global_position.z)
		var mb := fposmod(rad_to_deg(atan2(to.x, -to.y)), 360.0)
		var diff := fposmod(mb - bearing + 180.0, 360.0) - 180.0
		if absf(diff) < 60.0:
			var mx := cx + diff * px_per_deg
			c.draw_circle(Vector2(mx, 58), 5.0, Color("ffd34d"))
			_text(c, Vector2(mx, 78), "%d م" % int(to.length()), 12, Color("ffd34d"), HORIZONTAL_ALIGNMENT_CENTER, null, 80)

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
	for ad in world.airdrops:
		var q: Vector2 = r.get_center() + (Vector2(ad.global_position.x, ad.global_position.z) - Vector2(pos.x, pos.z)) * s
		if r.has_point(q): _crate_icon(c, q, ad.landed)
	if marker != Vector2.INF:
		var mq: Vector2 = r.get_center() + (marker - Vector2(pos.x, pos.z)) * s
		if r.grow(-4).has_point(mq):
			_pin(c, mq + Vector2(0, 4))
		else:
			# Off the minimap: a small pin on its edge pointing that way.
			var dir := (mq - r.get_center()).normalized()
			var e := r.get_center() + dir * (size * 0.5 - 8.0) / maxf(absf(dir.x), absf(dir.y))
			c.draw_circle(e, 5.0, Color("ffd34d"))
	for m in world.teammates(p):
		if world.is_gone(m): continue
		var tq: Vector2 = r.get_center() + (Vector2(m.global_position.x, m.global_position.z) - Vector2(pos.x, pos.z)) * s
		if r.grow(-4).has_point(tq):
			c.draw_circle(tq, 5.0, Color.BLACK)
			c.draw_circle(tq, 4.0, world.TEAM_COLORS[m.slot % 4] if not world.is_down(m) else Color("ff3a2a"))
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
		var ammo_txt := "سلاح أبيض" if wd.get("melee", false) else "%d/%d" % [s.mag, p.ammo[wd.ammo]]
		_text(c, Vector2(rr.position.x + 6, rr.end.y - 7), ammo_txt, 14, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, bold, rr.size.x)
		_text(c, Vector2(rr.end.x - 6, rr.end.y - 7), wd.name, 11, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, null, rr.size.x)
		# Fitted attachments: one small lit square per slot (sight, muzzle, mag, grip).
		var att: Dictionary = s.get("att", {})
		for k in Items.ATTACH_SLOTS.size():
			var slot_name: String = Items.ATTACH_SLOTS[k]
			if not Items.ATTACH.values().any(func(a): return a.slot == slot_name and a["for"].has(wd.cls)): continue
			var sq := Rect2(rr.end.x - 10 - (3 - k) * 11, rr.position.y + 4, 8, 8)
			c.draw_rect(sq, Color("ffd34d") if att.has(slot_name) else Color(1, 1, 1, 0.15))
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
		"dmr": [[0.0, 0.42], [0.25, 0.36], [0.3, 0.28], [0.5, 0.28], [0.5, 0.2], [0.58, 0.2], [0.58, 0.28], [1.0, 0.3], [1.0, 0.38], [0.55, 0.42], [0.42, 0.5], [0.38, 0.75], [0.31, 0.75], [0.3, 0.52], [0.0, 0.62]],
		"crossbow": [[0.0, 0.42], [0.3, 0.36], [0.62, 0.36], [0.62, 0.05], [0.7, 0.05], [0.7, 0.36], [1.0, 0.36], [1.0, 0.44], [0.7, 0.44], [0.7, 0.95], [0.62, 0.95], [0.62, 0.44], [0.42, 0.46], [0.36, 0.72], [0.3, 0.72], [0.28, 0.5], [0.0, 0.6]],
		"melee": [[0.05, 0.42], [0.45, 0.4], [0.5, 0.3], [0.62, 0.12], [0.8, 0.08], [0.95, 0.25], [0.97, 0.5], [0.92, 0.75], [0.78, 0.9], [0.6, 0.85], [0.5, 0.6], [0.45, 0.52], [0.05, 0.52]],
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

## Looking through a sight: reflex sights (red dot, holographic) keep the view
## open inside a thin housing; magnified scopes black out all but the lens.
func _draw_scope(c: Control, sz: Vector2, w: Dictionary) -> void:
	var ctr := sz * 0.5
	var sight: String = w.get("sight", "")
	var red := Color(1.0, 0.16, 0.12)
	if sight == "reddot" or sight == "holo":
		# Housing: dark frame around a slightly tinted glass.
		var hw := minf(sz.x, sz.y) * 0.34
		var r := Rect2(ctr - Vector2(hw, hw * 0.78), Vector2(hw * 2, hw * 1.56))
		c.draw_rect(r, Color(0.3, 0.5, 0.6, 0.06))
		c.draw_rect(r, Color(0.05, 0.05, 0.06, 0.9), false, 8.0)
		c.draw_rect(r.grow(-7), Color(0.4, 0.42, 0.45, 0.6), false, 1.5)
		if sight == "reddot":
			c.draw_circle(ctr, 3.2, red)
			c.draw_circle(ctr, 6.0, Color(red.r, red.g, red.b, 0.18))
		else:
			c.draw_arc(ctr, 26.0, 0, TAU, 48, red, 2.0, true)
			c.draw_circle(ctr, 2.4, red)
			for d in [Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
				c.draw_line(ctr + d * 26.0, ctr + d * 34.0, red, 2.0)
		_hit_marks(c, ctr)
		return
	var r := minf(sz.x, sz.y) * 0.44
	if r < 4.0: return
	# Black mask around a round scope: one thick ring out past the corners.
	var outer := ctr.length() + 4.0
	c.draw_arc(ctr, (r + outer) * 0.5, 0, TAU, 128, Color.BLACK, outer - r + 2.0)
	# Lens edge darkening.
	for i in 6:
		c.draw_arc(ctr, r - i * 4.0, 0, TAU, 96, Color(0, 0, 0, 0.35 - i * 0.05), 5.0, true)
	var ink := Color(0.02, 0.02, 0.02, 0.95)
	match sight:
		"x2":
			c.draw_circle(ctr, 2.6, red)
			c.draw_arc(ctr, 30.0, PI * 0.15, PI * 0.85, 24, ink, 1.6, true)
		"x4":
			# Chevron with bullet-drop marks below.
			c.draw_polyline(PackedVector2Array([ctr + Vector2(-9, 9), ctr, ctr + Vector2(9, 9)]), red, 2.2, true)
			c.draw_line(ctr + Vector2(0, 3), ctr + Vector2(0, r * 0.55), ink, 1.4)
			for k in 4:
				var y := ctr.y + 30.0 + k * 26.0
				var hw2 := 14.0 - k * 2.5
				c.draw_line(Vector2(ctr.x - hw2, y), Vector2(ctr.x + hw2, y), ink, 1.4)
			c.draw_line(Vector2(ctr.x - r, ctr.y), Vector2(ctr.x - 40, ctr.y), ink, 2.0)
			c.draw_line(Vector2(ctr.x + 40, ctr.y), Vector2(ctr.x + r, ctr.y), ink, 2.0)
		_:
			# 8x / sniper scope: thin crosshair with mil dots and thick outer posts.
			c.draw_line(Vector2(ctr.x - r, ctr.y), Vector2(ctr.x + r, ctr.y), ink, 1.2)
			c.draw_line(Vector2(ctr.x, ctr.y - r), Vector2(ctr.x, ctr.y + r), ink, 1.2)
			for k in range(1, 6):
				for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					c.draw_circle(ctr + d * k * 22.0, 2.0, ink)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1)]:
				c.draw_line(ctr + d * r * 0.62, ctr + d * r, ink, 6.0)
			c.draw_circle(ctr, 1.8, red)
	_hit_marks(c, ctr)
	# Magnification label.
	var zoom := float(w.get("zoom", 1.0))
	_text(c, Vector2(ctr.x + r * 0.62, ctr.y + r * 0.86), "%dx" % int(round(zoom)), 16, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, bold)

func _hit_marks(c: Control, ctr: Vector2) -> void:
	if hit_t > 0.0:
		var hc := Color("ff4040") if hit_head else Color.WHITE
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			c.draw_line(ctr + d * 7.0, ctr + d * 15.0, hc, 2.5)

func _draw_prompt(c: Control, sz: Vector2, p: Player) -> void:
	if p.heal_id != "":
		_draw_heal(c, sz, p)
		return
	var it = world.nearest_pickup(p.global_position, 2.4)
	var key := "[F] " if Game.settings.controls == "kbm" else ""
	if it == null:
		if world.nearest_vehicle(p.global_position, 3.5):
			_text(c, Vector2(sz.x * 0.5, sz.y * 0.64), key + "ركوب السيارة", 19, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold)
		return
	if it.has_meta("crate") and is_instance_valid(it.get_meta("crate")):
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.64), key + "افتح صندوق " + str(it.get_meta("crate").get_meta("owner")), 19, Color("ffd34d"), HORIZONTAL_ALIGNMENT_CENTER, bold)
		return
	var label: String = world.pickup_name(it.get_meta("data"))
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

# ---------- Full map (M): zoom with the wheel, drag to move, click to mark ----------
var map_zoom := 1.0
var map_focus := Vector2.ZERO        # world point at the middle of the map view
var marker := Vector2.INF            # your map marker (world x, z)
var _map_rect := Rect2()
var _region_centres := {}
var _map_drag := false
var _map_press := Vector2.ZERO

func _map_k() -> float:
	return _map_rect.size.x / world.island.size * map_zoom

func _w2m(q: Vector2) -> Vector2:
	return _map_rect.get_center() + (q - map_focus) * _map_k()

func _m2w(sp: Vector2) -> Vector2:
	return map_focus + (sp - _map_rect.get_center()) / _map_k()

func _clamp_focus() -> void:
	var S: float = world.island.size
	var half := S * 0.5 / map_zoom
	map_focus = Vector2(clampf(map_focus.x, half, S - half), clampf(map_focus.y, half, S - half))

func _map_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and _map_rect.has_point(event.position):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var at := _m2w(event.position)
			map_zoom = clampf(map_zoom * (1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 1.0, 8.0)
			# Keep the point under the mouse where it is.
			map_focus = at - (event.position - _map_rect.get_center()) / _map_k()
			_clamp_focus()
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			_map_press = event.position
			_map_drag = true
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			marker = Vector2.INF
			return true
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _map_drag:
		_map_drag = false
		# A click (not a drag) puts the marker there.
		if event.position.distance_to(_map_press) < 6.0 and _map_rect.has_point(event.position):
			var w := _m2w(event.position)
			marker = Vector2.INF if marker != Vector2.INF and _w2m(marker).distance_to(event.position) < 12.0 else w
		return true
	if event is InputEventMouseMotion and _map_drag and event.position.distance_to(_map_press) >= 6.0:
		map_focus -= event.relative / _map_k()
		_clamp_focus()
		return true
	return false

func _draw_full_map(c: Control, sz: Vector2, p: Player) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.04, 0.06, 0.95))
	var size := minf(sz.x - 360.0, sz.y - 60.0)
	var r := Rect2((sz.x - size) * 0.5, 30.0, size, size)
	_map_rect = r
	if map_focus == Vector2.ZERO:
		map_focus = Vector2.ONE * world.island.size * 0.5
	_clamp_focus()
	var S: float = world.island.size
	var k := _map_k()
	c.draw_rect(r, Color(0.1, 0.27, 0.42))
	if world.map_texture:
		var tex: Texture2D = world.map_texture
		var tk := tex.get_width() / S
		var view := S / map_zoom
		var src := Rect2((map_focus - Vector2.ONE * view * 0.5) * tk, Vector2.ONE * view * tk)
		c.draw_texture_rect_region(tex, r, src)
	# Grid: big squares with letters and numbers, small ones when zoomed in.
	var cell := S / Game.GRID
	var fine := 4 if map_zoom >= 2.5 else 1
	for i in range(1, Game.GRID * fine):
		var o := i * cell / fine
		var major := i % fine == 0
		var col := Color(1, 1, 1, 0.32 if major else 0.12)
		var gx := _w2m(Vector2(o, 0)).x
		var gy := _w2m(Vector2(0, o)).y
		if gx > r.position.x and gx < r.end.x: c.draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), col, 1.0)
		if gy > r.position.y and gy < r.end.y: c.draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), col, 1.0)
	var letters := "ABCDEFGH"
	for i in Game.GRID:
		var mx := _w2m(Vector2((i + 0.5) * cell, 0)).x
		var my := _w2m(Vector2(0, (i + 0.5) * cell)).y
		if mx > r.position.x + 10 and mx < r.end.x - 10:
			_text(c, Vector2(mx, r.position.y - 8), letters[i], 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 30)
		if my > r.position.y + 10 and my < r.end.y - 10:
			_text(c, Vector2(r.position.x - 14, my + 5), str(i + 1), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 30)
	# Region names, large and faint, when the whole map is in view.
	if map_zoom < 1.8:
		if _region_centres.is_empty():
			var sums := {}
			for t in world.island.towns:
				var reg: String = t.get("region", "")
				if reg == "": continue
				if not sums.has(reg): sums[reg] = [Vector2.ZERO, 0]
				sums[reg][0] += t.pos
				sums[reg][1] += 1
			for reg in sums:
				_region_centres[reg] = sums[reg][0] / float(sums[reg][1])
		for reg in _region_centres:
			var rp := _w2m(_region_centres[reg]) + Vector2(0, 34)
			if r.has_point(rp):
				_text(c, rp, Island.REGION_TITLES.get(reg, ""), 26, Color(1, 1, 1, 0.32), HORIZONTAL_ALIGNMENT_CENTER, bold, 300)
	# Places: a dot and the name (gold for the military base).
	var taken: Array[Rect2] = []
	for t in world.island.towns:
		var tp := _w2m(t.pos)
		if not r.grow(-20).has_point(tp): continue
		var tc: Color = Color("ffe08a") if t.military else Color.WHITE
		c.draw_circle(tp, 3.0, Color(0, 0, 0, 0.6))
		c.draw_circle(tp, 2.0, tc)
		var fs := 13 + int(minf(map_zoom, 3.0))
		var tw := bold.get_string_size(t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# Above the dot, or below / beside it when another name is there.
		var at := tp + Vector2(0, -7)
		for off in [Vector2(0, -7), Vector2(0, fs + 8), Vector2(tw * 0.5 + 8, fs * 0.4), Vector2(-tw * 0.5 - 8, fs * 0.4)]:
			var box := Rect2(tp + off - Vector2(tw * 0.5, fs), Vector2(tw, fs + 2))
			var free := true
			for o in taken:
				if o.intersects(box): free = false
			if free:
				at = tp + off
				break
		taken.append(Rect2(at - Vector2(tw * 0.5, fs), Vector2(tw, fs + 2)))
		_text(c, at, t.name, fs, tc, HORIZONTAL_ALIGNMENT_CENTER, bold)
	if world.plane_active:
		_clipped_line(c, r, _w2m(Vector2(world.plane_from.x, world.plane_from.z)), _w2m(Vector2(world.plane_to.x, world.plane_to.z)), Color(1, 1, 1, 0.8))
		var pp: Vector3 = world.plane_position()
		var pd: Vector3 = (world.plane_to - world.plane_from).normalized()
		var ps := _w2m(Vector2(pp.x, pp.z))
		if r.has_point(ps): _arrow(c, ps, atan2(pd.x, -pd.z), Color.WHITE, 11.0)
	var z: Zone = world.zone
	if z.state != "idle":
		_clipped_circle(c, r, _w2m(z.center), z.radius * k, Color(0.25, 0.5, 1.0, 0.95), 2.5)
		_clipped_circle(c, r, _w2m(z.next_center), z.next_radius * k, Color.WHITE, 2.0)
	for ad in world.airdrops:
		var q := _w2m(Vector2(ad.global_position.x, ad.global_position.z))
		if r.has_point(q): _crate_icon(c, q, ad.landed)
	for f in world._drop_flights:
		var fp: Vector3 = f.node.global_position
		var q2 := _w2m(Vector2(fp.x, fp.z))
		if r.has_point(q2): c.draw_circle(q2, 4.0, Color(1, 1, 1, 0.9))
	var me := Vector2(p.global_position.x, p.global_position.z)
	if marker != Vector2.INF:
		var ms := _w2m(marker)
		if r.has_point(ms):
			_clipped_line(c, r, _w2m(me), ms, Color(1, 0.83, 0.3, 0.6))
			_pin(c, ms)
			_text(c, ms + Vector2(0, 16), "%d م" % int(me.distance_to(marker)), 13, Color("ffd34d"), HORIZONTAL_ALIGNMENT_CENTER, bold, 80)
	var mp := _w2m(me)
	if r.has_point(mp):
		c.draw_arc(mp, 13.0 + 3.0 * sin(world.time * 4.0), 0, TAU, 24, Color(1, 0.83, 0.3, 0.5), 2.0)
		_arrow(c, mp, -p.yaw, Color("ffd34d"), 11.0)
	for m in world.teammates(p):
		if world.is_gone(m): continue
		var tq := _w2m(Vector2(m.global_position.x, m.global_position.z))
		if r.has_point(tq):
			c.draw_circle(tq, 6.0, Color.BLACK)
			c.draw_circle(tq, 5.0, world.TEAM_COLORS[m.slot % 4] if not world.is_down(m) else Color("ff3a2a"))
	c.draw_rect(r, Color(1, 1, 1, 0.55), false, 2.0)
	# Scale bar.
	var bar_m := 1000.0 if map_zoom < 1.6 else (500.0 if map_zoom < 3.2 else (200.0 if map_zoom < 6.0 else 100.0))
	var bl := bar_m * k
	var b0 := Vector2(r.end.x - bl - 14, r.end.y - 16)
	c.draw_rect(Rect2(b0 - Vector2(6, 22), Vector2(bl + 12, 30)), Color(0, 0, 0, 0.45))
	c.draw_line(b0, b0 + Vector2(bl, 0), Color.WHITE, 3.0)
	_text(c, b0 + Vector2(bl * 0.5, -6), "%d م" % int(bar_m), 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, null, 80)
	# Side panel: zone, marker, keys.
	var px := r.end.x + 22.0
	var pw := sz.x - px - 16.0
	if pw > 120.0:
		var y := r.position.y + 10.0
		var lines := []
		if z.state == "idle":
			lines.append(["المنطقة الزرقاء", "لم تبدأ بعد", Color.WHITE])
		else:
			var tl := int(maxf(0.0, z.time_left))
			lines.append(["المنطقة الزرقاء", ("تضيق الآن" if z.state == "shrink" else "تضيق بعد %d:%02d" % [tl / 60, tl % 60]) if z.state != "done" else "انتهت", Color("9fd0ff")])
			var dd := z.distance_to_safe(p.global_position)
			lines.append(["المنطقة الآمنة", "أنت بداخلها" if dd <= 0.0 else "تبعد %d م" % int(dd), Color.WHITE if dd <= 0.0 else Color("ff9a7a")])
		lines.append(["الباقون", str(world.alive_count()), Color.WHITE])
		if marker != Vector2.INF:
			lines.append(["علامتك", "%d م" % int(me.distance_to(marker)), Color("ffd34d")])
		var cell_name := "%s%d" % [letters[clampi(int(me.x / cell), 0, Game.GRID - 1)], clampi(int(me.y / cell), 0, Game.GRID - 1) + 1]
		lines.append(["مكانك", cell_name, Color("ffd34d")])
		for ln in lines:
			c.draw_rect(Rect2(px, y, pw, 52), Color(1, 1, 1, 0.06))
			_text(c, Vector2(px + 10, y + 20), ln[0], 13, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_LEFT, null, pw - 20)
			_text(c, Vector2(px + 10, y + 43), ln[1], 18, ln[2], HORIZONTAL_ALIGNMENT_LEFT, bold, pw - 20)
			y += 58.0
		y += 10.0
		for h in ["عجلة الماوس: تكبير وتصغير", "اسحب بالماوس: تحريك الخريطة", "كبسة شمال: حط علامة", "كبسة يمين: امسح العلامة", "M: إغلاق الخريطة"]:
			_text(c, Vector2(px + 4, y), h, 12, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT, null, pw)
			y += 20.0

func _clipped_line(c: Control, r: Rect2, a: Vector2, b: Vector2, col: Color) -> void:
	# Liang-Barsky clip to the map, then a dashed line.
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for ax in 2:
		for side in 2:
			var pp := -d[ax] if side == 0 else d[ax]
			var q := (a[ax] - r.position[ax]) if side == 0 else (r.end[ax] - a[ax])
			if absf(pp) < 0.0001:
				if q < 0.0: return
				continue
			var t := q / pp
			if pp < 0.0: t0 = maxf(t0, t)
			else: t1 = minf(t1, t)
	if t0 >= t1: return
	c.draw_dashed_line(a + d * t0, a + d * t1, col, 2.0, 8.0)

## Yellow map pin.
func _pin(c: Control, at: Vector2) -> void:
	c.draw_colored_polygon(PackedVector2Array([at, at + Vector2(-6, -12), at + Vector2(6, -12)]), Color("ffd34d"))
	c.draw_circle(at + Vector2(0, -14), 7.0, Color("ffd34d"))
	c.draw_circle(at + Vector2(0, -14), 3.0, Color(0.15, 0.1, 0.0))

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

## Dotted arc where a grenade would fly, with a ring where it lands.
func _draw_throw_arc(c: Control, p: Player) -> void:
	var cam := p.camera
	var pts := p.throw_arc()
	var prev := Vector2.INF
	for i in pts.size():
		if cam.is_position_behind(pts[i]): continue
		var sp := cam.unproject_position(pts[i])
		if prev != Vector2.INF and i % 2 == 0:
			c.draw_line(prev, sp, Color(1, 1, 1, 0.85), 2.0)
		prev = sp
	if pts.size() > 1 and not cam.is_position_behind(pts[-1]):
		var land := cam.unproject_position(pts[-1])
		c.draw_arc(land, 10.0 if p.throw_kind != "molotov" else 18.0, 0, TAU, 20, THROW_COLORS[p.throw_kind], 2.0)
	_text(c, Vector2(c.size.x * 0.5, c.size.y * 0.7), "اترك G أو اضغط إطلاق للرمي", 15)

const THROW_COLORS := {"frag": Color("9fb07a"), "smoke": Color("c9cdd2"), "molotov": Color("ff8a3c"), "flash": Color("8fc4ff")}

## Small card next to the weapons with the selected grenade and how many.
func _draw_throw_card(c: Control, sz: Vector2, p: Player) -> void:
	var n := 0
	for k in p.throwables: n += int(p.throwables[k])
	if n == 0: return
	var r := Rect2(Hud.slot_rect(0, sz).position.x - 74, sz.y - 98, 66, 62)
	c.draw_rect(r, Color(0, 0, 0, 0.5) if p.throw_ready else Color(0, 0, 0, 0.3))
	c.draw_rect(r, Color("ffd34d") if p.throw_ready else Color(1, 1, 1, 0.18), false, 1.2)
	var col: Color = THROW_COLORS[p.throw_kind]
	c.draw_circle(r.get_center() + Vector2(0, -6), 11.0, col)
	c.draw_rect(Rect2(r.get_center() + Vector2(-3, -21), Vector2(6, 5)), col)
	_text(c, Vector2(r.get_center().x, r.end.y - 6), "×%d" % p.throwables[p.throw_kind], 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 60)

## Supply crate marker: red box, with a parachute while still falling.
func _crate_icon(c: Control, at: Vector2, landed: bool) -> void:
	c.draw_rect(Rect2(at - Vector2(6, 5), Vector2(12, 10)), Color("d93030"))
	c.draw_rect(Rect2(at - Vector2(6, 5), Vector2(12, 10)), Color.WHITE, false, 1.5)
	if not landed:
		c.draw_arc(at + Vector2(0, -10), 8.0, PI, TAU, 10, Color.WHITE, 2.0)

## Speedometer and car health while driving.
func _draw_vehicle(c: Control, sz: Vector2, p: Player) -> void:
	var v: Vehicle = p.vehicle
	if v == null: return
	var ctr := Vector2(sz.x * 0.5, sz.y - 70.0)
	var kmh := absf(v.speed()) * 3.6
	c.draw_arc(ctr, 46.0, PI * 0.75, PI * 2.25, 40, Color(0, 0, 0, 0.45), 8.0)
	c.draw_arc(ctr, 46.0, PI * 0.75, PI * 0.75 + PI * 1.5 * clampf(kmh / 130.0, 0.0, 1.0), 40, Color.WHITE, 8.0)
	_text(c, ctr + Vector2(0, 8), str(int(kmh)), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 90)
	_text(c, ctr + Vector2(0, 26), "كم/س", 12, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, null, 90)
	var w := 160.0
	var hp := clampf(v.health / v.max_health, 0.0, 1.0)
	var r := Rect2(ctr.x - w * 0.5, ctr.y + 40.0, w, 7.0)
	c.draw_rect(r, Color(0, 0, 0, 0.5))
	c.draw_rect(Rect2(r.position, Vector2(w * hp, 7.0)), Color("ffcf5a") if hp > 0.3 else Color("ff4a3a"))
	_text(c, Vector2(ctr.x, r.end.y + 16), "حالة السيارة", 12, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, null, 160)
	# Player health stays visible too.
	var hw := 260.0
	c.draw_rect(Rect2(sz.x * 0.5 - hw * 0.5, sz.y - 14.0, hw, 6.0), Color(0, 0, 0, 0.5))
	c.draw_rect(Rect2(sz.x * 0.5 - hw * 0.5, sz.y - 14.0, hw * clampf(p.health / 100.0, 0.0, 1.0), 6.0), Color.WHITE)
