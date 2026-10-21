class_name LoadingScreen
extends CanvasLayer
## Full-screen loading screen in the lobby's cinematic style: the key art
## drifting slowly behind black film bars, the map (or season) name large in
## the corner, a tip with a gold accent and a thin gold bar along the bottom.

const TIPS := [
	"افتح المظلة بدري لتطير مسافة أبعد.",
	"القاعدة العسكرية فيها أسلحة أقوى… وخصوم أكثر.",
	"الانبطاح يصعّب على الخصوم رؤيتك.",
	"اسحب عصا الحركة لفوق لتثبيت الركض.",
	"الطلقة في الرأس تضاعف الضرر.",
	"اركض وانزل لتتزحلق وتهرب من الرصاص.",
	"اسمع خطوات الخصم قبل ما تشوفه.",
]

const ART := ["res://assets/textures/ui/art_soldier.jpg", "res://assets/textures/ui/art_city.jpg", "res://assets/textures/ui/art_desert.jpg"]
const GOLD := Color("ffb321")
const BAR_TOP := 0.075     # film bars, as a share of the height
const BAR_BOTTOM := 0.13

var progress := 0.0
var shown := 0.0
var note := ""
var title := ""            # big name in the corner; the season when empty
var subtitle := ""         # small gold line above it
var art: TextureRect
var canvas: Control
var tip: String
var _t := 0.0

func _ready() -> void:
	layer = 50
	tip = TIPS[randi() % TIPS.size()]
	if title == "":
		title = Game.SEASON_NAME
		subtitle = "الموسم الأول"
	var bg := ColorRect.new()
	bg.color = Color("06080c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	art = TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = load(ART[randi() % ART.size()])
	art.modulate = Color(0.0, 0.0, 0.0)
	add_child(art)
	# Grade it: warm it slightly and darken toward the words.
	for spec in [[Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.85), false], [Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55), true]]:
		var shade := TextureRect.new()
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.texture = UiKit.gradient(spec[0], spec[1], spec[2])
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.material = ShaderMaterial.new()
	vig.material.shader = load("res://shaders/vignette.gdshader")
	add_child(vig)
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_ui)
	add_child(canvas)
	# Fade the picture up out of black.
	create_tween().tween_property(art, "modulate", Color(1.0, 0.97, 0.92), 0.8)

## Fades away over the first view of the match, then removes itself.
func fade_out(sec := 0.6) -> void:
	var tw := create_tween().set_parallel()
	for c in get_children():
		if c is CanvasItem: tw.tween_property(c, "modulate:a", 0.0, sec)
	tw.chain().tween_callback(queue_free)

func set_progress(v: float, text := "") -> void:
	progress = clampf(v, 0.0, 1.0)
	if text != "": note = text

func _process(delta: float) -> void:
	_t += delta
	shown = move_toward(shown, progress, delta * 1.5)
	# A slow push in on the art, like a camera on a dolly.
	var sz := canvas.size
	var k := 1.04 + minf(_t, 20.0) * 0.004
	art.pivot_offset = sz * Vector2(0.4, 0.45)
	art.scale = Vector2(k, k)
	canvas.queue_redraw()

func _txt(pos: Vector2, s: String, size: int, col := Color.WHITE, f: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, w := 600.0, outline := 5) -> void:
	var fnt: Font = f if f else UiKit.font()
	if outline > 0:
		canvas.draw_string_outline(fnt, pos, s, align, w, size, outline, Color(0, 0, 0, 0.5))
	canvas.draw_string(fnt, pos, s, align, w, size, col)

