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

## Cinematic opening, all drawn by hand so every letter can move on its own:
##   0.0  a line of light opens across the middle (whoosh)
##   0.55 the bolt emblem slams in: flash, shock ring, screen shake, boom
##   0.8  ZERO ZONE flies in letter by letter out of the depth (trails, glitch)
##   1.5  S T U D I O types in, the studio name drops in letter by letter
##        with a bounce and sparks where each letter lands
##   2.9  a light sweep crosses the names; then they float, with a rare glitch
## Outro: the letters scatter outwards and the loading screen comes in.
const T_LINE := 0.0
const T_BOLT := 0.55
const T_ZZ := 0.8
const T_SUB := 1.5
const T_JD := 1.75
const T_SWEEP := 2.9
const T_READY := 3.4

var stage: Control
var _shake := 0.0
var _out := 0.0
var _events := {}

func _hide_for_intro() -> void:
	bar.modulate.a = 0.0
	(_intro.pill as Control).modulate.a = 0.0
	_started = false

var _started := false

func _animate_intro() -> void:
	_started = true
	var tw := create_tween()
	tw.tween_interval(T_READY)
	tw.tween_property(bar, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(_intro.pill, "modulate:a", 1.0, 0.5)

## One-off moments of the timeline: flash, shake and sound.
func _timeline_events() -> void:
	_event("whoosh", 0.05, func(): _sound("flyby_2", 0.7, -8.0))
	_event("impact", T_BOLT + 0.18, func():
		_flash = 0.6
		_shake = 1.0
		_sound("explosion", 0.62, -3.0))
	var jd_land := T_JD + (_jd_text().length() - 1) * 0.05 + 0.3
	_event("jd", jd_land, func():
		_shake = maxf(_shake, 0.35)
		_sound("far_crack_2", 0.8, -10.0))

func _event(key: String, at: float, f: Callable) -> void:
	if t >= at and not _events.has(key):
		_events[key] = true
		f.call()

func _sound(name: String, pitch: float, vol: float) -> void:
	if not Game.settings.sound or DisplayServer.get_name() == "headless": return
	var st: AudioStream = load("res://assets/sounds/%s.ogg" % name)
	if st == null: return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.pitch_scale = pitch
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _k(start: float, dur: float) -> float:
	return clampf((t - start) / dur, 0.0, 1.0)

static func _out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)

static func _out_back(x: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)

func _jd_text() -> String:
	return Game.STUDIO.to_upper()

