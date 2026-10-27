extends Node
## The game's trailer, shot in the engine under Godot's movie writer, one part
## at a time (each part is its own recording; the edit puts them together):
## godot --path godot --write-movie air.avi --fixed-fps 30 res://tests/trailer.tscn -- --part=air
## Parts: air (opening lines, the island, the plane, the jump, the title),
## ground (push-off, sprint, a hurdle, a kill), urban (up an apartment block's
## stairs, a fight from its roof, the warehouse gallery) and war (the
## shelling, a car chase, the last look over the island, the end card).
## Ground-level shots are hand-held (a slow drift plus kicks on blasts and
## shots) with a shallow focus, like a film camera. Free cinematic cameras
## over a real match: HUD off, film bars. "TRAILER" lines give the timeline;
## "TRAILER_START <frame>" is the movie frame where the part begins.

var world: Node
var p: Player
var cam: Camera3D
var fade: ColorRect
var title: Label
var sub: Label
var part := "air"
var _upd: Callable = Callable()
var _t0 := 0.0           # when the current shot began
var _clock := 0.0        # film time of this part
var _frames := 0         # frames written so far (the movie writer writes one per frame)
const GOLD := Color("ffb321")
var shake := 0.0         # hand-held drift for the current shot (0 = on a tripod)
var _kick := 0.0         # a jolt that dies away (a blast, a shot)
var _dof: CameraAttributesPractical

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--part="): part = a.substr(7)
	Game.settings.controls = "touch"
	Game.settings.mode = "solo"
	Game.training = false
	Game.spawn_island = false
	Game.wallet.login_date = Game.today()
	Game.settings.weather = "sunset"
	# Best picture, and no automatic stepping down (the movie writer's fixed
	# frame rate would look like a slow machine to it).
	Game.settings.quality = "ultra"
	Game.settings.lite = false
	Game.settings.auto_perf = false
	_run.call_deferred()

func _process(delta: float) -> void:
	_frames += 1
	_clock += delta / maxf(Engine.time_scale, 0.01)
	if p and is_instance_valid(p) and p.state != "dead": p.health = 100.0
	if _upd.is_valid() and cam and is_instance_valid(cam):
		_upd.call(_clock - _t0)
		_handheld(delta / maxf(Engine.time_scale, 0.01))

## Operator drift (a few slow, unrelated waves) and the jolt of a kick.
func _handheld(dt: float) -> void:
	var c := _clock
	var a := shake * 0.0045
	var k := _kick * _kick * 0.03
	cam.rotate_object_local(Vector3.RIGHT, a * (sin(c * 1.7) * 0.6 + sin(c * 4.1 + 1.0) * 0.3 + sin(c * 9.3) * 0.1) + k * sin(c * 41.0))
	cam.rotate_object_local(Vector3.UP, a * (sin(c * 1.3 + 2.0) * 0.6 + sin(c * 3.7) * 0.3) + k * sin(c * 33.0 + 1.3))
	cam.rotate_object_local(Vector3.FORWARD, a * 0.5 * sin(c * 0.9 + 0.5) + k * 0.5 * sin(c * 27.0))
	_kick = move_toward(_kick, 0.0, dt * 2.2)

func kick(k := 1.0) -> void:
	_kick = maxf(_kick, k)

## Focus: things past `far` metres go soft (0 = all sharp, for the wide shots).
func focus(far: float) -> void:
	_dof.dof_blur_far_enabled = far > 0.0
	_dof.dof_blur_far_distance = maxf(far, 1.0)
	_dof.dof_blur_far_transition = maxf(far, 1.0) * 1.5
	_dof.dof_blur_amount = 0.08

## A new shot: the camera follows `f(t)` (t = seconds into the shot).
func shot(f: Callable, name: String) -> void:
	_t0 = _clock
	_upd = f
	print("TRAILER %.2f %s" % [_clock, name])
	f.call(0.0)

func slow(k: float) -> void:
	Engine.time_scale = k

func overlay() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 120
	add_child(cl)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(root)
	# Film bars (2.35:1).
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 0.876
		bar.anchor_bottom = 0.124 if top else 1.0
		root.add_child(bar)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade)
	title = UiKit.label("", 64, Color.WHITE, UiKit.bold(), 0)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(title)
	sub = UiKit.label("", 26, GOLD, UiKit.bold(), 0)
	sub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(sub)

