extends Node3D
## The gun slung on the back, the strap and the pistol holster: from behind
## and the side, bare, with a vest and with a big backpack; and the swing
## of the slung gun when setting off and stopping.
## Run: godot --path godot res://tests/back_shots.tscn -- --out=/dir --char=lola

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
	pm.size = Vector2(40, 10)
	fl.mesh = pm
	add_child(fl)
	_run.call_deferred()

func _run() -> void:
	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.current = true
	# [gear (vest, helmet, pack), turned (0 back to camera), moving speed]
	var rows := [[[0, 0, 0], 0.35, 0.0], [[2, 2, 0], 0.35, 0.0], [[2, 2, 3], 0.35, 0.0], [[2, 2, 3], PI * 0.5, 0.0],
		[[0, 0, 2], PI + 0.4, 0.0], [[2, 2, 2], 0.35, 4.5]]
	var models := []
	for i in rows.size():
		var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), who)
		add_child(m)
		m.position = Vector3(i * 1.3 - (rows.size() - 1) * 0.65, 0, 0)
		m.rotation.y = rows[i][1]
		m.set_weapon("m416")
		m.set_back_weapon("akm")
		m.set_side_weapon("p92")
		var g: Array = rows[i][0]
		m.set_gear(g[0], g[1], g[2])
		models.append(m)
	cam.look_at_from_position(Vector3(0, 1.35, 10.0), Vector3(0, 1.0, 0))
	for f in 60:
		for i in rows.size():
			var m: HumanModel = models[i]
			var sp: float = rows[i][2]
			m.move_local = Vector2(0, sp)
			if sp > 0.0: m.position.z -= 0.0
			m.set_pose("stand", sp, true, 1.0 / 30.0, f / 30.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("back_%s.png" % who))
	print("shot back ", who)
	get_tree().quit()
