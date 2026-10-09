extends Node
## Global state (autoload "Game"): settings, player profile, career stats and shared data.

const MAP_SIZE := 8192.0          # metres; shown on the map as an 8×8 grid (1 km squares)
const GRID := 8
const SAVE_PATH := "user://zero_zone.json"
const VERSION := "v1.0.0"
const STUDIO := "Jordan Dan"
const SEASON_NAME := "ليلة القمر الأحمر"
const PASS_XP := 300               # season-pass XP per level
const PASS_MAX := 30

## Weapons. dmg per hit, rate = seconds between shots, range in metres.
const WEAPONS := {
	"p92":    {"name": "P92",    "cls": "pistol",  "ammo": "9mm", "dmg": 24, "rate": 0.17,  "mag": 15, "reload": 1.6, "spread": 1.6, "range": 120, "auto": false, "zoom": 1.0, "recoil": 1.2},
	"ump":    {"name": "UMP45",  "cls": "smg",     "ammo": "9mm", "dmg": 22, "rate": 0.092, "mag": 25, "reload": 2.0, "spread": 2.2, "range": 160, "auto": true,  "zoom": 1.2, "recoil": 0.7},
	"s1897":  {"name": "S1897",  "cls": "shotgun", "ammo": "12g", "dmg": 12, "rate": 0.85,  "mag": 5,  "reload": 2.6, "spread": 5.5, "range": 45,  "auto": false, "zoom": 1.0, "recoil": 4.0, "pellets": 9},
	"m416":   {"name": "M416",   "cls": "ar",      "ammo": "556", "dmg": 22, "rate": 0.086, "mag": 30, "reload": 2.1, "spread": 1.4, "range": 400, "auto": true,  "zoom": 1.5, "recoil": 0.9},
	"akm":    {"name": "AKM",    "cls": "ar",      "ammo": "762", "dmg": 27, "rate": 0.1,   "mag": 30, "reload": 2.3, "spread": 2.0, "range": 400, "auto": true,  "zoom": 1.5, "recoil": 1.4},
	"mp44":   {"name": "MP44",   "cls": "ar",      "ammo": "762", "dmg": 26, "rate": 0.11,  "mag": 30, "reload": 2.4, "spread": 1.7, "range": 380, "auto": true,  "zoom": 1.5, "recoil": 1.2},
	"kar98":  {"name": "Kar98k", "cls": "sr",      "ammo": "762", "dmg": 85, "rate": 1.5,   "mag": 5,  "reload": 3.2, "spread": 0.1, "range": 800, "auto": false, "zoom": 4.0, "recoil": 5.0},
	"vector": {"name": "Vector", "cls": "smg",     "ammo": "9mm", "dmg": 19, "rate": 0.055, "mag": 19, "reload": 1.9, "spread": 1.9, "range": 140, "auto": true,  "zoom": 1.2, "recoil": 0.5},
	"uzi":    {"name": "Micro UZI", "cls": "smg",  "ammo": "9mm", "dmg": 18, "rate": 0.048, "mag": 25, "reload": 1.8, "spread": 2.6, "range": 110, "auto": true,  "zoom": 1.1, "recoil": 0.6},
	"scar":   {"name": "SCAR-L", "cls": "ar",      "ammo": "556", "dmg": 22, "rate": 0.096, "mag": 30, "reload": 2.0, "spread": 1.3, "range": 400, "auto": true,  "zoom": 1.5, "recoil": 0.75},
	"beryl":  {"name": "Beryl M762", "cls": "ar",  "ammo": "762", "dmg": 28, "rate": 0.086, "mag": 30, "reload": 2.4, "spread": 2.2, "range": 400, "auto": true,  "zoom": 1.5, "recoil": 1.6},
	"sks":    {"name": "SKS",    "cls": "dmr",     "ammo": "762", "dmg": 50, "rate": 0.25,  "mag": 10, "reload": 2.9, "spread": 0.5, "range": 650, "auto": false, "zoom": 2.0, "recoil": 2.4},
	"mini14": {"name": "Mini14", "cls": "dmr",     "ammo": "556", "dmg": 44, "rate": 0.2,   "mag": 20, "reload": 2.6, "spread": 0.35, "range": 700, "auto": false, "zoom": 2.0, "recoil": 1.6},
	"crossbow": {"name": "قوس (كروسبو)", "cls": "crossbow", "ammo": "bolt", "dmg": 105, "rate": 0.4, "mag": 1, "reload": 3.0, "spread": 0.3, "range": 300, "auto": false, "zoom": 1.6, "recoil": 1.0, "silent": true},
	"pan":    {"name": "مقلاة",  "cls": "melee",   "ammo": "9mm", "dmg": 80, "rate": 0.75,  "mag": 0,  "reload": 0.1, "spread": 0.0, "range": 2.4, "auto": false, "zoom": 1.0, "recoil": 0.0, "melee": true},
	# Airdrop-only weapons
	"awm":    {"name": "AWM",    "cls": "sr",      "ammo": "300", "dmg": 120, "rate": 1.8,  "mag": 5,  "reload": 3.6, "spread": 0.05, "range": 1000, "auto": false, "zoom": 6.0, "recoil": 6.0, "crate": true},
	"m249":   {"name": "M249",   "cls": "lmg",     "ammo": "556", "dmg": 22, "rate": 0.075, "mag": 100, "reload": 5.5, "spread": 2.2, "range": 450, "auto": true,  "zoom": 1.5, "recoil": 0.8, "crate": true},
	"groza":  {"name": "Groza",  "cls": "ar",      "ammo": "762", "dmg": 28, "rate": 0.08,  "mag": 30, "reload": 2.4, "spread": 1.5, "range": 420, "auto": true,  "zoom": 1.5, "recoil": 1.1, "crate": true},
}
const AMMO_NAMES := {"9mm": "9 ملم", "556": "5.56 ملم", "762": "7.62 ملم", "12g": "خرطوش 12", "300": ".300 ماغنوم", "bolt": "سهام قوس"}

