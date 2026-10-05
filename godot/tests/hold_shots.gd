extends Node
## In-match screenshots of the player holding weapons: ready, aiming, sprinting,
## reloading, crouched and a bot seen from the front.
## Run: godot --path godot res://tests/hold_shots.tscn -- --out=/dir

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
	Game.settings.quality = "high"
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
	world.hud.visible = false
	for b in world.bots: b.set_physics_process(false)
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[0].pos + Vector2(40, 0)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	p._land()
	p.give_weapon("akm", 30)
	p.give_weapon("m416", 30)
	p.ammo["556"] = 200
	p.yaw = 0.4
	p.pitch = -0.12
	await wait(1.5)
	await shot("hold_ready")
	p.aiming = true
	await wait(1.0)
	await shot("hold_aim")
	p.aiming = false
	p.sprinting = true
	p.touch_move = Vector2(0, 1)
	await wait(1.2)
	await shot("hold_sprint")
	p.touch_move = Vector2.ZERO
	p.sprinting = false
	p.slots[p.active].mag = 5
	p.start_reload()
	await wait(0.6)
	await shot("hold_reload")
	await wait(2.0)
	p.set_stance("crouch")
	p.aiming = true
	await wait(1.0)
	await shot("hold_crouch")
	p.aiming = false
	p.set_stance("crouch")
	# A bot facing the camera, aiming.
	var b: Bot = world.bots[0]
	b.state = "ground"
	b.visible = true
	b.weapon_id = "akm"
	b.model.set_weapon("akm")
	b.model.set_gear(2, 2, 2)
	var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	var bp := p.global_position + fwd * 4.0 + Vector3(cos(p.yaw), 0, -sin(p.yaw)) * 1.0
	b.global_position = Vector3(bp.x, world.ground_height(bp), bp.z)
	b.yaw = p.yaw + PI
	b.model.rotation.y = b.yaw
	b.target = p
	b.mode = "fight"
	b.set_physics_process(true)
	b.process_mode = Node.PROCESS_MODE_DISABLED
	b.process_mode = Node.PROCESS_MODE_INHERIT
	for f in 20:
		b.model.aiming = true
		b.model.set_pose("stand", 0.0, true, 0.05, f * 0.05)
		await get_tree().process_frame
	b.set_physics_process(false)
	for f in 10:
		b.model.aiming = true
		b.model.set_pose("stand", 0.0, true, 0.05, f * 0.05)
		await get_tree().process_frame
	await shot("hold_bot")
	tree.quit()
