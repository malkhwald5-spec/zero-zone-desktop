class_name WorldBuilder
extends RefCounted
## Turns Island data into scene nodes: terrain (+ collision), water, sky and
## light, buildings you can walk into, trees, rocks, bridges and grass.

const WALL_H := 3.4
const WALL_T := 0.25
const DOOR_W := 1.3
const DOOR_H := 2.3

var island: Island
var root: Node3D
var height_tex: ImageTexture
var mask_tex: ImageTexture
var noise_a: NoiseTexture2D
var noise_b: NoiseTexture2D
var env: Environment
var sun: DirectionalLight3D
var grass: MultiMeshInstance3D
var grass_mat: ShaderMaterial

func _init(isl: Island, parent: Node3D) -> void:
	island = isl
	root = parent

## Build steps with a label each, so the loading screen can show progress.
func steps() -> Array:
	return [
		[_textures, "جاري تجهيز التضاريس"], [_environment, "جاري تجهيز السماء"], [_terrain, "جاري بناء الأرض"],
		[_water, "جاري تعبئة البحر"], [_buildings, "جاري بناء المدن"], [_trees, "جاري زراعة الغابات"],
		[_rocks, "جاري توزيع الصخور"], [_bridges, "جاري بناء الجسور"], [_grass, "جاري تجهيز العشب"],
	]

func build_all() -> void:
	_textures()
	_environment()
	_terrain()
	_water()
	_buildings()
	_trees()
	_rocks()
	_bridges()
	_grass()

func _noise_tex(freq: float, seed_v: int) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 4
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	t.generate_mipmaps = true
	return t

func _textures() -> void:
	height_tex = ImageTexture.create_from_image(island.height_image())
	mask_tex = ImageTexture.create_from_image(island.mask_image(1024))
	noise_a = _noise_tex(0.012, 3)
	noise_b = _noise_tex(0.03, 9)

# ---------- Sky, sun, post-processing ----------
func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.43, 0.74)
	sky_mat.sky_horizon_color = Color(0.68, 0.78, 0.88)
	sky_mat.ground_horizon_color = Color(0.68, 0.78, 0.88)
	sky_mat.ground_bottom_color = Color(0.36, 0.5, 0.58)
	sky_mat.ground_curve = 0.3
	sky_mat.sun_angle_max = 20.0
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.76, 0.86)
	env.fog_density = 0.00045
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.85, 0.88, 0.92)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	root.add_child(sun)
	Game.apply_quality(env, sun)

# ---------- Terrain ----------
func _terrain() -> void:
	var s := island.size
	var plane := PlaneMesh.new()
	plane.size = Vector2(s, s)
	plane.subdivide_width = Island.N - 2
	plane.subdivide_depth = Island.N - 2
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("heightmap", height_tex)
	mat.set_shader_parameter("maskmap", mask_tex)
	mat.set_shader_parameter("noise_a", noise_a)
	mat.set_shader_parameter("noise_b", noise_b)
	mat.set_shader_parameter("map_size", s)
	mat.set_shader_parameter("texel", 1.0 / float(Island.N - 1))
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(s * 0.5, 0, s * 0.5)
	mi.custom_aabb = AABB(Vector3(-s * 0.5, -40, -s * 0.5), Vector3(s, 160, s))
	mi.name = "Terrain"
	root.add_child(mi)

	# Collision: a heightmap shape scaled so one sample = one step.
	var shape := HeightMapShape3D.new()
	shape.map_width = Island.N
	shape.map_depth = Island.N
	var scaled := PackedFloat32Array()
	scaled.resize(island.heights.size())
	for i in island.heights.size():
		scaled[i] = island.heights[i] / island.step
	shape.map_data = scaled
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(island.step, island.step, island.step)
	body.position = Vector3(s * 0.5, 0, s * 0.5)
	body.add_child(cs)
	root.add_child(body)

