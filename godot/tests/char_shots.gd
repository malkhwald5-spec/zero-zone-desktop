extends Node3D
## Every character in a row wearing gear (levels 1, 2, 3 in turn), seen from
## the front, back and side; then holding a rifle and walking.
## Run with --out=/dir.

var out := "user://"
const WHO := ["soldier", "lola", "survivor", "bundeswehr", "remy"]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	_run.call_deferred()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.72, 0.76, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	for lvl in [1, 2, 3]:
		var models := []
		for i in WHO.size():
			var m := HumanModel.new(Color("4a5d6b"), Color("c84f3a"), Color("33373d"), WHO[i])
			add_child(m)
			m.position = Vector3(i * 1.1 - 2.2, 0, 0)
			m.set_gear(lvl, lvl, lvl)
			models.append(m)
		for view in [["front", 0.0], ["back", PI], ["side", -PI / 2]]:
			for m in models: m.rotation.y = view[1]
			cam.position = Vector3(0, 1.4, 6.2)
			cam.look_at(Vector3(0, 0.95, 0))
			for f in 8:
				for m in models: m.set_pose("stand", 0.0, false, 0.03, f * 0.03)
				await get_tree().process_frame
			await shot("chars_l%d_%s" % [lvl, view[0]])
		# Close-up of the heads and chests.
		if lvl == 3:
			for m in models: m.rotation.y = 0.5
			cam.position = Vector3(0, 1.55, 3.2)
			cam.look_at(Vector3(0, 1.35, 0))
			for f in 4: await get_tree().process_frame
			await shot("chars_l3_close")
			# Holding a rifle, walking.
			for m in models:
				m.set_weapon("m416")
				m.rotation.y = -0.6
			cam.position = Vector3(0, 1.4, 6.2)
			cam.look_at(Vector3(0, 0.95, 0))
			for f in 25:
				for m in models:
					m.move_local = Vector2(0, 1.5)
					m.set_pose("stand", 1.5, true, 0.03, f * 0.03)
				await get_tree().process_frame
			await shot("chars_rifle_walk")
		for m in models: m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
