class_name TouchEditor
extends Control
## Layout editor for the on-screen buttons (settings → controls): drag any
## button or the joystick to move it, pick one to change its size, keep
## three layouts, reset, save. Unsaved changes are dropped on exit.

signal closed

var ui: TouchUI
var _saved_layouts: Array
var _saved_index := 0
var _drag := ""
var _drag_off := Vector2.ZERO
var _bar: HBoxContainer
var _sel_box: PanelContainer
var _sel_name: Label
var _size: HSlider
var _toast: Label
var _toast_t := 0.0

const NAMES := {"fire": "زر الإطلاق", "fire_l": "زر الإطلاق اليسار", "aim": "المنظار", "jump": "القفز",
	"crouch": "الانحناء", "prone": "الانبطاح", "reload": "التلقيم", "throw": "القنبلة", "peek_l": "ميلان يسار",
	"peek_r": "ميلان يمين", "bag": "الحقيبة", "heal": "العلاج", "boost": "المنشّط", "map": "الخريطة",
	"pause": "الإعدادات", "interact": "زر التقاط / ركوب", "joy": "عصا الحركة"}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_saved_layouts = _layouts().duplicate(true)
	_saved_index = int(Game.settings.get("touch_layout", 0))
	# A battle scene behind, darkened, so the buttons are seen as in a match.
	var art := TextureRect.new()
	art.texture = load("res://assets/textures/ui/art_city.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.modulate = Color(0.45, 0.45, 0.48)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	ui = TouchUI.new()
	ui.edit = true
	add_child(ui)
	# Top bar: layouts, reset, save, exit.
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 6)
	_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.position.y = 8
	add_child(_bar)
	_build_bar()
	# Size of the picked button.
	_sel_box = PanelContainer.new()
	_sel_box.add_theme_stylebox_override("panel", UiKit.style(Color(0, 0, 0, 0.75), 4, Color(1, 1, 1, 0.2), 1, 10))
	_sel_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sel_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sel_box.position.y = 62
	_sel_box.visible = false
	add_child(_sel_box)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_sel_box.add_child(hb)
	_sel_name = UiKit.label("", 16, Color("ffd34d"), UiKit.bold(), 0)
	hb.add_child(_sel_name)
	hb.add_child(UiKit.label("الحجم", 15, Color.WHITE, null, 0))
	_size = HSlider.new()
	_size.min_value = 0.6
	_size.max_value = 1.7
	_size.step = 0.05
	_size.custom_minimum_size = Vector2(220, 28)
	_size.value_changed.connect(_on_size)
	hb.add_child(_size)
	var hint := UiKit.label("اسحب أي زر لمكان جديد، واختار زر لتغيير حجمه", 15, Color(1, 1, 1, 0.75), null, 0)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.position.y -= 34
	add_child(hint)
	_toast = UiKit.label("", 18, Color("7dff8a"), UiKit.bold(), 0)
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_toast)

func _layouts() -> Array:
	var all = Game.settings.get("touch_layouts", [])
	if typeof(all) != TYPE_ARRAY: all = []
	while all.size() < 3: all.append({})
	for i in 3:
		if typeof(all[i]) != TYPE_DICTIONARY: all[i] = {}
	Game.settings.touch_layouts = all
	return all

func _cur() -> Dictionary:
	return _layouts()[clampi(int(Game.settings.get("touch_layout", 0)), 0, 2)]

