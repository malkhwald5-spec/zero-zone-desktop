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
	print("GEAR TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
