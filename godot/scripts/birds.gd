class_name Birds
extends Node3D
## Birds that burst out of the trees and fly away when there is shooting or an
## explosion nearby (only near the camera). Each tree area rests for a while
## after its birds have gone.

var world: Node
var _grid := {}                 # Vector2i (64 m cell) -> Array of tree indices
var _rested := {}               # cell -> time its birds can come back
var _flocks: Array = []         # {birds: [Node3D], vel: [Vector3], t}
var _body_mesh: Mesh
var _wing_mesh: Mesh
const CELL := 64.0
const HEAR := 90.0              # trees this close to a shot lose their birds
const VIEW := 260.0             # only shots this close to the camera
const LIFE := 14.0

func setup(w: Node) -> void:
	world = w
	var trees: Array = w.island.trees
	for i in trees.size():
		var c := Vector2i(floori(trees[i].pos.x / CELL), floori(trees[i].pos.y / CELL))
		if not _grid.has(c): _grid[c] = []
		_grid[c].append(i)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.12, 0.12)
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := CapsuleMesh.new()
	body.radius = 0.05
	body.height = 0.26
	body.radial_segments = 6
	body.rings = 2
	body.material = mat
	_body_mesh = body
	# A wing: a thin swept triangle, root at the origin, tip out along +X.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for v in [Vector3(0, 0, -0.06), Vector3(0.26, 0, 0.05), Vector3(0, 0, 0.07)]:
		st.add_vertex(v)
	st.set_material(mat)
	_wing_mesh = st.commit()

## A shot or blast at `pos`: the nearest wooded spot nearby loses its birds.
func on_noise(pos: Vector3) -> void:
	if world == null or world.view_position().distance_to(pos) > VIEW: return
	var now: float = world.time
	var p2 := Vector2(pos.x, pos.z)
	var cc := Vector2i(floori(p2.x / CELL), floori(p2.y / CELL))
	var trees: Array = world.island.trees
	var spawned := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := cc + Vector2i(dx, dz)
			if not _grid.has(c) or float(_rested.get(c, 0.0)) > now: continue
			var idx: Array = _grid[c]
			if idx.size() < 3: continue     # a lone tree has no flock
			var t: Dictionary = trees[idx[randi() % idx.size()]]
			if Vector2(t.pos).distance_to(p2) > HEAR: continue
			_rested[c] = now + 60.0
			var top := Vector3(t.pos.x, world.island.height_at(t.pos.x, t.pos.y) + float(t.get("h", 8.0)) * 0.85, t.pos.y)
			_flock(top, top - pos)
			spawned += 1
			if spawned >= 2: break
		if spawned >= 2: break
	# The whole area has gone quiet: more shots here scare no more birds for a while.
	if spawned > 0:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				_rested[cc + Vector2i(dx, dz)] = now + 60.0

func _flock(at: Vector3, away: Vector3) -> void:
	var dir := Vector3(away.x, 0, away.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var f := {"birds": [], "vel": [], "t": 0.0}
	for i in randi_range(6, 12):
		var b := Node3D.new()
		add_child(b)
		b.global_position = at + Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
		var body := MeshInstance3D.new()
		body.mesh = _body_mesh
		body.rotation.x = PI / 2
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(body)
		for side in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			w.mesh = _wing_mesh
			w.scale = Vector3(side, 1, 1)
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.add_child(w)
		b.set_meta("phase", randf() * TAU)
		b.set_meta("rate", randf_range(16.0, 22.0))
		var d := dir.rotated(Vector3.UP, randf_range(-0.5, 0.5))
		f.birds.append(b)
		f.vel.append(d * randf_range(6.0, 9.0) + Vector3(0, randf_range(3.5, 6.0), 0))
	_flocks.append(f)

func _process(delta: float) -> void:
	for f in _flocks:
		f.t += delta
		for i in f.birds.size():
			var b: Node3D = f.birds[i]
			var v: Vector3 = f.vel[i]
			# Climb hard at first, then level out and glide on, weaving a little.
			v.y = move_toward(v.y, 1.0, delta * 1.5)
			v = v.rotated(Vector3.UP, sin(f.t * 1.3 + i) * delta * 0.4)
			f.vel[i] = v
			b.global_position += v * delta
			b.look_at(b.global_position + v, Vector3.UP)
			var flap := sin(f.t * float(b.get_meta("rate")) + float(b.get_meta("phase")))
			if v.y < 1.6 and fmod(f.t + i * 0.3, 2.4) > 1.5: flap = 0.15     # glide now and then
			b.get_child(1).rotation.z = flap * 0.9
			b.get_child(2).rotation.z = -flap * 0.9
	var gone := _flocks.filter(func(f): return f.t > LIFE)
	for f in gone:
		for b in f.birds: b.queue_free()
	_flocks = _flocks.filter(func(f): return f.t <= LIFE)

func flock_count() -> int:
	return _flocks.size()
