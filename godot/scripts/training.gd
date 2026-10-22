class_name Training
extends CanvasLayer
## The training ground: the match world with no bots, no zone and no plane.
## You start on open ground and are walked through the basics one step at a
## time (move, jump, crouch, go prone, pick up a rifle and armour, shoot
## targets, aim, heal, throw a grenade, drive), each ticked off as you do it.

var world: Node
var player: Player
var step := -1
var steps: Array = []
var targets: Array = []
var marker: MeshInstance3D
var car: Vehicle
var _origin := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _right := Vector3.RIGHT
var _base := {}                  # what was true when the step began
var _done_t := -1.0              # the tick shows for a moment before the next step
var _aim_down := false
var _panel: PanelContainer
var _count: Label
var _title: Label
var _hint: Label
var _bar: ProgressBar

func _touch() -> bool:
	return Game.settings.get("controls", "kbm") == "touch"

func setup(w: Node) -> void:
	world = w
	player = w.player
	layer = 15
	_place_player()
	steps = [
		{"t": "تحرّك للعلامة", "k": "حرّك بـ %s %s %s %s ولف الكاميرا بالماوس" % [_k("move_forward"), _k("move_left"), _k("move_back"), _k("move_right")],
			"m": "حرّك عصا الحركة اليسار، ولف الكاميرا بإصبعك على يمين الشاشة", "go": _go_walk, "ok": func(): return _near(marker.global_position, 2.5)},
		{"t": "اقفز", "k": "اضغط " + _k("jump"), "m": "اضغط زر القفز (السهمين لفوق)",
			"ok": func(): return not player.is_on_floor() and player.velocity.y > 1.0},
		{"t": "انحني", "k": "اضغط " + _k("crouch"), "m": "اضغط زر الانحناء",
			"ok": func(): return player.stance == "crouch"},
		{"t": "انبطح", "k": "اضغط " + _k("prone"), "m": "اضغط زر الانبطاح",
			"ok": func(): return player.stance == "prone"},
		{"t": "التقط البندقية والذخيرة", "k": "قرّب منها واضغط %s (الذخيرة بتنلقط لحالها)" % _k("interact"), "m": "قرّب منها واضغط على اسمها اللي بيطلع ع الشاشة",
			"go": _go_rifle, "ok": func(): return player.slots.any(func(x): return x != null) and int(player.ammo["556"]) > 0},
		{"t": "البس الدرع والخوذة", "k": "قرّب واضغط %s على كل وحدة" % _k("interact"), "m": "قرّب واضغط على اسم كل وحدة",
			"go": _go_armour, "ok": func(): return int(player.gear.vest) > 0 and int(player.gear.helmet) > 0},
		{"t": "اطخ على الأهداف الثلاثة", "k": "الماوس اليسار للطخ — %s لتعبئة المخزن" % _k("reload"), "m": "زر الطخ — وزر التعبئة لما يخلص المخزن",
			"go": _go_targets, "ok": func(): return targets.filter(func(x): return x.dead).size() >= 3},
		{"t": "نشّن واصيب الهدف البعيد", "k": "الماوس اليمين للتنشين، وبعدين اطخ", "m": "زر المنظار، وبعدين اطخ",
			"go": _go_far, "ok": func(): return _aim_down},
		{"t": "عالج حالك", "k": "التقط الضمادات واضغط " + _k("heal"), "m": "التقط الضمادات واضغط زر العلاج (+)",
			"go": _go_heal, "ok": func(): return player.health >= 60.0},
		{"t": "ارمي قنبلة", "k": "اضغط %s، صوّب، واضغط الماوس اليسار للرمي" % _k("throw"), "m": "اضغط زر القنبلة، صوّب، وارفع إصبعك للرمي",
			"go": _go_grenade, "ok": func(): return int(player.throwables.frag) < 2},
		{"t": "اركب السيارة", "k": "قرّب منها واضغط " + _k("interact"), "m": "قرّب منها واضغط زر الركوب",
			"go": _go_car, "ok": func(): return player.state == "vehicle"},
		{"t": "سوق لقدام 40 متر", "k": "%s للبنزين، %s و %s للتوجيه، %s للنزول" % [_k("move_forward"), _k("move_left"), _k("move_right"), _k("interact")],
			"m": "عصا الحركة للسواقة، وزر النزول لما تخلص", "go": _go_drive,
			"ok": func(): return player.state == "vehicle" and is_instance_valid(car) and car.global_position.distance_to(_base.get("car_at", car.global_position)) > 40.0},
	]
	_build_ui()
	_next()

