extends Node
## Nature close up in each region: a boulder (photo rock) with the ground
## clutter around it (wild grasses, weeds, fallen branches, stones).
## Run with --out=/dir.

var out := "user://"

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
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
	for i in 1200:
		if world.ready_done: break
		await wait(0.1)
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(9000, 0, 9000)
	var p: Player = world.player
	p.health = 1e9
	p.jump_from_plane()
	world.plane_active = false
	var isl = world.island
	print("NATURE rocks=", isl.rocks.size(), " clutter layers=", world.builder.clutter.size())
	for reg in ["plains", "nordic", "jungle", "desert", "tropic"]:
		var rock = null
		for r in isl.rocks:
			if isl.region_at(r.pos.x, r.pos.y) == reg and r.r > 1.6 and isl.height_at(r.pos.x, r.pos.y) > 3.0:
				rock = r
				break
		if rock == null:
			print("NATURE no rock in ", reg)
			continue
		var c: Vector2 = rock.pos + Vector2(rock.r * 2.2 + 4.0, 0)
		p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
		p.velocity = Vector3.ZERO
		var to: Vector2 = rock.pos - c
		p.yaw = atan2(-to.x, -to.y) - 0.35
		p.pitch = -0.12
		await wait(2.5)
		world.hud.visible = false
		await shot("nature_" + reg)
		world.hud.visible = true
	# A desert cliff (mesa side) from 45 m.
	for k in 20000:
		var q := Vector2(randf_range(300, isl.size - 300), randf_range(300, isl.size - 300))
		if isl.region_at(q.x, q.y) != "desert": continue
		var g: float = absf(isl.height_at(q.x + 2, q.y) - isl.height_at(q.x - 2, q.y)) + absf(isl.height_at(q.x, q.y + 2) - isl.height_at(q.x, q.y - 2))
		if g < 3.0: continue
		var dirv := Vector2(isl.height_at(q.x - 2, q.y) - isl.height_at(q.x + 2, q.y), isl.height_at(q.x, q.y - 2) - isl.height_at(q.x, q.y + 2)).normalized()
		var c := q + dirv * 45.0
		if isl.height_at(c.x, c.y) > isl.height_at(q.x, q.y) - 3.0: continue
		p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
		p.velocity = Vector3.ZERO
		p.yaw = atan2(dirv.x, dirv.y)
		p.pitch = 0.12
		await wait(2.5)
		world.hud.visible = false
		await shot("nature_cliff")
		break
	tree.quit()
