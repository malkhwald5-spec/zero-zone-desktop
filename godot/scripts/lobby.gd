extends Node3D
## The lobby, made over after the big mobile shooters: an airfield at dusk,
## the transport plane waiting with its propellers turning behind your squad
## line-up (you in the middle, your teammates beside you, "+" where a place is
## free), runway lights, a hangar and a jeep. Over it: your profile and level,
## a side menu, money, rotating event banners, the season pass, today's
## missions, the mode card and a big start button.

var soldier: HumanModel           # you
var mates: Array = []             # teammates' models in the line-up
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
var _plates: Array = []           # [Control, slot index] name plates over the line-up

const ACCENT := Color("ffb321")
const CYAN := Color("3fd0ff")
const GLASS := Color(0.03, 0.05, 0.08, 0.62)
## Where each member of the squad stands (you first).
const SLOTS := [Vector3(0, 0, 0), Vector3(1.22, 0, -0.95), Vector3(-1.22, 0, -0.95), Vector3(2.45, 0, -1.9)]
const MATE_NAMES := ["صقر_الليل", "Falcon_IQ", "ليث", "Viper_SY", "شاهين", "Storm_MA"]

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Game.training = false
	Net.failed.connect(_on_net_failed)
	Net.roster_changed.connect(_friends_fill)
	Net.rooms_changed.connect(_friends_fill)
	_build_scene()
	_build_ui()
	if Net.active: _friends_room.call_deferred()      # back from an online match: the room again
	if not Game.last_reward.is_empty():
		# Back from a win: a cheer first.
		if Game.last_reward.get("won", false) and soldier.ap.has_animation("mx/victory"): soldier.play_action("victory", 3.0, 0.0, 1.67)
		_show_reward(Game.last_reward)
		Game.last_reward = {}
	if Game.is_integrated_gpu(): _gpu_warning()
	if Game.phone():
		# Phones: everything a little bigger (small screen, thumbs).
		get_tree().root.content_scale_factor = 1.15
	if String(Game.profile.name) == "" and not bool(Game.wallet.get("intro_done", false)): _first_run.call_deferred()
	elif Game.login_due(): _login_gift.call_deferred()

func _exit_tree() -> void:
	get_tree().root.content_scale_factor = 1.0

