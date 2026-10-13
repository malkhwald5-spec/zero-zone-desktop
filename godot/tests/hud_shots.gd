extends Node
## The in-match screen with the HUD, as a phone player sees it (touch buttons)
## and as a PC player sees it. Run: godot --path godot res://tests/hud_shots.tscn -- --out=/dir

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
	Game.settings.controls = "touch"
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	p.health = 1e9
	for b in world.bots: b.set_physics_process(false)
	p.jump_from_plane()
	world.plane_active = false
	world.plane.visible = false
	world.zone.start()
	var c: Vector2 = world.island.towns[6].pos + Vector2(60, 40)
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	p._land()
	p.give_weapon("m416", 30)
	p.give_weapon("akm", 30)
	p.ammo["556"] = 120
	p.ammo["762"] = 60
	p.heals["bandage"] = 5
	p.heals["firstaid"] = 2
	p.throwables["frag"] = 2
	p.equip("vest", 2, 200.0)
	p.equip("helmet", 2, 150.0)
	p.equip("pack", 2, 0.0)
	p.health = 76.0
	p.yaw = 0.6
	p.pitch = -0.08
	await wait(2.0)
	await shot("hud_touch")
	Game.settings.controls = "kbm"
	world.hud.touch.visible = false
	await wait(0.5)
	await shot("hud_pc")
	print("HUD SHOTS DONE")
	tree.quit()
