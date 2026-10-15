class_name Vehicle
extends VehicleBody3D
## A drivable car, motorbike or boat, facing +Z like Godot vehicles. Cars and
## the bike have real wheels and suspension (the bike runs on two narrow pairs
## kept upright and leans into turns); the boat floats and is pushed by its
## outboard motor. The player gets in with F,
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
var kind := "sedan"              # "sedan" | "jeep" | "pickup" | "bike" | "boat" | "apc"
var team := -1                   # team war: whose armoured car it is
var _turret: Node3D              # armoured car: the gun on the roof
var _gun_cd := 0.0
var max_health := MAX_HEALTH
var max_speed := MAX_SPEED
var max_force := MAX_FORCE
var max_steer := MAX_STEER
var _lean_node: Node3D           # the bike's body and rider lean into turns
var lean := 0.0
var _tail_mat: StandardMaterial3D
var _engine: AudioStreamPlayer3D
var _dust: Array = []
var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var _gear := 1
var _hit_cd := {}                # body -> seconds until it can be hit again
var _wheels: Array = []
var _flip_t := 0.0

func _ready() -> void:
	if kind == "bike":
		_ready_bike()
		return
	if kind == "boat":
		_ready_boat()
		return
	if kind == "apc":
		_ready_apc()
		return
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
	# Body and cabin boxes: [size, centre] for each, the car facing +Z.
	var boxes: Array = {
		"sedan": [[Vector3(1.75, 0.7, 4.4), Vector3(0, 0.62, 0)], [Vector3(1.45, 0.5, 2.1), Vector3(0, 1.2, -0.15)]],
		"pickup": [[Vector3(1.85, 0.85, 5.1), Vector3(0, 0.85, 0)], [Vector3(1.7, 0.7, 1.9), Vector3(0, 1.62, 0.55)]],
	}.get(kind, [[Vector3(1.75, 0.85, 4.05), Vector3(0, 0.86, 0)], [Vector3(1.7, 0.8, 2.6), Vector3(0, 1.7, -0.7)]])
	for b in boxes: _add_box_shape(b[0], b[1])
	if kind == "pickup": mass = 1500.0
	_build_model()
	var imp := CarModels.imported(kind)
	for spot in imp.wheels:
		var c: Vector3 = spot[1]
		var w := VehicleWheel3D.new()
		w.position = c + Vector3(0, 0.18, 0)
		w.wheel_radius = imp.radius
		w.wheel_rest_length = 0.18
		w.suspension_travel = 0.22
		w.suspension_stiffness = 45.0
		w.suspension_max_force = 9000.0 * mass / 1150.0
		w.damping_compression = 0.9
		w.damping_relaxation = 1.1
		w.wheel_friction_slip = 2.6
		w.wheel_roll_influence = 0.08
		w.use_as_steering = c.z > 0.0          # front wheels (car faces +Z)
		w.use_as_traction = true
		add_child(w)
		var im := MeshInstance3D.new()
		im.mesh = spot[0]
		w.add_child(im)

func _ready_common(m: float) -> void:
	mass = m
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	collision_layer = 1
	collision_mask = 1
	contact_monitor = false
	linear_damp = 0.05
	angular_damp = 1.2