func _water() -> void:
	var s := island.size
	var plane := PlaneMesh.new()
	plane.size = Vector2(s * 12.0, s * 12.0)
	plane.subdivide_width = 160
	plane.subdivide_depth = 160
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("heightmap", height_tex)
	mat.set_shader_parameter("noise_a", noise_a)
	mat.set_shader_parameter("noise_b", noise_b)
	mat.set_shader_parameter("map_size", s)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(s * 0.5, Island.WATER, s * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Water"
	root.add_child(mi)
	# Dark sea floor beyond the island.
	var floor_mi := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(s * 12.0, s * 12.0)
	floor_mi.mesh = fp
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.08, 0.2, 0.26)
	floor_mi.material_override = fm
	floor_mi.position = Vector3(s * 0.5, -23.0, s * 0.5)
	root.add_child(floor_mi)

# ---------- Buildings ----------
func _wall_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = noise_b
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.15, 0.15, 0.15)
	m.roughness = 0.92
	return m

func _add_box(st: SurfaceTool, c: Vector3, sz: Vector3, col: Color) -> void:
	var h := sz * 0.5
	var corners := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 3, 2, 1, Vector3(0, 0, -1)], [4, 5, 6, 7, Vector3(0, 0, 1)], [0, 4, 7, 3, Vector3(-1, 0, 0)],
		[1, 2, 6, 5, Vector3(1, 0, 0)], [3, 7, 6, 2, Vector3(0, 1, 0)], [0, 1, 5, 4, Vector3(0, -1, 0)]]
	st.set_color(col)
	for f in faces:
		st.set_normal(f[4])
		for idx in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(c + corners[f[idx]])

