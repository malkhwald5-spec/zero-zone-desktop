extends Node3D
## Lobby in the style of mobile battle royales: a city rooftop at sunset with
## the player's character and a classic car, and the full lobby UI (profile,
## currencies, season pass, events, mode card, big start button and the
## bottom menu bar). Solo only: no squads.

var soldier: HumanModel
var holder: Node3D
var cam: Camera3D
var ui: CanvasLayer
var root: Control
var panel: Control
var toast_box: PanelContainer
var labels := {}
var t := 0.0
var drag_rot := 0.0
var _dragging := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_scene()
	_build_ui()
	if not Game.last_reward.is_empty():
		_show_reward(Game.last_reward)
		Game.last_reward = {}

# =====================================================================
# 3D scene: rooftop at sunset
# =====================================================================
func _mat(c: Color, rough := 0.9, emit := 0.0, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m

func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	(parent if parent else self).add_child(mi)
	return mi

func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b

func _cyl(r1: float, r2: float, h: float, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r2
	c.height = h
	c.radial_segments = seg
	return c

## Concrete roof tiles: noisy slabs with dark joints.
func _tiles() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.frequency = 0.08
	var img := Image.create(128, 128, true, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := 0.78 + n.get_noise_2d(x, y) * 0.12
			if x % 64 < 2 or y % 64 < 2: v = 0.5
			img.set_pixel(x, y, Color(v, v * 0.95, v * 0.9))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _noise(freq: float, seed_v: int, size := 256) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	nt.noise = n
	nt.seamless = true
	nt.width = size
	nt.height = size
	return nt

func _build_scene() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var env := Environment.new()
	# Real photographed sunset (ambientCG EveningSkyHDRI032A, CC0), sun lined up
	# with the scene's sun light.
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky_photo.gdshader")
	sky_mat.set_shader_parameter("pano", load("res://assets/textures/sky_sunset.jpg"))
	sky_mat.set_shader_parameter("photo_sun", Vector2(0.499, 0.465))
	sky_mat.set_shader_parameter("energy", 1.2)
	sky_mat.set_shader_parameter("sun_boost", 2.0)
	sky_mat.set_shader_parameter("haze", Color("e9a878"))
	sky_mat.set_shader_parameter("haze_amount", 0.15)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color("e9a878")
	env.fog_sun_scatter = 0.2
	env.fog_density = 0.00025
	env.fog_aerial_perspective = 0.35
	# Thin warm haze only (the quality presets switch volumetric fog on, and
	# its default thickness turned the whole lobby into a dust storm).
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color("f0c8a0")
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_anisotropy = 0.6
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Low warm sun behind the skyline, long shadows towards the camera.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffc48a")
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	sun.look_at_from_position(Vector3(-30, 9, -60), Vector3.ZERO)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("8fa2d8")
	fill.light_energy = 0.35
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)
	fill.look_at_from_position(Vector3(10, 6, 20), Vector3.ZERO)
	Game.apply_quality(env, sun)

	# Rooftop: concrete floor with stains, low brick parapets, stair house.
	var floor_mat := _mat(Color("c9b6a6"), 0.95)
	floor_mat.albedo_texture = load("res://assets/textures/concrete_col.jpg")
	floor_mat.normal_enabled = true
	floor_mat.normal_texture = load("res://assets/textures/concrete_nrm.jpg")
	floor_mat.uv1_scale = Vector3(8, 6, 1)
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 20)
	_mesh(pm, floor_mat, Vector3(0, 0, -2))
	var brick := _mat(Color("9a5a44"), 0.9)
	brick.albedo_texture = _noise(0.08, 11)
	brick.uv1_scale = Vector3(3, 1, 1)
	_mesh(_box(Vector3(30, 0.9, 0.35)), brick, Vector3(0, 0.45, -11.5))
	_mesh(_box(Vector3(0.35, 0.9, 20)), brick, Vector3(-14.5, 0.45, -2))
	_mesh(_box(Vector3(0.35, 0.9, 20)), brick, Vector3(14.5, 0.45, -2))
	var house := Node3D.new()
	house.position = Vector3(-8.5, 0, -6)
	add_child(house)
	_mesh(_box(Vector3(4, 3.2, 3.5)), brick, Vector3(0, 1.6, 0), Vector3.ZERO, house)
	_mesh(_box(Vector3(4.4, 0.15, 3.9)), _mat(Color("5c4a42")), Vector3(0, 3.25, 0), Vector3.ZERO, house)
	_mesh(_box(Vector3(1.1, 2.1, 0.08)), _mat(Color("3d3a3a"), 0.5, 0.0, 0.5), Vector3(1.0, 1.05, 1.76), Vector3.ZERO, house)
	# Water tower on legs.
	var wt := Node3D.new()
	wt.position = Vector3(7.5, 0, -8.5)
	add_child(wt)
	var wood := _mat(Color("7b5a40"), 0.9)
	_mesh(_cyl(1.3, 1.3, 2.4, 20), wood, Vector3(0, 4.4, 0), Vector3.ZERO, wt)
	_mesh(_cyl(0.0, 1.45, 1.0, 20), _mat(Color("4a3a30")), Vector3(0, 6.1, 0), Vector3.ZERO, wt)
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4
		_mesh(_cyl(0.06, 0.06, 3.2, 6), _mat(Color("2c2c2e"), 0.6, 0.0, 0.6), Vector3(cos(a), 1.6, sin(a)), Vector3.ZERO, wt)
	# AC units and antennas with cables.
	var metal := _mat(Color("8d9298"), 0.5, 0.0, 0.6)
	for p in [Vector3(4.5, 0, -10.2), Vector3(-4.2, 0, -10.4), Vector3(10.5, 0, -3.5)]:
		_mesh(_box(Vector3(1.2, 0.9, 0.8)), metal, p + Vector3(0, 0.45, 0))
	var poles := [Vector3(-12, 0, -9), Vector3(-3, 0, -11), Vector3(12, 0, -10)]
	for p in poles:
		_mesh(_cyl(0.05, 0.07, 6.0, 6), _mat(Color("3a3533")), p + Vector3(0, 3.0, 0))
	var cable := _mat(Color("1d1b1b"))
	for i in poles.size() - 1:
		var a: Vector3 = poles[i] + Vector3(0, 5.8, 0)
		var b: Vector3 = poles[i + 1] + Vector3(0, 5.8, 0)
		for s in 10:
			var u0 := s / 10.0
			var u1 := (s + 1) / 10.0
			var p0 := a.lerp(b, u0) - Vector3(0, sin(u0 * PI) * 0.8, 0)
			var p1 := a.lerp(b, u1) - Vector3(0, sin(u1 * PI) * 0.8, 0)
			var seg := _mesh(_cyl(0.015, 0.015, p0.distance_to(p1), 4), cable, (p0 + p1) * 0.5)
			seg.look_at_from_position((p0 + p1) * 0.5, p1, Vector3.UP if absf((p1 - p0).normalized().y) < 0.99 else Vector3.RIGHT)
			seg.rotate_object_local(Vector3.RIGHT, PI / 2)

	_skyline(rng)
	_car(Vector3(-3.4, 0, -2.2), PI - 0.75)

	holder = Node3D.new()
	add_child(holder)
	_spawn_soldier()

	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.look_at_from_position(Vector3(0.2, 1.25, 4.6), Vector3(0.0, 1.05, 0.0))
	cam.current = true

## Distant city: towers with lit windows, billboards and a spire, mountains behind.
func _skyline(rng: RandomNumberGenerator) -> void:
	var img := Image.create(32, 64, false, Image.FORMAT_RGB8)
	img.fill(Color("4b4650"))
	for y in range(2, 64, 4):
		for x in range(2, 32, 4):
			var lit := rng.randf() < 0.35
			var c := Color("ffd59a") if lit else Color("2c2f3a").lerp(Color("8fa6c8"), rng.randf() * 0.5)
			img.fill_rect(Rect2i(x, y, 2, 2), c)
	var wtex := ImageTexture.create_from_image(img)
	var tones := [Color("9c8c80"), Color("7d7680"), Color("a8957c"), Color("6a6672"), Color("8c7a66")]
	for i in 70:
		var ang := rng.randf_range(-1.25, 1.25)
		var dist := rng.randf_range(45.0, 170.0)
		var x := sin(ang) * dist
		var z := -cos(ang) * dist - 12.0
		var w := rng.randf_range(6, 16)
		var d := rng.randf_range(6, 16)
		var h := rng.randf_range(12, 55) * (1.4 if dist > 80 else 1.0)
		var base := -30.0
		var m := StandardMaterial3D.new()
		m.albedo_texture = wtex
		m.albedo_color = tones[i % tones.size()]
		m.uv1_scale = Vector3(w / 8.0, h / 16.0, 1)
		m.emission_enabled = true
		m.emission_texture = wtex
		m.emission = Color(1, 0.8, 0.55)
		m.emission_energy_multiplier = 0.25
		m.roughness = 0.8
		var b := _mesh(_box(Vector3(w, h, d)), m, Vector3(x, base + h * 0.5, z))
		b.rotation.y = rng.randf_range(-0.2, 0.2)
		if rng.randf() < 0.22:
			var bc: Color = [Color("e2483d"), Color("2fb3a3"), Color("f08a2c"), Color("e8e4dc"), Color("4b7de0")][rng.randi() % 5]
			var bb := _mesh(_box(Vector3(w * 0.6, h * 0.18, 0.2)), _mat(bc, 0.5, 1.2), Vector3(x, base + h * rng.randf_range(0.55, 0.85), z + d * 0.5 + 0.15))
			bb.rotation.y = b.rotation.y
	# A tall spire tower, landmark of the city.
	var sm := _mat(Color("b8aa9a"), 0.7)
	var y := -30.0
	for s in [[14.0, 60.0], [10.0, 22.0], [7.0, 14.0], [4.0, 10.0]]:
		_mesh(_box(Vector3(s[0], s[1], s[0])), sm, Vector3(-38, y + s[1] * 0.5, -120))
		y += s[1]
	_mesh(_cyl(0.3, 1.2, 16.0, 8), sm, Vector3(-38, y + 8.0, -120))
	# Mountains in the haze.
	var mm := _mat(Color("8a7f8e"), 1.0)
	for i in 9:
		var mx := -260.0 + i * 65.0 + rng.randf_range(-20, 20)
		var mh := rng.randf_range(40, 95)
		_mesh(_cyl(0.0, rng.randf_range(70, 120), mh, 7), mm, Vector3(mx, -30 + mh * 0.5, -330 - rng.randf_range(0, 60)), Vector3(0, rng.randf(), 0))

## A classic convertible parked on the roof.
func _car(pos: Vector3, yaw: float) -> void:
	var car := Node3D.new()
	car.position = pos
	car.rotation.y = yaw
	add_child(car)
	var paint := _mat(Color("4a2f4f"), 0.25, 0.0, 0.55)
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.8
	var chrome := _mat(Color("d8dde2"), 0.15, 0.0, 1.0)
	var black := _mat(Color("121214"), 0.8)
	var seat := _mat(Color("6b4a3a"), 0.7)
	var glass := _mat(Color(0.7, 0.8, 0.9, 0.35), 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Body: lower hull, hood and trunk, with rounded fenders.
	_mesh(_box(Vector3(1.7, 0.42, 4.3)), paint, Vector3(0, 0.55, 0), Vector3.ZERO, car)
	_mesh(_box(Vector3(1.66, 0.18, 1.3)), paint, Vector3(0, 0.84, -1.45), Vector3(0.05, 0, 0), car)
	_mesh(_box(Vector3(1.66, 0.2, 1.1)), paint, Vector3(0, 0.85, 1.55), Vector3(-0.04, 0, 0), car)
	for side in [-1, 1]:
		var f := CapsuleMesh.new()
		f.radius = 0.24
		f.height = 4.3
		var fm := _mesh(f, paint, Vector3(side * 0.74, 0.62, 0), Vector3(PI / 2, 0, 0), car)
		fm.scale = Vector3(1, 1, 1.15)
		_mesh(_box(Vector3(0.12, 0.5, 1.6)), paint, Vector3(side * 0.8, 0.95, 0.2), Vector3.ZERO, car)  # doors
	# Interior, seats, steering wheel.
	_mesh(_box(Vector3(1.4, 0.1, 1.9)), black, Vector3(0, 0.8, 0.25), Vector3.ZERO, car)
	for x in [-0.36, 0.36]:
		_mesh(_box(Vector3(0.55, 0.2, 0.55)), seat, Vector3(x, 0.92, 0.1), Vector3.ZERO, car)
		_mesh(_box(Vector3(0.55, 0.55, 0.14)), seat, Vector3(x, 1.12, 0.4), Vector3(-0.15, 0, 0), car)
	_mesh(_box(Vector3(1.4, 0.45, 0.2)), seat, Vector3(0, 1.0, 1.0), Vector3(-0.1, 0, 0), car)
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.15
	wheel.outer_radius = 0.18
	_mesh(wheel, black, Vector3(-0.36, 1.15, -0.45), Vector3(1.1, 0, 0), car)
	# Windshield with chrome frame.
	_mesh(_box(Vector3(1.5, 0.45, 0.03)), glass, Vector3(0, 1.18, -0.75), Vector3(-0.45, 0, 0), car)
	_mesh(_box(Vector3(1.55, 0.04, 0.05)), chrome, Vector3(0, 1.38, -0.65), Vector3(-0.45, 0, 0), car)
	# Wheels with chrome hubs.
	for wx in [-0.78, 0.78]:
		for wz in [-1.4, 1.35]:
			_mesh(_cyl(0.34, 0.34, 0.24, 20), black, Vector3(wx, 0.34, wz), Vector3(0, 0, PI / 2), car)
			_mesh(_cyl(0.2, 0.2, 0.26, 16), chrome, Vector3(wx, 0.34, wz), Vector3(0, 0, PI / 2), car)
	# Bumpers, grille and round headlights.
	for z in [-2.18, 2.18]:
		var bump := CapsuleMesh.new()
		bump.radius = 0.06
		bump.height = 1.8
		_mesh(bump, chrome, Vector3(0, 0.45, z), Vector3(0, 0, PI / 2), car)
	_mesh(_box(Vector3(0.7, 0.22, 0.05)), chrome, Vector3(0, 0.66, -2.16), Vector3.ZERO, car)
	for x in [-0.55, 0.55]:
		_mesh(_cyl(0.11, 0.11, 0.06, 16), _mat(Color("fff6dc"), 0.1, 1.5), Vector3(x, 0.72, -2.16), Vector3(PI / 2, 0, 0), car)
		_mesh(_box(Vector3(0.22, 0.08, 0.04)), _mat(Color("c62828"), 0.3, 0.8), Vector3(x, 0.7, 2.17), Vector3.ZERO, car)

func _spawn_soldier() -> void:
	if soldier: soldier.queue_free()
	soldier = HumanModel.new(Game.outfit_color(), Color("f2a900"), Game.pants_color(), Game.outfit_character())
	soldier.set_style(Game.outfit_style())
	soldier.set_gear(0, 0, 0)
	soldier.rotation.y = PI    # face the camera
	holder.add_child(soldier)

func _process(delta: float) -> void:
	t += delta
	holder.rotation.y = drag_rot
	soldier.set_pose("stand", 0.0, false, delta, t)
	_tick_ui(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		drag_rot += event.relative.x * 0.01
	elif event is InputEventScreenDrag:
		drag_rot += event.relative.x * 0.01

# =====================================================================
# UI
# =====================================================================
func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	_top_left()
	_top_center()
	_top_right()
	_right_column()
	_bottom_left()
	_bottom_bar()
	_refresh()

func _anchor(c: Control, preset: int, offset: Vector2) -> void:
	root.add_child(c)
	c.set_anchors_and_offsets_preset(preset)
	if preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT]:
		c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM]:
		c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM]:
		c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.position += offset

