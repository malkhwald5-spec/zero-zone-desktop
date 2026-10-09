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

## Palm (10 m): a slender curved trunk with rings, a crown of long drooping
## fronds (frond cards, stem at u = 0) and a few coconuts.
static func palm(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.8, 1.8)
	var tp := []
	var tr := []
	for i in 9:
		var t := i / 8.0
		tp.append(Vector3(0, -0.3 + t * 10.0, 0) + bend * t * t)
		tr.append(lerpf(0.26, 0.15, t) * (1.08 if i % 2 == 0 else 1.0))
	_tube(bark, tp, tr, 8)
	var top: Vector3 = tp[-1]
	# Coconuts under the crown.
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf()
		var c := top + Vector3(cos(a) * 0.25, -0.35, sin(a) * 0.25)
		_tube(bark, [c - Vector3(0, 0.12, 0), c, c + Vector3(0, 0.12, 0)], [0.06, 0.13, 0.06], 6)
	bark.generate_tangents()
	var fronds := SurfaceTool.new()
	fronds.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := top
	var squash := Vector3(4.0, 2.0, 4.0)
	var n := rng.randi_range(11, 14)
	for k in n:
		var a := TAU * k / n + rng.randf_range(-0.2, 0.2)
		var up := rng.randf_range(-0.15, 0.55) if k % 3 != 0 else rng.randf_range(0.5, 0.9)
		var out := Vector3(cos(a), up, sin(a)).normalized()
		var side := Vector3(-sin(a), 0, cos(a))
		var length := rng.randf_range(3.6, 4.6)
		# Two segments so the frond arches over and droops at the tip.
		_card(fronds, top, out, side, length * 0.55, length * 0.32, centre, squash, 0.5, 1.0, true)
		var out2 := Vector3(cos(a), up - 0.75, sin(a)).normalized()
		_card(fronds, top + out * length * 0.5, out2, side, length * 0.55, length * 0.3, centre, squash, 0.6, 1.0, true)
	return _commit([bark, fronds])

## Saguaro cactus (built 4 m tall): a ribbed column with two or three arms.
static func cactus(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Saguaro: a ribbed column with a rounded top and arms that bend up.
	var h := rng.randf_range(3.6, 4.4)
	var col := []
	var rad := []
	for i in 9:
		var t := i / 8.0
		col.append(Vector3(0, -0.2 + t * h, 0))
		rad.append(0.3 * (1.0 - 0.12 * t))
	_ribbed(st, col, rad, true)
	for k in rng.randi_range(1, 3):
		var a := rng.randf() * TAU
		var y := rng.randf_range(1.2, h * 0.62)
		var dir := Vector3(cos(a), 0, sin(a))
		var up := rng.randf_range(0.9, 1.6)
		var arm := []
		for i in 8:
			var t := i / 7.0
			# Out from the trunk, a round elbow, then straight up.
			var out := 0.75 * smoothstep(0.0, 0.45, t)
			var lift := 0.25 * smoothstep(0.0, 0.35, t) + up * smoothstep(0.3, 1.0, t)
			arm.append(Vector3(0, y + lift, 0) + dir * out)
		var ar := []
		for i in 8: ar.append(0.19 * (1.0 - 0.15 * i / 7.0))
		_ribbed(st, arm, ar, true)
	st.generate_normals()
	st.generate_tangents()
	return _commit([st])

## A tube with eight ribs (cactus), optionally closed with a dome.
static func _ribbed(st: SurfaceTool, pts: Array, radii: Array, dome: bool) -> void:
	var sides := 16
	var all_pts := pts.duplicate()
	var all_r := radii.duplicate()
	if dome:
		var last: Vector3 = pts[pts.size() - 1]
		var dir: Vector3 = (last - pts[pts.size() - 2]).normalized()
		var r: float = radii[radii.size() - 1]
		for k in range(1, 5):
			var a := k / 4.0 * PI / 2.0
			all_pts.append(last + dir * sin(a) * r * 0.9)
			all_r.append(maxf(cos(a) * r, 0.005))
	var v := 0.0
	var rings := []
	for i in all_pts.size():
		var dir: Vector3 = (all_pts[mini(i + 1, all_pts.size() - 1)] - all_pts[maxi(i - 1, 0)]).normalized()
		var side := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(dir)
		var ring := []
		for k in sides + 1:
			var a := TAU * k / sides
			var rr: float = all_r[i] * (1.0 + 0.13 * cos(a * 8.0))
			ring.append([all_pts[i] + (side * cos(a) + up * sin(a)) * rr, Vector2(float(k) / sides, v)])
		rings.append(ring)
		if i + 1 < all_pts.size(): v += all_pts[i].distance_to(all_pts[i + 1]) / 1.2
	for i in rings.size() - 1:
		for k in sides:
			var q := [rings[i][k], rings[i + 1][k + 1], rings[i][k + 1], rings[i][k], rings[i + 1][k], rings[i + 1][k + 1]]
			for c in q:
				st.set_uv(c[1])
				st.set_uv2(Vector2(1, 0))
				st.add_vertex(c[0])

## Dead desert tree: a gnarled trunk that splits into branches, and those
## into twigs (bark only).
static func dead(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tp := []
	var tr := []
	for i in 6:
		var t := i / 5.0
		tp.append(Vector3(sin(t * 2.6 + seed) * 0.35, -0.3 + t * 3.4, cos(t * 1.9 + seed) * 0.3))
		tr.append(lerpf(0.3, 0.13, t))
	_tube(bark, tp, tr, 8)
	_dead_limbs(bark, rng, tp[tp.size() - 1], Vector3(0, 1, 0), 0.13, 2.4, 0)
	for k in rng.randi_range(1, 2):
		var a := rng.randf() * TAU
		var from: Vector3 = tp[rng.randi_range(2, 3)]
		_dead_limbs(bark, rng, from, Vector3(cos(a), 0.6, sin(a)).normalized(), 0.1, 2.0, 1)
	bark.generate_tangents()
	return _commit([bark])

static func _dead_limbs(st: SurfaceTool, rng: RandomNumberGenerator, from: Vector3, dir: Vector3, r: float, length: float, depth: int) -> void:
	var n := 3 if depth == 0 else 2
	for k in n:
		var a := TAU * k / n + rng.randf_range(-0.6, 0.6)
		var spread := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.5, 0.9)
		var d := (dir + spread).normalized()
		var br := _branch(rng, from, d, length * rng.randf_range(0.75, 1.1), r)
		_tube(st, br[0], br[1], 6 if depth == 0 else 4)
		if depth < 2:
			var tip: Vector3 = br[0][br[0].size() - 1]
			_dead_limbs(st, rng, tip, d, r * 0.45, length * 0.55, depth + 1)

static func _commit(sts: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for st in sts:
		st.index()
		st.commit(mesh)
	return mesh