## The very first time: your name, then an offer of the controls guide.
func _first_run() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.06, 0.1, 0.97), 16, ACCENT, 2, 26))
	dim.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pc.add_child(v)
	v.add_child(UiKit.label("أهلاً بمنطقة الصفر! 👋", 30, ACCENT, UiKit.bold(), 0))
	# Language first (Arabic by default): English reloads the lobby in English.
	var lang_b := _small_btn("English" if Game.settings.get("lang", "ar") == "ar" else "العربية", func():
		Game.settings.lang = "en" if Game.settings.get("lang", "ar") == "ar" else "ar"
		Game.apply_lang()
		Game.save_data()
		get_tree().reload_current_scene())
	lang_b.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(lang_b)
	v.add_child(UiKit.label("شو بدك يكون اسمك باللعبة؟", 18, Color.WHITE, null, 0))
	var le := LineEdit.new()
	le.placeholder_text = "اكتب اسمك"
	le.max_length = 16
	le.custom_minimum_size = Vector2(360, 48)
	le.add_theme_font_size_override("font_size", 20)
	v.add_child(le)
	var go := UiKit.yellow_button("يلا", func():
		var nm := le.text.strip_edges()
		Game.profile.name = nm if nm != "" else "لاعب%d" % randi_range(100, 999)
		Game.wallet.intro_done = true
		Game.save_data()
		for c in v.get_children(): c.queue_free()
		v.add_child(UiKit.label("أهلاً %s! بدك تجرّب التدريب قبل أول مباراة؟" % Game.profile.name, 22, Color.WHITE, UiKit.bold(), 0))
		v.add_child(UiKit.label("دقيقتين بتتعلّم فيهم كل شي — وبتاخد 300 ذهب", 16, Color(1, 1, 1, 0.75), null, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(row)
		row.add_child(_small_btn("آه، يلا نتدرّب", func():
			dim.queue_free()
			_start_training()))
		row.add_child(_small_btn("لا، بعرف", func():
			dim.queue_free()
			_refresh()
			if Game.login_due(): _login_gift(), true, false)), Vector2(200, 52), 24)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(go)
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	le.grab_focus.call_deferred()

## The daily log-in gift: seven days in a row, today's lit, one button to take it.
func _login_gift() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.06, 0.1, 0.97), 16, ACCENT, 2, 22))
	dim.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pc.add_child(v)
	var head := UiKit.label("🎁 هدية الدخول اليومية", 28, ACCENT, UiKit.bold(), 3)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var sub := UiKit.label("ادخل كل يوم ورا بعض لتوصل لهدية اليوم السابع الكبيرة", 15, Color(1, 1, 1, 0.75), null, 0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var today := Game.login_next()
	for i in Game.LOGIN_GIFTS.size():
		var g: Array = Game.LOGIN_GIFTS[i]
		var d := i + 1
		var done := d < today
		var now := d == today
		var big := d == 7
		var tile := PanelContainer.new()
		tile.custom_minimum_size = Vector2(96, 120) if not big else Vector2(120, 120)
		tile.add_theme_stylebox_override("panel", UiKit.style(Color(1, 0.7, 0.13, 0.25) if now else (Color(1, 1, 1, 0.04) if done else Color(1, 1, 1, 0.08)), 10, ACCENT if now else Color(1, 1, 1, 0.12), 2 if now else 1, 8))
		var tv := VBoxContainer.new()
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tile.add_child(tv)
		for t2 in [["اليوم %d" % d, 13, Color(1, 1, 1, 0.7)], [("✓" if done else ("🎁" if big else "🪙")), 30, Color("7dff8a") if done else Color.WHITE],
				["%d ذهب" % int(g[0]), 15, ACCENT], [("+%d ZC" % int(g[1])) if int(g[1]) > 0 else "", 12, CYAN]]:
			var l := UiKit.label(t2[0], t2[1], t2[2], UiKit.bold(), 2)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tv.add_child(l)
		row.add_child(tile)
	var take := UiKit.yellow_button("استلم هدية اليوم", func():
		var got := Game.claim_login()
		dim.queue_free()
		_toast("🎁 +%d ذهب%s" % [int(got[0]), ("  +%d ZC" % int(got[1])) if int(got[1]) > 0 else ""])
		_refresh(), Vector2(320, 56), 24)
	take.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(take)
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	pc.scale = Vector2(0.9, 0.9)
	pc.pivot_offset = pc.size * 0.5
	pc.create_tween().tween_property(pc, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The game is running on the built-in graphics chip (very slow): say how to
## move it onto the real graphics card.
var _exit_box: Control

## Phone back button: close the open page, else ask before leaving the game.
func go_back() -> void:
	if _friends:
		_friends_close()
	elif _picker:
		_picker.queue_free()
		_picker = null
	elif _more_box:
		_more_box.queue_free()
		_more_box = null
	elif _exit_box:
		_exit_box.queue_free()
		_exit_box = null
	elif panel:
		_close_panel()
	else:
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.6)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		ui.add_child(dim)
		_exit_box = dim
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.06, 0.1, 0.97), 16, ACCENT, 2, 22))
		dim.add_child(pc)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 14)
		pc.add_child(v)
		v.add_child(UiKit.label("بدك تطلع من اللعبة؟", 24, Color.WHITE, UiKit.bold(), 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(row)
		row.add_child(_small_btn("إيه، اطلع", func():
			Game.save_data()
			get_tree().quit(), true, false))
		row.add_child(_small_btn("لا", func():
			_exit_box.queue_free()
			_exit_box = null))
		pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
		pc.grow_vertical = Control.GROW_DIRECTION_BOTH

func _gpu_warning() -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.style(Color(0.35, 0.06, 0.04, 0.94), 6, Color("ffb070"), 2, 14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	v.add_child(UiKit.label("⚠ اللعبة شغالة على كرت الشاشة المدمج: %s" % RenderingServer.get_video_adapter_name(), 17, Color("ffd34d"), UiKit.bold(), 0))
	v.add_child(UiKit.label("هاد الكرت ضعيف وبيعطي FPS قليل. خلّي الويندوز يشغّل اللعبة على كرت NVIDIA:\n1) إعدادات ويندوز ← النظام ← الشاشة ← الرسومات (Graphics)\n2) اختار ZeroZone.exe (أو استعراض وزيده) ← خيارات ← أداء عالي (High performance) ← حفظ\n3) سكّر اللعبة وافتحها من جديد", 15, Color.WHITE, null, 0))
	v.add_child(_small_btn("تمام", func(): box.queue_free()))
	ui.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH

# =====================================================================
# 3D scene: the airfield at dusk
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
	var env := Environment.new()
	# Real photographed sunset (ambientCG EveningSkyHDRI032A, CC0).
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky_photo.gdshader")
	sky_mat.set_shader_parameter("pano", load("res://assets/textures/sky_sunset.jpg"))
	sky_mat.set_shader_parameter("photo_sun", Vector2(0.499, 0.465))
	sky_mat.set_shader_parameter("energy", 0.82)
	sky_mat.set_shader_parameter("sun_boost", 1.6)
	sky_mat.set_shader_parameter("haze", Color("e9a878"))
	sky_mat.set_shader_parameter("haze_amount", 0.08)
	sky_mat.set_shader_parameter("saturation", 1.4)
	sky_mat.set_shader_parameter("deepen", 0.35)
	sky_mat.set_shader_parameter("sea_below", true)
	sky_mat.set_shader_parameter("sea_color", Color("1d3a48"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.08
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.025
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color("d99a72")
	env.fog_sun_scatter = 0.3
	env.fog_density = 0.00045
	env.fog_aerial_perspective = 0.75
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.14
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Low warm sun behind the plane, long shadows towards the camera.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffbf86")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3(-25, 8, -60), Vector3.ZERO)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("7f95d8")
	fill.light_energy = 0.4
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)
	fill.look_at_from_position(Vector3(10, 6, 20), Vector3.ZERO)
	Game.apply_quality(env, sun)
	_light_lobby(env, sun)

	# Behind the squad: the game itself (the headland, the island, the zone,
	# the plane and the chutes).
	add_child(LobbyVista.new())
	_stage()
	_dust()
	holder = Node3D.new()
	add_child(holder)
	_spawn_soldier()
	_spawn_mates()

	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.look_at_from_position(CAM_AT, CAM_LOOK)
	cam.current = true

## The lobby shows only a small corner of a world: the big-world effects
## (global illumination, screen-space reflections, volumetric fog) cost a lot
## here and show nothing, so they stay off whatever the quality preset.
func _light_lobby(env: Environment, sun: DirectionalLight3D) -> void:
	if env:
		env.sdfgi_enabled = false
		env.ssil_enabled = false
		env.ssr_enabled = false
		env.volumetric_fog_enabled = false
		env.ssao_enabled = false
	if sun:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 40.0
	var vp := get_viewport()
	vp.use_taa = false
	if vp.msaa_3d > Viewport.MSAA_2X: vp.msaa_3d = Viewport.MSAA_2X
	RenderingServer.directional_shadow_atlas_set_size(2048, true)

# Straight on, as on a character screen: you stand in the middle of the
# frame, the squad either side and behind, the island over your shoulders.
const CAM_AT := Vector3(0.0, 1.22, 4.3)
const CAM_LOOK := Vector3(0.0, 1.02, 0.0)





## Where the squad stands: a low dark platform with a glowing edge under each
## place, a spotlight on the line-up and warm and blue rim lights behind.
var _ring_mats: Array = []
func _stage() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.62
	disc.bottom_radius = 0.66
	disc.height = 0.06
	disc.radial_segments = 40
	var steel := _mat(Color("1c1f24"), 0.3, 0.0, 0.7)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.62
	ring.outer_radius = 0.65
	ring.rings = 48
	for i in SLOTS.size():
		_mesh(disc, steel, SLOTS[i] + Vector3(0, 0.03, 0))
		var rm := _mat(ACCENT if i == 0 else CYAN, 0.3, 1.4)
		_ring_mats.append(rm)
		_mesh(ring, rm, SLOTS[i] + Vector3(0, 0.07, 0))
	var spot := SpotLight3D.new()
	spot.light_color = Color("fff1dc")
	spot.light_energy = 5.0
	spot.spot_range = 12.0
	spot.spot_angle = 30.0
	spot.shadow_enabled = not Game.phone()
	add_child(spot)
	spot.look_at_from_position(Vector3(1.5, 5.5, 4.2), Vector3(0, 0.8, -0.6))
	for r in [[Vector3(-2.2, 2.2, -2.4), Color("ff8a3c"), 3.0], [Vector3(2.6, 2.4, -2.6), Color("3f8dff"), 3.0]]:
		var o := OmniLight3D.new()
		o.light_color = r[1]
		o.light_energy = r[2]
		o.omni_range = 5.0
		o.position = r[0]
		add_child(o)

## Dust motes drifting through the light.
func _dust() -> void:
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(6.0, 1.5, 3.0)
	p.position = Vector3(0, 1.5, -1.0)
	p.direction = Vector3(1, 0.2, 0)
	p.spread = 30.0
	p.gravity = Vector3(0.05, 0.02, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.2
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.02)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.85, 0.6, 0.6)
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = g
	m.albedo_texture = dot
	q.material = m
	p.mesh = q
	add_child(p)


func _spawn_soldier() -> void:
	if soldier: soldier.queue_free()
	soldier = HumanModel.new(Game.outfit_color(), Color("f2a900"), Game.pants_color(), Game.outfit_character(), Game.outfit_dyed())
	soldier.set_style(Game.outfit_style())
	soldier.set_gear(0, 0, 0)
	# As on a character screen: empty-handed, standing easy, facing you.
	soldier.idle_clip = "u_idle"
	soldier.rotation.y = PI
	holder.add_child(soldier)
	_idle_t = 0.0
	_idle_i = 0

## How many teammates the chosen mode brings.
func _mate_count() -> int:
	match Game.settings.get("mode", "solo"):
		"duo": return 1
		"squad": return 3
	return 0

## Your teammates beside you (bot characters, each with a gun on the back).
func _spawn_mates() -> void:
	for m in mates: m.queue_free()
	mates.clear()
	var guns := ["akm", "scar", "kar98"]
	for i in _mate_count():
		var who: String = ["bundeswehr", "albu", "survivor"][i % 3]
		var m := HumanModel.new(Color.from_hsv(0.3 + i * 0.2, 0.3, 0.4), Color("c84f3a"), Color.from_hsv(0.1, 0.2, 0.25), who)
		m.set_gear(1 + i % 2, 1, 1)
		m.set_weapon(guns[i])
		add_child(m)
		m.position = SLOTS[i + 1]
		m.rotation.y = PI + (0.25 if SLOTS[i + 1].x > 0.0 else -0.25)
		mates.append(m)
	for i in _ring_mats.size():
		(_ring_mats[i] as StandardMaterial3D).emission_energy_multiplier = 1.4 if i <= mates.size() else 0.25

## The character's idle in the lobby: easy stance, looking at you, now and
## then looking round.
const IDLE_STEPS := [["idle", 6.0], ["look", 4.5], ["idle", 5.0], ["look", 4.5]]
var _idle_t := 0.0
var _idle_i := 0

## The hand button: salute, dance, cheer in turn (a wave if the clips are missing).
const LOBBY_EMOTES := [["salute", 2.8], ["dance_hiphop", 4.7], ["victory", 1.7], ["dance_break", 5.0]]
var _emote_i := -1

func _emote() -> void:
	_emote_i = (_emote_i + 1) % LOBBY_EMOTES.size()
	var e: Array = LOBBY_EMOTES[_emote_i]
	if soldier.ap.has_animation("mx/" + e[0]): soldier.play_action(e[0], e[1])
	else: soldier.wave(2.2)

func _idle_director(delta: float) -> void:
	_idle_t += delta
	var step: Array = IDLE_STEPS[_idle_i]
	if _idle_t >= float(step[1]):
		_idle_t = 0.0
		_idle_i = (_idle_i + 1) % IDLE_STEPS.size()
		step = IDLE_STEPS[_idle_i]
	var k: float = _idle_t / float(step[1])
	var to_cam := soldier.global_transform.affine_inverse() * cam.global_position
	var yaw := atan2(-to_cam.x, -to_cam.z)
	var pitch := atan2(to_cam.y - 1.6, Vector2(to_cam.x, to_cam.z).length())
	if step[0] == "look":
		yaw = sin(k * TAU) * 0.9
		pitch = 0.05
	var w := minf(1.0, delta * 3.0)
	soldier.look_yaw = lerpf(soldier.look_yaw, yaw, w)
	soldier.look_pitch = lerpf(soldier.look_pitch, pitch, w)

var _relax := 1.0

func _process(delta: float) -> void:
	t += delta
	holder.rotation.y = drag_rot
	_idle_director(delta)
	soldier.set_pose("stand", 0.0, false, delta, t)
	# Arms hanging easy at the sides (not while an emote plays).
	_relax = move_toward(_relax, 0.0 if soldier.is_acting() else 1.0, delta * 3.0)
	if _relax > 0.0: soldier.relax_arms(t, smoothstep(0.0, 1.0, _relax))
	for i in mates.size():
		var m: HumanModel = mates[i]
		m.look_yaw = sin(t * 0.3 + i * 1.7) * 0.5
		m.set_pose("stand", 0.0, true, delta, t + i * 1.3)
	if panel == null:
		cam.look_at_from_position(CAM_AT + Vector3(sin(t * 0.17) * 0.12, sin(t * 0.29) * 0.04, 0), CAM_LOOK)
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
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.material = ShaderMaterial.new()
	vig.material.shader = load("res://shaders/vignette.gdshader")
	ui.add_child(vig)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# Soft night-blue shade at the top (under the title) and a deep one at the
	# bottom (under the start and the dock), the film look of the design.
	for top in [true, false]:
		var band := TextureRect.new()
		band.texture = UiKit.gradient(Color(0.03, 0.05, 0.12, 0.62) if top else Color(0, 0, 0, 0), Color(0, 0, 0, 0) if top else Color(0.01, 0.01, 0.03, 0.78))
		band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		band.stretch_mode = TextureRect.STRETCH_SCALE
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(band)
		band.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top: band.offset_bottom = 160
		else: band.offset_top = -230
	_c_top()
	_c_identity()
	_c_play()
	_c_news()
	_c_dock()
	_lineup_plates()
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
	UiKit._springy(b)
	var lbl := UiKit.label(text, 13 if icon_above else 16, Color.WHITE, UiKit.bold(), 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(lbl)
	b.set_meta("label", lbl)
	b.draw.connect(func():
		var sz := b.size
		if icon_above:
			Icons.draw(b, icon, Vector2(sz.x * 0.5, sz.y * 0.36), sz.y * 0.19, icon_col)
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

## A small coloured tag ("جديد", a count) pinned to a corner of c.
func _tag(c: Control, text: String, col: Color, at := Vector2(-8, -6)) -> Label:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.style(col, 9, Color(0, 0, 0, 0), 0, 3))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 11, Color.WHITE, UiKit.bold(), 0)
	pc.add_child(l)
	c.add_child(pc)
	pc.position = at
	return l

# ---------------------------------------------------------------- cinematic UI
## The lobby as a film still: the scene fills the screen and the words sit on
## it in clean type over soft shade. Logo and the main sections along the top,
## who you are and today's missions on the right, the mode and the big start
## bottom right, news bottom left. The pages open over it as before.

const C_DIM := Color(1, 1, 1, 0.62)
var _mode_chips := {}

## A word you can press (no box): dim, white under the mouse, accent when held.
func _txt_button(text: String, size: int, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UiKit.bold())
	b.add_theme_font_size_override("font_size", size)
	for k in ["font_color", "font_focus_color"]: b.add_theme_color_override(k, col)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus"]: b.add_theme_stylebox_override(s, empty)
	b.pressed.connect(cb)
	return b

## A rounded rectangle as a polygon (for the gradient-filled start button).
static func _round_rect(r: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [[r.position + Vector2(r.size.x - rad, rad), -PI / 2], [r.end - Vector2(rad, rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI / 2], [r.position + Vector2(rad, rad), PI]]
	for c in corners:
		for k in 7:
			var a: float = c[1] + k * (PI / 2) / 6.0
			pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	return pts

## Smoked glass with a thin gold edge: every card of the lobby.
const GOLD := Color("f2c46b")
const GOLD_DARK := Color("c8913a")
func _glass(radius := 15, margin := 12) -> StyleBoxFlat:
	var st := UiKit.style(Color(0.04, 0.08, 0.16, 0.58), radius, Color(0.95, 0.77, 0.42, 0.38), 1, margin)
	st.shadow_color = Color(0, 0, 0, 0.32)
	st.shadow_size = 14
	return st

func _glass_panel(radius := 15, margin := 12) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _glass(radius, margin))
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	return pc

## Top: the big gold title in the middle, who you are on the right (a glass
## card), money and the small icons on the left (glass pills).
func _c_top() -> void:
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -6)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t1 := UiKit.label("منطقة الصفر", 44, GOLD, UiKit.italic(), 0)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.add_theme_color_override("font_shadow_color", Color(0.25, 0.12, 0.0, 0.75))
	t1.add_theme_constant_override("shadow_offset_y", 3)
	t1.add_theme_constant_override("shadow_offset_x", 0)
	t1.add_theme_constant_override("shadow_outline_size", 8)
	t1.add_theme_color_override("font_outline_color", Color("7a4e14"))
	t1.add_theme_constant_override("outline_size", 2)
	title.add_child(t1)
	var t2 := UiKit.label("Z E R O   Z O N E", 12, Color(0.92, 0.86, 0.75, 0.85), UiKit.bold(), 3)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_child(t2)
	_anchor(title, Control.PRESET_CENTER_TOP, Vector2(0, 8))
	labels.title = t1
	# Money and the small icons (left).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_anchor(row, Control.PRESET_TOP_LEFT, Vector2(20, 22))
	var pill := Color(0.04, 0.08, 0.16, 0.58)
	var g := _icon_button("coin", "", func(): _open("shop"), Vector2(112, 36), false, pill, Color("ffd34d"), 18)
	labels.gold = g.get_meta("label")
	row.add_child(g)
	var z := _icon_button("gem", "", func(): _open("crate"), Vector2(96, 36), false, pill, Color("7fd8ff"), 18)
	labels.zc = z.get_meta("label")
	row.add_child(z)
	row.add_child(_icon_button("gear", "", func(): _open("settings"), Vector2(36, 36), false, pill, Color.WHITE, 18))
	if not Game.phone():
		row.add_child(_icon_button("expand", "", func(): _toggle_fullscreen(), Vector2(36, 36), false, pill, Color.WHITE, 18))
	var more := _icon_button("plus", "", _more_menu, Vector2(36, 36), false, pill, GOLD, 18)
	row.add_child(more)
	labels.more_btn = more
	for b in row.get_children():
		var st: StyleBoxFlat = (b as Button).get_theme_stylebox("normal")
		st.border_color = Color(0.95, 0.77, 0.42, 0.35)

## Top right: your card (rank badge as the picture, name, level and rank),
## and under it today's missions with rings, the season and your squad.
func _c_identity() -> void:
	var card := _glass_panel(18, 8)
	_anchor(card, Control.PRESET_TOP_RIGHT, Vector2(-20, 18))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)
	var rb := RankBadge.new(int(Game.stats.rp), 22.0)
	rb.custom_minimum_size = Vector2(44, 44)
	hb.add_child(rb)
	labels.rank_badge = rb
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	hb.add_child(v)
	var nb := _txt_button("", 19, Color.WHITE, func(): _open("cards"))
	nb.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(nb)
	labels.name = nb
	labels.rank = UiKit.label("", 11, GOLD, UiKit.bold(), 2)
	labels.rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(labels.rank)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(6, 0)
	hb.add_child(sp)
	hb.layout_direction = Control.LAYOUT_DIRECTION_RTL
	# Today's missions.
	var mc := _glass_panel(18, 14)
	_anchor(mc, Control.PRESET_TOP_RIGHT, Vector2(-20, 100))
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 9)
	mv.custom_minimum_size = Vector2(252, 0)
	mc.add_child(mv)
	var head := _txt_button("مهام اليوم  ›", 15, GOLD, func(): _open("missions"))
	head.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mv.add_child(head)
	labels.missions_dot = _tag(head, "", Color("e53935"), Vector2(-4, 2))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	mv.add_child(list)
	labels.mission_list = list
	var line := ColorRect.new()
	line.color = Color(0.95, 0.77, 0.42, 0.22)
	line.custom_minimum_size = Vector2(0, 1)
	mv.add_child(line)
	var pass_btn := _txt_button("", 12, GOLD, func(): _open("season"))
	pass_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mv.add_child(pass_btn)
	labels.pass_level = pass_btn
	labels.squad_line = UiKit.label("", 11, C_DIM, null, 2)
	labels.squad_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mv.add_child(labels.squad_line)

## The three missions closest to done, each with a ring that fills.
func _fill_missions() -> void:
	var mv: VBoxContainer = labels.mission_list
	for c in mv.get_children(): c.queue_free()
	var ms := _missions().filter(func(m): return not _claimed(m.id))
	ms.sort_custom(func(a, b): return float(a.cur) / a.goal > float(b.cur) / b.goal)
	for m in ms.slice(0, 3):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		hb.layout_direction = Control.LAYOUT_DIRECTION_RTL
		var k := clampf(float(m.cur) / float(m.goal), 0.0, 1.0)
		var ring := Control.new()
		ring.custom_minimum_size = Vector2(32, 32)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var done: bool = m.done
		var txt := "✓" if done else "%d/%d" % [mini(int(m.cur), int(m.goal)), int(m.goal)]
		ring.draw.connect(func():
			var c := ring.size * 0.5
			ring.draw_circle(c, 13.0, Color(0.07, 0.12, 0.23, 0.95))
			ring.draw_arc(c, 14.0, 0.0, TAU, 40, Color(1, 1, 1, 0.15), 3.0, true)
			if k > 0.0: ring.draw_arc(c, 14.0, -PI / 2.0, -PI / 2.0 + TAU * k, 40, Color("7dff8a") if done else GOLD, 3.0, true))
		var rl := UiKit.label(txt, 9 if not done else 13, Color.WHITE, UiKit.bold(), 0)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rl.set_anchors_preset(Control.PRESET_FULL_RECT)
		ring.add_child(rl)
		hb.add_child(ring)
		var tl := UiKit.label(m.text, 13, Color(1, 1, 1, 0.92), null, 3)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size = Vector2(200, 0)
		hb.add_child(tl)
		mv.add_child(hb)

## Bottom left: the mode card (tap: the quick picker), the three modes as a
## segmented row, and the start: wide, gold, glowing, a light sweeping it.
func _c_play() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(350, 0)
	_anchor(v, Control.PRESET_BOTTOM_LEFT, Vector2(20, -18))
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(350, 58)
	for k in ["normal", "focus"]: card.add_theme_stylebox_override(k, _glass(16, 10))
	var hv := _glass(16, 10)
	hv.bg_color = Color(0.08, 0.13, 0.24, 0.7)
	for k in ["hover", "pressed"]: card.add_theme_stylebox_override(k, hv)
	card.pressed.connect(_mode_picker)
	v.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", -4)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cv.offset_right = -16
	cv.offset_left = 56
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(cv)
	var m1 := UiKit.label("", 16, Color.WHITE, UiKit.bold(), 3)
	m1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cv.add_child(m1)
	var m2 := UiKit.label("", 11, Color(1, 1, 1, 0.78), null, 2)
	m2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cv.add_child(m2)
	labels.mode_title = m1
	labels.mode = m2
	card.draw.connect(func(): Icons.draw(card, "globe", Vector2(30, card.size.y * 0.5), 15.0, GOLD))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.layout_direction = Control.LAYOUT_DIRECTION_RTL
	v.add_child(chips)
	for m in MODES:
		var id: String = m[0]
		var c := UiKit.button(String(m[1]).replace("⚔ ", ""), func():
			Game.settings.mode = id
			Game.save_data()
			_refresh(), Vector2(0, 36), null, 15)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_theme_font_override("font", UiKit.bold())
		chips.add_child(c)
		_mode_chips[id] = c
	var start := Button.new()
	start.custom_minimum_size = Vector2(350, 70)
	start.focus_mode = Control.FOCUS_NONE
	start.clip_contents = true
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]: start.add_theme_stylebox_override(st, empty)
	start.pressed.connect(_start)
	start.draw.connect(func():
		var r := Rect2(Vector2.ZERO, start.size)
		var poly := _round_rect(r, 17.0)
		var cols := PackedColorArray()
		for p in poly:
			var y := p.y / maxf(r.size.y, 1.0)
			cols.append(Color("ffe2a0").lerp(GOLD, smoothstep(0.0, 0.45, y)).lerp(GOLD_DARK, smoothstep(0.45, 1.0, y)))
		start.draw_polygon(poly, cols)
		start.draw_polyline(_round_rect(Rect2(Vector2(1, 1), r.size - Vector2(2, 2)), 16.0) + PackedVector2Array([_round_rect(Rect2(Vector2(1, 1), r.size - Vector2(2, 2)), 16.0)[0]]), Color(1, 1, 1, 0.45), 1.5))
	v.add_child(start)
	var glow := Panel.new()
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0, 0, 0, 0)
	gs.shadow_color = Color(0.95, 0.77, 0.42, 0.45)
	gs.shadow_size = 24
	gs.set_corner_radius_all(17)
	glow.add_theme_stylebox_override("panel", gs)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.show_behind_parent = true
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	start.add_child(glow)
	var shine := ColorRect.new()
	shine.color = Color(1, 1, 1, 0.3)
	shine.size = Vector2(30, 140)
	shine.rotation = 0.35
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start.add_child(shine)
	labels.shine = shine
	var sl := UiKit.label("ابدأ  ◂", 36, Color("241604"), UiKit.bold(), 0)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start.add_child(sl)
	labels.start = start

