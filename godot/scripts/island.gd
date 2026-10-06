class_name Island
extends RefCounted
## Procedural island data: heightmap, towns, roads, bridges, building lots,
## trees and rocks. Pure data — world.gd turns it into nodes.

const N := 513                 # heightmap samples per side
const WATER := 0.0             # sea level (m)
const DEEP := -1.7             # deeper than this: too deep to wade
const TOWN_NAMES := ["الميناء", "المدينة القديمة", "المزرعة", "المحطة", "الوادي", "القلعة", "السوق", "المصنع",
	"التلال", "الواحة", "المنارة", "الجسر", "المطار", "النخيل", "المنجم", "الصخرة"]

var size: float
var step: float
var heights := PackedFloat32Array()
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var towns: Array = []          # {name, pos: Vector2, r, military}
var roads: Array = []          # {a: Vector2, b: Vector2, w}
var bridges: Array = []        # {a, b, w}
var buildings: Array = []      # {pos: Vector2 (centre), size: Vector2, rot: 0|90, floor, military, doors: Array}
var trees: Array = []          # {pos: Vector2, h, r, pine}
var rocks: Array = []          # {pos: Vector2, r}
var loot_spots: Array = []     # {pos: Vector2, military, level?}
var structures: Array = []     # {kind, pos: Vector2, rot (0 or 90), level, col} containers, silos, towers...
var obstacles: Array = []      # {pos: Vector2, half: Vector2} footprints of structures
var fields: Array = []         # Rect2 crop fields next to farms
var river_amp := 0.0
var river_phase := 0.0
var river_base := 0.0
var south := Vector2.ZERO

func _init(seed_value: int, map_size: float) -> void:
	size = map_size
	step = size / float(N - 1)
	rng.seed = seed_value
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 900.0
	noise.fractal_octaves = 5
	detail.seed = seed_value + 7
	detail.frequency = 1.0 / 260.0
	detail.fractal_octaves = 3

func generate() -> void:
	_heights()
	_towns()
	_roads()
	_buildings()
	_props()

# ---------- Terrain ----------
func river_z(x: float) -> float:
	return river_base + sin(x / (size * 0.12) + river_phase) * size * 0.06 + sin(x / (size * 0.045)) * size * 0.015

func channel_z(x: float) -> float:
	return size * 0.735 + sin(x / 230.0) * 18.0

func _land_mask(x: float, z: float) -> float:
	var n := detail.get_noise_2d(x, z) * 0.28
	var mc := Vector2(size * 0.5, size * 0.45)
	var mr := size * 0.385
	var m_main := 1.0 - Vector2((x - mc.x) / mr, (z - mc.y) / (mr * 0.9)).length() + n
	var sr := size * 0.12
	var m_south := 1.0 - Vector2((x - south.x) / sr, (z - south.y) / (sr * 0.8)).length() + n * 0.6
	var cz := channel_z(x)
	var m := -1.0
	if z < cz - 22.0: m = maxf(m, m_main)
	if z > cz + 22.0: m = maxf(m, m_south)
	return m

func _heights() -> void:
	river_phase = rng.randf() * TAU
	river_base = size * (0.3 + rng.randf() * 0.08)
	south = Vector2(size * (0.45 + rng.randf() * 0.12), size * 0.86)
	heights.resize(N * N)
	for j in N:
		for i in N:
			var x := i * step
			var z := j * step
			var m := _land_mask(x, z)
			var h: float
			if m <= 0.0:
				var cd := absf(x - south.x) / (size * 0.12 * 1.4)
				var in_channel := absf(z - channel_z(x)) < 50.0 and cd < 1.0
				h = -1.2 - cd * cd * 6.0 if in_channel else maxf(-22.0, -1.0 + m * 70.0)
			else:
				var hills := pow((noise.get_noise_2d(x + 2000.0, z + 900.0) + 1.0) * 0.5, 2.2) * 95.0
				h = 1.2 + hills * smoothstep(0.0, 0.2, m)
				# River: shallow and wadeable, with gentle banks.
				var dr := absf(z - river_z(x))
				var rw := 22.0 + (detail.get_noise_2d(x, 99.0) + 1.0) * 8.0
				if dr < rw:
					h = -1.2
				else:
					h = minf(h, 1.0 + (dr - rw) * 0.12 + h * smoothstep(rw, rw + 120.0, dr))
			heights[j * N + i] = h

