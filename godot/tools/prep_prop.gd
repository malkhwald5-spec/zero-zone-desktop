extends SceneTree
## Prepares a downloaded static model (helmet, vest, backpack...) for the game:
## godot --headless --path godot -s res://tools/prep_prop.gd -- --src=res://x/scene.gltf --out=res://assets/models/gear/x.glb [--tris=6000] [--tex=1024] [--only=Name1,Name2]
## - every mesh (or only the nodes whose names start with one of --only) is
##   merged into one mesh, a surface per material, in the model's own space;
## - simplified to about --tris triangles with the engine's mesh simplifier,
##   which keeps the UVs (so the textures still fit);
## - textures shrunk to --tex pixels; written as one .glb.

func _init() -> void:
	var src := ""
	var out := ""
	var tris := 6000
	var tex := 1024
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="): src = a.substr(6)
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--tris="): tris = int(a.substr(7))
		if a.begins_with("--tex="): tex = int(a.substr(6))
		if a.begins_with("--only="): only = a.substr(7).split(",")
	var sc: Node = load(src).instantiate()
	var by_mat := {}
	_collect(sc, Transform3D.IDENTITY, by_mat, only, false)
	var im := ImporterMesh.new()
	var total := 0
	for mat in by_mat:
		var arr: Array = (by_mat[mat] as SurfaceTool).commit_to_arrays()
		total += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arr[Mesh.ARRAY_INDEX] else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mat)
	var keep := clampf(float(tris) / maxf(total, 1.0), 0.0, 1.0)
	if keep < 1.0: im.generate_lods(25.0, 60.0, [])
	var mesh := ArrayMesh.new()
	var got := 0
	for s in im.get_surface_count():
		var arr := im.get_surface_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var best := idx
		if keep < 1.0:
			for l in im.get_surface_lod_count(s):
				var li := im.get_surface_lod_indices(s, l)
				if li.size() >= idx.size() * keep: best = li
		arr = _compact(arr, best)
		got += best.size() / 3
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m := im.get_surface_material(s)
		if m is BaseMaterial3D: _shrink(m, tex)
		mesh.surface_set_material(s, m)
	var root := Node3D.new()
	root.name = "prop"
	var mi := MeshInstance3D.new()
	mi.name = "mesh"
	mi.mesh = mesh
	root.add_child(mi)
	mi.owner = root
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
	if err == OK: err = doc.write_to_filesystem(st, ProjectSettings.globalize_path(out))
	print("prop ", src, " tris ", total, " -> ", got, " aabb ", mesh.get_aabb(), " err=", err)
	sc.free()
	root.free()
	quit()

func _collect(n: Node, xf: Transform3D, by_mat: Dictionary, only: PackedStringArray, picked: bool) -> void:
	if n is Node3D:
		if not (n as Node3D).visible: return
		xf = xf * (n as Node3D).transform
	if not picked and only.size() > 0:
		for o in only:
			if String(n.name).begins_with(o): picked = true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and (picked or only.is_empty()):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(i)
			if not by_mat.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = st
			(by_mat[mat] as SurfaceTool).append_from(mi.mesh, i, xf)
	for c in n.get_children(): _collect(c, xf, by_mat, only, picked)

## Keeps only the vertices the index list uses.
func _compact(arr: Array, idx: PackedInt32Array) -> Array:
	var n: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var remap := PackedInt32Array()
	remap.resize(n)
	remap.fill(-1)
	var order := PackedInt32Array()
	for i in idx:
		if remap[i] < 0:
			remap[i] = order.size()
			order.append(i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in Mesh.ARRAY_MAX:
		var a = arr[k]
		if a == null or k == Mesh.ARRAY_INDEX: continue
		var per := 1
		if k == Mesh.ARRAY_TANGENT: per = 4
		var src_size: int = a.size()
		if src_size != n * per: continue
		var b = a.duplicate()
		b.resize(order.size() * per)
		for j in order.size():
			for c in per: b[j * per + c] = a[order[j] * per + c]
		out[k] = b
	var ni := PackedInt32Array()
	ni.resize(idx.size())
	for i in idx.size(): ni[i] = remap[idx[i]]
	out[Mesh.ARRAY_INDEX] = ni
	return out

func _shrink(m: BaseMaterial3D, tex: int) -> void:
	for p in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "emission_texture", "ao_texture"]:
		var t: Texture2D = m.get(p)
		if t == null: continue
		var img := t.get_image()
		if img == null: continue
		if img.is_compressed(): img.decompress()
		var k := float(tex) / maxf(img.get_width(), img.get_height())
		if k < 1.0: img.resize(maxi(4, int(img.get_width() * k)), maxi(4, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		m.set(p, ImageTexture.create_from_image(img))
