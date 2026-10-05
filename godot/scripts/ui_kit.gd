class_name UiKit
extends RefCounted
## Small shared helpers for building the menus (fonts, styles, labels, buttons).

const YELLOW := Color("ffd21f")
const INK := Color("1b1300")

static var _font: Font
static var _bold: FontVariation
static var _italic: FontVariation

static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/Cairo.ttf")
	return _font

static func bold() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = font()
		_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	return _bold

## Bold and slanted, for logos.
static func italic() -> FontVariation:
	if _italic == null:
		_italic = FontVariation.new()
		_italic.base_font = font()
		_italic.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 900}
		_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
	return _italic

## Bold font with extra space between letters ("S T U D I O").
static func spaced(px: int, weight := 700) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = font()
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	f.spacing_glyph = px
	return f

static func style(bg: Color, radius := 6, border := Color(0, 0, 0, 0), border_w := 2, margin := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	return sb

static func label(text: String, size: int, col := Color.WHITE, f: Font = null, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
		l.add_theme_constant_override("outline_size", outline)
	if f: l.add_theme_font_override("font", f)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func button(text: String, cb: Callable, size := Vector2(0, 44), st: StyleBoxFlat = null, font_size := 17, col := Color.WHITE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", font_size)
	var s := st if st else style(Color(0, 0, 0, 0.55), 2)
	b.add_theme_stylebox_override("normal", s)
	var hov := s.duplicate() as StyleBoxFlat
	hov.bg_color = s.bg_color.lightened(0.12)
	b.add_theme_stylebox_override("hover", hov)
	var prs := s.duplicate() as StyleBoxFlat
	prs.bg_color = s.bg_color.darkened(0.15)
	b.add_theme_stylebox_override("pressed", prs)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, col)
	b.pressed.connect(cb)
	return b

static func yellow_button(text: String, cb: Callable, size: Vector2, font_size := 36) -> Button:
	var st := style(YELLOW, 3, Color("fff3a0"), 2)
	var b := button(text, cb, size, st, font_size, INK)
	b.add_theme_font_override("font", bold())
	return b

## Vertical gradient texture (top -> bottom), for cards and backgrounds.
static func gradient(top: Color, bottom: Color, horizontal := false) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	return t
