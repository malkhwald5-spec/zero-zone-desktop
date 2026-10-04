extends Node3D
## Lobby: a night-time courtyard (arches, palms, lanterns, string lights,
## crescent moon) with the player's soldier, plus the lobby UI. Solo only.

var soldier: SoldierModel
var holder: Node3D
var cam: Camera3D
var ui: CanvasLayer
var font_bold: FontVariation
var panel: Control
var t := 0.0
var drag_rot := -1.05
var _dragging := false
var labels := {}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_scene()
	_build_ui()

# ---------- 3D scene ----------
func _mat(c: Color, rough := 0.9, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
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

func _build_scene() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.02, 0.03, 0.09)
	sky_mat.sky_horizon_color = Color(0.1, 0.09, 0.2)
	sky_mat.ground_horizon_color = Color(0.1, 0.09, 0.2)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_color = Color(0.35, 0.38, 0.6)
	env.ambient_light_energy = 0.5
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.06, 0.14)
	env.fog_density = 0.01
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.65, 0.72, 1.0)
	moon.light_energy = 0.35
	moon.rotation_degrees = Vector3(-50, 40, 0)
	add_child(moon)
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.82, 0.6)
	key.light_energy = 6.0
	key.spot_range = 14.0
	key.spot_angle = 35.0
	key.shadow_enabled = true
	key.position = Vector3(3, 6, 4)
	add_child(key)
	key.look_at(Vector3(0, 1, 0))

	# Floor and platform
	var floor_mat := _mat(Color("b39e80"), 0.85)
	var nt := NoiseTexture2D.new()
	nt.noise = FastNoiseLite.new()
	nt.seamless = true
	floor_mat.albedo_texture = nt
	floor_mat.uv1_scale = Vector3(6, 6, 6)
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	_mesh(pm, floor_mat, Vector3.ZERO)
	var plat := CylinderMesh.new()
	plat.top_radius = 1.3
	plat.bottom_radius = 1.4
	plat.height = 0.15
	_mesh(plat, _mat(Color("8b7a63"), 0.6), Vector3(0, 0.075, 0))

	# Arcades on both sides and a gate with towers at the back.
	var wall := _mat(Color("b48a62"))
	var trim := _mat(Color("7a5236"))
	var lantern := _mat(Color("ffcf6a"), 0.5, 4.0)
	for side in [-1, 1]:
		for i in 6:
			var a := Node3D.new()
			a.position = Vector3(-9 + i * 3.2, 0, side * 6.5)
			add_child(a)
			_mesh(_box(Vector3(0.4, 3.2, 0.4)), wall, Vector3(-1.1, 1.6, 0), Vector3.ZERO, a)
			var torus := TorusMesh.new()
			torus.inner_radius = 0.9
			torus.outer_radius = 1.3
			_mesh(torus, wall, Vector3(0, 3.2, 0), Vector3(PI / 2, 0, 0), a)
			_mesh(_box(Vector3(3.2, 0.7, 0.5)), wall, Vector3(0, 4.45, 0), Vector3.ZERO, a)
			_mesh(_box(Vector3(3.2, 0.12, 0.6)), trim, Vector3(0, 4.85, 0), Vector3.ZERO, a)
			_mesh(_box(Vector3(0.25, 0.4, 0.25)), lantern, Vector3(0, 3.0, 0), Vector3.ZERO, a)
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.72, 0.35)
			ol.light_energy = 0.9
			ol.omni_range = 4.0
			ol.position = Vector3(0, 2.8, 0)
			a.add_child(ol)
	_mesh(_box(Vector3(0.8, 7.0, 14.0)), wall, Vector3(-11, 3.5, 0))
	var gate := TorusMesh.new()
	gate.inner_radius = 1.6
	gate.outer_radius = 2.1
	_mesh(gate, trim, Vector3(-10.55, 3.8, 0), Vector3(0, 0, PI / 2))
	_mesh(_box(Vector3(0.1, 3.8, 3.2)), _mat(Color("1d120a")), Vector3(-10.55, 1.9, 0))
	for z in [-4.5, 4.5]:
		_mesh(_box(Vector3(2, 10, 2)), wall, Vector3(-11, 5, z))
		_mesh(_box(Vector3(2.3, 0.4, 2.3)), trim, Vector3(-11, 10.1, z))

	# Palms
	var trunk_mat := _mat(Color("6b4a2f"))
	var leaf_mat := _mat(Color("2f5a2b"), 0.8)
	for pos in [Vector3(-7, 0, -3.5), Vector3(-7, 0, 3.8), Vector3(-2, 0, -5.2), Vector3(-2, 0, 5.4)]:
		var pn := Node3D.new()
		pn.position = pos
		add_child(pn)
		var h := randf_range(5.0, 6.5)
		var tm := CylinderMesh.new()
		tm.top_radius = 0.12
		tm.bottom_radius = 0.18
		tm.height = h
		_mesh(tm, trunk_mat, Vector3(0, h * 0.5, 0), Vector3(0, 0, 0.08), pn)
		for i in 9:
			var leaf := CylinderMesh.new()
			leaf.top_radius = 0.0
			leaf.bottom_radius = 0.2
			leaf.height = 2.4
			var a := i * TAU / 9.0
			_mesh(leaf, leaf_mat, Vector3(cos(a) * 0.9 + 0.3, h, sin(a) * 0.9), Vector3(sin(a) * 1.25, 0, -cos(a) * 1.25), pn)

	# String lights (glowing bulbs) and stars
	var bulb := SphereMesh.new()
	bulb.radius = 0.06
	bulb.height = 0.12
	var bulb_mat := _mat(Color("ffd36b"), 0.5, 6.0)
	for z in [-5.5, 5.5]:
		for i in 40:
			var x := -10.0 + i * 0.5
			_mesh(bulb, bulb_mat, Vector3(x, 5.6 - sin(i / 39.0 * PI) * 0.7, z * (0.6 + 0.4 * sin(i / 39.0 * PI))))
	var star_mat := _mat(Color.WHITE, 1.0, 3.0)
	var star := SphereMesh.new()
	star.radius = 0.12
	star.height = 0.24
	for i in 160:
		var a := randf() * TAU
		var e := randf_range(0.2, 1.3)
		_mesh(star, star_mat, Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e)) * 70.0 + Vector3(-20, 0, 0))
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 3.0
	moon_mesh.height = 6.0
	_mesh(moon_mesh, _mat(Color("fff3d0"), 1.0, 2.5), Vector3(-60, 30, -14))
	_mesh(moon_mesh, _mat(Color(0.02, 0.03, 0.09)), Vector3(-59.2, 30.5, -12.8))  # bite out of the moon -> crescent

	# Loot chest with a glow
	var chest := Node3D.new()
	chest.position = Vector3(-1.2, 0, -2.0)
	chest.rotation.y = 0.5
	add_child(chest)
	_mesh(_box(Vector3(1.0, 0.7, 0.7)), _mat(Color("e9e2d4")), Vector3(0, 0.35, 0), Vector3.ZERO, chest)
	_mesh(_box(Vector3(1.04, 0.22, 0.74)), _mat(Color("9b2b2b"), 0.6, 0.6), Vector3(0, 0.8, 0), Vector3.ZERO, chest)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.75, 0.3)
	glow.light_energy = 2.0
	glow.omni_range = 3.0
	glow.position = Vector3(0, 1.1, 0)
	chest.add_child(glow)

	holder = Node3D.new()
	holder.position = Vector3(0, 0.15, 0)
	add_child(holder)
	_spawn_soldier()

	cam = Camera3D.new()
	cam.fov = 40
	cam.position = Vector3(5.2, 1.8, -1.1)
	add_child(cam)
	cam.look_at(Vector3(0, 1.1, -0.55))
	cam.current = true

