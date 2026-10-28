extends Node3D
## The vest skinned to the body against the old rigid one: the same bent
## poses (crouched aim, a deep crouch, prone, mid-roll, sprinting, reaching
## down) with level 3 gear; top row rigid, bottom row skinned.
## Run: godot --path godot res://tests/gear_bend.tscn -- --out=/dir --char=lola

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
	e.ambient_light_energy = 0.6
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 50, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	var poses := [["idle_crouch_aim", 0.3], ["kneel", 1.0], ["prone_idle", 0.5], ["c_dive_roll", 1.4], ["sprint_f", 0.2], ["pickup", 0.9]]
	var models := []
	for i in poses.size():
		var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), who)
		add_child(m)
		m.position = Vector3(i * 1.5 - (poses.size() - 1) * 0.75, 0, 0)
		m.rotation.y = PI * 1.2
		m.set_gear(3, 3, 0)
		models.append([m, poses[i]])
	cam.look_at_from_position(Vector3(0, 2.2, 7.2), Vector3(0, 0.7, 0))
	for skinned in [false, true]:
		for mp in models:
			var hm: HumanModel = mp[0]
			if hm.vest_skin:
				hm.vest_skin.visible = skinned
				hm.vest.layers = 0 if skinned else 1
		for f in 3:
			for mp in models:
				var hm: HumanModel = mp[0]
				var pz: Array = mp[1]
				if hm.ap.has_animation("mx/" + pz[0]):
					hm.ap.play("mx/" + pz[0], 0.0)
					hm.ap.seek(pz[1], true)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var nm := "gear_bend_%s_%s.png" % [who, "skinned" if skinned else "rigid"]
		get_viewport().get_texture().get_image().save_png(out.path_join(nm))
		print("shot ", nm)
	get_tree().quit()
