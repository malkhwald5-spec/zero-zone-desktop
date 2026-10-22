class_name TrainingTarget
extends StaticBody3D
## A pop-up target for the training ground: a person-shaped board on a post.
## Falls back flat when shot down; `stand_up()` raises it again.

signal downed(by_aiming: bool)

var health := 100.0
var dead := false
var _pivot: Node3D
var _shape: CollisionShape3D

func _init() -> void:
	collision_layer = 4          # hit by bullets (they look at layers 1 and 3)
	collision_mask = 0
	_pivot = Node3D.new()
	add_child(_pivot)
	var board := StandardMaterial3D.new()
	board.albedo_color = Color("e8e0cf")
	board.roughness = 0.8
	var ring := StandardMaterial3D.new()
	ring.albedo_color = Color("e2572b")
	ring.roughness = 0.7
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 1.15, 0.05)
	body.mesh = bm
	body.material_override = board
	body.position.y = 0.95
	_pivot.add_child(body)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.16
	hm.bottom_radius = 0.16
	hm.height = 0.05
	head.mesh = hm
	head.material_override = board
	head.rotation.x = PI / 2
	head.position.y = 1.68
	_pivot.add_child(head)
	# Orange rings on the chest and the head.
	for at in [[Vector3(0, 1.1, 0.03), 0.16], [Vector3(0, 1.68, 0.03), 0.08]]:
		var r := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = at[1]
		rm.bottom_radius = at[1]
		rm.height = 0.01
		r.mesh = rm
		r.material_override = ring
		r.rotation.x = PI / 2
		r.position = at[0]
		_pivot.add_child(r)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.08, 0.4, 0.08)
	post.mesh = pm
	post.position.y = 0.2
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("3b3f44")
	post.material_override = steel
	add_child(post)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.6, 1.5, 0.25)
	cs.shape = sh
	cs.position.y = 1.1
	add_child(cs)
	_shape = cs

## Shot: falls once its health is gone (a head shot counts double, as for players).
func take_damage(amount: float, attacker: Node, _head := false) -> bool:
	if dead: return false
	health -= amount
	if health > 0.0: return false
	dead = true
	_shape.set_deferred("disabled", true)     # lying flat: shots go over it
	var aiming: bool = attacker != null and "aiming" in attacker and attacker.aiming
	create_tween().tween_property(_pivot, "rotation:x", -PI / 2, 0.25).set_ease(Tween.EASE_IN)
	downed.emit(aiming)
	return true

func stand_up() -> void:
	dead = false
	health = 100.0
	_shape.set_deferred("disabled", false)
	create_tween().tween_property(_pivot, "rotation:x", 0.0, 0.35).set_ease(Tween.EASE_OUT)
