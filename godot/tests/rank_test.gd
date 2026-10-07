extends Node
## Ranks: tier names and steps, points after a match, career totals and history;
## pictures of the results screen with the rank change and the career page.
## The saved stats are put back at the end.

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
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	var saved: Dictionary = Game.stats.duplicate(true)
	var saved_mode: String = Game.settings.get("mode", "solo")
	# Tier names.
	check("start is Bronze V", Game.rank_info(1000).name == "برونز V", Game.rank_info(1000).name)
	check("1150 is Bronze IV", Game.rank_info(1150).name == "برونز IV", Game.rank_info(1150).name)
	check("1499 is Bronze I", Game.rank_info(1499).name == "برونز I", Game.rank_info(1499).name)
	check("2000 is Gold V", Game.rank_info(2000).name == "ذهب V", Game.rank_info(2000).name)
	check("4200 is Ace", Game.rank_info(4200).name == "آس")
	check("5000 is Conqueror", Game.rank_info(5000).name == "الفاتح" and Game.rank_info(5000).to_next == 0)
	check("progress in a step", absf(Game.rank_info(1150).frac - 0.5) < 0.01)
	# Points.
	check("a win gains a lot", Game.rank_delta(1, 100, 6, true, 1000) > 60, str(Game.rank_delta(1, 100, 6, true, 1000)))
	check("early exit loses", Game.rank_delta(95, 100, 0, false, 2600) < 0, str(Game.rank_delta(95, 100, 0, false, 2600)))
	check("top 10 without kills still gains", Game.rank_delta(8, 100, 0, false, 1200) > 0, str(Game.rank_delta(8, 100, 0, false, 1200)))
	# Career.
	Game.stats.rp = 1000
	Game.stats.history = []
	Game.stats.modes = {}
	var r := Game.record_match({"rank": 90, "teams": 100, "kills": 0, "won": false, "dmg": 10, "heads": 0, "longest": 0, "time": 60, "mode": "solo"})
	check("never below Bronze V", int(Game.stats.rp) == 1000 and r.delta == 0)
	r = Game.record_match({"rank": 1, "teams": 25, "kills": 7, "won": true, "dmg": 940, "heads": 3, "longest": 212, "time": 1500, "mode": "squad"})
	check("win raises rank", int(Game.stats.rp) > 1050 and r.delta > 50, "%d %s" % [int(Game.stats.rp), r.after.name])
	check("history newest first", Game.stats.history.size() == 2 and int(Game.stats.history[0].rank) == 1)
	check("squad totals", int(Game.stats.modes.squad.wins) == 1 and int(Game.stats.modes.squad.kills) == 7)
	check("longest kill kept", int(Game.stats.longest) >= 212)
	for i in 6:
		Game.record_match({"rank": 3 + i * 7, "teams": 100, "kills": 4 - i % 4, "won": false, "dmg": 300 + i * 40, "heads": 1, "longest": 80 + i * 30, "time": 600 + i * 50, "mode": ["solo", "duo"][i % 2]})
	# Results screen in a real match.
	Game.settings.mode = "solo"
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	var p: Player = world.player
	p.jump_from_plane()
	var c: Vector2 = world.island.towns[1].pos
	p.global_position = Vector3(c.x, world.ground_height(Vector3(c.x, 0, c.y)) + 1.0, c.y)
	await wait(1.0)
	var games0: int = Game.stats.history.size()
	p.kills = 5
	p.dmg_dealt = 612.0
	p.head_kills = 2
	for b in world.bots: b._die(p)
	await wait(0.6)
	check("match recorded", Game.stats.history.size() == mini(10, games0 + 1) and bool(Game.stats.history[0].won))
	check("damage recorded", int(Game.stats.history[0].dmg) == 612, str(Game.stats.history[0].dmg))
	check("results show rank", world.hud.results != null and not world.hud._rank_change.is_empty())
	await wait(0.3)
	await shot("rank_results")
	# Career page in the lobby.
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await wait(2.0)
	await shot("rank_lobby")
	var lobby = tree.current_scene
	lobby._open("cards")
	await wait(0.6)
	await shot("rank_page")
	var sc: ScrollContainer = null
	for n in lobby.panel.get_children():
		if n is ScrollContainer: sc = n
	if sc:
		sc.scroll_vertical = 2000
		await wait(0.3)
		await shot("rank_page_history")
	Game.stats = saved
	Game.settings.mode = saved_mode
	Game.save_data()
	print("RANK TEST ", "OK" if fails == 0 else "FAILED", " (%d failed)" % fails)
	tree.quit()
