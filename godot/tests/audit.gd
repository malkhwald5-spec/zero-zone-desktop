extends Node
## Game audit: checks the generated maps over several seeds, then plays a match
## (pickup, shooting a bot, bots behaviour, performance, death -> results -> lobby).
## Run: godot --path godot res://tests/audit.tscn -- --out=/some/dir

var out := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.quality = "low"
	_run.call_deferred()

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	_map_audit()
	await _match_audit()
	print("AUDIT DONE")
	tree.quit()

# ---------------------------------------------------------------- map
func _in_rect(p: Vector2, b: Dictionary, pad: float) -> bool:
	return absf(p.x - b.pos.x) < b.size.x * 0.5 + pad and absf(p.y - b.pos.y) < b.size.y * 0.5 + pad

func _map_audit() -> void:
	for seed_v in [1, 2, 3, 12345, 777, 4242]:
		var t0 := Time.get_ticks_msec()
		var isl := Island.new(seed_v, Game.MAP_SIZE)
		isl.generate()
		var ms := Time.get_ticks_msec() - t0
		var b_water := 0
		var b_overlap := 0
		var b_road := 0
		var loot_deep := 0
		var loot_outside := 0
		var trees_in := 0
		var rocks_in := 0
		var steep := 0
		for i in isl.buildings.size():
			var b: Dictionary = isl.buildings[i]
			var h: Vector2 = b.size * 0.5
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var p: Vector2 = b.pos + c * h
				if isl.height_at(p.x, p.y) < Island.WATER + 0.2:
					b_water += 1
					break
			# Ground under the footprint should be flat close to the floor height.
			var hmin := 1e9
			var hmax := -1e9
			for k in 9:
				var p2: Vector2 = b.pos + Vector2((k % 3 - 1) * h.x * 0.9, (k / 3 - 1) * h.y * 0.9)
				var hh: float = isl.height_at(p2.x, p2.y)
				hmin = minf(hmin, hh)
				hmax = maxf(hmax, hh)
			if hmax - hmin > 1.0 or absf(hmax - float(b.floor)) > 1.2: steep += 1
			for j in range(i + 1, isl.buildings.size()):
				var o: Dictionary = isl.buildings[j]
				if absf(b.pos.x - o.pos.x) < (b.size.x + o.size.x) * 0.5 and absf(b.pos.y - o.pos.y) < (b.size.y + o.size.y) * 0.5:
					b_overlap += 1
			if isl.near_road(b.pos, 0.0): b_road += 1
		for s in isl.loot_spots:
			if isl.is_deep(s.pos.x, s.pos.y): loot_deep += 1
			var inside := false
			for b in isl.buildings:
				if _in_rect(s.pos, b, 0.0): inside = true
			if not inside: loot_outside += 1
		for t in isl.trees:
			for b in isl.buildings:
				if _in_rect(t.pos, b, 0.5):
					trees_in += 1
					break
		for r in isl.rocks:
			for b in isl.buildings:
				if _in_rect(r.pos, b, r.r):
					rocks_in += 1
					break
		var land := 0
		for k in 4000:
			var p := Vector2(randf(), randf()) * isl.size
			if isl.is_land(p.x, p.y): land += 1
		print("MAP seed=%d gen=%dms towns=%d buildings=%d loot=%d trees=%d rocks=%d land=%d%% | in_water=%d uneven=%d overlap=%d on_road=%d loot_deep=%d loot_outside=%d trees_in_bld=%d rocks_in_bld=%d" % [
			seed_v, ms, isl.towns.size(), isl.buildings.size(), isl.loot_spots.size(), isl.trees.size(), isl.rocks.size(), land * 100 / 4000,
			b_water, steep, b_overlap, b_road, loot_deep, loot_outside, trees_in, rocks_in])

