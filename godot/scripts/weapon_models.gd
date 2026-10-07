class_name WeaponModels
## Detailed weapon models. Each weapon is built once (parts merged into one
## mesh per material) and shared by everyone holding it.
## Weapon frame: origin at the pistol grip (where the right hand holds it),
## barrel towards -Z, +Y up. Each model also says where the left hand goes
## (`fore`), where the muzzle is and has a separate magazine for reloads.

const POLY := "res://assets/models/weapons/"
const CLASS_DEFAULT := {"ar": "m416", "smg": "ump", "shotgun": "s1897", "sr": "kar98", "dmr": "sks", "lmg": "m249", "pistol": "p92", "crossbow": "crossbow", "melee": "pan"}

static var _cache := {}
static var _mats := {}

static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"metal": m.albedo_color = Color(0.09, 0.09, 0.1); m.metallic = 0.7; m.roughness = 0.38
		"poly": m.albedo_color = Color(0.13, 0.13, 0.13); m.roughness = 0.7
		"tan": m.albedo_color = Color(0.48, 0.41, 0.29); m.roughness = 0.75
		"wood": m.albedo_color = Color(0.36, 0.19, 0.09); m.roughness = 0.55
		"olive": m.albedo_color = Color(0.25, 0.28, 0.18); m.roughness = 0.65
		"glass": m.albedo_color = Color(0.25, 0.05, 0.05); m.metallic = 0.9; m.roughness = 0.05
	_mats[key] = m
	return m

static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

