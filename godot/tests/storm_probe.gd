extends Node
## Dune Valley sandstorm: starts it and prints what the air does (headless).
func _ready() -> void:
	Game.spawn_island = false
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/world.tscn")
	await tree.create_timer(0.5).timeout
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await tree.create_timer(0.1).timeout
	world.player.jump_from_plane()
	world.player.state = "ground"
	print("STORM map=", world.island.map_id, " events=", world.events != null, " fx=", world.region_fx != null, " fog0=", world.builder.env.fog_density, " lite=", Game.lite())
	world.events.start("sandstorm")
	for k in 6:
		await tree.create_timer(2.0).timeout
		print("STORM t=%d storm=%.2f fog=%.4f kind=%s" % [k * 2, world.region_fx.storm, world.builder.env.fog_density, world.region_fx._kind])
	tree.quit()
