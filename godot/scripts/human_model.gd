class_name HumanModel
extends Node3D
## Realistic animated soldier (skinned mesh with idle/walk/run animations).
## Same small API as SoldierModel (set_pose / set_gear / set_weapon / gun),
## so players and bots can use either. Poses the animations don't cover
## (rifle hold, crouch, prone, skydive, parachute, dead) are made on top of
## them with a two-bone "reach" solver for arms and legs and by tilting the body.
## The model faces -Z like the rest of the game.


var body: Node3D              # the imported model; tilted/lowered for poses
var sk: Skeleton3D
var ap: AnimationPlayer
var gun: Node3D               # holder of the weapon model (weapon frame: grip at origin, barrel -Z)
var weapon_node: Node3D       # current WeaponModels.build() result
var _weapon_id := ""
var _cls := ""
## Weapon handling, set by the owner each frame.
var aiming := false           # rifle up at the shoulder (ADS / firing)
var sprinting := false        # rifle carried across the chest
var aim_pitch := 0.0          # look up/down (radians): bends the upper body
var reload_p := -1.0          # reload progress 0..1 (-1 = not reloading)
var recoil := 0.0             # kick from the last shot (decays here)
var _gun_xf := Transform3D()  # smoothed weapon pose (model space)
var _gun_drop := 0.0            # extra height offset of the gun (crouch-walk)
var _speed := 0.0               # ground speed this frame (m/s)
var move_local := Vector2.ZERO  # ground velocity relative to facing: x = right, y = forward (m/s)
var canopy: Node3D            # ram-air parachute (canopy + suspension lines)
## Skydive / parachute controls, set by the owner each frame.
var dive := 0.0               # 0 = belly to earth, 1 = head-down dive
var lean := 0.0               # roll while skydiving (-1..1)
var peek := 0.0               # leaning round cover: -1 left .. 1 right
var ride := ""               # vehicle kind while driving (hands and feet placed for it)
var flinch := 0.0             # hit reaction: 1 when just hit, fades out
var foot_ik := false          # set by the owner when standing on the ground near the camera
var downed := false           # knocked down in a team match: crawls on hands and knees
var swimming := false         # in deep water: treads water, no weapon
var reviving := false         # kneeling by a downed teammate
var drinking := false         # energy drink / painkillers, standing still
var bandaging := false        # bandage / first aid: down on one knee, wrapping the arm
var sliding := 0.0            # 0..1: sliding on the hip after a sprint (crouch while sprinting)
var inspect_t := -1.0         # 0..1 through looking the gun over (-1 = not)
var bolt_p := -1.0            # 0..1 through working the bolt after a shot (bolt-action rifles)
var idle_clip := ""           # standing still: this clip instead of the usual idle (lobby)
var look_yaw := 0.0           # head turned left (+) / right (-) from the body, radians
var look_pitch := 0.0         # head tilted up (+) / down (-)
var turn_dir := 0             # turning on the spot: 1 left, -1 right (0 = not turning)
var turn_yaw := 0.0           # how far the turn clip has turned the body so far (radians)
var _turn_h0 := Quaternion.IDENTITY
var _foot_dy := [0.0, 0.0]    # smoothed ground height under each foot (left, right)
var _foot_n := [Vector3.UP, Vector3.UP]
var _hip_drop := 0.0
var _flinch_side := 0.0
var steer := 0.0              # parachute toggles: -1 pull left .. 1 pull right
var brake := 0.0              # parachute flare 0..1
var chute_open := 1.0         # 0 = just pulled (bunched up) .. 1 = fully open
var helmet: MeshInstance3D
var pack: MeshInstance3D
var vest: MeshInstance3D
var _fit: Array = []
var _has_weapon := false
var _anim := ""
var _bone := {}
var _hips := 0
var _cscale := 1.0              # size the character model is drawn at
var _wave := 0.0
var _skel_scale := 0.01
var _mats := {}

## Characters: Lola (a realistic Mixamo human) and the dyed-uniform soldier (albu).
## Survivor, Bundeswehr soldier and Remy: Sketchfab / Mixamo characters (see
## README), cleaned by tools/prep_character.gd, moves by tools/retarget_mixamo.gd.
## "fit": fine-tuning of the measured gear fit (see _build_gear):
## [helmet scale, vest/pack scale, helmet lift m, vest lift m, vest forward m, pack forward m].
const CHARACTERS := {
	"lola": {"scene": "res://assets/models/lola/lola.fbx", "anims": "res://assets/anims/mixamo_lola.res", "turn": PI, "scale": 0.92, "tint": false,
		"fit": [1.0, 1.0, 0.0, 0.0, 0.0, 0.0]},
	"survivor": {"scene": "res://assets/models/chars/survivor.glb", "anims": "res://assets/anims/mixamo_survivor.res", "turn": PI, "scale": 0.92, "tint": false,
		"fit": [1.0, 1.0, 0.0, 0.0, 0.0, 0.0]},
	"bundeswehr": {"scene": "res://assets/models/chars/bundeswehr.glb", "anims": "res://assets/anims/mixamo_bundeswehr.res", "turn": PI, "scale": 0.6, "tint": false,
		"pack": false,      # wears his own rucksack (it also deepens his measured back)
		"fit": [1.0, 0.95, 0.0, 0.0, 0.07, 0.0]},
	"remy": {"scene": "res://assets/models/chars/remy.glb", "anims": "res://assets/anims/mixamo_remy.res", "turn": PI, "scale": 0.5, "tint": false,
		"fit": [1.0, 1.0, 0.0, 0.0, 0.0, 0.0]},
	# Desert-camo soldier from Sketchfab (DenisAlbu, CC-BY-SA). His jacket,
	# cap and trousers are separate materials: the coloured outfits dye them.
	"albu": {"scene": "res://assets/models/chars/albu.glb", "anims": "res://assets/anims/mixamo_albu.res", "turn": PI, "scale": 1.07, "tint": false,
		"dye": {"Topmat": "top", "Hatmat": "top", "Bottommat": "pants"},
		"fit": [1.0, 1.0, 0.0, 0.0, 0.0, 0.0]},
}
## Characters the bots are drawn from (real people only: the old armoured
## "soldier" model is no longer in the game).
const BOT_CHARACTERS := ["survivor", "bundeswehr", "remy", "lola", "albu", "albu", "albu"]
## The coloured outfits are this character with his uniform dyed.
const DYE_BASE := "albu"
var character := "albu"
var _dyed: Array[StandardMaterial3D] = []    # the dyed uniform materials (gold plates only these)
var _u := 1.0                   # gear offsets are in centimetres of bone space; this converts

func _init(clothes: Color = Color("4a5d6b"), chute_color: Color = Color("c84f3a"), _pants: Color = Color("33373d"), who := DYE_BASE, dyed := false) -> void:
	character = who if CHARACTERS.has(who) else DYE_BASE
	var cdef: Dictionary = CHARACTERS[character]
	# body: the posed/tilted node; the model inside is turned to face -Z and sized.
	body = Node3D.new()
	add_child(body)
	var inst: Node3D = (load(cdef.scene) as PackedScene).instantiate()
	inst.rotation.y = cdef.turn
	inst.scale = Vector3.ONE * cdef.scale
	_cscale = cdef.scale
	body.add_child(inst)
	sk = inst.find_child("Skeleton3D", true, false)
	ap = inst.find_child("AnimationPlayer", true, false)
	if ap == null:
		# Characters prepared without their own clips: the moves are all ours.
		ap = AnimationPlayer.new()
		inst.add_child(ap)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for a in ["Idle", "Walk", "Run"]:
		if ap.has_animation(a): ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	# Mixamo rifle moves (aim, fire, reload, run, strafe), retargeted to this skeleton.
	ap.add_animation_library("mx", load(cdef.anims))
	# Skeleton units per metre of the model: every scale between the model's
	# root and the skeleton (some rigs carry it a few nodes up).
	_skel_scale = 1.0
	var sn: Node = sk
	while sn != inst and sn is Node3D:
		_skel_scale *= (sn as Node3D).scale.x
		sn = sn.get_parent()
	_u = 0.01 / _skel_scale
	for i in sk.get_bone_count():
		_bone[sk.get_bone_name(i).replace("mixamorig_", "")] = i
	_hips = _bone.get("Hips", 0)    # some rigs have an extra root joint above the hips
	# Tint the uniform with the outfit colour (keeps the texture detail).
	for mi in (sk.get_children() if cdef.tint else []):
		if mi is MeshInstance3D and mi.mesh:
			var m: Material = mi.mesh.surface_get_material(0)
			if m is StandardMaterial3D:
				var t: StandardMaterial3D = m.duplicate()
				t.albedo_color = Color.WHITE.lerp(clothes, 0.55)
				mi.material_override = t
	if dyed and cdef.has("dye"):
		# Dye the uniform (the cloth texture shows through), leave skin and kit.
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m0: Material = (mi as MeshInstance3D).get_active_material(0)
			if m0 is StandardMaterial3D and cdef.dye.has(m0.resource_name):
				var d: StandardMaterial3D = m0.duplicate()
				var c: Color = clothes if cdef.dye[m0.resource_name] == "top" else _pants
				d.albedo_color = Color.WHITE.lerp(c, 0.7) * 1.15
				(mi as MeshInstance3D).set_surface_override_material(0, d)
				_dyed.append(d)
	_build_gun()
	_build_gear()
	canopy = Node3D.new()
	canopy.position.y = RISER_Y
	canopy.visible = false
	add_child(canopy)
	if ResourceLoader.exists(CHUTE_MODEL):
		# Low-poly ram-air canopy with its lines (calebcram, CC-BY): the
		# lines meet at a bar just above the hands.
		var cm: Node3D = (load(CHUTE_MODEL) as PackedScene).instantiate()
		cm.position.y = 2.1 - RISER_Y
		cm.scale = Vector3.ONE * 0.76
		canopy.add_child(cm)
	else:
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
	set_process(false)

