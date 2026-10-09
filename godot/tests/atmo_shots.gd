extends Node
## Light and atmosphere: --weather=fog (morning mist over a valley),
## --weather=rain (wet road and puddles), and inside a house in any weather
## (sun shafts through the windows in the dusty air). Run with --out=/dir.

var out := "user://"
var weather := "fog"
var dust := -1.0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--weather="): weather = a.substr(10)
		if a.begins_with("--dust="): dust = float(a.substr(7))
	Game.settings.controls = "kbm"
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	var saved_w: String = Game.settings.weather
	Game.settings.weather = weather
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 1200:
		if world.ready_done: break
		await wait(0.1)
	Game.settings.weather = saved_w
	if dust >= 0.0: world.dust_density = dust
	print("ATMO weather=", world.weather, " vfog=", world.builder.env.volumetric_fog_enabled)
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(9000, 0, 9000)
	var p: Player = world.player
	p.health = 1e9
	p.jump_from_plane()
	world.plane_active = false
	var isl = world.island
	world.hud.visible = false
	# 1) Overview: from a hilltop looking down over lower ground.
	var best := Vector2.ZERO
	var best_h := 0.0
	for k in 3000:
		var q := Vector2(randf_range(800, isl.size - 800), randf_range(800, isl.size - 800))
		var h: float = isl.height_at(q.x, q.y)
		if h > best_h and h < 45.0 and isl.region_at(q.x, q.y) in ["plains", "nordic"]:
			best_h = h
			best = q
	p.global_position = Vector3(best.x, isl.height_at(best.x, best.y) + 1.0, best.y)
	var low := best
	var low_h := 999.0
	for k in 36:
		var q := best + Vector2(300, 0).rotated(k * TAU / 36.0)
		if isl.height_at(q.x, q.y) < low_h and isl.height_at(q.x, q.y) > 2.0:
			low_h = isl.height_at(q.x, q.y)
			low = q
	var d := low - best
	p.yaw = atan2(-d.x, -d.y)
	p.pitch = -0.12
	await wait(3.0)
	await shot("atmo_%s_view" % weather)
	# 2) A road close up.
	var rd: Dictionary = isl.roads[0]
	for r in isl.roads:
		var mid: Vector2 = (r.a + r.b) * 0.5
		if isl.height_at(mid.x, mid.y) > 3.0 and isl.region_at(mid.x, mid.y) != "desert":
			rd = r
			break
	var m: Vector2 = rd.a.lerp(rd.b, 0.5)
	var along: Vector2 = (rd.b - rd.a).normalized()
	p.global_position = Vector3(m.x, isl.height_at(m.x, m.y) + 1.0, m.y)
	p.yaw = atan2(-along.x, -along.y)
	p.pitch = -0.3
	await wait(2.5)
	await shot("atmo_%s_road" % weather)
	# 3b) A house whose door faces the sun: look across the beam coming in.
	var sun_l: Vector3 = -world.builder.sun.global_basis.z     # direction the light travels
	var door_n := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	for b in isl.buildings:
		if b.get("kind", "house") != "house" or int(b.get("storeys", 1)) != 1 or b.military: continue
		var hit := -1
		for dd in b.doors:
			if door_n[dd].dot(Vector2(sun_l.x, sun_l.z).normalized()) < -0.6: hit = dd
		if hit < 0: continue
		var c2: Vector2 = b.pos
		var dn: Vector2 = door_n[hit]
		var side := Vector2(-dn.y, dn.x)
		var half: Vector2 = b.size * 0.5
		var cam_at: Vector2 = c2 + dn * (absf(dn.x) * half.x + absf(dn.y) * half.y) * 0.45 + side * (absf(side.x) * half.x + absf(side.y) * half.y) * 0.8
		p.global_position = Vector3(cam_at.x, float(b.floor) + 0.3, cam_at.y)
		var look: Vector2 = -side
		p.yaw = atan2(-look.x, -look.y)
		p.pitch = -0.1
		await wait(4.0)
		await shot("atmo_%s_beam" % weather)
		break
	# 3) Inside a house, looking at a window on the sun side.
	var bl: Dictionary = {}
	for b in isl.buildings:
		if b.get("kind", "house") == "house" and int(b.get("storeys", 1)) == 1 and not b.military:
			bl = b
			break
	var c: Vector2 = bl.pos
	p.global_position = Vector3(c.x, float(bl.floor) + 0.3, c.y)
	var sun_dir: Vector3 = -world.builder.sun.global_basis.z
	p.yaw = atan2(sun_dir.x, sun_dir.z)     # facing the sun: light comes in towards you
	p.pitch = 0.05
	await wait(4.0)
	await shot("atmo_%s_inside" % weather)
	print("ATMO dust building=", world._air_building, " density=", world._dust_mat.density if world._dust_mat else -1.0)
	tree.quit()
