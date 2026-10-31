extends Node
## A field of tall dry grass on the plains: the player standing in it,
## through the game camera and from low down.
## Run: godot --path godot res://tests/field_shots.tscn -- --out=/dir

var out := "user://"

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.controls = "touch"
	Game.settings.weather = "clear"
	Game.settings.mode = "solo"
	Game.spawn_island = false
	Game.settings.lite = false
	Game.settings.quality = "high"
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	p.health = 1e9
	p.jump_from_plane()
	for b in world.bots: b.set_physics_process(false)
	var img: Image = world.builder.noise_a.get_image()
	var isl = world.island
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var at := Vector3.ZERO
	var best := 0.0
	for k in 6000:
		var x: float = rng.randf_range(0.1, 0.9) * float(isl.size)
		var z: float = rng.randf_range(0.1, 0.9) * float(isl.size)
		if not isl.is_land(x, z) or isl.region_at(x, z) in ["nordic", "volcano", "jungle", "desert"]: continue
		var u := fposmod(x / 260.0 + 0.71, 1.0)
		var v := fposmod(z / 260.0 + 0.23, 1.0)
		var n: float = img.get_pixel(int(u * img.get_width()) % img.get_width(), int(v * img.get_height()) % img.get_height()).r
		if n > best and world._in_building(Vector2(x, z), 6.0) == false:
			best = n
			at = Vector3(x, isl.height_at(x, z), z)
	print("FIELD at %s noise %.2f region %s" % [at, best, isl.region_at(at.x, at.z)])
	p.global_position = at + Vector3(0, 0.5, 0)
	p.velocity = Vector3.ZERO
	p._land()
	p.yaw = 0.6
	p.pitch = -0.1
	p.give_weapon("m416", 30)
	p.switch_slot(0)
	await wait(2.5)
	await shot("field_0_game")
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 50.0
	cam.global_position = at + Vector3(5, 1.4, 5)
	cam.look_at(at + Vector3(0, 0.9, 0))
	cam.current = true
	world.hud.visible = false
	await wait(0.6)
	await shot("field_1_low")
	cam.global_position = at + Vector3(14, 7, 10)
	cam.look_at(at + Vector3(0, 0.5, 0))
	await wait(0.6)
	await shot("field_2_high")
	tree.quit()
