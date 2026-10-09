class_name LootModels
## What loot looks like lying on the ground: the real gun models laid on
## their side, ammo boxes with a few rounds beside them, recognisable meds
## (bandage rolls, a first-aid box with a red cross, a medic bag, an energy
## drink can, a pill bottle), scopes, suppressors, magazines and grips, and
## the helmets, vests and backpacks. Each look is one shared mesh (a surface
## per material) with its base at y = 0, built once.

static var _cache := {}
static var _mats := {}

## Mesh for a pickup's data (same keys as world pickups).
static func mesh(data: Dictionary) -> Mesh:
	var key := _key(data)
	if _cache.has(key): return _cache[key]
	var m: Mesh
	match data.kind:
		"weapon": m = _weapon(data.id)
		"ammo": m = _ammo(data.type)
		"gear": m = _gear(data.gear, int(data.lvl))
		"throw": m = _throwable(data.id)
		"attach": m = _attach(data.id)
		_: m = _heal(data.id)
	_cache[key] = m
	return m

static func _key(data: Dictionary) -> String:
	match data.kind:
		"weapon": return "w_" + data.id
		"ammo": return "a_" + data.type
		"gear": return "g_%s_%d" % [data.gear, data.lvl]
		"throw": return "t_" + data.id
		"attach": return "x_" + data.id
	return "h_" + data.id

