class_name CarModels
## Car bodies built from lofted cross-sections (smooth sides, tumblehome,
## wheel arches, glass) plus detail parts. Two kinds, like the PUBG cars:
## "sedan" (small four-door saloon) and "jeep" (open-top off-roader).
## Cars face +Z. Meshes are cached per kind; paint is a per-car material.

static var _cache := {}

const WHEEL_Z := 1.35
const WHEEL_X := 0.82

## Profile of a kind: belt line (top of the doors / bonnet / boot) and roof
## line as [z, y] points from the back to the front.
static func _spec(kind: String) -> Dictionary:
	if kind == "jeep":
		return {"len": [-2.0, 2.05], "half_w": 0.92, "cab_w": 0.86, "sill": 0.55, "floor": 0.48,
			"belt": [[-2.0, 1.12], [-1.2, 1.15], [0.6, 1.15], [0.75, 1.22], [2.0, 1.2], [2.05, 0.95]],
			"roof": [], "arch_r": 0.5, "nose": 0.75}
	return {"len": [-2.18, 2.2], "half_w": 0.89, "cab_w": 0.74, "sill": 0.36, "floor": 0.32,
		"belt": [[-2.18, 0.78], [-2.1, 0.98], [-1.55, 1.02], [0.95, 1.0], [2.05, 0.86], [2.2, 0.66]],
		"roof": [[-1.62, 1.03], [-0.95, 1.46], [0.2, 1.48], [0.98, 1.01]], "arch_r": 0.47, "nose": 0.62}

static func _lerp_line(pts: Array, z: float, fallback: float) -> float:
	if pts.is_empty() or z < pts[0][0] or z > pts[-1][0]: return fallback
	for i in pts.size() - 1:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if z >= a[0] and z <= b[0]:
			return lerpf(a[1], b[1], (z - a[0]) / maxf(b[0] - a[0], 0.001))
	return fallback

## Bottom edge of the body side at z: the sill, rising into a round arch over each wheel.
static func _sill(sp: Dictionary, z: float) -> float:
	var y: float = sp.sill
	for wz in [-WHEEL_Z, WHEEL_Z]:
		var d := absf(z - wz)
		if d < sp.arch_r:
			y = maxf(y, 0.38 + sqrt(sp.arch_r * sp.arch_r - d * d))
	return y

