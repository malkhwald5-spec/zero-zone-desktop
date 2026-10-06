extends Node
## Checks the smarter bots: cover when hurt, hearing shots, climbing stairs.

var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok: fails += 1

func _ready() -> void:
	_run.call_deferred()

func _place(world, b: Bot, pos: Vector3) -> void:
	b.state = "ground"
	b.global_position = Vector3(pos.x, world.ground_height(pos) + 0.3, pos.z)
	b.visible = true
	b._land()
	b.velocity = Vector3.ZERO

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 600:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(5000, 0, 5000)
	p.jump_from_plane()
	# A town house to hide behind.
	var house: Dictionary = {}
	for bd in world.island.buildings:
		if bd.get("storeys", 1) >= 2:
			house = bd
			break
	check("found a two-storey house", not house.is_empty())
	var hc: Vector2 = house.pos
	var ppos := Vector3(hc.x + 45.0, 0, hc.y)
	p.global_position = Vector3(ppos.x, world.ground_height(ppos) + 2.0, ppos.z)
	for i in 60:
		if p.state == "ground": break
		await wait(0.1)
	p.set_physics_process(false)
	# 1) Hurt bot in a fight looks for cover.
	var b: Bot = world.bots[0]
	b.weapon_id = "m416"
	b.mag = 30
	b.reserve = 90
	b.skill = 1.0
	b.meds = 0
	_place(world, b, Vector3(hc.x + house.size.x * 0.5 + 6.0, 0, hc.y + house.size.y * 0.5 + 6.0))
	var went := false
	for i in 10:
		b.health = 45.0
		b.hurt_t = 0.0
		b.mode = "fight"
		b.target = p
		if b._tactics(true) and b.mode == "cover":
			went = true
			break
	check("hurt bot runs for cover", went, "mode=%s" % b.mode)
	if went:
		var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 1.5, 0), b.goal + Vector3(0, 1.1, 0), 1)
		check("cover spot is hidden from the enemy", not world.get_world_3d().direct_space_state.intersect_ray(q).is_empty())
		b.set_physics_process(true)
		var g := b.goal
		var best := INF
		for i in 40:
			await wait(0.25)
			best = minf(best, b.global_position.distance_to(g))
			if best < 2.0: break
		b.set_physics_process(false)
		check("bot reaches cover", best < 2.5, "closest %.1f" % best)
	# 2) A shot is heard by an idle bot.
	var c: Bot = world.bots[1]
	c.weapon_id = "akm"
	c.mag = 30
	c.reserve = 60
	c.skill = 1.0
	var heard := false
	for i in 10:
		_place(world, c, ppos + Vector3(0, 0, 90))
		c.target = null
		c.mode = "roam"
		world.notify_shot(p.global_position, p)
		if c.mode == "alert" or c.target != null:
			heard = true
			break
	check("idle bot hears a shot and comes to look", heard, "mode=%s" % c.mode)
	var far_bot: Bot = world.bots[2]
	_place(world, far_bot, ppos + Vector3(0, 0, 300))
	far_bot.mode = "roam"
	world.notify_shot(p.global_position, p)
	check("far bot does not hear it", far_bot.mode == "roam")
	# 3) A route to someone upstairs goes up the stairs.
	var st: Array = WorldBuilder.stair_points(house)
	var up := Vector3(hc.x, float(house.floor) + WorldBuilder.STOREY_H + 0.1, hc.y)
	var r: Array = world.route(ppos, up)
	check("route upstairs uses the stairs", r.size() >= 3 and r[-1] == st[2] and r[-2] == st[1] and r[-3] == st[0], str(r))
	var d: Bot = world.bots[3]
	d.weapon_id = "m416"
	d.mag = 30
	d.skill = 1.0
	c.set_physics_process(false)
	c.global_position = Vector3(5000, 0, 5000)
	b.global_position = Vector3(5000, 0, 5040)
	p.global_position = Vector3(hc.x + 3000.0, 400.0, hc.y)
	_place(world, d, ppos)
	d.target = null
	d.mode = "alert"
	d._go(up)
	d.set_physics_process(true)
	var top := 0.0
	for i in 160:
		await wait(0.25)
		top = maxf(top, d.global_position.y - float(house.floor))
		if top > 3.0: break
	check("bot climbs the stairs", top > 3.0, "best height %.1f mode=%s" % [top, d.mode])
	print("BOT TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
