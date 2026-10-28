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
var sound_marks: Array = []  # [{pos: Vector3, kind: "shot" | "step", t}]: where you hear someone (PUBG Mobile's sound markers)

## Someone fired or is walking near you: a marker round the crosshair points there.
func sound_mark(pos: Vector3, kind: String) -> void:
	for m in sound_marks:
		if m.kind == kind and m.pos.distance_to(pos) < 5.0:
			m.pos = pos
			m.t = 1.6
			return
	if sound_marks.size() >= 12: sound_marks.pop_front()
	sound_marks.append({"pos": pos, "kind": kind, "t": 1.6})
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
	p.hit_confirmed.connect(_on_hit)
	p.damaged.connect(func(dir): dmg_dirs.append({"dir": dir, "t": 1.2}))
	p.message.connect(show_banner)
	if world.war:
		show_banner("حرب الفرق! أنت مع %s — جهّز حالك واشتري من المتجر قبل ما تنفتح البوابات" % War.TEAMS[world.player.team].name)
	else:
		show_banner("مرحباً في منطقة الصفر — جهّز حالك، الطيارة جاية" if world.spawn != null else "مرحباً في منطقة الصفر — اقفز من الطائرة فوق الجزيرة")
	Game.cursor_free = false
	if Game.settings.controls == "kbm":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Tweens die with their node, so nothing fires after leaving the match.
		create_tween().tween_callback(show_banner.bind("اضغط Ctrl لإظهار الماوس أو إخفائه")).set_delay(3.2)
	var wtext: String = {"rain": "الطقس: مطر — الرؤية أقل والأصوات أوطى", "sunset": "الطقس: غروب", "fog": "الطقس: ضباب الصبح — الوديان مغطاية، انتبه"}.get(world.weather, "")
	if wtext != "":
		create_tween().tween_callback(show_banner.bind(wtext)).set_delay(6.6)

var _radio: PanelContainer

## «راديو الصفر»: a short line from the match commentator, sliding in under
## the compass for a few seconds.
func radio(text: String) -> void:
	if _radio: _radio.queue_free()
	_radio = PanelContainer.new()
	_radio.add_theme_stylebox_override("panel", UiKit.style(Color(0.05, 0.05, 0.06, 0.78), 6, Color(1, 0.83, 0.3, 0.6), 1, 8))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	_radio.add_child(hb)
	hb.add_child(UiKit.label("📻 راديو الصفر", 14, Color("ffd34d"), bold, 2))
	hb.add_child(UiKit.label(text, 16, Color.WHITE, bold, 2))
	add_child(_radio)
	_radio.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_radio.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_radio.position.y = 52
	_radio.modulate.a = 0.0
	var r := _radio
	var tw := r.create_tween()
	tw.tween_property(r, "modulate:a", 1.0, 0.25)
	tw.tween_interval(4.5)
	tw.tween_property(r, "modulate:a", 0.0, 0.6)
	tw.tween_callback(r.queue_free)

var _got: PanelContainer

## Picked up or bought a gun: its picture and name, big, for a moment.
func weapon_toast(id: String) -> void:
	if _got: _got.queue_free()
	_got = PanelContainer.new()
	_got.add_theme_stylebox_override("panel", UiKit.style(Color(0.03, 0.05, 0.08, 0.78), 10, Color(1, 0.83, 0.3, 0.7), 1, 10))
	_got.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	_got.add_child(hb)
	var tex := Icons.weapon(id)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(190, 80)
		hb.add_child(tr)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(v)
	var wd: Dictionary = Game.WEAPONS[id]
	v.add_child(UiKit.label(String(wd.name), 26, Color("ffd34d"), bold, 3))
	v.add_child(UiKit.label("ضرر %d • مخزن %d" % [int(wd.dmg), int(wd.mag)] if not wd.get("melee", false) else "سلاح أبيض", 14, Color.WHITE, null, 2))
	add_child(_got)
	_got.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_got.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_got.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_got.position.y -= 150.0
	var g := _got
	g.modulate.a = 0.0
	g.scale = Vector2(0.9, 0.9)
	g.pivot_offset = Vector2(200, 50)
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(g, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.6)
	tw.tween_property(g, "modulate:a", 0.0, 0.35)
	tw.tween_callback(g.queue_free)

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
	if world.war:
		_draw_war_teams(c)
		return
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
		var d: float = cam.global_position.distance_to(wp)
		if world.war and d > 35.0: continue       # 24 teammates: only the ones near you
		var sp := cam.unproject_position(wp)
		var col: Color = world.TEAM_COLORS[m.slot % 4] if not world.war else War.TEAMS[m.team].col
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
	kill_t = maxf(0.0, kill_t - delta)
	_streak_t = maxf(0.0, _streak_t - delta)
	if flash_t > 0.0:
		flash_t = maxf(0.0, flash_t - delta)
		var vol := AudioServer.get_bus_volume_db(0)
		AudioServer.set_bus_volume_db(0, 0.0 if flash_t <= 0.0 else move_toward(vol, 0.0, delta * 18.0 / flash_len))
	for d in dmg_dirs: d.t -= delta
	dmg_dirs = dmg_dirs.filter(func(d): return d.t > 0.0)
	for m in sound_marks: m.t -= delta
	sound_marks = sound_marks.filter(func(m): return m.t > 0.0)
	# On the spawn island the countdown sits where messages go: messages drop below it.
	banner.position.y = (get_viewport().get_visible_rect().size.y * 0.21 + 112.0) if world.spawn != null else 120.0
	if _banner_t > 0.0:
		_banner_t -= delta
		banner.modulate.a = clampf(_banner_t, 0.0, 1.0)
	banner.visible = not map_open and not bag_open and shop == null
	if world.war: _update_shop_btn()
	_update_ready_btn()
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
		elif world.war and event.physical_keycode == KEY_V and Game.action_for(KEY_V) == "":
			toggle_shop()
		elif event.physical_keycode == KEY_ESCAPE and shop != null:
			toggle_shop()
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
var shop: ShopPanel
var _ready_btn: Button

