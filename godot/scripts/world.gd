extends Node3D
## Match scene: builds the island, flies the plane, spawns loot and bots,
## and keeps the HUD fed.

const BOT_COUNT := 99          # + the player = 100

var island: Island
var builder: WorldBuilder
var effects: Effects
var birds: Birds
var player: Player
var hud: Hud
var zone: Zone
var _zone_tick := 0.0
var zone_deaths := 0
var smokes: Array = []          # {pos: Vector3, r, t}
var airdrops: Array = []        # Airdrop nodes (falling or landed)
var vehicles: Array = []
var _drop_flights: Array = []   # {node, from, to, t, dur, drop: Vector3, dropped}
var _drop_phase := 0
var _boom_stream: AudioStreamWAV
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
var weather := "clear"          # clear | rain | sunset (see Game.pick_weather)
var _rain: GPUParticles3D
var _rain_snd: AudioStreamPlayer
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
	weather = Game.pick_weather()
	builder.weather = weather
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
	_boom_stream = _make_boom_sound()
	for k in SOUNDS:
		_snd[k] = load("res://assets/sounds/%s.ogg" % k)
	_spawn_loot()
	_build_cover()
	_spawn_vehicles()
	_spawn_boats()
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
	zone.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # animated in _process
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
	birds = Birds.new()
	add_child(birds)
	birds.setup(self)
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
	plane_dur = plane_from.distance_to(plane_to) / (90.0 if s <= 4096.0 else 125.0)
	plane = _plane_model()
	plane.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(plane)
	plane.look_at_from_position(plane_from, plane_to, Vector3.UP)

## Four-engine military transport (C-130 style) with spinning propellers and
## an open rear ramp. Faces -Z.
func _plane_model() -> Node3D:
	var plane := Node3D.new()
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("7d858a")
	skin.metallic = 0.35
	skin.roughness = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("2b2f33")
	dark.roughness = 0.5
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("10161c")
	glass.metallic = 0.8
	glass.roughness = 0.1
	var nose := SphereMesh.new()
	nose.radius = 2.3
	nose.height = 4.6
	var parts := [
		# Fuselage, nose, cockpit glass, tail cone rising to the fin.
		[_cyl(2.3, 2.3, 22.0), Vector3(0, 0, 0), Vector3(PI / 2, 0, 0), skin, Vector3.ONE],
		[nose, Vector3(0, -0.15, -11.0), Vector3.ZERO, skin, Vector3(1.0, 0.95, 1.6)],
		[_box(Vector3(2.6, 0.7, 1.4)), Vector3(0, 1.25, -12.6), Vector3(-0.5, 0, 0), glass, Vector3.ONE],
		[_cyl(0.7, 2.3, 9.0), Vector3(0, 0.9, 15.3), Vector3(PI / 2 - 0.12, 0, 0), skin, Vector3.ONE],
		# High wing with engines hanging below it.
		[_box(Vector3(40.0, 0.55, 4.6)), Vector3(0, 2.3, -2.5), Vector3.ZERO, skin, Vector3.ONE],
		[_box(Vector3(4.0, 0.8, 4.0)), Vector3(0, 2.0, -2.5), Vector3.ZERO, skin, Vector3.ONE],
		# Tail: fin and stabiliser.
		[_box(Vector3(0.45, 7.5, 5.0)), Vector3(0, 5.2, 18.0), Vector3(0.25, 0, 0), skin, Vector3.ONE],
		[_box(Vector3(15.0, 0.4, 3.4)), Vector3(0, 2.0, 18.8), Vector3.ZERO, skin, Vector3.ONE],
		# Open rear ramp hanging down, landing-gear pods.
		[_box(Vector3(3.2, 0.25, 5.0)), Vector3(0, -2.4, 13.6), Vector3(0.35, 0, 0), dark, Vector3.ONE],
		[_box(Vector3(1.4, 1.4, 6.0)), Vector3(-2.4, -1.6, 0.5), Vector3.ZERO, skin, Vector3.ONE],
		[_box(Vector3(1.4, 1.4, 6.0)), Vector3(2.4, -1.6, 0.5), Vector3.ZERO, skin, Vector3.ONE],
	]
	for x in [-13.0, -6.5, 6.5, 13.0]:
		parts.append([_cyl(0.75, 0.9, 5.0), Vector3(x, 1.7, -3.6), Vector3(PI / 2, 0, 0), skin, Vector3.ONE])
		parts.append([_cyl(0.35, 0.0, 0.8), Vector3(x, 1.7, -6.5), Vector3(-PI / 2, 0, 0), dark, Vector3.ONE])
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.position = p[1]
		mi.rotation = p[2]
		mi.scale = p[4]
		mi.material_override = p[3]
		plane.add_child(mi)
	# Window row and roundels.
	for i in 7:
		var w := MeshInstance3D.new()
		w.mesh = _box(Vector3(4.66, 0.35, 0.45))
		w.position = Vector3(0, 0.9, -8.0 + i * 2.2)
		w.material_override = glass
		plane.add_child(w)
	# Propellers: four blades each, spun every frame.
	var props := []
	for x in [-13.0, -6.5, 6.5, 13.0]:
		var hub := Node3D.new()
		hub.position = Vector3(x, 1.7, -6.6)
		plane.add_child(hub)
		for k in 4:
			var blade := MeshInstance3D.new()
			blade.mesh = _box(Vector3(0.28, 2.0, 0.08))
			blade.material_override = dark
			blade.position = Vector3(0, 1.0, 0).rotated(Vector3.BACK, k * PI / 2)
			blade.rotation.z = k * PI / 2
			hub.add_child(blade)
		props.append(hub)
	plane.set_meta("props", props)
	return plane

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
const LOOT_TABLE := [["p92", 6], ["ump", 5], ["s1897", 4], ["m416", 4], ["akm", 4], ["mp44", 2.5], ["kar98", 1.2],
	["vector", 2], ["uzi", 3], ["scar", 3], ["beryl", 2], ["sks", 1.5], ["mini14", 1.8], ["crossbow", 0.8], ["pan", 1.5]]

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
				y = b.floor + (WorldBuilder.STOREY_H if spot.get("level", 0) == 1 else 0.0)
		var id := _pick_weapon(spot.military)
		_add_pickup({"kind": "weapon", "id": id, "mag": 0}, Vector3(p.x, y, p.y))
		var at: String = Game.WEAPONS[id].ammo
		if not Game.WEAPONS[id].get("melee", false):
			_add_pickup({"kind": "ammo", "type": at, "amount": {"12g": 10, "bolt": 8}.get(at, 30)}, Vector3(p.x + 0.6, y, p.y + 0.4))
		if randf() < (0.5 if spot.military else 0.35):
			var kind: String = ["vest", "helmet", "pack"][randi() % 3]
			_add_gear(kind, Items.roll_level(spot.military), -1.0, Vector3(p.x - 0.6, y, p.y + 0.3))
		if randf() < 0.22:
			_add_pickup({"kind": "throw", "id": Items.roll_throw(), "n": 1}, Vector3(p.x + 0.4, y, p.y - 0.5))
		if randf() < (0.6 if spot.military else 0.4):
			_add_pickup({"kind": "attach", "id": Items.roll_attach(spot.military)}, Vector3(p.x - 0.4, y, p.y - 0.6))
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
		"throw": return Items.THROWS[data.id]
		"attach": return Items.ATTACH[data.id].name
	return ""

## Pickups are kept in a coarse grid so nearby lookups don't scan the whole map.
const CELL := 16.0
var _grid := {}                 # Vector2i -> Array[Node3D]

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))

