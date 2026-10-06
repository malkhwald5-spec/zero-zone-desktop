extends Node
## Weapon attachments: fitting, stats, swapping, dropping with the gun, and
## (with a renderer) pictures through every sight.
## Run: godot --path godot res://tests/attach_test.tscn -- --out=/dir

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
	Game.settings.quality = "high"
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
	p.health = 1e9
	world.hud.visible = true
	for b in world.bots: b.set_physics_process(false)
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[1].pos + Vector2(40, 40)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 0.5, c.y)
	for i in 50:
		if p.state == "ground": break
		await wait(0.1)
	var spawned := 0
	for it in world.pickups:
		if it.get_meta("data").kind == "attach": spawned += 1
	check(spawned > 50, "attachments lie around the map  count=%d" % spawned)
	p.give_weapon("m416", 30)
	p.ammo["556"] = 120
	check(p.add_attachment("x4") and p.weapon().zoom == 4.0, "4x scope fits the M416  zoom=%s" % p.weapon().zoom)
	var base: Dictionary = Game.WEAPONS["m416"]
	check(p.add_attachment("ext_mag") and p.weapon().mag == int(round(base.mag * 1.35)), "extended mag  mag=%d" % p.weapon().mag)
	check(p.add_attachment("vgrip") and p.weapon().recoil < base.recoil, "vertical grip lowers recoil  %.2f < %.2f" % [p.weapon().recoil, base.recoil])
	check(p.add_attachment("suppressor") and p.weapon().get("suppressed", false), "suppressor")
	# Swapping a sight drops the old one at your feet.
	var n0: int = world.pickups.size()
	check(p.add_attachment("x2") and p.weapon().zoom == 2.0 and world.pickups.size() == n0 + 1, "2x replaces the 4x, which drops")
	# A part that fits none of your guns is refused.
	p.give_weapon("p92", 15)
	p.switch_slot(0)
	var before: Dictionary = p.slots[2].get("att", {}).duplicate()
	check(not Items.attach_fits("x8", "pistol") and p.slots[2].get("att", {}) == before, "8x does not fit a pistol")
	# Picking one up from the ground.
	var it = world._add_pickup({"kind": "attach", "id": "compensator"}, p.global_position)
	world.pickup(p, it)
	check(not world.pickups.has(it), "picking up an attachment fits it")
	# Drop the gun (by taking another) and pick it up again: parts stay on it.
	var att_before: Dictionary = p.slots[0].att.duplicate()
	p.give_weapon("akm", 30)       # goes to the free second slot
	p.switch_slot(0)
	p.give_weapon("ump", 25)       # both full: replaces the M416 in your hands
	var dropped = null
	for d in world.pickups:
		var dd: Dictionary = d.get_meta("data")
		if dd.kind == "weapon" and dd.id == "m416": dropped = d
	check(dropped != null and dropped.get_meta("data").get("att", {}) == att_before, "dropped M416 keeps its attachments")
	# Pictures through each sight (renderer only).
	p.give_weapon("m416", 30)
	for sight in ["reddot", "holo", "x2", "x4", "x8"]:
		p.add_attachment(sight)
		p.yaw = PI * 0.25
		p.pitch = 0.02
		p.aiming = true
		await wait(0.8)
		check(p.scoped(), "aiming through the %s" % sight)
		await shot("sight_" + sight)
	p.aiming = false
	p.yaw = PI * 0.75
	await wait(1.0)
	await shot("gun_with_parts")
	print("ATTACH TEST %s (%d failed)" % ["OK" if failed == 0 else "FAILED", failed])
	tree.quit(failed)
