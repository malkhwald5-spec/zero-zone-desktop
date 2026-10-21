extends Node
## Lobby screenshots with different outfits (plain, gold armour, panda mask),
## each with a different squad line-up (solo, squad, team war).
## Run: godot --path godot res://tests/lobby_shots.tscn -- --out=/dir

var out := "user://"

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		# --locale=ar: an Arabic Windows (used to mirror the whole layout).
		if a.begins_with("--locale="): TranslationServer.set_locale(a.substr(9))
		if a.begins_with("--quality="): Game.settings.quality = a.substr(10)
	_run.call_deferred()

func _run() -> void:
	Game.wallet.login_date = Game.today()     # no daily-gift popup over the pictures
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	var modes := ["solo", "squad", "war"]
	var outfits := [Game.LOLA, 0, Game.WARDROBE.size() - 2]
	for k in 3:
		var i: int = outfits[k]
		Game.profile.outfit = i
		Game.settings.mode = modes[k]
		tree.change_scene_to_file("res://scenes/lobby.tscn")
		await wait(2.5)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("lobby_%d.png" % i))
		print("shot lobby ", i)
	Game.settings.mode = "solo"
	tree.quit()
