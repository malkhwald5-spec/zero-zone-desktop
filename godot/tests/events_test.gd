extends Node
## Mid-match events: each one runs without errors and does its job (crash
## leaves two loot crates, the eruption's rocks land and explode, the quake
## shakes the player).

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _ready() -> void:
	Game.settings.controls = "kbm"
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
	var p: Player = world.player
	p.health = 1e9
	p.jump_from_plane()
	var c: Vector2 = world.zone.center
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	var ev: MatchEvents = world.events
	check(not ev._volcano_spots.is_empty(), "the island has a volcano to erupt")
	var drops0: int = world.airdrops.size()
	ev.start("crash")
	await tree.create_timer(0.5).timeout
	check(world.airdrops.size() == drops0 + 2, "the crash leaves two crates  (%d)" % (world.airdrops.size() - drops0))
	ev.start("eruption")
	var thrown := 0
	for i in 60:
		await tree.create_timer(0.1).timeout
		thrown = maxi(thrown, ev._bombs.size())
	check(thrown > 0, "the volcano throws rocks")
	await tree.create_timer(6.0).timeout
	ev._erupt_t = 0.0
	await tree.create_timer(6.0).timeout
	check(ev._bombs.is_empty(), "the rocks land  (%d in the air)" % ev._bombs.size())
	ev.start("quake")
	await tree.create_timer(0.5).timeout
	check(p.shake > 0.3, "the quake shakes the player")
	# The zone triggers them by itself at the start of phases 1 and 3.
	var used0: int = ev._used.size()
	world.zone.start()
	world.zone._begin_phase(1)
	await tree.create_timer(0.3).timeout
	check(ev._used.size() == used0 + 1, "an event starts with phase 1")
	print("EVENTS TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	tree.quit()