func _chip(text: String, cb: Callable, col := Color.WHITE, bg := Color(0, 0, 0, 0.45)) -> Button:
	var b := UiKit.button(text, cb, Vector2(0, 34), UiKit.style(bg, 17, Color(1, 1, 1, 0.14), 1, 12), 15, col)
	return b

## Button with a drawn icon: either beside the text (pill) or above it (tab).
func _icon_button(icon: String, text: String, cb: Callable, size: Vector2, icon_above := false, bg := Color(0, 0, 0, 0.45), icon_col := Color.WHITE, radius := 17) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.text = ""
	var st := UiKit.style(bg, radius, Color(1, 1, 1, 0.14) if bg.a > 0.0 else Color(0, 0, 0, 0), 1 if bg.a > 0.0 else 0, 4)
	b.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate()
	hv.bg_color = Color(bg.r, bg.g, bg.b, minf(bg.a + 0.2, 1.0)) if bg.a > 0.0 else Color(1, 1, 1, 0.08)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.pressed.connect(cb)
	var lbl := UiKit.label(text, 14 if icon_above else 16, Color.WHITE, UiKit.bold(), 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(lbl)
	b.set_meta("label", lbl)
	b.draw.connect(func():
		var sz := b.size
		if icon_above:
			Icons.draw(b, icon, Vector2(sz.x * 0.5, sz.y * 0.36), sz.y * 0.2, icon_col)
		else:
			Icons.draw(b, icon, Vector2(sz.y * 0.5 + 2, sz.y * 0.5), sz.y * 0.3, icon_col))
	b.resized.connect(func():
		var sz := b.size
		lbl.size = Vector2(sz.x, 22)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if icon_above:
			lbl.position = Vector2(0, sz.y * 0.62)
		else:
			lbl.position = Vector2(sz.y * 0.5, sz.y * 0.5 - 12)
			lbl.size.x = sz.x - sz.y * 0.5 - 6)
	return b

func _top_left() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_anchor(box, Control.PRESET_TOP_LEFT, Vector2(18, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var av := Button.new()
	av.custom_minimum_size = Vector2(72, 72)
	av.add_theme_stylebox_override("normal", UiKit.style(Color("2f3a4c"), 4, Color("e8edf4"), 2, 0))
	av.add_theme_stylebox_override("hover", UiKit.style(Color("3a475c"), 4, Color.WHITE, 2, 0))
	av.add_theme_stylebox_override("pressed", UiKit.style(Color("3a475c"), 4, Color.WHITE, 2, 0))
	av.add_theme_font_override("font", UiKit.bold())
	av.add_theme_font_size_override("font_size", 32)
	av.pressed.connect(func(): _open("cards"))
	labels.avatar = av
	row.add_child(av)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UiKit.style(Color("1d6fd8"), 4, Color.WHITE, 1, 3))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lvl := UiKit.label("", 12, Color.WHITE, UiKit.bold(), 0)
	badge.add_child(lvl)
	badge.position = Vector2(-6, -6)
	av.add_child(badge)
	labels.level_badge = lvl
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 4)
	labels.name = UiKit.label("", 22, Color.WHITE, UiKit.bold())
	who.add_child(labels.name)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.add_child(_icon_button("clan", "العشيرة", func(): _open("clan"), Vector2(118, 34)))
	chips.add_child(_icon_button("home", "المنزل", func(): _toast("المنزل قريباً… نجهّزه للموسم الجاي"), Vector2(104, 34)))
	who.add_child(chips)
	row.add_child(who)
	# Side column: mail bell and friends, like the mobile lobby.
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	box.add_child(side)
	var bell := _icon_button("bell", "", func(): _open("mail"), Vector2(72, 40), false, Color(0, 0, 0, 0.5), Color("ffd34d"), 6)
	labels.bell = bell.get_meta("label")
	bell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	side.add_child(bell)
	var fr := _icon_button("friends", "0/1", func(): _open("mode"), Vector2(72, 40), false, Color(0, 0, 0, 0.5), Color.WHITE, 6)
	fr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	side.add_child(fr)

func _top_center() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	_anchor(tabs, Control.PRESET_CENTER_TOP, Vector2(0, 14))
	for tb in [["الرئيسية", ""], ["المتجر", "shop"], ["الفعاليات", "events"]]:
		var key: String = tb[1]
		var on := key == ""
		var st := UiKit.style(Color(1, 1, 1, 0.92) if on else Color(0, 0, 0, 0.45), 3, Color(1, 1, 1, 0.35), 1, 6)
		var b := UiKit.button(tb[0], func(): if key != "": _open(key), Vector2(116, 36), st, 15, Color("1b1b1b") if on else Color.WHITE)
		b.add_theme_font_override("font", UiKit.bold())
		tabs.add_child(b)

func _top_right() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_anchor(row, Control.PRESET_TOP_RIGHT, Vector2(-18, 14))
	row.add_child(_icon_button("crown", "PRIME", func(): _open("season"), Vector2(104, 36), false, Color(0, 0, 0, 0.5), Color("ffd34d")))
	var g := _icon_button("coin", "", func(): _open("shop"), Vector2(110, 36), false, Color(0, 0, 0, 0.5))
	labels.gold = g.get_meta("label")
	row.add_child(g)
	var z := _icon_button("gem", "", func(): _open("season"), Vector2(110, 36), false, Color(0, 0, 0, 0.5))
	labels.zc = z.get_meta("label")
	row.add_child(z)
	row.add_child(_icon_button("plus", "", func(): _open("shop"), Vector2(36, 36), false, Color("ffd34d"), UiKit.INK, 18))
	row.add_child(_icon_button("gear", "", func(): _open("settings"), Vector2(36, 36), false, Color(0, 0, 0, 0.5), Color.WHITE, 18))

func _card(size: Vector2, top: Color, bottom: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var tr := TextureRect.new()
	tr.texture = UiKit.gradient(top, bottom)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tr)
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fs := StyleBoxFlat.new()
	fs.draw_center = false
	fs.border_color = Color(1, 1, 1, 0.35)
	fs.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", fs)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(frame)
	b.pressed.connect(cb)
	return b

func _place(parent: Control, c: Control, pos: Vector2) -> Control:
	parent.add_child(c)
	c.position = pos
	return c

func _right_column() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_anchor(col, Control.PRESET_TOP_RIGHT, Vector2(-18, 64))
	# Season pass card.
	var pass_card := _card(Vector2(236, 132), Color("2a1838"), Color("8a1f35"), func(): _open("season"))
	pass_card.draw.connect(func(): Icons.draw(pass_card, "trophy", Vector2(200, 40), 22, Color(1, 0.84, 0.3, 0.9)))
	_place(pass_card, UiKit.label("ZERO PASS", 26, Color.WHITE, UiKit.italic()), Vector2(12, 4))
	_place(pass_card, UiKit.label(Game.SEASON_NAME, 13, Color("ffb0c0")), Vector2(12, 42))
	var lv := PanelContainer.new()
	lv.add_theme_stylebox_override("panel", UiKit.style(UiKit.YELLOW, 3, Color(0, 0, 0, 0), 0, 5))
	var lvl := UiKit.label("", 20, UiKit.INK, UiKit.bold(), 0)
	lv.add_child(lvl)
	labels.pass_level = lvl
	_place(pass_card, lv, Vector2(160, 86))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(136, 8)
	bar.add_theme_stylebox_override("background", UiKit.style(Color(0, 0, 0, 0.5), 3, Color(0, 0, 0, 0), 0, 0))
	bar.add_theme_stylebox_override("fill", UiKit.style(UiKit.YELLOW, 3, Color(0, 0, 0, 0), 0, 0))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.pass_bar = bar
	_place(pass_card, bar, Vector2(12, 100))
	col.add_child(pass_card)
	# Yellow crate / shop strip.
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	strip.add_child(_icon_button("crate", "الصناديق", func(): _open("crate"), Vector2(116, 58), true, UiKit.YELLOW, UiKit.INK, 4))
	strip.add_child(_icon_button("cart", "المتجر", func(): _open("shop"), Vector2(116, 58), true, UiKit.YELLOW, UiKit.INK, 4))
	for b in strip.get_children(): (b.get_meta("label") as Label).add_theme_color_override("font_color", UiKit.INK)
	for b in strip.get_children(): (b.get_meta("label") as Label).add_theme_constant_override("outline_size", 0)
	col.add_child(strip)
	# Two offer cards.
	var offers := HBoxContainer.new()
	offers.add_theme_constant_override("separation", 4)
	var sale := _card(Vector2(116, 62), Color("f5f5f5"), Color("cfd6de"), func(): _open("shop"))
	_place(sale, UiKit.label("عروض", 17, Color("c62828"), UiKit.bold(), 0), Vector2(10, 4))
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UiKit.style(Color("e53935"), 3, Color(0, 0, 0, 0), 0, 3))
	badge.add_child(UiKit.label("NEW", 11, Color.WHITE, UiKit.bold(), 0))
	_place(sale, badge, Vector2(66, 6))
	_place(sale, UiKit.label("SALE", 14, Color("1b1b1b"), UiKit.bold(), 0), Vector2(10, 32))
	offers.add_child(sale)
	var zp := _card(Vector2(116, 62), Color("f5f5f5"), Color("cfd6de"), func(): _open("missions"))
	zp.draw.connect(func(): Icons.draw(zp, "tasks", Vector2(94, 20), 11, Color("2d6fb8")))
	_place(zp, UiKit.label("المهام", 17, Color("1b1b1b"), UiKit.bold(), 0), Vector2(10, 4))
	var mlabel := UiKit.label("", 12, Color("2d6fb8"), null, 0)
	labels.missions_hint = mlabel
	_place(zp, mlabel, Vector2(10, 34))
	offers.add_child(zp)
	col.add_child(offers)
	var ev := _icon_button("calendar", "الفعاليات", func(): _open("events"), Vector2(236, 54), false, Color(0.96, 0.96, 0.96, 0.95), Color("c62828"), 4)
	(ev.get_meta("label") as Label).add_theme_color_override("font_color", Color("1b1b1b"))
	(ev.get_meta("label") as Label).add_theme_constant_override("outline_size", 0)
	col.add_child(ev)

