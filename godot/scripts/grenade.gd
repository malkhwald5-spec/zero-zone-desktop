class_name Grenade
extends RigidBody3D
## A thrown grenade. Bounces off the world and goes off after its fuse:
## frag = explosion that hurts everyone nearby who is not behind cover,
## smoke = a thick cloud that blocks sight for a while,
## molotov = a bottle that bursts into flames where it lands,
## flash = a blinding bang after a short fuse.

const FUSE := 4.0
const FRAG_RADIUS := 9.0
const FRAG_DAMAGE := 125.0

var world: Node
var kind := "frag"            # frag | smoke | molotov | flash
var thrower: Node = null
var _t := 0.0

static var _models := {}

## Grenade model (Fab: pineapple frag, smoke canister), all surfaces merged.
static func model_mesh(kind: String) -> Mesh:
	if _models.has(kind): return _models[kind]
	if kind == "molotov":
		_models[kind] = _bottle()
		return _models[kind]
	if kind == "flash" and _models.has("smoke"):
		return _models["smoke"]
	var scene: Node3D = load("res://assets/models/grenades/%s.fbx" % ("frag" if kind == "frag" else "smoke")).instantiate()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		var m: Mesh = mi.mesh
		# The models sit off-centre in their files: centre them on the origin, base at y = 0.
		var ab: AABB = mi.transform * mi.get_aabb()
		var xf: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-ab.get_center().x, -ab.position.y, -ab.get_center().z)) * mi.transform
		for i in m.get_surface_count():
			st.append_from(m, i, xf)
	scene.free()
	var mesh := st.commit()
	_models[kind] = mesh
	return mesh
## Glass bottle with a rag in the neck (built from cylinders).
static func _bottle() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [[0.045, 0.045, 0.19, 0.095], [0.045, 0.016, 0.05, 0.215], [0.016, 0.016, 0.06, 0.27], [0.012, 0.02, 0.06, 0.32]]
	for pt in parts:
		var c := CylinderMesh.new()
		c.top_radius = pt[1]
		c.bottom_radius = pt[0]
		c.height = pt[2]
		c.radial_segments = 12
		c.rings = 1
		st.append_from(c, 0, Transform3D(Basis.IDENTITY, Vector3(0, pt[3], 0)))
	return st.commit()

static var _mats := {}

func _ready() -> void:
	collision_layer = 8
	collision_mask = 1
	continuous_cd = true
	mass = 0.4
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	physics_material_override = pm
	linear_damp = 0.05
	angular_damp = 1.0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.07
	cs.shape = sh
	add_child(cs)
	if not _mats.has(kind):
		var m := StandardMaterial3D.new()
		m.albedo_color = {"frag": Color("3d4a2c"), "smoke": Color("8a8f94"), "molotov": Color(0.35, 0.5, 0.3, 0.85), "flash": Color("4a6a8a")}[kind]
		m.roughness = 0.6 if kind != "molotov" else 0.15
		if kind == "molotov":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[kind] = m
	if kind == "molotov":
		# Bursts on the first thing it hits.
		contact_monitor = true
		max_contacts_reported = 1
		body_entered.connect(func(_b): _burst())
	var mi := MeshInstance3D.new()
	mi.mesh = model_mesh(kind)
	mi.material_override = _mats[kind]
	mi.position.y = -0.065
	add_child(mi)

func _physics_process(delta: float) -> void:
	_t += delta
	if kind == "molotov":
		if _t > 0.08 and get_contact_count() > 0: _burst()
		elif _t > 6.0: _burst()
		return
	if _t >= (2.0 if kind == "flash" else FUSE):
		match kind:
			"frag": world.explode(global_position + Vector3(0, 0.15, 0), thrower)
			"flash": world.flashbang(global_position + Vector3(0, 0.15, 0), thrower)
			_: world.add_smoke(global_position)
		queue_free()

var _burst_done := false

func _burst() -> void:
	if _burst_done or _t < 0.08: return
	_burst_done = true
	world.add_fire(global_position, thrower)
	queue_free()

## Launch velocity that lands a throw from `from` at `to` with a ~40° arc
## (empty Vector3 if out of reach).
static func aim_velocity(from: Vector3, to: Vector3, max_speed := 24.0) -> Vector3:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	var d := flat.length()
	var h := to.y - from.y
	var th := deg_to_rad(40.0)
	var denom := 2.0 * pow(cos(th), 2) * (d * tan(th) - h)
	if denom <= 0.0: return Vector3.ZERO
	var v := sqrt(g * d * d / denom)
	if v > max_speed: return Vector3.ZERO
	return flat.normalized() * v * cos(th) + Vector3.UP * v * sin(th)
