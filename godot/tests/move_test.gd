extends Node
## Lean (Q / E) and vaulting: climbs through a house window, leans out with
## the camera and the gun. Pictures with --out=/dir when rendered.

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

## A window in one of the house walls: [outside point, facing yaw].
func _find_window(world) -> Array:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for b in world.island.buildings:
		if b.get("kind", "house") != "house": continue
		var h: Vector2 = b.size * 0.5
		var y: float = b.floor
		for x in range(int((-h.x + 1.0) * 10), int((h.x - 1.0) * 10), 2):
			var px: float = b.pos.x + x / 10.0
			var a := Vector3(px, y + 1.6, b.pos.y - h.y - 1.0)
			var c := Vector3(px, y + 1.6, b.pos.y - h.y + 1.0)
			var low := space.intersect_ray(PhysicsRayQueryParameters3D.create(a - Vector3(0, 0.75, 0), c - Vector3(0, 0.75, 0), 1))
			var top := space.intersect_ray(PhysicsRayQueryParameters3D.create(a + Vector3(0, 0.45, 0), c + Vector3(0, 0.45, 0), 1))
			var high := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, c, 1))
			# The middle of the opening: clear 0.3 m to both sides too.
			var l2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(a + Vector3(0.3, 0, 0), c + Vector3(0.3, 0, 0), 1))
			var l3 := space.intersect_ray(PhysicsRayQueryParameters3D.create(a - Vector3(0.3, 0, 0), c - Vector3(0.3, 0, 0), 1))
			if high.is_empty() and top.is_empty() and l2.is_empty() and l3.is_empty() and not low.is_empty():
				var g: float = world.ground_height(Vector3(px, 0, b.pos.y - h.y - 0.75))
				return [Vector3(px, maxf(g, y - 0.1) + 0.05, b.pos.y - h.y - 0.75), PI, b]
	return []

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
	var win := _find_window(world)
	check("found a house window", not win.is_empty())
	if win.is_empty():
		tree.quit()
		return
	var b: Dictionary = win[2]
	p.global_position = win[0] + Vector3(0, 0.5, 0)
	p.yaw = win[1]
	p.pitch = -0.1
	for i in 40:
		if p.state == "ground" and p.is_on_floor(): break
		await wait(0.1)
	# Square in front of the opening.
	p.global_position = Vector3(win[0].x, p.global_position.y, p.global_position.z)
	p.give_weapon("m416", 30)
	await wait(0.6)
	await shot("vault_before")
	# Walk up to the wall, then Space: over the sill into the room.
	var face_z: float = b.pos.y - b.size.y * 0.5
	for k in 3:
		p.global_position = Vector3(win[0].x, maxf(p.global_position.y, win[0].y) + 0.05, face_z - 0.6)
		p.velocity = Vector3.ZERO
		p.touch_move = Vector2(0, 1)
		await wait(0.35)
		p.touch_move = Vector2.ZERO
		await wait(0.25)
		if p.is_on_floor() and absf(p.global_position.z - face_z) < 0.8: break
	p.action("jump", true)
	await wait(0.2)
	check("vault started", p.vault_t >= 0.0, "vault_t=%.2f" % p.vault_t)
	if p.vault_t < 0.0:
		# What is in front (for fixing it).
		var sp: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		var fw := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		for hy in [0.05, 0.2, 0.35, 0.5, 0.8, 1.2, 1.6]:
			var o: Vector3 = p.global_position + Vector3(0, hy, 0)
			var hh := sp.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + fw * 3.0, 1, [p.get_rid()]))
			print("  at %.2f m: %s" % [hy, ("hit %.2f m away" % o.distance_to(hh.position)) if not hh.is_empty() else "clear"])
		print("  window at ", win[0], " player ", p.global_position, " on floor ", p.is_on_floor())
	await wait(0.2)
	await shot("vault_mid")
	await wait(1.0)
	var inside: bool = world.building_at(Vector2(p.global_position.x, p.global_position.z)) >= 0
	check("climbed through the window into the house", inside and p.vault_t < 0.0, "pos=%s" % p.global_position)
	check("collision back on after the vault", not p.shape_node.disabled)
	await shot("vault_after")
	# Open ground: nothing to vault, Space jumps.
	var c: Vector2 = b.pos + Vector2(0, -b.size.y * 0.5 - 12.0)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 0.3, c.y)
	p.yaw = PI * 0.5
	await wait(0.8)
	p.action("jump", true)
	await wait(0.1)
	check("no vault on open ground", p.vault_t < 0.0)
	await wait(1.0)
	# Lean right then left: the camera and the gun move out to that side.
	p.yaw = 0.0
	await wait(0.5)
	var cam0: Vector3 = p.camera.global_position
	var gun0: Vector3 = p.model.gun.global_position
	p.action("peek_r", true)
	await wait(0.6)
	var right := p.cam_rig.global_transform.basis.x
	var cam_r: float = (p.camera.global_position - cam0).dot(right)
	var gun_r: float = (p.model.gun.global_position - gun0).dot(right)
	check("lean right moves the camera right", cam_r > 0.3, "%.2f m" % cam_r)
	check("lean right moves the gun right", gun_r > 0.2, "%.2f m" % gun_r)
	await shot("peek_right")
	p.action("peek_l", true)
	await wait(0.8)
	var cam_l: float = (p.camera.global_position - cam0).dot(right)
	check("lean left moves the camera left", cam_l < -0.3, "%.2f m" % cam_l)
	await shot("peek_left")
	p.action("peek_l", true)
	await wait(0.6)
	check("lean off again", absf(p.peek) < 0.01)
	print("MOVE TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
