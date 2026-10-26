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
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.3)
	var world = tree.current_scene
	for i in 2000:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	p.health = 1e9
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
	await wait(1.0)
	# Run down the street.
	p.touch_move = Vector2(0, 1)
	p.sprinting = true
	await pan(p, 0.7, 3.0)
	p.sprinting = false
	p.touch_move = Vector2(1, 0.3)
	await wait(1.5)
	p.touch_move = Vector2.ZERO
	await wait(0.6)
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
		ev.red_center = Vector2(p.global_position.x, p.global_position.z) + Vector2(fwd.x, fwd.z) * 40.0
		ev.red_radius = 45.0
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
	print("REEL DONE")
	tree.quit()