func _bottom_left() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_anchor(box, Control.PRESET_BOTTOM_LEFT, Vector2(18, -22))
	var auto := CheckBox.new()
	auto.text = "مطابقة تلقائية"
	auto.button_pressed = true
	auto.add_theme_font_size_override("font_size", 14)
	auto.add_theme_stylebox_override("normal", UiKit.style(Color(0, 0, 0, 0.5), 3, Color(1, 1, 1, 0.12), 1, 6))
	box.add_child(auto)
	var mode := _card(Vector2(264, 72), Color(0, 0, 0, 0.62), Color(0, 0, 0, 0.78), func(): _open("mode"))
	var thumb := TextureRect.new()
	thumb.texture = UiKit.gradient(Color("3f7a5a"), Color("2c6d8f"))
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.custom_minimum_size = Vector2(84, 62)
	thumb.size = Vector2(84, 62)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(mode, thumb, Vector2(5, 5))
	thumb.draw.connect(func(): Icons.draw(thumb, "globe", Vector2(42, 31), 20, Color(1, 1, 1, 0.9)))
	_place(mode, UiKit.label("منظور الشخص الثالث", 16, Color.WHITE, UiKit.bold(), 0), Vector2(96, 6))
	var ml := UiKit.label("", 12, Color(1, 1, 1, 0.8), null, 0)
	labels.mode = ml
	_place(mode, ml, Vector2(96, 38))
	box.add_child(mode)
	var start := UiKit.yellow_button("انطلاق", _start, Vector2(264, 92), 46)
	start.pivot_offset = Vector2(132, 46)
	labels.start = start
	box.add_child(start)
	var status := UiKit.label("", 12, Color(1, 1, 1, 0.75), null, 3)
	labels.status = status
	box.add_child(status)

