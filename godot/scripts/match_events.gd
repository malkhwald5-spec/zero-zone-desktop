class_name MatchEvents
extends Node3D
## Surprises in the middle of a match, two per game, never the same twice:
## - "crash":    a cargo plane comes down burning inside the next safe zone;
##               the wreck holds two crates' worth of rare loot;
## - "eruption": the volcano erupts: burning rocks rain down round the crater
##               for a minute (they explode where they land), ash in the air;
## - "quake":    the ground shakes for a few seconds, dust bursts from the
##               houses round you;
## - "sandstorm": Dune Valley only: a wall of sand blows through the whole
##               valley for a minute, you can barely see 60 m.
## Besides these, every few minutes a red zone (as in PUBG): a circle inside
## the play area marked on the map, then shelled for half a minute. A roof
## and walls keep you safe; out in the open you'd better run.

const KINDS := ["crash", "eruption", "quake", "sandstorm"]
## Zone phases at whose start an event happens.
const AT_PHASES := [1, 3]

var world: Node
var _done_phases := {}
var _used: Array[String] = []
var _bombs: Array = []            # {node, vel, life}
var _erupt_t := 0.0
var _quake_t := 0.0
var _storm_t := 0.0
var _volcano_spots: Array[Vector2] = []

func setup(w: Node) -> void:
	world = w
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Where burning rocks can land: the volcano region.
	var isl = world.island
	for k in 4000:
		var q: Vector2 = Vector2(randf(), randf()) * isl.size
		if isl.region_at(q.x, q.y) == "volcano" and isl.is_land(q.x, q.y):
			_volcano_spots.append(q)
			if _volcano_spots.size() >= 120: break

func _process(delta: float) -> void:
	var z = world.zone
	if z.phase in AT_PHASES and not _done_phases.has(z.phase) and z.state == "wait":
		_done_phases[z.phase] = true
		start(_pick())
	_tick_eruption(delta)
	_tick_quake(delta)
	_tick_red(delta)
	_tick_storm(delta)

func _pick() -> String:
	var dunes: bool = world.island.map_id == "dunes"
	var left := KINDS.filter(func(k): return not k in _used and (k != "eruption" or not _volcano_spots.is_empty()) and (k != "sandstorm" or dunes))
	# Dune Valley always gets its sandstorm.
	if dunes and not "sandstorm" in _used and _used.size() >= 1: return "sandstorm"
	return left[randi() % left.size()] if not left.is_empty() else "quake"

func start(kind: String) -> void:
	_used.append(kind)
	match kind:
		"crash": _crash()
		"eruption":
			_erupt_t = 60.0
			_banner("🌋 البركان ثار! ابعد عن الجبل — صخور نار عم تنزل")
		"sandstorm":
			_storm_t = 65.0
			_banner("🌪 عاصفة رملية جاية! الرؤية رح تقل كتير — استغلها وتحرّك")
		"quake":
			_quake_t = 6.0
			_banner("⚠ زلزال! الأرض عم تهتز")

func _banner(text: String) -> void:
	if world.hud:
		world.hud.show_banner(text)
		world.hud.radio({"crash": "عاجل: طيارة شحن سقطت! الكل رايح ع الحطام", "eruption": "البركان صحي! اللي قريب من الجبل الله يعينه",
			"quake": "زلزال! تمسّكوا بشي", "sandstorm": "عاصفة رملية! ما حدا شايف حدا — وقت الهجوم أو الهروب"}.get(_used.back() if not _used.is_empty() else "", "خبر عاجل!"))

# ---------- Plane crash ----------
func _crash() -> void:
	var z = world.zone
	var spot := Vector3.ZERO
	for k in 60:
		var q: Vector2 = z.next_center + Vector2(randf() * z.next_radius * 0.6, 0).rotated(randf() * TAU)
		if world.island.is_land(q.x, q.y) and not world.island.is_deep(q.x, q.y) and not world._in_building(q, 12.0):
			spot = Vector3(q.x, world.island.height_at(q.x, q.y), q.y)
			break
	if spot == Vector3.ZERO: return
	# The wreck: the cargo plane nose down in the ground, broken and burning.
	var wreck: Node3D = world._plane_model()
	world.add_child(wreck)
	wreck.global_position = spot + Vector3(0, 1.5, 0)
	wreck.rotation = Vector3(-0.35, randf() * TAU, 0.25)
	for pr in wreck.get_meta("props", []): pr.visible = false
	for mi in wreck.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.16, 0.15, 0.14)
		m.roughness = 0.9
		(mi as MeshInstance3D).material_overlay = m
		(mi as MeshInstance3D).transparency = 0.0
	world.effects.explosion(spot + Vector3(0, 2, 0))
	world.sound_boom(spot)
	world.effects.fire(spot + Vector3(3, 0, 2), 240.0, 4.0)
	world.effects.fire(spot + Vector3(-4, 0, -3), 240.0, 3.0)
	world.effects.smoke_cloud(spot + Vector3(0, 2, 0), 240.0, Color(0.12, 0.12, 0.13))
	# Two crates of rare loot thrown clear of the fire.
	for off in [Vector3(9, 0, 0), Vector3(-8, 0, 7)]:
		var p: Vector3 = spot + off
		p.y = world.ground_height(p)
		var ad := Airdrop.new()
		ad.world = world
		ad.target = p
		world.add_child(ad)
		ad.global_position = p
		world.airdrops.append(ad)
	_banner("✈ طيارة شحن وقعت جوّا المنطقة الآمنة! — غنايم نادرة بالحطام")

