extends Node
## Every lobby screen in turn (main, each page), then pressing start: the
## loading screen and the first view of the match, with the time it took.
## Run: godot --path godot res://tests/lobby_tour.tscn -- --out=/dir

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

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await wait(3.0)
	await shot("tour_main")
	var lobby = tree.current_scene
	for page in ["inventory", "cards", "workshop", "season", "missions", "mail", "clan", "shop", "crate", "events", "settings", "mode", "help"]:
		lobby._open(page)
		await wait(0.8)
		await shot("tour_" + page)
		lobby._close_panel()
		await wait(0.2)
	var t0 := Time.get_ticks_msec()
	lobby._start()
	await wait(1.5)
	await shot("tour_loading")
	var world = null
	for i in 1200:
		world = tree.current_scene
		if world and world.get("ready_done"): break
		await wait(0.1)
	print("TOUR match ready after %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	await wait(2.0)
	await shot("tour_spawn")
	print("TOUR DONE")
	tree.quit()