func _bottom_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	_anchor(bar, Control.PRESET_BOTTOM_RIGHT, Vector2(-18, -12))
	var items := [["العشيرة", "clan", "clan"], ["البريد", "mail", "mail"], ["المهام", "missions", "tasks"], ["الموسم", "season", "trophy"],
		["ورشة العمل", "workshop", "wrench"], ["البطاقات", "cards", "card"], ["المخزون", "inventory", "shirt"]]
	for it in items:
		var key: String = it[1]
		var b := _icon_button(it[2], it[0], func(): _open(key), Vector2(92, 66), true, Color(0, 0, 0, 0.0), Color.WHITE, 6)
		bar.add_child(b)
		labels["bar_" + key] = b.get_meta("label")
	# Small round action icons above the bar.
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 10)
	_anchor(icons, Control.PRESET_BOTTOM_RIGHT, Vector2(-22, -92))
	for ic in [["question", func(): _open("help")], ["hand", func(): soldier.wave(2.2)], ["expand", func(): _toggle_fullscreen()]]:
		icons.add_child(_icon_button(ic[0], "", ic[1], Vector2(40, 40), false, Color(0, 0, 0, 0.45), Color.WHITE, 20))
	# Darkened strip behind the bar.
	var strip := TextureRect.new()
	strip.texture = UiKit.gradient(Color(0, 0, 0, 0), Color(0, 0, 0, 0.65))
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)
	root.move_child(strip, 0)
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -110