## On the spawn island: "ready" sends the plane off at once.
func _update_ready_btn() -> void:
	var show_it: bool = world.spawn != null and world.ready_done and world.spawn.left > 3.0 and not map_open and not bag_open and not Net.in_match
	if show_it and _ready_btn == null:
		_ready_btn = UiKit.yellow_button("جاهز ✓  يلا نطلع", func():
			if world.spawn: world.spawn.left = minf(world.spawn.left, 3.0), Vector2(240, 50), 22)
		add_child(_ready_btn)
	if _ready_btn:
		if not show_it:
			_ready_btn.queue_free()
			_ready_btn = null
		else:
			var sz := get_viewport().get_visible_rect().size
			_ready_btn.position = Vector2(sz.x * 0.5 - 120, sz.y * 0.21 + 52)

var _shop_btn: Button

## Team war: the fort's shop (only inside your own fort, alive).
func toggle_shop() -> void:
	if pause_panel or results: return
	if shop:
		shop.queue_free()
		shop = null
		if Game.settings.controls == "kbm":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Game.cursor_free = false
		return
	var p: Player = world.player
	if p.state != "ground" or not world.war.in_own_fort(p.global_position):
		show_banner("المتجر بس جوّا حصنك")
		return
	if bag_open: toggle_bag()
	if map_open: toggle_map()
	shop = ShopPanel.new(world)
	add_child(shop)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.cursor_free = true
	p.firing = false
	p.aiming = false

## The on-screen shop button, shown inside your fort.
func _update_shop_btn() -> void:
	var p: Player = world.player
	var show_it: bool = world.war != null and shop == null and p.state == "ground" and world.war.in_own_fort(p.global_position) and not map_open and not bag_open
	if show_it and _shop_btn == null:
		var key := " (V)" if Game.settings.controls == "kbm" else ""
		_shop_btn = UiKit.yellow_button("المتجر" + key, toggle_shop, Vector2(170, 52), 22)
		add_child(_shop_btn)
		# Under the team list, clear of the touch buttons.
		_shop_btn.position = Vector2(14, 236)
	elif not show_it and _shop_btn != null:
		_shop_btn.queue_free()
		_shop_btn = null
	# Walked out of the fort with the shop open: it closes.
	if shop and (p.state != "ground" or not world.war.in_own_fort(p.global_position)):
		toggle_shop()

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
		if _settings_box:
			_settings_box.queue_free()
			_settings_box = null
		get_tree().paused = false
		if Game.settings.controls == "kbm":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Game.cursor_free = false
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_panel = _panel("إيقاف مؤقت", [["متابعة", toggle_pause], ["الإعدادات", _match_settings], ["القائمة الرئيسية", _confirm_leave]])
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS

## Leaving a match you are still alive in: asked once.
func _confirm_leave() -> void:
	if world.player.state == "dead" or world.match_over:
		_to_lobby()
		return
	if pause_panel:
		pause_panel.queue_free()
	pause_panel = _panel("تطلع من المباراة؟", [["إيه، اطلع", _to_lobby], ["لا، كمّل", func():
		pause_panel.queue_free()
		pause_panel = null
		toggle_pause()]], "رح تخسر هالمباراة وما رح تنحسبلك")
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS

## Phone back button: close what is open (map, bag, shop), else pause.
func go_back() -> void:
	if results: return
	if map_open: toggle_map()
	elif bag_open: toggle_bag()
	elif shop: toggle_shop()
	else: toggle_pause()

var _settings_box: Control

