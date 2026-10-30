class_name SpawnIsland
extends Node3D
## The waiting island before the match (like PUBG's spawn island): a small
## grassy island out at sea, off the map. Everyone waits here for a minute,
## picks up the guns lying about and shoots for fun (nobody can be hurt),
## then the whole lobby boards the plane with empty hands.

const RADIUS := 44.0          # the flat grassy top (m)
const TOP := 1.5              # its height above the sea
const WAIT := 30.0            # seconds before the plane leaves (or "ready")
const WALKERS := 26           # other players milling about
const GUNS := ["m416", "akm", "ump", "scar", "vector", "uzi", "s1897", "kar98", "p92", "beryl", "mini14", "sks"]

var world: Node
var left := WAIT
var _walkers: Array = []      # {m, goal: Vector2, wait, burst, shots, gun}
var _blocks: Array = []       # footprints (local Rect2) nobody walks through

func setup(w: Node, centre: Vector3) -> void:
	world = w
	w.add_child(self)
	global_position = centre
	_ground()
	_buildings()
	_trees()
	_flowers()
	_loot()
	_people()

## Local position on the grass from a point on the island's plan.
func _at(p: Vector2) -> Vector3:
	return global_position + Vector3(p.x, TOP, p.y)

func _material(tex: String, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/%s_col.jpg" % tex)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/%s_nrm.jpg" % tex)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = 0.95
	return m

## Grassy top on a sandy beach that runs down under the sea.
func _ground() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	for part in [[RADIUS, RADIUS + 10.0, 8.0, TOP, "grass", 0.25], [RADIUS + 7.0, RADIUS + 26.0, 9.0, TOP - 0.7, "sand", 0.2]]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = part[0]
		cyl.bottom_radius = part[1]
		cyl.height = part[2]
		cyl.radial_segments = 48
		cyl.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = _material(part[4], part[5])
		mi.position.y = float(part[3]) - float(part[2]) * 0.5
		add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = cyl.create_convex_shape()
		cs.position = mi.position
		body.add_child(cs)

## Two old houses you can walk into (the same model as in the towns).
func _buildings() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	for b in [["bld_abandoned", Vector2(-15, -13), 0.0], ["bld_abandoned", Vector2(17, 9), PI / 2]]:
		var mh: Array = WorldBuilder._model_building(b[0])
		var mi := MeshInstance3D.new()
		mi.mesh = mh[0]
		mi.position = Vector3(b[1].x, TOP, b[1].y)
		mi.rotation.y = b[2]
		add_child(mi)
		var fp: Vector2 = Island.MODEL_BUILDINGS[b[0]]
		if b[2] != 0.0: fp = Vector2(fp.y, fp.x)
		var cs := CollisionShape3D.new()
		if mh[2]:
			cs.shape = mh[2]
			cs.transform = Transform3D(Basis(Vector3.UP, b[2]), mi.position)
		else:
			var box := BoxShape3D.new()
			box.size = Vector3(fp.x, mh[1], fp.y)
			cs.shape = box
			cs.position = mi.position + Vector3(0, mh[1] * 0.5, 0)
		body.add_child(cs)
		_blocks.append(Rect2(b[1] - fp * 0.5 - Vector2(1.5, 1.5), fp + Vector2(3, 3)))

## Palms round the edge.
func _trees() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		var p := Vector2(cos(a), sin(a)) * rng.randf_range(RADIUS - 9.0, RADIUS - 3.0)
		var mesh: ArrayMesh = TreeModels.imported("palm_a" if i % 2 == 0 else "palm_b")
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var h := mesh.get_aabb().size.y
		mi.scale = Vector3.ONE * rng.randf_range(8.0, 11.0) / maxf(h, 0.1)
		mi.position = Vector3(p.x, TOP - 0.1, p.y)
		mi.rotation.y = rng.randf() * TAU
		add_child(mi)
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.3
		cy.height = 4.0
		cs.shape = cy
		cs.position = mi.position + Vector3(0, 2.0, 0)
		body.add_child(cs)
		_blocks.append(Rect2(p - Vector2(1, 1), Vector2(2, 2)))

## Patches of wild flowers and weeds (crossed cards).
func _flowers() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := k * PI / 2
		var d := Vector3(cos(a), 0, sin(a)) * 0.5
		var n := Vector3(-d.z, 0, d.x).normalized()
		for v in [[-d, 0.0, 1.0], [d, 1.0, 1.0], [d + Vector3.UP, 1.0, 0.0], [-d, 0.0, 1.0], [d + Vector3.UP, 1.0, 0.0], [-d + Vector3.UP, 0.0, 0.0]]:
			st.set_normal(Vector3.UP.lerp(n, 0.3).normalized())
			st.set_uv(Vector2(v[1], v[2]))
			st.add_vertex(v[0])
	var card := st.commit()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for tex in ["lupine_atlas.png", "weeds_a.png", "weeds_b.png"]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/nature/" + tex)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.9
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = card
		mm.instance_count = 140
		for i in mm.instance_count:
			# Clumps: a few centres with plants gathered round them.
			var c := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(6.0, RADIUS - 4.0)
			if i % 7 != 0: c = _last_clump
			_last_clump = c
			var p := c + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
			var s := rng.randf_range(0.6, 1.1)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(p.x, TOP - 0.02, p.y)))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

