extends SceneTree
func _init():
	var t0 := Time.get_ticks_msec()
	var isl := Island.new(12345, 3072.0)
	isl.generate()
	var t1 := Time.get_ticks_msec()
	var hi := isl.height_image()
	var mi := isl.mask_image(1024)
	var t2 := Time.get_ticks_msec()
	print("gen ms ", t1 - t0, " images ms ", t2 - t1)
	print("towns ", isl.towns.size(), " roads ", isl.roads.size(), " bridges ", isl.bridges.size(), " buildings ", isl.buildings.size(), " trees ", isl.trees.size(), " rocks ", isl.rocks.size(), " loot ", isl.loot_spots.size())
	var mn := 1e9; var mx := -1e9
	for h in isl.heights:
		mn = min(mn, h); mx = max(mx, h)
	print("height range ", mn, " .. ", mx)
	quit()