# ---------------------------------------------------------------- materials
## Vertex-coloured materials: "matte" (cloth, plastic, card), "metal", "shiny" (cans, brass, lenses).
static func _mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind): return _mats[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	match kind:
		"metal": m.metallic = 0.65; m.roughness = 0.38
		"shiny": m.metallic = 0.85; m.roughness = 0.22
		_: m.roughness = 0.75
	_mats[kind] = m
	return m

# ---------------------------------------------------------------- building blocks
static func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b

## Cylinder standing along Y.
static func _cyl(r: float, h: float, r2 := -1.0, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r2 < 0.0 else r2
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

## parts: [mesh, position, rotation (euler), colour, material kind]
## -> one ArrayMesh, a surface per material kind, base moved to y = 0.
static func _build(parts: Array) -> ArrayMesh:
	var by_kind := {}
	for pt in parts:
		var kind: String = pt[4] if pt.size() > 4 else "matte"
		var tmp := SurfaceTool.new()
		tmp.create_from(pt[0], 0)
		var arr := tmp.commit_to_arrays()
		var cols := PackedColorArray()
		cols.resize(arr[Mesh.ARRAY_VERTEX].size())
		cols.fill(pt[3])
		arr[Mesh.ARRAY_COLOR] = cols
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if not by_kind.has(kind):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_kind[kind] = st
		by_kind[kind].append_from(am, 0, Transform3D(Basis.from_euler(pt[2]), pt[1]))
	var out := ArrayMesh.new()
	for kind in by_kind:
		var st: SurfaceTool = by_kind[kind]
		st.set_material(_mat(kind))
		st.commit(out)
	return _grounded(out)

## Same mesh moved so it is centred on the origin with its base at y = 0.
static func _grounded(m: ArrayMesh) -> ArrayMesh:
	var ab := m.get_aabb()
	var shift := Vector3(-ab.get_center().x, -ab.position.y, -ab.get_center().z)
	var out := ArrayMesh.new()
	for i in m.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(m, i, Transform3D(Basis.IDENTITY, shift))
		st.set_material(m.surface_get_material(i))
		st.commit(out)
	return out

# ---------------------------------------------------------------- weapons
## The held gun model, magazine in, laid on its right side.
static func _weapon(id: String) -> Mesh:
	var root := WeaponModels.build(id)
	var lay := Transform3D(Basis(Vector3.FORWARD, -PI / 2), Vector3.ZERO)
	var by_mat := {}
	_collect(root, lay, by_mat)
	root.free()
	var out := ArrayMesh.new()
	for mat in by_mat:
		var st: SurfaceTool = by_mat[mat]
		st.set_material(mat)
		st.commit(out)
	return _grounded(out)

## Every visible mesh under `n`, merged per material.
static func _collect(n: Node, xf: Transform3D, by_mat: Dictionary) -> void:
	if n is Node3D:
		if not (n as Node3D).visible: return
		xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.material_override if mi.material_override else mi.get_surface_override_material(i)
			if mat == null: mat = mi.mesh.surface_get_material(i)
			if mat == null: mat = WeaponModels._mat("metal")
			if not by_mat.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = st
			by_mat[mat].append_from(mi.mesh, i, xf)
	for c in n.get_children():
		_collect(c, xf, by_mat)

# ---------------------------------------------------------------- ammo
const BRASS := Color(0.78, 0.6, 0.28)
const COPPER := Color(0.72, 0.4, 0.22)

## A box of rounds with a coloured band (the HUD colour of that calibre)
## and a few loose rounds lying in front of it.
static func _ammo(type: String) -> Mesh:
	var band: Color = {"9mm": Color("c9a64a"), "556": Color("5f9a4f"), "762": Color("b8673f"), "12g": Color("b03a3a"), "300": Color("6a4fa8"), "bolt": Color("8a6a3a")}.get(type, Color.GRAY)
	var parts := []
	if type == "bolt":
		# Crossbow bolts: a bundle of shafts with fletching.
		for i in 4:
			var x := (i - 1.5) * 0.022
			parts.append([_cyl(0.006, 0.4, -1.0, 6), Vector3(x, 0.006, 0), Vector3(PI / 2, 0, 0), Color(0.35, 0.3, 0.22)])
			parts.append([_cyl(0.008, 0.035, 0.002, 6), Vector3(x, 0.006, -0.215), Vector3(-PI / 2, 0, 0), Color(0.6, 0.62, 0.65), "metal"])
			parts.append([_box(Vector3(0.002, 0.016, 0.05)), Vector3(x, 0.014, 0.17), Vector3.ZERO, Color(0.75, 0.2, 0.15)])
		parts.append([_box(Vector3(0.1, 0.025, 0.03)), Vector3(0, 0.01, 0.05), Vector3.ZERO, band])
		return _build(parts)
	var can := type in ["556", "762", "300"]
	var sz := Vector3(0.26, 0.17, 0.12) if can else Vector3(0.18, 0.09, 0.12)
	var body_col := Color(0.28, 0.31, 0.2) if can else (Color(0.62, 0.15, 0.13) if type == "12g" else Color(0.66, 0.56, 0.4))
	parts.append([_box(sz), Vector3(0, sz.y * 0.5, 0), Vector3.ZERO, body_col, "metal" if can else "matte"])
	if can:
		# Ammo can: lid, latch, carry handle.
		parts.append([_box(Vector3(sz.x + 0.012, 0.025, sz.z + 0.012)), Vector3(0, sz.y + 0.005, 0), Vector3.ZERO, body_col.darkened(0.15), "metal"])
		parts.append([_box(Vector3(0.03, 0.06, 0.015)), Vector3(sz.x * 0.5 + 0.004, sz.y - 0.02, 0), Vector3.ZERO, body_col.darkened(0.3), "metal"])
		parts.append([_box(Vector3(0.12, 0.012, 0.025)), Vector3(0, sz.y + 0.025, 0), Vector3.ZERO, Color(0.12, 0.12, 0.12)])
	# Calibre band round the box and a label.
	parts.append([_box(Vector3(sz.x + 0.004, 0.03, sz.z + 0.004)), Vector3(0, sz.y * 0.45, 0), Vector3.ZERO, band])
	parts.append([_box(Vector3(sz.x * 0.5, sz.y * 0.35, 0.004)), Vector3(-sz.x * 0.15, sz.y * 0.5, -sz.z * 0.5 - 0.003), Vector3.ZERO, Color(0.9, 0.88, 0.8)])
	# Loose rounds in front.
	var r := {"9mm": [0.005, 0.03], "556": [0.0045, 0.057], "762": [0.0062, 0.07], "300": [0.0068, 0.085], "12g": [0.0105, 0.07]}.get(type, [0.005, 0.05]) as Array
	for i in 3:
		var x := -0.06 + i * 0.045
		var z := -sz.z * 0.5 - 0.05 - (i % 2) * 0.02
		var yaw := 0.3 + i * 0.5
		var case_len: float = r[1] * 0.72
		var case_col := Color(0.75, 0.15, 0.12) if type == "12g" else BRASS
		var along := Basis.from_euler(Vector3(PI / 2, yaw, 0))
		var p0 := Vector3(x, r[0], z)
		parts.append([_cyl(r[0], case_len, -1.0, 8), p0, along.get_euler(), case_col, "shiny"])
		var tip_off := along * Vector3(0, -(case_len * 0.5 + r[1] * 0.14), 0)
		if type == "12g":
			parts.append([_cyl(r[0] * 1.05, r[1] * 0.2, -1.0, 8), p0 + along * Vector3(0, case_len * 0.5 + r[1] * 0.1, 0), along.get_euler(), BRASS, "shiny"])
		else:
			parts.append([_cyl(r[0] * 0.25, r[1] * 0.28, r[0] * 0.9, 8), p0 + tip_off, along.get_euler(), COPPER, "shiny"])
	return _build(parts)

# ---------------------------------------------------------------- meds
static func _heal(id: String) -> Mesh:
	var parts := []
	var red := Color(0.8, 0.1, 0.1)
	var white := Color(0.93, 0.93, 0.9)
	match id:
		"bandage":
			# Two rolls of gauze and a strip unrolled.
			parts.append([_cyl(0.035, 0.07, -1.0, 14), Vector3(0, 0.035, 0), Vector3.ZERO, white])
			parts.append([_cyl(0.035, 0.07, -1.0, 14), Vector3(0.08, 0.035, 0.03), Vector3(PI / 2, 0.4, 0), white])
			parts.append([_box(Vector3(0.06, 0.003, 0.16)), Vector3(-0.02, 0.0015, -0.1), Vector3(0, 0.3, 0), white.darkened(0.05)])
			parts.append([_box(Vector3(0.045, 0.004, 0.045)), Vector3(0, 0.071, 0), Vector3.ZERO, Color(0.85, 0.82, 0.72)])
		"firstaid":
			# White box with a red cross on the lid and a clasp.
			parts.append([_box(Vector3(0.26, 0.09, 0.18)), Vector3(0, 0.045, 0), Vector3.ZERO, white])
			parts.append([_box(Vector3(0.27, 0.015, 0.19)), Vector3(0, 0.09, 0), Vector3.ZERO, white.darkened(0.08)])
			parts.append([_box(Vector3(0.09, 0.004, 0.028)), Vector3(0, 0.099, 0), Vector3.ZERO, red])
			parts.append([_box(Vector3(0.028, 0.004, 0.09)), Vector3(0, 0.099, 0), Vector3.ZERO, red])
			parts.append([_box(Vector3(0.08, 0.02, 0.01)), Vector3(0, 0.07, -0.093), Vector3.ZERO, Color(0.3, 0.3, 0.3), "metal"])
		"medkit":
			# Red medic bag: rounded body, white cross both sides, handles and zip.
			parts.append([_box(Vector3(0.36, 0.17, 0.2)), Vector3(0, 0.085, 0), Vector3.ZERO, red])
			parts.append([_cyl(0.1, 0.36, -1.0, 16), Vector3(0, 0.17, 0), Vector3(0, 0, PI / 2), red.darkened(0.05)])
			for s in [-1.0, 1.0]:
				parts.append([_box(Vector3(0.11, 0.035, 0.004)), Vector3(0, 0.12, s * 0.101), Vector3.ZERO, white])
				parts.append([_box(Vector3(0.035, 0.11, 0.004)), Vector3(0, 0.12, s * 0.101), Vector3.ZERO, white])
			parts.append([_box(Vector3(0.34, 0.008, 0.012)), Vector3(0, 0.268, 0), Vector3.ZERO, Color(0.15, 0.15, 0.15)])
			parts.append([_box(Vector3(0.16, 0.012, 0.03)), Vector3(0, 0.29, 0), Vector3.ZERO, Color(0.12, 0.12, 0.12)])
		"drink":
			# Energy drink can on its side.
			parts.append([_cyl(0.033, 0.12, -1.0, 18), Vector3(0, 0.033, 0), Vector3(0, 0.6, PI / 2), Color(0.12, 0.42, 0.85), "shiny"])
			parts.append([_cyl(0.0335, 0.04, -1.0, 18), Vector3(0, 0.033, 0), Vector3(0, 0.6, PI / 2), Color(0.95, 0.75, 0.1), "shiny"])
			var tip := Basis.from_euler(Vector3(0, 0.6, PI / 2)) * Vector3(0, 0.063, 0)
			parts.append([_cyl(0.028, 0.008, 0.033, 18), Vector3(0, 0.033, 0) + tip, Vector3(0, 0.6, PI / 2), Color(0.78, 0.8, 0.82), "shiny"])
		_:
			# Painkillers: orange bottle with a white cap and a label.
			parts.append([_cyl(0.028, 0.085, -1.0, 16), Vector3(0, 0.0425, 0), Vector3.ZERO, Color(0.92, 0.5, 0.08), "shiny"])
			parts.append([_cyl(0.03, 0.025, -1.0, 16), Vector3(0, 0.097, 0), Vector3.ZERO, white])
			parts.append([_cyl(0.0285, 0.04, -1.0, 16), Vector3(0, 0.04, 0), Vector3.ZERO, Color(0.95, 0.95, 0.92)])
	return _build(parts)

# ---------------------------------------------------------------- attachments
static func _attach(id: String) -> Mesh:
	var parts := []
	var dark := Color(0.09, 0.095, 0.1)
	var lens := Color(0.12, 0.35, 0.45)
	var Z := Vector3(PI / 2, 0, 0)     # cylinder along Z
	match id:
		"reddot":
			parts.append([_box(Vector3(0.035, 0.012, 0.06)), Vector3(0, 0.006, 0), Vector3.ZERO, dark, "metal"])
			parts.append([_cyl(0.017, 0.045, -1.0, 14), Vector3(0, 0.03, 0), Z, dark, "metal"])
			parts.append([_cyl(0.014, 0.004, -1.0, 14), Vector3(0, 0.03, -0.023), Z, Color(0.7, 0.15, 0.1), "shiny"])
		"holo":
			parts.append([_box(Vector3(0.045, 0.016, 0.09)), Vector3(0, 0.008, 0), Vector3.ZERO, dark, "metal"])
			parts.append([_box(Vector3(0.045, 0.04, 0.006)), Vector3(0, 0.036, -0.035), Vector3.ZERO, dark, "metal"])
			parts.append([_box(Vector3(0.045, 0.04, 0.006)), Vector3(0, 0.036, 0.03), Vector3.ZERO, dark, "metal"])
			parts.append([_box(Vector3(0.006, 0.04, 0.07)), Vector3(0.021, 0.036, 0), Vector3.ZERO, dark, "metal"])
			parts.append([_box(Vector3(0.006, 0.04, 0.07)), Vector3(-0.021, 0.036, 0), Vector3.ZERO, dark, "metal"])
			parts.append([_box(Vector3(0.036, 0.03, 0.003)), Vector3(0, 0.036, -0.03), Vector3.ZERO, lens, "shiny"])
		"x2", "x4", "x8":
			var L: float = {"x2": 0.14, "x4": 0.2, "x8": 0.28}[id]
			var bell: float = {"x2": 0.022, "x4": 0.026, "x8": 0.032}[id]
			parts.append([_cyl(0.015, L * 0.5, -1.0, 16), Vector3(0, bell, 0), Z, dark, "metal"])
			parts.append([_cyl(bell, L * 0.25, 0.015, 16), Vector3(0, bell, -L * 0.37), Z, dark, "metal"])
			parts.append([_cyl(0.02, L * 0.2, 0.015, 16), Vector3(0, bell, L * 0.33), Vector3(-PI / 2, 0, 0), dark, "metal"])
			parts.append([_cyl(bell * 0.85, 0.003, -1.0, 16), Vector3(0, bell, -L * 0.5), Z, lens, "shiny"])
			parts.append([_cyl(0.008, 0.02, -1.0, 8), Vector3(0, bell + 0.017, 0), Vector3.ZERO, dark, "metal"])
			for z in [-0.03, 0.03]:
				parts.append([_box(Vector3(0.03, 0.012, 0.016)), Vector3(0, 0.006, z), Vector3.ZERO, dark, "metal"])
		"suppressor":
			parts.append([_cyl(0.019, 0.2, -1.0, 16), Vector3(0, 0.019, 0), Z, dark, "metal"])
			parts.append([_cyl(0.0195, 0.01, -1.0, 16), Vector3(0, 0.019, -0.06), Z, Color(0.2, 0.2, 0.22), "metal"])
			parts.append([_cyl(0.0195, 0.01, -1.0, 16), Vector3(0, 0.019, 0.06), Z, Color(0.2, 0.2, 0.22), "metal"])
		"compensator":
			parts.append([_cyl(0.014, 0.09, -1.0, 12), Vector3(0, 0.014, 0), Z, dark, "metal"])
			for z in [-0.025, 0.0, 0.025]:
				parts.append([_box(Vector3(0.03, 0.006, 0.008)), Vector3(0, 0.026, z), Vector3.ZERO, Color(0.02, 0.02, 0.02)])
		"ext_mag", "quick_mag", "ext_quick":
			# Curved rifle magazine lying flat; quick-draw ones have a pull tab.
			var n := 4 if id != "quick_mag" else 3
			for i in n:
				parts.append([_box(Vector3(0.07, 0.025, 0.05)), Vector3(i * 0.052, 0.0125, i * i * 0.006), Vector3(0, -i * 0.12, 0), dark, "metal"])
			parts.append([_box(Vector3(0.012, 0.027, 0.04)), Vector3(-0.03, 0.0135, 0), Vector3.ZERO, BRASS, "shiny"])
			if id != "ext_mag":
				parts.append([_box(Vector3(0.02, 0.012, 0.04)), Vector3(n * 0.052 + 0.01, 0.006, n * n * 0.006), Vector3.ZERO, Color(0.75, 0.25, 0.1)])
		"angled":
			parts.append([_box(Vector3(0.03, 0.015, 0.09)), Vector3(0, 0.0075, 0), Vector3.ZERO, dark, "metal"])
			parts.append([_box(Vector3(0.028, 0.06, 0.03)), Vector3(0, 0.03, 0.03), Vector3(0.7, 0, 0), dark])
		_:
			# Vertical grip lying on its side.
			parts.append([_box(Vector3(0.03, 0.015, 0.05)), Vector3(0, 0.017, -0.06), Vector3.ZERO, dark, "metal"])
			parts.append([_cyl(0.017, 0.11, 0.015, 12), Vector3(0, 0.017, 0), Z, dark])
	return _build(parts)

# ---------------------------------------------------------------- grenades
static func _throwable(id: String) -> Mesh:
	var m: Mesh = Grenade.model_mesh(id)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("3d4a2c") if id == "frag" else Color("6f7a6a")
	mat.metallic = 0.3
	mat.roughness = 0.55
	var out := ArrayMesh.new()
	for i in m.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(m, i, Transform3D())
		st.set_material(mat)
		st.commit(out)
	return _grounded(out)

# ---------------------------------------------------------------- gear
static func _gear(kind: String, lvl: int) -> Mesh:
	if kind == "helmet":
		# Upside down would look odd: sitting on its rim, turned a little.
		return _grounded(_retint(HumanModel.gear_mesh("helmet", lvl), Transform3D(Basis.from_euler(Vector3(-0.25, 0, 0.1)), Vector3.ZERO)))
	if kind == "pack":
		# Lying on its back, straps down.
		return _grounded(_retint(HumanModel.gear_mesh("pack", lvl), Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3.ZERO)))
	# Vest: plate carrier lying flat (front up) with mag pouches and straps.
	var col: Color = [Color.WHITE, Color("6b6a52"), Color("4a5236"), Color("2a2c2a")][lvl]
	var parts := []
	parts.append([_box(Vector3(0.34, 0.05, 0.4)), Vector3(0, 0.025, 0), Vector3.ZERO, col])
	parts.append([_box(Vector3(0.36, 0.03, 0.12)), Vector3(0, 0.02, 0.17), Vector3.ZERO, col.darkened(0.12)])      # cummerbund
	for x in [-1.0, 1.0]:
		parts.append([_box(Vector3(0.07, 0.035, 0.14)), Vector3(x * 0.12, 0.03, -0.24), Vector3.ZERO, col.darkened(0.08)])   # shoulder straps
	for i in 3:
		parts.append([_box(Vector3(0.08, 0.05, 0.12)), Vector3((i - 1) * 0.095, 0.075, 0.08), Vector3.ZERO, col.darkened(0.18)])   # mag pouches
		parts.append([_box(Vector3(0.082, 0.012, 0.04)), Vector3((i - 1) * 0.095, 0.1, 0.03), Vector3.ZERO, col.darkened(0.3)])
	if lvl >= 2:
		parts.append([_box(Vector3(0.14, 0.04, 0.08)), Vector3(0.05, 0.065, -0.07), Vector3.ZERO, col.darkened(0.1)])     # admin pouch
		parts.append([_box(Vector3(0.05, 0.004, 0.035)), Vector3(-0.1, 0.052, -0.08), Vector3.ZERO, Color(0.15, 0.15, 0.15)])
	if lvl == 3:
		parts.append([_box(Vector3(0.36, 0.02, 0.06)), Vector3(0, 0.06, -0.15), Vector3.ZERO, col.darkened(0.25)])
	return _build(parts)

## Copy of a vertex-coloured gear mesh with a transform applied (keeps its material).
static func _retint(m: Mesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in m.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(m, i, xf)
		st.set_material(m.surface_get_material(i))
		st.commit(out)
	return out