func _mat(key: String, c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]

# ---------------------------------------------------------------- parachute
const CHUTE_MODEL := "res://assets/models/air/parachute.glb"
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
	add_child(gun)
	gun.visible = false

## Helmet, vest and backpack follow the head and chest bones. Gear models
## are in real metres; the slot scale turns that into this skeleton's units.
## Where they go is measured on the body itself (top of the head, chest
## front and back), so every character gets a fit; "fit" fine-tunes it.
func _build_gear() -> void:
	_fit = CHARACTERS[character].get("fit", [1.0, 1.0, 0.0, 0.0, 0.0, 0.0])
	var u := 1.0 / (_skel_scale * _cscale)       # skeleton units per metre
	var m := _measure(u)
	_pack_back = m.back2 + _fit[5] * u
	helmet = _gear_slot("Head", Vector3(m.head_c.x, m.head_top - (0.075 - _fit[2]) * u, m.head_c.z + 0.005 * u), u * _fit[0] * m.head_k)
	vest = _gear_slot("Spine1", Vector3(0, (0.03 + _fit[3]) * u, (m.front1 + m.back1) * 0.5 + _fit[4] * u), u * _fit[1] * m.chest_k)
	pack = _gear_slot("Spine2", Vector3(0, -0.02 * u, m.back2), u * _fit[1])
	set_gear(0, 0, 0)

var _pack_back := 0.0
static var _measure_cache := {}

## Body measurements in the bone spaces of Head, Spine1 and Spine2 (skeleton
## units), from the skinned vertices at rest: top and middle of the head,
## chest front/back and width, upper back. Once per character.
func _measure(u: float) -> Dictionary:
	if _measure_cache.has(character): return _measure_cache[character]
	var hb: int = _bone.get("Head", 0)
	var s1: int = _bone.get("Spine1", 0)
	var s2: int = _bone.get("Spine2", s1)
	var hinv := sk.get_bone_global_rest(hb).affine_inverse()
	var s1inv := sk.get_bone_global_rest(s1).affine_inverse()
	var s2inv := sk.get_bone_global_rest(s2).affine_inverse()
	var head := []
	var front1 := -INF
	var back1 := INF
	var x1 := Vector2(INF, -INF)
	var back2 := INF
	var band := 0.07 * u
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null: continue
		var skin := mi.skin
		var bind_bone := PackedInt32Array()
		for bi in skin.get_bind_count():
			var bn := String(skin.get_bind_name(bi))
			bind_bone.append(sk.find_bone(bn) if bn != "" else skin.get_bind_bone(bi))
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null or verts.is_empty(): continue
			var per: int = bones.size() / verts.size()
			for i in range(0, verts.size(), 2):
				var best := 0
				for k in per:
					if weights[i * per + k] > weights[i * per + best]: best = k
				var bi: int = bones[i * per + best]
				if bi >= bind_bone.size() or bind_bone[bi] < 0: continue
				var bone: int = bind_bone[bi]
				var bname := sk.get_bone_name(bone)
				var p: Vector3 = sk.get_bone_global_rest(bone) * (skin.get_bind_pose(bi) * verts[i])
				if bname.ends_with("Head") or bname.ends_with("HeadTop_End"):
					head.append(hinv * p)
				elif bname.ends_with("Spine1") or bname.ends_with("Spine2") or bname.ends_with("Spine"):
					var q1 := s1inv * p
					if absf(q1.y) < band:
						front1 = maxf(front1, q1.z)
						back1 = minf(back1, q1.z)
						x1 = Vector2(minf(x1.x, q1.x), maxf(x1.y, q1.x))
					var q2 := s2inv * p
					if absf(q2.y) < band: back2 = minf(back2, q2.z)
	var top := -INF
	for q: Vector3 in head: top = maxf(top, q.y)
	var c := Vector3.ZERO
	var n := 0
	var hx := Vector2(INF, -INF)
	for q: Vector3 in head:
		if q.y > top - 0.06 * u:
			c += q
			n += 1
		if q.y > top - 0.12 * u: hx = Vector2(minf(hx.x, q.x), maxf(hx.y, q.x))
	if n > 0: c /= n
	var out := {"head_top": top if n > 0 else 0.17 * u, "head_c": c, "back2": back2 if back2 < INF else -0.12 * u,
		"front1": front1 if front1 > -INF else 0.12 * u, "back1": back1 if back1 < INF else -0.12 * u,
		# A head about 18 cm wide (ears, hair) wears the helmets as modelled; a chest
		# about 34 cm wide wears the vests as modelled.
		"head_k": clampf((hx.y - hx.x) / u / 0.18, 0.85, 1.2) if hx.y > hx.x else 1.0,
		"chest_k": clampf((x1.y - x1.x) / u / 0.34, 0.85, 1.25) if x1.y > x1.x else 1.0}
	_measure_cache[character] = out
	return out

## A gear node on a bone: position in that bone's space (skeleton units),
## scale from metres to skeleton units.
func _gear_slot(bone: String, pos: Vector3, f: float) -> MeshInstance3D:
	var att := BoneAttachment3D.new()
	att.bone_name = sk.get_bone_name(_bone.get(bone, _bone.get("Spine2", 0)))
	sk.add_child(att)
	var mi := MeshInstance3D.new()
	mi.scale = Vector3.ONE * f
	mi.position = pos
	att.add_child(mi)
	return mi

## Switching guns: the hand goes back over the shoulder for the new one
## (a short part of the clip).
func draw_weapon() -> void:
	play_action("draw", 0.6, 0.8, 3.0)

## Weapon id ("m416") or class ("ar"); "" = empty hands.
func set_weapon(id_or_cls: String) -> void:
	_has_weapon = id_or_cls != ""
	gun.visible = _has_weapon
	if id_or_cls == _weapon_id: return
	_weapon_id = id_or_cls
	if weapon_node:
		weapon_node.queue_free()
		weapon_node = null
	if id_or_cls == "": return
	_cls = Game.WEAPONS[id_or_cls].cls if Game.WEAPONS.has(id_or_cls) else id_or_cls
	weapon_node = WeaponModels.build(id_or_cls)
	gun.add_child(weapon_node)
	_att_key = ""

var _att_key := ""

## Shows sights, muzzle devices, magazines and grips on the held gun.
## Sizes and places come from the gun's own bounds (barrel along -Z).
func set_attachments(att: Dictionary) -> void:
	if weapon_node == null: return
	var key := str(att)
	if key == _att_key and weapon_node.get_node_or_null("Attachments"): return
	_att_key = key
	var old := weapon_node.get_node_or_null("Attachments")
	if old:
		weapon_node.remove_child(old)
		old.queue_free()
	if att.is_empty(): return
	var box := _local_aabb(weapon_node)
	var L := maxf(box.size.z, 0.3)
	var root := Node3D.new()
	root.name = "Attachments"
	weapon_node.add_child(root)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("1b1d21")
	dark.metallic = 0.6
	dark.roughness = 0.35
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.1, 0.25, 0.35)
	lens.metallic = 0.9
	lens.roughness = 0.05
	var top := box.position.y + box.size.y
	var mid_z := box.position.z + box.size.z * 0.55
	var muzzle_z: float = weapon_node.get_meta("muzzle", box.position.z)
	var cyl_z := func(r: float, h: float, pos: Vector3, mat: Material) -> void:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = 14
		mi.mesh = cm
		mi.material_override = mat
		mi.rotation = Vector3(PI * 0.5, 0, 0)
		mi.position = pos
		root.add_child(mi)
	var cube := func(sz: Vector3, pos: Vector3, mat: Material) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sz
		mi.mesh = bm
		mi.material_override = mat
		mi.position = pos
		root.add_child(mi)
	match att.get("sight", ""):
		"reddot", "holo":
			cube.call(Vector3(0.035, 0.012, 0.07) * L / 0.9, Vector3(0, top + 0.006, mid_z), dark)
			cube.call(Vector3(0.04, 0.045, 0.012) * L / 0.9, Vector3(0, top + 0.03 * L / 0.9, mid_z - 0.02), lens)
			cube.call(Vector3(0.045, 0.05, 0.02) * L / 0.9, Vector3(0, top + 0.03 * L / 0.9, mid_z + 0.02), dark)
		"x2", "x4", "x8":
			var n := {"x2": 0.16, "x4": 0.22, "x8": 0.28}[att.sight] as float
			var r := (0.02 if att.sight == "x2" else 0.025) * L / 0.9
			cube.call(Vector3(0.02, 0.025, 0.08) * L / 0.9, Vector3(0, top + 0.012, mid_z), dark)
			cyl_z.call(r, n * L / 0.9, Vector3(0, top + 0.03 * L / 0.9 + r, mid_z), dark)
			cyl_z.call(r * 1.25, 0.03 * L / 0.9, Vector3(0, top + 0.03 * L / 0.9 + r, mid_z - n * 0.5 * L / 0.9), dark)
			cyl_z.call(r * 1.25, 0.03 * L / 0.9, Vector3(0, top + 0.03 * L / 0.9 + r, mid_z + n * 0.5 * L / 0.9), dark)
	match att.get("muzzle", ""):
		"suppressor":
			cyl_z.call(0.022 * L / 0.9, 0.2 * L / 0.9, Vector3(0, 0.03, muzzle_z - 0.1 * L / 0.9), dark)
		"compensator":
			cyl_z.call(0.018 * L / 0.9, 0.07 * L / 0.9, Vector3(0, 0.03, muzzle_z - 0.035 * L / 0.9), dark)
	match att.get("grip", ""):
		"vgrip":
			cube.call(Vector3(0.025, 0.08, 0.03) * L / 0.9, Vector3(0, box.position.y - 0.02 * L / 0.9, box.position.z + box.size.z * 0.3), dark)
		"angled":
			cube.call(Vector3(0.025, 0.045, 0.07) * L / 0.9, Vector3(0, box.position.y + 0.005, box.position.z + box.size.z * 0.3), dark)
	if att.has("mag") and att.mag != "quick_mag":
		var mag := weapon_node.get_node_or_null("Mag") as Node3D
		if mag: mag.scale = Vector3(1, 1.35, 1)

