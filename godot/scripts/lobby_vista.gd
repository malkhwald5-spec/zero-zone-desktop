class_name LobbyVista
extends Node3D
## What lies behind the squad in the lobby: the game itself. You stand on a
## rocky headland at sunset; across the sea the island waits, its volcano
## smoking, the glowing wall of the zone closing round it; the transport plane
## crosses the sky and the first parachutes open under it.

const SEA_Y := -30.0
const ISLAND := Vector2(40.0, -560.0)      # centre of the island (x, z)
const ISLAND_R := 340.0
const VOLCANO := Vector2(230.0, -650.0)
const ZONE_C := Vector3(-30.0, SEA_Y, -560.0)
const ZONE_R := 235.0

var _plane: Node3D
var _plane_x := -320.0
var _props: Array = []
var _chutes: Array = []                  # [Node3D, velocity Vector3, active bool]
var _next_drop := 0.0
var _noise := FastNoiseLite.new()
var _t := 0.0

func _ready() -> void:
	_noise.seed = 11
	_noise.frequency = 0.012
	_noise.fractal_octaves = 4
	var lite: bool = Game.phone()
	_terrain(Rect2(-44, -28, 88, 44), 0.8 if not lite else 1.6, true)
	_terrain(Rect2(-900, -1080, 1800, 1030), 8.0 if not lite else 14.0, false)
	_sea()
	_volcano()
	_zone_wall()
	_flyover()

func _process(delta: float) -> void:
	_t += delta
	# The plane crosses, then comes round again after a pause.
	_plane_x += delta * 34.0
	if _plane_x > 420.0: _plane_x = -420.0
	_plane.position = Vector3(_plane_x, 34.0 + sin(_t * 0.4) * 1.5, -205.0)
	_plane.rotation.z = sin(_t * 0.5) * 0.03
	for p in _props: (p as Node3D).rotate_object_local(Vector3.BACK, delta * 14.0)
	# Players leaving the door: a chute opens a moment behind the plane.
	if absf(_plane_x) < 200.0 and _t > _next_drop:
		_next_drop = _t + randf_range(1.1, 2.4)
		for c in _chutes:
			if not c[2]:
				var n: Node3D = c[0]
				n.position = Vector3(_plane_x - 18.0, 26.0, -205.0 + randf_range(-25.0, 30.0))
				c[1] = Vector3(randf_range(-1.5, 1.5), -randf_range(3.0, 4.2), randf_range(0.5, 2.0))
				c[2] = true
				n.visible = true
				n.scale = Vector3.ONE * 0.2
				break
	for c in _chutes:
		if not c[2]: continue
		var n: Node3D = c[0]
		n.position += (c[1] as Vector3) * delta
		n.scale = n.scale.lerp(Vector3.ONE, minf(1.0, delta * 2.5))
		n.rotation = Vector3(sin(_t * 0.9 + n.position.x) * 0.08, sin(_t * 0.2 + n.position.z) * 0.6, sin(_t * 1.1 + n.position.x) * 0.12)
		if n.position.y < SEA_Y + 22.0:
			c[2] = false
			n.visible = false

