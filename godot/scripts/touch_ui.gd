class_name TouchUI
extends Control
## On-screen controls (mobile battle royale layout). Multi-touch aware; with
## "emulate touch from mouse" it also works with a mouse on desktop.
##  - Left: movement joystick (drag far up to lock sprint)
##  - Right: drag anywhere free to look; buttons for fire, scope, reload, jump,
##    crouch, prone, interact; the fire buttons also turn the camera while held.

var hud: Hud
var joy_center := Vector2.ZERO
var joy_radius := 72.0
var joy_vec := Vector2.ZERO
var sprint_lock := false
var buttons: Array = []           # {act, label, icon, pos, r}
var touches := {}                 # index -> {role, last}
var font: Font
var edit := false                 # layout editor: nothing is played, every button is drawn
var selected := ""                # layout editor: the button being moved

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load("res://assets/fonts/Cairo.ttf")
	resized.connect(_layout)
	_layout()

## Default places, tidied like the mobile shooters: fire, scope and jump on
## the right, crouch and prone in the corner, reload and grenade left of the
## fire button, lean buttons above. Each can be moved and resized in the
## layout editor (settings); `id` names the button in the saved layouts.
func defaults(s: Vector2) -> Array:
	return [
		{"id": "fire", "act": "fire", "icon": "◉", "label": "", "pos": Vector2(s.x - 170, s.y - 170), "r": 60.0},
		{"id": "fire_l", "act": "fire", "icon": "◉", "label": "", "pos": Vector2(110, s.y * 0.42), "r": 38.0},
		{"id": "aim", "act": "aim", "icon": "⌖", "label": "منظار", "pos": Vector2(s.x - 75, s.y - 265), "r": 32.0},
		{"id": "jump", "act": "jump", "icon": "⤒", "label": "قفز", "pos": Vector2(s.x - 60, s.y - 155), "r": 30.0},
		{"id": "crouch", "act": "crouch", "icon": "⤓", "label": "انحناء", "pos": Vector2(s.x - 135, s.y - 58), "r": 26.0},
		{"id": "prone", "act": "prone", "icon": "▁", "label": "انبطاح", "pos": Vector2(s.x - 60, s.y - 58), "r": 26.0},
		{"id": "reload", "act": "reload", "icon": "⟳", "label": "تلقيم", "pos": Vector2(s.x - 315, s.y - 160), "r": 30.0},
		{"id": "throw", "act": "throw", "icon": "", "label": "قنبلة", "pos": Vector2(s.x - 330, s.y - 262), "r": 26.0},
		{"id": "peek_l", "act": "peek_l", "icon": "", "label": "ميلان ←", "pos": Vector2(s.x - 300, s.y - 372), "r": 24.0},
		{"id": "peek_r", "act": "peek_r", "icon": "", "label": "→ ميلان", "pos": Vector2(s.x - 195, s.y - 372), "r": 24.0},
		{"id": "bag", "act": "bag", "icon": "", "label": "الحقيبة", "pos": Vector2(40, s.y - 64), "r": 24.0},
		{"id": "heal", "act": "heal", "icon": "", "label": "علاج", "pos": Vector2(Hud.slot_rect(2, s).end.x + 38, s.y - 82), "r": 24.0},
		{"id": "boost", "act": "boost", "icon": "", "label": "منشّط", "pos": Vector2(Hud.slot_rect(2, s).end.x + 96, s.y - 82), "r": 24.0},
		{"id": "freelook", "act": "freelook", "icon": "", "label": "نظرة حرة", "pos": Vector2(s.x - 330, s.y * 0.36), "r": 26.0},
		{"id": "map", "act": "map", "icon": "⌗", "label": "الخريطة", "pos": Vector2(s.x - 36, 330), "r": 24.0},
		{"id": "emote", "act": "emote", "icon": "", "label": "رقصة", "pos": Vector2(s.x - 36, 400), "r": 22.0},
		{"id": "pause", "act": "pause", "icon": "⚙", "label": "", "pos": Vector2(s.x - 245, 34), "r": 22.0},
		{"id": "slot1", "act": "slot1", "icon": "", "label": "", "pos": Hud.slot_rect(0, s).get_center(), "r": 0.0},
		{"id": "slot2", "act": "slot2", "icon": "", "label": "", "pos": Hud.slot_rect(1, s).get_center(), "r": 0.0},
		{"id": "slot3", "act": "slot3", "icon": "", "label": "", "pos": Hud.slot_rect(2, s).get_center(), "r": 0.0},
		{"id": "interact", "act": "interact", "icon": "", "label": "", "pos": Vector2(s.x - 470, s.y * 0.55), "r": 0.0},
	]

