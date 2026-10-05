extends Node
## Screenshots of both car kinds, driving (driver in the seat, dust) and a
## damaged car on fire. Run: godot --path godot res://tests/car_shots.tscn -- --out=/dir

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
	var cam := Camera3D.new()
	world.add_child(cam)
	for kind in ["sedan", "jeep"]:
		var car: Vehicle = null
		for v in world.vehicles:
			if v.kind == kind: car = v; break
		if car == null: continue
		p.global_position = car.global_position + Vector3(30, 50, 0)
		await wait(1.0)
		var tf: Transform3D = car.global_transform
		cam.current = true
		cam.fov = 45
		cam.look_at_from_position(tf * Vector3(3.2, 1.6, 4.6), tf * Vector3(0, 0.8, 0))
		await wait(0.3)
		await shot("car_%s_front" % kind)
		cam.look_at_from_position(tf * Vector3(-3.8, 1.9, -4.2), tf * Vector3(0, 0.8, 0))
		await wait(0.3)
		await shot("car_%s_back" % kind)
	# Drive the first car.
	var car2: Vehicle = world.vehicles[0]
	p.jump_from_plane()
	p.global_position = car2.global_position + Vector3(2, 0.5, 0)
	p._land()
	p.enter_vehicle(car2)
	camera_player(p)
	p.yaw = car2.global_rotation.y + PI
	p.pitch = -0.2
	p.touch_move = Vector2(0, 1)
	await wait(3.5)
	p.touch_move = Vector2(-0.6, 1)
	await wait(0.8)
	await shot("car_drive")
	print("speed km/h ", car2.speed() * 3.6)
	p.touch_move = Vector2.ZERO
	await wait(2.0)
	# Damaged car.
	var car3: Vehicle = world.vehicles[1]
	car3.take_damage(car3.MAX_HEALTH * 0.85, null)
	p.exit_vehicle()
	p.global_position = car3.global_position + Vector3(30, 50, 0)
	cam.current = true
	var tf3: Transform3D = car3.global_transform
	cam.look_at_from_position(tf3 * Vector3(3.5, 2.0, 5.0), tf3 * Vector3(0, 0.9, 0))
	await wait(2.0)
	await shot("car_damaged")
	tree.quit()

func camera_player(p: Player) -> void:
	p.camera.current = true
