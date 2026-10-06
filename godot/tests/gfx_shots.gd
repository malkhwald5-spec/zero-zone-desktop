extends Node
## Fixed set of screenshots for judging graphics: lobby, town, forest, coast, air.
## Run: godot --path godot res://tests/gfx_shots.tscn -- --out=/dir [--quality=high]

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
	Game.settings.controls = "kbm"
	_run.call_deferred()

func _view(world, p: Player, pos: Vector3, yaw: float, pitch: float) -> void:
	p.global_position = pos
	p.yaw = yaw
	p.pitch = pitch
	p.velocity = Vector3.ZERO

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await wait(3.0)
	await shot("gfx_lobby")
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
	# From the parachute.
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[1].pos
	p.global_position = Vector3(c.x - 150, 260, c.y + 150)
	p.open_chute()
	p.state = "chute"
	p.yaw = atan2(150.0, -150.0)
	p.pitch = -0.45
	await wait(1.0)
	await shot("gfx_air")
	# Town street.
	p.global_position = Vector3(c.x + 30, world.ground_height(Vector3(c.x + 30, 0, c.y)) + 2.0, c.y)
	for i in 50:
		if p.state == "ground": break
		await wait(0.1)
	p.give_weapon("m416", 30)
	p.yaw = PI * 0.5
	p.pitch = -0.08
	await wait(1.5)
	await shot("gfx_town")
	# Close look at a house front (frames, brick, chimney, base course).
	var hb: Dictionary = world.island.buildings[0]
	for b in world.island.buildings:
		if not b.military:
			hb = b
			break
	var hp: Vector2 = hb.pos + Vector2(hb.size.x * 0.3, -hb.size.y * 0.5 - 9.0)
	p.global_position = Vector3(hp.x, world.ground_height(Vector3(hp.x, 0, hp.y)) + 0.3, hp.y)
	p.yaw = PI
	p.pitch = 0.12
	await wait(1.5)
	await shot("gfx_house")
	# Forest / hills: the densest tree spot.
	var best: Vector2 = c
	var best_n := 0
	for k in 60:
		var t: Dictionary = world.island.trees[randi() % world.island.trees.size()]
		var n := 0
		for t2 in world.island.trees:
			if t.pos.distance_to(t2.pos) < 40.0: n += 1
		if n > best_n:
			best_n = n
			best = t.pos
	var fp := best + Vector2(30, 30)
	p.global_position = Vector3(fp.x, world.ground_height(Vector3(fp.x, 0, fp.y)) + 0.5, fp.y)
	p.yaw = atan2(-(best - fp).x, -(best - fp).y)
	p.pitch = -0.02
	await wait(1.5)
	await shot("gfx_forest")
	# Pine wood: the densest pine spot, seen from just outside it.
	var pbest: Vector2 = c
	var pbest_n := 0
	for k in 80:
		var t: Dictionary = world.island.trees[randi() % world.island.trees.size()]
		if not t.pine: continue
		var n := 0
		for t2 in world.island.trees:
			if t2.pine and t.pos.distance_to(t2.pos) < 30.0: n += 1
		if n > pbest_n:
			pbest_n = n
			pbest = t.pos
	var pp := pbest + Vector2(22, -14)
	p.global_position = Vector3(pp.x, world.ground_height(Vector3(pp.x, 0, pp.y)) + 0.5, pp.y)
	p.yaw = atan2(-(pbest - pp).x, -(pbest - pp).y)
	p.pitch = 0.05
	await wait(1.5)
	await shot("gfx_pines")
	# Coast: walk from the island centre outwards until the ground reaches the sea.
	var centre := Vector2(world.island.size * 0.5, world.island.size * 0.45)
	var dir := Vector2(1, 0.3).normalized()
	var q := centre
	for k in 400:
		q += dir * 8.0
		if world.island.height_at(q.x, q.y) < 1.5: break
	var shore := q - dir * 25.0
	p.global_position = Vector3(shore.x, world.ground_height(Vector3(shore.x, 0, shore.y)) + 0.5, shore.y)
	p.yaw = atan2(-dir.x, -dir.y)
	p.pitch = -0.05
	await wait(1.5)
	await shot("gfx_coast")
	print("GFX DONE")
	tree.quit()
