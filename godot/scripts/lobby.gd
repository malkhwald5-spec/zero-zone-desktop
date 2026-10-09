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

	# The battlefield art (desert camp at dusk) as a big painted backdrop,
	# sandy ground under the character fading into it, sandbags and ammo crates.
	_backdrop()
	var sand := ShaderMaterial.new()
	sand.shader = load("res://shaders/lobby_ground.gdshader")
	sand.set_shader_parameter("tex", load("res://assets/textures/sand_col.jpg"))
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 22)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	_mesh(pm, sand, Vector3(0, 0, -6))
	var bag := _mat(Color("b39c74"), 0.95)
	bag.albedo_texture = _noise(0.25, 21)
	for row in [[Vector3(-3.6, 0, -2.8), 7, 0.35], [Vector3(2.9, 0, -3.4), 6, -0.25]]:
		var at: Vector3 = row[0]
		var n: int = row[1]
		var ang: float = row[2]
		var dir := Vector3(cos(ang), 0, sin(ang))
		for layer in 3:
			for k in n - layer:
				var c := CapsuleMesh.new()
				c.radius = 0.2
				c.height = 0.78
				c.radial_segments = 10
				c.rings = 4
				var pos := at + dir * ((k - (n - layer - 1) * 0.5) * 0.66) + Vector3(0, 0.17 + layer * 0.3, 0)
				var m := _mesh(c, bag, pos, Vector3(0, -ang, PI / 2))
				m.scale = Vector3(1, 1, 0.75)
	var crate := _mat(Color("3f4f34"), 0.7)
	crate.albedo_texture = _noise(0.5, 31)
	var steel := _mat(Color("2b2f2c"), 0.5, 0.0, 0.6)
	for c in [[Vector3(2.7, 0, -4.6), 0.3, Vector3(0.8, 0.4, 0.45)], [Vector3(2.8, 0.4, -4.65), 0.15, Vector3(0.7, 0.32, 0.4)],
			[Vector3(-3.1, 0, -5.0), -0.4, Vector3(0.85, 0.42, 0.48)]]:
		var box_n := _mesh(_box(c[2]), crate, c[0] + Vector3(0, c[2].y * 0.5, 0), Vector3(0, c[1], 0))
		_mesh(_box(Vector3(c[2].x + 0.02, 0.06, c[2].z + 0.02)), steel, c[0] + Vector3(0, c[2].y - 0.05, 0), Vector3(0, c[1], 0))
		box_n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	holder = Node3D.new()
	add_child(holder)
	_spawn_soldier()

	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.look_at_from_position(Vector3(0.2, 1.25, 4.6), Vector3(0.0, 1.05, 0.0))
	cam.current = true

var _art: MeshInstance3D

## The war art far behind the scene, unlit (it is already painted), with its
## lower edge fading into the sand.
func _backdrop() -> void:
	var tex: Texture2D = load("res://assets/textures/ui/art_desert.jpg")
	var q := QuadMesh.new()
	var w := 66.0
	q.size = Vector2(w, w * float(tex.get_height()) / tex.get_width())
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/lobby_backdrop.gdshader")
	m.set_shader_parameter("tex", tex)
	_art = MeshInstance3D.new()
	_art.mesh = q
	_art.material_override = m
	_art.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_art.position = Vector3(0, q.size.y * 0.5 - 3.4, -30)
	add_child(_art)

func _spawn_soldier() -> void:
	if soldier: soldier.queue_free()
	soldier = HumanModel.new(Game.outfit_color(), Color("f2a900"), Game.pants_color(), Game.outfit_character())
	soldier.set_style(Game.outfit_style())
	soldier.set_gear(0, 0, 0)
	soldier.set_weapon("m416")
	soldier.rotation.y = PI - 0.45    # turned a little off the camera: a stronger stance
	holder.add_child(soldier)
	_idle_t = 0.0
	_idle_i = 0

