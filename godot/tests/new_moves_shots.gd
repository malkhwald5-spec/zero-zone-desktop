extends Node3D
## The newer moves side by side on one character: drawing a gun, reloading
## on one knee, pistol up in both hands, opening a door, the crouched throw,
## jumping over a wall, dying while lying down. --who=lola etc. Run with --out=/dir.

var out := "user://"
var who := "survivor"
# [label, weapon, pose, aiming, reload_p, action [name, secs, from, to] or [], frames to run]
const CASES := [["draw", "m416", "stand", false, -1.0, ["draw", 0.6, 0.8, 3.0], 9],
	["crouch reload", "m416", "crouch", false, 0.45, [], 6],
	["pistol aim", "p92", "stand", true, -1.0, [], 6],
	["door", "", "stand", false, -1.0, ["door", 0.5, 0.7, 2.4], 9],
	["crouch throw", "", "crouch", false, -1.0, ["toss2", 1.0, 0.5, 2.3], 14],
	["vault", "m416", "stand", false, -1.0, ["vault", 0.6, 1.75, 3.0], 12],
	["prone death", "m416", "prone", false, -1.0, [], 6]]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--who="): who = a.substr(6)
	_run.call_deferred()

func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.75, 0.78, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 10)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var models := []
	for i in CASES.size():
		var c: Array = CASES[i]
		var m := HumanModel.new(Color("4a5d6b"), Color("c84f3a"), Color("33373d"), who)
		add_child(m)
		m.position = Vector3(i * 1.5 - 4.5, 0, 0)
		m.rotation.y = -PI / 2 + 0.5
		m.set_weapon(c[1])
		m.aiming = c[3]
		m.reload_p = c[4]
		models.append(m)
		var lab := Label3D.new()
		lab.text = c[0]
		lab.font_size = 36
		lab.position = m.position + Vector3(0, 2.15, 0)
		add_child(lab)
	for f in 8:
		for i in CASES.size(): models[i].set_pose(CASES[i][2], 0.0, CASES[i][1] != "", 0.03, f * 0.03)
		await get_tree().process_frame
	for i in CASES.size():
		var act: Array = CASES[i][5]
		if not act.is_empty(): models[i].play_action(act[0], act[1], act[2], act[3])
		if CASES[i][0] == "prone death": models[i].set_pose("dead", 0.0, false, 0.03, 0.3)
	for f in 14:
		for i in CASES.size():
			if f >= CASES[i][6]: continue
			if CASES[i][0] == "prone death": models[i]._process(0.08)
			else: models[i].set_pose(CASES[i][2], 0.0, CASES[i][1] != "", 0.03, 0.3 + f * 0.03)
		await get_tree().process_frame
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 1.6, 8.5)
	cam.look_at(Vector3(0, 0.9, 0))
	for f in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("new_moves_%s.png" % who))
	print("shot new_moves")
	get_tree().quit()
