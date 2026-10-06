extends Node
## Bag screen: opens with the mouse free, takes attachments off / fits them,
## drops items to the ground, and closes again.
## Run: godot --path godot res://tests/inventory_test.tscn -- --out=/dir

var out := "user://"
var failed := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok: failed += 1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.controls = "kbm"
	_run.call_deferred()

func _ground_count(world, kind: String) -> int:
	var n := 0
	for it in world.pickups_near(world.player.global_position, 3.0):
		if it.get_meta("data").kind == kind: n += 1
	return n

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
	p.health = 1e9
	for b in world.bots: b.set_physics_process(false)
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[1].pos + Vector2(45, -35)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 0.5, c.y)
	for i in 50:
		if p.state == "ground": break
		await wait(0.1)
	# Clear what lies here so the counts below are ours.
	for it in world.pickups_near(p.global_position, 3.0): world._remove_pickup(it)
	p.give_weapon("m416", 30)
	p.give_weapon("akm", 30)
	p.ammo["556"] = 120
	p.ammo["762"] = 60
	p.heals["bandage"] = 5
	p.equip("vest", 2, 150.0)
	p.equip("pack", 3, 0.0)
	p.add_attachment("x4")
	p.add_attachment("ext_mag")
	p.switch_slot(0)
	world.hud.toggle_bag()
	await wait(0.4)
	check(world.hud.inventory != null and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "B opens the bag screen with the mouse free")
	await shot("bag_open")
	# Take the scope off the AKM into the bag, fit it on the M416.
	p.detach(1, "sight")
	check(p.spares.has("x4") and not p.slots[1].att.has("sight"), "scope taken off into the bag")
	check(p.fit_spare(p.spares.find("x4"), 0) and p.slots[0].att.get("sight", "") == "x4", "scope fitted on the M416 from the bag")
	# Drop things.
	p.drop_ammo("556", 30)
	check(p.ammo["556"] == 90 and _ground_count(world, "ammo") == 1, "dropped 30 rounds")
	p.drop_heal("bandage")
	check(p.heals["bandage"] == 4 and _ground_count(world, "heal") == 1, "dropped a bandage")
	p.drop_gear("vest")
	check(p.gear.vest == 0 and _ground_count(world, "gear") == 1, "dropped the vest")
	p.drop_slot(1)
	check(p.slots[1] == null and _ground_count(world, "weapon") == 1, "dropped the AKM")
	p.detach(0, "sight")
	var si: int = p.spares.find("x4")
	p.drop_spare(si)
	check(si >= 0 and not p.spares.has("x4") and _ground_count(world, "attach") == 1, "dropped a spare attachment")
	await wait(0.4)
	check(world.hud.inventory.get_child_count() > 0, "screen rebuilt after changes")
	await shot("bag_after")
	world.hud.toggle_bag()
	await wait(0.2)
	# (Without a window the mouse cannot be captured, so only check that with one.)
	check(world.hud.inventory == null and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"), "B closes it and captures the mouse")
	print("INVENTORY TEST %s (%d failed)" % ["OK" if failed == 0 else "FAILED", failed])
	tree.quit(failed)
