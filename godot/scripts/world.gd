extends Node3D
## Match scene: builds the island, flies the plane, spawns loot and bots,
## and keeps the HUD fed.

const BOT_COUNT := 16

var island: Island
var builder: WorldBuilder
var effects: Effects
var player: Player
var hud: Hud
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

func _add_pickup(data: Dictionary, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.set_meta("data", data)
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	if data.kind == "weapon":
		var len := {"pistol": 0.3, "smg": 0.55, "shotgun": 0.85, "ar": 0.9, "sr": 1.15}.get(Game.WEAPONS[data.id].cls, 0.8) as float
		mi.mesh = _box(Vector3(len, 0.1, 0.08))
		mat.albedo_color = Color("2a2c30")
		mat.metallic = 0.5
		mat.roughness = 0.35
	else:
		mi.mesh = _box(Vector3(0.28, 0.2, 0.2))
		mat.albedo_color = {"9mm": Color("c9a64a"), "556": Color("5f9a4f"), "762": Color("b8673f"), "12g": Color("b03a3a")}[data.type]
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.25
	mi.material_override = mat
	mi.position.y = 0.12
	n.add_child(mi)
	add_child(n)
	n.global_position = pos
	n.rotation.y = randf() * TAU
	pickups.append(n)
	return n

func nearest_pickup(p: Vector3, r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for it in pickups:
		var d: float = it.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = it
	return best

func pickup(who: Player, it: Node3D) -> void:
	var data: Dictionary = it.get_meta("data")
	if data.kind == "weapon":
		who.give_weapon(data.id, data.mag)
	else:
		who.ammo[data.type] += data.amount
	pickups.erase(it)
	it.queue_free()

func drop_weapon(id: String, mag: int, pos: Vector3) -> void:
	_add_pickup({"kind": "weapon", "id": id, "mag": mag}, pos + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)))

# ---------- Bots ----------
func _spawn_bots() -> void:
	var names := ["صقر_الليل", "ذيب", "Ghost_KSA", "Shadow99", "ليث", "Falcon_IQ", "Viper_SY", "نمر_EG", "Hunter_JO", "Storm_MA", "قناص_العرب", "Titan313", "Wolf_YT", "برق", "Cobra_007", "رعد"]
	for i in BOT_COUNT:
		var t: Dictionary = island.towns[i % island.towns.size()]
		var p: Vector2 = t.pos + Vector2(randf_range(10.0, t.r), 0).rotated(randf() * TAU)
		if not island.is_land(p.x, p.y): p = t.pos
		var b := Bot.new()
		b.world = self
		b.display_name = names[i % names.size()]
		b.skill = {"easy": 0.25, "normal": 0.5, "hard": 0.8}.get(Game.settings.difficulty, 0.5) + randf_range(-0.15, 0.15)
		b.weapon_id = ["m416", "akm", "ump", "m416", "s1897"][i % 5]
		b.mag = Game.WEAPONS[b.weapon_id].mag
		add_child(b)
		b.global_position = Vector3(p.x, island.height_at(p.x, p.y) + 0.5, p.y)
		bots.append(b)

func alive_count() -> int:
	var n := 1 if player and player.state != "dead" else 0
	for b in bots:
		if not b.dead: n += 1
	return n

func on_bot_killed(bot: Bot, attacker: Node) -> void:
	hud.kill_feed(attacker.display_name if attacker and "display_name" in attacker else "", bot.display_name, attacker == player)
	if attacker == player:
		Game.stats.kills += 1
	drop_weapon(bot.weapon_id, 0, bot.global_position)
	if player.state != "dead" and alive_count() == 1:
		_end_match(true)

func _on_player_died(killer: String) -> void:
	hud.kill_feed(killer, player.display_name, false)
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
		elif plane_t > 0.92 and player.state == "plane" and plane_over_land():
			player.jump_from_plane()
		elif plane_t >= 0.995 and player.state == "plane":
			player.jump_from_plane()
	builder.update_grass(player.global_position)
	# Auto-pickup ammo for guns the player carries.
	if player.state == "ground":
		for it in pickups.duplicate():
			var data: Dictionary = it.get_meta("data")
			if data.kind != "ammo" or it.global_position.distance_to(player.global_position) > 1.4: continue
			for s in player.slots:
				if s != null and Game.WEAPONS[s.id].ammo == data.type:
					pickup(player, it)
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
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	map_texture = ImageTexture.create_from_image(vp.get_texture().get_image())
	vp.queue_free()
	player.camera.current = true
