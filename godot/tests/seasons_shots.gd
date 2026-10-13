extends Node
## Seasons Island: the full map screen and a look at each landmark from the air.
## Run: godot --path godot res://tests/seasons_shots.tscn -- --out=/dir

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
	await shot("seasons_map")
	world.hud.toggle_map()
	world.hud.visible = false
	p.jump_from_plane()
	p.open_chute()
	p.state = "chute"
	world.plane_active = false
	world.plane.visible = false
	var views := [["مدينة الشفق", 160.0, 420.0], ["فوهة اللهب", 260.0, 700.0], ["قرية الجليد", 120.0, 300.0],
		["واحة السراب", 140.0, 380.0], ["مطار الرمال", 120.0, 420.0], ["مرفأ الرماد", 90.0, 260.0],
		["المرصد", 60.0, 160.0], ["المنارة", 40.0, 140.0], ["حصن الصنوبر", 110.0, 300.0]]
	var i := 0
	for v in views:
		var t := _place(v[0])
		if t.is_empty(): continue
		_look(p, world, t.pos, v[1], v[2])
		await wait(1.5)
		await shot("seasons_%d" % i)
		i += 1
	# The lake and the river from above.
	var lake: Vector2 = world.island._m(Island.LAKE_C)
	_look(p, world, lake, 380.0, 700.0, Vector2(-0.3, 1.0))
	await wait(1.5)
	await shot("seasons_lake")
	print("SEASONS SHOTS DONE")
	tree.quit()
