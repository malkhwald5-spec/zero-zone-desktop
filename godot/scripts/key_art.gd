class_name KeyArt
extends Node3D
## Season key art ("ليلة القمر الأحمر") built from 3D primitives and rendered
## once into a texture for the loading screens: a gothic balcony at night under
## a blood moon, two players fighting a leaping villain and climbing ghouls,
## with shards of red glass flying everywhere.

## Renders the key art off-screen and returns it as a texture.
static func render(host: Node, size := Vector2i(1280, 720)) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var art := KeyArt.new()
	vp.add_child(art)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var tex := ImageTexture.create_from_image(vp.get_texture().get_image())
	vp.queue_free()
	return tex

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 7
	_environment()
	_backdrop()
	_balcony()
	_shards()
	_characters()
	var cam := Camera3D.new()
	cam.fov = 52
	add_child(cam)
	cam.look_at_from_position(Vector3(0.4, 1.7, 6.2), Vector3(0.2, 3.1, -4.0))
	cam.current = true

func _mat(c: Color, rough := 0.85, emit := 0.0, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m

func _put(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	add_child(mi)
	return mi

func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("1d1638")
	sky_mat.sky_horizon_color = Color("b9648f")
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color("6a3a62")
	sky_mat.ground_bottom_color = Color("120c1c")
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7d6aa8")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color("8a5a8e")
	env.fog_density = 0.012
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Cold moonlight from behind plus a warm rim from the lanterns.
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("d9b8ff")
	moon.light_energy = 0.9
	moon.shadow_enabled = true
	add_child(moon)
	moon.look_at_from_position(Vector3(4, 12, -30), Vector3.ZERO)
	var red := OmniLight3D.new()
	red.light_color = Color("ff3b4f")
	red.light_energy = 4.0
	red.omni_range = 9.0
	red.position = Vector3(0.5, 4.5, -2.5)
	add_child(red)

func _backdrop() -> void:
	# Blood moon with a halo.
	var moon := SphereMesh.new()
	moon.radius = 7.0
	moon.height = 14.0
	_put(moon, _mat(Color("d8344e"), 1.0, 1.1), Vector3(7, 20, -70))
	var halo := SphereMesh.new()
	halo.radius = 9.5
	halo.height = 19.0
	var hm := _mat(Color(1.0, 0.25, 0.35, 0.14), 1.0, 0.6)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_put(halo, hm, Vector3(7, 20, -72))
	# Gothic spires (cathedral silhouettes) in the haze.
	var spire_mat := _mat(Color("2a2140"), 0.9)
	var win_mat := _mat(Color("ffb35c"), 0.5, 3.0)
	for i in 14:
		var x := -26.0 + i * 4.2 + rng.randf_range(-1, 1)
		var z := -30.0 - rng.randf_range(0, 18)
		var h := rng.randf_range(8, 22)
		var w := rng.randf_range(1.6, 3.4)
		_put(_box(Vector3(w, h, w)), spire_mat, Vector3(x, h * 0.5 - 2, z))
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = w * 0.62
		cone.height = h * 0.45
		cone.radial_segments = 4
		_put(cone, spire_mat, Vector3(x, h - 2 + h * 0.22, z), Vector3(0, PI / 4, 0))
		for k in 3:
			if rng.randf() < 0.5:
				_put(_box(Vector3(0.3, 0.6, 0.05)), win_mat, Vector3(x + rng.randf_range(-w * 0.3, w * 0.3), rng.randf_range(2, h - 3), z + w * 0.51))
	# Bats.
	var bat_mat := _mat(Color("120d18"))
	for i in 9:
		var p := Vector3(rng.randf_range(-12, 14), rng.randf_range(8, 17), rng.randf_range(-30, -14))
		for side in [-1, 1]:
			_put(_box(Vector3(0.9, 0.05, 0.3)), bat_mat, p + Vector3(side * 0.42, 0, 0), Vector3(0, 0, side * 0.45))

func _balcony() -> void:
	var stone := _mat(Color("3b3446"), 0.9)
	var dark := _mat(Color("1c1824"), 0.9)
	# Floor and balustrade.
	_put(_box(Vector3(30, 0.4, 14)), stone, Vector3(0, -0.2, 2))
	_put(_box(Vector3(30, 0.25, 0.6)), stone, Vector3(0, 1.15, -1.2))
	_put(_box(Vector3(30, 0.2, 0.7)), stone, Vector3(0, 0.1, -1.2))
	var post := CylinderMesh.new()
	post.top_radius = 0.09
	post.bottom_radius = 0.13
	post.height = 0.85
	for i in 60:
		_put(post, stone, Vector3(-15 + i * 0.5, 0.62, -1.2))
	# Huge gothic window frame on both sides (dark pillars with arches).
	for side in [-1, 1]:
		_put(_box(Vector3(2.4, 14, 1.6)), dark, Vector3(side * 6.8, 7, -1.8))
		var arch := TorusMesh.new()
		arch.inner_radius = 6.0
		arch.outer_radius = 7.0
		arch.rings = 32
		_put(arch, dark, Vector3(0, 9.5, -1.8), Vector3(PI / 2, 0, 0), Vector3(1, 1, 0.25))
		# Lantern on the pillar.
		var lamp := _mat(Color("ffb057"), 0.4, 1.4)
		_put(_box(Vector3(0.35, 0.55, 0.35)), lamp, Vector3(side * 5.4, 4.2, -0.8))
		var ol := OmniLight3D.new()
		ol.light_color = Color("ffb057")
		ol.light_energy = 2.2
		ol.omni_range = 6.0
		ol.position = Vector3(side * 5.2, 4.2, -0.4)
		add_child(ol)

func _shards() -> void:
	# Shattered red stained glass, flying out of the window.
	for i in 70:
		var m := _mat(Color.from_hsv(rng.randf_range(0.95, 1.0), rng.randf_range(0.6, 0.9), rng.randf_range(0.45, 0.85), 0.8), 0.2, rng.randf_range(0.2, 0.7))
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var s := rng.randf_range(0.2, 0.9)
		var p := Vector3(rng.randf_range(-6, 6), rng.randf_range(2.2, 9.5), rng.randf_range(-4, 2.5))
		_put(_box(Vector3(s, s * rng.randf_range(0.8, 1.8), 0.02)), m, p, Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
	# Red energy streaks.
	var streak := _mat(Color("ff2a4a"), 0.3, 1.6)
	for i in 3:
		var a := rng.randf_range(-0.8, 0.8)
		_put(_box(Vector3(rng.randf_range(2.0, 3.5), 0.015, 0.015)), streak, Vector3(rng.randf_range(-4, 4), rng.randf_range(2, 7), rng.randf_range(-3, 0)), Vector3(0, rng.randf_range(-0.5, 0.5), a))

func _characters() -> void:
	# Player 1: left foreground, seen from behind, aiming up at the villain.
	var p1 := SoldierModel.new(Color("d8d8d2"), Color("f2a900"), Color("2c3a55"))
	p1.set_weapon("ar")
	p1.set_gear(2, 2, 0)
	add_child(p1)
	p1.position = Vector3(-1.9, 0, 2.6)
	p1.rotation.y = 0.35
	p1.set_pose("stand", 0.0, true, 0.016, 0.0)
	p1.spine.rotation.x = 0.35
	# Player 2: right, firing with a muzzle flash.
	var p2 := SoldierModel.new(Color("232327"), Color("f2a900"), Color("39404f"))
	p2.set_weapon("smg")
	p2.set_gear(0, 0, 0)
	add_child(p2)
	p2.position = Vector3(2.6, 0, 1.6)
	p2.rotation.y = -0.55
	p2.set_pose("stand", 0.0, true, 0.016, 0.0)
	p2.spine.rotation.x = 0.15
	var flash := OmniLight3D.new()
	flash.light_color = Color("ffb347")
	flash.light_energy = 6.0
	flash.omni_range = 4.0
	add_child(flash)
	flash.global_position = p2.to_global(Vector3(0.14, 1.45, -1.2))
	var fm := SphereMesh.new()
	fm.radius = 0.12
	fm.height = 0.24
	_put(fm, _mat(Color("ffc060"), 0.2, 2.5), flash.global_position, Vector3.ZERO, Vector3(1, 1, 2.2))
	# The villain: leaping through the window with a cape.
	var v := SoldierModel.new(Color("4a1420"), Color.BLACK, Color("1e0f14"))
	v.set_gear(0, 0, 0)
	add_child(v)
	v.position = Vector3(0.4, 3.0, -1.6)
	v.rotation.y = PI + 0.25
	v.set_pose("stand", 0.0, false, 0.016, 0.0)
	v.rig.rotation.x = 0.35
	v.arms[0].shoulder.rotation = Vector3(2.7, 0, 0.5)
	v.arms[1].shoulder.rotation = Vector3(1.6, 0, -0.9)
	v.legs[0].thigh.rotation.x = 1.0
	v.legs[0].knee.rotation.x = -1.4
	v.legs[1].thigh.rotation.x = -0.4
	v.legs[1].knee.rotation.x = -0.9
	var cape := _mat(Color("2a0a12"), 0.7)
	cape.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cm := MeshInstance3D.new()
	cm.mesh = _box(Vector3(1.4, 1.5, 0.03))
	cm.material_override = cape
	cm.position = Vector3(0, 0.2, 0.35)
	cm.rotation.x = 0.7
	v.spine.add_child(cm)
	# Ghouls climbing over the balustrade.
	for i in 5:
		var z := SoldierModel.new(Color("5c5a55"), Color.BLACK, Color("3b3833"))
		z.set_gear(0, 0, 0)
		z.mats.skin.albedo_color = Color("9aa08f")
		add_child(z)
		z.position = Vector3(-4.0 + i * 1.9 + rng.randf_range(-0.3, 0.3), -0.4 + rng.randf_range(-0.2, 0.3), -1.9)
		z.rotation.y = PI + rng.randf_range(-0.4, 0.4)
		z.set_pose("stand", 0.0, false, 0.016, 0.0)
		z.rig.rotation.x = -0.35
		for a in z.arms:
			a.shoulder.rotation = Vector3(1.5 + rng.randf_range(-0.3, 0.3), 0, 0)
