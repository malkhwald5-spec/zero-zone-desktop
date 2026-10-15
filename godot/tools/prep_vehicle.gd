extends SceneTree
## Prepares a downloaded car or boat for the game:
## godot --headless --path godot -s res://tools/prep_vehicle.gd -- --src=res://x/scene.gltf --out=res://assets/models/vehicles/x.glb
##     [--turn=180] [--len=4.4] [--tris=24000] [--wtris=1500] [--tex=1024] [--split-wheels] [--drop-far]
## - the nodes named wheel* stay separate ("wheel0".."wheelN", in model space);
##   with --split-wheels a model whose wheels are welded into the body gets them
##   cut out: the loose low round pieces at the four corners;
## - everything else is merged into "body", a surface per material, and
##   simplified to about --tris triangles (each wheel to --wtris);
## - --turn spins the model about the vertical (the game wants the nose at +Z),
##   --len scales it to that length; --drop-far removes loose pieces lying away
##   from the vehicle; textures shrunk to --tex pixels.
## Prints where the head- and tail-light materials sit, to check the facing.

func _init() -> void:
	var src := ""
	var out := ""
	var turn := 0.0
	var length := 0.0
	var tris := 24000
	var wtris := 1500
	var tex := 1024
	var split := false
	var drop_far := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="): src = a.substr(6)
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--turn="): turn = float(a.substr(7))
		if a.begins_with("--len="): length = float(a.substr(6))
		if a.begins_with("--tris="): tris = int(a.substr(7))
		if a.begins_with("--wtris="): wtris = int(a.substr(8))
		if a.begins_with("--tex="): tex = int(a.substr(6))
		if a == "--split-wheels": split = true
		if a == "--drop-far": drop_far = true
	var sc: Node = load(src).instantiate()
	var body := {}
	var wheels := []
	_collect(sc, Transform3D(Basis(Vector3.UP, deg_to_rad(turn)), Vector3.ZERO), body, wheels, null)
	# Scale to the wanted length.
	var ab := _bounds(body)
	for w in wheels: ab = ab.merge(_bounds(w))
	var k := length / ab.size.z if length > 0.0 else 1.0
	if k != 1.0:
		var sxf := Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3.ZERO)
		body = _moved(body, sxf)
		for i in wheels.size(): wheels[i] = _moved(wheels[i], sxf)
	if drop_far: body = _drop_far(body)
	if split: wheels = _split_wheels(body)
	for mat in body:
		var arr: Array = body[mat]
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var c := Vector3.ZERO
		for p in v: c += p
		var nm := (mat as Material).resource_name if mat else ""
		print("  material ", nm, " tris ", _tri_count(arr), " centre ", (c / maxf(v.size(), 1)).snapped(Vector3.ONE * 0.01))
	var root := Node3D.new()
	root.name = "vehicle"
	_add(root, "body", body, tris, tex)
	for i in wheels.size(): _add(root, "wheel%d" % i, wheels[i], wtris, tex)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
	if err == OK: err = doc.write_to_filesystem(st, ProjectSettings.globalize_path(out))
	print("vehicle ", out, " wheels ", wheels.size(), " size ", ab.size * k, " err=", err)
	sc.free()
	root.free()
	quit()

## Surfaces by material: {material: arrays}. Nodes named wheel* each go to
## their own dictionary in `wheels`.
func _collect(n: Node, xf: Transform3D, body: Dictionary, wheels: Array, into) -> void:
	if n is Node3D:
		if not (n as Node3D).visible: return
		xf = xf * (n as Node3D).transform
	if into == null and String(n.name).to_lower().begins_with("wheel"):
		into = {}
		wheels.append(into)
	var dst: Dictionary = into if into != null else body
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(i)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			if dst.has(mat): st.append_from(_mesh_of(dst[mat]), 0, Transform3D.IDENTITY)
			st.append_from(mi.mesh, i, xf)
			st.index()
			dst[mat] = st.commit_to_arrays()
	for c in n.get_children(): _collect(c, xf, body, wheels, into)

