extends Node
## The PUBG touches: free look (the view turns, the body and the aim stay),
## sound markers round the crosshair (gunfire, footsteps), and the red zone
## (marked on the map, shells that a roof stops). Pictures when rendered.

var out := "user://"
var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok: fails += 1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.controls = "touch"
	Game.settings.mode = "solo"
	Game.training = false
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	for b in world.bots: b.set_physics_process(false)
	p.jump_from_plane()
	world.plane_active = false
	world.plane.visible = false
	world.zone.start()
	var c: Vector2 = world.island.towns[6].pos + Vector2(60, 40)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	p._land()
	p.give_weapon("m416", 30)
	p.ammo["556"] = 120
	p.health = 100.0
	p.yaw = 0.6
	p.pitch = -0.08
	await wait(1.5)
	# Free look.
	var yaw0 := p.yaw
	p.action("freelook", true)
	p.add_look(-400.0, 0.0)
	await wait(0.3)
	check("free look turns the view only", absf(p.yaw - yaw0) < 0.001 and absf(p.look_off.x) > 0.5, "yaw %.3f off %.3f" % [p.yaw, p.look_off.x])
	check("camera turned", absf(wrapf(p.cam_rig.rotation.y - yaw0, -PI, PI)) > 0.5)
	await shot("pubg_freelook")
	p.action("freelook", false)
	await wait(0.8)
	check("view swings back", absf(p.look_off.x) < 0.05, "%.3f" % p.look_off.x)
	# Bullet drop: a sniper round fired level out over open ground is flown,
	# not landed at once, and falls on its way.
	p.give_weapon("kar98", 5)
	p.ammo["762"] = 20
	p.switch_slot(p.active if p.slots[p.active] != null and p.slots[p.active].id == "kar98" else (1 if p.slots[1] != null and p.slots[1].id == "kar98" else 0))
	await wait(1.0)
	p.pitch = 0.3
	await wait(0.3)
	p._fire_ray(Game.WEAPONS.kar98, 0.0)
	var lq := PhysicsRayQueryParameters3D.create(p.camera.global_position, p.camera.global_position - p.camera.global_basis.z * 80.0, 1 | 4)
	lq.exclude = [p.get_rid()]
	var lh := p.get_world_3d().direct_space_state.intersect_ray(lq)
	check("long shot is a round in flight", p._bullets.size() == 1, "%d cam=%s fwd=%s hit=%s %s" % [p._bullets.size(), p.camera.global_position, -p.camera.global_basis.z, lh.get("collider"), lh.get("position")])
	if p._bullets.size() == 1:
		var b0: Dictionary = p._bullets[0]
		var start: Vector3 = b0.pos
		var dir0: Vector3 = Vector3(b0.vel).normalized()
		await wait(0.25)
		if p._bullets.size() == 1:
			var now: Vector3 = p._bullets[0].pos
			var along := (now - start).dot(dir0)
			var line := start + dir0 * along
			check("it flies about 760 m/s", along > 100.0 and along < 260.0, "%.0f m" % along)
			check("and drops", line.y - now.y > 0.15, "%.2f m" % (line.y - now.y))
		else:
			check("still flying after 0.25 s", false)
	await wait(1.5)
	check("rounds don't pile up", p._bullets.is_empty(), str(p._bullets.size()))
	# Up close it lands at once.
	var dummy: Bot = world.bots[2]
	dummy.set_physics_process(false)
	dummy.state = "ground"
	dummy.visible = true
	dummy.shape.disabled = false
	var fwd0 := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	dummy.global_position = p.global_position + fwd0 * 9.0
	dummy.health = 100.0
	await wait(0.2)
	p.pitch = -0.08
	# The camera sits over the shoulder, so aim from where it ends up (a few passes).
	for k in 4:
		var to_d: Vector3 = dummy.global_position + Vector3(0, 1.1, 0) - p.camera.global_position
		p.yaw = atan2(-to_d.x, -to_d.z)
		p.pitch = atan2(to_d.y, Vector2(to_d.x, to_d.z).length())
		await wait(0.2)
	p._fire_ray(Game.WEAPONS.kar98, 0.0)
	var dq := PhysicsRayQueryParameters3D.create(p.camera.global_position, dummy.global_position + Vector3(0, 1.1, 0), 1 | 4)
	dq.exclude = [p.get_rid()]
	var dh := p.get_world_3d().direct_space_state.intersect_ray(dq)
	check("close shot lands at once", dummy.health < 100.0 or dummy.dead, "%s dead=%s ray=%s" % [dummy.health, dummy.dead, dh.get("collider")])
	dummy.global_position = Vector3(5000, 0, 5000)
	# Sound markers.
	var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	var rgt := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	world.notify_shot(p.global_position + fwd * 80.0 + rgt * 60.0, world.bots[0])
	world.footstep(p.global_position - rgt * 12.0, false, 0.9, world.bots[1])
	world.footstep(p.global_position + fwd * 2.0, true, 0.9)
	check("shot and step marked (own steps not)", world.hud.sound_marks.size() == 2, str(world.hud.sound_marks.size()))
	await wait(0.2)
	await shot("pubg_sound_marks")
	# Red zone: right where we are.
	var ev: MatchEvents = world.events
	check("events running", ev != null)
	world.zone.phase = 1
	ev.start_red()
	check("red zone marked", ev.red_on() and ev.red_radius >= 60.0, "%s r=%.0f" % [ev.red_center, ev.red_radius])
	ev.red_center = Vector2(p.global_position.x, p.global_position.z)
	check("we are inside it", ev.in_red(p.global_position))
	await wait(0.3)
	world.hud.toggle_map()
	world.hud.map_focus = ev.red_center
	await wait(0.4)
	await shot("pubg_red_map")
	world.hud.toggle_map()
	# Shells come down inside the circle and blow up.
	p.health = 1e9
	ev.red_t = MatchEvents.RED_TIME
	var n0: int = ev._shells.size()
	for i in 6: ev._shell()
	var inside := true
	for s in ev._shells:
		if Vector2(s.pos.x, s.pos.z).distance_to(ev.red_center) > ev.red_radius + 1.0: inside = false
	check("shells land inside", ev._shells.size() == n0 + 6 and inside)
	var mine: Array = ev._shells.duplicate()
	await wait(0.4)
	check("shells went off", mine.all(func(x): return not ev._shells.has(x)))
	await shot("pubg_red_shells")
	# The zone ends after its time.
	ev.red_t = 0.01
	await wait(0.2)
	check("red zone over", not ev.red_on())
	print("PUBG FEEL TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit(1 if fails > 0 else 0)
