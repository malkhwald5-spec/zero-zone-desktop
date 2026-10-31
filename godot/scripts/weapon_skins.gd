class_name WeaponSkins
## Weapon skins: a colour scheme laid over any gun (see weapon_skin.gdshader),
## bought with gold in the shop and worn on all your guns.

## id: [name, price in gold, kind, c1, c2, c3, glow]
const SKINS := {
	"neon": ["نيون الليل", 900, 0, Color("7a35f0"), Color("2a8cff"), Color("ff4fb4"), 1.2],
	"gold": ["الذهبي", 1500, 1, Color("e8b84a"), Color.BLACK, Color.BLACK, 0.0],
	"desert": ["تمويه صحراوي", 400, 2, Color("c9a46a"), Color("8a6a3e"), Color("5a4a32"), 0.0],
	"snow": ["تمويه ثلجي", 400, 2, Color("e6e9ec"), Color("8a9298"), Color("3c4248"), 0.0],
	"dragon": ["التنين الأحمر", 1200, 3, Color("141416"), Color("b0191e"), Color("ff6a1a"), 2.0],
	"carbon": ["كربون", 600, 4, Color("17181b"), Color("3a3d44"), Color.BLACK, 0.0],
}

static var _mats := {}

static func material(id: String) -> ShaderMaterial:
	if _mats.has(id): return _mats[id]
	var d: Array = SKINS[id]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/weapon_skin.gdshader")
	m.set_shader_parameter("kind", d[2])
	m.set_shader_parameter("c1", d[3])
	m.set_shader_parameter("c2", d[4])
	m.set_shader_parameter("c3", d[5])
	m.set_shader_parameter("glow", d[6])
	_mats[id] = m
	return m

## Puts the skin on every mesh of a built weapon ("" takes it off).
static func apply(weapon: Node, id: String) -> void:
	if weapon == null: return
	for n in weapon.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if id == "" or not SKINS.has(id):
			mi.material_overlay = null
			continue
		# Parts imported in other units: the pattern is worked out in metres.
		var xf := Transform3D()
		var up: Node = mi
		while up != weapon and up is Node3D:
			xf = (up as Node3D).transform * xf
			up = up.get_parent()
		var s := xf.basis.get_scale().x
		var m := material(id)
		if absf(s - 1.0) > 0.05 and s > 0.0:
			m = m.duplicate() as ShaderMaterial
			m.set_shader_parameter("scale", s)
		mi.material_overlay = m

## A swatch of the skin for the shop (a little gradient picture).
static func swatch(id: String) -> GradientTexture2D:
	var d: Array = SKINS[id]
	var g := Gradient.new()
	g.set_color(0, d[3])
	g.set_color(1, d[4] if d[2] != 1 else (d[3] as Color).darkened(0.35))
	if d[2] in [0, 2, 3]: g.add_point(0.6, d[5])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 96
	t.height = 48
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 1)
	return t
