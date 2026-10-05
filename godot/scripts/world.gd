extends Node3D
## Match scene: builds the island, flies the plane, spawns loot and bots,
## and keeps the HUD fed.

const BOT_COUNT := 49          # + the player = 50

var island: Island
var builder: WorldBuilder
var effects: Effects
var player: Player
var hud: Hud
var zone: Zone
var _zone_tick := 0.0
var zone_deaths := 0
var bots: Array = []
var pickups: Array = []
var plane: Node3D
var plane_from := Vector3.ZERO
var plane_to := Vector3.ZERO
var plane_t := 0.0
var plane_dur := 40.0
var plane_active := true
var map_texture: Texture2D
var match_over := false
var time := 0.0
var _shot_stream: AudioStreamWAV
var loading: LoadingScreen
var ready_done := false

func _ready() -> void:
	loading = LoadingScreen.new()
	add_child(loading)
	loading.set_progress(0.03, "جاري توليد الجزيرة")
	await _frame()
	_build()

func _frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _build() -> void:
	var seed_v := randi()
	if OS.has_feature("debug") and OS.get_cmdline_user_args().has("--fixed-seed"):
		seed_v = 12345
	island = Island.new(seed_v, Game.MAP_SIZE)
	island.generate()
	builder = WorldBuilder.new(island, self)
	var steps := builder.steps()
	for i in steps.size():
		loading.set_progress(0.1 + 0.6 * i / steps.size(), steps[i][1])
		await _frame()
		steps[i][0].call()
	loading.set_progress(0.75, "جاري توزيع الأسلحة")
	await _frame()
	effects = Effects.new()
	add_child(effects)
	_shot_stream = _make_shot_sound()
	_spawn_loot()
	_make_plane()
	loading.set_progress(0.85, "جاري تجهيز اللاعبين")
	await _frame()
	player = Player.new()
	player.world = self
	add_child(player)
	player.global_position = plane_position()
	player.yaw = atan2(-(plane_to - plane_from).x, -(plane_to - plane_from).z)
	player.pitch = -0.5
	_spawn_bots()
	zone = Zone.new()
	add_child(zone)
	zone.setup(self)
	hud = Hud.new()
	hud.world = self
	add_child(hud)
	player.died.connect(_on_player_died)
	loading.set_progress(0.95, "جاري رسم الخريطة")
	await _capture_map()
	loading.set_progress(1.0, "يلا!")
	await get_tree().create_timer(0.6).timeout
	loading.queue_free()
	loading = null
	ready_done = true
	Game.stats.games += 1
	Game.save_data()

# ---------- Queries used by the player and bots ----------
func ground_height(p: Vector3) -> float:
	return maxf(island.height_at(p.x, p.z), Island.WATER - 1.6)

func is_deep(p: Vector3) -> bool:
	return island.is_deep(p.x, p.z)

func plane_position() -> Vector3:
	return plane_from.lerp(plane_to, clampf(plane_t, 0.0, 1.0))

func plane_velocity() -> Vector3:
	return (plane_to - plane_from) / plane_dur

func plane_over_land() -> bool:
	var p := plane_position()
	return island.is_land(p.x, p.z)

## A dry landing spot near p (never in deep water).
func safe_landing(p: Vector3) -> Vector3:
	if not island.is_deep(p.x, p.z):
		return Vector3(p.x, maxf(p.y, island.height_at(p.x, p.z)), p.z)
	for r in range(10, 1500, 10):
		for k in 16:
			var q := Vector2(p.x, p.z) + Vector2(r, 0).rotated(k * TAU / 16.0)
			if island.is_land(q.x, q.y):
				return Vector3(q.x, island.height_at(q.x, q.y) + 0.5, q.y)
	return p

