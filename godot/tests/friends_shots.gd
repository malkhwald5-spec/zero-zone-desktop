extends Node
## The "play with friends" panel: before opening a room, and as the host.
## Run: godot --path godot res://tests/friends_shots.tscn -- --out=/dir

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
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await wait(3.0)
	var lobby = tree.current_scene
	for c in lobby.ui.get_children():
		if c is ColorRect and c != lobby.ui.get_child(0): c.queue_free()     # daily gift etc.
	lobby._friends_room()
	await wait(1.0)
	await shot("friends_find")
	lobby._f_host()
	await wait(1.0)
	await shot("friends_host")
	Net.leave()
	tree.quit()
