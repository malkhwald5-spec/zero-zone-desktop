extends Node
## Screenshots of the plane, freefall (belly and dive), parachute opening,
## canopy flight and landing. Also prints dive speeds.
## Run: godot --path godot res://tests/sky_shots.tscn -- --out=/dir

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
	Game.settings.quality = "high"
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
	# Plane from the side.
	world.plane_t = 0.3
	await wait(0.3)
	p.yaw += PI * 0.5
	p.pitch = -0.1
	await wait(1.0)
	await shot("sky_plane")
	p.jump_from_plane()
	p.yaw = world.plane.rotation.y
	p.pitch = -0.3
	await wait(4.0)
	await shot("sky_belly")
	print("belly speed %.0f km/h" % p.air_speed)
	p.pitch = -1.2
	p.touch_move = Vector2(0, 1)
	Game.settings.controls = "touch"
	await wait(5.0)
	await shot("sky_dive")
	print("dive speed %.0f km/h  dive=%.2f" % [p.air_speed, p.dive])
	p.pitch = -0.1
	await wait(4.0)
	print("glide speed %.0f km/h  vy=%.1f" % [p.air_speed, p.velocity.y])
	p.touch_move = Vector2.ZERO
	p.pitch = -0.25
	p.open_chute()
	await wait(0.5)
	await shot("sky_opening")
	await wait(2.0)
	print("chute speed %.0f km/h vy=%.1f" % [p.air_speed, p.velocity.y])
	p.yaw = p.chute_heading + PI * 0.5
	p.pitch = -0.15
	p.touch_move = Vector2(-1, 0)
	await wait(1.2)
	await shot("sky_turn")
	p.touch_move = Vector2.ZERO
	p.yaw = p.chute_heading + PI
	p.pitch = 0.25
	await wait(2.0)
	await shot("sky_front")
	# Drop to just above the ground.
	var g: float = world.ground_height(p.global_position)
	p.global_position.y = g + 6.0
	p.yaw = p.chute_heading + 0.6
	p.pitch = -0.2
	await wait(1.5)
	await shot("sky_landed")
	print("state after landing: ", p.state)
	tree.quit()
