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
var kind := "sedan"              # "sedan" | "jeep" | "bike" | "boat"
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
	box.size = Vector3(1.8, 0.7 if kind == "sedan" else 0.75, 4.2)
	cs.shape = box
	cs.position.y = 0.72 if kind == "sedan" else 0.92
	add_child(cs)
	var cab := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(1.5, 0.45, 2.3) if kind == "sedan" else Vector3(1.6, 0.6, 1.3)
	cab.shape = cbox
	cab.position = Vector3(0, 1.25, -0.35) if kind == "sedan" else Vector3(0, 1.55, -0.1)
	add_child(cab)
	_build_model()
	for x in [-0.82, 0.82]:
		for z in [-1.35, 1.35]:
			var w := VehicleWheel3D.new()
			w.position = Vector3(x, 0.5, z)
			w.wheel_radius = 0.38
			if kind == "jeep": w.position.y = 0.55
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
			var wm := CarModels.wheel(0.38, 0.26)
			var tyre := MeshInstance3D.new()
			tyre.mesh = wm.tyre
			tyre.material_override = _shared_mat("tyre", Color("1a1a1b"), 0.92)
			w.add_child(tyre)
			var rim := MeshInstance3D.new()
			rim.mesh = wm.rim
			rim.material_override = _shared_mat("rim", Color("9aa0a6") if kind == "sedan" else Color("2a2c2a"), 0.3, 0.85)
			w.add_child(rim)
			_wheels.append(w)

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

## Meshes from CarModels with one material per part name.
func _add_parts(parts: Dictionary, mats: Dictionary, parent: Node3D) -> void:
	for k in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = parts[k]
		mi.material_override = mats[k]
		parent.add_child(mi)

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
	var pm := _mat(paint, 0.25, 0.4)
	pm.clearcoat_enabled = true
	pm.clearcoat = 0.5
	_tail_mat = _mat(Color("8a1010"), 0.25)
	_tail_mat.emission_enabled = true
	_tail_mat.emission = Color("ff2a1a")
	_tail_mat.emission_energy_multiplier = 0.3
	var head := _shared_mat("head", Color("fff6dc"), 0.1)
	head.emission_enabled = true
	head.emission = Color("fff3d0")
	head.emission_energy_multiplier = 1.2
	_add_parts(CarModels.bike(), {"paint": pm, "dark": _shared_mat("dark", Color("141516"), 0.6),
		"chrome": _shared_mat("chrome", Color("d8dde2"), 0.12, 1.0), "seat": _shared_mat("seat", Color("1d1b1a"), 0.85),
		"head": head, "tail": _tail_mat}, _lean_node)
	# Two narrow pairs of wheels keep it on its feet; one tyre of each pair is
	# drawn, moved to the middle.
	for z in [-0.72, 0.72]:
		for x in [-0.11, 0.11]:
			var w := VehicleWheel3D.new()
			w.position = Vector3(x, 0.45, z)
			w.wheel_radius = 0.32
			w.wheel_rest_length = 0.12
			w.suspension_travel = 0.18
			w.suspension_stiffness = 40.0
			w.suspension_max_force = 3000.0
			w.damping_compression = 0.9
			w.damping_relaxation = 1.1
			w.wheel_friction_slip = 2.4
			w.wheel_roll_influence = 0.02
			w.use_as_steering = z > 0.0
			w.use_as_traction = z < 0.0
			add_child(w)
			_wheels.append(w)
			if x > 0.0:
				var wm := CarModels.wheel(0.32, 0.12)
				for part in [[wm.tyre, _shared_mat("tyre", Color("1a1a1b"), 0.92)], [wm.rim, _shared_mat("bike_rim", Color("2a2c2e"), 0.4, 0.7)]]:
					var mi := MeshInstance3D.new()
					mi.mesh = part[0]
					mi.material_override = part[1]
					mi.position.x = -x
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
	_add_box_shape(Vector3(1.8, 0.5, 4.4), Vector3(0, 0.38, 0))
	var hull := _mat(paint, 0.35)
	hull.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tail_mat = _mat(Color("8a1010"), 0.25)
	_add_parts(CarModels.boat(), {"paint": hull, "white": _shared_mat("boat_white", Color("ece9e2"), 0.5),
		"dark": _shared_mat("dark", Color("141516"), 0.6), "seat": _shared_mat("boat_seat", Color("2e5c74"), 0.8),
		"glass": _shared_mat("glass", Color(0.08, 0.1, 0.12), 0.04, 0.6), "chrome": _shared_mat("chrome", Color("d8dde2"), 0.12, 1.0)}, self)
	_effect_nodes(Vector3(0, 0.1, -2.6), [-0.4, 0.4], Vector3(0, 0.9, -2.4))
	for d in _dust:
		var dm: StandardMaterial3D = d.mesh.material
		dm.albedo_color = Color(0.92, 0.95, 0.97, 0.7)

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
		"boat": return Transform3D(Basis(Vector3.UP, PI), Vector3(0.35, 0.23, -1.75))
		"jeep": return Transform3D(Basis(Vector3.UP, PI), Vector3(0.38, 0.62, -0.18))
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
	var data := CarModels.body(kind)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = data.mesh
	# Car paint: glossy clear-coat look.
	var pm := _mat(paint, 0.22, 0.45)
	pm.clearcoat_enabled = true
	pm.clearcoat = 0.6
	pm.clearcoat_roughness = 0.15
	var gm := _shared_mat("glass", Color(0.08, 0.1, 0.12), 0.04, 0.6)
	var by_name := {"paint": pm, "glass": gm, "trim": _shared_mat("trim", Color("161719"), 0.8)}
	for i in data.surfaces.size():
		body.set_surface_override_material(i, by_name[data.surfaces[i]])
	add_child(body)
	var head := _shared_mat("head", Color("fff6dc"), 0.1)
	head.emission_enabled = true
	head.emission = Color("fff3d0")
	head.emission_energy_multiplier = 1.2
	_tail_mat = _mat(Color("8a1010"), 0.25)
	_tail_mat.emission_enabled = true
	_tail_mat.emission = Color("ff2a1a")
	_tail_mat.emission_energy_multiplier = 0.3
	var mats := {"dark": _shared_mat("dark", Color("141516"), 0.6), "chrome": _shared_mat("chrome", Color("d8dde2"), 0.12, 1.0),
		"white": _shared_mat("plate", Color("e8e8e2"), 0.5), "head": head, "tail": _tail_mat, "glass": gm}
	for k in data.details:
		var mi := MeshInstance3D.new()
		mi.mesh = data.details[k]
		mi.material_override = mats[k]
		add_child(mi)
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
