extends Node
## Two-storey houses: walk up the stairs to the first floor and take pictures.
## Run: godot --path godot res://tests/house_test.tscn -- --out=/dir

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
		if a.begins_with("--quality="): Game.settings.quality = a.substr(10)
	Game.settings.controls = "kbm"
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
	world.hud.visible = false
	for b in world.bots: b.set_physics_process(false)
	var house: Dictionary = {}
	var n2 := 0
	for b in world.island.buildings:
		if b.get("storeys", 1) == 2:
			n2 += 1
			if house.is_empty(): house = b
	check(n2 > 0, "two-storey houses exist  count=%d" % n2)
	if house.is_empty():
		tree.quit(1)
		return
	# Same layout maths as WorldBuilder._upper_floor.
	var sx: float = house.size.x
	var sz: float = house.size.y
	var hx := sx * 0.5
	var hz := sz * 0.5
	var w: int = house.stair
	var along_x := w == 0 or w == 2
	var length := sx if along_x else sz
	var band: float = [-hz + WorldBuilder.WALL_T + WorldBuilder.STAIR_W * 0.5, hx - WorldBuilder.WALL_T - WorldBuilder.STAIR_W * 0.5,
		hz - WorldBuilder.WALL_T - WorldBuilder.STAIR_W * 0.5, -hx + WorldBuilder.WALL_T + WorldBuilder.STAIR_W * 0.5][w]
	var start := -length * 0.5 + WorldBuilder.WALL_T + 1.2
	var dir := Vector2(1, 0) if along_x else Vector2(0, 1)
	var base := Vector2(start - 0.6, band) if along_x else Vector2(band, start - 0.6)
	var c: Vector2 = house.pos
	var floor_y: float = house.floor
	var hs := []
	for dx in [-3.0, 0.0, 3.0]:
		for dz in [-3.0, 0.0, 3.0]:
			hs.append(snappedf(world.island.height_at(c.x + dx, c.y + dz) - floor_y, 0.01))
	check(hs.max() < -0.05, "ground stays under the floor boards  ground-floor=%s" % [hs])
	p.jump_from_plane()
	p.global_position = Vector3(c.x + base.x, floor_y + 0.3, c.y + base.y)
	p.velocity = Vector3.ZERO
	for i in 50:
		if p.state == "ground": break
		await wait(0.1)
	check(p.state == "ground", "standing at the foot of the stairs  state=%s" % p.state)
	p.yaw = atan2(-dir.x, -dir.y)
	p.pitch = 0.0
	await wait(1.0)
	await shot("house_stairs")
	Input.action_press("move_forward")
	var top := -INF
	var from := p.global_position
	for i in 70:
		await wait(0.1)
		top = maxf(top, p.global_position.y)
		if i % 10 == 0: print("  t=%.1f pos=%s move=%s" % [i * 0.1, p.global_position - from, p.move_input])
	Input.action_release("move_forward")
	await wait(0.5)
	var up := p.global_position.y - floor_y
	check(up > WorldBuilder.STOREY_H - 0.4 and up < WorldBuilder.STOREY_H + 0.6, "walked up the stairs  height=%.2f (floor 2 at %.2f)" % [up, WorldBuilder.STOREY_H])
	p.yaw += PI * 0.5
	await wait(0.8)
	await shot("house_upstairs")
	# Ground floor room from the middle, looking at a corner.
	p.global_position = Vector3(c.x, floor_y + 0.3, c.y)
	p.velocity = Vector3.ZERO
	p.yaw = PI * 0.25
	p.pitch = -0.15
	await wait(1.2)
	await shot("house_room")
	p.yaw = PI * 1.25
	await wait(0.8)
	await shot("house_room2")
	p.pitch = -1.2
	await wait(0.8)
	await shot("house_floor")
	print("FLOOR player_y=%.2f floor=%.2f ground=%.2f" % [p.global_position.y, floor_y, world.island.height_at(c.x, c.y)])
	# Outside view of the house.
	var o := c + Vector2(0, -hz - 14.0)
	p.global_position = Vector3(o.x, world.ground_height(Vector3(o.x, 0, o.y)) + 0.3, o.y)
	p.yaw = PI
	p.pitch = 0.18
	await wait(1.2)
	await shot("house_outside")
	print("HOUSE TEST %s (%d failed)" % ["OK" if failed == 0 else "FAILED", failed])
	tree.quit(failed)