func _add_pickup(data: Dictionary, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.set_meta("data", data)
	# The real thing lying there: the gun itself, a box of rounds, a first-aid kit...
	var mi := MeshInstance3D.new()
	mi.mesh = LootModels.mesh(data)
	mi.position.y = 0.004
	# Small things only up close; no shadows (hundreds of extra draws otherwise).
	mi.visibility_range_end = 120.0 if data.kind in ["weapon", "gear"] else 70.0
	mi.visibility_range_end_margin = 10.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
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
			who.give_weapon(data.id, data.mag, data.get("att", {}))
		"attach":
			if not who.add_attachment(data.id): return
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
		"throw":
			if who.free_space() < Items.THROW_SIZE:
				if not quiet: who.message.emit("الحقيبة ممتلئة")
				return
			who.throwables[data.id] += 1
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

# ---------- Loot boxes of the fallen ----------
var crates: Array = []          # Node3D boxes still holding something
var _crate_look: Array = []     # [box mesh, material, lid mesh, lid material]

## A wooden box where someone died, holding everything they carried (taken
## out one by one in the bag screen, or all at once). Its name floats above.
func death_crate(owner_name: String, pos: Vector3, items: Array) -> Node3D:
	if items.is_empty(): return null
	# Sit on whatever is under the body (a floor, the ground, a roof).
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.0, 0), pos + Vector3(0, -6.0, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if not hit.is_empty() else Vector3(pos.x, ground_height(pos), pos.z)
	if _crate_look.is_empty():
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.5, 0.6)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load("res://assets/textures/wood_col.jpg")
		mat.normal_enabled = true
		mat.normal_texture = load("res://assets/textures/wood_nrm.jpg")
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(1.5, 1.5, 1.5)
		mat.albedo_color = Color("c9a070")
		mat.roughness = 0.8
		var lm := BoxMesh.new()
		lm.size = Vector3(0.94, 0.06, 0.64)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color("ffd34d")
		lmat.emission_enabled = true
		lmat.emission = Color("ffb300") * 0.6
		lmat.roughness = 0.5
		_crate_look = [bm, mat, lm, lmat]
	var box := Node3D.new()
	box.name = "LootBox"
	var mi := MeshInstance3D.new()
	mi.mesh = _crate_look[0]
	mi.material_override = _crate_look[1]
	mi.position.y = 0.25
	box.add_child(mi)
	var lid := MeshInstance3D.new()
	lid.mesh = _crate_look[2]
	lid.material_override = _crate_look[3]
	lid.position.y = 0.52
	box.add_child(lid)
	var lb := Label3D.new()
	lb.text = owner_name
	lb.font = load("res://assets/fonts/Cairo.ttf")
	lb.font_size = 48
	lb.pixel_size = 0.004
	lb.outline_size = 10
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = false
	lb.position.y = 1.0
	lb.visibility_range_end = 40.0
	box.add_child(lb)
	add_child(box)
	box.global_position = at
	box.rotation.y = randf() * TAU
	box.set_meta("owner", owner_name)
	box.set_meta("count", items.size())
	crates.append(box)
	for d in items:
		var it := _add_pickup(d, at + Vector3(0, 0.55, 0))
		it.get_child(0).visible = false     # inside the box
		it.set_meta("crate", box)
	return box

func drop_weapon(id: String, mag: int, pos: Vector3, att := {}) -> void:
	_add_pickup({"kind": "weapon", "id": id, "mag": mag, "att": att.duplicate()}, pos + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)))

# ---------- Bots ----------
const BOT_NAMES := ["صقر_الليل", "ذيب", "Ghost_KSA", "Shadow99", "ليث", "Falcon_IQ", "Viper_SY", "نمر_EG", "Hunter_JO", "Storm_MA",
	"قناص_العرب", "Titan313", "Wolf_YT", "برق", "Cobra_007", "رعد", "أسد_الجبل", "Ninja_DZ", "Sniper_LB", "فهد", "Eagle_PS", "Joker_TN",
	"زلزال", "Rex_QA", "عقاب", "Blaze_KW", "Hawk_OM", "إعصار", "Raven_BH", "شبح", "Fury_LY", "صاعقة", "Ace_SD", "نسر", "Bullet_YE",
	"الذئب_الأبيض", "Zero_MR", "Kaiser_AE", "سهم", "Phantom_IQ", "ثعلب", "Venom_SA", "بركان", "Ice_JO", "Sultan_EG", "شاهين", "Rage_SY",
	"Toxic_MA", "عاصفة", "Maverick_JO", "صياد", "Reaper_SA", "نجم_الشمال", "Bandit_EG", "حارس", "Spartan_IQ", "Nova_LB", "قرصان",
	"Ronin_DZ", "غضب", "Mamba_TN", "Delta_KW", "سيف_الدين", "Bravo_PS", "Lion_MA", "الصقر_الحر", "Apex_QA", "زئير", "Drago_SY",
	"Rogue_OM", "صخر", "Glitch_AE", "Thunder_YE", "مغوار", "Ghost_LY", "Blade_SD", "جمرة", "Sabre_BH", "Kilo_MR", "عنتر",
	"Frost_JO", "Lynx_EG", "وهج", "Omen_KSA", "Bolt_IQ", "قمر", "Saber_DZ", "Shark_LB", "رمح", "Tank_TN", "Echo_PS", "حديد",
	"Pixel_MA", "Rocket_KW", "ظل", "Arrow_SY", "Jaguar_QA", "نصر", "Wraith_AE"]

## Teams: you and the first (size - 1) bots are team 0; the other bots are in
## teams of the same size that drop together. Solo: everyone on their own.
var team_size := 1
const TEAM_COLORS := [Color("ffd34d"), Color("ff8a3c"), Color("5fd16a"), Color("58a8ff")]

func _spawn_bots() -> void:
	var dir := plane_to - plane_from
	team_size = Game.team_size()
	var lead_dest := Vector3.ZERO
	var lead_jump := 0.5
	for i in BOT_COUNT:
		var b := Bot.new()
		b.world = self
		b.display_name = BOT_NAMES[i % BOT_NAMES.size()]
		if team_size == 1:
			b.team = i + 1
		elif i < team_size - 1:
			b.team = 0
			b.buddy = true
			b.slot = i + 1
		else:
			b.team = 1 + (i - (team_size - 1)) / team_size
			b.slot = (i - (team_size - 1)) % team_size
		b.skill = clampf({"easy": 0.25, "normal": 0.5, "hard": 0.8}.get(Game.settings.difficulty, 0.5) + randf_range(-0.15, 0.15), 0.05, 0.95)
		# Pick a landing spot: mostly towns (hot drops), some lone houses/fields.
		var dest := _landing_spot()
		# Jump where the plane passes closest to that spot.
		var t := clampf((Vector2(dest.x, dest.z) - Vector2(plane_from.x, plane_from.z)).dot(Vector2(dir.x, dir.z)) / Vector2(dir.x, dir.z).length_squared(), 0.04, 0.96)
		if team_size > 1 and b.slot > 0 and not b.buddy:
			# Squad mates drop together, a few houses apart.
			var off := Vector2(randf_range(12.0, 28.0), 0).rotated(randf() * TAU)
			var p2 := Vector2(lead_dest.x, lead_dest.z) + off
			dest = Vector3(p2.x, island.height_at(p2.x, p2.y), p2.y) if island.is_land(p2.x, p2.y) and not _in_building(p2, 1.5) else lead_dest
			t = lead_jump
		elif team_size > 1:
			lead_dest = dest
			lead_jump = t
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

## Corners to walk past when the straight line from `a` to `b` would go
## through building i (both points outside it).
func _around(i: int, a: Vector2, b: Vector2) -> Array:
	var bl: Dictionary = island.buildings[i]
	var h: Vector2 = bl.size * 0.5 + Vector2(1.6, 1.6)
	var c: Vector2 = bl.pos
	if not _crosses(a, b, c, h - Vector2(1.0, 1.0)): return []
	var cs := [c + Vector2(-h.x, -h.y), c + Vector2(h.x, -h.y), c + Vector2(h.x, h.y), c + Vector2(-h.x, h.y)]
	var inner := h - Vector2(0.9, 0.9)
	var best := []
	var bd := INF
	for k in 4:
		var p: Vector2 = cs[k]
		if not _crosses(a, p, c, inner) and not _crosses(p, b, c, inner):
			var d := a.distance_to(p) + p.distance_to(b)
			if d < bd:
				bd = d
				best = [p]
		# Round two corners (target on the far side).
		for k2 in [(k + 1) % 4, (k + 3) % 4]:
			var q: Vector2 = cs[k2]
			if not _crosses(a, p, c, inner) and not _crosses(q, b, c, inner):
				var d2 := a.distance_to(p) + p.distance_to(q) + q.distance_to(b)
				if d2 < bd:
					bd = d2
					best = [p, q]
	var res := []
	for p in best: res.append(_v3(p))
	return res

