extends Node
## After you die: the killcam turns to your killer with their name, weapon and
## distance, then the results offer to watch the match; you follow the
## killer and move on to the next player when they die.

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
	Game.settings.controls = "kbm"
	_run.call_deferred()

func _place(world, b: Bot, pos: Vector3) -> void:
	b.state = "ground"
	b.global_position = Vector3(pos.x, world.ground_height(pos) + 0.3, pos.z)
	b.visible = true
	b._land()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 600:
		if world.ready_done: break
		await wait(0.1)
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(5000, 0, 5000)
	var p: Player = world.player
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[0].pos + Vector2(world.island.towns[0].r + 40.0, 0)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	for i in 40:
		if p.state == "ground" and p.is_on_floor(): break
		await wait(0.1)
	var k: Bot = world.bots[0]
	k.display_name = "ذيب"
	_place(world, k, p.global_position + Vector3(30, 0, -20))
	k.weapon_id = "akm"
	k.mag = 30
	var o: Bot = world.bots[1]
	_place(world, o, p.global_position + Vector3(-200, 0, 150))
	o.weapon_id = "m416"
	p.yaw = PI   # facing away from the killer
	await wait(0.3)
	p.take_damage(1000.0, k)
	check("you died", p.state == "dead")
	check("killcam knows the killer", p.killer == k)
	await wait(2.0)
	var to := k.global_position - p.cam_rig.global_position
	var face: float = absf(angle_difference(p.yaw, atan2(-to.x, -to.z)))
	check("camera turned to face the killer", face < 0.3, "off by %.2f rad" % face)
	check("results wait for the killcam", world.hud.results == null)
	await shot("killcam")
	await wait(2.5)
	check("results shown after the killcam", world.hud.results != null)
	var watch: Button = null
	if world.hud.results:
		for n in world.hud.results.find_children("*", "Button", true, false):
			if n.text == "مشاهدة اللاعبين": watch = n
	check("watch button there", watch != null)
	if watch: watch.pressed.emit()
	await wait(0.6)
	check("watching the killer", world.hud.spectating and p.spectate == k)
	check("detail follows the watched player", world.view_position().distance_to(k.global_position) < 0.1)
	await shot("spectate")
	# The killer dies: the camera moves to the next one still alive.
	k.take_damage(1000.0, o)
	await wait(2.8)
	check("moved on to the next player", is_instance_valid(p.spectate) and p.spectate != k and not p.spectate.dead, str(p.spectate))
	world.hud.spectate_next()
	await wait(0.2)
	check("next-player button works", is_instance_valid(p.spectate) and not p.spectate.dead)
	world.hud.stop_spectate()
	await wait(0.2)
	check("back to the results", world.hud.results != null and not world.hud.spectating)
	print("SPECTATE TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
