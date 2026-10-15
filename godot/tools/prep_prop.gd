extends SceneTree
## Prepares a downloaded static model (helmet, vest, backpack...) for the game:
## godot --headless --path godot -s res://tools/prep_prop.gd -- --src=res://x/scene.gltf --out=res://assets/models/gear/x.glb [--tris=6000] [--tex=1024] [--only=Name1,Name2]
## - every mesh (or only the nodes whose names start with one of --only) is
##   merged into one mesh, a surface per material, in the model's own space;
## - simplified to about --tris triangles with the engine's mesh simplifier,
##   which keeps the UVs (so the textures still fit);
## - textures shrunk to --tex pixels; written as one .glb, or, when --out ends
##   in .obj, as an OBJ with its .mtl and textures (what Mixamo's auto-rigger
##   takes: zip the folder and upload it).

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
	if out.ends_with(".obj"):
		_write_obj(mesh, out)
		print("obj ", src, " tris ", total, " -> ", got, " aabb ", mesh.get_aabb())
		sc.free()
		quit()
		return
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

## OBJ + MTL + PNG textures, one material group per surface.
func _write_obj(mesh: ArrayMesh, out: String) -> void:
	var dir := out.get_base_dir()
	var base := out.get_file().get_basename()
	DirAccess.make_dir_recursive_absolute(dir)
	var obj := FileAccess.open(out, FileAccess.WRITE)
	var mtl := FileAccess.open(dir.path_join(base + ".mtl"), FileAccess.WRITE)
	obj.store_line("mtllib %s.mtl" % base)
	var off := 1
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv = arr[Mesh.ARRAY_TEX_UV]
		var nr = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var mname := "mat%d" % s
		obj.store_line("o part%d" % s)
		for p in v: obj.store_line("v %f %f %f" % [p.x, p.y, p.z])
		if uv:
			for t in uv: obj.store_line("vt %f %f" % [t.x, 1.0 - t.y])
		if nr:
			for n in nr: obj.store_line("vn %f %f %f" % [n.x, n.y, n.z])
		obj.store_line("usemtl " + mname)
		for t in idx.size() / 3:
			# Godot winds clockwise; OBJ counter-clockwise.
			var a := idx[t * 3] + off
			var b := idx[t * 3 + 2] + off
			var c := idx[t * 3 + 1] + off
			obj.store_line("f %d/%d/%d %d/%d/%d %d/%d/%d" % [a, a, a, b, b, b, c, c, c])
		off += v.size()
		mtl.store_line("newmtl " + mname)
		var m := mesh.surface_get_material(s) as BaseMaterial3D
		if m and m.albedo_texture:
			var img := m.albedo_texture.get_image()
			if img.is_compressed(): img.decompress()
			img.save_png(dir.path_join(mname + ".png"))
			mtl.store_line("Kd 1 1 1")
			mtl.store_line("map_Kd %s.png" % mname)
		elif m:
			mtl.store_line("Kd %f %f %f" % [m.albedo_color.r, m.albedo_color.g, m.albedo_color.b])
	obj.close()
	mtl.close()
