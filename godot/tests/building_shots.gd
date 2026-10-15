extends Node
## The model buildings in the towns: each kind seen from the street, then a
## town from above. Run with --out=/dir.

var out := "user://"
var kinds: PackedStringArray = []     # --kinds=bld_a,bld_b: only these

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--kinds="): kinds = a.substr(8).split(",")
	Game.settings.quality = "high"
	Game.settings.weather = "clear"
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	world.hud.visible = false
	for b in world.bots: b.set_physics_process(false)
	var p: Player = world.player
	p.health = 1e9
	var cam := Camera3D.new()
	cam.fov = 55
	world.add_child(cam)
	var done := {}
	var counts := {}
	for st in world.island.structures:
		if String(st.kind).begins_with("bld_"): counts[st.kind] = counts.get(st.kind, 0) + 1
	print("model buildings ", counts)
	for st in world.island.structures:
		var k := String(st.kind)
		if not k.begins_with("bld_") or done.has(k) or (kinds.size() > 0 and not k in kinds): continue
		done[k] = true
		var c := Vector3(st.pos.x, world.island.height_at(st.pos.x, st.pos.y), st.pos.y)
		var h: Vector2 = st.half
		var d := maxf(h.x, h.y) * 2.2 + 8.0
		p.global_position = c + Vector3(d, 60, d)
		await wait(1.5)
		cam.current = true
		cam.look_at_from_position(c + Vector3(d * 0.8, 3.0 + h.length() * 0.25, d * 0.6), c + Vector3(0, 4.0 + h.length() * 0.2, 0))
		await wait(0.6)
		await shot("bld_" + k.substr(4))
		if WorldBuilder.MODEL_FILES[k].get("enter", false):
			# Inside, at eye height, looking along the longer side.
			var along := Vector3(h.x * 0.8, 0, h.y * 0.3) if h.x > h.y else Vector3(h.x * 0.3, 0, h.y * 0.8)
			cam.look_at_from_position(c + Vector3(0, 1.9, 0), c + along + Vector3(0, 1.4, 0))
			await wait(0.6)
			await shot("bld_" + k.substr(4) + "_in")
		if k == "bld_tenement" or k == "bld_tower":
			cam.look_at_from_position(c + Vector3(70, 55, 70), c)
			await wait(0.6)
			await shot("bld_town_" + k.substr(4))
	tree.quit()
