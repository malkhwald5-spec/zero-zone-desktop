class_name HumanModel
extends Node3D
## Realistic animated soldier (skinned mesh with idle/walk/run animations).
## Same small API as SoldierModel (set_pose / set_gear / set_weapon / gun),
## so players and bots can use either. Poses the animations don't cover
## (rifle hold, crouch, prone, skydive, parachute, dead) are made on top of
## them with a two-bone "reach" solver for arms and legs and by tilting the body.
## The model faces -Z like the rest of the game.

const SCENE := preload("res://assets/models/soldier.glb")

var body: Node3D              # the imported model; tilted/lowered for poses
var sk: Skeleton3D
var ap: AnimationPlayer
var gun: Node3D               # procedural rifle held at chest height
var gun_body: MeshInstance3D
var gun_barrel: MeshInstance3D
var gun_mag: MeshInstance3D
var canopy: Node3D            # ram-air parachute (canopy + suspension lines)
## Skydive / parachute controls, set by the owner each frame.
var dive := 0.0               # 0 = belly to earth, 1 = head-down dive
var lean := 0.0               # roll while skydiving (-1..1)
var steer := 0.0              # parachute toggles: -1 pull left .. 1 pull right
var brake := 0.0              # parachute flare 0..1
var chute_open := 1.0         # 0 = just pulled (bunched up) .. 1 = fully open
var helmet: MeshInstance3D
var pack: MeshInstance3D
var _helmet_att: BoneAttachment3D
var _pack_att: BoneAttachment3D
var _has_weapon := false
var _anim := ""
var _bone := {}
var _wave := 0.0
var _skel_scale := 0.01
var _mats := {}

func _init(clothes: Color = Color("4a5d6b"), chute_color: Color = Color("c84f3a"), _pants: Color = Color("33373d")) -> void:
	body = SCENE.instantiate()
	add_child(body)
	sk = body.find_child("Skeleton3D", true, false)
	ap = body.get_node("AnimationPlayer")
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for a in ["Idle", "Walk", "Run"]:
		ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_skel_scale = sk.get_parent().scale.x
	for i in sk.get_bone_count():
		_bone[sk.get_bone_name(i).replace("mixamorig_", "")] = i
	# Tint the uniform with the outfit colour (keeps the texture detail).
	for mi in sk.get_children():
		if mi is MeshInstance3D and mi.mesh:
			var m: Material = mi.mesh.surface_get_material(0)
			if m is StandardMaterial3D:
				var t: StandardMaterial3D = m.duplicate()
				t.albedo_color = Color.WHITE.lerp(clothes, 0.55)
				mi.material_override = t
	_build_gun()
	_build_gear()
	canopy = Node3D.new()
	canopy.position.y = RISER_Y
	canopy.visible = false
	add_child(canopy)
	var cmi := MeshInstance3D.new()
	cmi.mesh = chute_mesh(chute_color)
	cmi.position.y = -RISER_Y
	canopy.add_child(cmi)
	var lmi := MeshInstance3D.new()
	lmi.mesh = _lines_mesh()
	lmi.position.y = -RISER_Y
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	canopy.add_child(lmi)
	_play("Idle", 1.0)
	ap.advance(randf() * 1.5)

func _mat(key: String, c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]

# ---------------------------------------------------------------- parachute
const RISER_Y := 1.5          # where the risers meet the harness (model space)
const CANOPY_Y := 6.7         # top of the canopy arc
const ARC_R := 7.5            # canopy arc radius (span about 7 m)
const CELLS := 9
const CHORD := 3.0

static var _chute_cache := {}
static var _lines: ArrayMesh

