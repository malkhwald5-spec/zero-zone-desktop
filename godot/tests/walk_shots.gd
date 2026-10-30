extends Node
## The player on foot with a rifle, seen through the game's own camera and
## from the side: standing, walking, running, sprinting, aiming, crouched.
## For judging the walk and how the gun is held.
## Run: godot --path godot res://tests/walk_shots.tscn -- --out=/dir

var out := "user://"

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.controls = "touch"
	Game.settings.weather = "clear"
	Game.settings.mode = "solo"
	Game.spawn_island = false
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
	p.jump_from_plane()
	for b in world.bots: b.set_physics_process(false)
	# Open flat ground away from the houses.
	var t: Dictionary = world.island.towns[0]
	var at := Vector3(t.pos.x + float(t.r) + 40.0, 0, t.pos.y)
	at.y = world.ground_height(at)
	p.global_position = at + Vector3(0, 0.5, 0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	p._land()
	p.yaw = 0.0
	p.pitch = -0.12
	p.give_weapon("m416", 30)
	p.switch_slot(0)
	await wait(1.5)
	await shot("walk_0_stand")
	p.touch_move = Vector2(0, 0.45)
	await wait(1.4)
	await shot("walk_1_walk")
	p.touch_move = Vector2(0, 1)
	await wait(1.4)
	await shot("walk_2_run")
	p.sprinting = true
	await wait(1.2)
	await shot("walk_3_sprint")
	p.sprinting = false
	p.touch_move = Vector2(1, 0)
	await wait(1.2)
	await shot("walk_4_strafe")
	p.touch_move = Vector2.ZERO
	p.aiming = true
	await wait(1.0)
	await shot("walk_5_aim")
	p.aiming = false
	# From the side: a still camera, the player walking across it.
	var cam := Camera3D.new()
	world.add_child(cam)
	var base: Vector3 = p.global_position
	cam.global_position = base + Vector3(6.5, 1.3, 0)
	cam.look_at(base + Vector3(0, 1.0, 0))
	cam.current = true
	cam.fov = 45.0
	await wait(0.6)
	await shot("walk_6_side_stand")
	p.yaw = 0.0
	p.touch_move = Vector2(0, 1)
	for k in 3:
		await wait(0.33)
		cam.global_position = p.global_position + Vector3(6.5, 1.3, 0)
		cam.look_at(p.global_position + Vector3(0, 1.0, 0))
		await shot("walk_7_side_run_%d" % k)
	p.touch_move = Vector2.ZERO
	print("WALK SHOTS DONE")
	tree.quit()
