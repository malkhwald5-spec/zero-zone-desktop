extends Node
## The jump as the player sees it: the game's own camera and HUD, from the
## plane, through the freefall (glide, dive, turns), the parachute, to the
## landing. For judging the feel against the mobile battle royales.
## Film: godot --path godot --write-movie jump.avi --fixed-fps 30 res://tests/jump_film.tscn

var world: Node
var p: Player

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
	if p and is_instance_valid(p): p.health = 100.0

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
	# Skip most of the flight: on to the part over land.
	for i in 400:
		if world.plane_over_land(): break
		world.plane_t += 0.002
		await get_tree().process_frame
	await wait(2.0)
	print("FILM jump")
	p.interact()
	await wait(2.5)
	print("FILM glide")
	p.pitch = -0.35
	p.touch_move = Vector2(0, 1)
	await wait(3.0)
	print("FILM dive")
	p.pitch = -1.1
	await wait(3.0)
	p.pitch = -0.4
	p.touch_move = Vector2(-0.8, 0.6)
	await wait(1.5)
	p.touch_move = Vector2(0.8, 0.6)
	await wait(1.5)
	p.touch_move = Vector2(0, 1)
	p.pitch = -0.9
	for i in 600:
		if p.state != "fall": break
		await get_tree().physics_frame
	print("FILM chute alt=%.0f" % (p.global_position.y - world.ground_height(p.global_position)))
	p.touch_move = Vector2.ZERO
	p.pitch = -0.25
	await wait(4.0)
	p.touch_move = Vector2(-1, 0.3)
	await wait(2.5)
	p.touch_move = Vector2(0, 1)
	for i in 3000:
		if p.state == "ground": break
		await get_tree().physics_frame
	print("FILM landed")
	p.touch_move = Vector2.ZERO
	await wait(3.0)
	print("JUMP FILM DONE")
	tree.quit()
