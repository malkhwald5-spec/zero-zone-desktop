extends Node
## What a doctored or broken game on the network can do to ours: bad
## reports, huge or NaN damage, kills it didn't earn, loot from across the
## map, odd names, floods, and a hand-edited save file. All must be shrugged off.

var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok: fails += 1

func _ready() -> void:
	Game.settings.mode = "solo"
	Game.training = false
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	_names()
	_save()
	# A match with one other (pretend) player in it.
	Net.is_host = true
	Net.in_match = true
	Net.match_seed = 7
	Net.roster = {1: {"name": "me", "outfit": 0}, 5: {"name": "friend", "outfit": 0}}
	Game.spawn_island = false
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	var rp: RemotePlayer = world.puppets.get(5)
	check("puppet made", rp != null)
	# Put both on the ground next to each other.
	var at: Vector3 = world.pickups[0].global_position
	p.state = "ground"
	p.global_position = at + Vector3(3, 0.5, 0)
	await wait(0.3)
	var good := {"p": at + Vector3(2, 0.5, 0), "y": 0.0, "s": "ground", "st": "stand", "v": Vector3.ZERO, "w": "m416", "h": 100.0}
	world.net_state(5, good)
	await wait(0.2)
	check("good report moves the puppet", rp.global_position.distance_to(good.p) < 1.5, str(rp.global_position))
	var before: Vector3 = rp.global_position
	# Reports of the wrong kind or out of range.
	world.net_state(5, {"p": "here", "s": 5})
	world.net_state(5, {"p": Vector3(NAN, 0, 0)})
	world.net_state(5, {"p": Vector3(1e9, 0, 0)})
	world.net_state(5, {"p": good.p, "s": [1], "st": "fly", "w": "../../x", "v": "fast", "h": INF, "gv": 99, "y": NAN})
	await wait(0.2)
	check("bad reports ignored or cleaned", rp.global_position.is_finite() and rp.global_position.distance_to(before) < 2.0 and rp.weapon_id == "" and rp.gear.vest <= 3 and is_finite(rp.health) and is_finite(rp.yaw), "%s %s %s" % [rp.global_position, rp.weapon_id, rp.health])
	# Driving off with a car nobody is near, or a broken transform.
	if not world.vehicles.is_empty():
		var car: Vehicle = world.vehicles[0]
		var cpos: Vector3 = car.global_position
		world.net_state(5, {"p": good.p, "s": "vehicle", "vn": 0, "vx": Transform3D(Basis(), good.p)})
		await wait(0.2)
		check("can't take a far-away car", car.global_position.distance_to(cpos) < 3.0 and not car.has_meta("net_driven") and rp._ride == null, "%.2f m %s %s" % [car.global_position.distance_to(cpos), car.has_meta("net_driven"), rp._ride])
		world.net_state(5, {"p": good.p, "s": "vehicle", "vn": 0, "vx": Transform3D(Basis.from_scale(Vector3.ZERO), good.p)})
		await wait(0.1)
		check("zero-size car transform refused", rp.state != "vehicle", rp.state)
	world.net_state(5, good)
	await wait(0.2)
	# Damage.
	var h0 := p.health
	world.net_hit(99, 50.0, false)
	check("hit from a stranger ignored", p.health == h0)
	world.net_hit(5, NAN, false)
	world.net_hit(5, INF, false)
	world.net_hit(5, -80.0, false)
	check("NaN / INF / healing hits ignored", p.health == h0 and is_finite(p.health), str(p.health))
	world.net_hit(5, 10.0, false)
	check("a real hit still lands", p.health < h0, str(p.health))
	# Hits flood: only so many a second get through.
	var passed := 0
	for i in 200:
		if Net._spend(5, 1): passed += 1
	check("hit flood capped", passed <= 60, str(passed))
	check("stranger has no budget", not Net._spend(77, 0))
	# Kill credit.
	var k0 := p.kills
	world.net_died(5, Net.me())
	check("unearned kill not credited", p.kills == k0 and rp.dead)
	# Loot: far away refused.
	var far: Node3D = null
	var near: Node3D = null
	for it in world.pickups:
		if not it.has_meta("nid"): continue
		var d: float = it.global_position.distance_to(rp.global_position)
		if d > 200.0 and far == null: far = it
		if d < 6.0 and near == null: near = it
	world.net_taken(5, int(far.get_meta("nid")))
	check("dead player can't take loot", is_instance_valid(far) and world.pickups.has(far))
	rp.dead = false
	world.net_taken(5, int(far.get_meta("nid")))
	check("far loot not taken", world.pickups.has(far))
	if near:
		world.net_taken(5, int(near.get_meta("nid")))
		await wait(0.1)
		check("near loot taken", not world.pickups.has(near))
	world.net_taken(99, 0)
	check("stranger ignored", true)
	print("DONE fails=%d" % fails)
	Net.in_match = false
	Net.is_host = false
	Net.roster = {}
	get_tree().quit(1 if fails > 0 else 0)

func _names() -> void:
	check("clean name strips controls", Net.clean_name("a\nb" + String.chr(0x202E) + "c" + String.chr(1)) == "abc")
	check("clean name length", Net.clean_name("x".repeat(500)).length() == 16)
	check("clean name of non-text", Net.clean_name([1, 2]) != "")
	check("empty name", Net.clean_name("   ") == "لاعب")

func _save() -> void:
	var keep := FileAccess.get_file_as_string(Game.SAVE_PATH) if FileAccess.file_exists(Game.SAVE_PATH) else ""
	var gold0 = Game.wallet.gold
	var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"save_version": 9, "wallet": {"claimed": "oops", "gold": [1]}, "profile": {"owned": 5}, "settings": {"keys": "x", "sens": "fast"}}))
	f.close()
	Game.load_data()
	check("tampered save: kinds kept", typeof(Game.wallet.claimed) == TYPE_ARRAY and typeof(Game.profile.owned) == TYPE_ARRAY and typeof(Game.settings.keys) == TYPE_DICTIONARY and typeof(Game.wallet.gold) in [TYPE_INT, TYPE_FLOAT])
	Game.owns(0)
	Game.roll_periods()
	# Put the real save back.
	f = FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string(keep)
	f.close()
	if keep != "": Game.load_data()
	Game.wallet.gold = gold0