func _k(action: String) -> String:
	return Game.key_label(Game.key(action))

# ---------------------------------------------------------------- step set-ups
func _go_walk() -> void:
	_mark(_ahead(0.0, 14.0))

func _go_rifle() -> void:
	var p := _ahead(0.6, 5.0)
	world._add_pickup({"kind": "weapon", "id": "m416", "mag": 0}, p)
	world._add_pickup({"kind": "ammo", "type": "556", "amount": 120}, p + _right * 0.8)
	_mark(p)

func _go_armour() -> void:
	var p := _ahead(-0.8, 5.0)
	world._add_gear("vest", 2, -1.0, p)
	world._add_gear("helmet", 2, -1.0, p + _right * 1.2)
	_mark(p + _right * 0.6)

func _go_targets() -> void:
	_hide_mark()
	for i in 3: _target(_ahead(-4.0 + i * 4.0, 18.0 + i * 1.5))

func _go_far() -> void:
	_aim_down = false
	_target(_ahead(1.0, 45.0)).downed.connect(func(aim: bool): if aim: _aim_down = true)

func _go_heal() -> void:
	player.health = 50.0
	var p := _ahead(0.5, 3.5)
	world._add_pickup({"kind": "heal", "id": "bandage", "n": 5}, p)
	_mark(p)

func _go_grenade() -> void:
	_hide_mark()
	player.throwables.frag = 2
	player.message.emit("عطيناك قنبلتين")

func _go_car() -> void:
	car = Vehicle.new()
	car.world = world
	car.kind = "sedan"
	car.paint = Color("c9a227")
	var p := _ahead(4.0, 6.0)
	car.position = p + Vector3(0, 0.9, 0)
	car.rotation.y = atan2(_fwd.x, _fwd.z)
	world.add_child(car)
	world.vehicles.append(car)
	_mark(p)

func _go_drive() -> void:
	_hide_mark()
	_base.car_at = car.global_position if is_instance_valid(car) else player.global_position

## Open, flat ground near the first town (the map is new each time).
func _place_player() -> void:
	var isl = world.island
	var c: Vector2 = isl.towns[0].pos if not isl.towns.is_empty() else Vector2(isl.size * 0.5, isl.size * 0.5)
	var spot := Vector2(c.x + 60.0, c.y)
	for k in 600:
		var q := c + Vector2(randf_range(-400, 400), randf_range(-400, 400))
		var h0: float = isl.height_at(q.x, q.y)
		if h0 < 3.0 or world.building_at(q, 30.0) >= 0: continue
		var flat := true
		for d in [8.0, 20.0, 40.0, 55.0]:
			for dir in [Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1)]:
				var qq: Vector2 = q + dir * d
				if absf(isl.height_at(qq.x, qq.y) - h0) > 1.2 or world.building_at(qq, 4.0) >= 0: flat = false
		if flat:
			spot = q
			break
	_origin = Vector3(spot.x, world.ground_height(Vector3(spot.x, 0, spot.y)), spot.y)
	world.plane_active = false
	world.plane.visible = false
	player.jump_from_plane()
	player.global_position = _origin + Vector3(0, 0.6, 0)
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.pitch = -0.1
	player._land()
	_fwd = Vector3(0, 0, -1)
	_right = Vector3(1, 0, 0)

## A point on the ground `ahead` metres in front of where the player is
## looking now and `side` metres to the right.
func _ahead(side: float, ahead: float) -> Vector3:
	var f := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	var r := Vector3(cos(player.yaw), 0, -sin(player.yaw))
	_fwd = f
	_right = r
	var p := player.global_position + f * ahead + r * side
	return Vector3(p.x, world.ground_height(p), p.z)

