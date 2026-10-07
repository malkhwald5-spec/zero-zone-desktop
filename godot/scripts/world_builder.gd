class_name WorldBuilder
extends RefCounted
## Turns Island data into scene nodes: terrain (+ collision), water, sky and
## light, buildings you can walk into, trees, rocks, bridges and grass.

const WALL_H := 3.4
const WALL_T := 0.25
const DOOR_W := 1.3
const DOOR_H := 2.3
const STOREY_H := WALL_H + 0.2   # floor to floor height in two-storey houses
const STAIR_W := 1.1
const STAIR_RUN := 5.2

var island: Island
var root: Node3D
var height_tex: ImageTexture
var mask_tex: ImageTexture
var biome_tex: ImageTexture
var noise_a: NoiseTexture2D
var noise_b: NoiseTexture2D
var env: Environment
var sun: DirectionalLight3D
var weather := "clear"          # clear | rain | sunset
var grass: MultiMeshInstance3D
var grass_mat: ShaderMaterial
var grass_snap := 5.04
## Window glass: blocks only the camera (layer 5), not people or bullets.
const CAMERA_LAYER := 16
var _glass_body: StaticBody3D
var _lining: SurfaceTool        # inner plaster for brick houses (null otherwise)

func _init(isl: Island, parent: Node3D) -> void:
	island = isl
	root = parent

## Build steps with a label each, so the loading screen can show progress.
func steps() -> Array:
	return [
		[_textures, "جاري تجهيز التضاريس"], [_environment, "جاري تجهيز السماء"], [_terrain, "جاري بناء الأرض"],
		[_water, "جاري تعبئة البحر"], [_buildings, "جاري بناء المدن"], [_trees, "جاري زراعة الغابات"],
		[_structures, "جاري بناء المصانع والمزارع"], [_rocks, "جاري توزيع الصخور"], [_bridges, "جاري بناء الجسور"], [_power_lines, "جاري تمديد خطوط الكهرباء"],
		[_grass, "جاري تجهيز العشب"],
	]

func build_all() -> void:
	_textures()
	_environment()
	_terrain()
	_water()
	_buildings()
	_trees()
	_structures()
	_rocks()
	_bridges()
	_power_lines()
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
	mask_tex = ImageTexture.create_from_image(island.mask_image(2048))
	biome_tex = ImageTexture.create_from_image(island.biome_image())
	noise_a = _noise_tex(0.012, 3)
	noise_b = _noise_tex(0.03, 9)

# ---------- Sky, sun, post-processing ----------
func _environment() -> void:
	# Real photographed sky (ambientCG DaySkyHDRI063B, CC0) lined up with the sun.
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky_photo.gdshader")
	sky_mat.set_shader_parameter("pano", load("res://assets/textures/sky_day.jpg"))
	sky_mat.set_shader_parameter("photo_sun", Vector2(0.502, 0.403))
	sky_mat.set_shader_parameter("energy", 1.15)
	sky_mat.set_shader_parameter("haze", Color(0.7, 0.77, 0.84))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 10.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.ssao_detail = 0.6
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 0.9
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.72, 0.84)
	env.fog_density = 0.00022
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0012
	env.volumetric_fog_albedo = Color(0.8, 0.85, 0.92)
	env.volumetric_fog_length = 120.0
	# Light scattered forward through the haze: soft glow and shafts towards the sun.
	env.volumetric_fog_anisotropy = 0.55
	env.fog_sun_scatter = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.08
	_weather_look(sky_mat)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, -35, 0)
	sun.light_energy = 2.2
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	root.add_child(sun)
	if weather == "sunset":
		# Low warm evening sun from the west, long shadows.
		sun.rotation_degrees = Vector3(-11, -70, 0)
		sun.light_energy = 1.6
		sun.light_color = Color("ffbe82")
	elif weather == "rain":
		# Under the clouds: weak, cool, soft light.
		sun.rotation_degrees = Vector3(-55, -35, 0)
		sun.light_energy = 0.55
		sun.light_color = Color(0.82, 0.86, 0.92)
		sun.shadow_blur = 3.0
	Game.apply_quality(env, sun)
	if weather == "rain":
		# The quality presets switch volumetric fog on; keep the rain mist thick.
		env.volumetric_fog_density = maxf(env.volumetric_fog_density, 0.004)

## Sky, fog and colour for the match's weather.
func _weather_look(sky_mat: ShaderMaterial) -> void:
	match weather:
		"sunset":
			# Real photographed sunset (ambientCG EveningSkyHDRI032A, CC0).
			sky_mat.set_shader_parameter("pano", load("res://assets/textures/sky_sunset.jpg"))
			sky_mat.set_shader_parameter("photo_sun", Vector2(0.499, 0.465))
			sky_mat.set_shader_parameter("energy", 1.15)
			sky_mat.set_shader_parameter("sun_boost", 2.0)
			sky_mat.set_shader_parameter("haze", Color("e9a878"))
			sky_mat.set_shader_parameter("haze_amount", 0.2)
			env.ambient_light_energy = 0.55
			env.tonemap_exposure = 1.1
			env.fog_light_color = Color("e9a878")
			env.fog_density = 0.0003
			env.volumetric_fog_albedo = Color("f0c8a0")
			env.fog_sun_scatter = 0.35
		"rain":
			sky_mat.set_shader_parameter("overcast", 0.92)
			sky_mat.set_shader_parameter("energy", 0.75)
			sky_mat.set_shader_parameter("sun_boost", 0.0)
			sky_mat.set_shader_parameter("haze", Color(0.55, 0.58, 0.62))
			sky_mat.set_shader_parameter("haze_amount", 0.8)
			env.ambient_light_energy = 0.9
			env.tonemap_exposure = 1.05
			env.fog_light_color = Color(0.55, 0.58, 0.62)
			env.fog_density = 0.0011
			env.fog_aerial_perspective = 0.2
			env.fog_sun_scatter = 0.0
			env.volumetric_fog_albedo = Color(0.7, 0.72, 0.76)
			env.glow_intensity = 0.2
			env.adjustment_saturation = 0.82
			env.adjustment_contrast = 1.02

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
	mat.set_shader_parameter("biomemap", biome_tex)
	mat.set_shader_parameter("hm_cells", float(Island.N - 1))
	mat.set_shader_parameter("noise_a", noise_a)
	mat.set_shader_parameter("noise_b", noise_b)
	mat.set_shader_parameter("map_size", s)
	mat.set_shader_parameter("texel", 1.0 / float(Island.N - 1))
	for t in ["grass", "dirt", "sand", "rock", "asphalt", "forest", "moss"]:
		mat.set_shader_parameter(t + "_c", load("res://assets/textures/%s_col.jpg" % t))
		mat.set_shader_parameter(t + "_n", load("res://assets/textures/%s_nrm.jpg" % t))
	mat.set_shader_parameter("concrete_c", load("res://assets/textures/concrete_col.jpg"))
	mat.set_shader_parameter("use_normals", Game.quality_level() >= 1)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(s * 0.5, 0, s * 0.5)
	mi.custom_aabb = AABB(Vector3(-s * 0.5, -40, -s * 0.5), Vector3(s, 300, s))
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
	mat.set_shader_parameter("hm_cells", float(Island.N - 1))
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
		for idx in [0, 2, 1, 0, 3, 2]:   # clockwise = front face in Godot
			st.add_vertex(c + corners[f[idx]])

