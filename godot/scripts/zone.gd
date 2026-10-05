class_name Zone
extends Node3D
## The blue zone: a play area that waits, then shrinks towards a smaller circle
## inside it, phase after phase. Anyone outside takes damage every second,
## more in later phases. Drawn as a tall translucent blue wall.

## [wait seconds, shrink seconds, next radius as a fraction of the map, damage per second]
const PHASES := [
	[150.0, 110.0, 0.42, 0.6],
	[110.0, 75.0, 0.25, 1.0],
	[90.0, 55.0, 0.14, 2.0],
	[70.0, 40.0, 0.07, 4.0],
	[50.0, 32.0, 0.035, 6.0],
	[40.0, 25.0, 0.012, 9.0],
	[30.0, 20.0, 0.0, 14.0],
]

var world: Node
var center := Vector2.ZERO        # current circle
var radius := 0.0
var next_center := Vector2.ZERO   # circle it is shrinking towards
var next_radius := 0.0
var phase := -1                   # -1 = not started yet
var state := "idle"               # idle | wait | shrink | done
var time_left := 0.0
var dps := 0.5
var speed := 1.0                  # tests can speed the zone up
var _from_center := Vector2.ZERO
var _from_radius := 0.0
var _wall: MeshInstance3D
var _mat: ShaderMaterial

func setup(w: Node) -> void:
	world = w
	var s: float = world.island.size
	center = Vector2(s * 0.5, s * 0.5)
	radius = s * 0.72
	next_center = center
	next_radius = radius
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 128
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/zone.gdshader")
	_wall = MeshInstance3D.new()
	_wall.mesh = cyl
	_wall.material_override = _mat
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.extra_cull_margin = 16384.0
	add_child(_wall)
	_update_wall()

## Starts the first phase (called when the plane has flown over the island).
func start() -> void:
	if state != "idle": return
	_begin_phase(0)

func _begin_phase(i: int) -> void:
	phase = i
	if i >= PHASES.size():
		state = "done"
		return
	var ph: Array = PHASES[i]
	state = "wait"
	time_left = ph[0]
	dps = ph[3]
	_from_center = center
	_from_radius = radius
	next_radius = float(ph[2]) * world.island.size
	next_center = _pick_center(center, radius, next_radius)
	if world.hud: world.hud.show_banner("تم تحديد المنطقة الآمنة الجديدة — توجّه إليها!")

## A new centre inside the current circle, preferring dry land.
func _pick_center(c: Vector2, r: float, nr: float) -> Vector2:
	var best := c
	for k in 40:
		var p := c + Vector2(randf() * (r - nr) * 0.95, 0).rotated(randf() * TAU)
		if world.island.is_land(p.x, p.y) and not world.island.is_deep(p.x, p.y):
			return p
		best = p
	return c if nr > r * 0.5 else best

func _process(delta: float) -> void:
	if state == "idle" or state == "done":
		_update_wall()
		return
	time_left -= delta * speed
	if state == "wait":
		if time_left <= 0.0:
			state = "shrink"
			time_left = PHASES[phase][1]
			if world.hud: world.hud.show_banner("المنطقة الآمنة عم تصغر!")
	elif state == "shrink":
		var dur: float = PHASES[phase][1]
		var k := clampf(1.0 - time_left / dur, 0.0, 1.0)
		center = _from_center.lerp(next_center, k)
		radius = lerpf(_from_radius, next_radius, k)
		if time_left <= 0.0:
			center = next_center
			radius = next_radius
			_begin_phase(phase + 1)
	_update_wall()

func _update_wall() -> void:
	_wall.position = Vector3(center.x, 300.0, center.y)
	_wall.scale = Vector3(maxf(radius, 0.5), 1400.0, maxf(radius, 0.5))

func is_outside(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(center) > radius

## Distance from p to the edge of the next safe circle (0 when inside).
func distance_to_safe(p: Vector3) -> float:
	return maxf(0.0, Vector2(p.x, p.z).distance_to(next_center) - next_radius)

## Seconds until the next change, for the HUD.
func label() -> String:
	var t := int(ceil(time_left / speed))
	match state:
		"wait": return "تصغير المنطقة خلال %d:%02d" % [t / 60, t % 60]
		"shrink": return "المنطقة عم تصغر %d:%02d" % [t / 60, t % 60]
		"idle": return "المنطقة الآمنة قريباً"
	return "المنطقة النهائية"