static func body(kind: String) -> Dictionary:
	if _cache.has(kind): return _cache[kind]
	var sp := _spec(kind)
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0: float = sp.len[0]
	var z1: float = sp.len[1]
	var steps := 44
	var rings := []
	for i in steps + 1:
		var z := lerpf(z0, z1, float(i) / steps)
		var belt := _lerp_line(sp.belt, z, 0.9)
		var top := maxf(belt, _lerp_line(sp.roof, z, belt))
		var w: float = sp.half_w
		# Rounded nose and tail in plan view.
		var end_d := minf(z - z0, z1 - z)
		w *= 0.86 + 0.14 * smoothstep(0.0, 0.35, end_d)
		var cw: float = sp.cab_w * (0.92 + 0.08 * smoothstep(0.0, 0.4, end_d))
		var sill := _sill(sp, z)
		var fl: float = sp.floor
		var has_cab := top > belt + 0.05
		var roof_w := cw * 0.9
		# Cross-section, left to right over the top: [x, y, part]
		var r := [
			[-w * 0.8, fl, "trim"], [-w, sill, "paint"], [-w, belt - 0.12, "paint"], [-w * 0.985, belt - 0.03, "paint"],
			[-cw, belt + 0.005, "paint"],
			[-lerpf(cw, roof_w, 0.5), lerpf(belt, top, 0.55), "glass" if has_cab else "paint"],
			[-roof_w, top - 0.03, "glass" if has_cab else "paint"], [-roof_w * 0.92, top, "paint"],
			[roof_w * 0.92, top, "paint"], [roof_w, top - 0.03, "paint"],
			[lerpf(cw, roof_w, 0.5), lerpf(belt, top, 0.55), "glass" if has_cab else "paint"],
			[cw, belt + 0.005, "glass" if has_cab else "paint"],
			[w * 0.985, belt - 0.03, "paint"], [w, belt - 0.12, "paint"], [w, sill, "paint"], [w * 0.8, fl, "trim"],
		]
		rings.append([z, r, has_cab])
	# Skin: quads between neighbouring rings; each quad goes to the surface of its start point.
	for i in steps:
		var ra: Array = rings[i][1]
		var rb: Array = rings[i + 1][1]
		var za: float = rings[i][0]
		var zb: float = rings[i + 1][0]
		for k in ra.size():
			var k2 := (k + 1) % ra.size()
			var a0 := Vector3(ra[k][0], ra[k][1], za)
			var a1 := Vector3(ra[k2][0], ra[k2][1], za)
			var b0 := Vector3(rb[k][0], rb[k][1], zb)
			var b1 := Vector3(rb[k2][0], rb[k2][1], zb)
			var mid_z := (za + zb) * 0.5
			var cab: bool = rings[i][2] and rings[i + 1][2]
			var st: SurfaceTool = paint
			if k in [0, 14, 15]:
				st = trim
			elif cab and k in [4, 5, 9, 10] and mid_z > -1.45 and mid_z < 0.85 and absf(mid_z + 0.38) > 0.05:
				st = glass       # side windows (B pillar left in paint)
			elif cab and k in [6, 7, 8] and ((mid_z > 0.22 and mid_z < 0.96) or (mid_z > -1.6 and mid_z < -0.97)):
				st = glass       # windscreen and rear window
			for v in [a0, b1, b0, a0, a1, b1]:
				st.add_vertex(v)
	# End caps (front and back).
	for e in [0, steps]:
		var rr: Array = rings[e][1]
		var z: float = rings[e][0]
		var c := Vector3(0, 0.0, z)
		for p in rr: c += Vector3(p[0], p[1], 0) / rr.size()
		for k in rr.size():
			var k2 := (k + 1) % rr.size()
			var a := Vector3(rr[k][0], rr[k][1], z)
			var b := Vector3(rr[k2][0], rr[k2][1], z)
			var tri := [c, b, a] if e == steps else [c, a, b]
			for v in tri: trim.add_vertex(v)
	var mesh := ArrayMesh.new()
	var names := []
	for pair in [["paint", paint], ["glass", glass], ["trim", trim]]:
		var st: SurfaceTool = pair[1]
		if pair[0] == "glass" and kind == "jeep": continue      # open top: no glass in the body
		if pair[0] == "paint": st.index()       # shared vertices: smooth panels
		st.generate_normals()
		st.commit(mesh)
		names.append(pair[0])
	var details := _details(kind, sp)
	var d := {"mesh": mesh, "details": details, "spec": sp, "surfaces": names}
	_cache[kind] = d
	return d