func _toggle_fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

func _tick_ui(_delta: float) -> void:
	# The start button breathes gently.
	if labels.has("start"):
		var k := 1.0 + sin(t * 3.0) * 0.025
		labels.start.scale = Vector2(k, k)
	if labels.has("status"):
		var now := Time.get_time_dict_from_system()
		labels.status.text = "📶 عالية الدقة  الشرق الأوسط   %02d:%02d   %s" % [now.hour, now.minute, Game.VERSION]

func _refresh() -> void:
	labels.name.text = Game.player_name()
	labels.avatar.text = Game.player_name().left(1)
	labels.level_badge.text = str(Game.level())
	labels.gold.text = "%d" % int(Game.wallet.gold)
	labels.zc.text = "ZC %d" % int(Game.wallet.zc)
	labels.pass_level.text = " %d ›" % Game.pass_level()
	labels.pass_bar.value = float(int(Game.wallet.xp) % Game.PASS_XP) / Game.PASS_XP * 100.0
	var d := {"easy": "سهل", "normal": "عادي", "hard": "صعب"}[Game.settings.difficulty] as String
	labels.mode.text = "كلاسيكي - %s | %s" % [Game.MODE_NAMES.get(Game.settings.get("mode", "solo"), "فردي"), d]
	var ready := _missions().filter(func(m): return m.done and not _claimed(m.id)).size()
	labels.missions_hint.text = ("%d جاهزة!" % ready) if ready > 0 else "متاح الآن"
	var unread := not bool(Game.wallet.mail_read)
	labels.bell.text = "1" if unread else ""
	labels.bar_mail.text = "البريد •" if unread else "البريد"

func _start() -> void:
	get_tree().change_scene_to_file("res://scenes/world.tscn")

# ---------- Toasts / rewards ----------
func _toast(text: String) -> void:
	if toast_box: toast_box.queue_free()
	toast_box = PanelContainer.new()
	toast_box.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.05, 0.08, 0.9), 4, Color(1, 1, 1, 0.15), 1, 12))
	toast_box.add_child(UiKit.label(text, 16, Color.WHITE, UiKit.bold(), 0))
	ui.add_child(toast_box)
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_box.position.y = 90
	var box := toast_box
	box.create_tween().tween_callback(box.queue_free).set_delay(2.4)

func _show_reward(r: Dictionary) -> void:
	var title := "🏆 فوز! أنت الناجي الأخير" if r.won else "انتهت المباراة — الترتيب #%d" % r.rank
	_toast("%s   •   القتلى %d   •   +%d ذهب   •   +%d خبرة موسم" % [title, r.kills, r.gold, r.xp])

func _claimed(id: String) -> bool:
	return Game.wallet.claimed.has(id)

func _claim(id: String, gold: int, zc := 0) -> void:
	if _claimed(id): return
	Game.wallet.claimed.append(id)
	Game.wallet.gold = int(Game.wallet.gold) + gold
	Game.wallet.zc = int(Game.wallet.zc) + zc
	Game.save_data()
	_toast("تم الاستلام: %s" % (("+%d ذهب" % gold) + (("  +%d ZC" % zc) if zc > 0 else "")))
	_refresh()

func _missions() -> Array:
	return [
		{"id": "m_play1", "text": "العب مباراة واحدة", "cur": Game.stats.games, "goal": 1, "gold": 100},
		{"id": "m_play5", "text": "العب 5 مباريات", "cur": Game.stats.games, "goal": 5, "gold": 250},
		{"id": "m_kill5", "text": "اقضِ على 5 خصوم", "cur": Game.stats.kills, "goal": 5, "gold": 200},
		{"id": "m_kill25", "text": "اقضِ على 25 خصماً", "cur": Game.stats.kills, "goal": 25, "gold": 500},
		{"id": "m_win1", "text": "افز بمباراة", "cur": Game.stats.wins, "goal": 1, "gold": 400},
	].map(func(m): m.done = int(m.cur) >= int(m.goal); return m)

# =====================================================================
# Panels (full-screen pages with a header bar)
# =====================================================================
const TITLES := {
	"inventory": "المخزون", "cards": "البطاقات", "workshop": "ورشة العمل", "season": "الموسم — ZERO PASS",
	"missions": "المهام", "mail": "البريد", "clan": "العشيرة", "shop": "المتجر", "crate": "صندوق القمر الأحمر",
	"events": "الفعاليات", "settings": "الإعدادات", "keys": "الأزرار", "mode": "اختيار الوضع", "help": "طريقة اللعب",
}

func _open(which: String) -> void:
	_close_panel(false)
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(page)
	panel = page
	root.visible = false
	# The inventory keeps the character visible on the left.
	var side := which == "inventory"
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07, 0.86)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	if side:
		bg.anchor_left = 0.5
	page.add_child(bg)
	# Header.
	var head := ColorRect.new()
	head.color = Color(0, 0, 0, 0.7)
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_bottom = 56
	page.add_child(head)
	var back := UiKit.button("‹  رجوع", func(): _close_panel(), Vector2(110, 40), UiKit.style(Color(1, 1, 1, 0.08), 3, Color(1, 1, 1, 0.2), 1, 6), 16)
	back.position = Vector2(12, 8)
	page.add_child(back)
	var title := UiKit.label(TITLES.get(which, ""), 22, Color("ffd34d"), UiKit.bold())
	title.position = Vector2(140, 10)
	page.add_child(title)
	var money := UiKit.label("🪙 %d     💎 %d" % [int(Game.wallet.gold), int(Game.wallet.zc)], 16, Color.WHITE, UiKit.bold())
	page.add_child(money)
	money.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	money.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	money.position += Vector2(-20, 12)
	# Body.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 70
	scroll.offset_bottom = -16
	scroll.offset_left = 40
	scroll.offset_right = -40
	if side:
		scroll.anchor_left = 0.5
		scroll.offset_left = 20
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	match which:
		"inventory": _page_inventory(body)
		"cards": _page_cards(body)
		"workshop": _page_workshop(body)
		"season": _page_season(body)
		"missions": _page_missions(body)
		"mail": _page_mail(body)
		"clan": _page_clan(body)
		"shop": _page_shop(body)
		"crate": _page_crate(body)
		"events": _page_events(body)
		"settings": _page_settings(body)
		"keys": _page_keys(body)
		"mode": _page_mode(body)
		"help": _page_help(body)
	if side:
		drag_rot = 0.5

func _close_panel(refresh := true) -> void:
	if panel:
		panel.queue_free()
		panel = null
	root.visible = true
	drag_rot = 0.0
	Game.save_data()
	if refresh: _refresh()

