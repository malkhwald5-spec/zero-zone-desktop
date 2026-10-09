extends Node3D
## Pictures of the loot as it lies on the ground: every gun, ammo, meds,
## attachments, grenades and gear (close up), then a real match spot.
## Run: godot --path godot res://tests/loot_shots.tscn -- --out=/some/dir

var out := "user://"

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	_run.call_deferred()

func _items() -> Array:
	var guns := []
	for id in Game.WEAPONS: guns.append({"kind": "weapon", "id": id})
	var rest := []
	for t in ["9mm", "556", "762", "12g", "300", "bolt"]: rest.append({"kind": "ammo", "type": t})
	for h in Items.HEAL_ORDER: rest.append({"kind": "heal", "id": h})
	for t in Items.THROW_ORDER: rest.append({"kind": "throw", "id": t})
	var att := []
	for a in Items.ATTACH: att.append({"kind": "attach", "id": a})
	var gear := []
	for g in ["helmet", "vest", "pack"]:
		for l in [1, 2, 3]: gear.append({"kind": "gear", "gear": g, "lvl": l})
	return [guns, rest, att, gear]

func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.75)
	env.environment.ambient_light_color = Color(0.75, 0.77, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.95, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.46, 0.38)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	var sets := _items()
	var cam := Camera3D.new()
	cam.fov = 50
	add_child(cam)
	cam.current = true
	for si in sets.size():
		var holder := Node3D.new()
		add_child(holder)
		var items: Array = sets[si]
		var cols := 5 if si == 0 else 6
		var sp := 1.15 if si == 0 else 0.42
		for i in items.size():
			var mi := MeshInstance3D.new()
			mi.mesh = LootModels.mesh(items[i])
			holder.add_child(mi)
			mi.position = Vector3((i % cols - (cols - 1) * 0.5) * sp, 0.004, (i / cols) * sp * 0.75)
			mi.rotation.y = 0.35 * (1 if i % 2 == 0 else -1)
		var rows := ceili(items.size() / float(cols))
		var depth := rows * sp * 0.75
		cam.position = Vector3(0, sp * cols * 0.75, depth * 0.5 + sp * cols * 0.65)
		cam.look_at(Vector3(0, 0, depth * 0.45))
		for f in 4: await get_tree().process_frame
		await shot("loot_%d" % si)
		holder.queue_free()
	# In a match: a house's loot from the player's eyes.
	for n in get_children(): n.queue_free()
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await tree.create_timer(0.5).timeout
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await tree.create_timer(0.1).timeout
	var p: Player = world.player
	p.jump_from_plane()
	var best: Node3D = null
	var c: Vector2 = world.island.towns[0].pos
	for it in world.pickups:
		if it.get_meta("data").kind == "weapon" and Vector2(it.global_position.x, it.global_position.z).distance_to(c) < 300.0:
			if world.pickups_near(it.global_position, 3.0).size() >= 3:
				best = it
				break
	if best == null: best = world.pickups[0]
	var at: Vector3 = best.global_position
	p.global_position = at + Vector3(1.6, 0.3, 1.6)
	await get_tree().create_timer(1.5).timeout
	var c2 := Camera3D.new()
	world.add_child(c2)
	c2.global_position = at + Vector3(1.6, 1.7, 1.6)
	c2.look_at(at)
	c2.current = true
	for f in 20: await get_tree().process_frame
	await shot("loot_world")
	c2.global_position = at + Vector3(0.7, 0.9, 0.7)
	c2.look_at(at)
	for f in 5: await get_tree().process_frame
	await shot("loot_world_close")
	get_tree().quit()