# ---------- Plane ----------
func _make_plane() -> void:
	var s := island.size
	var a := randf() * TAU
	var c := Vector2(s * 0.5, s * 0.5) + Vector2(randf_range(-s * 0.15, s * 0.15), randf_range(-s * 0.15, s * 0.15))
	var d := Vector2(cos(a), sin(a)) * s * 0.75
	plane_from = Vector3(c.x - d.x, Player.PLANE_ALT, c.y - d.y)
	plane_to = Vector3(c.x + d.x, Player.PLANE_ALT, c.y + d.y)
	plane_dur = plane_from.distance_to(plane_to) / 70.0
	plane = Node3D.new()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color("c9cdd2")
	body_mat.metallic = 0.4
	body_mat.roughness = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("4a5058")
	var parts := [
		[_cyl(1.9, 1.6, 30.0), Vector3(0, 0, 0), Vector3(PI / 2, 0, 0), body_mat],
		[_box(Vector3(38, 0.5, 5)), Vector3(0, 0, -1), Vector3.ZERO, body_mat],
		[_box(Vector3(12, 0.4, 3)), Vector3(0, 0.5, 13.5), Vector3.ZERO, body_mat],
		[_box(Vector3(0.4, 5, 3.4)), Vector3(0, 2.6, 13.5), Vector3.ZERO, body_mat],
	]
	for x in [-11.0, -5.5, 5.5, 11.0]:
		parts.append([_cyl(0.8, 0.9, 3.4), Vector3(x, -0.6, -2.0), Vector3(PI / 2, 0, 0), dark])
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.position = p[1]
		mi.rotation = p[2]
		mi.material_override = p[3]
		plane.add_child(mi)
	add_child(plane)
	plane.look_at_from_position(plane_from, plane_to, Vector3.UP)

func _cyl(r1: float, r2: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r1
	m.bottom_radius = r2
	m.height = h
	return m

func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b

# ---------- Loot ----------
const LOOT_TABLE := [["p92", 6], ["ump", 5], ["s1897", 4], ["m416", 4], ["akm", 4], ["kar98", 1.2]]

func _pick_weapon(military: bool) -> String:
	var total := 0.0
	for e in LOOT_TABLE: total += e[1] * (1.6 if military and e[0] in ["m416", "akm", "kar98"] else 1.0)
	var r := randf() * total
	for e in LOOT_TABLE:
		r -= e[1] * (1.6 if military and e[0] in ["m416", "akm", "kar98"] else 1.0)
		if r <= 0.0: return e[0]
	return "m416"

func _spawn_loot() -> void:
	for spot in island.loot_spots:
		var p: Vector2 = spot.pos
		var y := island.height_at(p.x, p.y)
		for b in island.buildings:
			if absf(p.x - b.pos.x) < b.size.x * 0.5 and absf(p.y - b.pos.y) < b.size.y * 0.5:
				y = b.floor
		var id := _pick_weapon(spot.military)
		_add_pickup({"kind": "weapon", "id": id, "mag": 0}, Vector3(p.x, y, p.y))
		var at: String = Game.WEAPONS[id].ammo
		_add_pickup({"kind": "ammo", "type": at, "amount": 30 if at != "12g" else 10}, Vector3(p.x + 0.6, y, p.y + 0.4))
		if randf() < (0.5 if spot.military else 0.35):
			var kind: String = ["vest", "helmet", "pack"][randi() % 3]
			_add_gear(kind, Items.roll_level(spot.military), -1.0, Vector3(p.x - 0.6, y, p.y + 0.3))
		if randf() < 0.45:
			var hid := Items.roll_heal()
			_add_pickup({"kind": "heal", "id": hid, "n": 3 if hid == "bandage" else 1}, Vector3(p.x - 0.3, y, p.y - 0.6))

## Gear pickup; dur < 0 means brand new.
func _add_gear(kind: String, lvl: int, dur: float, pos: Vector3) -> void:
	if lvl <= 0: return
	if dur < 0.0:
		dur = (Items.VEST if kind == "vest" else Items.HELMET)[lvl].dur if kind != "pack" else 0.0
	_add_pickup({"kind": "gear", "gear": kind, "lvl": lvl, "dur": dur}, pos)

## Short label for a pickup (HUD prompt, bag).
func pickup_name(data: Dictionary) -> String:
	match data.kind:
		"weapon": return Game.WEAPONS[data.id].name
		"ammo": return "%s ×%d" % [Game.AMMO_NAMES[data.type], data.amount]
		"gear": return Items.gear_name(data.gear, data.lvl)
		"heal": return Items.HEALS[data.id].name + (" ×%d" % data.n if data.n > 1 else "")
	return ""

## Pickups are kept in a coarse grid so nearby lookups don't scan the whole map.
const CELL := 16.0
var _grid := {}                 # Vector2i -> Array[Node3D]
var _pickup_res := {}           # shared meshes/materials per kind

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))

