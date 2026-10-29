extends Node
## The parachute from the opening to the landing, filmed by a following
## camera: the canopy filling, the body swinging under it in the turns and the
## wind, the flare and the touch-down (soft), then a second jump diving in
## with W held (fast: the landing roll). Prints the touch-down speeds.
## Film: godot --path godot --write-movie chute.avi --fixed-fps 30 res://tests/chute_demo.tscn

var world: Node
var p: Player
var cam: Camera3D
var failed := 0
var _upd: Callable = Callable()
var _t0 := 0.0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok: failed += 1

func _ready() -> void:
	Game.settings.controls = "touch"
	Game.settings.weather = "clear"
	Game.settings.mode = "solo"
	Game.spawn_island = false
	Game.training = false
	_run.call_deferred()

func _process(_d: float) -> void:
	if _upd.is_valid() and cam: _upd.call(Time.get_ticks_msec() / 1000.0 - _t0)
	if p and is_instance_valid(p): p.health = 100.0

func follow(side: float, back: float, up: float) -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	_upd = func(_t: float):
		var b: Vector3 = p.get_global_transform_interpolated().origin
		var f := Vector3(-sin(p.chute_heading), 0, -cos(p.chute_heading)) if p.state == "chute" else Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		var r := f.cross(Vector3.UP)
		var want := b - f * back + r * side + Vector3(0, up, 0)
		want.y = maxf(want.y, world.ground_height(want) + 1.4)     # never in the ground or the grass
		cam.global_position = cam.global_position.lerp(want, 0.15) if cam.global_position.distance_to(want) < 30.0 else want
		cam.look_at(b + Vector3(0, 1.9, 0), Vector3.UP)

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	for i in 3000:
		world = tree.current_scene
		if world and world.get("ready_done"): break
		await wait(0.1)
	p = world.player
	world.hud.visible = false
	cam = Camera3D.new()
	cam.fov = 66.0
	world.add_child(cam)
	cam.current = true
	for k in 2:
		var dive := k == 1
		# Over open land, 260 m up.
		# The flattest open ground just outside the biggest town.
		var big: Dictionary = world.island.towns[0]
		for tw in world.island.towns:
			if tw.kind != "fort" and float(tw.r) > float(big.r): big = tw
		var c := Vector3(big.pos.x, 0, big.pos.y)
		var best := INF
		for i in 48:
			var q := Vector3(big.pos.x, 0, big.pos.y) + Vector3(float(big.r) + 60.0 + (i % 3) * 40.0, 0, 0).rotated(Vector3.UP, i * TAU / 16.0)
			if world.island.is_deep(q.x, q.z): continue
			var h0: float = world.ground_height(q)
			var bump := 0.0
			for d in [Vector3(25, 0, 0), Vector3(-25, 0, 0), Vector3(0, 0, 25), Vector3(0, 0, -25), Vector3(0, 0, -60)]:
				bump += absf(world.ground_height(q + d) - h0)
			if bump < best:
				best = bump
				c = q
		c += Vector3(0, 0, 70.0 * k)
		p.jump_from_plane()
		p.global_position = Vector3(c.x, world.ground_height(c) + (260.0 if dive else 640.0), c.z)
		p.velocity = Vector3(0, -40, 0)
		p.yaw = 0.0
		cam.global_position = p.global_position + Vector3(6, 2, 8)
		follow(3.5, 6.5, 0.6)
		print("DEMO %s jump" % ("dive" if dive else "soft"))
		if not dive:
			# Freefall first: belly down, then a head-first dive (arms back),
			# rolling into turns both ways, and sitting up to slow down.
			follow(0.0, 7.5, 2.2)
			await wait(1.5)
			p.pitch = -0.9
			p.touch_move = Vector2(0, 1)
			print("DEMO freefall dive")
			await wait(2.2)
			p.pitch = -0.3
			p.touch_move = Vector2(-1, 0.4)
			await wait(1.4)
			p.touch_move = Vector2(1, 0.4)
			await wait(1.4)
			p.touch_move = Vector2(0, -1)
			print("DEMO freefall brake")
			await wait(1.0)
			p.touch_move = Vector2.ZERO
			p.global_position.y = maxf(p.global_position.y, world.ground_height(p.global_position) + 220.0)
			follow(3.5, 6.5, 0.6)
		await wait(1.2)
		p.open_chute()
		print("DEMO open")
		await wait(3.0)
		if not dive:
			# Turns: left, right, then straight with the wind.
			follow(-4.0, 5.5, 0.4)
			p.touch_move = Vector2(-1, 0)
			await wait(3.0)
			p.touch_move = Vector2(1, 0)
			await wait(3.0)
			p.touch_move = Vector2.ZERO
			await wait(1.5)
		# Down to the last 40 m, then the camera low and to the side for the touch-down.
		p.global_position.y = world.ground_height(p.global_position) + 40.0
		p.touch_move = Vector2(0, 1) if dive else Vector2.ZERO
		follow(6.5, 3.5, 0.2)
		var touched := false
		for i in 1500:
			await get_tree().physics_frame
			if p.state == "ground":
				touched = true
				break
		print("DEMO touchdown vy=%.2f h=%.2f flare=%.2f anim=%s" % [p._touch_vel.y, Vector2(p._touch_vel.x, p._touch_vel.z).length(), p.chute_flare, p.model._anim])
		check(touched, "landed (%s)" % ("dive" if dive else "soft"))
		if dive: check(p._touch_vel.y < -6.5, "diving in comes down hard  vy=%.2f" % p._touch_vel.y)
		else: check(p._touch_vel.y > -5.0, "the flare makes a soft touch-down  vy=%.2f" % p._touch_vel.y)
		_upd = func(_t: float):
			var b: Vector3 = p.get_global_transform_interpolated().origin
			cam.look_at(b + Vector3(0, 1.0, 0), Vector3.UP)
		p.touch_move = Vector2.ZERO
		await wait(2.6)
	print("CHUTE DEMO %s (%d failed)" % ["OK" if failed == 0 else "FAILED", failed])
	tree.quit(failed)