func _build_bar() -> void:
	for c in _bar.get_children(): c.queue_free()
	var cur := int(Game.settings.get("touch_layout", 0))
	for i in 3:
		var on := i == cur
		var b := UiKit.button("تصميم %d" % (i + 1), func():
			Game.settings.touch_layout = i
			ui.selected = ""
			_sel_box.visible = false
			ui._layout()
			_build_bar(), Vector2(110, 40), UiKit.style(UiKit.YELLOW if on else Color(0.1, 0.12, 0.15, 0.9), 3, Color(1, 1, 1, 0.25), 1, 6), 15, UiKit.INK if on else Color.WHITE)
		_bar.add_child(b)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(20, 0)
	_bar.add_child(gap)
	_bar.add_child(UiKit.button("إعادة ضبط", func():
		_cur().clear()
		ui._layout()
		_say("رجعت الأزرار لأماكنها الأصلية"), Vector2(120, 40), UiKit.style(Color("47c6e6"), 3, Color(0, 0, 0, 0), 0, 6), 15, UiKit.INK))
	_bar.add_child(UiKit.button("حفظ", func():
		_saved_layouts = _layouts().duplicate(true)
		_saved_index = int(Game.settings.touch_layout)
		Game.save_data()
		_say("تم الحفظ ✓"), Vector2(110, 40), UiKit.style(UiKit.YELLOW, 3, Color(0, 0, 0, 0), 0, 6), 16, UiKit.INK))
	_bar.add_child(UiKit.button("خروج", func():
		# Whatever was not saved goes back as it was.
		Game.settings.touch_layouts = _saved_layouts.duplicate(true)
		Game.settings.touch_layout = _saved_index
		closed.emit()
		queue_free(), Vector2(100, 40), UiKit.style(Color(0.1, 0.12, 0.15, 0.9), 3, Color(1, 1, 1, 0.25), 1, 6), 15))

func _say(t: String) -> void:
	_toast.text = t
	_toast_t = 1.6

func _process(delta: float) -> void:
	_toast_t -= delta
	_toast.visible = _toast_t > 0.0
	queue_redraw()

## Weapon slot boxes (fixed) drawn as in the match, for reference.
func _draw() -> void:
	for i in 3:
		var r := Hud.slot_rect(i, size)
		draw_rect(r, Color(0, 0, 0, 0.35))
		draw_rect(r, Color(1, 1, 1, 0.35), false, 1.5)
	if ui and ui.selected == "joy":
		draw_arc(ui.joy_center, ui.joy_radius + 6.0, 0, TAU, 48, Color("ffd34d"), 3.0)

## What is under the pointer: a button id, "joy" or "".
func _pick(pos: Vector2) -> String:
	for b in ui.buttons:
		if b.act.begins_with("slot"): continue
		if b.act == "interact":
			if Rect2(b.pos - Vector2(80, 24), Vector2(160, 48)).has_point(pos): return b.id
		elif pos.distance_to(b.pos) < maxf(b.r, 20.0) * 1.1:
			return b.id
	if pos.distance_to(ui.joy_center) < ui.joy_radius: return "joy"
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var id := _pick(event.position)
			ui.selected = id
			_sel_box.visible = id != ""
			if id != "":
				_sel_name.text = NAMES.get(id, id)
				_size.set_value_no_signal(_size_of(id))
				_size.editable = id != "interact"
				_drag = id
				_drag_off = _pos_of(id) - event.position
		else:
			_drag = ""
		accept_event()
	elif event is InputEventMouseMotion and _drag != "":
		var p: Vector2 = (event.position + _drag_off).clamp(Vector2(20, 20), size - Vector2(20, 20))
		_place(_drag, p, _size_of(_drag))
		accept_event()

func _pos_of(id: String) -> Vector2:
	if id == "joy": return ui.joy_center
	for b in ui.buttons:
		if b.id == id: return b.pos
	return Vector2.ZERO

func _size_of(id: String) -> float:
	var o: Array = _cur().get(id, [])
	return float(o[2]) if o.size() == 3 else 1.0

func _place(id: String, pos: Vector2, sz: float) -> void:
	if size.x < 1.0 or size.y < 1.0: return
	_cur()[id] = [pos.x / size.x, pos.y / size.y, sz]
	ui._layout()

func _on_size(v: float) -> void:
	if ui.selected == "": return
	_place(ui.selected, _pos_of(ui.selected), v)