## The character's idle in the lobby: rifle at the ready, looking at you,
## and every few seconds something else — checks the magazine, raises the
## sight, looks around.
const IDLE_STEPS := [["idle", 6.0], ["check", 2.6], ["idle", 5.0], ["aim", 2.4], ["idle", 5.0], ["look", 4.5]]
var _idle_t := 0.0
var _idle_i := 0

func _idle_director(delta: float) -> void:
	_idle_t += delta
	var step: Array = IDLE_STEPS[_idle_i]
	if _idle_t >= float(step[1]):
		_idle_t = 0.0
		_idle_i = (_idle_i + 1) % IDLE_STEPS.size()
		step = IDLE_STEPS[_idle_i]
	var k: float = _idle_t / float(step[1])
	soldier.reload_p = k if step[0] == "check" else -1.0
	soldier.aiming = step[0] == "aim"
	# Where the head turns: at the camera, or sweeping round while looking about.
	var to_cam := soldier.global_transform.affine_inverse() * cam.global_position
	var yaw := atan2(-to_cam.x, -to_cam.z)     # the model faces -Z; left is +
	var pitch := atan2(to_cam.y - 1.6, Vector2(to_cam.x, to_cam.z).length())
	match step[0]:
		"aim":
			yaw = 0.0
			pitch = 0.0
		"check":
			yaw *= 0.2
			pitch = -0.35
		"look":
			yaw = sin(k * TAU) * 0.9
			pitch = 0.05
	var w := minf(1.0, delta * 3.0)
	soldier.look_yaw = lerpf(soldier.look_yaw, yaw, w)
	soldier.look_pitch = lerpf(soldier.look_pitch, pitch, w)

func _process(delta: float) -> void:
	t += delta
	holder.rotation.y = drag_rot
	_idle_director(delta)
	soldier.set_pose("stand", 0.0, true, delta, t)
	# The backdrop drifts slowly, like a camera breathing.
	if _art: _art.position.x = sin(t * 0.07) * 1.6
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
	var rank_btn := Button.new()
	rank_btn.custom_minimum_size = Vector2(150, 34)
	rank_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rank_btn.add_theme_stylebox_override("normal", UiKit.style(Color(0, 0, 0, 0.45), 17, Color(1, 1, 1, 0.15), 1, 4))
	rank_btn.add_theme_stylebox_override("hover", UiKit.style(Color(0, 0, 0, 0.6), 17, Color(1, 1, 1, 0.35), 1, 4))
	rank_btn.add_theme_stylebox_override("pressed", UiKit.style(Color(0, 0, 0, 0.6), 17, Color(1, 1, 1, 0.35), 1, 4))
	rank_btn.pressed.connect(func(): _open("cards"))
	var rb := RankBadge.new(int(Game.stats.rp), 28.0)
	rb.position = Vector2(6, 1)
	rank_btn.add_child(rb)
	var rl := UiKit.label("", 15, Color.WHITE, UiKit.bold(), 3)
	rl.position = Vector2(40, 5)
	rank_btn.add_child(rl)
	labels.rank_badge = rb
	labels.rank = rl
	who.add_child(rank_btn)
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
	var ri := Game.rank_info(int(Game.stats.rp))
	labels.rank.text = ri.name
	labels.rank.add_theme_color_override("font_color", ri.color)
	labels.rank_badge.rp = int(Game.stats.rp)
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
	"inventory": "المخزون", "cards": "الملف الشخصي والرتبة", "workshop": "ورشة العمل", "season": "الموسم — ZERO PASS",
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
	# The soldier art behind the menu pages, darkened so the panels read well.
	if not side:
		var art := TextureRect.new()
		art.texture = load("res://assets/textures/ui/art_soldier.jpg")
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(art)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07, 0.86 if side else 0.74)
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
	if which == "settings":
		scroll.offset_right = -250
		scroll.offset_left = 24
		_settings_tabs(page)
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
	_rank_panel(body)
	var st: Dictionary = Game.stats
	var games := maxi(1, int(st.games))
	var best: String = ("#%d" % st.best) if st.best > 0 else "-"
	var kd := float(st.kills) / maxf(1.0, float(st.games - st.wins))
	var avg_t := int(st.time) / maxi(1, _recorded_games())
	body.add_child(UiKit.label("الإحصائيات العامة", 18, Color.WHITE, UiKit.bold(), 0))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	for s in [["المباريات", str(int(st.games))], ["الانتصارات", str(int(st.wins))], ["نسبة الفوز", "%d%%" % roundi(100.0 * st.wins / games)],
			["أفضل 10", str(int(st.top10))], ["أفضل ترتيب", best], ["معدل K/D", "%.2f" % kd],
			["الإقصاءات", str(int(st.kills))], ["أكثر قتلات بمباراة", str(int(st.best_kills))], ["قتلات بالراس", str(int(st.heads))],
			["أبعد قتلة", "%d م" % int(st.longest)], ["الضرر الكلي", str(int(st.dmg))], ["معدل النجاة", "%d:%02d" % [avg_t / 60, avg_t % 60]]]:
		var c := _box_panel()
		c.custom_minimum_size = Vector2(150, 80)
		var v := VBoxContainer.new()
		v.add_child(UiKit.label(s[0], 13, Color(1, 1, 1, 0.7), null, 0))
		v.add_child(UiKit.label(s[1], 26, Color("ffd34d"), UiKit.bold(), 0))
		c.add_child(v)
		grid.add_child(c)
	_mode_table(body)
	_history(body)

