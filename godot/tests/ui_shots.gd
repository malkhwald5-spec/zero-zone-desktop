extends Node
## The lobby with the battlefield backdrop, a menu page over the soldier art,
## and both loading screen arts. Run with --out=/dir.

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
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await wait(2.5)
	await shot("ui_lobby")
	var lobby = tree.current_scene
	lobby._open("settings")
	await wait(0.6)
	await shot("ui_page")
	lobby._close_panel()
	for i in 2:
		var ls := LoadingScreen.new()
		tree.root.add_child(ls)
		ls.art.texture = load(LoadingScreen.ART[i])
		ls.set_progress(0.6, "جاري بناء الخريطة")
		await wait(1.0)
		await shot("ui_loading_%d" % i)
		ls.queue_free()
	print("UI SHOTS done")
	tree.quit()