## Point on the canopy: rib station i (0..CELLS), chord position u (0 = front),
## h = height above the canopy's mid-surface (top > 0, bottom < 0).
static func _canopy_pt(i: float, u: float, h: float) -> Vector3:
	var phi := lerpf(-0.5, 0.5, i / CELLS)
	var n := Vector3(sin(phi), cos(phi), 0.0)
	var camber := 0.12 * sin(u * PI)
	return Vector3(ARC_R * sin(phi), CANOPY_Y + ARC_R * (cos(phi) - 1.0), -CHORD * 0.5 + CHORD * u) + n * (h + camber)

static func _top(u: float) -> float: return 1.15 * (sqrt(u) - u)
static func _bottom(u: float) -> float: return -0.3 * (sqrt(u) - u) - 0.1 * (1.0 - u) * (1.0 - u)

## Rectangular ram-air canopy with open cells and ribs, striped like PUBG chutes.
static func chute_mesh(col: Color) -> ArrayMesh:
	var key := col.to_html()
	if _chute_cache.has(key): return _chute_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var us := [0.03, 0.08, 0.16, 0.26, 0.38, 0.52, 0.68, 0.84, 1.0]
	var stripe := col.lightened(0.55)
	for c in CELLS:
		var cc: Color = col if c % 2 == 0 else stripe
		if c == CELLS / 2: cc = Color(0.95, 0.95, 0.92)
		for k in us.size() - 1:
			var u0: float = us[k]
			var u1: float = us[k + 1]
			# Top skin, bottom skin (darker).
			for side in [[1.0, cc], [-1.0, cc.darkened(0.3)]]:
				var f := func(i: float, u: float) -> Vector3: return _canopy_pt(i, u, _top(u) if side[0] > 0 else _bottom(u))
				var a: Vector3 = f.call(c, u0)
				var b: Vector3 = f.call(c + 1, u0)
				var d: Vector3 = f.call(c + 1, u1)
				var e: Vector3 = f.call(c, u1)
				st.set_color(side[1])
				for v in ([a, b, d, a, d, e] if side[0] > 0 else [a, d, b, a, e, d]):
					st.add_vertex(v)
		# Rib wall between cells.
	for i in CELLS + 1:
		for k in us.size() - 1:
			var u0: float = us[k]
			var u1: float = us[k + 1]
			st.set_color(col.darkened(0.15))
			var a := _canopy_pt(i, u0, _top(u0))
			var b := _canopy_pt(i, u1, _top(u1))
			var d := _canopy_pt(i, u1, _bottom(u1))
			var e := _canopy_pt(i, u0, _bottom(u0))
			for v in [a, b, d, a, d, e]:
				st.add_vertex(v)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.75
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.backlight_enabled = true
	m.backlight = Color(0.35, 0.35, 0.35)
	st.set_material(m)
	var mesh := st.commit()
	_chute_cache[key] = mesh
	return mesh

## Suspension lines from the canopy's underside down to the two risers.
static func _lines_mesh() -> ArrayMesh:
	if _lines: return _lines
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in CELLS + 1:
		var riser := Vector3(-0.22 if i < (CELLS + 1) / 2 else 0.22, RISER_Y + 0.6, 0.0)
		for u in [0.1, 0.4, 0.75]:
			st.add_vertex(_canopy_pt(i, u, _bottom(u)))
			st.add_vertex(riser)
	for x in [-0.22, 0.22]:
		st.add_vertex(Vector3(x, RISER_Y + 0.6, 0.0))
		st.add_vertex(Vector3(x * 0.8, RISER_Y, 0.04))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.12, 0.12, 0.12)
	st.set_material(m)
	_lines = st.commit()
	return _lines

func _build_gun() -> void:
	gun = Node3D.new()
	body.add_child(gun)
	var gm := _mat("gun", Color("1f2124"), 0.35, 0.6)
	gun_body = MeshInstance3D.new()
	gun_body.mesh = SoldierModel._mesh("gunbody")
	gun_body.material_override = gm
	gun.add_child(gun_body)
	gun_barrel = MeshInstance3D.new()
	gun_barrel.mesh = SoldierModel._mesh("barrel")
	gun_barrel.material_override = gm
	gun_barrel.rotation.x = PI / 2
	gun.add_child(gun_barrel)
	gun_mag = MeshInstance3D.new()
	gun_mag.mesh = SoldierModel._mesh("mag")
	gun_mag.material_override = gm
	gun_mag.position = Vector3(0, -0.11, -0.1)
	gun.add_child(gun_mag)
	gun.visible = false

