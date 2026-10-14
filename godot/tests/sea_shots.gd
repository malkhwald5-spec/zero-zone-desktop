extends Node
## Screenshots of the sea: from the beach, from the parachute and from the plane's height.
## Run: godot --path godot res://tests/sea_shots.tscn -- --out=/dir [--quality=high]

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
		if a.begins_with("--quality="): Game.settings.quality = a.substr(10)
		if a == "--laptop": Game.settings.laptop = true
	Game.settings.controls = "kbm"
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
	# Walk from the centre outwards until open sea (several steps under water in a row).
	var isl = world.island
	var centre := Vector2(isl.size * 0.5, isl.size * 0.5)
	var dir := Vector2(-1, 0.25).normalized()
	var q := centre
	var wet := 0
	var shore := centre
	for k in 1200:
		q += dir * 6.0
		if isl.height_at(q.x, q.y) < -0.5:
			wet += 1
			if wet == 1: shore = q
			if wet >= 6: break
		else:
			wet = 0
	var stand := shore - dir * 14.0
	p.global_position = Vector3(stand.x, world.ground_height(Vector3(stand.x, 0, stand.y)) + 0.5, stand.y)
	p.yaw = atan2(-dir.x, -dir.y)
	p.pitch = -0.08
	for i in 30:
		if p.state == "ground": break
		await wait(0.1)
	await wait(1.5)
	await shot("sea_beach")
	p.yaw += 0.9
	await wait(0.6)
	await shot("sea_beach_side")
	# From the parachute, 150 m up over the shore, looking out to sea.
	p.jump_from_plane()
	p.open_chute()
	p.state = "chute"
	for alt in [[150.0, -0.35, "sea_chute"], [700.0, -0.3, "sea_high"], [700.0, -0.05, "sea_horizon"]]:
		var at := shore - dir * 120.0
		p.global_position = Vector3(at.x, alt[0], at.y)
		p.velocity = Vector3.ZERO
		p.yaw = atan2(-dir.x, -dir.y)
		p.pitch = alt[1]
		await wait(1.0)
		await shot(alt[2])
	print("SEA DONE")
	tree.quit()
