extends Node
## Pictures of the freefall as the player sees it (game camera and HUD):
## gliding belly-down and diving. Run: godot --path godot res://tests/fall_shots.tscn -- --out=/dir

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
	Game.settings.controls = "touch"
	Game.settings.weather = "clear"
	Game.spawn_island = false
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
	Game.settings.lite = false
	var p: Player = world.player
	for i in 400:
		if world.plane_over_land(): break
		world.plane_t += 0.002
		await tree.process_frame
	p.interact()
	p.pitch = -0.3
	p.touch_move = Vector2(0, 0.6)
	await wait(2.5)
	await shot("fall_glide")
	p.pitch = -1.1
	p.touch_move = Vector2(0, 1)
	await wait(2.5)
	await shot("fall_dive")
	print("FALL SHOTS DONE")
	tree.quit()
