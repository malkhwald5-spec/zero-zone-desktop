extends Node
## Squad mode: teams of 4, teammates jump and land with you, no friendly
## fire, knocked instead of killed, bots revive teammates (and you), you
## revive a teammate by holding F, a team with nobody standing is out.

var out := "user://"
var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok: fails += 1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.mode = "squad"
	Game.settings.controls = "touch"
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
	var mates: Array = world.teammates(p)
	check("three teammates", mates.size() == 3 and mates.all(func(m): return m.buddy))
	var teams := {}
	for b in world.bots: teams[b.team] = teams.get(b.team, 0) + 1
	var full := 0
	for t in teams:
		if t != 0 and teams[t] == 4: full += 1
	check("24 enemy squads of 4 (+ your 3 teammates)", teams.size() == 25 and full == 24 and teams[0] == 3, str(teams))
	# Jump: teammates follow you out of the plane and down.
	for i in 400:
		if world.plane_over_land(): break
		await wait(0.1)
	p.jump_from_plane()
	await wait(2.5)
	check("teammates jumped after you", mates.all(func(m): return m.state in ["fall", "chute", "ground"]))
	Engine.time_scale = 4.0
	for i in 200:
		await wait(0.25)
		if p.state == "ground" and mates.all(func(m): return m.state == "ground"): break
	await wait(6.0)    # they walk over to you if they landed a bit off
	Engine.time_scale = 1.0
	var spread := 0.0
	for m in mates: spread = maxf(spread, m.global_position.distance_to(p.global_position))
	check("teammates landed next to you", p.state == "ground" and spread < 50.0, "farthest %.0f m" % spread)
	# Freeze everyone else for the knock tests.
	for b in world.bots:
		if not b.buddy:
			b.set_physics_process(false)
			b.global_position = Vector3(5000, 0, 5000)
	p.health = 100.0
	var m1: Bot = mates[0]
	# No friendly fire.
	var h0: float = m1.health
	m1.take_damage(50.0, p)
	check("no friendly fire", m1.health == h0)
	# An enemy squad member is knocked, not killed; its teammate picks it up.
	var e: Array = world.bots.filter(func(b): return b.team == 5)
	var spot := p.global_position + Vector3(60, 0, 0)
	_place(world, e[0], spot)
	_place(world, e[1], spot + Vector3(8, 0, 3))
	e[1].weapon_id = "m416"
	e[1].mag = 30
	e[0].set_physics_process(true)
	e[1].set_physics_process(true)
	e[0].take_damage(500.0, p)
	check("enemy knocked, not dead", e[0].knocked and not e[0].dead)
	var revived := false
	for i in 60:
		await wait(0.25)
		if not e[0].knocked:
			revived = true
			break
	check("its teammate picked it up", revived and not e[0].dead, "mode=%s" % e[1].mode)
	# Knock all four: the team is out.
	for b in e:
		b.set_physics_process(true)
		if not b.knocked and not b.dead:
			b.health = 1.0
			b.take_damage(500.0, p)
	await wait(0.3)
	check("a team with nobody standing is out", e.all(func(b): return b.dead), str(e.map(func(b): return [b.knocked, b.dead])))
	# You get knocked: a teammate comes and picks you up.
	var enemy: Bot = world.bots.filter(func(b): return b.team == 6)[0]
	for m in mates: m.global_position = p.global_position + Vector3(randf_range(-6, 6), 0.5, randf_range(-6, 6))
	await wait(0.5)
	p.take_damage(1000.0, enemy)
	check("you are knocked", p.knocked and p.state == "ground")
	await wait(0.3)
	await shot("knocked")
	var up := false
	for i in 60:
		await wait(0.25)
		if not p.knocked:
			up = true
			break
	check("a teammate picked you up", up and p.state != "dead", "health %.0f" % p.health)
	# You pick up a knocked teammate by holding F.
	for m in mates: m.set_physics_process(false)
	var m2: Bot = mates[1]
	m2.set_physics_process(true)
	m2.health = 1.0
	m2.take_damage(500.0, enemy)
	check("teammate knocked", m2.knocked)
	m2.set_physics_process(false)
	p.global_position = m2.global_position + Vector3(1.2, 0.3, 0)
	await wait(0.5)
	check("revive prompt next to them", p.downed_mate_near() == m2)
	await shot("revive_prompt")
	p.action("interact", true)
	await wait(3.0)
	check("reviving…", p.revive_target == m2 and p.revive_t > 2.0)
	await shot("reviving")
	await wait(3.5)
	p.action("interact", false)
	check("you picked them up", not m2.knocked and not m2.dead)
	print("SQUAD TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