## Bounding box of all meshes under n, in n's own space.
static func _local_aabb(n: Node3D) -> AABB:
	var res := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var c: Node = mi
		while c != n and c != null:
			xf = (c as Node3D).transform * xf
			c = c.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		res = b if first else res.merge(b)
		first = false
	return res

var _back_att: BoneAttachment3D
var _back_id := ""
var _back_dirty := false

## Muzzle up over the left shoulder, top of the gun facing away from the back
## (worked out in model space once the skeleton is posed).
func _place_back() -> void:
	_back_dirty = false
	if _back_att == null or _back_att.get_child_count() == 0: return
	var holder: Node3D = _back_att.get_child(_back_att.get_child_count() - 1)
	var b := Basis.looking_at(Vector3(-0.55, 0.83, 0.0).normalized(), Vector3(0, 0, 1)).scaled(Vector3.ONE * WSCALE)
	holder.global_transform = global_transform * Transform3D(b, Vector3(0.02, 1.2, 0.2) + b * Vector3(0, 0, 0.25))

## Weapon slung diagonally across the back ("" = none).
func set_back_weapon(id: String) -> void:
	if id == _back_id: return
	_back_id = id
	if _back_att == null:
		_back_att = BoneAttachment3D.new()
		_back_att.bone_name = sk.get_bone_name(_bone.Spine2)
		sk.add_child(_back_att)
	for c in _back_att.get_children(): c.queue_free()
	if id == "": return
	var holder := Node3D.new()
	holder.add_child(WeaponModels.build(id))
	_back_att.add_child(holder)
	_back_dirty = true

## World position of the muzzle (bullets and flashes start here).
func muzzle_position() -> Vector3:
	var z: float = weapon_node.get_meta("muzzle", -0.6) if weapon_node else -0.6
	return gun.global_transform * (Vector3(0, 0.03, z) * WSCALE)

func set_gear(vest_lvl: int, helmet_lvl: int, pack_lvl: int) -> void:
	if not CHARACTERS[character].get("vest", true): vest_lvl = 0
	if not CHARACTERS[character].get("pack", true): pack_lvl = 0
	for e in [[helmet, "helmet", helmet_lvl], [vest, "vest", vest_lvl], [pack, "pack", pack_lvl]]:
		var mi: MeshInstance3D = e[0]
		mi.visible = e[2] > 0
		if e[2] > 0:
			mi.mesh = gear_mesh(e[1], e[2])
			if e[1] == "pack":
				# The pack's front face sits against the back (its straps reach
				# about 9 cm further forward, round the shoulders).
				mi.position.z = _pack_back - (mi.mesh.get_aabb().size.z * 0.5 - 0.09) * mi.scale.x

static var _gear_cache := {}

## Helmets (1 off-road, 2 military, 3 Altyn with visor), vests (1 soft, 2
## carrier, 3 heavy with shoulder guards) and backpacks (1 small, 2 canvas,
## 3 tactical): Sketchfab models (see README) baked by tools/prep_prop.gd.
## [model front turned to +Z (radians about Y), how it is sized, size m].
const GEAR_MODELS := {
	"helmet1": [-PI / 2, "max", 0.32], "helmet2": [-PI / 2, "max", 0.28], "helmet3": [-PI / 2, "max", 0.31],
	"vest1": [0.0, "keep", 1.0], "vest2": [0.0, "keep", 1.0], "vest3": [0.0, "keep", 1.0],
	"pack1": [PI, "y", 0.44], "pack2": [PI, "y", 0.52], "pack3": [PI, "y", 0.56],
}

## Gear model in metres, +Z = the front of the body, centred on its middle.
static func gear_mesh(kind: String, lvl: int) -> ArrayMesh:
	var key := "%s%d" % [kind, clampi(lvl, 1, 3)]
	if _gear_cache.has(key): return _gear_cache[key]
	var cfg: Array = GEAR_MODELS[key]
	var sc: Node3D = load("res://assets/models/gear/%s.glb" % key).instantiate()
	var src: Mesh = null
	for mi: MeshInstance3D in sc.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh: src = mi.mesh
	var rot := Basis(Vector3.UP, cfg[0])
	var a: AABB = Transform3D(rot, Vector3.ZERO) * src.get_aabb()
	var k := 1.0
	match cfg[1]:
		"max": k = cfg[2] / maxf(a.size.x, maxf(a.size.y, a.size.z))
		"y": k = cfg[2] / a.size.y
	var xf := Transform3D(rot.scaled(Vector3.ONE * k), -a.get_center() * k)
	var mesh := ArrayMesh.new()
	for i in src.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(src, i, xf)
		st.set_material(src.surface_get_material(i))
		st.commit(mesh)
	sc.free()
	_gear_cache[key] = mesh
	return mesh

var _style := ""
var _panda: Node3D

## Outfit style: "gold" plates the armour in gold, "panda" adds a panda mask.
func set_style(style: String) -> void:
	if style == _style: return
	_style = style
	if not _dyed.is_empty():
		# A dyed uniform: only the cloth turns to gold.
		if style == "gold":
			for d in _dyed:
				d.albedo_color = Color(1.0, 0.86, 0.5)
				d.metallic = 0.85
				d.roughness = 0.3
	for mi in (sk.get_children() if _dyed.is_empty() else []):
		if mi is MeshInstance3D and mi.mesh and mi.material_override == null and mi.mesh.surface_get_material(0) is StandardMaterial3D:
			mi.material_override = mi.mesh.surface_get_material(0)
		if mi is MeshInstance3D and mi.mesh and mi.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = (mi.material_override as StandardMaterial3D).duplicate()
			if style == "gold":
				m.albedo_color = Color(1.0, 0.86, 0.5)
				m.metallic = 0.9
				m.roughness = 0.28
			mi.material_override = m
	if _panda:
		_panda.queue_free()
		_panda = null
	if style == "panda":
		var att := BoneAttachment3D.new()
		att.bone_name = sk.get_bone_name(_bone.Head)
		sk.add_child(att)
		_panda = att
		var mesh := MeshInstance3D.new()
		mesh.mesh = panda_mesh()
		mesh.scale = Vector3.ONE / _skel_scale
		att.add_child(mesh)

## Panda mask: white head with black ears, eye patches and nose (bone space, +Z = face).
static var _panda_mesh: ArrayMesh
static func panda_mesh() -> ArrayMesh:
	if _panda_mesh: return _panda_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [[0.135, Vector3(0, 0.1, 0.015), Vector3(1.0, 0.95, 1.0), Color(0.95, 0.95, 0.93)],
		[0.05, Vector3(-0.095, 0.215, -0.005), Vector3(1, 1, 0.6), Color(0.07, 0.07, 0.07)],
		[0.05, Vector3(0.095, 0.215, -0.005), Vector3(1, 1, 0.6), Color(0.07, 0.07, 0.07)],
		[0.04, Vector3(-0.048, 0.115, 0.122), Vector3(1.0, 1.3, 0.5), Color(0.07, 0.07, 0.07)],
		[0.04, Vector3(0.048, 0.115, 0.122), Vector3(1.0, 1.3, 0.5), Color(0.07, 0.07, 0.07)],
		[0.012, Vector3(-0.044, 0.12, 0.142), Vector3.ONE, Color(0.9, 0.9, 0.9)],
		[0.012, Vector3(0.044, 0.12, 0.142), Vector3.ONE, Color(0.9, 0.9, 0.9)],
		[0.022, Vector3(0, 0.07, 0.148), Vector3(1.2, 0.8, 0.8), Color(0.05, 0.05, 0.05)],
		[0.06, Vector3(0, 0.055, 0.105), Vector3(1.2, 0.8, 0.8), Color(0.9, 0.9, 0.88)]]
	for pt in parts:
		var sph := SphereMesh.new()
		sph.radius = pt[0]
		sph.height = pt[0] * 2.0
		sph.radial_segments = 16
		sph.rings = 8
		var tmp := SurfaceTool.new()
		tmp.create_from(sph, 0)
		var arr := tmp.commit_to_arrays()
		var cols := PackedColorArray()
		cols.resize(arr[Mesh.ARRAY_VERTEX].size())
		cols.fill(pt[3])
		arr[Mesh.ARRAY_COLOR] = cols
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		st.append_from(am, 0, Transform3D(Basis.from_scale(pt[2]), pt[1]))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.85
	st.set_material(m)
	_panda_mesh = st.commit()
	return _panda_mesh

## Lobby emote.
func wave(seconds: float) -> void:
	_wave = seconds

const DEATHS := ["death_front", "death_back", "death_right", "death_head", "death_back_head"]
var death_anim := ""            # pick a specific death ("death_crouch", "death_walk"...); "" = random
var vel_y := 0.0                # vertical speed (jump / fall animations)
var _action := ""
var _action_t := 0.0
var _action_speed := 1.0