## Top left under the money: what's new (the desert map), with the tips
## turning over under it; tapping it picks that map. Two small actions.
const TIPS := ["مدينة قديمة بأسوار، قلعة، واحة نخيل… وعاصفة رملية بنص المباراة", "نصيحة: اقفز فوق المدينة لغنائم أكتر بس انتبه من الزحمة",
	"راديو الصفر بيحكيلك شو عم يصير بالمباراة", "اللي قتلك بيرجع بالمباراة الجاية… وبيدوّر عليك", "برّا المنطقة الآمنة الجزيرة بتنقلب عليك",
	"المهام اليومية بتعطيك ذهب — شوفها من القائمة"]
var _tip_i := 0
var _tip_t := 0.0

func _c_news() -> void:
	var card := _glass_panel(18, 12)
	_anchor(card, Control.PRESET_TOP_LEFT, Vector2(20, 100))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	v.custom_minimum_size = Vector2(262, 0)
	card.add_child(v)
	var head := _txt_button("جديد: وادي الرمال  ›", 15, GOLD, func():
		Game.settings.map = "dunes"
		Game.save_data()
		_toast("اخترت خريطة وادي الرمال")
		_refresh())
	head.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(head)
	var pic := TextureRect.new()
	pic.texture = load("res://assets/textures/ui/art_desert.jpg")
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(262, 96)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.clip_contents = true
	var mask := Panel.new()
	mask.add_theme_stylebox_override("panel", UiKit.style(Color.WHITE, 12, Color(0, 0, 0, 0), 0, 0))
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mask.custom_minimum_size = Vector2(262, 96)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(pic)
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_child(mask)
	var tip := UiKit.label(TIPS[0], 12, Color(1, 1, 1, 0.88), null, 2)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(262, 36)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(tip)
	labels.tip = tip
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 6)
	for ic in [["hand", _emote], ["question", func(): _open("help")]]:
		var b := _icon_button(ic[0], "", ic[1], Vector2(38, 38), false, Color(0.04, 0.08, 0.16, 0.58), Color.WHITE, 19)
		icons.add_child(b)
	_anchor(icons, Control.PRESET_TOP_LEFT, Vector2(20, 336))
	var status := UiKit.label("", 10, Color(1, 1, 1, 0.42), null, 2)
	labels.status = status
	_anchor(status, Control.PRESET_CENTER_BOTTOM, Vector2(0, -4))

