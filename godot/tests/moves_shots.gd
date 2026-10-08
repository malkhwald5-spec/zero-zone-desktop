extends Node
## The new Mixamo moves on both characters (top row the soldier, bottom row
## Lola): lying still, crawling on the belly, crawling when knocked down,
## treading water. Two frames a little apart so the movement shows.
## Run with --out=/dir.

var out := "user://"
var set2 := false    # --set=2: pistol walk and idle, swimming, climbing, hard landing
var set3 := false    # --set=3: kneeling to revive, getting down to prone, turning on the spot (left, right)
var base_yaw := {}
var models := []
var poses := []

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a == "--set=2": set2 = true
		if a == "--set=3": set3 = true
	_run.call_deferred()

func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.75)
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.75)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.5, 0.32)
	ground.material_override = gm
	add_child(ground)
	var water := MeshInstance3D.new()
	var wp := PlaneMesh.new()
	wp.size = Vector2(3.2, 7.0)
	water.mesh = wp
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.45, 0.6, 0.7)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = wm
	water.position = Vector3(4.5, 1.0, 1.2)
	add_child(water)
	var names := ["prone_idle", "prone_crawl", "knocked_crawl", "swim"]
	if set2: names = ["pistol_walk", "swim_fwd", "climb", "hard_land"]
	if set3: names = ["revive", "to_prone", "turn_left", "turn_right"]
	for row in 2:
		for col in 4:
			var m := HumanModel.new(Color("4a5d6b"), Color("c84f3a"), Color("33373d"), ["soldier", "lola"][row])
			add_child(m)
			m.position = Vector3(col * 3.0 - 4.5, 0, row * 2.6 - 0.2)
			m.rotation.y = -PI / 2         # side on to the camera
			m.set_weapon("p92" if names[col] == "pistol_walk" else "m416")
			models.append(m)
			poses.append(names[col])
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4.2, 8.5)
	cam.fov = 60
	add_child(cam)
	cam.look_at(Vector3(0, 0.3, 1.0))
	cam.current = true
	var frames := 5 if set3 else 2
	for k in frames:
		for i in 25: await get_tree().process_frame
		if set2 and k == 0:
			for i in models.size():
				if poses[i] == "climb": models[i].play_action("climb", 6.0)
				if poses[i] == "hard_land": models[i].play_action("hard_land", 6.0)
			await wait(1.4)
		if set3 and k == 0:
			for i in models.size():
				base_yaw[i] = models[i].rotation.y
				if poses[i] == "to_prone": models[i].play_action("kneel_to_prone", 4.0)
				if poses[i] == "turn_left": models[i].start_turn(1)
				if poses[i] == "turn_right": models[i].start_turn(-1)
			await wait(0.1)
		await shot(("moves3_%d" if set3 else ("moves2_%d" if set2 else "moves_%d")) % k)
		await wait(0.5)
	print("MOVES ok")
	get_tree().quit()

func _process(delta: float) -> void:
	for i in models.size():
		var m: HumanModel = models[i]
		match poses[i]:
			"prone_idle":
				m.set_pose("prone", 0.0, true, delta, 0.0)
			"prone_crawl":
				m.move_local = Vector2(0, 0.85)
				m.set_pose("prone", 0.85, true, delta, 0.0)
			"knocked_crawl":
				m.downed = true
				m.move_local = Vector2(0, 0.6)
				m.set_pose("prone", 0.6, false, delta, 0.0)
			"swim":
				m.swimming = true
				m.set_pose("stand", 0.0, true, delta, 0.0)
			"pistol_walk":
				m.move_local = Vector2(0, 1.5)
				m.set_pose("stand", 1.5, true, delta, 0.0)
			"swim_fwd":
				m.swimming = true
				m.move_local = Vector2(0, 1.6)
				m.set_pose("stand", 1.6, true, delta, 0.0)
			"climb", "hard_land", "to_prone":
				m.set_pose("stand", 0.0, true, delta, 0.0)
			"revive":
				m.reviving = true
				m.set_pose("crouch", 0.0, true, delta, 0.0)
			"turn_left", "turn_right":
				m.set_pose("stand", 0.0, true, delta, 0.0)
				if base_yaw.has(i): m.rotation.y = base_yaw[i] + m.turn_yaw
