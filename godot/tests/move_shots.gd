extends Node
## Pictures of the moves: getting into a car (you and a bot), a bot driving
## past, leaning round cover. Run: godot --path godot res://tests/move_shots.tscn -- --out=/dir

var out := "user://"
var cam: Camera3D

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	cam.make_current()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.controls = "kbm"
	Game.settings.weather = "clear"
	Game.settings.quality = "high"
	Game.settings.mode = "solo"
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
	if world.spawn: world.board_plane()
	p.jump_from_plane()
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(5000, -50, 5000)
	cam = Camera3D.new()
	cam.fov = 50
	world.add_child(cam)
	# A flat open spot on a road.
	var isl = world.island
	var at := Vector2.ZERO
	var dir := Vector2(0, 1)
	for rd in isl.roads:
		if rd.get("runway", false): continue
		var q: Vector2 = rd.a.lerp(rd.b, 0.5)
		var g: float = absf(isl.height_at(q.x + 6.0, q.y) - isl.height_at(q.x - 6.0, q.y)) + absf(isl.height_at(q.x, q.y + 6.0) - isl.height_at(q.x, q.y - 6.0))
		if isl.height_at(q.x, q.y) > 1.5 and g < 0.6 and world.building_at(q, 12.0) < 0:
			at = q
			dir = (rd.b - rd.a).normalized()
			break
	var v: Vehicle = null
	for c in world.vehicles:
		if c.kind == "sedan" and not c.dead:
			v = c
			break
	var gy: float = world.ground_height(Vector3(at.x, 0, at.y))
	v.freeze = false
	v.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(at.x, gy + 0.9, at.y))
	v.linear_velocity = Vector3.ZERO
	v.reset_physics_interpolation()
	await wait(1.5)
	# You get in: from the side, beside the driver's door.
	var door: Vector3 = v.global_transform * (v.seat_xform().origin + Vector3(1.0, 0, 0))
	p.global_position = Vector3(door.x, world.ground_height(door) + 0.3, door.z)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	for i in 40:
		if p.state == "ground": break
		await wait(0.25)
	await wait(0.5)
	var c0: Vector3 = v.global_transform * Vector3(4.5, 1.6, 1.5)
	cam.look_at_from_position(c0, v.global_position + Vector3(0, 0.7, 0))
	await shot("move_0_by_car")
	p.enter_vehicle(v)
	for k in [0.15, 0.35, 0.6, 1.0]:
		await wait(0.25 if k < 1.0 else 0.4)
		await shot("move_board_%d" % int(k * 100))
	p.exit_vehicle()
	await wait(0.5)
	# A bot drives past you.
	var b: Bot = world.bots[0]
	b.weapon_id = "m416"
	b.mag = 30
	b.reserve = 60
	b.blind_t = 1e6
	var side := Vector3(-dir.y, 0, dir.x)
	var bp: Vector3 = v.global_position + side * 3.5
	b.global_position = Vector3(bp.x, world.ground_height(bp) + 0.3, bp.z)
	b.state = "ground"
	b.visible = true
	b.shape.disabled = false
	b.goal = v.global_position + Vector3(dir.x, 0, dir.y) * 600.0
	b.mode = "zone"
	p.global_position = v.global_position - side * 6.0 + Vector3(dir.x, 0, dir.y) * 14.0
	p.global_position.y = world.ground_height(p.global_position) + 0.4
	p.reset_physics_interpolation()
	if b._want_car():
		b.set_physics_process(true)
		for i in 40:
			if b.state == "vehicle": break
			await wait(0.1)
		cam.look_at_from_position(v.global_transform * Vector3(-5.0, 1.8, 2.0), v.global_position + Vector3(0, 0.8, 0))
		await wait(0.35)
		await shot("move_bot_boarding")
		await wait(2.4)
		var bv: Vehicle = b.vehicle if b.vehicle else v
		var vp: Vector3 = bv.global_position
		print("shot info: bot car ", bv == v, " state ", b.state, " speed ", bv.speed(), " at ", bv.global_position, " cam ", vp + side * 9.0 + bv.linear_velocity * 0.6)
		cam.look_at_from_position(vp + side * 9.0 + Vector3(0, 2.0, 0) + bv.linear_velocity * 0.6, vp + Vector3(0, 0.8, 0))
		await shot("move_bot_driving")
	print("MOVE SHOTS DONE")
	tree.quit()
