extends Node
## Loot box of the fallen: a bot's things go into a box with its name, F
## opens the bag on it, "take all" empties it and the box disappears.

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
	# Open ground away from the town loot.
	var c: Vector2 = world.island.towns[0].pos + Vector2(world.island.towns[0].r + 40.0, 0)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	for i in 40:
		if p.state == "ground" and p.is_on_floor(): break
		await wait(0.1)
	p.equip("pack", 2, 0.0)
	var v: Bot = world.bots[0]
	v.state = "ground"
	v.global_position = p.global_position + Vector3(0, 0.3, -4.0)
	v._land()
	v.weapon_id = "m416"
	v.mag = 22
	v.reserve = 75
	v.gear = {"vest": 2, "vest_dur": 120.0, "helmet": 1, "helmet_dur": 60.0, "pack": 0}
	v.meds = 2
	v.frags = 1
	v.display_name = "ذيب"
	var before: int = world.crates.size()
	v.health = 1.0
	v.take_damage(10.0, p)
	await wait(0.3)
	check("bot died", v.dead)
	check("a loot box appeared", world.crates.size() == before + 1)
	var box: Node3D = world.crates[-1] if not world.crates.is_empty() else null
	var inside := []
	if box:
		for it in world.pickups_near(box.global_position + Vector3(0, 0.55, 0), 1.0):
			if it.has_meta("crate") and it.get_meta("crate") == box: inside.append(it.get_meta("data").kind)
	check("box holds gun, ammo, vest, helmet, frag and meds", inside.size() == 6, str(inside))
	check("box carries the owner's name", box != null and str(box.get_meta("owner")) == "ذيب")
	# Walk up to it: F opens the bag on it.
	p.yaw = 0.0
	p.global_position = box.global_position + Vector3(0, 0.3, 1.6)
	await wait(0.6)
	await shot("crate_world")
	p.interact()
	await wait(0.4)
	check("F next to the box opens the bag", world.hud.bag_open)
	await shot("crate_bag")
	var inv: InventoryPanel = world.hud.inventory
	var took := false
	if inv:
		var head_btn: Button = null
		for n in inv.find_children("*", "Button", true, false):
			if n.text == "أخذ الكل": head_btn = n
		if head_btn:
			head_btn.pressed.emit()
			took = true
	check("take-all button there", took)
	await wait(0.4)
	check("got the M416", p.slots[0] != null and p.slots[0].id == "m416", str(p.slots))
	check("got the vest", p.gear.vest == 2)
	check("got the ammo", p.ammo["556"] >= 75, str(p.ammo["556"]))
	check("box gone once empty", not is_instance_valid(box) or box.is_queued_for_deletion() or not world.crates.has(box))
	await shot("crate_after")
	world.hud.toggle_bag()
	print("CRATE TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
