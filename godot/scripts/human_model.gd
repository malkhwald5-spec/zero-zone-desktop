class_name HumanModel
extends Node3D
## Realistic animated soldier (skinned mesh with idle/walk/run animations).
## Same small API as SoldierModel (set_pose / set_gear / set_weapon / gun),
## so players and bots can use either. Poses the animations don't cover
## (rifle hold, crouch, prone, skydive, parachute, dead) are made on top of
## them with a two-bone "reach" solver for arms and legs and by tilting the body.
## The model faces -Z like the rest of the game.

const SCENE := preload("res://assets/models/soldier.glb")
const MIXAMO := preload("res://assets/anims/mixamo_anims.res")

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
var _foot_dy := [0.0, 0.0]    # smoothed ground height under each foot (left, right)
var _foot_n := [Vector3.UP, Vector3.UP]
var _hip_drop := 0.0
var _flinch_side := 0.0
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

## Characters: the armoured soldier, or Lola (a realistic Mixamo human).
const CHARACTERS := {
	"soldier": {"scene": "res://assets/models/soldier.glb", "anims": "res://assets/anims/mixamo_anims.res", "turn": 0.0, "scale": 1.0, "tint": true},
	"lola": {"scene": "res://assets/models/lola/lola.fbx", "anims": "res://assets/anims/mixamo_lola.res", "turn": PI, "scale": 0.92, "tint": false},
}
var character := "soldier"
var _u := 1.0                   # gear offsets are in centimetres of bone space; this converts

func _init(clothes: Color = Color("4a5d6b"), chute_color: Color = Color("c84f3a"), _pants: Color = Color("33373d"), who := "soldier") -> void:
	character = who if CHARACTERS.has(who) else "soldier"
	var cdef: Dictionary = CHARACTERS[character]
	# body: the posed/tilted node; the model inside is turned to face -Z and sized.
	body = Node3D.new()
	add_child(body)
	var inst: Node3D = (SCENE if character == "soldier" else load(cdef.scene)).instantiate()
	inst.rotation.y = cdef.turn
	inst.scale = Vector3.ONE * cdef.scale
	body.add_child(inst)
	sk = inst.find_child("Skeleton3D", true, false)
	ap = inst.find_child("AnimationPlayer", true, false)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for a in ["Idle", "Walk", "Run"]:
		if ap.has_animation(a): ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	# Mixamo rifle moves (aim, fire, reload, run, strafe), retargeted to this skeleton.
	ap.add_animation_library("mx", MIXAMO if character == "soldier" else load(cdef.anims))
	_skel_scale = sk.get_parent().scale.x if sk.get_parent() is Node3D and sk.get_parent() != inst else 1.0
	_u = 0.01 / _skel_scale
	for i in sk.get_bone_count():
		_bone[sk.get_bone_name(i).replace("mixamorig_", "")] = i
	# Tint the uniform with the outfit colour (keeps the texture detail).
	for mi in (sk.get_children() if cdef.tint else []):
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

## Helmet and backpack follow the head and upper back bones.
func _build_gear() -> void:
	_helmet_att = BoneAttachment3D.new()
	_helmet_att.bone_name = sk.get_bone_name(_bone.Head)
	sk.add_child(_helmet_att)
	helmet = MeshInstance3D.new()
	helmet.mesh = gear_mesh("helmet", 2)
	helmet.scale = Vector3.ONE / _skel_scale * 1.08
	helmet.position = Vector3(0, 7.5, 0.8) * _u
	helmet.material_override = _mat("helmet", Color("5a7a4a"), 0.5)
	_helmet_att.add_child(helmet)
	_pack_att = BoneAttachment3D.new()
	_pack_att.bone_name = sk.get_bone_name(_bone.Spine2)
	sk.add_child(_pack_att)
	pack = MeshInstance3D.new()
	pack.mesh = gear_mesh("pack", 2)
	pack.scale = Vector3.ONE / _skel_scale
	pack.position = Vector3(0, 4.0, -15.0) * _u
	pack.material_override = _mat("pack", Color("5a4a2e"), 0.9)
	_pack_att.add_child(pack)

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

func set_gear(_vest: int, helmet_lvl: int, pack_lvl: int) -> void:
	helmet.visible = helmet_lvl > 0
	pack.visible = pack_lvl > 0
	if helmet_lvl > 0:
		helmet.mesh = gear_mesh("helmet", helmet_lvl)
		helmet.material_override = null
	if pack_lvl > 0:
		pack.mesh = gear_mesh("pack", pack_lvl)
		pack.material_override = null

static var _gear_cache := {}