# ---------------------------------------------------------------- match
func _match_audit() -> void:
	var tree := get_tree()
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	var t0 := Time.get_ticks_msec()
	for i in 600:
		if world.ready_done: break
		await wait(0.1)
	print("MATCH load=%dms bots=%d pickups=%d" % [Time.get_ticks_msec() - t0, world.bots.size(), world.pickups.size()])
	var p: Player = world.player
	var bad_home := 0
	for b in world.bots:
		if b.home.distance_to(b.global_position) > 5.0: bad_home += 1
	print("BOTS home_wrong=%d" % bad_home)
	# Land the player next to a pickup inside a town.
	var it: Node3D = world.pickups[0]
	for q in world.pickups:
		if q.get_meta("data").kind == "weapon" and q.get_meta("data").id in ["m416", "akm"]:
			it = q
			break
	p.jump_from_plane()
	p.global_position = it.global_position + Vector3(0, 6, 0)
	for i in 80:
		if p.state == "ground": break
		await wait(0.1)
	print("LAND state=%s dist_to_item=%.1f y=%.2f ground=%.2f" % [p.state, p.global_position.distance_to(it.global_position), p.global_position.y, world.ground_height(p.global_position)])
	p.global_position = it.global_position + Vector3(0, 0.2, 0)
	await wait(0.3)
	var n_before: int = world.pickups.size()
	p.interact()
	await wait(0.2)
	print("PICKUP slot0=%s pickups %d->%d" % [str(p.slots[0]), n_before, world.pickups.size()])
	if p.slots[0] == null: p.give_weapon("m416", 30)
	p.ammo["556"] = 120
	p.ammo["762"] = 120
	p.slots[p.active].mag = 30
	# Engagement test: open ground, a bot 30 m away facing the player.
	var spot := Vector3.ZERO
	for k in 400:
		var q: Vector2 = Vector2(randf(), randf()) * world.island.size
		if world.island.is_land(q.x, q.y) and not world.island.is_deep(q.x, q.y) and not world._in_building(q, 40.0) and world.island.height_at(q.x, q.y) > 3.0:
			spot = Vector3(q.x, world.island.height_at(q.x, q.y) + 0.3, q.y)
			break
	p.global_position = spot
	p.global_position = spot
	await wait(0.4)
	# Shooting test: put a bot 15 m in front of the player in the open.
	var bot: Bot = world.bots[0]
	var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	var bp := p.global_position + fwd * 15.0
	bot.global_position = Vector3(bp.x, world.ground_height(bp) + 0.2, bp.z)
	bot.set_physics_process(false)
	await wait(0.3)
	var to_b: Vector3 = bot.global_position + Vector3(0, 1.2, 0) - p.camera.global_position
	p.yaw = atan2(-to_b.x, -to_b.z)
	p.pitch = asin(clampf(to_b.normalized().y, -1, 1))
	await wait(0.3)
	var hp0 := bot.health
	p.firing = true
	await wait(0.5)
	p.firing = false
	print("SHOOT bot hp %.0f -> %.0f dead=%s mag=%d player_kills=%d" % [hp0, bot.health, bot.dead, p.slots[p.active].mag, p.kills])
	await shot("audit_shoot")
	bot.set_physics_process(true)
	var b2: Bot = world.bots[2]
	var bpos := spot + Vector3(30, 0, 0)
	b2.global_position = Vector3(bpos.x, world.ground_height(bpos) + 0.3, bpos.z)
	b2.home = b2.global_position
	b2.yaw = atan2(-(spot.x - bpos.x), -(spot.z - bpos.z))
	var hp_e := p.health
	var seen := false
	for i in 40:
		await wait(0.1)
		if (b2.target == p): seen = true
	print("ENGAGE bot_sees=%s player_hp %.0f -> %.0f bot_mag=%d" % [seen, hp_e, p.health, b2.mag])
	p.health = 100.0
	# Let the match run, watching bots, health, performance and node count.
	var start_pos := {}
	for b in world.bots: start_pos[b] = b.global_position
	var nodes0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var hp_start := p.health
	var fps_sum := 0.0
	var fps_n := 0
	var bot_shots_seen := 0
	for i in 30:
		await wait(1.0)
		fps_sum += Engine.get_frames_per_second()
		fps_n += 1
		for b in world.bots:
			if b.target == p: bot_shots_seen += 1
		if p.state == "dead": break
	var stuck := 0
	var underground := 0
	var in_deep := 0
	var alive := 0
	for b in world.bots:
		if b.dead: continue
		alive += 1
		if b.global_position.distance_to(start_pos[b]) < 3.0: stuck += 1
		if b.global_position.y < world.ground_height(b.global_position) - 1.0: underground += 1
		if world.is_deep(b.global_position): in_deep += 1
	print("RUN30 fps_avg=%.1f nodes %d->%d player_hp %.0f->%.0f state=%s bots_alive=%d stuck=%d underground=%d deep=%d sees_player_samples=%d alive_count=%d" % [
		fps_sum / fps_n, nodes0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), hp_start, p.health, p.state, alive, stuck, underground, in_deep, bot_shots_seen, world.alive_count()])
	await shot("audit_run")
	# Keys: B opens the bag, Ctrl frees the cursor.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for k in [KEY_B, KEY_CTRL]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = true
		Input.parse_input_event(ev)
		await wait(0.1)
		ev = ev.duplicate()
		ev.pressed = false
		Input.parse_input_event(ev)
		await wait(0.1)
	print("KEYS bag_open=%s mouse=%d cursor_free=%s" % [world.hud.bag_open, Input.mouse_mode, Game.cursor_free])
	# Pause / Ctrl / bag sanity.
	world.hud.toggle_pause()
	await wait(0.2)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await wait(0.2)
	print("PAUSE then Esc: paused=%s" % tree.paused)
	if tree.paused: world.hud.toggle_pause()
	# Death -> results -> lobby.
	if p.state != "dead":
		p.take_damage(1000.0, world.bots[1])
	await wait(0.5)
	print("DEATH state=%s match_over=%s results=%s reward=%s" % [p.state, world.match_over, world.hud.results != null, str(Game.last_reward)])
	await shot("audit_results")
	world.hud._to_lobby()
	await wait(2.0)
	print("BACK scene=%s mouse=%d" % [tree.current_scene.name if tree.current_scene else "null", Input.mouse_mode])
	await shot("audit_lobby_after")