## Lights, grille, bumpers, mirrors, plates, door seams, roll bar... merged.
static func _details(kind: String, sp: Dictionary) -> Dictionary:
	var dark := SurfaceTool.new(); dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var chrome := SurfaceTool.new(); chrome.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := SurfaceTool.new(); white.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head := SurfaceTool.new(); head.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tail := SurfaceTool.new(); tail.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glassd := SurfaceTool.new(); glassd.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := func(st: SurfaceTool, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
		var b := BoxMesh.new()
		b.size = size
		st.append_from(b, 0, Transform3D(Basis.from_euler(rot), pos))
	var tube := func(st: SurfaceTool, r: float, a: Vector3, b: Vector3) -> void:
		var c := CylinderMesh.new()
		c.top_radius = r
		c.bottom_radius = r
		c.height = a.distance_to(b)
		c.radial_segments = 8
		c.rings = 1
		var up := (b - a).normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		st.append_from(c, 0, Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5))
	var z0: float = sp.len[0]
	var z1: float = sp.len[1]
	var w: float = sp.half_w
	var nose: float = sp.nose
	# Bumpers: a low bar wrapping round the corners, a rubber strip on top.
	for e in [[z1, 1.0], [z0, -1.0]]:
		var ez: float = e[0] - e[1] * 0.03
		box.call(dark, Vector3(w * 1.78, 0.17, 0.12), Vector3(0, nose - 0.1, ez))
		box.call(chrome, Vector3(w * 1.7, 0.025, 0.02), Vector3(0, nose - 0.03, ez + e[1] * 0.06))
		for x in [-1.0, 1.0]:
			box.call(dark, Vector3(0.12, 0.17, 0.32), Vector3(x * (w * 0.9 - 0.02), nose - 0.1, ez - e[1] * 0.12), Vector3(0, x * e[1] * 0.5, 0))
	# Grille: dark recess with chrome slats and a frame; number plates.
	box.call(dark, Vector3(0.66, 0.15, 0.03), Vector3(0, nose + 0.1, z1 + 0.002))
	for i in 3:
		box.call(chrome, Vector3(0.64, 0.012, 0.02), Vector3(0, nose + 0.05 + i * 0.05, z1 + 0.012))
	box.call(chrome, Vector3(0.7, 0.02, 0.025), Vector3(0, nose + 0.185, z1 + 0.006))
	box.call(white, Vector3(0.36, 0.1, 0.02), Vector3(0, nose - 0.1, z1 + 0.04))
	box.call(white, Vector3(0.36, 0.1, 0.02), Vector3(0, nose + 0.12, z0 - 0.01))
	# Lights: lenses in chrome bezels, indicators, wide tail-light bars.
	for x in [-1.0, 1.0]:
		box.call(chrome, Vector3(0.34, 0.13, 0.02), Vector3(x * (w - 0.25), nose + 0.11, z1 - 0.015))
		box.call(head, Vector3(0.3, 0.1, 0.02), Vector3(x * (w - 0.25), nose + 0.11, z1 - 0.004))
		box.call(tail, Vector3(0.4, 0.11, 0.03), Vector3(x * (w - 0.24), nose + 0.18, z0 + 0.008))
		box.call(chrome, Vector3(0.1, 0.05, 0.02), Vector3(x * (w - 0.07), nose + 0.11, z1 - 0.03))
	if kind == "sedan":
		# Door seams, handles, mirrors.
		for x in [-1.0, 1.0]:
			for z in [0.95, -0.38, -1.5]:
				box.call(dark, Vector3(0.012, 0.55, 0.012), Vector3(x * (w + 0.002), 0.72, z))
			for z in [0.2, -1.0]:
				box.call(chrome, Vector3(0.02, 0.03, 0.14), Vector3(x * (w + 0.01), 0.9, z))
			box.call(dark, Vector3(0.12, 0.09, 0.16), Vector3(x * (w + 0.06), 1.08, 0.82), Vector3(0, 0, 0))
			# Rubber side strip along the doors.
			box.call(dark, Vector3(0.02, 0.045, 2.5), Vector3(x * (w + 0.008), 0.62, -0.3))
		# Exhaust pipe under the back.
		tube.call(chrome, 0.035, Vector3(-0.5, 0.33, z0 + 0.25), Vector3(-0.5, 0.31, z0 - 0.05))
	else:
		# Jeep: windscreen frame, roll bar, seats, spare wheel, side steps, bonnet lines.
		for x in [-1.0, 1.0]:
			tube.call(dark, 0.03, Vector3(x * 0.82, 1.2, 0.72), Vector3(x * 0.8, 1.68, 0.5))
			tube.call(dark, 0.035, Vector3(x * 0.8, 1.14, -0.6), Vector3(x * 0.78, 1.82, -0.6))
			box.call(dark, Vector3(0.16, 0.05, 1.2), Vector3(x * (w + 0.04), 0.52, 0.0))
			box.call(dark, Vector3(0.5, 0.5, 0.12), Vector3(x * 0.4, 1.15, -0.25), Vector3(-0.2, 0, 0))    # seat backs
		tube.call(dark, 0.03, Vector3(-0.8, 1.68, 0.5), Vector3(0.8, 1.68, 0.5))
		tube.call(dark, 0.035, Vector3(-0.78, 1.82, -0.6), Vector3(0.78, 1.82, -0.6))
		box.call(glassd, Vector3(1.5, 0.44, 0.02), Vector3(0, 1.44, 0.62), Vector3(0.45, 0, 0))
		box.call(dark, Vector3(1.5, 0.03, 0.03), Vector3(0, 1.22, 0.74))
		box.call(dark, Vector3(0.3, 0.35, 0.03), Vector3(0, 1.0, 2.06))
		var spare := CylinderMesh.new()
		spare.top_radius = 0.36
		spare.bottom_radius = 0.36
		spare.height = 0.24
		spare.radial_segments = 16
		dark.append_from(spare, 0, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 1.0, z0 - 0.14)))
	# Steering wheel and dashboard (driver on the left, +X).
	var sw_pos := Vector3(0.38, 1.02 if kind == "sedan" else 1.2, 0.42)
	var sw := TorusMesh.new()
	sw.inner_radius = 0.15
	sw.outer_radius = 0.18
	sw.rings = 16
	sw.ring_segments = 6
	dark.append_from(sw, 0, Transform3D(Basis(Vector3.RIGHT, PI / 2 - 0.45), sw_pos))
	tube.call(dark, 0.025, sw_pos, sw_pos + Vector3(0, -0.12, 0.3))
	box.call(dark, Vector3(1.5, 0.18, 0.3), Vector3(0, sw_pos.y - 0.12, sw_pos.z + 0.3))
	var out := {}
	for pair in [["dark", dark], ["chrome", chrome], ["white", white], ["head", head], ["tail", tail], ["glass", glassd]]:
		var st: SurfaceTool = pair[1]
		if kind != "jeep" and pair[0] == "glass": continue
		out[pair[0]] = st.commit()
	return out