func _add_box_shape(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	add_child(cs)

func _ready_bike() -> void:
	max_health = 320.0
	health = max_health
	max_speed = 38.0
	max_force = 900.0
	max_steer = 0.42
	display_name = "موتور"
	_ready_common(230.0)
	center_of_mass = Vector3(0, 0.25, 0)
	angular_damp = 2.5
	_add_box_shape(Vector3(0.45, 0.5, 1.7), Vector3(0, 0.75, 0))
	_lean_node = Node3D.new()
	add_child(_lean_node)
	_tail_mat = _mat(Color("8a1010"), 0.25)
	var imp := CarModels.imported("bike")
	var body := MeshInstance3D.new()
	body.mesh = imp.body
	_lean_node.add_child(body)
	# Two narrow pairs of wheels keep it on its feet; one tyre of each pair is
	# drawn, moved to the middle.
	for iw in imp.wheels:
		var c: Vector3 = iw[1]
		for x in [-0.11, 0.11]:
			var w := VehicleWheel3D.new()
			w.position = Vector3(x, c.y + 0.12, c.z)
			w.wheel_radius = imp.radius
			w.wheel_rest_length = 0.12
			w.suspension_travel = 0.18
			w.suspension_stiffness = 40.0
			w.suspension_max_force = 3000.0
			w.damping_compression = 0.9
			w.damping_relaxation = 1.1
			w.wheel_friction_slip = 2.4
			w.wheel_roll_influence = 0.02
			w.use_as_steering = c.z > 0.0
			w.use_as_traction = c.z < 0.0
			add_child(w)
			_wheels.append(w)
			if x > 0.0:
				var mi := MeshInstance3D.new()
				mi.mesh = iw[0]
				mi.position.x = c.x - x
				w.add_child(mi)
	_effect_nodes(Vector3(0, 0.15, -0.95), [0.0], Vector3(0, 0.8, 0.5))

func _ready_boat() -> void:
	max_health = 500.0
	health = max_health
	max_speed = 18.0
	max_force = 5200.0
	display_name = "قارب"
	_ready_common(650.0)
	center_of_mass = Vector3(0, 0.1, -0.2)
	linear_damp = 0.0
	angular_damp = 0.8
	_add_box_shape(Vector3(2.3, 0.6, 5.2), Vector3(0, 0.45, 0))
	_tail_mat = _mat(Color("8a1010"), 0.25)
	var body := MeshInstance3D.new()
	body.mesh = CarModels.imported("boat").body
	add_child(body)
	_paint_surface(body, "GreenPlate", 0.35)
	_effect_nodes(Vector3(0, 0.1, -2.6), [-0.4, 0.4], Vector3(0, 0.9, -2.4))
	for d in _dust:
		var dm: StandardMaterial3D = d.mesh.material
		dm.albedo_color = Color(0.92, 0.95, 0.97, 0.7)

## مدرعة: a six-wheeled armoured car (team war, from the fort's shop). Slow
## and heavy, shrugs off most bullets, with a machine gun on the roof that
## the driver fires where the camera looks.
func _ready_apc() -> void:
	max_health = 2400.0
	health = max_health
	max_speed = 22.0
	max_force = 9000.0
	max_steer = 0.42
	display_name = "مدرعة"
	_ready_common(4200.0)
	center_of_mass = Vector3(0, 0.45, 0)
	_add_box_shape(Vector3(2.6, 1.5, 6.4), Vector3(0, 1.55, 0))
	_add_box_shape(Vector3(1.3, 0.6, 1.3), Vector3(0, 2.6, -0.3))
	var olive := _shared_mat("apc_olive", Color("56603f"), 0.75, 0.25)
	var dark := _shared_mat("apc_dark", Color("23261f"), 0.8, 0.2)
	var stripe := _mat(War.TEAMS[team].col if team >= 0 else Color("c9a03a"), 0.6)
	_tail_mat = _mat(Color("8a1010"), 0.25)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	War._box(st, Vector3(0, 1.15, 0), Vector3(2.5, 0.9, 6.3))          # lower hull
	War._box(st, Vector3(0, 1.95, -0.4), Vector3(2.3, 0.75, 5.0))      # upper hull
	War._box(st, Vector3(1.35, 1.6, -1.6), Vector3(0.3, 0.6, 2.2))      # side boxes
	War._box(st, Vector3(-1.35, 1.6, -1.6), Vector3(0.3, 0.6, 2.2))
	var hull := MeshInstance3D.new()
	hull.mesh = st.commit()
	hull.material_override = olive
	add_child(hull)
	# The sloped nose plate.
	var nose := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(2.3, 0.12, 1.6)
	nose.mesh = nb
	nose.material_override = olive
	nose.position = Vector3(0, 1.85, 2.55)
	nose.rotation.x = 0.55
	add_child(nose)
	# Vision slits and the team stripe.
	for part in [[Vector3(0, 2.1, 2.08), Vector3(1.6, 0.12, 0.05), dark], [Vector3(1.16, 1.95, 0.6), Vector3(0.05, 0.12, 0.9), dark],
			[Vector3(-1.16, 1.95, 0.6), Vector3(0.05, 0.12, 0.9), dark], [Vector3(1.26, 1.25, 0), Vector3(0.02, 0.22, 5.6), stripe],
			[Vector3(-1.26, 1.25, 0), Vector3(0.02, 0.22, 5.6), stripe]]:
		var pm := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = part[1]
		pm.mesh = b
		pm.material_override = part[2]
		pm.position = part[0]
		add_child(pm)
	# Roof gun.
	_turret = Node3D.new()
	_turret.position = Vector3(0, 2.4, -0.3)
	add_child(_turret)
	var ring := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 0.6
	rc.bottom_radius = 0.65
	rc.height = 0.35
	ring.mesh = rc
	ring.material_override = olive
	_turret.add_child(ring)
	for part in [[Vector3(0, 0.35, 0.15), Vector3(0.9, 0.35, 0.8), olive], [Vector3(0, 0.38, 0.9), Vector3(0.12, 0.12, 1.4), dark]]:
		var gm := MeshInstance3D.new()
		var gb := BoxMesh.new()
		gb.size = part[1]
		gm.mesh = gb
		gm.material_override = part[2]
		gm.position = part[0]
		_turret.add_child(gm)
	# Six big wheels, all driven, the front two steer.
	var tyre := CylinderMesh.new()
	tyre.top_radius = 0.55
	tyre.bottom_radius = 0.55
	tyre.height = 0.45
	tyre.radial_segments = 16
	var tyre_mat := _shared_mat("apc_tyre", Color("161616"), 0.95)
	for z in [2.1, 0.0, -2.1]:
		for x in [-1.25, 1.25]:
			var w := VehicleWheel3D.new()
			w.position = Vector3(x, 0.75, z)
			w.wheel_radius = 0.55
			w.wheel_rest_length = 0.2
			w.suspension_travel = 0.25
			w.suspension_stiffness = 60.0
			w.suspension_max_force = 30000.0
			w.damping_compression = 1.2
			w.damping_relaxation = 1.4
			w.wheel_friction_slip = 3.0
			w.wheel_roll_influence = 0.05
			w.use_as_steering = z > 1.0
			w.use_as_traction = true
			add_child(w)
			_wheels.append(w)
			var im := MeshInstance3D.new()
			im.mesh = tyre
			im.material_override = tyre_mat
			im.rotation.z = PI * 0.5
			w.add_child(im)
	_effect_nodes(Vector3(0, 0.3, -3.1), [-0.9, 0.9], Vector3(0, 2.2, -2.4))

## The driver aims the roof gun with the camera and fires it (the fire button).
func turret_aim(yaw: float, pitch: float, fire: bool, shooter: Node, delta: float) -> void:
	if _turret == null or dead: return
	# Faces -Z when its local yaw is 0; the car faces +Z.
	var local := wrapf(yaw + PI - global_rotation.y, -PI, PI)
	_turret.rotation.y = lerp_angle(_turret.rotation.y, local, minf(1.0, delta * 8.0))
	_gun_cd -= delta
	if not fire or _gun_cd > 0.0: return
	_gun_cd = 0.085
	var cam: Camera3D = shooter.camera
	var dir: Vector3 = -cam.global_basis.z
	dir = dir.rotated(cam.global_basis.x, randf_range(-0.012, 0.012)).rotated(Vector3.UP, randf_range(-0.012, 0.012))
	var muzzle: Vector3 = _turret.global_position + Vector3(0, 0.4, 0) + Vector3(dir.x, 0, dir.z).normalized() * 1.6
	# Aim at what the crosshair is on (the camera sits behind the car).
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + dir * 500.0, 1 | 4)
	q.exclude = [get_rid(), shooter.get_rid()]
	var hit0 := space.intersect_ray(q)
	var aim: Vector3 = hit0.position if hit0 else cam.global_position + dir * 500.0
	var q2 := PhysicsRayQueryParameters3D.create(muzzle, aim + (aim - muzzle).normalized() * 0.2, 1 | 4)
	q2.exclude = [get_rid(), shooter.get_rid()]
	var hit := space.intersect_ray(q2)
	var end: Vector3 = hit.position if hit else aim
	world.effects.tracer(muzzle, end)
	world.sound_shot("lmg", muzzle, true)
	world.notify_shot(muzzle, shooter)
	if hit and hit.collider and hit.collider.has_method("take_damage"):
		var col: Object = hit.collider
		# Heavy rounds: they chew through fort hearts and towers.
		var dmg := 26.0 * (5.0 if col is FortHeart or col is WarTurret else 1.0)
		var killed: bool = col.take_damage(dmg, shooter)
		if shooter.has_signal("hit_confirmed"): shooter.hit_confirmed.emit(false, killed, end)
		if killed and "kills" in shooter: shooter.kills += 1
		world.effects.impact(end, hit.normal, not (col is Vehicle or col.is_in_group("bloodless")))
	elif hit:
		world.effects.impact(end, hit.normal, false)

