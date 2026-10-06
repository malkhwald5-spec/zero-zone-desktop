extends Node
## Frames of the studio intro animation, then the lobby.
## Run: godot --path godot res://tests/intro_shots.tscn -- --out=/dir

var out := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	_run.call_deferred()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/splash.tscn")
	await tree.process_frame
	while tree.current_scene == null:
		await tree.process_frame
	var sp = tree.current_scene
	# Follow the intro's own clock (software rendering is slow).
	for at in [0.3, 0.62, 0.78, 1.05, 1.4, 1.9, 2.3, 3.2, 4.2]:
		while not sp._started or sp.t < at:
			await tree.process_frame
		await shot("intro_%02d" % int(at * 10))
	# The outro scatter.
	while sp.get("_out") != null and sp._out < 0.35:
		if tree.current_scene != sp: break
		await tree.process_frame
	if tree.current_scene == sp: await shot("intro_out")
	for i in 600:
		if tree.current_scene and tree.current_scene.name == "Lobby": break
		await tree.create_timer(0.1).timeout
	await tree.create_timer(2.0).timeout
	await shot("lobby")
	tree.quit()