## Plays a whole-body action once ("toss" = grenade throw) for `seconds`.
## `from`/`to` pick part of a longer clip (seconds into it).
func play_action(name: String, seconds: float, from := 0.0, to := -1.0) -> void:
	var a: Animation = ap.get_animation("mx/" + name)
	if a == null: return
	if to < 0.0: to = a.length
	_action = name
	_action_t = seconds
	_action_speed = (to - from) / seconds
	_anim = "mx/" + name
	ap.play("mx/" + name, 0.1)
	ap.seek(from, true)
	ap.speed_scale = _action_speed
	# Climbs and drops carry their own rise/fall; the owner already moves the
	# body, so that part is taken out of the hips (see set_pose).
	_action_rise = 0.0
	var up := _skeleton_up()
	for tr in a.get_track_count():
		if a.track_get_type(tr) == Animation.TYPE_POSITION_3D:
			_action_y0 = a.position_track_interpolate(tr, 0.0).dot(up)
			_action_rise = a.position_track_interpolate(tr, a.length).dot(up) - _action_y0
			break
var _action_y0 := 0.0
var _sk_up := Vector3.ZERO

## The model's up direction in skeleton space (the soldier's skeleton is turned).
func _skeleton_up() -> Vector3:
	if _sk_up == Vector3.ZERO:
		var t := Transform3D()
		var n: Node = sk
		while n != self and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		_sk_up = (t.basis.inverse() * Vector3.UP).normalized()
	return _sk_up
var _action_rise := 0.0

var _can: MeshInstance3D

## The energy drink can in the left hand while drinking.
func _place_can() -> void:
	var on := _anim == "mx/drink"
	if on and _can == null:
		_can = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.033
		cm.bottom_radius = 0.033
		cm.height = 0.12
		cm.radial_segments = 12
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("2a6fd6")
		mat.metallic = 0.7
		mat.roughness = 0.3
		cm.material = mat
		_can.mesh = cm
		_can.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_can)
	if _can:
		_can.visible = on and is_inside_tree()
		if _can.visible:
			var hand: Transform3D = sk.global_transform * sk.get_bone_global_pose(_bone["LeftHand"])
			var b := hand.basis.orthonormalized()
			_can.global_transform = Transform3D(b, hand.origin + b * Vector3(0.0, 0.07, 0.04))

## Starts a 90° turn on the spot (1 = left, -1 = right). The clip's own body
## turn is taken out of the hips and handed to the owner as `turn_yaw`, who
## turns the whole model by it, so the feet stay planted as they step round.
func start_turn(d: int) -> void:
	turn_dir = d
	turn_yaw = 0.0
	var name := "mx/turn90_l" if d > 0 else "mx/turn90_r"
	var a: Animation = ap.get_animation(name)
	if a == null:
		turn_dir = 0
		return
	_turn_h0 = Quaternion.IDENTITY
	for tr in a.get_track_count():
		if a.track_get_type(tr) == Animation.TYPE_ROTATION_3D and String(a.track_get_path(tr)).ends_with(sk.get_bone_name(_hips)):
			_turn_h0 = a.rotation_track_interpolate(tr, 0.0)
			break
	ap.play(name, 0.15)
	ap.seek(0.0, true)
	_anim = name

func _turn_step() -> void:
	var up := _skeleton_up()
	var cur := sk.get_bone_pose_rotation(_hips)
	var q := cur * _turn_h0.inverse()
	var a := 2.0 * atan2(Vector3(q.x, q.y, q.z).dot(up), q.w)
	a = wrapf(a, -PI, PI)
	sk.set_bone_pose_rotation(_hips, Quaternion(up, -a) * cur)
	turn_yaw = a
	if ap.current_animation_position >= ap.current_animation_length - 0.02:
		turn_yaw = PI / 2.0 * turn_dir
		turn_dir = 0

const DIRS8 := ["f", "fr", "r", "br", "b", "bl", "l", "fl"]
var _dir_k := 0

## Direction of travel relative to facing, in eight sectors. A little
## stickiness at the borders so a stick held between two directions does
## not flick between their clips.
func _dir8() -> String:
	if move_local.length() < 0.05: return DIRS8[_dir_k]
	var a := atan2(move_local.x, move_local.y)
	if absf(wrapf(a - _dir_k * PI / 4.0, -PI, PI)) > PI / 8.0 + 0.14:
		_dir_k = wrapi(int(round(a / (PI / 4.0))), 0, 8)
	return DIRS8[_dir_k]

## Walk / run / crouch-walk cycles: switching between them keeps the step.
static func _is_cycle(n: String) -> bool:
	for pre in ["mx/walk_", "mx/run_", "mx/sprint_", "mx/crouch_", "mx/pwalk_", "mx/prun_", "mx/pstrafe_", "mx/u_walk", "mx/u_run", "mx/u_back", "mx/u_sprint"]:
		if n.begins_with(pre): return true
	return false

## Where in a cycle the left foot is furthest ahead (0..1), measured once per
## clip from its thigh rotations and kept on the clip.
func _cycle_phase(a: Animation) -> float:
	if a.has_meta("phase0"): return float(a.get_meta("phase0"))
	var ph := 0.0
	var trk := {}
	for side in ["Left", "Right"]:
		if not _bone.has(side + "UpLeg") or not _bone.has(side + "Leg"): continue
		var bn := sk.get_bone_name(_bone[side + "UpLeg"])
		for tr in a.get_track_count():
			if a.track_get_type(tr) == Animation.TYPE_ROTATION_3D and String(a.track_get_path(tr)).ends_with(":" + bn):
				trk[side] = tr
	if trk.size() == 2:
		# Forward, in the hips' space: the model faces -Z.
		var hips_gb: Basis = sk.get_bone_global_rest(_hips).basis
		var fwd: Vector3 = (hips_gb.inverse() * (_sk_to_model().basis.inverse() * Vector3(0, 0, -1))).normalized()
		var kl: Vector3 = sk.get_bone_rest(_bone["LeftLeg"]).origin
		var kr: Vector3 = sk.get_bone_rest(_bone["RightLeg"]).origin
		var best := -INF
		for i in 32:
			var t := a.length * i / 32.0
			var d := (a.rotation_track_interpolate(trk["Left"], t) * kl - a.rotation_track_interpolate(trk["Right"], t) * kr).dot(fwd)
			if d > best:
				best = d
				ph = i / 32.0
	a.set_meta("phase0", ph)
	return ph

## Locomotion clip with its playback speed matched to the real ground speed.
func _play_moving(name: String, speed: float, max_scale := 2.2) -> void:
	var a: Animation = ap.get_animation(name)
	# The clip's speed was measured on the unscaled model.
	var clip_speed: float = (a.get_meta("speed", 2.0) if a else 2.0) * _cscale
	_play(name, clampf(speed / maxf(clip_speed, 0.15), 0.4, max_scale))

func _dying() -> bool:
	return _anim.begins_with("mx/death") or _anim == "mx/prone_death"

## Dead: keep playing the death animation until it ends (owners stop calling set_pose).
func _process(delta: float) -> void:
	if _dying() and ap.current_animation_position < ap.current_animation_length:
		ap.advance(delta)
	else:
		set_process(false)

## The soldier's own clips; other characters use the Mixamo equivalents.
const FALLBACK := {"Idle": "mx/idle", "Walk": "mx/walk_f", "Run": "mx/run_f"}

func _play(name: String, speed_scale: float) -> void:
	if not ap.has_animation(name) and FALLBACK.has(name): name = FALLBACK[name]
	if _anim != name:
		var from := _anim
		var at := ap.current_animation_position if _is_cycle(from) and ap.current_animation != "" else 0.0
		# Cross-fade time runs at the clip's speed: keep it ~0.2 s of real time.
		ap.play(name, clampf(0.2 * absf(speed_scale), 0.0, 0.4))
		_anim = name
		if _is_cycle(from) and _is_cycle(name) and ap.has_animation(from):
			# Same foot forward in the new cycle as in the old one.
			var a0: Animation = ap.get_animation(from)
			var a1: Animation = ap.get_animation(name)
			var u := fposmod(at / maxf(a0.length, 0.01) - _cycle_phase(a0) + _cycle_phase(a1), 1.0)
			ap.seek(u * a1.length, true)
	ap.speed_scale = speed_scale

