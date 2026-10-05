class_name Effects
extends Node3D
## Short-lived visual effects: tracers, impacts, muzzle flashes, explosions and smoke.

var _tracer_mat: StandardMaterial3D
var _spark_mat: StandardMaterial3D
var _dust_mat: StandardMaterial3D

func _ready() -> void:
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.85, 0.5)
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color(1.0, 0.8, 0.4)
	_tracer_mat.emission_energy_multiplier = 4.0
	_spark_mat = _tracer_mat.duplicate()
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.albedo_color = Color(0.55, 0.5, 0.42, 0.8)
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.5: return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, minf(length, 14.0))
	bm.material = _tracer_mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = from
	mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tw := create_tween()
	var dur := clampf(length / 600.0, 0.03, 0.4)
	tw.tween_property(mi, "global_position", to, dur)
	tw.tween_callback(mi.queue_free)

func impact(pos: Vector3, normal: Vector3, flesh: bool) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 10 if flesh else 14
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 45.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.07
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 4
	m.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.05, 0.05) if flesh else Color(0.62, 0.56, 0.45)
	m.material = mat
	p.mesh = m
	add_child(p)
	p.global_position = pos + normal * 0.05
	p.create_tween().tween_callback(p.queue_free).set_delay(1.0)

func muzzle_flash(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 3.0
	l.omni_range = 4.0
	add_child(l)
	l.global_position = pos
	l.create_tween().tween_callback(l.queue_free).set_delay(0.05)

func _ball(col: Color, emit: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	if emit > 0.0:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = Color(col.r, col.g, col.b)
		mat.emission_energy_multiplier = emit
	m.material = mat
	return m

## Fireball, flash, debris and a dark smoke puff.
func explosion(pos: Vector3) -> void:
	var fire := CPUParticles3D.new()
	fire.one_shot = true
	fire.emitting = true
	fire.amount = 26
	fire.lifetime = 0.6
	fire.explosiveness = 1.0
	fire.spread = 180.0
	fire.initial_velocity_min = 3.0
	fire.initial_velocity_max = 9.0
	fire.gravity = Vector3(0, 2.0, 0)
	fire.scale_amount_min = 0.6
	fire.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	ramp.set_color(1, Color(0.6, 0.15, 0.05, 0.0))
	fire.color_ramp = ramp
	fire.mesh = _ball(Color.WHITE, 3.0)
	add_child(fire)
	fire.global_position = pos
	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.emitting = true
	smoke.amount = 18
	smoke.lifetime = 2.2
	smoke.explosiveness = 0.9
	smoke.spread = 180.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 3.0
	smoke.gravity = Vector3(0, 1.2, 0)
	smoke.scale_amount_min = 1.2
	smoke.scale_amount_max = 2.6
	var sramp := Gradient.new()
	sramp.set_color(0, Color(0.15, 0.13, 0.12, 0.8))
	sramp.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	smoke.color_ramp = sramp
	smoke.mesh = _ball(Color.WHITE, 0.0)
	add_child(smoke)
	smoke.global_position = pos
	var dirt := CPUParticles3D.new()
	dirt.one_shot = true
	dirt.emitting = true
	dirt.amount = 24
	dirt.lifetime = 1.0
	dirt.explosiveness = 1.0
	dirt.direction = Vector3.UP
	dirt.spread = 70.0
	dirt.initial_velocity_min = 5.0
	dirt.initial_velocity_max = 12.0
	dirt.gravity = Vector3(0, -9.8, 0)
	dirt.scale_amount_min = 0.06
	dirt.scale_amount_max = 0.16
	dirt.mesh = _ball(Color(0.35, 0.3, 0.25), 0.0)
	add_child(dirt)
	dirt.global_position = pos
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.35)
	l.light_energy = 10.0
	l.omni_range = 14.0
	add_child(l)
	l.global_position = pos + Vector3(0, 0.5, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	tw.tween_callback(l.queue_free)
	for n in [fire, smoke, dirt]:
		n.create_tween().tween_callback(n.queue_free).set_delay(2.5)

## A thick grey smoke cloud that lasts `duration` seconds.
func smoke_cloud(pos: Vector3, duration: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 5.0
	p.preprocess = 2.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.5
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, 0.15, 0)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 5.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(0.85, 0.86, 0.88, 0.0), Color(0.8, 0.82, 0.84, 0.85), Color(0.75, 0.76, 0.78, 0.0)])
	p.color_ramp = ramp
	p.mesh = _ball(Color.WHITE, 0.0)
	add_child(p)
	p.global_position = pos + Vector3(0, 1.5, 0)
	var tw := p.create_tween()
	tw.tween_interval(duration - 5.0)
	tw.tween_property(p, "emitting", false, 0.0)
	tw.tween_interval(5.5)
	tw.tween_callback(p.queue_free)