## Bottom right: the sections as a glass dock of icons, a red count where
## something waits.
func _c_dock() -> void:
	var dock := _glass_panel(18, 6)
	_anchor(dock, Control.PRESET_BOTTOM_RIGHT, Vector2(-20, -18))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	dock.add_child(hb)
	# (right to left on screen: added from the left end)
	for it in [["صحابك", "friends", "friends"], ["البريد", "mail", "mail"], ["صناديق", "crate", "gift"], ["إنجازات", "achievements", "crown"],
			["الموسم", "season", "trophy"], ["المتجر", "shop", "cart"], ["المخزون", "inventory", "shirt"], ["لعب", "", "home"]]:
		var key: String = it[1]
		var on := key == ""
		var b := _icon_button(it[2], it[0], func():
			if key == "friends": _friends_room()
			elif key != "": _open(key), Vector2(62, 58), true, Color(0.95, 0.77, 0.42, 0.18) if on else Color(0, 0, 0, 0), GOLD if on else Color.WHITE, 13)
		(b.get_meta("label") as Label).add_theme_font_size_override("font_size", 11)
		if on: (b.get_meta("label") as Label).add_theme_color_override("font_color", GOLD)
		hb.add_child(b)
		if key == "mail": labels.mail_dot = _tag(b, "1", Color("e53935"), Vector2(36, 2))
		if key == "achievements": labels.ach_dot = _tag(b, "", Color("e53935"), Vector2(36, 2))

var _more_box: Control

## The pages used less often, in a small menu under the top-left icons.
func _more_menu() -> void:
	if _more_box:
		_more_box.queue_free()
		_more_box = null
		return
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.style(Color(0.03, 0.05, 0.08, 0.92), 12, Color(1, 1, 1, 0.12), 1, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	for it in [["مع صحابك", "friends", "friends"], ["التدريب", "training", "trophy"], ["البريد", "mail", "mail"], ["الإنجازات", "achievements", "trophy"], ["ورشة العمل", "workshop", "wrench"], ["البطاقات والإحصائيات", "cards", "card"],
			["العشيرة", "clan", "clan"], ["الصناديق", "crate", "crate"], ["الفعاليات", "events", "trophy"], ["طريقة اللعب", "help", "tasks"]]:
		var key: String = it[1]
		var b := _icon_button(it[2], it[0], func():
			_more_box.queue_free()
			_more_box = null
			if key == "training": _start_training()
			elif key == "friends": _friends_room()
			else: _open(key), Vector2(240, 44), false, Color(0, 0, 0, 0), Color.WHITE, 8)
		v.add_child(b)
	_anchor(pc, Control.PRESET_TOP_LEFT, Vector2(28, 58))
	_more_box = pc

var _picker: Control

## Tapping the mode card: the modes and match length right there, above it
## (the full page is one more tap away).
func _mode_picker() -> void:
	if _picker:
		_picker.queue_free()
		_picker = null
		return
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.style(Color(0.03, 0.05, 0.08, 0.95), 14, ACCENT, 1, 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	v.add_child(UiKit.label("اختار الوضع", 18, ACCENT, UiKit.bold(), 0))
	var cur: String = Game.settings.get("mode", "solo")
	for m in MODES:
		var id: String = m[0]
		var on := id == cur
		var b := UiKit.button(("✓  " if on else "") + String(m[1]), func():
			Game.settings.mode = id
			Game.save_data()
			_picker.queue_free()
			_picker = null
			_refresh(), Vector2(320, 48), UiKit.style(Color(1, 0.7, 0.1, 0.25) if on else Color(1, 1, 1, 0.06), 8, ACCENT if on else Color(0, 0, 0, 0), 1, 8), 18)
		v.add_child(b)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	for L in [["classic", "كلاسيكي 25 د"], ["quick", "سريع 10 د"]]:
		var lid: String = L[0]
		var lon: bool = Game.settings.get("length", "classic") == lid
		hb.add_child(UiKit.button(L[1], func():
			Game.settings.length = lid
			Game.save_data()
			_picker.queue_free()
			_picker = null
			_refresh(), Vector2(156, 40), UiKit.style(Color(1, 0.7, 0.1, 0.25) if lon else Color(1, 1, 1, 0.06), 8, ACCENT if lon else Color(0, 0, 0, 0), 1, 6), 15))
	v.add_child(hb)
	var mb := HBoxContainer.new()
	mb.add_theme_constant_override("separation", 6)
	for mp in [["random", "عشوائية"], ["seasons", "الفصول"], ["dunes", "وادي الرمال"]]:
		var mid: String = mp[0]
		var mon: bool = Game.settings.get("map", "random") == mid
		mb.add_child(UiKit.button(mp[1], func():
			Game.settings.map = mid
			Game.save_data()
			_picker.queue_free()
			_picker = null
			_refresh(), Vector2(102, 40), UiKit.style(Color(1, 0.7, 0.1, 0.25) if mon else Color(1, 1, 1, 0.06), 8, ACCENT if mon else Color(0, 0, 0, 0), 1, 6), 14))
	v.add_child(mb)
	v.add_child(UiKit.button("كل الخيارات (الصعوبة…) ›", func():
		_picker.queue_free()
		_picker = null
		_open("mode"), Vector2(320, 36), UiKit.style(Color(0, 0, 0, 0), 6), 14, ACCENT))
	_anchor(pc, Control.PRESET_BOTTOM_LEFT, Vector2(20, -212))
	_picker = pc

## The chosen map's name for the start button ("random" says so).
func _map_label() -> String:
	var m: String = Game.settings.get("map", "random")
	return Game.map_name(m) if Game.MAPS.has(m) else "خريطة عشوائية"

## Name plates over the line-up (or "+" to bring teammates where a place is free).
func _lineup_plates() -> void:
	for p in _plates: (p[0] as Control).queue_free()
	_plates.clear()
	for i in SLOTS.size():
		var c: Control
		if i == 0 or i - 1 < mates.size():
			# A glass pill: the name, and your level or a mate's "ready".
			var pc := PanelContainer.new()
			var ps := _glass(14, 0)
			ps.content_margin_left = 12
			ps.content_margin_right = 12
			ps.content_margin_top = 1
			ps.content_margin_bottom = 2
			if i == 0: ps.border_color = GOLD
			pc.add_theme_stylebox_override("panel", ps)
			pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var v := HBoxContainer.new()
			v.add_theme_constant_override("separation", 8)
			v.layout_direction = Control.LAYOUT_DIRECTION_RTL
			pc.add_child(v)
			var nm := Game.player_name() if i == 0 else String(MATE_NAMES[(i - 1) % MATE_NAMES.size()])
			v.add_child(UiKit.label(nm, 14 if i == 0 else 12, Color.WHITE, UiKit.bold(), 0))
			v.add_child(UiKit.label(("★ %d" % Game.level()) if i == 0 else "✓", 12, GOLD if i == 0 else Color("7dff8a"), UiKit.bold(), 0))
			c = pc
		else:
			var b := Button.new()
			b.text = "+"
			b.custom_minimum_size = Vector2(54, 54)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 30)
			b.add_theme_stylebox_override("normal", UiKit.style(Color(0, 0, 0, 0.45), 27, Color(1, 1, 1, 0.5), 2, 0))
			b.add_theme_stylebox_override("hover", UiKit.style(Color(0, 0, 0, 0.6), 27, ACCENT, 2, 0))
			b.add_theme_stylebox_override("pressed", UiKit.style(Color(0, 0, 0, 0.6), 27, ACCENT, 2, 0))
			b.tooltip_text = "زميل — اختار ثنائي أو فرقة"
			b.pressed.connect(func(): _open("mode"))
			UiKit._springy(b)
			c = b
		root.add_child(c)
		root.move_child(c, 2)
		_plates.append([c, i])

func _place_plates() -> void:
	if cam == null: return
	for p in _plates:
		var c: Control = p[0]
		var i: int = p[1]
		var occupied: bool = i == 0 or i - 1 < mates.size()
		# Under each one's feet, on the front edge of the disc (an empty place: a
		# "+" over it).
		var wp: Vector3 = SLOTS[i] + (Vector3(0, -0.02, 0.8) if occupied else Vector3(0, 1.1, 0))
		var sp := cam.unproject_position(wp)
		c.position = sp - c.size * 0.5

func _toggle_fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

func _tick_ui(delta: float) -> void:
	_place_plates()
	if labels.has("start"):
		var k := 1.0 + sin(t * 2.2) * 0.012
		labels.start.scale = Vector2(k, k)
		labels.start.pivot_offset = labels.start.size * 0.5
		# The light sweeps across every few seconds.
		var sw := fmod(t, 3.2) / 0.8
		labels.shine.position = Vector2(lerpf(-80.0, 420.0, clampf(sw, 0.0, 1.0)), -30)
	if labels.has("tip"):
		_tip_t += delta
		var lt: Label = labels.tip
		lt.modulate.a = clampf(minf(_tip_t, 6.0 - _tip_t) * 2.0, 0.0, 1.0)
		if _tip_t > 6.0:
			_tip_t = 0.0
			_tip_i = (_tip_i + 1) % TIPS.size()
			lt.text = TIPS[_tip_i]
	if labels.has("status"):
		var now := Time.get_time_dict_from_system()
		var txt := "📶 عالية الدقة • الشرق الأوسط • %02d:%02d • %s" % [now.hour, now.minute, Game.VERSION]
		if labels.status.text != txt: labels.status.text = txt

const MODE_PICS := {"solo": "br", "duo": "duo", "squad": "squad"}

func _refresh() -> void:
	labels.name.text = Game.player_name()
	var ri := Game.rank_info(int(Game.stats.rp))
	labels.rank.text = "المستوى %d  •  %s" % [Game.level(), ri.name]
	labels.rank_badge.rp = int(Game.stats.rp)
	labels.gold.text = "%d" % int(Game.wallet.gold)
	labels.zc.text = "%d" % int(Game.wallet.zc)
	labels.pass_level.text = "ZERO PASS • مستوى %d من %d" % [Game.pass_level(), Game.PASS_MAX]
	var mode: String = Game.settings.get("mode", "solo")
	var n := _mate_count()
	labels.squad_line.text = "لحالك" if n == 0 else "الفريق %d/%d جاهزين" % [n + 1, n + 1]
	var d := {"easy": "سهل", "normal": "عادي", "hard": "صعب"}[Game.settings.difficulty] as String
	var quick: bool = Game.settings.get("length", "classic") == "quick"
	labels.mode_title.text = "باتل رويال • %s" % ("سريع" if quick else "كلاسيكي")
	labels.mode.text = ("%s • %s • %s" % [_map_label(), "50 لاعب" if quick else ("60 لاعب" if Game.settings.get("map", "") == "dunes" else "100 لاعب"), d])
	for id in _mode_chips:
		var on: bool = id == mode
		var c: Button = _mode_chips[id]
		var st := UiKit.style(GOLD if on else Color(1, 1, 1, 0.08), 12, Color(0, 0, 0, 0) if on else Color(1, 1, 1, 0.16), 0 if on else 1, 4)
		if on:
			st.bg_color = GOLD.lerp(GOLD_DARK, 0.25)
			st.shadow_color = Color(0.95, 0.7, 0.3, 0.35)
			st.shadow_size = 8
		for k in ["normal", "hover", "pressed"]: c.add_theme_stylebox_override(k, st)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]: c.add_theme_color_override(k, Color("1f1405") if on else Color.WHITE)
	var ready := _missions().filter(func(m): return m.done and not _claimed(m.id)).size()
	labels.missions_dot.text = str(ready)
	labels.missions_dot.get_parent().visible = ready > 0
	labels.mail_dot.get_parent().visible = not bool(Game.wallet.mail_read)
	var ach := _achievements_ready()
	labels.ach_dot.text = str(ach)
	labels.ach_dot.get_parent().visible = ach > 0
	_fill_missions()
	if mates.size() != _mate_count():
		_spawn_mates()
		_lineup_plates()