func fade_to(a: float, sec: float) -> void:
	create_tween().set_ignore_time_scale().tween_property(fade, "color:a", a, sec)

func text(t: String, s := "", sec := 1.6, size := 64, col := Color.WHITE) -> void:
	# Sizes are for a 720-line picture; scaled to the real one.
	var k: float = get_viewport().get_visible_rect().size.y / 720.0
	title.text = t
	title.add_theme_font_size_override("font_size", int(size * k))
	title.add_theme_color_override("font_color", col)
	sub.text = s
	sub.add_theme_font_size_override("font_size", int(30 * k))
	sub.offset_top = 0.0 if s == "" else size * k * 1.05
	sub.offset_bottom = sub.offset_top
	title.offset_top = 0.0 if s == "" else -24.0 * k
	title.offset_bottom = title.offset_top
	title.modulate.a = 0.0
	sub.modulate.a = 0.0
	# Comes in from slightly large, settles (a slow push on the letters).
	title.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	title.scale = Vector2.ONE * 1.08
	var tw := create_tween().set_ignore_time_scale()
	tw.tween_property(title, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(title, "scale", Vector2.ONE, sec)
	tw.parallel().tween_property(sub, "modulate:a", 1.0, 0.6)
	tw.tween_interval(0.0)
	var tw2 := create_tween().set_ignore_time_scale()
	tw2.tween_interval(maxf(0.1, sec - 0.35))
	tw2.tween_property(title, "modulate:a", 0.0, 0.35)
	tw2.parallel().tween_property(sub, "modulate:a", 0.0, 0.35)

func ground(q: Vector3) -> float:
	return world.ground_height(q)

## The way from `at` with the most open, level ground (no running into walls).
func open_dir(at: Vector3, from_yaw: float, reach := 45.0) -> float:
	var best := from_yaw
	var best_d := -1e9
	var space := p.get_world_3d().direct_space_state
	var g0 := ground(at)
	for i in 24:
		var y := from_yaw + TAU * float(i) / 24.0
		var d := Vector3(-sin(y), 0, -cos(y))
		var o := at + Vector3(0, 0.8, 0)
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + d * reach, 1, [p.get_rid()]))
		var free: float = reach if h.is_empty() else o.distance_to(h.position)
		var bump := 0.0
		for k in [6.0, 12.0, 20.0]:
			bump += absf(ground(at + d * k) - g0)
		var score := free - bump * 4.0
		if score > best_d:
			best_d = score
			best = y
	return best

func put(q: Vector2, yaw_hint := 0.0) -> void:
	p.global_position = Vector3(q.x, ground(Vector3(q.x, 0, q.y)) + 1.0, q.y)
	p._land()
	p.yaw = open_dir(p.global_position, yaw_hint)
	p.pitch = -0.05

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	overlay()
	tree.change_scene_to_file("res://scenes/world.tscn")
	world = null
	for i in 3000:
		world = tree.current_scene
		if world and world.get("ready_done"): break
		await wait(0.1)
	p = world.player
	world.hud.visible = false
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 4000.0
	_dof = CameraAttributesPractical.new()
	_dof.dof_blur_far_enabled = false
	cam.attributes = _dof
	world.add_child(cam)
	cam.current = true
	match part:
		"air": await _air()
		"ground": await _ground()
		"war": await _war()
		"urban": await _urban()
	print("TRAILER %.2f end" % _clock)
	print("TRAILER DONE")
	tree.quit()

func _start() -> void:
	_clock = 0.0
	print("TRAILER_START %d" % _frames)

