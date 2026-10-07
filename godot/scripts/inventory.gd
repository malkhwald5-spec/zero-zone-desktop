class_name InventoryPanel
extends Control
## Bag screen (B / I): what lies around you, what is in your bag and what you
## carry. Click to pick up, drop, fit or take off attachments, and change guns.
## Rebuilt whenever the contents change.

var player: Player
var world: Node
var _sig := ""
var _cols: Array = []          # VBoxContainers: nearby, bag, equipment
var _cap_bar: ProgressBar
var _cap_label: Label
var _picked_spare := -1         # a spare chosen to fit (click a gun slot next)

const GOLD := Color("ffd34d")
const DIM := Color(1, 1, 1, 0.55)

func _init(p: Player, w: Node) -> void:
	player = p
	world = w

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.86)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 18
	root.offset_bottom = -18
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	# Header: title, capacity, close.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(UiKit.label("الحقيبة", 26, GOLD, UiKit.bold()))
	_cap_bar = ProgressBar.new()
	_cap_bar.custom_minimum_size = Vector2(260, 14)
	_cap_bar.show_percentage = false
	_cap_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cap_bar.add_theme_stylebox_override("background", UiKit.style(Color(1, 1, 1, 0.1), 3, Color(0, 0, 0, 0), 0, 0))
	_cap_bar.add_theme_stylebox_override("fill", UiKit.style(GOLD, 3, Color(0, 0, 0, 0), 0, 0))
	head.add_child(_cap_bar)
	_cap_label = UiKit.label("", 15, DIM)
	head.add_child(_cap_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(UiKit.button("إغلاق  (B)", func(): world.hud.toggle_bag(), Vector2(120, 38), UiKit.style(Color(1, 1, 1, 0.1), 6), 15))
	root.add_child(head)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	for i in 3:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiKit.style(Color(1, 1, 1, 0.05), 8, Color(1, 1, 1, 0.1), 1, 12))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_stretch_ratio = [0.9, 1.0, 1.35][i]
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		var title := UiKit.label(["بالقرب منك", "داخل الحقيبة", "المعدات والأسلحة"][i], 18, Color.WHITE, UiKit.bold())
		v.add_child(title)
		v.add_child(HSeparator.new())
		var sc := ScrollContainer.new()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 5)
		sc.add_child(list)
		v.add_child(sc)
		panel.add_child(v)
		cols.add_child(panel)
		_cols.append(list)
	root.add_child(UiKit.label("اضغط على المنظار أو أي ملحق بالسلاح لتفكّه للحقيبة • اختار ملحق من الحقيبة وبعدين اضغط على مكانه بالسلاح لتركبه • «رمي» بيحطه على الأرض", 13, DIM))
	_rebuild()

func _process(_d: float) -> void:
	var s := _signature()
	if s != _sig: _rebuild()

## Changes when anything shown here changes.
func _signature() -> String:
	var near := []
	for it in world.pickups_near(player.global_position, 3.0):
		near.append(it.get_instance_id())
		near.append(str(it.get_meta("data")))
	return str([player.slots, player.active, player.ammo, player.heals, player.throwables, player.spares, player.gear, near, _picked_spare])

func _clear(list: VBoxContainer) -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()