func _shape(body: StaticBody3D, c: Vector3, sz: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = sz
	cs.shape = b
	cs.position = c
	body.add_child(cs)

## Wall along local X (length L) at local z, with door/window openings.
## Window and door openings get painted frames, sills and glazing bars (trim).
func _wall(st: SurfaceTool, glass: SurfaceTool, trim: SurfaceTool, body: StaticBody3D, origin: Vector3, along_x: bool, length: float, door_at: float, col: Color, trim_col: Color) -> void:
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
	# Local wall coordinates (u along the wall, y up, depth across it) to building space.
	var at := func(u: float, y: float) -> Vector3:
		return origin + (Vector3(u, y, 0) if along_x else Vector3(0, y, u))
	var box_size := func(du: float, dy: float, depth: float) -> Vector3:
		return Vector3(du, dy, depth) if along_x else Vector3(depth, dy, du)
	var pieces := []   # [start, end, bottom, top]
	var cur := 0.0
	for o in openings:
		if o[0] > cur: pieces.append([cur, o[0], 0.0, WALL_H])
		if o[2] > 0.0: pieces.append([o[0], o[1], 0.0, o[2]])
		pieces.append([o[0], o[1], o[3], WALL_H])
		cur = o[1]
		var u0: float = o[0]
		var u1: float = o[1]
		var y0: float = o[2]
		var y1: float = o[3]
		var mid := (u0 + u1) * 0.5
		var fd := WALL_T + 0.1      # frames stick out 5 cm on both faces
		var fw := 0.09
		_add_box(trim, at.call(u0 - fw * 0.5, (y0 + y1) * 0.5), box_size.call(fw, y1 - y0, fd), trim_col)
		_add_box(trim, at.call(u1 + fw * 0.5, (y0 + y1) * 0.5), box_size.call(fw, y1 - y0, fd), trim_col)
		_add_box(trim, at.call(mid, y1 + fw * 0.5), box_size.call(u1 - u0 + fw * 2.0, fw, fd), trim_col)
		if y0 > 0.0:
			# Sill, glazing bars and the glass itself (visual only).
			_add_box(trim, at.call(mid, y0 - 0.03), box_size.call(u1 - u0 + 0.24, 0.07, WALL_T + 0.26), trim_col.darkened(0.1))
			_add_box(trim, at.call(mid, (y0 + y1) * 0.5), box_size.call(0.05, y1 - y0, 0.07), trim_col)
			_add_box(trim, at.call(mid, y0 + (y1 - y0) * 0.62), box_size.call(u1 - u0, 0.05, 0.07), trim_col)
			_add_box(glass, at.call(mid, (y0 + y1) * 0.5), box_size.call(u1 - u0, y1 - y0, 0.03), Color(0.2, 0.26, 0.3))
			if _glass_body:
				_shape(_glass_body, at.call(mid, (y0 + y1) * 0.5), box_size.call(u1 - u0, y1 - y0, WALL_T))
	if cur < length: pieces.append([cur, length, 0.0, WALL_H])
	# Brick houses are plastered inside: a thin lining on the inner face.
	var inward := (Vector3(0, 0, -signf(origin.z)) if along_x else Vector3(-signf(origin.x), 0, 0)) * (WALL_T * 0.5 + 0.012)
	for p in pieces:
		var mid: float = (p[0] + p[1]) * 0.5
		var c := origin + (Vector3(mid, (p[2] + p[3]) * 0.5, 0) if along_x else Vector3(0, (p[2] + p[3]) * 0.5, mid))
		var sz := Vector3(p[1] - p[0], p[3] - p[2], WALL_T) if along_x else Vector3(WALL_T, p[3] - p[2], p[1] - p[0])
		_add_box(st, c, sz, col)
		_shape(body, c, sz)
		if _lining:
			_add_box(_lining, c + inward, Vector3(sz.x, sz.y, 0.02) if along_x else Vector3(0.02, sz.y, sz.z), Color("ddd5c4"))

func _wall_shader(tex: String, tile: float, tint: float, grime: float, rough: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/building_wall.gdshader")
	m.set_shader_parameter("albedo_tex", load("res://assets/textures/%s_col.jpg" % tex))
	m.set_shader_parameter("normal_tex", load("res://assets/textures/%s_nrm.jpg" % tex))
	m.set_shader_parameter("grime_noise", noise_b)
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("tint_amount", tint)
	m.set_shader_parameter("grime", grime)
	m.set_shader_parameter("roughness", rough)
	return m

func _buildings() -> void:
	var plaster_mat := _wall_shader("plaster", 3.0, 1.0, 1.0, 0.92)
	var brick_mat := _wall_shader("brick", 1.3, 0.35, 0.8, 0.9)
	var stone_mat := _wall_shader("stone", 2.2, 0.0, 0.6, 0.95)
	var floor_mat := _wall_shader("wood", 2.0, 0.5, 0.0, 0.75)
	var planks_mat := _wall_shader("planks", 2.0, 1.0, 0.6, 0.85)
	var tin_mat := StandardMaterial3D.new()
	tin_mat.vertex_color_use_as_albedo = true
	tin_mat.vertex_color_is_srgb = true
	tin_mat.albedo_texture = load("res://assets/textures/corrugated_col.jpg")
	tin_mat.normal_enabled = true
	tin_mat.normal_texture = load("res://assets/textures/corrugated_nrm.jpg")
	tin_mat.uv1_triplanar = true
	tin_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	tin_mat.metallic = 0.3
	tin_mat.roughness = 0.6
	# Wall paint per region: desert mud-brick, beach-house pastels, jungle
	# timber, northern painted boards (barn red, blue, ochre, white, green).
	var style_tints := {
		"desert": [Color("d2b48c"), Color("c9a77c"), Color("deb887"), Color("bf9b6f"), Color("e0c9a6")],
		"tropic": [Color("f2efe8"), Color("bfe3e0"), Color("f5d9a8"), Color("e8c6c0"), Color("d8e8c8")],
		"jungle": [Color("a07850"), Color("8a6a48"), Color("b08a60"), Color("7a6a50"), Color("9a8060")],
		"nordic": [Color("9a3a2e"), Color("3a5878"), Color("c8a048"), Color("e8e4dc"), Color("5a6a48")],
	}
	var trim_mat := StandardMaterial3D.new()
	trim_mat.vertex_color_use_as_albedo = true
	trim_mat.vertex_color_is_srgb = true
	trim_mat.roughness = 0.6
	var glass_mat := StandardMaterial3D.new()
	glass_mat.vertex_color_use_as_albedo = true
	glass_mat.roughness = 0.04
	glass_mat.metallic = 0.0
	glass_mat.metallic_specular = 1.0
	var roof_mat := StandardMaterial3D.new()
	roof_mat.vertex_color_use_as_albedo = true
	roof_mat.vertex_color_is_srgb = true
	roof_mat.albedo_texture = load("res://assets/textures/roof_col.jpg")
	roof_mat.normal_enabled = true
	roof_mat.normal_texture = load("res://assets/textures/roof_nrm.jpg")
	roof_mat.uv1_triplanar = true
	roof_mat.uv1_scale = Vector3(0.4, 0.4, 0.4)
	roof_mat.roughness = 0.8
	var tints := [Color("cfc4ac"), Color("c4ad88"), Color("d6cfc2"), Color("b8a68e"), Color("a9b4a4")]
	# Multiplies the terracotta tile texture: natural tiles, darker, grey-brown, red, weathered.
	var roofs := [Color("ffffff"), Color("c9b6a6"), Color("a8a8ae"), Color("f2c8b8"), Color("b8b8a0")]
	# Painted window and door frames: white, cream, dark brown, green, blue-grey.
	var trims := [Color("f0ece4"), Color("e4dcc8"), Color("4a3828"), Color("4d5e48"), Color("5a6878")]
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
		_glass_body = StaticBody3D.new()
		_glass_body.collision_layer = CAMERA_LAYER
		_glass_body.collision_mask = 0
		node.add_child(_glass_body)
		var sts := {}
		for k in ["wall", "glass", "roof", "trim", "stone", "floor", "brick", "planks", "tin"]:
			var t := SurfaceTool.new()
			t.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts[k] = t
		var kind: String = b.get("kind", "house")
		if kind == "warehouse" or kind == "barn":
			_big_shed(node, body, b)
			continue
		var style: String = b.get("style", "plains")
		# Plains: about a third of the houses are red brick, the rest painted
		# plaster. Jungle and north: wooden boards. Desert and beach: plaster.
		var brick: bool = style == "plains" and not b.military and (b.tint + b.roof) % 3 == 0
		var planks: bool = style in ["jungle", "nordic"] and not b.military
		var st: SurfaceTool = sts.brick if brick else (sts.planks if planks else sts.wall)
		_lining = sts.wall if (brick or planks) else null
		var sx: float = b.size.x
		var sz: float = b.size.y
		var hx := sx * 0.5
		var hz := sz * 0.5
		var col: Color = Color("a9ada0") if b.military else (Color.WHITE if brick else (style_tints[style][b.tint] if style_tints.has(style) else tints[b.tint]))
		var tcol: Color = Color("5c5f58") if b.military else trims[(b.tint * 3 + b.roof) % trims.size()]
		var doors: Array = b.doors
		var storeys: int = b.get("storeys", 1)
		for lv in storeys:
			var y0 := lv * STOREY_H
			# Doors only on the ground floor.
			var dr: Array = doors if lv == 0 else []
			_wall(st, sts.glass, sts.trim, body, Vector3(-hx, y0, -hz + WALL_T * 0.5), true, sx, sx * 0.5 if dr.has(0) else -1.0, col, tcol)
			_wall(st, sts.glass, sts.trim, body, Vector3(-hx, y0, hz - WALL_T * 0.5), true, sx, sx * 0.5 if dr.has(2) else -1.0, col, tcol)
			_wall(st, sts.glass, sts.trim, body, Vector3(-hx + WALL_T * 0.5, y0, -hz), false, sz, sz * 0.5 if dr.has(3) else -1.0, col, tcol)
			_wall(st, sts.glass, sts.trim, body, Vector3(hx - WALL_T * 0.5, y0, -hz), false, sz, sz * 0.5 if dr.has(1) else -1.0, col, tcol)
		var top_y := (storeys - 1) * STOREY_H + WALL_H
		# Floor slab (wooden boards inside)
		_add_box(sts.floor, Vector3(0, -0.15, 0), Vector3(sx, 0.3, sz), Color("b09070") if not b.military else Color("8a8a84"))
		_shape(body, Vector3(0, -0.15, 0), Vector3(sx, 0.3, sz))
		if storeys > 1:
			_upper_floor(sts, body, b, col, tcol)
		if not b.military:
			for lv in storeys:
				_furnish(sts, body, b, lv, kind == "shop")
		# Ceiling slab under the roof
		_add_box(sts.wall, Vector3(0, top_y + 0.1, 0), Vector3(sx + 0.2, 0.2, sz + 0.2), Color("d8d0c0") if brick else col.darkened(0.25))
		_shape(body, Vector3(0, top_y + 0.1, 0), Vector3(sx + 0.2, 0.2, sz + 0.2))
		# Stone foundation down into the ground (hides gaps on slopes) and a
		# half-metre stone base course on the outside of the walls.
		_add_box(sts.stone, Vector3(0, -1.08, 0), Vector3(sx + 0.14, 2.1, sz + 0.14), Color.WHITE)
		for w in 4:
			var along := w % 2 == 0
			var length := sx if along else sz
			var sgn := -1.0 if w == 0 or w == 3 else 1.0
			var spans := [[-length * 0.5, length * 0.5]]
			if doors.has(w):
				spans = [[-length * 0.5, -DOOR_W * 0.5 - 0.1], [DOOR_W * 0.5 + 0.1, length * 0.5]]
			for sp in spans:
				var m: float = (sp[0] + sp[1]) * 0.5
				var l: float = sp[1] - sp[0]
				if along:
					_add_box(sts.stone, Vector3(m, 0.25, sgn * (hz + 0.04)), Vector3(l + (0.16 if not doors.has(w) else 0.0), 0.56, 0.08), Color.WHITE)
				else:
					_add_box(sts.stone, Vector3(sgn * (hx + 0.04), 0.25, m), Vector3(0.08, 0.56, l), Color.WHITE)
		# Gable roof (houses) or parapet (military)
		if kind == "shop":
			for side in [-1, 1]:
				_add_box(st, Vector3(0, top_y + 0.45, side * hz), Vector3(sx + 0.2, 0.5, 0.2), col.darkened(0.15))
				_add_box(st, Vector3(side * hx, top_y + 0.45, 0), Vector3(0.2, 0.5, sz + 0.2), col.darkened(0.15))
			# Shop sign over the door side.
			var dv: Vector2 = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][doors[0]]
			var sp := Vector3(dv.x * (hx + 0.15), top_y + 1.0, dv.y * (hz + 0.15))
			_add_box(sts.trim, sp, Vector3(0.12, 1.0, sz * 0.7) if dv.x != 0.0 else Vector3(sx * 0.7, 1.0, 0.12), Color("c62f2f"))
			_add_box(sts.trim, sp + Vector3(0, 0.2, 0), Vector3(0.14, 0.18, sz * 0.6) if dv.x != 0.0 else Vector3(sx * 0.6, 0.18, 0.14), Color("f2e6c8"))
		elif b.military:
			for side in [-1, 1]:
				_add_box(st, Vector3(0, top_y + 0.45, side * hz), Vector3(sx + 0.2, 0.5, 0.2), col.darkened(0.15))
		elif style == "desert" or (style == "tropic" and b.roof % 2 == 0):
			# Flat roof behind a parapet, with roof-top water tanks and wooden beam ends.
			for side in [-1, 1]:
				_add_box(sts.wall, Vector3(0, top_y + 0.5, side * hz), Vector3(sx + 0.2, 0.6, 0.22), col.darkened(0.08))
				_add_box(sts.wall, Vector3(side * hx, top_y + 0.5, 0), Vector3(0.22, 0.6, sz + 0.2), col.darkened(0.08))
			if style == "desert":
				for k in int(sx / 1.6):
					_add_box(sts.floor, Vector3(-hx + 0.8 + k * 1.6, top_y - 0.25, hz + 0.2), Vector3(0.14, 0.14, 0.5), Color("6a4a30"))
			_add_box(sts.trim, Vector3(hx * 0.4, top_y + 0.85, -hz * 0.3), Vector3(1.0, 1.1, 1.0), Color("2a2a2a") if style == "desert" else Color("e8e8e8"))
		else:
			var rh := (2.2 if sx > sz else 2.0) * (1.35 if style == "nordic" else 1.0)   # steep northern roofs
			var rst: SurfaceTool = sts.tin if style == "jungle" else sts.roof
			var rcol: Color = roofs[b.roof]
			if style == "nordic": rcol = [Color("5a5a60"), Color("6a5048"), Color("4a5a50"), Color("707070"), Color("5a4a40")][b.roof]
			elif style == "jungle": rcol = [Color("b0a898"), Color("a07858"), Color("8a9090"), Color("c09070"), Color("9a9a88")][b.roof]
			_gable(rst, Vector3(0, top_y + 0.2, 0), sx + 0.8, sz + 0.8, rh, sx >= sz, rcol)
			_roof_shape(body, Vector3(0, top_y + 0.2, 0), sx + 0.8, sz + 0.8, rh, sx >= sz)
			rst.generate_normals()
			if style in ["plains", "nordic"]:
				# Chimney poking through the roof, off-centre along the ridge.
				var cx := (hx * 0.45) * (1.0 if b.tint % 2 == 0 else -1.0)
				var cpos := Vector3(cx, top_y + 1.6 + (0.6 if style == "nordic" else 0.0), hz * 0.2) if sx >= sz else Vector3(hx * 0.2, top_y + 1.6, cx * sz / sx)
				_add_box(sts.brick if style == "plains" else sts.stone, cpos, Vector3(0.6, 2.6, 0.6), Color.WHITE)
				_add_box(sts.stone, cpos + Vector3(0, 1.35, 0), Vector3(0.72, 0.1, 0.72), Color.WHITE)
		# One mesh per material (a SurfaceTool with no vertices cannot be committed).
		var mats := {"wall": plaster_mat, "brick": brick_mat, "glass": glass_mat, "roof": roof_mat,
			"trim": trim_mat, "stone": stone_mat, "floor": floor_mat, "planks": planks_mat, "tin": tin_mat}
		for k in sts:
			var mesh: ArrayMesh = sts[k].commit()
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			mesh.surface_set_material(0, mats[k])
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			node.add_child(mi)

## Furniture pieces: lists of boxes [u, y, d, size_u, size_y, size_d, surface, colour]
## with u along the wall, d out from the wall into the room.
const FURNITURE := {
	"bed": [2.1, [[0, 0.22, 0.75, 2.0, 0.44, 1.4, "floor", "8a6a4a"], [0, 0.5, 0.75, 1.9, 0.14, 1.3, "trim", "e8e4dc"],
		[0, 0.52, 0.75, 1.0, 0.16, 1.32, "trim", "5d7a9c"], [-0.98, 0.55, 0.75, 0.08, 1.1, 1.4, "floor", "6e5236"]]],
	"sofa": [2.1, [[0, 0.22, 0.45, 2.0, 0.44, 0.9, "trim", "6b4a3a"], [0, 0.65, 0.1, 2.0, 0.6, 0.2, "trim", "5e4032"],
		[-0.92, 0.45, 0.45, 0.18, 0.5, 0.9, "trim", "5e4032"], [0.92, 0.45, 0.45, 0.18, 0.5, 0.9, "trim", "5e4032"]]],
	"table": [2.2, [[0, 0.74, 0.55, 1.4, 0.06, 0.85, "floor", "9a7650"], [-0.62, 0.36, 0.2, 0.07, 0.72, 0.07, "floor", "7a5a3a"],
		[0.62, 0.36, 0.2, 0.07, 0.72, 0.07, "floor", "7a5a3a"], [-0.62, 0.36, 0.9, 0.07, 0.72, 0.07, "floor", "7a5a3a"],
		[0.62, 0.36, 0.9, 0.07, 0.72, 0.07, "floor", "7a5a3a"], [-0.95, 0.45, 0.55, 0.42, 0.06, 0.42, "floor", "8a6a4a"],
		[-1.14, 0.7, 0.55, 0.05, 0.55, 0.42, "floor", "8a6a4a"], [0.95, 0.45, 0.55, 0.42, 0.06, 0.42, "floor", "8a6a4a"],
		[1.14, 0.7, 0.55, 0.05, 0.55, 0.42, "floor", "8a6a4a"]]],
	"wardrobe": [1.3, [[0, 1.0, 0.3, 1.2, 2.0, 0.6, "floor", "7a5a3a"], [0, 1.0, 0.61, 0.02, 1.9, 0.02, "trim", "3a2a1a"]]],
	"shelf": [1.3, [[0, 0.9, 0.2, 1.2, 1.8, 0.4, "floor", "8a6a4a"], [0, 0.6, 0.25, 1.0, 0.3, 0.3, "trim", "7a3030"],
		[0, 1.25, 0.25, 0.9, 0.28, 0.3, "trim", "2f4f6f"]]],
	"kitchen": [2.6, [[0, 0.45, 0.3, 2.4, 0.9, 0.6, "trim", "e6e2d8"], [0, 0.92, 0.31, 2.44, 0.05, 0.64, "trim", "4a4a4a"],
		[0.6, 0.95, 0.3, 0.5, 0.02, 0.4, "trim", "9aa0a6"]]],
	"fridge": [0.9, [[0, 0.9, 0.35, 0.75, 1.8, 0.7, "trim", "eeeeea"], [0.3, 1.2, 0.71, 0.04, 0.5, 0.03, "trim", "8a8a8a"]]],
	"counter": [3.0, [[0, 0.5, 0.35, 2.8, 1.0, 0.7, "floor", "8a6a4a"], [0, 1.02, 0.36, 2.84, 0.05, 0.74, "trim", "5a5a5a"]]],
}

## Furniture along the walls of one storey, kept clear of doors, corners and
## the staircase, and outside the middle of the room where the loot lies.
func _furnish(sts: Dictionary, body: StaticBody3D, b: Dictionary, lv: int, shop: bool) -> void:
	var sx: float = b.size.x
	var sz: float = b.size.y
	var hx := sx * 0.5 - WALL_T
	var hz := sz * 0.5 - WALL_T
	var y0 := lv * STOREY_H
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b.pos.x * 31.0 + b.pos.y * 17.0) + lv * 101
	var pool: Array = ["counter", "shelf", "shelf", "fridge"] if shop else \
		(["bed", "wardrobe", "bed", "shelf", "sofa"] if lv == 1 else ["sofa", "table", "kitchen", "fridge", "shelf", "wardrobe", "table"])
	for w in 4:
		if b.get("stair", -1) == w: continue
		var along_x := w == 0 or w == 2
		var half := hx if along_x else hz
		var spans := [[-half + 0.5, half - 0.5]]
		if lv == 0 and b.doors.has(w):
			spans = [[-half + 0.5, -DOOR_W * 0.5 - 0.7], [DOOR_W * 0.5 + 0.7, half - 0.5]]
		# Keep the end next to the staircase free (its foot and its landing).
		var sw: int = b.get("stair", -1)
		var trim_hi := (along_x and sw == 1) or (not along_x and sw == 2)
		var trim_lo := (along_x and sw == 3) or (not along_x and sw == 0)
		for sp in spans:
			if trim_hi: sp[1] = minf(sp[1], half - WorldBuilder.STAIR_W - 1.3)
			if trim_lo: sp[0] = maxf(sp[0], -half + WorldBuilder.STAIR_W + 1.3)
		for sp in spans:
			var room: float = sp[1] - sp[0]
			var options := pool.filter(func(k): return FURNITURE[k][0] <= room)
			if options.is_empty() or rng.randf() < 0.2: continue
			var key: String = options[rng.randi() % options.size()]
			var length: float = FURNITURE[key][0]
			var u0: float = rng.randf_range(sp[0] + length * 0.5, sp[1] - length * 0.5)
			# Room-space position of (u along the wall, d away from it).
			var place := func(u: float, y: float, d: float) -> Vector3:
				match w:
					0: return Vector3(u0 + u, y0 + y, -hz + d)
					2: return Vector3(u0 + u, y0 + y, hz - d)
					1: return Vector3(hx - d, y0 + y, u0 + u)
					_: return Vector3(-hx + d, y0 + y, u0 + u)
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for part in FURNITURE[key][1]:
				var c: Vector3 = place.call(part[0], part[1], part[2])
				var size := Vector3(part[3], part[4], part[5]) if along_x else Vector3(part[5], part[4], part[3])
				_add_box(sts[part[6]], c, size, Color(part[7]))
				lo = lo.min(c - size * 0.5)
				hi = hi.max(c + size * 0.5)
			# One collision box round the whole piece (low pieces you can step over stay low).
			_shape(body, (lo + hi) * 0.5, hi - lo)

