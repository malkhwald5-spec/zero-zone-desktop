extends Node
## Third-person view standing on a road, looking along it (as in the PUBG
## screenshot the look is matched to), in the plains, the north and the
## desert; HUD on. Run with --out=/dir.

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
	Game.settings.quality = "high"
	Game.settings.weather = "clear"
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
	for b in world.bots: b.set_physics_process(false)
	var p: Player = world.player
	p.health = 1e9
	var island: Island = world.island
	p.jump_from_plane()
	p.give_weapon("m416", 30)
	for reg in ["plains", "nordic", "desert"]:
		var spot := Vector2.INF
		var dir := Vector2.ZERO
		for rd in island.roads:
			var a: Vector2 = rd.a
			var b: Vector2 = rd.b
			if a.distance_to(b) < 300.0: continue
			for t in [0.3, 0.5, 0.7]:
				var c: Vector2 = a.lerp(b, t)
				if island.region_at(c.x, c.y) == reg and island.height_at(c.x, c.y) > Island.WATER + 1.0:
					spot = c
					dir = (b - a).normalized()
					break
			if spot != Vector2.INF: break
		if spot == Vector2.INF: continue
		p.global_position = Vector3(spot.x, island.height_at(spot.x, spot.y) + 0.3, spot.y)
		p._land()
		p.yaw = atan2(-dir.x, -dir.y)
		p.pitch = -0.05
		await wait(2.5)
		await shot("look_" + reg)
	tree.quit()