## Wardrobe items: [name, shirt colour, pants colour, price in gold (0 = owned from start), style].
## Style "" = plain uniform tint, "gold" = gold-plated armour, "panda" = panda mask.
const WARDROBE := [
	["أزرق المدينة", Color("2d6fb8"), Color("3a4250"), 0],
	["زيتي الصحراء", Color("3f5f3a"), Color("6b5f45"), 0],
	["خطوط البحر", Color("2f8f86"), Color("b7ad95"), 0],
	["أحمر النار", Color("a8302c"), Color("2b2b2e"), 250],
	["الظل الأسود", Color("1f2023"), Color("1a1a1c"), 400],
	["رمال ذهبية", Color("c9b48a"), Color("7a6a4c"), 300],
	["ليلة القمر", Color("5e3a7a"), Color("2b2433"), 600],
	["الثلج", Color("e6e8ea"), Color("9aa3ab"), 500],
	["المحارب الذهبي", Color("d9a53a"), Color("8a6420"), 1500, "gold"],
	["الباندا", Color("f2f2f0"), Color("2f4a72"), 1200, "panda"],
	["لولا", Color("d9662a"), Color("d9662a"), 0, "lola"],
]

var settings := {
	"controls": "kbm",        # "kbm" (keyboard + mouse, PC default) or "touch" (on-screen buttons)
	"quality": "medium",      # PUBG Mobile names: "low" سلس | "medium" متوازن | "high" HD | "hdr" HDR | "ultra" ألترا HD
	"fps": 60,                # frame-rate cap: 30 | 60 | 90 | 120
	"sensitivity": 1.0,
	"sound": true,
	"difficulty": "normal",
	"weather": "random",      # "random" | "clear" | "rain" | "sunset" | "fog"
	"aim_sens": 0.45,         # look speed while aiming / scoped, relative to normal
	"invert_y": false,
	"keys": {},               # action -> physical keycode, only the ones changed
	"mode": "solo",           # "solo" | "duo" | "squad"
	"laptop": false,          # laptop mode: lighter effects, lower render resolution, shorter view
	"render_scale": 1.0,      # 3D resolution (0.5–1.0), sharpened back up with FSR
	"show_fps": true,         # frame counter under the minimap
}