## Graphics and controls without leaving the match (opened from the pause menu).
func _match_settings() -> void:
	if _settings_box: _settings_box.queue_free()
	var pc := PanelContainer.new()
	pc.process_mode = Node.PROCESS_MODE_ALWAYS
	pc.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.06, 0.09, 0.95), 12, Color(1, 0.83, 0.3, 0.35), 1, 24))
	add_child(pc)
	_settings_box = pc
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	var head := UiKit.label("الإعدادات", 28, Color("ffd34d"), bold)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	vb.add_child(cols)
	var gfx := _settings_col(cols, "الجرافيك")
	var apply := func():
		Game.apply_quality(world.builder.env, world.builder.sun)
		Game.save_data()
	_seg_row(gfx, "الجودة", Game.QUALITIES, Game.QUALITY_NAMES, "quality", apply)
	_seg_row(gfx, "الإطارات بالثانية", Game.FPS_OPTIONS, Game.FPS_OPTIONS.map(func(f): return str(f)), "fps", apply)
	_seg_row(gfx, "وضع اللابتوب", [true, false], ["تشغيل", "إيقاف"], "laptop", apply)
	_slider_row(gfx, "دقة الرسم", "render_scale", 0.7, 1.0, 1.0, apply, true)
	_slider_row(gfx, "السطوع", "brightness", 0.7, 1.4, 1.0, apply, true)
	_seg_row(gfx, "عداد الإطارات", [true, false], ["تشغيل", "إيقاف"], "show_fps", apply)
	var note := UiKit.label("بعض التغييرات (المسافة والعشب) بتبين بالمباراة الجاية", 13, Color(1, 1, 1, 0.6))
	gfx.add_child(note)
	var ctl := _settings_col(cols, "التحكم")
	var sens := func():
		world.player.sens = float(Game.settings.sensitivity)
		Game.save_data()
	_slider_row(ctl, "حساسية النظر", "sensitivity", 0.3, 3.0, 1.0, sens)
	_slider_row(ctl, "حساسية التصويب والسكوب", "aim_sens", 0.15, 1.2, 0.45, sens)
	_seg_row(ctl, "عكس محور النظر", [false, true], ["عادي", "معكوس"], "invert_y", sens)
	_seg_row(ctl, "مساعدة التصويب", [true, false], ["تشغيل", "إيقاف"], "aim_assist", sens)
	_seg_row(ctl, "التحكم", ["kbm", "touch"], ["كيبورد وماوس", "أزرار لمس"], "controls", func():
		touch.visible = Game.settings.controls == "touch"
		Game.save_data())
	_seg_row(ctl, "الصوت", [true, false], ["تشغيل", "إيقاف"], "sound", func():
		Game.apply_audio()
		Game.save_data())
	var done := UiKit.yellow_button("تمام", func():
		_settings_box.queue_free()
		_settings_box = null, Vector2(200, 48), 22)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(done)
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH

