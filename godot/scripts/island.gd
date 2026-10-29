class_name Island
extends RefCounted
## The island: heightmap, towns, roads, bridges, building lots, trees and
## rocks. Pure data — world.gd turns it into nodes.
## The map is "جزيرة الفصول" (Seasons Island), laid out after a painted map
## (assets/map/seasons_land.png holds its coast, made by
## tools/map_from_image.py): snowy peaks across the north, a dark forest in the
## west, golden plains with farms and a lake in the middle, a desert of
## canyons in the south and a volcano land in the east, with a river from the
## mountains through the lake to the sea. Places and roads are written below
## in the picture's own pixels (1932 across = 8 km), see _m().

const N := 1025                # heightmap samples per side
const WATER := 0.0             # sea level (m)
const DEEP := -1.7             # deeper than this: too deep to wade
const REGION_TITLES := {"plains": "سهول الذهب", "nordic": "قمم الصقيع", "jungle": "غابة الظلال", "desert": "صحراء السراب", "volcano": "أرض البركان"}
const MAP_NAME := "جزيرة الفصول"
const SEA_NAME := "بحر اللازورد"
const BIOME_N := 256           # biome grid samples per side
const PIC := 1932.0            # width of the painted map the layout was taken from

# ---------- The layout (picture pixels) ----------
## Regions as outlines; plains are what is left over. The borders are warped
## a little when sampled, so they don't look drawn with a ruler.
const NORDIC_AREA := [Vector2(-200, -200), Vector2(2200, -200), Vector2(2200, 520), Vector2(1600, 540), Vector2(1400, 545),
	Vector2(1220, 560), Vector2(1180, 650), Vector2(1130, 730), Vector2(1000, 720), Vector2(850, 690), Vector2(700, 630),
	Vector2(600, 600), Vector2(400, 540), Vector2(230, 490), Vector2(-200, 470)]
const VOLCANO_AREA := [Vector2(1220, 560), Vector2(1400, 545), Vector2(1600, 540), Vector2(2200, 520), Vector2(2200, 2200),
	Vector2(1390, 2200), Vector2(1350, 1720), Vector2(1300, 1560), Vector2(1262, 1420), Vector2(1262, 1260), Vector2(1305, 1120),
	Vector2(1365, 1000), Vector2(1370, 820), Vector2(1265, 760), Vector2(1185, 680)]
const DESERT_AREA := [Vector2(-200, 1470), Vector2(250, 1470), Vector2(600, 1450), Vector2(800, 1440), Vector2(1000, 1450),
	Vector2(1150, 1440), Vector2(1262, 1420), Vector2(1300, 1560), Vector2(1350, 1720), Vector2(1390, 2200), Vector2(-200, 2200)]
const FOREST_AREA := [Vector2(190, 700), Vector2(350, 640), Vector2(560, 650), Vector2(650, 720), Vector2(700, 900),
	Vector2(690, 1050), Vector2(650, 1200), Vector2(600, 1300), Vector2(560, 1420), Vector2(400, 1460), Vector2(230, 1460),
	Vector2(185, 1200), Vector2(170, 900)]
## Big labels on the map for the regions, the sea and the island.
const REGION_LABELS := {"nordic": Vector2(965, 520), "jungle": Vector2(385, 870), "plains": Vector2(700, 1375),
	"desert": Vector2(385, 1570), "volcano": Vector2(1690, 725)}
## Places: name, kind, centre, radius in metres, region, military (best loot).
const PLACES := [
	["قرية الجليد", "town", Vector2(555, 425), 115.0, "nordic", false],
	["المرصد", "observatory", Vector2(1450, 372), 60.0, "nordic", false],
	["حصن الصنوبر", "town", Vector2(385, 1015), 125.0, "jungle", false],
	["الميناء الغربي", "port", Vector2(228, 1318), 90.0, "plains", false],
	["مزارع الشمال", "farm", Vector2(805, 765), 70.0, "plains", false],
	["المزارع", "farm", Vector2(968, 1262), 70.0, "plains", false],
	["مدينة الشفق", "city", Vector2(1225, 892), 300.0, "plains", false],
	["منجم الكبريت", "mine", Vector2(1470, 738), 70.0, "volcano", true],
	["فوهة اللهب", "crater", Vector2(1595, 965), 60.0, "volcano", false],
	["مرفأ الرماد", "port", Vector2(1642, 1478), 140.0, "volcano", false],
	["واحة السراب", "town", Vector2(715, 1622), 160.0, "desert", false],
	["مطار الرمال", "airport", Vector2(1070, 1652), 150.0, "desert", true],
	["الأطلال", "ruins", Vector2(1095, 1795), 55.0, "desert", false],
	["المنارة", "lighthouse", Vector2(1823, 98), 35.0, "nordic", false],
	["قاعدة الصقر", "base", Vector2(950, 330), 90.0, "nordic", true],
	["قرية البازلت", "town", Vector2(1800, 1100), 100.0, "volcano", false],
	["محطة الطاقة", "industrial", Vector2(1550, 1200), 80.0, "volcano", false],
	["مخيم الحطابين", "town", Vector2(350, 780), 80.0, "jungle", false],
	["قرية الضفة", "town", Vector2(285, 1190), 85.0, "jungle", false],
	["المنطقة الصناعية", "industrial", Vector2(1050, 1450), 90.0, "plains", false],
	["قرية الكثبان", "town", Vector2(300, 1600), 100.0, "desert", false],
]
## Small islands the painting has but the coast map may have lost: centre, radius (px).
const ISLETS := [[Vector2(1823, 98), 42.0], [Vector2(1095, 1800), 30.0], [Vector2(105, 1822), 45.0]]
## Paved roads (w 9 m) and dirt tracks (w 6 m) as polylines.
const PAVED := [
	[Vector2(555, 430), Vector2(620, 490), Vector2(700, 560), Vector2(755, 640), Vector2(790, 730), Vector2(800, 850),
		Vector2(800, 960), Vector2(802, 1066), Vector2(815, 1180), Vector2(828, 1300), Vector2(835, 1400), Vector2(820, 1480),
		Vector2(790, 1550), Vector2(755, 1605), Vector2(730, 1620)],
	[Vector2(400, 1020), Vector2(500, 1028), Vector2(620, 1050), Vector2(720, 1065), Vector2(802, 1066), Vector2(860, 1030),
		Vector2(930, 962), Vector2(1010, 930), Vector2(1090, 905), Vector2(1150, 895)],
	[Vector2(1215, 820), Vector2(1265, 740), Vector2(1320, 640), Vector2(1370, 540), Vector2(1410, 450), Vector2(1450, 388)],
	[Vector2(1335, 950), Vector2(1325, 1050), Vector2(1305, 1150), Vector2(1300, 1255), Vector2(1330, 1310), Vector2(1410, 1370),
		Vector2(1500, 1415), Vector2(1590, 1455), Vector2(1640, 1475)],
]
const DIRT := [
	[Vector2(290, 265), Vector2(380, 300), Vector2(460, 340), Vector2(530, 400), Vector2(555, 425)],
	[Vector2(540, 440), Vector2(495, 540), Vector2(450, 660), Vector2(415, 800), Vector2(392, 930), Vector2(385, 1015),
		Vector2(370, 1100), Vector2(335, 1200), Vector2(290, 1280), Vector2(250, 1318)],
	[Vector2(1450, 380), Vector2(1540, 410), Vector2(1640, 400), Vector2(1740, 345)],
	[Vector2(1340, 900), Vector2(1400, 830), Vector2(1450, 770), Vector2(1470, 742)],
	[Vector2(1310, 1265), Vector2(1400, 1200), Vector2(1480, 1140), Vector2(1540, 1090)],
	[Vector2(450, 1700), Vector2(600, 1690), Vector2(760, 1682), Vector2(935, 1688)],
	[Vector2(815, 1490), Vector2(880, 1570), Vector2(960, 1640), Vector2(1030, 1720), Vector2(1080, 1785)],
	[Vector2(620, 490), Vector2(720, 430), Vector2(830, 370), Vector2(935, 335)],
	[Vector2(1540, 1090), Vector2(1640, 1085), Vector2(1730, 1095), Vector2(1790, 1100)],
	[Vector2(1480, 1140), Vector2(1520, 1175), Vector2(1550, 1195)],
	[Vector2(415, 800), Vector2(380, 790), Vector2(355, 782)],
	[Vector2(835, 1400), Vector2(930, 1420), Vector2(1040, 1448)],
	[Vector2(450, 1700), Vector2(380, 1660), Vector2(310, 1605)],
]
const RUNWAY := [Vector2(935, 1682), Vector2(1200, 1612)]
## Water: the lake (centre, radii in px) with its islet, and the river from
## the mountains into the lake and on from the lake to the sea.
const LAKE_C := Vector2(965, 1037)
const LAKE_R := Vector2(130, 77)
const LAKE_ISLET := Vector2(930, 1024)
const RIVERS := [
	[Vector2(1010, 325), Vector2(1000, 400), Vector2(962, 480), Vector2(932, 560), Vector2(916, 650), Vector2(915, 760),
		Vector2(924, 860), Vector2(932, 940), Vector2(940, 975)],
	[Vector2(1060, 1060), Vector2(1100, 1080), Vector2(1150, 1105), Vector2(1200, 1160), Vector2(1250, 1230), Vector2(1272, 1300),
		Vector2(1278, 1415), Vector2(1285, 1560), Vector2(1320, 1660), Vector2(1366, 1736), Vector2(1385, 1800)],
]
## Lava from the crater down the volcano, each ending in a pool.
const CRATER := Vector2(1595, 965)
const LAVA := [
	[Vector2(1595, 965), Vector2(1576, 1010), Vector2(1560, 1060), Vector2(1520, 1110), Vector2(1480, 1160), Vector2(1450, 1208), Vector2(1435, 1235)],
	[Vector2(1595, 965), Vector2(1615, 1010), Vector2(1640, 1060), Vector2(1690, 1110), Vector2(1730, 1160), Vector2(1765, 1205), Vector2(1780, 1225)],
	[Vector2(1560, 1060), Vector2(1520, 1085), Vector2(1470, 1110)],
]
const LAVA_POOLS := [[Vector2(1435, 1237), 17.0], [Vector2(1780, 1226), 14.0]]
## Crop fields of the two farm areas (px rectangles).
const FIELD_AREAS := [Rect2(700, 705, 190, 125), Rect2(880, 1170, 210, 175)]