## Dust (or spray) behind, smoke and fire when damaged.
func _effect_nodes(dust_at: Vector3, xs: Array, engine_at: Vector3) -> void:
	for x in xs:
		var d := _particles(Color(0.62, 0.55, 0.42, 0.55), 1.1, 0.6, 18)
		d.position = dust_at + Vector3(x, 0, 0)
		d.direction = Vector3(0, 0.6, -1)
		_dust.append(d)
	_smoke = _particles(Color(0.25, 0.25, 0.25, 0.7), 2.2, 0.5, 16)
	_smoke.position = engine_at
	_smoke.gravity = Vector3(0, 1.6, 0)
	_fire = _particles(Color(1.0, 0.45, 0.1, 0.9), 0.5, 0.3, 14)
	_fire.position = engine_at
	_fire.gravity = Vector3(0, 2.5, 0)
	var fm: StandardMaterial3D = _fire.mesh.material
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.1)
	fm.emission_energy_multiplier = 3.0

## Where the driver sits (vehicle space; the model faces -Z so it is turned round).
func seat_xform() -> Transform3D:
	match kind:
		"bike": return Transform3D(Basis(Vector3.BACK, lean), Vector3.ZERO) * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.53, -0.08))
		"boat": return Transform3D(Basis(Vector3.UP, PI), Vector3(0.55, 1.23, -0.3))
		"jeep": return Transform3D(Basis(Vector3.UP, PI), Vector3(0.38, 0.62, -0.18))
		"pickup": return Transform3D(Basis(Vector3.UP, PI), Vector3(0.42, 0.5, 0.45))
		"apc": return Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 1.9, -0.3))
	return Transform3D(Basis(Vector3.UP, PI), Vector3(0.38, 0.42, -0.18))

