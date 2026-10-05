extends Node
## Follows a few bots after landing and logs what they do (looting diagnostics).

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

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
	p.health = 1e9
	# Land every bot right away at its destination.
	for b in world.bots:
		b.visible = true
		b.global_position = b.dest + Vector3(0, 0.3, 0)
		b._land()
	p.global_position = Vector3(10, 200, 10)
	p.state = "ground"
	world.zone.speed = 0.0001
	Engine.time_scale = 4.0
	var watch: Array = world.bots.slice(0, 8)
	for i in 30:
		await wait(2.0)
		var line := "T%02d " % i
		for b in watch:
			var ld := -1.0
			if b.loot_item and is_instance_valid(b.loot_item): ld = b.global_position.distance_to(b.loot_item.global_position)
			line += "| %s %s w=%s ld=%.0f path=%d st=%d y=%.1f " % [b.display_name.left(6), b.mode, b.weapon_id, ld, b.path.size(), b.stuck_n, b.global_position.y - world.ground_height(b.global_position)]
		print(line)
	var armed := 0
	var near_items := 0
	for b in world.bots:
		if b.armed(): armed += 1
		if world.find_pickup(b.global_position, 70.0, func(it): return it.get_meta("data").kind == "weapon"): near_items += 1
	print("DEBUG armed=%d/%d bots_with_weapon_within_70m=%d" % [armed, world.bots.size(), near_items])
	print("DEBUG DONE")
	tree.quit()
