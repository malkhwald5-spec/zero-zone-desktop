extends Node
## Two copies of the game on one machine: one hosts a room, the other joins
## by address. Both load the same island (same loot), see each other where
## they are, and a shot from the host takes the other's health down to
## death; the host wins. Run both:
##   godot --headless res://tests/net_test.tscn -- --host
##   godot --headless res://tests/net_test.tscn -- --join

var fails := 0
var role := "host"

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + "[%s] " % role + name + ("  " + info if info != "" else ""))
	if not ok: fails += 1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--join": role = "join"
	Game.settings.controls = "touch"
	Game.profile.name = "HOST" if role == "host" else "GUEST"
	_run.call_deferred()

func _done() -> void:
	print("NET TEST %s %s (%d failed)" % [role, "OK" if fails == 0 else "FAILED", fails])
	await wait(0.5)
	get_tree().quit()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	if role == "host":
		check("room opened", Net.host())
		for i in 600:
			if Net.roster.size() >= 2: break
			await wait(0.1)
		check("guest joined", Net.roster.size() == 2, str(Net.roster))
		Net.start_match()
	else:
		await wait(1.0)
		Net.join("127.0.0.1")
		for i in 600:
			if Net.in_match: break
			await wait(0.1)
		check("match started by the host", Net.in_match)
	await wait(0.5)
	var world = tree.current_scene
	for i in 1800:
		if world and world.ready_done and world.net_started: break
		await wait(0.1)
	check("both loaded, countdown started", world.net_started)
	check("one other player", world.puppets.size() == 1, str(world.puppets.keys()))
	var h := 0
	for id in world._by_nid:
		var it: Node3D = world._by_nid[id]
		h = (h * 31 + int(it.global_position.x * 10.0) + int(it.global_position.z * 10.0)) % 1000000007
	print("LOOTHASH %d %d" % [world._by_nid.size(), h])
	# Off the island, onto the same spot of the map: host at P, guest 8 m north.
	world.board_plane()
	var p: Player = world.player
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[0].pos + Vector2(30, 30)
	var base := Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)), c.y)
	var me := base if role == "host" else base + Vector3(0, 0, -8)
	p.global_position = me + Vector3(0, 0.6, 0)
	p._land()
	p.global_position = me + Vector3(0, 0.6, 0)
	p.velocity = Vector3.ZERO
	p.yaw = 0.0
	await wait(3.0)
	var other: RemotePlayer = world.puppets.values()[0]
	var expect := base + Vector3(0, 0, -8) if role == "host" else base
	check("sees the other where they are", Vector2(other.global_position.x - expect.x, other.global_position.z - expect.z).length() < 2.5,
		"%s vs %s" % [other.global_position, expect])
	check("the other is on the ground", other.state == "ground", other.state)
	if role == "host":
		# Take a loot item: it goes from the guest's island too.
		var nid: int = world._by_nid.keys()[3]
		world._remove_pickup(world._by_nid[nid])
		print("TOOK %d" % nid)
		p.give_weapon("m416", 30)
		p.ammo["556"] = 90
		await wait(1.0)
		for k in 30:
			if other.dead: break
			var to: Vector3 = other.global_position + Vector3(0, 1.1, 0) - p.camera.global_position
			p.yaw = atan2(-to.x, -to.z)
			p.pitch = atan2(to.y, Vector2(to.x, to.z).length())
			await wait(0.15)
			p.firing = true
			p._try_fire()
			p.firing = false
			await wait(0.25)
		await wait(1.5)
		check("the guest died", other.dead)
		check("host won", world.match_over and p.state != "dead")
		check("kill counted", p.kills == 1, str(p.kills))
	else:
		await wait(2.0)
		for i in 300:
			if p.state == "dead": break
			await wait(0.1)
		check("shot by the host", p.state == "dead", "health %.0f" % p.health)
		check("lost", world.match_over)
		var gone := 0
		for i in 3:
			gone = world.pickups.size()
		print("PICKUPS %d" % world._by_nid.size())
	await wait(1.0)
	_done()
