class_name Airdrop
extends Node3D
## A supply crate: dropped by a cargo plane, floats down under a parachute,
## lands with a column of red smoke and holds rare loot (crate-only weapons,
## level 3 gear, a medkit).

const FALL_SPEED := 7.0

var world: Node
var landed := false
var target := Vector3.ZERO        # landing point on the ground
var _chute: MeshInstance3D
var _body: StaticBody3D

static var _mats := {}

static func _mat(key: String, c: Color, emit := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.6
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emit
		if key == "chute": m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return _mats[key]

func _ready() -> void:
	# Crate: blue box with red bands (easy to spot from far).
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 0.9, 1.0)
	box.mesh = bm
	box.material_override = _mat("crate", Color("2f5fb0"))
	box.position.y = 0.45
	add_child(box)
	for x in [-0.45, 0.45]:
		var band := MeshInstance3D.new()
		var b2 := BoxMesh.new()
		b2.size = Vector3(0.14, 0.92, 1.02)
		band.mesh = b2
		band.material_override = _mat("band", Color("d93030"), 0.4)
		band.position = Vector3(x, 0.45, 0)
		add_child(band)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.3)
	light.light_energy = 1.2
	light.omni_range = 6.0
	light.position.y = 1.4
	add_child(light)
	_chute = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.2
	sm.height = 1.8
	sm.is_hemisphere = true
	sm.radial_segments = 20
	sm.rings = 5
	_chute.mesh = sm
	_chute.material_override = _mat("chute", Color("e8e8e8"))
	_chute.position.y = 6.0
	add_child(_chute)
	_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.4, 0.9, 1.0)
	cs.shape = sh
	cs.position.y = 0.45
	_body.add_child(cs)
	_body.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_body)

func _process(delta: float) -> void:
	if landed: return
	global_position.y -= FALL_SPEED * delta
	rotation.y += delta * 0.3
	if global_position.y <= target.y:
		global_position = target
		_land()

func _land() -> void:
	landed = true
	_chute.visible = false
	_body.process_mode = Node.PROCESS_MODE_INHERIT
	world.effects.smoke_cloud(global_position + Vector3(2.0, 0, 0), 90.0, Color(0.85, 0.15, 0.12))
	# Loot sits on top of the crate.
	var top := global_position + Vector3(0, 0.95, 0)
	var weapon: String = ["awm", "m249", "groza"][randi() % 3]
	world.drop_weapon(weapon, Game.WEAPONS[weapon].mag, top)
	var at: String = Game.WEAPONS[weapon].ammo
	world._add_pickup({"kind": "ammo", "type": at, "amount": 40 if at != "300" else 20}, top + Vector3(0.4, 0, 0.2))
	world._add_gear("vest" if randf() < 0.5 else "helmet", 3, -1.0, top + Vector3(-0.4, 0, -0.2))
	world._add_pickup({"kind": "heal", "id": "medkit", "n": 1}, top + Vector3(0.3, 0, -0.3))
	if randf() < 0.5:
		world._add_pickup({"kind": "throw", "id": "frag", "n": 1}, top + Vector3(-0.3, 0, 0.3))
