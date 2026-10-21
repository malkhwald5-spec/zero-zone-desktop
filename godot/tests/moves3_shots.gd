extends Node3D
## The new moves side by side: punch, bandage, slide, bolt-action reload,
## shotgun shells, working the bolt, looking the gun over (both sides),
## salute and a dance. Run: godot --path godot res://tests/moves3_shots.tscn -- --out=/dir

var out := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.75)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.7
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 10)
	fl.mesh = pm
	add_child(fl)
	# [label, pose, speed, weapon, settings, action [name, len, from, to] or []]
	var rows := [["punch", "stand", 0.0, "", {}, ["punch", 0.5, 1.0, 1.55]], ["bandage", "stand", 0.0, "", {"bandaging": true}, []],
		["slide", "crouch", 4.0, "m416", {"sliding": 1.0}, []], ["kar98 reload", "stand", 0.0, "kar98", {"reload_p": 0.5}, []],
		["shotgun shells", "stand", 0.0, "s1897", {"reload_p": 0.35}, []], ["bolt", "stand", 0.0, "kar98", {"bolt_p": 0.45, "aiming": false}, []],
		["inspect a", "stand", 0.0, "m416", {"inspect_t": 0.25}, []], ["inspect b", "stand", 0.0, "m416", {"inspect_t": 0.75}, []],
		["salute", "stand", 0.0, "", {}, ["salute", 2.8, 1.2, 1.25]], ["dance", "stand", 0.0, "", {}, ["dance_hiphop", 4.7, 2.0, 2.05]]]
	var models := []
	for i in rows.size():
		var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), "albu", true)
		add_child(m)
		m.position = Vector3(i * 1.5 - (rows.size() - 1) * 0.75, 0, 0)
		m.rotation.y = PI - 0.7
		m.set_weapon(rows[i][3])
		m.set_gear(0, 0, 0)
		models.append(m)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.6, 15.5), Vector3(0, 0.9, 0))
	cam.current = true
	for f in 40:
		for i in rows.size():
			var m: HumanModel = models[i]
			for k in rows[i][4]: m.set(k, rows[i][4][k])
			var act: Array = rows[i][5]
			if not act.is_empty() and f == 20: m.play_action(act[0], 1.0, act[2], act[3])
			m.set_pose(rows[i][1], rows[i][2], rows[i][3] != "", 1.0 / 30.0, f / 30.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("moves3.png"))
	print("shot moves3")
	get_tree().quit()
