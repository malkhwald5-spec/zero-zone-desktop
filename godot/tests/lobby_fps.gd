extends Node
## Frame rate in the lobby (after it settles), at the given quality.
## Run: godot --path godot res://tests/lobby_fps.tscn -- [--quality=high]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="): Game.settings.quality = a.substr(10)
	Game.settings.fps = 120
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await tree.create_timer(4.0).timeout
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await tree.create_timer(6.0).timeout
	var fps := (Engine.get_frames_drawn() - f0) / ((Time.get_ticks_msec() - t0) / 1000.0)
	print("LOBBY FPS %.1f quality %s" % [fps, Game.settings.quality])
	tree.quit()