## pose: "stand" | "crouch" | "prone" | "fall" | "chute" | "dead"
func set_pose(pose: String, speed: float, armed: bool, delta: float, t: float) -> void:
	# One-shot action (grenade toss) takes over the whole body for a moment.
	if _action_t > 0.0:
		_action_t -= delta
		_play("mx/" + _action, _action_speed)
		ap.advance(delta)
		if _action == "melee" and _has_weapon:
			# The pan swings in the right hand (handle along the fingers).
			var hand: Transform3D = sk.global_transform * sk.get_bone_global_pose(_bone["RightHand"])
			gun.global_transform = Transform3D(hand.basis.orthonormalized() * Basis(Vector3.RIGHT, PI / 2.0), hand.origin)
		if _action == "vault":
			# Jumping over a low wall: the owner carries the body over it, so
			# the clip's own hop is taken out of the hips.
			var upv := _skeleton_up()
			var hv := sk.get_bone_pose_position(_hips)
			sk.set_bone_pose_position(_hips, hv + upv * (minf(hv.dot(upv), _action_y0) - hv.dot(upv)))
		elif _action in ["climb", "wall_climb", "drop_down", "swim_edge"] and absf(_action_rise) > 0.3:
			# Climbing: the hips never go above where they started (the body is
			# lifted by the owner); dropping down: never below. Crouches stay.
			var up := _skeleton_up()
			var hp := sk.get_bone_pose_position(_hips)
			var h := hp.dot(up)
			var keep := minf(h, _action_y0) if _action_rise > 0.0 else maxf(h, _action_y0)
			sk.set_bone_pose_position(_hips, hp + up * (keep - h))
		gun.visible = _action == "melee" and _has_weapon
		body.position = Vector3.ZERO
		body.rotation = Vector3.ZERO
		canopy.visible = false
		return
	if pose == "dead":
		# A death animation plays once by itself (see _process) and stays down.
		if not _dying():
			# Shot while lying down: dies where he lies.
			var dn := death_anim
			if dn == "": dn = "prone_death" if _anim.begins_with("mx/prone") and ap.has_animation("mx/prone_death") else DEATHS[randi() % DEATHS.size()]
			_play("mx/" + dn, 1.0)
			set_process(true)
		gun.visible = false
		canopy.visible = false
		body.position = Vector3.ZERO
		body.rotation = Vector3.ZERO
		return
	# Base animation from the ground speed and its direction (8-way rifle set).
	_speed = speed
	var dir := _dir8()
	# One-handed guns (pistol, pan) have their own walk, run and idle.
	var pistol: bool = armed and _cls in ["pistol", "melee"] and ap.has_animation("mx/pidle")
	if bandaging and pose in ["stand", "crouch"] and speed < 0.3 and ap.has_animation("mx/kneel"):
		# Down on one knee to patch up: loop the low part of the kneel clip.
		_play("mx/kneel", 1.0)
		if ap.current_animation_position < 1.8 or ap.current_animation_position > 6.2: ap.seek(3.2, true)
	elif drinking and pose in ["stand", "crouch"] and speed < 0.3:
		# Bottle to the mouth: loop the drinking part of the clip.
		_play("mx/drink", 1.0)
		if ap.current_animation_position < 1.9 or ap.current_animation_position > 5.7: ap.seek(2.0, true)
	elif reviving and pose in ["stand", "crouch"] and ap.has_animation("mx/revive"):
		# Down on one knee by the teammate, tending them: loop the low part of the clip.
		_play("mx/revive", 1.0)
		if ap.current_animation_position < 2.8 or ap.current_animation_position > 6.4: ap.seek(3.0, true)
	elif reviving and pose in ["stand", "crouch"]:
		_play("mx/kneel", 1.0)
		if ap.current_animation_position < 1.8 or ap.current_animation_position > 6.2: ap.seek(3.2, true)
	elif turn_dir != 0 and pose == "stand" and speed < 0.3:
		_play("mx/turn90_l" if turn_dir > 0 else "mx/turn90_r", 1.0)
	elif swimming and pose in ["stand", "crouch", "prone"]:
		if speed > 0.3: _play_moving("mx/swim", speed, 2.6)
		else: _play("mx/swim_tread", 1.0)
	elif pose == "stand" and speed > 0.3 and pistol:
		var pset := "prun_" if speed > 3.2 else "pwalk_"
		_play_moving("mx/" + (("pstrafe_" + dir) if dir in ["l", "r"] else pset + dir), speed)
	elif pose == "stand" and speed > 0.3 and not armed and ap.has_animation("mx/u_walk"):
		# Empty hands: the unarmed locomotion set.
		var clip := "u_walk"
		if dir in ["b", "bl", "br"]: clip = "u_back"
		elif dir == "l": clip = "u_run_l" if speed > 3.2 else "u_walk_l"
		elif dir == "r": clip = "u_run_r" if speed > 3.2 else "u_walk_r"
		elif sprinting: clip = "u_sprint"
		elif speed > 3.2: clip = "u_run"
		_play_moving("mx/" + clip, speed)
	elif pose == "stand" and speed > 0.3:
		var set := "walk_"
		if sprinting and dir in ["f", "fl", "fr"]: set = "sprint_"
		elif speed > 3.2: set = "run_"
		_play_moving("mx/" + set + dir, speed)
	elif pose == "crouch" and speed > 0.3:
		_play_moving("mx/crouch_" + dir, speed)
	elif pose == "crouch" and armed and not pistol and reload_p >= 0.0 and ap.has_animation("mx/preload"):
		# Reloading on one knee: the clip's mag change, timed to the reload.
		_play("mx/preload", 0.0)
		ap.seek(0.4 + clampf(reload_p, 0.0, 1.0) * 6.0, true)
	elif pose == "crouch" and pistol and not aiming:
		_play("mx/pkneel", 1.0)
	elif pose == "crouch":
		_play("mx/idle_crouch_aim" if aiming else "mx/idle_crouch", 1.0)
	elif pose == "airborne":
		_play("mx/jump_up" if vel_y > 1.0 else ("mx/fall" if vel_y < -9.0 else "mx/jump_loop"), 1.0)
	elif pose == "prone" and speed > 0.2:
		# Crawling: on the belly (or on hands and knees when knocked down);
		# backwards plays the crawl in reverse.
		var clip := "mx/crawl" if downed else "mx/prone_f"
		var back := dir in ["b", "bl", "br"]
		_play_moving(clip, speed, 3.0)
		if back: ap.speed_scale = -absf(ap.speed_scale)
	elif pose == "prone" and downed:
		_play("mx/crawl", 0.08)
	elif pose == "prone":
		if reload_p >= 0.0: _play("mx/prone_reload", 6.4 / 2.4)
		elif aiming or recoil > 0.3: _play("mx/prone_fire", 1.0 if recoil > 0.3 else 0.06)
		else: _play("mx/prone_idle", 1.0)
	elif pose == "stand" and armed and reload_p >= 0.0:
		_play("mx/reload", 1.4)
	elif pose == "stand" and pistol and aiming and _cls == "pistol" and ap.has_animation("mx/pfire"):
		# Pistol up in both hands.
		_play("mx/pfire", 1.0 if recoil > 0.3 else 0.3)
	elif pose == "stand" and pistol:
		_play("mx/pidle", 1.0)
	elif pose == "stand" and armed and aiming:
		_play("mx/fire" if recoil > 0.3 else "mx/idle_aim", 1.0)
	elif pose == "stand" and speed < 0.3 and idle_clip != "" and ap.has_animation("mx/" + idle_clip):
		_play("mx/" + idle_clip, 1.0)
	elif pose == "stand" and armed:
		_play("mx/idle", 1.0)
	elif pose == "stand" and ap.has_animation("mx/u_idle"):
		_play("mx/u_idle", 1.0)
	elif pose == "drive" and ride != "bike" and ap.has_animation("mx/drive"):
		# Seated at the wheel (Mixamo driving clip); the hands follow the wheel below.
		_play("mx/drive", 1.0)
	elif pose == "fall" and ap.has_animation("mx/skydive"):
		# Belly to earth, arched, arms and legs out (Mixamo skydive clip).
		_play("mx/skydive", 1.0)
	else:
		_play("Idle", 1.0)
	ap.advance(delta)
	if turn_dir != 0: _turn_step()
	if _back_dirty and is_inside_tree(): _place_back()
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	_gun_drop = 0.0
	canopy.visible = pose == "chute"
	if canopy.visible:
		var e := ease(clampf(chute_open, 0.0, 1.0), 0.4)
		canopy.scale = Vector3(lerpf(0.12, 1.0, e), lerpf(0.3, 1.0, e), lerpf(0.35, 1.0, e))
	gun.visible = _has_weapon and pose in ["stand", "crouch", "prone", "airborne"]
	# Crawling, knocked down, swimming or helping a mate up: hands are busy, the gun is put away.
	if swimming or reviving or (drinking and _anim == "mx/drink") or (bandaging and _anim == "mx/kneel") or (pose == "prone" and (downed or _anim == "mx/prone_f")): gun.visible = false
	if swimming: body.position.y = 0.4          # afloat: head and shoulders out of the water
	recoil = move_toward(recoil, 0.0, delta * 6.0)
	match pose:
		"crouch":
			_gun_drop = -0.42        # the animations crouch the body
		"prone":
			if not (_anim.begins_with("mx/prone") or _anim == "mx/crawl"):
				# Crawling: the walk cycle turned face down.
				body.rotation.x = -PI / 2
				body.position = Vector3(0, 0.22, 0.9)
		"fall" when _anim == "mx/skydive":
			# The clip is already flat on the belly: diving tips the head
			# down (about the hips), steering rolls the body.
			var d := clampf(dive, 0.0, 1.0)
			body.rotation = Vector3(-d * 1.15, 0.0, -lean * 0.5)
			var hip := Vector3(0, 1.0, 0)
			body.position = hip - body.basis * hip
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
		"drive":
			# Seated: hips low, feet on the pedals, hands on the wheel (turning it).
			# The driving clip is already seated (hips 37 cm lower than standing).
			var seated := _anim == "mx/drive"
			body.position.y = -0.23 if seated else -0.6
			if ride == "bike":
				# Astride: hands on the grips (turning with the bars), feet on the pegs.
				for side in [["Left", -1.0], ["Right", 1.0]]:
					var sd: float = side[1]
					_arm(side[0], Vector3(sd * 0.32, 0.58 + sd * steer * 0.04, -0.55 - sd * steer * 0.08), Vector3(sd, -1, 0.3))
					_leg(side[0], Vector3(sd * 0.2, -0.08, -0.18), Vector3(0, 0.5, -1))
				return
			var a := steer * 0.9
			for side in [["Left", -1.0], ["Right", 1.0]]:
				var ang: float = (PI * 0.5 + 0.35) * side[1] + a
				_arm(side[0], Vector3(sin(ang) * 0.17, 1.02 + cos(ang) * 0.17 * 0.8, -0.42), Vector3(side[1], -1, 0.5))
				if not seated: _leg(side[0], Vector3(side[1] * 0.16, 0.02, -0.62), Vector3(0, 1, -1))
		"chute":
			# Hands on the toggles; pulling one down turns, both down flares.
			var pl := 0.4 * maxf(-steer, 0.0) + 0.35 * brake
			var pr := 0.4 * maxf(steer, 0.0) + 0.35 * brake
			_arm("Left", Vector3(-0.27, 2.05 - pl, -0.02), Vector3(-1, 0, 0.3))
			_arm("Right", Vector3(0.27, 2.05 - pr, -0.02), Vector3(1, 0, 0.3))
			var sw := sin(t * 1.7) * 0.05
			_leg("Left", Vector3(-0.13, 0.06, -0.12 + sw), Vector3(0, 0, -1))
			_leg("Right", Vector3(0.13, 0.04, -0.06 - sw), Vector3(0, 0, -1))
	_lean_into_moves(pose, speed, delta)
	if sliding > 0.0 and pose == "crouch":
		# On the hip: leaning back, low, the lead leg out in front.
		body.rotation.x += 0.42 * sliding
		body.position.y -= 0.22 * sliding
		body.position.z += 0.25 * sliding
	if pose in ["stand", "crouch"] and not swimming:
		_plant_feet(delta)
	else:
		_hip_drop = 0.0
	if absf(peek) > 0.01 and pose in ["stand", "crouch"]:
		body.position.x += peek * PEEK_SHIFT     # weight onto the outer foot
		_peek_feet(pose)
		_lean_spine()
	if flinch > 0.0 and pose in ["stand", "crouch", "prone"]:
		_flinch_spine()
		flinch = maxf(0.0, flinch - delta * 3.5)
	if armed and gun.visible:
		_place_gun(pose, delta)
		_bend_spine(pose)
		_hold_gun()
	else:
		gun.visible = false
		# The unarmed clips swing their own arms; the rifle ones need fixing up.
		if pose in ["stand", "crouch"] and not swimming and not reviving and _anim != "mx/drink" and not _anim.begins_with("mx/u_"):
			_relaxed_arms(speed)
	if bandaging and _anim == "mx/kneel": _bandage_hands(t)
	_place_can()
	if absf(look_yaw) > 0.01 or absf(look_pitch) > 0.01: _look_head()
	if _wave > 0.0:
		_wave -= delta
		_arm("Right", Vector3(0.45, 1.95 + sin(t * 10.0) * 0.06, -0.1 + sin(t * 10.0) * 0.12), Vector3(1, 0, 0))

