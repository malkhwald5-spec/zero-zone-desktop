extends Node
## Dune Valley: the full map screen, each landmark from the air, and a few
## views from the ground (the old city lanes, the souq, the castle gate).
## Run: godot --path godot res://tests/dunes_shots.tscn -- --out=/dir --map=dunes

var out := "user://"

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.controls = "kbm"
	_run.call_deferred()

func _place(name: String) -> Dictionary:
	for t in get_tree().current_scene.island.towns:
		if t.name == name: return t
	return {}

## Hovers the camera at `up` metres, `back` metres away from the spot, looking at it.
func _look(p: Player, world, at: Vector2, up: float, back: float, from_dir := Vector2(0.5, 1.0)) -> void:
	var d := from_dir.normalized()
	var eye := at + d * back
	var gy: float = world.ground_height(Vector3(at.x, 0, at.y))
	p.global_position = Vector3(eye.x, gy + up, eye.y)
	p.velocity = Vector3.ZERO
	p.yaw = atan2(d.x, d.y)
	p.pitch = -atan2(up, back)

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
	await wait(2.0)
	world.hud.toggle_map()
	await wait(0.6)
	await shot("dunes_map")
	world.hud.toggle_map()
	world.hud.visible = false
	p.jump_from_plane()
	p.open_chute()
	p.state = "chute"
	world.plane_active = false
	world.plane.visible = false
	var views := [["المدينة القديمة", 170.0, 420.0], ["القلعة", 70.0, 170.0], ["واحة النخيل", 90.0, 260.0],
		["ميناء الصيادين", 80.0, 240.0], ["مطار الصحراء", 110.0, 380.0], ["محطة النفط", 90.0, 260.0],
		["قرية الطين", 70.0, 200.0], ["المحجر", 60.0, 180.0], ["المنارة", 40.0, 140.0]]
	var i := 0
	for v in views:
		var t := _place(v[0])
		if t.is_empty(): continue
		_look(p, world, t.pos, v[1], v[2])
		await wait(1.5)
		await shot("dunes_%d" % i)
		i += 1
	# On the ground: in the old city's lanes and by the castle gate.
	p.state = "ground"
	p._land()
	var med := _place("المدينة القديمة")
	for k in 3:
		var at: Vector2 = med.pos + Vector2(40.0 + k * 30.0, 0).rotated(k * 2.1)
		p.global_position = Vector3(at.x, world.ground_height(Vector3(at.x, 0, at.y)) + 0.3, at.y)
		p.velocity = Vector3.ZERO
		p.yaw = k * 2.1 + PI * 0.5
		p.pitch = 0.05
		await wait(1.5)
		await shot("dunes_ground_%d" % k)
	var cas := _place("القلعة")
	_look(p, world, cas.pos, 30.0, 95.0, Vector2(0.8, 0.6))
	p.state = "chute"
	await wait(1.5)
	await shot("dunes_castle_close")
	print("DUNES SHOTS DONE")
	tree.quit()