var size: float
var map_id := "seasons"        # "seasons" | "dunes"
var L: Dictionary              # the map's layout (see SEASONS and DUNES at the end)
var step: float
var heights := PackedFloat32Array()
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var towns: Array = []          # {name, pos: Vector2, r, military, kind, region}
var roads: Array = []          # {a: Vector2, b: Vector2, w, dirt?, runway?}
var bridges: Array = []        # {a, b, w}
var buildings: Array = []      # {pos: Vector2 (centre), size: Vector2, rot: 0|90, floor, military, doors: Array}
var trees: Array = []          # {pos: Vector2, h, r, pine}
var rocks: Array = []          # {pos: Vector2, r}
var loot_spots: Array = []     # {pos: Vector2, military, level?}
var structures: Array = []     # {kind, pos: Vector2, rot (0 or 90), level, col} containers, silos, towers...
var obstacles: Array = []      # {pos: Vector2, half: Vector2} footprints of structures
var fields: Array = []         # Rect2 crop fields next to farms
var boat_spots: Array = []     # {pos: Vector2, dir: Vector2 (out to sea)} boats tied up at the piers
var lava: Array = []           # polylines of world points (Vector2), see LAVA
var lava_pools: Array = []     # [centre: Vector2, radius]
var crater := Vector2.ZERO
var labels := {}               # region -> world position of its name on the map
var warp := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
## Region weights on a coarse grid: desert, jungle (the forest), nordic, volcano (plains = the rest).
var biome := PackedFloat32Array()
var _water_d := PackedFloat32Array()   # per height sample: metres to the nearest river line
var _lava_d := PackedFloat32Array()    # per height sample: metres to the nearest lava line

func _init(seed_value: int, map_size: float, which := "seasons") -> void:
	map_id = which if which == "dunes" else "seasons"
	L = DUNES if map_id == "dunes" else SEASONS
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
	warp.seed = seed_value + 13
	warp.frequency = 1.0 / 1400.0
	warp.fractal_octaves = 2
	ridge.seed = seed_value + 21
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.frequency = 1.0 / 700.0
	ridge.fractal_octaves = 4

func generate() -> void:
	_heights()
	_towns()
	_roads()
	_carve_water()
	_buildings()
	_props()

## A point of the painted map (pixels) in world metres.
func _m(p: Vector2) -> Vector2:
	return p * size / L.pic

func _poly(src: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in src: out.append(_m(p))
	return out

# ---------- Terrain ----------
## Metres from the coast: positive inland, negative out at sea.
func coast_at(x: float, z: float) -> float:
	if _coast_w == 0: _load_coast()
	var w := _coast_w
	var fx := clampf(x / size * w - 0.5, 0.0, w - 1.001)
	var fz := clampf(z / size * w - 0.5, 0.0, w - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var o := j * w + i
	var m := lerpf(lerpf(_coast_m[o], _coast_m[o + 1], tx), lerpf(_coast_m[o + w], _coast_m[o + w + 1], tx), tz)
	# The small islands, round as painted.
	for il in _islets:
		var c: Vector2 = il[0]
		var r: float = il[1]
		var dx := x - c.x
		var dz := z - c.y
		if dx * dx + dz * dz < (r + 40.0) * (r + 40.0):
			m = maxf(m, r - sqrt(dx * dx + dz * dz) + detail.get_noise_2d(x, z) * 12.0)
	return m

var _coast_m := PackedFloat32Array()   # metres from the shore per pixel of the coast map
var _coast_w := 0
var _islets: Array = []                # [centre, radius] in metres

func _load_coast() -> void:
	var img := (load(String(L.coast)) as Image).duplicate()
	img.convert(Image.FORMAT_L8)
	_coast_w = img.get_width()
	var data: PackedByteArray = img.get_data()
	_coast_m.resize(data.size())
	for k in data.size():
		_coast_m[k] = (float(data[k]) - 128.0) * 2.0
	for il in L.islets:
		_islets.append([_m(il[0]), _m(Vector2(il[1], 0)).x])

# ---------- Regions ----------
func _biomes() -> void:
	var polys := [_poly(L.desert), _poly(L.forest), _poly(L.nordic), _poly(L.volcano)]
	var raw := PackedFloat32Array()
	raw.resize(BIOME_N * BIOME_N * 4)
	for j in BIOME_N:
		for i in BIOME_N:
			var x := (i + 0.5) / BIOME_N * size
			var z := (j + 0.5) / BIOME_N * size
			var q := Vector2(x + warp.get_noise_2d(x, z) * 160.0, z + warp.get_noise_2d(x + 5000.0, z - 3000.0) * 160.0)
			for c in 4:
				if Geometry2D.is_point_in_polygon(q, polys[c]):
					raw[(j * BIOME_N + i) * 4 + c] = 1.0
					break
	# Soft borders: average over a few cells (about 100 m), across then down.
	biome.resize(BIOME_N * BIOME_N * 4)
	var rad := 3
	var tmp := PackedFloat32Array()
	tmp.resize(raw.size())
	for pass_i in 2:
		var src := raw if pass_i == 0 else tmp
		var dst := tmp if pass_i == 0 else biome
		for j in BIOME_N:
			for i in BIOME_N:
				for c in 4:
					var sum := 0.0
					for d in range(-rad, rad + 1):
						var ii := clampi(i + d, 0, BIOME_N - 1) if pass_i == 0 else i
						var jj := j if pass_i == 0 else clampi(j + d, 0, BIOME_N - 1)
						sum += src[(jj * BIOME_N + ii) * 4 + c]
					dst[(j * BIOME_N + i) * 4 + c] = sum / (2 * rad + 1)

	# The lighthouse rock is bare dark stone as painted, not snowfield.
	var lh := _m(L.islets[0][0])
	var lr: float = _m(Vector2(L.islets[0][1], 0)).x * 1.8
	for j in BIOME_N:
		for i in BIOME_N:
			var q := Vector2((i + 0.5) / BIOME_N * size, (j + 0.5) / BIOME_N * size)
			var k := 1.0 - smoothstep(lr * 0.7, lr, q.distance_to(lh))
			if k <= 0.0: continue
			var o := (j * BIOME_N + i) * 4
			for c in 4: biome[o + c] = lerpf(biome[o + c], 1.0 if c == 3 else 0.0, k)

## Region weights at a point: [desert, jungle (forest), nordic, volcano].
func biome_at(x: float, z: float) -> Array:
	var fx := clampf(x / size * BIOME_N - 0.5, 0.0, BIOME_N - 1.001)
	var fz := clampf(z / size * BIOME_N - 0.5, 0.0, BIOME_N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var res := [0.0, 0.0, 0.0, 0.0]
	for c in 4:
		var a := biome[(j * BIOME_N + i) * 4 + c]
		var b := biome[(j * BIOME_N + i + 1) * 4 + c]
		var d := biome[((j + 1) * BIOME_N + i) * 4 + c]
		var e := biome[((j + 1) * BIOME_N + i + 1) * 4 + c]
		res[c] = lerpf(lerpf(a, b, tx), lerpf(d, e, tx), tz)
	return res

## The strongest region at a point: plains, desert, jungle (the forest), nordic or volcano.
func region_at(x: float, z: float) -> String:
	var w := biome_at(x, z)
	var best := "plains"
	var bw := 0.5
	var names := ["desert", "jungle", "nordic", "volcano"]
	for c in 4:
		if w[c] > bw:
			bw = w[c]
			best = names[c]
	return best

## Distance from every height sample within `reach` of the polylines to the
## nearest of them (only the samples near each segment are visited).
func _line_field(lines: Array, reach: float) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(N * N)
	f.fill(1e9)
	for line in lines:
		for k in line.size() - 1:
			var a: Vector2 = line[k]
			var b: Vector2 = line[k + 1]
			var i0 := maxi(0, int((minf(a.x, b.x) - reach) / step))
			var i1 := mini(N - 1, int((maxf(a.x, b.x) + reach) / step) + 1)
			var j0 := maxi(0, int((minf(a.y, b.y) - reach) / step))
			var j1 := mini(N - 1, int((maxf(a.y, b.y) + reach) / step) + 1)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var p := Vector2(i * step, j * step)
					var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
					var o := j * N + i
					if d < f[o]: f[o] = d
	return f

## How far into the lake a point is: < 1 inside the water (0 at the centre).
func lake_t(p: Vector2) -> float:
	var c := _m(L.lake_c)
	var r := _m(L.lake_r)
	var wob := 1.0 + detail.get_noise_2d(p.x * 2.0, p.y * 2.0) * 0.08
	return Vector2((p.x - c.x) / r.x, (p.y - c.y) / r.y).length() * wob

## Near the lake or a river (for keeping houses and towns off the banks).
func near_water(p: Vector2, pad: float) -> bool:
	if lake_t(p) < 1.0 + pad / _m(L.lake_r).y: return true
	for line in L.rivers:
		for k in line.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, _m(line[k]), _m(line[k + 1])).distance_to(p) < 22.0 + pad:
				return true
	return false

## On the glowing lava (a flow, a pool or the crater lake).
func on_lava(p: Vector2) -> bool:
	if p.distance_to(crater) < 55.0: return true
	for pl in lava_pools:
		if p.distance_to(pl[0]) < pl[1]: return true
	for line in lava:
		for k in line.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1]).distance_to(p) < 7.0:
				return true
	return false