## Helmet and backpack follow the head and upper back bones.
func _build_gear() -> void:
	_helmet_att = BoneAttachment3D.new()
	_helmet_att.bone_name = sk.get_bone_name(_bone.Head)
	sk.add_child(_helmet_att)
	helmet = MeshInstance3D.new()
	helmet.mesh = SoldierModel._mesh("helmet")
	helmet.scale = Vector3.ONE / _skel_scale * 1.08
	helmet.position = Vector3(0, 7.5, 0.8)
	helmet.material_override = _mat("helmet", Color("5a7a4a"), 0.5)
	_helmet_att.add_child(helmet)
	_pack_att = BoneAttachment3D.new()
	_pack_att.bone_name = sk.get_bone_name(_bone.Spine2)
	sk.add_child(_pack_att)
	pack = MeshInstance3D.new()
	pack.mesh = SoldierModel._mesh("pack")
	pack.scale = Vector3.ONE / _skel_scale * Vector3(0.9, 0.95, 0.95)
	pack.position = Vector3(0, 4.0, -15.0)
	pack.material_override = _mat("pack", Color("5a4a2e"), 0.9)
	_pack_att.add_child(pack)

func set_weapon(cls: String) -> void:
	_has_weapon = cls != ""
	gun.visible = _has_weapon
	if cls == "": return
	var len := {"pistol": 0.25, "smg": 0.5, "shotgun": 0.8, "ar": 0.85, "dmr": 0.95, "sr": 1.1, "lmg": 0.95}.get(cls, 0.8) as float
	gun_body.scale = Vector3(1, 1, len * 0.6)
	gun_body.position.z = -len * 0.1
	gun_barrel.scale = Vector3(1, len * 0.55, 1)
	gun_barrel.position.z = -len * 0.55
	gun_mag.visible = cls != "shotgun" and cls != "sr"

func set_gear(_vest: int, helmet_lvl: int, pack_lvl: int) -> void:
	helmet.visible = helmet_lvl > 0
	pack.visible = pack_lvl > 0
	if helmet_lvl > 0: helmet.material_override = _mat("helmet%d" % helmet_lvl, [Color.WHITE, Color("a8a27c"), Color("5a7a4a"), Color("1e1e1e")][helmet_lvl], 0.5)
	if pack_lvl > 0: pack.material_override = _mat("pack%d" % pack_lvl, [Color.WHITE, Color("7a6648"), Color("5a5a3c"), Color("3a3a32")][pack_lvl], 0.9)

## Lobby emote.
func wave(seconds: float) -> void:
	_wave = seconds

func _play(name: String, speed_scale: float) -> void:
	if _anim != name:
		ap.play(name, 0.2)
		_anim = name
	ap.speed_scale = speed_scale

