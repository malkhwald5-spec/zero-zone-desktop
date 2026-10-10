extends Node
## Windows: a shot through a pane breaks it (and only that one), the bullet
## goes on, a grenade blast breaks the panes around it. Pictures before and
## after shooting out a window.

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

func _normal(pn: Dictionary) -> Vector3:
	return Vector3(0, 0, 1) if pn.ax else Vector3(1, 0, 0)

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
	var panes: Array = world.builder.panes
	check("houses have window panes", panes.size() > 1000, str(panes.size()))
	var p: Player = world.player
	p.jump_from_plane()
	# A ground-floor pane with open, flat ground in front of it.
	var pn: Dictionary = {}
	var front := Vector3.ZERO
	for cand in panes:
		if cand.c.y - world.ground_height(cand.c) > 2.5: continue
		var b: Dictionary = world.island.buildings[cand.b]
		var n := _normal(cand)
		# Outwards = away from the building centre.
		var bc := Vector3(b.pos.x, cand.c.y, b.pos.y)
		if (cand.c - bc).dot(n) < 0.0: n = -n
		var f: Vector3 = cand.c + n * 6.0
		if world.building_at(Vector2(f.x, f.z)) >= 0: continue
		if absf(world.ground_height(f) - world.ground_height(cand.c)) > 0.6: continue
		pn = cand
		front = f
		break
	check("found a window", not pn.is_empty())
	p.global_position = Vector3(front.x, world.ground_height(front) + 0.2, front.z)
	p.velocity = Vector3.ZERO
	var to: Vector3 = pn.c - front
	p.yaw = atan2(-to.x, -to.z)
	p.pitch = atan2(to.y - 1.5, Vector2(to.x, to.z).length()) * 0.6
	await wait(1.5)
	await shot("window_before")
	# A shot straight through it.
	var a: Vector3 = front + Vector3(0, pn.c.y - front.y, 0)
	var b2: Vector3 = pn.c + (pn.c - a).normalized() * 3.0
	var alive_before := 0
	for q in panes: if q.alive: alive_before += 1
	world.bullet_glass(a, b2)
	var alive_after := 0
	for q in panes: if q.alive: alive_after += 1
	check("shot breaks the pane", not pn.alive)
	check("only that pane", alive_before - alive_after == 1, "%d" % (alive_before - alive_after))
	await wait(0.25)
	await shot("window_shatter")
	await wait(1.5)
	await shot("window_after")
	# A shot that misses the glass (above the roof) breaks nothing.
	var before := alive_after
	world.bullet_glass(a + Vector3(0, 12, 0), b2 + Vector3(0, 12, 0))
	var now := 0
	for q in panes: if q.alive: now += 1
	check("a miss breaks nothing", now == before)
	# A grenade next to another house.
	var other: Dictionary = {}
	for cand in panes:
		if cand.alive and cand.b != pn.b:
			other = cand
			break
	world.explode(other.c + _normal(other) * 2.0, null)
	await wait(0.2)
	check("blast breaks nearby panes", not other.alive)
	print("WINDOW TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	tree.quit()
