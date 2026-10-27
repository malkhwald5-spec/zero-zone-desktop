extends SceneTree
## Run: put the Mixamo FBX files (without skin, 30 fps) in assets/incoming/, then
## godot --headless --path godot -s res://tools/retarget_mixamo.gd
## Retargets Mixamo FBX animations (metres, Y up) onto the soldier's skeleton
## (centimetres, rotated parent) using world-space rotation deltas from the
## T-pose rest, and saves an AnimationLibrary.

## Animation name -> FBX file name in assets/incoming/ (missing files are skipped;
## animations already in the library are kept).
const SRC := {"aim_idle": "rifle_aiming_idle", "fire": "firing_rifle", "reload": "reloading",
	"rifle_run": "rifle_run", "walk": "walking", "fall": "Falling", "skydive": "skydive",
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
	"toss": "toss_grenade", "hit": "hit_reaction", "prone_fire": "prone_firing", "prone_reload": "prone_reloading",
	"prone_f": "prone_forward", "prone_stop": "prone_forward_stop", "prone_idle": "prone_idle", "crawl": "crawling",
	"kneel": "kneel", "prone_to_kneel": "rifle_prone_to_kneel", "kneel_to_prone": "rifle_kneel_to_prone",
	"turn90_l": "turn_90_left", "turn_l": "turn_left",
	"melee": "standing_melee", "pickup": "pick_up_item", "drink": "drinking",
	"swim_tread": "treading_water", "swim": "swimming", "hard_land": "hard_landing", "climb": "climbing", "drop_down": "jumping_down",
	# Pistol set (the pack's arcs and strafes come in mirrored pairs).
	"pidle": "pistol_idle", "pkneel": "pistol_kneeling_idle",
	"pwalk_f": "pistol_walk", "pwalk_b": "pistol_walk_backward", "pwalk_fr": "pistol_walk_arc", "pwalk_fl": "pistol_walk_arc_2",
	"pwalk_bl": "pistol_walk_backward_arc", "pwalk_br": "pistol_walk_backward_arc_2",
	"prun_f": "pistol_run", "prun_b": "pistol_run_backward", "prun_fr": "pistol_run_arc", "prun_fl": "pistol_run_arc_2",
	"prun_bl": "pistol_run_backward_arc", "prun_br": "pistol_run_backward_arc_2", "pstrafe_l": "pistol_strafe", "pstrafe_r": "pistol_strafe_2",
	# Empty hands (Mixamo Locomotion Pack and single clips, files renamed u_*).
	# Walking, running and sprinting empty-handed: real people (CMU motion
	# capture, one whole stride each, see tools/bvh2glb.py "loop").
	"u_walk": "cmu_16_21", "u_run": "cmu_16_46", "u_sprint": "cmu_09_06", "u_idle": "cmu_111_28", "u_back": "u_walking_backwards",
	"u_walk_l": "u_strafe_walk_left", "u_walk_r": "u_strafe_walk_right", "u_run_l": "u_strafe_run_left", "u_run_r": "u_strafe_run_right",
	"u_jump": "u_jump",
	# Weapon switching, pistol, prone death, door, second throw, vault.
	"draw": "grab_and_put_back_rifle", "holster": "put_back_rifle_behind_shoulder",
	"preload": "pistol_reload", "pfire": "pistol_shooting", "pgunplay": "gunplay",
	"prone_death": "prone_death", "door": "opening", "toss2": "throw_grenade", "vault": "jumping_over_into_combat",
	# Vehicles, ladders, reviving a teammate.
	"drive": "driving", "sit": "sitting_idle", "car_enter": "entering_car", "ladder": "climbing_ladder", "revive": "kneel_1",
	# Round 3: out of the car, up a high wall, fists, a second drink, looking
	# the gun over, water, and the lobby / celebration moves.
	"car_exit": "exiting_car", "wall_climb": "sprint_to_wall_climb", "punch": "punching_bag", "drink2": "drinking_1",
	"inspect": "inspecting", "swim_tread2": "treading_water_1", "swim_edge": "swimming_to_edge",
	"salute": "salute", "dance_hiphop": "hip_hop_dancing", "dance_break": "breakdance_freeze_var_4",
	"rifle_idle": "rifle_idle", "victory": "victory_idle",
	# Standing about: looking round, an easy relaxed idle.
	"look_around": "look_around", "happy_idle": "happy_idle",
	# Upright rifle locomotion for the blended movement (see LocoBlend):
	# walking, strafing and running with the gun held up, starts, stops, turns.
	"r_walk_f": "rifle_walking", "r_walk_b": "backwards_rifle_walk", "r_strafe_l": "strafe_left", "r_strafe_r": "strafe_right",
	"r_run_f": "rifle_run_upright", "r_run_b": "backwards_rifle_run",
	"r_start": "rifle_start_walking", "r_stop": "rifle_walk_to_stop", "r_stop2": "rifle_stop_walking",
	"r_stop_b": "rifle_walk_backwards_stop", "r_turn_l": "rifle_turn_90_left",
	# Motion capture from the CMU Graphics Lab database (BVH converted to GLB by
	# tools/bvh2glb.py; free for any use): real people starting, stopping and
	# turning at a run, vaulting and diving.
	"c_run_start": "cmu_104_53", "c_run_stop": "cmu_104_56", "c_quick_stop": "cmu_127_05",
	"c_run_vault": "cmu_127_25", "c_dive_roll": "cmu_127_23",
	# Touching down off a drop (the canopy landing), and standing at ease.
	"c_land": "cmu_82_02"}
