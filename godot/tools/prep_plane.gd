extends SceneTree
## Prepares the downloaded transport plane for the game:
## godot --headless --path godot -s res://tools/prep_plane.gd -- --src=res://x/scene.gltf --out=res://assets/models/air/plane.glb [--tex=1024]
## - only the outside is kept (skin, windows, propellers): nobody sees the
##   cockpit, and its instruments are most of the triangles;
## - the propeller surface is split into one node per engine ("prop0".."prop3"),
##   each with its pivot on the hub, so the game can spin them;
## - the nose is turned to face -Z and the plane centred; textures shrunk to --tex.

const KEEP := ["DefaultWhite_texture_png_001", "transparentExt"]
const PROP := "DefaultWhite_propeller_png"

func _init() -> void:
	var src := ""
	var out := ""
	var tex := 1024
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="): src = a.substr(6)
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--tex="): tex = int(a.substr(6))
	var sc: Node = load(src).instantiate()
	var body := {}
	var props := SurfaceTool.new()
	props.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prop_mat: Material = null
	_collect(sc, Transform3D.IDENTITY, body, props, func(m: Material) -> void: prop_mat = m)
	# Instruments sit at -X, so the nose points -X: turn it to -Z.
	var turn := Transform3D(Basis(Vector3.UP, -PI / 2), Vector3.ZERO)
	var mesh := ArrayMesh.new()
	for mat in body:
		var st: SurfaceTool = body[mat]
		var arr := _simplified(_moved(st.commit_to_arrays(), turn), 0.45)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_shrink(mat, tex)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	var body_tris := 0
	for i in mesh.get_surface_count(): body_tris += mesh.surface_get_array_index_len(i) / 3
	print("body tris ", body_tris)
	var centre := mesh.get_aabb().get_center()
	centre.y = 0.0
	var root := Node3D.new()
	root.name = "plane"
	var mi := MeshInstance3D.new()
	mi.name = "body"
	mi.mesh = mesh
	mi.position = -centre
	root.add_child(mi)
	mi.owner = root
	# Split the propellers by engine: four clusters along the wing (X now).
	_shrink(prop_mat, tex)
	var parr := _moved(props.commit_to_arrays(), turn)
	var verts: PackedVector3Array = parr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = parr[Mesh.ARRAY_INDEX]
	var xs := PackedFloat32Array()
	for t in idx.size() / 3:
		xs.append((verts[idx[t * 3]].x + verts[idx[t * 3 + 1]].x + verts[idx[t * 3 + 2]].x) / 3.0)
	# One-dimensional k-means: each triangle goes to the nearest engine.
	var lo := mesh.get_aabb().position.x
	var span := mesh.get_aabb().size.x
	var cx := [lo + span * 0.125, lo + span * 0.375, lo + span * 0.625, lo + span * 0.875]
	var groups := [[], [], [], []]
	for it in 12:
		groups = [[], [], [], []]
		for t in xs.size():
			var best := 0
			for g in 4:
				if absf(xs[t] - cx[g]) < absf(xs[t] - cx[best]): best = g
			groups[best].append(t)
		for g in 4:
			if groups[g].is_empty(): continue
			var sum := 0.0
			for t in groups[g]: sum += xs[t]
			cx[g] = sum / groups[g].size()
	for g in 4:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var ab := AABB()
		var first := true
		for t in groups[g]:
			for k in 3:
				var p := verts[idx[t * 3 + k]]
				if first: ab = AABB(p, Vector3.ZERO)
				else: ab = ab.expand(p)
				first = false
		var hub := ab.get_center()
		var shift := Transform3D(Basis.IDENTITY, -hub)
		for t in groups[g]:
			for k in 3:
				var i := idx[t * 3 + k]
				if parr[Mesh.ARRAY_NORMAL]: st.set_normal(parr[Mesh.ARRAY_NORMAL][i])
				if parr[Mesh.ARRAY_TEX_UV]: st.set_uv(parr[Mesh.ARRAY_TEX_UV][i])
				st.add_vertex(shift * verts[i])
		st.index()
		var pm := ArrayMesh.new()
		pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _simplified(st.commit_to_arrays(), 0.2))
		pm.surface_set_material(0, prop_mat)
		var pi := MeshInstance3D.new()
		pi.name = "prop%d" % g
		pi.mesh = pm
		pi.position = hub - centre
		root.add_child(pi)
		pi.owner = root
		print("prop", g, " tris ", groups[g].size(), " hub ", hub - centre)
	var doc := GLTFDocument.new()
	var gs := GLTFState.new()
	var err := doc.append_from_scene(root, gs)
	if err == OK: err = doc.write_to_filesystem(gs, ProjectSettings.globalize_path(out))
	print("plane ", out, " body aabb ", mesh.get_aabb(), " err=", err)
	sc.free()
	root.free()
	quit()

func _collect(n: Node, xf: Transform3D, body: Dictionary, props: SurfaceTool, on_prop: Callable) -> void:
	if n is Node3D:
		if not (n as Node3D).visible: return
		xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(i)
			var nm := mat.resource_name.replace(".", "_") if mat else ""
			if nm == PROP:
				on_prop.call(mat)
				props.append_from(mi.mesh, i, xf)
			elif nm in KEEP:
				if not body.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					body[mat] = st
				(body[mat] as SurfaceTool).append_from(mi.mesh, i, xf)
	for c in n.get_children(): _collect(c, xf, body, props, on_prop)

func _moved(arr: Array, xf: Transform3D) -> Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size(): v[i] = xf * v[i]
	arr[Mesh.ARRAY_VERTEX] = v
	if arr[Mesh.ARRAY_NORMAL]:
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in nr.size(): nr[i] = xf.basis * nr[i]
		arr[Mesh.ARRAY_NORMAL] = nr
	if arr[Mesh.ARRAY_TANGENT]:
		arr[Mesh.ARRAY_TANGENT] = null
	return arr

## The engine's simplifier (keeps UVs): the level of detail closest to keep * triangles.
func _simplified(arr: Array, keep: float) -> Array:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(25.0, 60.0, [])
	var idx: PackedInt32Array = im.get_surface_arrays(0)[Mesh.ARRAY_INDEX]
	var best := idx
	for l in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, l)
		if li.size() >= idx.size() * keep: best = li
	var out := im.get_surface_arrays(0)
	out[Mesh.ARRAY_INDEX] = best
	return out

func _shrink(m: Material, tex: int) -> void:
	if not m is BaseMaterial3D: return
	for p in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "emission_texture", "ao_texture"]:
		var t: Texture2D = m.get(p)
		if t == null: continue
		var img := t.get_image()
		if img == null: continue
		if img.is_compressed(): img.decompress()
		var k := float(tex) / maxf(img.get_width(), img.get_height())
		if k < 1.0: img.resize(maxi(4, int(img.get_width() * k)), maxi(4, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		m.set(p, ImageTexture.create_from_image(img))
