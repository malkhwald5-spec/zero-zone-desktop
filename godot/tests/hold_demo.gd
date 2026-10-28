extends Node
## The rifle and the gear in motion, filmed from the side and behind: walking,
## quick turns (the gun lags and settles), a sprint and a sudden stop (the
## gun and the backpack swing on), standing (breathing).
## Film: godot --path godot --write-movie hold.avi --fixed-fps 30 res://tests/hold_demo.tscn

var world: Node
var p: Player
var cam: Camera3D
var _upd: Callable = Callable()

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	Game.settings.controls = "touch"
	Game.settings.weather = "clear"
	Game.settings.mode = "solo"
	Game.spawn_island = false
	Game.training = false
	_run.call_deferred()

func _process(_d: float) -> void:
	if _upd.is_valid() and cam: _upd.call()
	if p and is_instance_valid(p): p.health = 100.0

## The camera at `off` from her (in her facing frame), looking at her chest.
func follow(off: Vector3) -> void:
	_upd = func():
		var b: Vector3 = p.get_global_transform_interpolated().origin
		var f := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		var r := f.cross(Vector3.UP)
		var want := b + r * off.x + Vector3(0, off.y, 0) - f * off.z
		cam.global_position = cam.global_position.lerp(want, 0.08) if cam.global_position.distance_to(want) < 6.0 else want
		cam.look_at(b + Vector3(0, 1.2, 0), Vector3.UP)

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
	for b in world.bots: b.set_physics_process(false)
	cam = Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.current = true
	# Flat open ground by the biggest town.
	var big: Dictionary = world.island.towns[0]
	for tw in world.island.towns:
		if tw.kind != "fort" and float(tw.r) > float(big.r): big = tw
	var q := Vector3(big.pos.x + float(big.r) + 50.0, 0, big.pos.y)
	p.global_position = Vector3(q.x, world.ground_height(q) + 1.0, q.z)
	p._land()
	p.give_weapon("m416", 30)
	p.equip("vest", 3, 200.0)
	p.equip("helmet", 3, 150.0)
	p.equip("pack", 3, 0.0)
	p.yaw = 0.0
	await wait(1.5)
	# Standing, from the front quarter.
	follow(Vector3(1.8, 1.5, 2.4))
	await wait(2.5)
	# Walking, from the side.
	follow(Vector3(3.0, 1.3, 0.3))
	p.touch_move = Vector2(0, 0.6)
	await wait(3.0)
	# Quick turns while walking: the gun lags and catches up.
	for k in 4:
		var y0 := p.yaw
		var to := y0 + (1.2 if k % 2 == 0 else -1.2)
		for i in 10:
			p.yaw = lerpf(y0, to, (i + 1) / 10.0)
			await get_tree().process_frame
		await wait(0.6)
	# Sprint, from behind: the backpack bounces; then a sudden stop.
	follow(Vector3(0.9, 1.6, -3.2))
	p.touch_move = Vector2(0, 1)
	p.sprinting = true
	await wait(3.0)
	follow(Vector3(3.2, 1.3, 0.0))
	await wait(0.8)
	p.touch_move = Vector2.ZERO
	p.sprinting = false
	await wait(2.0)
	# Crouched, then standing to aim.
	p.set_stance("crouch")
	await wait(1.5)
	p.set_stance("stand")
	follow(Vector3(1.4, 1.6, -2.0))
	p.action("aim", true)
	await wait(1.6)
	p.action("fire", true)
	await wait(0.6)
	p.action("fire", false)
	await wait(1.2)
	print("HOLD DEMO done")
	tree.quit()
