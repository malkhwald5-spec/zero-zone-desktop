extends SceneTree
## Run: put the Mixamo FBX files (without skin, 30 fps) in assets/incoming/, then
## godot --headless --path godot -s res://tools/retarget_mixamo.gd
## Retargets Mixamo FBX animations (metres, Y up) onto the soldier's skeleton
## (centimetres, rotated parent) using world-space rotation deltas from the
## T-pose rest, and saves an AnimationLibrary.

## Animation name -> FBX file name in assets/incoming/ (missing files are skipped;
## animations already in the library are kept).
const SRC := {"aim_idle": "rifle_aiming_idle", "fire": "firing_rifle", "reload": "reloading",
	"rifle_run": "rifle_run", "walk": "walking", "fall": "Falling",
	# Rifle 8-way locomotion: f, fl, fr, l, r, b, bl, br.
	"walk_f": "walk_forward", "walk_fl": "walk_forward_left", "walk_fr": "walk_forward_right", "walk_l": "walk_left",
	"walk_r": "walk_right", "walk_b": "walk_backward", "walk_bl": "walk_backward_left", "walk_br": "walk_backward_right",
	"run_f": "run_forward", "run_fl": "run_forward_left", "run_fr": "run_forward_right", "run_l": "run_left",
	"run_r": "run_right", "run_b": "run_backward", "run_bl": "run_backward_left", "run_br": "run_backward_right",
	"sprint_f": "sprint_forward", "sprint_fl": "sprint_forward_left", "sprint_fr": "sprint_forward_right",
	"crouch_f": "walk_crouching_forward", "crouch_fl": "walk_crouching_forward_left", "crouch_fr": "walk_crouching_forward_right",
	"crouch_l": "walk_crouching_left", "crouch_r": "walk_crouching_right", "crouch_b": "walk_crouching_backward",
	"crouch_bl": "walk_crouching_backward_left", "crouch_br": "walk_crouching_backward_right",
	"idle": "idle", "idle_aim": "idle_aiming", "idle_crouch": "idle_crouching", "idle_crouch_aim": "idle_crouching_aiming",
	"jump_up": "jump_up", "jump_loop": "jump_loop", "jump_down": "jump_down",
	"death_front": "death_from_the_front", "death_back": "death_from_the_back", "death_right": "death_from_right",
	"death_head": "death_from_front_headshot", "death_back_head": "death_from_back_headshot",
	"death_crouch": "death_crouching_headshot_front", "death_walk": "walking_to_dying",
	"toss": "toss_grenade", "hit": "hit_reaction", "prone_fire": "prone_firing", "prone_reload": "prone_reloading"}
## Played once (not looped).
const ONCE := ["jump_up", "jump_down", "toss", "hit", "death_front", "death_back", "death_right", "death_head",
	"death_back_head", "death_crouch", "death_walk"]
## Old names replaced by the 8-way set.
const DROP := ["strafe_a", "strafe_b", "crouch_fwd", "crouch_right", "crouch_left"]
const OUT := "res://assets/anims/mixamo_anims.res"
const FPS := 30.0

func _globals(sk: Skeleton3D, local_rot: Array) -> Array:
	var g := []
	g.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		g[i] = (g[p] * local_rot[i]) if p >= 0 else local_rot[i]
	return g

func _rest_rot(sk: Skeleton3D) -> Array:
	var r := []
	for i in sk.get_bone_count(): r.append(sk.get_bone_rest(i).basis.get_rotation_quaternion())
	return r

