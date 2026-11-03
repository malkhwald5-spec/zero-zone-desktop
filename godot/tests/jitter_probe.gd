extends Node
## Is there jitter in the player's own movement? The player walks and runs in
## a straight line; every drawn frame the body (as drawn), the hips, the right
## hand, the gun and the pack are recorded. A smooth move has even steps:
## the report gives, per part, how uneven the steps are (mean and worst
## change of step from one frame to the next, in cm) for the body's travel
## and for each part relative to the body.
## Run: godot --headless --path godot --fixed-fps 45 res://tests/jitter_probe.tscn

var world: Node
var p: Player
var rec: Array = []
var on := false
var label := ""

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	Game.settings.controls = "touch"
	Game.settings.mode = "solo"
	Game.spawn_island = false
	_run.call_deferred()

func _process(_d: float) -> void:
	if not on or p == null: return
	var m: HumanModel = p.model
	# What is drawn: the body where the engine draws it (between ticks) and
	# every part where it sits on the body (its place in the player's own
	# space, which is what the drawn body carries along).
	var body: Vector3 = p.get_global_transform_interpolated().origin
	var inv: Transform3D = p.global_transform.affine_inverse()
	var sk_xf: Transform3D = m.sk.global_transform
	var hips: Vector3 = inv * (sk_xf * m.sk.get_bone_global_pose(m._bone["Hips"]).origin)
	var hand: Vector3 = inv * (sk_xf * m.sk.get_bone_global_pose(m._bone["RightHand"]).origin)
	var gun: Vector3 = inv * m.gun.global_position
	var pack: Vector3 = inv * m.pack.global_position if m.pack and m.pack.visible else Vector3.ZERO
	var cam: Vector3 = p.camera.global_position
	if rec.size() > 1:
		var d1: Vector3 = body - (rec[-1]["body"] as Vector3)
		var d0: Vector3 = (rec[-1]["body"] as Vector3) - (rec[-2]["body"] as Vector3)
		if (d1 - d0).length() > 0.05:
			print("BODYSPIKE %s frame %d step %s prev %s floor %s vel %s" % [label, rec.size(), d1, d0, p.is_on_floor(), p.velocity])
	if rec.size() > 0 and (hand - (rec[-1]["hand"] as Vector3)).length() > 0.2:
		print("SPIKE %s frame %d anim %s state %s stance %s action %s vault %.2f floor %s" % [label, rec.size(), m._anim, p.state, p.stance, m._action, p.vault_t, p.is_on_floor()])
	rec.append({"body": body, "hips": hips, "hand": hand, "gun": gun, "pack": pack, "cam": cam})

func report() -> void:
	for key in ["body", "cam", "hips", "hand", "gun", "pack"]:
		var steps: Array = []
		for i in range(1, rec.size()):
			steps.append((rec[i][key] as Vector3) - (rec[i - 1][key] as Vector3))
		var sum := 0.0
		var worst := 0.0
		for i in range(1, steps.size()):
			var j: float = ((steps[i] as Vector3) - (steps[i - 1] as Vector3)).length() * 100.0
			sum += j
			worst = maxf(worst, j)
		print("JITTER %s %s mean %.2f cm worst %.2f cm (frames %d)" % [label, key, sum / maxf(steps.size() - 1, 1), worst, rec.size()])

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
	var isl = world.island
	var t: Dictionary = isl.towns[0]
	var c: Vector2 = t.pos + Vector2(float(t.r) + 60.0, 0)
	p.global_position = Vector3(c.x, isl.height_at(c.x, c.y) + 0.5, c.y)
	p.velocity = Vector3.ZERO
	p._land()
	p.global_position = Vector3(c.x, isl.height_at(c.x, c.y) + 0.5, c.y)
	p.give_weapon("m416", 30)
	p.switch_slot(0)
	p.equip("pack", 2, 0.0)
	p.yaw = 0.0
	await wait(2.0)
	for mode in [["walk", Vector2(0, 0.45), false], ["run", Vector2(0, 1), false], ["sprint", Vector2(0, 1), true]]:
		label = mode[0]
		p.touch_move = mode[1]
		p.sprinting = mode[2]
		await wait(1.5)
		rec.clear()
		on = true
		await wait(3.0)
		on = false
		report()
	print("JITTER DONE")
	tree.quit()