func _draw_ui() -> void:
	var sz := canvas.size
	var top := roundf(sz.y * BAR_TOP)
	var bot := sz.y - roundf(sz.y * BAR_BOTTOM)
	var m := maxf(28.0, sz.x * 0.035)
	# Film bars.
	canvas.draw_rect(Rect2(0, 0, sz.x, top), Color(0, 0, 0, 0.92))
	canvas.draw_rect(Rect2(0, bot, sz.x, sz.y - bot), Color(0, 0, 0, 0.92))
	# Logo in the top bar, right; "ZERO" white, "ZONE" gold.
	var lf := UiKit.spaced(6)
	var zone_w := lf.get_string_size("ZONE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var ly := top * 0.5 + 8.0
	_txt(Vector2(sz.x - m - zone_w, ly), "ZONE", 20, GOLD, lf, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	_txt(Vector2(sz.x - m - zone_w - 12 - 400, ly), "ZERO", 20, Color.WHITE, lf, HORIZONTAL_ALIGNMENT_RIGHT, 400, 0)
	# Live dot and "loading" on the left of the top bar.
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	canvas.draw_circle(Vector2(m + 5, top * 0.5), 4.5, Color(GOLD, 0.45 + 0.55 * pulse))
	_txt(Vector2(m + 18, ly - 2), "جاري التحميل", 15, Color(1, 1, 1, 0.7), UiKit.font(), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	# Title block over the art, bottom right, sliding up as it fades in.
	var a := clampf((_t - 0.25) / 0.6, 0.0, 1.0)
	var rise := (1.0 - a) * 18.0
	var tw := minf(sz.x * 0.6, 760.0)
	var tx := sz.x - m - tw
	var ty := bot - 34.0 + rise
	_txt(Vector2(tx, ty), title, 56, Color(1, 1, 1, a), UiKit.bold(), HORIZONTAL_ALIGNMENT_RIGHT, tw, 8)
	canvas.draw_rect(Rect2(sz.x - m - 54, ty - 83, 54, 3), Color(GOLD, a))
	_txt(Vector2(tx, ty - 76), subtitle, 18, Color(GOLD, a), UiKit.bold(), HORIZONTAL_ALIGNMENT_RIGHT, tw - 66, 4)
	# Tip, bottom left over the art, with a gold accent bar.
	var line := tip
	var tip_w := minf(sz.x * 0.36, 460.0)
	canvas.draw_rect(Rect2(m, bot - 78, 3, 52), Color(GOLD, a))
	_txt(Vector2(m + 14, bot - 58), "نصيحة", 15, Color(GOLD, a), UiKit.bold(), HORIZONTAL_ALIGNMENT_LEFT, tip_w, 3)
	_txt(Vector2(m + 14, bot - 32), line, 17, Color(1, 1, 1, 0.88 * a), UiKit.font(), HORIZONTAL_ALIGNMENT_LEFT, tip_w, 4)
	# Progress: a hairline across the edge of the bottom bar, gold with a glowing head.
	var bw := sz.x - m * 2.0
	var by := bot + 22.0
	canvas.draw_rect(Rect2(m, by, bw, 2), Color(1, 1, 1, 0.14))
	var fill := bw * shown
	var steps := 24
	for i in steps:
		var f0 := fill * i / steps
		var f1 := fill * (i + 1) / steps
		var c := Color("ffd560").lerp(Color("ff8a2a"), float(i) / steps)
		canvas.draw_rect(Rect2(m + f0, by - 0.5, f1 - f0 + 0.5, 3), c)
	if shown > 0.0:
		var head := Vector2(m + fill, by + 1)
		canvas.draw_circle(head, 9.0, Color(1.0, 0.6, 0.2, 0.18))
		canvas.draw_circle(head, 4.0, Color(1.0, 0.85, 0.55, 0.9))
	var pct := int(round(shown * 100.0))
	_txt(Vector2(sz.x - m - 200, by + 34), "%d%%" % pct, 18, Color.WHITE, UiKit.bold(), HORIZONTAL_ALIGNMENT_RIGHT, 200, 0)
	if note != "":
		_txt(Vector2(m, by + 34), note, 15, Color(1, 1, 1, 0.65), UiKit.font(), HORIZONTAL_ALIGNMENT_LEFT, bw - 120, 0)
	var spin := _t * 5.0
	canvas.draw_arc(Vector2(sz.x - m - 70, by + 28), 7.0, spin, spin + 4.2, 16, Color(1, 1, 1, 0.55), 2.0)
