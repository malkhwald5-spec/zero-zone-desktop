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
var fx: Control            # background glow, sparks, light sweep and flash
var _intro := {}           # animated nodes
var _sweep := -1.0         # light sweep position 0..1 (-1 = none)
var _flash := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_hide_for_intro()
	_render_art()
	# Let the first frames (shader compiles, key art) pass before the intro.
	for i in 3:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	t = 0.0
	_animate_intro()

## Wraps a container child in a fixed-size slot so it can slide inside it.
func _slot(c: Control) -> Control:
	var slot := Control.new()
	slot.add_child(c)
	# The text's real size is only known once fonts apply (inside the tree).
	var fit := func(): slot.custom_minimum_size = c.get_combined_minimum_size()
	c.minimum_size_changed.connect(fit)
	slot.ready.connect(fit)
	return slot

## Opening: the bolt pops in with a shock ring, the names slide in from both
## sides and fade up, the divider grows, a light sweep crosses the logos.
func _hide_for_intro() -> void:
	(_intro.bolt as Control).scale = Vector2.ZERO
	for k in ["zz_text", "jd", "pill"]: (_intro[k] as Control).modulate.a = 0.0
	for sub in _intro.subs: (sub as Control).modulate.a = 0.0
	(_intro.div as Control).scale = Vector2(1, 0)
	bar.modulate.a = 0.0
	_started = false

var _started := false

func _animate_intro() -> void:
	_started = true
	var bolt: Control = _intro.bolt
	var zz_text: Control = _intro.zz_text
	var jd: Control = _intro.jd
	var div: Control = _intro.div
	var subs: Array = _intro.subs
	bolt.pivot_offset = Vector2(32, 32)
	bolt.scale = Vector2.ZERO
	zz_text.modulate.a = 0.0
	zz_text.position.x = -70.0
	jd.modulate.a = 0.0
	jd.position.x = 70.0
	div.pivot_offset = Vector2(0, 48)
	div.scale = Vector2(1, 0)
	for sub in subs: sub.modulate.a = 0.0
	bar.modulate.a = 0.0
	_intro.pill.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(bolt, "scale", Vector2(1.25, 1.25), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _flash = 0.5)
	tw.tween_property(bolt, "scale", Vector2.ONE, 0.18)
	tw.parallel().tween_property(div, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(zz_text, "position:x", 0.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(zz_text, "modulate:a", 1.0, 0.45)
	tw.parallel().tween_property(jd, "position:x", 0.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.12)
	tw.parallel().tween_property(jd, "modulate:a", 1.0, 0.45).set_delay(0.12)
	for sub in subs:
		tw.parallel().tween_property(sub, "modulate:a", 1.0, 0.6).set_delay(0.35)
	tw.tween_method(func(v): _sweep = v, 0.0, 1.0, 0.7).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): _sweep = -1.0)
	tw.parallel().tween_property(bar, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(_intro.pill, "modulate:a", 1.0, 0.4)

func _draw_fx() -> void:
	var sz := fx.size
	var c := sz * 0.5 + Vector2(0, -40)
	# Slow breathing glow behind the logos.
	var g := 0.5 + 0.5 * sin(t * 1.4)
	for i in 6:
		var r := 220.0 + i * 70.0
		fx.draw_circle(c, r, Color(0.25, 0.45, 0.9, 0.018 + g * 0.01))
	# Drifting sparks.
	for i in 40:
		var sd := float(i) * 12.9898
		var x := fmod(sin(sd) * 43758.5453, 1.0)
		x = absf(x) * sz.x
		var spd := 12.0 + fmod(absf(cos(sd) * 1000.0), 30.0)
		var y := sz.y - fmod(t * spd + absf(sin(sd * 3.1)) * sz.y, sz.y + 40.0)
		var a := 0.25 + 0.25 * sin(t * 2.0 + sd)
		fx.draw_circle(Vector2(x, y), 1.4 + fmod(absf(sd), 1.6), Color(1.0, 0.78, 0.3, a))
	# Shock ring when the bolt lands.
	if _flash > 0.0:
		var bolt: Control = _intro.bolt
		var bc := bolt.global_position - fx.global_position + Vector2(32, 32)
		var k := 1.0 - _flash / 0.5
		fx.draw_arc(bc, 30.0 + k * 120.0, 0, TAU, 64, Color(1.0, 0.8, 0.3, _flash * 1.4), 3.0)
		fx.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 0.9, 0.7, _flash * 0.15))