const JOY_R := 72.0
var joy_home := Vector2.ZERO      # where the joystick rests (it can float to the thumb)

func _layout() -> void:
	var s := size if size.x > 0 else get_viewport_rect().size
	buttons = defaults(s)
	for b in buttons:
		b.base_r = b.r
		var o := Game.touch_override(b.id)
		if not o.is_empty():
			b.pos = Vector2(float(o[0]) * s.x, float(o[1]) * s.y)
			if b.r > 0.0: b.r = b.base_r * float(o[2])
	joy_home = Vector2(150, s.y - 150)
	joy_radius = JOY_R
	var jo := Game.touch_override("joy")
	if not jo.is_empty():
		joy_home = Vector2(float(jo[0]) * s.x, float(jo[1]) * s.y)
		joy_radius = JOY_R * float(jo[2])
	joy_center = joy_home

## Is this button on screen right now? (the left fire button can be off or only while aiming)
func shown(b: Dictionary) -> bool:
	if b.id == "fire_l" and not edit:
		var mode: String = Game.settings.get("left_fire", "always")
		if mode == "off": return false
		if mode == "scope" and hud and hud.world.player and not hud.world.player.aiming: return false
	return true

func _interact_label() -> String:
	var p: Player = hud.world.player
	match p.state:
		"plane": return "اقفز" if hud.world.plane_over_land() else ""
		"fall": return "افتح المظلة" if p.global_position.y < Player.PLANE_ALT - 40.0 else ""
		"ground":
			if p.knocked: return ""
			var mate = p.downed_mate_near()
			if mate: return "ارفع (اضغط مطوّل)"
			var door := p.door_target()
			if not door.is_empty(): return "سكّر الباب" if door.target > 0.5 else "افتح الباب"
			var it = hud.world.nearest_pickup(p.global_position, 2.4)
			if it: return "افتح الصندوق" if it.has_meta("crate") else "التقاط"
			return "ركوب" if hud.world.nearest_vehicle(p.global_position, 3.5) else ""
		"vehicle": return "نزول"
	return ""

func _hit_button(pos: Vector2) -> Dictionary:
	for b in buttons:
		if not shown(b): continue
		if b.act == "interact":
			if _interact_label() != "" and Rect2(b.pos - Vector2(80, 24), Vector2(160, 48)).has_point(pos): return b
		elif b.act.begins_with("slot"):
			if Hud.slot_rect(int(b.act.substr(4)) - 1, size).has_point(pos): return b
		elif pos.distance_to(b.pos) < b.r * 1.15:
			return b
	return {}