func _mat(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

static var _mats := {}
func _shared_mat(key: String, c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		_mats[key] = _mat(c, rough, metal)
	return _mats[key]

func _build_model() -> void:
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = CarModels.imported(kind).body
	add_child(body)
	_tail_mat = _mat(Color("8a1010"), 0.25)
	if kind == "sedan":
		_paint_surface(body, "BaseColorCuzov", 0.22)
		# Brake lights glow when braking.
		for i in body.mesh.get_surface_count():
			var m := body.mesh.surface_get_material(i)
			if m and m.resource_name == "stopari":
				_tail_mat.emission_enabled = true
				_tail_mat.emission = Color("ff2a1a")
				_tail_mat.emission_energy_multiplier = 0.3
				body.set_surface_override_material(i, _tail_mat)
	# Dust from the rear wheels on the move, smoke and fire when badly damaged.
	for x in [-WHEEL_DUST_X, WHEEL_DUST_X]:
		var d := _particles(Color(0.62, 0.55, 0.42, 0.55), 1.1, 0.6, 18)
		d.position = Vector3(x, 0.15, -1.45)
		d.direction = Vector3(0, 0.6, -1)
		_dust.append(d)
	_smoke = _particles(Color(0.25, 0.25, 0.25, 0.7), 2.2, 0.5, 16)
	_smoke.position = Vector3(0, 1.1, 1.5)
	_smoke.gravity = Vector3(0, 1.6, 0)
	_fire = _particles(Color(1.0, 0.45, 0.1, 0.9), 0.5, 0.3, 14)
	_fire.position = Vector3(0, 1.05, 1.5)
	_fire.gravity = Vector3(0, 2.5, 0)
	var fm: StandardMaterial3D = _fire.mesh.material
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.1)
	fm.emission_energy_multiplier = 3.0

const WHEEL_DUST_X := 0.82

## Car paint (the vehicle's own colour) on the model's surface with that material.
func _paint_surface(body: MeshInstance3D, mat_name: String, rough: float) -> void:
	for i in body.mesh.get_surface_count():
		var m := body.mesh.surface_get_material(i)
		if m and m.resource_name == mat_name:
			var pm := _mat(paint, rough, 0.45)
			pm.clearcoat_enabled = true
			pm.clearcoat = 0.6
			pm.clearcoat_roughness = 0.15
			body.set_surface_override_material(i, pm)

func _particles(col: Color, life: float, size: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff_tex()
	q.material = m
	p.mesh = q
	p.direction = Vector3(0, 1, 0)
	p.spread = 25.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0, 0.4, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.8))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = grad
	add_child(p)
	return p

