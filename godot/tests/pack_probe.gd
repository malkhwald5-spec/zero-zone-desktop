extends Node3D
## Where the backpack sits against the back standing, running and sprinting:
## distance from the pack's front face to the Spine2 bone (cm).
## Run: godot --headless --path godot res://tests/pack_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), "lola")
	add_child(m)
	m.set_weapon("m416")
	m.set_gear(3, 3, 3)
	var att = m.pack.get_parent().get_parent()
	print("ATT ", att, " ", att.get("bone_name"), " idx ", att.get("bone_idx"))
	for st in [["stand", 0.0, false], ["run", 5.0, false], ["sprint", 6.5, true]]:
		m.sprinting = st[2]
		m.move_local = Vector2(0, st[1])
		for f in 60:
			m.set_pose("stand", st[1], true, 1.0 / 60.0, f / 60.0)
			await get_tree().process_frame
		var sp: Transform3D = m.sk.global_transform * m.sk.get_bone_global_pose(m._bone["Spine2"])
		var pk: Vector3 = m.pack.global_position
		var local := m.global_transform.affine_inverse() * pk
		var bl := m.global_transform.affine_inverse() * sp.origin
		for bn in ["Hips", "Spine", "Spine1", "Spine2", "Neck"]:
			var g: Transform3D = m.global_transform.affine_inverse() * m.sk.global_transform * m.sk.get_bone_global_pose(m._bone[bn])
			var up := g.basis.y.normalized()
			print("  %s %s tilt=%.0f pos=%s" % [st[0], bn, rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1, 1))), g.origin])
		print("PACK %s pack(model)=%s spine2(model)=%s  d=%.1fcm" % [st[0], local, bl, pk.distance_to(sp.origin) * 100.0])
	get_tree().quit()
