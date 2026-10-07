extends Node
## Settings: rebinding keys (a used key swaps), the new key works in the
## match, movement keys follow, reset; pictures of the settings and keys pages.

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

func _key(code: int, pressed := true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = pressed
	return e

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.controls = "kbm"
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	var saved: Dictionary = Game.settings.keys.duplicate()
	Game.reset_keys()
	# Rebinding.
	Game.set_key("crouch", KEY_X)
	check("crouch moved to X", Game.key("crouch") == KEY_X and Game.action_for(KEY_X) == "crouch")
	check("C is free now", Game.action_for(KEY_C) == "")
	Game.set_key("crouch", KEY_R)
	check("taking R swaps reload onto X", Game.key("crouch") == KEY_R and Game.key("reload") == KEY_X)
	Game.set_key("move_forward", KEY_UP)
	var evs := InputMap.action_get_events("move_forward")
	check("walking forward follows the new key", evs.size() == 1 and (evs[0] as InputEventKey).physical_keycode == KEY_UP)
	# In the lobby: settings and keys pages.
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await wait(2.0)
	var lobby = tree.current_scene
	lobby._open("settings")
	await wait(0.5)
	await shot("settings")
	lobby._open("keys")
	await wait(0.3)
	# Click "crouch", press V.
	lobby._wait_key = "crouch"
	lobby._input(_key(KEY_V))
	await wait(0.3)
	check("keys page takes a pressed key", Game.key("crouch") == KEY_V)
	await shot("keys")
	# In a match the new key does it.
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 600:
		if world.ready_done: break
		await wait(0.1)
	for b in world.bots: b.set_physics_process(false)
	var p: Player = world.player
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[0].pos + Vector2(world.island.towns[0].r + 40.0, 0)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	for i in 40:
		if p.state == "ground" and p.is_on_floor(): break
		await wait(0.1)
	p._unhandled_input(_key(KEY_C))
	check("old key does nothing", p.stance == "stand")
	p._unhandled_input(_key(KEY_V))
	check("new key crouches", p.stance == "crouch")
	Game.reset_keys()
	check("reset gives the original keys", Game.key("crouch") == KEY_C and Game.key("reload") == KEY_R and Game.key("move_forward") == KEY_W)
	Game.settings.keys = saved
	Game.apply_keys()
	print("KEYS TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
