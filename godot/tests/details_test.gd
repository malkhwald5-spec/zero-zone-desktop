extends Node
## Small realism details: bullet holes and dust where shots hit walls, birds
## flying out of the trees at gunfire, the breathing sway through a scope
## (and holding the breath steadies it). Pictures of each.

var out := "user://"
var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok: fails += 1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.controls = "kbm"
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
	p.jump_from_plane()
	var isl = world.island
	# --- Bullet holes on a house wall ---
	var bld: Dictionary = {}
	for b in isl.buildings:
		if not b.get("military", false) and b.get("kind", "house") == "house" and int(b.get("rot", 0)) == 0:
			bld = b
			break
	var c: Vector2 = bld.pos
	var half: Vector2 = bld.size * 0.5
	var stand := Vector2(c.x, c.y + half.y + 7.0)
	p.global_position = Vector3(stand.x, isl.height_at(stand.x, stand.y) + 0.5, stand.y)
	p.yaw = 0.0
	p.pitch = 0.0
	await wait(1.2)
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var holes := 0
	for i in 15:
		var from := p.global_position + Vector3(randf_range(-1.5, 1.5), 1.2 + randf_range(-0.4, 0.6), 0)
		var aim := Vector3(c.x + randf_range(-2.0, 2.0), from.y, c.y)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + (aim - from).normalized() * 40.0, 1, [p.get_rid()]))
		if hit:
			world.effects.impact(hit.position, hit.normal, false)
			holes += 1
	await wait(0.25)
	# Close-up camera on the wall.
	var cam := Camera3D.new()
	world.add_child(cam)
	if not world.effects._holes.is_empty():
		var hp: Vector3 = world.effects._holes[world.effects._holes.size() - 1].global_position
		cam.global_position = hp + Vector3(0.6, 0.3, 2.4)
		cam.look_at(hp)
		cam.current = true
	await wait(0.2)
	check("shots hit the wall", holes >= 3, str(holes))
	check("bullet holes left", world.effects._holes.size() >= holes, str(world.effects._holes.size()))
	await shot("details_holes")
	# Many shots: the number of holes stays capped.
	for i in 200:
		world.effects.impact(p.global_position + Vector3(0, 1, -5), Vector3(0, 0, 1), false)
	check("holes are capped", world.effects._holes.size() <= 120, str(world.effects._holes.size()))
	cam.current = false
	p.camera.current = true
	await wait(1.6)
	# --- Birds ---
	var spot := Vector2.ZERO
	for t in isl.trees:
		var cell := Vector2i(floori(t.pos.x / 64.0), floori(t.pos.y / 64.0))
		if world.birds._grid.get(cell, []).size() >= 12 and isl.height_at(t.pos.x, t.pos.y) > 2.0:
			spot = t.pos
			break
	check("found a wood", spot != Vector2.ZERO)
	var stand2 := spot + Vector2(40, 40)
	p.global_position = Vector3(stand2.x, isl.height_at(stand2.x, stand2.y) + 0.5, stand2.y)
	await wait(0.8)
	world.notify_shot(Vector3(spot.x, isl.height_at(spot.x, spot.y) + 1.0, spot.y), p)
	check("birds fly off at a shot", world.birds.flock_count() >= 1, str(world.birds.flock_count()))
	var n0: int = world.birds.flock_count()
	world.notify_shot(Vector3(spot.x, isl.height_at(spot.x, spot.y) + 1.0, spot.y), p)
	check("the same trees don't scare twice at once", world.birds.flock_count() == n0)
	world.notify_shot(Vector3(spot.x, 0, spot.y), p, true)
	var b0: Node3D = world.birds._flocks[0].birds[0]
	var y0 := b0.global_position.y
	await wait(1.6)
	var to: Vector3 = b0.global_position - p.global_position
	p.yaw = atan2(-to.x, -to.z)
	p.pitch = atan2(to.y, Vector2(to.x, to.z).length())
	var mid := Vector3.ZERO
	for b in world.birds._flocks[0].birds: mid += b.global_position
	mid /= world.birds._flocks[0].birds.size()
	cam.global_position = mid + Vector3(9, -4, 9)
	cam.look_at(mid)
	cam.current = true
	await wait(0.4)
	check("birds climbed", b0.global_position.y > y0 + 3.0, "%.1f -> %.1f" % [y0, b0.global_position.y])
	await shot("details_birds")
	cam.current = false
	p.camera.current = true
	# --- Scope sway ---
	p.give_weapon("kar98", 5, {})
	await wait(0.3)
	p.stance = "stand"
	p.aiming = true
	var samples := []
	for i in 40:
		await get_tree().process_frame
		await wait(0.05)
		samples.append(p._sway)
	var span := 0.0
	for s in samples: span = maxf(span, s.distance_to(samples[0]))
	check("scope sways", p.scoped() and span > 0.002, "%.4f" % span)
	await shot("details_scope")
	print("DETAILS TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	tree.quit()