func _settings_col(parent: Control, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(380, 0)
	parent.add_child(col)
	col.add_child(UiKit.label(title, 20, Color.WHITE, bold))
	return col

## A row of choices for one setting; the chosen one is yellow.
func _seg_row(parent: Control, text: String, values: Array, names: Array, key: String, after: Callable) -> void:
	parent.add_child(UiKit.label(text, 14, Color(1, 1, 1, 0.75)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var btns := []
	for i in values.size():
		var b := UiKit.button(str(names[i]), func(): pass, Vector2(0, 34), null, 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		btns.append(b)
	var paint := func():
		for i in values.size():
			var on: bool = str(Game.settings.get(key)) == str(values[i])
			btns[i].add_theme_stylebox_override("normal", UiKit.style(Color("ffd34d") if on else Color(1, 1, 1, 0.08), 4))
			btns[i].add_theme_color_override("font_color", Color("1a1a1a") if on else Color.WHITE)
	for i in values.size():
		var v = values[i]
		btns[i].pressed.connect(func():
			Game.settings[key] = v
			paint.call()
			after.call())
	paint.call()

func _slider_row(parent: Control, text: String, key: String, lo: float, hi: float, def: float, after: Callable, pct := false) -> void:
	var lab := UiKit.label("", 14, Color(1, 1, 1, 0.75))
	parent.add_child(lab)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.05
	sl.value = float(Game.settings.get(key, def))
	sl.custom_minimum_size = Vector2(360, 26)
	parent.add_child(sl)
	var show := func(v: float): lab.text = "%s: %s" % [text, ("%d%%" % roundi(v * 100.0)) if pct else ("%.2f" % v)]
	show.call(sl.value)
	sl.value_changed.connect(func(v):
		Game.settings[key] = v
		show.call(v)
		after.call())

func show_results(won: bool, rank: int, kills: int, reward: Dictionary = {}) -> void:
	if spectating:
		spectating = false
		if _spec_panel:
			_spec_panel.queue_free()
			_spec_panel = null
	var title := ("فوز! أنت الناجي الأخير 🏆" if world.team_size <= 1 else "فوز! فريقك آخر فريق 🏆") if won else "الترتيب #%d" % rank
	var p0: Player = world.player
	var alive_t := int(world.time - (p0.dead_t if p0.state == "dead" else 0.0))
	var sub := "الإقصاءات: %d    الضرر: %d    النجاة: %d:%02d" % [kills, roundi(p0.dmg_dealt), alive_t / 60, alive_t % 60]
	if not reward.is_empty():
		sub += "\n+%d ذهب    +%d خبرة موسم" % [reward.gold, reward.xp]
	_results_args = [title, sub]
	_rank_change = reward.get("rank_change", {})
	var p: Player = world.player
	if not won and p.state == "dead" and is_instance_valid(p.killer) and p.dead_t < KILLCAM_TIME:
		# Killcam first: the results come up after a few seconds.
		get_tree().create_timer(KILLCAM_TIME - p.dead_t).timeout.connect(_show_results_panel)
	else:
		_show_results_panel()

const KILLCAM_TIME := 4.0
var _rank_change := {}

## Rank emblem, name, points won or lost and the bar to the next step.
func _rank_row(rc: Dictionary) -> Control:
	var after: Dictionary = rc.after
	var delta: int = rc.delta
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	hb.add_child(RankBadge.new(int(Game.stats.rp), 60.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var up: bool = int(after.tier) > int(rc.before.tier) or (after.name != rc.before.name and delta > 0)
	var head := Label.new()
	head.text = after.name + ("   ⬆ ترقية!" if up else "")
	head.add_theme_font_override("font", bold)
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", after.color)
	v.add_child(head)
	var d := Label.new()
	d.text = ("+%d" % delta if delta >= 0 else str(delta)) + " نقطة رتبة    (%d)" % int(Game.stats.rp)
	d.add_theme_color_override("font_color", Color("7dff8a") if delta >= 0 else Color("ff7a7a"))
	v.add_child(d)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(200, 8)
	bar.value = float(after.frac) * 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	var fg := StyleBoxFlat.new()
	fg.bg_color = after.color
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	v.add_child(bar)
	hb.add_child(v)
	return hb
var _results_args := ["", ""]
var spectating := false

func _show_results_panel() -> void:
	if results or spectating: return
	var buttons := []
	if world.player.state == "dead" and world.alive_count() > 0:
		buttons.append(["مشاهدة اللاعبين", start_spectate])
	buttons.append(["العب مرة ثانية", _play_again])
	buttons.append(["العودة إلى اللوبي", _to_lobby])
	results = _panel(_results_args[0], buttons, _results_args[1])
	if not _rank_change.is_empty():
		results.get_child(0).add_child(_rank_row(_rank_change))
		results.get_child(0).move_child(results.get_child(0).get_child(-1), 2)
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

## Straight into another match of the same mode.
func _play_again() -> void:
	if Net.active:
		_to_lobby()       # online: back to the room, the host starts the next one
		return
	get_tree().paused = false
	AudioServer.set_bus_volume_db(0, 0.0)
	Game.spawn_island = true
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _to_lobby() -> void:
	if Net.in_match:
		# Leaving mid-match counts as out, for the others.
		if world.player and world.player.state != "dead": Net.send_died(0)
		Net.match_over()
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
	s = Game.t(s)
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
			if p.view_zoom >= 1.9 and Game.settings.controls == "kbm": _draw_breath(c, sz, p)
		else:
			_draw_crosshair(c, sz, p)
		_draw_revive(c, sz, p)
		if not p.knocked and p.revive_target == null and p.downed_mate_near() == null: _draw_prompt(c, sz, p)
		if Game.settings.get("heal_prompt", true) and not p.knocked and p.heal_id == "" and p.health < 55.0 and p.best_heal() != "":
			# Hurt and carrying meds: a reminder above the health bar.
			var hk := "[%s] " % Game.key_label(Game.key("heal")) if Game.settings.controls == "kbm" else ""
			var a := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.006)
			_text(c, Vector2(sz.x * 0.5, sz.y - 112), hk + "صحتك قليلة — عالج نفسك (" + Items.HEALS[p.best_heal()].name + ")", 16, Color(0.55, 1.0, 0.6, a), HORIZONTAL_ALIGNMENT_CENTER, bold)
		if p.throw_ready: _draw_throw_arc(c, p)
		_draw_throw_card(c, sz, p)
	elif p.state == "vehicle":
		_draw_vehicle(c, sz, p)
	elif p.state in ["fall", "chute"]:
		_draw_gauges(c, sz, p)
	elif p.state == "plane":
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.68), "اضغط F للقفز" if world.plane_over_land() else "الطائرة تقترب من الجزيرة…", 20)
	var view_yaw: float = p.yaw + p.look_off.x
	for d in dmg_dirs:
		var rel: float = atan2(d.dir.x, -d.dir.z) + view_yaw
		var center := sz * 0.5
		var a := rel - PI / 2.0     # straight ahead is up, to your right is right
		c.draw_arc(center, 120.0, a - 0.3, a + 0.3, 12, Color(1, 0.2, 0.2, minf(1.0, d.t)), 6.0)
	if p.state in ["ground", "vehicle"]: _draw_sound_marks(c, sz, p, view_yaw)
	if world.spawn != null:
		# Waiting on the spawn island: how long until the plane leaves.
		var left := ceili(maxf(world.spawn.left, 0.0))
		var col := Color("ffd34d") if left <= 10 else Color.WHITE
		if Net.in_match and not world.net_started:
			_text(c, Vector2(sz.x * 0.5, sz.y * 0.21), "بانتظار صحابك يخلّصوا تحميل…", 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold)
		else:
			_text(c, Vector2(sz.x * 0.5, sz.y * 0.21), "الطيارة بتقلع بعد %d ثانية" % left, 28, col, HORIZONTAL_ALIGNMENT_CENTER, bold)
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.21 + 30), "جزيرة الانتظار — جرّب الأسلحة، ما حدا بيتأذى هون", 16, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, bold)
	_draw_dmg_numbers(c)
	if world.war: _draw_war(c, sz, p)
	if p.state in ["ground", "vehicle"] and world.zone.state != "idle" and world.zone.is_outside(p.global_position):
		# Caught in the disaster outside the zone: its colour over the screen.
		var dz: Array = Zone.DISASTERS[world.zone.disaster_at(p.global_position)]
		c.draw_rect(Rect2(Vector2.ZERO, sz), dz[1])
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.3), "أنت بـ%s — ارجع للمنطقة الآمنة!" % dz[0], 22, Color(dz[1], 1.0).lightened(0.4), HORIZONTAL_ALIGNMENT_CENTER, bold)
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
	if world.war: pills = [["$%d" % world.war.money, "فلوسك"], [str(world.player.kills), "الإقصاءات"]]
	for b in pills:
		var nw: float = maxf(40.0, String(b[0]).length() * 11.0 + 8.0)
		var w: float = nw + 12.0 + String(b[1]).length() * 9.0
		c.draw_rect(Rect2(x, 12, w, 30), Color(0, 0, 0, 0.42))
		c.draw_rect(Rect2(x, 12, nw, 30), Color(0, 0, 0, 0.55))
		_text(c, Vector2(x + nw * 0.5, 35), b[0], 19, Color("ffd34d") if String(b[0]).begins_with("$") else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, nw)
		_text(c, Vector2(x + nw + 6, 34), b[1], 14, Color(0.92, 0.94, 0.96), HORIZONTAL_ALIGNMENT_LEFT, null, w - nw - 6)
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
	if world.war:
		for f in world.war.forts:
			var fq: Vector2 = r.get_center() + (f.pos - Vector2(pos.x, pos.z)) * s
			if r.grow(-6).has_point(fq): _fort_icon(c, fq, f, 7.0)
		for pt in world.war.points:
			var pq: Vector2 = r.get_center() + (Vector2(pt.pos.x, pt.pos.z) - Vector2(pos.x, pos.z)) * s
			if r.grow(-6).has_point(pq): _flag_icon(c, pq, pt, 1.0)
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
	elif world.events and world.events.in_red(p.global_position):
		_text(c, Vector2(r.position.x + size * 0.5, zy + 40), "🔴 أنت بالمنطقة الحمراء — تخبّى!", 13, Color("ff7a6a"), HORIZONTAL_ALIGNMENT_CENTER, null, size)
	_text(c, Vector2(r.end.x - 8, y + 17), "%d ms 📶" % (18 + int(world.time * 3.7) % 9), 12, Color("8ef08e"), HORIZONTAL_ALIGNMENT_RIGHT, null, 90)
	if bool(Game.settings.get("show_fps", true)):
		var fps := int(Engine.get_frames_per_second())
		var fc := Color("8ef08e") if fps >= 55 else (Color("ffd34d") if fps >= 30 else Color("ff6a5a"))
		_text(c, Vector2(r.position.x + size * 0.5, y + 17), "FPS %d" % fps, 13, fc, HORIZONTAL_ALIGNMENT_CENTER, UiKit.bold(), 90)

