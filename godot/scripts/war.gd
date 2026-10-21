class_name War
extends Node3D
## حرب الفرق (team war): four teams of 25 (12 on phones), one per region,
## each with a stone fort. Everyone starts inside their own fort; for the
## first minute and a half the gates are shut by a wall of light (time to
## buy and get ready). While a fort's heart stands, its team comes back
## there after dying; break an enemy heart and that team is down to the
## people still alive. Four places in the plains can be taken (they pay
## their owner every few seconds). After 15 minutes every heart goes out and
## the zone closes in for the final battle. Last team standing wins.

const TEAMS := [
	{"name": "فريق الجليد", "fort": "حصن الجليد", "col": Color("7fd3ff")},
	{"name": "فريق النار", "fort": "حصن النار", "col": Color("ff6a3a")},
	{"name": "فريق الرمل", "fort": "حصن الرمال", "col": Color("f2c14e")},
	{"name": "فريق الغابة", "fort": "حصن الغابة", "col": Color("5fd16a")},
]
const PREP_TIME := 90.0
const FINAL_AT := 900.0           # seconds into the match: the hearts go out, the zone closes in
const RESPAWN_TIME := 8.0
const BOT_RESPAWN := 10.0
const HEART_HP := [0.0, 5000.0, 7500.0, 10000.0]     # by fort level
const LEVEL_COST := [0, 0, 3000, 6000]               # team money to reach level n
const POINT_R := 22.0
const CAPTURE_TIME := 14.0        # seconds for one person to take a point
const WALL_H := 5.0
const WALL_T := 1.2
const GATE_W := 10.0
const H := Island.FORT_HALF
const HEART_Y := 7.3              # the heart's crystal sits on a pillar this high

var world: Node
var forts: Array = []    # {team, pos: Vector2, y, gate: Vector2, center: Vector3, heart, level, bank, respawn, barrier, shop: Vector3, node}
var points: Array = []   # {name, pos: Vector3, owner, capper, prog, flag_mat, ring_mat, label}
var money := 600         # the player's own money
var time := 0.0
var prep_left := PREP_TIME
var final := false
var player_respawn := -1.0
var _respawns: Array = []        # {old: Bot, t}
var _point_t := 0.0
var _income_t := 0.0
var _bank_t := 0.0
var _alert_t := {}               # team -> seconds until the next "under attack" warning
var _heart_cash := 0.0
var _warned_final := false

# ---------------------------------------------------------------- setup
func setup(w: Node) -> void:
	world = w
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for fd in world.island.forts:
		var c: Vector2 = fd.pos
		var f := {"team": fd.team, "pos": c, "y": fd.y, "gate": fd.gate, "center": Vector3(c.x, fd.y, c.y),
			"level": 1, "bank": 0, "respawn": true, "heart": null, "barrier": null, "node": null, "towers": [], "bags": 0}
		forts.append(f)
		_build_fort(f)
	for wp in world.island.war_points:
		var p: Vector2 = wp.pos
		var pt := {"name": wp.name, "pos": Vector3(p.x, world.island.height_at(p.x, p.y), p.y), "owner": -1, "capper": -1, "prog": 0.0}
		points.append(pt)
		_build_point(pt)
	_spawn_teams()

## Everyone into their fort: the player's team gets one place fewer for bots.
func _spawn_teams() -> void:
	var p: Player = world.player
	var mine := randi() % 4
	p.team = mine
	p.slot = 0
	p.state = "ground"
	p.global_position = _spawn_point(forts[mine])
	p.yaw = atan2(-forts[mine].gate.x, -forts[mine].gate.y)
	p.pitch = -0.1
	p.reset_physics_interpolation()
	give_player_kit(p, 1)
	var per_team: int = (world.BOT_COUNT_MOBILE + 1) / 4 if OS.has_feature("mobile") else (world.BOT_COUNT + 1) / 4
	var names: Array = world.BOT_NAMES.duplicate()
	names.shuffle()
	var n := 0
	for t in 4:
		for k in per_team - (1 if t == mine else 0):
			var r := randf()
			var persona := "sniper" if r < 0.15 else ("rusher" if r < 0.3 else ("camper" if r < 0.42 else ""))
			var skill := clampf({"easy": 0.25, "normal": 0.5, "hard": 0.8}.get(Game.settings.difficulty, 0.5) + randf_range(-0.15, 0.15), 0.05, 0.95)
			_spawn_bot(t, String(names[n % names.size()]), persona, skill, k + 1)
			n += 1

func _spawn_bot(team: int, bot_name: String, persona: String, skill: float, slot: int) -> Bot:
	var b := Bot.new()
	b.world = world
	b.display_name = bot_name
	b.team = team
	b.slot = slot
	b.skill = skill
	b.persona = persona
	b.state = "ground"
	b.war_role = _pick_role()
	b.position = _spawn_point(forts[team])
	b.yaw = randf() * TAU
	world.add_child(b)
	world.bots.append(b)
	_bot_kit(b, int(forts[team].level))
	return b

func _pick_role() -> String:
	var r := randf()
	var raid := 0.3 if time < 300.0 else 0.45
	return "raid" if r < raid else ("defend" if r < raid + 0.18 else "capture")

## A free spot in the courtyard, round the heart.
func _spawn_point(f: Dictionary) -> Vector3:
	var c: Vector3 = f.center
	var g: Vector2 = f.gate
	for k in 20:
		var off := Vector2(randf_range(7.0, H - 6.0), 0).rotated(randf() * TAU)
		# Not on the shop.
		if off.distance_to(g * 12.0 + Vector2(-g.y, g.x) * 8.0) < 5.0: continue
		return Vector3(c.x + off.x, c.y + 0.2, c.z + off.y)
	return c + Vector3(6, 0.2, 0)

