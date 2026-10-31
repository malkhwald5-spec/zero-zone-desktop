extends Node
## Freefall pose numbers (headless): where the hands and feet sit against the
## body's own axes (along the spine, across the shoulders, towards the belly).
func _ready() -> void:
	Game.spawn_island = false
	Game.settings.controls = "touch"
	_run.call_deferred()

func _axes(m: HumanModel) -> Array:
	var sk: Skeleton3D = m.sk
	var to_m: Transform3D = m.global_transform.affine_inverse() * sk.global_transform
	var b: Dictionary = m._bone
	var hips: Vector3 = to_m * sk.get_bone_global_pose(b["Hips"]).origin
	var ls: Vector3 = to_m * sk.get_bone_global_pose(b["LeftArm"]).origin
	var rs: Vector3 = to_m * sk.get_bone_global_pose(b["RightArm"]).origin
	var up := ((ls + rs) * 0.5 - hips).normalized()
	var ac := (rs - ls).normalized()
	return [to_m, hips, up, ac, up.cross(ac).normalized() * m._belly_sign]

func _rel(m: HumanModel, bone: String) -> String:
	var a := _axes(m)
	var pos: Vector3 = a[0] * m.sk.get_bone_global_pose(m._bone[bone]).origin - a[1]
	return "%s(up %.2f across %.2f belly %.2f)" % [bone, pos.dot(a[2]), pos.dot(a[3]), pos.dot(a[4])]

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
	for i in 400:
		if world.plane_over_land(): break
		world.plane_t += 0.002
		await tree.process_frame
	p.interact()
	for phase in [["still", Vector2.ZERO, -0.3], ["glide", Vector2(0, 0.6), -0.3], ["dive", Vector2(0, 1), -1.1]]:
		p.touch_move = phase[1]
		p.pitch = phase[2]
		await tree.create_timer(2.0).timeout
		var m: HumanModel = p.model
		print("POSE %s %s %s %s %s" % [phase[0], _rel(m, "LeftFoot"), _rel(m, "RightFoot"), _rel(m, "LeftHand"), _rel(m, "RightHand")])
		print("POSE %s knees %s %s" % [phase[0], _rel(m, "LeftLeg"), _rel(m, "RightLeg")])
	tree.quit()
