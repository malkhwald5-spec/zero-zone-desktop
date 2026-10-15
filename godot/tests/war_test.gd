extends Node
## Team war: four forts and teams, shut gates while getting ready, bots
## marching out, places taken, coming back after dying, a broken heart
## stopping a team's return, the match ending with one team left.

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)
	else:
		print("ok   ", what)

func _ready() -> void:
	Game.settings.controls = "kbm"
	Game.settings.mode = "war"
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await tree.create_timer(0.5).timeout
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await tree.create_timer(0.1).timeout
	var w: War = world.war
	check(w != null, "the war is on")
	check(w.forts.size() == 4 and w.points.size() == 4, "four forts and four places")
	var p: Player = world.player
	var counts := [0, 0, 0, 0]
	counts[p.team] += 1
	for b in world.bots: counts[b.team] += 1
	check(counts == [25, 25, 25, 25], "four teams of 25  %s" % str(counts))
	check(w.fort_at(Vector2(p.global_position.x, p.global_position.z)) == p.team and p.state == "ground", "you start in your own fort")
	check(p.slots[0] != null and p.slots[2] != null, "with a gun and a pistol")
	for f in w.forts:
		var c: Vector2 = f.pos
		check(world.island.is_land(c.x, c.y) and not world.island.is_deep(c.x, c.y), "%s stands on land (h %.1f)" % [War.TEAMS[f.team].fort, world.island.height_at(c.x, c.y)])
	# Getting ready: nobody gets out.
	await tree.create_timer(12.0).timeout
	var outside := 0
	for b in world.bots:
		if w.fort_at(Vector2(b.global_position.x, b.global_position.z), 2.0) != b.team: outside += 1
	check(outside == 0, "everyone stays in while the gates are shut  (%d out)" % outside)
	check(not w.hurt_heart(w.forts[(p.team + 1) % 4].heart, 99999.0, p, true), "hearts can't be hurt before the war")
	w.prep_left = 0.05
	await tree.create_timer(1.0).timeout
	check(w.forts[0].barrier == null, "the gates open")
	await tree.create_timer(40.0).timeout
	outside = 0
	for b in world.bots:
		if not b.dead and w.fort_at(Vector2(b.global_position.x, b.global_position.z), 2.0) != b.team: outside += 1
	check(outside > 30, "bots march out of their forts  (%d out)" % outside)
	# A place: stand in it alone and take it.
	var pt: Dictionary = w.points[0]
	p.health = 1e9
	p.global_position = pt.pos + Vector3(2, 1, 0)
	p.reset_physics_interpolation()
	for b in world.bots:
		if b.team != p.team and b.global_position.distance_to(pt.pos) < 60.0:
			b.global_position = w.forts[b.team].center + Vector3(5, 1, 5)
	var m0: int = w.money
	var took := false
	for i in 40:
		await tree.create_timer(0.5).timeout
		if pt.owner == p.team:
			took = true
			break
	check(took, "you take %s on your own" % pt.name)
	check(w.money >= m0 + 200, "and get paid for it  (+%d)" % (w.money - m0))
	# Dying and coming back.
	p.health = 50.0
	p.take_damage(500.0, null)
	check(p.state == "dead" and w.player_respawn > 0.0, "you die and wait to come back")
	await tree.create_timer(War.RESPAWN_TIME + 1.0).timeout
	check(p.state == "ground" and w.fort_at(Vector2(p.global_position.x, p.global_position.z)) == p.team, "you come back in your fort")
	check(p.slots[0] != null, "with a gun again")
	# Dying at the wheel of the armoured car: the car is free again after.
	var apc: Vehicle = w.spawn_apc(p.team)
	await tree.create_timer(1.0).timeout
	p.global_position = apc.global_position + Vector3(2, 0, 0)
	p.enter_vehicle(apc)
	p.health = 10.0
	p.take_damage(500.0, null)
	check(apc.driver == null and p.vehicle == null, "dying in the armoured car leaves it empty")
	await tree.create_timer(War.RESPAWN_TIME + 1.0).timeout
	check(p.state == "ground" and not p.shape_node.disabled, "and you come back on your feet")
	p.enter_vehicle(apc)
	check(p.state == "vehicle", "and can drive it again")
	p.exit_vehicle()
	# Bots come back too.
	var enemy := (p.team + 1) % 4
	var victim: Bot = null
	for b in world.bots:
		if b.team == enemy and not b.dead:
			victim = b
			break
	var n0: int = w.alive_in(enemy)
	victim.take_damage(9999.0, p)
	check(w.alive_in(enemy) == n0 - 1, "an enemy bot dies")
	await tree.create_timer(War.BOT_RESPAWN + 1.5).timeout
	check(w.alive_in(enemy) == n0, "and comes back in its fort  (%d/%d)" % [w.alive_in(enemy), n0])
	# Breaking a heart: that team doesn't come back any more.
	var h: FortHeart = w.forts[enemy].heart
	w.hurt_heart(h, h.hp + 10.0, p, true)
	check(h.dead and not w.can_respawn(enemy), "a broken heart ends the coming back")
	var dead_n := 0
	for b in world.bots.duplicate():
		if b.team == enemy and not b.dead:
			b.take_damage(9999.0, p)
			dead_n += 1
	await tree.create_timer(1.0).timeout
	check(not w.team_in(enemy) and w.teams_in() == 3, "with all of them dead the team is out  (%d teams left)" % w.teams_in())
	# The last two enemy teams go the same way: you win.
	for t in 4:
		if t == p.team or t == enemy: continue
		w.hurt_heart(w.forts[t].heart, 1e9, p, true)
		for b in world.bots.duplicate():
			if b.team == t and not b.dead: b.take_damage(9999.0, p)
	await tree.create_timer(0.5).timeout
	check(world.match_over, "last team standing wins")
	print("WAR TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	Game.settings.mode = "solo"     # don't leave later tests (and the lobby) in team war
	Game.save_data()
	tree.quit()
