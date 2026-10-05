extends Node
## Checks the cars and the bigger map (run headless).

var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

var _car: Vehicle
var _p: Player
var _world: Node

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if _car:
		print("     car pos=%s up=%.2f speed=%.1f hp=%.0f dead=%s driver=%s sleeping=%s ground=%.1f | player %s at %s" % [
			_car.global_position.snapped(Vector3(0.1, 0.1, 0.1)), _car.global_basis.y.y, _car.speed() * 3.6, _car.health, _car.dead,
			_car.driver != null, _car.sleeping, _world.ground_height(_car.global_position), _p.state, _p.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
	if not ok: fails += 1

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	Game.settings.controls = "touch"     # drive through touch_move in this test
	var t0 := Time.get_ticks_msec()
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	var isl: Island = world.island
	check("map is 4 km", is_equal_approx(isl.size, 4096.0))
	check("more towns", isl.towns.size() >= 14, "towns=%d buildings=%d trees=%d" % [isl.towns.size(), isl.buildings.size(), isl.trees.size()])
	print("INFO load %d ms, pickups %d" % [Time.get_ticks_msec() - t0, world.pickups.size()])
	for b in world.bots: b.set_physics_process(false)
	check("cars parked on roads", world.vehicles.size() >= 12, "cars=%d" % world.vehicles.size())
	var p: Player = world.player
	p.jump_from_plane()
	# Pick a car on flat ground.
	var car: Vehicle = world.vehicles[0]
	# Start on the longest dry road, facing along it (a random spot could face the sea).
	var best_rd: Dictionary = isl.roads[0]
	var best_len := 0.0
	for rd in isl.roads:
		var dry := true
		for k in 20:
			var q: Vector2 = rd.a.lerp(rd.b, k / 19.0)
			if isl.height_at(q.x, q.y) < 1.0: dry = false
		var ln: float = rd.a.distance_to(rd.b)
		if dry and ln > best_len:
			best_len = ln
			best_rd = rd
	var sdir: Vector2 = (best_rd.b - best_rd.a).normalized()
	var sp0: Vector2 = best_rd.a.lerp(best_rd.b, 0.15)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(sdir.x, sdir.y)), Vector3(sp0.x, isl.height_at(sp0.x, sp0.y) + 1.0, sp0.y))
	await wait(1.0)
	_car = car
	_p = p
	_world = world
	p.global_position = car.global_position + car.global_basis.x * 2.5 + Vector3(0, 1.0, 0)
	for i in 40:
		if p.state == "ground": break
		await wait(0.1)
	p.global_position = car.global_position + car.global_basis.x * 2.2
	await wait(0.5)
	var settled_y: float = car.global_position.y - world.ground_height(car.global_position)
	check("car rests on its wheels", settled_y > -0.3 and settled_y < 1.5 and car.global_basis.y.y > 0.9, "height=%.2f up=%.2f" % [settled_y, car.global_basis.y.y])
	p.interact()
	check("get in with F", p.state == "vehicle" and car.driver == p)
	var start := car.global_position
	p.touch_move = Vector2(0, 1)
	await wait(4.0)
	var moved := car.global_position.distance_to(start)
	check("drives forward", moved > 20.0 and car.speed() > 8.0, "moved=%.1f m speed=%.1f km/h" % [moved, car.speed() * 3.6])
	var yaw0 := car.rotation.y
	p.touch_move = Vector2(1, 1)
	await wait(1.5)
	check("steers", absf(angle_difference(yaw0, car.rotation.y)) > 0.3, "turned %.2f rad" % absf(angle_difference(yaw0, car.rotation.y)))
	var before_brake := car.speed()
	p.touch_move = Vector2(0, -1)
	var slowest := 999.0
	for i in 80:
		await wait(0.05)
		slowest = minf(slowest, absf(car.speed()))
	check("brakes", slowest < 2.0, "from %.0f km/h, slowest %.1f km/h" % [before_brake * 3.6, slowest * 3.6])
	p.touch_move = Vector2(0, -1)
	for i in 60:
		await wait(0.1)
		if absf(car.speed()) < 0.5: break
	p.touch_move = Vector2.ZERO
	await wait(0.5)
	# Run a bot over: get up to speed, then put the bot 12 m ahead on the car's path.
	# (Up to 3 tries: on a random map the car may hit a tree or a wall first.)
	var bot: Bot = world.bots[0]
	bot.state = "ground"
	bot.visible = true
	var min_d := 999.0
	var top_speed := 0.0
	for attempt in 3:
		# Straight run on open ground away from obstacles: reset the car onto a road.
		var rd: Dictionary = best_rd
		var rdir: Vector2 = (rd.b - rd.a).normalized()
		var rp: Vector2 = rd.a.lerp(rd.b, 0.35 + attempt * 0.15)
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.global_transform = Transform3D(Basis(Vector3.UP, atan2(rdir.x, rdir.y)), Vector3(rp.x, isl.height_at(rp.x, rp.y) + 1.0, rp.y))
		await wait(0.6)
		p.touch_move = Vector2(0, 1)
		await wait(2.5)
		var dir: Vector3 = car.linear_velocity
		dir.y = 0.0
		var ahead: Vector3 = car.global_position + dir.normalized() * 12.0
		bot.global_position = Vector3(ahead.x, world.ground_height(ahead) + 0.2, ahead.z)
		bot._land()
		bot.health = 100.0
		min_d = 999.0
		top_speed = 0.0
		for i in 30:
			await wait(0.05)
			min_d = minf(min_d, car.global_position.distance_to(bot.global_position))
			top_speed = maxf(top_speed, car.speed())
			if bot.health < 100.0: break
		if bot.health < 100.0: break
	check("running someone over hurts", bot.health < 100.0, "bot hp=%.0f closest=%.1f m top=%.0f km/h" % [bot.health, min_d, top_speed * 3.6])
	# Stop before getting out.
	p.touch_move = Vector2(0, -1)
	for i in 300:
		await wait(0.02)
		if absf(car.speed()) < 2.0: break
	p.touch_move = Vector2.ZERO
	await wait(2.0)
	p.interact()
	await wait(0.3)
	var out_d := p.global_position.distance_to(car.global_position)
	check("get out next to the car", p.state == "ground" and out_d > 1.0 and out_d < 4.0 and car.driver == null, "d=%.1f" % out_d)
	# Destroy a car with someone inside.
	p.health = 100.0
	p.interact()
	check("back in", p.state == "vehicle")
	car.take_damage(Vehicle.MAX_HEALTH + 10.0, bot)
	await wait(0.3)
	check("car explodes and throws the driver out", car.dead and p.state != "vehicle" and p.health < 100.0, "state=%s hp=%.0f" % [p.state, p.health])
	print("VEHICLE TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
