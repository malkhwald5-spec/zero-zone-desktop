extends Node
## The new places from the air: on Seasons Island the military base, the
## new villages and works; on Dune Valley the bigger port with its boats and
## a close look at the old houses (arched windows, studded wooden doors).
## Run: godot --path godot res://tests/new_places_shots.tscn -- --out=/dir [--map=dunes]

var out := "user://"

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.controls = "kbm"
	_run.call_deferred()

func _place(name: String) -> Dictionary:
	for t in get_tree().current_scene.island.towns:
		if t.name == name: return t
	return {}

## Hovers the camera at `up` metres, `back` metres away from the spot, looking at it.
func _look(p: Player, world, at: Vector2, up: float, back: float, from_dir := Vector2(0.5, 1.0)) -> void:
	var d := from_dir.normalized()
	var eye := at + d * back
	var gy: float = world.ground_height(Vector3(at.x, 0, at.y))
	p.global_position = Vector3(eye.x, gy + up, eye.y)
	p.velocity = Vector3.ZERO
	p.yaw = atan2(d.x, d.y)
	p.pitch = -atan2(up, back)

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
	for b in world.bots: b.set_physics_process(false)
	await wait(2.0)
	var dunes: bool = world.island.map_id == "dunes"
	world.hud.toggle_map()
	await wait(0.6)
	await shot("places_map")
	world.hud.toggle_map()
	world.hud.visible = false
	p.jump_from_plane()
	p.open_chute()
	p.state = "chute"
	world.plane_active = false
	world.plane.visible = false
	var views := [["ميناء الصيادين", 70.0, 200.0]] if dunes else [["قاعدة الصقر", 55.0, 150.0], ["قرية البازلت", 80.0, 230.0],
		["محطة الطاقة", 70.0, 200.0], ["مخيم الحطابين", 70.0, 200.0], ["قرية الضفة", 70.0, 200.0],
		["المنطقة الصناعية", 70.0, 200.0], ["قرية الكثبان", 80.0, 230.0], ["مرفأ الرماد", 70.0, 220.0]]
	var i := 0
	for v in views:
		var t := _place(v[0])
		if t.is_empty(): continue
		_look(p, world, t.pos, v[1], v[2])
		await wait(1.5)
		await shot("place_%d" % i)
		i += 1
	if not dunes:
		var base := _place("قاعدة الصقر")
		_look(p, world, base.pos, 9.0, 40.0, Vector2(-0.3, 1.0))
		await wait(1.5)
		await shot("place_base_close")
	# An old house up close: arched windows and the wooden door.
	var best: Dictionary = {}
	for b in world.island.buildings:
		if b.get("style", "") == "desert" and not b.military and b.get("kind", "house") == "house" and b.doors.size() > 0:
			best = b
			break
	if not best.is_empty():
		var d := int(best.doors[0])
		var n := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][d] as Vector2
		var hw: float = (best.size.x if d % 2 == 0 else best.size.y) * 0.5
		var dist: float = (best.size.y if d % 2 == 0 else best.size.x) * 0.5 + 7.0
		_look(p, world, best.pos + n * (dist - 7.0), 1.8, 7.0, n + Vector2(-n.y, n.x) * 0.35)
		p.pitch = -0.05
		await wait(1.5)
		await shot("place_house_close")
	# The map's own air, from the ground: the sandstorm in Dune Valley, the
	# snow in the north of Seasons Island.
	var med: Dictionary = world.island.towns[0]
	if not dunes:
		for t in world.island.towns:
			if t.region == "nordic" and t.kind == "town": med = t
	var gp := Vector3(med.pos.x + float(med.r) * 0.6, 0, med.pos.y)
	p.global_position = Vector3(gp.x, world.ground_height(gp) + 0.3, gp.z)
	p.state = "ground"
	p.velocity = Vector3.ZERO
	p.yaw = 0.6
	p.pitch = -0.05
	Game.settings.lite = false     # (the slow test machine trips the auto drop to weak-phone mode)
	if dunes:
		if world.events: world.events._storm_t = 40.0
		world.region_fx.storm = 1.0
	await wait(3.0)
	await shot("place_air_fx")
	print("PLACES SHOTS DONE")
	tree.quit()