# ---------------------------------------------------------------- kits
## What you come back with, by how far your fort has been built up.
func give_player_kit(p: Player, lvl: int) -> void:
	p.strip_for_flight()
	match lvl:
		1:
			p.give_weapon("ump", Game.WEAPONS.ump.mag)
			p.ammo["9mm"] += 150
			p.equip("vest", 1, Items.VEST[1].dur)
			p.heals.bandage = 5
		2:
			p.give_weapon("m416", Game.WEAPONS.m416.mag)
			p.ammo["556"] += 180
			p.equip("vest", 2, Items.VEST[2].dur)
			p.equip("helmet", 1, Items.HELMET[1].dur)
			p.heals.bandage = 5
			p.heals.firstaid = 1
		_:
			p.give_weapon("m416", Game.WEAPONS.m416.mag, {"sight": "reddot"})
			p.ammo["556"] += 210
			p.equip("vest", 2, Items.VEST[2].dur)
			p.equip("helmet", 2, Items.HELMET[2].dur)
			p.heals.bandage = 5
			p.heals.firstaid = 2
			p.throwables.frag = 1
	p.give_weapon("p92", Game.WEAPONS.p92.mag)
	p.ammo["9mm"] += 30
	p.switch_slot(0)

const BOT_GUNS := [[], ["ump", "uzi", "vector", "s1897"], ["m416", "akm", "scar", "beryl", "mini14"], ["m416", "akm", "groza", "m249", "kar98", "sks"]]

func _bot_kit(b: Bot, lvl: int) -> void:
	var pool: Array = BOT_GUNS[clampi(lvl, 1, 3)]
	var id: String = pool[randi() % pool.size()]
	if b.persona == "sniper" and lvl >= 2: id = "kar98" if lvl == 3 or randf() < 0.5 else "mini14"
	b.weapon_id = id
	b.mag = int(Game.WEAPONS[id].mag)
	b.reserve = 150
	b.gear.vest = mini(lvl, 2)
	b.gear.vest_dur = float(Items.VEST[b.gear.vest].dur)
	b.gear.helmet = lvl - 1
	b.gear.helmet_dur = float(Items.HELMET[b.gear.helmet].dur)
	b.meds = 2
	b.frags = 1 if lvl >= 3 else 0
	b.model.set_weapon(id)
	b.model.set_gear(b.gear.vest, b.gear.helmet, 0)

# ---------------------------------------------------------------- the forts
func _build_fort(f: Dictionary) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = f.center
	f.node = node
	var col: Color = TEAMS[f.team].col
	var body := StaticBody3D.new()
	node.add_child(body)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g: Vector2 = f.gate
	# Four walls; the one facing the island's middle has the gate in it.
	for side in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var along := Vector2(-side.y, side.x)
		var c2: Vector2 = side * H
		var half_len := H + WALL_T * 0.5
		if side == g:
			_wall_seg(st, body, c2 - along * half_len, c2 - along * GATE_W * 0.5)
			_wall_seg(st, body, c2 + along * GATE_W * 0.5, c2 + along * half_len)
		else:
			_wall_seg(st, body, c2 - along * half_len, c2 + along * half_len)
	# Corner towers with battlements and the team's banner.
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var tc := Vector3(cx * H, 0, cz * H)
			_box(st, tc + Vector3(0, 4.5, 0), Vector3(7, 12, 7))
			_shape(body, tc + Vector3(0, 4.5, 0), Vector3(7, 12, 7))
			for k in 4:
				for m in 3:
					var d := Vector2(-2.6 + m * 2.6, 3.1).rotated(k * PI * 0.5)
					_box(st, tc + Vector3(d.x, 11.1, d.y), Vector3(1.2, 1.2, 1.2))
			_banner(node, tc + Vector3(0, 10.5, 0), col)
	# Gate pillars and the arch over the gateway.
	var gc := Vector3(g.x * H, 0, g.y * H)
	var ga := Vector3(-g.y, 0, g.x)
	for s in [-1.0, 1.0]:
		var pc: Vector3 = gc + ga * s * (GATE_W * 0.5 + 1.0)
		_box(st, pc + Vector3(0, 2.75, 0), Vector3(2.4, 8.5, 2.4))
		_shape(body, pc + Vector3(0, 2.75, 0), Vector3(2.4, 8.5, 2.4))
	var arch_sz := Vector3(GATE_W + 4.4, 1.6, WALL_T + 0.6) if absf(g.y) > 0.5 else Vector3(WALL_T + 0.6, 1.6, GATE_W + 4.4)
	_box(st, gc + Vector3(0, 7.6, 0), arch_sz)
	_shape(body, gc + Vector3(0, 7.6, 0), arch_sz)
	# The heart stands on a stone pillar, over the walls: a beacon seen from
	# far off (and a target from outside the walls).
	_box(st, Vector3(0, -0.4, 0), Vector3(7, 1.0, 7))
	_box(st, Vector3(0, 3.5, 0), Vector3(2.6, 7.0, 2.6))
	_box(st, Vector3(0, 7.0, 0), Vector3(3.8, 0.6, 3.8))
	_shape(body, Vector3(0, -0.4, 0), Vector3(7, 1.0, 7))
	_shape(body, Vector3(0, 3.5, 0), Vector3(2.6, 7.0, 2.6))
	_shape(body, Vector3(0, 7.0, 0), Vector3(3.8, 0.6, 3.8))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _stone()
	node.add_child(mi)
	# The heart.
	var heart := FortHeart.new()
	heart.war = self
	heart.team = f.team
	heart.max_hp = HEART_HP[1]
	heart.hp = heart.max_hp
	heart.display_name = "قلب " + TEAMS[f.team].fort
	node.add_child(heart)
	heart.position = Vector3(0, HEART_Y, 0)
	f.heart = heart
	# The shop: a stall by the heart, between it and the gate.
	var shop := Vector3(g.x * 12.0 - g.y * 8.0, 0, g.y * 12.0 + g.x * 8.0)
	_stall(node, body, shop, col)
	f.shop = f.center + shop
	# The gate is shut by a wall of light until the war begins.
	var bar := StaticBody3D.new()
	node.add_child(bar)
	bar.position = gc + Vector3(0, 3.0, 0)
	var bsz := Vector3(GATE_W + 0.4, 8.0, 0.5) if absf(g.y) > 0.5 else Vector3(0.5, 8.0, GATE_W + 0.4)
	_shape(bar, Vector3.ZERO, bsz)
	var bm := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = bsz
	bm.mesh = bbox
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(col, 0.35)
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.mesh.material = gm
	bar.add_child(bm)
	f.barrier = bar
	# Its name over the gate.
	var lb := _label(TEAMS[f.team].fort, 96, col)
	lb.position = gc + Vector3(0, 10.0, 0)
	lb.visibility_range_end = 600.0
	node.add_child(lb)