# ------------------------------------------------------------------ air
func _air() -> void:
	_start()
	text("جزيرة واحدة", "", 1.4, 58)
	await wait(1.5)
	text("مية لاعب", "", 1.4, 58)
	await wait(1.5)
	text("ناجي واحد بس", "", 1.6, 64, GOLD)
	await wait(1.7)
	# The biggest town, from the air, gliding in towards it.
	var big: Dictionary = world.island.towns[0]
	for tw in world.island.towns:
		if tw.kind != "fort" and float(tw.r) > float(big.r): big = tw
	var town: Vector2 = big.pos
	var dir := Vector3(1, 0, -1).normalized()
	var a0 := Vector3(town.x, 0, town.y) - dir * 420.0
	a0.y = ground(Vector3(town.x, 0, town.y)) + 120.0
	shot(func(t: float):
		var at: Vector3 = a0 + dir * t * 30.0
		cam.fov = 55.0
		cam.global_position = at
		cam.look_at(at + dir * 320.0 + Vector3(0, -115.0, 0), Vector3.UP)
		cam.rotate_object_local(Vector3.FORWARD, sin(t * 0.4) * 0.03), "aerial")
	fade_to(0.0, 0.6)
	await wait(5.2)
	# The plane goes over us; the props roar past.
	world.plane_t = 0.45
	var pp: Vector3 = world.plane_position()
	var pv: Vector3 = (world.plane_to - world.plane_from).normalized()
	var side := pv.cross(Vector3.UP).normalized()
	var spot := pp + pv * 140.0 + side * 38.0 + Vector3(0, -16.0, 0)
	shot(func(_t: float):
		cam.fov = 48.0
		cam.global_position = spot
		cam.look_at(world.plane.global_position + pv * 6.0, Vector3.UP), "plane")
	await wait(4.3)
	# Out of the door, falling at us, then the canopy snaps open.
	p.jump_from_plane()
	p.dive = 1.0
	shot(func(t: float):
		var b: Vector3 = p.global_position
		var vel: Vector3 = p.velocity
		var hv := Vector3(vel.x, 0, vel.z).normalized() if Vector2(vel.x, vel.z).length() > 1.0 else pv
		cam.fov = 60.0
		cam.global_position = b + Vector3(0, -7.0 + t * 0.4, 0) + hv * 9.0 + hv.cross(Vector3.UP) * 3.0
		cam.look_at(b + Vector3(0, 0.6, 0), Vector3.UP), "skydive")
	await wait(2.6)
	p.global_position.y = minf(p.global_position.y, ground(p.global_position) + 230.0)
	p.open_chute()
	shot(func(t: float):
		var b: Vector3 = p.global_position
		var f := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		cam.global_position = b - f * (9.0 + t) + Vector3(0, -2.0, 0) + f.cross(Vector3.UP) * 4.0
		cam.look_at(b + Vector3(0, 3.0, 0), Vector3.UP), "chute")
	await wait(2.6)
	fade.color.a = 1.0
	_upd = Callable()
	print("TRAILER %.2f title" % _clock)
	text("ZERO ZONE", "باتل رويال • ١٠٠ لاعب", 2.2, 96, Color.WHITE)
	await wait(2.4)

