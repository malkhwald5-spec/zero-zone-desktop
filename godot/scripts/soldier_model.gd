class_name SoldierModel
extends Node3D
## A procedurally built soldier (≈1.8 m tall, facing -Z like Godot cameras).
## Kept behind a small API (set_pose / set_gear / set_weapon) so it can later be
## replaced by an imported, animated character model.

var rig: Node3D      # pose tilts/offsets go here; the root keeps the facing (yaw)
var hip: Node3D
var spine: Node3D
var legs := []       # [{thigh, knee}]
var arms := []       # [{shoulder, elbow}]
var gun: Node3D
var gun_body: MeshInstance3D
var gun_barrel: MeshInstance3D
var gun_mag: MeshInstance3D
var vest: MeshInstance3D
var helmet: MeshInstance3D
var pack: MeshInstance3D
var canopy: MeshInstance3D
var hair: MeshInstance3D
var mats := {}
var walk_phase := 0.0
var _has_weapon := false

static var _meshes := {}

static func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh
	match key:
		"thigh": m = _capsule(0.075, 0.42)
		"shin": m = _capsule(0.065, 0.42)
		"upper": m = _capsule(0.052, 0.3)
		"fore": m = _capsule(0.046, 0.3)
		"torso": m = _capsule(0.17, 0.55)
		"head":
			m = SphereMesh.new(); m.radius = 0.115; m.height = 0.24
		"helmet":
			m = SphereMesh.new(); m.radius = 0.135; m.height = 0.2; m.is_hemisphere = true
		"hair":
			m = SphereMesh.new(); m.radius = 0.122; m.height = 0.17; m.is_hemisphere = true
		"eye":
			m = SphereMesh.new(); m.radius = 0.014; m.height = 0.028
		"brow": m = _box(Vector3(0.045, 0.01, 0.012))
		"nose": m = _box(Vector3(0.024, 0.04, 0.03))
		"neck": m = _capsule(0.05, 0.14)
		"hand":
			m = SphereMesh.new(); m.radius = 0.05; m.height = 0.1
		"boot": m = _box(Vector3(0.12, 0.08, 0.24))
		"hips": m = _box(Vector3(0.32, 0.16, 0.2))
		"vest": m = _box(Vector3(0.38, 0.36, 0.28))
		"pack": m = _box(Vector3(0.32, 0.4, 0.18))
		"gunbody": m = _box(Vector3(0.06, 0.1, 1.0))
		"barrel":
			m = CylinderMesh.new(); m.top_radius = 0.016; m.bottom_radius = 0.016; m.height = 1.0
		"mag": m = _box(Vector3(0.045, 0.16, 0.07))
		"canopy":
			m = SphereMesh.new(); m.radius = 2.6; m.height = 1.4; m.is_hemisphere = true; m.radial_segments = 24; m.rings = 6
	_meshes[key] = m
	return m

static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 3
	return c

static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b

func _init(clothes: Color = Color("4a5d6b"), chute_color: Color = Color("c84f3a"), pants: Color = Color("33373d")) -> void:
	mats.skin = _mat(Color("d9a77f"), 0.7)
	mats.shirt = _mat(clothes, 0.85)
	mats.pants = _mat(pants, 0.9)
	mats.hair = _mat(Color("1c1712"), 0.8)
	mats.eye = _mat(Color("15110e"), 0.3)
	mats.boots = _mat(Color("1d1d1f"), 0.6)
	mats.vest = _mat(Color("4e6fa8"), 0.8)
	mats.helmet = _mat(Color("5a7a4a"), 0.5)
	mats.pack = _mat(Color("5a4a2e"), 0.9)
	mats.gun = _mat(Color("1f2124"), 0.35, 0.6)
	mats.chute = _mat(chute_color, 0.8)
	mats.chute.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build()