## No gun: the stock animations all hold a rifle (chest turned, hunched,
## hands up), so the upper body is straightened and the arms swing freely,
## each arm going forward with the opposite leg; elbows bend more the
## faster he goes.
func _relaxed_arms(speed: float) -> void:
	var run := clampf((speed - 2.2) / 3.0, 0.0, 1.0)
	if _anim.begins_with("mx/crouch") or _anim.begins_with("mx/idle_crouch"): run = 0.0
	_upright_spine(lerpf(0.04, 0.2, run) + (0.08 if sprinting else 0.0))
	var to_model := _sk_to_model()
	var lf: Vector3 = to_model * sk.get_bone_global_pose(_bone["LeftFoot"]).origin
	var rf: Vector3 = to_model * sk.get_bone_global_pose(_bone["RightFoot"]).origin
	# +1: left foot ahead (right arm forward). The model faces -Z.
	var stride := clampf((rf.z - lf.z) / 0.55, -1.0, 1.0) * clampf(speed / 1.2, 0.0, 1.0)
	var amp := lerpf(0.42, 0.72, run)
	var bend := lerpf(0.3, 1.5, run) + (0.15 if sprinting else 0.0)
	for side in [["Left", -1.0], ["Right", 1.0]]:
		var sd: float = side[1]
		var sh: Vector3 = to_model * sk.get_bone_global_pose(_bone[side[0] + "Arm"]).origin
		var el: Vector3 = to_model * sk.get_bone_global_pose(_bone[side[0] + "ForeArm"]).origin
		var hd: Vector3 = to_model * sk.get_bone_global_pose(_bone[side[0] + "Hand"]).origin
		var a := sh.distance_to(el)
		var b := el.distance_to(hd)
		# Shoulder to hand with the elbow bent (law of cosines), angle from straight down.
		var reach := sqrt(a * a + b * b + 2.0 * a * b * cos(bend))
		var ang := stride * sd * amp + bend * 0.4
		var out := 0.12 - run * 0.06 * maxf(0.0, stride * sd)       # forward hand comes in a little
		var d := Vector3(sd * out, -cos(ang), -sin(ang)).normalized()
		_arm(side[0], sh + d * reach, Vector3(sd * 0.35, 0.0, 1.0))

## Skeleton space -> model space (works before the model is in the tree).
func _sk_to_model() -> Transform3D:
	var t := Transform3D()
	var n: Node = sk
	while n != self and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

## Chest over the hips, facing straight ahead, leaning `lean` radians forward;
## neck and head back to straight. Spread over the three spine bones.
func _upright_spine(lean: float) -> void:
	if not (_bone.has("Spine") and _bone.has("Spine2") and _bone.has("Neck")): return
	var to_model := _sk_to_model()
	var to_sk: Basis = to_model.basis.inverse()
	var want_up := Vector3(0.0, cos(lean), -sin(lean))
	var bones := ["Spine", "Spine1", "Spine2"]
	for k in bones.size():
		if not _bone.has(bones[k]): continue
		var i: int = _bone[bones[k]]
		var base: Vector3 = to_model * sk.get_bone_global_pose(_bone["Spine"]).origin
		var neck: Vector3 = to_model * sk.get_bone_global_pose(_bone["Neck"]).origin
		var la: Vector3 = to_model * sk.get_bone_global_pose(_bone["LeftArm"]).origin
		var ra: Vector3 = to_model * sk.get_bone_global_pose(_bone["RightArm"]).origin
		var up := (neck - base).normalized()
		var tilt := Quaternion(up, want_up)
		var right := tilt * (ra - la)
		right -= want_up * want_up.dot(right)
		var yaw := 0.0
		if right.length() > 0.001:
			var r := right.normalized()
			yaw = atan2(-r.z, r.x)        # chest turned to the left is positive
		var fix := Quaternion(want_up, -yaw) * tilt
		fix = Quaternion.IDENTITY.slerp(fix, 1.0 / float(bones.size() - k))
		var r_sk := (to_sk * Basis(fix) * to_model.basis).orthonormalized()
		var gp: Transform3D = sk.get_bone_global_pose(i)
		var parent_gp: Transform3D = sk.get_bone_global_pose(sk.get_bone_parent(i))
		sk.set_bone_pose_rotation(i, (parent_gp.basis.inverse() * (r_sk * gp.basis)).get_rotation_quaternion())
	for bn in ["Neck", "Head"]:
		if not _bone.has(bn): continue
		var i: int = _bone[bn]
		var rest := sk.get_bone_rest(i).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i).slerp(rest, 0.8))

func _phase() -> float:
	if ap.current_animation != "" and ap.current_animation_length > 0.0:
		return ap.current_animation_position / ap.current_animation_length * TAU
	return 0.0

const AIM_PIVOT := Vector3(0.0, 1.4, 0.05)     # between the shoulders (model space)
const WSCALE := 0.85                            # weapons sized to this character's reach