## One wheel: tyre with sidewall bevel and a five-spoke rim. Axis along X.
static func wheel(radius: float, width: float) -> Dictionary:
	var key := "wheel%.2f" % radius
	if _cache.has(key): return _cache[key]
	var tyre := SurfaceTool.new()
	tyre.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	# Tyre: profile rings around the axis (outer tread, rounded shoulders, sidewalls).
	var prof := [[-width * 0.5, radius * 0.62], [-width * 0.5, radius * 0.92], [-width * 0.42, radius], [width * 0.42, radius],
		[width * 0.5, radius * 0.92], [width * 0.5, radius * 0.62]]
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		for k in prof.size() - 1:
			var p0: Array = prof[k]
			var p1: Array = prof[k + 1]
			# Tread blocks: the outer ring alternates a little in radius.
			var bump := 0.012 if (k == 2 and i % 2 == 0) else 0.0
			var q := [Vector3(p0[0], cos(a0) * (p0[1] + bump), sin(a0) * (p0[1] + bump)), Vector3(p1[0], cos(a0) * (p1[1] + bump), sin(a0) * (p1[1] + bump)),
				Vector3(p1[0], cos(a1) * (p1[1] + bump), sin(a1) * (p1[1] + bump)), Vector3(p0[0], cos(a1) * (p0[1] + bump), sin(a1) * (p0[1] + bump))]
			for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
				tyre.add_vertex(v)
	tyre.generate_normals()
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 0.62
	disc.bottom_radius = radius * 0.62
	disc.height = width * 0.7
	disc.radial_segments = 20
	rim.append_from(disc, 0, Transform3D(Basis(Vector3.BACK, PI / 2), Vector3.ZERO))
	var hub := CylinderMesh.new()
	hub.top_radius = radius * 0.16
	hub.bottom_radius = radius * 0.2
	hub.height = width * 0.9
	rim.append_from(hub, 0, Transform3D(Basis(Vector3.BACK, PI / 2), Vector3.ZERO))
	for k in 5:
		var b := BoxMesh.new()
		b.size = Vector3(0.05, radius * 0.5, 0.07)
		var ang := TAU * k / 5.0
		rim.append_from(b, 0, Transform3D(Basis(Vector3.RIGHT, ang), Vector3(width * 0.37, cos(ang) * radius * 0.3, sin(ang) * radius * 0.3)))
		rim.append_from(b, 0, Transform3D(Basis(Vector3.RIGHT, ang), Vector3(-width * 0.37, cos(ang) * radius * 0.3, sin(ang) * radius * 0.3)))
	var d := {"tyre": tyre.commit(), "rim": rim.commit()}
	_cache[key] = d
	return d