func _mat(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _part(mesh_key: String, mat: Material, parent: Node3D, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(mesh_key)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build() -> void:
	rig = Node3D.new()
	add_child(rig)
	hip = Node3D.new()
	hip.position.y = 0.95
	rig.add_child(hip)
	_part("hips", mats.pants, hip, Vector3(0, 0.02, 0))
	for side in [-1, 1]:
		var thigh := Node3D.new()
		thigh.position = Vector3(0.1 * side, 0, 0)
		hip.add_child(thigh)
		_part("thigh", mats.pants, thigh, Vector3(0, -0.22, 0))
		var knee := Node3D.new()
		knee.position.y = -0.45
		thigh.add_child(knee)
		_part("shin", mats.pants, knee, Vector3(0, -0.22, 0))
		_part("boot", mats.boots, knee, Vector3(0, -0.47, -0.04))
		legs.append({"thigh": thigh, "knee": knee})

	spine = Node3D.new()
	spine.position.y = 0.08
	hip.add_child(spine)
	var torso := _part("torso", mats.shirt, spine, Vector3(0, 0.3, 0))
	torso.scale = Vector3(1.15, 1, 0.8)
	vest = _part("vest", mats.vest, spine, Vector3(0, 0.33, 0))
	_part("neck", mats.skin, spine, Vector3(0, 0.62, -0.01))
	var head := _part("head", mats.skin, spine, Vector3(0, 0.75, -0.02))
	head.scale = Vector3(0.95, 1.05, 1.0)
	for side in [-1, 1]:
		_part("eye", mats.eye, spine, Vector3(0.042 * side, 0.765, -0.128))
		var brow := _part("brow", mats.hair, spine, Vector3(0.042 * side, 0.792, -0.124))
		brow.rotation.z = -0.12 * side
	_part("nose", mats.skin, spine, Vector3(0, 0.74, -0.13))
	hair = _part("hair", mats.hair, spine, Vector3(0, 0.785, 0.0))
	hair.scale = Vector3(1.0, 1.1, 1.08)
	hair.visible = false
	helmet = _part("helmet", mats.helmet, spine, Vector3(0, 0.79, -0.01))
	pack = _part("pack", mats.pack, spine, Vector3(0, 0.36, 0.23))

	for side in [-1, 1]:
		var sh := Node3D.new()
		sh.position = Vector3(0.24 * side, 0.55, 0)
		spine.add_child(sh)
		_part("upper", mats.shirt, sh, Vector3(0, -0.16, 0))
		var el := Node3D.new()
		el.position.y = -0.32
		sh.add_child(el)
		_part("fore", mats.shirt, el, Vector3(0, -0.15, 0))
		_part("hand", mats.skin, el, Vector3(0, -0.33, 0))
		arms.append({"shoulder": sh, "elbow": el})

	# Weapon held at chest height, pointing forward (-Z).
	gun = Node3D.new()
	gun.position = Vector3(0.14, 0.42, -0.25)
	spine.add_child(gun)
	gun_body = _part("gunbody", mats.gun, gun)
	gun_barrel = _part("barrel", mats.gun, gun)
	gun_barrel.rotation.x = PI / 2
	gun_mag = _part("mag", mats.gun, gun, Vector3(0, -0.11, -0.1))

	canopy = _part("canopy", mats.chute, self, Vector3(0, 4.6, 0))
	canopy.visible = false
	set_weapon("")

func set_weapon(cls: String) -> void:
	_has_weapon = cls != ""
	gun.visible = _has_weapon
	if cls == "":
		return
	var len := {"pistol": 0.25, "smg": 0.5, "shotgun": 0.8, "ar": 0.85, "dmr": 0.95, "sr": 1.1, "lmg": 0.95}.get(cls, 0.8) as float
	gun_body.scale = Vector3(1, 1, len * 0.6)
	gun_body.position.z = -len * 0.1
	gun_barrel.scale = Vector3(1, len * 0.55, 1)
	gun_barrel.position.z = -len * 0.55
	gun_mag.visible = cls != "shotgun" and cls != "sr"

func set_gear(vest_lvl: int, helmet_lvl: int, pack_lvl: int) -> void:
	vest.visible = vest_lvl > 0
	helmet.visible = helmet_lvl > 0
	hair.visible = helmet_lvl == 0
	pack.visible = pack_lvl > 0
	var vc := [Color.WHITE, Color("8d9a6b"), Color("4e6fa8"), Color("2b2b2b")]
	var hc := [Color.WHITE, Color("a8a27c"), Color("5a7a4a"), Color("1e1e1e")]
	if vest_lvl > 0: mats.vest.albedo_color = vc[vest_lvl]
	if helmet_lvl > 0: mats.helmet.albedo_color = hc[helmet_lvl]

## pose: "stand" | "crouch" | "prone" | "fall" | "chute" | "dead"
## speed: ground speed (m/s) for the walk cycle; armed: holding a weapon.
func set_pose(pose: String, speed: float, armed: bool, delta: float, t: float) -> void:
	if speed > 0.3:
		walk_phase += delta * speed * (2.2 if pose == "stand" else 1.6)
	var sw := sin(walk_phase) if speed > 0.3 else 0.0
	var sw2 := sin(walk_phase + PI) if speed > 0.3 else 0.0
	rig.rotation = Vector3.ZERO
	rig.position = Vector3.ZERO
	hip.position.y = 0.95
	spine.rotation = Vector3.ZERO
	var th := [sw * 0.6, sw2 * 0.6]
	var kn := [maxf(0.0, -sw) * 0.9, maxf(0.0, -sw2) * 0.9]
	# Arm rotations (index 0 = left, 1 = right): x pitches the arm forward/up, z spreads it.
	var sh := [Vector3(1.45, -0.45, 0.25), Vector3(1.2, 0, -0.1)] if armed else [Vector3(sw2 * 0.4, 0, -0.08), Vector3(sw * 0.4, 0, 0.08)]
	var el := [0.45, 0.35] if armed else [0.15, 0.15]
	match pose:
		"crouch":
			hip.position.y = 0.6
			th = [1.3 + sw * 0.15, 1.3 + sw2 * 0.15]
			kn = [2.1, 2.1]
			spine.rotation.x = -0.25
		"prone", "dead":
			rig.rotation.x = -PI / 2 if pose == "prone" else PI / 2
			rig.position = Vector3(0, 0.18, 0.9 if pose == "prone" else -0.9)
			th = [sw * 0.2, sw2 * 0.2]
			kn = [0.0, 0.0]
			if pose == "prone" and armed:
				sh = [Vector3(2.75, -0.3, 0.2), Vector3(2.6, 0, -0.1)]
			elif pose == "dead":
				sh = [Vector3(0.3, 0, -1.3), Vector3(0.3, 0, 1.3)]
				el = [0.0, 0.0]
		"fall":
			rig.rotation.x = -PI / 2 + 0.3
			rig.position = Vector3(0, 0.3, 0.8)
			th = [0.3, 0.3]
			kn = [0.6, 0.6]
			sh = [Vector3(0.4, 0, -1.4 - sin(t * 8.0) * 0.05), Vector3(0.4, 0, 1.4)]
			el = [0.3, 0.3]
		"chute":
			th = [0.25 + sw * 0.1, 0.15]
			kn = [0.35, 0.35]
			sh = [Vector3(0, 0, -2.9), Vector3(0, 0, 2.9)]
			el = [0.2, 0.2]
	for i in 2:
		legs[i].thigh.rotation = Vector3(th[i], 0, 0.35 * (i * 2 - 1) if pose == "fall" else 0.0)
		legs[i].knee.rotation.x = -kn[i]
	for i in 2:
		arms[i].shoulder.rotation = sh[i]
		arms[i].elbow.rotation.x = el[i]
	canopy.visible = pose == "chute"
	gun.visible = _has_weapon and pose != "fall" and pose != "chute" and pose != "dead"
