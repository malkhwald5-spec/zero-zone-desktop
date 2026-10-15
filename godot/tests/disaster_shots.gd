extends Node
## Standing outside the safe zone in each region (volcano, north, desert,
## plains): the disaster there, and the zone's edge seen from outside.
## Run: godot --path godot res://tests/disaster_shots.tscn -- --out=/dir

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
	Game.settings.controls = "kbm"
	Game.settings.weather = "clear"
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
	for b in world.bots: b.set_physics_process(false)
	p.jump_from_plane()
	var isl = world.island
	# A tiny safe zone in the middle: everywhere else is outside.
	var z: Zone = world.zone
	z.start()
	z.center = Vector2(isl.size * 0.5, isl.size * 0.5)
	z.radius = 300.0
	z.next_center = z.center
	z.next_radius = 300.0
	z.state = "wait"
	z.time_left = 999.0
	for want in ["volcano", "nordic", "desert", "plains"]:
		var at := Vector2.INF
		for k in 3000:
			var q: Vector2 = Vector2(randf_range(0.08, 0.92), randf_range(0.08, 0.92)) * isl.size
			if q.distance_to(z.center) > 600.0 and isl.region_at(q.x, q.y) == want and isl.height_at(q.x, q.y) > 2.0 and isl.height_at(q.x, q.y) < 200.0:
				at = q
				break
		if at == Vector2.INF: continue
		p.global_position = Vector3(at.x, isl.height_at(at.x, at.y) + 1.0, at.y)
		var to := (z.center - at).normalized()
		p.yaw = atan2(-to.x, -to.y) + 0.6
		p.pitch = -0.05
		for i in 40:
			if p.state == "ground": break
			await wait(0.1)
		await wait(3.0)
		await shot("disaster_" + want)
	# The zone's edge from outside, near the volcano side.
	print("DISASTER DONE")
	tree.quit()
