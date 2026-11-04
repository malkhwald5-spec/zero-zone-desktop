extends Node
## The rifle while running and sprinting, from several sides (a camera that
## runs along with the player), a few steps apart; and the game's own camera.
## Run: godot --path godot res://tests/sprint_shots.tscn -- --out=/dir

var out := "user://"
var world: Node
var p: Player
var cam: Camera3D
var rel := Vector3.ZERO          # camera: forward, right, up of the player
var look_h := 1.1

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
	Game.settings.weather = "clear"
	Game.settings.mode = "solo"
	Game.settings.lite = false
	Game.spawn_island = false
	_run.call_deferred()

func _process(_d: float) -> void:
	if cam == null or not cam.current or p == null: return
	var b: Basis = p.model.global_basis
	var f: Vector3 = -b.z
	f.y = 0.0
	f = f.normalized()
	var r := f.cross(Vector3.UP).normalized()
	var base: Vector3 = p.get_global_transform_interpolated().origin
	cam.global_position = base + f * rel.x + r * rel.y + Vector3(0, rel.z, 0)
	cam.look_at(base + Vector3(0, look_h, 0))

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	p = world.player
	p.health = 1e9
	p.jump_from_plane()
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(9000, -80, 9000)
	var t: Dictionary = world.island.towns[0]
	var at := Vector3(t.pos.x + float(t.r) + 40.0, 0, t.pos.y)
	at.y = world.ground_height(at)
	p.global_position = at + Vector3(0, 0.5, 0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	p._land()
	p.yaw = PI * 0.5
	p.pitch = -0.12
	p.give_weapon("m416", 30)
	p.switch_slot(0)
	p.equip("pack", 2, 0.0)
	await wait(2.0)
	cam = Camera3D.new()
	world.add_child(cam)
	cam.fov = 45.0
	for mode in ["run", "sprint"]:
		p.touch_move = Vector2(0, 1)
		p.sprinting = mode == "sprint"
		await wait(1.5)
		cam.current = false
		world.hud.visible = true
		await shot("%s_0_game" % mode)
		cam.current = true
		world.hud.visible = false
		var views := {"side_l": Vector3(-1.2, -3.2, 1.3), "back_l": Vector3(-3.0, -1.6, 1.6), "front34": Vector3(2.6, 2.2, 1.4), "side_r": Vector3(-0.5, 3.2, 1.3)}
		for v in views:
			rel = views[v]
			for k in 3:
				await wait(0.13)
				await shot("%s_%s_%d" % [mode, v, k])
	p.touch_move = Vector2.ZERO
	p.sprinting = false
	tree.quit()