# ------------------------------------------------------------------ land
## Height of the land: the headland you stand on (flat on top, a cliff
## dropping into the sea beyond), and the island far off with its hills.
func _h(x: float, z: float, near: bool) -> float:
	if near:
		var e := Vector2(x / 15.0, (z + 0.6) / 5.6).length()
		var bump := _noise.get_noise_2d(x * 6.0, z * 6.0) * 0.18
		var top := bump + maxf(0.0, absf(x) - 9.0) * 0.12
		var drop := smoothstep(1.0, 1.45, e + _noise.get_noise_2d(x * 3.0, z * 3.0) * 0.12)
		return lerpf(top, SEA_Y - 6.0, drop) + _noise.get_noise_2d(x * 9.0, z * 9.0) * 1.2 * drop
	var d := Vector2(x, z).distance_to(ISLAND)
	var r := ISLAND_R * (1.0 + _noise.get_noise_2d(x * 0.3, z * 0.3) * 0.35)
	var m := 1.0 - smoothstep(0.55, 1.05, d / r)
	var hills := (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * 70.0
	var h := SEA_Y - 8.0 + m * (12.0 + hills)
	var dv := Vector2(x, z).distance_to(VOLCANO)
	h += 150.0 * pow(maxf(0.0, 1.0 - dv / 170.0), 1.7)
	h -= 22.0 * maxf(0.0, 1.0 - dv / 18.0)                  # the crater
	return h

func _terrain(r: Rect2, step: float, near: bool) -> void:
	var nx := int(r.size.x / step)
	var nz := int(r.size.y / step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := PackedFloat32Array()
	hs.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			hs[j * (nx + 1) + i] = _h(r.position.x + i * step, r.position.y + j * step, near)
	for j in nz:
		for i in nx:
			var x0 := r.position.x + i * step
			var z0 := r.position.y + j * step
			var a := Vector3(x0, hs[j * (nx + 1) + i], z0)
			var b := Vector3(x0 + step, hs[j * (nx + 1) + i + 1], z0)
			var c := Vector3(x0 + step, hs[(j + 1) * (nx + 1) + i + 1], z0 + step)
			var d := Vector3(x0, hs[(j + 1) * (nx + 1) + i], z0 + step)
			if maxf(maxf(a.y, b.y), maxf(c.y, d.y)) < SEA_Y - 3.0: continue
			for v in [a, b, c, a, c, d]: st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/lobby_vista.gdshader")
	m.set_shader_parameter("rock_tex", load("res://assets/textures/rock_col.jpg"))
	m.set_shader_parameter("grass_tex", load("res://assets/textures/grass_col.jpg"))
	m.set_shader_parameter("sand_tex", load("res://assets/textures/sand_col.jpg"))
	m.set_shader_parameter("tile", 0.22 if near else 0.03)
	m.set_shader_parameter("near", 1.0 if near else 0.0)
	m.set_shader_parameter("sea", SEA_Y)
	mi.material_override = m
	if not near: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _sea() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/lobby_sea.gdshader")
	var n := NoiseTexture2D.new()
	n.seamless = true
	n.as_normal_map = true
	n.bump_strength = 6.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	n.noise = fn
	m.set_shader_parameter("waves", n)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, SEA_Y, -2600)
	add_child(mi)

## The volcano's glowing crater and its smoke.
func _volcano() -> void:
	var top := Vector3(VOLCANO.x, _h(VOLCANO.x, VOLCANO.y, false) + 8.0, VOLCANO.y)
	var glow := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 16.0
	sm.height = 10.0
	glow.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.45, 0.1)
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.4, 0.08)
	gm.emission_energy_multiplier = 4.0
	glow.material_override = gm
	glow.position = top - Vector3(0, 6, 0)
	add_child(glow)
	var smoke := CPUParticles3D.new()
	smoke.amount = 28
	smoke.lifetime = 14.0
	smoke.preprocess = 14.0
	smoke.position = top
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 10.0
	smoke.direction = Vector3(0.4, 1, 0)
	smoke.spread = 12.0
	smoke.gravity = Vector3(1.5, 1.0, 0)
	smoke.initial_velocity_min = 4.0
	smoke.initial_velocity_max = 7.0
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.35, 0.3, 0.28, 0.0))
	grad.add_point(0.15, Color(0.3, 0.27, 0.26, 0.55))
	grad.set_color(grad.get_point_count() - 1, Color(0.5, 0.45, 0.42, 0.0))
	smoke.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(40, 40)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = RegionFx._soft_dot()
	q.material = qm
	smoke.mesh = q
	add_child(smoke)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.45, 0.15)
	lamp.light_energy = 6.0
	lamp.omni_range = 90.0
	lamp.position = top + Vector3(0, 12, 0)
	add_child(lamp)

## The zone: a glowing wall standing round the island, crawling with light.
func _zone_wall() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = ZONE_R
	cm.bottom_radius = ZONE_R
	cm.height = 240.0
	cm.radial_segments = 96
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/lobby_zone.gdshader")
	var n := NoiseTexture2D.new()
	n.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	n.noise = fn
	m.set_shader_parameter("noise", n)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = ZONE_C + Vector3(0, 120.0 - 6.0, 0)
	add_child(mi)

## The transport plane passing over, and a few chutes to open under it.
func _flyover() -> void:
	_plane = PlaneModel.make()
	_plane.rotation.y = -PI * 0.5
	add_child(_plane)
	for k in 4:
		var p := _plane.find_child("prop%d" % k, true, false)
		if p: _props.append(p)
	var cols := [Color("c84f3a"), Color("e8b030"), Color("2f8fd8"), Color("4caf50"), Color("d84fa0"), Color("f08030")]
	for i in 7:
		var n := Node3D.new()
		var cm := MeshInstance3D.new()
		cm.mesh = HumanModel.chute_mesh(cols[i % cols.size()])
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(cm)
		var ln := MeshInstance3D.new()
		ln.mesh = HumanModel._lines_mesh()
		n.add_child(ln)
		var man := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.3
		cap.height = 1.7
		man.mesh = cap
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.12, 0.13, 0.12)
		man.material_override = mm
		man.position = Vector3(0, HumanModel.RISER_Y - 0.9, 0)
		n.add_child(man)
		n.visible = false
		add_child(n)
		_chutes.append([n, Vector3.ZERO, false])
	# A few already on their way down when you arrive.
	for i in 3:
		var c: Array = _chutes[i]
		var n: Node3D = c[0]
		n.position = Vector3(-120.0 + i * 95.0, 4.0 + i * 7.0, -215.0 + i * 12.0)
		c[1] = Vector3(0.8, -3.4, 1.0)
		c[2] = true
		n.visible = true
