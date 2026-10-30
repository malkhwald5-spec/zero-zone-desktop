class_name RegionFx
extends Node3D
## What makes each map feel its own around the camera, all the time:
## - Seasons Island: light snow drifting down in the north, embers and ash
##   floating over the volcano land, pollen and leaves in the forest;
## - Dune Valley: fine sand blowing along the ground, and (an event, see
##   MatchEvents) the sandstorm that swallows the whole valley for a minute.

var world: Node
var _p: CPUParticles3D
var _kind := ""
var storm := 0.0            # 0..1 while the Dune Valley sandstorm blows
var _fog_base := -1.0
var _fog_col := Color.WHITE

const LOOKS := {
	# colour, size, gravity, amount, spread box half size
	"snow": [Color(1, 1, 1, 0.9), 0.05, Vector3(0.3, -1.2, 0.1), 220, Vector3(14, 8, 14)],
	"ash": [Color(1.0, 0.5, 0.15, 0.9), 0.035, Vector3(0.2, 0.35, 0.0), 120, Vector3(14, 6, 14)],
	"leaves": [Color(0.75, 0.8, 0.35, 0.8), 0.06, Vector3(0.6, -0.4, 0.2), 50, Vector3(14, 6, 14)],
	"sand": [Color(0.9, 0.75, 0.5, 0.55), 0.05, Vector3(4.0, -0.2, 1.0), 160, Vector3(16, 1.5, 16)],
	"sandstorm": [Color(0.86, 0.68, 0.42, 0.75), 0.18, Vector3(14.0, -0.3, 3.0), 600, Vector3(14, 6, 14)],
}

func setup(w: Node) -> void:
	world = w
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _process(delta: float) -> void:
	var p: Node3D = world.player
	var cam := get_viewport().get_camera_3d()
	if p == null or cam == null or Game.lite(): return
	var want := ""
	var q: Vector3 = p.global_position
	if p.get("state") != "plane":
		if world.island.map_id == "dunes":
			want = "sandstorm" if storm > 0.3 else "sand"
		else:
			match world.island.region_at(q.x, q.z):
				"nordic": want = "snow"
				"volcano": want = "ash"
				"jungle": want = "leaves"
	if p.get("state") == "ground" and world.roofed_at(q) >= 0 and want != "sandstorm": want = ""
	if want != _kind: _make(want)
	if _p:
		_p.global_position = cam.global_position + Vector3(0, -1.0 if _kind == "sand" else 2.0, 0)
	_storm_fog(delta)

func _make(kind: String) -> void:
	_kind = kind
	if _p:
		_p.emitting = false
		_p.queue_free()
		_p = null
	if kind == "": return
	var d: Array = LOOKS[kind]
	_p = CPUParticles3D.new()
	_p.amount = d[3]
	_p.lifetime = 3.0 if kind in ["snow", "ash", "leaves"] else 1.4
	_p.local_coords = false
	_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_p.emission_box_extents = d[4]
	_p.gravity = d[2]
	_p.initial_velocity_min = 0.2
	_p.initial_velocity_max = 1.2
	_p.spread = 180.0
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE * float(d[1]) * (Vector2(3, 1) if kind in ["sand", "sandstorm"] else Vector2.ONE)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = d[0]
	if kind == "ash":
		m.emission_enabled = true
		m.emission = Color(1.0, 0.45, 0.1)
		m.emission_energy_multiplier = 2.0
	qm.material = m
	_p.mesh = qm
	add_child(_p)

## The sandstorm thickens the haze over the whole valley and tints it sand.
func _storm_fog(delta: float) -> void:
	var env: Environment = world.builder.env
	if env == null or world.island.map_id != "dunes": return
	if _fog_base < 0.0:
		_fog_base = env.fog_density
		_fog_col = env.fog_light_color
	if storm <= 0.0 and env.fog_density <= _fog_base + 0.0001: return
	env.fog_enabled = true
	env.fog_density = lerpf(env.fog_density, _fog_base + 0.022 * storm, minf(1.0, delta * 2.0))
	env.fog_light_color = _fog_col.lerp(Color(0.8, 0.62, 0.38), clampf(storm, 0.0, 1.0))
	env.fog_sky_affect = 0.85 * clampf(storm, 0.0, 1.0)