## Where the weapon should be for this pose (model space), then eased there.
## Positions are the pistol grip (right hand); rotations are pitch, yaw, roll.
func _place_gun(pose: String, delta: float) -> void:
	var pistol := _cls in ["pistol", "melee"]
	var pos: Vector3
	var rot := Vector3.ZERO
	var pitch_with_aim := true
	if pose == "prone":
		pos = Vector3(0.1, 0.3, -0.75)
		rot = Vector3(clampf(aim_pitch, -0.15, 0.25), 0, 0)
		pitch_with_aim = false
	elif sprinting and reload_p < 0.0:
		# Carried across the chest, muzzle up to the left, top of the gun facing out.
		if pistol:
			pos = Vector3(0.2, 1.0, -0.12)
			rot = Vector3(-1.2, 0, 0)
		else:
			pos = Vector3(0.16, 1.12, -0.2)
			var bb := Basis.looking_at(Vector3(-0.62, 0.72, -0.3).normalized(), Vector3(0, 0, -1))
			rot = bb.get_euler(EULER_ORDER_YXZ)
		pitch_with_aim = false
	elif aiming or recoil > 0.05:
		# Stock in the shoulder, sight in front of the eye.
		pos = Vector3(0.08, 1.44, -0.24) if not pistol else Vector3(0.03, 1.44, -0.4)
	else:
		# Ready: muzzle a little down and inwards; lower and across the body
		# when running (low ready).
		pos = Vector3(0.12, 1.32, -0.22) if not pistol else Vector3(0.12, 1.15, -0.28)
		rot = Vector3(-0.22, 0.2, 0.06) if not pistol else Vector3(-0.6, 0.2, 0)
		var low := clampf((_speed - 3.0) / 1.5, 0.0, 1.0) if pose == "stand" else 0.0
		if low > 0.0 and not pistol:
			pos = pos.lerp(Vector3(0.13, 1.14, -0.24), low)
			rot = rot.lerp(Vector3(-0.75, 0.5, 0.3), low)
		pitch_with_aim = low < 0.5
	if inspect_t >= 0.0 and reload_p < 0.0 and not aiming:
		# Looking the gun over: brought up in front, turned to one side, then the other.
		var ki := sin(clampf(inspect_t, 0.0, 1.0) * PI)
		var sw := sin(inspect_t * TAU)
		pos = pos.lerp(Vector3(0.05, 1.34, -0.36), ki)
		rot = rot.lerp(Vector3(0.12, 0.7 * sw, 1.25 * sw), ki)
		pitch_with_aim = false
	if reload_p >= 0.0:
		# Gun brought in front of the chest and rolled to see the magazine well
		# (a bolt-action or a shotgun: rolled to show the loading port).
		var k := sin(clampf(reload_p, 0.0, 1.0) * PI)
		pos = pos.lerp(Vector3(0.1, 1.3, -0.2), k)
		rot = rot.lerp(Vector3(0.1, 0.3, 0.55) if _cls not in ["sr", "shotgun"] else Vector3(0.15, 0.25, -0.5), k)
	pos.y += body.position.y + _gun_drop
	var b := Basis.from_euler(rot, EULER_ORDER_YXZ)
	var target := Transform3D(b, pos)
	if pitch_with_aim:
		var piv := AIM_PIVOT + Vector3(0, body.position.y, 0)
		var pr := Basis(Vector3.RIGHT, aim_pitch * (1.0 if aiming else 0.6))
		target = Transform3D(pr * target.basis, piv + pr * (target.origin - piv))
	if absf(peek) > 0.01 and pose != "prone":
		# Leaning round cover: the gun goes with the upper body.
		var hip := Vector3(0, 0.95 + body.position.y, 0)
		var rb := Basis(Vector3.BACK, -peek * PEEK_ROLL)
		target = Transform3D(rb * target.basis, hip + rb * (target.origin - hip) + Vector3(peek * PEEK_SHIFT, 0, 0))
	if absf(_turn_lean) > 0.002 or absf(_go_lean) > 0.002:
		# The gun leans with the body (it turns about the feet).
		target = Transform3D(Basis.from_euler(Vector3(_go_lean, 0.0, _turn_lean)), Vector3.ZERO) * target
	target.origin += target.basis * Vector3(0, 0.01, 0.06) * recoil
	target.basis = target.basis * Basis(Vector3.RIGHT, recoil * 0.07)
	var k2 := minf(1.0, delta * 14.0)
	_gun_xf = Transform3D(_gun_xf.basis.slerp(target.basis.orthonormalized(), k2).orthonormalized(), _gun_xf.origin.lerp(target.origin, k2)) if _gun_xf.origin != Vector3.ZERO else target
	gun.transform = _gun_xf
	if weapon_node: weapon_node.scale = Vector3.ONE * WSCALE
	# Magazine out and back in during a reload.
	var mag := weapon_node.get_node_or_null("Mag") as Node3D if weapon_node else null
	if mag and mag is MeshInstance3D:
		var p := reload_p
		var drop := 0.0
		if p >= 0.15 and p < 0.6: drop = 1.0
		elif p >= 0.6 and p < 0.8: drop = 1.0 - (p - 0.6) / 0.2
		mag.position = Vector3(0, -0.28 * drop, 0.05 * drop)
		mag.visible = not (p >= 0.3 and p < 0.45)

## Hit: the upper body jerks back and a little to one side, the head snaps.
func hit(strength := 1.0) -> void:
	flinch = clampf(strength, 0.3, 1.0)
	_flinch_side = randf_range(-1.0, 1.0)

func _flinch_spine() -> void:
	var k := sin(flinch * PI * 0.5)     # fast in, eased out
	var to_sk: Transform3D = sk.global_transform.affine_inverse() * global_transform
	var right := (to_sk.basis * Vector3.RIGHT).normalized()
	var fwd := (to_sk.basis * Vector3.BACK).normalized()
	for bn in ["Spine1", "Spine2", "Neck", "Head"]:
		if not _bone.has(bn): continue
		var i: int = _bone[bn]
		var inv := sk.get_bone_global_pose(i).basis.inverse()
		var amt := 0.12 if bn.begins_with("Spine") else 0.2
		var q := Quaternion((inv * right).normalized(), -amt * k) * Quaternion((inv * fwd).normalized(), _flinch_side * amt * 0.6 * k)
		sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * q)

var _yaw0 := INF
var _speed0 := 0.0
var _turn_lean := 0.0
var _go_lean := 0.0

## Running round a bend the body leans into it; setting off it tips forward
## for a step, pulling up it rocks back. From the model's own turn rate and
## change of speed, so it works the same for the player and the bots.
func _lean_into_moves(pose: String, speed: float, delta: float) -> void:
	if delta <= 0.0 or not is_inside_tree(): return
	var yaw := atan2(global_basis.z.x, global_basis.z.z)
	var rate := 0.0
	if _yaw0 != INF: rate = wrapf(yaw - _yaw0, -PI, PI) / delta
	_yaw0 = yaw
	var acc := (speed - _speed0) / delta
	_speed0 = speed
	var on := pose == "stand" and not swimming and _action_t <= 0.0
	var want_turn := clampf(rate * speed * 0.012, -0.13, 0.13) if on and speed > 2.0 else 0.0
	var want_go := clampf(-acc * 0.012, -0.09, 0.07) if on and absf(acc) > 1.5 else 0.0
	_turn_lean = lerpf(_turn_lean, want_turn, clampf(delta * 6.0, 0.0, 1.0))
	_go_lean = lerpf(_go_lean, want_go, clampf(delta * (8.0 if absf(want_go) > absf(_go_lean) else 3.0), 0.0, 1.0))
	if absf(_turn_lean) < 0.002 and absf(_go_lean) < 0.002: return
	body.rotation.z += _turn_lean
	body.rotation.x += _go_lean

const PEEK_ROLL := 0.36      # radians the upper body tilts when leaning
const PEEK_SHIFT := 0.22     # metres the body shifts sideways

## Leaning out: the hips go over, the inner foot mostly stays where it stood
## and the outer one steps out wider (standing still; walking keeps the clip).
func _peek_feet(pose: String) -> void:
	var still := clampf(1.0 - (_speed - 0.3) / 1.2, 0.0, 1.0)
	if still <= 0.0: return
	var to_model := _sk_to_model()
	var shift := peek * PEEK_SHIFT * still
	for i in 2:
		var side: String = ["Left", "Right"][i]
		var sd := -1.0 if i == 0 else 1.0
		var fp: Vector3 = to_model * sk.get_bone_global_pose(_bone[side + "Foot"]).origin
		var knee: Vector3 = to_model * sk.get_bone_global_pose(_bone[side + "Leg"]).origin
		var hip: Vector3 = to_model * sk.get_bone_global_pose(_bone[side + "UpLeg"]).origin
		var out := sd * signf(peek) > 0.0
		var step := (0.13 if pose == "stand" else 0.08) * absf(peek) * still * sd if out else 0.0
		var pole := knee - (hip + fp) * 0.5
		if pole.length() < 0.01: pole = Vector3(0, 0, -1)
		# The knee also points out a little over the outer foot.
		_leg(side, fp + Vector3(step - shift * 0.6, 0, 0), (pole.normalized() + Vector3(sd * 0.3 if out else 0.0, 0, 0)).normalized())
	# Eyes stay closer to level: neck and head take back part of the tilt.
	var to_sk: Transform3D = sk.global_transform.affine_inverse() * global_transform
	var axis_sk := (to_sk.basis * Vector3.BACK).normalized()
	for bn in ["Neck", "Head"]:
		if not _bone.has(bn): continue
		var b: int = _bone[bn]
		var inv := sk.get_bone_global_pose(b).basis.inverse()
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion((inv * axis_sk).normalized(), peek * PEEK_ROLL * 0.22))

## Patching up: the left forearm held across the chest, the right hand
## winding the bandage round it.
func _bandage_hands(t: float) -> void:
	if not _bone.has("Spine2"): return
	var to_model := _sk_to_model()
	var chest: Vector3 = to_model * sk.get_bone_global_pose(_bone["Spine2"]).origin
	var held := chest + Vector3(-0.04, -0.12, -0.3)
	_arm("Left", held, Vector3(-1, -1, 0))
	var a := t * 7.0
	_arm("Right", held + Vector3(0.1 + cos(a) * 0.05, sin(a) * 0.06, cos(a) * 0.04), Vector3(1, -1, 0.3))

## Stops a one-shot action early (an emote cut short by moving).
func stop_action() -> void:
	_action_t = 0.0

## Lean sideways from the hips (Q / E), split over the three spine bones.
func _lean_spine() -> void:
	var to_sk: Transform3D = sk.global_transform.affine_inverse() * global_transform
	var axis_sk := (to_sk.basis * Vector3.BACK).normalized()
	for bn in ["Spine", "Spine1", "Spine2"]:
		if not _bone.has(bn): continue
		var i: int = _bone[bn]
		var inv := sk.get_bone_global_pose(i).basis.inverse()
		var q := Quaternion((inv * axis_sk).normalized(), -peek * PEEK_ROLL / 3.0)
		sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * q)

## Turns the neck and head towards look_yaw / look_pitch (the neck takes 40 %).
func _look_head() -> void:
	var to_sk: Transform3D = sk.global_transform.affine_inverse() * global_transform
	var up_sk := (to_sk.basis * Vector3.UP).normalized()
	var right_sk := (to_sk.basis * Vector3.RIGHT).normalized()
	for bn in [["Neck", 0.4], ["Head", 0.6]]:
		if not _bone.has(bn[0]): continue
		var i: int = _bone[bn[0]]
		var inv := sk.get_bone_global_pose(i).basis.inverse()
		var share: float = bn[1]
		var q := Quaternion((inv * up_sk).normalized(), clampf(look_yaw, -1.2, 1.2) * share) \
			* Quaternion((inv * right_sk).normalized(), clampf(look_pitch, -0.5, 0.5) * share)
		sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * q)