func _spawn_soldier() -> void:
	if soldier: soldier.queue_free()
	soldier = SoldierModel.new(Game.outfit_color(), Color("f2a900"))
	soldier.set_weapon("ar")
	soldier.set_gear(2, 2, 2)
	holder.add_child(soldier)

func _process(delta: float) -> void:
	t += delta
	holder.rotation.y = drag_rot + sin(t * 0.3) * 0.08
	soldier.set_pose("stand", 0.0, true, delta, t)
	soldier.spine.rotation.x = sin(t * 1.6) * 0.02

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		drag_rot += event.relative.x * 0.01
	elif event is InputEventScreenDrag:
		drag_rot += event.relative.x * 0.01

# ---------- UI ----------
func _style(bg: Color, radius := 6, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	return sb

func _label(text: String, size: int, col := Color.WHITE, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	if bold: l.add_theme_font_override("font", font_bold)
	return l

func _button(text: String, cb: Callable, size := Vector2(0, 44), style: StyleBoxFlat = null, font_size := 17) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", font_size)
	var st := style if style else _style(Color(0, 0, 0, 0.55), 2)
	b.add_theme_stylebox_override("normal", st)
	var hov := st.duplicate()
	hov.bg_color = st.bg_color.lightened(0.15)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b

func _build_ui() -> void:
	font_bold = FontVariation.new()
	font_bold.base_font = load("res://assets/fonts/Cairo.ttf")
	font_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	# Top-left profile
	var prof := HBoxContainer.new()
	prof.position = Vector2(18, 14)
	prof.add_theme_constant_override("separation", 10)
	root.add_child(prof)
	var av := PanelContainer.new()
	av.custom_minimum_size = Vector2(54, 54)
	av.add_theme_stylebox_override("panel", _style(Color("f2a900"), 8, Color("ffe08a")))
	var avl := _label(Game.player_name().left(1), 26, Color("1a1205"), true)
	avl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(avl)
	labels.avatar = avl
	prof.add_child(av)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", -4)
	labels.name = _label(Game.player_name(), 19, Color.WHITE, true)
	labels.level = _label("المستوى %d" % Game.level(), 14, Color("ffd34d"))
	who.add_child(labels.name)
	who.add_child(labels.level)
	prof.add_child(who)

	# Title
	var title := _label("منطقة الصفر", 34, Color.WHITE, true)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.position.y = 8
	root.add_child(title)
	var tag := _label("50 لاعباً… ناجٍ واحد فقط", 15, Color("f0e6cc"))
	tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	tag.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.position.y = 58
	root.add_child(tag)

	# Top-right wallet (career numbers) + settings
	var wallet := HBoxContainer.new()
	wallet.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	wallet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wallet.position = Vector2(-18, 16)
	wallet.add_theme_constant_override("separation", 8)
	root.add_child(wallet)
	for item in [["🏆", "wins"], ["☠", "kills"]]:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.55), 18))
		var l := _label("%s  %d" % [item[0], Game.stats[item[1]]], 16)
		pc.add_child(l)
		labels[item[1]] = l
		wallet.add_child(pc)
	wallet.add_child(_button("⚙", func(): _open("settings"), Vector2(44, 44), _style(Color(0, 0, 0, 0.55), 22)))

	# Bottom-left: mode card + START
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	left.position = Vector2(18, -22)
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)
	var mode := _button("", _cycle_difficulty, Vector2(300, 64), _style(Color(0, 0, 0, 0.6), 6, Color(1, 1, 1, 0.18)))
	labels.mode = mode
	left.add_child(mode)
	_update_mode()
	var start_style := _style(Color("ffd21f"), 4)
	var start := _button("ابدأ", _start, Vector2(300, 78), start_style, 38)
	start.add_theme_font_override("font", font_bold)
	start.add_theme_color_override("font_color", Color("1b1300"))
	start.add_theme_color_override("font_hover_color", Color("1b1300"))
	start.add_theme_color_override("font_pressed_color", Color("1b1300"))
	left.add_child(start)

	# Bottom-right tabs
	var tabs := HBoxContainer.new()
	tabs.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tabs.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tabs.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tabs.position = Vector2(-18, -22)
	tabs.add_theme_constant_override("separation", 4)
	root.add_child(tabs)
	for tb in [["الإحصائيات", "stats"], ["المظهر", "outfit"], ["طريقة اللعب", "help"], ["الإعدادات", "settings"], ["خروج", "quit"]]:
		var key: String = tb[1]
		tabs.add_child(_button(tb[0], func(): _open(key), Vector2(0, 46)))

