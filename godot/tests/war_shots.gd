extends Node
## Team war pictures: a fort from the air, its courtyard (heart, shop) with
## the HUD while getting ready, the gate's wall of light, a capture point,
## the shop screen, a machine-gun tower and sandbags, the armoured car, and
## the map with the forts and places.
## Run: godot --path godot res://tests/war_shots.tscn -- --out=/dir

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
	Game.settings.weather = "clear"
	Game.settings.quality = "high"
	Game.settings.mode = "war"
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
	var w: War = world.war
	var p: Player = world.player
	p.health = 1e9
	var f: Dictionary = w.forts[p.team]
	var g: Vector2 = f.gate
	var c: Vector3 = f.center
	w.prep_left = 9999.0
	w.build(f, "tower")
	w.build(f, "tower")
	for k in 4: w.build(f, "bags")
	# In the courtyard, looking at the heart, the HUD while getting ready.
	var spot: Vector3 = c + Vector3(-g.x, 0, -g.y) * 14.0 + Vector3(g.y, 0, -g.x) * 5.0
	p.global_position = spot + Vector3(0, 0.5, 0)
	var to := c - spot
	p.yaw = atan2(-to.x, -to.z) - 0.25
	p.pitch = -0.08
	p.reset_physics_interpolation()
	await wait(4.0)
	for b in world.bots: b.set_physics_process(false)
	await shot("war_1_courtyard_hud")
	world.hud.toggle_shop()
	await wait(0.6)
	await shot("war_2_shop")
	world.hud.shop.tab = "fort"
	world.hud.shop._fill()
	await wait(0.4)
	await shot("war_3_shop_fort")
	world.hud.toggle_shop()
	# Free camera for the rest.
	var cam := Camera3D.new()
	cam.far = 4000.0
	world.add_child(cam)
	cam.current = true
	world.hud.visible = false
	var side := Vector3(g.y, 0, -g.x)
	cam.global_position = c + Vector3(g.x, 0, g.y) * 95.0 + side * 55.0 + Vector3(0, 55.0, 0)
	cam.look_at(c, Vector3.UP)
	await wait(1.5)
	await shot("war_4_fort_air")
	var gate: Vector3 = c + Vector3(g.x, 0, g.y) * (War.H + 34.0) + side * 9.0
	gate.y = world.ground_height(gate) + 3.0
	cam.global_position = gate
	cam.look_at(c + Vector3(g.x, 0, g.y) * War.H + Vector3(0, 3, 0), Vector3.UP)
	await wait(1.0)
	await shot("war_5_gate_closed")
	var apc := w.spawn_apc(p.team)
	await wait(2.0)
	var ap: Vector3 = apc.global_position
	cam.global_position = ap + side * 7.0 + Vector3(g.x, 0, g.y) * 6.0 + Vector3(0, 2.6, 0)
	cam.look_at(ap + Vector3(0, 1.2, 0), Vector3.UP)
	await wait(0.8)
	await shot("war_6_apc")
	var pt: Dictionary = w.points[1]
	pt.owner = (p.team + 1) % 4
	w._paint_point(pt)
	var pp: Vector3 = pt.pos
	cam.global_position = pp + Vector3(30, world.ground_height(pp + Vector3(30, 0, 18)) - pp.y + 6.0, 18)
	cam.look_at(pp + Vector3(0, 6, 0), Vector3.UP)
	await wait(1.5)
	await shot("war_7_point")
	# The map.
	cam.current = false
	p.camera.current = true
	world.hud.visible = true
	world.hud.toggle_map()
	await wait(0.6)
	await shot("war_8_map")
	print("WAR SHOTS DONE")
	tree.quit()
