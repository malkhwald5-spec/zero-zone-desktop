extends Node
## New weapons: each one is found, fires and hurts; the crossbow is silent;
## the pan hits up close and stops bullets on your back; DMRs take scopes.
## Pictures of each gun in the hands with --out=/dir.

var out := "user://"
var fails := 0
const NEW := ["vector", "uzi", "scar", "beryl", "sks", "mini14", "crossbow", "pan"]

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
	var found := {}
	for it in world.pickups:
		var d: Dictionary = it.get_meta("data")
		if d.kind == "weapon": found[d.id] = true
	var missing := NEW.filter(func(id): return not found.has(id))
	check("all new weapons lie around the map", missing.is_empty(), "missing %s" % str(missing))
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
	p.equip("pack", 3, 0.0)
	for k in p.ammo: p.ammo[k] = 200
	var dummy: Bot = world.bots[0]
	for id in NEW:
		# A target 7 m ahead (1.5 m for the pan), standing still.
		p.yaw = 0.0
		p.pitch = 0.0
		var fwd := Vector3(0, 0, -1)
		var dist := 1.5 if id == "pan" else 7.0
		var at := p.global_position + fwd * dist
		dummy.dead = false
		dummy.state = "ground"
		dummy.collision_layer = 4
		dummy.global_position = Vector3(at.x, world.ground_height(at) + 0.05, at.z)
		dummy.health = 100.0
		dummy.gear = {"vest": 0, "vest_dur": 0.0, "helmet": 0, "helmet_dur": 0.0, "pack": 0}
		dummy.visible = true
		dummy.shape.disabled = false
		await wait(0.3)
		# Aim at its chest.
		var to: Vector3 = dummy.global_position + Vector3(0, 1.1, 0) - p.camera.global_position
		p.pitch = atan2(to.y, Vector2(to.x, to.z).length())
		p.give_weapon(id, Game.WEAPONS[id].mag, {})
		await wait(0.4)
		await shot("hold_" + id)
		var h0: float = dummy.health
		for k in 3:
			p.firing = true
			p._try_fire()
			await wait(maxf(0.3, float(Game.WEAPONS[id].rate) + 0.05))
		p.firing = false
		check(id + " hurts the target", dummy.health < h0 or dummy.dead, "%.0f -> %.0f" % [h0, dummy.health])
		p.drop_slot(p.active)
		await wait(0.1)
	# The crossbow is silent: a bot 60 m away does not hear it.
	var ear: Bot = world.bots[1]
	ear.state = "ground"
	ear.global_position = p.global_position + Vector3(60, 0.5, 0)
	ear.mode = "roam"
	ear.target = null
	ear.skill = 1.0
	p.give_weapon("crossbow", 1, {})
	await wait(0.3)
	p.firing = true
	p._try_fire()
	p.firing = false
	check("crossbow is silent at 60 m", ear.mode == "roam" and ear.target == null, "mode=%s" % ear.mode)
	# The pan on your back stops a shot from behind.
	p.health = 100.0
	p.give_weapon("pan", 0, {})
	p.switch_slot(0)
	await wait(0.2)
	var behind: Bot = world.bots[2]
	behind.state = "ground"
	behind.global_position = p.global_position + Vector3(-sin(p.model.rotation.y), 0, -cos(p.model.rotation.y)) * -10.0
	var hp: float = p.health
	p.take_damage(30.0, behind)
	check("pan on your back blocks a shot from behind", p.health == hp, "%.0f" % p.health)
	var front: Bot = world.bots[3]
	front.state = "ground"
	front.global_position = p.global_position + Vector3(-sin(p.model.rotation.y), 0, -cos(p.model.rotation.y)) * 10.0
	p.take_damage(30.0, front)
	check("but not from the front", p.health < hp)
	check("SKS takes a 4x scope", Items.attach_fits("x4", Game.WEAPONS.sks.cls))
	print("WEAPONS TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
