extends Node
## The spawn island: you start on it with guns lying about, others walking
## round, a countdown; nothing hurts you; when time is up everyone is on the
## plane with empty hands and the island's loot is gone.
## Run: godot --path godot res://tests/spawn_test.tscn -- --out=/dir (screenshots
## only when rendering; the checks work headless too).

var out := ""
var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok: fails += 1

func shot(name: String) -> void:
	if out == "" or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.controls = "kbm"
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	Game.spawn_island = true
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	var sp: SpawnIsland = world.spawn
	check(sp != null, "match starts on the spawn island")
	check(p.state == "ground", "player is standing (not in the plane)")
	check(not world.plane_active and not world.plane.visible, "plane waits, hidden")
	await wait(2.0)
	var c: Vector3 = sp.global_position
	check(absf(p.global_position.y - SpawnIsland.TOP) < 1.0, "player stands on the island's grass (y=%.2f)" % p.global_position.y)
	var near: Array = world.pickups.filter(func(it): return it.global_position.distance_to(c) < SpawnIsland.RADIUS + 5.0)
	check(near.size() >= 20, "guns and ammo lying about (%d)" % near.size())
	var plane_bots: int = world.bots.filter(func(b): return b.state == "plane").size()
	check(plane_bots == world.bots.size(), "bots stay on the plane while waiting (%d/%d)" % [plane_bots, world.bots.size()])
	p.yaw = 0.4
	p.pitch = -0.12
	await wait(1.0)
	await shot("spawn_view")
	# Pick up a gun and get "shot": no harm done.
	var gun: Node3D = null
	for it in near:
		if it.get_meta("data").kind == "weapon":
			gun = it
			break
	world.pickup(p, gun)
	check(p.active >= 0, "picked up a gun (%s)" % (p.slots[p.active].id if p.active >= 0 else "none"))
	var hp := p.health
	p.take_damage(50.0, world.bots[0])
	check(p.health == hp, "no damage on the spawn island")
	p.yaw = PI + 0.3
	await wait(1.5)
	await shot("spawn_armed")
	# A look over the whole island from above.
	p.global_position = c + Vector3(30, SpawnIsland.TOP + 0.2, 30)
	p.yaw = atan2(30.0, 30.0)
	p.pitch = -0.35
	await wait(1.0)
	await shot("spawn_overview")
	# Time's up.
	sp.left = 0.0
	await wait(0.5)
	check(world.spawn == null and not is_instance_valid(sp), "the island is gone")
	check(p.state == "plane" and world.plane_active and world.plane.visible, "everyone is on the plane")
	check(p.active == -1 and p.slots == [null, null, null], "empty hands on the plane")
	check(p.health == 100.0, "full health")
	var left: Array = world.pickups.filter(func(it): return it.global_position.distance_to(c) < SpawnIsland.RADIUS + 40.0)
	check(left.is_empty(), "the island's loot is gone (%d left)" % left.size())
	await wait(3.0)
	check(world.plane_t > 0.0, "the plane is flying (t=%.3f)" % world.plane_t)
	print("TEST ", "OK" if fails == 0 else "FAILED %d" % fails)
	tree.quit(0 if fails == 0 else 1)