static var _puff: GradientTexture2D

## Soft round puff for dust / smoke / flames.
static func _puff_tex() -> GradientTexture2D:
	if _puff: return _puff
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_puff = GradientTexture2D.new()
	_puff.gradient = g
	_puff.fill = GradientTexture2D.FILL_RADIAL
	_puff.fill_from = Vector2(0.5, 0.5)
	_puff.fill_to = Vector2(1.0, 0.5)
	_puff.width = 64
	_puff.height = 64
	return _puff

## Engine note: a looping rumble whose pitch follows the revs (with gear changes).
static var _engine_stream: AudioStreamWAV

static func engine_stream() -> AudioStreamWAV:
	if _engine_stream: return _engine_stream
	var rate := 22050
	var n := rate        # one second loop, 40 Hz base (whole number of cycles)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for h in [[1.0, 0.5], [2.0, 0.35], [3.0, 0.2], [4.0, 0.12], [6.0, 0.06]]:
			v += sin(TAU * 40.0 * h[0] * t) * h[1]
		v *= 0.75 + 0.25 * sin(TAU * 20.0 * t)       # firing pulses
		lp = lp * 0.7 + (randf() * 2.0 - 1.0) * 0.3
		v += lp * 0.15
		data.encode_s16(i * 2, int(clampf(v * 0.5, -1.0, 1.0) * 30000.0))
	_engine_stream = AudioStreamWAV.new()
	_engine_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_engine_stream.mix_rate = rate
	_engine_stream.data = data
	_engine_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_engine_stream.loop_end = n
	return _engine_stream