## Cylinder lying along Z.
static func _tube(r: float, length: float, r2 := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r2 < 0.0 else r2
	c.height = length
	c.radial_segments = 10
	c.rings = 1
	return c

## Recipe entries: [material, mesh, position, rotation (euler), is_magazine]
static func _recipe(id: String) -> Dictionary:
	var X := Vector3.ZERO
	var Z90 := Vector3(PI / 2, 0, 0)      # cylinder along Z
	match id:
		"m416":
			return {"fore": Vector3(0, -0.06, -0.32), "muzzle": -0.84, "parts": [
				["metal", _box(0.055, 0.085, 0.42), Vector3(0, 0.035, -0.12), X],          # receiver
				["metal", _box(0.035, 0.016, 0.62), Vector3(0, 0.086, -0.26), X],          # top rail
				["poly", _box(0.064, 0.07, 0.3), Vector3(0, 0.03, -0.46), X],              # handguard
				["metal", _tube(0.012, 0.22), Vector3(0, 0.035, -0.7), Z90],               # barrel
				["metal", _tube(0.019, 0.07), Vector3(0, 0.035, -0.8), Z90],               # muzzle brake
				["metal", _tube(0.016, 0.16), Vector3(0, 0.05, 0.17), Z90],                # buffer tube
				["tan", _box(0.045, 0.11, 0.15), Vector3(0, 0.025, 0.28), X],              # stock
				["poly", _box(0.034, 0.1, 0.045), Vector3(0, -0.045, 0.02), Vector3(0.3, 0, 0)],  # grip
				["poly", _tube(0.017, 0.1), Vector3(0, -0.04, -0.42), X],                  # foregrip
				["metal", _box(0.036, 0.045, 0.07), Vector3(0, 0.115, -0.08), X],          # red dot
				["glass", _box(0.026, 0.026, 0.004), Vector3(0, 0.12, -0.115), X],
				["metal", _box(0.006, 0.03, 0.01), Vector3(0, 0.105, -0.55), X],           # front sight
				["tan", _box(0.03, 0.17, 0.065), Vector3(0, -0.08, -0.16), Vector3(-0.2, 0, 0), true],
			]}
		"akm":
			return {"fore": Vector3(0, -0.05, -0.33), "muzzle": -0.82, "parts": [
				["metal", _box(0.05, 0.08, 0.4), Vector3(0, 0.03, -0.1), X],
				["metal", _box(0.052, 0.02, 0.3), Vector3(0, 0.08, -0.1), X],              # dust cover
				["wood", _box(0.06, 0.065, 0.26), Vector3(0, 0.02, -0.42), X],             # lower handguard
				["wood", _tube(0.017, 0.2), Vector3(0, 0.072, -0.42), Z90],                # upper guard / gas tube
				["metal", _tube(0.011, 0.25), Vector3(0, 0.03, -0.66), Z90],
				["metal", _tube(0.016, 0.05), Vector3(0, 0.03, -0.79), Z90],
				["metal", _box(0.008, 0.05, 0.015), Vector3(0, 0.07, -0.7), X],            # front sight
				["wood", _box(0.042, 0.1, 0.3), Vector3(0, -0.005, 0.22), Vector3(-0.12, 0, 0)],  # stock
				["wood", _box(0.032, 0.1, 0.04), Vector3(0, -0.045, 0.02), Vector3(0.3, 0, 0)],
				["metal", _box(0.028, 0.2, 0.06), Vector3(0, -0.1, -0.17), Vector3(-0.38, 0, 0), true],   # banana mag
			]}
		"groza":
			return {"fore": Vector3(0, -0.06, -0.3), "muzzle": -0.55, "parts": [
				["poly", _box(0.06, 0.12, 0.62), Vector3(0, 0.02, 0.0), X],                # bullpup body
				["poly", _box(0.05, 0.05, 0.22), Vector3(0, 0.07, -0.3), X],
				["metal", _tube(0.012, 0.2), Vector3(0, 0.03, -0.42), Z90],
				["metal", _tube(0.02, 0.06), Vector3(0, 0.03, -0.53), Z90],
				["metal", _box(0.034, 0.045, 0.06), Vector3(0, 0.11, -0.12), X],
				["poly", _box(0.032, 0.1, 0.04), Vector3(0, -0.07, 0.0), Vector3(0.25, 0, 0)],
				["poly", _box(0.034, 0.08, 0.04), Vector3(0, -0.07, -0.26), X],
				["metal", _box(0.028, 0.18, 0.06), Vector3(0, -0.1, 0.17), Vector3(-0.3, 0, 0), true],
			]}
		"ump":
			return {"fore": Vector3(0, -0.07, -0.3), "muzzle": -0.5, "parts": [
				["poly", _box(0.06, 0.1, 0.42), Vector3(0, 0.02, -0.15), X],
				["metal", _box(0.03, 0.012, 0.3), Vector3(0, 0.077, -0.15), X],
				["metal", _tube(0.013, 0.1), Vector3(0, 0.03, -0.41), Z90],
				["metal", _tube(0.018, 0.04), Vector3(0, 0.03, -0.47), Z90],
				["poly", _box(0.03, 0.1, 0.04), Vector3(0, -0.05, 0.02), Vector3(0.25, 0, 0)],
				["poly", _box(0.03, 0.03, 0.22), Vector3(0, 0.03, 0.15), X],               # folding stock
				["poly", _box(0.03, 0.09, 0.02), Vector3(0, 0.0, 0.26), X],
				["metal", _box(0.034, 0.04, 0.06), Vector3(0, 0.1, -0.1), X],
				["poly", _box(0.03, 0.17, 0.05), Vector3(0, -0.1, -0.15), Vector3(-0.1, 0, 0), true],
			]}
		"s1897":
			return {"fore": Vector3(0, -0.04, -0.36), "muzzle": -0.92, "parts": [
				["metal", _box(0.05, 0.08, 0.2), Vector3(0, 0.03, -0.06), X],
				["metal", _tube(0.014, 0.75), Vector3(0, 0.05, -0.53), Z90],                # barrel
				["metal", _tube(0.012, 0.6), Vector3(0, 0.015, -0.46), Z90],                # magazine tube
				["wood", _tube(0.022, 0.18), Vector3(0, 0.012, -0.42), Z90],                # pump
				["wood", _box(0.042, 0.11, 0.34), Vector3(0, -0.02, 0.22), Vector3(-0.15, 0, 0)],
				["metal", _box(0.01, 0.01, 0.01), Vector3(0, 0.068, -0.88), X],
				["metal", _box(0.01, 0.01, 0.01), Vector3(0, -0.02, -0.1), X, true],
			]}
		"m249":
			return {"fore": Vector3(0, -0.05, -0.36), "muzzle": -0.98, "parts": [
				["metal", _box(0.08, 0.12, 0.5), Vector3(0, 0.03, -0.1), X],
				["metal", _box(0.07, 0.03, 0.26), Vector3(0, 0.1, -0.05), X],               # feed cover
				["poly", _box(0.07, 0.07, 0.24), Vector3(0, 0.02, -0.46), X],               # handguard
				["metal", _tube(0.014, 0.4), Vector3(0, 0.035, -0.75), Z90],
				["metal", _tube(0.02, 0.06), Vector3(0, 0.035, -0.95), Z90],
				["metal", _box(0.014, 0.05, 0.12), Vector3(0, 0.15, -0.3), X],              # carry handle
				["metal", _tube(0.008, 0.3), Vector3(0.03, -0.12, -0.72), Vector3(0.6, 0, 0.25)],   # bipod legs
				["metal", _tube(0.008, 0.3), Vector3(-0.03, -0.12, -0.72), Vector3(0.6, 0, -0.25)],
				["poly", _box(0.05, 0.12, 0.26), Vector3(0, 0.0, 0.3), X],
				["poly", _box(0.034, 0.1, 0.045), Vector3(0, -0.05, 0.03), Vector3(0.3, 0, 0)],
				["olive", _box(0.09, 0.13, 0.12), Vector3(-0.06, -0.08, -0.1), X, true],    # ammo box
			]}
		"vector":
			# Kriss Vector: tall angular receiver, short barrel shroud, folding stock.
			return {"fore": Vector3(0, -0.08, -0.25), "muzzle": -0.46, "parts": [
				["poly", _box(0.058, 0.14, 0.34), Vector3(0, 0.0, -0.12), X],
				["poly", _box(0.05, 0.06, 0.12), Vector3(0, -0.07, -0.22), Vector3(0.6, 0, 0)],    # slanted front
				["metal", _box(0.03, 0.014, 0.3), Vector3(0, 0.077, -0.14), X],
				["metal", _tube(0.017, 0.13), Vector3(0, 0.03, -0.38), Z90],
				["poly", _box(0.03, 0.1, 0.04), Vector3(0, -0.06, 0.02), Vector3(0.2, 0, 0)],
				["poly", _box(0.026, 0.026, 0.22), Vector3(0, 0.04, 0.16), X],
				["poly", _box(0.03, 0.09, 0.02), Vector3(0, 0.01, 0.27), X],
				["metal", _box(0.034, 0.04, 0.06), Vector3(0, 0.1, -0.1), X],
				["poly", _box(0.026, 0.14, 0.04), Vector3(0, -0.13, -0.06), Vector3(-0.05, 0, 0), true],
			]}
		"uzi":
			return {"fore": Vector3(0, -0.04, -0.2), "muzzle": -0.3, "parts": [
				["metal", _box(0.05, 0.08, 0.3), Vector3(0, 0.02, -0.08), X],
				["metal", _tube(0.012, 0.08), Vector3(0, 0.02, -0.26), Z90],
				["metal", _box(0.02, 0.02, 0.18), Vector3(0, 0.035, 0.12), X],             # wire stock
				["metal", _box(0.02, 0.07, 0.02), Vector3(0, 0.0, 0.21), X],
				["metal", _box(0.032, 0.03, 0.03), Vector3(0, 0.07, -0.18), X],
				["poly", _box(0.034, 0.12, 0.045), Vector3(0, -0.07, 0.0), Vector3(0.1, 0, 0)],
				["metal", _box(0.026, 0.12, 0.035), Vector3(0, -0.15, 0.005), Vector3(0.1, 0, 0), true],   # mag in the grip
			]}
		"scar":
			return {"fore": Vector3(0, -0.06, -0.33), "muzzle": -0.82, "parts": [
				["tan", _box(0.058, 0.09, 0.44), Vector3(0, 0.035, -0.14), X],
				["metal", _box(0.034, 0.016, 0.6), Vector3(0, 0.088, -0.25), X],
				["tan", _box(0.066, 0.07, 0.26), Vector3(0, 0.03, -0.46), X],
				["metal", _tube(0.012, 0.22), Vector3(0, 0.035, -0.68), Z90],
				["metal", _tube(0.02, 0.07), Vector3(0, 0.035, -0.79), Z90],
				["tan", _box(0.05, 0.1, 0.24), Vector3(0, 0.03, 0.24), X],                  # folding stock
				["poly", _box(0.034, 0.1, 0.045), Vector3(0, -0.045, 0.02), Vector3(0.3, 0, 0)],
				["metal", _box(0.006, 0.03, 0.01), Vector3(0, 0.106, -0.52), X],
				["metal", _box(0.03, 0.16, 0.06), Vector3(0, -0.08, -0.17), Vector3(-0.15, 0, 0), true],
			]}
		"beryl":
			return {"fore": Vector3(0, -0.05, -0.33), "muzzle": -0.8, "parts": [
				["metal", _box(0.05, 0.08, 0.4), Vector3(0, 0.03, -0.1), X],
				["metal", _box(0.034, 0.014, 0.5), Vector3(0, 0.08, -0.2), X],              # rail
				["poly", _box(0.062, 0.07, 0.26), Vector3(0, 0.025, -0.42), X],
				["metal", _tube(0.012, 0.22), Vector3(0, 0.03, -0.65), Z90],
				["metal", _tube(0.018, 0.06), Vector3(0, 0.03, -0.77), Z90],
				["poly", _box(0.04, 0.1, 0.28), Vector3(0, 0.0, 0.22), Vector3(-0.1, 0, 0)],
				["poly", _box(0.032, 0.1, 0.04), Vector3(0, -0.045, 0.02), Vector3(0.3, 0, 0)],
				["poly", _box(0.03, 0.2, 0.06), Vector3(0, -0.1, -0.17), Vector3(-0.38, 0, 0), true],
			]}
		"sks":
			return {"fore": Vector3(0, -0.04, -0.38), "muzzle": -0.95, "parts": [
				["metal", _box(0.045, 0.06, 0.32), Vector3(0, 0.035, -0.08), X],
				["wood", _box(0.05, 0.06, 0.48), Vector3(0, -0.0, -0.36), X],               # fore-end
				["wood", _box(0.045, 0.12, 0.36), Vector3(0, -0.03, 0.22), Vector3(-0.14, 0, 0)],
				["metal", _tube(0.012, 0.4), Vector3(0, 0.04, -0.72), Z90],
				["metal", _tube(0.015, 0.05), Vector3(0, 0.04, -0.93), Z90],
				["metal", _box(0.008, 0.04, 0.015), Vector3(0, 0.07, -0.86), X],
				["metal", _box(0.03, 0.12, 0.08), Vector3(0, -0.06, -0.12), X, true],
			]}
		"mini14":
			return {"fore": Vector3(0, -0.04, -0.36), "muzzle": -0.9, "parts": [
				["metal", _box(0.045, 0.06, 0.3), Vector3(0, 0.035, -0.08), X],
				["wood", _box(0.052, 0.06, 0.4), Vector3(0, 0.0, -0.34), X],
				["wood", _box(0.045, 0.11, 0.36), Vector3(0, -0.03, 0.22), Vector3(-0.12, 0, 0)],
				["metal", _tube(0.012, 0.36), Vector3(0, 0.04, -0.7), Z90],
				["metal", _tube(0.017, 0.05), Vector3(0, 0.04, -0.88), Z90],
				["metal", _box(0.034, 0.04, 0.06), Vector3(0, 0.09, -0.06), X],
				["metal", _box(0.028, 0.13, 0.05), Vector3(0, -0.06, -0.1), Vector3(-0.15, 0, 0), true],
			]}
		"crossbow":
			# Stock with a bow across the front and the string pulled back.
			return {"fore": Vector3(0, -0.05, -0.3), "muzzle": -0.62, "parts": [
				["olive", _box(0.05, 0.07, 0.62), Vector3(0, 0.02, -0.2), X],
				["olive", _box(0.045, 0.1, 0.2), Vector3(0, 0.0, 0.24), Vector3(-0.12, 0, 0)],
				["poly", _box(0.032, 0.1, 0.04), Vector3(0, -0.05, 0.02), Vector3(0.3, 0, 0)],
				["metal", _box(0.62, 0.025, 0.04), Vector3(0, 0.03, -0.5), X],             # limbs
				["metal", _box(0.12, 0.025, 0.04), Vector3(-0.33, 0.03, -0.47), Vector3(0, 0.35, 0)],
				["metal", _box(0.12, 0.025, 0.04), Vector3(0.33, 0.03, -0.47), Vector3(0, -0.35, 0)],
				["poly", _tube(0.003, 0.5), Vector3(-0.19, 0.04, -0.33), Vector3(PI / 2, -0.75, 0)],   # string
				["poly", _tube(0.003, 0.5), Vector3(0.19, 0.04, -0.33), Vector3(PI / 2, 0.75, 0)],
				["metal", _box(0.034, 0.045, 0.07), Vector3(0, 0.08, -0.05), X],
				["tan", _tube(0.006, 0.42), Vector3(0, 0.065, -0.4), Z90, true],                # the bolt
			]}
		"pan":
			# Frying pan, held by the handle (the grip is the hand).
			return {"fore": Vector3(0, -0.02, -0.05), "muzzle": -0.45, "parts": [
				["metal", _tube(0.13, 0.03), Vector3(0, 0.0, -0.36), X],                    # pan, flat side up
				["metal", _tube(0.14, 0.05, 0.12), Vector3(0, 0.02, -0.36), X],
				["wood", _box(0.03, 0.025, 0.24), Vector3(0, 0.005, -0.08), X],
				["metal", _box(0.01, 0.01, 0.01), Vector3(0, 0.0, 0.0), X, true],
			]}
	return {}

## Imported Poly Haven models: [scene, hidden node name parts, transform into the weapon frame, fore, muzzle]
static func _imported(id: String) -> Array:
	match id:
		"kar98", "awm":
			# Barrel along +X, butt at -X, trigger near x = -0.29.
			return [POLY + "bolt_action_rifle_7_62/bolt_action_rifle_7_62.gltf", ["bullet"],
				Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, -0.01, -0.24)), Vector3(0, -0.06, -0.36), -0.86, "bolt_action_rifle_7_62_scope"]
		"akm":
			# Fab AK-47: barrel towards +Z (turned round), butt at z = -0.37, pistol grip near z = -0.04.
			return ["res://assets/models/weapons/ak47/ak47.glb", [],
				Transform3D(Basis(Vector3.UP, PI), Vector3(-0.013, 0.0, -0.036)), Vector3(0, -0.05, -0.27), -0.56, ""]
		"mp44":
			# Fab MP44 (centimetres): butt at z = +0.37 m, muzzle at -0.57 m.
			return ["res://assets/models/weapons/mp44/mp44.glb", [],
				Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.025), Vector3(0.002, -0.025, -0.07)), Vector3(0, -0.05, -0.3), -0.64, ""]
		"p92":
			return [POLY + "service_pistol/service_pistol.gltf", ["_b", "magazine", "bullet"],
				Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 0.02, -0.03)), Vector3(0, -0.05, 0.0), -0.2, ""]
	return []

