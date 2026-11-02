extends Node
## The poses next to the user's PUBG screenshots: aiming, running, crouched,
## prone (still, aiming), the gear on the back; from the game camera and from
## the side. Full gear (level 3) and two guns.
## Run: godot --path godot res://tests/pubg_poses.tscn -- --out=/dir --map=dunes [--only=aim,run]

var out := "user://"
var only: PackedStringArray = []

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--skin="): Game.profile.gun_skin = a.substr(7)
		if a.begins_with("--only="): only = a.substr(7).split(",")
	Game.settings.controls = "touch"
	Game.settings.weather = "clear"
	Game.settings.mode = "solo"
	Game.settings.map = "dunes"
	Game.settings.lite = false
	Game.spawn_island = false
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
	p.jump_from_plane()
	for b in world.bots: b.set_physics_process(false)
	# Open flat ground away from the houses.
	var t: Dictionary = world.island.towns[0]
	var at := Vector3(t.pos.x + float(t.r) + 40.0, 0, t.pos.y)
	at.y = world.ground_height(at)
	p.global_position = at + Vector3(0, 0.5, 0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	p._land()
	p.yaw = 0.0
	p.pitch = -0.12
	p.give_weapon("m416", 30)
	p.switch_slot(0)
	p.give_weapon("akm", 30)
	p.switch_slot(0)
	p.give_weapon("m249", 100)
	p.switch_slot(0)
	p.equip("vest", 3, 100.0)
	p.equip("helmet", 3, 100.0)
	p.equip("pack", 3, 0.0)
	await wait(2.0)
	p.global_position = Vector3(at.x, world.ground_height(at) + 0.2, at.z)
	p.velocity = Vector3.ZERO
	await wait(1.0)
	world.hud.visible = false
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 45.0
	var poses := [["stand", "", false, Vector2.ZERO, false], ["aim", "", true, Vector2.ZERO, false], ["run", "", false, Vector2(0, 1), false],
		["sprint", "", false, Vector2(0, 1), true], ["crouch", "crouch", false, Vector2.ZERO, false], ["crouch_aim", "crouch", true, Vector2.ZERO, false],
		["prone", "prone", false, Vector2.ZERO, false], ["prone_aim", "prone", true, Vector2.ZERO, false]]
	for ps in poses:
		var nm: String = ps[0]
		if not only.is_empty() and not nm in only: continue
		p.global_position = Vector3(at.x, world.ground_height(at) + 0.2, at.z)
		p.velocity = Vector3.ZERO
		p.yaw = 0.0
		p.stance = ps[1] if ps[1] != "" else "stand"
		p.aiming = ps[2]
		p.touch_move = ps[3]
		p.sprinting = ps[4]
		await wait(1.6)
		var base: Vector3 = p.global_position
		var fwd: Vector3 = -p.global_basis.z
		var right: Vector3 = p.global_basis.x
		cam.current = false
		await shot("pp_%s_game" % nm)
		var h := 1.2 if p.stance == "stand" else (0.9 if p.stance == "crouch" else 0.6)
		var look := base + Vector3(0, h * 0.8, 0)
		cam.global_position = base - right * 3.2 + fwd * 1.2 + Vector3(0, h + 0.2, 0)
		cam.look_at(look)
		cam.current = true
		await wait(0.1)
		await shot("pp_%s_side" % nm)
		cam.global_position = base - fwd * 2.8 + right * 1.6 + Vector3(0, h + 0.4, 0)
		cam.look_at(look)
		await wait(0.1)
		await shot("pp_%s_back" % nm)
		cam.current = false
	p.touch_move = Vector2.ZERO
	tree.quit()
