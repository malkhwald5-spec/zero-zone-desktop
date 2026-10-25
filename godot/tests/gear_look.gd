extends Node3D
## Close-ups of the gear levels as worn: helmet, vest and backpack at levels
## 1, 2 and 3, from the front-quarter and the back-quarter, holding a rifle.
## Run: godot --path godot res://tests/gear_look.tscn -- --out=/dir --char=lola

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
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 10)
	fl.mesh = pm
	add_child(fl)
	_run.call_deferred()

func _run() -> void:
	var cam := Camera3D.new()
	cam.fov = 26
	add_child(cam)
	cam.current = true
	for view in ["front", "back"]:
		var models := []
		for i in 3:
			var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), who)
			add_child(m)
			m.position = Vector3(i * 1.25 - 1.25, 0, 0)
			m.rotation.y = PI - 0.5 if view == "front" else 0.5
			m.set_weapon("m416")
			m.set_gear(i + 1, i + 1, i + 1)
			models.append(m)
		cam.look_at_from_position(Vector3(0, 1.45, 6.2), Vector3(0, 1.25, 0))
		for f in 30:
			for m in models: m.set_pose("stand", 0.0, true, 1.0 / 30.0, 1.0 + f / 30.0)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("gear_%s_%s.png" % [who, view]))
		print("shot gear ", view)
		for m in models: m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
