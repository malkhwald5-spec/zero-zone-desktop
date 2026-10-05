class_name LoadingScreen
extends CanvasLayer
## Full-screen loading screen: season key art, game logo, a thin progress bar
## with percentage and date, and a helmet emblem (mobile battle royale style).

const TIPS := [
	"نصيحة: افتح المظلة بدري لتطير مسافة أبعد.",
	"نصيحة: القاعدة العسكرية فيها أسلحة أقوى… وخصوم أكثر.",
	"نصيحة: الانبطاح يصعّب على الخصوم رؤيتك.",
	"نصيحة: اسحب عصا الحركة لفوق لتثبيت الركض.",
	"نصيحة: الطلقة في الرأس تضاعف الضرر.",
]

var progress := 0.0
var shown := 0.0
var note := ""
var art: TextureRect
var canvas: Control
var tip: String

func _ready() -> void:
	layer = 50
	tip = TIPS[randi() % TIPS.size()]
	var bg := ColorRect.new()
	bg.color = Color("0b0f18")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	art = TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = Game.key_art
	add_child(art)
	if Game.key_art == null:
		_make_art()
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.texture = UiKit.gradient(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.75))
	add_child(shade)
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_ui)
	add_child(canvas)

func _make_art() -> void:
	Game.key_art = await KeyArt.render(self)
	if is_instance_valid(art): art.texture = Game.key_art

func set_progress(v: float, text := "") -> void:
	progress = clampf(v, 0.0, 1.0)
	if text != "": note = text

func _process(delta: float) -> void:
	shown = move_toward(shown, progress, delta * 1.5)
	canvas.queue_redraw()

func _txt(pos: Vector2, s: String, size: int, col := Color.WHITE, f: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, w := 600.0) -> void:
	var fnt: Font = f if f else UiKit.font()
	canvas.draw_string_outline(fnt, pos, s, align, w, size, 5, Color(0, 0, 0, 0.55))
	canvas.draw_string(fnt, pos, s, align, w, size, col)

func _draw_ui() -> void:
	var sz := canvas.size
	# Logo, top right.
	var lx := sz.x - 150.0
	canvas.draw_rect(Rect2(lx - 4, 18, 128, 48), Color(1, 1, 1, 0.92), false, 3.0)
	_txt(Vector2(lx, 50), "ZERO ZONE", 22, Color.WHITE, UiKit.bold(), HORIZONTAL_ALIGNMENT_CENTER, 120)
	_txt(Vector2(lx, 84), "BATTLE ROYALE", 11, Color.WHITE, UiKit.spaced(2), HORIZONTAL_ALIGNMENT_CENTER, 120)
	# Season title, top left.
	_txt(Vector2(28, 52), Game.SEASON_NAME, 28, Color("ffb0c0"), UiKit.bold())
	_txt(Vector2(30, 78), "الموسم الأول", 15, Color(1, 1, 1, 0.85))
	# Progress bar.
	var x0 := 126.0
	var x1 := sz.x - 150.0
	var y := sz.y - 72.0
	var pct := int(round(shown * 100.0))
	_txt(Vector2(x0, y - 10), "%d%%" % pct, 18, Color.WHITE, UiKit.bold())
	var now := Time.get_datetime_dict_from_system(true)
	var stamp := "(بالتوقيت العالمي+0) %02d:%02d %04d.%02d.%02d" % [now.hour, now.minute, now.year, now.month, now.day]
	_txt(Vector2(x0 + 58, y - 11), stamp, 14, Color(1, 1, 1, 0.85))
	canvas.draw_rect(Rect2(x0, y, x1 - x0, 4), Color(1, 1, 1, 0.22))
	canvas.draw_rect(Rect2(x0, y, (x1 - x0) * shown, 4), Color(1, 1, 1, 0.95))
	var line := note if note != "" else tip
	_txt(Vector2(x0, y + 30), line, 14, Color(1, 1, 1, 0.75))
	# Helmet emblem.
	var c := Vector2(sz.x - 82.0, sz.y - 70.0)
	canvas.draw_circle(c, 40.0, Color(1, 1, 1, 0.08))
	canvas.draw_arc(c, 40.0, 0, TAU, 48, Color(1, 1, 1, 0.85), 2.0)
	var dome := PackedVector2Array()
	for i in 17:
		var a := PI + i * PI / 16.0
		dome.append(c + Vector2(cos(a) * 20.0, sin(a) * 17.0 + 4.0))
	dome.append(c + Vector2(24, 8))
	dome.append(c + Vector2(-24, 8))
	canvas.draw_colored_polygon(dome, Color(1, 1, 1, 0.95))
	canvas.draw_rect(Rect2(c + Vector2(-18, 11), Vector2(36, 5)), Color(1, 1, 1, 0.95))
	canvas.draw_line(c + Vector2(-14, -2), c + Vector2(14, -2), Color("0b0f18"), 3.0)
	# Spinner.
	var t := Time.get_ticks_msec() / 1000.0
	canvas.draw_arc(c, 46.0, t * 4.0, t * 4.0 + 1.3, 16, Color(1, 1, 1, 0.6), 2.0)
