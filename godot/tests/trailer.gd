extends Node
## The game's trailer, shot in the engine under Godot's movie writer, one part
## at a time (each part is its own recording; the edit puts them together):
## godot --path godot --write-movie air.avi --fixed-fps 30 res://tests/trailer.tscn -- --part=air
## Parts: air (opening lines, the island, the plane, the jump, the title),
## ground (push-off, sprint, a hurdle, a kill) and war (the shelling, a car
## chase, the last look over the island, the end card). Free cinematic cameras
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
	if _upd.is_valid() and cam and is_instance_valid(cam): _upd.call(_clock - _t0)

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
	world.add_child(cam)
	cam.current = true
	match part:
		"air": await _air()
		"ground": await _ground()
		"war": await _war()
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
	shot(func(t: float):
		var b: Vector3 = p.get_global_transform_interpolated().origin
		var fe := (e_at - b)
		fe.y = 0.0
		fe = fe.normalized()
		var re := fe.cross(Vector3.UP)
		cam.fov = 40.0 - t * 5.0
		cam.global_position = b - fe * 2.0 + re * 1.5 + Vector3(0, 1.6, 0)
		cam.look_at(e_at, Vector3.UP), "aim")
	await wait(0.8)
	p.action("fire", true)
	await wait(0.9)
	p.action("fire", false)
	enemy.take_damage(999.0, p)
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
	fade_to(0.0, 0.3)
	for k in 8:
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
		await wait(0.4)
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
		p.touch_move = Vector2(0.35, 1.0)
		await wait(2.2)
		p.touch_move = Vector2.ZERO
		p.exit_vehicle(true)
		await wait(0.3)
	# 4: the last look: on high ground, the smoke rising over the town behind her.
	var hill := Vector3(rr.x, 0, rr.z) - f * 120.0
	var best := hill
	var best_h := -1e9
	for i in 16:
		var q := hill + Vector3(cos(i * TAU / 16.0), 0, sin(i * TAU / 16.0)) * 40.0
		var h := ground(q)
		if h > best_h and not world.island.is_deep(q.x, q.z):
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
		var ang := -0.9 + t * 0.22
		var off := Basis(Vector3.UP, ang) * (-to_town * 4.2)
		cam.fov = 50.0
		cam.global_position = b + off + Vector3(0, 1.0, 0)
		cam.look_at(b + to_town * 30.0 + Vector3(0, 2.5, 0), Vector3.UP), "lastlook")
	await wait(4.5)
	# End card.
	fade_to(1.0, 0.5)
	await wait(0.6)
	_upd = Callable()
	print("TRAILER %.2f endcard" % _clock)
	text("ZERO ZONE", "حمّلها هلأ • كمبيوتر وأندرويد", 4.5, 100, GOLD)
	await wait(4.8)