## Sound markers on a ring round the crosshair: gunfire as a red-orange
## bullet, footsteps as two white footprints; nearer ones stand out more.
func _draw_sound_marks(c: Control, sz: Vector2, p: Player, view_yaw: float) -> void:
	var center := sz * 0.5
	for m in sound_marks:
		var to: Vector3 = m.pos - p.global_position
		var d := Vector2(to.x, to.z).length()
		if d < 1.5: continue
		var a := atan2(to.x, -to.z) + view_yaw - PI / 2.0
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var near := clampf(1.0 - d / (220.0 if m.kind == "shot" else 40.0), 0.25, 1.0)
		var alpha := minf(1.0, m.t * 1.4) * (0.5 + 0.5 * near)
		var shade := Color(0, 0, 0, alpha * 0.45)
		if m.kind == "shot":
			# A short glowing arc on the ring and a bullet pointing out at the shooter.
			var col := Color(1.0, 0.36, 0.18, alpha)
			var span := 0.07 + 0.1 * near
			c.draw_arc(center, 150.0, a - span, a + span, 10, shade, 6.0)
			c.draw_arc(center, 150.0, a - span, a + span, 10, col, 3.0)
			var at := center + dir * 172.0
			var bullet := PackedVector2Array()
			for i in 7:
				var k := PI * float(i) / 6.0 - PI / 2.0
				bullet.append(at + dir * (4.0 + cos(k) * 7.0) + side * sin(k) * 4.5)
			bullet.append(at - dir * 8.0 + side * 4.5)
			bullet.append(at - dir * 8.0 - side * 4.5)
			c.draw_colored_polygon(bullet, col)
			var edge := bullet.duplicate()
			edge.append(bullet[0])
			c.draw_polyline(edge, shade, 1.5)
		else:
			# Two footprints, one ahead of the other, pointing their way.
			var col := Color(1, 1, 1, alpha * 0.95)
			var at := center + dir * 160.0
			for f in [[side * 5.0 - dir * 4.0], [-side * 5.0 + dir * 4.0]]:
				var fp: Vector2 = at + f[0]
				c.draw_circle(fp, 5.2, shade)
				c.draw_circle(fp, 4.0, col)
				c.draw_circle(fp + dir * 7.0, 2.6, shade)
				c.draw_circle(fp + dir * 7.0, 2.0, col)

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
		if not Icons.draw_weapon(c, s.id, Rect2(rr.position + Vector2(6, 3), Vector2(rr.size.x - 12, 38)), Color.WHITE if active else Color(1, 1, 1, 0.7)):
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
		# Opens up as you fire (each shot's kick) and when you run, closes as you settle.
		var sp := Vector2(p.velocity.x, p.velocity.z).length()
		gap += p.model.recoil * 9.0 + clampf(sp - 1.0, 0.0, 6.0) * 1.6
		var col: Color = Color("ffcf5a") if p.reload_t > 0.0 else Game.CROSSHAIR_COLORS.get(Game.settings.get("crosshair", "white"), Color(1, 1, 1, 0.9))
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			c.draw_line(ctr + d * gap, ctr + d * (gap + 9.0), col, 2.0)
	c.draw_rect(Rect2(ctr - Vector2(1.5, 1.5), Vector2(3, 3)), Color("ff3d4a"))
	_hit_marks(c, ctr)

