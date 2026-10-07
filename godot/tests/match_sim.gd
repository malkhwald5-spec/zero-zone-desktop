extends Node
## Simulates a whole match with an invulnerable player standing in the safe
## zone, to check the drop, looting, bot fights and the blue zone end to end.
## Run headless: godot --headless --path godot res://tests/match_sim.tscn

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="): Game.settings.mode = a.substr(7)
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
	print("SIM ready bots=%d pickups=%d" % [world.bots.size(), world.pickups.size()])
	var p: Player = world.player
	Engine.time_scale = 4.0
	# Ride the plane until everyone has jumped and landed.
	var t0: float = world.time
	for i in 400:
		await wait(0.25)
		var air := 0
		for b in world.bots:
			if b.state in ["plane", "fall", "chute"]: air += 1
		if p.state == "plane" and world.plane_over_land(): p.jump_from_plane()
		if air == 0 and p.state == "ground": break
	var bad := 0
	var inside := 0
	for b in world.bots:
		if world.is_deep(b.global_position): bad += 1
		if world._in_building(Vector2(b.global_position.x, b.global_position.z), 0.0): inside += 1
	print("SIM landed after %.0fs game time: in_deep=%d in_buildings=%d" % [world.time - t0, bad, inside])
	# Make the player a spectator: invulnerable, parked at the final zone centre later.
	p.health = 1e9
	world.zone.speed = 2.0
	var armed_log := []
	var last_alive: int = world.alive_count()
	var kills_by_zone := 0
	for i in 600:
		await wait(1.0)
		var z: Zone = world.zone
		var c := z.next_center
		p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y) + Vector3(0, 30, 0)   # hover above, out of fights
		p.velocity = Vector3.ZERO
		if i % 10 == 0:
			var armed := 0
			var modes := {}
			for b in world.bots:
				if b.dead: continue
				if b.armed(): armed += 1
				modes[b.mode] = modes.get(b.mode, 0) + 1
			print("SIM t=%4.0f zone=%s ph=%d r=%4.0f alive=%2d armed=%2d modes=%s zone_deaths=%d" % [world.time, z.state, z.phase, z.radius, world.alive_count(), armed, str(modes), world.zone_deaths])
		if world.alive_count() <= 1 or world.match_over or (world.team_size > 1 and world.teams_alive() <= 1): break
	Engine.time_scale = 1.0
	var top := []
	for b in world.bots:
		top.append([b.kills, b.display_name, b.dead])
	top.sort_custom(func(a, b): return a[0] > b[0])
	print("SIM end alive=%d teams=%d match_over=%s top_killers=%s" % [world.alive_count(), world.teams_alive(), world.match_over, str(top.slice(0, 3))])
	print("SIM DONE")
	tree.quit()
