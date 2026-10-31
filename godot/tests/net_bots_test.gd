extends Node
## The host's bots online: a host and a guest on one machine. Both have the
## same bots; the guest sees a bot where the host's bot is; the guest's shots
## kill a bot on the host (and the guest gets the kill); a bot's hit on the
## guest takes the guest's health. Run both:
##   godot --headless res://tests/net_bots_test.tscn -- --host
##   godot --headless res://tests/net_bots_test.tscn -- --join

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
	Game.settings.net_bots = true
	Game.profile.name = "HOST" if role == "host" else "GUEST"
	_run.call_deferred()

func _done() -> void:
	print("NET BOTS TEST %s %s (%d failed)" % [role, "OK" if fails == 0 else "FAILED", fails])
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
		Net.start_match()
	else:
		await wait(1.0)
		Net.join("127.0.0.1")
		for i in 600:
			if Net.in_match: break
			await wait(0.1)
	await wait(0.5)
	var world = tree.current_scene
	for i in 1800:
		if world and world.ready_done and world.net_started: break
		await wait(0.1)
	check("bots in the match", Net.bot_count > 0 and world.net_bots.size() == Net.bot_count, "%d / %d" % [world.net_bots.size(), Net.bot_count])
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
	p.health = 100.0
	var spot := base + Vector3(6, 0, 6)
	if role == "host":
		# The bots stand still (no fighting during the test); bot 0 at a known spot.
		for b in world.net_bots:
			b.set_physics_process(false)
			if b.state == "plane": b.state = "fall"
		var b0: Bot = world.net_bots[0]
		b0.state = "ground"
		b0.visible = true
		b0.global_position = spot
		await wait(6.0)
		check("guest's shots killed the bot here", b0.dead, "health %.0f" % b0.health)
		# Bot 1 shoots the guest.
		var b1: Bot = world.net_bots[1]
		var guest: RemotePlayer = world.puppets.values()[0]
		guest.take_damage(40.0, b1, false)
		await wait(4.0)
	else:
		await wait(3.0)
		var bp: RemotePlayer = world.net_bots[0]
		check("sees the host's bot where it is", Vector2(bp.global_position.x - spot.x, bp.global_position.z - spot.z).length() < 2.5, "%s vs %s" % [bp.global_position, spot])
		for k in 5:
			bp.take_damage(30.0, p, false)
			await wait(0.2)
		for i in 40:
			if bp.dead: break
			await wait(0.1)
		check("the bot died here too", bp.dead)
		check("kill counted for the guest", p.kills == 1, str(p.kills))
		for i in 60:
			if p.health < 99.0: break
			await wait(0.1)
		check("hit by the host's bot", p.health < 99.0, "health %.0f" % p.health)
	await wait(1.0)
	_done()
