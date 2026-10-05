class_name Vehicle
extends VehicleBody3D
## A drivable car (4 wheels, real suspension), facing +Z like Godot vehicles. The player gets in with F,
## drives with WASD (Space = handbrake) and gets out with F. Bullets damage
## it; at 0 health it blows up. Hitting someone at speed hurts them.

const MAX_FORCE := 3200.0
const MAX_STEER := 0.55
const MAX_SPEED := 32.0          # m/s (~115 km/h)
const MAX_HEALTH := 650.0
const BRAKE := 90.0

var world: Node
var display_name := "سيارة"
var health := MAX_HEALTH
var dead := false
var driver: Node3D = null
var throttle := 0.0              # -1..1
var steer_in := 0.0              # -1..1 (right positive)
var handbrake := false
var paint := Color("b8402f")
var _hit_cd := {}                # body -> seconds until it can be hit again
var _wheels: Array = []
var _flip_t := 0.0

func _ready() -> void:
	mass = 1150.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.1, 0)        # low, so it doesn't roll over in turns
	collision_layer = 1
	# People can't walk through cars, but a car is not stopped (or launched) by
	# people: hitting someone is handled as run-over damage instead.
	collision_mask = 1
	contact_monitor = false
	linear_damp = 0.05
	angular_damp = 1.2
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 0.8, 4.2)
	cs.shape = box
	cs.position.y = 0.85
	add_child(cs)
	var cab := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(1.6, 0.6, 2.0)
	cab.shape = cbox
	cab.position = Vector3(0, 1.55, -0.2)
	add_child(cab)
	_build_model()
	for x in [-0.82, 0.82]:
		for z in [-1.35, 1.35]:
			var w := VehicleWheel3D.new()
			w.position = Vector3(x, 0.5, z)
			w.wheel_radius = 0.38
			w.wheel_rest_length = 0.18
			w.suspension_travel = 0.22
			w.suspension_stiffness = 45.0
			w.suspension_max_force = 9000.0
			w.damping_compression = 0.9
			w.damping_relaxation = 1.1
			w.wheel_friction_slip = 2.6
			w.wheel_roll_influence = 0.08
			w.use_as_steering = z > 0.0          # front wheels (car faces +Z)
			w.use_as_traction = true
			add_child(w)
			var tyre := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.38
			tm.bottom_radius = 0.38
			tm.height = 0.26
			tm.radial_segments = 16
			tyre.mesh = tm
			tyre.rotation.z = PI / 2
			tyre.material_override = _mat(Color("161618"), 0.9)
			w.add_child(tyre)
			var hub := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = 0.2
			hm.bottom_radius = 0.2
			hm.height = 0.28
			hub.mesh = hm
			hub.rotation.z = PI / 2
			hub.material_override = _mat(Color("c9ced3"), 0.2, 0.9)
			w.add_child(hub)
			_wheels.append(w)

