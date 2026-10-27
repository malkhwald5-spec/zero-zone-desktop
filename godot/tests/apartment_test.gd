extends Node
## Apartment blocks: walk up every flight to the flat roof and take pictures.
## Run: godot --path godot res://tests/apartment_test.tscn -- --out=/dir

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
	Game.settings.weather = "clear"
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
	var blk: Dictionary = {}
	var n := 0
	for b in world.island.buildings:
		if b.get("kind", "") == "apartment":
			n += 1
			if blk.is_empty(): blk = b
	check(n > 0, "apartment blocks exist  count=%d" % n)
	if blk.is_empty():
		tree.quit(1)
		return
	var storeys: int = blk.storeys
	var c: Vector2 = blk.pos
	var floor_y: float = blk.floor
	var hx: float = blk.size.x * 0.5
	var hz: float = blk.size.y * 0.5
	# Outside view first.
	var o := c + Vector2(hx + 16.0, -hz - 16.0)
	p.jump_from_plane()
	p.global_position = Vector3(o.x, world.ground_height(Vector3(o.x, 0, o.y)) + 0.3, o.y)
	p.velocity = Vector3.ZERO
	var to := Vector3(c.x, floor_y, c.y) - p.global_position
	p.yaw = atan2(-to.x, -to.z)
	p.pitch = 0.32
	await wait(1.5)
	await shot("apt_outside")
	var loot := 0
	for pk in world.pickups:
		if not is_instance_valid(pk): continue
		var q: Vector3 = pk.global_position
		if absf(q.x - c.x) < hx and absf(q.z - c.y) < hz and q.y > floor_y + 1.0: loot += 1
	print("loot upstairs: %d" % loot)
	# Every flight, from the floor below up to the next (the last to the roof).
	for lv in range(1, storeys + 1):
		var w: int = blk.stair if lv % 2 == 1 else (int(blk.stair) + 2) % 4
		var along_x := w == 0 or w == 2
		var length: float = blk.size.x if along_x else blk.size.y
		var band: float = [-hz + WorldBuilder.WALL_T + WorldBuilder.STAIR_W * 0.5, hx - WorldBuilder.WALL_T - WorldBuilder.STAIR_W * 0.5,
			hz - WorldBuilder.WALL_T - WorldBuilder.STAIR_W * 0.5, -hx + WorldBuilder.WALL_T + WorldBuilder.STAIR_W * 0.5][w]
		var start := -length * 0.5 + WorldBuilder.WALL_T + 1.2
		var dir := Vector2(1, 0) if along_x else Vector2(0, 1)
		var base := Vector2(start - 0.6, band) if along_x else Vector2(band, start - 0.6)
		var y0 := floor_y + (lv - 1) * WorldBuilder.STOREY_H
		p.global_position = Vector3(c.x + base.x, y0 + 0.3, c.y + base.y)
		p.velocity = Vector3.ZERO
		p.yaw = atan2(-dir.x, -dir.y)
		p.pitch = 0.1
		await wait(0.8)
		if lv == 1 or lv == storeys: await shot("apt_flight%d" % lv)
		Input.action_press("move_forward")
		for i in 60: await wait(0.1)
		Input.action_release("move_forward")
		await wait(0.5)
		var up := p.global_position.y - y0
		check(up > WorldBuilder.STOREY_H - 0.4 and up < WorldBuilder.STOREY_H + 0.6, "flight %d walked up  height=%.2f" % [lv, up])
		if lv < storeys and lv == 2:
			p.yaw += PI * 0.5
			p.pitch = -0.1
			await wait(0.8)
			await shot("apt_floor%d" % lv)
	# On the roof: look out over the town past the parapet.
	var ry := floor_y + storeys * WorldBuilder.STOREY_H
	check(p.global_position.y > ry - 0.3, "on the roof  y=%.2f roof=%.2f" % [p.global_position.y, ry])
	p.global_position = Vector3(c.x, ry + 0.3, c.y)
	p.velocity = Vector3.ZERO
	p.pitch = -0.05
	await wait(1.0)
	await shot("apt_roof")
	p.yaw += PI
	await wait(0.6)
	await shot("apt_roof2")
	# Walk into the parapet: it must hold.
	Input.action_press("move_forward")
	for i in 40: await wait(0.1)
	Input.action_release("move_forward")
	await wait(0.5)
	var q := p.global_position
	check(absf(q.x - c.x) < hx and absf(q.z - c.y) < hz and q.y > ry - 0.3, "parapet keeps you on the roof  pos=%s" % [q - Vector3(c.x, ry, c.y)])
	# Warehouse gallery: up the steel stair along the -z wall.
	var wh: Dictionary = {}
	for b in world.island.buildings:
		if WorldBuilder.has_mezzanine(b): wh = b
	check(not wh.is_empty(), "a warehouse with a gallery exists")
	if not wh.is_empty():
		var wc: Vector2 = wh.pos
		var whx: float = wh.size.x * 0.5
		var whz: float = wh.size.y * 0.5
		var x1 := -whx + WorldBuilder.MEZZ_D
		var band := -whz + WorldBuilder.WALL_T + WorldBuilder.STAIR_W * 0.5
		p.global_position = Vector3(wc.x + x1 + WorldBuilder.STAIR_RUN + 1.0, float(wh.floor) + 0.3, wc.y + band)
		p.velocity = Vector3.ZERO
		p.yaw = atan2(1.0, 0.0)     # facing -x
		p.pitch = 0.05
		await wait(1.0)
		await shot("wh_stairs")
		Input.action_press("move_forward")
		for i in 50: await wait(0.1)
		Input.action_release("move_forward")
		await wait(0.5)
		var up := p.global_position.y - float(wh.floor)
		check(up > WorldBuilder.STOREY_H - 0.4 and up < WorldBuilder.STOREY_H + 0.6, "walked up to the gallery  height=%.2f" % up)
		p.global_position = Vector3(wc.x - whx + 1.6, float(wh.floor) + WorldBuilder.STOREY_H + 0.3, wc.y + whz * 0.6)
		p.velocity = Vector3.ZERO
		p.yaw = atan2(-1.0, 0.3)
		p.pitch = -0.25
		await wait(1.0)
		await shot("wh_gallery")
	# A ruin from outside.
	var rn: Dictionary = {}
	var nr := 0
	for b in world.island.buildings:
		if b.get("kind", "") == "ruin":
			nr += 1
			if rn.is_empty() or b.pos.distance_to(blk.pos) < rn.pos.distance_to(blk.pos): rn = b
	check(nr > 0, "ruins exist  count=%d" % nr)
	if not rn.is_empty():
		var rc: Vector2 = rn.pos
		var ro := rc + Vector2(rn.size.x * 0.5 + 9.0, rn.size.y * 0.5 + 9.0)
		p.global_position = Vector3(ro.x, world.ground_height(Vector3(ro.x, 0, ro.y)) + 0.3, ro.y)
		p.velocity = Vector3.ZERO
		var tr := Vector3(rc.x, float(rn.floor), rc.y) - p.global_position
		p.yaw = atan2(-tr.x, -tr.z)
		p.pitch = 0.25
		await wait(1.5)
		await shot("ruin")
	print("APARTMENT TEST %s (%d failed)" % ["OK" if failed == 0 else "FAILED", failed])
	tree.quit(failed)
