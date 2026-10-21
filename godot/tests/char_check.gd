extends Node3D
## How the player's character looks in each everyday pose (for comparing
## with the big mobile shooters): idle with a rifle, walk, run, sprint, aim,
## crouch-walk, idle unarmed, walk unarmed; from the side and from behind.
## Run: godot --path godot res://tests/char_check.tscn -- --out=/dir --char=lola

var out := "user://"
var who := "lola"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--char="): who = a.substr(7)
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
	pm.size = Vector2(60, 20)
	fl.mesh = pm
	add_child(fl)
	# [label, pose, speed, armed, sprint, aim]
	var rows := [["idle", "stand", 0.0, true, false, false], ["walk", "stand", 1.8, true, false, false], ["run", "stand", 4.5, true, false, false],
		["sprint", "stand", 6.8, true, true, false], ["aim", "stand", 0.0, true, false, true], ["crouch walk", "crouch", 1.5, true, false, false],
		["idle unarmed", "stand", 0.0, false, false, false], ["walk unarmed", "stand", 1.8, false, false, false]]
	var cam := Camera3D.new()
	cam.fov = 35
	add_child(cam)
	cam.current = true
	for view in ["side", "back"]:
		var models := []
		for i in rows.size():
			var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), who)
			add_child(m)
			m.position = Vector3(i * 1.6 - (rows.size() - 1) * 0.8, 0, 0)
			m.rotation.y = PI * 0.5 if view == "side" else PI + 0.5
			if rows[i][3]: m.set_weapon("m416")
			m.set_gear(0, 0, 0)
			models.append(m)
		cam.look_at_from_position(Vector3(0, 1.5, 15.0), Vector3(0, 0.95, 0))
		for f in 50:
			for i in rows.size():
				var m: HumanModel = models[i]
				m.move_local = Vector2(0, rows[i][2])
				m.sprinting = rows[i][4]
				m.aiming = rows[i][5]
				m.set_pose(rows[i][1], rows[i][2], rows[i][3], 1.0 / 30.0, f / 30.0)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("char_%s_%s.png" % [who, view]))
		print("shot char ", who, " ", view)
		for m in models: m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