func _mesh_of(arr: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func _tri_count(arr: Array) -> int:
	var idx = arr[Mesh.ARRAY_INDEX]
	return (idx as PackedInt32Array).size() / 3 if idx else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

func _bounds(group: Dictionary) -> AABB:
	var ab := AABB()
	var first := true
	for mat in group:
		for p in (group[mat][Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if first: ab = AABB(p, Vector3.ZERO)
			else: ab = ab.expand(p)
			first = false
	return ab

func _moved(group: Dictionary, xf: Transform3D) -> Dictionary:
	var out := {}
	for mat in group:
		var arr: Array = group[mat].duplicate()
		var v: PackedVector3Array = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		for i in v.size(): v[i] = xf * v[i]
		arr[Mesh.ARRAY_VERTEX] = v
		out[mat] = arr
	return out

## Connected pieces of every surface: [[material, triangle list]], welding by position.
func _pieces(group: Dictionary) -> Array:
	var out := []
	for mat in group:
		var arr: Array = group[mat]
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx := _idx(arr)
		# Union-find over welded vertex positions.
		var key_of := {}
		var parent := PackedInt32Array()
		var weld := PackedInt32Array()
		weld.resize(v.size())
		for i in v.size():
			var key := Vector3i((v[i] * 1000.0).round())
			if not key_of.has(key):
				key_of[key] = parent.size()
				parent.append(parent.size())
			weld[i] = key_of[key]
		var find := func(x: int) -> int:
			while parent[x] != x:
				parent[x] = parent[parent[x]]
				x = parent[x]
			return x
		for t in idx.size() / 3:
			var a: int = find.call(weld[idx[t * 3]])
			for j in [1, 2]:
				var b: int = find.call(weld[idx[t * 3 + j]])
				if a != b: parent[b] = a
		var by_root := {}
		for t in idx.size() / 3:
			var r: int = find.call(weld[idx[t * 3]])
			if not by_root.has(r): by_root[r] = []
			by_root[r].append(t)
		for r in by_root: out.append([mat, PackedInt32Array(by_root[r])])
	return out

func _idx(arr: Array) -> PackedInt32Array:
	if arr[Mesh.ARRAY_INDEX] and (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0: return arr[Mesh.ARRAY_INDEX]
	return PackedInt32Array(range((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()))

func _piece_box(arr: Array, tris: PackedInt32Array) -> AABB:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx := _idx(arr)
	var ab := AABB(v[idx[tris[0] * 3]], Vector3.ZERO)
	for t in tris:
		for j in 3: ab = ab.expand(v[idx[t * 3 + j]])
	return ab

## Rebuilds a group keeping (keep = true) or dropping the given triangles per material.
func _filtered(group: Dictionary, chosen: Dictionary, keep: bool) -> Dictionary:
	var out := {}
	for mat in group:
		var arr: Array = group[mat]
		var idx := _idx(arr)
		var sel: Dictionary = chosen.get(mat, {})
		var ni := PackedInt32Array()
		for t in idx.size() / 3:
			if sel.has(t) == keep:
				ni.append(idx[t * 3])
				ni.append(idx[t * 3 + 1])
				ni.append(idx[t * 3 + 2])
		if ni.is_empty(): continue
		var a2 := arr.duplicate()
		a2[Mesh.ARRAY_INDEX] = ni
		out[mat] = a2
	return out

## Small pieces far from the main body (stray parts left in the file).
func _drop_far(group: Dictionary) -> Dictionary:
	var pieces := _pieces(group)
	var big := AABB()
	var best := 0
	for p in pieces:
		if p[1].size() > best:
			best = p[1].size()
			big = _piece_box(group[p[0]], p[1])
	big = big.grow(maxf(big.size.x, big.size.z) * 0.6)
	var drop := {}
	var n := 0
	for p in pieces:
		if not big.intersects(_piece_box(group[p[0]], p[1])):
			if not drop.has(p[0]): drop[p[0]] = {}
			for t in p[1]: drop[p[0]][t] = true
			n += 1
	print("  dropped ", n, " far pieces")
	return _filtered(group, drop, false)

## Wheels welded into the body: low, round pieces at the four corners. Every
## piece whose centre lies inside a corner wheel's box goes with it (tyre, rim, hub).
func _split_wheels(body: Dictionary) -> Array:
	var ab := _bounds(body)
	var pieces := _pieces(body)
	var tyres := {}         # corner -> AABB of its biggest round piece
	for p in pieces:
		var b := _piece_box(body[p[0]], p[1])
		var round_ok: bool = absf(b.size.y - b.size.z) < b.size.y * 0.3 and b.size.y > ab.size.y * 0.15 and b.size.y < ab.size.y * 0.55
		if not round_ok or b.position.y > ab.position.y + ab.size.y * 0.1: continue
		var c := b.get_center()
		var corner := Vector2i(1 if c.x > ab.get_center().x else 0, 1 if c.z > ab.get_center().z else 0)
		if not tyres.has(corner) or b.get_volume() > (tyres[corner] as AABB).get_volume():
			tyres[corner] = b
	var out := []
	var taken := {}
	for corner in tyres:
		var wb: AABB = (tyres[corner] as AABB).grow(0.02)
		var sel := {}
		for p in pieces:
			var b := _piece_box(body[p[0]], p[1])
			if wb.has_point(b.get_center()) and b.size.y <= wb.size.y + 0.05:
				if not sel.has(p[0]): sel[p[0]] = {}
				if not taken.has(p[0]): taken[p[0]] = {}
				for t in p[1]:
					sel[p[0]][t] = true
					taken[p[0]][t] = true
		out.append(_filtered(body, sel, true))
	var rest := _filtered(body, taken, false)
	body.clear()
	body.merge(rest)
	print("  split out ", out.size(), " wheels")
	return out

func _add(root: Node3D, name: String, group: Dictionary, tris: int, tex: int) -> void:
	var im := ImporterMesh.new()
	var total := 0
	for mat in group:
		total += _tri_count(group[mat])
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, group[mat], [], {}, mat)
	var keep := clampf(float(tris) / maxf(total, 1.0), 0.0, 1.0)
	if keep < 1.0: im.generate_lods(60.0, 90.0, [])
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
		arr[Mesh.ARRAY_INDEX] = best
		got += best.size() / 3
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m := im.get_surface_material(s)
		if m is BaseMaterial3D: _shrink(m, tex)
		mesh.surface_set_material(s, m)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	root.add_child(mi)
	mi.owner = root
	print("  ", name, " tris ", total, " -> ", got)

func _shrink(m: BaseMaterial3D, tex: int) -> void:
	for p in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "emission_texture", "ao_texture"]:
		var t: Texture2D = m.get(p)
		if t == null: continue
		var img := t.get_image()
		if img == null: continue
		if img.is_compressed(): img.decompress()
		var s := float(tex) / maxf(img.get_width(), img.get_height())
		if s < 1.0: img.resize(maxi(4, int(img.get_width() * s)), maxi(4, int(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
		m.set(p, ImageTexture.create_from_image(img))
