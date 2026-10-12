extends Node3D
## The fitted weapon models: side view of each in the weapon frame with the
## grip (red), left-hand (green) and muzzle (blue) points; then the soldier
## holding each one, aiming. Run with --out=/dir.

var out := "user://"
const K := ["m416", "scar", "ump", "s1897", "vector", "uzi", "beryl", "sks", "mini14", "m249", "crossbow", "pan"]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	_run.call_deferred()

func _dot(parent: Node3D, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.036
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	sm.material = m
	mi.mesh = sm
	mi.position = pos
	parent.add_child(mi)

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
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.9, 0)
	add_child(sun)
	var grid := Node3D.new()
	add_child(grid)
	for i in K.size():
		var w := WeaponModels.build(K[i])
		w.position = Vector3((i % 3) * 1.25 - 1.25, 1.2 - (i / 3) * 0.55, 0)
		w.rotation.y = -PI * 0.5      # muzzle to the right
		grid.add_child(w)
		_dot(w, Vector3.ZERO, Color.RED)
		_dot(w, w.get_meta("fore"), Color.GREEN)
		_dot(w, Vector3(0, 0, w.get_meta("muzzle")), Color.BLUE)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.5
	cam.position = Vector3(0, 0.4, 5)
	add_child(cam)
	cam.current = true
	for f in 4: await get_tree().process_frame
	await shot("fit_side")
	grid.queue_free()
	# Held, aiming: four at a time, close up, side-on and a little from the front.
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 40
	for page in 3:
		var models := []
		for j in 4:
			var i := page * 4 + j
			var m := HumanModel.new(Color("4a5d6b"), Color("c84f3a"), Color("33373d"), "soldier")
			add_child(m)
			m.position = Vector3(j * 1.5 - 2.25, 0, 0)
			m.rotation.y = -PI * 0.5 - 0.35
			m.set_weapon(K[i])
			m.aiming = K[i] != "pan"
			models.append(m)
		cam.position = Vector3(0, 1.75, 4.6)
		cam.look_at(Vector3(0, 1.3, 0))
		for f in 30:
			for m in models: m.set_pose("stand", 0.0, true, 0.03, f * 0.03)
			await get_tree().process_frame
		await shot("fit_held_%d" % page)
		for m in models: m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