func _shape(body: StaticBody3D, c: Vector3, sz: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = sz
	cs.shape = b
	cs.position = c
	body.add_child(cs)

## Wall along local X (length L) at local z, with door/window openings.
func _wall(st: SurfaceTool, glass: SurfaceTool, body: StaticBody3D, origin: Vector3, along_x: bool, length: float, door_at: float, col: Color) -> void:
	var openings := []   # [start, end, bottom, top]
	if door_at >= 0.0:
		openings.append([door_at - DOOR_W * 0.5, door_at + DOOR_W * 0.5, 0.0, DOOR_H])
	var n_win := int((length - 2.0) / 3.2)
	for k in n_win:
		var c := (k + 0.5) * (length / n_win) if n_win > 0 else length * 0.5
		if door_at >= 0.0 and absf(c - door_at) < 2.0: continue
		if c < 1.2 or c > length - 1.2: continue
		openings.append([c - 0.6, c + 0.6, 1.0, 2.2])
	openings.sort_custom(func(a, b): return a[0] < b[0])
	var pieces := []   # [start, end, bottom, top]
	var cur := 0.0
	for o in openings:
		if o[0] > cur: pieces.append([cur, o[0], 0.0, WALL_H])
		if o[2] > 0.0: pieces.append([o[0], o[1], 0.0, o[2]])
		pieces.append([o[0], o[1], o[3], WALL_H])
		cur = o[1]
		if o[2] > 0.0:
			# Window glass (visual only)
			var gc: float = (o[0] + o[1]) * 0.5
			var gpos := origin + (Vector3(gc, (o[2] + o[3]) * 0.5, 0) if along_x else Vector3(0, (o[2] + o[3]) * 0.5, gc))
			_add_box(glass, gpos, Vector3(o[1] - o[0], o[3] - o[2], 0.05) if along_x else Vector3(0.05, o[3] - o[2], o[1] - o[0]), Color(0.2, 0.3, 0.38))
	if cur < length: pieces.append([cur, length, 0.0, WALL_H])
	for p in pieces:
		var mid: float = (p[0] + p[1]) * 0.5
		var c := origin + (Vector3(mid, (p[2] + p[3]) * 0.5, 0) if along_x else Vector3(0, (p[2] + p[3]) * 0.5, mid))
		var sz := Vector3(p[1] - p[0], p[3] - p[2], WALL_T) if along_x else Vector3(WALL_T, p[3] - p[2], p[1] - p[0])
		_add_box(st, c, sz, col)
		_shape(body, c, sz)

func _buildings() -> void:
	var wall_mat := _wall_material()
	var glass_mat := StandardMaterial3D.new()
	glass_mat.vertex_color_use_as_albedo = true
	glass_mat.roughness = 0.05
	glass_mat.metallic = 0.6
	var roof_mat := StandardMaterial3D.new()
	roof_mat.vertex_color_use_as_albedo = true
	roof_mat.albedo_texture = noise_a
	roof_mat.uv1_triplanar = true
	roof_mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	roof_mat.roughness = 0.8
	var tints := [Color("e9e0cc"), Color("dcc9a8"), Color("efe8dc"), Color("d2c2ad"), Color("e2d3bd")]
	var roofs := [Color("8c3b2e"), Color("6e4a35"), Color("5c5f66"), Color("7a2f2f"), Color("4f5d4a")]
	var parent := Node3D.new()
	parent.name = "Buildings"
	root.add_child(parent)
	var bi := 0
	for b in island.buildings:
		var node := Node3D.new()
		node.position = Vector3(b.pos.x, b.floor, b.pos.y)
		node.name = "Building%d" % bi
		bi += 1
		parent.add_child(node)
		var body := StaticBody3D.new()
		node.add_child(body)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var gl := SurfaceTool.new()
		gl.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rf := SurfaceTool.new()
		rf.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sx: float = b.size.x
		var sz: float = b.size.y
		var hx := sx * 0.5
		var hz := sz * 0.5
		var col: Color = Color("a9ada0") if b.military else tints[b.tint]
		var doors: Array = b.doors
		_wall(st, gl, body, Vector3(-hx, 0, -hz + WALL_T * 0.5), true, sx, sx * 0.5 if doors.has(0) else -1.0, col)
		_wall(st, gl, body, Vector3(-hx, 0, hz - WALL_T * 0.5), true, sx, sx * 0.5 if doors.has(2) else -1.0, col)
		_wall(st, gl, body, Vector3(-hx + WALL_T * 0.5, 0, -hz), false, sz, sz * 0.5 if doors.has(3) else -1.0, col)
		_wall(st, gl, body, Vector3(hx - WALL_T * 0.5, 0, -hz), false, sz, sz * 0.5 if doors.has(1) else -1.0, col)
		# Floor slab, ceiling slab
		_add_box(st, Vector3(0, -0.15, 0), Vector3(sx, 0.3, sz), Color("8a7356") if not b.military else Color("6f706a"))
		_shape(body, Vector3(0, -0.15, 0), Vector3(sx, 0.3, sz))
		_add_box(st, Vector3(0, WALL_H + 0.1, 0), Vector3(sx + 0.2, 0.2, sz + 0.2), col.darkened(0.25))
		_shape(body, Vector3(0, WALL_H + 0.1, 0), Vector3(sx + 0.2, 0.2, sz + 0.2))
		# Foundation down into the ground (hides gaps on slopes)
		_add_box(st, Vector3(0, -1.2, 0), Vector3(sx + 0.1, 1.8, sz + 0.1), Color("6e6658"))
		# Gable roof (houses) or parapet (military)
		if b.military:
			for side in [-1, 1]:
				_add_box(st, Vector3(0, WALL_H + 0.45, side * hz), Vector3(sx + 0.2, 0.5, 0.2), col.darkened(0.15))
		else:
			_gable(rf, Vector3(0, WALL_H + 0.2, 0), sx + 0.8, sz + 0.8, 2.2 if sx > sz else 2.0, sx >= sz, roofs[b.roof])
			rf.generate_normals()
		# One mesh per material (a SurfaceTool with no vertices cannot be committed).
		for pair in [[st, wall_mat], [gl, glass_mat], [rf, roof_mat]]:
			var mesh: ArrayMesh = pair[0].commit()
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			mesh.surface_set_material(0, pair[1])
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			node.add_child(mi)

func _gable(st: SurfaceTool, base: Vector3, w: float, d: float, h: float, along_x: bool, col: Color) -> void:
	st.set_color(col)
	var hw := w * 0.5
	var hd := d * 0.5
	var p: Array
	if along_x:
		p = [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, h, 0), Vector3(-hw, h, 0), Vector3(-hw, 0, hd), Vector3(hw, 0, hd)]
		for tri in [[0, 2, 1], [0, 3, 2], [4, 5, 2], [4, 2, 3], [0, 4, 3], [1, 2, 5]]:
			for i in tri: st.add_vertex(base + p[i])
	else:
		p = [Vector3(-hw, 0, -hd), Vector3(-hw, 0, hd), Vector3(0, h, hd), Vector3(0, h, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd)]
		for tri in [[0, 1, 2], [0, 2, 3], [4, 3, 2], [4, 2, 5], [0, 3, 4], [1, 5, 2]]:
			for i in tri: st.add_vertex(base + p[i])