## pose: "stand" | "crouch" | "prone" | "fall" | "chute" | "dead"
func set_pose(pose: String, speed: float, armed: bool, delta: float, t: float) -> void:
	# Base animation: walk/run cycle from the ground speed.
	if pose in ["stand", "crouch"] and speed > 0.3:
		if speed > 4.0 and pose == "stand": _play("Run", speed / 5.2)
		else: _play("Walk", speed / (1.5 if pose == "stand" else 1.0))
	elif pose == "prone" and speed > 0.3:
		_play("Walk", speed / 0.8)
	else:
		_play("Idle", 1.0)
	ap.advance(delta)
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	canopy.visible = pose == "chute"
	if canopy.visible:
		var e := ease(clampf(chute_open, 0.0, 1.0), 0.4)
		canopy.scale = Vector3(lerpf(0.12, 1.0, e), lerpf(0.3, 1.0, e), lerpf(0.35, 1.0, e))
	gun.visible = _has_weapon and pose in ["stand", "crouch", "prone"]
	gun.position = Vector3(0.13, 1.33, -0.32)
	gun.rotation = Vector3.ZERO
	match pose:
		"crouch":
			body.position.y = -0.48
			gun.position.y += 0.06
			_leg("Left", Vector3(-0.14, 0.05, -0.32))
			_leg("Right", Vector3(0.16, 0.05, 0.18))
		"prone":
			# Lying face down; the walk cycle becomes a crawl. The rifle lies in
			# front of the face, still pointing forward.
			body.rotation.x = -PI / 2
			body.position = Vector3(0, 0.22, 0.9)
			gun.position = Vector3(0.13, 1.45, 0.12)
			gun.rotation.x = PI / 2
		"dead":
			body.rotation.x = PI / 2
			body.position = Vector3(0, 0.25, -0.9)
			_arm("Left", Vector3(-0.8, 1.5, 0.2), Vector3(0, 0, 1))
			_arm("Right", Vector3(0.8, 1.5, 0.2), Vector3(0, 0, 1))
		"fall":
			# Belly to earth (arms and legs spread) blending into a head-down
			# dive (arms along the body, legs together). Turned about the hips.
			var d := clampf(dive, 0.0, 1.0)
			body.rotation = Vector3(lerpf(-PI / 2 + 0.25, -PI * 0.86, d), 0.0, -lean * 0.5)
			var hip := Vector3(0, 1.0, 0)
			body.position = hip - body.basis * hip
			var flap := sin(t * 23.0) * 0.015 * (0.5 + d)
			_arm("Left", Vector3(-0.85, 1.45, -0.1).lerp(Vector3(-0.3, 0.95, 0.12), d) + Vector3(0, flap, 0), Vector3(0, -1, 0).lerp(Vector3(0, 0, 1), d))
			_arm("Right", Vector3(0.85, 1.45, -0.1).lerp(Vector3(0.3, 0.95, 0.12), d) - Vector3(0, flap, 0), Vector3(0, -1, 0).lerp(Vector3(0, 0, 1), d))
			_leg("Left", Vector3(-0.32, 0.12, 0.3).lerp(Vector3(-0.1, 0.02, 0.06), d), Vector3(0, 0, 1))
			_leg("Right", Vector3(0.32, 0.12, 0.3).lerp(Vector3(0.1, 0.02, 0.06), d), Vector3(0, 0, 1))
		"chute":
			# Hands on the toggles; pulling one down turns, both down flares.
			var pl := 0.4 * maxf(-steer, 0.0) + 0.35 * brake
			var pr := 0.4 * maxf(steer, 0.0) + 0.35 * brake
			_arm("Left", Vector3(-0.27, 2.05 - pl, -0.02), Vector3(-1, 0, 0.3))
			_arm("Right", Vector3(0.27, 2.05 - pr, -0.02), Vector3(1, 0, 0.3))
			var sw := sin(t * 1.7) * 0.05
			_leg("Left", Vector3(-0.13, 0.06, -0.12 + sw), Vector3(0, 0, -1))
			_leg("Right", Vector3(0.13, 0.04, -0.06 - sw), Vector3(0, 0, -1))
	if armed and gun.visible:
		_hold_gun()
	elif pose in ["stand", "crouch"]:
		_relaxed_arms(speed)
	if _wave > 0.0:
		_wave -= delta
		_arm("Right", Vector3(0.45, 1.95 + sin(t * 10.0) * 0.06, -0.1 + sin(t * 10.0) * 0.12), Vector3(1, 0, 0))

