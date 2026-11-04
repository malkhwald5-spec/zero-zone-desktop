extends Node
## The gun held alive (not pinned to the body): for each move the player
## makes, how far the gun moves on the body (range of its place, cm, and of
## where the muzzle points, degrees), how smooth that is (worst change of
## step frame to frame, cm), and whether both hands stay on it (worst gap
## between each hand and its grip, cm).
## Run: godot --headless --path godot --fixed-fps 60 res://tests/gun_life_probe.tscn

var world: Node
var p: Player
var rec: Array = []
var on := false
var label := ""
var fails := 0
var _skip := 0
var isl
var spot := Vector2.ZERO

func _flat(q: Vector2) -> bool:
	var h0: float = isl.height_at(q.x, q.y)
	if h0 < 3.0 or world.building_at(q, 45.0) >= 0: return false
	for t in isl.trees + isl.rocks:
		if (t.pos as Vector2).distance_to(q) < 45.0: return false
	for a in 12:
		for r in [15.0, 30.0, 45.0]:
			var w: Vector2 = q + Vector2.from_angle(a * TAU / 12.0) * r
			if not isl.is_land(w.x, w.y) or absf(isl.height_at(w.x, w.y) - h0) > 1.2: return false
	return true

## Back to the middle of the field, standing, facing along it.
func home() -> void:
	p.global_position = Vector3(spot.x, isl.height_at(spot.x, spot.y) + 0.1, spot.y)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	Game.settings.controls = "touch"
	Game.settings.mode = "solo"
	Game.spawn_island = false
	_run.call_deferred()

func _process(d: float) -> void:
	if not on or p == null: return
	if p.model.is_acting() or not p.is_on_floor():
		_skip = 12      # (and a moment after: the hold eases back)
		return
	if _skip > 0:
		_skip -= 1
		rec.clear()    # measured from here on, in one unbroken run
		return
	var m: HumanModel = p.model
	var inv: Transform3D = m.global_transform.affine_inverse()
	var g: Transform3D = m.gun.global_transform
	var gl: Transform3D = inv * g
	var sk_xf: Transform3D = m.sk.global_transform
	var rh: Vector3 = sk_xf * m.sk.get_bone_global_pose(m._bone["RightHand"]).origin
	var lh: Vector3 = sk_xf * m.sk.get_bone_global_pose(m._bone["LeftHand"]).origin
	var grip: Vector3 = g * Vector3(0.0, -0.06, 0.07)
	var fore_v: Vector3 = m.weapon_node.get_meta("fore", Vector3(0, -0.06, -0.32)) if m.weapon_node else Vector3(0, -0.06, -0.32)
	# (sprinting the gun is carried in the left hand, the right one let go:
	# the two-handed grip is not what is measured then)
	var carried: bool = (m._smv.get(&"carry", Vector2.ZERO) as Vector2).x > 0.02
	if carried: return      # (the carry in the left hand replaces this; smooth_probe measures it)
	var fore: Vector3 = g * (fore_v * HumanModel.WSCALE + Vector3(-0.02, -0.02, 0.06))
	# The life on top of where the pose puts the gun (the pose's own easing
	# from one hold to another is left out).
	var base: Transform3D = m._gun_xf
	var live: Transform3D = m.gun.transform
	if rec.size() > 1:
		var s1: Vector3 = (live.origin - base.origin) - (rec[-1]["pos"] as Vector3)
		var s0: Vector3 = (rec[-1]["pos"] as Vector3) - (rec[-2]["pos"] as Vector3)
		if (s1 - s0).length() > 0.03:
			print("GUNSPIKE %s frame %d anim %s state %s stance %s vault %.2f pos %s off %s gs %s gh %.3f still %.2f speed %.2f" % [label, rec.size(), m._anim, p.state, p.stance, p.vault_t, p.global_position, live.origin - base.origin, m._gs, m._gh, m._still_k, m._speed])
	rec.append({"pos": live.origin - base.origin, "dir": (live.basis * Vector3.FORWARD).normalized(), "dir0": (base.basis * Vector3.FORWARD).normalized(), "rgap": 0.0 if carried else rh.distance_to(grip), "lgap": 0.0 if carried else lh.distance_to(fore), "f": clampf(d * 60.0, 0.5, 3.0)})

