extends Node3D
## Renders the realistic soldier in every pose (for checking poses by eye).
## Run: godot --path godot res://tests/pose_test.tscn -- --out=/some/dir

var out := "user://"
var models := []
# [pose, speed, armed, weapon, extra settings]
const POSES := [["stand", 1.2, false, "", {}], ["stand", 0.0, true, "mp44", {"aiming": true}], ["stand", 0.0, true, "akm", {"aiming": true}],
	["stand", 0.0, true, "kar98", {"aiming": true, "aim_pitch": 0.5}], ["stand", 6.5, true, "m416", {"sprinting": true}],
	["stand", 0.0, true, "ump", {"reload_p": 0.25}], ["crouch", 1.2, true, "s1897", {"aiming": true}],
	["prone", 0.0, true, "m249", {}], ["stand", 0.0, true, "p92", {"aiming": true}], ["fall", 0.0, false, "", {}], ["dead", 0.0, false, "", {}]]

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
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 10)
	floor_mi.mesh = pm
	add_child(floor_mi)
	for i in POSES.size():
		var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"))
		add_child(m)
		m.position = Vector3(i * 2.0 - 10.0, 0, 0)
		m.rotation.y = PI - 0.6      # three-quarter view from the front
		m.set_weapon(POSES[i][3])
		for k in POSES[i][4]: m.set(k, POSES[i][4][k])
		m.set_gear(2, 1 + i % 3, 1 + i % 3)
		models.append(m)
	var cam := Camera3D.new()
	cam.fov = 45
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.4, 15.0), Vector3(0, 1.0, 0))
	cam.current = true
	for f in 75:
		for i in POSES.size():
			if POSES[i][4].has("reload_p"): models[i].reload_p = POSES[i][4].reload_p
			models[i].set_pose(POSES[i][0], POSES[i][1], POSES[i][2], 1.0 / 30.0, f / 30.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("poses.png"))
	for i in [1, 2, 3, 4, 5, 8]:
		var mp: Vector3 = models[i].global_position
		cam.fov = 30
		cam.look_at_from_position(mp + Vector3(-0.6, 1.6, 3.2), mp + Vector3(0, 1.1, 0))
		if OS.get_cmdline_user_args().has("--side"):
			cam.look_at_from_position(mp + models[i].global_basis * Vector3(2.8, 0.3, -0.6) + Vector3(0, 1.3, 0), mp + Vector3(0, 1.2, 0))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("close_%d.png" % i))
	print("POSES DONE")
	get_tree().quit()
