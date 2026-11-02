extends Node
## A film of the game as it is now, every change in its own shot, the player
## moved by the game's own controls (no posing by hand):
##  seasons: holding the rifle still, walk, run, sprint, aiming and firing,
##  crouch (squat), crouch aim, prone, prone aim, guns put away on the back,
##  weapon skins, the camo jeep driven, a field of tall grass, the game camera.
##  dunes (--map=dunes): the jump, freefall and parachute over Dune Valley,
##  the landing, a walk through the old city, the sandstorm.
## Film: godot --path godot --write-movie out.avi --fixed-fps 30 res://tests/showcase_film.tscn -- [--map=dunes]
## "FILM <label> <frame>" lines give the timeline.

var world: Node
var p: Player
var cam: Camera3D
var dunes := false
var _frames := 0
var _want_pos := Vector3.ZERO
var _want_look := Vector3.ZERO
var _follow: Callable = Callable()
var _cam_k := 4.0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func mark(label: String) -> void:
	print("FILM %s %d" % [label, _frames])

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--map=dunes": dunes = true
	Game.settings.controls = "touch"
	Game.settings.weather = "clear"
	Game.settings.mode = "solo"
	Game.settings.lite = false
	Game.settings.quality = "high"
	Game.spawn_island = false
	Game.training = false
	Game.profile.gun_skin = ""
	_run.call_deferred()

func _process(delta: float) -> void:
	_frames += 1
	if p and is_instance_valid(p): p.health = 100.0
	if cam and _follow.is_valid():
		var r: Array = _follow.call()
		_want_pos = r[0]
		_want_look = r[1]
		var k := minf(1.0, delta * _cam_k)
		cam.global_position = cam.global_position.lerp(_want_pos, k)
		var cur_look: Vector3 = cam.global_position - cam.global_basis.z * 5.0
		cam.look_at(cur_look.lerp(_want_look, k) if cam.global_position.distance_to(_want_look) > 0.5 else _want_look)

## Camera relative to the player: forward, right, up (metres), looking at a height on them.
func follow(fwd: float, right: float, up: float, look_h := 1.1, k := 4.0, snap := true) -> void:
	_cam_k = k
	_follow = func() -> Array:
		var b: Basis = p.model.global_basis if p.vehicle == null else p.vehicle.global_basis.rotated(Vector3.UP, PI)
		var f: Vector3 = -b.z
		f.y = 0.0
		f = f.normalized()
		var r := f.cross(Vector3.UP).normalized()
		var base: Vector3 = p.global_position
		return [base + f * fwd + r * right + Vector3(0, up, 0), base + Vector3(0, look_h, 0)]
	if snap:
		var r0: Array = _follow.call()
		cam.global_position = r0[0]
		cam.look_at(r0[1])

func game_cam() -> void:
	_follow = Callable()
	cam.current = false
	world.hud.visible = true

func film_cam() -> void:
	cam.current = true
	world.hud.visible = false

func _flat_spot(isl, near: Vector2, flat_r := 14.0) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 3000:
		var q := near + Vector2(rng.randf_range(-260, 260), rng.randf_range(-260, 260))
		if not isl.is_land(q.x, q.y) or world.building_at(q, 14.0) >= 0: continue
		var h0: float = isl.height_at(q.x, q.y)
		if h0 < 2.0: continue
		var ok := true
		for d in [Vector2(flat_r, 0), Vector2(-flat_r, 0), Vector2(0, flat_r), Vector2(0, -flat_r)]:
			if absf(isl.height_at(q.x + d.x, q.y + d.y) - h0) > 0.6: ok = false
		if ok: return Vector3(q.x, h0, q.y)
	return Vector3(near.x, isl.height_at(near.x, near.y), near.y)