func _heights() -> void:
	_biomes()
	crater = _m(L.crater_px)
	for line in L.lava_px:
		var pts := []
		for q in line: pts.append(_m(q))
		lava.append(pts)
	for pl in L.lava_pools_px: lava_pools.append([_m(pl[0]), _m(Vector2(pl[1], 0)).x])
	for reg in L.region_labels: labels[reg] = _m(L.region_labels[reg])
	var rivers := []
	for line in L.rivers:
		var pts := []
		for q in line: pts.append(_m(q))
		rivers.append(pts)
	_water_d = _line_field(rivers, 220.0)
	_lava_d = _line_field(lava, 40.0)
	var islet := _m(L.lake_islet)
	var lake_c := _m(L.lake_c)
	var lake_r := _m(L.lake_r)
	heights.resize(N * N)
	for j in N:
		for i in N:
			var x := i * step
			var z := j * step
			var o := j * N + i
			var s := coast_at(x, z)
			var h: float
			if s <= 0.0:
				# Sea floor: shelves off from the beach.
				h = maxf(-24.0, -0.8 + s * 0.09)
			else:
				var bw := biome_at(x, z)
				var n0 := (noise.get_noise_2d(x + 2000.0, z + 900.0) + 1.0) * 0.5
				var plains := 2.0 + pow(n0, 2.0) * 26.0
				# Forest: rolling wooded hills.
				# (Each region's shape is only worked out where that region is.)
				var forest := 0.0
				if bw[1] > 0.001: forest = 4.0 + pow((noise.get_noise_2d(x * 1.6, z * 1.6) + 1.0) * 0.5, 1.6) * 62.0
				# Snowy peaks: ridges, higher towards the north coast.
				var nordic := 0.0
				if bw[2] > 0.001:
					var north_k := 1.0 - smoothstep(size * 0.08, size * 0.36, z)
					nordic = 30.0 + pow(n0, 1.4) * 70.0 + maxf(0.0, ridge.get_noise_2d(x, z)) * (90.0 + 150.0 * north_k)
				# Desert: canyons and flat-topped mesas in steps.
				var mesa := floorf(n0 * 4.5) / 4.5
				mesa = lerpf(mesa, n0, 0.25)
				var desert := 5.0 + pow(mesa, 1.5) * 95.0
				if map_id == "dunes":
					# Dune Valley: rolling sand dunes in long crests across the
					# wind, rocky hills now and then, a dry valley down the middle.
					var crest := absf(sin((x * 0.62 + z * 0.78) / 48.0 + detail.get_noise_2d(x * 0.4, z * 0.4) * 3.5))
					var hill := maxf(0.0, ridge.get_noise_2d(x * 0.8, z * 0.8)) * 70.0 * smoothstep(0.35, 0.75, n0)
					desert = 4.0 + pow(n0, 1.3) * 34.0 + pow(crest, 3.0) * 7.0 * (0.4 + n0) + hill
				# Volcano land: rough black ground rising to the cone.
				var volcano := 0.0
				if bw[3] > 0.001:
					var dc := Vector2(x, z).distance_to(crater)
					var cone := 235.0 * pow(clampf(1.0 - dc / 1500.0, 0.0, 1.0), 1.6)
					if dc < 110.0:
						cone -= 38.0 * (1.0 - smoothstep(55.0, 110.0, dc))     # the crater bowl
					volcano = 6.0 + pow(n0, 1.5) * 34.0 + cone + detail.get_noise_2d(x * 2.0, z * 2.0) * 6.0
				var sw: float = bw[0] + bw[1] + bw[2] + bw[3]
				var hills: float = plains * maxf(0.0, 1.0 - sw) + (desert * bw[0] + forest * bw[1] + nordic * bw[2] + volcano * bw[3]) / maxf(1.0, sw)
				# Beaches: low near the shore (the cone and cliffs rise behind).
				h = 1.2 + hills * smoothstep(0.0, 260.0, s)
				# The small islands are low rocks, whatever region they lie in.
				for il in _islets:
					var ir: float = il[1] * 1.4
					var di0 := Vector2(x, z).distance_to(il[0])
					if di0 < ir: h = minf(h, 1.4 + 7.0 * smoothstep(0.0, ir * 0.6, ir - di0))
				# The lake: shallow round the edge, deep in the middle, with its islet.
				var lt := 9.0
				if absf(x - lake_c.x) < lake_r.x * 2.0 and absf(z - lake_c.y) < lake_r.y * 2.5: lt = lake_t(Vector2(x, z))
				if lt < 1.0:
					h = lerpf(-6.0, -0.9, lt * lt)
				else:
					h = minf(h, 1.0 + (lt - 1.0) * 60.0)
				var di := Vector2(x, z).distance_to(islet)
				if di < 70.0: h = maxf(h, lerpf(3.2, -1.0, smoothstep(30.0, 70.0, di)))
				# Rivers: wadeable, in a valley (a gorge through the mountains).
				var dr := _water_d[o]
				var rw := 20.0
				if dr < 1e8: rw += (detail.get_noise_2d(x, z * 0.5) + 1.0) * 6.0
				if dr < rw:
					h = -1.2
				elif dr < 1e8:
					h = minf(h, 1.0 + (dr - rw) * 0.14 + h * smoothstep(rw, rw + 160.0, dr))
				# Lava runs in a shallow trough down the slope.
				var dl := _lava_d[o]
				if dl < 16.0: h -= 1.6 * (1.0 - smoothstep(6.0, 16.0, dl))
			heights[o] = h
	# The crater floor and the lava pools are level.
	flatten(crater, Vector2(50, 50), 30.0, height_at(crater.x, crater.y))
	for pl in lava_pools:
		flatten(pl[0], Vector2(pl[1], pl[1]) * 0.7, pl[1] * 0.5, height_at(pl[0].x, pl[0].y) - 0.8)

## Rivers and the lake again, after towns, fields and the runway were levelled
## (the levelling must not dam them).
func _carve_water() -> void:
	var lc := _m(L.lake_c)
	var lr := _m(L.lake_r)
	for j in N:
		for i in N:
			var o := j * N + i
			var p := Vector2(i * step, j * step)
			if _water_d[o] < 20.0: heights[o] = minf(heights[o], -1.2)
			if absf(p.x - lc.x) > lr.x * 1.3 or absf(p.y - lc.y) > lr.y * 1.3: continue
			var lt := lake_t(p)
			if lt < 1.0 and p.distance_to(_m(L.lake_islet)) > 40.0:
				heights[o] = minf(heights[o], lerpf(-6.0, -0.9, lt * lt))

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
	for pl in L.places:
		var t := {"name": pl[0], "kind": pl[1], "pos": _m(pl[2]), "r": pl[3], "region": pl[4], "military": pl[5]}
		towns.append(t)
	for t in towns:
		if t.kind in ["crater", "lighthouse", "ruins", "castle"]: continue
		# Town ground: level, a little above the sea (ports stay low by the water).
		var level := maxf(1.6, height_at(t.pos.x, t.pos.y) * (0.5 if not t.kind in ["city", "medina"] else 0.35))
		if t.kind == "port": level = maxf(1.8, height_at(t.pos.x, t.pos.y) * 0.3)
		var half := Vector2(t.r, t.r) * (0.85 if t.kind in ["city", "medina"] else 1.0)
		flatten(t.pos, half, 110.0, level)
	for fa in L.fields:
		var r: Rect2 = fa
		var c := _m(r.get_center())
		flatten(c, _m(r.size) * 0.5, 60.0, maxf(1.8, height_at(c.x, c.y)))

