class_name ShopPanel
extends Control
## The fort's shop in team war (inside your own fort): guns that come with
## their ammo, armour and meds, parts to upgrade your gun, and the fort
## itself (give money to level it up, buy machine-gun towers and sandbag
## walls). Some things need a higher fort level.

const GOLD := Color("ffd34d")
const TABS := [["guns", "الأسلحة"], ["gear", "دروع وعلاج"], ["mods", "تطوير السلاح"], ["fort", "الحصن"]]
## [id, price, fort level needed]
const GUNS := [["ump", 250, 1], ["vector", 300, 1], ["s1897", 250, 1], ["m416", 400, 1], ["akm", 400, 1], ["scar", 450, 1],
	["beryl", 500, 1], ["mini14", 450, 1], ["sks", 500, 1], ["kar98", 600, 1], ["groza", 1000, 2], ["m249", 1000, 2], ["awm", 1300, 2]]
## [id, name, price, level]
const GEAR := [["ammo", "ذخيرة لأسلحتك (+120)", 120, 1], ["vest2", "سترة مستوى 2", 300, 1], ["helmet2", "خوذة مستوى 2", 250, 1],
	["pack2", "حقيبة مستوى 2", 200, 1], ["vest3", "سترة مستوى 3", 700, 2], ["helmet3", "خوذة مستوى 3", 600, 2], ["pack3", "حقيبة مستوى 3", 450, 2],
	["firstaid", "إسعاف أولي ×3", 200, 1], ["medkit", "حقيبة طبية", 400, 1], ["drink", "مشروب طاقة ×2", 150, 1],
	["frag", "قنبلة متفجرة ×2", 250, 1], ["smoke", "قنبلة دخانية ×2", 100, 1], ["molotov", "مولوتوف ×2", 200, 1], ["flash", "قنبلة ضوئية ×2", 150, 1]]
const MODS := [["reddot", 100, 1], ["holo", 100, 1], ["x2", 150, 1], ["x4", 300, 1], ["x8", 500, 2], ["compensator", 200, 1],
	["suppressor", 300, 1], ["ext_mag", 250, 1], ["quick_mag", 200, 1], ["ext_quick", 400, 2], ["vgrip", 150, 1], ["angled", 150, 1]]

var world: Node
var war: War
var tab := "guns"
var _body: GridContainer
var _money: Label
var _tabs: HBoxContainer
var _info: Label

func _init(w: Node) -> void:
	world = w
	war = w.war

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.86)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var f: Dictionary = war.forts[world.player.team]
	head.add_child(UiKit.label("المتجر — " + War.TEAMS[f.team].fort, 28, GOLD, UiKit.bold()))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_money = UiKit.label("", 24, GOLD, UiKit.bold())
	head.add_child(_money)
	head.add_child(UiKit.button("إغلاق ✕", func(): world.hud.toggle_shop(), Vector2(120, 44), UiKit.style(Color(0.6, 0.15, 0.1, 0.9), 6), 18))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	root.add_child(_tabs)
	_info = UiKit.label("", 15, Color(1, 1, 1, 0.75))
	root.add_child(_info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = GridContainer.new()
	_body.columns = 4
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("h_separation", 10)
	_body.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_body)
	_fill()

func _process(_d: float) -> void:
	_money.text = "فلوسك: $%d" % war.money