func place(at: Vector3, yaw := 0.0) -> void:
	if p.vehicle: p.exit_vehicle(true)
	p.global_position = Vector3(at.x, world.ground_height(at) + 0.3, at.z)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	p.yaw = yaw
	p.pitch = -0.05
	p.touch_move = Vector2.ZERO
	p.sprinting = false
	p.aiming = false

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	for i in 3000:
		world = tree.current_scene
		if world and world.get("ready_done"): break
		await wait(0.1)
	p = world.player
	cam = Camera3D.new()
	cam.fov = 42.0
	world.add_child(cam)
	if dunes: await _dunes()
	else: await _seasons()
	print("SHOWCASE DONE")
	tree.quit()

# ------------------------------------------------------------------ seasons
func _seasons() -> void:
	p.jump_from_plane()
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(9000, -80, 9000)
		b.visible = false
	var isl = world.island
	# A town out on the green plains (not the snow or the desert).
	var t: Dictionary = isl.towns[0]
	for tt in isl.towns:
		if isl.region_at(tt.pos.x, tt.pos.y) == "plains":
			t = tt
			break
	var at := _flat_spot(isl, t.pos + Vector2(float(t.r) + 60.0, 0))
	place(at)
	p._land()
	place(at)
	p.give_weapon("akm", 30)
	p.switch_slot(0)
	p.give_weapon("m249", 100)
	p.switch_slot(0)
	p.equip("vest", 3, 100.0)
	p.equip("helmet", 3, 100.0)
	p.equip("pack", 3, 0.0)
	await wait(2.0)
	place(at)
	film_cam()
	# 1. Holding the rifle across the chest, standing still: a slow turn round.
	mark("stand")
	var ang := [0.0]
	_cam_k = 3.0
	_follow = func() -> Array:
		ang[0] += 0.006
		var c: Vector3 = p.global_position
		var d := Vector3(sin(ang[0] + 0.3), 0, -cos(ang[0] + 0.3))
		return [c + d * 3.0 + Vector3(0, 1.35, 0), c + Vector3(0, 1.15, 0)]
	cam.global_position = p.global_position + Vector3(sin(0.3), 0, -cos(0.3)) * 3.0 + Vector3(0, 1.35, 0)
	await wait(4.5)
	# 2. Walk, run, sprint: the camera alongside.
	mark("walk")
	follow(0.6, 3.6, 1.2, 1.0, 5.0)
	p.touch_move = Vector2(0, 0.45)
	await wait(3.0)
	mark("run")
	p.touch_move = Vector2(0, 1)
	await wait(3.0)
	mark("sprint")
	p.sprinting = true
	follow(-0.5, 3.8, 1.3, 1.0, 6.0, false)
	await wait(3.0)
	p.sprinting = false
	p.touch_move = Vector2.ZERO
	await wait(1.0)
	# 3. Aiming and firing.
	place(p.global_position, p.yaw)
	mark("aim")
	follow(2.2, 2.6, 1.45, 1.3, 4.0)
	p.aiming = true
	await wait(1.6)
	for k in 6:
		p.firing = true
		p._try_fire()
		await wait(0.12)
	p.firing = false
	follow(-2.6, 1.0, 1.55, 1.35, 3.0, false)
	await wait(2.0)
	p.aiming = false
	# 4. Crouch (squat), crouch aim, prone, prone aim.
	mark("crouch")
	p.stance = "crouch"
	follow(1.8, 2.8, 1.0, 0.75, 4.0)
	await wait(2.6)
	p.aiming = true
	await wait(2.0)
	p.aiming = false
	mark("prone")
	p.stance = "prone"
	follow(2.6, 2.2, 0.8, 0.35, 3.0)
	await wait(2.6)
	p.aiming = true
	await wait(2.2)
	p.aiming = false
	p.stance = "stand"
	await wait(1.2)
	# 5. Both guns put away on the back (the slot pressed again).
	mark("holster")
	p.tap_slot(p.active)
	follow(-2.8, 1.2, 1.5, 1.2, 3.0)
	await wait(2.0)
	p.touch_move = Vector2(0, 0.5)
	await wait(2.5)
	p.touch_move = Vector2.ZERO
	p.tap_slot(0)
	await wait(1.0)
	# 6. Weapon skins.
	mark("skins")
	place(p.global_position, p.yaw)
	follow(1.7, 0.7, 1.35, 1.2, 4.0)
	for sk in ["neon", "dragon", "gold", "desert"]:
		p.model.set_weapon_skin(sk)
		await wait(1.1)
	p.model.set_weapon_skin("")
	# 7. The camo jeep, driven.
	mark("drive")
	await _drive(isl)
	# 8. A field of tall grass.
	mark("field")
	await _field(isl)
	# 9. The game's own camera: running with the HUD.
	mark("gamecam")
	game_cam()
	p.yaw = randf() * TAU
	p.touch_move = Vector2(0, 1)
	await wait(3.5)
	p.touch_move = Vector2(0.6, 0.8)
	await wait(1.5)
	p.touch_move = Vector2.ZERO
	p.aiming = true
	await wait(1.2)
	p.aiming = false
	mark("end")