## Warehouse (corrugated metal, concrete floor, crates inside) or barn (red
## boards, hay inside): tall walls, wide doors, open roof space.
func _big_shed(node: Node3D, body: StaticBody3D, b: Dictionary) -> void:
	var barn: bool = b.kind == "barn"
	var sx: float = b.size.x
	var sz: float = b.size.y
	var hx := sx * 0.5
	var hz := sz * 0.5
	var wall_h := 5.6 if barn else 7.0
	var door_w := 3.6 if barn else 4.4
	var door_h := 4.0 if barn else 4.6
	var wall_mat := _wall_shader("planks" if barn else "corrugated", 2.0, 0.0, 0.7, 0.85)
	wall_mat.set_shader_parameter("tint", Color("b03c2c") if barn else [Color("c4cacd"), Color("98aab6"), Color("a8b39c")][b.tint % 3])
	wall_mat.set_shader_parameter("metallic", 0.0 if barn else 0.15)
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_texture = load("res://assets/textures/corrugated_col.jpg")
	roof_mat.normal_enabled = true
	roof_mat.normal_texture = load("res://assets/textures/corrugated_nrm.jpg")
	roof_mat.uv1_triplanar = true
	roof_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	roof_mat.albedo_color = Color("c4b2a4") if barn else Color("d0d4d6")
	roof_mat.metallic = 0.2
	roof_mat.roughness = 0.6
	var floor_mat := _wall_shader("concrete" if not barn else "wood", 3.0, 0.0, 0.0, 0.9)
	var crate_mat := _wall_shader("wood", 1.5, 0.0, 0.0, 0.8)
	var hay_mat := _hay_material()
	var sts := {}
	for k in ["wall", "roof", "floor", "crate", "hay", "trim"]:
		var t := SurfaceTool.new()
		t.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[k] = t
	var doors: Array = b.doors
	for w in 4:
		var along_x := w % 2 == 0
		var length := sx if along_x else sz
		var off := (-hz if w == 0 else hz) if along_x else (hx if w == 1 else -hx)
		var inset := -signf(off) * WALL_T * 0.5
		var spans := [[-length * 0.5, length * 0.5, 0.0, wall_h]]
		if doors.has(w):
			spans = [[-length * 0.5, -door_w * 0.5, 0.0, wall_h], [door_w * 0.5, length * 0.5, 0.0, wall_h], [-door_w * 0.5, door_w * 0.5, door_h, wall_h]]
			# Door frame
			for e in [-1.0, 1.0]:
				var fp := Vector3(e * (door_w * 0.5 + 0.08), door_h * 0.5, off + inset) if along_x else Vector3(off + inset, door_h * 0.5, e * (door_w * 0.5 + 0.08))
				_add_box(sts.trim, fp, Vector3(0.16, door_h, WALL_T + 0.12) if along_x else Vector3(WALL_T + 0.12, door_h, 0.16), Color("4a4440"))
		for sp in spans:
			var m: float = (sp[0] + sp[1]) * 0.5
			var l: float = sp[1] - sp[0]
			var y: float = (sp[2] + sp[3]) * 0.5
			var hh: float = sp[3] - sp[2]
			var cpos := Vector3(m, y, off + inset) if along_x else Vector3(off + inset, y, m)
			var csz := Vector3(l, hh, WALL_T) if along_x else Vector3(WALL_T, hh, l)
			_add_box(sts.wall, cpos, csz, Color.WHITE)
			_shape(body, cpos, csz)
	# Floor, foundation, and the gable roof (no ceiling: the roof space is open).
	_add_box(sts.floor, Vector3(0, -0.15, 0), Vector3(sx, 0.3, sz), Color.WHITE)
	_shape(body, Vector3(0, -0.15, 0), Vector3(sx, 0.3, sz))
	_add_box(sts.floor, Vector3(0, -1.2, 0), Vector3(sx + 0.1, 1.8, sz + 0.1), Color.WHITE)
	var rh := 3.6 if barn else 1.8
	_gable(sts.roof, Vector3(0, wall_h, 0), sx + 0.6, sz + 0.6, rh, sx >= sz, Color.WHITE)
	_roof_shape(body, Vector3(0, wall_h, 0), sx + 0.6, sz + 0.6, rh, sx >= sz)
	# Gable ends closed with boards / sheets.
	sts.roof.generate_normals()
	# Cover inside: crate stacks in the warehouse, hay bales in the barn.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b.pos.x * 7.0 + b.pos.y * 13.0)
	for k in 5:
		var p := Vector3(rng.randf_range(-hx + 2.0, hx - 2.0), 0, rng.randf_range(-hz + 2.0, hz - 2.0))
		if absf(p.x) < door_w * 0.5 + 1.0: continue     # keep the doorway lane clear
		if barn:
			for j in rng.randi_range(1, 3):
				var hb := Vector3(1.2, 0.9, 2.2)
				var hp := p + Vector3(0, 0.45 + j * 0.9, 0)
				_add_box(sts.hay, hp, hb, Color.WHITE)
				_shape(body, hp, hb)
		else:
			var n := rng.randi_range(1, 3)
			for j in n:
				var cs := Vector3(1.4, 1.2, 1.4)
				var cp := p + Vector3(rng.randf_range(-0.1, 0.1), 0.6 + j * 1.2 + 0.15, rng.randf_range(-0.1, 0.1))
				_add_box(sts.crate, cp, cs, Color.WHITE)
				_shape(body, cp, cs)
			var pal := Vector3(1.6, 0.15, 1.6)
			_add_box(sts.crate, p + Vector3(0, 0.075, 0), pal, Color.WHITE)
	var mats := {"wall": wall_mat, "roof": roof_mat, "floor": floor_mat, "crate": crate_mat, "hay": hay_mat, "trim": _trim_mat()}
	for k in sts:
		var mesh: ArrayMesh = sts[k].commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		mesh.surface_set_material(0, mats[k])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		node.add_child(mi)

