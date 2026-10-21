extends Node
## The lobby scene with no menus over it (backdrop for UI mock-ups).
## Run: godot --path godot res://tests/lobby_clean.tscn -- --out=/dir

var out := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.wallet.login_date = Game.today()
	Game.wallet.intro_done = true
	if String(Game.profile.name) == "": Game.profile.name = "لاعب"
	Game.settings.mode = "squad"
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await tree.create_timer(3.0).timeout
	var lobby = tree.current_scene
	lobby.ui.visible = false
	for f in 30: await tree.process_frame
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(out.path_join("lobby_clean.png"))
	print("shot lobby_clean")
	Game.settings.mode = "solo"
	Game.save_data()
	tree.quit()