## Parts helpers shared by the bike and the boat.
static func _box_into(st: SurfaceTool, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var b := BoxMesh.new()
	b.size = size
	st.append_from(b, 0, Transform3D(Basis.from_euler(rot), pos))

static func _tube_into(st: SurfaceTool, r: float, a: Vector3, b: Vector3, segs := 10) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = a.distance_to(b)
	c.radial_segments = segs
	c.rings = 1
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	st.append_from(c, 0, Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5))

static func _sts(keys: Array) -> Dictionary:
	var d := {}
	for k in keys:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		d[k] = st
	return d

static func _commit(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = d[k].commit()
	return out

## Dirt bike (faces +Z, wheels at z = ±0.72, seat top ~0.85 m): painted tank
## and side panels, black frame, fork, handlebar, engine, exhaust, lights.
static func bike() -> Dictionary:
	if _cache.has("bike"): return _cache["bike"]
	var s := _sts(["paint", "dark", "chrome", "seat", "head", "tail"])
	# Frame: down tube, top tube, rear frame to the axle.
	_tube_into(s.dark, 0.03, Vector3(0, 0.95, 0.5), Vector3(0, 0.42, 0.15))
	_tube_into(s.dark, 0.03, Vector3(0, 0.95, 0.5), Vector3(0, 0.85, -0.25))
	for x in [-0.09, 0.09]:
		_tube_into(s.dark, 0.022, Vector3(x, 0.8, -0.25), Vector3(x, 0.32, -0.72))   # swing arm/shock
		_tube_into(s.dark, 0.02, Vector3(x, 0.45, 0.1), Vector3(x, 0.32, -0.72))
		# Fork legs down to the front axle.
		_tube_into(s.chrome, 0.026, Vector3(x, 1.0, 0.55), Vector3(x, 0.32, 0.72))
	# Tank, side panels, front mudguard, rear fender.
	var tank := CapsuleMesh.new()
	tank.radius = 0.15
	tank.height = 0.55
	s.paint.append_from(tank, 0, Transform3D(Basis(Vector3.RIGHT, PI / 2 - 0.15), Vector3(0, 0.92, 0.22)))
	_box_into(s.paint, Vector3(0.26, 0.2, 0.5), Vector3(0, 0.78, -0.35), Vector3(0.15, 0, 0))
	_box_into(s.paint, Vector3(0.14, 0.03, 0.42), Vector3(0, 0.72, 0.78), Vector3(0.35, 0, 0))
	_box_into(s.paint, Vector3(0.16, 0.03, 0.5), Vector3(0, 0.88, -0.78), Vector3(-0.3, 0, 0))
	# Seat.
	_box_into(s.seat, Vector3(0.24, 0.08, 0.62), Vector3(0, 0.89, -0.25), Vector3(0.05, 0, 0))
	# Engine block and exhaust along the right side.
	_box_into(s.dark, Vector3(0.24, 0.26, 0.3), Vector3(0, 0.5, 0.05))
	_tube_into(s.chrome, 0.035, Vector3(0.12, 0.45, 0.25), Vector3(0.16, 0.42, -0.2))
	_tube_into(s.chrome, 0.045, Vector3(0.16, 0.42, -0.2), Vector3(0.17, 0.62, -0.75))
	# Handlebar with grips, headlight with a number plate shell, tail light.
	_tube_into(s.dark, 0.016, Vector3(-0.36, 1.1, 0.5), Vector3(0.36, 1.1, 0.5))
	_tube_into(s.dark, 0.022, Vector3(0, 1.0, 0.55), Vector3(0, 1.1, 0.5))
	for x in [-0.33, 0.33]:
		_tube_into(s.seat, 0.024, Vector3(x - 0.05, 1.1, 0.5), Vector3(x + 0.05, 1.1, 0.5))
	_box_into(s.paint, Vector3(0.22, 0.24, 0.06), Vector3(0, 0.98, 0.64), Vector3(-0.3, 0, 0))
	_box_into(s.head, Vector3(0.1, 0.08, 0.03), Vector3(0, 0.97, 0.68), Vector3(-0.3, 0, 0))
	_box_into(s.tail, Vector3(0.08, 0.05, 0.03), Vector3(0, 0.9, -1.02))
	var out := _commit(s)
	_cache["bike"] = out
	return out

## Small open motor boat (faces +Z, 4.7 m): flared V-hull with a painted
## top band and white bottom, gunwale rub rail, bow deck and rail, centre
## console with windscreen and wheel, padded benches, outboard motor.
static func boat() -> Dictionary:
	if _cache.has("boat"): return _cache["boat"]
	var s := _sts(["paint", "white", "dark", "seat", "glass", "chrome"])
	# Hull sections: [z, half width, keel depth, gunwale height].
	var secs := [[-2.3, 0.92, 0.02, 0.62], [-1.8, 0.95, -0.04, 0.62], [-1.0, 0.96, -0.1, 0.63], [0.0, 0.95, -0.13, 0.65],
		[0.8, 0.88, -0.12, 0.68], [1.4, 0.72, -0.08, 0.72], [1.85, 0.48, 0.02, 0.76], [2.2, 0.22, 0.15, 0.8], [2.4, 0.03, 0.36, 0.82]]
	# Ring, left to right: gunwale, end of the painted band, chine, keel.
	var ring := func(sec: Array) -> Array:
		var z: float = sec[0]
		var w: float = sec[1]
		var k: float = sec[2]
		var t: float = sec[3]
		return [Vector3(-w, t, z), Vector3(-w * 0.97, t - 0.2, z), Vector3(-w * 0.86, 0.14 + k * 0.5, z), Vector3(0, k, z),
			Vector3(w * 0.86, 0.14 + k * 0.5, z), Vector3(w * 0.97, t - 0.2, z), Vector3(w, t, z)]
	var band := SurfaceTool.new()
	band.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom := SurfaceTool.new()
	bottom.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in secs.size() - 1:
		var a: Array = ring.call(secs[i])
		var b: Array = ring.call(secs[i + 1])
		for j in a.size() - 1:
			var st: SurfaceTool = band if j == 0 or j == a.size() - 2 else bottom
			for v in [a[j], b[j + 1], b[j], a[j], a[j + 1], b[j + 1]]:
				st.add_vertex(v)
		# Inner liner above the deck (white), facing in; the bow is decked over.
		if i >= 5: continue
		for x in [-1.0, 1.0]:
			var p0 := Vector3(x * secs[i][1] * 0.95, secs[i][3], secs[i][0])
			var p1 := Vector3(x * secs[i + 1][1] * 0.95, secs[i + 1][3], secs[i + 1][0])
			var q0 := Vector3(x * secs[i][1] * 0.9, 0.32, secs[i][0])
			var q1 := Vector3(x * secs[i + 1][1] * 0.9, 0.32, secs[i + 1][0])
			var quad := [p0, q1, q0, p0, p1, q1] if x > 0.0 else [p0, q0, q1, p0, q1, p1]
			for v in quad: s.white.add_vertex(v)
	# Transom (flat back).
	var tr: Array = ring.call(secs[0])
	for j in range(1, tr.size() - 1):
		for v in [tr[0], tr[j + 1], tr[j]]:
			bottom.add_vertex(v)
	for st in [band, bottom]:
		st.index()
		st.generate_normals()
	s.paint.append_from(band.commit(), 0, Transform3D.IDENTITY)
	s.white.append_from(bottom.commit(), 0, Transform3D.IDENTITY)
	# Rub rail along the gunwale, bow deck, bow rail.
	for x in [-1.0, 1.0]:
		for i in secs.size() - 1:
			_tube_into(s.dark, 0.035, Vector3(x * secs[i][1], secs[i][3], secs[i][0]), Vector3(x * secs[i + 1][1], secs[i + 1][3], secs[i + 1][0]), 6)
		_tube_into(s.chrome, 0.015, Vector3(x * 0.6, 0.98, 1.3), Vector3(x * 0.12, 0.98, 2.25))
		_tube_into(s.chrome, 0.015, Vector3(x * 0.6, 0.72, 1.3), Vector3(x * 0.6, 0.98, 1.3))
		_tube_into(s.chrome, 0.015, Vector3(x * 0.12, 0.82, 2.25), Vector3(x * 0.12, 0.98, 2.25))
	_tube_into(s.chrome, 0.015, Vector3(-0.12, 0.98, 2.25), Vector3(0.12, 0.98, 2.25))
	for i in range(5, secs.size() - 1):
		var a0 := Vector3(-secs[i][1], secs[i][3], secs[i][0])
		var a1 := Vector3(secs[i][1], secs[i][3], secs[i][0])
		var b0 := Vector3(-secs[i + 1][1], secs[i + 1][3], secs[i + 1][0])
		var b1 := Vector3(secs[i + 1][1], secs[i + 1][3], secs[i + 1][0])
		for v in [a0, b1, a1, a0, b0, b1]: s.white.add_vertex(v)
	# Deck floor.
	_box_into(s.white, Vector3(1.66, 0.04, 3.7), Vector3(0, 0.32, -0.5))
	# Console: body, dark dash, windscreen in a chrome frame, wheel.
	_box_into(s.white, Vector3(0.62, 0.6, 0.5), Vector3(0.35, 0.62, -0.25))
	_box_into(s.dark, Vector3(0.58, 0.04, 0.3), Vector3(0.35, 0.94, -0.18), Vector3(-0.35, 0, 0))
	_box_into(s.glass, Vector3(0.62, 0.32, 0.015), Vector3(0.35, 1.08, -0.02), Vector3(-0.4, 0, 0))
	_tube_into(s.chrome, 0.012, Vector3(0.04, 0.93, 0.03), Vector3(0.04, 1.22, -0.09))
	_tube_into(s.chrome, 0.012, Vector3(0.66, 0.93, 0.03), Vector3(0.66, 1.22, -0.09))
	_tube_into(s.chrome, 0.012, Vector3(0.04, 1.22, -0.09), Vector3(0.66, 1.22, -0.09))
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.1
	wheel.outer_radius = 0.125
	wheel.rings = 14
	wheel.ring_segments = 5
	s.dark.append_from(wheel, 0, Transform3D(Basis(Vector3.RIGHT, PI / 2 - 0.6), Vector3(0.35, 0.98, -0.42)))
	# Benches with backrests on pedestals.
	for b in [[-1.75, 1.5], [0.9, 1.4]]:
		_box_into(s.seat, Vector3(b[1], 0.12, 0.45), Vector3(0, 0.56, b[0]))
		_box_into(s.white, Vector3(b[1] - 0.1, 0.2, 0.36), Vector3(0, 0.42, b[0]))
	_box_into(s.seat, Vector3(1.4, 0.3, 0.1), Vector3(0, 0.78, -2.0), Vector3(-0.12, 0, 0))
	# Outboard motor: rounded cowling, shaft, lower unit, propeller.
	var cowl := CapsuleMesh.new()
	cowl.radius = 0.2
	cowl.height = 0.62
	s.white.append_from(cowl, 0, Transform3D(Basis.from_scale(Vector3(0.85, 0.8, 1.2)), Vector3(0, 0.95, -2.5)))
	_box_into(s.dark, Vector3(0.36, 0.08, 0.5), Vector3(0, 0.8, -2.5))
	_box_into(s.dark, Vector3(0.1, 0.65, 0.16), Vector3(0, 0.38, -2.52))
	_box_into(s.dark, Vector3(0.14, 0.12, 0.4), Vector3(0, 0.05, -2.5))
	for k in 3:
		_box_into(s.chrome, Vector3(0.03, 0.18, 0.05), Vector3(0, 0.05, -2.74), Vector3(0, 0, TAU * k / 3.0))
	_tube_into(s.chrome, 0.02, Vector3(0, 0.95, -2.25), Vector3(0, 0.9, -1.85))   # tiller
	var out := _commit(s)
	_cache["boat"] = out
	return out

## Imported models (Sketchfab, CC-BY — see README): the UAZ jeep and the dirt
## bike. "len" scales the model to that length (0 = already in metres).
const IMPORTED := {
	"jeep": {"path": "res://assets/models/vehicles/uaz/scene.gltf", "len": 4.1},
	"bike": {"path": "res://assets/models/vehicles/dirt_bike/dirt_bike.glb", "len": 0.0},
}

## The body merged into one mesh and each wheel (nodes named wheel*) as its
## own mesh centred on its axle: {"body", "wheels": [[mesh, centre]], "radius"}.
## Faces +Z, ground at y = 0, the axles centred on z = 0.
static func imported(kind: String) -> Dictionary:
	if _cache.has("imp_" + kind): return _cache["imp_" + kind]
	var cfg: Dictionary = IMPORTED[kind]
	var sc: Node3D = load(cfg.path).instantiate()
	var acc := [null]
	WeaponModels._mesh_aabb(sc, Transform3D.IDENTITY, acc)
	var a: AABB = acc[0]
	var s: float = cfg.len / a.size.z if cfg.len > 0.0 else 1.0
	var wheels := []      # [node, parent transform]
	_find_wheels(sc, Transform3D.IDENTITY, wheels)
	var scale := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO)
	var boxes := []
	var lo := INF
	var zs := []
	for w in wheels:
		var wa := [null]
		WeaponModels._mesh_aabb(w[0], scale * w[1], wa)
		boxes.append(wa[0])
		lo = minf(lo, wa[0].position.y)
		zs.append(wa[0].get_center().z)
	var zmid: float = (zs.min() + zs.max()) * 0.5 if zs.size() > 0 else a.get_center().z * s
	var xf := Transform3D(Basis.IDENTITY, Vector3(-a.get_center().x * s, -lo, -zmid)) * scale
	var body := ArrayMesh.new()
	var by_mat := {}
	var flat := SurfaceTool.new()
	flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_flat := [false]
	_merge_body(sc, Transform3D.IDENTITY, xf, by_mat, flat, has_flat)
	_commit_merged(body, by_mat, flat, has_flat[0])
	var out_w := []
	var radius := 0.0
	for i in wheels.size():
		var c: Vector3 = Transform3D(Basis.IDENTITY, Vector3(-a.get_center().x * s, -lo, -zmid)) * boxes[i].get_center()
		radius = maxf(radius, boxes[i].size.y * 0.5)
		var wm := ArrayMesh.new()
		var wb := {}
		var wf := SurfaceTool.new()
		wf.begin(Mesh.PRIMITIVE_TRIANGLES)
		var whf := [false]
		WeaponModels._merge_fitted(wheels[i][0], Transform3D(Basis.IDENTITY, -c) * xf * wheels[i][1], wb, wf, whf)
		_commit_merged(wm, wb, wf, whf[0])
		out_w.append([wm, c])
	sc.free()
	var out := {"body": body, "wheels": out_w, "radius": radius}
	_cache["imp_" + kind] = out
	return out