var _hay_mat_cache: ShaderMaterial
func _hay_material() -> ShaderMaterial:
	if _hay_mat_cache == null:
		_hay_mat_cache = _wall_shader("sand", 0.8, 0.0, 0.0, 1.0)
		_hay_mat_cache.set_shader_parameter("tint", Color(1.0, 0.82, 0.45))
	return _hay_mat_cache

var _trim_mat_cache: StandardMaterial3D
func _trim_mat() -> StandardMaterial3D:
	if _trim_mat_cache == null:
		_trim_mat_cache = StandardMaterial3D.new()
		_trim_mat_cache.vertex_color_use_as_albedo = true
		_trim_mat_cache.vertex_color_is_srgb = true
		_trim_mat_cache.roughness = 0.6
	return _trim_mat_cache

# ---------- Containers, silos, chimneys, water towers, hay, gas stations ----------
func _structures() -> void:
	var parent := Node3D.new()
	parent.name = "Structures"
	root.add_child(parent)
	var body := StaticBody3D.new()
	parent.add_child(body)
	var cont_cols := [Color("9c3a2c"), Color("2f5d86"), Color("3f6b45"), Color("b0702a"), Color("7a7f84")]
	var cont_mats := []
	for c in cont_cols:
		var m := _wall_shader("corrugated", 1.2, 0.0, 0.5, 0.65)
		m.set_shader_parameter("tint", c)
		m.set_shader_parameter("metallic", 0.4)
		cont_mats.append(m)
	var metal := _wall_shader("corrugated", 1.6, 0.0, 0.4, 0.55)
	metal.set_shader_parameter("tint", Color("c9cdd0"))
	metal.set_shader_parameter("metallic", 0.5)
	var brick := _wall_shader("brick", 1.3, 0.0, 0.6, 0.9)
	var stone := _wall_shader("stone", 2.0, 0.0, 0.0, 0.9)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("ece9e2")
	white.roughness = 0.5
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("c62f2f")
	red.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("2b2b2b")
	dark.roughness = 0.6
	for st in island.structures:
		var p2: Vector2 = st.pos
		var g := island.height_at(p2.x, p2.y)
		var node := Node3D.new()
		node.position = Vector3(p2.x, g, p2.y)
		parent.add_child(node)
		match st.kind:
			"container":
				var size := Vector3(6.06, 2.59, 2.44)
				var y: float = 2.59 * st.level + 1.295
				_mesh_box(node, Vector3(0, y, 0), size, cont_mats[st.col])
				for e in [-1.0, 1.0]:
					_mesh_box(node, Vector3(e * 3.0, y, 0), Vector3(0.12, 2.6, 2.46), dark)   # end frames / doors
				_shape(body, node.position + Vector3(0, y, 0), size)
			"silo":
				_mesh_cyl(node, Vector3(0, 6.0, 0), 2.8, 2.8, 12.0, metal)
				_mesh_cyl(node, Vector3(0, 13.0, 0), 0.35, 2.95, 2.0, metal)
				_mesh_cyl(node, Vector3(0, 0.25, 0), 3.0, 3.0, 0.5, stone)
				for k in 12:
					_mesh_box(node, Vector3(2.9, 0.6 + k, 0), Vector3(0.05, 0.05, 0.5), dark)   # ladder rungs
				_cyl_shape(body, node.position + Vector3(0, 6.5, 0), 2.9, 13.0)
			"chimney":
				_mesh_cyl(node, Vector3(0, 17.0, 0), 1.1, 1.9, 34.0, brick)
				_mesh_cyl(node, Vector3(0, 33.6, 0), 1.3, 1.3, 0.8, stone)
				_mesh_cyl(node, Vector3(0, 1.0, 0), 2.3, 2.3, 2.0, stone)
				_cyl_shape(body, node.position + Vector3(0, 17.0, 0), 1.9, 34.0)
			"water_tower":
				for e in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					_mesh_box(node, Vector3(e.x * 2.2, 7.0, e.y * 2.2), Vector3(0.3, 14.0, 0.3), dark)
					_shape(body, node.position + Vector3(e.x * 2.2, 7.0, e.y * 2.2), Vector3(0.3, 14.0, 0.3))
				for hgt in [4.0, 9.0]:
					_mesh_box(node, Vector3(0, hgt, -2.2), Vector3(4.4, 0.15, 0.15), dark)
					_mesh_box(node, Vector3(0, hgt, 2.2), Vector3(4.4, 0.15, 0.15), dark)
					_mesh_box(node, Vector3(-2.2, hgt, 0), Vector3(0.15, 0.15, 4.4), dark)
					_mesh_box(node, Vector3(2.2, hgt, 0), Vector3(0.15, 0.15, 4.4), dark)
				_mesh_cyl(node, Vector3(0, 16.25, 0), 3.2, 3.2, 4.5, metal)
				_mesh_cyl(node, Vector3(0, 19.2, 0), 0.3, 3.35, 1.4, metal)
				_cyl_shape(body, node.position + Vector3(0, 16.25, 0), 3.2, 4.5)
			"hay":
				var hm := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.75
				cm.bottom_radius = 0.75
				cm.height = 1.3
				cm.radial_segments = 14
				hm.mesh = cm
				hm.material_override = _hay_material()
				hm.position = Vector3(0, 0.72, 0)
				hm.rotation = Vector3(0, deg_to_rad(st.rot), PI * 0.5)
				node.add_child(hm)
				_cyl_shape(body, node.position + Vector3(0, 0.75, 0), 0.75, 1.5)
			"canopy":
				var dir: Vector2 = st.get("dir", Vector2(1, 0))
				node.rotation.y = -atan2(dir.y, dir.x)
				for e in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var pp := Vector3(e.x * 4.5, 2.3, e.y * 3.0)
					_mesh_box(node, pp, Vector3(0.35, 4.6, 0.35), white)
					_shape(body, node.transform * pp, Vector3(0.35, 4.6, 0.35))
				_mesh_box(node, Vector3(0, 4.85, 0), Vector3(11.0, 0.5, 7.6), white)
				_mesh_box(node, Vector3(0, 4.85, 0), Vector3(11.06, 0.22, 7.66), red)
				for k in 2:
					var pp := Vector3(-2.2 + k * 4.4, 0.85, 0)
					_mesh_box(node, pp, Vector3(0.8, 1.7, 0.5), white)
					_mesh_box(node, pp + Vector3(0, 0.9, 0), Vector3(0.84, 0.16, 0.54), red)
					_mesh_box(node, pp + Vector3(0, 0.25, 0.27), Vector3(0.4, 0.3, 0.04), dark)
					_shape(body, node.transform * pp, Vector3(0.8, 1.7, 0.5))
				_mesh_box(node, Vector3(0, 0.08, 0), Vector3(10.5, 0.16, 3.0), stone)