func _update_mode() -> void:
	var d := {"easy": "سهل", "normal": "عادي", "hard": "صعب"}[Game.settings.difficulty] as String
	labels.mode.text = "  كلاسيكي — فردي   |   جزيرة الصفر   |   الخصوم: %s" % d

func _cycle_difficulty() -> void:
	var order := ["easy", "normal", "hard"]
	Game.settings.difficulty = order[(order.find(Game.settings.difficulty) + 1) % 3]
	Game.save_data()
	_update_mode()

func _start() -> void:
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _refresh() -> void:
	labels.name.text = Game.player_name()
	labels.avatar.text = Game.player_name().left(1)
	labels.level.text = "المستوى %d" % Game.level()
	labels.wins.text = "🏆  %d" % Game.stats.wins
	labels.kills.text = "☠  %d" % Game.stats.kills
	_update_mode()

func _open(which: String) -> void:
	if which == "quit":
		get_tree().quit()
		return
	if panel: panel.queue_free()
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style(Color(0.05, 0.07, 0.1, 0.94), 14, Color(1, 1, 1, 0.12)))
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(480, 0)
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	var titles := {"stats": "الإحصائيات", "outfit": "المظهر", "help": "طريقة اللعب", "settings": "الإعدادات"}
	var tl := _label(titles[which], 28, Color("ffd34d"), true)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tl)
	match which:
		"stats":
			for row in [["انتصارات", Game.stats.wins], ["أفضل ترتيب", ("#%d" % Game.stats.best) if Game.stats.best > 0 else "-"], ["مجموع القتلى", Game.stats.kills], ["مباريات", Game.stats.games]]:
				vb.add_child(_row(row[0], _label(str(row[1]), 18, Color.WHITE, true)))
		"outfit":
			var le := LineEdit.new()
			le.text = String(Game.profile.name)
			le.placeholder_text = "اكتب اسمك"
			le.max_length = 16
			le.custom_minimum_size = Vector2(240, 40)
			le.text_changed.connect(func(s): Game.profile.name = s.strip_edges())
			vb.add_child(_row("اسم اللاعب", le))
			var sw := HBoxContainer.new()
			sw.add_theme_constant_override("separation", 8)
			for i in Game.OUTFITS.size():
				var idx := i
				var st := _style(Game.OUTFITS[i], 18, Color("ffd34d") if i == int(Game.profile.outfit) else Color(1, 1, 1, 0.3))
				sw.add_child(_button("", func(): Game.profile.outfit = idx; Game.save_data(); _spawn_soldier(); _open("outfit"), Vector2(36, 36), st))
			vb.add_child(_row("لون الملابس", sw))
		"help":
			var help := _label("• اقفز من الطائرة فوق الجزيرة، وافتح المظلة.\n• اجمع الأسلحة والذخيرة (F أو زر «التقاط»).\n• عصا الحركة يساراً — اسحبها للأعلى لتثبيت الركض.\n• اسحب في اليمين للنظر، وأزرار الإطلاق تدير الكاميرا أيضاً.\n• لوحة المفاتيح: WASD، Shift ركض، C انحناء، Z انبطاح،\n   Space قفز، R تلقيم، زر الفأرة الأيمن منظار، M الخريطة.", 16)
			vb.add_child(help)
		"settings":
			vb.add_child(_row("مستوى الخصوم", _seg(["easy", "normal", "hard"], ["سهل", "عادي", "صعب"], "difficulty")))
			vb.add_child(_row("طريقة التحكم", _seg(["touch", "kbm"], ["أزرار الشاشة", "كيبورد وماوس"], "controls")))
			vb.add_child(_row("جودة الرسوميات", _seg(["low", "medium", "high"], ["منخفضة", "متوسطة", "عالية"], "quality")))
			var sl := HSlider.new()
			sl.min_value = 0.3
			sl.max_value = 3.0
			sl.step = 0.1
			sl.value = float(Game.settings.sensitivity)
			sl.custom_minimum_size = Vector2(220, 30)
			sl.value_changed.connect(func(v): Game.settings.sensitivity = v)
			vb.add_child(_row("حساسية النظر", sl))
			var snd := CheckButton.new()
			snd.button_pressed = bool(Game.settings.sound)
			snd.toggled.connect(func(v): Game.settings.sound = v)
			vb.add_child(_row("الصوت", snd))
	var back := _button("رجوع", _close_panel, Vector2(0, 46), _style(Color("f2a900"), 6))
	back.add_theme_color_override("font_color", Color("141414"))
	vb.add_child(back)
	ui.add_child(pc)
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel = pc

func _close_panel() -> void:
	Game.save_data()
	if panel: panel.queue_free()
	panel = null
	_refresh()

func _row(text: String, ctrl: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var l := _label(text, 16, Color(0.75, 0.8, 0.86))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	hb.add_child(ctrl)
	return hb

func _seg(values: Array, names: Array, key: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	for i in values.size():
		var v: String = values[i]
		var on: bool = Game.settings[key] == v
		var b := _button(names[i], func(): Game.settings[key] = v; Game.save_data(); _open("settings"), Vector2(0, 38), _style(Color("f2a900") if on else Color(1, 1, 1, 0.06), 4), 15)
		if on: b.add_theme_color_override("font_color", Color("141414"))
		hb.add_child(b)
	return hb