func _wall_seg(st: SurfaceTool, body: StaticBody3D, a: Vector2, b: Vector2) -> void:
	var mid := (a + b) * 0.5
	var length := a.distance_to(b)
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var sz := Vector3(length, WALL_H + 1.5, WALL_T) if along_x else Vector3(WALL_T, WALL_H + 1.5, length)
	var c := Vector3(mid.x, (WALL_H - 1.5) * 0.5, mid.y)
	_box(st, c, sz)
	_shape(body, c, sz)
	# Battlements along the top.
	var n := int(length / 2.6)
	var dir := (b - a) / maxf(length, 0.01)
	for k in n:
		var p := a + dir * (1.3 + k * 2.6)
		_box(st, Vector3(p.x, WALL_H + 0.5, p.y), Vector3(1.2, 1.0, WALL_T) if along_x else Vector3(WALL_T, 1.0, 1.2))

## Market stall: a counter with weapon crates under an awning, "المتجر" over it.
func _stall(node: Node3D, body: StaticBody3D, at: Vector3, col: Color) -> void:
	var wood := WorldBuilder._static_wall("planks", 1.5, 0.3, 0.8)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, at + Vector3(0, 0.5, 0), Vector3(3.4, 1.0, 1.2))
	_shape(body, at + Vector3(0, 0.5, 0), Vector3(3.4, 1.0, 1.2))
	for x in [-1.6, 1.6]:
		for z in [-0.7, 0.7]:
			_box(st, at + Vector3(x, 1.4, z), Vector3(0.14, 2.8, 0.14))
	_box(st, at + Vector3(0.9, 1.25, 0), Vector3(1.0, 0.5, 0.6))
	_box(st, at + Vector3(-0.8, 1.2, 0.1), Vector3(1.2, 0.4, 0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = wood
	node.add_child(mi)
	var awning := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(3.8, 0.12, 2.0)
	awning.mesh = am
	var cm := StandardMaterial3D.new()
	cm.albedo_color = col.darkened(0.15)
	cm.roughness = 0.9
	awning.material_override = cm
	awning.position = at + Vector3(0, 2.85, 0)
	awning.rotation.x = 0.12
	node.add_child(awning)
	var lb := _label("المتجر", 64, Color("ffd34d"))
	lb.position = at + Vector3(0, 3.5, 0)
	lb.visibility_range_end = 60.0
	node.add_child(lb)

func _banner(node: Node3D, at: Vector3, col: Color) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.08
	pm.height = 5.0
	pole.mesh = pm
	pole.position = at + Vector3(0, 2.5, 0)
	node.add_child(pole)
	var flag := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 1.6)
	flag.mesh = q
	var fm := StandardMaterial3D.new()
	fm.albedo_color = col
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.emission_enabled = true
	fm.emission = col
	fm.emission_energy_multiplier = 0.25
	flag.material_override = fm
	flag.position = at + Vector3(1.35, 4.1, 0)
	node.add_child(flag)

func _label(text: String, size: int, col: Color) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font = load("res://assets/fonts/Cairo.ttf")
	lb.font_size = size
	lb.pixel_size = 0.02
	lb.outline_size = 14
	lb.modulate = col
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return lb

static var _stone_mat: Material
func _stone() -> Material:
	if _stone_mat == null:
		_stone_mat = WorldBuilder._static_wall("stone", 2.6, 0.5, 0.92)
	return _stone_mat

static func _box(st: SurfaceTool, c: Vector3, sz: Vector3) -> void:
	var h := sz * 0.5
	var corners := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 3, 2, 1, Vector3(0, 0, -1)], [4, 5, 6, 7, Vector3(0, 0, 1)], [0, 4, 7, 3, Vector3(-1, 0, 0)],
		[1, 2, 6, 5, Vector3(1, 0, 0)], [3, 7, 6, 2, Vector3(0, 1, 0)], [0, 1, 5, 4, Vector3(0, -1, 0)]]
	st.set_color(Color.WHITE)
	for f in faces:
		st.set_normal(f[4])
		for idx in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(c + corners[f[idx]])