## Builds a weapon: returns a Node3D with meta "fore" (left hand), "muzzle"
## (z of the muzzle) and child "Mag" (moved during reloads).
static func build(id_or_cls: String) -> Node3D:
	var id := id_or_cls
	if not Game.WEAPONS.has(id): id = CLASS_DEFAULT.get(id_or_cls, "m416")
	var root := Node3D.new()
	root.name = "Weapon_" + id
	var imp := _imported(id)
	if not imp.is_empty():
		var sc: Node3D = load(imp[0]).instantiate()
		sc.transform = imp[2]
		root.add_child(sc)
		for c in sc.get_children():
			for hide in imp[1]:
				if String(c.name).contains(hide): c.visible = false
		var mag := Node3D.new()
		mag.name = "Mag"
		mag.position = Vector3(0, -0.05, -0.12)
		root.add_child(mag)
		root.set_meta("fore", imp[3])
		root.set_meta("muzzle", imp[4])
		return root
	var data: Dictionary = _cache.get(id, {})
	if data.is_empty():
		data = _merge(_recipe(id))
		_cache[id] = data
	var body := MeshInstance3D.new()
	body.mesh = data.body
	root.add_child(body)
	var mag_mi := MeshInstance3D.new()
	mag_mi.name = "Mag"
	mag_mi.mesh = data.mag
	root.add_child(mag_mi)
	root.set_meta("fore", data.fore)
	root.set_meta("muzzle", data.muzzle)
	return root

## Merges a recipe into one ArrayMesh with a surface per material (fewer draw calls).
static func _merge(r: Dictionary) -> Dictionary:
	var by_mat := {}
	var mag_st := SurfaceTool.new()
	mag_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mag_mat := "metal"
	for p in r.parts:
		var xf := Transform3D(Basis.from_euler(p[3]), p[2])
		var mesh: Mesh = p[1]
		if p.size() > 4 and p[4]:
			mag_st.append_from(mesh, 0, xf)
			mag_mat = p[0]
			continue
		if not by_mat.has(p[0]):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_mat[p[0]] = st
		by_mat[p[0]].append_from(mesh, 0, xf)
	var body := ArrayMesh.new()
	for k in by_mat:
		var st: SurfaceTool = by_mat[k]
		st.set_material(_mat(k))
		st.commit(body)
	mag_st.set_material(_mat(mag_mat))
	return {"body": body, "mag": mag_st.commit(), "fore": r.fore, "muzzle": r.muzzle}
