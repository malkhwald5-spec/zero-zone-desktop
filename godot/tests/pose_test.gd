extends Node3D
## Renders the realistic soldier in every pose (for checking poses by eye).
## Run: godot --path godot res://tests/pose_test.tscn -- --out=/some/dir

var out := "user://"
var models := []
const POSES := [["stand", 1.2, false], ["stand", 0.0, true], ["stand", 1.5, true], ["stand", 5.5, true], ["crouch", 0.0, true],
	["prone", 0.0, true], ["fall", 0.0, false], ["chute", 0.0, false], ["dead", 0.0, false]]

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
		m.position = Vector3(i * 2.2 - 8.8, 0, 0)
		m.rotation.y = PI - 0.6      # three-quarter view from the front
		m.set_weapon("ar")
		m.set_gear(2, 2, 1)
		models.append(m)
	var cam := Camera3D.new()
	cam.fov = 45
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.6, 13.5), Vector3(0, 1.0, 0))
	cam.current = true
	for f in 30:
		for i in POSES.size():
			models[i].set_pose(POSES[i][0], POSES[i][1], POSES[i][2], 1.0 / 30.0, f / 30.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("poses.png"))
	# Close-up of the rifle hold and the crouch.
	cam.look_at_from_position(models[0].global_position + Vector3(1.5, 1.5, 3.2), models[0].global_position + Vector3(1.1, 1.0, 0))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("poses_close.png"))
	print("POSES DONE")
	get_tree().quit()
