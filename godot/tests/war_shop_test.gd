extends Node
## Team war, part two: the shop (guns, armour, parts), giving money to the
## fort until it levels up, machine-gun towers firing at enemies, bots
## raiding enemy hearts, and the final battle closing the zone.

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
	var p: Player = world.player
	var f: Dictionary = w.forts[p.team]
	p.health = 1e9
	# A way into an enemy fort from behind goes round the walls to the gate.
	var ef: Dictionary = w.forts[(p.team + 1) % 4]
	var back: Vector2 = ef.pos - ef.gate * (War.H + 60.0) + Vector2(-ef.gate.y, ef.gate.x) * 10.0
	var from := Vector3(back.x, world.ground_height(Vector3(back.x, 0, back.y)), back.y)
	var pts: Array = world.route(from, ef.center)
	var prev := Vector2(from.x, from.z)
	var through := 0
	for i in pts.size() - 1:
		var q := Vector2(pts[i].x, pts[i].z)
		if world._crosses(prev, q, ef.pos, Vector2(War.H - 1.0, War.H - 1.0)): through += 1
		prev = q
	check(through == 0 and pts.size() >= 3, "the way in from behind goes round to the gate  (%d points, %d through walls)" % [pts.size(), through])
	# The shop opens inside the fort.
	world.hud.toggle_shop()
	check(world.hud.shop != null, "the shop opens in your fort")
	var shop: ShopPanel = world.hud.shop
	w.money = 5000
	shop._buy_gun(400, "m416")
	check(w.money == 4600 and (p.slots[0].id == "m416" or p.slots[1].id == "m416"), "buy an M416")
	check(int(p.ammo["556"]) >= 120, "it comes with ammo")
	shop._buy_gear(300, "vest2")
	check(int(p.gear.vest) == 2, "buy a level 2 vest")
	p.switch_slot(0 if p.slots[0].id == "m416" else 1)
	shop._buy_mod(300, "x4")
	check(p.slots[p.active].get("att", {}).get("sight", "") == "x4", "a 4x scope goes on the gun")
	for tb in ["guns", "gear", "mods", "fort"]:
		shop.tab = tb
		shop._fill()
		await tree.process_frame
	check(shop._body.get_child_count() > 0, "every shop page fills")
	world.hud.toggle_shop()
	check(world.hud.shop == null, "and closes")
	# Giving money to the fort.
	w.money = 4000
	w.donate(3500)
	await tree.create_timer(1.5).timeout
	check(int(f.level) == 2 and is_equal_approx(f.heart.max_hp, War.HEART_HP[2]), "the fort levels up with the team's money  (level %d)" % int(f.level))
	# A machine-gun tower shoots at an enemy outside the wall.
	w.build(f, "tower")
	check(f.towers.size() == 1, "a tower goes up")
	w.build(f, "bags")
	check(int(f.bags) == 1, "a sandbag wall goes up")
	w.prep_left = 0.05
	await tree.create_timer(0.5).timeout
	var tw: WarTurret = f.towers[0]
	var enemy: Bot = null
	for b in world.bots:
		if b.team != p.team and not b.dead:
			enemy = b
			break
	var g: Vector2 = f.gate
	var out: Vector2 = f.pos + g * (War.H + 30.0)
	enemy.global_position = Vector3(out.x, world.ground_height(Vector3(out.x, 0, out.y)) + 0.5, out.y)
	enemy.health = 1e6
	enemy.set_physics_process(false)
	var hp0: float = enemy.health
	await tree.create_timer(6.0).timeout
	check(enemy.health < hp0, "the tower shoots the enemy at the gate  (%.0f damage)" % (hp0 - enemy.health))
	enemy.set_physics_process(true)
	enemy.health = 100.0
	# Raiders get to an enemy heart.
	Engine.time_scale = 4.0
	var hurt := false
	for i in 480:
		await tree.create_timer(1.0).timeout
		for ff in w.forts:
			if ff.heart.hp < ff.heart.max_hp - 50.0: hurt = true
		if hurt: break
		if i % 30 == 29:
			var info := []
			for b in world.bots:
				if b.war_role == "raid" and not b.dead and info.size() < 6:
					var tg: int = b.war_goal
					var tt: String = "-" if b.target == null or not is_instance_valid(b.target) else ("heart" if b.target is FortHeart else ("tower" if b.target is WarTurret else "actor%d" % int(b.global_position.distance_to(b.target.global_position))))
					info.append("%s %s d=%d" % [b.mode, tt, int(b.global_position.distance_to(w.forts[tg].center)) if tg >= 0 else -1])
			print("t=%d raiders: %s" % [int(w.time), ", ".join(info)])
	Engine.time_scale = 1.0
	var hps := []
	for ff in w.forts: hps.append(int(ff.heart.hp))
	check(hurt, "bots raid and hurt an enemy heart  %s  (after %.0f s of war)" % [str(hps), w.time])
	var owned := 0
	for pt in w.points:
		if pt.owner >= 0: owned += 1
	check(owned >= 1, "bots take places  (%d held)" % owned)
	# The final battle.
	w.time = War.FINAL_AT - 0.5
	await tree.create_timer(1.0).timeout
	check(w.final and world.zone.state != "idle", "the final battle starts the zone")
	check(not w.can_respawn(p.team), "nobody comes back after that")
	print("WAR SHOP TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	tree.quit()