# ---------- Volcano ----------
func _tick_eruption(delta: float) -> void:
	if _erupt_t > 0.0:
		_erupt_t -= delta
		if randf() < delta * 3.0: _bomb()
	for b in _bombs.duplicate():
		b.vel += Vector3(0, -9.8, 0) * delta
		b.node.global_position += b.vel * delta
		b.node.rotate_x(delta * 4.0)
		var p: Vector3 = b.node.global_position
		if p.y <= world.ground_height(p) + 0.5:
			world.explode(Vector3(p.x, world.ground_height(p), p.z), null)
			b.node.queue_free()
			_bombs.erase(b)

## A burning rock thrown up and out of the crater, landing on the slopes.
func _bomb() -> void:
	var at: Vector2 = _volcano_spots[randi() % _volcano_spots.size()]
	var land := Vector3(at.x, world.island.height_at(at.x, at.y), at.y)
	var from := land + Vector3(randf_range(-60, 60), 160.0, randf_range(-60, 60))
	var t := 5.0
	var vel := (land - from) / t - Vector3(0, -9.8, 0) * t * 0.5
	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.9
	sm.height = 1.6
	sm.radial_segments = 8
	sm.rings = 4
	rock.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.08, 0.04)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.4, 0.08)
	m.emission_energy_multiplier = 4.0
	rock.material_override = m
	var trail := CPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 1.4
	trail.local_coords = false
	trail.gravity = Vector3(0, 1.5, 0)
	trail.initial_velocity_max = 0.5
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_color = Color(0.25, 0.22, 0.2, 0.5)
	q.material = tm
	trail.mesh = q
	rock.add_child(trail)
	world.add_child(rock)
	rock.global_position = from
	_bombs.append({"node": rock, "vel": vel})

# ---------- Red zone ----------
const RED_WARN := 8.0             # seconds marked on the map before the first shell
const RED_TIME := 24.0            # seconds of shelling
var red_t := 0.0                  # > 0 while a red zone is on (warning, then shelling)
var red_center := Vector2.ZERO
var red_radius := 0.0
var _red_next := 170.0            # seconds until the next one
var _shells: Array = []           # {pos, t}: a shell on its way down

func red_on() -> bool:
	return red_t > 0.0

func in_red(p: Vector3) -> bool:
	return red_t > 0.0 and Vector2(p.x, p.z).distance_to(red_center) < red_radius

func _tick_red(delta: float) -> void:
	for s in _shells.duplicate():
		s.t -= delta
		if s.t <= 0.0:
			_shells.erase(s)
			world.explode(s.pos, null)
	var z = world.zone
	if z.phase < 1 or z.state == "done" or z.radius < 120.0 or world.match_over: return
	if red_t <= 0.0:
		_red_next -= delta
		if _red_next <= 0.0:
			_red_next = randf_range(150.0, 230.0)
			start_red()
		return
	red_t -= delta
	if red_t < RED_TIME and randf() < delta * 2.4: _shell()

## Marks a red zone somewhere on land inside the current circle.
func start_red() -> void:
	var z = world.zone
	red_radius = clampf(z.radius * 0.35, 60.0, 120.0)
	for k in 40:
		var q: Vector2 = z.center + Vector2(randf() * maxf(0.0, z.radius - red_radius), 0).rotated(randf() * TAU)
		if world.island.is_land(q.x, q.y):
			red_center = q
			red_t = RED_WARN + RED_TIME
			if world.hud:
				world.hud.show_banner("🔴 منطقة حمراء! قصف بعد ثواني — ادخل بيت أو اطلع منها")
				world.hud.radio("منطقة حمراء على الخريطة! اللي برّا البيوت يتخبّى")
			return

## One shell: it lands where a line from the sky meets the first thing in
## the way (a roof takes it, not the room under it).
func _shell() -> void:
	var q := red_center + Vector2(sqrt(randf()) * red_radius, 0).rotated(randf() * TAU)
	var top := Vector3(q.x, 400.0, q.y)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(top, Vector3(q.x, -50.0, q.y), 1))
	var at: Vector3 = hit.position if not hit.is_empty() else Vector3(q.x, world.ground_height(Vector3(q.x, 0, q.y)), q.y)
	_shells.append({"pos": at, "t": 0.0})

# ---------- Earthquake ----------
func _tick_quake(delta: float) -> void:
	if _quake_t <= 0.0: return
	_quake_t -= delta
	var p: Player = world.player
	if p and p.state in ["ground", "vehicle"]:
		p.shake = maxf(p.shake, 0.9)
	# Dust bursting from the houses near the player.
	if p and randf() < delta * 4.0:
		for b in world.island.buildings:
			if Vector2(b.pos.x - p.global_position.x, b.pos.y - p.global_position.z).length() < 120.0 and randf() < 0.3:
				var at := Vector3(b.pos.x + randf_range(-4, 4), 0, b.pos.y + randf_range(-4, 4))
				at.y = world.ground_height(at) + 1.0
				world.effects.smoke_cloud(at, 6.0, Color(0.6, 0.55, 0.48))
				break

# ---------- Sandstorm (Dune Valley) ----------
func _tick_storm(delta: float) -> void:
	var fx: RegionFx = world.get("region_fx")
	if fx == null: return
	if _storm_t > 0.0:
		_storm_t -= delta
		# Builds up over 8 s, holds, and dies away over the last 10 s.
		fx.storm = move_toward(fx.storm, clampf(_storm_t / 10.0, 0.0, 1.0), delta / 8.0)
	else:
		fx.storm = move_toward(fx.storm, 0.0, delta / 6.0)
