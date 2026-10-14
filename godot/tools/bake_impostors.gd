extends Node
## Bakes the far-away tree cards: each detailed tree model photographed from the
## front, the side and from above (colour only, no lighting) into one atlas, plus where the
## tree sits in each picture.
## Run (needs a renderer): godot --path godot res://tools/bake_impostors.tscn
## Writes assets/textures/impostors/trees.png and trees.json.

const CELL := 256
const KEYS := ["bl0", "bl1", "pn0", "pn1", "fr0", "pm0", "pm1", "au0", "sk0"]

func _ready() -> void:
	_bake.call_deferred()

func _bake() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL * 2, CELL * 2)
	vp.transparent_bg = true
	vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color("c8b8a8")
	bark.albedo_texture = load("res://assets/textures/bark_col.jpg")
	var meshes := WorldBuilder.near_tree_meshes(bark, 0.0)
	var atlas := Image.create(CELL * KEYS.size(), CELL * 3, false, Image.FORMAT_RGBA8)
	var info := {}
	var mi := MeshInstance3D.new()
	vp.add_child(mi)
	for i in KEYS.size():
		var key: String = KEYS[i]
		mi.mesh = meshes[key]
		var ab: AABB = mi.mesh.get_aabb()
		# Square frame around the tree, its foot at the bottom edge.
		var side := maxf(ab.size.y, maxf(ab.size.x, ab.size.z)) * 1.02
		var foot := ab.position.y
		var top := maxf(ab.size.x, ab.size.z) * 1.02
		var c := ab.get_center()
		info[key] = {"col": i, "size": side, "foot": foot, "top": top, "cx": c.x, "cz": c.z}
		# Front, side, and straight down (seen from the parachute and the plane).
		for view in 3:
			var yaw := view * PI * 0.5
			var dir := Vector3(sin(yaw), 0, cos(yaw))
			cam.size = side
			cam.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, foot + side * 0.5, c.z) + dir * 60.0)
			if view == 2:
				cam.size = top
				cam.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(c.x, ab.end.y + 60.0, c.z))
			cam.near = 1.0
			cam.far = 200.0
			for f in 4: await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
			atlas.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(i * CELL, view * CELL))
		print("baked ", key, " size ", side)
	_dilate(atlas)
	atlas.save_png("res://assets/textures/impostors/trees.png")
	var f := FileAccess.open("res://assets/textures/impostors/trees.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"cell": CELL, "keys": KEYS, "trees": info}, "\t"))
	f.close()
	print("BAKE DONE")
	get_tree().quit()

## Spreads the leaf colours into the see-through pixels around them, so the
## smaller mip levels don't fade the edges to black.
func _dilate(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for pass_i in 8:
		var src := img.duplicate() as Image
		for y in h:
			for x in w:
				if src.get_pixel(x, y).a > 0.05: continue
				var acc := Color(0, 0, 0, 0)
				var n := 0
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + o
					if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h: continue
					var c := src.get_pixel(q.x, q.y)
					if c.a > 0.05:
						acc += Color(c.r, c.g, c.b, 0)
						n += 1
				if n > 0:
					var a := src.get_pixel(x, y).a
					img.set_pixel(x, y, Color(acc.r / n, acc.g / n, acc.b / n, minf(a, 0.04)))
