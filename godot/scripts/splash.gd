extends Control
## Start-up: studio splash (Zero Zone Studio × Jordan Dan Gaming Studios) with a
## progress bar, then the season loading screen, then the lobby.

const STEPS := [
	[0.0, "جاري تحميل الشخصيات"],
	[0.25, "جاري تحميل الحركات"],
	[0.45, "جاري تجهيز الأسلحة"],
	[0.7, "جاري تحميل الخريطة"],
	[0.88, "جاري تجهيز اللوبي"],
]

var progress := 0.0
var status := ""
var toast := ""
var toast_t := 0.0
var t := 0.0
var bar: Control
var _art_done := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_render_art()

func _render_art() -> void:
	if Game.key_art == null:
		Game.key_art = await KeyArt.render(self)
	_art_done = true

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0d1424")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Mode pill at the top.
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiKit.style(Color("121b2e"), 22, Color(1, 1, 1, 0.12), 1, 12))
	pill.add_child(UiKit.label("🎮 نمط اللعبة: كلاسيكي - %s" % Game.STUDIO, 14, Color(1, 1, 1, 0.85), null, 0))
	add_child(pill)
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.position.y = 30

	# The two studio logos with a divider.
	var logos := HBoxContainer.new()
	logos.add_theme_constant_override("separation", 40)
	logos.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(logos)
	logos.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	logos.grow_horizontal = Control.GROW_DIRECTION_BOTH
	logos.grow_vertical = Control.GROW_DIRECTION_BOTH
	logos.position.y -= 40

	var zz := HBoxContainer.new()
	zz.add_theme_constant_override("separation", 18)
	var zz_text := VBoxContainer.new()
	zz_text.alignment = BoxContainer.ALIGNMENT_CENTER
	zz_text.add_child(UiKit.label("ZERO ZONE", 26, Color("e8ecf4"), UiKit.spaced(5, 800), 0))
	var st := UiKit.label("S T U D I O", 13, Color("8b95a8"), UiKit.spaced(6, 500), 0)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zz_text.add_child(st)
	zz.add_child(zz_text)
	var bolt := Control.new()
	bolt.custom_minimum_size = Vector2(64, 64)
	bolt.draw.connect(func():
		var c := Vector2(32, 32)
		bolt.draw_circle(c, 30, Color("2a2214"))
		bolt.draw_arc(c, 30, 0, TAU, 48, Color("c9921e"), 2.0)
		bolt.draw_colored_polygon(PackedVector2Array([c + Vector2(4, -18), c + Vector2(-10, 3), c + Vector2(-1, 3), c + Vector2(-5, 18), c + Vector2(10, -4), c + Vector2(1, -4)]), Color("ffc23a")))
	zz.add_child(bolt)
	logos.add_child(zz)

	var div := ColorRect.new()
	div.color = Color(1, 1, 1, 0.12)
	div.custom_minimum_size = Vector2(1, 96)
	logos.add_child(div)

	var jd := VBoxContainer.new()
	jd.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 0)
	var parts := Game.STUDIO.to_upper().split(" ")
	name_row.add_child(UiKit.label(parts[0], 40, Color("f2f4f8"), UiKit.italic(), 0))
	if parts.size() > 1:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(12, 0)
		name_row.add_child(gap)
		name_row.add_child(UiKit.label(parts[1], 40, Color("4a8ff0"), UiKit.italic(), 0))
	jd.add_child(name_row)
	var gs := UiKit.label("G A M I N G  •  S T U D I O S", 13, Color("8b95a8"), UiKit.spaced(4, 500), 0)
	gs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jd.add_child(gs)
	logos.add_child(jd)

	# Progress bar, status text, graphics selector, version.
	bar = Control.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(_draw_bar)
	add_child(bar)

	var gfx := PanelContainer.new()
	gfx.add_theme_stylebox_override("panel", UiKit.style(Color("0a0f1a"), 8, Color(1, 1, 1, 0.15), 1, 8))
	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", 8)
	gh.add_child(UiKit.label("الجرافيك:", 15, Color.WHITE, UiKit.bold(), 0))
	var ob := OptionButton.new()
	for i in Game.QUALITIES.size():
		ob.add_item(Game.QUALITY_NAMES[i])
		if Game.settings.quality == Game.QUALITIES[i]: ob.select(i)
	ob.item_selected.connect(func(i): Game.settings.quality = Game.QUALITIES[i]; Game.save_data())
	ob.add_theme_font_size_override("font_size", 14)
	gh.add_child(ob)
	gfx.add_child(gh)
	add_child(gfx)
	gfx.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	gfx.grow_vertical = Control.GROW_DIRECTION_BEGIN
	gfx.position += Vector2(12, -14)

	var ver := UiKit.label(Game.VERSION, 12, Color("5b6680"), null, 0)
	add_child(ver)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.position += Vector2(-28, -42)

func _process(delta: float) -> void:
	t += delta
	var target := minf(t / 3.2, 1.0)
	if not _art_done: target = minf(target, 0.95)
	progress = move_toward(progress, target, delta * 0.8)
	for s in STEPS:
		if progress >= s[0]: status = s[1]
	if progress > 0.3 and toast == "":
		toast = "تم تحميل الشخصيات والحركات ✅ (22/22 حركة)"
		toast_t = 2.5
	toast_t -= delta
	bar.queue_redraw()
	if progress >= 1.0 and t > 3.4:
		set_process(false)
		_to_loading()

func _draw_bar() -> void:
	var sz := bar.size
	var w := 330.0
	var x0 := sz.x * 0.5 - w * 0.5
	var y := sz.y - 170.0
	var f := UiKit.font()
	bar.draw_string(f, Vector2(x0, y - 44), status + ".".repeat(int(t * 3) % 4), HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color("9aa3b5"))
	bar.draw_string(UiKit.bold(), Vector2(x0, y - 14), "%d%%" % int(progress * 100), HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color("ffc23a"))
	bar.draw_rect(Rect2(x0, y, w, 4), Color("1d2638"))
	var filled := w * progress
	var steps := 40
	for i in steps:
		var a := float(i) / steps
		if a * w > filled: break
		var col := Color("3d7be0").lerp(Color("ffc23a"), a)
		bar.draw_rect(Rect2(x0 + a * w, y, minf(w / steps + 0.5, filled - a * w), 4), col)
	bar.draw_line(Vector2(40, sz.y - 58), Vector2(sz.x - 40, sz.y - 58), Color(1, 1, 1, 0.06), 1.0)
	if toast_t > 0.0:
		var alpha := clampf(toast_t, 0.0, 1.0)
		var tw := 300.0
		var r := Rect2(sz.x * 0.5 - tw * 0.5, sz.y - 50, tw, 36)
		bar.draw_rect(r, Color(0.05, 0.07, 0.11, 0.95 * alpha))
		bar.draw_string(UiKit.bold(), Vector2(r.position.x, r.position.y + 24), toast, HORIZONTAL_ALIGNMENT_CENTER, tw, 14, Color(1, 1, 1, alpha))

func _to_loading() -> void:
	var ls := LoadingScreen.new()
	add_child(ls)
	var tw := create_tween()
	tw.tween_method(func(v): ls.set_progress(v), 0.0, 1.0, 2.2)
	await tw.finished
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
