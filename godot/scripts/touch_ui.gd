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

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load("res://assets/fonts/Cairo.ttf")
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var s := size if size.x > 0 else get_viewport_rect().size
	joy_center = Vector2(150, s.y - 150)
	buttons = [
		{"act": "fire", "icon": "◉", "label": "", "pos": Vector2(s.x - 130, s.y - 150), "r": 58.0},
		{"act": "fire", "icon": "◉", "label": "", "pos": Vector2(100, s.y * 0.42), "r": 38.0},
		{"act": "aim", "icon": "⌖", "label": "منظار", "pos": Vector2(s.x - 245, s.y - 250), "r": 32.0},
		{"act": "reload", "icon": "⟳", "label": "تلقيم", "pos": Vector2(s.x - 250, s.y - 140), "r": 30.0},
		{"act": "jump", "icon": "⤒", "label": "قفز", "pos": Vector2(s.x - 70, s.y - 285), "r": 30.0},
		{"act": "crouch", "icon": "⤓", "label": "انحناء", "pos": Vector2(s.x - 205, s.y - 45), "r": 28.0},
		{"act": "prone", "icon": "▁", "label": "انبطاح", "pos": Vector2(s.x - 135, s.y - 45), "r": 28.0},
		{"act": "map", "icon": "⌗", "label": "الخريطة", "pos": Vector2(s.x - 40, 255), "r": 24.0},
		{"act": "pause", "icon": "⚙", "label": "", "pos": Vector2(s.x - 245, 34), "r": 22.0},
		{"act": "slot1", "icon": "1", "label": "", "pos": Vector2(s.x * 0.5 - 140, s.y - 112), "r": 0.0},
		{"act": "slot2", "icon": "2", "label": "", "pos": Vector2(s.x * 0.5, s.y - 112), "r": 0.0},
		{"act": "slot3", "icon": "3", "label": "", "pos": Vector2(s.x * 0.5 + 140, s.y - 112), "r": 0.0},
		{"act": "interact", "icon": "", "label": "", "pos": Vector2(s.x - 380, s.y * 0.52), "r": 0.0},
	]

func _interact_label() -> String:
	var p: Player = hud.world.player
	match p.state:
		"plane": return "اقفز" if hud.world.plane_over_land() else ""
		"fall": return "افتح المظلة" if p.global_position.y < Player.PLANE_ALT - 40.0 else ""
		"ground":
			var it = hud.world.nearest_pickup(p.global_position, 2.4)
			return "التقاط" if it else ""
	return ""

func _hit_button(pos: Vector2) -> Dictionary:
	for b in buttons:
		if b.act == "interact":
			if _interact_label() != "" and Rect2(b.pos - Vector2(80, 24), Vector2(160, 48)).has_point(pos): return b
		elif b.act.begins_with("slot"):
			if Rect2(b.pos - Vector2(66, 20), Vector2(132, 40)).has_point(pos): return b
		elif pos.distance_to(b.pos) < b.r * 1.15:
			return b
	return {}

func _input(event: InputEvent) -> void:
	if not visible or hud.world.player == null: return
	var p: Player = hud.world.player
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.distance_to(joy_center) < joy_radius * 1.5 and not hud.map_open:
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
			elif t.role == "btn":
				_press(t.act, false)
			touches.erase(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and touches.has(event.index):
		var t: Dictionary = touches[event.index]
		if t.role == "joy":
			_joy(event.position)
		elif t.role == "look" or (t.role == "btn" and t.act == "fire"):
			p.add_look(event.relative.x * 1.4, event.relative.y * 1.4)
		get_viewport().set_input_as_handled()
	p.touch_move = Vector2(joy_vec.x, -joy_vec.y)
	p.sprinting = sprint_lock or joy_vec.y < -0.92

func _joy(pos: Vector2) -> void:
	var d := pos - joy_center
	sprint_lock = d.y < -joy_radius * 1.9 and absf(d.x) < joy_radius
	joy_vec = (d / joy_radius).limit_length(1.0)

func _press(act: String, down: bool) -> void:
	var p: Player = hud.world.player
	match act:
		"map": if down: hud.toggle_map()
		"pause": if down: hud.toggle_pause()
		_: p.action(act, down)

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	if hud.map_open: return
	# Joystick
	draw_circle(joy_center, joy_radius, Color(1, 1, 1, 0.08))
	draw_arc(joy_center, joy_radius, 0, TAU, 48, Color(1, 1, 1, 0.4), 2.0)
	draw_circle(joy_center + joy_vec * joy_radius, 30.0, Color(1, 1, 1, 0.45))
	var sp := joy_center + Vector2(0, -joy_radius - 52)
	draw_rect(Rect2(sp - Vector2(38, 14), Vector2(76, 28)), Color("f2a900") if sprint_lock else Color(0, 0, 0, 0.4))
	draw_string(font, sp + Vector2(-38, 7), "ركض ⬆", HORIZONTAL_ALIGNMENT_CENTER, 76, 14, Color.BLACK if sprint_lock else Color(1, 1, 1, 0.8))
	var pressed := {}
	for t in touches.values():
		if t.role == "btn": pressed[t.act] = true
	for b in buttons:
		if b.act.begins_with("slot"): continue
		if b.act == "interact":
			var label := _interact_label()
			if label == "": continue
			var r := Rect2(b.pos - Vector2(80, 24), Vector2(160, 48))
			draw_rect(r, Color(0, 0, 0, 0.6))
			draw_rect(r, Color("ffd34d"), false, 2.0)
			draw_string(font, Vector2(r.position.x, b.pos.y + 8), label, HORIZONTAL_ALIGNMENT_CENTER, 160, 20, Color.WHITE)
			continue
		var down: bool = pressed.has(b.act)
		draw_circle(b.pos, b.r, Color(0.95, 0.66, 0.0, 0.5) if down else Color(0.08, 0.1, 0.12, 0.45))
		draw_arc(b.pos, b.r, 0, TAU, 40, Color(1, 1, 1, 0.55), 2.0)
		var icon_size := int(b.r * (0.9 if b.label == "" else 0.7))
		draw_string(font, b.pos + Vector2(-b.r, icon_size * 0.35 - (6 if b.label != "" else 0)), b.icon, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2, icon_size, Color.WHITE)
		if b.label != "":
			draw_string(font, b.pos + Vector2(-b.r, b.r * 0.62), b.label, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2, 11, Color(1, 1, 1, 0.85))
