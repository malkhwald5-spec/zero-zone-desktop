extends Node
## Renders a picture of every gun (side on, transparent background) for the
## HUD slots, the shop and the pick-up notice: assets/textures/ui/weapons/<id>.png.
## Run (needs a GPU / lavapipe): godot --path godot res://tests/bake_weapon_icons.tscn -- --out=/dir

var out := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	_run.call_deferred()

func _aabb(n: Node, acc: Array) -> void:
	if n is MeshInstance3D and n.visible and (n as MeshInstance3D).mesh:
		var mi: MeshInstance3D = n
		var bb: AABB = mi.global_transform * mi.mesh.get_aabb()
		acc[0] = bb if acc[0] == null else (acc[0] as AABB).merge(bb)
	for c in n.get_children(): _aabb(c, acc)

func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 224)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.2
	vp.add_child(key)
	key.look_at_from_position(Vector3(3, 4, 2), Vector3.ZERO)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.2
	rim.light_color = Color(0.7, 0.85, 1.0)
	vp.add_child(rim)
	rim.look_at_from_position(Vector3(-2, 1, -3), Vector3.ZERO)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	cam.current = true
	for id in Game.WEAPONS:
		var w := WeaponModels.build(id)
		vp.add_child(w)
		await get_tree().process_frame
		var acc := [null]
		_aabb(w, acc)
		if acc[0] == null:
			w.queue_free()
			continue
		var bb: AABB = acc[0]
		var c := bb.get_center()
		# Side on (muzzle to the right), a touch from above.
		cam.size = maxf(bb.size.z * 0.5, bb.size.y * 1.15) * 1.12
		cam.look_at_from_position(c + Vector3(6, 0.35, 0), c, Vector3.UP)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(out.path_join(id + ".png"))
		print("icon ", id)
		w.queue_free()
	print("ICONS DONE")
	get_tree().quit()
