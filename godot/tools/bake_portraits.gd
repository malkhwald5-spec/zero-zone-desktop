extends Node
## Bakes a portrait of every outfit in the wardrobe (head to knees, lit like
## the lobby, see-through background) for the store and inventory cards.
## Run (needs a renderer): godot --path godot res://tools/bake_portraits.tscn
## Writes assets/textures/ui/outfits/outfit_<i>.png.

const W := 256
const H := 340

func _ready() -> void:
	_bake.call_deferred()

func _bake() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(W * 2, H * 2)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("fff1dc")
	key.light_energy = 1.6
	vp.add_child(key)
	key.look_at_from_position(Vector3(1.5, 2.5, 3.0), Vector3(0, 1, 0))
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("ffb070")
	rim.light_energy = 1.2
	vp.add_child(rim)
	rim.look_at_from_position(Vector3(-2.0, 2.0, -2.5), Vector3(0, 1, 0))
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.25, 4.2), Vector3(0, 1.05, 0))
	cam.current = true
	var saved := int(Game.profile.outfit)
	for i in Game.WARDROBE.size():
		Game.profile.outfit = i
		var m := HumanModel.new(Game.outfit_color(), Color("f2a900"), Game.pants_color(), Game.outfit_character(), Game.outfit_dyed())
		m.set_style(Game.outfit_style())
		m.set_gear(0, 0, 0)
		m.set_weapon("")
		m.rotation.y = PI - 0.3
		vp.add_child(m)
		for f in 12:
			m.set_pose("stand", 0.0, false, 0.05, f * 0.05)
			await RenderingServer.frame_post_draw
		for f in 3: await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img = _fit(img)
		img.save_png("res://assets/textures/ui/outfits/outfit_%d.png" % i)
		print("baked outfit ", i, " ", Game.WARDROBE[i][0])
		m.queue_free()
		await get_tree().process_frame
	Game.profile.outfit = saved
	print("PORTRAITS DONE")
	get_tree().quit()

## Crops to the figure (with a little air round it) and fits it into W x H.
func _fit(img: Image) -> Image:
	var used := img.get_used_rect()
	var pad := int(used.size.y * 0.04)
	used = used.grow(pad).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var k := minf(float(W) / used.size.x, float(H) / used.size.y)
	var part := img.get_region(used)
	part.resize(int(used.size.x * k), int(used.size.y * k), Image.INTERPOLATE_LANCZOS)
	var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
	out.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i((W - part.get_width()) / 2, H - part.get_height()))
	return out
