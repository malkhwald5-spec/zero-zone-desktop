extends Node
## The game's trailer, shot in the engine under Godot's movie writer:
## godot --path godot --write-movie trailer.avi --fixed-fps 30 res://tests/trailer.tscn
## Free cinematic cameras over a real match (HUD off, film bars), cut to the
## beats of the music made by tools/trailer_score.py. Times are in seconds of
## the finished film; the timeline is printed for the edit.

var world: Node
var p: Player
var cam: Camera3D
var fade: ColorRect
var title: Label
var sub: Label
var _upd: Callable = Callable()
var _t0 := 0.0           # when the current shot began
var _clock := 0.0        # film time
const GOLD := Color("ffb321")

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func _ready() -> void:
	Game.settings.controls = "touch"
	Game.settings.mode = "solo"
	Game.training = false
	Game.spawn_island = false
	Game.wallet.login_date = Game.today()
	Game.settings.weather = "sunset"
	_run.call_deferred()

func _process(delta: float) -> void:
	_clock += delta / maxf(Engine.time_scale, 0.01)
	if p and is_instance_valid(p) and p.state != "dead": p.health = 100.0
	if _upd.is_valid() and cam and is_instance_valid(cam): _upd.call(_clock - _t0)

## A new shot: the camera follows `f(t)` (t = seconds into the shot).
func shot(f: Callable, name: String) -> void:
	_t0 = _clock
	_upd = f
	print("TRAILER %.2f %s" % [_clock, name])
	f.call(0.0)

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
	var tw := create_tween().set_ignore_time_scale()
	tw.tween_property(title, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(sub, "modulate:a", 1.0, 0.5)
	tw.tween_interval(maxf(0.1, sec - 0.7))
	tw.tween_property(title, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(sub, "modulate:a", 0.0, 0.35)

func ground(q: Vector3) -> float:
	return world.ground_height(q)

func open_dir(at: Vector3, from_yaw: float) -> float:
	var best := from_yaw
	var best_d := -1.0
	var space := p.get_world_3d().direct_space_state
	for i in 24:
		var y := from_yaw + TAU * float(i) / 24.0
		var o := at + Vector3(0, 0.8, 0)
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + Vector3(-sin(y), 0, -cos(y)) * 45.0, 1, [p.get_rid()]))
		var free: float = 45.0 if h.is_empty() else o.distance_to(h.position)
		if free > best_d:
			best_d = free
			best = y
	return best

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
	_clock = 0.0
	# ---- 0: black, three lines over the drone of the score.
	text("جزيرة واحدة", "", 1.4, 54)
	await wait(1.5)
	text("مية لاعب", "", 1.4, 54)
	await wait(1.5)
	text("ناجي واحد بس", "", 1.6, 60, GOLD)
	await wait(1.7)
	# ---- 1: over the island at dawn (hit on the first braam).
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
	# ---- 2: the plane goes over us; the props roar past.
	world.plane_t = 0.45
	var pp: Vector3 = world.plane_position()
	var pv: Vector3 = (world.plane_to - world.plane_from).normalized()
	var side := pv.cross(Vector3.UP).normalized()
	var spot := pp + pv * 140.0 + side * 38.0 + Vector3(0, -16.0, 0)
	shot(func(_t: float):
		cam.global_position = spot
		cam.look_at(world.plane.global_position + pv * 6.0, Vector3.UP), "plane")
	cam.fov = 48.0
	await wait(4.3)
	# ---- 3: out of the door, falling at us, then the canopy snaps open.
	cam.fov = 60.0
	p.jump_from_plane()
	p.dive = 1.0
	shot(func(t: float):
		var b: Vector3 = p.global_position
		var vel: Vector3 = p.velocity
		var hv := Vector3(vel.x, 0, vel.z).normalized() if Vector2(vel.x, vel.z).length() > 1.0 else pv
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
	# ---- 4: title hit.
	fade.color.a = 1.0
	_upd = Callable()
	text("ZERO ZONE", "باتل رويال • ١٠٠ لاعب", 2.2, 92, Color.WHITE)
	print("TRAILER %.2f title" % _clock)
	# Meanwhile put her down in a town with a rifle.
	var c: Vector2 = world.island.towns[2].pos + Vector2(30, 20)
	p.global_position = Vector3(c.x, ground(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	p._land()
	p.give_weapon("m416", 30)
	p.ammo["556"] = 240
	p.equip("vest", 2, 200.0)
	p.equip("helmet", 2, 150.0)
	p.equip("pack", 2, 0.0)
	p.yaw = open_dir(p.global_position, 0.0)
	p.pitch = -0.05
	await wait(2.4)
	# ---- 5: she pushes off and sprints down the street; the camera runs alongside.
	fade_to(0.0, 0.25)
	p.touch_move = Vector2(0, 1)
	p.sprinting = true
	shot(func(t: float):
		var b: Vector3 = p.get_global_transform_interpolated().origin
		var f := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		var r := f.cross(Vector3.UP)
		var k := clampf(t / 3.0, 0.0, 1.0)
		cam.global_position = b + f * lerpf(3.2, 1.2, k) - r * 2.4 + Vector3(0, 0.9, 0)
		cam.look_at(b + Vector3(0, 1.05, 0) - f * 0.6, Vector3.UP), "sprint")
	await wait(3.4)
	p.touch_move = Vector2.ZERO
	p.sprinting = false
	await wait(1.3)
	# ---- 6: contact. Shoulder-cam burst at a target, then the side view of it dropping.
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
	var f0 := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	var ep := p.global_position + f0 * 24.0
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
		# Over her right shoulder, easing in on the target.
		var b: Vector3 = p.get_global_transform_interpolated().origin
		var fe := (e_at - b)
		fe.y = 0.0
		fe = fe.normalized()
		var re := fe.cross(Vector3.UP)
		cam.fov = 40.0 - t * 4.0
		cam.global_position = b - fe * 2.3 + re * 0.75 + Vector3(0, 1.75, 0)
		cam.look_at(e_at, Vector3.UP), "aim")
	await wait(0.7)
	p.action("fire", true)
	await wait(0.9)
	p.action("fire", false)
	enemy.take_damage(999.0, p)
	var es: Vector3 = enemy.global_position
	shot(func(t: float):
		var r := f0.cross(Vector3.UP)
		cam.fov = 50.0
		cam.global_position = es + r * (3.4 - t * 0.4) - f0 * 1.6 + Vector3(0, 0.9, 0)
		cam.look_at(es + Vector3(0, 0.7, 0), Vector3.UP), "drop")
	Engine.time_scale = 0.45
	await wait(1.3)
	Engine.time_scale = 1.0
	p.action("aim", false)
	# ---- 7: the red zone: shells walking across the town, slow motion on the big one.
	var ev: MatchEvents = world.events
	if ev:
		world.zone.phase = 1
		ev.start_red()
		var rc := Vector2(p.global_position.x, p.global_position.z) + Vector2(f0.x, f0.z) * 70.0
		ev.red_center = rc
		ev.red_radius = 30.0
		ev.red_t = MatchEvents.RED_TIME
		var rr := Vector3(rc.x, ground(Vector3(rc.x, 0, rc.y)), rc.y)
		shot(func(t: float):
			cam.fov = 58.0
			var o: Vector3 = rr - f0 * 55.0 + f0.cross(Vector3.UP) * 22.0 + Vector3(0, 12.0 - t * 1.0, 0)
			cam.global_position = o
			cam.look_at(rr + Vector3(0, 4.0, 0), Vector3.UP), "shelling")
		for k in 9:
			ev._shell()
			if k % 3 == 1: ev._shell()
			await wait(0.3)
		Engine.time_scale = 0.35
		ev._shell()
		await wait(0.7)
		Engine.time_scale = 1.0
		await wait(0.6)
	# ---- 8: into a car and over the hill, low chase camera.
	var car: Vehicle = world.nearest_vehicle(p.global_position, 600.0)
	if car:
		p.global_position = car.global_position + car.global_basis.x * 2.5 + Vector3(0, 0.5, 0)
		await wait(0.1)
		p.enter_vehicle(car)
		p.touch_move = Vector2(0.0, 1.0)
		await wait(0.5)
		shot(func(t: float):
			var cb: Vector3 = car.get_global_transform_interpolated().origin
			var cf: Vector3 = -car.global_basis.z
			cf.y = 0.0
			cf = cf.normalized()
			var cr := cf.cross(Vector3.UP)
			cam.fov = 62.0
			cam.global_position = cb - cf * (6.5 - t * 0.6) + cr * (2.5 + t * 0.8) + Vector3(0, 0.7, 0)
			cam.look_at(cb + cf * 3.0 + Vector3(0, 0.8, 0), Vector3.UP), "car")
		await wait(2.0)
		p.touch_move = Vector2(0.4, 1.0)
		await wait(2.0)
		p.touch_move = Vector2.ZERO
	# ---- 9: the blue wall closing in over the land.
	var z: Zone = world.zone
	var zc: Vector2 = z.center
	var zr: float = z.radius
	# A stretch of the wall over land, seen from inside the circle.
	var out_dir := Vector3(1, 0, 0)
	for i in 36:
		var d := Vector3(cos(i * TAU / 36.0), 0, sin(i * TAU / 36.0))
		var q := Vector2(zc.x, zc.y) + Vector2(d.x, d.z) * zr
		var q2 := Vector2(zc.x, zc.y) + Vector2(d.x, d.z) * (zr - 160.0)
		if world.island.is_land(q.x, q.y) and world.island.is_land(q2.x, q2.y):
			out_dir = d
			break
	var edge := Vector3(zc.x, 0, zc.y) + out_dir * zr
	edge.y = ground(edge)
	shot(func(t: float):
		cam.fov = 62.0
		var o: Vector3 = edge - out_dir * (170.0 - t * 12.0) + out_dir.cross(Vector3.UP) * 40.0
		o.y = ground(o) + 28.0
		cam.global_position = o
		cam.look_at(edge + Vector3(0, 18.0, 0), Vector3.UP), "zone")
	await wait(3.0)
	# ---- 10: end card.
	fade_to(1.0, 0.5)
	await wait(0.6)
	_upd = Callable()
	text("ZERO ZONE", "حمّلها هلأ • كمبيوتر وأندرويد", 4.5, 96, GOLD)
	await wait(4.8)
	print("TRAILER %.2f end" % _clock)
	print("TRAILER DONE")
	tree.quit()