## True when segment a-b passes through the box centred at c with half size h.
func _crosses(a: Vector2, b: Vector2, c: Vector2, h: Vector2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for ax in 2:
		var lo: float = c[ax] - h[ax]
		var hi: float = c[ax] + h[ax]
		if absf(d[ax]) < 0.0001:
			if a[ax] < lo or a[ax] > hi: return false
			continue
		var ta: float = (lo - a[ax]) / d[ax]
		var tb: float = (hi - a[ax]) / d[ax]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1: return false
	return true

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
		if ib < 0: pts.append_array(_around(ia, a2, b2))
	# Short walks outside: go round a house in the way instead of into its wall.
	if ia < 0 and ib < 0 and a2.distance_to(b2) < 80.0:
		var reach := a2.distance_to(b2)
		for i in island.buildings.size():
			var bl: Dictionary = island.buildings[i]
			if a2.distance_to(bl.pos) > reach + bl.size.length():
				continue
			var ar := _around(i, a2, b2)
			if not ar.is_empty():
				pts.append_array(ar)
				break
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
		pts.append_array(_around(ib, from, best2[0]))
		pts.append(_v3(best2[0]))
		pts.append(_v3(best2[1]))
	# Two-storey houses: come down the stairs before leaving an upper floor,
	# and climb them to reach someone upstairs.
	var a_up := ia >= 0 and a.y > float(island.buildings[ia].floor) + 2.0
	var b_up := ib >= 0 and b.y > float(island.buildings[ib].floor) + 2.0
	if a_up and not (ia == ib and b_up):
		var st := WorldBuilder.stair_points(island.buildings[ia])
		if not st.is_empty():
			pts = [st[2], st[1], st[0]] + pts
	if b_up and not (ia == ib and a_up):
		var st2 := WorldBuilder.stair_points(island.buildings[ib])
		if not st2.is_empty():
			pts.append_array(st2)
	return pts

# ---------- Cover for bots ----------
const COVER_CELL := 32.0
var _cover := {}            # Vector2i -> Array of [Vector2 centre, radius]

func _build_cover() -> void:
	var add := func(p: Vector2, r: float):
		var k := Vector2i(floori(p.x / COVER_CELL), floori(p.y / COVER_CELL))
		if not _cover.has(k): _cover[k] = []
		_cover[k].append([p, r])
	for t in island.trees: add.call(t.pos, float(t.r) + 0.2)
	for r in island.rocks: add.call(r.pos, float(r.r) * 0.8)
	for b in island.buildings:
		var h: Vector2 = b.size * 0.5
		for cx in [-1.0, 0.0, 1.0]:
			for cz in [-1.0, 0.0, 1.0]:
				if cx == 0.0 and cz == 0.0: continue
				add.call(b.pos + Vector2(cx * h.x, cz * h.y), minf(h.x, h.y) * 0.5)
	for s in island.structures:
		add.call(s.pos, 1.6)

## A spot behind something solid, away from `threat`, within `reach` metres
## of `from` (Vector3.INF if none). Checked with a ray from the threat's eyes.
func find_cover(from: Vector3, threat: Vector3, reach := 30.0) -> Vector3:
	var f := Vector2(from.x, from.z)
	var t := Vector2(threat.x, threat.z)
	var best := Vector3.INF
	var bd := INF
	var k0 := Vector2i(floori(f.x / COVER_CELL), floori(f.y / COVER_CELL))
	var tries := 0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for c in _cover.get(k0 + Vector2i(dx, dz), []):
				var o: Vector2 = c[0]
				var spot: Vector2 = o + (o - t).normalized() * (float(c[1]) + 0.9)
				var d := spot.distance_to(f)
				if d > reach or spot.distance_to(t) < 10.0: continue
				# Prefer near spots that do not mean running towards the threat.
				var score := d + maxf(0.0, t.distance_to(f) - t.distance_to(spot)) * 2.0
				if score >= bd: continue
				if not island.is_land(spot.x, spot.y): continue
				var p3 := Vector3(spot.x, ground_height(Vector3(spot.x, 0, spot.y)), spot.y)
				tries += 1
				if tries > 8: return best
				var q := PhysicsRayQueryParameters3D.create(threat + Vector3(0, 1.5, 0), p3 + Vector3(0, 1.1, 0), 1)
				if get_world_3d().direct_space_state.intersect_ray(q).is_empty(): continue
				bd = score
				best = p3
	return best

## A gunshot: bots that hear it turn towards it and come to have a look.
func notify_shot(pos: Vector3, shooter: Node, suppressed := false) -> void:
	var r := 40.0 if suppressed else 130.0
	if birds and not suppressed: birds.on_noise(pos)
	for b in bots:
		if b == shooter or b.dead: continue
		if b.global_position.distance_squared_to(pos) < r * r:
			b.hear(pos, shooter)

## Everyone still in the match (player and bots).
## Where the camera is: you, or the player you are watching after dying.
## Detail, sounds and grass follow this point.
func view_position() -> Vector3:
	if player and player.state == "dead" and is_instance_valid(player.spectate):
		return player.spectate.global_position
	return player.global_position if player else Vector3.ZERO

## Built once per physics frame: with 100 players every bot asks for it.
func actors() -> Array:
	var f := Engine.get_physics_frames()
	if f == _actors_frame: return _actors
	var res := []
	if player and player.state != "dead": res.append(player)
	for b in bots:
		if not b.dead: res.append(b)
	_actors = res
	_actors_frame = f
	return res

var _actors: Array = []
var _actors_frame := -1

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
		b.model.set_weapon(data.id)
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
	elif data.kind == "throw":
		if data.id != "frag": return
		b.frags += 1
	_remove_pickup(it)

func _remove_pickup(it: Node3D) -> void:
	if it.has_meta("crate"):
		# The last thing taken out of a loot box: the box goes too.
		var box = it.get_meta("crate")
		if is_instance_valid(box):
			box.set_meta("count", int(box.get_meta("count")) - 1)
			if int(box.get_meta("count")) <= 0:
				crates.erase(box)
				box.queue_free()
	pickups.erase(it)
	var c := _cell(it.global_position)
	if _grid.has(c): _grid[c].erase(it)
	it.queue_free()

## Teammates of `a` (player or bot), not counting `a`.
func teammates(a: Node) -> Array:
	var res := []
	if team_size <= 1: return res
	if player and a != player and player.team == a.team: res.append(player)
	for b in bots:
		if b != a and b.team == a.team: res.append(b)
	return res

func same_team(a: Node, b: Node) -> bool:
	return team_size > 1 and a != null and b != null and "team" in a and "team" in b and a.team == b.team

static func is_down(a: Node) -> bool:
	return ("knocked" in a and a.knocked)

static func is_gone(a: Node) -> bool:
	return ("dead" in a and a.dead) or ("state" in a and a.state == "dead")

## Can `a` be knocked down instead of dying? Only with a teammate still on
## their feet to pick them up.
func can_knock(a: Node) -> bool:
	if team_size <= 1 or is_down(a): return false
	for m in teammates(a):
		if not is_gone(m) and not is_down(m): return true
	return false

## Someone was knocked down: feed line, and if nobody in their team is left
## standing, the whole team is out.
func on_actor_knocked(victim: Node, attacker: Node) -> void:
	var by: String = attacker.display_name if attacker and "display_name" in attacker else ""
	if hud: hud.knock_feed(by, victim.display_name, attacker == player)
	_check_team_wipe(victim.team)

func _check_team_wipe(team: int) -> void:
	if team_size <= 1: return
	var members := []
	if player.team == team: members.append(player)
	for b in bots:
		if b.team == team: members.append(b)
	for m in members:
		if not is_gone(m) and not is_down(m): return
	for m in members:
		if is_down(m) and not is_gone(m): m.bleed_out()

## Teams with someone still alive (standing or knocked).
func teams_alive() -> int:
	var seen := {}
	if player and player.state != "dead": seen[player.team] = true
	for b in bots:
		if not b.dead: seen[b.team] = true
	return seen.size()

func team_alive(team: int) -> bool:
	if player.team == team and player.state != "dead": return true
	for b in bots:
		if b.team == team and not b.dead: return true
	return false

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
		player.longest_kill = maxf(player.longest_kill, player.global_position.distance_to(victim.global_position))
	if attacker == null: zone_deaths += 1
	# Bled out or team wiped: the kill goes to whoever knocked them down.
	if victim is Bot and victim.bled and attacker != null and is_instance_valid(attacker) and attacker != victim:
		if attacker == player: player.kills += 1
		elif attacker is Bot: attacker.kills += 1
	if victim is Bot:
		var v: Bot = victim
		# Everything it carried goes into a loot box where it fell.
		var items := []
		if v.armed():
			items.append({"kind": "weapon", "id": v.weapon_id, "mag": v.mag, "att": {}})
			if v.reserve > 0:
				items.append({"kind": "ammo", "type": Game.WEAPONS[v.weapon_id].ammo, "amount": v.reserve})
		for kind in ["vest", "helmet", "pack"]:
			if v.gear[kind] > 0:
				var lvl: int = v.gear[kind]
				var dur: float = float(v.gear.get(kind + "_dur", 0.0)) if kind != "pack" else 0.0
				items.append({"kind": "gear", "gear": kind, "lvl": lvl, "dur": dur})
		for k in v.frags:
			items.append({"kind": "throw", "id": "frag", "n": 1})
		if v.meds > 0:
			items.append({"kind": "heal", "id": "firstaid", "n": v.meds})
		death_crate(v.display_name, v.global_position, items)
	if team_size > 1 and "team" in victim: _check_team_wipe(victim.team)
	# Last team (or last player) standing wins.
	if team_alive(player.team) and teams_alive() == 1:
		_end_match(true)
	elif team_size > 1 and player.state == "dead" and not team_alive(player.team):
		_end_match(false)

func _on_player_died(_killer: String) -> void:
	# In a team the match goes on while a teammate lives: you watch them.
	if team_alive(player.team) and team_size > 1:
		hud.team_still_alive()
		return
	_end_match(false)

func _end_match(won: bool) -> void:
	if match_over: return
	match_over = true
	var rank := 1 if won else (teams_alive() + 1 if team_size > 1 else alive_count() + 1)
	if won: Game.stats.wins += 1
	if Game.stats.best == 0 or rank < Game.stats.best: Game.stats.best = rank
	var reward := Game.reward_match(rank, player.kills, won)
	var alive_t := time - (player.dead_t if player.state == "dead" else 0.0)
	reward.rank_change = Game.record_match({"rank": rank, "teams": int(ceil(float(bots.size() + 1) / team_size)), "kills": player.kills, "won": won,
		"dmg": roundi(player.dmg_dealt), "heads": player.head_kills, "longest": roundi(player.longest_kill),
		"time": roundi(alive_t), "mode": Game.settings.get("mode", "solo")})
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_results(won, rank, player.kills, reward)

# ---------- Per frame ----------
func _process(delta: float) -> void:
	if player == null: return
	time += delta
	_update_ambience(delta)
	_update_interior_air(delta)
	if plane_active:
		plane_t += delta / plane_dur
		plane.global_position = plane_position()
		for pr in plane.get_meta("props", []): pr.rotate_object_local(Vector3.BACK, delta * 40.0)
		if plane_t >= 1.0:
			plane_active = false
			plane.visible = false
			zone.start()
		elif plane_t > 0.92 and player.state == "plane" and plane_over_land():
			player.jump_from_plane()
		elif plane_t >= 0.995 and player.state == "plane":
			player.jump_from_plane()
	builder.update_grass(view_position())
	builder.spin(delta, view_position())
	_update_doors(delta)
	_perf_governor(delta)
	_update_airdrops(delta)
	for s in smokes: s.t -= delta
	smokes = smokes.filter(func(s): return s.t > 0.0)
	if not fires.is_empty(): _update_fires(delta)
	# Blue zone damage, once a second.
	_zone_tick += delta
	if _zone_tick >= 1.0 and zone.state != "idle":
		_zone_tick = 0.0
		for a in actors():
			if a.on_ground() and zone.is_outside(a.global_position):
				a.take_damage(zone.dps, null)
	# Auto-pickup (settings): ammo for guns the player carries, meds and
	# grenades up to the chosen amounts, attachments that fit a free slot.
	if player.state == "ground" and Game.settings.get("auto_pick", true):
		for it in pickups_near(player.global_position, 1.4):
			if not is_instance_valid(it): continue
			var data: Dictionary = it.get_meta("data")
			if it.global_position.distance_to(player.global_position) > 1.4: continue
			if _auto_wanted(data): pickup(player, it, true)

var _gov_t := 0.0
var _gov_frames := 0
# ---------- Windows ----------
var _pane_grid := {}            # Vector2i (16 m cell) -> Array of pane indices

func _pane_cells() -> void:
	for i in builder.panes.size():
		var c: Vector3 = builder.panes[i].c
		var k := Vector2i(floori(c.x / CELL), floori(c.z / CELL))
		if not _pane_grid.has(k): _pane_grid[k] = []
		_pane_grid[k].append(i)

## A shot from `a` to `b`: every window pane it passes through shatters
## (glass does not stop bullets). Only near the camera, where it can be seen.
func bullet_glass(a: Vector3, b: Vector3) -> void:
	if builder.panes.is_empty(): return
	if _pane_grid.is_empty(): _pane_cells()
	var v := view_position()
	if a.distance_to(v) > 350.0 and b.distance_to(v) > 350.0: return
	var seen := {}
	var length := a.distance_to(b)
	var n := int(length / 6.0) + 1
	for s in n + 1:
		var p := a.lerp(b, float(s) / n)
		var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if seen.has(k): continue
		seen[k] = true
		for i in _pane_grid.get(k, []):
			var pn: Dictionary = builder.panes[i]
			if not pn.alive: continue
			var c: Vector3 = pn.c
			var t: float
			if pn.ax:
				if absf(b.z - a.z) < 0.0001: continue
				t = (c.z - a.z) / (b.z - a.z)
			else:
				if absf(b.x - a.x) < 0.0001: continue
				t = (c.x - a.x) / (b.x - a.x)
			if t < 0.0 or t > 1.0: continue
			var q := a.lerp(b, t)
			var du := absf(q.x - c.x) if pn.ax else absf(q.z - c.z)
			if du < pn.w * 0.5 and absf(q.y - c.y) < pn.h * 0.5:
				break_pane(pn, b - a)

func break_pane(pn: Dictionary, dir: Vector3) -> void:
	if not pn.alive: return
	pn.alive = false
	pn.mm.set_instance_transform(pn.i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), pn.c))
	effects.glass_shatter(pn.c, dir.normalized(), Vector2(pn.w, pn.h), pn.ax)
	if Game.settings.sound and _snd.has("glass_break") and pn.c.distance_to(view_position()) < 70.0:
		var p := AudioStreamPlayer3D.new()
		p.stream = _snd["glass_break"]
		p.unit_size = 5.0
		p.max_distance = 70.0
		p.volume_db = -2.0
		p.pitch_scale = randf_range(0.9, 1.12)
		p.bus = _bus_at(pn.c)
		add_child(p)
		p.global_position = pn.c
		p.play()
		p.finished.connect(p.queue_free)

