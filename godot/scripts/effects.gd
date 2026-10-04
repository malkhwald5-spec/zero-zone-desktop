class_name Effects
extends Node3D
## Short-lived visual effects: tracers, impacts and muzzle flashes.

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
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func muzzle_flash(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 3.0
	l.omni_range = 4.0
	add_child(l)
	l.global_position = pos
	get_tree().create_timer(0.05).timeout.connect(l.queue_free)