func _row(list: VBoxContainer, text: String, sub: String, buttons: Array, highlight := false) -> HBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.style(Color(1, 0.83, 0.3, 0.16) if highlight else Color(0, 0, 0, 0.35), 5, GOLD if highlight else Color(0, 0, 0, 0), 1, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", -4)
	tv.add_child(UiKit.label(text, 16, Color.WHITE, UiKit.bold(), 0))
	if sub != "": tv.add_child(UiKit.label(sub, 12, DIM, null, 0))
	h.add_child(tv)
	for b in buttons:
		h.add_child(_small(b[0], b[1], b.size() > 2 and b[2]))
	pc.add_child(h)
	list.add_child(pc)
	return h

func _small(text: String, cb: Callable, accent := false) -> Button:
	var st := UiKit.style(GOLD if accent else Color(1, 1, 1, 0.12), 5, Color(0, 0, 0, 0), 0, 6)
	var b := UiKit.button(text, cb, Vector2(0, 30), st, 13, Color.BLACK if accent else Color.WHITE)
	b.focus_mode = Control.FOCUS_NONE
	return b

func _rebuild() -> void:
	_sig = _signature()
	var p := player
	_cap_bar.max_value = p.capacity()
	_cap_bar.value = p.used_space()
	_cap_label.text = "%d / %d" % [int(p.used_space()), int(p.capacity())]
	# 1) Around you.
	var near: VBoxContainer = _cols[0]
	_clear(near)
	var items: Array = world.pickups_near(p.global_position, 3.0)
	if items.is_empty():
		near.add_child(UiKit.label("ما في إشي قريب", 14, DIM, null, 0))
	# Loot boxes first (each with its owner's name and "take all"), then the ground.
	var boxes := {}
	var loose := []
	for it in items:
		var box = it.get_meta("crate") if it.has_meta("crate") else null
		if box != null and is_instance_valid(box):
			if not boxes.has(box): boxes[box] = []
			boxes[box].append(it)
		else:
			loose.append(it)
	for box in boxes:
		var list: Array = boxes[box]
		var head := HBoxContainer.new()
		var t := UiKit.label("صندوق " + str(box.get_meta("owner")), 16, GOLD, UiKit.bold(), 0)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		head.add_child(_small("أخذ الكل", func(): _take_all(list), true))
		near.add_child(head)
		for it in list:
			var d: Dictionary = it.get_meta("data")
			_row(near, world.pickup_name(d), _kind_name(d), [["التقاط", func(): world.pickup(p, it), true]])
	if not boxes.is_empty() and not loose.is_empty():
		near.add_child(UiKit.label("على الأرض", 15, DIM, UiKit.bold(), 0))
	for it in loose:
		var d: Dictionary = it.get_meta("data")
		_row(near, world.pickup_name(d), _kind_name(d), [["التقاط", func(): world.pickup(p, it), true]])
	# 2) In the bag.
	var bag: VBoxContainer = _cols[1]
	_clear(bag)
	for at in p.ammo:
		if p.ammo[at] > 0:
			_row(bag, "ذخيرة " + Game.AMMO_NAMES[at], "العدد: %d" % p.ammo[at], [["رمي 30", func(): p.drop_ammo(at, 30)], ["رمي الكل", func(): p.drop_ammo(at)]])
	for hid in Items.HEAL_ORDER:
		if p.heals[hid] > 0:
			_row(bag, Items.HEALS[hid].name, "العدد: %d" % p.heals[hid], [["استعمال", func(): p.use_heal(hid)], ["رمي", func(): p.drop_heal(hid)]])
	for tid in p.throwables:
		if p.throwables[tid] > 0:
			_row(bag, Items.THROWS[tid], "العدد: %d" % p.throwables[tid], [["رمي", func(): p.drop_throw(tid)]])
	for i in p.spares.size():
		var id: String = p.spares[i]
		var chosen := _picked_spare == i
		_row(bag, Items.ATTACH[id].name, "ملحق — " + Items.ATTACH_SLOT_NAMES[Items.ATTACH[id].slot], [
			["تركيب", func(): _picked_spare = -1 if chosen else i, not chosen],
			["رمي", func():
				_picked_spare = -1
				p.drop_spare(i)]], chosen)
	if bag.get_child_count() == 0:
		bag.add_child(UiKit.label("الحقيبة فاضية", 14, DIM, null, 0))
	# 3) Equipment: guns with their attachment slots, then armour.
	var eq: VBoxContainer = _cols[2]
	_clear(eq)
	for i in 3:
		var s = p.slots[i]
		var slot_title: String = ["السلاح الأول", "السلاح الثاني", "المسدس"][i]
		if s == null:
			_row(eq, slot_title, "فاضي", [])
			continue
		var wd: Dictionary = Game.WEAPONS[s.id]
		var buttons := []
		if p.active != i: buttons.append(["بالإيد", func(): p.switch_slot(i)])
		buttons.append(["رمي", func(): p.drop_slot(i)])
		_row(eq, wd.name + ("  ◀" if p.active == i else ""), "%s • %d/%d" % [slot_title, s.mag, p.ammo[wd.ammo]], buttons, p.active == i)
		var grid := HBoxContainer.new()
		grid.add_theme_constant_override("separation", 5)
		for slot_name in Items.ATTACH_SLOTS:
			var fits_any := false
			for a in Items.ATTACH.values():
				if a.slot == slot_name and a["for"].has(wd.cls): fits_any = true
			if not fits_any: continue
			var att: Dictionary = s.get("att", {})
			var label: String = Items.ATTACH_SLOT_NAMES[slot_name] + "\n" + (Items.ATTACH[att[slot_name]].name if att.has(slot_name) else "—")
			var can_fit: bool = _picked_spare >= 0 and _picked_spare < p.spares.size() and Items.ATTACH[p.spares[_picked_spare]].slot == slot_name and Items.attach_fits(p.spares[_picked_spare], wd.cls)
			var st := UiKit.style(GOLD if can_fit else (Color(0.25, 0.4, 0.6, 0.55) if att.has(slot_name) else Color(1, 1, 1, 0.07)), 5, Color(1, 1, 1, 0.15), 1, 6)
			var b := UiKit.button(label, func():
				if can_fit:
					p.fit_spare(_picked_spare, i)
					_picked_spare = -1
				elif att.has(slot_name):
					p.detach(i, slot_name), Vector2(96, 52), st, 12, Color.BLACK if can_fit else Color.WHITE)
			b.focus_mode = Control.FOCUS_NONE
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(b)
		eq.add_child(grid)
	eq.add_child(HSeparator.new())
	for g in ["helmet", "vest", "pack"]:
		var lvl: int = p.gear[g]
		var gname := {"helmet": "الخوذة", "vest": "السترة", "pack": "الحقيبة"}[g] as String
		if lvl <= 0:
			_row(eq, gname, "ما في", [])
			continue
		var sub := "مستوى %d" % lvl
		if g != "pack":
			sub += "  •  المتانة %d%%" % int(100.0 * float(p.gear[g + "_dur"]) / float((Items.HELMET if g == "helmet" else Items.VEST)[lvl].dur))
		_row(eq, gname, sub, [["رمي", func(): p.drop_gear(g)]])

## Everything out of a loot box that fits: the better gun into an empty slot
## first, gear only when better, the rest while there is room.
func _take_all(list: Array) -> void:
	for it in list.duplicate():
		if not is_instance_valid(it) or not world.pickups.has(it): continue
		var d: Dictionary = it.get_meta("data")
		if d.kind == "weapon":
			var cls: String = Game.WEAPONS[d.id].cls
			var slot := 2 if cls == "pistol" else (0 if player.slots[0] == null else (1 if player.slots[1] == null else -1))
			if slot < 0 or player.slots[slot] != null: continue
		world.pickup(player, it, true)

func _kind_name(d: Dictionary) -> String:
	match d.kind:
		"weapon": return "سلاح" + ("  +%d ملحق" % d.get("att", {}).size() if not d.get("att", {}).is_empty() else "")
		"ammo": return "ذخيرة"
		"gear": return "معدات"
		"heal": return "علاج"
		"throw": return "قنبلة"
		"attach": return "ملحق — " + Items.ATTACH_SLOT_NAMES[Items.ATTACH[d.id].slot]
	return ""
