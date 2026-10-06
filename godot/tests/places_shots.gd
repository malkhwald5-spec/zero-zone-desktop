extends Node
## Pictures of the special places: factory yard, farm and gas station.
## Run: godot --path godot res://tests/places_shots.tscn -- --out=/dir [--quality=high]

var out := "user://"

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--quality="): Game.settings.quality = a.substr(10)
	Game.settings.controls = "kbm"
	_run.call_deferred()

## Stand `dist` metres from `target` (towards `from_dir`) and look at it.
func _look(world, p: Player, target: Vector2, from_dir: Vector2, dist: float, pitch: float) -> void:
	var at := target + from_dir.normalized() * dist
	p.global_position = Vector3(at.x, world.ground_height(Vector3(at.x, 0, at.y)) + 0.3, at.y)
	p.velocity = Vector3.ZERO
	var d := target - at
	p.yaw = atan2(-d.x, -d.y)
	p.pitch = pitch
	await wait(1.5)

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
	var p: Player = world.player
	p.health = 1e9
	world.hud.visible = false
	for b in world.bots: b.set_physics_process(false)
	p.jump_from_plane()
	var isl: Island = world.island
	var counts := {}
	for st in isl.structures: counts[st.kind] = counts.get(st.kind, 0) + 1
	var kinds := {}
	for b in isl.buildings: kinds[b.get("kind", "house")] = kinds.get(b.get("kind", "house"), 0) + 1
	print("PLACES structures=%s buildings=%s" % [counts, kinds])
	for t in isl.towns:
		if t.get("kind", "") == "industrial":
			await _look(world, p, t.pos, Vector2(0.4, 1), 48.0, 0.12)
			await shot("place_industrial")
			break
	for t in isl.towns:
		if t.get("kind", "") == "farm":
			await _look(world, p, t.pos + Vector2(-4, -6), Vector2(-0.6, 1), 34.0, 0.1)
			await shot("place_farm")
			break
	for st in isl.structures:
		if st.kind == "canopy":
			await _look(world, p, st.pos, Vector2(st.dir.x, st.dir.y), 20.0, 0.05)
			await shot("place_gas")
			break
	print("PLACES DONE")
	tree.quit()