func _near(p: Vector3, r: float) -> bool:
	return Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length() < r

func _target(p: Vector3) -> TrainingTarget:
	var t := TrainingTarget.new()
	world.add_child(t)
	t.global_position = p
	t.look_at(Vector3(player.global_position.x, p.y, player.global_position.z), Vector3.UP, true)
	targets.append(t)
	return t

## A glowing ring on the ground where to go next.
func _mark(p: Vector3) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.1
		tm.outer_radius = 1.35
		marker.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.75, 0.2, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color(1.0, 0.7, 0.2)
		marker.material_override = m
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(marker)
	marker.visible = true
	marker.global_position = p + Vector3(0, 0.1, 0)

func _hide_mark() -> void:
	if marker: marker.visible = false

func _next() -> void:
	step += 1
	_done_t = -1.0
	if step >= steps.size():
		_finish()
		return
	var s: Dictionary = steps[step]
	if s.has("go"): (s.go as Callable).call()
	_count.text = "التدريب  •  %d / %d" % [step + 1, steps.size()]
	_title.text = s.t
	_hint.text = s.m if _touch() else s.k
	_bar.value = float(step) / steps.size() * 100.0
	_panel.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.25)

func _process(delta: float) -> void:
	if step < 0 or step >= steps.size() or player == null: return
	if marker and marker.visible: marker.rotate_y(delta * 1.5)
	if player.state == "dead":
		# Can't really happen here, but never leave the player stuck.
		_finish()
		return
	if _done_t >= 0.0:
		_done_t -= delta
		if _done_t < 0.0: _next()
		return
	if (steps[step].ok as Callable).call():
		_title.text = "✓  " + String(steps[step].t)
		_hint.text = "ممتاز!"
		Game.ui_sound("coin", 1.2, -6.0)
		_done_t = 0.9

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.style(Color(0.03, 0.05, 0.08, 0.82), 12, Color(1.0, 0.7, 0.13, 0.7), 1, 14))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	_count = UiKit.label("", 14, Color("ffb321"), UiKit.bold(), 3)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_count)
	_title = UiKit.label("", 28, Color.WHITE, UiKit.bold(), 5)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_hint = UiKit.label("", 17, Color(1, 1, 1, 0.85), null, 4)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 520
	v.add_child(_hint)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(520, 5)
	_bar.add_theme_stylebox_override("background", UiKit.style(Color(1, 1, 1, 0.15), 3, Color(0, 0, 0, 0), 0, 0))
	_bar.add_theme_stylebox_override("fill", UiKit.style(Color("ffb321"), 3, Color(0, 0, 0, 0), 0, 0))
	v.add_child(_bar)
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.position.y = 64
	var skip := UiKit.button("تخطّي التدريب", _leave, Vector2(150, 40), UiKit.style(Color(0, 0, 0, 0.5), 8, Color(1, 1, 1, 0.25), 1, 6), 15)
	add_child(skip)
	skip.position = Vector2(14, 52)     # under the kills / players-left counters

## All done: a reward the first time, then a real match or the lobby.
func _finish() -> void:
	step = steps.size()
	_hide_mark()
	_panel.visible = false
	var first := not bool(Game.wallet.get("training_done", false))
	if first:
		Game.wallet.training_done = true
		Game.wallet.gold = int(Game.wallet.gold) + 300
		Game.coin_sound()
	Game.save_data()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.style(Color(0.04, 0.06, 0.1, 0.97), 16, Color("ffb321"), 2, 26))
	dim.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pc.add_child(v)
	v.add_child(UiKit.label("خلّصت التدريب! 🎉", 32, Color("ffb321"), UiKit.bold(), 0))
	v.add_child(UiKit.label("صرت جاهز لأول مباراة." + ("  +300 ذهب" if first else ""), 20, Color.WHITE, null, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(UiKit.yellow_button("العب مباراة", func():
		Game.training = false
		Game.spawn_island = true
		get_tree().change_scene_to_file("res://scenes/world.tscn"), Vector2(220, 56), 24))
	row.add_child(UiKit.button("رجوع للوبي", _leave, Vector2(180, 56), null, 20))
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _leave() -> void:
	Game.training = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