## Looking through a sight: reflex sights (red dot, holographic) keep the view
## open inside a thin housing; magnified scopes black out all but the lens.
## Breath bar under the scope: hold Shift to steady the aim.
func _draw_breath(c: Control, sz: Vector2, p: Player) -> void:
	var w := 160.0
	var pos := Vector2(sz.x * 0.5 - w * 0.5, sz.y * 0.5 + minf(sz.x, sz.y) * 0.25)
	c.draw_rect(Rect2(pos, Vector2(w, 5)), Color(0, 0, 0, 0.5))
	var col := Color("9fd0ff") if p.breath > 0.3 else Color("ff8a6a")
	c.draw_rect(Rect2(pos, Vector2(w * p.breath, 5)), col)
	var t := "حابس نفسك…" if p.holding_breath else "%s: حبس النفس" % Game.key_label(Game.key("sprint"))
	_text(c, pos + Vector2(w * 0.5, 22), t, 13, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, null, 240)

func _draw_scope(c: Control, sz: Vector2, w: Dictionary) -> void:
	var ctr := sz * 0.5
	var sight: String = w.get("sight", "")
	var red := Color(0.25, 1.0, 0.3) if Game.settings.get("dot_color", "red") == "green" else Color(1.0, 0.16, 0.12)
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
		# The hit tick pops out a little bigger and settles back (0.22 s).
		var hc := Color("ff4040") if hit_head else Color.WHITE
		var pop := 1.0 + 0.45 * clampf((hit_t - 0.14) / 0.08, 0.0, 1.0)
		hc.a = clampf(hit_t / 0.08, 0.0, 1.0)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			c.draw_line(ctr + d * 7.0 * pop, ctr + d * 15.0 * pop, Color(0, 0, 0, hc.a * 0.5), 4.5)
			c.draw_line(ctr + d * 7.0 * pop, ctr + d * 15.0 * pop, hc, 2.5)
	if kill_t > 0.0:
		# A kill: a big red cross that grows out from the crosshair.
		var k := 1.0 - kill_t / 0.6
		var r := 12.0 + k * 10.0
		var col := Color(1, 0.2, 0.15, clampf(kill_t / 0.3, 0.0, 1.0))
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			c.draw_line(ctr + d * (r * 0.4), ctr + d * r, col, 4.0)

# ---------- Hit feedback: damage numbers, hit ticks, kills and streaks ----------
var kill_t := 0.0
var _dmg_nums: Array = []        # {pos: Vector3, text, col, t}
var _streak := 0
var _streak_t := 0.0
var _tick_snd: AudioStreamWAV
var _kill_snd: AudioStreamWAV

func _on_hit(head: bool, killed: bool, pos: Vector3) -> void:
	hit_t = 0.22
	hit_head = head
	var w: Dictionary = world.player.weapon()
	var dmg := int(float(w.get("dmg", 20)) * (2.0 if head else 1.0))
	_dmg_nums.append({"pos": pos + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3)), "text": str(dmg), "col": Color("ffd34d") if head else Color.WHITE, "t": 0.8})
	if _dmg_nums.size() > 12: _dmg_nums.pop_front()
	_beep(true if killed else false, head)
	if killed:
		kill_t = 0.6
		_streak = _streak + 1 if _streak_t > 0.0 else 1
		_streak_t = 10.0
		var names := {2: "إقصاء مزدوج!", 3: "ثلاثي!", 4: "رباعي!", 5: "لا يوقف!"}
		var txt: String = names.get(mini(_streak, 5), "") if _streak >= 2 else ""
		_kill_card(txt)

## A short synthesised sound: a soft tick for a hit (higher for the head),
## a bright double chime for a kill.
func _beep(kill: bool, head: bool) -> void:
	if not Game.settings.sound: return
	if _tick_snd == null:
		_tick_snd = _tone([[1800.0, 0.035]], 0.5)
		_kill_snd = _tone([[1320.0, 0.07], [1980.0, 0.12]], 0.6)
		_thud_snd = _thud()
	# The round landing: a dull thud under the tick (a sharper crack on the head).
	var th := AudioStreamPlayer.new()
	th.stream = _thud_snd
	th.volume_db = -8.0
	th.pitch_scale = 1.5 if head else randf_range(0.9, 1.1)
	add_child(th)
	th.play()
	th.finished.connect(th.queue_free)
	var p := AudioStreamPlayer.new()
	p.stream = _kill_snd if kill else _tick_snd
	p.volume_db = -6.0 if kill else -14.0
	p.pitch_scale = 1.25 if head and not kill else 1.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

var _thud_snd: AudioStreamWAV

