extends Node
## Skydive and canopy handling: A/D fly sideways in freefall and turn the
## canopy, and the speed changes smoothly (no jumps from one tick to the next).
## Run headless: godot --headless --path godot res://tests/fall_test.tscn

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok: fails += 1

func _ready() -> void:
	Game.settings.controls = "touch"     # drive the stick directly
	_run.call_deferred()

func _ticks(n: int) -> void:
	for i in n: await get_tree().physics_frame

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await get_tree().create_timer(0.5).timeout
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await get_tree().create_timer(0.1).timeout
	var p: Player = world.player
	p.health = 1e9
	for b in world.bots: b.set_physics_process(false)
	world.plane_active = false
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[2].pos
	p.global_position = Vector3(c.x, 560.0, c.y)
	p.velocity = Vector3.ZERO
	p.yaw = 0.0
	p.pitch = -0.3
	await _ticks(90)
	# Hold right for 4 s.
	var start := p.global_position
	p.touch_move = Vector2(1, 0)
	var worst := 0.0
	var prev := p.velocity
	for i in 240:
		await get_tree().physics_frame
		worst = maxf(worst, (p.velocity - prev).length())
		prev = p.velocity
	var right := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	var moved := (p.global_position - start).dot(right)
	check(moved > 35.0, "freefall: D flies sideways (%.0f m in 4 s)" % moved)
	check(p.fall_lean > 0.8, "freefall: the body rolls into it (%.2f)" % p.fall_lean)
	check(worst < 1.2, "freefall: smooth, biggest change per tick %.2f m/s" % worst)
	p.touch_move = Vector2(-1, 0)
	await _ticks(240)
	check((p.global_position - start).dot(right) < moved - 25.0, "freefall: A flies back the other way")
	p.touch_move = Vector2.ZERO
	# Canopy: hold left, the heading turns smoothly.
	p.global_position.y = 400.0
	p.open_chute()
	await _ticks(120)
	var h0 := p.chute_heading
	p.touch_move = Vector2(-1, 0)
	worst = 0.0
	var prev_h := h0
	for i in 180:
		await get_tree().physics_frame
		worst = maxf(worst, absf(wrapf(p.chute_heading - prev_h, -PI, PI)))
		prev_h = p.chute_heading
	var turned := absf(wrapf(p.chute_heading - h0, -PI, PI))
	check(turned > 1.0, "canopy: A turns it (%.0f° in 3 s)" % rad_to_deg(turned))
	check(worst < 0.05, "canopy: the turn eases in (max %.3f rad per tick)" % worst)
	print("TEST ", "OK" if fails == 0 else "FAILED %d" % fails)
	tree.quit(0 if fails == 0 else 1)
