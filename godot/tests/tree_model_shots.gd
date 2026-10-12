extends Node3D
## Close-up of the imported tree models in a row on grass, in sunlight.
## Run: godot --path godot res://tests/tree_model_shots.tscn -- --out=/dir

var out := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("9ec3e6")
	env.environment.ambient_light_color = Color(0.7, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("5d7a3a")
	ground.material_override = gm
	add_child(ground)
	var names := ["broad_a", "broad_b", "broad_c", "fir", "palm_a", "palm_b", "sakura"]
	for i in names.size():
		var mi := MeshInstance3D.new()
		mi.mesh = TreeModels.imported(names[i])
		mi.position = Vector3((i - 3.0) * 8.0, 0, 0)
		add_child(mi)
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 6, 34), Vector3(0, 5, 0))
	cam.current = true
	for f in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("trees.png"))
	cam.look_at_from_position(Vector3(14, 3, 12), Vector3(14, 5, 0))
	for f in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("trees_close.png"))
	print("shot trees")
	get_tree().quit()
