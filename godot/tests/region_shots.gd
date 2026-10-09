extends Node
## Pictures of the big map: the whole map, then a town in each region from
## the ground and from above. Run with --out=/dir.

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
	await wait(3.0)
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(9000, 0, 9000)
	var p: Player = world.player
	p.jump_from_plane()
	world.plane_active = false
	world.hud.toggle_map()
	await wait(0.6)
	await shot("map_full")
	world.hud.toggle_map()
	var counts := {}
	for t in world.island.towns:
		var reg: String = t.get("region", "plains")
		counts[reg] = counts.get(reg, 0) + 1
	print("REGION towns ", counts)
	var extras_only := OS.get_cmdline_user_args().has("--extras")
	for reg in ([] if extras_only else ["plains", "nordic", "jungle", "desert", "tropic"]):
		var town = null
		for t in world.island.towns:
			if t.get("region", "") == reg and t.get("kind", "town") == "town":
				town = t
				break
		if town == null:
			print("REGION none in ", reg)
			continue
		var c: Vector2 = town.pos + Vector2(town.r + 30.0, 10.0)
		p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.5, c.y)
		p.velocity = Vector3.ZERO
		p.yaw = PI * 0.5
		p.pitch = -0.08
		await wait(2.5)
		await shot("region_%s" % reg)
		# From a hill above.
		p.global_position = Vector3(c.x + 120.0, world.ground_height(Vector3(c.x + 120.0, 0, c.y)) + 60.0, c.y)
		p.state = "chute"
		p.pitch = -0.35
		await wait(1.2)
		await shot("region_%s_air" % reg)
		p.state = "ground"
	# A windmill among the lupine fields, and a jungle channel.
	for st in world.island.structures:
		if st.kind == "windmill":
			var w: Vector2 = st.pos
			var q := w + Vector2(-26.0, 18.0)
			p.global_position = Vector3(q.x, world.ground_height(Vector3(q.x, 0, q.y)) + 1.5, q.y)
			p.velocity = Vector3.ZERO
			p.yaw = atan2(-(w.x - q.x), -(w.y - q.y))
			p.pitch = 0.12
			await wait(2.5)
			await shot("windmill")
			break
	var isl = world.island
	for k in 4000:
		var q := Vector2(randf_range(400, isl.size * 0.5), randf_range(isl.size * 0.5, isl.size * 0.85))
		if isl.region_at(q.x, q.y) != "jungle" or isl.height_at(q.x, q.y) > -2.0: continue
		var land := q + Vector2(60, 0)
		if not isl.is_land(land.x, land.y): continue
		p.global_position = Vector3(land.x, world.ground_height(Vector3(land.x, 0, land.y)) + 1.5, land.y)
		p.velocity = Vector3.ZERO
		p.yaw = PI * 0.5
		p.pitch = -0.05
		await wait(2.5)
		await shot("jungle_channel")
		break
	print("REGION SHOTS DONE")
	tree.quit()
