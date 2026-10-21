class_name PlaneModel
## The transport plane (Lockheed AC-130 model by helijah, CC-BY) in the game's
## own livery: dark two-tone grey-olive, the national markings taken off,
## "ZERO ZONE" on the sides and an orange band on the fins. Faces -Z.

const LIVERY := "res://assets/models/air/plane_livery.jpg"

static func make() -> Node3D:
	var plane: Node3D = (load("res://assets/models/air/plane.glb") as PackedScene).instantiate()
	var tex: Texture2D = load(LIVERY)
	for mi in plane.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s) as StandardMaterial3D
			if src == null or src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
			var mat := src.duplicate() as StandardMaterial3D
			mat.albedo_texture = tex
			mat.metallic = 0.35
			mat.roughness = 0.55
			mat.metallic_specular = 0.6
			m.set_surface_override_material(s, mat)
	return plane
