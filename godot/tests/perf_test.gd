extends Node
## CPU cost per frame with all bots landed close to the player (worst case).

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 600:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	p.health = 1e9
	var t: Dictionary = world.island.towns[1]
	p.jump_from_plane()
	p.global_position = Vector3(t.pos.x, world.ground_height(Vector3(t.pos.x, 0, t.pos.y)) + 2.0, t.pos.y)
	for b in world.bots:
		var q: Vector2 = t.pos + Vector2(randf_range(20, 180), 0).rotated(randf() * TAU)
		b.visible = true
		b.global_position = Vector3(q.x, world.ground_height(Vector3(q.x, 0, q.y)) + 0.3, q.y)
		b._land()
	await wait(2.0)
	# Run physics as fast as the CPU allows and count ticks per real second.
	var args := OS.get_cmdline_user_args()
	if args.has("--nobots"):
		for b in world.bots: b.set_physics_process(false)
	Engine.max_physics_steps_per_frame = 200
	Engine.physics_ticks_per_second = 1000
	var ticks := [0]
	tree.physics_frame.connect(func(): ticks[0] += 1)
	var t0 := Time.get_ticks_msec()
	await get_tree().create_timer(3.0, true, false, true).timeout
	var real_s := (Time.get_ticks_msec() - t0) / 1000.0
	Engine.physics_ticks_per_second = 60
	print("PERF %.2f ms per physics tick (%d ticks in %.1f s, %d bots within 180 m)" % [real_s * 1000.0 / maxf(1.0, ticks[0]), ticks[0], real_s, world.bots.size()])
	tree.quit()
