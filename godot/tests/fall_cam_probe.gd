extends Node
## Freefall camera: how far the camera is from the body while gliding and
## diving, and where the body sits in the view (headless numbers).
func _ready() -> void:
	Game.spawn_island = false
	Game.settings.controls = "touch"
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await tree.create_timer(0.5).timeout
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await tree.create_timer(0.1).timeout
	var p: Player = world.player
	for i in 400:
		if world.plane_over_land(): break
		world.plane_t += 0.002
		await tree.process_frame
	p.interact()
	for phase in [["glide", -0.35, Vector2(0, 1)], ["dive", -1.1, Vector2(0, 1)]]:
		p.pitch = phase[1]
		p.touch_move = phase[2]
		for k in 3:
			await tree.create_timer(1.0).timeout
			var cam: Camera3D = p.camera
			var body: Vector3 = p.model.global_position + Vector3(0, 1.0, 0)
			var sp := cam.unproject_position(body)
			print("CAM %s t=%d dist=%.1f spring=%.2f springlen=%.2f fov=%.0f screen=(%.0f,%.0f) vp=%s speed=%.0f" % [phase[0], k, cam.global_position.distance_to(body), p.spring.get_hit_length(), p.spring.spring_length, cam.fov, sp.x, sp.y, str(cam.get_viewport().get_visible_rect().size), p.air_speed])
	p.pitch = -1.1
	p.touch_move = Vector2(0, 1)
	var last := 0.0
	for i in 3000:
		var alt: float = p.global_position.y - world.ground_height(p.global_position)
		if p.state != "fall":
			print("CHUTE opened alt=%.0f prev=%.0f vy=%.1f y=%.0f ground=%.0f" % [alt, last, p.velocity.y, p.global_position.y, world.ground_height(p.global_position)])
			break
		last = alt
		await tree.physics_frame
	tree.quit()