## Made by mirroring a clip left <-> right (there is no right-hand version).
const MIRROR := {"turn90_r": "turn_90_left", "turn_r": "turn_left", "r_turn_r": "rifle_turn_90_left"}
## Played once (not looped).
const ONCE := ["jump_up", "jump_down", "toss", "hit", "death_front", "death_back", "death_right", "death_head",
	"death_back_head", "death_crouch", "death_walk", "prone_stop", "hard_land", "climb", "drop_down",
	"kneel", "prone_to_kneel", "kneel_to_prone", "turn90_l", "turn90_r", "turn_l", "turn_r", "melee", "pickup", "u_jump",
	"draw", "holster", "preload", "pfire", "pgunplay", "prone_death", "door", "toss2", "vault", "car_enter",
	"car_exit", "wall_climb", "swim_edge", "salute", "r_start", "r_stop", "r_stop2", "r_stop_b", "r_turn_l", "r_turn_r",
	"c_run_start", "c_run_stop", "c_quick_stop", "c_run_vault", "c_dive_roll", "c_land"]
## Old names replaced by the 8-way set.
const DROP := ["strafe_a", "strafe_b", "crouch_fwd", "crouch_right", "crouch_left",
	"c_run_turn_l", "c_run_turn_r", "c_jog_start", "c_jog_stop", "c_sudden_stop", "c_hang"]