func _start() -> void:
	if _starting: return
	_starting = true
	if _picker:
		_picker.queue_free()
		_picker = null
	# Finding the match: the players filling up, as in the online games
	# (two seconds; it can be cancelled).
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.style(Color(0.03, 0.05, 0.08, 0.95), 16, ACCENT, 2, 22))
	dim.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pc.add_child(v)
	v.add_child(UiKit.label("جاري البحث عن لاعبين…", 26, Color.WHITE, UiKit.bold(), 0))
	var total := 100 if Game.settings.get("length", "classic") != "quick" else 50
	var count := UiKit.label("1 / %d" % total, 34, ACCENT, UiKit.bold(), 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(count)
	var bar := _bar(0.0, ACCENT)
	bar.custom_minimum_size = Vector2(360, 10)
	v.add_child(bar)
	var cancelled := [false]
	var cancel := _small_btn("إلغاء", func():
		cancelled[0] = true
		_starting = false
		dim.queue_free(), true, false)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(cancel)
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	var steps := 22
	for i in steps:
		await get_tree().create_timer(0.09).timeout
		if cancelled[0] or not is_inside_tree(): return
		var n := mini(total, 1 + int(float(total - 1) * ease(float(i + 1) / steps, 0.6)))
		count.text = "%d / %d" % [n, total]
		bar.value = float(n) / total * 100.0
	count.text = "تم! ✓"
	await get_tree().create_timer(0.35).timeout
	if cancelled[0] or not is_inside_tree(): return
	Game.spawn_island = true
	# A quick fade to black, then the match loads behind its loading screen.
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/world.tscn"))

var _starting := false

# ---------- Playing with friends (see Net) ----------
var _friends: Control
var _friends_box: VBoxContainer
var _ip_edit: LineEdit

## The room: open one, find one on this Wi-Fi or type its address, see who
## is in, and (the host) start.
func _friends_room() -> void:
	if _friends: return
	Net.start_finding()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	_friends = dim
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.06, 0.1, 0.97), 16, ACCENT, 2, 24))
	pc.custom_minimum_size = Vector2(620, 0)
	dim.add_child(pc)
	_friends_box = VBoxContainer.new()
	_friends_box.add_theme_constant_override("separation", 12)
	pc.add_child(_friends_box)
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	_friends_fill()

func _friends_close() -> void:
	if Net.active and not Net.in_match: Net.leave()
	Net.stop_finding()
	if _friends: _friends.queue_free()
	_friends = null
	_friends_box = null

func _friends_fill() -> void:
	if _friends_box == null or not is_instance_valid(_friends_box): return
	var typed := _ip_edit.text if _ip_edit and is_instance_valid(_ip_edit) else ""
	for c in _friends_box.get_children(): c.queue_free()
	var v := _friends_box
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UiKit.label("العب مع صحابك", 28, ACCENT, UiKit.bold(), 0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_small_btn("✕", _friends_close, true, false))
	if not Net.active:
		v.add_child(UiKit.label("كلكم على نفس الواي فاي: واحد يفتح غرفة والباقي بينضمّوا.", 16, Color(1, 1, 1, 0.8), null, 0))
		var host_b := UiKit.yellow_button("افتح غرفة", _f_host, Vector2(260, 52), 22)
		host_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(host_b)
		v.add_child(UiKit.label("الغرف القريبة:", 18, Color.WHITE, UiKit.bold(), 0))
		if Net.rooms.is_empty():
			v.add_child(UiKit.label("عم ندوّر…", 15, Color(1, 1, 1, 0.6), null, 0))
		for ip in Net.rooms:
			var r: Dictionary = Net.rooms[ip]
			var row := HBoxContainer.new()
			var l := UiKit.label("غرفة %s — %d لاعبين" % [r.name, int(r.players)], 17, Color.WHITE, null, 0)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var addr: String = ip
			row.add_child(_small_btn("انضم", _f_join.bind(addr)))
			v.add_child(row)
		var mrow := HBoxContainer.new()
		mrow.add_theme_constant_override("separation", 8)
		_ip_edit = LineEdit.new()
		_ip_edit.placeholder_text = "أو اكتب عنوان الغرفة (مثل 192.168.1.5)"
		_ip_edit.text = typed
		_ip_edit.custom_minimum_size = Vector2(380, 44)
		_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mrow.add_child(_ip_edit)
		mrow.add_child(_small_btn("انضم", func(): _f_join(_ip_edit.text)))
		v.add_child(mrow)
		return
	if Net.roster.is_empty():
		v.add_child(UiKit.label("عم نوصل للغرفة…", 18, Color.WHITE, null, 0))
	else:
		v.add_child(UiKit.label("اللاعبين بالغرفة (%d/%d):" % [Net.roster.size(), Net.MAX_PLAYERS], 18, Color.WHITE, UiKit.bold(), 0))
		for id in Net.roster:
			var nm: String = Net.roster[id].name
			v.add_child(UiKit.label(("👑 " if int(id) == 1 else "• ") + nm + ("  (إنت)" if int(id) == Net.me() else ""), 17, Color.WHITE, null, 0))
	if Net.is_host:
		var ips := Net.local_addresses()
		if not ips.is_empty():
			v.add_child(UiKit.label("عنوان غرفتك: " + ", ".join(ips), 15, Color(1, 1, 1, 0.7), null, 0))
		var go := UiKit.yellow_button("ابدأ المباراة", func(): Net.start_match(), Vector2(280, 56), 24)
		go.disabled = Net.roster.size() < 2
		go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(go)
		if Net.roster.size() < 2: v.add_child(UiKit.label("بانتظار صحابك ينضمّوا…", 15, Color(1, 1, 1, 0.6), null, 0))
	elif not Net.roster.is_empty():
		v.add_child(UiKit.label("بانتظار صاحب الغرفة يبلّش…", 16, Color(1, 1, 1, 0.7), null, 0))
	v.add_child(_small_btn("اطلع من الغرفة", _f_leave, true, false))

func _f_host() -> void:
	Net.host()
	_friends_fill()

func _f_join(address: String) -> void:
	if address.strip_edges() == "": return
	Net.join(address)
	_friends_fill()

func _f_leave() -> void:
	Net.leave()
	_friends_fill()

func _on_net_failed(text: String) -> void:
	_toast(text)
	_friends_fill()

## The end of the game's log (errors and warnings) onto the clipboard, to
## paste into a message when reporting a problem.
func _copy_log() -> void:
	var txt := FileAccess.get_file_as_string("user://logs/godot.log")
	if txt == "":
		_toast("ما في سجل لسا")
		return
	var lines := txt.split("\n")
	var tail := "\n".join(lines.slice(maxi(0, lines.size() - 300)))
	DisplayServer.clipboard_set("Zero Zone %s • %s • %s\n%s" % [ProjectSettings.get_setting("application/config/version", ""), OS.get_name(), RenderingServer.get_video_adapter_name(), tail])
	_toast("انسخ ✓ — الصقه بأي رسالة وابعته")

## The training ground: the match world with no bots, a step-by-step guide.
func _start_training() -> void:
	Game.training = true
	Game.spawn_island = false
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/world.tscn"))

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
	Game.coin_sound()
	if r.get("level_up", false):
		Game.ui_sound("level_up", 1.0, -4.0, 0.6)
		get_tree().create_timer(3.5).timeout.connect(_toast.bind("⬆ مستوى جديد في الموسم: %d" % Game.pass_level()))

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
	Game.roll_periods()
	var top10 := int(Game.stats.get("top10", 0))
	var day: Dictionary = Game.stats.day
	var wk: Dictionary = Game.stats.week
	var d := "d_" + Game.today() + "_"
	var w := "wk_" + Game.this_week() + "_"
	return [
		# Today's (new ones every day) and this week's.
		{"id": d + "play", "text": "اليوم: العب مباراتين", "cur": day.games, "goal": 2, "gold": 200, "icon": "calendar"},
		{"id": d + "kill", "text": "اليوم: اقضِ على 5 خصوم", "cur": day.kills, "goal": 5, "gold": 250, "icon": "calendar"},
		{"id": d + "top10", "text": "اليوم: خلّص بين أول 10", "cur": day.top10, "goal": 1, "gold": 300, "icon": "calendar"},
		{"id": w + "play", "text": "الأسبوع: العب 10 مباريات", "cur": wk.games, "goal": 10, "gold": 800, "icon": "trophy"},
		{"id": w + "kill", "text": "الأسبوع: اقضِ على 30 خصم", "cur": wk.kills, "goal": 30, "gold": 1000, "icon": "trophy"},
		{"id": w + "win", "text": "الأسبوع: افز بمباراتين", "cur": wk.wins, "goal": 2, "gold": 1500, "icon": "trophy"},
		{"id": "m_play1", "text": "العب مباراة واحدة", "cur": Game.stats.games, "goal": 1, "gold": 100, "icon": "globe"},
		{"id": "m_play5", "text": "العب 5 مباريات", "cur": Game.stats.games, "goal": 5, "gold": 250, "icon": "globe"},
		{"id": "m_play20", "text": "العب 20 مباراة", "cur": Game.stats.games, "goal": 20, "gold": 800, "icon": "globe"},
		{"id": "m_kill5", "text": "اقضِ على 5 خصوم", "cur": Game.stats.kills, "goal": 5, "gold": 200, "icon": "tasks"},
		{"id": "m_kill25", "text": "اقضِ على 25 خصماً", "cur": Game.stats.kills, "goal": 25, "gold": 500, "icon": "tasks"},
		{"id": "m_kill100", "text": "اقضِ على 100 خصم", "cur": Game.stats.kills, "goal": 100, "gold": 1500, "icon": "tasks"},
		{"id": "m_top10", "text": "خلّص بين أول 10 بـ 3 مباريات", "cur": top10, "goal": 3, "gold": 350, "icon": "crown"},
		{"id": "m_win1", "text": "افز بمباراة", "cur": Game.stats.wins, "goal": 1, "gold": 400, "icon": "trophy"},
		{"id": "m_win5", "text": "افز بـ 5 مباريات", "cur": Game.stats.wins, "goal": 5, "gold": 2000, "icon": "trophy"},
	].map(func(m): m.done = int(m.cur) >= int(m.goal); return m)