static func _shape(body: StaticBody3D, c: Vector3, sz: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = sz
	cs.shape = b
	cs.position = c
	body.add_child(cs)

## A capture point: a tall pole with a flag in its owner's colour and a
## glowing ring on the ground round it.
func _build_point(pt: Dictionary) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = pt.pos
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.1
	pm.bottom_radius = 0.16
	pm.height = 14.0
	pole.mesh = pm
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.75, 0.76, 0.78)
	metal.metallic = 0.8
	metal.roughness = 0.35
	pole.material_override = metal
	pole.position.y = 7.0
	node.add_child(pole)
	var flag := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.4, 2.1)
	flag.mesh = q
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.9, 0.9, 0.9)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.emission_enabled = true
	fm.emission = Color(0.9, 0.9, 0.9)
	fm.emission_energy_multiplier = 0.3
	flag.material_override = fm
	flag.position = Vector3(1.75, 12.6, 0)
	node.add_child(flag)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = POINT_R - 0.35
	tm.outer_radius = POINT_R
	tm.rings = 64
	tm.ring_segments = 4
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1, 1, 1, 0.8)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.scale = Vector3(1, 0.3, 1)
	ring.position.y = 0.4
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ring)
	var lb := _label(pt.name, 72, Color.WHITE)
	lb.position.y = 16.0
	lb.visibility_range_end = 500.0
	node.add_child(lb)
	pt.flag_mat = fm
	pt.ring_mat = rm
	pt.label = lb

func _paint_point(pt: Dictionary) -> void:
	var col: Color = TEAMS[pt.owner].col if pt.owner >= 0 else Color(0.9, 0.9, 0.9)
	pt.flag_mat.albedo_color = col
	pt.flag_mat.emission = col
	pt.ring_mat.albedo_color = Color(col, 0.8)
	pt.label.modulate = col

# ---------------------------------------------------------------- queries
## Index of the fort whose walls enclose p (with padding), or -1.
func fort_at(p: Vector2, pad := 0.0) -> int:
	for f in forts:
		var c: Vector2 = f.pos
		if absf(p.x - c.x) < H + pad and absf(p.y - c.y) < H + pad: return f.team
	return -1

## Through the gate: [inside, outside] when leaving, [outside, inside] when coming in.
func gate_path(fi: int, leaving: bool) -> Array:
	var f: Dictionary = forts[fi]
	var g: Vector2 = f.gate
	var c: Vector2 = f.pos
	var inner := c + g * (H - 6.0)
	var outer := c + g * (H + 9.0)
	var a := Vector3(inner.x, f.y, inner.y)
	var b := Vector3(outer.x, world.island.height_at(outer.x, outer.y), outer.y)
	return [a, b] if leaving else [b, a]

## Corners to walk past so that going from a to b does not run into the
## walls of a fort on the way (none when nothing is in the way).
func around_forts(a: Vector3, b: Vector3) -> Array:
	var res := []
	var p := Vector2(a.x, a.z)
	var goal := Vector2(b.x, b.z)
	for f in forts:
		var c: Vector2 = f.pos
		if not world._crosses(p, goal, c, Vector2(H + 2.0, H + 2.0)): continue
		var hh := H + 8.0
		var cs := [c + Vector2(-hh, -hh), c + Vector2(hh, -hh), c + Vector2(hh, hh), c + Vector2(-hh, hh)]
		var inner := Vector2(H + 2.0, H + 2.0)
		var best := []
		var bd := INF
		for k in 4:
			var q: Vector2 = cs[k]
			if not world._crosses(p, q, c, inner) and not world._crosses(q, goal, c, inner):
				var d := p.distance_to(q) + q.distance_to(goal)
				if d < bd:
					bd = d
					best = [q]
			for k2 in [(k + 1) % 4, (k + 3) % 4]:
				var q2: Vector2 = cs[k2]
				if not world._crosses(p, q, c, inner) and not world._crosses(q2, goal, c, inner):
					var d2 := p.distance_to(q) + q.distance_to(q2) + q2.distance_to(goal)
					if d2 < bd:
						bd = d2
						best = [q, q2]
		for q in best:
			res.append(Vector3(q.x, world.island.height_at(q.x, q.y), q.y))
			p = q
	return res

func can_respawn(team: int) -> bool:
	return bool(forts[team].respawn) and not forts[team].heart.dead

## Teams still in the match: a heart to come back to, or someone alive.
func team_in(team: int) -> bool:
	if can_respawn(team): return true
	return world.team_alive(team)

func teams_in() -> int:
	var n := 0
	for t in 4:
		if team_in(t): n += 1
	return n

func alive_in(team: int) -> int:
	var n := 1 if world.player.team == team and world.player.state != "dead" else 0
	for b in world.bots:
		if b.team == team and not b.dead: n += 1
	return n

func near_shop(p: Vector3) -> bool:
	var f: Dictionary = forts[world.player.team]
	return Vector2(p.x - f.shop.x, p.z - f.shop.z).length() < 4.0

## Inside your own fort's walls (the shop is open to you there).
func in_own_fort(p: Vector3) -> bool:
	return fort_at(Vector2(p.x, p.z)) == world.player.team

func points_owned(team: int) -> int:
	var n := 0
	for pt in points:
		if pt.owner == team: n += 1
	return n