## Upper body follows the aim up/down; the head looks a bit further.
func _bend_spine(pose: String) -> void:
	if pose == "prone": return
	var to_sk: Transform3D = sk.global_transform.affine_inverse() * global_transform
	var axis_sk := (to_sk.basis * Vector3.RIGHT).normalized()
	var up_sk := (to_sk.basis * Vector3.UP).normalized()
	var amount := clampf(aim_pitch, -1.0, 1.0) * (0.75 if aiming else 0.5)
	# Bladed rifle stance: chest turned right (left shoulder forward), head turned back.
	var twist := -0.3 if not (_cls in ["pistol", "melee"]) and not sprinting else 0.0
	if _anim.begins_with("mx/aim") or _anim.begins_with("mx/fire") or _anim.begins_with("mx/reload"): twist = 0.0   # already bladed
	for bn in ["Spine", "Spine1", "Spine2", "Neck", "Head"]:
		if not _bone.has(bn): continue
		var i: int = _bone[bn]
		var gp: Transform3D = sk.get_bone_global_pose(i)
		var inv := gp.basis.inverse()
		var share := 0.3 if bn.begins_with("Spine") else 0.12
		var tw := twist / 3.0 if bn.begins_with("Spine") else -twist * 0.5
		var q := Quaternion((inv * axis_sk).normalized(), amount * share) * Quaternion((inv * up_sk).normalized(), tw)
		if bn == "Head" and aiming:
			q = q * Quaternion((inv * axis_sk).normalized(), -0.12)     # cheek down to the sight
		sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * q)

## Hands on the weapon: right hand at the grip, left hand on the handguard
## (or on the magazine while reloading).
func _hold_gun() -> void:
	var to_local := global_transform.affine_inverse()
	var g := gun.global_transform
	var grip := g * Vector3(0.0, -0.06, 0.07)
	var fore_v: Vector3 = weapon_node.get_meta("fore", Vector3(0, -0.06, -0.32)) if weapon_node else Vector3(0, -0.06, -0.32)
	var fore := g * (fore_v * WSCALE + Vector3(-0.02, -0.02, 0.06))
	var p := reload_p
	var rgrip := grip
	var pouch_r := global_transform * Vector3(0.22, 1.0 + body.position.y, 0.05)
	if p >= 0.0 and _cls == "sr":
		# Bolt-action: bolt up and back, rounds pushed in from a clip, bolt home.
		var bolt := g * Vector3(0.04, 0.05, -0.06)
		var bolt_back := g * Vector3(0.04, 0.06, 0.04)
		var port := g * Vector3(0.0, 0.08, -0.1)
		if p < 0.12: rgrip = grip.lerp(bolt, p / 0.12)
		elif p < 0.2: rgrip = bolt.lerp(bolt_back, (p - 0.12) / 0.08)
		elif p < 0.8:
			var q := fmod((p - 0.2) / 0.6 * 2.0, 1.0)      # two clips' worth of trips
			rgrip = bolt_back.lerp(pouch_r, sin(q * PI)) if q < 0.5 else pouch_r.lerp(port, (q - 0.5) * 2.0)
		elif p < 0.9: rgrip = bolt_back.lerp(bolt, (p - 0.8) / 0.1)
		else: rgrip = bolt.lerp(grip, (p - 0.9) / 0.1)
		p = -1.0      # the support hand stays under the gun
	elif p >= 0.0 and _cls == "shotgun":
		# Shells one at a time from the belt into the port under the gun.
		var port := g * Vector3(0.0, -0.07, -0.14)
		var q := fmod(p * 4.0, 1.0)
		rgrip = pouch_r.lerp(port, smoothstep(0.2, 0.8, q)) if p < 0.95 else port.lerp(grip, (p - 0.95) / 0.05)
		if p < 0.06: rgrip = grip.lerp(pouch_r, p / 0.06)
		p = -1.0
	elif bolt_p >= 0.0 and _cls == "sr":
		# Working the bolt after a shot: up, back, forward, down.
		var bolt := g * Vector3(0.04, 0.05, -0.06)
		var bolt_back := g * Vector3(0.04, 0.06, 0.04)
		if bolt_p < 0.25: rgrip = grip.lerp(bolt, bolt_p / 0.25)
		elif bolt_p < 0.5: rgrip = bolt.lerp(bolt_back, (bolt_p - 0.25) / 0.25)
		elif bolt_p < 0.75: rgrip = bolt_back.lerp(bolt, (bolt_p - 0.5) / 0.25)
		else: rgrip = bolt.lerp(grip, (bolt_p - 0.75) / 0.25)
	if p >= 0.0:
		var mag := weapon_node.get_node_or_null("Mag") as Node3D
		var mag_pt := (mag.global_transform * Vector3(-0.03, -0.08, 0.0)) if mag else fore
		var pouch := global_transform * Vector3(-0.22, 1.0 + body.position.y, 0.0)
		if p < 0.15: fore = fore.lerp(mag_pt, p / 0.15)
		elif p < 0.3: fore = mag_pt
		elif p < 0.45: fore = mag_pt.lerp(pouch, (p - 0.3) / 0.15)
		elif p < 0.6: fore = pouch.lerp(mag_pt, (p - 0.45) / 0.15)
		elif p < 0.8: fore = mag_pt
		else: fore = mag_pt.lerp(fore, (p - 0.8) / 0.2)
	_arm("Right", to_local * rgrip, Vector3(1, -1, 0.4))
	if _cls in ["pistol", "melee"] and not aiming and reload_p < 0.0:
		_arm("Left", to_local * (grip + g.basis * Vector3(-0.05, -0.02, 0.02)), Vector3(-1, -1, 0))
	else:
		_arm("Left", to_local * fore, Vector3(-1, -1, 0))

# ---------------------------------------------------------------- feet on the ground
const FOOT_RAY := 0.6           # how far above/below the feet we look for ground
const HIP_DROP_MAX := 0.32

## Slopes and steps: the animations assume flat ground. Each foot is moved
## onto the ground under it and turned to its slope; the hips drop so the
## lower foot can reach.
func _plant_feet(delta: float) -> void:
	var k := clampf(delta * 14.0, 0.0, 1.0)
	if not foot_ik or not is_inside_tree():
		_foot_dy = [lerpf(_foot_dy[0], 0.0, k), lerpf(_foot_dy[1], 0.0, k)]
		_hip_drop = lerpf(_hip_drop, 0.0, k)
		if absf(_hip_drop) < 0.005 and absf(_foot_dy[0]) < 0.005 and absf(_foot_dy[1]) < 0.005: return
	else:
		var space := get_world_3d().direct_space_state
		var up := global_basis.y
		for i in 2:
			var side: String = ["Left", "Right"][i]
			var fp: Vector3 = (sk.global_transform * sk.get_bone_global_pose(_bone[side + "Foot"])).origin
			var flat := fp - up * up.dot(fp - global_position)
			var q := PhysicsRayQueryParameters3D.create(flat + up * FOOT_RAY, flat - up * FOOT_RAY, 1)
			var hit := space.intersect_ray(q)
			var dy := 0.0
			var n := Vector3.UP
			if hit:
				dy = clampf(up.dot(hit.position - global_position), -FOOT_RAY, FOOT_RAY * 0.8)
				n = global_basis.inverse() * hit.normal
				if n.y < 0.5: n = Vector3.UP     # a wall, not a floor
			_foot_dy[i] = lerpf(_foot_dy[i], dy, k)
			_foot_n[i] = _foot_n[i].lerp(n, k).normalized()
		_hip_drop = lerpf(_hip_drop, clampf(minf(minf(_foot_dy[0], _foot_dy[1]), 0.0), -HIP_DROP_MAX, 0.0), k)
	body.position.y += _hip_drop
	var inv := global_transform.affine_inverse()
	for i in 2:
		var side: String = ["Left", "Right"][i]
		var foot: int = _bone[side + "Foot"]
		var lift: float = _foot_dy[i] - _hip_drop
		if absf(lift) < 0.01 and _foot_n[i].y > 0.99: continue
		# Where the animation put the foot (after the hip drop), raised onto the ground.
		var fp: Vector3 = inv * (sk.global_transform * sk.get_bone_global_pose(foot)).origin
		var knee: Vector3 = inv * (sk.global_transform * sk.get_bone_global_pose(_bone[side + "Leg"])).origin
		var hip: Vector3 = inv * (sk.global_transform * sk.get_bone_global_pose(_bone[side + "UpLeg"])).origin
		var pole := (knee - (hip + fp) * 0.5)
		if pole.length() < 0.01: pole = Vector3(0, 0, -1)
		_leg(side, fp + Vector3(0, lift, 0), pole.normalized())
		# Turn the foot to the slope.
		var n: Vector3 = _foot_n[i]
		if n.y < 0.995:
			var sk_basis: Basis = (sk.global_transform.affine_inverse() * global_transform).basis
			var tilt := Quaternion(Vector3.UP, n)
			var tilt_sk := Quaternion((sk_basis * Basis(tilt) * sk_basis.inverse()).orthonormalized())
			var gp: Transform3D = sk.get_bone_global_pose(foot)
			var parent_gp: Transform3D = sk.get_bone_global_pose(sk.get_bone_parent(foot))
			var new_gp := Basis(tilt_sk.slerp(Quaternion.IDENTITY, 0.3)) * gp.basis
			sk.set_bone_pose_rotation(foot, (parent_gp.basis.inverse() * new_gp).get_rotation_quaternion())

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
