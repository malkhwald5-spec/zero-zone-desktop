class_name LocoBlend
extends RefCounted
## Walking and running as one continuous movement: the walk and run cycles
## of the directions either side of where the body is heading are sampled
## at the same point of the stride (left foot forward at phase 0 in every
## clip) and mixed bone by bone. The stride advances by the distance
## actually covered, so the feet keep pace with the ground at any speed and
## in any direction instead of switching clips (and sliding) at thresholds.

var sk: Skeleton3D
var ap: AnimationPlayer
var cscale := 1.0
var phase_of: Callable            # Animation -> where its left foot is furthest ahead (0..1)
var phase := 0.0                  # 0..1 through the shared stride
var _clips := {}

## Directions round the body (degrees: 0 ahead, 90 right, ±180 behind) -> clip.
const ARMED_WALK := {0: "r_walk_f", 90: "r_strafe_r", -90: "r_strafe_l", 180: "r_walk_b"}
const ARMED_RUN := {0: "r_run_f", 45: "run_fr", -45: "run_fl", 90: "run_r", -90: "run_l", 180: "r_run_b"}
const EMPTY_WALK := {0: "u_walk", 90: "u_walk_r", -90: "u_walk_l", 180: "u_back"}
const EMPTY_RUN := {0: "u_run", 90: "u_run_r", -90: "u_run_l", 180: "u_back"}

func _init(skel: Skeleton3D, player: AnimationPlayer, scale: float, phase_fn: Callable) -> void:
	sk = skel
	ap = player
	cscale = scale
	phase_of = phase_fn

## Every clip the armed or empty-handed sets need is in this character's library.
func ready_for(armed: bool) -> bool:
	for dset in ([ARMED_WALK, ARMED_RUN] if armed else [EMPTY_WALK, EMPTY_RUN]):
		for k in dset:
			if not ap.has_animation("mx/" + String(dset[k])): return false
	return true

## A clip's tracks (bone per track), its stride phase, ground speed and stride length.
func clip(name: String) -> Dictionary:
	if _clips.has(name): return _clips[name]
	var a: Animation = ap.get_animation("mx/" + name)
	if a == null: return {}
	var tracks := []
	for t in a.get_track_count():
		var ty := a.track_get_type(t)
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D: continue
		var b := sk.find_bone(String(a.track_get_path(t).get_concatenated_subnames()))
		if b >= 0: tracks.append([t, b, ty == Animation.TYPE_POSITION_3D])
	var spd: float = float(a.get_meta("speed", 1.8)) * cscale
	var d := {"a": a, "len": a.length, "tracks": tracks, "ph": float(phase_of.call(a)), "spd": spd, "stride": maxf(spd * a.length, 0.3)}
	_clips[name] = d
	return d

## The two directions of `dset` either side of heading `deg`, weighted by
## how close each is (one, if it sits right on it).
static func _around(dset: Dictionary, deg: float) -> Array:
	var lo := 0
	var hi := 0
	var dlo := 999.0
	var dhi := 999.0
	for k in dset:
		var d := wrapf(deg - float(k), -180.0, 180.0)
		if d >= 0.0 and d < dlo:
			dlo = d
			lo = k
		if d <= 0.0 and -d < dhi:
			dhi = -d
			hi = k
	if lo == hi or dlo + dhi < 0.01: return [[dset[lo], 1.0]]
	return [[dset[lo], dhi / (dlo + dhi)], [dset[hi], dlo / (dlo + dhi)]]

## Works out this frame's mix for moving at `vel` (m/s, x right, y ahead)
## and steps the stride on; returns [[clip dict, weight]].
func mix(vel: Vector2, armed: bool, sprint: bool, delta: float) -> Array:
	var speed := vel.length()
	var deg := rad_to_deg(atan2(vel.x, vel.y)) if speed > 0.05 else 0.0
	var walk := _around(ARMED_WALK if armed else EMPTY_WALK, deg)
	var run_set: Dictionary = (ARMED_RUN if armed else EMPTY_RUN).duplicate()
	if sprint and absf(deg) < 30.0:
		run_set[0] = "sprint_f" if armed and ap.has_animation("mx/sprint_f") else "u_sprint"
	var run := _around(run_set, deg)
	var vw := 0.0
	var vr := 0.0
	for e in walk: vw += clip(e[0]).spd * float(e[1])
	for e in run: vr += clip(e[0]).spd * float(e[1])
	# Between the walk's own pace and the run's: how far towards running.
	var k := clampf((speed - vw) / maxf(vr - vw, 0.3), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var out := []
	var stride := 0.0
	for e in walk:
		var w := float(e[1]) * (1.0 - k)
		if w > 0.001: out.append([clip(e[0]), w])
	for e in run:
		var w := float(e[1]) * k
		if w > 0.001: out.append([clip(e[0]), w])
	for e in out: stride += float(e[0].stride) * float(e[1])
	phase = fposmod(phase + speed * delta / maxf(stride, 0.3), 1.0)
	return out

## Poses the skeleton: every clip at the shared stride point, bone by bone.
var _rot: Array[Quaternion] = []
var _pos: Array[Vector3] = []
var _rw := PackedFloat32Array()
var _pw := PackedFloat32Array()

func apply(entries: Array) -> void:
	var n := sk.get_bone_count()
	if _rot.size() != n:
		_rot.resize(n)
		_pos.resize(n)
	_rw.resize(n)
	_pw.resize(n)
	_rw.fill(0.0)
	_pw.fill(0.0)
	for e in entries:
		var c: Dictionary = e[0]
		var w: float = e[1]
		var a: Animation = c.a
		var t := fposmod(phase + float(c.ph), 1.0) * float(c.len)
		for tk in c.tracks:
			var b: int = tk[1]
			if tk[2]:
				var p: Vector3 = a.position_track_interpolate(tk[0], t)
				var s0 := _pw[b]
				_pos[b] = p if s0 == 0.0 else _pos[b].lerp(p, w / (s0 + w))
				_pw[b] = s0 + w
			else:
				var q: Quaternion = a.rotation_track_interpolate(tk[0], t)
				var s1 := _rw[b]
				_rot[b] = q if s1 == 0.0 else _rot[b].slerp(q, w / (s1 + w))
				_rw[b] = s1 + w
	for b in n:
		if _rw[b] > 0.0: sk.set_bone_pose_rotation(b, _rot[b])
		if _pw[b] > 0.0: sk.set_bone_pose_position(b, _pos[b])
