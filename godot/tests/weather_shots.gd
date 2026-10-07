extends Node
## A town in each weather: --weather=rain|sunset|clear. Checks the rain is
## there (streaks and sound) and takes pictures with --out=/dir.

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
	var w := "rain"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--weather="): w = a.substr(10)
	Game.settings.weather = w
	Game.settings.controls = "kbm"
	_run.call_deferred(w)

func _run(w: String) -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 600:
		if world.ready_done: break
		await wait(0.1)
	check("weather is " + w, world.weather == w)
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(5000, 0, 5000)
	var p: Player = world.player
	p.jump_from_plane()
	var t: Dictionary = world.island.towns[1]
	var c: Vector2 = t.pos + Vector2(t.r + 25.0, 0)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	p.yaw = PI * 0.5     # facing the town (-x)
	p.pitch = -0.05
	await wait(3.0)
	if w == "rain":
		check("rain falling", world._rain != null and world._rain.emitting)
		if Game.settings.sound:
			check("rain heard", world._rain_snd != null and world._rain_snd.playing)
	await shot("weather_" + w)
	p.yaw = -PI * 0.5
	await wait(1.0)
	await shot("weather_" + w + "_2")
	print("WEATHER TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