func _pickup_look(data: Dictionary) -> Array:
	var key: String
	match data.kind:
		"weapon": key = Game.WEAPONS[data.id].cls
		"ammo": key = "ammo_" + data.type
		"gear": key = "gear_%s_%d" % [data.gear, data.lvl]
		_: key = "heal_" + data.id
	if not _pickup_res.has(key):
		var mat := StandardMaterial3D.new()
		var mesh: Mesh
		if data.kind == "weapon":
			var len := {"pistol": 0.3, "smg": 0.55, "shotgun": 0.85, "ar": 0.9, "sr": 1.15}.get(key, 0.8) as float
			mesh = _box(Vector3(len, 0.1, 0.08))
			mat.albedo_color = Color("2a2c30")
			mat.metallic = 0.5
			mat.roughness = 0.35
		elif data.kind == "ammo":
			mesh = _box(Vector3(0.28, 0.2, 0.2))
			mat.albedo_color = {"9mm": Color("c9a64a"), "556": Color("5f9a4f"), "762": Color("b8673f"), "12g": Color("b03a3a")}[data.type]
		elif data.kind == "gear":
			var tint: Color = [Color.WHITE, Color("8d9a6b"), Color("4e6fa8"), Color("2b2b2b")][data.lvl]
			match data.gear:
				"vest": mesh = _box(Vector3(0.5, 0.12, 0.42))
				"helmet":
					var sp := SphereMesh.new()
					sp.radius = 0.17
					sp.height = 0.22
					sp.is_hemisphere = true
					mesh = sp
				_:
					mesh = _box(Vector3(0.4, 0.22, 0.5))
					tint = [Color.WHITE, Color("7a6648"), Color("5a5a3c"), Color("3a3a32")][data.lvl]
			mat.albedo_color = tint
		else:
			mesh = _box(Vector3(0.22, 0.12, 0.16))
			mat.albedo_color = {"bandage": Color("e8e2d6"), "firstaid": Color("f2f2f2"), "medkit": Color("d93a3a"), "drink": Color("2f86d6"), "pills": Color("e8b23a")}[data.id]
		mat.emission_enabled = true
		mat.emission = mat.albedo_color * 0.25
		_pickup_res[key] = [mesh, mat]
	return _pickup_res[key]