# ------------------------------------------------------------------ ground
func _ground() -> void:
	var big: Dictionary = world.island.towns[0]
	for tw in world.island.towns:
		if tw.kind != "fort" and float(tw.r) > float(big.r): big = tw
	put(big.pos + Vector2(float(big.r) * 0.8, 10.0))
	p.give_weapon("m416", 30)
	p.ammo["556"] = 240
	p.equip("vest", 2, 200.0)
	p.equip("helmet", 2, 150.0)
	p.equip("pack", 2, 0.0)
	await wait(1.5)
	_start()
	shake = 1.0
	focus(25.0)
	# 1: standing start, she pushes off straight at the camera, which backs away low.
	var f := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	var r := f.cross(Vector3.UP)
	var b0: Vector3 = p.global_position
	shot(func(t: float):
		var b: Vector3 = p.get_global_transform_interpolated().origin
		cam.fov = 50.0
		var back := maxf(3.6, (b - b0).dot(f) + 3.6 - t * 0.3)
		cam.global_position = b0 + f * back + r * 0.9 + Vector3(0, 0.45, 0)
		cam.global_position.y = ground(cam.global_position) + 0.45
		cam.look_at(b + Vector3(0, 1.1, 0), Vector3.UP), "pushoff")
	fade_to(0.0, 0.4)
	await wait(0.5)
	p.touch_move = Vector2(0, 1)
	p.sprinting = true
	await wait(1.6)
	# 2: running alongside her.
	shot(func(t: float):
		var b: Vector3 = p.get_global_transform_interpolated().origin
		cam.fov = 58.0
		var k := clampf(t / 2.4, 0.0, 1.0)
		cam.global_position = b + f * lerpf(2.5, 0.6, k) - r * 2.6 + Vector3(0, 0.95, 0)
		cam.look_at(b + Vector3(0, 1.05, 0) - f * 0.5, Vector3.UP), "sprint")
	await wait(2.4)
	# 3: a low wall across her path: she hurdles it in stride, in slow motion.
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4.0, 0.95, 0.35)
	cs.shape = bx
	wall.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bx.size
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.8, 0.78, 0.75)
	wm.albedo_texture = load("res://assets/textures/concrete_col.jpg") if ResourceLoader.exists("res://assets/textures/concrete_col.jpg") else null
	wm.uv1_scale = Vector3(4, 1, 1)
	wm.roughness = 0.95
	bm.material = wm
	mi.mesh = bm
	wall.add_child(mi)
	world.add_child(wall)
	var wp: Vector3 = p.global_position + f * 6.5
	wall.global_position = Vector3(wp.x, ground(wp) + 0.47, wp.z)
	wall.rotation.y = p.yaw
	var wc := wall.global_position
	shot(func(t: float):
		cam.fov = 45.0
		cam.global_position = wc + r * 4.2 + f * (0.4 - t * 0.5) + Vector3(0, 0.25, 0)
		cam.look_at(wc + Vector3(0, 0.9, 0) - f * 0.3, Vector3.UP), "hurdle")
	var vaulted := false
	for i in 120:
		await get_tree().process_frame
		if not vaulted and p.vault_t < 0.0 and p.global_position.distance_to(wc) < 1.15:
			p.jump_queued = true
		if not vaulted and p.vault_t >= 0.0:
			vaulted = true
			slow(0.35)
		if vaulted and p.vault_t < 0.0: break
	slow(1.0)
	print("TRAILER vaulted=%s" % vaulted)
	await wait(0.6)
	p.touch_move = Vector2.ZERO
	p.sprinting = false
	await wait(0.6)
	# 4: contact. Over her shoulder at a man ahead; a burst; he drops, slow.
	var enemy: Bot = null
	for b in world.bots:
		if not b.dead:
			enemy = b
			break
	enemy.set_physics_process(false)
	enemy.state = "ground"
	enemy.visible = true
	enemy.shape.disabled = false
	enemy.health = 70.0
	f = Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	r = f.cross(Vector3.UP)
	var ep: Vector3 = p.global_position + f * 22.0
	enemy.global_position = Vector3(ep.x, ground(ep) + 0.05, ep.z)
	enemy.yaw = p.yaw
	enemy.model.rotation.y = enemy.yaw + PI
	await wait(0.1)
	for k in 3:
		var to_e: Vector3 = enemy.global_position + Vector3(0, 1.25, 0) - p.camera.global_position
		p.yaw = atan2(-to_e.x, -to_e.z)
		p.pitch = atan2(to_e.y, Vector2(to_e.x, to_e.z).length())
		await get_tree().process_frame
	p.action("aim", true)
	var e_at: Vector3 = enemy.global_position + Vector3(0, 1.2, 0)
	# Over whichever shoulder has nothing in the way of the lens.
	var sh := 1.5
	var pb := p.global_position + Vector3(0, 1.6, 0)
	var fe0 := (e_at - pb)
	fe0.y = 0.0
	fe0 = fe0.normalized()
	var space := p.get_world_3d().direct_space_state
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(pb, pb - fe0 * 2.2 + fe0.cross(Vector3.UP) * 2.0, 1, [p.get_rid()])).is_empty():
		sh = -1.5
	shot(func(t: float):
		var b: Vector3 = p.get_global_transform_interpolated().origin
		var fe := (e_at - b)
		fe.y = 0.0
		fe = fe.normalized()
		var re := fe.cross(Vector3.UP)
		cam.fov = 40.0 - t * 5.0
		cam.global_position = b - fe * 2.0 + re * sh + Vector3(0, 1.6, 0)
		cam.look_at(e_at, Vector3.UP), "aim")
	await wait(0.8)
	p.action("fire", true)
	for k in 6:
		kick(0.25)
		await wait(0.15)
	p.action("fire", false)
	enemy.take_damage(999.0, p)
	enemy.set_physics_process(true)      # so he goes down (his body is posed there)
	var es: Vector3 = enemy.global_position
	shot(func(t: float):
		cam.fov = 50.0
		cam.global_position = es + r * (3.4 - t * 0.4) - f * 1.6 + Vector3(0, 0.9, 0)
		cam.look_at(es + Vector3(0, 0.7, 0), Vector3.UP), "drop")
	slow(0.4)
	await wait(1.8)
	slow(1.0)
	p.action("aim", false)
	fade_to(1.0, 0.3)
	await wait(0.35)