const MODE_NAMES := {"solo": "فردي", "duo": "ثنائي", "squad": "فرقة"}

## Players per team in the chosen mode.
func team_size() -> int:
	return {"solo": 1, "duo": 2, "squad": 4}.get(settings.get("mode", "solo"), 1)

## Keyboard actions you can rebind (Settings → الأزرار), their default keys
## and names. Esc and 4-8 (heals) stay fixed.
const KEY_ORDER := ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "crouch", "prone",
	"interact", "reload", "peek_l", "peek_r", "heal", "boost", "throw", "throw_kind", "slot1", "slot2", "slot3", "map", "bag", "cursor"]
const KEY_DEFAULTS := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"sprint": KEY_SHIFT, "jump": KEY_SPACE, "crouch": KEY_C, "prone": KEY_Z, "interact": KEY_F, "reload": KEY_R,
	"peek_l": KEY_Q, "peek_r": KEY_E, "heal": KEY_H, "boost": KEY_Y, "throw": KEY_G, "throw_kind": KEY_T,
	"slot1": KEY_1, "slot2": KEY_2, "slot3": KEY_3, "map": KEY_M, "bag": KEY_B, "cursor": KEY_CTRL}
const KEY_NAMES := {"move_forward": "لقدام", "move_back": "لورا", "move_left": "يسار", "move_right": "يمين",
	"sprint": "ركض", "jump": "قفز / نطّ فوق حيط", "crouch": "انحناء", "prone": "انبطاح", "interact": "التقاط / ركوب / فتح صندوق",
	"reload": "تلقيم", "peek_l": "ميلان يسار", "peek_r": "ميلان يمين", "heal": "علاج", "boost": "منشّط",
	"throw": "رمي قنبلة", "throw_kind": "نوع القنبلة", "slot1": "السلاح الأول", "slot2": "السلاح الثاني",
	"slot3": "المسدس", "map": "الخريطة", "bag": "الحقيبة", "cursor": "إظهار الماوس"}

## The physical key for an action.
func key(action: String) -> int:
	return int(settings.keys.get(action, KEY_DEFAULTS.get(action, 0)))

## The action on a physical key ("" if none).
func action_for(code: int) -> String:
	for a in KEY_ORDER:
		if key(a) == code: return a
	return ""

## Put an action on a key; whatever was on that key takes the old one.
func set_key(action: String, code: int) -> void:
	var other := action_for(code)
	if other != "" and other != action:
		settings.keys[other] = key(action)
	settings.keys[action] = code
	apply_keys()
	save_data()

func reset_keys() -> void:
	settings.keys = {}
	apply_keys()
	save_data()

static func key_label(code: int) -> String:
	match code:
		KEY_SPACE: return "Space"
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_TAB: return "Tab"
	return OS.get_keycode_string(code)

## WASD (or the chosen keys) are input-map actions; the rest is read by code.
func apply_keys() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		if not InputMap.has_action(a): InputMap.add_action(a, 0.5)
		InputMap.action_erase_events(a)
		var ev := InputEventKey.new()
		ev.physical_keycode = key(a)
		InputMap.action_add_event(a, ev)

const WEATHER_NAMES := {"random": "عشوائي", "clear": "صافي", "rain": "مطر", "sunset": "غروب", "fog": "ضباب الصبح"}

## This match's weather (from the setting, or picked at random).
func pick_weather() -> String:
	var w: String = settings.get("weather", "random")
	if w != "random": return w
	var r := randf()
	return "clear" if r < 0.45 else ("rain" if r < 0.65 else ("sunset" if r < 0.82 else "fog"))