func _add_pickup(data: Dictionary, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.set_meta("data", data)
	var look := _pickup_look(data)
	var mi := MeshInstance3D.new()
	mi.mesh = look[0]
	mi.material_override = look[1]
	mi.position.y = 0.12
	mi.visibility_range_end = 120.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	add_child(n)
	n.global_position = pos
	n.rotation.y = randf() * TAU
	pickups.append(n)
	var c := _cell(pos)
	if not _grid.has(c): _grid[c] = []
	_grid[c].append(n)
	return n

## Pickups within r metres of p (r up to CELL).
func pickups_near(p: Vector3, r: float) -> Array:
	var res := []
	var c := _cell(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for it in _grid.get(c + Vector2i(dx, dz), []):
				if it.global_position.distance_to(p) < r:
					res.append(it)
	return res

func nearest_pickup(p: Vector3, r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for it in pickups_near(p, r):
		var d: float = it.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = it
	return best

func pickup(who: Player, it: Node3D, quiet := false) -> void:
	var data: Dictionary = it.get_meta("data")
	match data.kind:
		"weapon":
			who.give_weapon(data.id, data.mag)
		"ammo":
			# Only what fits in the bag; the rest stays on the ground.
			var fits := int(who.free_space() / Items.AMMO_SIZE)
			var take := mini(int(data.amount), fits)
			if take <= 0:
				if not quiet: who.message.emit("الحقيبة ممتلئة")
				return
			who.ammo[data.type] += take
			data.amount = int(data.amount) - take
			if data.amount > 0: return
		"gear":
			var cur: int = who.gear[data.gear]
			if data.lvl < cur or (data.lvl == cur and data.gear != "pack" and float(data.dur) <= float(who.gear[data.gear + "_dur"])):
				who.message.emit("عندك " + Items.gear_name(data.gear, cur) + " أفضل")
				return
			var old := who.equip(data.gear, int(data.lvl), float(data.dur))
			_add_gear(data.gear, old.lvl, old.dur, who.global_position)
		"heal":
			var size: float = Items.HEALS[data.id].size
			var n := mini(int(data.n), int(who.free_space() / size))
			if n <= 0:
				if not quiet: who.message.emit("الحقيبة ممتلئة")
				return
			who.heals[data.id] += n
			data.n = int(data.n) - n
			if data.n > 0: return
	_remove_pickup(it)

func drop_weapon(id: String, mag: int, pos: Vector3) -> void:
	_add_pickup({"kind": "weapon", "id": id, "mag": mag}, pos + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)))

# ---------- Bots ----------
const BOT_NAMES := ["صقر_الليل", "ذيب", "Ghost_KSA", "Shadow99", "ليث", "Falcon_IQ", "Viper_SY", "نمر_EG", "Hunter_JO", "Storm_MA",
	"قناص_العرب", "Titan313", "Wolf_YT", "برق", "Cobra_007", "رعد", "أسد_الجبل", "Ninja_DZ", "Sniper_LB", "فهد", "Eagle_PS", "Joker_TN",
	"زلزال", "Rex_QA", "عقاب", "Blaze_KW", "Hawk_OM", "إعصار", "Raven_BH", "شبح", "Fury_LY", "صاعقة", "Ace_SD", "نسر", "Bullet_YE",
	"الذئب_الأبيض", "Zero_MR", "Kaiser_AE", "سهم", "Phantom_IQ", "ثعلب", "Venom_SA", "بركان", "Ice_JO", "Sultan_EG", "شاهين", "Rage_SY",
	"Toxic_MA", "عاصفة"]

func _spawn_bots() -> void:
	var dir := plane_to - plane_from
	for i in BOT_COUNT:
		var b := Bot.new()
		b.world = self
		b.display_name = BOT_NAMES[i % BOT_NAMES.size()]
		b.skill = clampf({"easy": 0.25, "normal": 0.5, "hard": 0.8}.get(Game.settings.difficulty, 0.5) + randf_range(-0.15, 0.15), 0.05, 0.95)
		# Pick a landing spot: mostly towns (hot drops), some lone houses/fields.
		var dest := _landing_spot()
		# Jump where the plane passes closest to that spot.
		var t := clampf((Vector2(dest.x, dest.z) - Vector2(plane_from.x, plane_from.z)).dot(Vector2(dir.x, dir.z)) / Vector2(dir.x, dir.z).length_squared(), 0.04, 0.96)
		b.dest = dest
		b.jump_at = t + randf_range(-0.03, 0.01)
		b.chute_alt = randf_range(110.0, 220.0)
		b.position = plane_position() + Vector3(0, -3, 0)
		add_child(b)
		bots.append(b)

func _landing_spot() -> Vector3:
	for k in 30:
		var p: Vector2
		if randf() < 0.8:
			var t: Dictionary = island.towns[randi() % island.towns.size()]
			p = t.pos + Vector2(randf_range(0.0, t.r * 1.1), 0).rotated(randf() * TAU)
		else:
			p = Vector2(randf_range(0.1, 0.9), randf_range(0.1, 0.9)) * island.size
		if island.is_land(p.x, p.y) and not island.is_deep(p.x, p.y) and not _in_building(p, 1.5):
			return Vector3(p.x, island.height_at(p.x, p.y), p.y)
	var t2: Dictionary = island.towns[0]
	return Vector3(t2.pos.x, island.height_at(t2.pos.x, t2.pos.y), t2.pos.y)

func _in_building(p: Vector2, pad: float) -> bool:
	return building_at(p, pad) >= 0

## Index of the building containing p (with padding), or -1.
func building_at(p: Vector2, pad := 0.0) -> int:
	for i in island.buildings.size():
		var bl: Dictionary = island.buildings[i]
		if absf(p.x - bl.pos.x) < bl.size.x * 0.5 + pad and absf(p.y - bl.pos.y) < bl.size.y * 0.5 + pad:
			return i
	return -1

## Door positions of a building: [outside point, inside point] per door.
func _doors(i: int) -> Array:
	var bl: Dictionary = island.buildings[i]
	var h: Vector2 = bl.size * 0.5
	var res := []
	for d in bl.doors:
		var n: Vector2 = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][d]
		var edge: Vector2 = bl.pos + Vector2(n.x * h.x, n.y * h.y)
		res.append([edge + n * 2.0, edge - n * 1.5])
	return res

func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, island.height_at(p.x, p.y), p.y)