static func _find_wheels(n: Node, xf: Transform3D, out: Array) -> void:
	if String(n.name).to_lower().begins_with("wheel"):
		out.append([n, xf])
		return
	if n is Node3D: xf = xf * (n as Node3D).transform
	for c in n.get_children(): _find_wheels(c, xf, out)

static func _merge_body(n: Node, parent: Transform3D, xf: Transform3D, by_mat: Dictionary, flat: SurfaceTool, has_flat: Array) -> void:
	if String(n.name).to_lower().begins_with("wheel"): return
	if n is MeshInstance3D:
		WeaponModels._merge_fitted(n, xf * parent, by_mat, flat, has_flat)
		return
	var here := parent * (n as Node3D).transform if n is Node3D else parent
	for c in n.get_children(): _merge_body(c, here, xf, by_mat, flat, has_flat)

static func _commit_merged(mesh: ArrayMesh, by_mat: Dictionary, flat: SurfaceTool, has_flat: bool) -> void:
	for mat in by_mat:
		var st: SurfaceTool = by_mat[mat]
		st.set_material(mat)
		st.commit(mesh)
	if has_flat:
		var fm := StandardMaterial3D.new()
		fm.vertex_color_use_as_albedo = true
		fm.vertex_color_is_srgb = true
		fm.roughness = 0.45
		fm.metallic = 0.2
		flat.set_material(fm)
		flat.commit(mesh)