# =====================================================================
# Panels (full-screen pages with a header bar)
# =====================================================================
const TITLES := {
	"inventory": "المخزون", "cards": "الملف الشخصي والرتبة", "workshop": "ورشة العمل", "season": "الموسم — ZERO PASS",
	"missions": "المهام", "mail": "البريد", "clan": "العشيرة", "shop": "المتجر", "crate": "صندوق القمر الأحمر",
	"events": "الفعاليات", "achievements": "الإنجازات", "settings": "الإعدادات", "keys": "الأزرار", "mode": "اختيار الوضع", "help": "طريقة اللعب",
}

var _page := ""

func _open(which: String) -> void:
	_close_panel(false)
	_page = which
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
	var bg := TextureRect.new()
	bg.texture = UiKit.gradient(Color(0.02, 0.04, 0.08, 0.9 if side else 0.78), Color(0.01, 0.02, 0.04, 0.95 if side else 0.88))
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	if side:
		bg.anchor_left = 0.5
	page.add_child(bg)
	# Header: glass bar with a gold line under it, round back button, title, money.
	var head := ColorRect.new()
	head.color = Color(0.02, 0.03, 0.05, 0.85)
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_bottom = 60
	page.add_child(head)
	var line := ColorRect.new()
	line.color = Color(ACCENT, 0.7)
	line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	line.offset_top = 60
	line.offset_bottom = 62
	page.add_child(line)
	var back := UiKit.button("‹", func(): _close_panel(), Vector2(44, 44), UiKit.style(Color(1, 1, 1, 0.1), 22, Color(1, 1, 1, 0.3), 1, 0), 26)
	back.position = Vector2(14, 8)
	page.add_child(back)
	var title := UiKit.label(TITLES.get(which, ""), 24, Color.WHITE, UiKit.bold(), 3)
	title.position = Vector2(70, 10)
	page.add_child(title)
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 8)
	for m in [["coin", int(Game.wallet.gold)], ["gem", int(Game.wallet.zc)]]:
		var pill := _icon_button(m[0], str(m[1]), func(): pass, Vector2(118, 36), false, Color(1, 1, 1, 0.08), Color.WHITE, 18)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		money.add_child(pill)
	page.add_child(money)
	money.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	money.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	money.position += Vector2(-16, 12)
	# Body.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 76
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
		"achievements": _page_achievements(body)
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
	# Pages fade and slide in.
	page.modulate.a = 0.0
	scroll.position.y += 18.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(page, "modulate:a", 1.0, 0.18)
	tw.tween_property(scroll, "position:y", scroll.position.y - 18.0, 0.22)

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
	_outfit_grid(body, 3)

## Rarity by price: [name, top colour, bottom colour].
func _rarity(price: int) -> Array:
	if price >= 1000: return ["أسطوري", Color("c98a1c"), Color("4a2e08")]
	if price >= 500: return ["ملحمي", Color("7b3fb8"), Color("2a1240")]
	if price > 0: return ["نادر", Color("2f6fc0"), Color("0f2240")]
	return ["عادي", Color("4a5866"), Color("1c232b")]

## The wardrobe as tall cards with the outfit's portrait: rarity colours,
## price or "owned", the equipped one marked; the whole card is the button.
func _outfit_grid(body: VBoxContainer, columns: int) -> void:
	body.add_child(UiKit.label("الملابس — اضغط على البطاقة للتجهيز أو الشراء", 15, Color(1, 1, 1, 0.7), null, 0))
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	for i in Game.WARDROBE.size():
		grid.add_child(_outfit_card(i))

func _outfit_card(i: int) -> Control:
	var w: Array = Game.WARDROBE[i]
	var owned := Game.owns(i)
	var equipped := int(Game.profile.outfit) == i
	var rar := _rarity(int(w[3]))
	var card := Button.new()
	card.custom_minimum_size = Vector2(172, 262)
	card.clip_contents = true
	var st := UiKit.style(Color(0, 0, 0, 0), 10, Color("ffd34d") if equipped else Color(1, 1, 1, 0.12), 3 if equipped else 1, 0)
	for k in ["normal", "hover", "pressed", "focus"]:
		var sk := st.duplicate() as StyleBoxFlat
		if k == "hover": sk.border_color = Color(1, 1, 1, 0.6)
		card.add_theme_stylebox_override(k, sk)
	card.pressed.connect(func(): _wear_or_buy(i))
	UiKit._springy(card)
	var bg := TextureRect.new()
	bg.texture = UiKit.gradient(rar[1], rar[2])
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)
	var path := "res://assets/textures/ui/outfits/outfit_%d.png" % i
	if ResourceLoader.exists(path):
		var pic := TextureRect.new()
		pic.texture = load(path)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.offset_top = 22
		pic.offset_bottom = -58
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(pic)
	var tag := UiKit.label(rar[0], 12, Color(1, 1, 1, 0.85), UiKit.bold(), 2)
	tag.position = Vector2(8, 4)
	card.add_child(tag)
	var foot := ColorRect.new()
	foot.color = Color(0, 0, 0, 0.55)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -56
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(foot)
	var name_l := UiKit.label(w[0], 16, Color.WHITE, UiKit.bold(), 2)
	name_l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_l.offset_top = -54
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(name_l)
	var state := "✔ مُجهّز" if equipped else ("مملوك — اضغط للتجهيز" if owned else "🪙 %d" % int(w[3]))
	var st_l := UiKit.label(state, 13, Color("ffd34d") if (equipped or not owned) else Color(1, 1, 1, 0.75), null, 2)
	st_l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	st_l.offset_top = -28
	st_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(st_l)
	return card

func _wear_or_buy(i: int) -> void:
	if not Game.owns(i):
		var price := int(Game.WARDROBE[i][3])
		if int(Game.wallet.gold) < price:
			_toast("ما معك ذهب كافي — العب مباريات وخلّص المهام")
			return
		Game.wallet.gold = int(Game.wallet.gold) - price
		Game.profile.owned.append(i)
		Game.coin_sound()
		_toast("اشتريت: %s" % Game.WARDROBE[i][0])
	Game.profile.outfit = i
	Game.save_data()
	_spawn_soldier()
	_open(_page if _page in ["inventory", "shop"] else "inventory")

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
		# Levels 15 and 30: an outfit as well (the two dearest ones).
		var outfit := -1
		if n in [15, 30]:
			outfit = _pass_outfit(n)
		var c := _box_panel(Color(1, 0.82, 0.12, 0.15) if reached else Color(1, 1, 1, 0.05))
		var v := VBoxContainer.new()
		v.add_child(UiKit.label("المستوى %d" % n, 14, Color.WHITE, UiKit.bold(), 0))
		v.add_child(UiKit.label("🪙 %d%s" % [gold, ("  💎 %d" % zc) if zc > 0 else ""], 13, Color("ffd34d"), null, 0))
		if outfit >= 0: v.add_child(UiKit.label("👕 " + String(Game.WARDROBE[outfit][0]), 13, Color("c79bff"), UiKit.bold(), 0))
		var claimed := _claimed(id)
		var oi := outfit
		var btn := _small_btn("مستلم ✓" if claimed else ("استلام" if reached else "🔒"), func():
			if oi >= 0 and not Game.owns(oi): Game.profile.owned.append(oi)
			_claim(id, gold, zc)
			_open("season"), reached and not claimed)
		btn.custom_minimum_size = Vector2(130, 32)
		v.add_child(btn)
		c.add_child(v)
		grid.add_child(c)

## The outfit a season level gives: the dearest ones, one per reward level.
func _pass_outfit(n: int) -> int:
	var order := range(Game.WARDROBE.size())
	order.sort_custom(func(a, b): return int(Game.WARDROBE[a][3]) > int(Game.WARDROBE[b][3]))
	return order[0] if n == 30 else order[1]

func _page_missions(body: VBoxContainer) -> void:
	var list := _missions()
	var ready := list.filter(func(m): return m.done and not _claimed(m.id))
	var head := _box_panel(Color(1, 0.82, 0.12, 0.12))
	var hh := HBoxContainer.new()
	head.add_child(hh)
	var ht := UiKit.label(("عندك %d مهام جاهزة للاستلام!" % ready.size()) if ready.size() > 0 else "خلّص المهام واجمع الذهب — بتتحدث كل ما تلعب", 17, Color("ffd34d"), UiKit.bold(), 0)
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(ht)
	if ready.size() > 1:
		hh.add_child(_small_btn("استلم الكل", func():
			for m in ready: _claim(m.id, m.gold)
			_open("missions")))
	body.add_child(head)
	# Ready ones first, then the ones in progress, the claimed ones last.
	list.sort_custom(func(x, y): return _mission_order(x) < _mission_order(y))
	for m in list:
		body.add_child(_mission_card(m))

func _mission_order(m: Dictionary) -> int:
	if _claimed(m.id): return 2
	return 0 if m.done else 1