func _init() -> void:
	var sol: Node3D = load("res://assets/models/soldier.glb").instantiate()
	var tsk: Skeleton3D = sol.find_child("Skeleton3D", true, false)
	var tpath := String(sol.get_path_to(tsk))
	# Target skeleton space -> soldier model space (rotation only) and its unit scale.
	var t_xf: Transform3D = sol.global_transform if false else Transform3D()
	var n: Node = tsk
	var chain := []
	while n != sol:
		chain.push_front(n)
		n = n.get_parent()
	for c in chain: t_xf = t_xf * (c as Node3D).transform
	var C := t_xf.basis.orthonormalized().get_rotation_quaternion()
	var t_scale := t_xf.basis.get_scale().x
	var t_rest := _rest_rot(tsk)
	var t_rest_g := _globals(tsk, t_rest)
	var lib: AnimationLibrary = load(OUT) if ResourceLoader.exists(OUT) else AnimationLibrary.new()
	for k in DROP:
		if lib.has_animation(k): lib.remove_animation(k)
	for key in SRC:
		var path := "res://assets/incoming/%s.fbx" % SRC[key]
		if not ResourceLoader.exists(path): continue
		if lib.has_animation(key): lib.remove_animation(key)
		var sc: Node3D = load(path).instantiate()
		var ssk: Skeleton3D = sc.find_child("Skeleton3D", true, false)
		var ap: AnimationPlayer = sc.find_child("AnimationPlayer", true, false)
		# Files downloaded "with skin" also hold an empty T-pose take: use the Mixamo clip.
		var src: Animation = ap.get_animation("mixamo_com" if ap.has_animation("mixamo_com") else ap.get_animation_list()[0])
		var spath := String(sc.get_path_to(ssk))
		var s_rest := _rest_rot(ssk)
		var s_rest_g := _globals(ssk, s_rest)
		# Facing: align source forward (toe direction) with the target's.
		var fw_s := _forward(ssk, Quaternion.IDENTITY, 1.0)
		var fw_t := _forward(tsk, C, t_scale)
		var Q := Quaternion(fw_s, fw_t) if fw_s.dot(fw_t) > -0.99 else Quaternion(Vector3.UP, PI)
		var hips_s := ssk.find_bone("mixamorig_Hips")
		var s_h := ssk.get_bone_rest(hips_s).origin.y
		var t_h := (C * (tsk.get_bone_rest(0).origin * t_scale)).y
		var ratio := t_h / s_h
		var out := Animation.new()
		out.length = src.length
		out.loop_mode = Animation.LOOP_NONE if key in ONCE else Animation.LOOP_LINEAR
		# Map target bone -> source bone index by name.
		var map := {}
		for i in tsk.get_bone_count():
			var j := ssk.find_bone(tsk.get_bone_name(i))
			if j >= 0: map[i] = j
		var rot_tracks := {}
		for i in map:
			var tr := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(tr, NodePath(tpath + ":" + tsk.get_bone_name(i)))
			rot_tracks[i] = tr
		var pos_tr := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(pos_tr, NodePath(tpath + ":" + tsk.get_bone_name(0)))
		var frames := int(ceil(src.length * FPS))
		var start_pos := Vector3.ZERO
		var end_pos := Vector3.ZERO
		for f in frames + 1:
			var t := minf(f / FPS, src.length)
			var sl := s_rest.duplicate()
			for j in ssk.get_bone_count():
				var ti := src.find_track(NodePath(spath + ":" + ssk.get_bone_name(j)), Animation.TYPE_ROTATION_3D)
				if ti >= 0: sl[j] = src.rotation_track_interpolate(ti, t)
			var sg := _globals(ssk, sl)
			var tg := t_rest_g.duplicate()
			# World-space delta of each bone from its rest, moved into the target.
			for i in tsk.get_bone_count():
				if not map.has(i):
					var p := tsk.get_bone_parent(i)
					if p >= 0: tg[i] = tg[p] * t_rest[i]
					continue
				var j: int = map[i]
				var d: Quaternion = sg[j] * s_rest_g[j].inverse()        # source world delta
				var dw: Quaternion = Q * d * Q.inverse()                 # in target model frame
				var dt: Quaternion = C.inverse() * dw * C                # in target skeleton space
				tg[i] = dt * t_rest_g[i]
			for i in map:
				var p := tsk.get_bone_parent(i)
				var loc: Quaternion = (tg[p].inverse() * tg[i]) if p >= 0 else tg[i]
				out.rotation_track_insert_key(rot_tracks[i], t, loc.normalized())
			# Hips position: in place (no forward drift), height scaled to the soldier.
			var hp := ssk.get_bone_rest(hips_s).origin
			var ht := src.find_track(NodePath(spath + ":mixamorig_Hips"), Animation.TYPE_POSITION_3D)
			if ht >= 0: hp = src.position_track_interpolate(ht, t)
			if f == 0: start_pos = hp
			end_pos = hp
			var rest_w := C * (tsk.get_bone_rest(0).origin * t_scale)
			var w := Q * (Vector3(0, hp.y, 0) * ratio)
			w = Vector3(rest_w.x, w.y, rest_w.z)
			out.position_track_insert_key(pos_tr, t, C.inverse() * w / t_scale)
		var drift := Q * (end_pos - start_pos) * ratio
		# Ground speed of the clip (m/s): used to match steps to the real speed.
		out.set_meta("speed", Vector2(drift.x, drift.z).length() / maxf(src.length, 0.01))
		print(key, " len=%.2f frames=%d drift=%s ratio=%.2f" % [src.length, frames, str(drift.snapped(Vector3.ONE * 0.01)), ratio])
		lib.add_animation(key, out)
		sc.free()
	print("fw target ", _forward(tsk, C, t_scale))
	ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
	print("saved")
	quit()

func _forward(sk: Skeleton3D, C: Quaternion, s: float) -> Vector3:
	var rest := []
	for i in sk.get_bone_count(): rest.append(sk.get_bone_rest(i))
	var g := []
	g.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		g[i] = (g[p] * rest[i]) if p >= 0 else rest[i]
	var foot := sk.find_bone("mixamorig_LeftFoot")
	var toe := sk.find_bone("mixamorig_LeftToeBase")
	var v: Vector3 = C * (g[toe].origin - g[foot].origin)
	v.y = 0.0
	return v.normalized()
