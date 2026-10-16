extends Node3D
## Strips of one clip at evenly spaced times (for picking parts of clips by eye),
## plus peek / lean checks.
## Run: godot --path godot res://tests/clip_shots.tscn -- --out=/dir --clip=car_enter

var out := "user://"
var clip := "car_enter"
var char_name := "soldier"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--clip="): clip = a.substr(7)
		if a.begins_with("--char="): char_name = a.substr(7)
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
	var cam := Camera3D.new()
	cam.fov = 45
	add_child(cam)
	cam.current = true
	var n := 8
	var models := []
	for i in n:
		var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), char_name)
		add_child(m)
		m.position = Vector3(i * 1.6 - (n - 1) * 0.8, 0, 0)
		m.rotation.y = PI * 0.5      # side view
		models.append(m)
	var a: Animation = models[0].ap.get_animation("mx/" + clip)
	cam.look_at_from_position(Vector3(0, 1.4, 13.0), Vector3(0, 0.9, 0))
	for f in 3:
		for i in n:
			var hm: HumanModel = models[i]
			hm.ap.play("mx/" + clip, 0.0)
			hm.ap.seek(a.length * i / float(n - 1), true)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("clip_%s.png" % clip))
	print("shot clip ", clip, " length ", a.length)
	# Peek: standing still, left / none / right, armed; crouched right; then from behind.
	for m in models: m.queue_free()
	await get_tree().process_frame
	var peeks := [[-1.0, "stand"], [0.0, "stand"], [1.0, "stand"], [1.0, "crouch"], [-1.0, "crouch"]]
	var pm2 := []
	for i in peeks.size():
		var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), char_name)
		add_child(m)
		m.position = Vector3(i * 1.8 - 3.6, 0, 0)
		m.rotation.y = 0.0     # back to the camera, like the player sees
		m.set_weapon("m416")
		pm2.append(m)
	cam.look_at_from_position(Vector3(0, 1.6, 7.5), Vector3(0, 1.0, 0))
	for f in 40:
		for i in peeks.size():
			pm2[i].peek = minf(1.0, f / 10.0) * peeks[i][0]
			pm2[i].set_pose(peeks[i][1], 0.0, true, 1.0 / 30.0, f / 30.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("peek.png"))
	print("shot peek")
	# Running round a left bend / setting off.
	for m in pm2: m.queue_free()
	await get_tree().process_frame
	var r := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), char_name)
	add_child(r)
	r.set_weapon("m416")
	var s2 := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), char_name)
	add_child(s2)
	s2.set_weapon("m416")
	s2.position = Vector3(2.0, 0, 0)
	cam.look_at_from_position(Vector3(1.0, 1.4, 6.5), Vector3(1.0, 1.0, 0))
	for f in 24:
		r.rotation.y = f * 0.06          # turning left at 1.8 rad/s
		r.move_local = Vector2(0, 5.5)
		r.set_pose("stand", 5.5, true, 1.0 / 30.0, f / 30.0)
		var sp := minf(f * 0.6, 5.5) if f > 16 else 0.0
		s2.rotation.y = PI * 0.5
		s2.move_local = Vector2(0, sp)
		s2.set_pose("stand", sp, true, 1.0 / 30.0, f / 30.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("lean.png"))
	print("shot lean")
	get_tree().quit()