func _drive(isl) -> void:
	var best: Dictionary = isl.roads[0]
	var best_len := 0.0
	for rd in isl.roads:
		if rd.get("runway", false): continue
		var ok := true
		for k in 21:
			var q: Vector2 = rd.a.lerp(rd.b, k / 20.0)
			if isl.height_at(q.x, q.y) < 1.5: ok = false
		var l: float = rd.a.distance_to(rd.b)
		if ok and l > best_len:
			best_len = l
			best = rd
	var dir2: Vector2 = (best.b - best.a).normalized()
	var a2: Vector2 = best.a + dir2 * 40.0
	var v: Vehicle = null
	for c in world.vehicles:
		if c.kind == "jeep" and c.driver == null and not c.dead:
			v = c
			break
	if v == null: return
	var body := v.get_node_or_null("Body") as MeshInstance3D
	if body and body.material_overlay is ShaderMaterial:
		(body.material_overlay as ShaderMaterial).set_shader_parameter("camo", 1.0)
	v.freeze = false
	v.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir2.x, dir2.y)), Vector3(a2.x, world.ground_height(Vector3(a2.x, 0, a2.y)) + 0.9, a2.y))
	v.linear_velocity = Vector3.ZERO
	v.reset_physics_interpolation()
	place(Vector3(a2.x + 3.0, 0, a2.y), 0.0)
	await wait(0.5)
	p.enter_vehicle(v)
	await wait(1.2)
	_follow = func() -> Array:
		var f: Vector3 = v.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := f.cross(Vector3.UP).normalized()
		return [v.global_position + f * 7.0 + r * 3.0 + Vector3(0, 1.6, 0), v.global_position + Vector3(0, 0.9, 0)]
	_cam_k = 2.5
	var r0: Array = _follow.call()
	cam.global_position = r0[0]
	p.touch_move = Vector2(0, 1)
	await wait(2.5)
	_follow = func() -> Array:
		var f: Vector3 = v.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := f.cross(Vector3.UP).normalized()
		return [v.global_position - f * 8.0 + r * 1.5 + Vector3(0, 2.6, 0), v.global_position + f * 4.0 + Vector3(0, 0.8, 0)]
	await wait(3.5)
	p.touch_move = Vector2.ZERO
	await wait(1.0)
	p.exit_vehicle(true)
	await wait(0.6)

