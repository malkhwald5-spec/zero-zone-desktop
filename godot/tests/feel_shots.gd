extends Node
## Pictures of the match feel: loot glowing on the floor with its names, the
## gun picture when you pick one up, damage numbers and the kill mark, and
## the weapon pictures in the HUD slots.
## Run: godot --path godot res://tests/feel_shots.tscn -- --out=/dir

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
	Game.settings.controls = "kbm"
	Game.settings.weather = "clear"
	Game.settings.quality = "high"
	Game.settings.mode = "solo"
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
	if world.spawn: world.board_plane()
	p.jump_from_plane()
	for b in world.bots: b.set_physics_process(false)
	# An open spot in a town, loot laid out in front of you.
	var t: Dictionary = world.island.towns[4]
	var at := Vector3(t.pos.x + 30, 0, t.pos.y + 30)
	for k in 40:
		var q := Vector2(at.x, at.z) + Vector2(k * 3.0, 0).rotated(k)
		if world.building_at(q, 4.0) < 0 and world.island.is_land(q.x, q.y):
			at = Vector3(q.x, 0, q.y)
			break
	at.y = world.ground_height(at)
	p.global_position = at + Vector3(0, 0.5, 0)
	p.yaw = 0.0
	p.pitch = -0.32
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	for i in 60:
		if p.state == "ground": break
		await wait(0.5)
	p.velocity = Vector3.ZERO
	at = p.global_position
	var fwd := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)
	var items := [{"kind": "weapon", "id": "m416", "mag": 30}, {"kind": "weapon", "id": "awm", "mag": 5}, {"kind": "gear", "gear": "vest", "lvl": 3, "dur": 200.0},
		{"kind": "gear", "gear": "helmet", "lvl": 2, "dur": 150.0}, {"kind": "weapon", "id": "ump", "mag": 25}, {"kind": "attach", "id": "x4"}]
	for i in items.size():
		var pos: Vector3 = at + fwd * (2.6 + (i / 3) * 1.8) + right * ((i % 3) - 1) * 1.5
		pos.y = world.ground_height(pos)
		world._add_pickup(items[i], pos)
	for i in 60:
		if p.state == "ground": break
		await wait(0.5)
	await wait(1.0)
	print("SHOT state ", p.state, " at ", p.global_position, " first ", world.pickups[-1].global_position, " labels ", world._loot_labels.filter(func(l): return l.visible).size(), " near ", world.pickups_near(p.global_position, 7.0).size())
	await shot("feel_1_loot")
	p.give_weapon("m416", 30)
	p.give_weapon("kar98", 5)
	world.hud.weapon_toast("kar98")
	await wait(0.5)
	await shot("feel_2_pickup")
	# Hits and a kill on a bot in front.
	var b: Bot = world.bots[0]
	b.set_physics_process(true)
	b.state = "ground"
	b.visible = true
	b.global_position = at + fwd * 9.0
	b.global_position.y = world.ground_height(b.global_position)
	await wait(0.5)
	b.set_physics_process(false)
	p.switch_slot(0)
	var hp: Vector3 = b.global_position + Vector3(0, 1.3, 0)
	world.hud._on_hit(false, false, hp)
	world.hud._on_hit(true, false, hp + Vector3(0.2, 0.2, 0))
	world.hud._on_hit(false, true, hp)
	world.hud._streak = 2
	world.hud._streak_t = 5.0
	world.hud._on_hit(true, true, hp)
	await wait(0.25)
	await shot("feel_3_hits")
	print("FEEL SHOTS DONE")
	tree.quit()