func height_at(x: float, z: float) -> float:
	var fx := clampf(x / step, 0.0, N - 1.001)
	var fz := clampf(z / step, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := heights[j * N + i]
	var b := heights[j * N + i + 1]
	var c := heights[(j + 1) * N + i]
	var d := heights[(j + 1) * N + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > 0.4

func is_deep(x: float, z: float) -> bool:
	return height_at(x, z) < DEEP

## Flattens the heightmap inside a rectangle (plus a soft margin) to `level`.
func flatten(center: Vector2, half: Vector2, margin: float, level: float) -> void:
	var i0 := maxi(0, int((center.x - half.x - margin) / step))
	var i1 := mini(N - 1, int((center.x + half.x + margin) / step) + 1)
	var j0 := maxi(0, int((center.y - half.y - margin) / step))
	var j1 := mini(N - 1, int((center.y + half.y + margin) / step) + 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2(i * step, j * step)
			var dx := maxf(absf(p.x - center.x) - half.x, 0.0)
			var dz := maxf(absf(p.y - center.y) - half.y, 0.0)
			var k := 1.0 - smoothstep(0.0, margin, Vector2(dx, dz).length())
			var idx := j * N + i
			heights[idx] = lerpf(heights[idx], level, k)

func _land_around(p: Vector2, r: float) -> bool:
	if not is_land(p.x, p.y): return false
	for a in 8:
		var q := p + Vector2(r, 0).rotated(a * TAU / 8.0)
		if not is_land(q.x, q.y): return false
	return true

# ---------- Towns, roads, buildings ----------
func _towns() -> void:
	var names := TOWN_NAMES.duplicate()
	names.shuffle()
	# Military base on the southern island.
	var mil := {"name": "القاعدة العسكرية", "pos": south, "r": 120.0, "military": true, "kind": "military"}
	for k in 300:
		var p := south + Vector2(rng.randf_range(-90, 90), rng.randf_range(-40, 40))
		if _land_around(p, 150.0):
			mil.pos = p
			break
	towns.append(mil)
	var tries := 0
	var want := mini(16, int(12.0 * size / 3072.0))
	while towns.size() < want and tries < 4000:
		tries += 1
		var r := rng.randf_range(75.0, 125.0)
		var p := Vector2(rng.randf_range(180, size - 180), rng.randf_range(180, channel_z(size * 0.5) - 90))
		if not _land_around(p, r + 35.0): continue
		if absf(p.y - river_z(p.x)) < r + 45.0: continue
		var ok := true
		for t in towns:
			if p.distance_to(t.pos) < t.r + r + 160.0:
				ok = false
				break
		if not ok: continue
		towns.append({"name": names.pop_back() if names.size() > 0 else "قرية", "pos": p, "r": r, "military": false, "kind": "town"})
	# Special places, joined to the road network like towns: factory yards and farms.
	for spec in [["industrial", ["المنطقة الصناعية", "المصنع القديم"], 72.0], ["farm", ["مزرعة الزيتون", "مزرعة القمح", "مزرعة التلال"], 62.0]]:
		var made := 0
		var tries2 := 0
		while made < spec[1].size() and tries2 < 3000:
			tries2 += 1
			var r: float = spec[2]
			var p := Vector2(rng.randf_range(180, size - 180), rng.randf_range(180, channel_z(size * 0.5) - 90))
			if not _land_around(p, r + 35.0): continue
			if absf(p.y - river_z(p.x)) < r + 45.0: continue
			var ok := true
			for t in towns:
				if p.distance_to(t.pos) < t.r + r + 140.0:
					ok = false
					break
			if not ok: continue
			towns.append({"name": spec[1][made], "pos": p, "r": r, "military": false, "kind": spec[0]})
			made += 1
	for t in towns:
		flatten(t.pos, Vector2(t.r, t.r), 110.0, maxf(1.6, height_at(t.pos.x, t.pos.y) * 0.5))

func _roads() -> void:
	var keys := {}
	for i in towns.size():
		var dists := []
		for j in towns.size():
			if i != j: dists.append([towns[i].pos.distance_to(towns[j].pos), j])
		dists.sort_custom(func(a, b): return a[0] < b[0])
		for k in mini(2, dists.size()):
			var j: int = dists[k][1]
			var key := "%d-%d" % [mini(i, j), maxi(i, j)]
			if keys.has(key): continue
			keys[key] = true
			roads.append({"a": towns[i].pos, "b": towns[j].pos, "w": 8.0})
	# Bridges where roads cross water.
	for rd in roads:
		var a: Vector2 = rd.a
		var b: Vector2 = rd.b
		var length := a.distance_to(b)
		var steps := int(length / 4.0)
		var start := -1.0
		for k in steps + 1:
			var t := float(k) / steps
			var p := a.lerp(b, t)
			var wet := height_at(p.x, p.y) < 0.6
			if wet and start < 0.0:
				start = maxf(0.0, t - 12.0 / length)
			if (not wet or k == steps) and start >= 0.0:
				var t2 := minf(1.0, t + 12.0 / length)
				bridges.append({"a": a.lerp(b, start), "b": a.lerp(b, t2), "w": 9.0})
				start = -1.0

func near_road(p: Vector2, pad: float) -> bool:
	for rd in roads:
		if Geometry2D.get_closest_point_to_segment(p, rd.a, rd.b).distance_to(p) < rd.w * 0.5 + pad:
			return true
	return false

func _overlaps(c: Vector2, half: Vector2, pad: float) -> bool:
	for o in obstacles:
		if absf(c.x - o.pos.x) < half.x + o.half.x + pad and absf(c.y - o.pos.y) < half.y + o.half.y + pad:
			return true
	for b in buildings:
		var bh: Vector2 = b.size * 0.5
		if absf(c.x - b.pos.x) < half.x + bh.x + pad and absf(c.y - b.pos.y) < half.y + bh.y + pad:
			return true
	return false

func _add_building(c: Vector2, sz: Vector2, military: bool, storeys := 1, kind := "house") -> void:
	var floor_h := maxf(1.6, height_at(c.x, c.y))
	# Ground a little below the floor boards so it never shows through them.
	flatten(c, sz * 0.5, 14.0, floor_h - 0.12)
	# Door on one or two sides: 0 = -z, 1 = +x, 2 = +z, 3 = -x
	var doors := [rng.randi_range(0, 3)]
	if rng.randf() < 0.5:
		doors.append((doors[0] + 2) % 4)
	# Two-storey houses: the staircase runs along a wall without a door.
	var stair := -1
	if storeys > 1:
		var free := [0, 1, 2, 3].filter(func(w): return not doors.has(w))
		stair = free[rng.randi() % free.size()]
	buildings.append({"pos": c, "size": sz, "floor": floor_h, "military": military, "doors": doors,
		"tint": rng.randi_range(0, 4), "roof": rng.randi_range(0, 4), "storeys": storeys, "stair": stair, "kind": kind})
	for k in rng.randi_range(2, 5 if military else 4):
		loot_spots.append({"pos": c + Vector2(rng.randf_range(-sz.x * 0.35, sz.x * 0.35), rng.randf_range(-sz.y * 0.35, sz.y * 0.35)), "military": military})
	if storeys > 1:
		for k in rng.randi_range(2, 3):
			loot_spots.append({"pos": c + Vector2(rng.randf_range(-sz.x * 0.25, sz.x * 0.25), rng.randf_range(-sz.y * 0.25, sz.y * 0.25)), "military": false, "level": 1})

func _structure(kind: String, p: Vector2, half: Vector2, extra := {}) -> void:
	var d := {"kind": kind, "pos": p, "rot": 0, "level": 0, "col": rng.randi_range(0, 4)}
	d.merge(extra, true)
	structures.append(d)
	obstacles.append({"pos": p, "half": half})

## Factory yard: two big warehouses, rows of shipping containers (some
## stacked), a tall brick chimney and a water tower.
func _industrial(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	for k in 2:
		var bc := c + Vector2(-17.0 + k * 34.0, -14.0)
		_add_building(bc, Vector2(24, 14), false, 1, "warehouse")
		buildings[-1].doors = [0, 2]
	for row in 2:
		for i in 5:
			var p := c + Vector2(-22.0 + i * 8.5, 10.0 + row * 7.0)
			if not is_land(p.x, p.y): continue
			_structure("container", p, Vector2(3.1, 1.3))
			if rng.randf() < 0.35:
				structures.append({"kind": "container", "pos": p, "rot": 0, "level": 1, "col": rng.randi_range(0, 4)})
	var ch := c + Vector2(34.0, 18.0)
	if is_land(ch.x, ch.y): _structure("chimney", ch, Vector2(2.2, 2.2))
	var wt := c + Vector2(-36.0, 20.0)
	if is_land(wt.x, wt.y): _structure("water_tower", wt, Vector2(3.6, 3.6))
	for k in 4:
		loot_spots.append({"pos": c + Vector2(rng.randf_range(-25, 15), rng.randf_range(9, 19)), "military": false})

## Farm: a red barn, the farmhouse, two grain silos, hay bales and fields.
func _farm(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	_add_building(c + Vector2(-8, -6), Vector2(16, 10), false, 1, "barn")
	buildings[-1].doors = [0, 2]
	var hs := Vector2(11, 9)
	var hc := c + Vector2(16, 12)
	if not _overlaps(hc, hs * 0.5, 4.0):
		_add_building(hc, hs, false, 2 if rng.randf() < 0.6 else 1)
	for k in 2:
		var sp := c + Vector2(4.0 + k * 6.6, -12.0)
		_structure("silo", sp, Vector2(3.0, 3.0))
	for k in rng.randi_range(6, 10):
		var hp := c + Vector2(rng.randf_range(-40, 40), rng.randf_range(18, 45))
		if is_land(hp.x, hp.y) and not _overlaps(hp, Vector2(1, 1), 1.0):
			_structure("hay", hp, Vector2(0.8, 0.8), {"rot": rng.randi_range(0, 1) * 90})
	fields.append(Rect2(c + Vector2(-45, 15), Vector2(90, 40)))
	fields.append(Rect2(c + Vector2(-50, -55), Vector2(40, 38)))

## Gas stations by the roads: canopy over two pumps and a small shop.
func _gas_stations() -> void:
	var made := 0
	var order := range(roads.size())
	order.shuffle()
	for i in order:
		if made >= 3: break
		var rd: Dictionary = roads[i]
		var a: Vector2 = rd.a
		var b: Vector2 = rd.b
		if a.distance_to(b) < 300.0: continue
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var mid := a.lerp(b, rng.randf_range(0.35, 0.65))
		var c: Vector2 = mid + side * (rd.w * 0.5 + 9.0)
		var shop: Vector2 = c + side * 11.0
		if not (_land_around(c, 22.0) and _land_around(shop, 10.0)): continue
		if absf(c.y - river_z(c.x)) < 50.0: continue
		var near_town := false
		for t in towns:
			if c.distance_to(t.pos) < t.r + 60.0: near_town = true
		if near_town or _overlaps(c, Vector2(7, 7), 4.0) or _overlaps(shop, Vector2(6, 5), 4.0): continue
		var h := maxf(1.6, height_at(c.x, c.y))
		flatten((c + shop) * 0.5, Vector2(14, 14), 16.0, h)
		_structure("canopy", c, Vector2(5.5, 4.0), {"dir": dir})
		var door := (1 if -side.x > 0 else 3) if absf(side.x) > absf(side.y) else (2 if -side.y > 0 else 0)
		_add_building(shop, Vector2(9, 7), false, 1, "shop")
		buildings[-1].doors = [door]
		made += 1

func _buildings() -> void:
	for t in towns:
		if t.get("kind", "town") == "industrial":
			_industrial(t)
			continue
		if t.get("kind", "town") == "farm":
			_farm(t)
			continue
		var count: int = 11 if t.military else rng.randi_range(5, 9)
		var placed := 0
		var attempts := 0
		while placed < count and attempts < 500:
			attempts += 1
			var sz := Vector2(rng.randf_range(9, 16 if t.military else 13), rng.randf_range(8, 13 if t.military else 11))
			if t.military and rng.randf() < 0.35:
				sz = Vector2(rng.randf_range(18, 26), rng.randf_range(12, 16))   # warehouses
			var c: Vector2 = t.pos + Vector2(rng.randf_range(0, t.r), 0).rotated(rng.randf() * TAU)
			var half := sz * 0.5
			if not (is_land(c.x - half.x, c.y - half.y) and is_land(c.x + half.x, c.y + half.y) and is_land(c.x - half.x, c.y + half.y) and is_land(c.x + half.x, c.y - half.y)):
				continue
			if _overlaps(c, half, 7.0): continue
			if near_road(c, half.length() + 2.0): continue
			var storeys := 2 if not t.military and sz.x >= 10.0 and sz.y >= 8.5 and rng.randf() < 0.45 else 1
			_add_building(c, sz, t.military, storeys)
			placed += 1
	_gas_stations()
	# Lone houses in the countryside.
	var lone := 0
	var tries := 0
	var lone_want := int(26.0 * _area())
	while lone < lone_want and tries < 6000:
		tries += 1
		var sz := Vector2(rng.randf_range(8, 11), rng.randf_range(7, 10))
		var c := Vector2(rng.randf_range(100, size - 100), rng.randf_range(100, size - 100))
		if not _land_around(c, 22.0): continue
		if absf(c.y - river_z(c.x)) < 70.0: continue
		var near_town := false
		for t in towns:
			if c.distance_to(t.pos) < t.r + 80.0: near_town = true
		if near_town: continue
		if _overlaps(c, sz * 0.5, 60.0): continue
		if near_road(c, 10.0): continue
		_add_building(c, sz, false)
		lone += 1

func _blocked(p: Vector2, r: float) -> bool:
	if not _land_around(p, r) or height_at(p.x, p.y) < 1.4: return true
	if _overlaps(p, Vector2(r, r), 3.0): return true
	if near_road(p, r + 1.0): return true
	return false

## Map area relative to the original 3 km island (props scale with it).
func _area() -> float:
	return pow(size / 3072.0, 2.0)

func _props() -> void:
	var k_area := _area()
	# Forests and scattered trees.
	for f in int(70 * k_area):
		var c := Vector2(rng.randf_range(80, size - 80), rng.randf_range(80, size - 80))
		var pine := rng.randf() < 0.55
		for k in rng.randi_range(15, 40):
			var p := c + Vector2(absf(rng.randfn(0.0, 1.0)) * 55.0, 0).rotated(rng.randf() * TAU)
			_add_tree(p, pine if rng.randf() < 0.85 else not pine)
	for k in int(900 * k_area):
		_add_tree(Vector2(rng.randf_range(40, size - 40), rng.randf_range(40, size - 40)), rng.randf() < 0.4)
	for k in int(260 * k_area):
		var p := Vector2(rng.randf_range(60, size - 60), rng.randf_range(60, size - 60))
		var r := rng.randf_range(0.8, 2.6)
		if _blocked(p, r + 1.0): continue
		rocks.append({"pos": p, "r": r})
	for k in int(90 * k_area):
		var p := Vector2(rng.randf_range(80, size - 80), rng.randf_range(80, size - 80))
		if _blocked(p, 3.0): continue
		loot_spots.append({"pos": p, "military": false})

func _add_tree(p: Vector2, pine: bool) -> void:
	if _blocked(p, 2.5): return
	for t in towns:
		if p.distance_to(t.pos) < t.r * 0.8: return
	trees.append({"pos": p, "h": rng.randf_range(7.0, 13.0), "r": rng.randf_range(0.18, 0.32), "pine": pine, "shade": rng.randf()})

# ---------- Images for shaders and the map ----------
func height_image() -> Image:
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RF, heights.to_byte_array())
	img.convert(Image.FORMAT_RH)
	return img

## RGBA mask for the terrain shader: R = road, G = field, B = town ground.
func mask_image(res: int) -> Image:
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var k := res / size
	for t in towns:
		if t.get("kind", "town") != "farm":
			_disc(img, t.pos * k, (t.r + 25.0) * k, Color(0, 0, 1, 0), true)
	for f in fields:
		img.fill_rect(Rect2i(Vector2i(f.position * k), Vector2i(f.size * k)), Color(0, 1, 0, 0))
	for f in 22:
		var p := Vector2(rng.randf_range(100, size - 200), rng.randf_range(100, size - 200))
		var s := Vector2(rng.randf_range(60, 140), rng.randf_range(50, 110))
		if not (is_land(p.x, p.y) and is_land(p.x + s.x, p.y + s.y)) or height_at(p.x, p.y) > 30.0: continue
		img.fill_rect(Rect2i(Vector2i(p * k), Vector2i(s * k)), Color(0, 1, 0, 0))
	# Red 0.3: no grass under buildings and structures (roads use red >= 0.5).
	var rects := []
	for b in buildings:
		rects.append([b.pos, b.size * 0.5 + Vector2(1.5, 1.5)])
	for o in obstacles:
		rects.append([o.pos, o.half + Vector2(0.5, 0.5)])
	for r in rects:
		var x0 := maxi(0, int((r[0].x - r[1].x) * k))
		var x1 := mini(res - 1, int((r[0].x + r[1].x) * k) + 1)
		var y0 := maxi(0, int((r[0].y - r[1].y) * k))
		var y1 := mini(res - 1, int((r[0].y + r[1].y) * k) + 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var cur := img.get_pixel(x, y)
				if cur.r < 0.3:
					cur.r = 0.3
					img.set_pixel(x, y, cur)
	# Alpha: forest floor (leaf litter and moss) under and around the trees.
	for t in trees:
		_disc(img, t.pos * k, maxf(7.0 * k, 1.5), Color(0, 0, 0, 1), true)
	for rd in roads:
		var a: Vector2 = rd.a * k
		var b: Vector2 = rd.b * k
		var w: float = rd.w * k * 0.5
		var n := int(a.distance_to(b) / maxf(1.0, w * 0.5))
		for i in n + 1:
			_disc(img, a.lerp(b, float(i) / n), w, Color(1, 0, 0, 0), false)
	return img

func _disc(img: Image, c: Vector2, r: float, col: Color, soft: bool) -> void:
	var x0 := maxi(0, int(c.x - r))
	var x1 := mini(img.get_width() - 1, int(c.x + r))
	var y0 := maxi(0, int(c.y - r))
	var y1 := mini(img.get_height() - 1, int(c.y + r))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x, y).distance_to(c)
			if d > r: continue
			var cur := img.get_pixel(x, y)
			var a := 1.0 - smoothstep(r * 0.6, r, d) if soft else 1.0
			img.set_pixel(x, y, Color(maxf(cur.r, col.r * a), maxf(cur.g, col.g * a), maxf(cur.b, col.b * a), maxf(cur.a, col.a * a)))
