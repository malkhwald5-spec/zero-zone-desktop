extends Node
## Settings: every tab of the settings page and the touch button editor
## (pictures), moving and resizing a button and saving it, and that the
## options work in a match (scope modes, shot on release, hold-to-lean,
## per-scope sensitivity, auto-pickup limits, crosshair colour, left fire
## button). The saved settings are put back at the end.

var out := "user://"
var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok: fails += 1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	_run.call_deferred()

func _drag(target: Control, from: Vector2, to: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = from
	target._gui_input(e)
	var m := InputEventMouseMotion.new()
	m.position = to
	target._gui_input(m)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = to
	target._gui_input(u)

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	var saved: Dictionary = Game.settings.duplicate(true)
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await wait(2.0)
	var lobby = tree.current_scene
	for t in lobby.SET_TABS:
		lobby._set_tab = t[0]
		lobby._open("settings")
		await wait(0.3)
		await shot("settings_" + t[0])
	# A choice button saves at once.
	lobby._set_tab = "scope"
	lobby._open("settings")
	await wait(0.2)
	Game.settings.crosshair = "white"
	var found: Button = null
	for b in lobby.panel.find_children("*", "Button", true, false):
		if (b as Button).text == "أخضر" and found == null: found = b
	if found: found.pressed.emit()
	check("choice saves", Game.settings.crosshair == "green", str(Game.settings.crosshair))
	# Touch editor: drag the jump button, resize it, save.
	Game.settings.touch_layouts = [{}, {}, {}]
	Game.settings.touch_layout = 0
	lobby._open_touch_editor()
	await wait(0.4)
	var ed: TouchEditor = lobby._editor
	check("editor opens", ed != null)
	await shot("touch_editor_default")
	var jump_pos: Vector2 = ed._pos_of("jump")
	var to := Vector2(ed.size.x * 0.5, ed.size.y * 0.5)
	_drag(ed, jump_pos, to)
	check("button moved", ed._pos_of("jump").distance_to(to) < 2.0, str(ed._pos_of("jump")))
	_drag(ed, ed._pos_of("jump"), ed._pos_of("jump"))
	ed._size.value = 1.5
	var r := 0.0
	for b in ed.ui.buttons:
		if b.id == "jump": r = b.r
	check("button resized", absf(r - 45.0) < 0.5, str(r))
	_drag(ed, ed.ui.joy_center, Vector2(220, ed.size.y - 200))
	await wait(0.2)
	await shot("touch_editor")
	for b in ed._bar.get_children():
		if b is Button and b.text == "حفظ": b.pressed.emit()
	check("layout saved", Game.touch_override("jump").size() == 3 and Game.touch_override("joy").size() == 3)
	for b in ed._bar.get_children():
		if b is Button and b.text == "خروج": b.pressed.emit()
	await wait(0.2)
	check("editor closed, layout kept", lobby._editor == null and Game.touch_override("jump").size() == 3)
	# In a match.
	Game.settings.controls = "touch"
	lobby._close_panel()
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[2].pos
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	await wait(1.0)
	var touch: TouchUI = world.hud.touch
	var jb := {}
	for b in touch.buttons:
		if b.id == "jump": jb = b
	var tsz: Vector2 = touch.size if touch.size.x > 0 else touch.get_viewport_rect().size
	check("match uses saved layout", jb.pos.distance_to(tsz * 0.5) < 3.0, str(jb.pos) + " " + str(tsz))
	# Scope modes.
	Game.settings.scope_mode = "tap"
	p.aiming = false
	p.action("aim", true); p.action("aim", false)
	check("tap: toggles on", p.aiming)
	p.action("aim", true); p.action("aim", false)
	check("tap: toggles off", not p.aiming)
	Game.settings.scope_mode = "hold"
	p.action("aim", true)
	var held := p.aiming
	p.action("aim", false)
	check("hold: only while held", held and not p.aiming)
	Game.settings.scope_mode = "mixed"
	p.action("aim", true); p.action("aim", false)
	check("mixed: short tap toggles", p.aiming)
	p.action("aim", true); p.action("aim", false)
	p._aim_t0 -= 1000
	p.action("aim", true)
	p._aim_t0 -= 1000
	p.action("aim", false)
	check("mixed: long press is hold", not p.aiming)
	# Shot on release (bolt action).
	p.give_weapon("kar98", 5, {})
	Game.settings.bolt_fire = "release"
	p.firing = false
	p.action("fire", true)
	var on_press := p.firing
	p.action("fire", false)
	check("bolt: fires on release", not on_press and p.firing)
	p.firing = false
	Game.settings.bolt_fire = "tap"
	# Lean hold.
	Game.settings.lean_mode = "hold"
	p.action("peek_l", true)
	var leaning := p.peek_toggle < 0.0
	p.action("peek_l", false)
	check("lean hold", leaning and p.peek_toggle == 0.0)
	Game.settings.lean_mode = "tap"
	# Per-scope sensitivity.
	p.slots[p.active].att = {"sight": "x4"}
	p._after_attach_change(p.active)
	p.aiming = true
	var y0 := p.yaw
	Game.settings.sens_4x = 0.5
	p.add_look(100, 0)
	var d1 := absf(p.yaw - y0)
	y0 = p.yaw
	Game.settings.sens_4x = 1.0
	p.add_look(100, 0)
	var d2 := absf(p.yaw - y0)
	check("4x sensitivity setting", absf(d2 / maxf(d1, 0.00001) - 2.0) < 0.05, "%.5f %.5f" % [d1, d2])
	p.aiming = false
	# Auto-pickup limits.
	p.heals.bandage = 20
	Game.settings.max_bandage = 20
	check("bandage limit stops", not world._auto_wanted({"kind": "heal", "id": "bandage", "n": 5}))
	Game.settings.max_bandage = 30
	check("bandage limit raised", world._auto_wanted({"kind": "heal", "id": "bandage", "n": 5}))
	Game.settings.pick_meds = false
	check("meds off", not world._auto_wanted({"kind": "heal", "id": "bandage", "n": 5}))
	Game.settings.pick_meds = true
	check("fitting attachment wanted", world._auto_wanted({"kind": "attach", "id": "suppressor"}))
	# Left fire button.
	var lf := {}
	for b in touch.buttons:
		if b.id == "fire_l": lf = b
	Game.settings.left_fire = "off"
	var off := not touch.shown(lf)
	Game.settings.left_fire = "scope"
	var scope_hidden := not touch.shown(lf)
	Game.settings.left_fire = "always"
	check("left fire off / with scope", off and scope_hidden and touch.shown(lf))
	# Picture: hurt, heal prompt, green crosshair, custom layout.
	Game.settings.crosshair = "green"
	p.health = 40.0
	p.heals.firstaid = 1
	await wait(0.5)
	await shot("settings_match")
	Game.settings = saved
	Game.save_data()
	print("SETTINGS TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	tree.quit()