# ---------- Trees and rocks ----------
func _multimesh(mesh: Mesh, count: int, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	return mm

func _trees() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.6
	trunk.bottom_radius = 1.0
	trunk.height = 1.0
	trunk.radial_segments = 7
	trunk.rings = 1
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color("4d3624")
	trunk_mat.roughness = 1.0
	trunk.material = trunk_mat
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 8
	cone.rings = 1
	var blob := SphereMesh.new()
	blob.radius = 1.0
	blob.height = 1.8
	blob.radial_segments = 9
	blob.rings = 5
	var fol := ShaderMaterial.new()
	fol.shader = load("res://shaders/foliage.gdshader")
	cone.material = fol
	blob.material = fol

	var trees: Array = island.trees
	var pines := trees.filter(func(t): return t.pine)
	var leafy := trees.filter(func(t): return not t.pine)
	var mm_trunk := _multimesh(trunk, trees.size(), false)
	var mm_cone := _multimesh(cone, pines.size() * 3, true)
	var mm_blob := _multimesh(blob, leafy.size() * 3, true)
	var body := StaticBody3D.new()
	body.name = "TreeBodies"
	root.add_child(body)
	var ti := 0
	var ci := 0
	var bi := 0
	var pine_cols := [Color("2b4a27"), Color("31552b"), Color("274224")]
	var leaf_cols := [Color("4a7330"), Color("3e682c"), Color("577c36"), Color("456f2e")]
	for t in trees:
		var g := island.height_at(t.pos.x, t.pos.y) - 0.3
		var p := Vector3(t.pos.x, g, t.pos.y)
		var h: float = t.h
		var trunk_h := h * (0.45 if t.pine else 0.5)
		mm_trunk.set_instance_transform(ti, Transform3D(Basis.from_scale(Vector3(t.r, trunk_h, t.r)), p + Vector3(0, trunk_h * 0.5, 0)))
		ti += 1
		var rot := Basis(Vector3.UP, t.shade * TAU)
		if t.pine:
			var c: Color = pine_cols[int(t.shade * 3) % 3]
			for k in 3:
				var w := h * (0.32 - k * 0.07)
				var lh := h * 0.42
				mm_cone.set_instance_transform(ci, Transform3D(rot.scaled(Vector3(w, lh, w)), p + Vector3(0, h * 0.3 + k * h * 0.2 + lh * 0.5, 0)))
				mm_cone.set_instance_color(ci, c.lightened(k * 0.05))
				ci += 1
		else:
			var c: Color = leaf_cols[int(t.shade * 4) % 4]
			var offs := [Vector3(0, 0, 0), Vector3(1.4, 0.9, 0.5), Vector3(-1.1, 1.2, -0.8)]
			for k in 3:
				var w := h * (0.3 - k * 0.05)
				mm_blob.set_instance_transform(bi, Transform3D(rot.scaled(Vector3(w, w * 0.8, w)), p + Vector3(0, h * 0.62, 0) + offs[k] * (h / 10.0)))
				mm_blob.set_instance_color(bi, c.lightened(k * 0.06))
				bi += 1
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = t.r + 0.1
		cyl.height = 4.0
		cs.shape = cyl
		cs.position = p + Vector3(0, 2.0, 0)
		body.add_child(cs)
	for mm in [mm_trunk, mm_cone, mm_blob]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)

