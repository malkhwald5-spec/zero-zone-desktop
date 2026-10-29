extends SceneTree
## Builds Dune Valley (no rendering) and prints what it holds.
## Run: godot --headless --path godot -s res://tests/dunes_gen.gd
func _init():
	var t0 := Time.get_ticks_msec()
	var isl := Island.new(12345, 4096.0, "dunes")
	isl.generate()
	print("gen ms ", Time.get_ticks_msec() - t0)
	print("towns ", isl.towns.size(), " roads ", isl.roads.size(), " bridges ", isl.bridges.size(), " buildings ", isl.buildings.size(),
		" structures ", isl.structures.size(), " trees ", isl.trees.size(), " rocks ", isl.rocks.size(), " loot ", isl.loot_spots.size())
	var kinds := {}
	for st in isl.structures: kinds[st.kind] = kinds.get(st.kind, 0) + 1
	print("structure kinds ", kinds)
	var tk := {}
	for t in isl.trees: tk[t.kind] = tk.get(t.kind, 0) + 1
	print("tree kinds ", tk)
	var regs := {}
	for j in 40:
		for i in 40:
			var x := (i + 0.5) / 40.0 * isl.size
			var z := (j + 0.5) / 40.0 * isl.size
			if isl.is_land(x, z):
				var r := isl.region_at(x, z)
				regs[r] = regs.get(r, 0) + 1
	print("regions on land ", regs)
	for t in isl.towns:
		print("  %s %s land=%s h=%.1f" % [t.name, t.kind, isl.is_land(t.pos.x, t.pos.y), isl.height_at(t.pos.x, t.pos.y)])
	quit()
