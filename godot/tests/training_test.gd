extends Node
## The training ground: no bots, no zone, the player on open ground, and each
## step ticks off when its action is done, through to the reward at the end.

var out := "user://"
var fails := 0

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok: fails += 1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.settings.controls = "touch"
	Game.settings.mode = "solo"
	Game.wallet.training_done = false
	Game.training = true
	_run.call_deferred()

## Waits until the training moves past step i (or gives up).
func _past(tr: Training, i: int) -> bool:
	for k in 60:
		if tr.step > i: return true
		await wait(0.1)
	return false

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done and world.training != null: break
		await wait(0.1)
	var tr: Training = world.training
	var p: Player = world.player
	check("training started", tr != null and tr.step == 0)
	check("no bots", world.bots.is_empty())
	check("on the ground", p.state == "ground", p.state)
	await wait(1.0)
	await shot("train_0")
	var gold0 := int(Game.wallet.gold)
	# 0 walk to the ring
	p.global_position = tr.marker.global_position + Vector3(0, 0.5, 0)
	check("walk", await _past(tr, 0))
	# 1 jump
	await wait(0.3)
	p.velocity.y = 5.4
	check("jump", await _past(tr, 1))
	await wait(0.6)
	p.set_stance("crouch")
	check("crouch", await _past(tr, 2))
	p.set_stance("prone")
	check("prone", await _past(tr, 3))
	await shot("train_rifle")
	p.set_stance("stand")
	p.give_weapon("m416", 30)
	p.ammo["556"] = 60
	check("rifle", await _past(tr, 4))
	p.gear.vest = 2
	p.gear.helmet = 2
	check("armour", await _past(tr, 5))
	await wait(0.5)
	await shot("train_targets")
	for t in tr.targets: t.take_damage(999.0, p)
	check("targets", await _past(tr, 6))
	p.aiming = true
	tr.targets[-1].take_damage(999.0, p)
	p.aiming = false
	check("aimed shot", await _past(tr, 7))
	check("hurt for the heal step", p.health <= 55.0, str(p.health))
	p.health = 80.0
	check("heal", await _past(tr, 8))
	p.throwables.frag = 1
	check("grenade", await _past(tr, 9))
	await wait(0.5)
	await shot("train_car")
	check("car placed", is_instance_valid(tr.car))
	p.enter_vehicle(tr.car)
	check("in the car", await _past(tr, 10))
	await wait(0.3)
	tr.car.global_position += Vector3(50, 0, 0)
	check("drive", await _past(tr, 11))
	await wait(0.5)
	check("finished", tr.step >= tr.steps.size())
	check("reward", bool(Game.wallet.get("training_done", false)) and int(Game.wallet.gold) == gold0 + 300, "%d -> %d" % [gold0, int(Game.wallet.gold)])
	check("player can't die here", not p.take_damage(500.0, null) and p.health > 0.0)
	await shot("train_done")
	print("TRAINING TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
