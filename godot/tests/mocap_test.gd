extends Node
## The motion-captured moves (CMU): pushing off into a sprint, braking out of
## one, hurdling a low wall at a run and rolling out of a fall while moving.
## Pictures of each when rendered: godot --path godot res://tests/mocap_test.tscn -- --out=/dir

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
	Game.spawn_island = false
	_run.call_deferred()

## Faces the most open way along the ground.
func open_yaw(p: Player) -> float:
	var best := p.yaw
	var best_d := -1.0
	var space := p.get_world_3d().direct_space_state
	for i in 24:
		var y := TAU * float(i) / 24.0
		var from := p.global_position + Vector3(0, 0.6, 0)
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(-sin(y), 0, -cos(y)) * 50.0, 1, [p.get_rid()]))
		var free: float = 50.0 if h.is_empty() else from.distance_to(h.position)
		if free > best_d:
			best_d = free
			best = y
	return best

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
	var c: Vector2 = world.island.towns[3].pos + Vector2(world.island.towns[3].r + 60.0, 0)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	p._land()
	p.health = 100.0
	if OS.get_cmdline_user_args().has("--armed"):
		p.give_weapon("m416", 30)
		p.ammo["556"] = 60
	await wait(1.0)
	p.yaw = open_yaw(p)
	p.pitch = -0.2
	await wait(0.5)
	# Push off into a sprint from standing.
	p.touch_move = Vector2(0, 1)
	p.sprinting = true
	await wait(0.15)
	check("push-off plays", p.model._action == "c_run_start", p.model._action)
	await wait(0.2)
	await shot("mocap_start")
	await wait(2.0)
	await shot("mocap_sprint")
	var v0 := Vector2(p.velocity.x, p.velocity.z).length()
	# Let go: brake over a couple of strides.
	p.touch_move = Vector2.ZERO
	p.sprinting = false
	await wait(0.12)
	check("brake plays", p.model._action == "c_run_stop", p.model._action)
	var v1 := Vector2(p.velocity.x, p.velocity.z).length()
	check("still carried on a moment", v1 > 2.0 and v1 < v0, "%.1f -> %.1f" % [v0, v1])
	await wait(0.25)
	await shot("mocap_brake")
	await wait(1.0)
	check("comes to a stop", Vector2(p.velocity.x, p.velocity.z).length() < 0.5)
	# Steering again during a brake takes over at once.
	p.touch_move = Vector2(0, 1)
	p.sprinting = true
	await wait(2.0)
	p.touch_move = Vector2.ZERO
	p.sprinting = false
	await wait(0.1)
	p.touch_move = Vector2(1, 0)
	await wait(0.1)
	check("brake cancelled by moving", p._brake_t <= 0.0)
	p.touch_move = Vector2.ZERO
	await wait(0.8)
	# Hurdle a low wall at a run (on level ground: a way where the ground
	# 7 m ahead is at your height).
	var gy: float = world.ground_height(p.global_position)
	for k in 24:
		var tf := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		var ok := true
		for d in [2.0, 4.0, 7.0, 9.0]:
			if absf(world.ground_height(p.global_position + tf * d) - gy) > 0.3: ok = false
		var o := p.global_position + Vector3(0, 0.5, 0)
		if not p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + tf * 12.0, 1, [p.get_rid()])).is_empty(): ok = false
		if ok: break
		p.yaw += TAU / 24.0
	await wait(0.3)
	var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(3.0, 0.9, 0.25)
	cs.shape = bx
	wall.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bx.size
	mi.mesh = bm
	wall.add_child(mi)
	world.add_child(wall)
	var wp := p.global_position + fwd * 7.0
	wall.global_position = Vector3(wp.x, world.ground_height(wp) + 0.45, wp.z)
	wall.rotation.y = p.yaw
	await wait(0.2)
	p.touch_move = Vector2(0, 1)
	p.sprinting = true
	var vaulted := false
	for i in 60:
		await wait(0.02)
		if p.vault_t < 0.0 and p.global_position.distance_to(wall.global_position) < 1.05: p.jump_queued = true
		if p.model._action == "c_run_vault":
			vaulted = true
			break
	check("hurdles the wall at a run", vaulted, "%s d=%.2f floor=%s spd=%.1f h=%.2f" % [p.model._action, p.global_position.distance_to(wall.global_position), p.is_on_floor(), Vector2(p.velocity.x, p.velocity.z).length(), wall.global_position.y - p.global_position.y])
	await wait(0.2)
	await shot("mocap_vault")
	await wait(1.0)
	check("over the wall", (p.global_position - wall.global_position).dot(fwd) > 0.3)
	p.touch_move = Vector2.ZERO
	p.sprinting = false
	await wait(1.0)
	# A long drop while running on: roll.
	p.global_position += Vector3(0, 9.0, 0)
	p.velocity = fwd * 6.0
	p.touch_move = Vector2(0, 1)
	var rolled := false
	for i in 60:
		await wait(0.05)
		if p.model._action == "c_dive_roll":
			rolled = true
			break
	check("rolls out of the fall", rolled, p.model._action)
	await wait(0.3)
	await shot("mocap_roll")
	check("keeps moving through it", Vector2(p.velocity.x, p.velocity.z).length() > 1.5, "%.1f" % Vector2(p.velocity.x, p.velocity.z).length())
	p.touch_move = Vector2.ZERO
	# Coming down under the canopy: feet first, knees give.
	await wait(1.5)
	p.state = "chute"
	p._land()
	check("canopy landing plays", p.model._action == "c_land", p.model._action)
	print("MOCAP TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit(1 if fails > 0 else 0)