## A short, low, muffled knock: noise smoothed into a low rumble that dies in 80 ms.
func _thud() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.08)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / rate
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		var body := sin(t * TAU * 95.0) * 0.6 + lp * 2.2
		var env := minf(1.0, t * 900.0) * exp(-t * 45.0)
		data.encode_s16(i * 2, int(clampf(body * env * 0.7, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.data = data
	return st

func _tone(notes: Array, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	for nt in notes:
		var n := int(rate * float(nt[1]))
		var start := data.size()
		data.resize(start + n * 2)
		for i in n:
			var t := float(i) / rate
			var env := minf(1.0, t * 400.0) * exp(-t * 30.0)
			data.encode_s16(start + i * 2, int(sin(t * TAU * float(nt[0])) * env * vol * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.data = data
	return st

var _kill_box: Control

## Middle of the screen under the crosshair: a skull, "إقصاء" and the streak.
func _kill_card(streak_text: String) -> void:
	if _kill_box: _kill_box.queue_free()
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l1 := UiKit.label("☠ إقصاء", 26, Color("ff5a4a"), bold, 5)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l1)
	if streak_text != "":
		var l2 := UiKit.label(streak_text, 22, Color("ffd34d"), bold, 5)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l2)
	add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.position.y -= 110.0
	v.pivot_offset = v.size * 0.5
	v.scale = Vector2(1.5, 1.5)
	_kill_box = v
	var tw := v.create_tween()
	tw.tween_property(v, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(v, "modulate:a", 0.0, 0.4)
	tw.tween_callback(v.queue_free)

func _draw_dmg_numbers(c: Control) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null: return
	var dt := get_process_delta_time()
	for d in _dmg_nums:
		d.t -= dt
		d.pos.y += dt * 1.2
		if cam.is_position_behind(d.pos): continue
		var sp := cam.unproject_position(d.pos)
		var a := clampf(d.t / 0.3, 0.0, 1.0)
		_text(c, sp, d.text, 22 if d.col != Color.WHITE else 18, Color(d.col, a), HORIZONTAL_ALIGNMENT_CENTER, bold, 80)
	_dmg_nums = _dmg_nums.filter(func(d): return d.t > 0.0)

func _draw_prompt(c: Control, sz: Vector2, p: Player) -> void:
	if p.heal_id != "":
		_draw_heal(c, sz, p)
		return
	var key := "[F] " if Game.settings.controls == "kbm" else ""
	if world.war and world.war.near_shop(p.global_position):
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.64), key + "افتح المتجر", 19, Color("ffd34d"), HORIZONTAL_ALIGNMENT_CENTER, bold)
		return
	var door := p.door_target()
	if not door.is_empty():
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.64), key + ("سكّر الباب" if door.target > 0.5 else "افتح الباب"), 19, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold)
		return
	var it = world.nearest_pickup(p.global_position, 2.4)
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
		if t.name == "": continue
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
		if _region_centres.is_empty() and not world.island.labels.is_empty():
			_region_centres = world.island.labels.duplicate()
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
	# Lava flows and pools on the volcano.
	var lava_col := Color(1.0, 0.45, 0.1)
	for line in world.island.lava:
		for li in line.size() - 1:
			var la := _w2m(line[li])
			var lb := _w2m(line[li + 1])
			if r.has_point(la) and r.has_point(lb): c.draw_line(la, lb, lava_col, 3.0, true)
	for pl in [[world.island.crater, 56.0]] + world.island.lava_pools:
		var pc := _w2m(pl[0])
		if r.grow(-6).has_point(pc): c.draw_circle(pc, maxf(3.0, (_w2m(pl[0] + Vector2(pl[1], 0)) - pc).x), lava_col)
	# Places: a dot and the name (gold for the military base).
	var taken: Array[Rect2] = []
	for t in world.island.towns:
		var tp := _w2m(t.pos)
		if t.name == "" or not r.grow(-20).has_point(tp): continue
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
	if world.events and world.events.red_on():
		var rc := _w2m(world.events.red_center)
		if r.has_point(rc): c.draw_circle(rc, world.events.red_radius * k, Color(1, 0.1, 0.05, 0.28))
		_clipped_circle(c, r, rc, world.events.red_radius * k, Color(1, 0.2, 0.15, 0.95), 2.0)
	for ad in world.airdrops:
		var q := _w2m(Vector2(ad.global_position.x, ad.global_position.z))
		if r.has_point(q): _crate_icon(c, q, ad.landed)
	if world.war:
		for f in world.war.forts:
			var fq := _w2m(f.pos)
			if not r.grow(-10).has_point(fq): continue
			_fort_icon(c, fq, f, 11.0)
			_text(c, fq + Vector2(0, 30), War.TEAMS[f.team].fort, 14, War.TEAMS[f.team].col, HORIZONTAL_ALIGNMENT_CENTER, bold, 200)
		for pt in world.war.points:
			var pq := _w2m(Vector2(pt.pos.x, pt.pos.z))
			if not r.grow(-10).has_point(pq): continue
			_flag_icon(c, pq, pt, 1.5)
			# (Places that are towns already have their name on the map.)
			if not world.island.towns.any(func(t): return t.name == pt.name):
				_text(c, pq + Vector2(0, 24), pt.name, 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 200)
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
	if world.events and world.events.red_on():
		_clipped_circle(c, r, ctr + (world.events.red_center - me) * s, world.events.red_radius * s, Color(1, 0.2, 0.15, 0.95), 2.0)
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

# ---------- Team war ----------
## Left: the four teams — heart, fort level, people alive, places held.
func _draw_war_teams(c: Control) -> void:
	var w: War = world.war
	var y := 50.0
	for t in 4:
		var f: Dictionary = w.forts[t]
		var col: Color = War.TEAMS[t].col
		var mine: bool = t == world.player.team
		var out: bool = not w.team_in(t)
		c.draw_rect(Rect2(14, y, 236, 40), Color(0, 0, 0, 0.5 if mine else 0.35))
		c.draw_rect(Rect2(14, y, 6, 40), col if not out else Color(0.4, 0.4, 0.4))
		if mine: c.draw_rect(Rect2(14, y, 236, 40), Color(col, 0.8), false, 1.5)
		var nm: String = War.TEAMS[t].name + ("  (فريقك)" if mine else "")
		_text(c, Vector2(26, y + 16), nm, 13, Color(1, 1, 1, 0.45) if out else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, bold, 150)
		_text(c, Vector2(244, y + 16), "مستوى %d" % int(f.level), 11, Color("ffd34d"), HORIZONTAL_ALIGNMENT_RIGHT, null, 70)
		var h: FortHeart = f.heart
		if h.dead:
			_text(c, Vector2(26, y + 34), "القلب انكسر  •  حي %d" % w.alive_in(t), 12, Color("ff8a7a"), HORIZONTAL_ALIGNMENT_LEFT, null, 220)
		else:
			var k := clampf(h.hp / h.max_hp, 0.0, 1.0)
			c.draw_rect(Rect2(26, y + 24, 120, 7), Color(1, 1, 1, 0.15))
			c.draw_rect(Rect2(26, y + 24, 120 * k, 7), col if h.hit_t > 0.5 else Color.WHITE)
			_text(c, Vector2(152, y + 33), "حي %d  •  🚩%d" % [w.alive_in(t), w.points_owned(t)], 11, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, null, 100)
		y += 44.0
	feed.position.y = y + (66.0 if _shop_btn else 6.0)

func _fort_icon(c: Control, at: Vector2, f: Dictionary, s: float) -> void:
	var col: Color = War.TEAMS[f.team].col
	c.draw_rect(Rect2(at - Vector2(s, s), Vector2(s, s) * 2.0), Color.BLACK)
	c.draw_rect(Rect2(at - Vector2(s, s) * 0.8, Vector2(s, s) * 1.6), col if not f.heart.dead else col.darkened(0.6))
	if f.heart.dead:
		c.draw_line(at - Vector2(s, s) * 0.6, at + Vector2(s, s) * 0.6, Color.BLACK, 2.0)
		c.draw_line(at + Vector2(-s, s) * 0.6, at + Vector2(s, -s) * 0.6, Color.BLACK, 2.0)

func _flag_icon(c: Control, at: Vector2, pt: Dictionary, k: float) -> void:
	var col: Color = War.TEAMS[pt.owner].col if pt.owner >= 0 else Color(0.92, 0.92, 0.92)
	c.draw_line(at + Vector2(0, 7) * k, at + Vector2(0, -8) * k, Color.BLACK, 3.0 * k)
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8) * k, at + Vector2(10, -4.5) * k, at + Vector2(0, -1) * k]), col)
	c.draw_line(at + Vector2(0, 7) * k, at + Vector2(0, -8) * k, Color.WHITE, 1.4 * k)