## Panes within r metres of a blast.
func blast_glass(pos: Vector3, r: float) -> void:
	if builder.panes.is_empty(): return
	if _pane_grid.is_empty(): _pane_cells()
	var k := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for i in _pane_grid.get(k + Vector2i(dx, dz), []):
				var pn: Dictionary = builder.panes[i]
				if pn.alive and pn.c.distance_to(pos) < r:
					break_pane(pn, pn.c - pos)

# ---------- Doors ----------
var _door_grid := {}            # Vector2i (16 m cell) -> Array of door indices
var _door_moving: Array = []    # doors swinging right now

func _door_cells() -> void:
	for i in builder.doors.size():
		var c: Vector3 = builder.doors[i].center
		var k := Vector2i(floori(c.x / CELL), floori(c.z / CELL))
		if not _door_grid.has(k): _door_grid[k] = []
		_door_grid[k].append(i)

## Nearest door (its dictionary) within r metres of p, or {}.
func nearest_door(p: Vector3, r: float) -> Dictionary:
	if _door_grid.is_empty() and not builder.doors.is_empty(): _door_cells()
	var best := {}
	var bd := r
	var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for i in _door_grid.get(k + Vector2i(dx, dz), []):
				var d: Dictionary = builder.doors[i]
				var dist := Vector2(p.x - d.center.x, p.z - d.center.z).length()
				if dist < bd and absf(p.y - d.center.y) < 2.2:
					bd = dist
					best = d
	return best

## Opens a shut door (away from `by`) or shuts an open one.
func toggle_door(d: Dictionary, by: Vector3) -> void:
	if d.is_empty(): return
	if d.target < 0.5:
		if d.t < 0.05: d.swing = WorldBuilder._swing_away(d, by)
		d.target = 1.0
		d.open = true
		_door_sound(d, "door_open")
	else:
		d.target = 0.0
		d.open = false
		_door_sound(d, "door_close")
	if not _door_moving.has(d): _door_moving.append(d)

func open_door(d: Dictionary, by: Vector3) -> void:
	if not d.is_empty() and d.target < 0.5: toggle_door(d, by)

func _door_sound(d: Dictionary, name: String) -> void:
	if not Game.settings.sound or not _snd.has(name): return
	if d.center.distance_to(view_position()) > 40.0: return
	var p := AudioStreamPlayer3D.new()
	p.stream = _snd[name]
	p.unit_size = 4.0
	p.max_distance = 40.0
	p.volume_db = -4.0
	p.pitch_scale = randf_range(0.9, 1.1)
	p.bus = _bus_at(d.center)
	add_child(p)
	p.global_position = d.center
	p.play()
	p.finished.connect(p.queue_free)

func _update_doors(delta: float) -> void:
	for d in _door_moving:
		d.t = move_toward(d.t, d.target, delta * 2.6)
		var e := ease(d.t, -1.8)
		d.pivot.rotation.y = d.base + d.swing * WorldBuilder.DOOR_OPEN * e
	_door_moving = _door_moving.filter(func(d): return d.t != d.target)

