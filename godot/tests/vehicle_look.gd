extends Node
## The cars side by side on the runway (are they level, on their wheels?), a
## driver in each, a short drive (speed), and a boat in the sea.
## Run: godot --path godot res://tests/vehicle_look.tscn -- --out=/dir

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
	Game.settings.quality = "high"
	Game.settings.weather = "clear"
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
	world.hud.visible = false
	for b in world.bots: b.set_physics_process(false)
	p.jump_from_plane()
	var isl = world.island
	var ra: Vector2 = isl._m(Island.RUNWAY[0])
	var rb: Vector2 = isl._m(Island.RUNWAY[1])
	var along := (rb - ra).normalized()
	var mid := ra.lerp(rb, 0.5)
	var cars := []
	var kinds := ["sedan", "jeep", "pickup"]
	for i in kinds.size():
		var v := Vehicle.new()
		v.world = world
		v.kind = kinds[i]
		v.paint = Color("b8402f")
		var at: Vector2 = mid + along * (i - 1) * 8.0
		v.position = Vector3(at.x, isl.height_at(at.x, at.y) + 1.0, at.y)
		v.rotation.y = atan2(along.y, -along.x)        # facing across the runway
		world.add_child(v)
		world.vehicles.append(v)
		cars.append(v)
	p.global_position = Vector3(mid.x, isl.height_at(mid.x, mid.y) + 40.0, mid.y)
	await wait(3.0)
	for v in cars:
		print("%s up %.2f  y %.2f" % [v.kind, v.global_transform.basis.y.dot(Vector3.UP), v.global_position.y - isl.height_at(v.global_position.x, v.global_position.z)])
	var cam := Camera3D.new()
	cam.fov = 50
	world.add_child(cam)
	cam.current = true
	var c3: Vector3 = cars[1].global_position
	var side := Vector3(along.x, 0, along.y).cross(Vector3.UP)
	cam.look_at_from_position(c3 + side * 6.0 + Vector3(0, 4, 0) + Vector3(along.x, 0, along.y) * 3.0, c3)
	await wait(0.3)
	await shot("veh_row")
	cam.look_at_from_position(c3 - side * 7.0 + Vector3(0, 1.4, 0) - Vector3(along.x, 0, along.y) * 12.0, c3)
	await wait(0.3)
	await shot("veh_row2")
	# Seated, seen from the driver's side; then drive.
	for v in cars:
		p.global_position = v.global_position + Vector3(2, 0.5, 0)
		p._land()
		p.enter_vehicle(v)
		await wait(0.8)
		var tv: Transform3D = v.global_transform
		cam.look_at_from_position(tv * Vector3(-4.5, 1.6, 0.8), tv * Vector3(0, 1.0, 0))
		await wait(0.3)
		await shot("veh_seat_" + v.kind)
		p.touch_move = Vector2(0, 1)
		await wait(3.0)
		print("%s speed km/h %.1f" % [v.kind, v.speed() * 3.6])
		p.touch_move = Vector2.ZERO
		p.exit_vehicle(true)
		await wait(0.5)
	# The boat.
	var boat: Vehicle = null
	for v in world.vehicles:
		if v.kind == "boat": boat = v; break
	if boat:
		p.global_position = boat.global_position + Vector3(0, 30, 0)
		await wait(1.0)
		var tb: Transform3D = boat.global_transform
		cam.look_at_from_position(tb * Vector3(6.5, 2.5, 3.0), tb * Vector3(0, 0.8, 0))
		await wait(0.3)
		await shot("veh_boat")
		p.global_position = boat.global_position + Vector3(2, 0.5, 0)
		p.enter_vehicle(boat)
		await wait(0.8)
		tb = boat.global_transform
		cam.look_at_from_position(tb * Vector3(-5.0, 2.2, 1.0), tb * Vector3(0, 1.0, 0))
		await wait(0.3)
		await shot("veh_seat_boat")
	print("VEHICLE LOOK DONE")
	tree.quit()