var _last_clump := Vector2.ZERO

## Guns with a box of rounds next to each, a few grenades and smokes.
func _loot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n := 0
	for k in 200:
		if n >= 18: break
		var p := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * (RADIUS - 6.0)
		if p.length() > RADIUS - 6.0 or p.length() < 4.0 or _blocked(p): continue
		var id: String = GUNS[n % GUNS.size()]
		world._add_pickup({"kind": "weapon", "id": id, "mag": int(Game.WEAPONS[id].get("mag", 30))}, _at(p))
		var at: String = Game.WEAPONS[id].ammo
		world._add_pickup({"kind": "ammo", "type": at, "amount": {"12g": 20, "bolt": 15}.get(at, 90)}, _at(p + Vector2(0.7, 0.4)))
		if n % 4 == 1: world._add_pickup({"kind": "throw", "id": "frag" if n % 8 == 1 else "smoke", "n": 2}, _at(p + Vector2(-0.6, 0.5)))
		n += 1

func _blocked(p: Vector2) -> bool:
	for r: Rect2 in _blocks:
		if r.has_point(p): return true
	return false

func _free_spot(rng_r: float) -> Vector2:
	for k in 40:
		var p := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * rng_r
		if p.length() <= rng_r and not _blocked(p): return p
	return Vector2.ZERO

## Other players: walk about, stop, now and then fire a burst into the air.
func _people() -> void:
	for i in WALKERS:
		var m := HumanModel.new(Color.from_hsv(randf(), 0.35, 0.45), Color.from_hsv(randf(), 0.6, 0.85), Color.from_hsv(randf(), 0.2, 0.25),
			HumanModel.BOT_CHARACTERS[randi() % HumanModel.BOT_CHARACTERS.size()], randf() < 0.6)
		add_child(m)
		m.set_gear(0, 0, 0)
		var p := _free_spot(RADIUS - 5.0)
		m.position = Vector3(p.x, TOP, p.y)
		m.rotation.y = randf() * TAU
		var gun := ""
		if randf() < 0.55:
			gun = GUNS[randi() % GUNS.size()]
			m.set_weapon(gun)
		_walkers.append({"m": m, "goal": _free_spot(RADIUS - 5.0), "wait": randf_range(0.0, 4.0), "burst": randf_range(4.0, 20.0), "shots": 0, "cd": 0.0, "gun": gun, "run": randf() < 0.3})

func _process(delta: float) -> void:
	left -= delta
	var t: float = world.time
	for w in _walkers:
		var m: HumanModel = w.m
		var here := Vector2(m.position.x, m.position.z)
		var speed := 0.0
		if w.wait > 0.0:
			w.wait -= delta
		else:
			var to: Vector2 = w.goal - here
			if to.length() < 0.6:
				w.wait = randf_range(1.5, 6.0)
				w.goal = _free_spot(RADIUS - 5.0)
				w.run = randf() < 0.3
			else:
				speed = 3.6 if w.run else 1.5
				var step := to.normalized() * minf(speed * delta, to.length())
				if _blocked(here + step * 4.0):
					# Something in the way: pick somewhere else.
					w.goal = _free_spot(RADIUS - 5.0)
				else:
					m.position += Vector3(step.x, 0, step.y)
				m.rotation.y = lerp_angle(m.rotation.y, atan2(-to.x, -to.y), minf(1.0, delta * 8.0))
		# Showing off: a few shots into the sky while standing still.
		m.aiming = false
		if w.gun != "" and speed == 0.0:
			w.burst -= delta
			if w.burst <= 0.0 and w.shots == 0:
				w.shots = randi_range(3, 8)
			if w.shots > 0:
				m.aiming = true
				w.cd -= delta
				if w.cd <= 0.0:
					w.cd = 0.13
					w.shots -= 1
					m.recoil = 1.0
					world.sound_shot(Game.WEAPONS[w.gun].cls, m.global_position + Vector3(0, 1.5, 0), false, false, w.gun)
					if w.shots == 0: w.burst = randf_range(8.0, 25.0)
		m.move_local = Vector2(0, speed)
		m.sprinting = w.run and speed > 0.0
		m.set_pose("stand", speed, w.gun != "", delta, t)

func _physics_process(_delta: float) -> void:
	# Nobody wanders off into the sea.
	var p: Node3D = world.player
	if p == null or p.state != "ground": return
	var off := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z)
	var lim := RADIUS + 9.0
	if off.length() > lim:
		off = off.normalized() * lim
		p.global_position = Vector3(global_position.x + off.x, p.global_position.y, global_position.z + off.y)

## The guns and everything else lying about (or dropped) here go with the island.
func clear_loot() -> void:
	for it in world.pickups.duplicate():
		if is_instance_valid(it) and Vector2(it.global_position.x - global_position.x, it.global_position.z - global_position.z).length() < RADIUS + 40.0:
			world._remove_pickup(it)
