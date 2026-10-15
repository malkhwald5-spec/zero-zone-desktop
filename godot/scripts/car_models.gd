class_name CarModels
## Vehicle models: imported, cleaned-up models (see IMPORTED). Each is cached
## per kind; paint is a per-vehicle material set by Vehicle.

static var _cache := {}

## Imported models (Sketchfab, CC-BY — see README): the UAZ jeep, the dirt
## bike, the Lada saloon, the pickup and the speedboat (the last three made by
## tools/prep_vehicle.gd). "len" scales the model to that length (0 = already in metres).
const IMPORTED := {
	"jeep": {"path": "res://assets/models/vehicles/uaz/scene.gltf", "len": 4.1},
	"bike": {"path": "res://assets/models/vehicles/dirt_bike/dirt_bike.glb", "len": 0.0},
	"sedan": {"path": "res://assets/models/vehicles/lada/lada.glb", "len": 0.0, "keep": ["BaseColorCuzov", "stopari"]},
	"pickup": {"path": "res://assets/models/vehicles/pickup/pickup.glb", "len": 0.0},
	"boat": {"path": "res://assets/models/vehicles/speedboat/speedboat.glb", "len": 0.0, "keep": ["GreenPlate"]},
}

## The body merged into one mesh (plain colours into one vertex-coloured
## surface, except the "keep" materials) and each wheel (nodes named wheel*) as its
## own mesh centred on its axle: {"body", "wheels": [[mesh, centre]], "radius"}.
## Faces +Z, ground at y = 0, the axles centred on z = 0.
static func imported(kind: String) -> Dictionary:
	if _cache.has("imp_" + kind): return _cache["imp_" + kind]
	var cfg: Dictionary = IMPORTED[kind]
	var sc: Node3D = load(cfg.path).instantiate()
	var acc := [null]
	WeaponModels._mesh_aabb(sc, Transform3D.IDENTITY, acc)
	var a: AABB = acc[0]
	var s: float = cfg.len / a.size.z if cfg.len > 0.0 else 1.0
	var wheels := []      # [node, parent transform]
	_find_wheels(sc, Transform3D.IDENTITY, wheels)
	var scale := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO)
	var boxes := []
	var lo := INF
	var zs := []
	for w in wheels:
		var wa := [null]
		WeaponModels._mesh_aabb(w[0], scale * w[1], wa)
		boxes.append(wa[0])
		lo = minf(lo, wa[0].position.y)
		zs.append(wa[0].get_center().z)
	var zmid: float = (zs.min() + zs.max()) * 0.5 if zs.size() > 0 else a.get_center().z * s
	if wheels.is_empty(): lo = a.position.y * s     # a boat: the keel on y = 0
	var xf := Transform3D(Basis.IDENTITY, Vector3(-a.get_center().x * s, -lo, -zmid)) * scale
	var body := ArrayMesh.new()
	var by_mat := {}
	var flat := SurfaceTool.new()
	flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_flat := [false]
	_merge_body(sc, Transform3D.IDENTITY, xf, by_mat, flat, has_flat, cfg.get("keep", []))
	_commit_merged(body, by_mat, flat, has_flat[0])
	var out_w := []
	var radius := 0.0
	for i in wheels.size():
		var c: Vector3 = Transform3D(Basis.IDENTITY, Vector3(-a.get_center().x * s, -lo, -zmid)) * boxes[i].get_center()
		radius = maxf(radius, boxes[i].size.y * 0.5)
		var wm := ArrayMesh.new()
		var wb := {}
		var wf := SurfaceTool.new()
		wf.begin(Mesh.PRIMITIVE_TRIANGLES)
		var whf := [false]
		WeaponModels._merge_fitted(wheels[i][0], Transform3D(Basis.IDENTITY, -c) * xf * wheels[i][1], wb, wf, whf)
		_commit_merged(wm, wb, wf, whf[0])
		out_w.append([wm, c])
	sc.free()
	var out := {"body": body, "wheels": out_w, "radius": radius}
	_cache["imp_" + kind] = out
	return out

static func _find_wheels(n: Node, xf: Transform3D, out: Array) -> void:
	if String(n.name).to_lower().begins_with("wheel"):
		out.append([n, xf])
		return
	if n is Node3D: xf = xf * (n as Node3D).transform
	for c in n.get_children(): _find_wheels(c, xf, out)

static func _merge_body(n: Node, parent: Transform3D, xf: Transform3D, by_mat: Dictionary, flat: SurfaceTool, has_flat: Array, keep: Array = []) -> void:
	if String(n.name).to_lower().begins_with("wheel"): return
	if n is MeshInstance3D:
		WeaponModels._merge_fitted(n, xf * parent, by_mat, flat, has_flat, keep)
		return
	var here := parent * (n as Node3D).transform if n is Node3D else parent
	for c in n.get_children(): _merge_body(c, here, xf, by_mat, flat, has_flat, keep)

static func _commit_merged(mesh: ArrayMesh, by_mat: Dictionary, flat: SurfaceTool, has_flat: bool) -> void:
	for mat in by_mat:
		var st: SurfaceTool = by_mat[mat]
		st.set_material(mat)
		st.commit(mesh)
	if has_flat:
		var fm := StandardMaterial3D.new()
		fm.vertex_color_use_as_albedo = true
		fm.vertex_color_is_srgb = true
		fm.roughness = 0.45
		fm.metallic = 0.2
		flat.set_material(fm)
		flat.commit(mesh)
