extends Node
## Full map screen pictures: on the plane (route) and later (zones, markers).
## Run: godot --path godot res://tests/map_shots.tscn -- --out=/dir

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
	_run.call_deferred()

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
	await wait(3.0)
	world.hud.toggle_map()
	await wait(0.5)
	await shot("map_plane")
	world.hud.toggle_map()
	var p: Player = world.player
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[0].pos
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 2.0, c.y)
	world.plane_active = false
	world.zone.start()
	await wait(1.0)
	world.hud.toggle_map()
	await wait(0.5)
	await shot("map_zone")
	var hud = world.hud
	hud.marker = c + Vector2(260, -180)
	hud.map_zoom = 3.5
	hud.map_focus = c + Vector2(80, -60)
	await wait(0.5)
	await shot("map_zoom")
	hud.toggle_map()
	await wait(0.5)
	await shot("hud_marker")
	print("MAP SHOTS DONE")
	tree.quit()
