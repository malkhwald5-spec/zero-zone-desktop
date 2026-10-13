extends Node
## Screenshots of the trip down: riding the plane, freefall (belly and dive),
## the open parachute from behind and from the side, an airdrop plane.
## Run: godot --path godot res://tests/air_shots.tscn -- --out=/dir

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
	print("props ", world.plane.get_meta("props", []).size())
	await wait(2.0)
	p.yaw += 0.6
	await wait(0.5)
	await shot("air_plane")
	p.jump_from_plane()
	await wait(2.0)
	await shot("air_fall")
	p.dive = 1.0
	await get_tree().process_frame
	await shot("air_dive")
	p.global_position.y = 300.0
	p.open_chute()
	await wait(3.0)
	await shot("air_chute")
	p.yaw += PI * 0.5
	await wait(0.6)
	await shot("air_chute_side")
	# An airdrop plane passing overhead.
	world.call_drop()
	await wait(0.2)
	var f: Dictionary = world._drop_flights.back()
	f.t = 0.5
	var at: Vector3 = f.from.lerp(f.to, 0.5)
	p.global_position = at + Vector3(0, -40, 0) + (f.to - f.from).normalized().cross(Vector3.UP) * 60.0
	p.velocity = Vector3.ZERO
	var d: Vector3 = at - p.global_position
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = 0.3
	await wait(0.6)
	await shot("air_drop_plane")
	tree.quit()
