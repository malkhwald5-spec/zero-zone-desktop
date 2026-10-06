extends Node
## Checks armour, helmets, backpacks, meds and boost (run headless).

var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok: fails += 1

func _ready() -> void:
	_run.call_deferred()

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
	var bot: Bot = world.bots[0]
	# Freeze the bots so nobody shoots during the checks.
	for b in world.bots: b.set_physics_process(false)
	# Put the player on open ground.
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[0].pos
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 3.0, c.y)
	for i in 50:
		if p.state == "ground": break
		await wait(0.1)
	check("landed", p.state == "ground")
	var gear_count := 0
	var heal_count := 0
	for it in world.pickups:
		var k: String = it.get_meta("data").kind
		if k == "gear": gear_count += 1
		if k == "heal": heal_count += 1
	check("gear and meds spawned", gear_count > 30 and heal_count > 50, "gear=%d heals=%d" % [gear_count, heal_count])
	# Armour.
	p.health = 100.0
	p.take_damage(20.0, bot, false)
	check("no vest: full damage", is_equal_approx(p.health, 80.0), "hp=%.1f" % p.health)
	p.equip("vest", 2, Items.VEST[2].dur)
	p.health = 100.0
	p.take_damage(20.0, bot, false)
	check("vest 2 absorbs 40%", is_equal_approx(p.health, 88.0), "hp=%.1f dur=%.0f" % [p.health, p.gear.vest_dur])
	p.equip("helmet", 1, Items.HELMET[1].dur)
	p.health = 100.0
	p.take_damage(90.0, bot, true)
	check("helmet 1 breaks after 80 dmg", p.gear.helmet == 0 and is_equal_approx(p.health, 37.0), "hp=%.1f helmet=%d" % [p.health, p.gear.helmet])
	p.health = 100.0
	p.take_damage(10.0, null, false)
	check("zone ignores armour", is_equal_approx(p.health, 90.0), "hp=%.1f" % p.health)
	# Healing.
	p.heals.bandage = 2
	p.health = 50.0
	p.use_heal("bandage")
	await wait(Items.HEALS.bandage.time + 0.5)
	check("bandage +10", is_equal_approx(p.health, 60.0) and p.heals.bandage == 1, "hp=%.1f" % p.health)
	p.heals.firstaid = 1
	p.use_heal("firstaid")
	p.firing = true
	await wait(0.3)
	p.firing = false
	check("firing cancels healing", p.heal_id == "" and p.heals.firstaid == 1)
	p.use_heal("firstaid")
	await wait(Items.HEALS.firstaid.time + 0.5)
	check("first aid -> 75", p.health >= 75.0 and p.heals.firstaid == 0, "hp=%.1f" % p.health)
	p.health = 76.0
	p.heals.bandage = 1
	p.use_heal("bandage")
	check("bandage refused above 75", p.heal_id == "")
	p.heals.drink = 1
	p.use_heal("drink")
	await wait(Items.HEALS.drink.time + 0.5)
	var hp_b := p.health
	await wait(3.0)
	check("boost heals over time", p.boost > 30.0 and p.health > hp_b, "boost=%.0f hp %.1f -> %.1f" % [p.boost, hp_b, p.health])
	# Capacity.
	p.ammo["556"] = 0
	p.heals = {"bandage": 0, "firstaid": 0, "medkit": 0, "drink": 0, "pills": 0}
	check("base capacity 60", is_equal_approx(p.capacity(), 60.0))
	p.ammo["556"] = 118
	var it2: Node3D = world._add_pickup({"kind": "ammo", "type": "556", "amount": 30}, p.global_position)
	world.pickup(p, it2)
	check("bag full: only 2 rounds fit, rest stays", p.ammo["556"] == 120 and world.pickups.has(it2) and it2.get_meta("data").amount == 28, "ammo=%d" % p.ammo["556"])
	var pk: Node3D = world._add_pickup({"kind": "gear", "gear": "pack", "lvl": 2, "dur": 0.0}, p.global_position)
	world.pickup(p, pk)
	check("backpack 2 equipped", p.gear.pack == 2 and is_equal_approx(p.capacity(), 160.0))
	world.pickup(p, it2)
	check("then the rest fits", p.ammo["556"] == 148 and not world.pickups.has(it2), "ammo=%d" % p.ammo["556"])
	# Bots: armour and gear pickup.
	var b2: Bot = world.bots[1]
	b2.state = "ground"
	b2.gear.vest = 3
	b2.gear.vest_dur = 200.0
	b2.health = 100.0
	b2.take_damage(20.0, p, false)
	check("bot vest 3 absorbs 55%", is_equal_approx(b2.health, 91.0), "hp=%.1f" % b2.health)
	var hl: Node3D = world._add_pickup({"kind": "gear", "gear": "helmet", "lvl": 2, "dur": 150.0}, b2.global_position)
	world.bot_take(b2, hl)
	check("bot wears helmet 2", b2.gear.helmet == 2)
	# Grenades.
	var b3: Bot = world.bots[2]
	b3.state = "ground"
	b3.gear.vest = 0
	b3.health = 100.0
	var open_pos: Vector3 = p.global_position + Vector3(6, 0, 0)
	b3.global_position = Vector3(open_pos.x, world.ground_height(open_pos) + 0.1, open_pos.z)
	await wait(0.2)
	world.explode(b3.global_position + Vector3(3, 0.2, 0), p)
	check("frag hurts at 3 m", b3.health < 60.0, "hp=%.1f" % b3.health)
	# Behind a wall: bot in the middle of a house, blast outside a wall without a door.
	var bl: Dictionary = {}
	for x in world.island.buildings:
		if not x.doors.has(1) and x.size.x < 12.0:
			bl = x
			break
	b3.health = 100.0
	b3.global_position = Vector3(bl.pos.x, float(bl.floor) + 0.2, bl.pos.y)
	await wait(0.3)
	var outside := Vector3(bl.pos.x + bl.size.x * 0.5 + 1.5, world.ground_height(Vector3(bl.pos.x + bl.size.x * 0.5 + 1.5, 0, bl.pos.y)) + 0.3, bl.pos.y)
	world.explode(outside, p)
	check("walls stop the blast", is_equal_approx(b3.health, 100.0), "hp=%.1f d=%.1f" % [b3.health, outside.distance_to(b3.global_position)])
	# Player throw flow.
	p.throwables.frag = 1
	p.start_throw()
	check("throw ready shows arc", p.throw_ready and p.throw_arc().size() > 5)
	p.release_throw()
	var g_count := 0
	for n in world.get_children():
		if n is Grenade: g_count += 1
	check("grenade thrown", g_count == 1 and p.throwables.frag == 0)
	await wait(Grenade.FUSE + 0.5)
	g_count = 0
	for n in world.get_children():
		if n is Grenade: g_count += 1
	check("grenade went off", g_count == 0)
	# Smoke blocks sight.
	var sp: Vector3 = p.global_position + Vector3(0, 0, 10)
	world.add_smoke(sp)
	check("smoke blocks a line through it", world.smoke_blocks(p.global_position + Vector3(0, 1.5, 0), sp + Vector3(0, 1.5, 10)))
	check("smoke does not block other lines", not world.smoke_blocks(p.global_position + Vector3(0, 1.5, 0), p.global_position + Vector3(30, 1.5, 0)))
	# Bot throws at a hidden target.
	b3.global_position = outside + Vector3(15, 0, 0)
	b3.global_position.y = world.ground_height(b3.global_position) + 0.1
	b3.frags = 1
	b3.weapon_id = "m416"
	b3.target = p
	p.global_position = Vector3(bl.pos.x, float(bl.floor) + 0.2, bl.pos.y)
	await wait(0.2)
	b3.throw_cd = 0.0
	var dd := b3.global_position.distance_to(p.global_position)
	var clr := b3._clear_line(p)
	var vv := Grenade.aim_velocity(b3._eye(), p.global_position + Vector3(0, 0.3, 0))
	# Hidden: throws at once. In plain view: only now and then (12% per decision).
	for k in 80:
		b3.throw_cd = 0.0
		b3._maybe_throw()
		if b3.frags == 0: break
	check("bot throws frags in a fight", b3.frags == 0, "d=%.1f clear=%s v=%s" % [dd, clr, vv])
	# Airdrops.
	world.zone.start()
	world.call_drop()
	check("cargo plane on its way", world._drop_flights.size() == 1)
	var f: Dictionary = world._drop_flights[0]
	f.t = 0.45
	for i in 200:
		if not world.airdrops.is_empty(): break
		await wait(0.05)
	check("crate dropped near the spot", world.airdrops.size() == 1)
	var ad: Airdrop = world.airdrops[0]
	ad.global_position.y = ad.target.y + 2.0
	await wait(0.6)
	check("crate landed", ad.landed)
	var crate_items: Array = world.pickups_near(ad.global_position + Vector3(0, 0.95, 0), 1.5)
	var has_crate_gun := false
	for it in crate_items:
		var cd: Dictionary = it.get_meta("data")
		if cd.kind == "weapon" and Game.WEAPONS[cd.id].get("crate", false): has_crate_gun = true
	check("crate holds a crate-only weapon and gear", has_crate_gun and crate_items.size() >= 4, "items=%d" % crate_items.size())
	var inside: bool = world.zone.distance_to_safe(ad.global_position) == 0.0
	check("drop is inside the next safe zone", inside)
	# A bot nearby goes for it.
	var b4: Bot = world.bots[3]
	# Only this bot: others nearby would pull it into a fight.
	# Frozen bots can still be seen and fought, so move them well out of sight.
	for ob in world.bots:
		if ob != b4:
			ob.set_physics_process(false)
			ob.global_position = ad.global_position + Vector3(3000, 0, 3000)
	b4.state = "ground"
	b4.weapon_id = "ump"
	b4.reserve = 100
	b4.target = null
	var start := ad.global_position + Vector3(25, 0, 0)
	b4.global_position = Vector3(start.x, world.ground_height(start) + 0.3, start.z)
	b4.visible = true
	b4._land()
	b4.set_physics_process(true)
	p.set_physics_process(false)
	p.global_position = ad.global_position + Vector3(0, 200, 0)
	for i in 120:
		await wait(0.25)
		if Game.WEAPONS[b4.weapon_id].get("crate", false): break
	check("bot loots the crate", Game.WEAPONS[b4.weapon_id].get("crate", false), "bot weapon=%s mode=%s d=%.1f target=%s" % [b4.weapon_id, b4.mode, b4.global_position.distance_to(ad.global_position), str(b4.target)])
	print("GEAR TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
