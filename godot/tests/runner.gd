extends Node
## Automated smoke test: lobby -> match -> plane -> skydive -> landing, saving screenshots.
## Run: godot --path godot res://tests/runner.tscn -- --out=/some/dir

var out := "user://"
var log_lines := []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	if OS.get_cmdline_user_args().has("--low"):
		Game.settings.quality = "low"
	_run.call_deferred()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name, " t=", Time.get_ticks_msec())

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _run() -> void:
	# Detach from the current scene so scene changes do not free the runner.
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/splash.tscn")
	await wait(1.6)
	await shot("splash")
	for i in 100:
		if tree.current_scene and tree.current_scene.get_child_count() > 0 and tree.current_scene.get_child(-1) is LoadingScreen: break
		await wait(0.1)
	await wait(1.0)
	await shot("loading")
	for i in 100:
		if tree.current_scene and tree.current_scene.name == "Lobby": break
		await wait(0.1)
	await wait(1.5)
	await shot("lobby")
	var lobby = tree.current_scene
	Game.wallet.gold = 500
	lobby._open("inventory")
	await wait(0.6)
	await shot("lobby_inventory")
	lobby._open("season")
	await wait(0.4)
	await shot("lobby_season")
	lobby._close_panel()
	lobby._start()
	await wait(1.2)
	await shot("match_loading")
	var world = tree.current_scene
	for i in 300:
		if world.ready_done: break
		await wait(0.1)
	print("world built; bots=", world.bots.size(), " pickups=", world.pickups.size())
	await shot("plane")
	# Wait until the plane is over land, then jump.
	for i in 200:
		if world.plane_over_land(): break
		await wait(0.1)
	world.player.interact()
	print("state after jump: ", world.player.state)
	world.player.pitch = -0.6
	await wait(1.5)
	await shot("fall")
	world.player.open_chute()
	await wait(1.5)
	await shot("chute")
	# Speed up the descent for the test.
	world.player.global_position.y = world.ground_height(world.player.global_position) + 8.0
	for i in 100:
		if world.player.state == "ground": break
		await wait(0.1)
	print("landed: ", world.player.state, " at ", world.player.global_position)
	world.player.pitch = -0.12
	world.player.give_weapon("m416", 30)
	world.player.ammo["556"] = 90
	await wait(1.0)
	await shot("ground")
	world.player.firing = true
	await wait(0.6)
	world.player.firing = false
	print("mag after burst: ", world.player.slots[0].mag)
	world.player.action("crouch", true)
	await wait(0.5)
	await shot("crouch")
	world.hud.toggle_bag()
	await wait(0.3)
	await shot("bag")
	world.hud.toggle_bag()
	world.hud.toggle_map()
	await wait(0.4)
	await shot("map")
	print("TEST DONE")
	get_tree().quit()