## Games played since the career page tracked details (older saves only counted totals).
func _recorded_games() -> int:
	var n := 0
	for m in Game.stats.get("modes", {}).values(): n += int(m.games)
	return n

func _rank_panel(body: VBoxContainer) -> void:
	var rp := int(Game.stats.rp)
	var ri := Game.rank_info(rp)
	var box := _box_panel(Color(ri.color.r, ri.color.g, ri.color.b, 0.12))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	box.add_child(hb)
	hb.add_child(RankBadge.new(rp, 110.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.label("الرتبة — %s" % Game.SEASON_NAME, 14, Color(1, 1, 1, 0.7), null, 0))
	v.add_child(UiKit.label(ri.name, 34, ri.color, UiKit.bold(), 4))
	var b := _bar(ri.frac, ri.color)
	b.custom_minimum_size = Vector2(420, 12)
	v.add_child(b)
	var next := ("باقي %d نقطة للرتبة الجاية" % ri.to_next) if ri.to_next > 0 else "وصلت لأعلى رتبة! 👑"
	v.add_child(UiKit.label("نقاط الرتبة: %d     %s" % [rp, next], 15, Color.WHITE, null, 0))
	v.add_child(UiKit.label("بتربح نقاط لما تخلص بترتيب عالي وتقتل أكثر، وبتخسر شوي إذا طلعت بكير.", 13, Color(1, 1, 1, 0.6), null, 0))
	hb.add_child(v)
	# The ladder: every tier, the reached ones lit.
	var ladder := HBoxContainer.new()
	ladder.add_theme_constant_override("separation", 6)
	ladder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in Game.RANK_TIERS.size():
		var tv := VBoxContainer.new()
		var rb := RankBadge.new(int(Game.RANK_TIERS[i][2]), 40.0)
		rb.modulate = Color.WHITE if i <= ri.tier else Color(1, 1, 1, 0.28)
		rb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tv.add_child(rb)
		var l := UiKit.label(Game.RANK_TIERS[i][0], 11, Color.WHITE if i <= ri.tier else Color(1, 1, 1, 0.4), null, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tv.add_child(l)
		ladder.add_child(tv)
	hb.add_child(ladder)
	body.add_child(box)

func _mode_table(body: VBoxContainer) -> void:
	body.add_child(UiKit.label("حسب الوضع", 18, Color.WHITE, UiKit.bold(), 0))
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 36)
	g.add_theme_constant_override("v_separation", 6)
	var box := _box_panel()
	box.add_child(g)
	body.add_child(box)
	for h in ["الوضع", "مباريات", "فوز", "قتلات", "أفضل 10", "ضرر/مباراة"]:
		g.add_child(UiKit.label(h, 14, Color(1, 1, 1, 0.6), UiKit.bold(), 0))
	for mode in ["solo", "duo", "squad"]:
		var m: Dictionary = Game.stats.get("modes", {}).get(mode, {"games": 0, "wins": 0, "kills": 0, "top10": 0, "dmg": 0})
		var n := int(m.games)
		for x in [Game.MODE_NAMES[mode], str(n), str(int(m.wins)), str(int(m.kills)), str(int(m.top10)), str(int(m.dmg) / maxi(1, n))]:
			g.add_child(UiKit.label(x, 16, Color.WHITE if n > 0 else Color(1, 1, 1, 0.4), null, 0))

func _history(body: VBoxContainer) -> void:
	body.add_child(UiKit.label("آخر المباريات", 18, Color.WHITE, UiKit.bold(), 0))
	var hist: Array = Game.stats.get("history", [])
	if hist.is_empty():
		body.add_child(UiKit.label("لسا ما لعبت مباريات — العب وحتشوف نتايجك هون.", 15, Color(1, 1, 1, 0.6), null, 0))
		return
	for h in hist:
		var won: bool = h.get("won", false)
		var c := _box_panel(Color(1, 0.82, 0.12, 0.14) if won else Color(1, 1, 1, 0.05))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 28)
		c.add_child(hb)
		var place := UiKit.label("🏆 #1" if won else "#%d" % int(h.rank), 22, Color("ffd34d") if won else Color.WHITE, UiKit.bold(), 0)
		place.custom_minimum_size = Vector2(80, 0)
		hb.add_child(place)
		var t := int(h.get("time", 0))
		for x in [Game.MODE_NAMES.get(h.get("mode", "solo"), ""), "قتلات %d" % int(h.kills), "ضرر %d" % int(h.get("dmg", 0)), "نجاة %d:%02d" % [t / 60, t % 60]]:
			var l := UiKit.label(x, 15, Color(1, 1, 1, 0.85), null, 0)
			l.custom_minimum_size = Vector2(110, 0)
			hb.add_child(l)
		var d := int(h.get("rp", 0))
		var dl := UiKit.label(("+%d" % d if d >= 0 else str(d)) + " نقطة", 16, Color("7dff8a") if d >= 0 else Color("ff7a7a"), UiKit.bold(), 0)
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(dl)
		body.add_child(c)

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
	var cls_names := {"pistol": "مسدس", "smg": "رشاش خفيف", "shotgun": "شوزن", "ar": "رشاش هجومي", "sr": "قناصة", "lmg": "رشاش ثقيل",
		"dmr": "قناصة نص أوتوماتيك", "crossbow": "قوس صامت", "melee": "سلاح أبيض"}
	for id in Game.WEAPONS:
		var w: Dictionary = Game.WEAPONS[id]
		var c := _box_panel()
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		c.add_child(hb)
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(170, 0)
		v.add_child(UiKit.label(w.name, 22, Color.WHITE, UiKit.bold(), 0))
		v.add_child(UiKit.label("%s • %s%s" % [cls_names.get(w.cls, ""), ("" if w.get("melee", false) else Game.AMMO_NAMES[w.ammo]), "  • إنزال جوي فقط" if w.get("crate", false) else ""], 13, Color("ff8a8a") if w.get("crate", false) else Color(1, 1, 1, 0.65), null, 0))
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