var _gov_test := -1
var _gov_wait := 10.0            # first check after loading hitches and shader compiles

## Auto performance (settings): if the frame rate stays well under the cap,
## lower the 3D resolution, then the graphics quality, then laptop mode, one
## step every few seconds, and keep it for the next matches.
func _perf_governor(delta: float) -> void:
	if not Game.settings.get("auto_perf", true) or DisplayServer.get_name() == "headless": return
	if _gov_test == 1: return
	if _gov_test < 0:
		# Picture tests (slow software rendering) keep their settings.
		_gov_test = 0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--out="): _gov_test = 1
		if _gov_test == 1: return
	_gov_wait -= delta
	if _gov_wait > 0.0: return
	_gov_t += delta
	_gov_frames += 1
	if _gov_t < 3.0: return
	var fps := _gov_frames / _gov_t
	_gov_t = 0.0
	_gov_frames = 0
	var want := minf(float(Game.settings.get("fps", 60)), 60.0) * 0.75
	if fps >= want: return
	var step := ""
	if Game.render_scale() > 0.55:
		Game.settings.render_scale = maxf(0.5, Game.render_scale() - 0.1)
		step = "دقة الرسم %d%%" % roundi(Game.render_scale() * 100.0)
	elif Game.quality_level() > 0:
		Game.settings.quality = Game.QUALITIES[Game.quality_level() - 1]
		step = "الجودة: " + Game.QUALITY_NAMES[Game.quality_level()]
	elif not Game.laptop():
		Game.settings.laptop = true
		step = "وضع اللابتوب"
	else:
		return
	Game.apply_quality(builder.env, builder.sun)
	Game.save_data()
	player.message.emit("خففنا الرسوميات لحالها عشان اللعب يصير أسلس (%s)" % step)
	_gov_wait = 3.0

func _auto_wanted(data: Dictionary) -> bool:
	var st: Dictionary = Game.settings
	match data.kind:
		"heal":
			if not st.get("pick_meds", true) or player.free_space() < Items.HEALS[data.id].size: return false
			match data.id:
				"bandage": return int(player.heals.bandage) < int(st.get("max_bandage", 20))
				"firstaid": return int(player.heals.firstaid) < int(st.get("max_firstaid", 5))
				"medkit": return int(player.heals.medkit) < 2
				_: return int(player.heals.drink) + int(player.heals.pills) < int(st.get("max_boost", 6))
		"ammo":
			if not st.get("pick_ammo", true) or player.free_space() < Items.AMMO_SIZE: return false
			for s in player.slots:
				if s != null and Game.WEAPONS[s.id].ammo == data.type: return true
		"throw":
			if not st.get("pick_throw", true) or player.free_space() < Items.THROW_SIZE: return false
			var n := 0
			for k in player.throwables: n += int(player.throwables[k])
			return n < int(st.get("max_throw", 6))
		"attach":
			if not st.get("pick_attach", true): return false
			var slot: String = Items.ATTACH[data.id].slot
			for s in player.slots:
				if s != null and Items.attach_fits(data.id, Game.WEAPONS[s.id].cls) and not s.get("att", {}).has(slot): return true
	return false

# ---------- Vehicles ----------
const CAR_COLORS := [Color("b8402f"), Color("2f5fb0"), Color("e0e0dc"), Color("2b2d30"), Color("c9a03a"), Color("3f6b3a")]

## Cars parked along the roads, roughly one per 300 m of road.
func _spawn_vehicles() -> void:
	for rd in island.roads:
		var a: Vector2 = rd.a
		var b: Vector2 = rd.b
		var n := int(a.distance_to(b) / 300.0) + (1 if randf() < 0.6 else 0)
		for k in n:
			var t := randf_range(0.15, 0.85)
			var p := a.lerp(b, t)
			var dir := (b - a).normalized()
			p += Vector2(-dir.y, dir.x) * 6.0 * (1.0 if randf() < 0.5 else -1.0)
			if island.height_at(p.x, p.y) < 0.8 or _in_building(p, 3.0): continue
			var v := Vehicle.new()
			v.world = self
			var r := randf()
			v.kind = "bike" if r < 0.25 else ("jeep" if r < 0.55 else "sedan")
			v.paint = CAR_COLORS[randi() % CAR_COLORS.size()] if v.kind != "jeep" else [Color("4b5a3a"), Color("6b6250"), Color("3d4a52")][randi() % 3]
			v.position = Vector3(p.x, island.height_at(p.x, p.y) + (0.9 if v.kind != "bike" else 0.6), p.y)
			v.rotation.y = atan2(dir.x, dir.y) + (PI if randf() < 0.5 else 0.0)   # cars face +Z
			add_child(v)
			vehicles.append(v)

## Motor boats moored in deep water just off the shores and in the river.
func _spawn_boats() -> void:
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 10 and tries < 4000:
		tries += 1
		var p := Vector2(randf_range(0.05, 0.95), randf_range(0.05, 0.95)) * island.size
		if not island.is_deep(p.x, p.y) or island.height_at(p.x, p.y) > -2.0: continue
		# Wading depth 3-6 m away, so you can walk up and climb in.
		var shore := Vector2.INF
		for k in 16:
			var dir := Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0))
			for d in [3.0, 4.5, 6.0]:
				var q: Vector2 = p + dir * d
				if not island.is_deep(q.x, q.y):
					shore = q
					break
			if shore != Vector2.INF: break
		if shore == Vector2.INF: continue
		var near := false
		for o in placed:
			if o.distance_to(p) < 250.0: near = true
		if near: continue
		placed.append(p)
		var v := Vehicle.new()
		v.world = self
		v.kind = "boat"
		v.paint = [Color("c8d2d8"), Color("2f5d7a"), Color("b8402f"), Color("e8e4da")][randi() % 4]
		v.position = Vector3(p.x, Island.WATER + 0.2, p.y)
		# Side on to the shore, so you can step aboard.
		var to := (shore - p).normalized()
		v.rotation.y = atan2(-to.y, to.x)
		add_child(v)
		vehicles.append(v)

func nearest_vehicle(p: Vector3, r: float) -> Vehicle:
	var best: Vehicle = null
	var bd := r
	for v in vehicles:
		if v.dead or v.driver != null: continue
		var d: float = p.distance_to(v.global_position) - (2.5 if v.kind == "boat" else 0.0)
		if d < bd:
			bd = d
			best = v
	return best

# ---------- Airdrops ----------
## One supply drop each time a new safe zone is announced (phases 2 to 5).
func _update_airdrops(delta: float) -> void:
	if zone.phase >= 1 and zone.phase <= 4 and zone.phase != _drop_phase:
		_drop_phase = zone.phase
		call_drop()
	for f in _drop_flights.duplicate():
		f.t += delta / f.dur
		var pos: Vector3 = f.from.lerp(f.to, f.t)
		f.node.global_position = pos
		if not f.dropped and Vector2(pos.x, pos.z).distance_to(Vector2(f.drop.x, f.drop.z)) < 40.0:
			f.dropped = true
			var ad := Airdrop.new()
			ad.world = self
			ad.target = f.drop
			add_child(ad)
			ad.global_position = Vector3(f.drop.x, pos.y - 6.0, f.drop.z)
			airdrops.append(ad)
		if f.t >= 1.0:
			f.node.queue_free()
			_drop_flights.erase(f)

## Sends a cargo plane over a spot inside the next safe circle.
func call_drop() -> void:
	var c: Vector2 = zone.next_center
	var spot := Vector3.ZERO
	for k in 40:
		var q: Vector2 = c + Vector2(randf() * zone.next_radius * 0.7, 0).rotated(randf() * TAU)
		if island.is_land(q.x, q.y) and not island.is_deep(q.x, q.y) and not _in_building(q, 3.0):
			spot = Vector3(q.x, island.height_at(q.x, q.y), q.y)
			break
	if spot == Vector3.ZERO: return
	var a := randf() * TAU
	var d := Vector3(cos(a), 0, sin(a)) * 2200.0
	var from := spot - d + Vector3(0, 380.0, 0)
	var to := spot + d + Vector3(0, 380.0 - spot.y, 0)
	from.y = 380.0
	var node := _plane_model()
	add_child(node)
	node.look_at_from_position(from, to, Vector3.UP)
	_drop_flights.append({"node": node, "from": from, "to": to, "t": 0.0, "dur": from.distance_to(to) / 90.0, "drop": spot, "dropped": false})
	if hud: hud.show_banner("طائرة إنزال جوي في الطريق!")