## Helmets (level 1 light shell, 2 military with ear guards and NVG mount,
## 3 heavy dark shell) and backpacks (bigger and with more pockets per level).
## Built in metres in bone space: +Z is the front of the body.
static func gear_mesh(kind: String, lvl: int) -> ArrayMesh:
	var key := "%s%d" % [kind, lvl]
	if _gear_cache.has(key): return _gear_cache[key]
	var parts := []      # [mesh, position, rotation, scale, colour]
	if kind == "helmet":
		var col: Color = [Color.WHITE, Color("8c8670"), Color("4f5d3a"), Color("2a2d2a")][lvl]
		var dome := SphereMesh.new()
		dome.radius = 0.138 + lvl * 0.004
		dome.height = 0.2 + lvl * 0.01
		dome.is_hemisphere = true
		dome.radial_segments = 20
		dome.rings = 8
		parts.append([dome, Vector3(0, -0.005, -0.005), Vector3.ZERO, Vector3(1, 1, 1.1), col])
		var rim := CylinderMesh.new()
		rim.top_radius = 0.142 + lvl * 0.004
		rim.bottom_radius = 0.149 + lvl * 0.004
		rim.height = 0.022
		rim.radial_segments = 20
		parts.append([rim, Vector3(0, 0.0, -0.005), Vector3.ZERO, Vector3(1, 1, 1.1), col.darkened(0.25)])
		if lvl >= 2:
			for x in [-1.0, 1.0]:
				var ear := BoxMesh.new()
				ear.size = Vector3(0.025, 0.085, 0.11)
				parts.append([ear, Vector3(x * 0.142, -0.045, -0.02), Vector3(0, 0, x * 0.12), Vector3.ONE, col.darkened(0.1)])
			var nvg := BoxMesh.new()
			nvg.size = Vector3(0.05, 0.035, 0.02)
			parts.append([nvg, Vector3(0, 0.055, 0.15), Vector3(-0.35, 0, 0), Vector3.ONE, Color(0.1, 0.1, 0.1)])
			var strap := CylinderMesh.new()
			strap.top_radius = 0.152
			strap.bottom_radius = 0.152
			strap.height = 0.018
			strap.radial_segments = 20
			parts.append([strap, Vector3(0, 0.05, -0.005), Vector3.ZERO, Vector3(1, 1, 1.1), col.darkened(0.45)])
		if lvl == 3:
			var visor := BoxMesh.new()
			visor.size = Vector3(0.2, 0.05, 0.02)
			parts.append([visor, Vector3(0, -0.02, 0.155), Vector3(0.2, 0, 0), Vector3.ONE, Color(0.06, 0.06, 0.07)])
	else:
		var col: Color = [Color.WHITE, Color("6e5c40"), Color("4e5236"), Color("3a3a30")][lvl]
		var sc: float = [1.0, 0.85, 1.0, 1.15][lvl]
		var b := func(sz: Vector3) -> BoxMesh:
			var m := BoxMesh.new()
			m.size = sz * sc
			return m
		parts.append([b.call(Vector3(0.3, 0.38, 0.16)), Vector3(0, 0, 0), Vector3.ZERO, Vector3.ONE, col])
		parts.append([b.call(Vector3(0.31, 0.07, 0.17)), Vector3(0, 0.2 * sc, 0.0), Vector3(0.1, 0, 0), Vector3.ONE, col.darkened(0.15)])
		parts.append([b.call(Vector3(0.22, 0.15, 0.05)), Vector3(0, -0.08 * sc, -0.1 * sc), Vector3.ZERO, Vector3.ONE, col.darkened(0.08)])
		for x in [-1.0, 1.0]:
			parts.append([b.call(Vector3(0.05, 0.18, 0.1)), Vector3(x * 0.17 * sc, -0.05 * sc, 0), Vector3.ZERO, Vector3.ONE, col.darkened(0.12)])
			parts.append([b.call(Vector3(0.04, 0.4, 0.015)), Vector3(x * 0.08 * sc, 0.0, 0.09 * sc), Vector3.ZERO, Vector3.ONE, Color(0.1, 0.1, 0.1)])
		if lvl >= 2:
			var roll := CylinderMesh.new()
			roll.top_radius = 0.055 * sc
			roll.bottom_radius = 0.055 * sc
			roll.height = 0.34 * sc
			parts.append([roll, Vector3(0, 0.26 * sc, -0.01), Vector3(0, 0, PI / 2), Vector3.ONE, Color("3f4a3a") if lvl == 2 else Color("2a3a4a")])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pt in parts:
		var tmp := SurfaceTool.new()
		tmp.create_from(pt[0], 0)
		var arr := tmp.commit_to_arrays()
		var n: int = arr[Mesh.ARRAY_VERTEX].size()
		var cols := PackedColorArray()
		cols.resize(n)
		cols.fill(pt[4])
		arr[Mesh.ARRAY_COLOR] = cols
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		st.append_from(am, 0, Transform3D(Basis.from_euler(pt[2]).scaled(pt[3]), pt[1]))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.6 if kind == "helmet" else 0.92
	st.set_material(m)
	var mesh := st.commit()
	_gear_cache[key] = mesh
	return mesh