func _mission_card(m: Dictionary) -> Control:
	var claimed := _claimed(m.id)
	var ready: bool = m.done and not claimed
	var c := _box_panel(Color(1, 0.82, 0.12, 0.16) if ready else Color(1, 1, 1, 0.05 if not claimed else 0.025))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	c.add_child(hb)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(52, 52)
	var icon: String = m.get("icon", "tasks")
	ic.draw.connect(func():
		ic.draw_circle(Vector2(26, 26), 25, Color("ffd34d") if ready else Color(1, 1, 1, 0.1))
		Icons.draw(ic, icon, Vector2(26, 26), 13, Color("1a1a1a") if ready else Color(1, 1, 1, 0.85)))
	hb.add_child(ic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	v.add_child(UiKit.label(m.text, 17, Color.WHITE if not claimed else Color(1, 1, 1, 0.5), UiKit.bold(), 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var pr := _bar(float(m.cur) / float(m.goal), Color("ffd34d") if not claimed else Color(1, 1, 1, 0.3))
	pr.custom_minimum_size = Vector2(360, 10)
	row.add_child(pr)
	row.add_child(UiKit.label("%d / %d" % [mini(int(m.cur), int(m.goal)), m.goal], 13, Color(1, 1, 1, 0.75), null, 0))
	v.add_child(row)
	hb.add_child(v)
	var reward := UiKit.label("🪙 %d" % m.gold, 18, Color("ffd34d"), UiKit.bold(), 0)
	reward.custom_minimum_size = Vector2(90, 0)
	reward.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(reward)
	var id: String = m.id
	var gold: int = m.gold
	var back := _page
	var btn := _small_btn("مستلم ✓" if claimed else ("استلام" if m.done else "قيد التقدم"), func(): _claim(id, gold); _open(back), ready)
	btn.custom_minimum_size = Vector2(130, 44)
	hb.add_child(btn)
	return c

## Career goals with a reward each (claimed once, kept for good).
const ACHIEVEMENTS := [
	["ach_win1", "أول فوز — آخر واحد واقف", "wins", 1, 500, "trophy"],
	["ach_win5", "خمس فوزات", "wins", 5, 1500, "trophy"],
	["ach_win20", "أسطورة المنطقة — 20 فوز", "wins", 20, 5000, "trophy"],
	["ach_k10", "صياد — 10 إقصاءات", "kills", 10, 300, "tasks"],
	["ach_k100", "مقاتل — 100 إقصاء", "kills", 100, 1500, "tasks"],
	["ach_k500", "ما حدا بيوقفك — 500 إقصاء", "kills", 500, 4000, "tasks"],
	["ach_bk8", "مذبحة — 8 إقصاءات بمباراة وحدة", "best_kills", 8, 1200, "tasks"],
	["ach_head25", "عين الصقر — 25 طلقة راس", "heads", 25, 800, "globe"],
	["ach_long300", "قناص — إقصاء من 300 متر", "longest", 300, 1000, "globe"],
	["ach_top10", "دايماً بالقمة — أول 10 عشر مرات", "top10", 10, 700, "calendar"],
	["ach_games20", "لاعب ملتزم — 20 مباراة", "games", 20, 600, "calendar"],
	["ach_games100", "ابن المنطقة — 100 مباراة", "games", 100, 2500, "calendar"],
	["ach_dmg10k", "عاصفة نار — 10,000 ضرر", "dmg", 10000, 1000, "globe"],
]

## Achievements reached but not yet collected (the red count on the dock).
func _achievements_ready() -> int:
	var n := 0
	for a in ACHIEVEMENTS:
		if int(Game.stats.get(a[2], 0)) >= int(a[3]) and not _claimed(a[0]): n += 1
	return n

func _page_achievements(body: VBoxContainer) -> void:
	var list := []
	for a in ACHIEVEMENTS:
		var cur := int(Game.stats.get(a[2], 0))
		list.append({"id": a[0], "text": a[1], "cur": cur, "goal": a[3], "gold": a[4], "icon": a[5], "done": cur >= int(a[3])})
	var done := list.filter(func(m): return m.done).size()
	var head := _box_panel(Color(1, 0.82, 0.12, 0.12))
	head.add_child(UiKit.label("🏆 خلّصت %d من %d إنجاز — كل واحد إلو جائزة" % [done, list.size()], 17, Color("ffd34d"), UiKit.bold(), 0))
	body.add_child(head)
	list.sort_custom(func(x, y): return _mission_order(x) < _mission_order(y))
	for m in list:
		body.add_child(_mission_card(m))

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
	for m in [["mail_dunes", "🏜 خريطة جديدة: وادي الرمال", "مدينة قديمة بأسوار وسوق وجامع، قلعة على التلة، واحة نخيل وميناء صيادين.\nوانتبه: بنص المباراة بتهب عاصفة رملية ما بتخليك تشوف أبعد من إيدك.", 300, 20],
			["mail_season", "🌙 الموسم الجديد: ليلة القمر الأحمر", "ZERO PASS فيه 30 مستوى، وبالمستوى 15 و30 أغلى لبستين باللعبة هدية.\nوصفحة الإنجازات الجديدة بتعطيك ذهب على كل هدف بتوصلو.", 200, 10]]:
		var mc := _box_panel()
		var mv := VBoxContainer.new()
		mv.add_theme_constant_override("separation", 8)
		mc.add_child(mv)
		mv.add_child(UiKit.label(m[1], 19, Color("ffd34d"), UiKit.bold(), 0))
		mv.add_child(UiKit.label(m[2], 15, Color.WHITE, null, 0))
		var mid: String = m[0]
		var mg: int = m[3]
		var mz: int = m[4]
		var got := _claimed(mid)
		mv.add_child(_small_btn("مستلم ✓" if got else "استلام 🪙 %d  💎 %d" % [mg, mz], func(): _claim(mid, mg, mz); _open("mail"), not got))
		body.add_child(mc)

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
	_daily_deals(body)
	_outfit_grid(body, 6)

## Today's deals: three outfits you don't own at 40% off, new ones every day.
func _daily_deals(body: VBoxContainer) -> void:
	var pool := []
	for i in Game.WARDROBE.size():
		if not Game.owns(i) and int(Game.WARDROBE[i][3]) > 0: pool.append(i)
	if pool.is_empty(): return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Game.today())
	var picks := []
	while picks.size() < mini(3, pool.size()):
		var k: int = pool[rng.randi() % pool.size()]
		if not k in picks: picks.append(k)
	body.add_child(UiKit.label("🔥 عروض اليوم — خصم 40%، بتتغير كل يوم", 17, Color("ff8a4d"), UiKit.bold(), 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	for i in picks:
		var w: Array = Game.WARDROBE[i]
		var price := int(int(w[3]) * 0.6)
		var c := _box_panel(Color(1, 0.45, 0.15, 0.14))
		var v := VBoxContainer.new()
		v.add_child(UiKit.label(String(w[0]), 16, Color.WHITE, UiKit.bold(), 0))
		v.add_child(UiKit.label("🪙 %d  (بدل %d)" % [price, int(w[3])], 14, Color("ffd34d"), null, 0))
		var idx: int = i
		v.add_child(_small_btn("اشتري", func():
			if int(Game.wallet.gold) < price:
				_toast("ما معك ذهب كافي — العب مباريات وخلّص المهام")
				return
			Game.wallet.gold = int(Game.wallet.gold) - price
			Game.profile.owned.append(idx)
			Game.profile.outfit = idx
			Game.coin_sound()
			Game.save_data()
			_toast("اشتريت بخصم: %s" % Game.WARDROBE[idx][0])
			_spawn_soldier()
			_open("shop")))
		c.add_child(v)
		row.add_child(c)

func _page_crate(body: VBoxContainer) -> void:
	var c := _box_panel(Color(0.55, 0.12, 0.22, 0.3))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	c.add_child(hb)
	var box := Control.new()
	box.custom_minimum_size = Vector2(120, 120)
	box.draw.connect(func():
		box.draw_circle(Vector2(60, 60), 58, Color(1, 0.75, 0.2, 0.18))
		Icons.draw(box, "crate", Vector2(60, 60), 34, Color("ffd34d")))
	hb.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.label("صندوق القمر الأحمر — 🪙 150", 22, Color.WHITE, UiKit.bold(), 0))
	v.add_child(UiKit.label("40% فرصة تطلعلك ملابس ما عندك، غير هيك ذهب بين 60 و 300", 15, Color(1, 1, 1, 0.8), null, 0))
	var open_b := UiKit.yellow_button("افتح الصندوق", _open_crate, Vector2(260, 56), 24)
	open_b.disabled = int(Game.wallet.gold) < 150
	v.add_child(open_b)
	hb.add_child(v)
	body.add_child(c)
	# The diamonds (ZC, from the season pass and the daily gifts) buy the
	# better box: an outfit you don't have, for certain.
	var c2 := _box_panel(Color(0.15, 0.35, 0.6, 0.3))
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 20)
	c2.add_child(hb2)
	var gem := Control.new()
	gem.custom_minimum_size = Vector2(120, 100)
	gem.draw.connect(func():
		gem.draw_circle(Vector2(60, 50), 48, Color(0.3, 0.7, 1.0, 0.18))
		Icons.draw(gem, "gem", Vector2(60, 50), 30, Color("7fd8ff")))
	hb2.add_child(gem)
	var v2 := VBoxContainer.new()
	v2.add_theme_constant_override("separation", 8)
	v2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v2.add_child(UiKit.label("صندوق الماس — 💎 %d" % GEM_CRATE, 22, Color.WHITE, UiKit.bold(), 0))
	v2.add_child(UiKit.label("ملابس ما عندك مضمونة 100% (إذا عندك كلهم: 🪙 400). الماس بتجمعه من الموسم وهدية الدخول اليومية.", 15, Color(1, 1, 1, 0.8), null, 0))
	var gb := UiKit.yellow_button("افتح بالماس", _open_gem_crate, Vector2(260, 52), 22)
	gb.disabled = int(Game.wallet.zc) < GEM_CRATE
	v2.add_child(gb)
	hb2.add_child(v2)
	body.add_child(c2)
	var missing := []
	for i in Game.WARDROBE.size():
		if not Game.owns(i): missing.append(i)
	if missing.is_empty():
		body.add_child(UiKit.label("عندك كل الملابس! الصندوق بيعطيك ذهب بس.", 15, Color(1, 1, 1, 0.7), null, 0))
		return
	body.add_child(UiKit.label("ممكن يطلعلك:", 15, Color(1, 1, 1, 0.7), null, 0))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	body.add_child(grid)
	for i in missing: grid.add_child(_outfit_card(i))

const GEM_CRATE := 40

func _open_gem_crate() -> void:
	if int(Game.wallet.zc) < GEM_CRATE: return
	Game.wallet.zc = int(Game.wallet.zc) - GEM_CRATE
	var missing := []
	for i in Game.WARDROBE.size():
		if not Game.owns(i): missing.append(i)
	if missing.is_empty():
		Game.wallet.gold = int(Game.wallet.gold) + 400
		Game.coin_sound()
		Game.save_data()
		_open("crate")
		_reveal("طلعلك 🪙 400", null)
		return
	var i: int = missing[randi() % missing.size()]
	Game.profile.owned.append(i)
	Game.coin_sound()
	Game.save_data()
	_open("crate")
	_reveal("🎉 طلعلك: %s" % Game.WARDROBE[i][0], load("res://assets/textures/ui/outfits/outfit_%d.png" % i))

func _open_crate() -> void:
	if int(Game.wallet.gold) < 150: return
	Game.wallet.gold = int(Game.wallet.gold) - 150
	var missing := []
	for i in Game.WARDROBE.size():
		if not Game.owns(i): missing.append(i)
	if not missing.is_empty() and randf() < 0.4:
		var i: int = missing[randi() % missing.size()]
		Game.profile.owned.append(i)
		Game.coin_sound()
		Game.save_data()
		_open("crate")
		_reveal("🎉 طلعلك: %s" % Game.WARDROBE[i][0], load("res://assets/textures/ui/outfits/outfit_%d.png" % i))
	else:
		var g := randi_range(60, 300)
		Game.wallet.gold = int(Game.wallet.gold) + g
		Game.save_data()
		_open("crate")
		_reveal("طلعلك 🪙 %d" % g, null)

## The prize: a burst of light and the prize growing into view; click to close.
func _reveal(text: String, pic: Texture2D) -> void:
	var o := Button.new()
	o.flat = true
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_theme_stylebox_override("normal", UiKit.style(Color(0, 0, 0, 0.78), 0))
	o.add_theme_stylebox_override("hover", UiKit.style(Color(0, 0, 0, 0.78), 0))
	o.add_theme_stylebox_override("pressed", UiKit.style(Color(0, 0, 0, 0.78), 0))
	o.pressed.connect(o.queue_free)
	ui.add_child(o)
	var burst := Control.new()
	burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(burst)
	var spin := [0.0]
	burst.draw.connect(func():
		var c := burst.size * 0.5
		for k in 16:
			var a: float = spin[0] + k * TAU / 16.0
			burst.draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a - 0.08), sin(a - 0.08)) * 520.0, c + Vector2(cos(a + 0.08), sin(a + 0.08)) * 520.0]), Color(1, 0.8, 0.3, 0.09))
		burst.draw_circle(c, 150, Color(1, 0.8, 0.3, 0.12)))
	var tw_spin := burst.create_tween().set_loops()
	tw_spin.tween_method(func(v): spin[0] = v; burst.queue_redraw(), 0.0, TAU / 16.0, 1.2)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_child(col)
	if pic:
		var tr := TextureRect.new()
		tr.texture = pic
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(240, 320)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(tr)
	var l := UiKit.label(text, 34, Color("ffd34d"), UiKit.bold(), 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	var hint := UiKit.label("اضغط بأي مكان للمتابعة", 14, Color(1, 1, 1, 0.6), null, 2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	col.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	col.scale = Vector2(0.3, 0.3)
	col.modulate.a = 0.0
	var tw := col.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(col, "scale", Vector2.ONE, 0.45)
	tw.tween_property(col, "modulate:a", 1.0, 0.25)

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
		Game.coin_sound()
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
	_light_lobby(env, sun)

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
			var lg := _section(body, "اللغة / Language")
			lg.add_child(_cell("لغة اللعبة", _choice(["ar", "en"], ["العربية", "English"], "lang", func():
				Game.apply_lang()
				get_tree().reload_current_scene())))
			var g := _section(body, "التصويب والإطلاق")
			g.add_child(_cell("مساعدة التصويب", _onoff("aim_assist")))
			g.add_child(_cell("القناصات والقوس: الإطلاق", _choice(["tap", "release"], ["ضغطة", "عند الإفلات"], "bolt_fire")))
			g.add_child(_cell("الشوزن: الإطلاق", _choice(["tap", "release"], ["ضغطة", "عند الإفلات"], "shotgun_fire")))
			g.add_child(_cell("زر المنظار", _choice(["tap", "hold", "mixed"], ["ضغطة", "مطوّل", "مختلط"], "scope_mode")))
			g.add_child(_cell("أزرار الميلان (الشاشة)", _choice(["tap", "hold"], ["ضغطة", "مطوّل"], "lean_mode")))
			g = _section(body, "أثناء اللعب")
			g.add_child(_cell("زر الإطلاق اليسار", _choice(["always", "scope", "off"], ["دائماً", "مع المنظار", "مخفي"], "left_fire")))
			g.add_child(_cell("تنبيه العلاج", _onoff("heal_prompt")))
			g.add_child(_cell("فتح الأبواب تلقائياً", _onoff("auto_door")))
			g.add_child(_cell("لون الإصابة", _choice(["red", "green"], ["أحمر", "أخضر"], "hit_color")))
			g.add_child(_cell("إظهار عدد الإطارات (FPS)", _onoff("show_fps")))
			g = _section(body, "المباراة")
			g.add_child(_cell("مستوى الخصوم", _choice(["easy", "normal", "hard"], ["سهل", "عادي", "صعب"], "difficulty")))
			g.add_child(_cell("الطقس", _choice(["random", "clear", "rain", "sunset", "fog"], ["عشوائي", "صافي", "مطر", "غروب", "ضباب"], "weather")))
			g = _section(body, "المساعدة")
			g.add_child(_cell("صار عندك خلل؟ انسخ سجل اللعبة وابعته", _small_btn("نسخ السجل", _copy_log)))
			body.add_child(_row("", _small_btn("الخروج من اللعبة", func(): get_tree().quit(), true, false)))
		"graphics":
			var g := _section(body, "الجودة")
			g.add_child(_cell("الرسوميات", _choice(Game.QUALITIES, Game.QUALITY_NAMES, "quality", _apply_gfx)))
			g.add_child(_cell("عدد الإطارات", _choice(Game.FPS_OPTIONS, Game.FPS_OPTIONS.map(func(f): return str(f)), "fps", func(): Game.apply_fps())))
			g.add_child(_cell("وضع اللابتوب (أسرع)", _onoff("laptop", _apply_gfx)))
			g.add_child(_cell("وضع الأجهزة الضعيفة (أسرع شي)", _onoff("lite", _apply_gfx)))
			g.add_child(_cell("دقة الرسم (أقل = أسرع)", _slider("render_scale", 0.45 if Game.phone() else 0.7, 1.0, 0.05, 1.0, _pct, _apply_gfx)))
			g.add_child(_cell("السطوع", _slider("brightness", 0.7, 1.4, 0.05, 1.0, _pct, _apply_gfx)))
			g.add_child(_cell("ضبط تلقائي للأداء (يخفف لما اللعبة تعلّق)", _onoff("auto_perf")))
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

## Choosing how to play: three big cards (solo, duo, squad) with a
## picture each, then how long and how hard.
const MODES := [
	["solo", "فردي", "100 لاعب، كل واحد لحاله. آخر واحد واقف بيربح.", "br"],
	["duo", "ثنائي", "إنت وزميل من الكمبيوتر بتنزلوا سوا وبترفعوا بعض.", "duo"],
	["squad", "فرقة", "فرقة من 4: بتنطّوا سوا، بتقاتلوا سوا، بترفعوا بعض.", "squad"],
]

func _page_mode(body: VBoxContainer) -> void:
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	body.add_child(cards)
	for m in MODES:
		var id: String = m[0]
		var on: bool = Game.settings.get("mode", "solo") == id
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 300)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.clip_contents = true
		var st := UiKit.style(Color(0.05, 0.07, 0.1, 0.9), 12, ACCENT if on else Color(1, 1, 1, 0.15), 3 if on else 1, 0)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", UiKit.style(Color(0.08, 0.1, 0.14, 0.95), 12, ACCENT, 2, 0))
		b.add_theme_stylebox_override("pressed", st)
		b.pressed.connect(func():
			Game.settings.mode = id
			Game.save_data()
			_open("mode"))
		UiKit._springy(b)
		cards.add_child(b)
		var pic := TextureRect.new()
		pic.texture = load("res://assets/textures/ui/modes/%s.jpg" % m[3])
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.set_anchors_preset(Control.PRESET_TOP_WIDE)
		pic.offset_bottom = 150
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(pic)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_top = 160
		v.offset_left = 14
		v.offset_right = -14
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		v.add_child(UiKit.label(m[1], 22, ACCENT if on else Color.WHITE, UiKit.bold(), 2))
		var d := UiKit.label(m[2], 14, Color(1, 1, 1, 0.75), null, 0)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(200, 0)
		v.add_child(d)
		if on: v.add_child(UiKit.label("✓ مختار", 15, Color("7dff8a"), UiKit.bold(), 0))
	var opts := _box_panel()
	body.add_child(opts)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 10)
	opts.add_child(ov)
	ov.add_child(_row("الخريطة", _seg(["random", "seasons", "dunes"], ["عشوائية", "جزيرة الفصول (8 كم)", "وادي الرمال (4 كم)"], "map", "mode")))
	ov.add_child(_row("طول المباراة", _seg(["classic", "quick"], ["كلاسيكي (100 لاعب، 25 دقيقة)", "سريع (50 لاعب، 10 دقايق)"], "length", "mode")))
	ov.add_child(_row("مستوى الخصوم", _seg(["easy", "normal", "hard"], ["سهل", "عادي", "صعب"], "difficulty", "mode")))
	var go := UiKit.yellow_button("تأكيد", func(): _close_panel(), Vector2(220, 52), 24)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(go)

func _page_help(body: VBoxContainer) -> void:
	body.add_child(UiKit.label("• اقفز من الطائرة فوق الجزيرة، وافتح المظلة.\n• اجمع الأسلحة والذخيرة (F أو زر «التقاط»).\n• عصا الحركة يسار — اسحبها لفوق لتثبيت الركض.\n• اسحب يمين الشاشة للنظر، وأزرار الإطلاق بتدوّر الكاميرا كمان.\n• كيبورد: WASD حركة، Shift ركض، C انحناء، Z انبطاح،\n   Space قفز ونطّ فوق الحيطان والشبابيك، R تلقيم، زر الماوس اليمين منظار،\n   Q و E ميلان، M الخريطة، B الحقيبة، Ctrl لإظهار الماوس أو إخفائه.\n   (كل الأزرار بتقدر تغيّرها من الإعدادات ← تغيير الأزرار)\n• H علاج، Y منشّط، G قنبلة (اترك الزر للرمي)، T نوع القنبلة.\n• F جنب صندوق الميت بتفتح أغراضه، وبتركب سيارة أو موتور أو قارب.\n• العب مباريات لتجمع ذهب وخبرة الموسم، واشتري ملابس من المخزون.", 17, Color.WHITE, null, 0))
