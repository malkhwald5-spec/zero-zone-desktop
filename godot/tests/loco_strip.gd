extends Node3D
## One character through a whole move, side on, as a strip of moments:
## standing, setting off, walking, speeding up to a run, slowing and
## stopping. Each copy stops at its moment and stands where the moving one
## had got to, so the steps line up with the ground (sliding feet show).
## Run: godot --path godot res://tests/loco_strip.tscn -- --out=/dir --char=lola [--empty] [--side]

var out := "user://"
var who := "lola"
var armed := true
var side := false         # strafing to the right instead of going forward

## Ground speed (m/s) at time t of the move.
func speed_at(t: float) -> float:
	if t < 0.4: return 0.0
	if t < 0.9: return lerpf(0.0, 1.8, (t - 0.4) / 0.5)
	if t < 2.2: return 1.8
	if t < 2.7: return lerpf(1.8, 5.2, (t - 2.2) / 0.5)
	if t < 3.6: return 5.2
	if t < 3.9: return lerpf(5.2, 1.8, (t - 3.6) / 0.3)
	if t < 4.6: return 1.8
	if t < 4.8: return lerpf(1.8, 0.0, (t - 4.6) / 0.2)
	return 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--char="): who = a.substr(7)
		if a == "--empty": armed = false
		if a == "--side": side = true
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
	# Ground with a metre grid, to see the feet against.
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 10)
	fl.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.82, 0.82, 0.8)
	fl.material_override = gm
	add_child(fl)
	for i in 41:
		var ln := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.005, 3.0)
		ln.mesh = bm
		ln.position = Vector3(i - 20.0, 0.003, 0)
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.4, 0.4, 0.4)
		ln.material_override = lm
		add_child(ln)
	_run.call_deferred()

func _run() -> void:
	var cam := Camera3D.new()
	cam.fov = 38
	add_child(cam)
	cam.current = true
	var shots := 16
	var models := []
	for i in shots:
		var m := HumanModel.new(Color("2d6fb8"), Color("f2a900"), Color("33373d"), who)
		add_child(m)
		m.rotation.y = -PI * 0.5 if not side else 0.0     # facing +X (the way it goes), side on to the camera
		if armed: m.set_weapon("m416")
		m.set_gear(0, 0, 0)
		models.append(m)
	var dt := 1.0 / 30.0
	var total := 5.6
	var dist := 0.0
	var frames := int(total / dt)
	for f in frames:
		var t := f * dt
		var sp := speed_at(t)
		dist += sp * dt
		for i in shots:
			var stop_t: float = total * float(i) / (shots - 1)
			if t > stop_t: continue
			var m: HumanModel = models[i]
			m.move_local = Vector2(sp, 0) if side else Vector2(0, sp)
			m.set_pose("stand", sp, armed, dt, t)
			m.set_meta("x", dist)
		await get_tree().process_frame
	# Lay the frozen copies out, each where the moving one had got to.
	for i in shots:
		var m: HumanModel = models[i]
		m.position = Vector3(float(m.get_meta("x", 0.0)), 0, 0)
	var mid := float(models[-1].get_meta("x", 0.0)) * 0.5
	cam.look_at_from_position(Vector3(mid, 1.3, 24.0), Vector3(mid, 0.9, 0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("loco_%s_%s%s.png" % [who, "rifle" if armed else "empty", "_side" if side else ""]))
	print("shot loco ", who)
	get_tree().quit()