var _style := ""
var _panda: Node3D

## Outfit style: "gold" plates the armour in gold, "panda" adds a panda mask.
func set_style(style: String) -> void:
	if style == _style: return
	_style = style
	for mi in sk.get_children():
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
func play_action(name: String, seconds: float) -> void:
	var a: Animation = ap.get_animation("mx/" + name)
	if a == null: return
	_action = name
	_action_t = seconds
	_action_speed = a.length / seconds
	_anim = ""
	ap.play("mx/" + name, 0.1)

## Direction of travel relative to facing, in eight sectors.
func _dir8() -> String:
	if move_local.length() < 0.05: return "f"
	var k := wrapi(int(round(atan2(move_local.x, move_local.y) / (PI / 4.0))), 0, 8)
	return ["f", "fr", "r", "br", "b", "bl", "l", "fl"][k]

## Locomotion clip with its playback speed matched to the real ground speed.
func _play_moving(name: String, speed: float, max_scale := 2.2) -> void:
	var a: Animation = ap.get_animation(name)
	var clip_speed: float = a.get_meta("speed", 2.0) if a else 2.0
	_play(name, clampf(speed / maxf(clip_speed, 0.15), 0.4, max_scale))

## Dead: keep playing the death animation until it ends (owners stop calling set_pose).
func _process(delta: float) -> void:
	if _anim.begins_with("mx/death") and ap.current_animation_position < ap.current_animation_length:
		ap.advance(delta)
	else:
		set_process(false)

## The soldier's own clips; other characters use the Mixamo equivalents.
const FALLBACK := {"Idle": "mx/idle", "Walk": "mx/walk_f", "Run": "mx/run_f"}

func _play(name: String, speed_scale: float) -> void:
	if not ap.has_animation(name) and FALLBACK.has(name): name = FALLBACK[name]
	if _anim != name:
		# Cross-fade time runs at the clip's speed: keep it ~0.2 s of real time.
		ap.play(name, clampf(0.2 * absf(speed_scale), 0.0, 0.4))
		_anim = name
	ap.speed_scale = speed_scale

