class_name WarTurret
extends StaticBody3D
## برج رشاش: a wooden tower inside a fort's wall with a machine gun on top
## that fires by itself at enemies it can see over the wall. Bought in the
## shop (or by the team's money); shot to pieces it falls.

const RANGE := 85.0
const DMG := 8.0
const HP := 900.0
const GUN_Y := 7.6

var world: Node
var team := 0
var hp := HP
var dead := false
var display_name := "برج رشاش"
var _gun: Node3D
var _target: Node3D = null
var _look_t := randf() * 0.5
var _fire_t := 0.0
var _burst := 0

func _ready() -> void:
	add_to_group("bloodless")
	var wood := WorldBuilder._static_wall("planks", 1.5, 0.3, 0.85)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-1.3, 1.3]:
		for z in [-1.3, 1.3]:
			War._box(st, Vector3(x, 3.2, z), Vector3(0.3, 6.6, 0.3))
	War._box(st, Vector3(0, 6.6, 0), Vector3(3.4, 0.25, 3.4))
	# Cross braces.
	War._box(st, Vector3(0, 2.4, -1.3), Vector3(2.6, 0.2, 0.15))
	War._box(st, Vector3(0, 2.4, 1.3), Vector3(2.6, 0.2, 0.15))
	War._box(st, Vector3(-1.3, 4.4, 0), Vector3(0.15, 0.2, 2.6))
	War._box(st, Vector3(1.3, 4.4, 0), Vector3(0.15, 0.2, 2.6))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = wood
	add_child(mi)
	# Sandbags round the platform.
	var bags := SurfaceTool.new()
	bags.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 4:
		var d := Vector2(0, 1.5).rotated(k * PI * 0.5)
		War._box(bags, Vector3(d.x, 7.1, d.y), Vector3(3.2, 0.7, 0.5) if k % 2 == 0 else Vector3(0.5, 0.7, 3.2))
	var bm := MeshInstance3D.new()
	bm.mesh = bags.commit()
	bm.material_override = _sand_mat()
	add_child(bm)
	War._shape(self, Vector3(0, 3.4, 0), Vector3(3.0, 6.8, 3.0))
	War._shape(self, Vector3(0, 7.1, 0), Vector3(3.4, 0.8, 3.4))
	# The gun on its post.
	_gun = Node3D.new()
	_gun.position = Vector3(0, GUN_Y, 0)
	add_child(_gun)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	dark.metallic = 0.7
	dark.roughness = 0.4
	for part in [[Vector3(0, 0, -0.35), Vector3(0.18, 0.2, 1.2)], [Vector3(0, 0.02, -1.2), Vector3(0.07, 0.07, 0.9)], [Vector3(0, -0.2, 0.1), Vector3(0.1, 0.4, 0.1)]]:
		var pm := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = part[1]
		pm.mesh = b
		pm.material_override = dark
		pm.position = part[0]
		_gun.add_child(pm)
	var flag := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.6)
	flag.mesh = q
	var fm := StandardMaterial3D.new()
	fm.albedo_color = War.TEAMS[team].col
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = fm
	flag.position = Vector3(1.5, 8.6, 1.5)
	add_child(flag)

static var _sand: Material
static func _sand_mat() -> Material:
	if _sand == null:
		_sand = WorldBuilder._static_wall("sand", 1.2, 0.2, 0.95)
		(_sand as ShaderMaterial).set_shader_parameter("tint", Color("d8c39a"))
	return _sand

func take_damage(amount: float, attacker: Node, _head := false) -> bool:
	if dead: return false
	if attacker != null and "team" in attacker and attacker.team == team: return false
	if world.war and world.war.prep_left > 0.0: return false
	hp -= amount * 0.5
	if hp <= 0.0:
		_fall()
	return false

func _fall() -> void:
	dead = true
	world.effects.explosion(global_position + Vector3(0, GUN_Y, 0))
	world.sound_boom(global_position, 0.0, 1.2)
	world.effects.smoke_cloud(global_position + Vector3(0, 3, 0), 40.0, Color(0.2, 0.2, 0.2))
	var tw := create_tween()
	tw.tween_property(self, "rotation:z", 1.4, 1.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

func _process(delta: float) -> void:
	if dead or world == null or world.player == null: return
	if world.war and world.war.prep_left > 0.0: return
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = 0.4
		_target = _find()
	if _target == null or not is_instance_valid(_target) or _gone(_target):
		_target = null
		return
	var eye := global_position + Vector3(0, GUN_Y, 0)
	var aim: Vector3 = _target.global_position + Vector3(0, 1.1, 0)
	_gun.look_at(aim, Vector3.UP)
	_fire_t -= delta
	if _fire_t > 0.0: return
	if _burst <= 0: _burst = randi_range(4, 8)
	_burst -= 1
	_fire_t = 0.11 if _burst > 0 else randf_range(0.6, 1.1)
	var d := eye.distance_to(aim)
	var err := 0.3 + d * 0.025
	var to := aim + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * err
	var q := PhysicsRayQueryParameters3D.create(eye, eye + (to - eye).normalized() * (RANGE + 10.0), 1 | 2 | 4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit.position if hit else eye + (to - eye).normalized() * RANGE
	if global_position.distance_to(world.view_position()) < 400.0:
		world.effects.tracer(eye + (aim - eye).normalized() * 1.6, end)
		world.sound_shot("lmg", eye, false)
	if hit and hit.collider and hit.collider.has_method("take_damage") and hit.collider != self:
		hit.collider.take_damage(DMG, self, false)
	world.notify_shot(eye, self)

static func _gone(a: Node) -> bool:
	return ("dead" in a and a.dead) or ("state" in a and a.state == "dead")

## Nearest enemy in range it can see from the gun.
func _find() -> Node3D:
	var eye := global_position + Vector3(0, GUN_Y, 0)
	var best: Node3D = null
	var bd := RANGE
	var space := get_world_3d().direct_space_state
	for a in world.actors():
		if a.team == team or not a.on_ground(): continue
		var d: float = eye.distance_to(a.global_position)
		if d > bd: continue
		var q := PhysicsRayQueryParameters3D.create(eye, a.global_position + Vector3(0, 1.2, 0), 1)
		q.exclude = [get_rid()]
		if not space.intersect_ray(q).is_empty(): continue
		best = a
		bd = d
	return best
