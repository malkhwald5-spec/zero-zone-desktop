extends Node
## Laptop mode: lower 3D resolution, lighter effects, shorter grass and tree distance;
## the same view with it off and on (frame time and pictures), the FPS counter and
## the settings page. Settings are put back at the end.

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

## Average frame time over a few seconds, in ms.
func frame_ms(sec: float) -> float:
	var n := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < int(sec * 1e6):
		await get_tree().process_frame
		n += 1
	return float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, n)

func _match(laptop: bool) -> Node:
	Game.settings.laptop = laptop
	var tree := get_tree()
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	p.health = 1e9
	for b in world.bots: b.set_physics_process(false)
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[2].pos + Vector2(30, 30)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 0.5, c.y)
	p.yaw = 0.7
	await wait(2.0)
	return world

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	var saved: Dictionary = Game.settings.duplicate(true)
	Game.settings.quality = "high"
	Game.settings.render_scale = 1.0
	Game.settings.show_fps = true
	var world = await _match(false)
	check("full resolution when off", absf(get_viewport().scaling_3d_scale - 1.0) < 0.01)
	var ms_off := await frame_ms(3.0)
	await shot("laptop_off")
	world = await _match(true)
	var vp := get_viewport()
	check("laptop draws 3D at 77%", absf(vp.scaling_3d_scale - 0.77) < 0.01 and vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR, str(vp.scaling_3d_scale))
	check("heavy effects off", not world.builder.env.ssao_enabled and not world.builder.env.volumetric_fog_enabled)
	check("shorter camera range", world.player.camera.far < 3000.0)
	var ms_on := await frame_ms(3.0)
	print("FRAME ms: off %.1f  laptop %.1f" % [ms_off, ms_on])
	check("laptop is not slower", ms_on <= ms_off * 1.05, "%.1f vs %.1f" % [ms_on, ms_off])
	await shot("laptop_on")
	Game.settings.render_scale = 0.6
	Game.apply_quality(world.builder.env, null)
	check("render scale slider", absf(vp.scaling_3d_scale - 0.6) < 0.01)
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await wait(2.0)
	tree.current_scene._open("settings")
	await wait(0.5)
	await shot("laptop_settings")
	Game.settings = saved
	Game.apply_quality(null, null)
	Game.save_data()
	print("LAPTOP TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	tree.quit()