func _input(event: InputEvent) -> void:
	if edit or not visible or hud.world.player == null: return
	var p: Player = hud.world.player
	if event is InputEventScreenTouch:
		if event.pressed:
			var floating: bool = Game.settings.get("joy_float", false) and event.position.x < size.x * 0.35 and event.position.y > size.y * 0.4 \
				and _hit_button(event.position).is_empty()
			if floating and not hud.map_open and not _joy_busy():
				joy_center = event.position
			if event.position.distance_to(joy_center) < joy_radius * 1.5 and not hud.map_open and not _joy_busy():
				touches[event.index] = {"role": "joy", "last": event.position}
				sprint_lock = false
				_joy(event.position)
			else:
				var b := _hit_button(event.position)
				if not b.is_empty():
					touches[event.index] = {"role": "btn", "act": b.act, "last": event.position}
					_press(b.act, true)
				elif event.position.x > size.x * 0.3 and not hud.map_open:
					touches[event.index] = {"role": "look", "last": event.position}
			get_viewport().set_input_as_handled()
		elif touches.has(event.index):
			var t: Dictionary = touches[event.index]
			if t.role == "joy":
				if sprint_lock:
					joy_vec = Vector2(0, -1)
				else:
					joy_vec = Vector2.ZERO
					joy_center = joy_home
			elif t.role == "btn":
				_press(t.act, false)
			touches.erase(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and touches.has(event.index):
		var t: Dictionary = touches[event.index]
		if t.role == "joy":
			_joy(event.position)
		elif t.role == "look" or (t.role == "btn" and t.act in ["fire", "freelook"]):
			p.add_look(event.relative.x * 1.4, event.relative.y * 1.4)
		get_viewport().set_input_as_handled()
	p.touch_move = Vector2(joy_vec.x, -joy_vec.y)
	p.sprinting = sprint_lock or joy_vec.y < -0.92

func _joy_busy() -> bool:
	for t in touches.values():
		if t.role == "joy": return true
	return false

func _joy(pos: Vector2) -> void:
	var d := pos - joy_center
	sprint_lock = d.y < -joy_radius * 1.9 and absf(d.x) < joy_radius
	joy_vec = (d / joy_radius).limit_length(1.0)

func _press(act: String, down: bool) -> void:
	var p: Player = hud.world.player
	match act:
		"map": if down: hud.toggle_map()
		"pause": if down: hud.toggle_pause()
		"bag": if down: hud.toggle_bag()
		_: p.action(act, down)

func _process(_d: float) -> void:
	modulate.a = 1.0 if edit else clampf(float(Game.settings.get("touch_alpha", 0.8)), 0.2, 1.0)
	queue_redraw()

func _draw() -> void:
	if not edit and hud.map_open: return
	_draw_joystick()
	var pressed := {}
	for t in touches.values():
		if t.role == "btn": pressed[t.act] = true
	for b in buttons:
		if b.act.begins_with("slot") or not shown(b): continue
		if b.act == "interact":
			var label := "التقاط" if edit else _interact_label()
			if label == "": continue
			_draw_interact(b.pos, Game.t(label))
			continue
		var down: bool = pressed.has(b.act) or (edit and b.id == selected)
		var pt: float = 0.0 if edit else hud.world.player.peek_toggle
		var on: bool = (b.act == "peek_l" and pt < 0.0) or (b.act == "peek_r" and pt > 0.0)
		_draw_button(b, down, on)

const GOLD := Color("ffb321")
const FIRE_RING := Color("ff5a3c")

## A round button like the mobile shooters': a soft shadow, smoked glass with a
## lighter top, a thin bright rim; pressed it sinks a little and glows gold
## (the fire button glows red). Toggled buttons (leaning) keep a gold rim.
func _draw_button(b: Dictionary, down: bool, on: bool) -> void:
	var fire: bool = b.act == "fire"
	var r: float = b.r * (0.93 if down else 1.0)
	var c: Vector2 = b.pos
	draw_circle(c + Vector2(0, r * 0.06), r + 3.0, Color(0, 0, 0, 0.22))
	var base := Color(0.05, 0.07, 0.09, 0.46)
	if down: base = Color(0.55, 0.12, 0.05, 0.62) if fire else Color(0.62, 0.42, 0.02, 0.6)
	draw_circle(c, r, base)
	# Glass: a lighter cap over the top half, fading downwards.
	for i in 4:
		var k := 1.0 - i * 0.18
		draw_arc(c, r * k - 1.5, PI * 1.12, PI * 1.88, 24, Color(1, 1, 1, 0.05 + i * 0.012), r * 0.16)
	var rim := FIRE_RING if fire else (GOLD if (down or on) else Color(1, 1, 1, 0.62))
	if down or on:
		draw_arc(c, r + 2.5, 0, TAU, 48, Color(rim.r, rim.g, rim.b, 0.35), 5.0)
	draw_arc(c, r, 0, TAU, 48, rim, 3.0 if fire else 1.8)
	if fire:
		draw_arc(c, r - 7.0, 0, TAU, 48, Color(1, 1, 1, 0.18), 1.2)
	_icon(b.act, c, r)
	if b.label != "":
		var bl := Game.t(b.label)
		var fs := 12
		var tw := font.get_string_size(bl, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x + 12.0
		var pill := Rect2(c + Vector2(-tw * 0.5, b.r + 4.0), Vector2(tw, 17))
		draw_style_box(_pill_box(Color(0, 0, 0, 0.42), Color(0, 0, 0, 0)), pill)
		draw_string(font, Vector2(pill.position.x, pill.position.y + 13), bl, HORIZONTAL_ALIGNMENT_CENTER, tw, fs, Color(1, 1, 1, 0.92))

var _pills := {}
func _pill_box(bg: Color, border: Color, width := 0) -> StyleBoxFlat:
	var key := "%s/%s/%d" % [bg, border, width]
	if not _pills.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(width)
		sb.set_corner_radius_all(9)
		sb.anti_aliasing = true
		_pills[key] = sb
	return _pills[key]

## The move stick: a ring with arrow marks at the four sides, a knob with a
## highlight, and the run lock above it (gold while locked on).
func _draw_joystick() -> void:
	var c := joy_center
	var r := joy_radius
	draw_circle(c, r + 2.0, Color(0, 0, 0, 0.16))
	draw_circle(c, r, Color(0.05, 0.07, 0.09, 0.3))
	draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.45), 2.0)
	draw_arc(c, r * 0.62, 0, TAU, 48, Color(1, 1, 1, 0.1), 1.0)
	for i in 4:
		var d := Vector2.UP.rotated(i * PI * 0.5)
		var t := c + d * (r - 11.0)
		var sd := d.orthogonal()
		var lit := joy_vec.length() > 0.3 and joy_vec.normalized().dot(d) > 0.7
		draw_polyline(PackedVector2Array([t - d * 5.0 + sd * 6.0, t, t - d * 5.0 - sd * 6.0]), GOLD if lit else Color(1, 1, 1, 0.5), 2.0)
	var kp := c + joy_vec * r
	draw_circle(kp + Vector2(0, 2), 31.0, Color(0, 0, 0, 0.25))
	draw_circle(kp, 30.0, Color(0.92, 0.94, 0.96, 0.5))
	draw_arc(kp, 30.0, 0, TAU, 40, Color(1, 1, 1, 0.8), 2.0)
	draw_arc(kp, 22.0, PI * 1.15, PI * 1.85, 16, Color(1, 1, 1, 0.45), 5.0)
	var sp := c + Vector2(0, -r - 50)
	var pill := Rect2(sp - Vector2(42, 15), Vector2(84, 30))
	draw_style_box(_pill_box(GOLD if sprint_lock else Color(0, 0, 0, 0.42), Color(1, 1, 1, 0.0 if sprint_lock else 0.35), 0 if sprint_lock else 1), pill)
	var ic := GOLD.darkened(0.75) if sprint_lock else Color(1, 1, 1, 0.85)
	for o in [-4.0, 3.0]:
		draw_polyline(PackedVector2Array([sp + Vector2(-34, 4 + o), sp + Vector2(-28, -2 + o), sp + Vector2(-22, 4 + o)]), ic, 2.0)
	draw_string(font, sp + Vector2(-16, 6), Game.t("ركض"), HORIZONTAL_ALIGNMENT_CENTER, 50, 15, ic)

