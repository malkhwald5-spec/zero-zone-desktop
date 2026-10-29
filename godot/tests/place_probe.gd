extends SceneTree
## Checks candidate spots for new places on a map (land, region, height, how
## far from the nearest place and road).
## Run: godot --headless --path godot -s res://tests/place_probe.gd -- seasons 950,330 1800,1100
func _init():
	var args := OS.get_cmdline_user_args()
	var which: String = args[0] if args.size() > 0 else "seasons"
	var isl := Island.new(12345, 8192.0 if which == "seasons" else 4096.0, which)
	isl.generate()
	for a in args.slice(1):
		var xy: PackedStringArray = String(a).split(",")
		var px := Vector2(float(xy[0]), float(xy[1]))
		var p: Vector2 = px * isl.size / float(isl.L.pic)
		var best := INF
		var bn := ""
		for t in isl.towns:
			var d: float = p.distance_to(t.pos) - float(t.r)
			if d < best:
				best = d
				bn = t.name
		var land := 0
		for k in 16:
			var q := p + Vector2(120, 0).rotated(k * TAU / 16.0)
			if isl.is_land(q.x, q.y): land += 1
		print("%s land=%s ring=%d/16 region=%s h=%.1f nearest=%s %.0fm road=%s lava=%.0f" % [a, isl.is_land(p.x, p.y), land,
			isl.region_at(p.x, p.y), isl.height_at(p.x, p.y), bn, best, isl.near_road(p, 30.0), isl.lava_dist(p)])
	quit()
