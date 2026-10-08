class_name Effects
extends Node3D
## Short-lived visual effects: tracers, impacts, muzzle flashes, explosions and smoke.

var _tracer_mat: StandardMaterial3D
var _spark_mat: StandardMaterial3D
var _dust_mat: StandardMaterial3D
var _tracer_mesh: BoxMesh             # shared unit box, stretched per tracer
var _impact_mesh := {}                # flesh(bool) -> shared SphereMesh with material
var _hole_tex: ImageTexture           # bullet hole (dark centre, chipped ring)
var _holes: Array[Decal] = []         # oldest first; the oldest is reused when full
var _puff_mesh: QuadMesh              # soft dust puff billboard
const HOLE_DIST := 120.0              # bullet holes and dust only this close to the camera
var _puff_budget := 12.0              # dust puffs allowed right now (refills 12 a second)

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
	if _tracer_mesh == null:
		_tracer_mesh = BoxMesh.new()
		_tracer_mesh.size = Vector3(0.025, 0.025, 1.0)
		_tracer_mesh.material = _tracer_mat
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	mi.scale = Vector3(1, 1, minf(length, 14.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = from
	mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	mi.scale = Vector3(1, 1, minf(length, 14.0))
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
	if not _impact_mesh.has(flesh):
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = 4
		m.rings = 2
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.6, 0.05, 0.05) if flesh else Color(0.62, 0.56, 0.45)
		m.material = mat
		_impact_mesh[flesh] = m
	p.mesh = _impact_mesh[flesh]
	add_child(p)
	p.global_position = pos + normal * 0.05
	p.create_tween().tween_callback(p.queue_free).set_delay(1.0)
	if not flesh and _near_view(pos):
		_bullet_hole(pos, normal)
		if _puff_budget >= 1.0:
			_puff_budget -= 1.0
			_dust_puff(pos, normal)

func _process(delta: float) -> void:
	_puff_budget = minf(12.0, _puff_budget + delta * 12.0)

func _near_view(pos: Vector3) -> bool:
	var w = get_parent()
	return w != null and w.has_method("view_position") and w.view_position().distance_to(pos) < HOLE_DIST

## A hole left by the bullet, projected onto whatever was hit (walls, cars, ground).
func _bullet_hole(pos: Vector3, normal: Vector3) -> void:
	if _hole_tex == null: _hole_tex = _make_hole_texture()
	var max_holes := 50 if Game.laptop() else 120
	var d: Decal
	if _holes.size() >= max_holes:
		d = _holes.pop_front()
		if not is_instance_valid(d): d = null
	if d == null:
		d = Decal.new()
		d.texture_albedo = _hole_tex
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.cull_mask = 1
		add_child(d)
	_holes.append(d)
	var s := randf_range(0.12, 0.18)
	d.size = Vector3(s, 0.16, s)
	# A decal projects along its -Y: point Y out of the surface, random spin.
	var y := normal.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized().rotated(y, randf() * TAU)
	d.global_transform = Transform3D(Basis(x, y, x.cross(y)), pos)
	d.modulate = Color(1, 1, 1, 1)

static func _make_hole_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var chips := []
	for i in 7: chips.append([rng.randf() * TAU, rng.randf_range(0.55, 0.95)])
	for y in n:
		for x in n:
			var v := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5) / (n * 0.5)
			var r := v.length()
			var ang := atan2(v.y, v.x)
			var edge := 0.42
			for c in chips:
				var da := absf(wrapf(ang - c[0], -PI, PI))
				if da < 0.25: edge = maxf(edge, lerpf(c[1], 0.42, da / 0.25))
			var col := Color(0, 0, 0, 0)
			if r < 0.2:
				col = Color(0.03, 0.03, 0.03, 1.0)                       # the hole
			elif r < 0.3:
				col = Color(0.12, 0.11, 0.1, lerpf(1.0, 0.85, (r - 0.2) / 0.1))
			elif r < edge:
				col = Color(0.55, 0.53, 0.5, 0.55 * (1.0 - (r - 0.3) / maxf(0.01, edge - 0.3)))   # chipped, lighter ring
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## A small cloud of dust kicked up where the bullet hit.
func _dust_puff(pos: Vector3, normal: Vector3) -> void:
	if _puff_mesh == null:
		_puff_mesh = QuadMesh.new()
		_puff_mesh.size = Vector2(0.35, 0.35)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _soft_dot()
		m.disable_receive_shadows = true
		_puff_mesh.material = m
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 5
	p.lifetime = 1.1
	p.explosiveness = 0.9
	p.mesh = _puff_mesh
	p.direction = normal
	p.spread = 30.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.4
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.gravity = Vector3(0, 0.15, 0)
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 2.4))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.57, 0.52, 0.55))
	g.set_color(1, Color(0.62, 0.6, 0.56, 0.0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos + normal * 0.08
	p.emitting = true
	p.create_tween().tween_callback(p.queue_free).set_delay(1.4)

static var _dot: ImageTexture
static func _soft_dot() -> ImageTexture:
	if _dot: return _dot
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r, 0.0, 1.0) ** 1.6))
	_dot = ImageTexture.create_from_image(img)
	return _dot

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

