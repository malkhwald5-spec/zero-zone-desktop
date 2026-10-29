extends Node
## A film of Dune Valley: over the island from the sea, the old city from
## above, down into its lanes and the souq, the mosque, the castle on its
## hill, the palm oasis, the port and the lighthouse. "TOUR" lines give the
## timeline. Film: godot --path godot --write-movie tour.avi --fixed-fps 30
##   res://tests/dunes_tour.tscn -- --map=dunes

var world: Node
var p: Player
var cam: Camera3D
var fade: ColorRect
var title: Label
var _upd: Callable = Callable()
var _t0 := 0.0
var _clock := 0.0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	Game.settings.controls = "touch"
	Game.settings.weather = "clear"
	Game.settings.mode = "solo"
	Game.settings.quality = "ultra"
	Game.settings.auto_perf = false
	Game.spawn_island = false
	Game.training = false
	_run.call_deferred()

func _process(delta: float) -> void:
	_clock += delta
	if p and is_instance_valid(p): p.health = 100.0
	if _upd.is_valid() and cam: _upd.call(_clock - _t0)

func shot(f: Callable, name: String) -> void:
	_t0 = _clock
	_upd = f
	print("TOUR %.2f %s" % [_clock, name])
	f.call(0.0)

func caption(t: String, sec := 2.4) -> void:
	title.text = t
	title.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(title, "modulate:a", 1.0, 0.4)
	tw.tween_interval(sec)
	tw.tween_property(title, "modulate:a", 0.0, 0.4)

func place(name: String) -> Dictionary:
	for t in world.island.towns:
		if t.name == name: return t
	return {}

func g(q: Vector2) -> float:
	return world.ground_height(Vector3(q.x, 0, q.y))

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	var cl := CanvasLayer.new()
	cl.layer = 120
	add_child(cl)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 0.88
		bar.anchor_bottom = 0.12 if top else 1.0
		cl.add_child(bar)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(fade)
	title = UiKit.label("", 44, Color.WHITE, UiKit.bold(), 6)
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	title.offset_bottom = -110
	cl.add_child(title)
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	for i in 3000:
		world = tree.current_scene
		if world and world.get("ready_done"): break
		await wait(0.1)
	p = world.player
	world.hud.visible = false
	for b in world.bots: b.set_physics_process(false)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 4000.0
	world.add_child(cam)
	cam.current = true
	_clock = 0.0
	print("TOUR_START")
	var S: float = world.island.size
	var mid := Vector2(S * 0.5, S * 0.5)
	# 1: in from the sea over the whole island.
	shot(func(t: float):
		var a := Vector3(S * 1.05 - t * 55.0, 520.0 - t * 6.0, S * 0.75 - t * 18.0)
		cam.global_position = a
		cam.look_at(Vector3(mid.x, 40.0, mid.y), Vector3.UP), "island")
	create_tween().tween_property(fade, "color:a", 0.0, 1.0)
	caption("وادي الرمال")
	await wait(6.0)
	# 2: the old city from above, circling.
	var med := place("المدينة القديمة")
	var mc: Vector2 = med.pos
	var mh := g(mc)
	shot(func(t: float):
		var a := 0.6 + t * 0.09
		cam.global_position = Vector3(mc.x + cos(a) * 330.0, mh + 170.0 - t * 6.0, mc.y + sin(a) * 330.0)
		cam.look_at(Vector3(mc.x, mh + 8.0, mc.y), Vector3.UP), "medina_air")
	caption("المدينة القديمة")
	await wait(6.0)
	# 3: down in the lanes, walking between the houses.
	var lane := mc + Vector2(70, 40)
	shot(func(t: float):
		var q := lane + Vector2(-t * 3.2, t * 1.0)
		cam.global_position = Vector3(q.x, g(q) + 1.7, q.y)
		cam.look_at(Vector3(q.x - 10.0, g(q) + 2.2, q.y + 3.0), Vector3.UP), "lanes")
	await wait(4.0)
	# 4: the souq and the mosque.
	var mosque: Vector2 = mc
	var stall: Vector2 = mc
	for st in world.island.structures:
		if st.kind == "mosque": mosque = st.pos
		if st.kind == "souq_stall" and stall == mc: stall = st.pos
	shot(func(t: float):
		var q := stall + Vector2(-8.0 + t * 1.5, -6.0)
		cam.global_position = Vector3(q.x, g(q) + 2.0, q.y)
		cam.look_at(Vector3(stall.x + 6.0, g(stall) + 1.5, stall.y + 6.0), Vector3.UP), "souq")
	caption("السوق")
	await wait(4.0)
	shot(func(t: float):
		var a := 2.0 + t * 0.12
		cam.global_position = Vector3(mosque.x + cos(a) * 38.0, g(mosque) + 6.0 + t * 1.5, mosque.y + sin(a) * 38.0)
		cam.look_at(Vector3(mosque.x, g(mosque) + 9.0, mosque.y), Vector3.UP), "mosque")
	caption("الجامع الكبير")
	await wait(5.0)
	# 5: the castle on its hill.
	var cas := place("القلعة")
	var cc: Vector2 = cas.pos
	shot(func(t: float):
		var a := -0.8 + t * 0.1
		cam.global_position = Vector3(cc.x + cos(a) * 120.0, g(cc) + 30.0 - t * 1.5, cc.y + sin(a) * 120.0)
		cam.look_at(Vector3(cc.x, g(cc) + 6.0, cc.y), Vector3.UP), "castle")
	caption("القلعة • أحسن غنايم")
	await wait(6.0)
	# 6: the oasis.
	var lake: Vector2 = world.island._m(world.island.L.lake_c)
	shot(func(t: float):
		var q := lake + Vector2(-260.0 + t * 22.0, 120.0)
		cam.global_position = Vector3(q.x, g(lake) + 45.0, q.y)
		cam.look_at(Vector3(lake.x, g(lake), lake.y), Vector3.UP), "oasis")
	caption("واحة النخيل")
	await wait(5.0)
	# 7: the port and the lighthouse at sunset light over the sea.
	var port := place("ميناء الصيادين")
	var pc: Vector2 = port.pos
	shot(func(t: float):
		cam.global_position = Vector3(pc.x + 140.0 - t * 6.0, 40.0, pc.y + 60.0)
		cam.look_at(Vector3(pc.x, 4.0, pc.y), Vector3.UP), "port")
	caption("ميناء الصيادين")
	await wait(4.5)
	# 8: up and away over the whole valley, the title.
	shot(func(t: float):
		cam.global_position = Vector3(mid.x - 300.0, 200.0 + t * 70.0, mid.y + 1400.0 + t * 60.0)
		cam.look_at(Vector3(mid.x, 0.0, mid.y), Vector3.UP), "away")
	await wait(3.0)
	caption("ZERO ZONE • وادي الرمال", 3.0)
	await wait(3.5)
	create_tween().tween_property(fade, "color:a", 1.0, 0.8)
	await wait(1.0)
	print("TOUR %.2f end" % _clock)
	print("TOUR DONE")
	tree.quit()
