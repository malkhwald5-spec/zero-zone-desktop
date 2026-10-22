extends Node
## English: plain text and text with numbers / names put in translate, the
## lobby and the match HUD come up in English, and Arabic comes back.

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
	_run.call_deferred()

func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	Game.settings.lang = "en"
	Game.apply_lang()
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://i18n/en.json"))
	check("translations load", typeof(data) == TYPE_DICTIONARY and data.size() > 800)
	check("plain text", Game.t("لعب") == String(data.get("لعب", "?")) and Game.t("لعب") != "لعب", Game.t("لعب"))
	# Every key with a number or a name in it, filled in, comes out in English with the value kept.
	var n := 0
	var bad := []
	for k in data:
		var key := String(k)
		if not ("%d" in key) or "%s" in key or "%." in key or "%0" in key: continue
		var filled := key.replace("%%", "%").replace("%d", "47")
		var got := Game.t(filled)
		n += 1
		if got == filled or not got.contains("47"): bad.append(key)
	check("filled-in text (%d keys)" % n, bad.is_empty(), str(bad.slice(0, 3)))
	tree.change_scene_to_file("res://scenes/lobby.tscn")
	await wait(3.0)
	await shot("en_lobby")
	tree.change_scene_to_file("res://scenes/world.tscn")
	await wait(0.5)
	var world = tree.current_scene
	for i in 900:
		if world.ready_done: break
		await wait(0.1)
	await wait(1.5)
	await shot("en_hud")
	Game.settings.lang = "ar"
	Game.apply_lang()
	check("back to Arabic", Game.t("لعب") == "لعب")
	print("LANG TEST %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	tree.quit()