func _row(text: String, ctrl: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var l := UiKit.label(text, 17, Color(0.78, 0.82, 0.88), null, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	hb.add_child(ctrl)
	return hb

func _box_panel(color := Color(1, 1, 1, 0.06)) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.style(color, 4, Color(1, 1, 1, 0.1), 1, 12))
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return pc

func _small_btn(text: String, cb: Callable, enabled := true, primary := true) -> Button:
	var st := UiKit.style(UiKit.YELLOW if (enabled and primary) else Color(1, 1, 1, 0.1), 3, Color(0, 0, 0, 0), 0, 8)
	var b := UiKit.button(text, cb, Vector2(120, 38), st, 15, UiKit.INK if (enabled and primary) else Color(1, 1, 1, 0.6))
	b.disabled = not enabled
	return b

func _page_inventory(body: VBoxContainer) -> void:
	body.add_child(UiKit.label("الملابس — اضغط للتجهيز أو الشراء", 15, Color(1, 1, 1, 0.7), null, 0))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	for i in Game.WARDROBE.size():
		var w: Array = Game.WARDROBE[i]
		var idx := i
		var owned := Game.owns(i)
		var equipped := int(Game.profile.outfit) == i
		var card := _box_panel(Color(1, 0.82, 0.12, 0.18) if equipped else Color(1, 1, 1, 0.06))
		card.custom_minimum_size = Vector2(270, 0)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		card.add_child(hb)
		var sw := Control.new()
		sw.custom_minimum_size = Vector2(46, 76)
		var style: String = w[4] if w.size() > 4 else ""
		sw.draw.connect(func():
			if style == "panda":
				sw.draw_circle(Vector2(16, 3), 4, Color.BLACK)
				sw.draw_circle(Vector2(30, 3), 4, Color.BLACK)
			sw.draw_circle(Vector2(23, 8), 7, Color.WHITE if style == "panda" else (Color("e8b84a") if style == "gold" else Color("d9a77f")))
			sw.draw_rect(Rect2(8, 16, 30, 28), w[1])
			sw.draw_rect(Rect2(10, 44, 12, 30), w[2])
			sw.draw_rect(Rect2(24, 44, 12, 30), w[2]))
		hb.add_child(sw)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiKit.label(w[0], 16, Color.WHITE, UiKit.bold(), 0))
		var state := "مُجهّز" if equipped else ("مملوك" if owned else "🪙 %d" % int(w[3]))
		info.add_child(UiKit.label(state, 13, Color("ffd34d") if not owned else Color(1, 1, 1, 0.7), null, 0))
		hb.add_child(info)
		var b := _small_btn("تجهيز" if owned else "شراء", func(): _wear_or_buy(idx), not equipped)
		b.custom_minimum_size = Vector2(80, 36)
		hb.add_child(b)
		grid.add_child(card)

func _wear_or_buy(i: int) -> void:
	if not Game.owns(i):
		var price := int(Game.WARDROBE[i][3])
		if int(Game.wallet.gold) < price:
			_toast("ما معك ذهب كافي — العب مباريات وخلّص المهام")
			return
		Game.wallet.gold = int(Game.wallet.gold) - price
		Game.profile.owned.append(i)
		_toast("اشتريت: %s" % Game.WARDROBE[i][0])
	Game.profile.outfit = i
	Game.save_data()
	_spawn_soldier()
	_open("inventory")

func _page_cards(body: VBoxContainer) -> void:
	var le := LineEdit.new()
	le.text = String(Game.profile.name)
	le.placeholder_text = "اكتب اسمك"
	le.max_length = 16
	le.custom_minimum_size = Vector2(260, 40)
	le.text_changed.connect(func(s): Game.profile.name = s.strip_edges())
	body.add_child(_row("اسم اللاعب", le))
	body.add_child(_row("المستوى", UiKit.label(str(Game.level()), 20, Color.WHITE, UiKit.bold(), 0)))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	body.add_child(grid)
	var best: String = ("#%d" % Game.stats.best) if Game.stats.best > 0 else "-"
	var kd := float(Game.stats.kills) / maxf(1.0, float(Game.stats.games - Game.stats.wins))
	for s in [["الانتصارات", str(Game.stats.wins)], ["المباريات", str(Game.stats.games)], ["الإقصاءات", str(Game.stats.kills)], ["أفضل ترتيب", best], ["معدل K/D", "%.2f" % kd], ["مستوى الموسم", str(Game.pass_level())]]:
		var c := _box_panel()
		c.custom_minimum_size = Vector2(200, 90)
		var v := VBoxContainer.new()
		v.add_child(UiKit.label(s[0], 14, Color(1, 1, 1, 0.7), null, 0))
		v.add_child(UiKit.label(s[1], 30, Color("ffd34d"), UiKit.bold(), 0))
		c.add_child(v)
		grid.add_child(c)

func _bar(v: float, col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.value = clampf(v, 0.0, 1.0) * 100.0
	b.custom_minimum_size = Vector2(160, 8)
	b.add_theme_stylebox_override("background", UiKit.style(Color(1, 1, 1, 0.1), 2, Color(0, 0, 0, 0), 0, 0))
	b.add_theme_stylebox_override("fill", UiKit.style(col, 2, Color(0, 0, 0, 0), 0, 0))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b

func _page_workshop(body: VBoxContainer) -> void:
	var cls_names := {"pistol": "مسدس", "smg": "رشاش خفيف", "shotgun": "شوزن", "ar": "رشاش هجومي", "sr": "قناصة", "lmg": "رشاش ثقيل"}
	for id in Game.WEAPONS:
		var w: Dictionary = Game.WEAPONS[id]
		var c := _box_panel()
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		c.add_child(hb)
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(170, 0)
		v.add_child(UiKit.label(w.name, 22, Color.WHITE, UiKit.bold(), 0))
		v.add_child(UiKit.label("%s • %s%s" % [cls_names.get(w.cls, ""), Game.AMMO_NAMES[w.ammo], "  • إنزال جوي فقط" if w.get("crate", false) else ""], 13, Color("ff8a8a") if w.get("crate", false) else Color(1, 1, 1, 0.65), null, 0))
		hb.add_child(v)
		var dps := float(w.dmg) * float(w.get("pellets", 1)) / float(w.rate)
		var stats := GridContainer.new()
		stats.columns = 2
		stats.add_theme_constant_override("h_separation", 10)
		for s in [["الضرر", float(w.dmg) * float(w.get("pellets", 1)) / 110.0], ["سرعة الإطلاق", 0.09 / float(w.rate)], ["المدى", float(w.range) / 800.0], ["الثبات", 1.0 - float(w.recoil) / 5.5], ["القوة/ث", dps / 300.0]]:
			stats.add_child(UiKit.label(s[0], 13, Color(1, 1, 1, 0.75), null, 0))
			stats.add_child(_bar(s[1], UiKit.YELLOW))
		hb.add_child(stats)
		body.add_child(c)

func _page_season(body: VBoxContainer) -> void:
	var lvl := Game.pass_level()
	var head := _box_panel(Color(0.55, 0.12, 0.22, 0.35))
	var hv := VBoxContainer.new()
	hv.add_child(UiKit.label("%s — المستوى %d / %d" % [Game.SEASON_NAME, lvl, Game.PASS_MAX], 20, Color.WHITE, UiKit.bold(), 0))
	var b := _bar(float(int(Game.wallet.xp) % Game.PASS_XP) / Game.PASS_XP, UiKit.YELLOW)
	b.custom_minimum_size = Vector2(400, 10)
	hv.add_child(b)
	hv.add_child(UiKit.label("خبرة الموسم: %d — تجمعها من المباريات (القتل والفوز)" % int(Game.wallet.xp), 13, Color(1, 1, 1, 0.75), null, 0))
	head.add_child(hv)
	body.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for n in range(3, Game.PASS_MAX + 1, 3):
		var id := "pass_%d" % n
		var reached := lvl >= n
		var gold := 50 * n
		var zc := 10 if n % 9 == 0 else 0
		var c := _box_panel(Color(1, 0.82, 0.12, 0.15) if reached else Color(1, 1, 1, 0.05))
		var v := VBoxContainer.new()
		v.add_child(UiKit.label("المستوى %d" % n, 14, Color.WHITE, UiKit.bold(), 0))
		v.add_child(UiKit.label("🪙 %d%s" % [gold, ("  💎 %d" % zc) if zc > 0 else ""], 13, Color("ffd34d"), null, 0))
		var claimed := _claimed(id)
		var btn := _small_btn("مستلم ✓" if claimed else ("استلام" if reached else "🔒"), func(): _claim(id, gold, zc); _open("season"), reached and not claimed)
		btn.custom_minimum_size = Vector2(130, 32)
		v.add_child(btn)
		c.add_child(v)
		grid.add_child(c)

func _page_missions(body: VBoxContainer) -> void:
	for m in _missions():
		var c := _box_panel()
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		c.add_child(hb)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UiKit.label(m.text, 17, Color.WHITE, UiKit.bold(), 0))
		var pr := _bar(float(m.cur) / float(m.goal), Color("4caf50"))
		pr.custom_minimum_size = Vector2(300, 8)
		v.add_child(pr)
		v.add_child(UiKit.label("%d / %d     المكافأة: 🪙 %d" % [mini(int(m.cur), int(m.goal)), m.goal, m.gold], 13, Color(1, 1, 1, 0.7), null, 0))
		hb.add_child(v)
		var id: String = m.id
		var gold: int = m.gold
		var claimed := _claimed(id)
		hb.add_child(_small_btn("مستلم ✓" if claimed else ("استلام" if m.done else "قيد التقدم"), func(): _claim(id, gold); _open("missions"), m.done and not claimed))
		body.add_child(c)

