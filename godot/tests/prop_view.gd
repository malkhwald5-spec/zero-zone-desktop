extends Node3D
## A prop model alone from four sides (+Z front, right, back, left).
## Run: godot --path godot res://tests/prop_view.tscn -- --out=/dir --model=res://assets/models/gear/x.glb

var out := "user://"
var model := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--model="): model = a.substr(8)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.75)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.8
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var sc: Node3D = load(model).instantiate()
	var acc := [null]
	WeaponModels._mesh_aabb(sc, Transform3D.IDENTITY, acc)
	var a: AABB = acc[0]
	var r := maxf(a.size.x, maxf(a.size.y, a.size.z))
	for i in 4:
		var n: Node3D = sc if i == 0 else load(model).instantiate()
		var piv := Node3D.new()
		add_child(piv)
		piv.add_child(n)
		n.position = -a.get_center()
		piv.position = Vector3((i - 1.5) * r * 1.3, 0, 0)
		piv.rotation.y = -i * PI / 2.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, r * 0.3, r * 3.6), Vector3.ZERO)
	cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("prop.png"))
	print("shot prop")
	get_tree().quit()