func _field(isl) -> void:
	var img: Image = world.builder.noise_a.get_image()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var at := Vector3.ZERO
	var best := 0.0
	for k in 6000:
		var x: float = rng.randf_range(0.1, 0.9) * float(isl.size)
		var z: float = rng.randf_range(0.1, 0.9) * float(isl.size)
		if not isl.is_land(x, z) or isl.region_at(x, z) in ["nordic", "volcano", "jungle", "desert"]: continue
		var u := fposmod(x / 260.0 + 0.71, 1.0)
		var vv := fposmod(z / 260.0 + 0.23, 1.0)
		var n: float = img.get_pixel(int(u * img.get_width()) % img.get_width(), int(vv * img.get_height()) % img.get_height()).r
		if n > best and world.building_at(Vector2(x, z), 6.0) < 0:
			best = n
			at = Vector3(x, isl.height_at(x, z), z)
	place(at, 0.4)
	await wait(1.5)
	follow(3.5, 3.0, 1.0, 0.9, 3.0)
	p.touch_move = Vector2(0, 0.45)
	await wait(4.0)
	p.touch_move = Vector2.ZERO

# ------------------------------------------------------------------ dunes
func _dunes() -> void:
	# The jump, as the player sees it.
	game_cam()
	for i in 400:
		if world.plane_over_land(): break
		world.plane_t += 0.002
		await get_tree().process_frame
	mark("plane")
	await wait(2.0)
	mark("jump")
	p.interact()
	await wait(2.5)
	p.pitch = -0.35
	p.touch_move = Vector2(0, 1)
	await wait(2.5)
	p.pitch = -1.0
	await wait(2.5)
	p.touch_move = Vector2(0, 1)
	p.pitch = -0.9
	for i in 900:
		if p.state != "fall": break
		await get_tree().physics_frame
	mark("chute")
	p.touch_move = Vector2.ZERO
	p.pitch = -0.25
	await wait(3.0)
	p.touch_move = Vector2(-0.6, 0.6)
	await wait(2.0)
	p.touch_move = Vector2(0, 1)
	for i in 3000:
		if p.state == "ground": break
		await get_tree().physics_frame
	mark("landed")
	p.touch_move = Vector2.ZERO
	await wait(2.0)
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(9000, -80, 9000)
		b.visible = false
	# A walk through the old city (the biggest town), armed.
	var isl = world.island
	var town: Dictionary = isl.towns[0]
	for tt in isl.towns:
		if float(tt.r) > float(town.r): town = tt
	p.give_weapon("akm", 30)
	p.switch_slot(0)
	p.give_weapon("m416", 30)
	p.switch_slot(0)
	p.equip("helmet", 3, 100.0)
	p.equip("pack", 2, 0.0)
	var c: Vector2 = town.pos
	var at := Vector3(c.x, 0, c.y)
	for k in 60:
		var q := c + Vector2(randf_range(-40, 40), randf_range(-40, 40))
		if world.building_at(q, 4.0) < 0:
			at = Vector3(q.x, 0, q.y)
			break
	place(at, 0.0)
	await wait(1.5)
	mark("city")
	game_cam()
	p.touch_move = Vector2(0, 1)
	await wait(4.0)
	film_cam()
	follow(0.5, 3.4, 1.3, 1.0, 5.0)
	await wait(3.0)
	p.touch_move = Vector2.ZERO
	# A drone over the old city.
	mark("drone")
	var t0 := [0.0]
	_cam_k = 2.0
	_follow = func() -> Array:
		t0[0] += 0.0035
		var cc := Vector3(c.x, isl.height_at(c.x, c.y), c.y)
		var d := Vector3(cos(t0[0]), 0, sin(t0[0]))
		return [cc + d * float(town.r) * 1.4 + Vector3(0, 70, 0), cc + Vector3(0, 5, 0)]
	var r0: Array = _follow.call()
	cam.global_position = r0[0]
	await wait(5.0)
	# The sandstorm rolls in.
	mark("storm")
	if world.events: world.events.start("sandstorm")
	follow(-3.0, 1.2, 1.6, 1.2, 3.0)
	p.touch_move = Vector2(0, 0.8)
	await wait(7.0)
	p.touch_move = Vector2.ZERO
	game_cam()
	await wait(3.0)
	mark("end")