## The use / pick-up button: a pill with a gold rim and a hand mark.
func _draw_interact(c: Vector2, label: String) -> void:
	var w := maxf(150.0, font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 19).x + 56.0)
	var r := Rect2(c - Vector2(w * 0.5, 24), Vector2(w, 48))
	draw_style_box(_pill_box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0)), Rect2(r.position + Vector2(0, 3), r.size))
	var sb := _pill_box(Color(0.06, 0.08, 0.1, 0.72), GOLD, 2)
	sb.set_corner_radius_all(24)
	draw_style_box(sb, r)
	# A hand reaching (fingers up).
	var h := Vector2(r.position.x + 24, c.y + 2)
	draw_rect(Rect2(h + Vector2(-7, -2), Vector2(14, 11)), GOLD)
	for i in 4:
		draw_rect(Rect2(h + Vector2(-7 + i * 3.6, -11 + absf(i - 1.5) * 1.5), Vector2(2.6, 10)), GOLD)
	draw_string(font, Vector2(r.position.x + 36, c.y + 8), label, HORIZONTAL_ALIGNMENT_CENTER, w - 44, 19, Color.WHITE)

## Vector icons in the style of mobile shooters.
func _icon(act: String, c: Vector2, r: float) -> void:
	var w := Color(1, 1, 1, 0.92)
	var k := r / 30.0
	match act:
		"fire":
			# Bullet.
			var bw := 9.0 * k
			draw_rect(Rect2(c + Vector2(-bw, -4 * k), Vector2(bw * 2, 20 * k)), w)
			var tip := PackedVector2Array()
			for i in 9:
				var a := PI + i * PI / 8.0
				tip.append(c + Vector2(cos(a) * bw, -4 * k + sin(a) * 14.0 * k))
			draw_colored_polygon(tip, w)
			draw_rect(Rect2(c + Vector2(-bw - 1.5 * k, 12 * k), Vector2(bw * 2 + 3 * k, 4 * k)), Color(0.08, 0.1, 0.12, 0.8))
		"aim":
			draw_arc(c, 13 * k, 0, TAU, 32, w, 2.0)
			draw_arc(c, 4 * k, 0, TAU, 16, w, 2.0)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				draw_line(c + d * 8 * k, c + d * 18 * k, w, 2.0)
		"reload":
			draw_arc(c, 12 * k, -PI * 0.35, PI * 1.35, 24, w, 3.0 * k)
			var e := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * 12 * k
			draw_colored_polygon(PackedVector2Array([e + Vector2(-6, -5) * k, e + Vector2(7, -1) * k, e + Vector2(-2, 8) * k]), w)
		"jump":
			for o in [-4.0, 5.0]:
				draw_polyline(PackedVector2Array([c + Vector2(-10, 6 + o) * k, c + Vector2(0, -4 + o) * k, c + Vector2(10, 6 + o) * k]), w, 3.0 * k)
		"crouch":
			draw_circle(c + Vector2(4, -13) * k, 4.5 * k, w)
			draw_polyline(PackedVector2Array([c + Vector2(3, -7) * k, c + Vector2(-4, 3) * k, c + Vector2(6, 6) * k, c + Vector2(2, 15) * k]), w, 3.5 * k)
			draw_line(c + Vector2(1, -3) * k, c + Vector2(11, -1) * k, w, 3.0 * k)
		"emote":
			# A figure with both arms up (cheering).
			draw_circle(c + Vector2(0, -10) * k, 4.5 * k, w)
			draw_line(c + Vector2(0, -4) * k, c + Vector2(0, 8) * k, w, 3.5 * k)
			draw_line(c + Vector2(0, -2) * k, c + Vector2(-9, -12) * k, w, 3.0 * k)
			draw_line(c + Vector2(0, -2) * k, c + Vector2(9, -12) * k, w, 3.0 * k)
			draw_line(c + Vector2(0, 8) * k, c + Vector2(-6, 16) * k, w, 3.0 * k)
			draw_line(c + Vector2(0, 8) * k, c + Vector2(6, 16) * k, w, 3.0 * k)
		"freelook":
			# An eye.
			var eye := PackedVector2Array()
			for i in 17:
				var a := i * TAU / 16.0
				eye.append(c + Vector2(cos(a) * 14.0, sin(a) * (7.0 if i <= 8 else 7.0)) * k)
			draw_polyline(eye, w, 2.5 * k)
			draw_circle(c, 4.5 * k, w)
		"peek_l", "peek_r":
			# A figure leaning out to that side.
			var sd := -1.0 if act == "peek_l" else 1.0
			draw_line(c + Vector2(0, 14) * k, c + Vector2(0, 3) * k, w, 3.5 * k)
			draw_line(c + Vector2(0, 3) * k, c + Vector2(7 * sd, -8) * k, w, 3.5 * k)
			draw_circle(c + Vector2(10 * sd, -13) * k, 4.5 * k, w)
		"prone":
			draw_circle(c + Vector2(-13, 2) * k, 4.5 * k, w)
			draw_line(c + Vector2(-7, 4) * k, c + Vector2(15, 5) * k, w, 4.0 * k)
			draw_line(c + Vector2(-6, 6) * k, c + Vector2(-14, 10) * k, w, 2.5 * k)
		"map":
			draw_polyline(PackedVector2Array([c + Vector2(-13, -9) * k, c + Vector2(-4, -12) * k, c + Vector2(4, -9) * k, c + Vector2(13, -12) * k, c + Vector2(13, 9) * k, c + Vector2(4, 12) * k, c + Vector2(-4, 9) * k, c + Vector2(-13, 12) * k, c + Vector2(-13, -9) * k]), w, 2.0)
			draw_line(c + Vector2(-4, -12) * k, c + Vector2(-4, 9) * k, w, 1.5)
			draw_line(c + Vector2(4, -9) * k, c + Vector2(4, 12) * k, w, 1.5)
		"pause":
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * 8 * k, c + Vector2(cos(a), sin(a)) * 14 * k, w, 4.0 * k)
			draw_arc(c, 9 * k, 0, TAU, 24, w, 3.0 * k)
		"throw":
			draw_circle(c + Vector2(0, 3) * k, 9.0 * k, w)
			draw_rect(Rect2(c + Vector2(-3, -11) * k, Vector2(6, 6) * k), w)
			draw_arc(c + Vector2(6, -10) * k, 4.0 * k, PI, TAU * 0.9, 8, w, 2.0)
		"heal":
			draw_rect(Rect2(c + Vector2(-3, -11) * k, Vector2(6, 22) * k), Color("7dff8a"))
			draw_rect(Rect2(c + Vector2(-11, -3) * k, Vector2(22, 6) * k), Color("7dff8a"))
		"boost":
			draw_colored_polygon(PackedVector2Array([c + Vector2(3, -13) * k, c + Vector2(-8, 2) * k, c + Vector2(-1, 2) * k, c + Vector2(-4, 13) * k, c + Vector2(8, -3) * k, c + Vector2(1, -3) * k]), Color("ffae2b"))
		"bag":
			draw_rect(Rect2(c + Vector2(-11, -8) * k, Vector2(22, 20) * k), w)
			draw_arc(c + Vector2(0, -8) * k, 6 * k, PI, TAU, 12, w, 2.5 * k)
			draw_rect(Rect2(c + Vector2(-7, 1) * k, Vector2(14, 6) * k), Color(0.08, 0.1, 0.12, 0.7))