const LOLA := 10            # WARDROBE index of the Lola character (the default look)
var profile := {"name": "", "outfit": LOLA, "clan": "", "owned": [0, 1, 2, LOLA]}
var stats := {"wins": 0, "best": 0, "kills": 0, "games": 0,
	"rp": 1000, "top10": 0, "dmg": 0, "heads": 0, "longest": 0, "best_kills": 0, "time": 0,
	"modes": {}, "history": []}
## Lobby economy: gold earned in matches, season-pass XP, claimed mail/rewards.
var wallet := {"gold": 0, "zc": 0, "xp": 0, "claimed": [], "mail_read": false}
## Key art rendered once at start-up (used by the loading screens).
var key_art: Texture2D
## Last match summary shown in the lobby.
var last_reward := {}
## In a match with keyboard+mouse: true while the player freed the cursor with Ctrl.
var cursor_free := false

func _ready() -> void:
	load_data()
	apply_fps.call_deferred()

## First launch: integrated graphics (Intel) start on متوازن, real cards on HD.
func _auto_quality() -> void:
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	if not (gpu.contains("intel") or gpu.contains("uhd") or gpu.contains("iris") or gpu.contains("llvmpipe")):
		settings.quality = "high"
	if is_laptop_gpu(): settings.laptop = true

## Graphics chips made only for laptops (or named as laptop parts).
func is_laptop_gpu() -> bool:
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	for k in ["laptop", "mobile", "max-q", "rtx 2050", "rtx 3050 ti", " mx1", " mx2", " mx3", " mx4", " mx5"]:
		if gpu.contains(k): return true
	return false

## Laptop mode on, or the "سلس" preset: the 3D picture is drawn smaller.
func render_scale() -> float:
	var sc := clampf(float(settings.get("render_scale", 1.0)), 0.5, 1.0)
	if quality_level() == 0: sc = minf(sc, 0.8)
	if laptop(): sc = minf(sc, 0.77)
	return sc

func laptop() -> bool:
	return bool(settings.get("laptop", false))

## View distances (grass, detailed trees, far bots) shrink in laptop mode.
func view_k() -> float:
	return 0.7 if laptop() else 1.0

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_auto_quality()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	# Saves from before v0.7.1 defaulted to touch buttons; the game is now PC-first.
	if int(data.get("save_version", 1)) < 2 and data.has("settings") and typeof(data.settings) == TYPE_DICTIONARY:
		data.settings.controls = "kbm"
	for key in ["settings", "profile", "stats", "wallet"]:
		if data.has(key) and typeof(data[key]) == TYPE_DICTIONARY:
			var target: Dictionary = get(key)
			for k in data[key]:
				target[k] = data[key][k]
	# v3: Lola became the default character; switch older saves to her once.
	if int(data.get("save_version", 1)) < 3:
		profile.outfit = LOLA
		if not profile.owned.has(LOLA): profile.owned.append(LOLA)
	# JSON numbers come back as floats; career counters are whole numbers.
	for k in stats.keys():
		if typeof(stats[k]) == TYPE_FLOAT: stats[k] = int(stats[k])
	# v4: laptop mode arrived; laptop graphics chips start with it on.
	if int(data.get("save_version", 1)) < 4 and is_laptop_gpu():
		settings.laptop = true
	if typeof(settings.get("keys")) != TYPE_DICTIONARY: settings.keys = {}
	for k in settings.keys.keys():
		settings.keys[k] = int(settings.keys[k])
	apply_keys()

func save_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"save_version": 4, "settings": settings, "profile": profile, "stats": stats, "wallet": wallet}))

func outfit_color() -> Color:
	return WARDROBE[clampi(int(profile.outfit), 0, WARDROBE.size() - 1)][1]

## Which character model the outfit uses ("soldier" or "lola").
func outfit_character() -> String:
	return "lola" if outfit_style() == "lola" else "soldier"

func outfit_style() -> String:
	var w: Array = WARDROBE[clampi(int(profile.outfit), 0, WARDROBE.size() - 1)]
	return w[4] if w.size() > 4 else ""