## Capture point the player stands in (or {}).
func point_here(p: Vector3) -> Dictionary:
	for pt in points:
		if Vector2(p.x - pt.pos.x, p.z - pt.pos.z).length() < POINT_R: return pt
	return {}

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if world.player == null or not world.ready_done or world.match_over: return
	time += delta
	if prep_left > 0.0:
		prep_left -= delta
		if prep_left <= 0.0: _open_gates()
	_point_t += delta
	if _point_t >= 0.5:
		_tick_points(_point_t)
		_point_t = 0.0
	_income_t += delta
	if _income_t >= 20.0:
		_income_t = 0.0
		_pay_income()
	_bank_t += delta
	if _bank_t >= 5.0:
		_bank_t = 0.0
		for f in forts: _spend(f)
	for t in _alert_t.keys(): _alert_t[t] -= delta
	# Hearts mend slowly when left alone.
	for f in forts:
		var h: FortHeart = f.heart
		if not h.dead and h.hit_t > 20.0 and h.hp < h.max_hp: h.hp = minf(h.max_hp, h.hp + 15.0 * delta)
	# Coming back.
	for r in _respawns.duplicate():
		r.t -= delta
		if r.t > 0.0: continue
		_respawns.erase(r)
		var old: Bot = r.old
		var team: int = old.team
		world.bots.erase(old)
		old.queue_free()
		if can_respawn(team):
			_spawn_bot(team, old.display_name, old.persona, old.skill, old.slot)
	if player_respawn > 0.0 and world.player.state == "dead":
		player_respawn -= delta
		if player_respawn <= 0.0:
			if can_respawn(world.player.team): respawn_player()
			else: _player_out()
	if not _warned_final and time > FINAL_AT - 120.0:
		_warned_final = true
		_announce("بعد دقيقتين قلوب الحصون بتنطفي — المعركة الأخيرة جاية!")
	if not final and time >= FINAL_AT:
		_final_battle()

func _open_gates() -> void:
	for f in forts:
		if is_instance_valid(f.barrier): f.barrier.queue_free()
		f.barrier = null
	_announce("⚔ الحرب بلّشت! البوابات انفتحت")
	if world.hud: world.hud.radio("البوابات انفتحت! الفرق الأربعة طالعة من حصونها — الله يستر")
	world.sound_boom(world.player.global_position + Vector3(0, 40, 0), -10.0, 0.7)

func _announce(text: String) -> void:
	if world.hud: world.hud.show_banner(text)

## Capture points: one team alone in the ring takes it (faster with more
## people); two or more teams there and nothing moves.
func _tick_points(dt: float) -> void:
	for pt in points:
		var counts := [0, 0, 0, 0]
		for a in world.actors():
			if not a.on_ground(): continue
			var ap: Vector3 = a.global_position
			if Vector2(ap.x - pt.pos.x, ap.z - pt.pos.z).length() < POINT_R: counts[a.team] += 1
		var present := []
		for t in 4:
			if counts[t] > 0: present.append(t)
		if present.size() != 1: continue
		var t: int = present[0]
		var rate := dt / CAPTURE_TIME * minf(3.0, 1.0 + (counts[t] - 1) * 0.5)
		if t == pt.owner:
			pt.prog = minf(1.0, pt.prog + rate)
		elif pt.owner >= 0:
			pt.prog -= rate
			if pt.prog <= 0.0:
				var lost: int = pt.owner
				pt.owner = -1
				pt.capper = t
				pt.prog = 0.0
				_paint_point(pt)
				if lost == world.player.team: _announce("خسرنا %s!" % pt.name)
		else:
			if pt.capper != t:
				pt.prog -= rate
				if pt.prog <= 0.0:
					pt.capper = t
					pt.prog = 0.0
			else:
				pt.prog += rate
				if pt.prog >= 1.0: _captured(pt, t)

func _captured(pt: Dictionary, t: int) -> void:
	pt.owner = t
	pt.prog = 1.0
	_paint_point(pt)
	forts[t].bank += 300
	var p: Player = world.player
	if t == p.team:
		if p.state != "dead" and Vector2(p.global_position.x - pt.pos.x, p.global_position.z - pt.pos.z).length() < POINT_R:
			money += 200
			_announce("🚩 احتلّيت %s! +200" % pt.name)
		else:
			_announce("🚩 فريقك احتلّ %s" % pt.name)
	elif world.hud:
		world.hud.radio("%s احتلّ %s" % [TEAMS[t].name, pt.name])

## Every 20 seconds: each place pays its owner, and you get your share.
func _pay_income() -> void:
	for pt in points:
		if pt.owner < 0: continue
		forts[pt.owner].bank += 120
		if pt.owner == world.player.team: money += 60
	money += 25

## The team's money goes into the fort: the next level when it can, and
## with money to spare, machine-gun towers and sandbag walls.
func _spend(f: Dictionary) -> void:
	if f.heart.dead or final: return
	var lvl: int = f.level
	var bank: int = f.bank
	if lvl < 3 and bank >= LEVEL_COST[lvl + 1]:
		f.bank = bank - LEVEL_COST[lvl + 1]
		level_up(f)
		return
	var keep: int = 0 if lvl >= 3 else 1000
	if build_free(f, "tower") and bank >= BUILDS.tower.price + keep:
		f.bank = bank - int(BUILDS.tower.price)
		build(f, "tower")
	elif build_free(f, "bags") and bank >= BUILDS.bags.price + keep:
		f.bank = bank - int(BUILDS.bags.price)
		build(f, "bags")