# ------------------------------------------------------------------ war
func _war() -> void:
	var big: Dictionary = world.island.towns[0]
	for tw in world.island.towns:
		if tw.kind != "fort" and float(tw.r) > float(big.r): big = tw
	put(big.pos + Vector2(-float(big.r) * 0.7, -15.0))
	p.give_weapon("m416", 30)
	p.ammo["556"] = 240
	p.equip("vest", 2, 200.0)
	p.equip("helmet", 2, 150.0)
	p.equip("pack", 2, 0.0)
	await wait(1.5)
	var ev: MatchEvents = world.events
	world.zone.phase = 1
	ev.start_red()
	var f := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	var rc := Vector2(p.global_position.x, p.global_position.z) + Vector2(f.x, f.z) * 70.0
	ev.red_center = rc
	ev.red_radius = 32.0
	ev.red_t = MatchEvents.RED_TIME
	var rr := Vector3(rc.x, ground(Vector3(rc.x, 0, rc.y)), rc.y)
	var side := f.cross(Vector3.UP)
	_start()
	# 1: the town under the shells, wide.
	shot(func(t: float):
		cam.fov = 58.0
		var o: Vector3 = rr - f * 58.0 + side * 24.0 + Vector3(0, 13.0 - t * 1.0, 0)
		cam.global_position = o
		cam.look_at(rr + Vector3(0, 4.0, 0), Vector3.UP), "shelling")
	shake = 0.7
	fade_to(0.0, 0.3)
	for k in 8:
		if k % 2 == 0: kick(0.35)
		ev._shell()
		if k % 3 == 1: ev._shell()
		await wait(0.3)
	# 2: one lands close to the lens, in slow motion.
	var near: Vector3 = rr - f * 18.0 + side * 6.0
	near.y = ground(near)
	shot(func(t: float):
		cam.fov = 64.0
		cam.global_position = near - f * 16.0 - side * 5.0 + Vector3(0, 1.4 + t * 0.3, 0)
		cam.look_at(near + Vector3(0, 2.0, 0), Vector3.UP), "impact")
	await wait(0.35)
	world.explode(near, null)
	kick(1.0)
	slow(0.3)
	await wait(1.6)
	slow(1.0)
	ev._shell()
	await wait(0.6)
	# 3: into a car and away from it, the camera low at the wheel.
	var car: Vehicle = world.nearest_vehicle(p.global_position, 700.0)
	if car:
		p.global_position = car.global_position + car.global_basis.x * 2.5 + Vector3(0, 0.5, 0)
		await wait(0.1)
		p.enter_vehicle(car)
		p.touch_move = Vector2(0.0, 1.0)
		await wait(1.2)
		print("TRAILER car state=%s speed=%.1f" % [p.state, car.linear_velocity.length()])
		shot(func(t: float):
			var cb: Vector3 = car.get_global_transform_interpolated().origin
			var cf: Vector3 = -car.global_basis.z
			cf.y = 0.0
			cf = cf.normalized()
			var cr := cf.cross(Vector3.UP)
			cam.fov = 62.0
			cam.global_position = cb - cf * (6.5 - t * 0.6) + cr * (2.5 + t * 0.8) + Vector3(0, 0.7, 0)
			cam.look_at(cb + cf * 3.0 + Vector3(0, 0.8, 0), Vector3.UP), "car")
		await wait(1.3)
		var boom: Vector3 = car.global_position - car.global_basis.z * -6.0 + car.global_basis.x * 7.0
		boom.y = ground(boom)
		world.explode(boom, null)
		kick(0.8)
		p.touch_move = Vector2(0.35, 1.0)
		await wait(2.2)
		p.touch_move = Vector2.ZERO
		p.exit_vehicle(true)
		await wait(0.3)
	# 4: the last look: on high ground, the smoke rising over the town behind her.
	# The highest open ground 150-400 m out from the town, clear of buildings.
	var best := Vector3(rr.x, 0, rr.z) - f * 200.0
	var best_h := -1e9
	for ring in [130.0, 170.0, 220.0]:
		for i in 32:
			var q: Vector3 = Vector3(rr.x, 0, rr.z) + Vector3(cos(i * TAU / 32.0), 0, sin(i * TAU / 32.0)) * float(ring)
			var h: float = ground(q)
			if h > best_h and not world.island.is_deep(q.x, q.z) and world.building_at(Vector2(q.x, q.z), 14.0) < 0:
				best_h = h
				best = q
	p.global_position = Vector3(best.x, best_h + 1.0, best.z)
	p.velocity = Vector3.ZERO
	await wait(0.2)
	var to_town := Vector3(rr.x - best.x, 0, rr.z - best.z).normalized()
	p.yaw = atan2(-to_town.x, -to_town.z)
	for k in 3:
		ev._shell()
	shot(func(t: float):
		var b: Vector3 = p.get_global_transform_interpolated().origin
		# Up behind her shoulder, over the grass, the town ahead; slowly round.
		var ang := -0.7 + t * 0.16
		var off := Basis(Vector3.UP, ang) * (-to_town * 5.5)
		cam.fov = 46.0
		cam.global_position = b + off + Vector3(0, 2.3 + t * 0.12, 0)
		cam.look_at(b + to_town * 60.0 + Vector3(0, -2.0, 0), Vector3.UP), "lastlook")
	# The town still burning in the distance.
	for k in 6:
		ev._shell()
		ev._shell()
		await wait(0.75)
	shake = 0.4
	focus(0.0)
	# End card.
	fade_to(1.0, 0.5)
	await wait(0.6)
	_upd = Callable()
	print("TRAILER %.2f endcard" % _clock)
	text("ZERO ZONE", "حمّلها هلأ • كمبيوتر وأندرويد", 4.5, 100, GOLD)
	await wait(4.8)

