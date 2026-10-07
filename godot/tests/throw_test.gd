extends Node
## Molotov and flashbang: a thrown bottle bursts into fire that burns a bot
## (which runs out of it); a flashbang blinds a bot and whites out your screen.

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
	_run.call_deferred()

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
	p.health = 1e6
	p.yaw = 0.0
	p.pitch = -0.25
	# A bot 9 m ahead, unarmed and standing still.
	var v: Bot = world.bots[0]
	var at := p.global_position + Vector3(0, 0, -9.0)
	v.state = "ground"
	v.global_position = Vector3(at.x, world.ground_height(at) + 0.3, at.z)
	v._land()
	v.weapon_id = ""
	v.health = 100.0
	v.set_physics_process(true)
	await wait(0.3)
	# Throw a molotov.
	p.throwables.molotov = 1
	p.throw_kind = "molotov"
	p.start_throw()
	check("molotov ready", p.throw_ready)
	p.release_throw()
	var lit := false
	for i in 40:
		await wait(0.1)
		if not world.fires.is_empty():
			lit = true
			break
	check("bottle burst into fire", lit)
	await wait(0.3)
	await shot("molotov")
	# Fire right under the bot: it burns and runs out.
	world.add_fire(v.global_position, p)
	var h0: float = v.health
	await wait(1.6)
	check("bot burned in the fire", v.health < h0 or v.dead, "health %.0f -> %.0f" % [h0, v.health])
	await wait(2.0)
	check("bot ran out of the fire", v.dead or world.fire_at(v.global_position) == Vector3.INF, "mode=%s" % v.mode)
	# Flashbang 3 m in front of an armed bot that faces it.
	var w: Bot = world.bots[1]
	var at2 := p.global_position + Vector3(14, 0, 0)
	w.state = "ground"
	w.global_position = Vector3(at2.x, world.ground_height(at2) + 0.3, at2.z)
	w._land()
	w.weapon_id = "m416"
	w.mag = 30
	w.yaw = PI * 0.5   # facing -x, back towards the player side
	await wait(0.2)
	world.flashbang(w.global_position + Vector3(-3, 1.0, 0), null)
	check("bot blinded by the flash", w.blind_t > 1.0, "blind %.1f s" % w.blind_t)
	check("blinded bot sees nobody", w._look_for_enemy() == null)
	# One in front of you.
	p.yaw = 0.0
	p.pitch = 0.0
	await wait(0.3)
	world.flashbang(p.camera.global_position + (-p.camera.global_basis.z) * 5.0, null)
	await wait(0.1)
	check("your screen whites out", world.hud.flash_t > 1.0, "%.1f s" % world.hud.flash_t)
	await shot("flash")
	await wait(world.hud.flash_t + 0.5)
	check("and clears again with the sound back", world.hud.flash_t == 0.0 and AudioServer.get_bus_volume_db(0) == 0.0)
	# T cycles through the kinds you carry.
	p.throwables = {"frag": 1, "smoke": 0, "molotov": 1, "flash": 1}
	p.throw_kind = "frag"
	p.switch_throw()
	var k1 := p.throw_kind
	p.switch_throw()
	check("T skips kinds you don't have", k1 == "molotov" and p.throw_kind == "flash", "%s, %s" % [k1, p.throw_kind])
	print("THROW TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