## Nearest landed crate within r that still holds something ok(item) accepts.
func nearest_airdrop(p: Vector3, r: float, ok: Callable) -> Node3D:
	var best: Node3D = null
	var bd := r
	for ad in airdrops:
		if not ad.landed: continue
		var d: float = p.distance_to(ad.global_position)
		if d >= bd: continue
		for it in pickups_near(ad.global_position + Vector3(0, 0.95, 0), 1.5):
			if ok.call(it):
				bd = d
				best = ad
				break
	return best

# ---------- Grenades ----------
## Frag explosion: damage falls off with distance; walls and terrain protect.
func explode(pos: Vector3, thrower: Node, exclude: Array = []) -> void:
	pos.y = maxf(pos.y, ground_height(pos) + 0.3)   # never start inside a slope
	effects.explosion(pos)
	sound_boom(pos)
	blast_glass(pos, 7.0)
	if birds: birds.on_noise(pos)
	var space := get_world_3d().direct_space_state
	for a in actors():
		if not a.on_ground(): continue
		var target: Vector3 = a.global_position + Vector3(0, 0.9, 0)
		var d := pos.distance_to(target)
		if d > Grenade.FRAG_RADIUS: continue
		# Covered only if both the body and the head are hidden from the blast.
		var hidden := true
		for hgt in [0.9, 1.6]:
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.2, 0), a.global_position + Vector3(0, hgt, 0), 1)
			q.exclude = exclude
			if space.intersect_ray(q).is_empty():
				hidden = false
				break
		if hidden: continue
		var dmg := Grenade.FRAG_DAMAGE * pow(1.0 - d / Grenade.FRAG_RADIUS, 1.3)
		var killed: bool = a.take_damage(dmg, thrower, false)
		if thrower == player and a != player:
			hud.hit_t = 0.22
			if killed: player.kills += 1
		elif killed and thrower is Bot and thrower != a:
			thrower.kills += 1
	for v in vehicles:
		if v.dead or v.global_position.distance_to(pos) > Grenade.FRAG_RADIUS: continue
		v.take_damage(Grenade.FRAG_DAMAGE * 2.0 * (1.0 - v.global_position.distance_to(pos) / Grenade.FRAG_RADIUS), thrower)
	var pd := pos.distance_to(player.global_position)
	if pd < 40.0: player.shake = maxf(player.shake, 1.0 - pd / 40.0)

# ---------- Molotov fire and flashbangs ----------
const FIRE_RADIUS := 3.2
const FIRE_TIME := 9.0
const FIRE_DPS := 14.0
var fires: Array = []           # {pos, t, thrower, tick}

## A molotov bursts: a pool of fire on the floor or ground under it that
## burns anyone standing in it.
func add_fire(pos: Vector3, thrower: Node) -> void:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -4.0, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if not hit.is_empty() else Vector3(pos.x, ground_height(pos), pos.z)
	effects.fire(at, FIRE_TIME, FIRE_RADIUS)
	sound_boom(at, -12.0, 1.6)
	fires.append({"pos": at, "t": FIRE_TIME, "thrower": thrower, "tick": 0.0})
	notify_shot(at, thrower)

## Fire burning at p (a pool's centre), or Vector3.INF.
func fire_at(p: Vector3, pad := 0.0) -> Vector3:
	for f in fires:
		var c: Vector3 = f.pos
		if Vector2(p.x - c.x, p.z - c.z).length() < FIRE_RADIUS + pad and absf(p.y - c.y) < 2.0:
			return c
	return Vector3.INF

func _update_fires(delta: float) -> void:
	for f in fires:
		f.t -= delta
		f.tick += delta
		if f.tick < 0.5: continue
		f.tick = 0.0
		for a in actors():
			if not a.on_ground(): continue
			if fire_at(a.global_position) != f.pos: continue
			var killed: bool = a.take_damage(FIRE_DPS * 0.5, f.thrower, false)
			if f.thrower == player and a != player:
				hud.hit_t = 0.15
				if killed: player.kills += 1
			elif killed and f.thrower is Bot and f.thrower != a and is_instance_valid(f.thrower):
				f.thrower.kills += 1
	fires = fires.filter(func(f): return f.t > 0.0)

## Flashbang: a blinding light and a bang. Whoever sees it is blinded for a
## few seconds (longer when close and looking at it); walls protect.
func flashbang(pos: Vector3, thrower: Node) -> void:
	effects.flash(pos)
	sound_boom(pos, -4.0, 1.9)
	notify_shot(pos, thrower)
	var space := get_world_3d().direct_space_state
	for a in actors():
		var eye: Vector3 = a.global_position + Vector3(0, 1.5, 0)
		var d := pos.distance_to(eye)
		if d > 24.0: continue
		var q := PhysicsRayQueryParameters3D.create(pos, eye, 1)
		if not space.intersect_ray(q).is_empty(): continue
		var to_flash := (pos - eye).normalized()
		var look: Vector3 = -a.camera.global_basis.z if a == player else Vector3(-sin(a.yaw), 0, -cos(a.yaw))
		var facing := clampf(look.dot(to_flash), 0.0, 1.0)
		var amount := clampf(1.0 - d / 24.0, 0.0, 1.0) * (0.35 + 0.65 * facing)
		if d < 4.0: amount = maxf(amount, 0.8)
		if amount < 0.08: continue
		var secs := 0.8 + 4.5 * amount
		if a == player:
			hud.flash(amount, secs)
		else:
			a.blind_t = maxf(a.blind_t, secs)

func add_smoke(pos: Vector3) -> void:
	effects.smoke_cloud(pos, 22.0)
	smokes.append({"pos": pos + Vector3(0, 1.5, 0), "r": 5.0, "t": 22.0})

## True when the line a->b passes through a smoke cloud.
func smoke_blocks(a: Vector3, b: Vector3) -> bool:
	for s in smokes:
		var c: Vector3 = s.pos
		var ab := b - a
		var k := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if (a + ab * k).distance_to(c) < float(s.r): return true
	return false

# ---------- Parachutes ----------
## When someone lands the canopy is released: it keeps flying a little,
## collapses and sinks into the ground, then disappears.
func drop_canopy(m: HumanModel, vel: Vector3) -> void:
	var src: Node3D = m.canopy
	var c: Node3D = src.duplicate()
	add_child(c)
	c.global_transform = src.global_transform
	c.visible = true
	var start := c.global_position
	var end := start + Vector3(vel.x, 0, vel.z).normalized() * 6.0 + Vector3(0, -2.0, 0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(c, "global_position", end, 2.2).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "scale", Vector3(1.2, 0.05, 0.6), 2.2).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "rotation:x", c.rotation.x + 0.9, 2.2)
	tw.chain().tween_callback(c.queue_free)

var _wind_stream: AudioStreamWAV

## Looping filtered noise used for the wind rush (and, pitched down, the plane drone).
func wind_stream() -> AudioStreamWAV:
	if _wind_stream: return _wind_stream
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / rate
		lp = lp * 0.82 + (randf() * 2.0 - 1.0) * 0.18
		lp2 = lp2 * 0.97 + lp * 0.03
		var gust := 0.75 + 0.25 * sin(t * TAU * 0.5)       # whole periods over the 2 s loop
		data.encode_s16(i * 2, int(clampf((lp * 0.6 + lp2 * 3.0) * gust, -1.0, 1.0) * 26000.0))
	_wind_stream = AudioStreamWAV.new()
	_wind_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_wind_stream.mix_rate = rate
	_wind_stream.data = data
	_wind_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_wind_stream.loop_end = n
	return _wind_stream

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