func _page_mail(body: VBoxContainer) -> void:
	Game.wallet.mail_read = true
	var c := _box_panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	c.add_child(v)
	v.add_child(UiKit.label("أهلاً فيك بمنطقة الصفر!", 20, Color("ffd34d"), UiKit.bold(), 0))
	v.add_child(UiKit.label("من: فريق %s Gaming Studios" % Game.STUDIO, 13, Color(1, 1, 1, 0.6), null, 0))
	v.add_child(UiKit.label("شكراً إنك جرّبت اللعبة. هي هدية صغيرة لتبلّش فيها:\nاشتري ملابس جديدة من المخزون، وخلّص المهام لتجمع ذهب أكثر.", 15, Color.WHITE, null, 0))
	var claimed := _claimed("mail_welcome")
	v.add_child(_small_btn("مستلم ✓" if claimed else "استلام 🪙 300", func(): _claim("mail_welcome", 300); _open("mail"), not claimed))
	body.add_child(c)

func _page_clan(body: VBoxContainer) -> void:
	var le := LineEdit.new()
	le.text = String(Game.profile.clan)
	le.placeholder_text = "اسم العشيرة"
	le.max_length = 14
	le.custom_minimum_size = Vector2(260, 40)
	le.text_changed.connect(func(s): Game.profile.clan = s.strip_edges())
	body.add_child(_row("اسم العشيرة", le))
	body.add_child(UiKit.label("اللعب فردي بهالنسخة، بس فيك تحط اسم عشيرتك ليظهر بالبطاقة.", 14, Color(1, 1, 1, 0.7), null, 0))
	var c := _box_panel()
	c.add_child(UiKit.label("👤 %s — القائد    •    المستوى %d" % [Game.player_name(), Game.level()], 16, Color.WHITE, null, 0))
	body.add_child(c)

func _page_shop(body: VBoxContainer) -> void:
	body.add_child(UiKit.label("كل شي بالمتجر بالذهب اللي تجمعه من اللعب — ما في دفع حقيقي.", 14, Color(1, 1, 1, 0.7), null, 0))
	var c := _box_panel(Color(0.55, 0.12, 0.22, 0.3))
	var hb := HBoxContainer.new()
	c.add_child(hb)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.label("🎁 صندوق القمر الأحمر", 20, Color.WHITE, UiKit.bold(), 0))
	v.add_child(UiKit.label("فيه ملابس عشوائية أو ذهب — 🪙 150", 14, Color("ffd34d"), null, 0))
	hb.add_child(v)
	hb.add_child(_small_btn("افتح", func(): _open("crate")))
	body.add_child(c)
	_page_inventory(body)

func _page_crate(body: VBoxContainer) -> void:
	var c := _box_panel(Color(0.55, 0.12, 0.22, 0.3))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	c.add_child(v)
	v.add_child(UiKit.label("افتح الصندوق بـ 🪙 150 وجرّب حظك:", 18, Color.WHITE, UiKit.bold(), 0))
	v.add_child(UiKit.label("• ملابس ما عندك (فرصة 40%)\n• أو ذهب بين 60 و 300", 15, Color(1, 1, 1, 0.8), null, 0))
	v.add_child(_small_btn("افتح الصندوق", _open_crate, int(Game.wallet.gold) >= 150))
	body.add_child(c)

func _open_crate() -> void:
	if int(Game.wallet.gold) < 150: return
	Game.wallet.gold = int(Game.wallet.gold) - 150
	var missing := []
	for i in Game.WARDROBE.size():
		if not Game.owns(i): missing.append(i)
	if not missing.is_empty() and randf() < 0.4:
		var i: int = missing[randi() % missing.size()]
		Game.profile.owned.append(i)
		_toast("🎉 طلعلك: %s" % Game.WARDROBE[i][0])
	else:
		var g := randi_range(60, 300)
		Game.wallet.gold = int(Game.wallet.gold) + g
		_toast("طلعلك 🪙 %d" % g)
	Game.save_data()
	_open("crate")

func _page_events(body: VBoxContainer) -> void:
	var c := _box_panel(Color(0.35, 0.08, 0.2, 0.4))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	c.add_child(v)
	v.add_child(UiKit.label("🌙 فعالية: %s" % Game.SEASON_NAME, 22, Color("ffb0c0"), UiKit.bold(), 0))
	v.add_child(UiKit.label("اقضِ على 10 خصوم خلال الموسم واربح لبس «ليلة القمر» مجاناً.", 15, Color.WHITE, null, 0))
	var pr := _bar(float(Game.stats.kills) / 10.0, Color("e0446a"))
	pr.custom_minimum_size = Vector2(400, 10)
	v.add_child(pr)
	v.add_child(UiKit.label("%d / 10" % mini(int(Game.stats.kills), 10), 14, Color(1, 1, 1, 0.75), null, 0))
	var done := int(Game.stats.kills) >= 10
	var got := Game.owns(6)
	v.add_child(_small_btn("مستلم ✓" if got else ("استلام" if done else "قيد التقدم"), func():
		Game.profile.owned.append(6)
		Game.save_data()
		_toast("🎉 ربحت لبس «ليلة القمر»")
		_open("events"), done and not got))
	body.add_child(c)
	var m := _box_panel()
	m.add_child(UiKit.label("📋 فيه كمان مهام بتعطيك ذهب — من زر «المهام».", 15, Color.WHITE, null, 0))
	body.add_child(m)