func _draw_sweep() -> void:
	if _sweep < 0.0: return
	var sw: Control = _intro.sweep
	var sz := sw.size
	var x := lerpf(-200.0, sz.x + 200.0, _sweep)
	for i in 12:
		var a := 0.06 * (1.0 - absf(i - 6) / 6.0)
		var dx := (i - 6) * 8.0
		sw.draw_colored_polygon(PackedVector2Array([Vector2(x + dx, 0), Vector2(x + dx + 8, 0), Vector2(x + dx - 92, sz.y), Vector2(x + dx - 100, sz.y)]), Color(1, 1, 1, a))

func _render_art() -> void:
	if Game.key_art == null:
		Game.key_art = await KeyArt.render(self)
	_art_done = true

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0d1424")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	fx = Control.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.draw.connect(_draw_fx)
	add_child(fx)

	# Mode pill at the top.
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiKit.style(Color("121b2e"), 22, Color(1, 1, 1, 0.12), 1, 12))
	pill.add_child(UiKit.label("🎮 نمط اللعبة: كلاسيكي - %s" % Game.STUDIO, 14, Color(1, 1, 1, 0.85), null, 0))
	add_child(pill)
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.position.y = 30
	_intro.pill = pill

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
	_intro.zz_text = zz_text
	_intro.subs = [st]
	zz.add_child(_slot(zz_text))
	var bolt := Control.new()
	bolt.custom_minimum_size = Vector2(64, 64)
	bolt.draw.connect(func():
		var c := Vector2(32, 32)
		bolt.draw_circle(c, 30, Color("2a2214"))
		bolt.draw_arc(c, 30, 0, TAU, 48, Color("c9921e"), 2.0)
		bolt.draw_colored_polygon(PackedVector2Array([c + Vector2(4, -18), c + Vector2(-10, 3), c + Vector2(-1, 3), c + Vector2(-5, 18), c + Vector2(10, -4), c + Vector2(1, -4)]), Color("ffc23a")))
	zz.add_child(bolt)
	_intro.bolt = bolt
	logos.add_child(zz)

	var div := ColorRect.new()
	div.color = Color(1, 1, 1, 0.12)
	div.custom_minimum_size = Vector2(1, 96)
	logos.add_child(div)
	_intro.div = div

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
	_intro.subs.append(gs)
	_intro.jd = jd
	logos.add_child(_slot(jd))
	# Light sweep drawn over the logos.
	var sweep := Control.new()
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.draw.connect(_draw_sweep)
	add_child(sweep)
	sweep.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sweep.size = Vector2(760, 160)
	sweep.position = -sweep.size * 0.5 + Vector2(0, -40)
	_intro.sweep = sweep
	_intro.logos = logos

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
	if not _started:
		fx.queue_redraw()
		return
	t += delta
	var target := minf(maxf(t - 1.2, 0.0) / 3.0, 1.0)     # starts after the intro
	if not _art_done: target = minf(target, 0.95)
	progress = move_toward(progress, target, delta * 0.8)
	for s in STEPS:
		if progress >= s[0]: status = s[1]
	if progress > 0.3 and toast == "":
		toast = "تم تحميل الشخصيات والحركات ✅ (22/22 حركة)"
		toast_t = 2.5
	toast_t -= delta
	_flash = maxf(_flash - delta, 0.0)
	bar.queue_redraw()
	fx.queue_redraw()
	(_intro.sweep as Control).queue_redraw()
	if progress >= 1.0 and t > 4.4:
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
	# Outro: logos push forward and fade, then the loading screen comes in.
	var logos: Control = _intro.logos
	logos.pivot_offset = logos.size * 0.5
	var out := create_tween().set_parallel(true)
	out.tween_property(logos, "scale", Vector2(1.08, 1.08), 0.45).set_ease(Tween.EASE_IN)
	out.tween_property(logos, "modulate:a", 0.0, 0.45)
	out.tween_property(bar, "modulate:a", 0.0, 0.3)
	await out.finished
	var ls := LoadingScreen.new()
	add_child(ls)
	var tw := create_tween()
	tw.tween_method(func(v): ls.set_progress(v), 0.0, 1.0, 2.2)
	await tw.finished
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