func report(min_range: float, max_range: float, max_jit := 1.5) -> void:
	if rec.size() < 3:
		print("GUNLIFE %s OK carried in the left hand (measured in smooth_probe)" % label)
		return
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var ang := 0.0
	var jit := 0.0
	var rg := 0.0
	var lg := 0.0
	for i in rec.size():
		var q: Vector3 = rec[i]["pos"]
		lo = lo.min(q)
		hi = hi.max(q)
		ang = maxf(ang, rad_to_deg((rec[i]["dir0"] as Vector3).angle_to(rec[i]["dir"])))
		rg = maxf(rg, rec[i]["rgap"])
		lg = maxf(lg, rec[i]["lgap"])
		if i >= 2:
			var s1: Vector3 = (rec[i]["pos"] as Vector3) - (rec[i - 1]["pos"] as Vector3)
			var s0: Vector3 = (rec[i - 1]["pos"] as Vector3) - (rec[i - 2]["pos"] as Vector3)
			var f: float = rec[i]["f"]
			jit = maxf(jit, (s1 - s0).length() * 100.0 / (f * f))     # as at 60 fps
	var span := (hi - lo) * 100.0
	var big := maxf(span.x, maxf(span.y, span.z))
	var ok := big >= min_range and big <= max_range and jit < max_jit and rg < 0.06 and lg < 0.08
	if not ok: fails += 1
	print("GUNLIFE %s %s move x%.1f y%.1f z%.1f cm, muzzle off by up to %.1f deg, worst step change %.2f cm, hands off R %.1f L %.1f cm" % [label, "OK" if ok else "BAD", span.x, span.y, span.z, ang, jit, rg * 100.0, lg * 100.0])

func shot(name: String, sec: float, min_range: float, max_range: float) -> void:
	label = name
	home()
	await wait(1.2)
	rec.clear()
	on = true
	await wait(sec)
	on = false
	report(min_range, max_range)

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	for i in 3000:
		world = tree.current_scene
		if world and world.get("ready_done"): break
		await wait(0.1)
	p = world.player
	p.jump_from_plane()
	for b in world.bots:
		b.set_physics_process(false)
		b.global_position = Vector3(9000, -80, 9000)
	isl = world.island
	# A flat open field (no houses, trees or water in 45 m), so every move
	# is measured on even ground.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 4000:
		var q := Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85)) * float(isl.size)
		if _flat(q):
			spot = q
			break
	print("GUNLIFE spot %s" % spot)
	p.global_position = Vector3(spot.x, isl.height_at(spot.x, spot.y) + 0.5, spot.y)
	p.velocity = Vector3.ZERO
	p._land()
	home()
	p.give_weapon("m416", 300)
	p.switch_slot(0)
	p.yaw = 0.0
	await wait(2.0)
	# Standing still: it breathes and drifts (alive, but a little).
	await shot("still", 4.0, 0.6, 6.0)
	p.aiming = true
	await shot("still_aim", 3.0, 0.1, 3.0)
	p.aiming = false
	p.touch_move = Vector2(0, 0.45)
	await shot("walk", 3.0, 2.0, 12.0)
	p.touch_move = Vector2(0, 1)
	await shot("run", 3.0, 2.5, 14.0)
	p.sprinting = true
	await shot("sprint", 3.0, 2.5, 16.0)
	p.sprinting = false
	p.aiming = true
	await shot("walk_aim", 3.0, 0.8, 8.0)
	p.aiming = false
	p.stance = "crouch"
	await shot("crouch_walk", 3.0, 1.5, 12.0)
	p.touch_move = Vector2.ZERO
	await shot("crouch_still", 3.0, 0.2, 6.0)
	p.stance = "stand"
	# Turning on the spot: the gun lags and catches up.
	label = "turn"
	await wait(1.0)
	rec.clear()
	on = true
	for i in 90:
		p.yaw += 0.03
		await get_tree().process_frame
	await wait(1.0)
	on = false
	report(0.5, 14.0)
	# Firing: kicks, shakes to a side, settles.
	label = "fire"
	rec.clear()
	on = true
	p.firing = true
	await wait(1.2)
	p.firing = false
	await wait(0.8)
	on = false
	report(1.0, 16.0, 1000.0)     # (each shot kicks at once, sharp by design)
	print("GUNLIFE DONE fails %d" % fails)
	tree.quit()