func _roads() -> void:
	for spec in [[L.paved, 9.0, false], [L.dirt, 6.0, true]]:
		for line in spec[0]:
			for k in line.size() - 1:
				roads.append({"a": _m(line[k]), "b": _m(line[k + 1]), "w": spec[1], "dirt": spec[2]})
	var ra := _m(L.runway[0])
	var rb := _m(L.runway[1])
	roads.append({"a": ra, "b": rb, "w": 42.0, "runway": true})
	# The runway and its apron are flat.
	var mid := (ra + rb) * 0.5
	var lv := maxf(4.0, height_at(mid.x, mid.y))
	var n := int(ra.distance_to(rb) / 40.0)
	for k in n + 1:
		var p := ra.lerp(rb, float(k) / n)
		flatten(p, Vector2(30, 30), 50.0, lv)
	# Bridges where roads cross water.
	for rd in roads:
		var a: Vector2 = rd.a
		var b: Vector2 = rd.b
		var length := a.distance_to(b)
		var steps := maxi(1, int(length / 4.0))
		var start := -1.0
		for k in steps + 1:
			var t := float(k) / steps
			var p := a.lerp(b, t)
			var wet := height_at(p.x, p.y) < 0.6
			if wet and start < 0.0:
				start = maxf(0.0, t - 12.0 / length)
			if (not wet or k == steps) and start >= 0.0:
				var t2 := minf(1.0, t + 12.0 / length)
				bridges.append({"a": a.lerp(b, start), "b": a.lerp(b, t2), "w": rd.w + 1.0})
				start = -1.0
	_road_grid()

## Road segments listed per 128 m cell they pass near (built after the roads).
const RD_CELL := 128.0
var _rd := {}

func _road_grid() -> void:
	_rd.clear()
	for rd in roads:
		var a: Vector2 = rd.a
		var b: Vector2 = rd.b
		var n := int(a.distance_to(b) / 32.0) + 1
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var key := Vector2i(floori(p.x / RD_CELL) + di, floori(p.y / RD_CELL) + dj)
					if not _rd.has(key): _rd[key] = []
					if not _rd[key].has(rd): _rd[key].append(rd)

func near_road(p: Vector2, pad: float) -> bool:
	if not _rd.is_empty():
		for rd in _rd.get(Vector2i(floori(p.x / RD_CELL), floori(p.y / RD_CELL)), []):
			if Geometry2D.get_closest_point_to_segment(p, rd.a, rd.b).distance_to(p) < rd.w * 0.5 + pad:
				return true
		return false
	for rd in roads:
		if Geometry2D.get_closest_point_to_segment(p, rd.a, rd.b).distance_to(p) < rd.w * 0.5 + pad:
			return true
	return false

## Footprints of buildings and structures in 64 m cells (the big map has
## thousands of things to check against).
const FP_CELL := 64.0
var _fp := {}

func _fp_add(c: Vector2, half: Vector2) -> void:
	var a := Vector2i(floori((c.x - half.x) / FP_CELL), floori((c.y - half.y) / FP_CELL))
	var b := Vector2i(floori((c.x + half.x) / FP_CELL), floori((c.y + half.y) / FP_CELL))
	for j in range(a.y, b.y + 1):
		for i in range(a.x, b.x + 1):
			var k := Vector2i(i, j)
			if not _fp.has(k): _fp[k] = []
			_fp[k].append([c, half])

func _overlaps(c: Vector2, half: Vector2, pad: float) -> bool:
	var a := Vector2i(floori((c.x - half.x - pad) / FP_CELL), floori((c.y - half.y - pad) / FP_CELL))
	var b := Vector2i(floori((c.x + half.x + pad) / FP_CELL), floori((c.y + half.y + pad) / FP_CELL))
	for j in range(a.y, b.y + 1):
		for i in range(a.x, b.x + 1):
			for o in _fp.get(Vector2i(i, j), []):
				var oc: Vector2 = o[0]
				var oh: Vector2 = o[1]
				if absf(c.x - oc.x) < half.x + oh.x + pad and absf(c.y - oc.y) < half.y + oh.y + pad:
					return true
	return false

func _add_building(c: Vector2, sz: Vector2, military: bool, storeys := 1, kind := "house") -> void:
	var floor_h := maxf(1.6, height_at(c.x, c.y))
	# Ground a little below the floor boards so it never shows through them.
	flatten(c, sz * 0.5, 14.0, floor_h - 0.12)
	# Door on one or two sides: 0 = -z, 1 = +x, 2 = +z, 3 = -x
	var doors := [rng.randi_range(0, 3)]
	if rng.randf() < 0.5 and kind != "apartment":
		doors.append((doors[0] + 2) % 4)
	# Two-storey houses: the staircase runs along a wall without a door.
	var stair := -1
	if storeys > 1:
		var free := [0, 1, 2, 3].filter(func(w): return not doors.has(w))
		stair = free[rng.randi() % free.size()]
		# Apartment blocks: the flights take turns along two opposite walls,
		# both without a door.
		if kind == "apartment": stair = (doors[0] + 1 + 2 * rng.randi_range(0, 1)) % 4
	_fp_add(c, sz * 0.5)
	buildings.append({"pos": c, "size": sz, "floor": floor_h, "military": military, "doors": doors,
		"tint": rng.randi_range(0, 4), "roof": rng.randi_range(0, 4), "storeys": storeys, "stair": stair, "kind": kind,
		"style": "plains" if military else region_at(c.x, c.y)})
	for k in rng.randi_range(2, 5 if military else 4):
		loot_spots.append({"pos": c + Vector2(rng.randf_range(-sz.x * 0.35, sz.x * 0.35), rng.randf_range(-sz.y * 0.35, sz.y * 0.35)), "military": military})
	for lv in range(1, storeys):
		for k in rng.randi_range(2, 3):
			loot_spots.append({"pos": c + Vector2(rng.randf_range(-sz.x * 0.25, sz.x * 0.25), rng.randf_range(-sz.y * 0.25, sz.y * 0.25)), "military": false, "level": lv})
	if kind == "apartment":
		loot_spots.append({"pos": c + Vector2(rng.randf_range(-sz.x * 0.2, sz.x * 0.2), rng.randf_range(-sz.y * 0.2, sz.y * 0.2)), "military": rng.randf() < 0.5, "level": storeys})

func _structure(kind: String, p: Vector2, half: Vector2, extra := {}) -> void:
	var d := {"kind": kind, "pos": p, "rot": 0, "level": 0, "col": rng.randi_range(0, 4)}
	d.merge(extra, true)
	structures.append(d)
	obstacles.append({"pos": p, "half": half})
	_fp_add(p, half)

## Factory yard: two big warehouses, rows of shipping containers (some
## stacked), a tall brick chimney and a water tower.
func _industrial(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	for k in 2:
		var bc := c + Vector2(-17.0 + k * 34.0, -14.0)
		_add_building(bc, Vector2(24, 14), false, 1, "warehouse")
		buildings[-1].doors = [0, 2]
		# Up on the gallery (WorldBuilder._mezzanine) at the -x end.
		for j in 2:
			loot_spots.append({"pos": bc + Vector2(-12.0 + 2.6, rng.randf_range(-3.5, 4.5)), "military": rng.randf() < 0.4, "level": 1})
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
		if near_water(c, 30.0) or lava_dist(c) < 40.0: continue
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
	for fa in L.fields:
		var r: Rect2 = fa
		# The painted fields: a patchwork of plots with tracks between.
		var a := _m(r.position)
		var b := _m(r.end)
		var y := a.y
		while y < b.y - 20.0:
			var x := a.x
			var hgt := rng.randf_range(40.0, 70.0)
			while x < b.x - 20.0:
				var w := rng.randf_range(45.0, 80.0)
				fields.append(Rect2(Vector2(x, y), Vector2(minf(w, b.x - x) - 6.0, minf(hgt, b.y - y) - 6.0)))
				x += w
			y += hgt
	for t in towns:
		match t.get("kind", "town"):
			"industrial": _industrial(t); continue
			"farm": _farm(t); continue
			"city": _city(t); continue
			"port": _port(t)
			"observatory": _observatory(t); continue
			"mine": _mine(t); continue
			"airport": _airport(t); continue
			"ruins": _ruins(t); continue
			"lighthouse": _lighthouse(t); continue
			"medina": _medina(t); continue
			"castle": _castle(t); continue
			"base": _base(t); continue
			"crater":
				for k in 6:
					loot_spots.append({"pos": t.pos + Vector2(rng.randf_range(70.0, 100.0), 0).rotated(rng.randf() * TAU), "military": true})
				continue
		var count: int = clampi(int(float(t.r) / 14.0), 5, 12)
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
			if storeys == 2 and sz.x >= 10.5 and sz.y >= 9.0 and rng.randf() < 0.5:
				# Apartment block: three or four storeys and a flat roof to fight from.
				_add_building(c, sz, false, rng.randi_range(3, 4), "apartment")
			elif storeys == 1 and not t.military and rng.randf() < 0.12:
				_add_building(c, sz, false, 1, "ruin")
			else:
				_add_building(c, sz, t.military, storeys)
			placed += 1
	_model_buildings()
	_gas_stations()
	_windmills()
	# Lone houses in the countryside.
	var lone := 0
	var tries := 0
	var lone_want := int(26.0 * _area())
	while lone < lone_want and tries < 6000:
		tries += 1
		var sz := Vector2(rng.randf_range(8, 11), rng.randf_range(7, 10))
		var c := Vector2(rng.randf_range(100, size - 100), rng.randf_range(100, size - 100))
		if not _land_around(c, 22.0): continue
		if near_water(c, 50.0) or lava_dist(c) < 60.0 or c.distance_to(crater) < 300.0: continue
		var near_town := false
		for t in towns:
			if c.distance_to(t.pos) < t.r + 80.0: near_town = true
		if near_town: continue
		if _overlaps(c, sz * 0.5, 60.0): continue
		if near_road(c, 10.0): continue
		_add_building(c, sz, false, 1, "ruin" if rng.randf() < 0.12 else "house")
		lone += 1

## Metres to the nearest lava flow or pool.
func lava_dist(p: Vector2) -> float:
	var best := p.distance_to(crater) - 55.0
	for pl in lava_pools: best = minf(best, p.distance_to(pl[0]) - pl[1])
	for line in lava:
		for k in line.size() - 1:
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1]).distance_to(p) - 7.0)
	return best

