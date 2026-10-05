class_name Items
extends RefCounted
## Gear and healing items: armour vests, helmets, backpacks, meds and boosts.

## Damage reduction and durability per level (index 0 = none).
const VEST := [
	{"name": "", "reduce": 0.0, "dur": 0.0},
	{"name": "سترة مستوى 1", "reduce": 0.30, "dur": 100.0},
	{"name": "سترة مستوى 2", "reduce": 0.40, "dur": 150.0},
	{"name": "سترة مستوى 3", "reduce": 0.55, "dur": 200.0},
]
const HELMET := [
	{"name": "", "reduce": 0.0, "dur": 0.0},
	{"name": "خوذة مستوى 1", "reduce": 0.30, "dur": 80.0},
	{"name": "خوذة مستوى 2", "reduce": 0.40, "dur": 150.0},
	{"name": "خوذة مستوى 3", "reduce": 0.55, "dur": 230.0},
]
const PACK := [
	{"name": "", "cap": 60.0},
	{"name": "حقيبة مستوى 1", "cap": 110.0},
	{"name": "حقيبة مستوى 2", "cap": 160.0},
	{"name": "حقيبة مستوى 3", "cap": 210.0},
]

## Meds: heal up to `max` health (or add boost), take `time` seconds, use `size` bag space.
const HEALS := {
	"bandage":  {"name": "ضمادة",        "heal": 10.0, "max": 75.0,  "boost": 0.0,  "time": 4.0, "size": 2.0},
	"firstaid": {"name": "إسعاف أولي",   "heal": 75.0, "max": 75.0,  "boost": 0.0,  "time": 6.0, "size": 10.0},
	"medkit":   {"name": "حقيبة طبية",   "heal": 100.0, "max": 100.0, "boost": 0.0, "time": 8.0, "size": 20.0},
	"drink":    {"name": "مشروب طاقة",   "heal": 0.0,  "max": 100.0, "boost": 40.0, "time": 4.0, "size": 4.0},
	"pills":    {"name": "مسكّن",        "heal": 0.0,  "max": 100.0, "boost": 60.0, "time": 6.0, "size": 10.0},
}
const HEAL_ORDER := ["bandage", "firstaid", "medkit", "drink", "pills"]
const AMMO_SIZE := 0.5            # bag space per round

static func gear_name(kind: String, lvl: int) -> String:
	match kind:
		"vest": return VEST[lvl].name
		"helmet": return HELMET[lvl].name
		"pack": return PACK[lvl].name
	return ""

## Random gear level for loot: mostly level 1, rarely 3 (more in the military base).
static func roll_level(military: bool) -> int:
	var r := randf()
	if military:
		return 3 if r < 0.2 else (2 if r < 0.6 else 1)
	return 3 if r < 0.06 else (2 if r < 0.32 else 1)

static func roll_heal() -> String:
	var r := randf()
	if r < 0.4: return "bandage"
	if r < 0.62: return "firstaid"
	if r < 0.7: return "medkit"
	if r < 0.88: return "drink"
	return "pills"
