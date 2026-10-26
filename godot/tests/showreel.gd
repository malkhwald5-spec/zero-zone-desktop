extends Node
## A short walk-through of a match for a demo video, run under Godot's movie
## writer (fixed frame rate, so it plays smoothly however slow the render):
## godot --path godot --write-movie reel.avi --fixed-fps 30 res://tests/showreel.tscn

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	Game.settings.controls = "touch"
	Game.settings.mode = "solo"
	Game.training = false
	Game.spawn_island = false
	Game.wallet.login_date = Game.today()
	_run.call_deferred()

var _p: Player = null

## The hero of the video doesn't die in it.
func _process(_d: float) -> void:
	if _p and is_instance_valid(_p) and _p.state != "dead": _p.health = 100.0

## The way along the ground with the most open space ahead (no running into walls).
func open_yaw(world: Node, p: Player) -> float:
	var best := p.yaw
	var best_d := -1.0
	var space := p.get_world_3d().direct_space_state
	for i in 24:
		var y := p.yaw + TAU * float(i) / 24.0
		var d := Vector3(-sin(y), 0, -cos(y))
		var from := p.global_position + Vector3(0, 1.0, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + d * 60.0, 1, [p.get_rid()])
		var h := space.intersect_ray(q)
		var free: float = 60.0 if h.is_empty() else from.distance_to(h.position)
		if free > best_d:
			best_d = free
			best = y
	return best

## Turns the view smoothly by `by` radians over `sec` seconds.
func pan(p: Player, by: float, sec: float, pitch_to := INF) -> void:
	var y0 := p.yaw
	var p0 := p.pitch
	var t := 0.0
	while t < sec:
		t += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, minf(t / sec, 1.0))
		p.yaw = y0 + by * k
		if pitch_to != INF: p.pitch = lerpf(p0, pitch_to, k)
		await get_tree().process_frame

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	# The lobby first.
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await wait(5.0)
	print("REEL lobby done f=", Engine.get_process_frames())
	# Press start, as a player would: matchmaking, the loading screen, the match.
	tree.current_scene._start()
	var world = null
	for i in 3000:
		world = tree.current_scene
		if world and world.get("ready_done"): break
		await wait(0.1)
	print("REEL world ready f=", Engine.get_process_frames())
	var p: Player = world.player
	_p = p
	# A look round the spawn island, then the countdown runs out and all board.
	if world.spawn != null:
		await pan(p, 1.2, 4.0)
		world.spawn.left = 0.5
		for i in 300:
			if world.spawn == null and p.state == "plane": break
			await wait(0.1)
	# Riding the plane, then out.
	await pan(p, 0.8, 3.0)
	p.jump_from_plane()
	await wait(2.5)
	p.dive = 1.0
	await pan(p, -0.6, 2.0)
	p.global_position.y = minf(p.global_position.y, world.ground_height(p.global_position) + 260.0)
	p.open_chute()
	await pan(p, 0.5, 3.0)
	# Down near a town.
	var c: Vector2 = world.island.towns[2].pos + Vector2(40, 30)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 40.0, c.y)
	await wait(2.5)
	if p.state != "ground":
		p.global_position.y = world.ground_height(p.global_position) + 1.0
		p._land()
	await wait(1.0)
	p.give_weapon("m416", 30)
	p.ammo["556"] = 240
	p.equip("vest", 2, 200.0)
	p.equip("helmet", 2, 150.0)
	p.equip("pack", 2, 0.0)
	p.pitch = -0.1
	await wait(0.5)
	await pan(p, wrapf(open_yaw(world, p) - p.yaw, -PI, PI), 1.0)
	await wait(0.3)
	# Run down the street.
	p.touch_move = Vector2(0, 1)
	p.sprinting = true
	await pan(p, 0.25, 3.0)
	p.sprinting = false
	p.touch_move = Vector2(1, 0.3)
	await wait(1.5)
	p.touch_move = Vector2.ZERO
	await wait(0.4)
	await pan(p, wrapf(open_yaw(world, p) - p.yaw, -PI, PI), 0.8)
	await wait(0.4)
	# A target in front: aim and fire.
	var dummy: Bot = null
	for b in world.bots:
		if not b.dead and b.state == "ground":
			dummy = b
			break
	if dummy == null: dummy = world.bots[0]
	dummy.set_physics_process(false)
	dummy.state = "ground"
	dummy.visible = true
	dummy.shape.disabled = false
	var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	var spot := p.global_position + fwd * 22.0
	dummy.global_position = Vector3(spot.x, world.ground_height(spot) + 0.05, spot.z)
	dummy.health = 400.0
	await wait(0.3)
	for k in 3:
		var to_d: Vector3 = dummy.global_position + Vector3(0, 1.2, 0) - p.camera.global_position
		p.yaw = atan2(-to_d.x, -to_d.z)
		p.pitch = atan2(to_d.y, Vector2(to_d.x, to_d.z).length())
		await wait(0.15)
	p.action("aim", true)
	await wait(0.8)
	p.action("fire", true)
	await wait(1.6)
	p.action("fire", false)
	await wait(0.5)
	p.action("aim", false)
	dummy.health = 1.0
	p.action("fire", true)
	await wait(0.4)
	p.action("fire", false)
	await wait(1.2)
	# Free look round while standing.
	p.action("freelook", true)
	for k in 60:
		p.add_look(-14.0, 0.0)
		await tree.process_frame
	await wait(0.5)
	p.action("freelook", false)
	await wait(1.0)
	# Gunfire and steps nearby: the markers round the crosshair.
	var rgt := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	for k in 6:
		world.notify_shot(p.global_position + rgt * 70.0 + fwd * 40.0, world.bots[1])
		world.footstep(p.global_position - rgt * 10.0, false, 0.9, world.bots[2])
		await wait(0.3)
	# A red zone right here: shells landing round us.
	var ev: MatchEvents = world.events
	if ev:
		world.zone.phase = 1
		ev.start_red()
		# Close enough to watch, far enough to live.
		var f2 := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		ev.red_center = Vector2(p.global_position.x, p.global_position.z) + Vector2(f2.x, f2.z) * 60.0
		ev.red_radius = 28.0
		await wait(2.5)
		ev.red_t = MatchEvents.RED_TIME
		for k in 10:
			ev._shell()
			await wait(0.35)
		await wait(1.0)
	# The map.
	world.hud.toggle_map()
	await wait(2.5)
	world.hud.toggle_map()
	# Into a car and away.
	var car: Vehicle = world.nearest_vehicle(p.global_position, 400.0)
	if car:
		p.global_position = car.global_position + car.global_basis.x * 2.5 + Vector3(0, 0.5, 0)
		await wait(0.4)
		p.enter_vehicle(car)
		await wait(1.0)
		p.touch_move = Vector2(0.0, 1.0)
		await wait(2.5)
		p.touch_move = Vector2(0.35, 1.0)
		await wait(2.5)
		p.touch_move = Vector2.ZERO
		await wait(1.0)
	print("REEL DONE state=", p.state)
	tree.quit()
