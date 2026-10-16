extends Node
## Bots driving: a bot with a long way to go takes a car parked next to it,
## gets in, drives it towards its goal (for real near you, "on paper" far
## off), and gets out near the goal or when shot at.

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
	Game.settings.controls = "touch"
	Game.settings.mode = "solo"
	_run.call_deferred()

## The longest dry, fairly flat road: [start, direction].
func _road(isl) -> Array:
	var best: Dictionary = isl.roads[0]
	var best_len := 0.0
	for rd in isl.roads:
		if rd.get("runway", false): continue
		var ok := true
		for k in 21:
			var q: Vector2 = rd.a.lerp(rd.b, k / 20.0)
			if isl.height_at(q.x, q.y) < 1.5: ok = false
		var l: float = rd.a.distance_to(rd.b)
		if ok and l > best_len:
			best_len = l
			best = rd
	return [best.a, (best.b - best.a).normalized(), best_len]

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
	if world.spawn: world.board_plane()
	p.jump_from_plane()
	p.health = 1e9
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(5000, -50, 5000)
	var r: Array = _road(world.island)
	var a2: Vector2 = r[0] + r[1] * 40.0
	var dir2: Vector2 = r[1]
	# A sedan on the road, the bot beside it, the goal 700 m on along it.
	var v: Vehicle = null
	for c in world.vehicles:
		if c.kind == "sedan" and c.driver == null and not c.dead:
			v = c
			break
	v.freeze = false
	v.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir2.x, dir2.y)), Vector3(a2.x, world.ground_height(Vector3(a2.x, 0, a2.y)) + 0.9, a2.y))
	v.linear_velocity = Vector3.ZERO
	v.reset_physics_interpolation()
	var b: Bot = world.bots[0]
	b.weapon_id = "m416"
	b.mag = 30
	b.reserve = 90
	var side := Vector2(-dir2.y, dir2.x) * 4.0
	var bp := Vector3(a2.x + side.x, 0, a2.y + side.y)
	b.global_position = Vector3(bp.x, world.ground_height(bp) + 0.3, bp.z)
	b.state = "ground"
	b.visible = true
	b.shape.disabled = false
	b.target = null
	b.blind_t = 1e6         # you are only watching: it does not go for you
	var gl: Vector2 = a2 + dir2 * minf(700.0, r[2] - 60.0)
	b.goal = Vector3(gl.x, 0, gl.y)
	b.mode = "zone"
	# You stand by the road watching (so the car is driven for real).
	var pp: Vector3 = Vector3(a2.x, 0, a2.y) - Vector3(side.x, 0, side.y) * 3.0
	p.global_position = Vector3(pp.x, world.ground_height(pp) + 0.5, pp.z)
	p.reset_physics_interpolation()
	await wait(1.0)
	check("wants the car", b._want_car(), "mode %s" % b.mode)
	b.set_physics_process(true)
	for i in 60:
		if b.state == "vehicle": break
		await wait(0.25)
	check("got in", b.state == "vehicle" and v.driver == b, "state %s driver %s" % [b.state, v.driver])
	var start := v.global_position
	await wait(1.0)
	await shot("drive_1_boarding")
	# (A car that starts against something backs up and tries again first.)
	var moved := 0.0
	var real := false
	for i in 40:
		await wait(0.5)
		moved = v.global_position.distance_to(start)
		real = not v.freeze
		if moved > 30.0: break
	check("drives off (near you, real physics)", moved > 30.0 and real, "%.0f m, stuck %d" % [moved, b._drive_stuck])
	await wait(5.0)
	await shot("drive_2_away")
	# Now you are far away: the car goes on without physics.
	p.global_position = Vector3(pp.x, world.ground_height(pp) + 0.5, pp.z) - Vector3(dir2.x, 0, dir2.y) * 600.0
	p.reset_physics_interpolation()
	var mid := v.global_position
	await wait(8.0)
	check("keeps going far off", v.global_position.distance_to(mid) > 40.0 and b.state == "vehicle", "%.0f m, frozen %s" % [v.global_position.distance_to(mid), v.freeze])
	for i in 120:
		if b.state != "vehicle": break
		await wait(0.5)
	check("gets out near the goal", b.state == "ground" and v.driver == null and b.global_position.distance_to(b.goal) < 120.0, "state %s %.0f m from goal" % [b.state, b.global_position.distance_to(b.goal)])
	check("car stands on the ground", v.global_position.y > world.ground_height(v.global_position) - 0.5, "")
	# Shot at the wheel: gets out to fight.
	if b.state == "ground":
		b.goal = b.global_position + Vector3(dir2.x, 0, dir2.y) * -600.0
		b.mode = "zone"
		p.global_position = b.global_position + Vector3(30, 0, 0)
		p.global_position.y = world.ground_height(p.global_position) + 0.5
		p.reset_physics_interpolation()
		await wait(0.5)
		v.driver = null
		v.freeze = false
		if b._want_car():
			for i in 60:
				if b.state == "vehicle": break
				await wait(0.25)
			await wait(2.0)
			v.take_damage(20.0, p)
			await wait(1.0)
			check("shot at: gets out", b.state == "ground" and b.health < 100.0, "state %s hp %.0f" % [b.state, b.health])
		else:
			check("wants the car again", false)
	print("DRIVE TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	tree.quit()