func _fill() -> void:
	for c in _tabs.get_children(): c.queue_free()
	for t in TABS:
		var on: bool = t[0] == tab
		var id: String = t[0]
		_tabs.add_child(UiKit.button(t[1], func(): tab = id; _fill(), Vector2(170, 42),
			UiKit.style(UiKit.YELLOW if on else Color(1, 1, 1, 0.08), 4), 17, UiKit.INK if on else Color.WHITE))
	for c in _body.get_children(): c.queue_free()
	var f: Dictionary = war.forts[world.player.team]
	var lvl: int = f.level
	match tab:
		"guns":
			_info.text = "السلاح بييجي مع ذخيرته. اللي بإيدك بينحط عالأرض إذا ما في محل."
			for g in GUNS:
				var w: Dictionary = Game.WEAPONS[g[0]]
				_card(String(w.name), "%s • ضرر %d" % [_cls_name(String(w.cls)), int(w.dmg)], int(g[1]), int(g[2]), lvl, _buy_gun.bind(String(g[0])), false, Icons.weapon(String(g[0])))
		"gear":
			_info.text = "دروع، علاج وقنابل."
			for g in GEAR:
				_card(String(g[1]), "", int(g[2]), int(g[3]), lvl, _buy_gear.bind(String(g[0])))
		"mods":
			_info.text = "قطع لتطوير سلاحك: بتتركّب على السلاح اللي بإيدك إذا بتناسبه."
			for g in MODS:
				var a: Dictionary = Items.ATTACH[g[0]]
				_card(String(a.name), Items.ATTACH_SLOT_NAMES[a.slot], int(g[1]), int(g[2]), lvl, _buy_mod.bind(String(g[0])))
		"fort":
			var next: String = ("المستوى الجاي (%d) بـ $%d من صندوق الفريق" % [lvl + 1, War.LEVEL_COST[lvl + 1]]) if lvl < 3 else "حصنك بأعلى مستوى"
			_info.text = "حصنك مستوى %d — بصندوق الفريق $%d — %s.\nمع كل مستوى: قلب أقوى، وبترجعوا بأسلحة أحسن، وبينفتح بالمتجر أغراض جديدة." % [lvl, int(f.bank), next]
			_card("تبرّع للحصن", "$500 من فلوسك لصندوق الفريق", 500, 1, lvl, func(_p):
				war.donate(500)
				_refill())
			_card("تبرّع بكل فلوسك", "كل اللي معك للصندوق", maxi(1, war.money), 1, lvl, func(_p):
				war.donate(war.money)
				_refill())
			_card("مدرعة", "6 عجلات، درع ورشاش عالسقف — بتستناك برّا البوابة", 1500, 2, lvl, _buy_apc)
			var towers := 0
			for t in f.towers:
				if is_instance_valid(t) and not t.dead: towers += 1
			_card("برج رشاش (%d/4)" % towers, "بيقوّص لحاله عالأعداء القريبين", int(War.BUILDS.tower.price), 1, lvl, _buy_build.bind("tower"), not war.build_free(f, "tower"))
			_card("متاريس رمل (%d/8)" % int(f.bags), "سواتر قدّام البوابة", int(War.BUILDS.bags.price), 1, lvl, _buy_build.bind("bags"), not war.build_free(f, "bags"))

func _refill() -> void:
	_fill.call_deferred()

func _cls_name(c: String) -> String:
	return {"pistol": "مسدس", "smg": "رشاش خفيف", "shotgun": "شوزن", "ar": "رشاش", "sr": "قناصة", "lmg": "رشاش ثقيل", "dmr": "بندقية دقيقة", "crossbow": "قوس", "melee": "سلاح أبيض"}.get(c, c)

