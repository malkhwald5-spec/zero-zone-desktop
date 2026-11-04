extends Node
## Smooth with every move: the player goes through one move after another
## (still, walk, run, sprint, stop, aim, crouch, prone, stand up, jump) and
## every drawn frame records the gun and the backpack on the body. Reported
## per move: the hardest change of speed (cm or degrees per frame, per frame,
## as at 60 fps): a smooth hand-over from one move to the next keeps it low,
## a snap shows as a spike. Also how far each hand gets off its grip.
## Run: godot --headless --path godot --fixed-fps 45 res://tests/smooth_probe.tscn

var world: Node
var p: Player
var isl
var spot := Vector2.ZERO
var rec: Array = []
var label := ""
var marks: Array = []        # [frame, label]
var on := false
var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	Game.settings.controls = "touch"
	Game.settings.mode = "solo"
	Game.spawn_island = false
	_run.call_deferred()

func _process(d: float) -> void:
	if not on or p == null: return
	var m: HumanModel = p.model
	var inv: Transform3D = m.global_transform.affine_inverse()
	var g: Transform3D = m.gun.transform
	var pk: Transform3D = inv * m.pack.global_transform
	var sk_xf: Transform3D = m.sk.global_transform
	var gg: Transform3D = m.gun.global_transform
	var rh: Vector3 = sk_xf * m.sk.get_bone_global_pose(m._bone["RightHand"]).origin
	var lh: Vector3 = sk_xf * m.sk.get_bone_global_pose(m._bone["LeftHand"]).origin
	var fore_v: Vector3 = m.weapon_node.get_meta("fore", Vector3(0, -0.06, -0.32)) if m.weapon_node else Vector3(0, -0.06, -0.32)
	# (sprinting the gun is carried in the left hand, the right one let go:
	# the two-handed grip is not what is measured then)
	var carried: bool = (m._smv.get(&"carry", Vector2.ZERO) as Vector2).x > 0.02
	var rgap := rh.distance_to(gg * Vector3(0.0, -0.06, 0.07)) if m.gun.visible and not carried else 0.0
	var lgap := lh.distance_to(gg * (fore_v * HumanModel.WSCALE + Vector3(-0.02, -0.02, 0.06))) if m.gun.visible and not carried else 0.0
	# The pack's bottom (it swings from the top): where it is and points.
	# (on the back: where it sits against the frame it hangs from, so the
	# body's own movement is left out and only the pack's is measured)
	var pf: Transform3D = inv * (m.pack.get_parent() as Node3D).global_transform
	var pb: Vector3 = pf.orthonormalized().affine_inverse() * (pk * Vector3(0, -0.2 / maxf(m.pack.scale.x, 1e-3), 0))
	var anc: Vector3 = (inv * (m.pack.get_parent() as Node3D).global_transform).origin
	var chest: Vector3 = inv * (sk_xf * m.sk.get_bone_global_pose(m._bone["Spine2"]).origin)
	var hips: Vector3 = inv * (sk_xf * m.sk.get_bone_global_pose(m._bone["Hips"]).origin)
	if OS.get_cmdline_user_args().has("--trace") and label in ["prone", "prone_up", "stand_up"]:
		print("TRACE %s %d act %s anim %s pose %s chest %s gun %s xf %.2f/%.2f hold %.2f rgap %.1f lgap %.1f vis %s gdir %s lsh %s fore %s" % [label, rec.size(), m.is_acting(), m._anim, p.stance, chest, m.gun.transform.origin, m._xf_t, m._xf_dur, m._hold_t, rgap * 100.0, lgap * 100.0, m.gun.visible, -m.gun.transform.basis.z, inv * (sk_xf * m.sk.get_bone_global_pose(m._bone["LeftArm"]).origin), inv * (gg * (fore_v * HumanModel.WSCALE + Vector3(-0.02, -0.02, 0.06)))])
	rec.append({"anc": anc, "chest": chest, "hips": hips, "base": m._gun_xf.origin, "bdir": -m._gun_xf.basis.z.normalized(), "cdir": -((m._sk_to_model() * m.sk.get_bone_global_pose(m._bone["Spine2"])).basis.orthonormalized().z), "ph": m._loco.phase if m._loco else 0.0, "ps": m._pack_s, "sl": (m._smv.get(&"pack_slide", Vector2.ZERO) as Vector2).x, "spd": m._speed, "plocal": m.pack.position, "label": label, "anim": m._anim, "gun": g.origin, "gdir": -g.basis.z.normalized(), "pack": pb, "pdir": pk.basis.y.normalized(), "f": clampf(d * 60.0, 0.5, 3.0), "act": m.is_acting(), "rgap": rgap, "lgap": lgap, "vis": m.gun.visible})

func step(name: String, sec: float) -> void:
	label = name
	await wait(sec)

