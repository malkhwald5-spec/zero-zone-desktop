extends Node
## How the rifle is held standing still (across the body) and walking off,
## from the front, the side and the game camera.
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
		if a.begins_with("--skin="): Game.profile.gun_skin = a.substr(7)
	Game.settings.controls = "touch"
	Game.settings.weather = "clear"
	Game.settings.mode = "solo"
	Game.settings.map = "dunes"
	Game.settings.lite = false
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
	await wait(2.0)
	p.global_position = Vector3(at.x, world.ground_height(at) + 0.2, at.z)
	p.velocity = Vector3.ZERO
	await wait(1.0)
	await shot("hold_0_game")
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 40.0
	var base: Vector3 = p.global_position
	var fwd: Vector3 = -p.global_basis.z
	var right: Vector3 = p.global_basis.x
	cam.global_position = base + fwd * 3.6 + Vector3(0, 1.2, 0)
	cam.look_at(base + Vector3(0, 1.0, 0))
	cam.current = true
	world.hud.visible = false
	await wait(0.5)
	await shot("hold_1_front")
	cam.global_position = base + fwd * 2.4 + right * 2.4 + Vector3(0, 1.3, 0)
	cam.look_at(base + Vector3(0, 1.05, 0))
	await wait(0.3)
	await shot("hold_2_front34")
	cam.global_position = base + right * 3.4 + Vector3(0, 1.2, 0)
	cam.look_at(base + Vector3(0, 1.0, 0))
	await wait(0.3)
	await shot("hold_3_side")
	cam.current = false
	world.hud.visible = true
	p.touch_move = Vector2(0, 1)
	await wait(1.4)
	await shot("hold_4_run_game")
	tree.quit()
