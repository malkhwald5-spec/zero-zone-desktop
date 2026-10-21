extends Node3D
## Close-ups of the armed character in the everyday states the player sees
## most: standing (each idle), walking, running, sprinting, aiming, firing and
## picking something up. Two views: three-quarter front and over the shoulder.
## Run: godot --path godot res://tests/pose_check.tscn -- --out=/dir --char=lola

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
	# [label, speed, sprint, aim, recoil, idle offset, action]
	var rows := [["idle", 0.0, false, false, 0.0, 0.0, ""], ["idle 2", 0.0, false, false, 0.0, 10.0, ""], ["idle 3", 0.0, false, false, 0.0, 20.0, ""],
		["walk", 1.8, false, false, 0.0, 0.0, ""], ["run", 4.5, false, false, 0.0, 0.0, ""], ["sprint", 6.8, true, false, 0.0, 0.0, ""],
		["aim", 0.0, false, true, 0.0, 0.0, ""], ["fire", 0.0, false, true, 1.0, 0.0, ""], ["pickup", 0.0, false, false, 0.0, 0.0, "pickup"]]
	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.current = true
	var all_rows := rows
	for view in ["front", "back"]:
		for grp in 3:
			rows = all_rows.slice(grp * 3, grp * 3 + 3)
			var models := []
			for i in rows.size():
				var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), who)
				add_child(m)
				m.position = Vector3(i * 1.3 - 1.3, 0, 0)
				m.rotation.y = PI - 0.6 if view == "front" else 0.35
				m.set_weapon("m416")
				m.set_gear(0, 0, 0)
				m._idle_seed = rows[i][5]
				models.append(m)
			cam.look_at_from_position(Vector3(0, 1.3, 9.0), Vector3(0, 1.0, 0))
			for f in 60:
				for i in rows.size():
					var m: HumanModel = models[i]
					if f == 50 and rows[i][6] != "": m.pick_up()
					m.move_local = Vector2(0, rows[i][1])
					m.sprinting = rows[i][2]
					m.aiming = rows[i][3]
					if rows[i][4] > 0.0: m.recoil = rows[i][4]
					m.set_pose("stand", rows[i][1], true, 1.0 / 30.0, 1.0 + f / 30.0)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("pose_%s_%s_%d.png" % [who, view, grp]))
			print("shot pose ", who, " ", view)
			for m in models: m.queue_free()
			await get_tree().process_frame
	get_tree().quit()
