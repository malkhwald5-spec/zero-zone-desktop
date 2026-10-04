extends Node
## Global state (autoload "Game"): settings, player profile, career stats and shared data.

const MAP_SIZE := 3072.0          # metres; shown on the map as an 8×8 grid
const GRID := 8
const SAVE_PATH := "user://zero_zone.json"

## Weapons. dmg per hit, rate = seconds between shots, range in metres.
const WEAPONS := {
	"p92":    {"name": "P92",    "cls": "pistol",  "ammo": "9mm", "dmg": 24, "rate": 0.17,  "mag": 15, "reload": 1.6, "spread": 1.6, "range": 120, "auto": false, "zoom": 1.0, "recoil": 1.2},
	"ump":    {"name": "UMP45",  "cls": "smg",     "ammo": "9mm", "dmg": 22, "rate": 0.092, "mag": 25, "reload": 2.0, "spread": 2.2, "range": 160, "auto": true,  "zoom": 1.2, "recoil": 0.7},
	"s1897":  {"name": "S1897",  "cls": "shotgun", "ammo": "12g", "dmg": 12, "rate": 0.85,  "mag": 5,  "reload": 2.6, "spread": 5.5, "range": 45,  "auto": false, "zoom": 1.0, "recoil": 4.0, "pellets": 9},
	"m416":   {"name": "M416",   "cls": "ar",      "ammo": "556", "dmg": 22, "rate": 0.086, "mag": 30, "reload": 2.1, "spread": 1.4, "range": 400, "auto": true,  "zoom": 1.5, "recoil": 0.9},
	"akm":    {"name": "AKM",    "cls": "ar",      "ammo": "762", "dmg": 27, "rate": 0.1,   "mag": 30, "reload": 2.3, "spread": 2.0, "range": 400, "auto": true,  "zoom": 1.5, "recoil": 1.4},
	"kar98":  {"name": "Kar98k", "cls": "sr",      "ammo": "762", "dmg": 85, "rate": 1.5,   "mag": 5,  "reload": 3.2, "spread": 0.1, "range": 800, "auto": false, "zoom": 4.0, "recoil": 5.0},
}
const AMMO_NAMES := {"9mm": "9 ملم", "556": "5.56 ملم", "762": "7.62 ملم", "12g": "خرطوش 12"}

const OUTFITS := [Color("2d6fb8"), Color("3f5f3a"), Color("7a2f2f"), Color("2b2b2e"), Color("c9b48a"), Color("5e4a6b")]

var settings := {
	"controls": "touch",      # "touch" (on-screen buttons) or "kbm" (keyboard + mouse)
	"quality": "high",        # "low" | "medium" | "high"
	"sensitivity": 1.0,
	"sound": true,
	"difficulty": "normal",
}
var profile := {"name": "", "outfit": 0}
var stats := {"wins": 0, "best": 0, "kills": 0, "games": 0}

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
	for key in ["settings", "profile", "stats"]:
		if data.has(key) and typeof(data[key]) == TYPE_DICTIONARY:
			var target: Dictionary = get(key)
			for k in data[key]:
				target[k] = data[key][k]

func save_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"settings": settings, "profile": profile, "stats": stats}))

func outfit_color() -> Color:
	return OUTFITS[clampi(int(profile.outfit), 0, OUTFITS.size() - 1)]

func player_name() -> String:
	return profile.name if String(profile.name) != "" else "لاعب"

func level() -> int:
	return 1 + int((stats.kills * 10 + stats.games * 25 + stats.wins * 100) / 200)

## Applies graphics quality to an Environment and the main sun light.
func apply_quality(env: Environment, sun: DirectionalLight3D) -> void:
	var q: String = settings.quality
	if env:
		env.ssao_enabled = q != "low"
		env.glow_enabled = q != "low"
		env.volumetric_fog_enabled = q == "high"
		env.sdfgi_enabled = false
	if sun:
		sun.shadow_enabled = q != "low"
		sun.directional_shadow_max_distance = 260.0 if q == "high" else 140.0
	get_viewport().msaa_3d = Viewport.MSAA_2X if q == "high" else Viewport.MSAA_DISABLED