const BUILDS := {"tower": {"name": "برج رشاش", "price": 800, "max": 4}, "bags": {"name": "متاريس رمل", "price": 250, "max": 8}}

## Where towers and sandbag walls go, in the fort's own space (gate along g).
func _build_spots(f: Dictionary, kind: String) -> Array:
	var g: Vector2 = f.gate
	var a := Vector2(-g.y, g.x)
	if kind == "tower":
		return [g * (H - 3.5) + a * 9.5, g * (H - 3.5) - a * 9.5, a * (H - 3.5) - g * 10.0, -a * (H - 3.5) - g * 10.0]
	return [g * (H + 8.0) + a * 7.0, g * (H + 8.0) - a * 7.0, g * (H + 15.0), g * (H + 4.0) + a * 15.0,
		g * (H + 4.0) - a * 15.0, g * (H - 9.0) + a * 5.0, g * (H - 9.0) - a * 5.0, g * (H + 20.0) + a * 12.0]

func build_free(f: Dictionary, kind: String) -> bool:
	if kind == "tower":
		var alive := 0
		for t in f.towers:
			if is_instance_valid(t) and not t.dead: alive += 1
		return alive < int(BUILDS.tower.max)
	return int(f.bags) < int(BUILDS.bags.max)

## Puts up the next tower or sandbag wall at the fort.
func build(f: Dictionary, kind: String) -> void:
	var spots := _build_spots(f, kind)
	var node: Node3D = f.node
	if kind == "tower":
		# The first spot without a standing tower.
		var used := []
		for t in f.towers:
			if is_instance_valid(t) and not t.dead: used.append(t.get_meta("spot"))
		for i in spots.size():
			if i in used: continue
			var tw := WarTurret.new()
			tw.world = world
			tw.team = f.team
			tw.set_meta("spot", i)
			node.add_child(tw)
			var sp: Vector2 = spots[i]
			tw.position = Vector3(sp.x, 0, sp.y)
			f.towers.append(tw)
			break
	else:
		var i: int = f.bags
		var sp: Vector2 = spots[i]
		var g: Vector2 = f.gate
		var along_x := absf(g.y) > 0.5
		var at := Vector3(sp.x, 0, sp.y)
		var wp: Vector3 = f.center + at
		at.y = world.ground_height(wp) - float(f.y)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Three rows of bags, staggered.
		for row in 3:
			for k in 5 - (row % 2):
				var o := -2.4 + k * 1.2 + (0.6 if row % 2 == 1 else 0.0)
				var c := at + (Vector3(o, 0.2 + row * 0.36, 0) if along_x else Vector3(0, 0.2 + row * 0.36, o))
				_box(st, c, Vector3(1.1, 0.36, 0.6) if along_x else Vector3(0.6, 0.36, 1.1))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = WarTurret._sand_mat()
		node.add_child(mi)
		var body := StaticBody3D.new()
		node.add_child(body)
		_shape(body, at + Vector3(0, 0.55, 0), Vector3(6.0, 1.1, 0.7) if along_x else Vector3(0.7, 1.1, 6.0))
		f.bags = i + 1
		# Bots take cover behind it.
		world._cover_add(Vector2(wp.x, wp.z), 2.5)

## An armoured car for the team, parked outside the gate, facing out.
func spawn_apc(team: int) -> Vehicle:
	var f: Dictionary = forts[team]
	var g: Vector2 = f.gate
	var at: Vector2 = f.pos + g * (H + 14.0) + Vector2(-g.y, g.x) * 6.5
	var v := Vehicle.new()
	v.world = world
	v.kind = "apc"
	v.team = team
	v.position = Vector3(at.x, world.ground_height(Vector3(at.x, 0, at.y)) + 1.3, at.y)
	v.rotation.y = atan2(g.x, g.y)
	world.add_child(v)
	world.vehicles.append(v)
	return v

## The player hands money over to the fort (the team builds with it).
func donate(amount: int) -> void:
	var give := mini(amount, money)
	if give <= 0: return
	money -= give
	forts[world.player.team].bank += give
	_bank_t = 4.5          # spent right away

func level_up(f: Dictionary) -> void:
	f.level = int(f.level) + 1
	var h: FortHeart = f.heart
	var add: float = HEART_HP[f.level] - h.max_hp
	h.max_hp = HEART_HP[f.level]
	h.hp += add
	if f.team == world.player.team:
		_announce("🏰 حصنك صار مستوى %d — أسلحة أقوى بترجع فيها!" % f.level)
	elif world.hud:
		world.hud.radio("%s طوّر حصنه لمستوى %d" % [TEAMS[f.team].name, f.level])

# ---------------------------------------------------------------- hearts
## A shot (blast = false, a fraction gets through the crystal) or a blast hit a heart.
func hurt_heart(h: FortHeart, amount: float, attacker: Node, blast: bool) -> bool:
	if h.dead: return false
	if attacker != null and "team" in attacker and attacker.team == h.team: return false
	if prep_left > 0.0:
		if attacker == world.player: world.player.message.emit("القلب محمي لحتى تنفتح البوابات")
		return false
	var dmg := amount * (1.0 if blast else 0.2)
	h.hp -= dmg
	h.hit_t = 0.0
	if h.team == world.player.team and Time.get_ticks_msec() - _fort_vo_ms > 45000:
		_fort_vo_ms = Time.get_ticks_msec()
		world.announce("fort_attack")
	if attacker == world.player:
		_heart_cash += dmg * 0.1
		if _heart_cash >= 1.0:
			money += int(_heart_cash)
			_heart_cash -= float(int(_heart_cash))
	# The defenders turn on whoever is at it.
	if attacker is Node3D and float(_alert_t.get(h.team, 0.0)) <= 0.0:
		_alert_t[h.team] = 2.0
		var hp3: Vector3 = h.global_position
		for b in world.bots:
			if b.dead or b.team != h.team or b.target != null: continue
			if b.global_position.distance_to(hp3) < 140.0:
				b.target = attacker
				b.react_t = 0.3
		if h.team == world.player.team and float(_alert_t.get("say", 0.0)) <= 0.0:
			_alert_t["say"] = 25.0
			_announce("⚠ قلب حصنك تحت الهجوم!")
	if h.hp <= 0.0:
		_heart_destroyed(h, attacker)
		return true
	return false

