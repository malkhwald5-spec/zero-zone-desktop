extends Node
## The whole way through, as a player clicks it: the splash, the lobby (the
## phone's back button asks before quitting), into a match, the results,
## "play again", pausing (back button, the app sent to the background),
## leaving with the confirm, and back in the lobby. Also: only real people
## (no armoured robot) anywhere.

var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok: fails += 1

func _ready() -> void:
	Game.settings.controls = "touch"
	Game.settings.mode = "solo"
	_run.call_deferred()

func _scene_is(path: String) -> bool:
	var sc := get_tree().current_scene
	return sc != null and sc.scene_file_path == path

func _until(path: String, sec: float) -> bool:
	for i in int(sec * 4.0):
		if _scene_is(path): return true
		await wait(0.25)
	return _scene_is(path)

func _world_ready(sec: float) -> Node:
	for i in int(sec * 4.0):
		var w := get_tree().current_scene
		if w and w.scene_file_path == "res://scenes/world.tscn" and w.get("ready_done"): return w
		await wait(0.25)
	return null

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	check("back button does not quit", not tree.is_quit_on_go_back())
	tree.change_scene_to_file("res://scenes/splash.tscn")
	check("splash -> lobby", await _until("res://scenes/lobby.tscn", 40.0))
	await wait(1.0)
	var lobby = tree.current_scene
	check("lobby character is a real person", lobby.soldier.character != "soldier", lobby.soldier.character)
	lobby.go_back()
	check("back in the lobby asks first", lobby._exit_box != null)
	lobby.go_back()
	check("back again closes the question", lobby._exit_box == null)
	lobby._open("settings")
	await wait(0.3)
	lobby.go_back()
	check("back closes an open page", lobby.panel == null)
	lobby._start()
	var world = await _world_ready(240.0)
	check("lobby -> match", world != null)
	if world == null:
		print("FLOW TEST FAILED (%d failed)" % fails)
		tree.quit()
		return
	var robots: Array = world.bots.filter(func(b): return b.model.character == "soldier")
	check("no robot bots", robots.is_empty(), "%d" % robots.size())
	check("player is a real person", world.player.model.character != "soldier")
	world.go_back()
	await wait(0.2)
	check("back button in a match pauses", world.hud.pause_panel != null and tree.paused)
	world.hud.toggle_pause()
	await wait(0.2)
	check("unpaused", not tree.paused)
	world.app_paused()
	check("app in the background pauses", tree.paused and world.hud.pause_panel != null)
	world.hud.toggle_pause()
	# Win it: the results with "play again".
	world._end_match(true)
	await wait(4.5)
	check("results shown", world.hud.results != null)
	var labels: Array = []
	if world.hud.results:
		for b in world.hud.results.find_children("*", "Button", true, false): labels.append(b.text)
	check("play again offered", labels.has("العب مرة ثانية"), str(labels))
	world.hud._play_again()
	await wait(1.0)
	var world2 = await _world_ready(240.0)
	check("play again -> new match", world2 != null and world2 != world)
	if world2:
		# Leave while alive: asked first, then the lobby.
		world2.hud.toggle_pause()
		world2.hud._confirm_leave()
		await wait(0.2)
		var labels2: Array = []
		for b in world2.hud.pause_panel.find_children("*", "Button", true, false): labels2.append(b.text)
		check("leaving asks first", labels2.has("إيه، اطلع"), str(labels2))
		world2.hud._to_lobby()
		check("match -> lobby", await _until("res://scenes/lobby.tscn", 30.0))
		await wait(1.0)
		check("lobby works after a match", tree.current_scene.soldier != null and not tree.paused)
	print("FLOW TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	tree.quit()
