extends Node
## Feet on the ground: standing across a slope, each foot sits on the ground
## under it (not floating, not sunk); pictures from the side with it off and on.

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
	_run.call_deferred()

## Height of each foot (ankle) above the ground under it.
func foot_gaps(world, m: HumanModel) -> Array:
	var r := []
	for side in ["Left", "Right"]:
		var fp: Vector3 = m.sk.global_transform * m.sk.get_bone_global_pose(m._bone[side + "Foot"]).origin
		# The real surface under the foot (a rock counts as ground too).
		var q := PhysicsRayQueryParameters3D.create(fp + Vector3(0, 1.5, 0), fp - Vector3(0, 3.0, 0), 1)
		var hit: Dictionary = m.get_world_3d().direct_space_state.intersect_ray(q)
		r.append(fp.y - (hit.position.y if hit else world.island.height_at(fp.x, fp.z)))
	return r

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
	# A dry, open slope of about 20-28 degrees.
	var spot := Vector2.ZERO
	var dirv := Vector2.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 40000:
		var q := Vector2(rng.randf_range(600, isl.size - 600), rng.randf_range(600, isl.size - 600))
		var h: float = isl.height_at(q.x, q.y)
		if h < 3.0: continue
		var gx: float = (isl.height_at(q.x + 1.0, q.y) - isl.height_at(q.x - 1.0, q.y)) * 0.5
		var gz: float = (isl.height_at(q.x, q.y + 1.0) - isl.height_at(q.x, q.y - 1.0)) * 0.5
		var g := Vector2(gx, gz).length()
		var clear := true
		for r in isl.rocks:
			if q.distance_to(r.pos) < r.r * 1.5 + 6.0:
				clear = false
				break
		if g > 0.36 and g < 0.53 and not isl.near_road(q, 12.0) and clear:
			spot = q
			dirv = Vector2(gx, gz).normalized()
			break
	check("found a slope", spot != Vector2.ZERO)
	# Stand side-on to the slope: one foot uphill, one downhill.
	p.global_position = Vector3(spot.x, isl.height_at(spot.x, spot.y) + 0.6, spot.y)
	p.yaw = atan2(-dirv.y, dirv.x)    # facing across the slope
	var cam := Camera3D.new()
	world.add_child(cam)
	await wait(1.5)
	var pp := p.global_position
	var fwd := Vector3(-sin(p.model.rotation.y), 0, -cos(p.model.rotation.y))
	cam.global_position = pp + fwd * 3.2 + Vector3(0, 1.0, 0)
	cam.look_at(pp + Vector3(0, 0.7, 0))
	cam.current = true
	world.hud.visible = false
	p.model.foot_ik = false
	p.set_physics_process(false)
	for i in 10:
		p.model.set_pose("stand", 0.0, true, 0.05, 0.0)
		await get_tree().process_frame
	var off := foot_gaps(world, p.model)
	await shot("feet_off")
	for i in 30:
		p.model.foot_ik = true
		p.model.set_pose("stand", 0.0, true, 0.05, 0.0)
		await get_tree().physics_frame
	var on := foot_gaps(world, p.model)
	await shot("feet_on")
	print("GAPS off %.2f %.2f   on %.2f %.2f" % [off[0], off[1], on[0], on[1]])
	check("both feet on the ground", absf(on[0] - on[1]) < 0.08 and maxf(on[0], on[1]) < 0.22 and minf(on[0], on[1]) > -0.05, "%.2f %.2f" % [on[0], on[1]])
	# Flat ground: nothing changes.
	var town: Vector2 = isl.towns[0].pos
	p.set_physics_process(true)
	p.global_position = Vector3(town.x + 20, isl.height_at(town.x + 20, town.y) + 0.6, town.y)
	await wait(1.0)
	p.set_physics_process(false)
	for i in 20:
		p.model.foot_ik = true
		p.model.set_pose("stand", 0.0, true, 0.05, 0.0)
		await get_tree().physics_frame
	check("flat ground: hips stay", absf(p.model._hip_drop) < 0.04, "%.3f" % p.model._hip_drop)
	print("FEET TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	tree.quit()