## One thing to buy: name, a line about it, price; greyed out when it needs
## a higher fort level, too dear, or full.
func _card(title: String, sub: String, price: int, need: int, lvl: int, cb: Callable, full := false, pic: Texture2D = null) -> void:
	var locked := need > lvl
	var dear := war.money < price
	var b := Button.new()
	b.custom_minimum_size = Vector2(260, 92 if pic == null else 150)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := Color(1, 1, 1, 0.07) if not (locked or full) else Color(1, 1, 1, 0.03)
	b.add_theme_stylebox_override("normal", UiKit.style(col, 8, Color(1, 0.83, 0.3, 0.25) if not (locked or dear or full) else Color(0, 0, 0, 0), 1))
	b.add_theme_stylebox_override("hover", UiKit.style(col.lightened(0.1), 8, GOLD, 1))
	b.add_theme_stylebox_override("pressed", UiKit.style(col.darkened(0.2), 8, GOLD, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 8
	v.offset_right = -12
	b.add_child(v)
	if pic:
		var tr := TextureRect.new()
		tr.texture = pic
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(0, 62)
		tr.modulate = Color(1, 1, 1, 0.45) if locked else Color.WHITE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tr)
	v.add_child(UiKit.label(title, 18, Color.WHITE if not locked else Color(1, 1, 1, 0.4), UiKit.bold(), 2))
	if sub != "": v.add_child(UiKit.label(sub, 13, Color(1, 1, 1, 0.6), null, 2))
	var tag := "$%d" % price
	if locked: tag = "🔒 بدها حصن مستوى %d" % need
	elif full: tag = "مكتمل"
	v.add_child(UiKit.label(tag, 17, (Color("ff8a7a") if dear else GOLD) if not (locked or full) else Color(1, 1, 1, 0.45), UiKit.bold(), 2))
	b.disabled = locked or full
	b.pressed.connect(func():
		if war.money < price:
			world.player.message.emit("ما معك فلوس كفاية")
			return
		cb.call(price))
	_body.add_child(b)

func _pay(price: int) -> bool:
	if war.money < price: return false
	war.money -= price
	Game.coin_sound()
	world.sound_local("reload_rifle", 0.0, 1.4, -10.0)
	return true

func _buy_gun(price: int, id: String) -> void:
	if not _pay(price): return
	var p: Player = world.player
	var w: Dictionary = Game.WEAPONS[id]
	p.give_weapon(id, int(w.mag))
	p.ammo[w.ammo] = int(p.ammo[w.ammo]) + (20 if w.ammo == "300" else (40 if w.ammo == "12g" else 120))
	world.hud.weapon_toast(id)
	_refill()

func _buy_gear(price: int, id: String) -> void:
	var p: Player = world.player
	match id:
		"ammo":
			var types := []
			for s in p.slots:
				if s != null and not Game.WEAPONS[s.id].get("melee", false): types.append(Game.WEAPONS[s.id].ammo)
			if types.is_empty(): return
			if not _pay(price): return
			for t in types: p.ammo[t] = int(p.ammo[t]) + (20 if t == "300" else 120)
		"vest2", "vest3", "helmet2", "helmet3":
			var kind := id.substr(0, id.length() - 1)
			var lv := int(id.right(1))
			if int(p.gear[kind]) >= lv and float(p.gear[kind + "_dur"]) >= (Items.VEST if kind == "vest" else Items.HELMET)[lv].dur * 0.99:
				p.message.emit("عندك وحدة متلها")
				return
			if not _pay(price): return
			p.equip(kind, lv, (Items.VEST if kind == "vest" else Items.HELMET)[lv].dur)
		"pack2", "pack3":
			var lv2 := int(id.right(1))
			if int(p.gear.pack) >= lv2: return
			if not _pay(price): return
			p.equip("pack", lv2, 0.0)
		"firstaid":
			if not _pay(price): return
			p.heals.firstaid = int(p.heals.firstaid) + 3
		"medkit":
			if not _pay(price): return
			p.heals.medkit = int(p.heals.medkit) + 1
		"drink":
			if not _pay(price): return
			p.heals.drink = int(p.heals.drink) + 2
		_:
			if not _pay(price): return
			p.throwables[id] = int(p.throwables[id]) + 2
	p.message.emit("تم الشراء")
	_refill()

func _buy_mod(price: int, id: String) -> void:
	var p: Player = world.player
	if not _pay(price): return
	if not p.add_attachment(id, true):
		war.money += price
	_refill()

func _buy_apc(price: int) -> void:
	if not _pay(price): return
	war.spawn_apc(world.player.team)
	world.player.message.emit("المدرعة جاهزة برّا البوابة — اركبها بـ F")
	_refill()

func _buy_build(price: int, kind: String) -> void:
	var f: Dictionary = war.forts[world.player.team]
	if not war.build_free(f, kind): return
	if not _pay(price): return
	war.build(f, kind)
	world.player.message.emit("انبنى %s بحصنك" % War.BUILDS[kind].name)
	_refill()