## pose: "stand" | "crouch" | "prone" | "fall" | "chute" | "dead"
func set_pose(pose: String, speed: float, armed: bool, delta: float, t: float) -> void:
	# One-shot action (grenade toss) takes over the whole body for a moment.
	if _action_t > 0.0:
		_action_t -= delta
		_play("mx/" + _action, _action_speed)
		ap.advance(delta)
		gun.visible = false
		body.position = Vector3.ZERO
		body.rotation = Vector3.ZERO
		canopy.visible = false
		return
	if pose == "dead":
		# A death animation plays once by itself (see _process) and stays down.
		if not _anim.begins_with("mx/death"):
			_play("mx/" + (death_anim if death_anim != "" else DEATHS[randi() % DEATHS.size()]), 1.0)
			set_process(true)
		gun.visible = false
		canopy.visible = false
		body.position = Vector3.ZERO
		body.rotation = Vector3.ZERO
		return
	# Base animation from the ground speed and its direction (8-way rifle set).
	var dir := _dir8()
	if pose == "stand" and speed > 0.3:
		var set := "walk_"
		if sprinting and dir in ["f", "fl", "fr"]: set = "sprint_"
		elif speed > 3.2: set = "run_"
		_play_moving("mx/" + set + dir, speed)
	elif pose == "crouch" and speed > 0.3:
		_play_moving("mx/crouch_" + dir, speed)
	elif pose == "crouch":
		_play("mx/idle_crouch_aim" if aiming else "mx/idle_crouch", 1.0)
	elif pose == "airborne":
		_play("mx/jump_up" if vel_y > 1.0 else ("mx/fall" if vel_y < -9.0 else "mx/jump_loop"), 1.0)
	elif swimming and pose in ["stand", "crouch", "prone"]:
		_play("mx/swim_tread", 1.0)
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
	elif pose == "stand" and armed and aiming:
		_play("mx/fire" if recoil > 0.3 else "mx/idle_aim", 1.0)
	elif pose == "stand" and armed:
		_play("mx/idle", 1.0)
	else:
		_play("Idle", 1.0)
	ap.advance(delta)
	if _back_dirty and is_inside_tree(): _place_back()
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	_gun_drop = 0.0
	canopy.visible = pose == "chute"
	if canopy.visible:
		var e := ease(clampf(chute_open, 0.0, 1.0), 0.4)
		canopy.scale = Vector3(lerpf(0.12, 1.0, e), lerpf(0.3, 1.0, e), lerpf(0.35, 1.0, e))
	gun.visible = _has_weapon and pose in ["stand", "crouch", "prone", "airborne"]
	# Crawling, knocked down or swimming: hands are busy, the gun is put away.
	if swimming or (pose == "prone" and (downed or _anim == "mx/prone_f")): gun.visible = false
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
			body.position.y = -0.6
			if ride == "bike":
				# Astride: hands on the grips (turning with the bars), feet on the pegs.
				for side in [["Left", -1.0], ["Right", 1.0]]:
					var sd: float = side[1]
					_arm(side[0], Vector3(sd * 0.32, 0.58 + sd * steer * 0.04, -0.55 - sd * steer * 0.08), Vector3(sd, -1, 0.3))
					_leg(side[0], Vector3(sd * 0.2, -0.08, -0.18), Vector3(0, 0.5, -1))
				return
			if ride == "boat":
				# On the stern bench: right hand on the tiller, left on the knee.
				_arm("Right", Vector3(0.36, 0.66, 0.1 + steer * 0.12), Vector3(1, -1, 0))
				_arm("Left", Vector3(-0.16, 0.45, -0.28), Vector3(-1, -1, 0))
				_leg("Left", Vector3(-0.16, -0.18, -0.5), Vector3(0, 0.5, -1))
				_leg("Right", Vector3(0.16, -0.18, -0.5), Vector3(0, 0.5, -1))
				return
			var a := steer * 0.9
			for side in [["Left", -1.0], ["Right", 1.0]]:
				var ang: float = (PI * 0.5 + 0.35) * side[1] + a
				_arm(side[0], Vector3(sin(ang) * 0.17, 1.02 + cos(ang) * 0.17 * 0.8, -0.42), Vector3(side[1], -1, 0.5))
				_leg(side[0], Vector3(side[1] * 0.16, 0.02, -0.62), Vector3(0, 1, -1))
		"chute":
			# Hands on the toggles; pulling one down turns, both down flares.
			var pl := 0.4 * maxf(-steer, 0.0) + 0.35 * brake
			var pr := 0.4 * maxf(steer, 0.0) + 0.35 * brake
			_arm("Left", Vector3(-0.27, 2.05 - pl, -0.02), Vector3(-1, 0, 0.3))
			_arm("Right", Vector3(0.27, 2.05 - pr, -0.02), Vector3(1, 0, 0.3))
			var sw := sin(t * 1.7) * 0.05
			_leg("Left", Vector3(-0.13, 0.06, -0.12 + sw), Vector3(0, 0, -1))
			_leg("Right", Vector3(0.13, 0.04, -0.06 - sw), Vector3(0, 0, -1))
	if pose in ["stand", "crouch"] and not swimming:
		_plant_feet(delta)
	else:
		_hip_drop = 0.0
	if absf(peek) > 0.01 and pose in ["stand", "crouch"]:
		body.position.x += peek * PEEK_SHIFT     # weight onto the outer foot
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
		if pose in ["stand", "crouch"] and not swimming:
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
		# Ready: muzzle a little down and inwards.
		pos = Vector3(0.12, 1.32, -0.22) if not pistol else Vector3(0.12, 1.15, -0.28)
		rot = Vector3(-0.22, 0.2, 0.06) if not pistol else Vector3(-0.6, 0.2, 0)
	if reload_p >= 0.0:
		# Gun brought in front of the chest and rolled to see the magazine well.
		var k := sin(clampf(reload_p, 0.0, 1.0) * PI)
		pos = pos.lerp(Vector3(0.1, 1.3, -0.2), k)
		rot = rot.lerp(Vector3(0.1, 0.3, 0.55), k)
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

const PEEK_ROLL := 0.36      # radians the upper body tilts when leaning
const PEEK_SHIFT := 0.22     # metres the body shifts sideways

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
	_arm("Right", to_local * grip, Vector3(1, -1, 0.4))
	if _cls in ["pistol", "melee"] and not aiming and p < 0.0:
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