func _seg(values: Array, names: Array, key: String, page: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	for i in values.size():
		var v = values[i]
		var on: bool = Game.settings[key] == v
		var b := UiKit.button(names[i], func(): Game.settings[key] = v; Game.save_data(); Game.apply_fps(); _open(page), Vector2(0, 38), UiKit.style(UiKit.YELLOW if on else Color(1, 1, 1, 0.08), 3, Color(0, 0, 0, 0), 0, 10), 15, UiKit.INK if on else Color.WHITE)
		hb.add_child(b)
	return hb

func _page_settings(body: VBoxContainer) -> void:
	body.add_child(_row("مستوى الخصوم", _seg(["easy", "normal", "hard"], ["سهل", "عادي", "صعب"], "difficulty", "settings")))
	body.add_child(_row("طريقة التحكم", _seg(["touch", "kbm"], ["أزرار الشاشة", "كيبورد وماوس"], "controls", "settings")))
	body.add_child(_row("جودة الرسوميات", _seg(Game.QUALITIES, Game.QUALITY_NAMES, "quality", "settings")))
	body.add_child(_row("عدد الإطارات", _seg(Game.FPS_OPTIONS, Game.FPS_OPTIONS.map(func(f): return str(f)), "fps", "settings")))
	body.add_child(_row("كرت الشاشة", UiKit.label(RenderingServer.get_video_adapter_name(), 14, Color(1, 1, 1, 0.7), null, 0)))
	var sl := HSlider.new()
	sl.min_value = 0.3
	sl.max_value = 3.0
	sl.step = 0.1
	sl.value = float(Game.settings.sensitivity)
	sl.custom_minimum_size = Vector2(240, 30)
	sl.value_changed.connect(func(v): Game.settings.sensitivity = v)
	body.add_child(_row("حساسية النظر", sl))
	var sl2 := HSlider.new()
	sl2.min_value = 0.15
	sl2.max_value = 1.2
	sl2.step = 0.05
	sl2.value = float(Game.settings.get("aim_sens", 0.45))
	sl2.custom_minimum_size = Vector2(240, 30)
	sl2.value_changed.connect(func(v): Game.settings.aim_sens = v)
	body.add_child(_row("حساسية التصويب والسكوب", sl2))
	var inv := CheckButton.new()
	inv.button_pressed = bool(Game.settings.get("invert_y", false))
	inv.toggled.connect(func(v): Game.settings.invert_y = v)
	body.add_child(_row("عكس النظر لفوق ولتحت", inv))
	body.add_child(_row("الطقس بالمباراة", _seg(["random", "clear", "rain", "sunset"], ["عشوائي", "صافي", "مطر", "غروب"], "weather", "settings")))
	body.add_child(_row("أزرار الكيبورد", _small_btn("تغيير الأزرار", func(): _open("keys"))))
	var snd := CheckButton.new()
	snd.button_pressed = bool(Game.settings.sound)
	snd.toggled.connect(func(v): Game.settings.sound = v)
	body.add_child(_row("الصوت", snd))
	body.add_child(_row("", _small_btn("الخروج من اللعبة", func(): get_tree().quit(), true, false)))

var _wait_key := ""         # action waiting for its new key on the keys page

## Every rebindable key: click one, then press the new key (Esc cancels).
## A key already in use swaps with it.
func _page_keys(body: VBoxContainer) -> void:
	body.add_child(UiKit.label("اكبس على أي زر، وبعدين اكبس الزر الجديد على الكيبورد. إذا الزر مستعمل لشي ثاني بيتبادلوا.", 15, Color(1, 1, 1, 0.75), null, 0))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for a in Game.KEY_ORDER:
		var hb := HBoxContainer.new()
		hb.custom_minimum_size = Vector2(420, 0)
		var l := UiKit.label(Game.KEY_NAMES[a], 16, Color(0.85, 0.88, 0.92), null, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		var waiting: bool = _wait_key == a
		var txt := "اكبس زر…" if waiting else Game.key_label(Game.key(a))
		var changed: bool = Game.settings.keys.has(a)
		var b := UiKit.button(txt, func():
			_wait_key = "" if _wait_key == a else a
			_open("keys"), Vector2(130, 36), UiKit.style(UiKit.YELLOW if waiting else Color(1, 1, 1, 0.12 if not changed else 0.22), 3, Color(1, 1, 1, 0.2), 1, 6), 15, UiKit.INK if waiting else Color.WHITE)
		b.focus_mode = Control.FOCUS_NONE
		hb.add_child(b)
		grid.add_child(hb)
	body.add_child(_row("", _small_btn("إرجاع الأزرار الأصلية", func():
		_wait_key = ""
		Game.reset_keys()
		_open("keys"), true, false)))

func _input(event: InputEvent) -> void:
	if _wait_key == "" or not (event is InputEventKey) or not event.pressed or event.echo: return
	get_viewport().set_input_as_handled()
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code != KEY_ESCAPE:
		Game.set_key(_wait_key, code)
	_wait_key = ""
	_open("keys")

func _page_mode(body: VBoxContainer) -> void:
	var c := _box_panel(Color(0.1, 0.3, 0.25, 0.35))
	var v := VBoxContainer.new()
	c.add_child(v)
	v.add_child(UiKit.label("كلاسيكي — جزيرة الصفر (8×8)", 20, Color.WHITE, UiKit.bold(), 0))
	v.add_child(UiKit.label("منظور الشخص الثالث • 100 لاعب", 14, Color(1, 1, 1, 0.75), null, 0))
	body.add_child(c)
	body.add_child(_row("الفريق", _seg(["solo", "duo", "squad"], ["فردي", "ثنائي (زميل واحد)", "فرقة (3 زملاء)"], "mode", "mode")))
	body.add_child(UiKit.label("بالثنائي والفرقة: زملاؤك من الكمبيوتر بينطّوا معك ويلحقوك، واللي بينصاب بينسقط على الأرض وزميله بيرفعه (F مطوّل).", 14, Color(1, 1, 1, 0.7), null, 0))
	body.add_child(_row("مستوى الخصوم", _seg(["easy", "normal", "hard"], ["سهل", "عادي", "صعب"], "difficulty", "mode")))
	body.add_child(_row("", _small_btn("تأكيد", func(): _close_panel())))

func _page_help(body: VBoxContainer) -> void:
	body.add_child(UiKit.label("• اقفز من الطائرة فوق الجزيرة، وافتح المظلة.\n• اجمع الأسلحة والذخيرة (F أو زر «التقاط»).\n• عصا الحركة يسار — اسحبها لفوق لتثبيت الركض.\n• اسحب يمين الشاشة للنظر، وأزرار الإطلاق بتدوّر الكاميرا كمان.\n• كيبورد: WASD حركة، Shift ركض، C انحناء، Z انبطاح،\n   Space قفز ونطّ فوق الحيطان والشبابيك، R تلقيم، زر الماوس اليمين منظار،\n   Q و E ميلان، M الخريطة، B الحقيبة، Ctrl لإظهار الماوس أو إخفائه.\n   (كل الأزرار بتقدر تغيّرها من الإعدادات ← تغيير الأزرار)\n• H علاج، Y منشّط، G قنبلة (اترك الزر للرمي)، T نوع القنبلة.\n• F جنب صندوق الميت بتفتح أغراضه، وبتركب سيارة أو موتور أو قارب.\n• العب مباريات لتجمع ذهب وخبرة الموسم، واشتري ملابس من المخزون.", 17, Color.WHITE, null, 0))