func pants_color() -> Color:
	return WARDROBE[clampi(int(profile.outfit), 0, WARDROBE.size() - 1)][2]

func owns(i: int) -> bool:
	for o in profile.owned:
		if int(o) == i: return true
	return false

func pass_level() -> int:
	return mini(PASS_MAX, 1 + int(wallet.xp) / PASS_XP)

## Rewards after a match: gold and season XP.
func reward_match(rank: int, kills: int, won: bool) -> Dictionary:
	var gold := 20 + kills * 15 + maxi(0, 17 - rank) * 4 + (100 if won else 0)
	var xp := 60 + kills * 40 + (200 if won else 0)
	wallet.gold = int(wallet.gold) + gold
	wallet.xp = int(wallet.xp) + xp
	last_reward = {"gold": gold, "xp": xp, "rank": rank, "kills": kills, "won": won}
	save_data()
	return last_reward

## Ranks like the mobile game: six tiers with five steps each (V … I), then Ace and Conqueror.
## [name, colour, rank points where the tier starts]
const RANK_TIERS := [
	["برونز", Color("c4895a"), 1000], ["فضة", Color("c5ced8"), 1500], ["ذهب", Color("f2c14e"), 2000],
	["بلاتين", Color("54d1c4"), 2500], ["ماس", Color("8fb4ff"), 3000], ["التاج", Color("ff9f43"), 3500],
	["آس", Color("ff5d73"), 4000], ["الفاتح", Color("ffe36e"), 5000],
]
const ROMAN := ["I", "II", "III", "IV", "V"]
const TIER_STEP := 100

func rank_tier(rp: int) -> int:
	var t := 0
	for i in RANK_TIERS.size():
		if rp >= int(RANK_TIERS[i][2]): t = i
	return t

## Name, colour and progress of a rank: {"tier", "name", "color", "frac", "to_next"}.
func rank_info(rp: int) -> Dictionary:
	var t := rank_tier(rp)
	var start: int = RANK_TIERS[t][2]
	var name: String = RANK_TIERS[t][0]
	var frac := 1.0
	var to_next := 0
	if t < 6:
		var step := mini(4, (rp - start) / TIER_STEP)
		name += " " + ROMAN[4 - step]
		frac = float(rp - start - step * TIER_STEP) / TIER_STEP
		to_next = start + (step + 1) * TIER_STEP - rp
	elif t == 6:
		frac = float(rp - start) / float(int(RANK_TIERS[7][2]) - start)
		to_next = int(RANK_TIERS[7][2]) - rp
	return {"tier": t, "name": name, "color": RANK_TIERS[t][1], "frac": clampf(frac, 0.0, 1.0), "to_next": to_next}

## Rank points for a match: a good placement and kills raise them; higher tiers lose more for an early exit.
func rank_delta(rank: int, teams: int, kills: int, won: bool, rp: int) -> int:
	var f := float(rank - 1) / maxf(1.0, float(teams - 1))
	var place := lerpf(32.0, -14.0, sqrt(f))
	var d := place + mini(kills, 10) * 4.0 + (15.0 if won else 0.0) - rank_tier(rp) * 2.5
	return roundi(d)