func _make_boom_sound() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 1.4)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var s := (randf() * 2.0 - 1.0) * exp(-t * 3.5)
		lp = lp * 0.93 + s * 0.07          # deep rumble
		data.encode_s16(i * 2, int(clampf(lp * 4.0, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

func sound_boom(pos: Vector3, volume := 4.0, pitch := 1.0) -> void:
	if not Game.settings.sound: return
	var p := AudioStreamPlayer3D.new()
	p.stream = _snd.get("explosion", _boom_stream)
	p.unit_size = 40.0
	p.max_distance = 1200.0
	p.volume_db = volume
	p.pitch_scale = randf_range(0.9, 1.05) * pitch
	add_child(p)
	p.global_position = pos
	var d := pos.distance_to(view_position()) if player else 0.0
	if d > 60.0:
		get_tree().create_timer(d / SPEED_OF_SOUND).timeout.connect(func():
			if is_instance_valid(p): p.play())
	else:
		p.play()
	p.finished.connect(p.queue_free)

## Inside a building: dusty air (a fog volume the size of the rooms) so the
## sunlight through the windows shows as shafts, with a few motes drifting.
var _dust_fog: FogVolume
var _dust_mat: FogMaterial
var _motes: CPUParticles3D
var _air_t := 0.0
var _air_building := -1
var dust_density := 0.1

var _vfog_len := -1.0

func _update_interior_air(delta: float) -> void:
	if builder == null: return
	_air_t -= delta
	if _air_t <= 0.0:
		_air_t = 0.25
		var vp := view_position()
		var idx := building_at(Vector2(vp.x, vp.z)) if player.state in ["ground", "dead"] else -1
		if idx != _air_building:
			_air_building = idx
			if idx >= 0 and Game.quality_level() >= 1: _place_dust(island.buildings[idx])
	var inside := _air_building >= 0
	# No rain under a roof.
	if _rain: _rain.visible = not inside
	if Game.quality_level() < 1: return
	var env: Environment = builder.env
	if _vfog_len < 0.0: _vfog_len = env.volumetric_fog_length
	# Indoors the fog grid is packed into the near metres: sharp light shafts.
	env.volumetric_fog_length = move_toward(env.volumetric_fog_length, 30.0 if inside else _vfog_len, delta * 120.0)
	if _dust_mat:
		# Not in the morning mist: the low sun would light the whole room up white.
		var want := dust_density if inside and weather != "fog" else 0.0
		_dust_mat.density = move_toward(_dust_mat.density, want, delta * 0.15)
		_dust_fog.visible = _dust_mat.density > 0.001
	if _motes: _motes.emitting = inside

func _place_dust(bl: Dictionary) -> void:
	var storeys: int = int(bl.get("storeys", 1))
	var h := WorldBuilder.STOREY_H * storeys
	var size := Vector3(bl.size.x - 0.3, h, bl.size.y - 0.3)
	var centre := Vector3(bl.pos.x, float(bl.floor) + h * 0.5, bl.pos.y)
	if _dust_fog == null:
		_dust_fog = FogVolume.new()
		_dust_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		_dust_mat = FogMaterial.new()
		_dust_mat.density = 0.0
		_dust_mat.albedo = Color(1.0, 0.95, 0.86)
		_dust_mat.edge_fade = 0.15
		_dust_fog.material = _dust_mat
		add_child(_dust_fog)
		_motes = CPUParticles3D.new()
		_motes.amount = 90
		_motes.lifetime = 9.0
		_motes.preprocess = 9.0
		_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_motes.direction = Vector3.UP
		_motes.spread = 180.0
		_motes.initial_velocity_min = 0.01
		_motes.initial_velocity_max = 0.06
		_motes.gravity = Vector3(0, -0.005, 0)
		_motes.scale_amount_min = 0.6
		_motes.scale_amount_max = 1.4
		var q := QuadMesh.new()
		q.size = Vector2(0.012, 0.012)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_color = Color(1.0, 0.95, 0.85, 0.35)
		q.material = m
		_motes.mesh = q
		_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_motes)
	_dust_fog.size = size
	_dust_fog.global_position = centre
	_motes.emission_box_extents = size * 0.5
	_motes.global_position = centre
	_motes.restart()

## Birds and wind in the background: full on the ground outside, quieter
## indoors and in a car, gone in the plane and while falling (the rushing
## air takes over).
func _update_ambience(delta: float) -> void:
	if not Game.settings.sound or player == null or not _snd.has("ambience"): return
	if _ambience == null:
		_ambience = AudioStreamPlayer.new()
		var st: AudioStreamOggVorbis = _snd.ambience
		st.loop = true
		_ambience.stream = st
		_ambience.volume_db = -60.0
		add_child(_ambience)
		_ambience.play()
	_update_rain(delta)
	var target := -60.0
	match player.state:
		"ground":
			target = -24.0 if building_at(Vector2(player.global_position.x, player.global_position.z)) >= 0 else -15.0
			if weather == "rain": target -= 14.0      # birds keep quiet in the rain
		"vehicle":
			target = -26.0
		"chute":
			target = -30.0
	_ambience.volume_db = move_toward(_ambience.volume_db, target, delta * 20.0)

## Rain: streaks falling around the camera and the hiss of rain (made from
## filtered noise), quieter indoors. Birds go quiet.
func _update_rain(delta: float) -> void:
	if weather != "rain": return
	var cam := get_viewport().get_camera_3d()
	if cam == null: return
	if _rain == null:
		_rain = GPUParticles3D.new()
		_rain.amount = 5000
		_rain.lifetime = 1.1
		_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 45, 60))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(22, 0.5, 22)
		pm.direction = Vector3(0.08, -1, 0.03)
		pm.spread = 2.0
		pm.initial_velocity_min = 22.0
		pm.initial_velocity_max = 26.0
		pm.gravity = Vector3(0, -9.8, 0)
		_rain.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.012, 0.55)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.8, 0.85, 0.9, 0.22)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		q.material = mat
		_rain.draw_pass_1 = q
		_rain.local_coords = false
		add_child(_rain)
	_rain.global_position = cam.global_position + Vector3(0, 14, 0) + Vector3(cam.global_basis.z.x, 0, cam.global_basis.z.z) * -8.0
	var inside := player.state == "ground" and building_at(Vector2(player.global_position.x, player.global_position.z)) >= 0
	if not Game.settings.sound: return
	if _rain_snd == null:
		_rain_snd = AudioStreamPlayer.new()
		_rain_snd.stream = _rain_noise()
		_rain_snd.volume_db = -40.0
		add_child(_rain_snd)
		_rain_snd.play()
	var tgt := -60.0 if player.state == "plane" else (-24.0 if inside else -13.0)
	_rain_snd.volume_db = move_toward(_rain_snd.volume_db, tgt, delta * 20.0)

