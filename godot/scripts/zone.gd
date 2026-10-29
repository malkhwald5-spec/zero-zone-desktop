class_name Zone
extends Node3D
## The safe zone: a play area that waits, then shrinks towards a smaller
## circle inside it, phase after phase. Anyone outside takes damage every
## second, more in later phases. Outside it the island turns on you with the
## disaster of that region (DISASTERS): fire and ash by the volcano, a
## snowstorm in the north, a sandstorm in the desert, a rain storm elsewhere.

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

## Region -> [name, screen tint, particle colour, particle size, fall speed, fog colour].
const DISASTERS := {
	"volcano": ["حمم ورماد", Color(1.0, 0.3, 0.05, 0.22), Color(1.0, 0.45, 0.1, 0.95), 0.07, -1.2, Color(0.45, 0.22, 0.12)],
	"nordic": ["عاصفة ثلجية", Color(0.85, 0.92, 1.0, 0.3), Color(1, 1, 1, 0.95), 0.07, 4.0, Color(0.88, 0.92, 0.97)],
	"desert": ["عاصفة رملية", Color(0.8, 0.6, 0.32, 0.32), Color(0.86, 0.68, 0.4, 0.8), 0.07, 0.6, Color(0.78, 0.6, 0.38)],
	"storm": ["عاصفة", Color(0.12, 0.18, 0.32, 0.25), Color(0.75, 0.82, 0.95, 0.6), 0.03, 18.0, Color(0.35, 0.4, 0.48)],
}

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
var rng := RandomNumberGenerator.new()   # online: seeded alike everywhere, so every game picks the same circles
var _from_center := Vector2.ZERO
var _from_radius := 0.0
var _wall: MeshInstance3D
var _mat: ShaderMaterial
var _fx: CPUParticles3D           # snow, sand, ash or rain round the player outside the zone
var _fx_kind := ""
var _fog_base := -1.0
var _fog_col := Color.WHITE
var _fog_k := 0.0

func setup(w: Node) -> void:
	world = w
	rng.seed = Net.match_seed if Net.in_match else randi()
	var s: float = world.island.size
	center = Vector2(s * 0.5, s * 0.5)
	radius = s * (0.5 if world.quick() else 0.72)
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
	_mat.set_shader_parameter("biomemap", world.builder.biome_tex)
	_mat.set_shader_parameter("noise_a", world.builder.noise_a)
	_mat.set_shader_parameter("map_size", s)
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
	time_left = ph[0] * _time_k()
	dps = ph[3]
	_from_center = center
	_from_radius = radius
	next_radius = float(ph[2]) * world.island.size
	next_center = _pick_center(center, radius, next_radius)
	if world.hud: world.hud.show_banner("تم تحديد المنطقة الآمنة الجديدة — الجزيرة عم تنقلب برّاها، توجّه إليها!")

## A new centre inside the current circle, preferring dry land.
func _pick_center(c: Vector2, r: float, nr: float) -> Vector2:
	var best := c
	for k in 40:
		var p := c + Vector2(rng.randf() * (r - nr) * 0.95, 0).rotated(rng.randf() * TAU)
		if world.island.is_land(p.x, p.y) and not world.island.is_deep(p.x, p.y):
			return p
		best = p
	return c if nr > r * 0.5 else best

func _process(delta: float) -> void:
	_disaster_fx(delta)
	if state == "idle" or state == "done":
		_update_wall()
		return
	time_left -= delta * speed
	if state == "wait":
		if time_left <= 0.0:
			state = "shrink"
			time_left = PHASES[phase][1] * _time_k()
			if world.hud: world.hud.show_banner("الكارثة عم تقرّب — المنطقة الآمنة عم تصغر!")
	elif state == "shrink":
		var dur: float = PHASES[phase][1] * _time_k()
		var k := clampf(1.0 - time_left / dur, 0.0, 1.0)
		center = _from_center.lerp(next_center, k)
		radius = lerpf(_from_radius, next_radius, k)
		if time_left <= 0.0:
			center = next_center
			radius = next_radius
			_begin_phase(phase + 1)
	_update_wall()

## The big map gives everyone a bit longer to reach each circle.
func _time_k() -> float:
	return clampf(world.island.size / 4096.0, 1.0, 1.35) * (0.45 if world.quick() else 1.0)

func _update_wall() -> void:
	_wall.position = Vector3(center.x, 300.0, center.y)
	_wall.scale = Vector3(maxf(radius, 0.5), 1400.0, maxf(radius, 0.5))

## Which disaster rages at p (a DISASTERS key).
func disaster_at(p: Vector3) -> String:
	var r: String = world.island.region_at(p.x, p.z)
	return r if DISASTERS.has(r) else "storm"

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

## Outside the zone the player is in the disaster: its particles blowing round
## the camera, thicker fog, and (in the HUD) its colour over the screen.
func _disaster_fx(delta: float) -> void:
	var p: Node3D = world.player
	if p == null: return
	var out: bool = state != "idle" and p.state in ["ground", "vehicle"] and is_outside(p.global_position)
	var kind := disaster_at(p.global_position) if out else ""
	if out and kind != _fx_kind:
		_make_fx(kind)
	if _fx:
		_fx.emitting = out
		var cam: Camera3D = p.get("camera")
		if cam: _fx.global_position = cam.global_position
	var env: Environment = world.builder.env
	if env:
		if _fog_base < 0.0:
			_fog_base = env.fog_density
			_fog_col = env.fog_light_color
		_fog_k = move_toward(_fog_k, 1.0 if out else 0.0, delta * 0.6)
		if _fx_kind != "":
			var extra: float = {"nordic": 0.03, "desert": 0.025, "volcano": 0.012, "storm": 0.008}[_fx_kind]
			env.fog_density = _fog_base + extra * _fog_k
			env.fog_light_color = _fog_col.lerp(DISASTERS[_fx_kind][5], _fog_k)

func _make_fx(kind: String) -> void:
	_fx_kind = kind
	var d: Array = DISASTERS[kind]
	if _fx == null:
		_fx = CPUParticles3D.new()
		_fx.amount = 260
		_fx.lifetime = 1.6
		_fx.local_coords = false
		_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_fx.emission_box_extents = Vector3(7, 4, 7)
		add_child(_fx)
	var q := QuadMesh.new()
	q.size = Vector2.ONE * float(d[3]) * (Vector2(1, 14) if kind == "storm" else Vector2.ONE)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if kind != "storm" else BaseMaterial3D.BILLBOARD_FIXED_Y
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = d[2]
	if kind != "storm":
		# Soft round flakes and sparks, not squares.
		var dot := GradientTexture2D.new()
		dot.fill = GradientTexture2D.FILL_RADIAL
		dot.fill_from = Vector2(0.5, 0.5)
		dot.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		dot.gradient = g
		m.albedo_texture = dot
	if kind == "volcano":
		m.emission_enabled = true
		m.emission = Color(1.0, 0.45, 0.1)
		m.emission_energy_multiplier = 2.5
	q.material = m
	_fx.mesh = q
	var fall: float = d[4]
	# Wind across, the fall speed of each kind (ash and embers rise).
	_fx.direction = Vector3(1, -signf(fall), 0.3).normalized()
	_fx.spread = 20.0 if kind == "storm" else 45.0
	_fx.gravity = Vector3(0, -fall, 0)
	_fx.initial_velocity_min = 6.0 if kind in ["nordic", "desert"] else 1.0
	_fx.initial_velocity_max = 12.0 if kind in ["nordic", "desert"] else 3.0
	_fx.amount = 900 if kind in ["nordic", "desert"] else 450