## Re-applies graphics settings to the lobby scene (laptop mode, render scale).
func _apply_gfx() -> void:
	var env: Environment = null
	var sun: DirectionalLight3D = null
	for n in get_children():
		if n is WorldEnvironment: env = n.environment
		elif n is DirectionalLight3D and sun == null: sun = n
	Game.apply_quality(env, sun)

# ---------------------------------------------------------------- settings
const SET_TABS := [["basic", "أساسي"], ["graphics", "الرسومات"], ["controls", "التحكم"], ["vehicle", "المركبات"],
	["sens", "الحساسية"], ["pickup", "الالتقاط"], ["scope", "المنظار"], ["audio", "الصوت"]]
var _set_tab := "basic"
var _editor: TouchEditor

## Tabs down the right side, as in the mobile game.
func _settings_tabs(page: Control) -> void:
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", UiKit.style(Color(0.06, 0.08, 0.11, 0.92), 0, Color(1, 1, 1, 0.08), 1, 0))
	side.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -230
	side.offset_top = 56
	page.add_child(side)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	side.add_child(v)
	for t in SET_TABS:
		var on: bool = _set_tab == t[0]
		var b := UiKit.button(t[1], func(): _set_tab = t[0]; _open("settings"), Vector2(230, 56),
			UiKit.style(Color("e09a1c") if on else Color(0, 0, 0, 0), 0, Color(1, 1, 1, 0.07), 1, 0), 18, Color.WHITE if on else Color(0.75, 0.8, 0.86))
		b.focus_mode = Control.FOCUS_NONE
		v.add_child(b)

