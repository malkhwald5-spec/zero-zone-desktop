extends Node
## Global state (autoload "Game"): settings, player profile, career stats and shared data.

const MAP_SIZE := 4096.0          # metres; shown on the map as an 8×8 grid (512 m squares)
const GRID := 8
const SAVE_PATH := "user://zero_zone.json"
const VERSION := "v0.9.0"
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
	"kar98":  {"name": "Kar98k", "cls": "sr",      "ammo": "762", "dmg": 85, "rate": 1.5,   "mag": 5,  "reload": 3.2, "spread": 0.1, "range": 800, "auto": false, "zoom": 4.0, "recoil": 5.0},
	# Airdrop-only weapons
	"awm":    {"name": "AWM",    "cls": "sr",      "ammo": "300", "dmg": 120, "rate": 1.8,  "mag": 5,  "reload": 3.6, "spread": 0.05, "range": 1000, "auto": false, "zoom": 6.0, "recoil": 6.0, "crate": true},
	"m249":   {"name": "M249",   "cls": "lmg",     "ammo": "556", "dmg": 22, "rate": 0.075, "mag": 100, "reload": 5.5, "spread": 2.2, "range": 450, "auto": true,  "zoom": 1.5, "recoil": 0.8, "crate": true},
	"groza":  {"name": "Groza",  "cls": "ar",      "ammo": "762", "dmg": 28, "rate": 0.08,  "mag": 30, "reload": 2.4, "spread": 1.5, "range": 420, "auto": true,  "zoom": 1.5, "recoil": 1.1, "crate": true},
}
const AMMO_NAMES := {"9mm": "9 ملم", "556": "5.56 ملم", "762": "7.62 ملم", "12g": "خرطوش 12", "300": ".300 ماغنوم"}

## Wardrobe items: [name, shirt colour, pants colour, price in gold (0 = owned from start)].
const WARDROBE := [
	["أزرق المدينة", Color("2d6fb8"), Color("3a4250"), 0],
	["زيتي الصحراء", Color("3f5f3a"), Color("6b5f45"), 0],
	["خطوط البحر", Color("2f8f86"), Color("b7ad95"), 0],
	["أحمر النار", Color("a8302c"), Color("2b2b2e"), 250],
	["الظل الأسود", Color("1f2023"), Color("1a1a1c"), 400],
	["رمال ذهبية", Color("c9b48a"), Color("7a6a4c"), 300],
	["ليلة القمر", Color("5e3a7a"), Color("2b2433"), 600],
	["الثلج", Color("e6e8ea"), Color("9aa3ab"), 500],
]

var settings := {
	"controls": "kbm",        # "kbm" (keyboard + mouse, PC default) or "touch" (on-screen buttons)
	"quality": "high",        # "low" | "medium" | "high" | "ultra"
	"sensitivity": 1.0,
	"sound": true,
	"difficulty": "normal",
}
var profile := {"name": "", "outfit": 0, "clan": "", "owned": [0, 1, 2]}
var stats := {"wins": 0, "best": 0, "kills": 0, "games": 0}
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

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
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

func save_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"save_version": 2, "settings": settings, "profile": profile, "stats": stats, "wallet": wallet}))

func outfit_color() -> Color:
	return WARDROBE[clampi(int(profile.outfit), 0, WARDROBE.size() - 1)][1]

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

func player_name() -> String:
	return profile.name if String(profile.name) != "" else "لاعب"

func level() -> int:
	return 1 + int((stats.kills * 10 + stats.games * 25 + stats.wins * 100) / 200)

## Applies graphics quality to an Environment and the main sun light.
func apply_quality(env: Environment, sun: DirectionalLight3D) -> void:
	var q: String = settings.quality
	var hi := q == "high" or q == "ultra"
	if env:
		env.ssao_enabled = q != "low"
		env.glow_enabled = q != "low"
		env.volumetric_fog_enabled = hi
		env.ssil_enabled = q == "ultra"
		env.sdfgi_enabled = false
	if sun:
		sun.shadow_enabled = q != "low"
		sun.directional_shadow_max_distance = {"ultra": 400.0, "high": 260.0}.get(q, 140.0)
		sun.light_angular_distance = 0.5 if q == "ultra" else 0.0
	var vp := get_viewport()
	vp.msaa_3d = {"ultra": Viewport.MSAA_4X, "high": Viewport.MSAA_2X}.get(q, Viewport.MSAA_DISABLED)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == "medium" else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if hi else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.directional_shadow_atlas_set_size(8192 if q == "ultra" else 4096, true)