# ------------------------------------------------------------------ urban
## A man standing still at `at`, facing `yaw`, ready to be shot.
func enemy_at(at: Vector3, yaw: float, skip: Array = []) -> Bot:
	for b in world.bots:
		if b.dead or b in skip: continue
		b.set_physics_process(false)
		b.state = "ground"
		b.visible = true
		b.shape.disabled = false
		b.health = 70.0
		b.global_position = Vector3(at.x, ground(at) + 0.05, at.z)
		b.yaw = yaw
		b.model.rotation.y = yaw + PI
		return b
	return null

## Stair flight `lv` of an apartment block: [foot, top, along] in world space.
func flight(blk: Dictionary, lv: int) -> Array:
	var hx: float = blk.size.x * 0.5
	var hz: float = blk.size.y * 0.5
	var w: int = blk.stair if lv % 2 == 1 else (int(blk.stair) + 2) % 4
	var along_x := w == 0 or w == 2
	var length: float = blk.size.x if along_x else blk.size.y
	var band: float = [-hz + WorldBuilder.WALL_T + WorldBuilder.STAIR_W * 0.5, hx - WorldBuilder.WALL_T - WorldBuilder.STAIR_W * 0.5,
		hz - WorldBuilder.WALL_T - WorldBuilder.STAIR_W * 0.5, -hx + WorldBuilder.WALL_T + WorldBuilder.STAIR_W * 0.5][w]
	var start := -length * 0.5 + WorldBuilder.WALL_T + 1.2
	var y0 := float(blk.floor) + (lv - 1) * WorldBuilder.STOREY_H
	var c: Vector2 = blk.pos
	var foot := Vector3(c.x + start - 0.6, y0, c.y + band) if along_x else Vector3(c.x + band, y0, c.y + start - 0.6)
	var dir := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	return [foot, foot + dir * (WorldBuilder.STAIR_RUN + 1.2) + Vector3(0, WorldBuilder.STOREY_H, 0), dir]