## Stores a finished match in the career: rank points, totals per mode and the match history.
## m: {"rank", "teams", "kills", "won", "dmg", "heads", "longest", "time", "mode"}
func record_match(m: Dictionary) -> Dictionary:
	var rp0 := int(stats.rp)
	var delta := rank_delta(int(m.rank), int(m.teams), int(m.kills), bool(m.won), rp0)
	stats.rp = maxi(1000, rp0 + delta)
	delta = int(stats.rp) - rp0
	if int(m.rank) <= 10: stats.top10 = int(stats.top10) + 1
	stats.dmg = int(stats.dmg) + int(m.dmg)
	stats.heads = int(stats.heads) + int(m.heads)
	stats.longest = maxi(int(stats.longest), int(m.longest))
	stats.best_kills = maxi(int(stats.best_kills), int(m.kills))
	stats.time = int(stats.time) + int(m.time)
	if typeof(stats.modes) != TYPE_DICTIONARY: stats.modes = {}
	var md: Dictionary = stats.modes.get(m.mode, {"games": 0, "wins": 0, "kills": 0, "top10": 0, "dmg": 0})
	md.games = int(md.games) + 1
	md.wins = int(md.wins) + (1 if m.won else 0)
	md.kills = int(md.kills) + int(m.kills)
	md.top10 = int(md.top10) + (1 if int(m.rank) <= 10 else 0)
	md.dmg = int(md.dmg) + int(m.dmg)
	stats.modes[m.mode] = md
	var h := m.duplicate()
	h.rp = delta
	if typeof(stats.history) != TYPE_ARRAY: stats.history = []
	stats.history.push_front(h)
	stats.history.resize(mini(stats.history.size(), 10))
	save_data()
	return {"delta": delta, "before": rank_info(rp0), "after": rank_info(int(stats.rp))}

func player_name() -> String:
	return profile.name if String(profile.name) != "" else "لاعب"

func level() -> int:
	return 1 + int((stats.kills * 10 + stats.games * 25 + stats.wins * 100) / 200)

## Applies graphics quality to an Environment and the main sun light.
## Graphics presets named like PUBG Mobile, from fastest to prettiest.
const QUALITIES := ["low", "medium", "high", "hdr", "ultra"]
const QUALITY_NAMES := ["سلس", "متوازن", "HD", "HDR", "ألترا HD"]
const FPS_OPTIONS := [30, 60, 90, 120]

## 0 = سلس ... 4 = ألترا HD
func quality_level() -> int:
	return max(QUALITIES.find(settings.quality), 0)

## Frame-rate cap. V-sync is off so the cap (not the monitor) decides.
func apply_fps() -> void:
	if DisplayServer.get_name() == "headless":
		return    # tests run as fast as they can
	Engine.max_fps = int(settings.get("fps", 60))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func apply_quality(env: Environment, sun: DirectionalLight3D) -> void:
	var lv := quality_level()
	var lap := laptop()
	if env:
		env.ssao_enabled = lv >= 2 and not lap
		env.glow_enabled = lv >= 1
		env.volumetric_fog_enabled = lv >= 2 and not lap
		env.ssil_enabled = lv >= 3 and not lap
		# Reflections in windows and wet surfaces from HDR up; real bounced
		# light (rooms lit by daylight through windows) on Ultra only.
		env.ssr_enabled = lv >= 3 and not lap
		env.ssr_max_steps = 48
		env.sdfgi_enabled = lv >= 4 and not lap
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.4
		env.volumetric_fog_length = 160.0 if lv >= 4 else 120.0
	if sun:
		sun.shadow_enabled = lv >= 1
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if lv <= 1 or lap else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = [80.0, 120.0, 220.0, 320.0, 500.0][lv] * (0.6 if lap else 1.0)
		sun.shadow_blur = 1.0 if lv < 4 else 1.4
		sun.light_angular_distance = 0.5 if lv == 4 and not lap else 0.0
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_DISABLED, Viewport.MSAA_2X][lv]
	if lap: vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if lv <= 1 or lap else Viewport.SCREEN_SPACE_AA_DISABLED
	# Temporal AA from HDR up: smooths the shimmer of leaves, grass and wires.
	vp.use_taa = lv >= 3 and not lap
	# A smaller 3D picture sharpened back up with FSR (like the mobile game).
	var sc := render_scale()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if sc < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = sc
	vp.mesh_lod_threshold = [4.0, 2.0, 1.0, 1.0, 0.5][lv] * (2.0 if lap else 1.0)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][mini(lv, 2) if lap else lv])
	RenderingServer.directional_shadow_atlas_set_size(mini([2048, 2048, 4096, 4096, 8192][lv], 2048 if lap else 8192), true)
	apply_fps()
