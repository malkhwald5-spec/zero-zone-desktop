extends Node
## Motorbike and boat: the bike speeds up, stays upright and leans into
## turns; the boat floats, sails, turns, and you can't step off into deep water.

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
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(5000, 0, 5000)
	var p: Player = world.player
	p.jump_from_plane()
	p.health = 1e6
	var bikes: Array = world.vehicles.filter(func(v): return v.kind == "bike")
	var boats: Array = world.vehicles.filter(func(v): return v.kind == "boat")
	check("bikes on the roads", bikes.size() >= 3, "%d" % bikes.size())
	check("boats by the shore", boats.size() >= 4, "%d" % boats.size())
	# --- Bike ---
	var bike: Vehicle = bikes[0]
	# A straight bit of road: put the bike on the longest road, facing along it.
	var best: Dictionary = world.island.roads[0]
	for rd in world.island.roads:
		if rd.a.distance_to(rd.b) > best.a.distance_to(best.b): best = rd
	var a2: Vector2 = best.a.lerp(best.b, 0.3)
	var dir: Vector2 = (best.b - best.a).normalized()
	bike.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(a2.x, world.ground_height(Vector3(a2.x, 0, a2.y)) + 0.7, a2.y))
	bike.linear_velocity = Vector3.ZERO
	await wait(1.0)
	p.global_position = bike.global_position + Vector3(2, 0.5, 0)
	await wait(0.3)
	p.enter_vehicle(bike)
	check("on the bike", p.state == "vehicle" and p.vehicle == bike)
	var start := bike.global_position
	p.touch_move = Vector2(0, 1)
	var top := 0.0
	for i in 30:
		await wait(0.2)
		top = maxf(top, absf(bike.speed()))
	check("bike speeds up", top > 14.0, "top %.1f m/s" % top)
	check("bike stays upright (no roll)", absf(bike.global_basis.x.y) < 0.1, "roll %.2f" % bike.global_basis.x.y)
	await shot("bike_ride")
	p.touch_move = Vector2(0.8, 1)
	var max_lean := 0.0
	for i in 10:
		await wait(0.15)
		max_lean = maxf(max_lean, absf(bike.lean))
	check("bike leans into the turn", max_lean > 0.08, "lean %.2f" % max_lean)
	check("still upright in the turn", absf(bike.global_basis.x.y) < 0.1)
	await shot("bike_turn")
	p.touch_move = Vector2.ZERO
	await wait(2.0)
	p.exit_vehicle()
	check("off the bike", p.state == "ground")
	# --- Boat ---
	var boat: Vehicle = boats[0]
	await wait(0.5)
	var dy: float = boat.global_position.y - Island.WATER
	check("boat floats", dy > -0.6 and dy < 0.5 and boat.global_basis.y.y > 0.9, "y-water=%.2f up=%.2f" % [dy, boat.global_basis.y.y])
	# Point it at open water.
	var best_dir := Vector3.FORWARD
	var best_free := -1.0
	for k in 16:
		var d3 := Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0))
		var free := 0.0
		while free < 150.0 and world.is_deep(boat.global_position + d3 * (free + 5.0)): free += 5.0
		if free > best_free:
			best_free = free
			best_dir = d3
	boat.global_transform = Transform3D(Basis(Vector3.UP, atan2(best_dir.x, best_dir.z)), Vector3(boat.global_position.x, Island.WATER + 0.2, boat.global_position.z))
	boat.linear_velocity = Vector3.ZERO
	boat.angular_velocity = Vector3.ZERO
	await wait(1.0)
	p.global_position = boat.global_position + Vector3(0, 1.5, 0)
	p.enter_vehicle(boat)
	check("in the boat", p.state == "vehicle")
	var b0: Vector3 = boat.global_position
	var yaw0: float = atan2(boat.global_basis.z.x, boat.global_basis.z.z)
	p.touch_move = Vector2(0, 1)
	await wait(2.0)
	await shot("boat_ride")
	p.touch_move = Vector2(0.7, 1)
	await wait(3.0)
	var moved: float = Vector2(boat.global_position.x - b0.x, boat.global_position.z - b0.z).length()
	check("boat sails", moved > 15.0, "%.0f m" % moved)
	var yaw1: float = atan2(boat.global_basis.z.x, boat.global_basis.z.z)
	check("boat turns", absf(angle_difference(yaw1, yaw0)) > 0.3, "%.2f rad, spin %s" % [angle_difference(yaw1, yaw0), boat.angular_velocity])
	if world.is_deep(boat.global_position):
		check("still afloat", absf(boat.global_position.y - Island.WATER) < 0.8 and boat.global_basis.y.y > 0.8)
	else:
		check("ran up on the shore upright", boat.global_basis.y.y > 0.7)
	p.touch_move = Vector2.ZERO
	await shot("boat_turn")
	# Out at sea: no getting off into deep water.
	var deep := true
	for off in [boat.global_basis.x * 1.6, -boat.global_basis.x * 1.6, boat.global_basis.z * 3.0, -boat.global_basis.z * 3.0]:
		if not world.is_deep(boat.global_position + off): deep = false
	if deep:
		p.exit_vehicle()
		check("can't step off into deep water", p.state == "vehicle")
	p.exit_vehicle(true)
	check("forced off lands somewhere you can stand", p.state == "ground" and not world.is_deep(p.global_position))
	print("RIDE TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
