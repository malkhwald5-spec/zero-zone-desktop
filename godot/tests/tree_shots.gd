extends Node
## A close look at each kind of tree (pine, leafy, palm, cactus, dead) from
## about 9 m, and a wider view of a wood. Run with --out=/dir.

var out := "user://"

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.weather = "clear"
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 1200:
		if world.ready_done: break
		await wait(0.1)
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(9000, 0, 9000)
	var p: Player = world.player
	p.health = 1e9
	p.jump_from_plane()
	world.plane_active = false
	world.hud.visible = false
	var isl = world.island
	var cam := Camera3D.new()
	world.add_child(cam)
	var kinds := {}
	for t in isl.trees:
		var k: String = t.get("kind", "pine" if t.get("pine", false) else "leafy")
		if not kinds.has(k) and isl.height_at(t.pos.x, t.pos.y) > 3.0: kinds[k] = t
	print("TREES kinds=", kinds.keys())
	for k in kinds:
		var t: Dictionary = kinds[k]
		var h: float = float(t.get("h", 8.0))
		var base := Vector3(t.pos.x, isl.height_at(t.pos.x, t.pos.y), t.pos.y)
		var from := base + Vector3(h * 0.9 + 4.0, h * 0.35 + 1.5, h * 0.5)
		p.global_position = from + Vector3(0, 30, 0)
		cam.global_position = from
		cam.look_at(base + Vector3(0, h * 0.5, 0))
		cam.current = true
		await wait(2.0)
		await shot("tree_" + k)
	tree.quit()