## Middle of the screen: getting ready, the clock to the final battle,
## taking a place, coming back after dying.
func _draw_war(c: Control, sz: Vector2, p: Player) -> void:
	var w: War = world.war
	var y := sz.y * 0.3
	if w.prep_left > 0.0:
		var t := ceili(w.prep_left)
		_text(c, Vector2(sz.x * 0.5, y), "البوابات بتنفتح بعد %d:%02d" % [t / 60, t % 60], 28, Color("ffd34d") if t <= 10 else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 600)
		_text(c, Vector2(sz.x * 0.5, y + 28), "جهّز حالك — اشتري سلاحك من المتجر جوّا الحصن", 16, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, bold, 600)
	elif not w.final:
		var t2 := maxi(0, int(War.FINAL_AT - w.time))
		_text(c, Vector2(sz.x * 0.5, 96), "المعركة الأخيرة بعد %d:%02d" % [t2 / 60, t2 % 60], 14, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, bold, 300)
	if p.state == "ground":
		var pt: Dictionary = w.point_here(p.global_position)
		if not pt.is_empty():
			var col: Color = War.TEAMS[pt.owner].col if pt.owner >= 0 else Color.WHITE
			var txt := ""
			var k: float = pt.prog
			if pt.owner == p.team:
				txt = "%s — لفريقك" % pt.name
			elif pt.owner >= 0:
				txt = "عم تشيل علم %s عن %s" % [War.TEAMS[pt.owner].name, pt.name]
			else:
				txt = "عم تحتل %s" % pt.name
				if pt.capper >= 0: col = War.TEAMS[pt.capper].col
				if pt.capper != p.team: k = 0.0
			var bw := 320.0
			var r := Rect2(sz.x * 0.5 - bw * 0.5, sz.y * 0.26, bw, 10)
			c.draw_rect(r, Color(0, 0, 0, 0.55))
			c.draw_rect(Rect2(r.position, Vector2(bw * clampf(k, 0.0, 1.0), 10)), col)
			_text(c, Vector2(sz.x * 0.5, sz.y * 0.26 - 8), txt, 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold, 600)
	if p.state == "dead" and w.player_respawn > 0.0:
		_text(c, Vector2(sz.x * 0.5, sz.y * 0.42), "رح ترجع بحصنك بعد %d" % ceili(w.player_respawn), 30, Color("7dff8a"), HORIZONTAL_ALIGNMENT_CENTER, bold, 600)

## Back from the dead in team war: no results panel or spectating left over.
func end_spectate_for_respawn() -> void:
	spectating = false
	if _spec_panel:
		_spec_panel.queue_free()
		_spec_panel = null
	if results:
		results.queue_free()
		results = null
