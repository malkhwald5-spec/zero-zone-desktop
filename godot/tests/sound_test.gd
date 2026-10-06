extends Node
## Recorded sounds: all load, and shots / reloads / empty click / fly-bys play
## without errors. Run: godot --headless --path godot res://tests/sound_test.tscn

var failed := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok: failed += 1

func _ready() -> void:
	Game.settings.controls = "kbm"
	Game.settings.sound = true
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	p.health = 1e9
	for b in world.bots: b.set_physics_process(false)
	for k in world.SOUNDS:
		check(world._snd.get(k) != null and world.sound_length(k) > 0.05, "sound %s loaded  %.2fs" % [k, world.sound_length(k)])
	p.jump_from_plane()
	p.global_position = Vector3(world.island.towns[1].pos.x, 80, world.island.towns[1].pos.y)
	for i in 100:
		if p.state == "ground": break
		await wait(0.1)
	# Empty gun with no spare ammo: click, no reload.
	p.give_weapon("m416", 0)
	p.ammo["556"] = 0
	p._try_fire()
	check(p.reload_t == 0.0 and p.fire_cd > 0.3, "empty gun clicks instead of reloading")
	# With ammo: reload starts (and plays the reload sound).
	p.ammo["556"] = 60
	p.start_reload()
	check(p.reload_t > 0.0, "reload starts")
	var n0: int = world.get_child_count()
	world.sound_shot("sr", p.global_position, true)
	world.sound_shot("ar", p.global_position + Vector3(300, 0, 0), false)
	world.sound_shot("ar", p.global_position + Vector3(20, 0, 0), false)
	world.sound_flyby(p.global_position + Vector3(1, 1.5, 0))
	check(world.get_child_count() >= n0 + 4, "shot, far shot, near shot and fly-by players created")
	await wait(2.5)
	check(world._sounds_playing <= 1, "finished sounds are cleaned up  playing=%d" % world._sounds_playing)
	print("SOUND TEST %s (%d failed)" % ["OK" if failed == 0 else "FAILED", failed])
	tree.quit(failed)