## Molotov: low flames over a round patch, black smoke above and a
## flickering orange light, for `duration` seconds.
func fire(pos: Vector3, duration: float, radius: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var fl := CPUParticles3D.new()
	fl.amount = 90
	fl.lifetime = 0.9
	fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	fl.emission_ring_axis = Vector3.UP
	fl.emission_ring_radius = radius * 0.85
	fl.emission_ring_inner_radius = radius * 0.4
	fl.emission_ring_height = 0.1
	fl.direction = Vector3.UP
	fl.spread = 15.0
	fl.initial_velocity_min = 1.0
	fl.initial_velocity_max = 2.6
	fl.gravity = Vector3(0, 1.5, 0)
	fl.scale_amount_min = 0.35
	fl.scale_amount_max = 0.9
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.75, 0.3, 1.0), Color(1.0, 0.35, 0.05, 0.9), Color(0.5, 0.08, 0.0, 0.0)])
	fl.color_ramp = ramp
	fl.mesh = _flame_mesh()
	root.add_child(fl)
	var fl2: CPUParticles3D = fl.duplicate()
	fl2.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fl2.emission_box_extents = Vector3(radius * 0.7, 0.05, radius * 0.7)
	fl2.amount = 70
	root.add_child(fl2)
	var sm := CPUParticles3D.new()
	sm.amount = 24
	sm.lifetime = 3.5
	sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(radius * 0.5, 0.2, radius * 0.5)
	sm.direction = Vector3.UP
	sm.spread = 10.0
	sm.initial_velocity_min = 1.5
	sm.initial_velocity_max = 3.0
	sm.gravity = Vector3(0.3, 0.6, 0)
	sm.scale_amount_min = 1.0
	sm.scale_amount_max = 2.2
	var sr := Gradient.new()
	sr.set_color(0, Color(0.1, 0.08, 0.07, 0.6))
	sr.set_color(1, Color(0.25, 0.25, 0.25, 0.0))
	sm.color_ramp = sr
	sm.mesh = _ball(Color.WHITE, 0.0)
	sm.position.y = 1.0
	root.add_child(sm)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 3.0
	l.omni_range = radius * 4.0
	l.position.y = 0.8
	root.add_child(l)
	var fk := l.create_tween().set_loops(int(duration / 0.3))
	fk.tween_property(l, "light_energy", 4.2, 0.15)
	fk.tween_property(l, "light_energy", 2.4, 0.15)
	var tw := root.create_tween()
	tw.tween_interval(duration - 0.8)
	tw.tween_callback(func():
		fl.emitting = false
		fl2.emitting = false
		sm.emitting = false)
	tw.tween_property(l, "light_energy", 0.0, 0.8)
	tw.tween_interval(3.0)
	tw.tween_callback(root.queue_free)

var _flame: SphereMesh

## Glowing additive blob for flames (the colour comes from the particle).
func _flame_mesh() -> SphereMesh:
	if _flame: return _flame
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.3
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.6, 1.6, 1.6)
	m.material = mat
	_flame = m
	return m

## Flashbang: a white burst of light and a few sparks.
func flash(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.98, 0.92)
	l.light_energy = 40.0
	l.omni_range = 26.0
	add_child(l)
	l.global_position = pos + Vector3(0, 0.4, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.3)
	tw.tween_callback(l.queue_free)
	var sp := CPUParticles3D.new()
	sp.one_shot = true
	sp.emitting = true
	sp.amount = 20
	sp.lifetime = 0.35
	sp.explosiveness = 1.0
	sp.spread = 180.0
	sp.initial_velocity_min = 4.0
	sp.initial_velocity_max = 10.0
	sp.scale_amount_min = 0.05
	sp.scale_amount_max = 0.15
	sp.mesh = _ball(Color(1, 1, 0.9), 6.0)
	add_child(sp)
	sp.global_position = pos
	var puff := CPUParticles3D.new()
	puff.one_shot = true
	puff.emitting = true
	puff.amount = 8
	puff.lifetime = 1.6
	puff.explosiveness = 1.0
	puff.spread = 180.0
	puff.initial_velocity_min = 0.5
	puff.initial_velocity_max = 1.5
	puff.scale_amount_min = 0.5
	puff.scale_amount_max = 1.0
	var pr := Gradient.new()
	pr.set_color(0, Color(0.85, 0.85, 0.85, 0.6))
	pr.set_color(1, Color(0.85, 0.85, 0.85, 0.0))
	puff.color_ramp = pr
	puff.mesh = _ball(Color.WHITE, 0.0)
	add_child(puff)
	puff.global_position = pos
	for n in [sp, puff]:
		n.create_tween().tween_callback(n.queue_free).set_delay(2.0)

## A thick grey smoke cloud that lasts `duration` seconds.
func smoke_cloud(pos: Vector3, duration: float, tint := Color(0.8, 0.82, 0.84)) -> void:
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
	ramp.colors = PackedColorArray([Color(tint, 0.0), Color(tint, 0.85), Color(tint.darkened(0.05), 0.0)])
	p.color_ramp = ramp
	p.mesh = _ball(Color.WHITE, 0.0)
	add_child(p)
	p.global_position = pos + Vector3(0, 1.5, 0)
	var tw := p.create_tween()
	tw.tween_interval(duration - 5.0)
	tw.tween_property(p, "emitting", false, 0.0)
	tw.tween_interval(5.5)
	tw.tween_callback(p.queue_free)