func _mat(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _part(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	add_child(mi)

func _build_model() -> void:
	var body := _mat(paint, 0.3, 0.4)
	var dark := _mat(Color("1d1f22"), 0.6)
	var glass := _mat(Color(0.25, 0.35, 0.45, 0.7), 0.05, 0.3)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_part(Vector3(1.8, 0.55, 4.2), Vector3(0, 0.8, 0), body)                       # lower body
	_part(Vector3(1.78, 0.2, 1.3), Vector3(0, 1.12, 1.4), body, Vector3(-0.06, 0, 0)) # bonnet
	_part(Vector3(1.6, 0.62, 2.0), Vector3(0, 1.4, -0.2), glass)                    # cabin glass
	_part(Vector3(1.62, 0.08, 2.0), Vector3(0, 1.74, -0.2), body)                   # roof
	for x in [-0.78, 0.78]:
		_part(Vector3(0.06, 0.62, 0.08), Vector3(x, 1.42, 0.78), body)              # pillars
		_part(Vector3(0.06, 0.62, 0.08), Vector3(x, 1.42, -1.18), body)
	_part(Vector3(1.85, 0.18, 0.1), Vector3(0, 0.62, -2.12), dark)                  # bumpers
	_part(Vector3(1.85, 0.18, 0.1), Vector3(0, 0.62, 2.12), dark)
	var lamp := _mat(Color("fff4cf"), 0.1)
	lamp.emission_enabled = true
	lamp.emission = Color("fff4cf")
	lamp.emission_energy_multiplier = 0.6
	var tail := _mat(Color("c21f1f"), 0.3)
	for x in [-0.62, 0.62]:
		_part(Vector3(0.36, 0.14, 0.04), Vector3(x, 0.92, 2.11), lamp)
		_part(Vector3(0.3, 0.12, 0.04), Vector3(x, 0.92, -2.11), tail)

## Forward speed in m/s (positive when moving forward).
func speed() -> float:
	return linear_velocity.dot(global_basis.z)

func _physics_process(delta: float) -> void:
	# Safety net: if the body ever sinks into the terrain, put it back on top.
	var g: float = world.ground_height(global_position)
	if global_position.y < g - 1.5 and not world.is_deep(global_position):
		global_position.y = g + 0.8
		linear_velocity = Vector3(linear_velocity.x, 0.0, linear_velocity.z) * 0.5
	if dead: return
	# On its roof or side and stopped for a moment: put it back on its wheels.
	if global_basis.y.y < 0.4 and linear_velocity.length() < 1.5:
		_flip_t += delta
		if _flip_t > 2.5:
			_flip_t = 0.0
			var fwd := Vector3(global_basis.z.x, 0.0, global_basis.z.z).normalized()
			global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), global_position + Vector3(0, 1.2, 0))
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_flip_t = 0.0
	var sp := speed()
	if driver:
		# A resting body falls asleep and would ignore the engine: keep it awake.
		if sleeping and (absf(throttle) > 0.01 or absf(steer_in) > 0.01): sleeping = false
		var t := throttle
		# Brake first when asked to go the other way.
		if (t < 0.0 and sp > 4.0) or (t > 0.0 and sp < -4.0):
			# Braking: wheel brakes plus engine braking against the motion.
			engine_force = -signf(sp) * MAX_FORCE * 1.2
			brake = BRAKE
		else:
			# Coasting: engine braking, and hold still when nearly stopped (no rolling downhill).
			brake = (BRAKE if absf(sp) < 3.0 else BRAKE * 0.25) if absf(t) < 0.01 else 0.0
			engine_force = t * MAX_FORCE * (1.0 if absf(sp) < MAX_SPEED else 0.0) * (0.5 if t < 0.0 else 1.0)
		if handbrake:
			engine_force = 0.0
			brake = BRAKE * 1.5
		# Less steering at speed (no rollovers); positive steering turns left.
		var steer_target := -steer_in * MAX_STEER * clampf(1.0 - absf(sp) / 30.0, 0.18, 1.0)
		steering = move_toward(steering, steer_target, delta * 2.5)
	else:
		# Nobody driving: roll to a stop within a few metres.
		engine_force = -signf(sp) * MAX_FORCE * 0.6 if absf(sp) > 1.0 else 0.0
		brake = BRAKE
		steering = move_toward(steering, 0.0, delta)
	# Running people over.
	for k in _hit_cd.keys():
		_hit_cd[k] -= delta
		if _hit_cd[k] <= 0.0: _hit_cd.erase(k)
	if absf(sp) > 6.0:
		# Anyone just in front of (or behind, when reversing) the moving car gets hit.
		var fwd: Vector3 = global_basis.z * signf(sp)
		for b in world.actors():
			if b == driver or _hit_cd.has(b) or not b.on_ground(): continue
			var to: Vector3 = b.global_position - global_position
			to.y = 0.0
			if to.length() < 3.0 and to.normalized().dot(fwd) > 0.35:
				_hit_cd[b] = 0.7
				b.take_damage(absf(sp) * 3.2, driver if driver else self, false)
	# Drowned in deep water: the engine dies.
	if global_position.y < Island.WATER - 1.0 and world.is_deep(global_position):
		take_damage(MAX_HEALTH * 2.0, null)

func take_damage(amount: float, attacker: Node, _head := false) -> bool:
	if dead: return false
	health -= amount
	if health <= 0.0:
		dead = true
		engine_force = 0.0
		brake = 20.0
		var who := driver
		if who and who.has_method("exit_vehicle"): who.exit_vehicle()
		world.explode(global_position + Vector3(0, 1.0, 0), attacker if attacker else self, [get_rid()])
		for c in get_children():
			if c is MeshInstance3D: c.material_override = _mat(Color("1b1a19"), 1.0)
		return true
	return false