func _mesh_box(node: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	node.add_child(mi)

func _mesh_cyl(node: Node3D, pos: Vector3, r_top: float, r_bottom: float, h: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = h
	cm.radial_segments = 20
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	node.add_child(mi)

func _cyl_shape(body: StaticBody3D, pos: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	cs.shape = cyl
	cs.position = pos
	body.add_child(cs)

## World-space approach, foot and top of a two-storey house's staircase (same layout
## as _upper_floor), for bots walking up and down. [] for other buildings.
static func stair_points(b: Dictionary) -> Array:
	if b.get("storeys", 1) < 2: return []
	var sx: float = b.size.x
	var sz: float = b.size.y
	var hx := sx * 0.5
	var hz := sz * 0.5
	var w: int = b.stair
	var along_x := w == 0 or w == 2
	var length := sx if along_x else sz
	var band: float = [-hz + WALL_T + STAIR_W * 0.5, hx - WALL_T - STAIR_W * 0.5, hz - WALL_T - STAIR_W * 0.5, -hx + WALL_T + STAIR_W * 0.5][w]
	var start := -length * 0.5 + WALL_T + 1.2
	var foot := Vector2(start - 0.6, band) if along_x else Vector2(band, start - 0.6)
	var top := Vector2(start + STAIR_RUN + 0.9, band) if along_x else Vector2(band, start + STAIR_RUN + 0.9)
	# A point in the room beside the first steps, so the foot is reached from
	# the side of the stairs and not along the end wall.
	var into := -signf(band)
	var near := Vector2(start + 0.4, band + into * 1.05) if along_x else Vector2(band + into * 1.05, start + 0.4)
	var c: Vector2 = b.pos
	return [Vector3(c.x + near.x, b.floor, c.y + near.y), Vector3(c.x + foot.x, b.floor, c.y + foot.y), Vector3(c.x + top.x, b.floor + STOREY_H, c.y + top.y)]

## Second floor of a two-storey house: the floor slab with a stairwell hole,
## a wooden staircase (ramp collision) along a wall without a door, a railing
## round the stairwell and a ledge on the outside between the storeys.
func _upper_floor(sts: Dictionary, body: StaticBody3D, b: Dictionary, col: Color, tcol: Color) -> void:
	var sx: float = b.size.x
	var sz: float = b.size.y
	var hx := sx * 0.5
	var hz := sz * 0.5
	var w: int = b.stair
	var along_x := w == 0 or w == 2
	var length := sx if along_x else sz
	var band := (-hz + WALL_T + STAIR_W * 0.5) if w == 0 else (hz - WALL_T - STAIR_W * 0.5) if w == 2 \
		else (hx - WALL_T - STAIR_W * 0.5) if w == 1 else (-hx + WALL_T + STAIR_W * 0.5)
	var start := -length * 0.5 + WALL_T + 1.2   # room to step on at the foot
	# (along, y, across offset) -> building space
	var at := func(a: float, y: float, c: float) -> Vector3:
		return Vector3(a, y, band + c) if along_x else Vector3(band + c, y, a)
	var size := func(da: float, dy: float, dc: float) -> Vector3:
		return Vector3(da, dy, dc) if along_x else Vector3(dc, dy, da)
	var steps := 16
	var tread := STAIR_RUN / steps
	var rise := STOREY_H / steps
	for i in steps:
		var hgt := (i + 1) * rise
		_add_box(sts.floor, at.call(start + (i + 0.5) * tread, hgt * 0.5, 0.0), size.call(tread, hgt, STAIR_W), Color("a08060"))
	var pts := PackedVector3Array()
	for c in [-STAIR_W * 0.5, STAIR_W * 0.5]:
		pts.append(at.call(start, 0.0, c))
		pts.append(at.call(start + STAIR_RUN, STOREY_H, c))
		pts.append(at.call(start + STAIR_RUN, 0.0, c))
	var cps := ConvexPolygonShape3D.new()
	cps.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = cps
	body.add_child(cs)
	# Floor slab with the stairwell cut out (head room from 1.8 m along the stairs).
	var y := STOREY_H - 0.1
	var h0 := start + 1.8
	var h1 := start + STAIR_RUN
	var c0 := -STAIR_W * 0.5 - 0.05
	var c1 := STAIR_W * 0.5 + 0.05
	var lo := -length * 0.5 - 0.1
	var hi := length * 0.5 + 0.1
	var across := (sz if along_x else sx) * 0.5 + 0.1
	var cmin := -across - band
	var cmax := across - band
	var pieces := [[lo, h0, cmin, cmax], [h1, hi, cmin, cmax], [h0, h1, cmin, c0], [h0, h1, c1, cmax]]
	for pc in pieces:
		if pc[1] - pc[0] < 0.01 or pc[3] - pc[2] < 0.01: continue
		var ctr: Vector3 = at.call((pc[0] + pc[1]) * 0.5, y, (pc[2] + pc[3]) * 0.5)
		var sz3: Vector3 = size.call(pc[1] - pc[0], 0.2, pc[3] - pc[2])
		_add_box(sts.floor, ctr + Vector3(0, 0.001, 0), sz3, Color("b09070"))
		_shape(body, ctr, sz3)
	# Railing on the open side of the stairwell.
	var side_c := c1 if absf(band + c1) < absf(band + c0) else c0
	var rail_c: Vector3 = at.call((h0 + h1) * 0.5, STOREY_H + 0.5, side_c)
	var rail_s: Vector3 = size.call(h1 - h0, 1.0, 0.06)
	_add_box(sts.trim, rail_c + Vector3(0, 0.45, 0), size.call(h1 - h0, 0.08, 0.1), tcol)
	for k in 5:
		_add_box(sts.trim, at.call(h0 + (h1 - h0) * k / 4.0, STOREY_H + 0.5, side_c), size.call(0.06, 1.0, 0.06), tcol)
	_shape(body, rail_c, rail_s)
	# Ledge between the storeys on the outside.
	_add_box(sts.stone, Vector3(0, STOREY_H - 0.05, -hz - 0.02), Vector3(sx + 0.2, 0.16, 0.16), Color.WHITE)
	_add_box(sts.stone, Vector3(0, STOREY_H - 0.05, hz + 0.02), Vector3(sx + 0.2, 0.16, 0.16), Color.WHITE)
	_add_box(sts.stone, Vector3(-hx - 0.02, STOREY_H - 0.05, 0), Vector3(0.16, 0.16, sz + 0.2), Color.WHITE)
	_add_box(sts.stone, Vector3(hx + 0.02, STOREY_H - 0.05, 0), Vector3(0.16, 0.16, sz + 0.2), Color.WHITE)

## Collision for a gable roof, so you can land on it instead of inside it.
func _roof_shape(body: StaticBody3D, base: Vector3, w: float, d: float, h: float, along_x: bool) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	var pts := PackedVector3Array([Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(-hw, 0, hd), Vector3(hw, 0, hd)])
	if along_x:
		pts.append_array([Vector3(-hw, h, 0), Vector3(hw, h, 0)])
	else:
		pts.append_array([Vector3(0, h, -hd), Vector3(0, h, hd)])
	for i in pts.size(): pts[i] += base
	var cps := ConvexPolygonShape3D.new()
	cps.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = cps
	body.add_child(cs)

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

## Pine crown in unit space (height 0..1, radius about 0.5): drooping star-shaped
## layers, smaller towards the top. UV.x carries ambient occlusion.
func _pine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var layers := 6
	var spokes := 14
	for k in layers:
		var f := float(k) / layers
		var y_bot := f * 0.82
		var y_top := y_bot + 0.34 - f * 0.1
		var rad := 0.52 * (1.0 - f * 0.82)
		var ring := []
		for i in spokes * 2:
			var a := TAU * i / (spokes * 2) + k * 0.4
			var r := rad * (1.0 if i % 2 == 0 else 0.62) * rng.randf_range(0.85, 1.1)
			var droop := -0.05 * (1.0 if i % 2 == 0 else 0.0)
			ring.append(Vector3(cos(a) * r, y_bot + droop + rng.randf_range(-0.015, 0.015), sin(a) * r))
		var apex := Vector3(rng.randf_range(-0.02, 0.02), y_top, rng.randf_range(-0.02, 0.02))
		var under := Vector3(0, y_bot + 0.06, 0)
		var ao_top := 0.55 + 0.45 * f
		for i in ring.size():
			var p0: Vector3 = ring[i]
			var p1: Vector3 = ring[(i + 1) % ring.size()]
			var n := (p1 - p0).cross(apex - p0).normalized()
			if n.y < 0: n = -n
			for v in [[apex, 1.0], [p1, ao_top * 0.75], [p0, ao_top * 0.75]]:
				var vn: Vector3 = (n + Vector3(v[0].x, 0, v[0].z).normalized() * 0.6).normalized()
				st.set_normal(vn)
				st.set_uv(Vector2(v[1], 1.0 - v[0].y))
				st.add_vertex(v[0])
			# Dark underside.
			for v in [p0, p1, under]:
				st.set_normal(Vector3.DOWN)
				st.set_uv(Vector2(0.25, 1.0 - v.y))
				st.add_vertex(v)
	st.index()
	return st.commit()

## Broadleaf crown in unit space: a cluster of noisy lumps, centred at y = 0.
func _leafy_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise := FastNoiseLite.new()
	noise.seed = 4
	noise.frequency = 2.2
	var lumps := [[Vector3(0, 0, 0), 0.42], [Vector3(0.28, 0.12, 0.1), 0.3], [Vector3(-0.25, 0.1, -0.15), 0.32],
		[Vector3(0.05, 0.3, -0.2), 0.28], [Vector3(-0.1, 0.28, 0.24), 0.27], [Vector3(0.22, -0.12, -0.24), 0.26], [Vector3(-0.3, -0.1, 0.2), 0.25]]
	var rings := 6
	var segs := 9
	for l in lumps:
		var c: Vector3 = l[0]
		var r: float = l[1]
		var grid := []
		for j in rings + 1:
			var row := []
			var phi := PI * j / rings
			for i in segs + 1:
				var th := TAU * i / segs
				var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
				var rr := r * (1.0 + 0.28 * noise.get_noise_3dv(c * 3.0 + d))
				var pos := c + d * rr
				pos.y = max(pos.y, c.y - r * 0.55)
				row.append([pos, d])
			grid.append(row)
		for j in rings:
			for i in segs:
				var quad := [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j][i], grid[j + 1][i + 1], grid[j + 1][i]]
				for q in quad:
					var pos: Vector3 = q[0]
					var nrm: Vector3 = (q[1] * 0.7 + (pos - Vector3(0, -0.1, 0)).normalized() * 0.3).normalized()
					st.set_normal(nrm)
					st.set_uv(Vector2(clamp(0.45 + (pos.y + 0.4) * 0.6 + pos.length() * 0.3, 0.3, 1.0), 0.5 - pos.y))
					st.add_vertex(pos)
	st.index()
	return st.commit()

func _trees() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.45
	trunk.bottom_radius = 1.0
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 2
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color("c8b8a8")
	trunk_mat.albedo_texture = load("res://assets/textures/bark_col.jpg")
	trunk_mat.normal_enabled = true
	trunk_mat.normal_texture = load("res://assets/textures/bark_nrm.jpg")
	trunk_mat.uv1_scale = Vector3(2.0, 3.0, 1.0)
	trunk_mat.roughness = 1.0
	trunk.material = trunk_mat
	var fol := ShaderMaterial.new()
	fol.shader = load("res://shaders/foliage.gdshader")
	var pine_mesh := _pine_mesh()
	pine_mesh.surface_set_material(0, fol)
	var leafy_mesh := _leafy_mesh()
	leafy_mesh.surface_set_material(0, fol)

	# Trees go into 256 m chunks so the renderer can cull whole chunks off screen.
	# Near chunks use the detailed trees (real trunk, branches and photo leaf
	# cards); far chunks swap to the cheap solid crowns.
	pine_mesh = _with_lods(pine_mesh)
	leafy_mesh = _with_lods(leafy_mesh)
	var near_d: float = [160.0, 240.0, 320.0, 450.0, 650.0][Game.quality_level()] * Game.view_k()
	var bark_mat := trunk_mat.duplicate() as StandardMaterial3D
	bark_mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	var leaf_mat := ShaderMaterial.new()
	leaf_mat.shader = load("res://shaders/leaf_card.gdshader")
	leaf_mat.set_shader_parameter("albedo_tex", load("res://assets/textures/leaf_cluster.png"))
	var palm_bark := bark_mat.duplicate() as StandardMaterial3D
	palm_bark.albedo_color = Color("c9b28c")
	palm_bark.uv1_scale = Vector3(1.0, 3.0, 1.0)
	var frond_mat := ShaderMaterial.new()
	frond_mat.shader = load("res://shaders/leaf_card.gdshader")
	frond_mat.set_shader_parameter("albedo_tex", load("res://assets/textures/palm_frond.png"))
	frond_mat.set_shader_parameter("translucency", 0.45)
	frond_mat.set_shader_parameter("sway", 1.4)
	var cactus_mat := StandardMaterial3D.new()
	cactus_mat.albedo_color = Color("4f6b38")
	cactus_mat.albedo_texture = load("res://assets/textures/moss_col.jpg")
	cactus_mat.uv1_scale = Vector3(4.0, 3.0, 1.0)
	cactus_mat.roughness = 0.75
	cactus_mat.vertex_color_use_as_albedo = false
	var needle_mat := ShaderMaterial.new()
	needle_mat.shader = load("res://shaders/leaf_card.gdshader")
	needle_mat.set_shader_parameter("albedo_tex", load("res://assets/textures/pine_branch.png"))
	needle_mat.set_shader_parameter("translucency", 0.3)
	needle_mat.set_shader_parameter("sway", 0.6)
	var near_meshes := {}
	for v in 2:
		var bl := TreeModels.broadleaf(3 + v * 17)
		bl.surface_set_material(0, bark_mat)
		bl.surface_set_material(1, leaf_mat)
		near_meshes["bl%d" % v] = bl
		var pn := TreeModels.pine(5 + v * 23)
		pn.surface_set_material(0, bark_mat)
		pn.surface_set_material(1, needle_mat)
		near_meshes["pn%d" % v] = pn
		var pm := TreeModels.palm(7 + v * 31)
		pm.surface_set_material(0, palm_bark)
		pm.surface_set_material(1, frond_mat)
		near_meshes["pm%d" % v] = pm
	# Cactus and dead trees are simple: the same mesh near and far.
	var mid_meshes := {}
	for v in 2:
		var ca := TreeModels.cactus(11 + v * 7)
		ca.surface_set_material(0, cactus_mat)
		mid_meshes["ca%d" % v] = ca
	var dd := TreeModels.dead(13)
	dd.surface_set_material(0, bark_mat)
	mid_meshes["dd0"] = dd
	var near_tints := [Color(0.82, 0.86, 0.8), Color(0.72, 0.84, 0.7), Color(0.92, 0.88, 0.66), Color(0.7, 0.8, 0.74), Color(0.86, 0.82, 0.62)]
	var chunks := {}
	# Collision cylinders go into one static body per chunk: thousands of shapes
	# on a single body make adding each one slower than the last.
	var bodies := {}
	var tree_root := Node3D.new()
	tree_root.name = "TreeBodies"
	root.add_child(tree_root)
	var pine_cols := [Color("23401f"), Color("2a4a24"), Color("1f3a20"), Color("30502a")]
	var leaf_cols := [Color("3f6a26"), Color("4a7228"), Color("557a2e"), Color("3a5f24"), Color("6a7a2c")]
	for t in island.trees:
		var key := Vector2i(int(t.pos.x / 256.0), int(t.pos.y / 256.0))
		if not chunks.has(key):
			chunks[key] = {"trunk": [], "pine": [], "leaf": [], "bl0": [], "bl1": [], "pn0": [], "pn1": [], "pm0": [], "pm1": [], "ca0": [], "ca1": [], "dd0": []}
		var ch: Dictionary = chunks[key]
		if not bodies.has(key):
			var bb := StaticBody3D.new()
			tree_root.add_child(bb)
			bodies[key] = bb
		var body: StaticBody3D = bodies[key]
		var g := island.height_at(t.pos.x, t.pos.y) - 0.3
		var p := Vector3(t.pos.x, g, t.pos.y)
		var h: float = t.h
		var tk: String = t.get("kind", "pine" if t.pine else "broad")
		if tk in ["palm", "cactus", "dead"]:
			var rot2 := Basis(Vector3.UP, t.shade * TAU)
			var v2 := int(t.shade * 997.0) % 2
			var tint2: Color = near_tints[int(t.shade * 31.0) % near_tints.size()]
			match tk:
				"palm":
					var k2 := h / 10.0
					ch["pm%d" % v2].append([Transform3D(rot2.scaled(Vector3(k2, k2, k2)), p + Vector3(0, 0.3, 0)), tint2])
					# Far away: the trunk and a flat green crown.
					ch.trunk.append([Transform3D(Basis.from_scale(Vector3(t.r, h, t.r)), p + Vector3(0, h * 0.5, 0)), Color.WHITE])
					ch.leaf.append([Transform3D(rot2.scaled(Vector3(h * 0.75, h * 0.22, h * 0.75)), p + Vector3(0, h * 0.97, 0)), Color("4f7a2a")])
				"cactus":
					var k3 := h / 4.0
					ch["ca%d" % v2].append([Transform3D(rot2.scaled(Vector3(k3, k3, k3)), p + Vector3(0, 0.25, 0)), Color.WHITE])
				"dead":
					var k4 := h / 4.5
					ch.dd0.append([Transform3D(rot2.scaled(Vector3(k4, k4, k4)), p + Vector3(0, 0.25, 0)), Color.WHITE])
			var cs2 := CollisionShape3D.new()
			var cyl2 := CylinderShape3D.new()
			cyl2.radius = t.r + 0.1
			cyl2.height = 4.0
			cs2.shape = cyl2
			cs2.position = p + Vector3(0, 2.0, 0)
			body.add_child(cs2)
			continue
		var trunk_h := h * (0.4 if t.pine else 0.55)
		ch.trunk.append([Transform3D(Basis.from_scale(Vector3(t.r, trunk_h, t.r)), p + Vector3(0, trunk_h * 0.5, 0)), Color.WHITE])
		var rot := Basis(Vector3.UP, t.shade * TAU)
		var variant := int(t.shade * 997.0) % 2
		var tint: Color = near_tints[int(t.shade * 31.0) % near_tints.size()]
		var k := h / 10.0
		var near_x := Transform3D(rot.scaled(Vector3(k, k * (0.92 + fmod(t.shade * 5.0, 1.0) * 0.16), k)), p + Vector3(0, 0.3, 0))
		if t.pine:
			var w := h * (0.55 + fmod(t.shade * 13.0, 1.0) * 0.15)
			ch.pine.append([Transform3D(rot.scaled(Vector3(w, h * 0.85, w)), p + Vector3(0, h * 0.18, 0)), pine_cols[int(t.shade * 7) % 4]])
			ch["pn%d" % variant].append([near_x, tint])
		else:
			var w := h * (0.62 + fmod(t.shade * 7.0, 1.0) * 0.2)
			ch.leaf.append([Transform3D(rot.scaled(Vector3(w, w * 0.85, w)), p + Vector3(0, h * 0.68, 0)), leaf_cols[int(t.shade * 11) % 5]])
			ch["bl%d" % variant].append([near_x, tint])
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = t.r + 0.1
		cyl.height = 4.0
		cs.shape = cyl
		cs.position = p + Vector3(0, 2.0, 0)
		body.add_child(cs)
	var meshes := {"trunk": trunk, "pine": pine_mesh, "leaf": leafy_mesh}
	meshes.merge(near_meshes)
	meshes.merge(mid_meshes)
	for key in chunks:
		for kind in meshes:
			var list: Array = chunks[key][kind]
			if list.is_empty(): continue
			var colored: bool = kind != "trunk" and not mid_meshes.has(kind)
			var mm := _multimesh(meshes[kind], list.size(), colored)
			for i in list.size():
				mm.set_instance_transform(i, list[i][0])
				if colored: mm.set_instance_color(i, list[i][1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if mid_meshes.has(kind):
				mmi.visibility_range_end = 700.0
			elif near_meshes.has(kind):
				mmi.visibility_range_end = near_d
				mmi.visibility_range_end_margin = 40.0
			else:
				mmi.visibility_range_begin = near_d
				mmi.visibility_range_begin_margin = 40.0
				if kind == "trunk":
					mmi.visibility_range_end = 900.0
			root.add_child(mmi)

## Adds automatic LOD levels to a generated mesh.
func _with_lods(mesh: ArrayMesh) -> ArrayMesh:
	var im := ImporterMesh.new()
	for i in mesh.get_surface_count():
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i), [], {}, mesh.surface_get_material(i))
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()

func _rock_mesh() -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 8
	noise.frequency = 1.4
	var sph := SphereMesh.new()
	sph.radial_segments = 14
	sph.rings = 8
	var arr := sph.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		var d := v.normalized() if v.length() > 0.001 else Vector3.UP
		v = d * (1.0 + 0.35 * noise.get_noise_3dv(d * 1.5) + 0.12 * noise.get_noise_3dv(d * 5.0))
		v.y = max(v.y, -0.45)
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.create_from(tmp, 0)
	st.generate_normals()
	return st.commit()

func _rocks() -> void:
	var rock := _rock_mesh()
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("d8d4cc")
	rm.albedo_texture = load("res://assets/textures/rock_col.jpg")
	rm.normal_enabled = true
	rm.normal_texture = load("res://assets/textures/rock_nrm.jpg")
	rm.uv1_triplanar = true
	rm.uv1_scale = Vector3(0.4, 0.4, 0.4)
	rm.roughness = 0.95
	rock.surface_set_material(0, rm)
	var mm := _multimesh(rock, island.rocks.size(), false)
	var bodies := {}
	var i := 0
	for r in island.rocks:
		var key := Vector2i(int(r.pos.x / 512.0), int(r.pos.y / 512.0))
		if not bodies.has(key):
			var bb := StaticBody3D.new()
			root.add_child(bb)
			bodies[key] = bb
		var body: StaticBody3D = bodies[key]
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

# ---------- Power lines along the roads ----------
func _power_lines() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://assets/textures/wood_col.jpg")
	wood.albedo_color = Color("8a7a6a")
	wood.normal_enabled = true
	wood.normal_texture = load("res://assets/textures/wood_nrm.jpg")
	wood.uv1_scale = Vector3(1.0, 4.0, 1.0)
	wood.roughness = 0.95
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.1
	pole.bottom_radius = 0.15
	pole.height = 9.0
	pole.radial_segments = 6
	pole.rings = 1
	st.append_from(pole, 0, Transform3D(Basis(), Vector3(0, 4.5, 0)))
	var arm := BoxMesh.new()
	arm.size = Vector3(1.8, 0.12, 0.12)
	st.append_from(arm, 0, Transform3D(Basis(), Vector3(0, 8.4, 0)))
	var ins := CylinderMesh.new()
	ins.top_radius = 0.04
	ins.bottom_radius = 0.06
	ins.height = 0.2
	ins.radial_segments = 6
	for x in [-0.8, 0.0, 0.8]:
		st.append_from(ins, 0, Transform3D(Basis(), Vector3(x, 8.56, 0)))
	var pole_mesh := st.commit()
	pole_mesh.surface_set_material(0, wood)
	var wire_mat := StandardMaterial3D.new()
	wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire_mat.albedo_color = Color(0.08, 0.08, 0.08)
	var body := StaticBody3D.new()
	body.name = "PowerPoles"
	root.add_child(body)
	var xforms := []
	var wires := SurfaceTool.new()
	wires.begin(Mesh.PRIMITIVE_LINES)
	for rd in island.roads:
		var a: Vector2 = rd.a
		var b: Vector2 = rd.b
		var dir := (b - a).normalized()
		var side: Vector2 = Vector2(-dir.y, dir.x) * (rd.w * 0.5 + 3.0)
		var length := a.distance_to(b)
		var prev: Array = []
		var d := 30.0
		while d < length - 30.0:
			var q: Vector2 = a + dir * d + side
			d += 40.0
			var free := island.height_at(q.x, q.y) > 1.2
			for bld in island.buildings:
				if free and q.distance_to(bld.pos) < maxf(bld.size.x, bld.size.y) * 0.75 + 2.0:
					free = false
			if not free:
				prev = []
				continue
			var g := island.height_at(q.x, q.y) - 0.4
			var basis := Basis(Vector3.UP, -atan2(dir.y, dir.x) + PI * 0.5)
			xforms.append(Transform3D(basis, Vector3(q.x, g, q.y)))
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.16
			cyl.height = 9.0
			cs.shape = cyl
			cs.position = Vector3(q.x, g + 4.5, q.y)
			body.add_child(cs)
			var tips := []
			for x in [-0.8, 0.0, 0.8]:
				tips.append(Vector3(q.x, g + 8.66, q.y) + basis * Vector3(x, 0, 0))
			if not prev.is_empty():
				for k in 3:
					# Sagging wire as a few straight pieces.
					var p0: Vector3 = prev[k]
					var p1: Vector3 = tips[k]
					var last := p0
					for i in range(1, 7):
						var t := i / 6.0
						var p := p0.lerp(p1, t) - Vector3(0, 4.0 * t * (1.0 - t) * 1.1, 0)
						wires.add_vertex(last)
						wires.add_vertex(p)
						last = p
			prev = tips
	if xforms.is_empty():
		return
	var mm := _multimesh(pole_mesh, xforms.size(), false)
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	root.add_child(mmi)
	var wm := wires.commit()
	wm.surface_set_material(0, wire_mat)
	var wmi := MeshInstance3D.new()
	wmi.mesh = wm
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wmi)

# ---------- Grass patch around the player ----------
func _grass() -> void:
	# One clump = three crossed cards with a photo grass tuft (real blades).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brng := RandomNumberGenerator.new()
	brng.seed = 21
	for k in 3:
		var ang := k * PI / 3.0 + brng.randf_range(-0.2, 0.2)
		var side := Vector3(cos(ang), 0, sin(ang)) * 0.36
		var off := Vector3(brng.randf_range(-0.08, 0.08), 0, brng.randf_range(-0.08, 0.08))
		var h := brng.randf_range(0.4, 0.5)
		var lean := Vector3(-sin(ang), 0, cos(ang)) * brng.randf_range(-0.08, 0.08)
		var c := [off - side, off + side, off + side + Vector3(0, h, 0) + lean, off - side + Vector3(0, h, 0) + lean]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[i])
			st.add_vertex(c[i])
	var blade := st.commit()
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	grass_mat.set_shader_parameter("heightmap", height_tex)
	grass_mat.set_shader_parameter("maskmap", mask_tex)
	grass_mat.set_shader_parameter("biomemap", biome_tex)
	grass_mat.set_shader_parameter("hm_cells", float(Island.N - 1))
	grass_mat.set_shader_parameter("noise_a", noise_a)
	grass_mat.set_shader_parameter("map_size", island.size)
	grass_mat.set_shader_parameter("grass_c", load("res://assets/textures/grass_col.jpg"))
	grass_mat.set_shader_parameter("tuft", load("res://assets/textures/grass_tuft.png"))
	var lv := Game.quality_level()
	var spacing: float = [0.8, 0.75, 0.55, 0.5, 0.42][lv]
	var radius: float = [30.0, 32.0, 40.0, 52.0, 70.0][lv] * Game.view_k()
	grass_snap = spacing * 12.0
	grass_mat.set_shader_parameter("radius", radius)
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
	grass.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # snaps along with the player
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
	grass.position = Vector3(snappedf(center.x, grass_snap), 0, snappedf(center.z, grass_snap))
	grass_mat.set_shader_parameter("center", center)
