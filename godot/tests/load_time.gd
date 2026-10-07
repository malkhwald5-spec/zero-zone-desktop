extends Node
## Time to build a match (headless), split by step.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	var t0 := Time.get_ticks_msec()
	var isl := Island.new(12345, Game.MAP_SIZE)
	isl._heights()
	print("regions: ", {"plains": 0}.size())
	var t1 := Time.get_ticks_msec()
	isl._towns()
	isl._roads()
	var t2 := Time.get_ticks_msec()
	isl._buildings()
	var t3 := Time.get_ticks_msec()
	isl._props()
	var t4 := Time.get_ticks_msec()
	print("LOAD island heights=%dms towns+roads=%dms buildings=%dms props=%dms  towns=%d buildings=%d trees=%d rocks=%d" % [t1 - t0, t2 - t1, t3 - t2, t4 - t3, isl.towns.size(), isl.buildings.size(), isl.trees.size(), isl.rocks.size()])
	t0 = Time.get_ticks_msec()
	tree.change_scene_to_file("res://scenes/world.tscn")
	await get_tree().create_timer(0.5).timeout
	var world = tree.current_scene
	for i in 1200:
		if world.ready_done: break
		await get_tree().create_timer(0.1).timeout
	print("LOAD world total=%dms pickups=%d" % [Time.get_ticks_msec() - t0, world.pickups.size()])
	tree.quit()