## Draws one letter centred on `pos` with scale / rotation / colour, plus an
## optional red-cyan glitch split and motion-trail ghosts.
func _glyph(font: Font, ch: String, pos: Vector2, fs: int, col: Color, sc: float, rot: float, glitch: float, trail: float) -> void:
	var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var o := Vector2(-w * 0.5, fs * 0.36)
	if trail > 0.01:
		for g in 3:
			var gs := sc * (1.0 + trail * (0.35 + g * 0.3))
			stage.draw_set_transform(pos, rot, Vector2(gs, gs))
			stage.draw_string(font, o, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, col.a * trail * (0.22 - g * 0.06)))
	if glitch > 0.01:
		stage.draw_set_transform(pos + Vector2(glitch * 7.0, 0), rot, Vector2(sc, sc))
		stage.draw_string(font, o, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.15, 0.25, col.a * 0.55))
		stage.draw_set_transform(pos - Vector2(glitch * 7.0, 0), rot, Vector2(sc, sc))
		stage.draw_string(font, o, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.9, 1, col.a * 0.55))
	stage.draw_set_transform(pos, rot, Vector2(sc, sc))
	stage.draw_string(font, o, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## Letter centres of a word laid out from x0 with extra tracking.
func _layout(font: Font, text: String, fs: int, x0: float, track: float) -> Array:
	var xs := []
	var x := x0
	for ch in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		xs.append(x + w * 0.5)
		x += w + track
	xs.append(x - track)     # end
	return xs

func _width(font: Font, text: String, fs: int, track: float) -> float:
	var xs := _layout(font, text, fs, 0.0, track)
	return xs[-1]

## Outro scatter: pushes a point away from the centre and fades it.
func _scatter(p: Vector2, c: Vector2, i: int) -> Vector2:
	if _out <= 0.0: return p
	var d := (p - c).normalized() if p.distance_to(c) > 1.0 else Vector2(0, -1)
	d = d.rotated(sin(i * 12.9898) * 0.6)
	return p + d * _out * _out * 700.0 + Vector2(0, -_out * 60.0)

func _draw_stage() -> void:
	var sz := stage.size
	var c := sz * 0.5 + Vector2(0, -50)
	var shake := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 9.0
	var fade := 1.0 - _out
	var glitch_pulse := 0.0
	var gp := fmod(t, 2.7)
	if t > T_READY + 0.5 and gp < 0.09: glitch_pulse = 0.8
	# 1) The line of light opening across the middle.
	var kl := _out_cubic(_k(T_LINE, 0.55))
	var line_a := (1.0 - _k(T_BOLT + 0.2, 0.6)) * fade
	if kl > 0.0 and line_a > 0.0:
		var hw := sz.x * 0.42 * kl
		for g in 5:
			stage.draw_rect(Rect2(c.x - hw, c.y - 1 - g * 2, hw * 2, 2 + g * 4), Color(1.0, 0.82, 0.45, line_a * (0.5 - g * 0.09)))
		stage.draw_rect(Rect2(c.x - hw, c.y - 1, hw * 2, 2), Color(1, 1, 1, line_a))
	# 2) The bolt emblem slamming in.
	var kb := _k(T_BOLT, 0.38)
	if kb > 0.0:
		var e := _out_back(kb)
		var sc := lerpf(3.4, 1.0, e) * (1.0 + _out * 0.6)
		var rot := (1.0 - e) * -0.7 + (sin(t * 0.8) * 0.03 if kb >= 1.0 else 0.0)
		var a := minf(kb * 2.5, 1.0) * fade
		stage.draw_set_transform(c + shake, rot, Vector2(sc, sc))
		stage.draw_circle(Vector2.ZERO, 40, Color(0.16, 0.13, 0.08, a))
		stage.draw_arc(Vector2.ZERO, 40, 0, TAU, 64, Color(0.95, 0.68, 0.16, a), 2.5, true)
		stage.draw_arc(Vector2.ZERO, 46, t * 1.5, t * 1.5 + PI * 0.7, 24, Color(1, 0.8, 0.3, a * 0.6), 1.5, true)
		stage.draw_arc(Vector2.ZERO, 46, t * 1.5 + PI, t * 1.5 + PI * 1.7, 24, Color(1, 0.8, 0.3, a * 0.6), 1.5, true)
		stage.draw_colored_polygon(PackedVector2Array([Vector2(5, -24), Vector2(-13, 4), Vector2(-1, 4), Vector2(-6, 24), Vector2(13, -5), Vector2(1, -5)]), Color(1, 0.78, 0.23, a))
	# 3) ZERO ZONE: each letter flies in out of the depth.
	var f_zz := UiKit.spaced(0, 800)
	var fs_zz := 46
	var zz := "ZERO ZONE"
	var w_zz := _width(f_zz, zz, fs_zz, 6.0)
	var xs := _layout(f_zz, zz, fs_zz, c.x - 78.0 - w_zz, 6.0)
	for i in zz.length():
		var st := T_ZZ + i * 0.06
		var k := _k(st, 0.5)
		if k <= 0.0 or zz[i] == " ": continue
		var e := _out_cubic(k)
		var float_y := sin(t * 1.6 + i * 0.5) * 1.6 if t > T_READY else 0.0
		var p := Vector2(xs[i], c.y - 12.0 - (1.0 - e) * 26.0 + float_y)
		p = _scatter(p, c, i)
		var col := Color(0.93, 0.95, 0.98, minf(k * 1.8, 1.0) * fade)
		_glyph(f_zz, zz[i], p + shake, fs_zz, col, lerpf(2.8, 1.0, e) * (1.0 + _out * 0.5),
			(1.0 - e) * (0.3 if i % 2 == 0 else -0.3), maxf(1.0 - _k(st, 0.7), glitch_pulse), 1.0 - e)
	# S T U D I O under it, typed in.
	var f_sub := UiKit.spaced(0, 500)
	var sub := "STUDIO"
	var w_sub := _width(f_sub, sub, 15, 10.0)
	var xs2 := _layout(f_sub, sub, 15, c.x - 78.0 - w_sub, 10.0)
	for i in sub.length():
		var k := _k(T_SUB + i * 0.05, 0.3)
		if k <= 0.0: continue
		var p := _scatter(Vector2(xs2[i], c.y + 26.0 + (1.0 - k) * 8.0), c, i + 20)
		_glyph(f_sub, sub[i], p + shake, 15, Color(0.55, 0.6, 0.68, k * fade), 1.0, 0.0, glitch_pulse * 0.5, 0.0)
	# 4) The studio name drops in from above with a bounce.
	var jd := _jd_text()
	var split := jd.find(" ")
	var f_jd := UiKit.italic()
	var fs_jd := 50
	var xs3 := _layout(f_jd, jd, fs_jd, c.x + 78.0, 2.0)
	for i in jd.length():
		if jd[i] == " ": continue
		var st := T_JD + i * 0.05
		var k := _k(st, 0.45)
		if k <= 0.0: continue
		var e := _out_back(k)
		var float_y := sin(t * 1.6 + i * 0.5 + 1.5) * 1.6 if t > T_READY else 0.0
		var p := Vector2(xs3[i], c.y - 12.0 - (1.0 - e) * 150.0 + float_y)
		p = _scatter(p, c, i + 40)
		var blue := split >= 0 and i > split
		var col := Color("4a8ff0") if blue else Color("f2f4f8")
		col.a = minf(k * 2.0, 1.0) * fade
		_glyph(f_jd, jd[i], p + shake, fs_jd, col, 1.0 + _out * 0.5, (1.0 - e) * 0.6, glitch_pulse, 0.0)
		# Sparks where it lands.
		var since := t - st - 0.32
		if since > 0.0 and since < 0.3 and _out <= 0.0:
			var sa := 1.0 - since / 0.3
			stage.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for s in 5:
				var ang := PI + 0.3 + s * 0.6
				var r0 := 14.0 + since * 90.0
				var base := Vector2(xs3[i], c.y + 10.0)
				stage.draw_line(base + Vector2(cos(ang), sin(ang)) * r0, base + Vector2(cos(ang), sin(ang)) * (r0 + 8.0), Color(1, 0.8, 0.35, sa), 2.0)
	# GAMING • STUDIOS fades in, its tracking closing up.
	var kg := _k(T_JD + 0.6, 0.6)
	if kg > 0.0:
		var gs := "GAMING  •  STUDIOS"
		var tr := lerpf(16.0, 4.0, _out_cubic(kg))
		var w_jd: float = xs3[-1] - (c.x + 78.0)
		var w_gs := _width(f_sub, gs, 14, tr)
		var xs4 := _layout(f_sub, gs, 14, c.x + 78.0 + (w_jd - w_gs) * 0.5, tr)
		for i in gs.length():
			if gs[i] == " ": continue
			var p := _scatter(Vector2(xs4[i], c.y + 26.0), c, i + 60)
			_glyph(f_sub, gs[i], p + shake, 14, Color(0.55, 0.6, 0.68, kg * fade), 1.0, 0.0, 0.0, 0.0)
	stage.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Underline growing out of the emblem on both sides.
	var ku := _out_cubic(_k(T_SUB + 0.2, 0.7)) * fade
	if ku > 0.0:
		var L := sz.x * 0.3 * ku
		stage.draw_line(c + Vector2(-60, 52), c + Vector2(-60 - L, 52), Color(1, 0.75, 0.25, 0.5 * ku), 1.5)
		stage.draw_line(c + Vector2(60, 52), c + Vector2(60 + L, 52), Color(0.29, 0.56, 0.94, 0.5 * ku), 1.5)
	# 5) Light sweep across everything.
	var ks := _k(T_SWEEP, 0.8)
	if ks > 0.0 and ks < 1.0:
		var x := lerpf(c.x - sz.x * 0.45, c.x + sz.x * 0.45, ks)
		for i in 12:
			var a := 0.07 * (1.0 - absf(i - 6) / 6.0)
			var dx := (i - 6) * 9.0
			stage.draw_colored_polygon(PackedVector2Array([Vector2(x + dx + 60, c.y - 90), Vector2(x + dx + 69, c.y - 90),
				Vector2(x + dx - 51, c.y + 70), Vector2(x + dx - 60, c.y + 70)]), Color(1, 1, 1, a))

func _draw_fx() -> void:
	var sz := fx.size
	var c := sz * 0.5 + Vector2(0, -50)
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
	# Shock ring and flash when the emblem lands.
	if _flash > 0.0:
		var k := 1.0 - _flash / 0.6
		fx.draw_arc(c, 40.0 + k * 260.0, 0, TAU, 96, Color(1.0, 0.82, 0.35, _flash * 1.3), 4.0 * _flash + 1.0, true)
		fx.draw_arc(c, 30.0 + k * 150.0, 0, TAU, 96, Color(1, 1, 1, _flash * 0.8), 2.0, true)
		fx.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 0.95, 0.85, _flash * 0.35))
	# Vignette: darker edges keep the eye in the middle.
	for i in 10:
		var m := 18.0 * i
		fx.draw_rect(Rect2(Vector2(m, m), sz - Vector2(m, m) * 2.0), Color(0, 0, 0, 0.05), false, 18.0)

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

	# The animated names and emblem, drawn by hand (see _draw_stage).
	stage = Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.draw.connect(_draw_stage)
	add_child(stage)

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
		stage.queue_redraw()
		return
	t += delta
	_timeline_events()
	_shake = maxf(_shake - delta * 2.5, 0.0)
	stage.queue_redraw()
	var target := minf(maxf(t - T_READY, 0.0) / 2.6, 1.0)     # starts after the intro
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
	if progress >= 1.0 and t > T_READY + 2.8:
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
	# Outro: the letters scatter outwards and fade, then the loading screen.
	_sound("flyby_3", 0.8, -10.0)
	var out := create_tween().set_parallel(true)
	out.tween_method(func(v):
		_out = v
		stage.queue_redraw(), 0.0, 1.0, 0.6).set_ease(Tween.EASE_IN)
	out.tween_property(bar, "modulate:a", 0.0, 0.3)
	out.tween_property(_intro.pill, "modulate:a", 0.0, 0.3)
	await out.finished
	var ls := LoadingScreen.new()
	add_child(ls)
	var tw := create_tween()
	tw.tween_method(func(v): ls.set_progress(v), 0.0, 1.0, 2.2)
	await tw.finished
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
