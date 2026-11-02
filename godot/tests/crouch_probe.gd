extends Node3D
## Picks the frame of the crouch-walk clip where both feet are flat and side
## by side (for the still squat).

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), "lola")
	add_child(m)
	var a: Animation = m.ap.get_animation("mx/crouch_f")
	m.ap.play("mx/crouch_f")
	m.ap.speed_scale = 0.0
	var t := 0.0
	while t < a.length:
		m.ap.seek(t, true)
		var to_m: Transform3D = m.global_transform.affine_inverse() * m.sk.global_transform
		var l: Vector3 = to_m * m.sk.get_bone_global_pose(m._bone["LeftFoot"]).origin
		var r: Vector3 = to_m * m.sk.get_bone_global_pose(m._bone["RightFoot"]).origin
		var h: Vector3 = to_m * m.sk.get_bone_global_pose(m._bone["Hips"]).origin
		print("CR t=%.2f dz=%.2f ly=%.2f ry=%.2f hips=%.2f" % [t, absf(l.z - r.z), l.y, r.y, h.y])
		t += 0.05
	print("LEN ", a.length)
	get_tree().quit()