## Sound, dust, brake lights and damage smoke (only matter near the player).
func _effects(sp: float) -> void:
	var near: bool = world.player != null and global_position.distance_to(world.view_position()) < 180.0
	var moving := absf(sp) > 4.0 and near
	if kind == "boat": moving = moving and _in_water
	for d in _dust: d.emitting = moving
	var braking := brake > 1.0 and driver != null
	_tail_mat.emission_energy_multiplier = 2.5 if braking else 0.3
	_smoke.emitting = near and health < max_health * 0.45 and not dead or (dead and near)
	_fire.emitting = near and (health < max_health * 0.2 or dead)
	if not Game.settings.sound or DisplayServer.get_name() == "headless": return
	if driver != null and _engine == null:
		_engine = AudioStreamPlayer3D.new()
		# Recorded engine (loop) if present, else the generated one; plus the
		# starter rev as you get in.
		var rec: AudioStreamOggVorbis = world_sound("engine_loop")
		if rec:
			rec.loop = true
			_engine.stream = rec
		else:
			_engine.stream = engine_stream()
		var start: AudioStream = world_sound("engine_start")
		if start:
			var sp3 := AudioStreamPlayer3D.new()
			sp3.stream = start
			sp3.unit_size = 8.0
			sp3.volume_db = -2.0
			add_child(sp3)
			sp3.play()
			sp3.finished.connect(sp3.queue_free)
		_engine.unit_size = 8.0
		_engine.max_distance = 160.0
		_engine.volume_db = -4.0
		add_child(_engine)
		_engine.play()
	if _engine:
		if driver == null or dead:
			_engine.queue_free()
			_engine = null
			return
		# Five gears; the revs climb within each gear, drop on a shift.
		var v := absf(sp)
		_gear = clampi(int(v / 7.0) + 1, 1, 5)
		var rev := clampf((v - (_gear - 1) * 7.0) / 7.0, 0.0, 1.0)
		var load := absf(throttle)
		var kp: float = {"bike": 1.35, "boat": 0.85}.get(kind, 1.0)
		if kind == "boat": rev = clampf(v / max_speed, 0.0, 1.0)
		_engine.pitch_scale = lerpf(_engine.pitch_scale, (0.75 + rev * 0.9 + (_gear * 0.08 if kind != "boat" else 0.0) + load * 0.1) * kp, 0.2)
		_engine.volume_db = lerpf(_engine.volume_db, -10.0 + load * 6.0, 0.1)

## A recorded sound loaded by the world (null if missing).
func world_sound(name: String) -> AudioStream:
	return world._snd.get(name) if world and "_snd" in world else null

## Forward speed in m/s (positive when moving forward).
func speed() -> float:
	return linear_velocity.dot(global_basis.z)

var _park_t := randf() * 0.5

## Parked far from the camera with nobody in it: frozen in place (no wheel
## physics at all). Woken again when the camera comes within 120 m.
func _update_parking() -> void:
	var far := driver == null and world != null and world.player != null \
		and global_position.distance_to(world.view_position()) > 120.0
	if far and not freeze and linear_velocity.length() < 0.6 and angular_velocity.length() < 0.3 and _resting():
		freeze = true
	elif not far and freeze:
		freeze = false

## Standing on its wheels (a boat: always), not in mid-air.
func _resting() -> bool:
	if kind == "boat": return true
	var n := 0
	for w in _wheels:
		if w is VehicleWheel3D and (w as VehicleWheel3D).is_in_contact(): n += 1
	return n >= 2

func _physics_process(delta: float) -> void:
	_park_t -= delta
	if _park_t <= 0.0:
		_park_t = 0.5
		_update_parking()
	if freeze: return
	if kind == "boat":
		_boat_physics(delta)
		return
	# Safety net: if the body ever sinks into the terrain, put it back on top.
	var g: float = world.ground_height(global_position)
	if global_position.y < g - 1.5 and not world.is_deep(global_position):
		global_position.y = g + 0.8
		linear_velocity = Vector3(linear_velocity.x, 0.0, linear_velocity.z) * 0.5
	_effects(speed())
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
			engine_force = -signf(sp) * max_force * 1.2
			brake = BRAKE
		else:
			# Coasting: engine braking, and hold still when nearly stopped (no rolling downhill).
			brake = (BRAKE if absf(sp) < 3.0 else BRAKE * 0.25) if absf(t) < 0.01 else 0.0
			engine_force = t * max_force * (1.0 if absf(sp) < max_speed else 0.0) * (0.5 if t < 0.0 else 1.0)
		if handbrake:
			engine_force = 0.0
			brake = BRAKE * 1.5
		# Less steering at speed (no rollovers); positive steering turns left.
		var steer_target := -steer_in * max_steer * clampf(1.0 - absf(sp) / (30.0 if kind != "bike" else 42.0), 0.18, 1.0)
		steering = move_toward(steering, steer_target, delta * 2.5)
	else:
		# Nobody driving: roll to a stop within a few metres.
		engine_force = -signf(sp) * max_force * 0.6 if absf(sp) > 1.0 else 0.0
		brake = BRAKE
		steering = move_toward(steering, 0.0, delta)
	if kind == "bike": _keep_upright(delta, sp)
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
	if kind != "boat" and global_position.y < Island.WATER - 1.0 and world.is_deep(global_position):
		take_damage(max_health * 2.0, null)