func _urban() -> void:
	# The apartment block nearest the biggest town.
	var big: Dictionary = world.island.towns[0]
	for tw in world.island.towns:
		if tw.kind != "fort" and float(tw.r) > float(big.r): big = tw
	var blk: Dictionary = {}
	for b in world.island.buildings:
		if b.get("kind", "") == "apartment" and (blk.is_empty() or b.pos.distance_to(big.pos) < blk.pos.distance_to(big.pos)): blk = b
	var storeys: int = blk.storeys
	var c: Vector2 = blk.pos
	var roof_y := float(blk.floor) + storeys * WorldBuilder.STOREY_H
	put(c + Vector2(blk.size.x, 0))
	p.give_weapon("m416", 30)
	p.ammo["556"] = 240
	p.equip("vest", 2, 200.0)
	p.equip("helmet", 2, 150.0)
	p.equip("pack", 2, 0.0)
	await wait(1.5)
	# Up the stairs: the camera low behind her on the steps.
	var fl: Array = flight(blk, 1)
	p.global_position = fl[0] + Vector3(0, 0.3, 0)
	p.velocity = Vector3.ZERO
	var d1: Vector3 = fl[2]
	p.yaw = atan2(-d1.x, -d1.z)
	await wait(0.6)
	_start()
	shake = 1.2
	focus(9.0)
	shot(func(t: float):
		var b: Vector3 = p.get_global_transform_interpolated().origin
		cam.fov = 62.0
		cam.global_position = b - d1 * 1.9 + Vector3(0, 0.75, 0)
		cam.look_at(b + d1 * 2.0 + Vector3(0, 1.7, 0), Vector3.UP), "stairs")
	fade_to(0.0, 0.3)
	p.touch_move = Vector2(0, 1)
	await wait(2.3)
	p.touch_move = Vector2.ZERO
	# Out onto the roof: the camera waits by the parapet as she comes up out of
	# the stairwell into the light.
	fl = flight(blk, storeys)
	var dl: Vector3 = fl[2]
	p.global_position = fl[0] + dl * 1.6 + Vector3(0, WorldBuilder.STOREY_H * 0.35, 0)
	p.velocity = Vector3.ZERO
	p.yaw = atan2(-dl.x, -dl.z)
	var top: Vector3 = fl[1]
	var across := dl.cross(Vector3.UP)
	if (Vector2(top.x, top.z) - c).dot(Vector2(across.x, across.z)) > 0.0: across = -across
	shake = 0.8
	focus(14.0)
	shot(func(t: float):
		var b: Vector3 = p.get_global_transform_interpolated().origin
		cam.fov = 50.0
		cam.global_position = top + dl * 2.4 + across * 2.6 + Vector3(0, 0.35 + t * 0.1, 0)
		cam.look_at(b + Vector3(0, 1.2, 0), Vector3.UP), "roof_up")
	p.touch_move = Vector2(0, 1)
	await wait(2.4)
	p.touch_move = Vector2.ZERO
	# To the parapet over the street; a man down there; she leans over and fires.
	var hx: float = blk.size.x * 0.5
	var hz: float = blk.size.y * 0.5
	var out := Vector3(1, 0, 0)
	var best := -1.0
	for o in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var reach: float = (hx if o.x != 0.0 else hz) + 26.0
		var q := Vector3(c.x, 0, c.y) + o * reach
		if world.building_at(Vector2(q.x, q.z), 3.0) < 0 and not world.island.is_deep(q.x, q.z):
			var free := 1.0 + randf() * 0.1
			if free > best:
				best = free
				out = o
	var edge: float = (hx if out.x != 0.0 else hz) - 0.9
	p.global_position = Vector3(c.x, roof_y + 0.3, c.y) + out * edge
	p.velocity = Vector3.ZERO
	var e_pos := Vector3(c.x, 0, c.y) + out * (edge + 24.0) + out.cross(Vector3.UP) * 4.0
	var enemy := enemy_at(e_pos, atan2(out.x, out.z))
	await wait(0.2)
	var e_at: Vector3 = enemy.global_position + Vector3(0, 1.2, 0)
	for k in 3:
		var to_e: Vector3 = e_at + Vector3(0, 0.05, 0) - p.camera.global_position
		p.yaw = atan2(-to_e.x, -to_e.z)
		p.pitch = atan2(to_e.y, Vector2(to_e.x, to_e.z).length())
		await get_tree().process_frame
	p.action("aim", true)
	var side := out.cross(Vector3.UP)
	shake = 1.0
	focus(0.0)
	shot(func(t: float):
		var b: Vector3 = p.get_global_transform_interpolated().origin
		cam.fov = 42.0 - t * 4.0
		cam.global_position = b - out * 1.8 + side * 1.1 + Vector3(0, 1.75, 0)
		cam.look_at(e_at, Vector3.UP), "roof_aim")
	await wait(0.9)
	p.action("fire", true)
	for k in 5:
		kick(0.25)
		await wait(0.15)
	p.action("fire", false)
	enemy.take_damage(999.0, p)
	enemy.set_physics_process(true)
	# From the street: looking up at her on the roof edge against the sky,
	# a grenade going off down by the wall.
	var es: Vector3 = enemy.global_position
	var low := es - out * 6.0 + side * 5.0
	low.y = ground(low)
	shake = 1.1
	focus(0.0)
	shot(func(t: float):
		cam.fov = 52.0
		cam.global_position = low + Vector3(0, 0.6 + t * 0.15, 0) + out * t * 0.6
		cam.look_at(p.global_position + Vector3(0, 1.0, 0), Vector3.UP), "from_street")
	slow(0.5)
	await wait(0.9)
	var gp := Vector3(c.x, 0, c.y) + out * (edge + 4.0) - side * 3.0
	gp.y = ground(gp)
	world.explode(gp, null)
	kick(1.0)
	await wait(1.4)
	slow(1.0)
	p.action("aim", false)
	# The warehouse gallery: she runs along it, seen from the floor through the rail.
	var wh: Dictionary = {}
	for b in world.island.buildings:
		if WorldBuilder.has_mezzanine(b) and (wh.is_empty() or b.pos.distance_to(c) < wh.pos.distance_to(c)): wh = b
	if not wh.is_empty():
		var wc: Vector2 = wh.pos
		var whx: float = wh.size.x * 0.5
		var whz: float = wh.size.y * 0.5
		var gy := float(wh.floor) + WorldBuilder.STOREY_H
		p.global_position = Vector3(wc.x - whx + 2.0, gy + 0.3, wc.y - whz + 2.2)
		p.velocity = Vector3.ZERO
		p.yaw = PI      # facing +z
		await wait(0.3)
		var e2 := enemy_at(Vector3(wc.x + 3.0, 0, wc.y + whz - 3.0), PI * 0.5, [enemy])
		shake = 1.0
		focus(12.0)
		shot(func(t: float):
			var b: Vector3 = p.get_global_transform_interpolated().origin
			cam.fov = 55.0
			cam.global_position = Vector3(wc.x - whx + WorldBuilder.MEZZ_D + 3.2, float(wh.floor) + 1.2, b.z - 1.5)
			cam.look_at(b + Vector3(0, 1.2, 0), Vector3.UP), "gallery")
		p.touch_move = Vector2(0, 1)
		p.sprinting = true
		await wait(2.0)
		p.touch_move = Vector2.ZERO
		p.sprinting = false
		if e2:
			var e2_at: Vector3 = e2.global_position + Vector3(0, 1.2, 0)
			for k in 3:
				var to_e: Vector3 = e2_at - p.camera.global_position
				p.yaw = atan2(-to_e.x, -to_e.z)
				p.pitch = atan2(to_e.y, Vector2(to_e.x, to_e.z).length())
				await get_tree().process_frame
			p.action("aim", true)
			await wait(0.5)
			p.action("fire", true)
			for k in 5:
				kick(0.2)
				await wait(0.15)
			p.action("fire", false)
			e2.take_damage(999.0, p)
			e2.set_physics_process(true)
			await wait(1.0)
			p.action("aim", false)
	fade_to(1.0, 0.3)
	await wait(0.35)