func report() -> void:
	var per := {}
	var order: Array = []
	for i in range(2, rec.size()):
		var r: Dictionary = rec[i]
		var a: Dictionary = rec[i - 1]
		var b: Dictionary = rec[i - 2]
		if r.act or a.act or b.act or not (r.vis and a.vis and b.vis): continue
		var f: float = r.f
		var k: float = 1.0 / (f * f)
		var gj: float = (((r.gun as Vector3) - a.gun) - ((a.gun as Vector3) - b.gun)).length() * 100.0 * k
		var ga: float = rad_to_deg((((r.gdir as Vector3) - a.gdir) - ((a.gdir as Vector3) - b.gdir)).length()) * k
		var pj: float = (((r.pack as Vector3) - a.pack) - ((a.pack as Vector3) - b.pack)).length() * 100.0 * k
		var lb: String = r.label
		if OS.get_cmdline_user_args().has("--diag") and ga > 1.2:
			var bd: float = rad_to_deg((((r.bdir as Vector3) - a.bdir) - ((a.bdir as Vector3) - b.bdir)).length()) * k
			var cd: float = rad_to_deg((((r.cdir as Vector3) - a.cdir) - ((a.cdir as Vector3) - b.cdir)).length()) * k
			print("ADIAG %s frame %d anim %s gun %.2f base %.2f chest %.2f phase %.3f->%.3f speed %.2f" % [lb, i, r.anim, ga, bd, cd, a.ph, r.ph, r.spd])
		if OS.get_cmdline_user_args().has("--diag") and (gj > 1.0 or pj > 0.6 or r.lgap > 0.04):
			var parts := ""
			for key in ["anc", "chest", "hips", "base", "plocal", "gun", "pack"]:
				parts += " %s %.2f" % [key, (((r[key] as Vector3) - a[key]) - ((a[key] as Vector3) - b[key])).length() * 100.0 * k]
			print("DIAG %s frame %d anim %s%s ps %s slide %.3f lgap %.1f" % [lb, i, r.get("anim", ""), parts, r.ps, r.sl, r.lgap * 100.0])
		if not per.has(lb):
			per[lb] = [0.0, 0.0, 0.0, 0.0, 0.0]
			order.append(lb)
		var e: Array = per[lb]
		e[0] = maxf(e[0], gj)
		e[1] = maxf(e[1], ga)
		e[2] = maxf(e[2], pj)
		e[3] = maxf(e[3], r.rgap * 100.0)
		e[4] = maxf(e[4], r.lgap * 100.0)
	for lb in order:
		var e: Array = per[lb]
		# A change of stance or a jump is a big move of the whole body: it may
		# speed up harder (no snap is what counts there); a sprint swings the
		# gun with the body's own swing.
		var big := 2.0 if lb in ["crouch", "stand_up", "prone", "prone_up", "jump"] else 1.0
		var sw := 1.5 if lb.begins_with("sprint") else 1.2
		var ok: bool = e[0] < 1.0 * big and e[1] < sw * big and e[2] < 0.6 * big and e[3] < 3.0 and e[4] < 4.0
		if not ok: fails += 1
		print("SMOOTH %-14s %s gun %.2f cm %.2f deg, pack %.2f cm, hands off R %.1f L %.1f cm" % [lb, "OK " if ok else "BAD", e[0], e[1], e[2], e[3], e[4]])

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
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 4000:
		var q := Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85)) * float(isl.size)
		if _flat(q):
			spot = q
			break
	p.global_position = Vector3(spot.x, isl.height_at(spot.x, spot.y) + 0.5, spot.y)
	p.velocity = Vector3.ZERO
	p._land()
	p.give_weapon("m416", 300)
	p.switch_slot(0)
	p.equip("pack", 2, 0.0)
	p.yaw = 0.0
	await wait(3.0)
	p.global_position = Vector3(spot.x, isl.height_at(spot.x, spot.y) + 0.1, spot.y)
	p.reset_physics_interpolation()
	await wait(1.0)
	on = true
	await step("still", 1.5)
	p.touch_move = Vector2(0, 0.45)
	await step("walk", 1.8)
	p.touch_move = Vector2(0, 1)
	await step("run", 1.8)
	p.sprinting = true
	await step("sprint", 1.8)
	p.sprinting = false
	await step("sprint>run", 1.2)
	p.touch_move = Vector2(0.7, 0.7)
	await step("run_diag", 1.2)
	for i in 50:
		p.yaw += 0.04
		await get_tree().process_frame
	label = "run_turn"
	await wait(0.5)
	p.touch_move = Vector2.ZERO
	await step("stop", 1.8)
	p.aiming = true
	await step("aim", 1.5)
	p.touch_move = Vector2(0, 0.45)
	await step("walk_aim", 1.5)
	p.touch_move = Vector2.ZERO
	p.aiming = false
	await step("aim_off", 1.5)
	p.stance = "crouch"
	await step("crouch", 1.5)
	p.touch_move = Vector2(0, 0.6)
	await step("crouch_walk", 1.5)
	p.touch_move = Vector2.ZERO
	p.stance = "stand"
	await step("stand_up", 1.5)
	p.stance = "prone"
	await step("prone", 2.0)
	p.stance = "stand"
	await step("prone_up", 2.0)
	p.touch_move = Vector2(0, 1)
	await step("run2", 1.0)
	p.jump_queued = true
	await step("jump", 2.0)
	p.touch_move = Vector2.ZERO
	await step("end", 1.0)
	on = false
	report()
	print("SMOOTH DONE fails %d" % fails)
	tree.quit()