## The bike stays on its wheels (a hidden hand on the handlebars), and its
## body leans into the turn by speed and steering.
func _keep_upright(delta: float, sp: float) -> void:
	var want := clampf(steering * absf(sp) / 14.0, -0.6, 0.6)
	lean = lerpf(lean, want, minf(1.0, delta * 5.0))
	if _lean_node: _lean_node.rotation.z = lean

## Bike: no roll at all for the body (the lean is only drawn), pitch and
## heading stay free so it follows slopes.
func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	if kind != "bike" or dead: return
	var t := st.transform
	var fwd := t.basis.z.normalized()
	var up := (Vector3.UP - fwd * fwd.dot(Vector3.UP))
	if up.length() < 0.2: return
	up = up.normalized()
	st.transform = Transform3D(Basis(up.cross(fwd), up, fwd), t.origin)
	var av := st.angular_velocity
	st.angular_velocity = av - fwd * av.dot(fwd)

# ---------- Boat ----------
var _in_water := false

## Floating: four points on the hull are pushed up by how deep they sit;
## water drag keeps it from sliding sideways; the motor pushes and turns it
## only when its stern is in the water.
func _boat_physics(delta: float) -> void:
	_effects(speed())
	var k := mass * 9.8 / (4.0 * 0.28)
	var submerged := 0
	for off in [Vector3(-0.8, 0.1, 1.6), Vector3(0.8, 0.1, 1.6), Vector3(-0.8, 0.1, -1.9), Vector3(0.8, 0.1, -1.9)]:
		var p: Vector3 = global_transform * off
		var depth := Island.WATER - p.y
		if depth <= 0.0: continue
		submerged += 1
		var r: Vector3 = p - global_position
		var vp: Vector3 = linear_velocity + angular_velocity.cross(r)
		apply_force(Vector3.UP * (k * minf(depth, 0.8) - vp.y * mass * 0.6), r)
	_in_water = submerged >= 2
	if dead: return
	var sp := speed()
	if _in_water:
		# Drag: little along the hull, a lot sideways.
		var side := global_basis.x
		var lat := linear_velocity.dot(side)
		apply_central_force(-side * lat * mass * 1.6 - global_basis.z * sp * mass * 0.12)
		angular_velocity.x *= 0.96
		angular_velocity.z *= 0.96
		if driver:
			if sleeping and (absf(throttle) > 0.01 or absf(steer_in) > 0.01): sleeping = false
			var t := throttle * (0.5 if throttle < 0.0 else 1.0)
			if absf(sp) < max_speed or signf(t) != signf(sp):
				apply_central_force(global_basis.z * t * max_force)
			# Turning needs way on; the bow lifts a little at speed.
			var turn := -steer_in * clampf(absf(sp) / 6.0, 0.25, 1.0) * signf(sp if absf(sp) > 0.5 else 1.0)
			apply_torque(Vector3.UP * turn * mass * 2.2)
			apply_torque(global_basis.x * -clampf(sp / max_speed, 0.0, 1.0) * mass * 0.6)
	else:
		# Beached: it just sits there.
		linear_velocity = linear_velocity.move_toward(Vector3.ZERO, delta * 6.0)

func take_damage(amount: float, attacker: Node, _head := false) -> bool:
	if dead: return false
	if kind == "apc":
		if attacker != null and "team" in attacker and attacker.team == team and team >= 0: return false
		amount *= 0.35       # armour
	health -= amount
	if health <= 0.0:
		dead = true
		engine_force = 0.0
		brake = 20.0
		var who := driver
		if who and who.has_method("exit_vehicle"): who.exit_vehicle(true)
		world.explode(global_position + Vector3(0, 1.0, 0), attacker if attacker else self, [get_rid()])
		var burnt := _mat(Color("1b1a19"), 1.0)
		for c in get_children():
			if c is MeshInstance3D:
				c.material_override = burnt
		return true
	return false