## Waypoints for walking from a to b: leave/enter buildings through doors and
## cross deep water on bridges. The goal itself is not included.
func route(a: Vector3, b: Vector3) -> Array:
	var pts := []
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var ia := building_at(a2)
	var ib := building_at(b2)
	if ia >= 0 and ia != ib:
		var best: Array = _doors(ia)[0]
		for d in _doors(ia):
			if d[0].distance_to(b2) < best[0].distance_to(b2): best = d
		pts.append(_v3(best[1]))
		pts.append(_v3(best[0]))
		a2 = best[0]
	# Deep water in between: use the nearest bridge.
	var wet := false
	for k in range(1, 20):
		var q := a2.lerp(b2, k / 20.0)
		if island.is_deep(q.x, q.y):
			wet = true
			break
	if wet and not island.bridges.is_empty():
		var br: Dictionary = island.bridges[0]
		var bd := INF
		for bb in island.bridges:
			var dd: float = a2.distance_to(bb.a) + b2.distance_to(bb.b)
			var dd2: float = a2.distance_to(bb.b) + b2.distance_to(bb.a)
			if minf(dd, dd2) < bd:
				bd = minf(dd, dd2)
				br = bb
		var e1: Vector2 = br.a
		var e2: Vector2 = br.b
		if a2.distance_to(e2) < a2.distance_to(e1):
			var tmp := e1
			e1 = e2
			e2 = tmp
		pts.append(Vector3(e1.x, 1.3, e1.y))
		pts.append(Vector3(e2.x, 1.3, e2.y))
	if ib >= 0 and ib != ia:
		var best2: Array = _doors(ib)[0]
		var from := Vector2(pts[-1].x, pts[-1].z) if not pts.is_empty() else a2
		for d in _doors(ib):
			if d[0].distance_to(from) < best2[0].distance_to(from): best2 = d
		pts.append(_v3(best2[0]))
		pts.append(_v3(best2[1]))
	return pts

## Everyone still in the match (player and bots).
func actors() -> Array:
	var res := []
	if player and player.state != "dead": res.append(player)
	for b in bots:
		if not b.dead: res.append(b)
	return res

## Nearest pickup within r for which ok(it) is true.
func find_pickup(p: Vector3, r: float, ok: Callable) -> Node3D:
	var best: Node3D = null
	var bd := r
	var c := _cell(p)
	var n := ceili(r / CELL)
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			for it in _grid.get(c + Vector2i(dx, dz), []):
				var d: float = it.global_position.distance_to(p)
				if d < bd and ok.call(it):
					bd = d
					best = it
	return best

## A bot picks something up.
func bot_take(b: Bot, it: Node3D) -> void:
	if not is_instance_valid(it) or not pickups.has(it): return
	var data: Dictionary = it.get_meta("data")
	if data.kind == "weapon":
		if b.armed():
			drop_weapon(b.weapon_id, b.mag, b.global_position)
		b.weapon_id = data.id
		b.mag = int(data.mag)
		b.reserve = maxi(b.reserve, 0)
		b.model.set_weapon(Game.WEAPONS[data.id].cls)
		if b.mag == 0: b.reload_t = Game.WEAPONS[data.id].reload
		b.reserve += 30   # some rounds come with the gun
	elif data.kind == "ammo":
		b.reserve += int(data.amount)
	elif data.kind == "gear":
		var kind: String = data.gear
		if int(data.lvl) <= int(b.gear[kind]): return
		if b.gear[kind] > 0: _add_gear(kind, b.gear[kind], float(b.gear.get(kind + "_dur", 0.0)), b.global_position)
		b.gear[kind] = int(data.lvl)
		if kind != "pack": b.gear[kind + "_dur"] = float(data.dur)
		b.model.set_gear(b.gear.vest, b.gear.helmet, b.gear.pack)
	elif data.kind == "heal":
		b.meds += int(data.n)
	_remove_pickup(it)

func _remove_pickup(it: Node3D) -> void:
	pickups.erase(it)
	var c := _cell(it.global_position)
	if _grid.has(c): _grid[c].erase(it)
	it.queue_free()

func alive_count() -> int:
	var n := 1 if player and player.state != "dead" else 0
	for b in bots:
		if not b.dead: n += 1
	return n