## Houses scattered in a ring round c (the usual town builder, reused by the special places).
func _houses(c: Vector2, r: float, count: int, military := false, two_storey := 0.45) -> void:
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 400:
		attempts += 1
		var sz := Vector2(rng.randf_range(9, 13), rng.randf_range(8, 11))
		var p := c + Vector2(rng.randf_range(0, r), 0).rotated(rng.randf() * TAU)
		var half := sz * 0.5
		if not _land_around(p, half.length() + 2.0): continue
		if _overlaps(p, half, 7.0) or near_road(p, half.length() + 2.0) or near_water(p, 10.0): continue
		var storeys := 2 if sz.x >= 10.0 and sz.y >= 8.5 and rng.randf() < two_storey else 1
		_add_building(p, sz, military, storeys)
		placed += 1

## The big city: blocks of houses on a street grid round a park, with the
## apartment blocks and towers in the middle.
func _city(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	var r: float = t.r
	var models := ["bld_pool", "bld_tower", "bld_tenement", "bld_tower", "bld_tenement", "bld_tower", "bld_tenement", "bld_house", "bld_shed", "bld_warehouse"]
	for kind in models:
		for attempt in 60:
			var rot := rng.randi_range(0, 3)
			var fp: Vector2 = MODEL_BUILDINGS[kind]
			var half := (fp if rot % 2 == 0 else Vector2(fp.y, fp.x)) * 0.5
			var p := c + Vector2(rng.randf_range(40.0, r * 0.55), 0).rotated(rng.randf() * TAU)
			if not _land_around(p, half.length() + 2.0): continue
			if _overlaps(p, half, 9.0) or near_road(p, half.length() + 3.0): continue
			flatten(p, half, 10.0, maxf(1.6, height_at(p.x, p.y)))
			_structure(kind, p, half, {"rot": rot, "half": half})
			_model_loot(kind, p, half)
			break
	# Street grid: lots of 36 m with paved streets between them, a house on
	# most lots, the middle left as a park.
	var cell := 36.0
	var n := int(r / cell)
	for gi in range(-n, n):
		var off := (gi + 0.5) * cell
		var half_len := sqrt(maxf(0.0, r * r - off * off))
		if half_len < 40.0: continue
		_street(c + Vector2(off, -half_len), c + Vector2(off, half_len))
		_street(c + Vector2(-half_len, off), c + Vector2(half_len, off))
	_road_grid()
	for gj in range(-n, n + 1):
		for gi in range(-n, n + 1):
			var p := c + Vector2(gi, gj) * cell + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			if p.distance_to(c) > r or p.distance_to(c) < 30.0: continue
			if rng.randf() < 0.18: continue
			var sz := Vector2(rng.randf_range(10, 15), rng.randf_range(9, 13))
			var half := sz * 0.5
			if not _land_around(p, half.length() + 2.0): continue
			if _overlaps(p, half, 5.0) or near_road(p, half.length() + 2.0) or near_water(p, 8.0): continue
			_add_building(p, sz, false, 2 if rng.randf() < 0.55 else 1)
	_structure("water_tower", c + Vector2(r * 0.7, -r * 0.3), Vector2(3.6, 3.6))

## A city street from a to b, broken where it would run through one of the
## model buildings (the pool, the warehouse, the apartment blocks).
func _street(a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var start := -1.0
	var d := 0.0
	while d <= length:
		var q := a + dir * d
		var blocked := false
		for st in structures:
			if String(st.kind).begins_with("bld_") and absf(q.x - st.pos.x) < st.half.x + 5.0 and absf(q.y - st.pos.y) < st.half.y + 5.0:
				blocked = true
				break
		if not blocked and start < 0.0: start = d
		if (blocked or d + 4.0 > length) and start >= 0.0:
			var end := d if blocked else length
			if end - start >= 20.0:
				roads.append({"a": a + dir * start, "b": a + dir * end, "w": 8.0, "street": true})
			start = -1.0
		d += 4.0

## Harbour: the village, a pier out over the water, containers and a crane on the quay.
func _port(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	# Which way the sea is: down the coast slope.
	var sea := Vector2.ZERO
	for a in 16:
		var d := Vector2(1, 0).rotated(a * TAU / 16.0)
		sea += d * (100.0 - clampf(coast_at(c.x + d.x * 150.0, c.y + d.y * 150.0), -100.0, 100.0))
	sea = sea.normalized()
	# Walk out to the shore.
	var shore := c
	for k in 80:
		if not is_land(shore.x + sea.x * 6.0, shore.y + sea.y * 6.0): break
		shore += sea * 6.0
	var rot := atan2(sea.y, sea.x)
	var perp := Vector2(-sea.y, sea.x)
	var big := float(t.r) >= 100.0
	_structure("pier", shore + sea * 28.0, Vector2(30, 30), {"dir": sea, "len": 60.0})
	obstacles.pop_back()   # you can walk the pier
	# Boats tied up along the pier (and the second one in the big ports).
	boat_spots.append({"pos": shore + sea * 44.0 + perp * 7.5, "dir": sea})
	if big:
		var p2 := shore + perp * 42.0
		if _land_around(p2 - sea * 6.0, 3.0):
			_structure("pier", p2 + sea * 22.0, Vector2(24, 24), {"dir": sea, "len": 48.0})
			obstacles.pop_back()
			boat_spots.append({"pos": p2 + sea * 34.0 - perp * 7.5, "dir": sea})
		boat_spots.append({"pos": shore + sea * 30.0 - perp * 7.5, "dir": sea})
		# A harbour shed and a row of fish stalls (market awnings) on the quay.
		var shed := shore - sea * 40.0 - perp * 20.0
		if _land_around(shed, 14.0) and not _overlaps(shed, Vector2(13, 8), 2.0):
			_add_building(shed, Vector2(24, 14), false, 1, "warehouse")
			buildings[-1].doors = [0, 2]
		for i in 4:
			var sp := shore - sea * 9.0 + perp * (-30.0 - i * 6.0)
			if _land_around(sp, 3.0) and not _overlaps(sp, Vector2(2.5, 2.5), 1.0):
				_structure("souq_stall", sp, Vector2(2.2, 1.2), {"dir": sea, "col": rng.randi_range(0, 5)})
	for row in 2:
		for i in 4:
			var p := shore - sea * (18.0 + row * 7.0) + Vector2(-sea.y, sea.x) * (-14.0 + i * 8.5)
			if not _land_around(p, 4.0) or _overlaps(p, Vector2(3.2, 3.2), 1.0): continue
			_structure("container", p, Vector2(3.1, 1.3))
			if rng.randf() < 0.3:
				structures.append({"kind": "container", "pos": p, "rot": 0, "level": 1, "col": rng.randi_range(0, 4)})
	var cp := shore - sea * 8.0 + Vector2(-sea.y, sea.x) * 26.0
	if _land_around(cp, 4.0) and not _overlaps(cp, Vector2(4, 4), 2.0):
		_structure("crane", cp, Vector2(3.0, 3.0), {"rot_f": rot})
	for k in 8 if big else 5:
		loot_spots.append({"pos": shore - sea * rng.randf_range(10.0, 30.0) + perp * rng.randf_range(-20, 20), "military": false})

## Military base: a square of concrete blast walls with a gate, watchtowers
## on the corners, two long barracks, a command block to fight from, a
## helipad, sandbag posts and rows of containers. The best loot around.
func _base(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	var half := 62.0
	flatten(c, Vector2(half + 10.0, half + 10.0), 60.0, maxf(2.0, height_at(c.x, c.y)))
	for side in 4:
		var n := Vector2(1, 0).rotated(side * PI * 0.5)
		var along := Vector2(-n.y, n.x)
		var k := -half + 3.0
		while k < half - 2.0:
			# The gate: a gap in the side facing south-west, towards the roads.
			if not (side == 1 and absf(k) < 7.0):
				_structure("blast_wall", c + n * half + along * k, Vector2(1.6, 1.6), {"dir": along})
			k += 3.0
	for e in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_structure("watchtower", c + e * (half - 5.0), Vector2(2.4, 2.4))
	for k in 2:
		_add_building(c + Vector2(-28.0, -32.0 + k * 22.0), Vector2(28, 11), true, 1, "warehouse")
		buildings[-1].doors = [0, 2]
	_add_building(c + Vector2(28.0, -30.0), Vector2(14, 12), true, 3, "apartment")
	_structure("helipad", c + Vector2(26.0, 22.0), Vector2(0.5, 0.5))
	obstacles.pop_back()
	for i in 5:
		var p := c + Vector2(-38.0 + i * 7.0, 36.0)
		_structure("container", p, Vector2(3.1, 1.3))
		if i % 2 == 0: structures.append({"kind": "container", "pos": p, "rot": 0, "level": 1, "col": 3})
	for e in [Vector2(-8, 50), Vector2(8, 50), Vector2(0, -12)]:
		_structure("sandbags", c + e, Vector2(2.0, 0.8))
	for k in 10:
		loot_spots.append({"pos": c + Vector2(rng.randf_range(-45, 45), rng.randf_range(-45, 45)), "military": true})

## Observatory on the peaks: the white dome, a lab and a cabin.
func _observatory(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	flatten(c, Vector2(40, 40), 40.0, height_at(c.x, c.y))
	_structure("observatory", c, Vector2(9, 9))
	_add_building(c + Vector2(-26, 14), Vector2(16, 10), true, 2, "house")
	_add_building(c + Vector2(24, 18), Vector2(10, 8), false)
	for k in 4:
		loot_spots.append({"pos": c + Vector2(rng.randf_range(14.0, 22.0), 0).rotated(rng.randf() * TAU), "military": true})

## Sulphur mine: the shaft head, sheds, silos and stacks of containers by the pit.
func _mine(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	_structure("mine_head", c, Vector2(5, 5))
	_add_building(c + Vector2(-30, -12), Vector2(24, 14), true, 1, "warehouse")
	buildings[-1].doors = [0, 2]
	_add_building(c + Vector2(28, 20), Vector2(11, 9), true)
	for k in 2:
		_structure("silo", c + Vector2(22.0 + k * 6.6, -16.0), Vector2(3.0, 3.0))
	for i in 5:
		var p := c + Vector2(-26.0 + i * 8.5, 26.0)
		if is_land(p.x, p.y) and not _overlaps(p, Vector2(3.2, 1.4), 1.0): _structure("container", p, Vector2(3.1, 1.3))
	_structure("chimney", c + Vector2(-44, 22), Vector2(2.2, 2.2))

## Airport: the runway (a road), a terminal, two hangars and the control tower.
func _airport(t: Dictionary) -> void:
	var ra := _m(L.runway[0])
	var rb := _m(L.runway[1])
	var dir := (rb - ra).normalized()
	var side := Vector2(-dir.y, dir.x)
	if side.y < 0.0: side = -side     # buildings on the land side (south of the strip faces the sea)
	var base := ra.lerp(rb, 0.72) + side * 70.0
	_add_building(base, Vector2(34, 14), true, 2, "warehouse")
	buildings[-1].doors = [0, 2]
	for k in 2:
		_add_building(ra.lerp(rb, 0.3 + k * 0.18) + side * 62.0, Vector2(26, 18), true, 1, "warehouse")
		buildings[-1].doors = [0, 2]
	_structure("control_tower", base + dir * 40.0, Vector2(4, 4))
	for k in 6:
		loot_spots.append({"pos": ra.lerp(rb, rng.randf_range(0.2, 0.9)) + side * rng.randf_range(45.0, 80.0), "military": true})

## Ruins on their islet: broken stone walls round an old courtyard.
func _ruins(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	for k in 9:
		var p := c + Vector2(rng.randf_range(6.0, 34.0), 0).rotated(k * TAU / 9.0 + rng.randf_range(-0.2, 0.2))
		if not _land_around(p, 3.0): continue
		_structure("ruin_wall", p, Vector2(3, 3), {"rot_f": rng.randf() * PI, "len": rng.randf_range(4.0, 9.0), "hgt": rng.randf_range(1.2, 4.0)})
	for k in 5:
		loot_spots.append({"pos": c + Vector2(rng.randf_range(0.0, 20.0), 0).rotated(rng.randf() * TAU), "military": true})

## Lighthouse on its rock, with the keeper's house.
func _lighthouse(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	flatten(c, Vector2(18, 18), 20.0, maxf(3.0, height_at(c.x, c.y)))
	_structure("lighthouse", c, Vector2(4, 4))
	_add_building(c + Vector2(-14, 10), Vector2(9, 7), false)
	for k in 3:
		loot_spots.append({"pos": c + Vector2(rng.randf_range(8.0, 14.0), 0).rotated(rng.randf() * TAU), "military": false})

## Buildings from Sketchfab models (see README; solid, not enterable): a
## house and a storehouse in every town, an apartment block in the bigger
## ones. Footprint in metres as drawn (world_builder scales the models to it).
const MODEL_BUILDINGS := {"bld_house": Vector2(9.7, 7.8), "bld_shed": Vector2(13.9, 7.9),
	"bld_tenement": Vector2(20.9, 45.3), "bld_tower": Vector2(17.7, 21.6),
	"bld_abandoned": Vector2(11.03, 7.98), "bld_warehouse": Vector2(16.0, 46.27), "bld_pool": Vector2(42.83, 50.8)}
## The model buildings you can walk into, and how many loot spots each holds.
const MODEL_LOOT := {"bld_abandoned": 2, "bld_warehouse": 4, "bld_pool": 3}

func _model_buildings() -> void:
	for t in towns:
		var want := []
		if t.military:
			want = ["bld_warehouse"]
		elif t.get("kind", "town") == "town" and map_id == "dunes":
			_minaret(t)
			_well(t)
			want = ["bld_abandoned"]
		elif t.get("kind", "town") == "town":
			_minaret(t)
			want = ["bld_house", "bld_shed", "bld_abandoned"]
			if rng.randf() < 0.4: want.append("bld_abandoned")
			if float(t.r) >= 100.0: want.append("bld_tenement" if rng.randf() < 0.5 else "bld_tower")
		elif t.get("kind", "") == "farm":
			want = ["bld_abandoned"]
		for kind in want:
			for attempt in 80:
				var rot := rng.randi_range(0, 3)
				var fp: Vector2 = MODEL_BUILDINGS[kind]
				var half := (fp if rot % 2 == 0 else Vector2(fp.y, fp.x)) * 0.5
				var c: Vector2 = t.pos + Vector2(rng.randf_range(float(t.r) * 0.3, float(t.r) * 1.1), 0).rotated(rng.randf() * TAU)
				if not _land_around(c, half.length() + 2.0): continue
				if _overlaps(c, half, 6.0) or near_road(c, half.length() + 2.0): continue
				flatten(c, half, 10.0, maxf(1.6, height_at(c.x, c.y)))
				_structure(kind, c, half, {"rot": rot, "half": half})
				_model_loot(kind, c, half)
				break

## A minaret near the middle of a town, standing over the roofs.
func _minaret(t: Dictionary) -> void:
	for attempt in 40:
		var p: Vector2 = t.pos + Vector2(rng.randf_range(8.0, float(t.r) * 0.45), 0).rotated(rng.randf() * TAU)
		var half := Vector2(2.4, 2.4)
		if not _land_around(p, 4.0) or _overlaps(p, half, 3.0) or near_road(p, 5.0): continue
		flatten(p, half, 6.0, maxf(1.6, height_at(p.x, p.y)))
		_structure("minaret", p, half)
		return

## Loot on the floors of a model building you can walk into ("ray": the
## world finds the floor under it).
func _model_loot(kind: String, c: Vector2, half: Vector2) -> void:
	for k in MODEL_LOOT.get(kind, 0):
		loot_spots.append({"pos": c + Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y)) * 0.55,
			"military": kind == "bld_warehouse" and rng.randf() < 0.5, "ray": true})

## Windmills (as on the small flowery map): one by each farm and a few more
## on open plains hills, among the lupine fields.
func _windmills() -> void:
	if map_id == "dunes": return
	for t in towns:
		if t.get("kind", "") != "farm": continue
		for k in 12:
			var p: Vector2 = t.pos + Vector2(rng.randf_range(45, 75), 0).rotated(rng.randf() * TAU)
			if _land_around(p, 8.0) and not _overlaps(p, Vector2(4, 4), 6.0) and not near_road(p, 8.0):
				_structure("windmill", p, Vector2(3.4, 3.4), {"rot": rng.randf() * TAU})
				break
	var made := 0
	var tries := 0
	while made < int(6.0 * _area()) and tries < 3000:
		tries += 1
		var p := Vector2(rng.randf_range(200, size - 200), rng.randf_range(200, size - 200))
		if region_at(p.x, p.y) != "plains" or not _land_around(p, 12.0): continue
		if height_at(p.x, p.y) < 12.0 or near_road(p, 25.0) or _overlaps(p, Vector2(4, 4), 40.0): continue
		var far_town := true
		for t in towns:
			if p.distance_to(t.pos) < t.r + 60.0: far_town = false
		if not far_town: continue
		_structure("windmill", p, Vector2(3.4, 3.4), {"rot": rng.randf() * TAU})
		made += 1

func _blocked(p: Vector2, r: float) -> bool:
	if not _land_around(p, r) or height_at(p.x, p.y) < 1.4: return true
	if lava_dist(p) < r + 6.0 or p.distance_to(crater) < 90.0: return true
	if _overlaps(p, Vector2(r, r), 3.0): return true
	if near_road(p, r + 1.0): return true
	return false

## Map area relative to the original 3 km island (props scale with it).
func _area() -> float:
	return pow(size / 3072.0, 2.0)

## Tree kinds per region: [kind, weight] (forests are thicker in the jungle and the north).
const REGION_TREES := {
	"plains": [["broad", 0.55], ["pine", 0.45]],
	"nordic": [["pine", 0.9], ["broad", 0.1]],
	"jungle": [["pine", 0.55], ["broad", 0.45]],
	"desert": [["cactus", 0.75], ["dead", 0.25]],
	"volcano": [["dead", 0.85], ["pine", 0.15]],
}
const REGION_FOREST := {"plains": 0.6, "nordic": 0.9, "jungle": 3.2, "desert": 0.12, "volcano": 0.15}

func _tree_kind(reg: String) -> String:
	var r := rng.randf()
	for e in L.trees[reg]:
		r -= e[1]
		if r <= 0.0: return e[0]
	return L.trees[reg][0][0]

func _props() -> void:
	var k_area := _area()
	# The dark forest is wall-to-wall trees (a jittered grid, with clearings).
	var fs := 19.0
	var gy := 0.0
	while gy < size:
		var gx := 0.0
		while gx < size:
			var p := Vector2(gx, gy) + Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
			gx += fs
			if region_at(p.x, p.y) != "jungle": continue
			if detail.get_noise_2d(p.x * 0.5, p.y * 0.5) > 0.32: continue    # clearings
			if rng.randf() < 0.62: _add_tree(p, _tree_kind("jungle"))
		gy += fs
	# Forests and scattered trees, each region with its own kinds.
	for f in int(70 * k_area):
		var c := Vector2(rng.randf_range(80, size - 80), rng.randf_range(80, size - 80))
		var reg := region_at(c.x, c.y)
		var dens: float = L.forest_density[reg]
		if dens < 1.0 and rng.randf() > dens: continue
		# Thick regions get several forests per try (the jungle is nearly all trees).
		for rep in int(ceil(dens)):
			if rep > 0:
				c = c + Vector2(rng.randf_range(90.0, 220.0), 0).rotated(rng.randf() * TAU)
			var main := _tree_kind(reg)
			for k in int(rng.randi_range(15, 40) * maxf(1.0, dens * 0.8)):
				var p := c + Vector2(absf(rng.randfn(0.0, 1.0)) * 55.0 * (1.4 if reg == "jungle" else 1.0), 0).rotated(rng.randf() * TAU)
				_add_tree(p, main if rng.randf() < 0.8 else _tree_kind(reg))
	# Rows of trees along the roads in the green country (windbreaks, as on
	# the farmland of the classic map); they line the horizon too.
	for rd in roads:
		var a: Vector2 = rd.a
		var b: Vector2 = rd.b
		var length := a.distance_to(b)
		if length < 60.0: continue
		var dir := (b - a) / length
		var nrm := Vector2(-dir.y, dir.x)
		var s0 := 0.0
		while s0 < length:
			var run := rng.randf_range(120.0, 380.0)
			if rng.randf() < 0.45:
				var sd := 1.0 if rng.randf() < 0.5 else -1.0
				var off: float = float(rd.w) * 0.5 + rng.randf_range(10.0, 16.0)
				var d := s0
				while d < minf(s0 + run, length):
					var p := a + dir * d + nrm * sd * off + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
					var reg := region_at(p.x, p.y)
					if map_id == "dunes":
						if reg == "plains" or rng.randf() < 0.25: _add_tree(p, "palm")     # palms along the desert roads
					elif reg in ["plains", "nordic"]:
						_add_tree(p, "broad" if reg == "plains" and rng.randf() < 0.7 else "pine")
					d += rng.randf_range(7.0, 11.0)
			s0 += run + rng.randf_range(60.0, 200.0)
	for k in int(900 * k_area):
		var p := Vector2(rng.randf_range(40, size - 40), rng.randf_range(40, size - 40))
		var reg := region_at(p.x, p.y)
		if reg == "desert" and rng.randf() < 0.5: continue
		_add_tree(p, _tree_kind(reg))
		if reg == "jungle":
			for k2 in 2: _add_tree(p + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), _tree_kind(reg))
	for k in int(260 * k_area):
		var p := Vector2(rng.randf_range(60, size - 60), rng.randf_range(60, size - 60))
		var reg := region_at(p.x, p.y)
		var r := rng.randf_range(0.8, 2.6) * (1.6 if reg in ["desert", "nordic"] else 1.0)
		if _blocked(p, r + 1.0): continue
		rocks.append({"pos": p, "r": r})
	# Boulders and rock piles in the desert and the north.
	for k in int(300 * k_area):
		var p := Vector2(rng.randf_range(60, size - 60), rng.randf_range(60, size - 60))
		if not region_at(p.x, p.y) in ["desert", "nordic"]: continue
		var r := rng.randf_range(1.2, 4.5)
		if _blocked(p, r + 1.0): continue
		rocks.append({"pos": p, "r": r})
	for k in int(90 * k_area):
		var p := Vector2(rng.randf_range(80, size - 80), rng.randf_range(80, size - 80))
		if _blocked(p, 3.0): continue
		loot_spots.append({"pos": p, "military": false})

func _add_tree(p: Vector2, kind: String) -> void:
	if _blocked(p, 2.5): return
	for t in towns:
		if p.distance_to(t.pos) < t.r * 0.8: return
	var h := rng.randf_range(7.0, 13.0)
	var r := rng.randf_range(0.18, 0.32)
	match kind:
		"palm": h = rng.randf_range(8.0, 14.0); r = rng.randf_range(0.16, 0.22)
		"cactus": h = rng.randf_range(2.5, 5.5); r = rng.randf_range(0.18, 0.28)
		"dead": h = rng.randf_range(4.0, 7.0); r = rng.randf_range(0.12, 0.2)
	trees.append({"pos": p, "h": h, "r": r, "pine": kind == "pine", "kind": kind, "shade": rng.randf()})

# ---------- Images for shaders and the map ----------
func height_image() -> Image:
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RF, heights.to_byte_array())
	img.convert(Image.FORMAT_RH)
	return img

## Region weights for the shaders: R desert, G forest, B north, A volcano.
func biome_image() -> Image:
	var img := Image.create(BIOME_N, BIOME_N, false, Image.FORMAT_RGBA8)
	for j in BIOME_N:
		for i in BIOME_N:
			var o := (j * BIOME_N + i) * 4
			img.set_pixel(i, j, Color(biome[o], biome[o + 1], biome[o + 2], biome[o + 3]))
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
			_disc(img, a.lerp(b, float(i) / n), w, Color(0.75 if rd.get("dirt", false) else 1.0, 0, 0, 0), false)
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

# ---------- The layouts ----------
## Seasons Island (the constants at the top, in its picture's pixels).
const SEASONS := {"name": MAP_NAME, "sea": SEA_NAME, "titles": REGION_TITLES, "coast": "res://assets/map/seasons_land.png",
	"pic": PIC, "nordic": NORDIC_AREA, "volcano": VOLCANO_AREA, "desert": DESERT_AREA, "forest": FOREST_AREA,
	"region_labels": REGION_LABELS, "places": PLACES, "islets": ISLETS,
	"paved": PAVED, "dirt": DIRT, "runway": RUNWAY, "lake_c": LAKE_C, "lake_r": LAKE_R, "lake_islet": LAKE_ISLET,
	"rivers": RIVERS, "crater_px": CRATER, "lava_px": LAVA, "lava_pools_px": LAVA_POOLS, "fields": FIELD_AREAS,
	"trees": REGION_TREES, "forest_density": REGION_FOREST}

## Dune Valley (وادي الرمال), 4 km: a desert island with an old walled city,
## a castle on a hill, a palm oasis round a pond, mud villages, a fishing
## port on the east coast, an airfield, an oil yard and a quarry. In a
## 1000-px frame (the coast is assets/map/dunes_land.png, made by
## tools/make_dunes_coast.py).
const DUNES := {"name": "وادي الرمال", "sea": "بحر العنبر", "coast": "res://assets/map/dunes_land.png", "pic": 1000.0,
	"titles": {"plains": "الواحة", "desert": "صحراء الرمال", "jungle": "بستان النخيل", "nordic": "", "volcano": ""},
	# Everything is desert but the oasis (cut out through a thin slit), and the palm grove inside it.
	"desert": [Vector2(-100, -100), Vector2(1100, -100), Vector2(1100, 1100), Vector2(-100, 1100), Vector2(-100, 602),
		Vector2(355, 602), Vector2(355, 690), Vector2(585, 690), Vector2(585, 515), Vector2(355, 515), Vector2(355, 598), Vector2(-100, 598)],
	"forest": [Vector2(395, 575), Vector2(430, 560), Vector2(470, 565), Vector2(515, 580), Vector2(535, 615), Vector2(520, 655),
		Vector2(475, 672), Vector2(425, 665), Vector2(392, 640), Vector2(380, 605)],
	"nordic": [], "volcano": [],
	"region_labels": {"desert": Vector2(760, 640), "plains": Vector2(470, 530), "jungle": Vector2(470, 690)},
	"places": [
		["المدينة القديمة", "medina", Vector2(500, 320), 240.0, "desert", false],
		["القلعة", "castle", Vector2(245, 225), 70.0, "desert", true],
		["واحة النخيل", "town", Vector2(400, 545), 95.0, "plains", false],
		["مزرعة التمر", "farm", Vector2(560, 560), 65.0, "plains", false],
		["ميناء الصيادين", "port", Vector2(845, 520), 150.0, "desert", false],
		["مطار الصحراء", "airport", Vector2(690, 835), 130.0, "desert", true],
		["محطة النفط", "industrial", Vector2(720, 195), 110.0, "desert", false],
		["قرية الطين", "town", Vector2(175, 470), 90.0, "desert", false],
		["قرية الجبل", "town", Vector2(705, 420), 80.0, "desert", false],
		["أطلال الوادي", "ruins", Vector2(300, 770), 55.0, "desert", false],
		["المحجر", "mine", Vector2(470, 855), 60.0, "desert", true],
		["المنارة", "lighthouse", Vector2(955, 135), 30.0, "desert", false],
	],
	"islets": [[Vector2(955, 135), 16.0], [Vector2(70, 965), 12.0]],
	"paved": [
		[Vector2(500, 320), Vector2(620, 375), Vector2(760, 445), Vector2(845, 500)],
		[Vector2(500, 320), Vector2(500, 440), Vector2(535, 560), Vector2(600, 700), Vector2(665, 800)],
		[Vector2(500, 320), Vector2(380, 275), Vector2(270, 235)],
		[Vector2(500, 320), Vector2(610, 255), Vector2(720, 200)],
	],
	"dirt": [
		[Vector2(400, 545), Vector2(290, 505), Vector2(175, 470)],
		[Vector2(400, 545), Vector2(345, 650), Vector2(300, 770), Vector2(390, 830), Vector2(470, 855)],
		[Vector2(705, 420), Vector2(620, 375)],
		[Vector2(665, 800), Vector2(565, 845), Vector2(470, 855)],
		[Vector2(175, 470), Vector2(210, 350), Vector2(245, 240)],
	],
	"runway": [Vector2(585, 850), Vector2(770, 805)],
	"lake_c": Vector2(462, 618), "lake_r": Vector2(34, 24), "lake_islet": Vector2(-5000, -5000),
	"rivers": [], "crater_px": Vector2(-9000, -9000), "lava_px": [], "lava_pools_px": [],
	"fields": [Rect2(525, 595, 75, 45)],
	"trees": {"plains": [["palm", 0.75], ["broad", 0.25]], "jungle": [["palm", 1.0]], "desert": [["dead", 0.55], ["palm", 0.25], ["cactus", 0.2]],
		"nordic": [["pine", 1.0]], "volcano": [["dead", 1.0]]},
	"forest_density": {"plains": 0.9, "jungle": 3.2, "desert": 0.06, "nordic": 0.0, "volcano": 0.0},
}

# ---------- Dune Valley places ----------
## The old walled city: a maze of flat-roofed stone houses packed along
## narrow lanes, a covered souq down the main street, the great mosque with
## its dome and minaret on the square, a well.
func _medina(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	var r: float = t.r
	# The square in the middle: mosque, minaret, well.
	_structure("mosque", c + Vector2(-26, -8), Vector2(9, 9))
	_structure("minaret", c + Vector2(-12, -20), Vector2(2.4, 2.4))
	_structure("well", c + Vector2(16, 12), Vector2(1.6, 1.6))
	# The souq: two rows of stalls under coloured awnings down one street.
	var dir := Vector2(1, 0).rotated(rng.randi_range(0, 3) * PI * 0.5)
	var side := Vector2(-dir.y, dir.x)
	for k in 9:
		for sd in [-1.0, 1.0]:
			var p: Vector2 = c + dir * (40.0 + k * 7.0) + side * sd * 5.5
			if _land_around(p, 3.0) and not _overlaps(p, Vector2(2.6, 2.0), 0.5):
				_structure("souq_stall", p, Vector2(2.6, 2.0), {"dir": dir * sd, "col": rng.randi_range(0, 5)})
	for k in 6:
		loot_spots.append({"pos": c + dir * rng.randf_range(40.0, 100.0) + side * rng.randf_range(-3.0, 3.0), "military": false})
	# Houses packed tight on a jittered grid: lanes of 4-6 m between them.
	var cell := 17.0
	var n := int(r / cell)
	for gj in range(-n, n + 1):
		for gi in range(-n, n + 1):
			var p := c + Vector2(gi, gj) * cell + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
			var d := p.distance_to(c)
			if d > r or d < 34.0: continue
			if rng.randf() < 0.1: continue
			var sz := Vector2(rng.randf_range(10, 13.5), rng.randf_range(9, 12.5))
			var half := sz * 0.5
			if not _land_around(p, half.length() + 1.0): continue
			if _overlaps(p, half, 3.0) or near_road(p, half.length() + 1.0): continue
			var roll := rng.randf()
			if roll < 0.08 and sz.x >= 10.5 and sz.y >= 9.0:
				_add_building(p, sz, false, rng.randi_range(3, 4), "apartment")
			elif roll < 0.14:
				_add_building(p, sz, false, 1, "ruin")
			else:
				_add_building(p, sz, false, 2 if roll < 0.55 and sz.x >= 10.0 and sz.y >= 8.5 else 1)
	# The old city wall round it, broken where the roads come in.
	_ring_wall(c, r + 14.0, 4.5)

## A stone wall round c, in straight pieces, with gaps for every road.
func _ring_wall(c: Vector2, rad: float, hgt: float) -> void:
	var n := int(TAU * rad / 22.0)
	for k in n:
		var a0 := k * TAU / n
		var a1 := (k + 1) * TAU / n
		var p0 := c + Vector2(rad, 0).rotated(a0)
		var p1 := c + Vector2(rad, 0).rotated(a1)
		var m := (p0 + p1) * 0.5
		if near_road(m, 8.0) or not _land_around(m, 3.0) or _overlaps(m, Vector2(3, 3), 0.5): continue
		var piece := p0.distance_to(p1) + 0.6
		_structure("castle_wall", m, Vector2(2, 2), {"rot_f": -atan2(p1.y - p0.y, p1.x - p0.x), "len": piece, "hgt": hgt, "thick": 1.6})
		if k % 4 == 0: _structure("castle_tower", p0, Vector2(2.6, 2.6), {"hgt": hgt + 3.0, "w": 5.0})

## The castle on its hill: four walls with a gate, a tower at each corner,
## the keep and the barracks inside (the best loot on the map).
func _castle(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	var h := 32.0
	flatten(c, Vector2(h + 10.0, h + 10.0), 30.0, maxf(8.0, height_at(c.x, c.y)))
	var gate := rng.randi_range(0, 3)
	for w in 4:
		var along_x := w % 2 == 0
		var off := Vector2(0, -h) if w == 0 else (Vector2(h, 0) if w == 1 else (Vector2(0, h) if w == 2 else Vector2(-h, 0)))
		var rot := 0.0 if along_x else PI * 0.5
		if w == gate:
			for sd in [-1.0, 1.0]:
				var q: Vector2 = c + off + (Vector2(sd * 18.5, 0) if along_x else Vector2(0, sd * 18.5))
				_structure("castle_wall", q, Vector2(14, 14), {"rot_f": rot, "len": 27.0, "hgt": 7.0, "thick": 2.2})
		else:
			_structure("castle_wall", c + off, Vector2(h, h), {"rot_f": rot, "len": h * 2.0, "hgt": 7.0, "thick": 2.2})
		obstacles.pop_back()
	for e in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_structure("castle_tower", c + e * h, Vector2(4, 4), {"hgt": 11.0, "w": 7.5})
	_fp_add(c, Vector2(h + 4.0, h + 4.0))
	# The keep (an apartment block: stairs to its roof) and two barracks.
	_add_building(c + Vector2(-8, -6), Vector2(12, 11), false, 3, "apartment")
	buildings[-1].military = true
	_add_building(c + Vector2(14, 12), Vector2(16, 10), true, 2)
	_add_building(c + Vector2(-16, 18), Vector2(12, 9), true, 1)
	for k in 6:
		loot_spots.append({"pos": c + Vector2(rng.randf_range(-24, 24), rng.randf_range(-24, 24)), "military": true})

## A village well with a little roof, in the middle of the oasis and mud villages.
func _well(t: Dictionary) -> void:
	for attempt in 30:
		var p: Vector2 = t.pos + Vector2(rng.randf_range(0.0, 20.0), 0).rotated(rng.randf() * TAU)
		if _land_around(p, 3.0) and not _overlaps(p, Vector2(2, 2), 2.0) and not near_road(p, 3.0):
			_structure("well", p, Vector2(1.6, 1.6))
			return