## No gun: arms hang by the sides and swing with the steps (the stock
## animations hold a rifle, so the hands are moved down).
func _relaxed_arms(speed: float) -> void:
	var phase := 0.0
	if ap.current_animation != "" and ap.current_animation_length > 0.0:
		phase = ap.current_animation_position / ap.current_animation_length * TAU
	var swing := sin(phase) * 0.18 * clampf(speed / 2.0, 0.0, 1.0)
	var y := 0.88 + body.position.y
	_arm("Left", Vector3(-0.3, y, 0.02 - swing), Vector3(0, 0, 1))
	_arm("Right", Vector3(0.3, y, 0.02 + swing), Vector3(0, 0, 1))

## Hands on the rifle: right hand at the grip, left hand under the barrel.
func _hold_gun() -> void:
	var grip := gun.global_transform * Vector3(0, -0.06, 0.1)
	var fore := gun.global_transform * Vector3(0, -0.05, -0.32)
	var to_local := global_transform.affine_inverse()
	_arm("Right", to_local * grip, Vector3(1, -1, 0.3))
	_arm("Left", to_local * fore, Vector3(-1, -1, 0))

# ---------------------------------------------------------------- reach solver
## Model-space target -> moves the hand there (elbow pushed towards `pole`).
func _arm(side: String, target: Vector3, pole: Vector3) -> void:
	_two_bone(_bone[side + "Arm"], _bone[side + "ForeArm"], _bone[side + "Hand"], target, pole)

## Model-space target for the foot (knee pushed forward by default).
func _leg(side: String, target: Vector3, pole := Vector3(0, 0, -1)) -> void:
	_two_bone(_bone[side + "UpLeg"], _bone[side + "Leg"], _bone[side + "Foot"], target, pole)

func _two_bone(upper: int, lower: int, end: int, target_model: Vector3, pole_model: Vector3) -> void:
	# Work in skeleton space.
	var to_sk: Transform3D = sk.global_transform.affine_inverse() * global_transform
	var target: Vector3 = to_sk * target_model
	var pole: Vector3 = (to_sk.basis * pole_model).normalized()
	var parent := sk.get_bone_parent(upper)
	var gp_parent: Transform3D = sk.get_bone_global_pose(parent)
	var gp_upper: Transform3D = sk.get_bone_global_pose(upper)
	var gp_lower: Transform3D = sk.get_bone_global_pose(lower)
	var gp_end: Transform3D = sk.get_bone_global_pose(end)
	var s := gp_upper.origin
	var e := gp_lower.origin
	var h := gp_end.origin
	var a := s.distance_to(e)
	var b := e.distance_to(h)
	var to_t := target - s
	var d := clampf(to_t.length(), absf(a - b) + 0.001, a + b - 0.001)
	var dir := to_t.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var p := (pole - dir * pole.dot(dir))
	if p.length() < 0.001: p = dir.cross(Vector3.RIGHT)
	p = p.normalized()
	var elbow := s + dir * a * cos_a + p * a * sqrt(1.0 - cos_a * cos_a)
	var hand := s + dir * d
	# Upper bone: turn so it points at the elbow.
	var q1 := Quaternion((e - s).normalized(), (elbow - s).normalized())
	var new_upper := Transform3D(Basis(q1) * gp_upper.basis, s)
	sk.set_bone_pose_rotation(upper, (gp_parent.affine_inverse() * new_upper).basis.get_rotation_quaternion())
	# Lower bone: keep its local offset, then turn it towards the hand.
	var local_lower: Transform3D = gp_upper.affine_inverse() * gp_lower
	var new_lower: Transform3D = new_upper * local_lower
	var local_end: Transform3D = gp_lower.affine_inverse() * gp_end
	var end_pos: Vector3 = (new_lower * local_end).origin
	var q2 := Quaternion((end_pos - new_lower.origin).normalized(), (hand - new_lower.origin).normalized())
	var new_lower2 := Transform3D(Basis(q2) * new_lower.basis, new_lower.origin)
	sk.set_bone_pose_rotation(lower, (new_upper.affine_inverse() * new_lower2).basis.get_rotation_quaternion())