## Someone died (player or bot). attacker is null for the blue zone.
func on_actor_killed(victim: Node, attacker: Node) -> void:
	var killer: String = attacker.display_name if attacker and "display_name" in attacker else ""
	if hud: hud.kill_feed(killer, victim.display_name, attacker == player, attacker == null)
	if attacker == player:
		Game.stats.kills += 1
	if attacker == null: zone_deaths += 1
	if victim is Bot:
		var v: Bot = victim
		if v.armed():
			drop_weapon(v.weapon_id, 0, v.global_position)
			var at: String = Game.WEAPONS[v.weapon_id].ammo
			if v.reserve > 0:
				_add_pickup({"kind": "ammo", "type": at, "amount": mini(v.reserve, 60)}, v.global_position + Vector3(0.5, 0, 0.4))
		for kind in ["vest", "helmet", "pack"]:
			if v.gear[kind] > 0:
				_add_gear(kind, v.gear[kind], float(v.gear.get(kind + "_dur", 0.0)), v.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
		if v.meds > 0:
			_add_pickup({"kind": "heal", "id": "firstaid", "n": mini(v.meds, 3)}, v.global_position + Vector3(-0.5, 0, -0.4))
	if player.state != "dead" and alive_count() == 1:
		_end_match(true)

func _on_player_died(_killer: String) -> void:
	_end_match(false)

func _end_match(won: bool) -> void:
	if match_over: return
	match_over = true
	var rank := 1 if won else alive_count() + 1
	if won: Game.stats.wins += 1
	if Game.stats.best == 0 or rank < Game.stats.best: Game.stats.best = rank
	var reward := Game.reward_match(rank, player.kills, won)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_results(won, rank, player.kills, reward)

# ---------- Per frame ----------
func _process(delta: float) -> void:
	if player == null: return
	time += delta
	if plane_active:
		plane_t += delta / plane_dur
		plane.global_position = plane_position()
		if plane_t >= 1.0:
			plane_active = false
			plane.visible = false
			zone.start()
		elif plane_t > 0.92 and player.state == "plane" and plane_over_land():
			player.jump_from_plane()
		elif plane_t >= 0.995 and player.state == "plane":
			player.jump_from_plane()
	builder.update_grass(player.global_position)
	# Blue zone damage, once a second.
	_zone_tick += delta
	if _zone_tick >= 1.0 and zone.state != "idle":
		_zone_tick = 0.0
		for a in actors():
			if a.on_ground() and zone.is_outside(a.global_position):
				a.take_damage(zone.dps, null)
	# Auto-pickup ammo for guns the player carries, and meds, while there is room.
	if player.state == "ground":
		for it in pickups_near(player.global_position, 1.4):
			var data: Dictionary = it.get_meta("data")
			if it.global_position.distance_to(player.global_position) > 1.4: continue
			if data.kind == "heal" and player.free_space() >= Items.HEALS[data.id].size:
				pickup(player, it, true)
			elif data.kind == "ammo" and player.free_space() >= Items.AMMO_SIZE:
				for s in player.slots:
					if s != null and Game.WEAPONS[s.id].ammo == data.type:
						pickup(player, it, true)
						break

# ---------- Sound ----------
func _make_shot_sound() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.35)
	var data := PackedByteArray()
	data.resize(n * 2)
	var prev := 0.0
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 18.0)
		var s := (randf() * 2.0 - 1.0) * env
		prev = prev * 0.6 + s * 0.4    # low-pass for a duller crack
		var v := int(clampf(prev * 0.9, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

func sound_shot(cls: String, pos: Vector3, own: bool) -> void:
	if not Game.settings.sound: return
	var p := AudioStreamPlayer3D.new()
	p.stream = _shot_stream
	p.unit_size = 25.0
	p.max_distance = 600.0
	p.volume_db = -4.0 if own else 0.0
	p.pitch_scale = {"pistol": 1.3, "smg": 1.4, "shotgun": 0.7, "ar": 1.0, "sr": 0.75}.get(cls, 1.0) * randf_range(0.95, 1.05)
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

# ---------- Map texture (rendered once from above) ----------
func _capture_map() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, 1024)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.own_world_3d = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = island.size
	cam.far = 2000.0
	vp.add_child(cam)
	add_child(vp)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, 0), Vector3(0, 0, -1)), Vector3(island.size * 0.5, 900.0, island.size * 0.5))
	cam.current = true
	var plane_was := plane.visible
	plane.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img: map_texture = ImageTexture.create_from_image(img)   # null when running headless
	vp.queue_free()
	plane.visible = plane_was and plane_active
	player.camera.current = true