func _heart_destroyed(h: FortHeart, attacker: Node) -> void:
	h.hp = 0.0
	h.shatter()
	var f: Dictionary = forts[h.team]
	var at: Vector3 = h.global_position + Vector3(0, 2.5, 0)
	world.effects.explosion(at)
	world.sound_boom(at, 8.0, 0.6)
	world.effects.smoke_cloud(at, 120.0, Color(0.15, 0.15, 0.16))
	for k in 3:
		get_tree().create_timer(0.4 + k * 0.5).timeout.connect(func():
			world.effects.explosion(at + Vector3(randf_range(-3, 3), randf_range(-1, 2), randf_range(-3, 3))))
	if attacker == world.player:
		money += 1000
		_announce("💥 كسرت قلب %s! +1000" % TEAMS[h.team].fort)
	elif h.team == world.player.team:
		_announce("💔 قلب حصنك انكسر — ما في رجعة بعد هلأ، دافع عن حالك!")
	else:
		_announce("💥 قلب %s انكسر — %s ما عاد يرجع" % [TEAMS[h.team].fort, TEAMS[h.team].name])
	if attacker != null and "team" in attacker and attacker.team != h.team:
		forts[attacker.team].bank += 2000
	if world.hud: world.hud.radio("قلب %s انكسر!" % TEAMS[h.team].fort)
	f.respawn = false
	check_end()

## A blast near a heart (grenades, the burning rocks, a car going up).
func blast(pos: Vector3, thrower: Node) -> void:
	for f in forts:
		var h: FortHeart = f.heart
		if h.dead: continue
		var d := pos.distance_to(h.global_position + Vector3(0, 2.0, 0))
		if d < Grenade.FRAG_RADIUS + 1.5:
			hurt_heart(h, Grenade.FRAG_DAMAGE * 2.0 * (1.0 - d / (Grenade.FRAG_RADIUS + 1.5)), thrower, true)

# ---------------------------------------------------------------- deaths
func on_kill(victim: Node, attacker: Node) -> void:
	if attacker == world.player and victim != world.player:
		money += 100
	elif attacker is Bot:
		forts[attacker.team].bank += 60
	if victim is Bot:
		if can_respawn(victim.team):
			_respawns.append({"old": victim, "t": BOT_RESPAWN})
		else:
			# No coming back: the body stays a while, then goes.
			var v: Bot = victim
			get_tree().create_timer(30.0).timeout.connect(func():
				if is_instance_valid(v) and v.dead:
					world.bots.erase(v)
					v.queue_free())
	check_end()

func on_player_died() -> void:
	if can_respawn(world.player.team):
		player_respawn = RESPAWN_TIME
		return
	_player_out()

## Dead with no heart to come back to: watch your team (or it's over).
func _player_out() -> void:
	player_respawn = -1.0
	if world.team_alive(world.player.team):
		world.hud.team_still_alive()
	else:
		check_end()

func respawn_player() -> void:
	var p: Player = world.player
	player_respawn = -1.0
	var f: Dictionary = forts[p.team]
	if world.hud: world.hud.end_spectate_for_respawn()
	# Died at the wheel: the car is free again, and so is the body.
	if p.vehicle != null:
		if is_instance_valid(p.vehicle) and p.vehicle.driver == p: p.vehicle.driver = null
		p.vehicle = null
	p.shape_node.disabled = false
	p.knocked = false
	p.killer = null
	p.spectate = null
	p.dead_t = 0.0
	p.model.death_anim = ""
	p.state = "ground"
	give_player_kit(p, int(f.level))
	p.global_position = _spawn_point(f)
	p.velocity = Vector3.ZERO
	p.yaw = atan2(-f.gate.x, -f.gate.y)
	p.reset_physics_interpolation()
	p.message.emit("رجعت! اشتري من المتجر واطلع للمعركة")

## The match is over when one team is left (or yours is out).
func check_end() -> void:
	if world.match_over: return
	var mine: int = world.player.team
	if not team_in(mine):
		world._end_match(false)
	elif teams_in() == 1:
		world._end_match(true)

# ---------------------------------------------------------------- the final battle
var _fort_vo_ms := -100000

func _final_battle() -> void:
	final = true
	world.announce("final_battle")
	for f in forts:
		f.respawn = false
	_respawns.clear()
	var c := Vector2.ZERO
	for pt in points: c += Vector2(pt.pos.x, pt.pos.z)
	c /= maxf(1.0, float(points.size()))
	var r := 0.0
	for f in forts: r = maxf(r, c.distance_to(f.pos) + 250.0)
	world.zone.start_war(c, r)
	_announce("🔥 المعركة الأخيرة! القلوب انطفت — ما في رجعة، والمنطقة عم تسكّر عالنص")
	if world.hud: world.hud.radio("المعركة الأخيرة! ما في رجعة لحدا — آخر فريق واقف بياخدها")
	check_end()

