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
	# Continue on dry ground in a town, away from buildings.
	var town: Dictionary = world.island.towns[0]
	for k in 200:
		var q: Vector2 = town.pos + Vector2(randf_range(0, town.r), 0).rotated(randf() * TAU)
		if world.island.height_at(q.x, q.y) > 1.0 and not world._in_building(q, 4.0):
			world.player.global_position = Vector3(q.x, world.island.height_at(q.x, q.y) + 0.2, q.y)
			break
	world.player.pitch = -0.12
	world.player.give_weapon("m416", 30)
	world.player.ammo["556"] = 90
	world.player.equip("vest", 2, 110.0)
	world.player.equip("helmet", 3, 230.0)
	world.player.equip("pack", 1, 0.0)
	world.player.heals.bandage = 5
	world.player.heals.firstaid = 1
	world.player.heals.drink = 2
	world.player.boost = 55.0
	world.player.health = 62.0
	await wait(1.0)
	await shot("ground")
	world.player.firing = true
	await wait(0.6)
	world.player.firing = false
	print("mag after burst: ", world.player.slots[0].mag)
	world.player.action("crouch", true)
	await wait(0.5)
	await shot("crouch")
	world.hud.toggle_cursor()
	print("ctrl 1: mouse_mode=", Input.mouse_mode, " free=", Game.cursor_free)
	world.hud.toggle_cursor()
	print("ctrl 2: mouse_mode=", Input.mouse_mode, " free=", Game.cursor_free)
	world.hud.toggle_bag()
	await wait(0.3)
	await shot("bag")
	world.hud.toggle_bag()
	world.player.use_heal("bandage")
	await wait(1.2)
	await shot("healing")
	world.hud.toggle_bag()
	world.player.cancel_heal()
	world.hud.toggle_bag()
	world.player.health = 100.0
	world.player.throwables.frag = 2
	world.player.throwables.smoke = 1
	world.player.pitch = 0.15
	world.player.start_throw()
	await wait(0.4)
	await shot("throw_arc")
	world.player.release_throw()
	world.player.pitch = -0.05
	await wait(Grenade.FUSE + 0.12)
	await shot("explosion")
	var ahead := Vector3(-sin(world.player.yaw), 0, -cos(world.player.yaw))
	var sp: Vector3 = world.player.global_position + ahead * 14.0
	world.add_smoke(Vector3(sp.x, world.ground_height(sp), sp.z))
	await wait(2.0)
	await shot("smoke")
	var ad := Airdrop.new()
	ad.world = world
	var dp: Vector3 = world.player.global_position + Vector3(-sin(world.player.yaw), 0, -cos(world.player.yaw)) * 18.0 + Vector3(6, 0, 0)
	ad.target = Vector3(dp.x, world.ground_height(dp), dp.z)
	world.add_child(ad)
	ad.global_position = ad.target + Vector3(0, 9, 0)
	world.airdrops.append(ad)
	world.player.pitch = 0.12
	await wait(0.4)
	await shot("airdrop_falling")
	ad.global_position.y = ad.target.y + 0.3
	await wait(2.5)
	world.player.pitch = -0.05
	await shot("airdrop_landed")
	# A car: walk up to it, then drive.
	var car: Vehicle = world.vehicles[0]
	var ppos: Vector3 = world.player.global_position
	var fw := Vector3(-sin(world.player.yaw), 0, -cos(world.player.yaw))
	var cp: Vector3 = ppos + fw * 7.0 + Vector3(-12, 0, 0)
	car.global_transform = Transform3D(Basis(Vector3.UP, world.player.yaw + 0.9), Vector3(cp.x, world.ground_height(cp) + 1.0, cp.z))
	world.player.global_position = car.global_position + car.global_basis.x * 2.4
	world.player.global_position.y = world.ground_height(world.player.global_position) + 0.2
	world.player.yaw = atan2(-(car.global_position - world.player.global_position).x, -(car.global_position - world.player.global_position).z) + 0.5
	await wait(1.5)
	await shot("car_near")
	world.player.enter_vehicle(car)
	Game.settings.controls = "touch"
	world.player.touch_move = Vector2(0.3, 1)
	world.player.yaw = car.rotation.y + PI
	await wait(2.5)
	await shot("driving")
	world.player.touch_move = Vector2.ZERO
	Game.settings.controls = "kbm"
	world.hud.toggle_bag()
	world.hud.toggle_map()
	await wait(0.4)
	await shot("map")
	world.zone.start()
	world.zone.speed = 40.0
	await wait(2.5)
	world.zone.speed = 1.0
	await shot("map_zone")
	world.hud.toggle_map()
	# Put a small circle 20 m in front of the player and look at its wall.
	var z = world.zone
	var pp: Vector3 = world.player.global_position
	var fwd := Vector2(-sin(world.player.yaw), -cos(world.player.yaw))
	z.state = "done"
	z.center = Vector2(pp.x, pp.z) + fwd * 70.0
	z.radius = 50.0
	z._update_wall()
	world.player.pitch = 0.05
	await wait(1.5)
	await shot("zone_wall")
	print("TEST DONE")
	get_tree().quit()