## Three seconds of rain hiss (low-passed white noise with soft patter), looped.
func _rain_noise() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 3
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.35
		lp2 += (lp - lp2) * 0.5
		var v := lp2 * 0.5
		if rng.randf() < 0.004: v += rng.randf_range(-0.5, 0.5)     # drops hitting things
		# Fade the ends together so the loop has no click.
		var edge := minf(1.0, minf(float(i), float(n - i)) / 600.0)
		data.encode_s16(i * 2, int(clampf(v * edge, -1.0, 1.0) * 26000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n
	return st

var _sounds_playing := 0
## Recorded sounds (freesound.org, see README): assets/sounds/<name>.ogg
const SOUNDS := ["shot_ak", "shot_rifle", "shot_rifle_b", "shot_burst", "shot_far", "far_crack_1", "far_crack_2", "far_crack_3",
	"auto_1", "auto_2", "auto_3", "auto_4", "auto_tail",
	"flyby_1", "flyby_2", "flyby_3", "reload_rifle", "reload_bolt", "bolt_cycle", "dry_click",
	"step_concrete_1", "step_concrete_2", "step_concrete_3", "step_concrete_4", "step_concrete_5",
	"step_grass_1", "step_grass_2", "step_grass_3", "step_grass_4", "step_grass_5", "step_grass_6", "step_grass_7", "step_grass_8",
	"step_wood_1", "step_wood_2", "step_wood_3", "step_wood_4", "step_wood_5",
	"step_sand_1", "step_sand_2", "step_sand_3", "step_sand_4", "step_sand_5", "step_sand_6",
	"step_water_1", "step_water_2", "step_water_3", "step_water_4",
	"explosion", "engine_start", "engine_loop", "ambience", "shot_pistol", "shot_shotgun", "shotgun_pump", "shot_far_2",
	"shot_sniper", "shot_sniper_b", "shot_sniper_far", "door_open", "door_close", "glass_break"]
var _ambience: AudioStreamPlayer
const AUTO_CLASSES := ["ar", "smg", "lmg"]
var _auto_tail_at := -1.0      # when the echo after your automatic fire is due
const SHOT_PITCH := {"pistol": 1.25, "smg": 1.15, "shotgun": 0.8, "ar": 1.0, "sr": 0.82, "lmg": 0.95, "dmr": 0.92}
const SPEED_OF_SOUND := 343.0
var _snd := {}

func sound_shot(cls: String, pos: Vector3, own: bool, suppressed := false) -> void:
	if not Game.settings.sound: return
	var d := pos.distance_to(view_position())
	# Cap how many play at once; past ~700 m nothing is heard anyway, and a
	# suppressed gun only within ~120 m.
	if not own and (_sounds_playing >= 14 or d > (120.0 if suppressed else 700.0)): return
	var far := not own and d > 160.0
	# Close: the punchy AK recording (sometimes another take for variety).
	# Far: a distant shot rolling over the hills, or a short sharp crack.
	var pick: String
	var pitch: float = SHOT_PITCH.get(cls, 1.0) * randf_range(0.96, 1.04)
	if cls == "crossbow" or cls == "melee":
		# A crossbow is only a twang of the string, heard close by.
		if cls == "crossbow" and (own or d < 30.0):
			if own: sound_local("bolt_cycle", 0.0, 1.8, -8.0)
			else: footstep(pos, false, 0.3)
		return
	var sniper := cls == "sr" or (cls == "dmr" and randf() < 0.5)
	if far and sniper and randf() < 0.7:
		# A sniper far away: a long rolling boom.
		pick = "shot_sniper_far"
		pitch = randf_range(0.94, 1.04)
	elif far:
		var r0 := randf()
		pick = "shot_far" if r0 < 0.35 else ("shot_far_2" if r0 < 0.65 else ["far_crack_1", "far_crack_2", "far_crack_3"][randi() % 3])
	elif sniper:
		# Bolt-action rifles have their own heavy recordings.
		pick = "shot_sniper" if randf() < 0.6 else "shot_sniper_b"
		pitch = randf_range(0.97, 1.03)
	elif cls == "pistol" or cls == "shotgun":
		# Their own recordings, at their natural pitch.
		pick = "shot_" + cls
		pitch = randf_range(0.97, 1.03)
	elif own and cls in AUTO_CLASSES:
		# Your automatic gun: short dry cracks; the echo plays when you let go.
		pick = "auto_%d" % (randi() % 4 + 1)
		_auto_tail_at = Time.get_ticks_msec() / 1000.0 + 0.16
	else:
		var r := randf()
		pick = "shot_ak" if r < 0.65 else ("shot_burst" if r < 0.8 else ("shot_rifle" if r < 0.9 else "shot_rifle_b"))
	var stream: AudioStream = _snd.get(pick, _shot_stream)
	_sounds_playing += 1
	var p
	if own:
		# Your own gun: straight into the ears, not placed in the world.
		var p2 := AudioStreamPlayer.new()
		p2.bus = _room_bus()
		p2.stream = stream
		p2.volume_db = -15.0 if suppressed else -3.0
		p2.pitch_scale = pitch * (1.25 if suppressed else 1.0)
		p = p2
		add_child(p2)
		p2.play()
		if cls == "sr":
			sound_local("bolt_cycle", 0.35)
		elif cls == "shotgun":
			sound_local("shotgun_pump", 0.45, 1.0, -6.0)
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = _bus_at(pos)
		p3.stream = stream
		p3.unit_size = 30.0 if not far else 120.0
		p3.max_distance = 900.0
		p3.volume_db = (2.0 if cls in ["sr", "lmg"] else 0.0) - (14.0 if suppressed else 0.0)
		if suppressed: p3.unit_size = 8.0
		p3.pitch_scale = pitch
		p = p3
		add_child(p3)
		p3.global_position = pos
		# Sound travels at 343 m/s: far shots are heard after you see them.
		if d > 60.0:
			get_tree().create_timer(d / SPEED_OF_SOUND).timeout.connect(func():
				if is_instance_valid(p3): p3.play())
		else:
			p3.play()
	p.finished.connect(func():
		_sounds_playing -= 1
		p.queue_free())

## Echo after a burst of your automatic fire (called every frame).
func _update_auto_tail() -> void:
	if _auto_tail_at > 0.0 and Time.get_ticks_msec() / 1000.0 > _auto_tail_at:
		_auto_tail_at = -1.0
		sound_local("auto_tail", 0.0, 1.0, -2.0)

## What the ground under a point sounds like.
## What the ground is made of: "wood" (house floors), "concrete" (roads,
## warehouses, the base), "water", "sand" (desert, beaches) or "grass".
func surface_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	var bi := building_at(q)
	if bi >= 0:
		var bl: Dictionary = island.buildings[bi]
		return "concrete" if bl.military or bl.get("kind", "house") in ["warehouse", "shop"] else "wood"
	if p.y < Island.WATER - 0.15: return "water"
	if island.near_road(q, 0.0): return "concrete"
	var g := island.height_at(p.x, p.z)
	var reg := island.region_at(p.x, p.z)
	if reg == "desert" or reg == "nordic" or g < 2.4: return "sand"     # sand and snow both crunch
	return "grass"

const STEP_SETS := {"concrete": 5, "grass": 8, "wood": 5, "sand": 6, "water": 4}

## One footstep. own = your own feet (not placed in the world); loud 0..1
## (crouching is quiet, sprinting loud). Enemies are heard up to ~40 m away.
func footstep(pos: Vector3, own: bool, loud: float) -> void:
	if not Game.settings.sound: return
	if not own and (_sounds_playing >= 14 or pos.distance_to(view_position()) > 40.0): return
	var surf := surface_at(pos)
	var snd := "step_%s_%d" % [surf, randi() % int(STEP_SETS[surf]) + 1]
	if not _snd.has(snd): snd = "step_grass_%d" % (randi() % 8 + 1)
	var vol := lerpf(-26.0, -8.0, loud)
	if own:
		sound_local(snd, 0.0, randf_range(0.92, 1.08), vol - 6.0)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _snd.get(snd)
	if p.stream == null: return
	p.bus = _bus_at(pos)
	p.unit_size = 3.0
	p.max_distance = 45.0
	p.volume_db = vol + 6.0
	p.pitch_scale = randf_range(0.9, 1.1)
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

## A bullet passing close to you: the crack/whizz right by your head.
func sound_flyby(pos: Vector3) -> void:
	if not Game.settings.sound: return
	var p := AudioStreamPlayer3D.new()
	p.stream = _snd.get(["flyby_1", "flyby_2", "flyby_3"][randi() % 3])
	if p.stream == null: return
	p.unit_size = 4.0
	p.volume_db = 2.0
	p.pitch_scale = randf_range(0.92, 1.1)
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

## Your own non-positional sounds (reload, bolt, empty click), optionally delayed.
## Indoors your own gun, steps and voices ring off the walls: a small room
## reverb on its own bus (made once, kept for the session).
func _room_bus() -> StringName:
	if _air_building < 0: return &"Master"
	if AudioServer.get_bus_index("Room") < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Room")
		AudioServer.set_bus_send(i, "Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.32
		rv.damping = 0.55
		rv.spread = 0.8
		rv.predelay_msec = 12.0
		rv.hipass = 0.15
		rv.wet = 0.3
		rv.dry = 1.0
		AudioServer.add_bus_effect(i, rv)
	return &"Room"

## A sound placed in the world rings like the room when it is in your building.
func _bus_at(pos: Vector3) -> StringName:
	if _air_building < 0 or building_at(Vector2(pos.x, pos.z)) != _air_building: return &"Master"
	return _room_bus()

func sound_local(name: String, delay := 0.0, pitch := 1.0, volume := -4.0) -> void:
	if not Game.settings.sound or not _snd.has(name): return
	var p := AudioStreamPlayer.new()
	p.bus = _room_bus()
	p.stream = _snd[name]
	p.volume_db = volume
	p.pitch_scale = pitch
	add_child(p)
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func():
			if is_instance_valid(p): p.play())
	else:
		p.play()
	p.finished.connect(p.queue_free)

## Length of a loaded sound in seconds (0 if missing).
func sound_length(name: String) -> float:
	var st: AudioStream = _snd.get(name)
	return st.get_length() if st else 0.0

# ---------- Map texture (rendered once from above) ----------
func _capture_map() -> void:
	if DisplayServer.get_name() == "headless": return   # nothing is drawn in tests
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, 2048)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.own_world_3d = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = island.size
	cam.far = 2000.0
	# No haze or glow from above: the map should be clear.
	var map_env: Environment = builder.env.duplicate()
	map_env.fog_enabled = false
	map_env.volumetric_fog_enabled = false
	map_env.glow_enabled = false
	map_env.ssr_enabled = false
	cam.environment = map_env
	vp.add_child(cam)
	add_child(vp)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, 0), Vector3(0, 0, -1)), Vector3(island.size * 0.5, 900.0, island.size * 0.5))
	cam.current = true
	var plane_was := plane.visible
	plane.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	plane.visible = plane_was and plane_active
	player.camera.current = true
	if img == null: return   # nothing rendered (headless)
	# Paint the clean map from the photo and the height map.
	var pv := SubViewport.new()
	pv.size = Vector2i(2048, 2048)
	pv.render_target_update_mode = SubViewport.UPDATE_ONCE
	pv.transparent_bg = false
	var rect := ColorRect.new()
	rect.size = Vector2(2048, 2048)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/map_paint.gdshader")
	mat.set_shader_parameter("photo", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("heights", builder.height_tex)
	mat.set_shader_parameter("mask", builder.mask_tex)
	mat.set_shader_parameter("biomes", builder.biome_tex)
	mat.set_shader_parameter("texel", 1.0 / float(Island.N))
	rect.material = mat
	pv.add_child(rect)
	add_child(pv)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var painted := pv.get_texture().get_image()
	map_texture = ImageTexture.create_from_image(painted if painted else img)
	pv.queue_free()