# ---------------------------------------------------------------- bots
## A bot's team-war plans (after fights, healing and the zone, before its
## usual looting and roaming). True when it has something to do.
func bot_think(b: Bot) -> bool:
	var f: Dictionary = forts[b.team]
	if prep_left > 0.0:
		_wander(b, f.center, H - 8.0, "roam")
		return true
	if final: return false
	match b.war_role:
		"defend":
			# Half by the heart, half round the gate.
			var g: Vector2 = f.gate
			var spot: Vector3 = f.center if b.slot % 2 == 0 else f.center + Vector3(g.x, 0, g.y) * (H + 14.0)
			_wander(b, spot, 18.0, "roam")
			return true
		"raid":
			var ti := _raid_target(b)
			if ti < 0:
				b.war_role = "capture"
				return bot_think(b)
			var h: FortHeart = forts[ti].heart
			var hp3: Vector3 = h.global_position
			var d := b.global_position.distance_to(hp3)
			var inside := fort_at(Vector2(b.global_position.x, b.global_position.z)) == ti
			if not b.war_push and not inside:
				# Raiders meet up out of sight of the gate and go in together.
				var tf: Dictionary = forts[ti]
				var r2: Vector2 = tf.pos + tf.gate * (H + 170.0) + Vector2(-tf.gate.y, tf.gate.x) * (float(b.team) - 1.5) * 30.0
				var rally := Vector3(r2.x, world.island.height_at(r2.x, r2.y), r2.y)
				if b.global_position.distance_to(rally) > 30.0:
					if b.mode != "march" or b.goal.distance_to(rally) > 20.0:
						b.mode = "march"
						b._go(rally + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10)))
					return true
				if b.war_since < 0.0: b.war_since = time
				var near := 0
				for o in world.bots:
					if o.team == b.team and not o.dead and o.war_role == "raid" and o.global_position.distance_to(rally) < 60.0: near += 1
				if near >= 4 or time - b.war_since > 45.0:
					b.war_push = true
				else:
					_wander(b, rally, 12.0, "hold")
					return true
			if inside or d < 30.0 or (d < 75.0 and _sees_heart(b, h)):
				b.target = h
				b.react_t = minf(b.react_t, 0.4)
				b.engage_t = 0.0
				b.mode = "fight"
				return true
			var fc: Vector3 = forts[ti].center
			if b.mode != "march" or b.goal.distance_to(fc) > 12.0:
				b.mode = "march"
				b._go(fc + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)))
			return true
		_:
			var pi := _capture_target(b)
			if pi < 0: return false
			var pt: Dictionary = points[pi]
			var pp: Vector3 = pt.pos
			if b.global_position.distance_to(pp) > POINT_R - 4.0:
				if b.mode != "march" or b.goal.distance_to(pp) > POINT_R:
					b.mode = "march"
					b._go(pp + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)))
			else:
				_wander(b, pp, POINT_R - 6.0, "hold")
			return true

## The enemy heart a pushing raider can shoot at right now (or null).
func raid_heart(b: Bot) -> FortHeart:
	if b.war_goal < 0 or b.war_goal == b.team: return null
	var h: FortHeart = forts[b.war_goal].heart
	if h.dead: return null
	var d := b.global_position.distance_to(h.global_position)
	if d > 160.0: return null
	if fort_at(Vector2(b.global_position.x, b.global_position.z)) == b.war_goal or d < 30.0 or _sees_heart(b, h): return h
	return null

## A clear line from the bot's eyes to the heart (through the gate).
func _sees_heart(b: Bot, h: FortHeart) -> bool:
	var q := PhysicsRayQueryParameters3D.create(b.global_position + Vector3(0, 1.5, 0), h.global_position + Vector3(0, 2.4, 0), 1)
	q.exclude = [b.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider == h

## The enemy fort a raider goes for: its pick while that heart stands.
func _raid_target(b: Bot) -> int:
	if b.war_goal >= 0 and b.war_goal != b.team and not forts[b.war_goal].heart.dead: return b.war_goal
	var best := -1
	var bd := INF
	for f in forts:
		if f.team == b.team or f.heart.dead: continue
		var d: float = Vector2(b.global_position.x, b.global_position.z).distance_to(f.pos) * randf_range(0.8, 1.25)
		if d < bd:
			bd = d
			best = f.team
	b.war_goal = best
	return best

## A place to take: the nearest one the team doesn't hold (or, all held, keep one).
func _capture_target(b: Bot) -> int:
	if b.war_goal >= 0 and b.war_goal < points.size() and points[b.war_goal].owner != b.team: return b.war_goal
	var best := -1
	var bd := INF
	var bp := Vector2(b.global_position.x, b.global_position.z)
	for i in points.size():
		var pt: Dictionary = points[i]
		var d := bp.distance_to(Vector2(pt.pos.x, pt.pos.z)) * (0.6 if pt.owner != b.team else 2.5) * randf_range(0.85, 1.15)
		if d < bd:
			bd = d
			best = i
	b.war_goal = best
	return best

## Mill about within r of c (a new spot each time it gets there).
func _wander(b: Bot, c: Vector3, r: float, mode: String) -> void:
	if b.mode == mode and b.global_position.distance_to(b.goal) > 2.5 and b.goal.distance_to(c) < r + 2.0: return
	b.mode = mode
	var p := c + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
	b._go(Vector3(p.x, world.ground_height(p), p.z))