## A boxed group of options in two columns.
func _section(body: VBoxContainer, title: String) -> GridContainer:
	var pc := _box_panel(Color(0.05, 0.07, 0.1, 0.78))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	if title != "":
		v.add_child(UiKit.label(title, 15, Color("ffd34d"), UiKit.bold(), 0))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 34)
	g.add_theme_constant_override("v_separation", 12)
	v.add_child(g)
	body.add_child(pc)
	return g

## Label + control at a fixed width (one grid cell).
func _cell(text: String, ctrl: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(470, 40)
	hb.add_theme_constant_override("separation", 10)
	var l := UiKit.label(text, 16, Color(0.86, 0.89, 0.93), null, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(l)
	hb.add_child(ctrl)
	return hb

## Segmented choice (gold = on) that saves at once and restyles in place.
func _choice(values: Array, names: Array, key: String, after := Callable()) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	var btns := []
	var paint := func():
		for i in btns.size():
			var on := _same(Game.settings.get(key), values[i])
			btns[i].add_theme_stylebox_override("normal", UiKit.style(Color("c9a24a") if on else Color(0.07, 0.08, 0.1, 0.95), 0, Color(1, 1, 1, 0.12), 1, 8))
			btns[i].add_theme_stylebox_override("hover", UiKit.style(Color("d8b45c") if on else Color(0.14, 0.15, 0.18, 0.95), 0, Color(1, 1, 1, 0.2), 1, 8))
			btns[i].add_theme_color_override("font_color", UiKit.INK if on else Color.WHITE)
			btns[i].add_theme_color_override("font_hover_color", UiKit.INK if on else Color.WHITE)
	for i in values.size():
		var b := UiKit.button(names[i], func():
			Game.settings[key] = values[i]
			paint.call()
			if after.is_valid(): after.call(), Vector2(maxf(78.0, names[i].length() * 11.0 + 24.0), 38), UiKit.style(Color(0, 0, 0, 0), 0), 15)
		b.focus_mode = Control.FOCUS_NONE
		btns.append(b)
		hb.add_child(b)
	paint.call()
	return hb

## Equal, without comparing different kinds of value (saved numbers come back as floats).
func _same(a, b) -> bool:
	var num := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in num and typeof(b) in num: return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b

func _onoff(key: String, after := Callable()) -> HBoxContainer:
	return _choice([false, true], ["إيقاف", "تشغيل"], key, after)

func _slider(key: String, lo: float, hi: float, step: float, def: float, fmt: Callable, after := Callable()) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = clampf(float(Game.settings.get(key, def)), lo, hi)
	sl.custom_minimum_size = Vector2(200, 30)
	var l := UiKit.label(fmt.call(sl.value), 15, Color.WHITE, UiKit.bold(), 0)
	l.custom_minimum_size = Vector2(52, 0)
	sl.value_changed.connect(func(v):
		Game.settings[key] = v
		l.text = fmt.call(v)
		if after.is_valid(): after.call())
	hb.add_child(l)
	hb.add_child(sl)
	return hb

func _pct(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)

func _page_settings(body: VBoxContainer) -> void:
	match _set_tab:
		"basic":
			var g := _section(body, "التصويب والإطلاق")
			g.add_child(_cell("مساعدة التصويب", _onoff("aim_assist")))
			g.add_child(_cell("القناصات والقوس: الإطلاق", _choice(["tap", "release"], ["ضغطة", "عند الإفلات"], "bolt_fire")))
			g.add_child(_cell("الشوزن: الإطلاق", _choice(["tap", "release"], ["ضغطة", "عند الإفلات"], "shotgun_fire")))
			g.add_child(_cell("زر المنظار", _choice(["tap", "hold", "mixed"], ["ضغطة", "مطوّل", "مختلط"], "scope_mode")))
			g.add_child(_cell("أزرار الميلان (الشاشة)", _choice(["tap", "hold"], ["ضغطة", "مطوّل"], "lean_mode")))
			g = _section(body, "أثناء اللعب")
			g.add_child(_cell("زر الإطلاق اليسار", _choice(["always", "scope", "off"], ["دائماً", "مع المنظار", "مخفي"], "left_fire")))
			g.add_child(_cell("تنبيه العلاج", _onoff("heal_prompt")))
			g.add_child(_cell("لون الإصابة", _choice(["red", "green"], ["أحمر", "أخضر"], "hit_color")))
			g.add_child(_cell("إظهار عدد الإطارات (FPS)", _onoff("show_fps")))
			g = _section(body, "المباراة")
			g.add_child(_cell("مستوى الخصوم", _choice(["easy", "normal", "hard"], ["سهل", "عادي", "صعب"], "difficulty")))
			g.add_child(_cell("الطقس", _choice(["random", "clear", "rain", "sunset", "fog"], ["عشوائي", "صافي", "مطر", "غروب", "ضباب"], "weather")))
			body.add_child(_row("", _small_btn("الخروج من اللعبة", func(): get_tree().quit(), true, false)))
		"graphics":
			var g := _section(body, "الجودة")
			g.add_child(_cell("الرسوميات", _choice(Game.QUALITIES, Game.QUALITY_NAMES, "quality", _apply_gfx)))
			g.add_child(_cell("عدد الإطارات", _choice(Game.FPS_OPTIONS, Game.FPS_OPTIONS.map(func(f): return str(f)), "fps", func(): Game.apply_fps())))
			g.add_child(_cell("وضع اللابتوب (أسرع)", _onoff("laptop", _apply_gfx)))
			g.add_child(_cell("دقة الرسم (أقل = أسرع)", _slider("render_scale", 0.5, 1.0, 0.05, 1.0, func(v): return "%d%%" % roundi(Game.render_scale() * 100.0) if Game.laptop() else _pct(v), _apply_gfx)))
			g.add_child(_cell("السطوع", _slider("brightness", 0.7, 1.4, 0.05, 1.0, _pct, _apply_gfx)))
			g.add_child(_cell("كرت الشاشة", UiKit.label(RenderingServer.get_video_adapter_name(), 14, Color(1, 1, 1, 0.7), null, 0)))
		"controls":
			var g := _section(body, "طريقة اللعب")
			g.add_child(_cell("التحكم", _choice(["touch", "kbm"], ["أزرار الشاشة", "كيبورد وماوس"], "controls")))
			g.add_child(_cell("أزرار الكيبورد", _small_btn("تغيير الأزرار", func(): _open("keys"))))
			g = _section(body, "أزرار الشاشة")
			g.add_child(_cell("ترتيب الأزرار", _small_btn("تخصيص", _open_touch_editor)))
			g.add_child(_cell("التصميم المستعمل", _choice([0, 1, 2], ["1", "2", "3"], "touch_layout")))
			g.add_child(_cell("شفافية الأزرار", _slider("touch_alpha", 0.2, 1.0, 0.05, 0.8, _pct)))
			g.add_child(_cell("عصا الحركة", _choice([false, true], ["ثابتة", "تلحق إصبعك"], "joy_float")))
		"vehicle":
			var g := _section(body, "الكاميرا")
			g.add_child(_cell("الكاميرا ترجع ورا المركبة", _onoff("veh_cam_follow")))
			g.add_child(_cell("بُعد الكاميرا", _choice([false, true], ["قريبة", "بعيدة"], "veh_cam_far")))
			body.add_child(UiKit.label("السيارة والموتور والقارب: W و S للبنزين والفرامل، A و D للتوجيه، F للنزول (أو العصا والأزرار على الشاشة).", 14, Color(1, 1, 1, 0.65), null, 0))
		"sens":
			var g := _section(body, "الكاميرا")
			g.add_child(_cell("حساسية النظر", _slider("sensitivity", 0.3, 3.0, 0.05, 1.0, _pct)))
			g.add_child(_cell("عكس النظر لفوق ولتحت", _onoff("invert_y")))
			g = _section(body, "التصويب")
			g.add_child(_cell("التصويب بدون سكوب", _slider("aim_sens", 0.15, 1.2, 0.05, 0.45, _pct)))
			g.add_child(_cell("ريد دوت وهولو", _slider("sens_1x", 0.3, 2.0, 0.05, 1.0, _pct)))
			g.add_child(_cell("سكوب 2", _slider("sens_2x", 0.2, 1.6, 0.05, 0.71, _pct)))
			g.add_child(_cell("سكوب 4", _slider("sens_4x", 0.1, 1.2, 0.05, 0.5, _pct)))
			g.add_child(_cell("سكوب 8", _slider("sens_8x", 0.05, 1.0, 0.05, 0.35, _pct)))
		"pickup":
			var g := _section(body, "الالتقاط التلقائي")
			g.add_child(_cell("الالتقاط التلقائي", _onoff("auto_pick")))
			g.add_child(_cell("طلق أسلحتك", _onoff("pick_ammo")))
			g.add_child(_cell("العلاجات", _onoff("pick_meds")))
			g.add_child(_cell("القنابل", _onoff("pick_throw")))
			g.add_child(_cell("القطع اللي بتركب على سلاحك", _onoff("pick_attach")))
			g = _section(body, "الحد الأعلى للالتقاط التلقائي")
			g.add_child(_cell("ضمادات", _choice([10, 20, 30], ["10", "20", "30"], "max_bandage")))
			g.add_child(_cell("إسعاف أولي", _choice([3, 5, 8], ["3", "5", "8"], "max_firstaid")))
			g.add_child(_cell("مشروبات ومسكّنات", _choice([4, 6, 10], ["4", "6", "10"], "max_boost")))
			g.add_child(_cell("قنابل", _choice([3, 6, 9], ["3", "6", "9"], "max_throw")))
		"scope":
			var g := _section(body, "علامة التصويب")
			g.add_child(_cell("لون علامة التصويب", _choice(["white", "red", "green", "yellow", "cyan"], ["أبيض", "أحمر", "أخضر", "أصفر", "سماوي"], "crosshair")))
			g.add_child(_cell("نقطة الريد دوت والهولو", _choice(["red", "green"], ["أحمر", "أخضر"], "dot_color")))
		"audio":
			var g := _section(body, "الصوت")
			g.add_child(_cell("الصوت", _onoff("sound", func(): Game.apply_audio())))
			g.add_child(_cell("مستوى الصوت", _slider("master_vol", 0.0, 1.0, 0.05, 1.0, _pct, func(): Game.apply_audio())))

## The on-screen buttons editor, over the whole lobby.
func _open_touch_editor() -> void:
	if _editor: return
	_editor = TouchEditor.new()
	ui.add_child(_editor)
	_editor.closed.connect(func(): _editor = null)

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
