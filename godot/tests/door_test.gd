extends Node
## Doors: a shut door blocks the doorway, F opens it (away from you) and
## shuts it, walking into a shut door opens it (auto-open setting), a bot
## walking through opens it too. Pictures of a shut and an open door.

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
	_run.call_deferred()

func _blocked(world, d: Dictionary) -> bool:
	var a: Vector3 = d.center + d.normal * 1.2
	var b: Vector3 = d.center - d.normal * 1.2
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and Vector2(hit.position.x - d.center.x, hit.position.z - d.center.z).length() < 0.8

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
	var doors: Array = world.builder.doors
	check("houses have doors", doors.size() > 200, str(doors.size()))
	var p: Player = world.player
	p.jump_from_plane()
	# A shut door on flat, dry ground.
	var d: Dictionary = {}
	for dd in doors:
		var o: Vector3 = dd.center + dd.normal * 2.5
		if dd.target < 0.5 and absf(world.ground_height(o) - (dd.center.y - 1.1)) < 0.4:
			d = dd
			break
	check("found a shut door", not d.is_empty())
	var outside: Vector3 = d.center + d.normal * 1.4
	p.global_position = Vector3(outside.x, d.center.y - 1.0, outside.z)
	p.velocity = Vector3.ZERO
	var to: Vector3 = d.center - outside
	p.yaw = atan2(-to.x, -to.z)
	p.pitch = -0.05
	Game.settings.auto_door = false
	await wait(1.0)
	check("shut door blocks the doorway", _blocked(world, d))
	check("prompt offers the door", p.door_target() == d)
	await shot("door_shut")
	p.interact()
	await wait(1.0)
	check("F opens it", d.target == 1.0 and d.t == 1.0 and not _blocked(world, d))
	# It swung away from you (into the house).
	var tip: Vector3 = d.pivot.global_transform * Vector3(1.2, 1.0, 0)
	check("opens away from you", (tip - d.center).dot(d.normal) < -0.3, str((tip - d.center).dot(d.normal)))
	await shot("door_open")
	p.interact()
	await wait(1.0)
	check("F shuts it", d.t == 0.0 and _blocked(world, d))
	# Auto-open: walk into it.
	Game.settings.auto_door = true
	var ctl: String = Game.settings.controls
	Game.settings.controls = "touch"
	p.touch_move = Vector2(0, 1)
	for i in 30:
		await wait(0.05)
		if d.target > 0.5: break
	p.touch_move = Vector2.ZERO
	Game.settings.controls = ctl
	check("walking into it opens it", d.target > 0.5)
	await wait(1.0)
	world.toggle_door(d, outside)
	await wait(1.0)
	# A bot walking through.
	var b = world.bots[0]
	b.global_position = Vector3(outside.x, d.center.y - 1.0, outside.z) + d.along * 0.0
	b.velocity = Vector3.ZERO
	var inside: Vector3 = d.center - d.normal * 3.0
	b.state = "ground"
	b.visible = true
	b.goal = Vector3(inside.x, d.center.y - 1.0, inside.z)
	b.mode = "roam"
	for i in 60:
		await wait(0.1)
		b.goal = Vector3(inside.x, d.center.y - 1.0, inside.z)
		b.mode = "roam"
		if d.target > 0.5: break
	check("a bot opens it", d.target > 0.5)
	print("DOOR TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	tree.quit()