func _rocks() -> void:
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 4
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("8a8b84")
	rm.albedo_texture = noise_b
	rm.uv1_triplanar = true
	rm.roughness = 0.95
	rock.material = rm
	var mm := _multimesh(rock, island.rocks.size(), false)
	var body := StaticBody3D.new()
	root.add_child(body)
	var i := 0
	for r in island.rocks:
		var p := Vector3(r.pos.x, island.height_at(r.pos.x, r.pos.y) + r.r * 0.2, r.pos.y)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, i * 1.7).scaled(Vector3(r.r * 1.2, r.r * 0.8, r.r)), p))
		i += 1
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = r.r * 0.85
		cs.shape = sph
		cs.position = p
		body.add_child(cs)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	root.add_child(mmi)

func _bridges() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("77716a")
	mat.roughness = 0.9
	for br in island.bridges:
		var a: Vector2 = br.a
		var b: Vector2 = br.b
		var length := a.distance_to(b)
		var mid := (a + b) * 0.5
		var ang := -atan2(b.y - a.y, b.x - a.x)
		var node := StaticBody3D.new()
		node.position = Vector3(mid.x, 1.2, mid.y)
		node.rotation.y = ang
		root.add_child(node)
		for part in [[Vector3(0, -0.2, 0), Vector3(length, 0.5, br.w)], [Vector3(0, 0.55, br.w * 0.5), Vector3(length, 1.0, 0.25)], [Vector3(0, 0.55, -br.w * 0.5), Vector3(length, 1.0, 0.25)]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = part[1]
			bm.material = mat
			mi.mesh = bm
			mi.position = part[0]
			node.add_child(mi)
			_shape(node, part[0], part[1])

# ---------- Grass patch around the player ----------
func _grass() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [[Vector3(-0.05, 0, 0), Vector2(0, 1)], [Vector3(0.05, 0, 0), Vector2(1, 1)], [Vector3(0.0, 0.55, 0.02), Vector2(0.5, 0)]]:
		st.set_uv(v[1])
		st.add_vertex(v[0])
	var blade := st.commit()
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	grass_mat.set_shader_parameter("heightmap", height_tex)
	grass_mat.set_shader_parameter("maskmap", mask_tex)
	grass_mat.set_shader_parameter("noise_a", noise_a)
	grass_mat.set_shader_parameter("map_size", island.size)
	var spacing := 0.42
	var radius := 40.0
	var xforms := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := int(radius / spacing)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var p := Vector3(i * spacing + rng.randf_range(-0.2, 0.2), 0, j * spacing + rng.randf_range(-0.2, 0.2))
			if Vector2(p.x, p.z).length() > radius: continue
			xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
	var mm := _multimesh(blade, xforms.size(), false)
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	grass = MultiMeshInstance3D.new()
	grass.multimesh = mm
	grass.material_override = grass_mat
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grass.custom_aabb = AABB(Vector3(-radius, -50, -radius), Vector3(radius * 2, 200, radius * 2))
	grass.visible = Game.settings.quality != "low"
	root.add_child(grass)

## Moves the grass patch with the player (snapped so blades do not slide).
func update_grass(center: Vector3) -> void:
	if grass == null or not grass.visible:
		return
	var snap := 0.42 * 8.0
	grass.position = Vector3(snappedf(center.x, snap), 0, snappedf(center.z, snap))
	grass_mat.set_shader_parameter("center", center)
