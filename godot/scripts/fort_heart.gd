class_name FortHeart
extends StaticBody3D
## قلب الحصن: the glowing crystal in the middle of a fort. While it stands,
## the fort's team comes back after dying; break it and they don't. Shots
## and blasts hurt it (see War.hurt_heart); left alone it slowly mends.

var war: Node
var team := 0
var hp := 5000.0
var max_hp := 5000.0
var dead := false
var display_name := ""
var hit_t := 99.0                 # seconds since it was last hurt
var _crystal: MeshInstance3D
var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _t := randf() * 10.0

func _ready() -> void:
	add_to_group("bloodless")
	var col: Color = War.TEAMS[team].col
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.3
	cyl.height = 4.4
	cs.shape = cyl
	cs.position = Vector3(0, 2.2, 0)
	add_child(cs)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = col.lightened(0.2)
	_mat.emission_enabled = true
	_mat.emission = col
	_mat.emission_energy_multiplier = 2.6
	_mat.roughness = 0.15
	_mat.metallic = 0.2
	# A cut gem: an eight-sided double pyramid.
	_crystal = MeshInstance3D.new()
	var gem := SphereMesh.new()
	gem.radial_segments = 8
	gem.rings = 2
	gem.radius = 0.85
	gem.height = 2.8
	_crystal.mesh = gem
	_crystal.material_override = _mat
	_crystal.position = Vector3(0, 2.6, 0)
	add_child(_crystal)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.45
	tm.outer_radius = 1.6
	tm.rings = 32
	_ring.mesh = tm
	_ring.material_override = _mat
	_ring.position = Vector3(0, 2.6, 0)
	add_child(_ring)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 2.2
	_light.omni_range = 28.0
	_light.position = Vector3(0, 3.0, 0)
	add_child(_light)

func take_damage(amount: float, attacker: Node, _head := false) -> bool:
	if dead or war == null: return false
	war.hurt_heart(self, amount, attacker, false)
	return false        # not a kill

func _process(delta: float) -> void:
	_t += delta
	hit_t += delta
	if dead: return
	_crystal.rotation.y = _t * 0.8
	_crystal.position.y = 2.6 + sin(_t * 1.6) * 0.15
	_ring.rotation = Vector3(0.5 + sin(_t * 0.7) * 0.2, _t * -0.5, 0.3)
	# Flickers while under fire, dimmer as it weakens.
	var k := clampf(hp / max_hp, 0.0, 1.0)
	var flick := 0.6 + 0.4 * sin(_t * 40.0) if hit_t < 0.4 else 1.0
	_mat.emission_energy_multiplier = (0.8 + 2.0 * k) * flick
	_light.light_energy = (0.6 + 1.8 * k) * flick

## Broken: the crystal shatters and the light goes out.
func shatter() -> void:
	dead = true
	_crystal.visible = false
	_ring.visible = false
	_light.visible = false
	for c in get_children():
		if c is CollisionShape3D: c.disabled = true
