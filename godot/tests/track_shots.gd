extends Node
## Tyre tracks: a car driven in a circle on grass, then braking hard on a road;
## pictures of the marks from above and from low behind.
## Run: godot --path godot res://tests/track_shots.tscn -- --out=/dir

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
	Game.spawn_island = false
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
	world.hud.visible = false
	for b in world.bots: b.set_physics_process(false)
	var p: Player = world.player
	p.health = 1e9
	var car: Vehicle = null
	for v in world.vehicles:
		if v.kind in ["sedan", "pickup", "uaz"]:
			car = v
			break
	# Open grass by the biggest town.
	var big: Dictionary = world.island.towns[0]
	for tw in world.island.towns:
		if tw.kind != "fort" and float(tw.r) > float(big.r): big = tw
	var q := Vector3(big.pos.x + float(big.r) + 60.0, 0, big.pos.y)
	car.global_position = Vector3(q.x, world.ground_height(q) + 1.2, q.z)
	car.linear_velocity = Vector3.ZERO
	await wait(0.8)
	p.global_position = car.global_position + car.global_basis.x * 2.5
	await wait(0.2)
	p.enter_vehicle(car)
	await wait(1.5)
	p.touch_move = Vector2(0.6, 1.0)
	for i in 7:
		await wait(1.0)
		print("drive state=%s speed=%.1f marks=%d" % [p.state, car.speed(), world._mark_n])
	p.touch_move = Vector2.ZERO
	await wait(2.0)
	print("shot marks=%d" % world._mark_n)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	var c: Vector3 = car.global_position - car.global_basis.z * 8.0
	cam.look_at_from_position(c + Vector3(6, 22, 6), c, Vector3.UP)
	await wait(0.5)
	await shot("tracks_above")
	var back: Vector3 = car.global_position - car.global_basis.z * 20.0
	back.y = world.ground_height(back) + 2.0
	cam.look_at_from_position(back, car.global_position, Vector3.UP)
	await wait(0.5)
	await shot("tracks_low")
	tree.quit()
