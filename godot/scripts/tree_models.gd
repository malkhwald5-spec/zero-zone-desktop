class_name TreeModels
## Close-up tree meshes: a real trunk with branches (bark texture) and crowns
## made of photo leaf cards. Built for a 10 m tall tree; instances scale it.
## Surface 0 = bark, surface 1 = leaves. UV2.x carries ambient occlusion.

static func _tube(st: SurfaceTool, pts: Array, radii: Array, sides := 7) -> void:
	var v := 0.0
	var rings := []
	for i in pts.size():
		var dir: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(dir)
		var ring := []
		for k in sides + 1:
			var a := TAU * k / sides
			var n := side * cos(a) + up * sin(a)
			ring.append([pts[i] + n * radii[i], n, Vector2(float(k) / sides, v)])
		rings.append(ring)
		if i + 1 < pts.size(): v += pts[i].distance_to(pts[i + 1]) / 1.5
	for i in rings.size() - 1:
		for k in sides:
			var a: Array = rings[i][k]
			var b: Array = rings[i][k + 1]
			var c: Array = rings[i + 1][k + 1]
			var d: Array = rings[i + 1][k]
			for q in [a, c, b, a, d, c]:
				st.set_normal(q[1])
				st.set_uv(q[2])
				st.set_uv2(Vector2(1, 0))
				st.add_vertex(q[0])

static func _branch(rng: RandomNumberGenerator, from: Vector3, dir: Vector3, length: float, r0: float) -> Array:
	var pts := []
	var radii := []
	var p := from
	for i in 5:
		pts.append(p)
		radii.append(lerpf(r0, r0 * 0.25, i / 4.0))
		dir = (dir + Vector3(rng.randf_range(-0.15, 0.15), 0.06, rng.randf_range(-0.15, 0.15))).normalized()
		p += dir * length / 4.0
	return [pts, radii]

## One textured card from `base` towards `tip_dir`; `n_fn` gives the lighting normal.
static func _card(st: SurfaceTool, base: Vector3, tip_dir: Vector3, side: Vector3, length: float, width: float,
		centre: Vector3, squash: Vector3, ao_lo: float, ao_hi: float, pine := false) -> void:
	var c := [base - side * width * 0.5, base + side * width * 0.5,
		base + tip_dir * length + side * width * 0.5, base + tip_dir * length - side * width * 0.5]
	# Leaf texture: the twig base is at the bottom (v = 1). Pine texture: trunk at u = 0.
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	if pine:
		uvs = [Vector2(0, 0.95), Vector2(0, 0.0), Vector2(1, 0.0), Vector2(1, 0.95)]
	for i in [0, 1, 2, 0, 2, 3]:
		var p: Vector3 = c[i]
		var rel: Vector3 = (p - centre) / squash
		var n := (rel.normalized() + Vector3.UP * 0.35).normalized()
		var ao := clampf(lerpf(ao_lo, ao_hi, clampf(rel.length(), 0.0, 1.0)) + rel.y * 0.15, 0.25, 1.0)
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.set_uv2(Vector2(ao, 0))
		st.add_vertex(p)

static func broadleaf(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 1.0, rng.randf_range(-0.25, 0.25)).normalized()
	var trunk_top := lean * 5.6
	var tp := []
	var tr := []
	for i in 6:
		var t := i / 5.0
		tp.append(lean * 5.6 * t + Vector3(sin(t * 3.0 + seed) * 0.12, 0, cos(t * 2.0 + seed) * 0.12) - Vector3(0, 0.3, 0) * (1.0 - t))
		tr.append(lerpf(0.34, 0.16, t))
	_tube(bark, tp, tr, 8)
	var centre := trunk_top + Vector3(0, 1.4, 0)
	var squash := Vector3(3.4, 2.9, 3.4)
	var tips := []
	var nb := rng.randi_range(5, 7)
	for k in nb:
		var a := TAU * k / nb + rng.randf_range(-0.3, 0.3)
		var from: Vector3 = tp[rng.randi_range(3, 5)]
		var dir := Vector3(cos(a) * 0.8, rng.randf_range(0.6, 1.0), sin(a) * 0.8).normalized()
		var br := _branch(rng, from, dir, rng.randf_range(2.6, 3.6), 0.12)
		_tube(bark, br[0], br[1], 5)
		tips.append(br[0][3])
		tips.append(br[0][4])
	bark.generate_tangents()
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 110:
		# Points mostly near the crown's surface; twig bases pulled towards branches.
		var d := Vector3(rng.randfn(), rng.randfn() * 0.8, rng.randfn()).normalized()
		var r := pow(rng.randf(), 0.35)
		var p := centre + d * squash * r * 0.9
		var near: Vector3 = tips[rng.randi() % tips.size()]
		var base := p.lerp(near, 0.25)
		var out := (d + Vector3(rng.randf_range(-0.5, 0.5), 0.45, rng.randf_range(-0.5, 0.5))).normalized()
		var side := out.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()).normalized()
		if side.length() < 0.1: side = Vector3.RIGHT
		var size := rng.randf_range(2.0, 2.8)
		_card(leaves, base - out * size * 0.35, out, side, size, size, centre, squash, 0.35, 1.0)
	return _commit([bark, leaves])

static func pine(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tp := []
	var tr := []
	for i in 7:
		var t := i / 6.0
		tp.append(Vector3(sin(t * 4.0 + seed) * 0.06, -0.3 + t * 10.3, cos(t * 3.0 + seed) * 0.06))
		tr.append(lerpf(0.3, 0.03, t))
	_tube(bark, tp, tr, 7)
	bark.generate_tangents()
	var needles := SurfaceTool.new()
	needles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0, 4.5, 0)
	var squash := Vector3(3.0, 6.0, 3.0)
	var whorls := 16
	for w in whorls:
		var f := float(w) / (whorls - 1)
		var y := lerpf(2.0, 9.6, f)
		var length := lerpf(3.3, 0.7, pow(f, 0.85)) * rng.randf_range(0.9, 1.1)
		var n := rng.randi_range(6, 8) if f < 0.8 else 5
		var off := rng.randf() * TAU
		for k in n:
			var a := off + TAU * k / n + rng.randf_range(-0.25, 0.25)
			var droop := rng.randf_range(0.18, 0.42)
			var out := Vector3(cos(a), -droop, sin(a)).normalized()
			var side := Vector3(-sin(a), 0, cos(a)).rotated(out, rng.randf_range(-0.6, 0.6))
			var base := Vector3(0, y, 0)
			_card(needles, base, out, side, length, length * 0.48, centre, squash, 0.3, 1.0, true)
			# A second, shorter spray under it at another tilt fills the branch out.
			var out2 := Vector3(cos(a + 0.3), -droop - 0.25, sin(a + 0.3)).normalized()
			var side2 := Vector3(-sin(a + 0.3), 0, cos(a + 0.3)).rotated(out2, rng.randf_range(0.6, 1.2) * (1 if k % 2 == 0 else -1))
			_card(needles, base + Vector3(0, -0.15, 0), out2, side2, length * 0.8, length * 0.4, centre, squash, 0.25, 0.85, true)
	# Pointed top: two crossed upright cards.
	for k in 2:
		var side := Vector3(1, 0, 0).rotated(Vector3.UP, k * PI * 0.5)
		_card(needles, Vector3(0, 9.0, 0), Vector3.UP, side, 1.6, 0.8, centre, squash, 0.9, 1.0, true)
	return _commit([bark, needles])

static func _commit(sts: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for st in sts:
		st.index()
		st.commit(mesh)
	return mesh