var OUT := "res://assets/anims/mixamo_anims.res"
## Character to retarget onto (-- --target=res://... --out=res://... [--only=key1,key2]).
var TARGET := "res://assets/models/soldier.glb"
const FPS := 30.0
var _yaw0 := Quaternion.IDENTITY
var _yaw1 := Quaternion.IDENTITY

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
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--target="): TARGET = a.substr(9)
		if a.begins_with("--out="): OUT = a.substr(6)
		if a.begins_with("--only="): only = a.substr(7).split(",")
	var sol: Node3D = load(TARGET).instantiate()
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
	for key in SRC.keys() + MIRROR.keys():
		var mirror := MIRROR.has(key)
		var path := "res://assets/incoming/%s.fbx" % (MIRROR[key] if mirror else SRC[key])
		if not ResourceLoader.exists(path): path = path.get_basename() + ".glb"
		if not ResourceLoader.exists(path) or (only.size() > 0 and not key in only): continue
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
		# Some downloads number the rig ("mixamorig12:Hips"): match by plain name.
		var sbones := {}
		for j in ssk.get_bone_count():
			var nm := ssk.get_bone_name(j)
			var k := nm.find("_")
			if nm.begins_with("mixamorig") and k > 0: nm = "mixamorig_" + nm.substr(k + 1)
			sbones[nm] = j
		var hips_s: int = sbones.get("mixamorig_Hips", -1)
		var s_h := ssk.get_bone_rest(hips_s).origin.y
		# Some rigs have an extra root joint above the hips: work on the hips bone.
		var t_hips := tsk.find_bone("mixamorig_Hips")
		var t_hips_g := tsk.get_bone_global_rest(t_hips)
		var t_hips_p := tsk.get_bone_global_rest(tsk.get_bone_parent(t_hips)) if tsk.get_bone_parent(t_hips) >= 0 else Transform3D()
		var t_h := (C * (t_hips_g.origin * t_scale)).y
		var ratio := t_h / s_h
		var out := Animation.new()
		out.length = src.length
		out.loop_mode = Animation.LOOP_NONE if key in ONCE else Animation.LOOP_LINEAR
		# Map target bone -> source bone index by name.
		var map := {}
		for i in tsk.get_bone_count():
			var bn := tsk.get_bone_name(i)
			if mirror: bn = bn.replace("Left", "#").replace("Right", "Left").replace("#", "Right")
			var j: int = sbones.get(bn, -1)
			if j >= 0: map[i] = j
		# Limbs posed differently at rest (some rigs stand with bent elbows):
		# turn each limb bone of the target to point like the source's at
		# rest first, so the moves start from the same pose.
		var fix := {}
		for pair in [["LeftArm", "LeftForeArm"], ["LeftForeArm", "LeftHand"], ["RightArm", "RightForeArm"], ["RightForeArm", "RightHand"],
				["LeftUpLeg", "LeftLeg"], ["LeftLeg", "LeftFoot"], ["RightUpLeg", "RightLeg"], ["RightLeg", "RightFoot"]]:
			var ti := tsk.find_bone("mixamorig_" + pair[0])
			var tc := tsk.find_bone("mixamorig_" + pair[1])
			if ti < 0 or tc < 0 or not map.has(ti) or not map.has(tc): continue
			var sd: Vector3 = ssk.get_bone_global_rest(map[tc]).origin - ssk.get_bone_global_rest(map[ti]).origin
			if mirror: sd.x = -sd.x
			var want: Vector3 = (C.inverse() * (Q * sd)).normalized()
			var have: Vector3 = (tsk.get_bone_global_rest(tc).origin - tsk.get_bone_global_rest(ti).origin).normalized()
			if have.angle_to(want) > deg_to_rad(15.0): fix[ti] = Quaternion(have, want)
		var rot_tracks := {}
		for i in map:
			var tr := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(tr, NodePath(tpath + ":" + tsk.get_bone_name(i)))
			rot_tracks[i] = tr
		var pos_tr := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(pos_tr, NodePath(tpath + ":" + tsk.get_bone_name(t_hips)))
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
				if mirror: d = Quaternion(d.x, -d.y, -d.z, d.w)          # reflected across the body's mid plane
				var dw: Quaternion = Q * d * Q.inverse()                 # in target model frame
				var dt: Quaternion = C.inverse() * dw * C                # in target skeleton space
				tg[i] = dt * (fix[i] * t_rest_g[i] if fix.has(i) else t_rest_g[i])
			for i in map:
				var p := tsk.get_bone_parent(i)
				var loc: Quaternion = (tg[p].inverse() * tg[i]) if p >= 0 else tg[i]
				out.rotation_track_insert_key(rot_tracks[i], t, loc.normalized())
			# Hips position: in place (no forward drift), height scaled to the soldier.
			var hp := ssk.get_bone_rest(hips_s).origin
			var ht := src.find_track(NodePath(spath + ":" + ssk.get_bone_name(hips_s)), Animation.TYPE_POSITION_3D)
			if ht >= 0: hp = src.position_track_interpolate(ht, t)
			if f == 0:
				start_pos = hp
				_yaw0 = sg[hips_s]
			_yaw1 = sg[hips_s]
			end_pos = hp
			var rest_w := C * (t_hips_g.origin * t_scale)
			var w := Q * (Vector3(0, hp.y, 0) * ratio)
			w = Vector3(rest_w.x, w.y, rest_w.z)
			out.position_track_insert_key(pos_tr, t, t_hips_p.affine_inverse() * (C.inverse() * w / t_scale))
		var drift := Q * (end_pos - start_pos) * ratio
		# Ground speed of the clip (m/s): used to match steps to the real speed.
		out.set_meta("speed", Vector2(drift.x, drift.z).length() / maxf(src.length, 0.01))
		var turn_deg := rad_to_deg((_yaw1 * _yaw0.inverse()).get_euler().y)
		if mirror: turn_deg = -turn_deg
		print(key, " len=%.2f frames=%d drift=%s ratio=%.2f turn=%.0f" % [src.length, frames, str(drift.snapped(Vector3.ONE * 0.01)), ratio, turn_deg])
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
	var foot := _find_any(sk, "LeftFoot")
	var toe := _find_any(sk, "LeftToeBase")
	var v: Vector3 = C * (g[toe].origin - g[foot].origin)
	v.y = 0.0
	return v.normalized()

## A bone by its plain Mixamo name, whatever the rig's prefix ("mixamorig12_").
func _find_any(sk: Skeleton3D, plain: String) -> int:
	var i := sk.find_bone("mixamorig_" + plain)
	if i >= 0: return i
	for j in sk.get_bone_count():
		var nm := sk.get_bone_name(j)
		if nm.begins_with("mixamorig") and nm.ends_with("_" + plain): return j
	return -1
