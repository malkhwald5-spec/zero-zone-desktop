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
var kind := "sedan"              # "sedan" | "jeep"
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
	var near: bool = world.player != null and global_position.distance_to(world.player.global_position) < 180.0
	var moving := absf(sp) > 4.0 and near
	for d in _dust: d.emitting = moving
	var braking := brake > 1.0 and driver != null
	_tail_mat.emission_energy_multiplier = 2.5 if braking else 0.3
	_smoke.emitting = near and health < MAX_HEALTH * 0.45 and not dead or (dead and near)
	_fire.emitting = near and (health < MAX_HEALTH * 0.2 or dead)
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
		_engine.pitch_scale = lerpf(_engine.pitch_scale, 0.75 + rev * 0.9 + _gear * 0.08 + load * 0.1, 0.2)
		_engine.volume_db = lerpf(_engine.volume_db, -10.0 + load * 6.0, 0.1)

## A recorded sound loaded by the world (null if missing).
func world_sound(name: String) -> AudioStream:
	return world._snd.get(name) if world and "_snd" in world else null

## Forward speed in m/s (positive when moving forward).
func speed() -> float:
	return linear_velocity.dot(global_basis.z)

func _physics_process(delta: float) -> void:
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
		var burnt := _mat(Color("1b1a19"), 1.0)
		for c in get_children():
			if c is MeshInstance3D:
				c.material_override = burnt
		return true
	return false
