class_name Items
extends RefCounted
## Gear and healing items: armour vests, helmets, backpacks, meds and boosts,
## and weapon attachments (sights, muzzles, magazines, grips).

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
const THROW_SIZE := 12.0          # bag space per grenade
const THROWS := {"frag": "قنبلة متفجرة", "smoke": "قنبلة دخانية", "molotov": "مولوتوف", "flash": "قنبلة ضوئية"}
const THROW_ORDER := ["frag", "smoke", "molotov", "flash"]

## Grenade found lying around.
static func roll_throw() -> String:
	var r := randf()
	return "frag" if r < 0.48 else ("smoke" if r < 0.68 else ("molotov" if r < 0.86 else "flash"))

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

# ---------- Weapon attachments ----------
## slot: one attachment per slot on a gun. for: weapon classes it fits.
## zoom (sights), recoil / spread / reload multipliers, mag multiplier,
## suppressed (quiet, no flash, heard only nearby).
const ATTACH := {
	"reddot":      {"name": "ريد دوت",          "slot": "sight",  "zoom": 1.35, "for": ["pistol", "smg", "shotgun", "ar", "lmg", "dmr", "crossbow"]},
	"holo":        {"name": "هولوغرافيك",       "slot": "sight",  "zoom": 1.35, "for": ["pistol", "smg", "shotgun", "ar", "lmg", "dmr", "crossbow"]},
	"x2":          {"name": "سكوب 2",          "slot": "sight",  "zoom": 2.0,  "for": ["smg", "ar", "lmg", "dmr", "crossbow"]},
	"x4":          {"name": "سكوب 4",          "slot": "sight",  "zoom": 4.0,  "for": ["ar", "lmg", "sr", "dmr", "crossbow"]},
	"x8":          {"name": "سكوب 8",          "slot": "sight",  "zoom": 8.0,  "for": ["ar", "sr", "dmr"]},
	"suppressor":  {"name": "كاتم صوت",         "slot": "muzzle", "suppressed": true, "for": ["pistol", "smg", "ar", "sr", "dmr"]},
	"compensator": {"name": "معوّض ارتداد",      "slot": "muzzle", "recoil": 0.75, "for": ["smg", "ar", "sr", "lmg", "dmr"]},
	"ext_mag":     {"name": "مخزن موسّع",        "slot": "mag",    "mag": 1.35, "for": ["pistol", "smg", "ar", "sr", "dmr"]},
	"quick_mag":   {"name": "مخزن سريع",        "slot": "mag",    "reload": 0.7, "for": ["pistol", "smg", "ar", "sr", "lmg", "dmr"]},
	"ext_quick":   {"name": "مخزن موسّع وسريع", "slot": "mag",    "mag": 1.35, "reload": 0.75, "for": ["pistol", "smg", "ar", "sr", "dmr"]},
	"vgrip":       {"name": "مقبض عمودي",       "slot": "grip",   "recoil": 0.8, "for": ["smg", "ar", "lmg"]},
	"angled":      {"name": "مقبض مائل",        "slot": "grip",   "recoil": 0.9, "spread": 0.85, "for": ["smg", "ar", "lmg"]},
}
const ATTACH_SLOTS := ["sight", "muzzle", "mag", "grip"]
const ATTACH_SLOT_NAMES := {"sight": "منظار", "muzzle": "فوهة", "mag": "مخزن", "grip": "مقبض"}
## Loot weights: [town, military]
const ATTACH_LOOT := {"reddot": [6, 4], "holo": [5, 4], "x2": [4, 4], "x4": [2.2, 4], "x8": [0.7, 2],
	"suppressor": [1.6, 3], "compensator": [3, 3], "ext_mag": [4, 3], "quick_mag": [4, 3], "ext_quick": [1.2, 2.5],
	"vgrip": [3, 3], "angled": [3, 3]}

static func roll_attach(military: bool) -> String:
	var total := 0.0
	for k in ATTACH_LOOT: total += ATTACH_LOOT[k][1 if military else 0]
	var r := randf() * total
	for k in ATTACH_LOOT:
		r -= ATTACH_LOOT[k][1 if military else 0]
		if r <= 0.0: return k
	return "reddot"

static func attach_fits(id: String, cls: String) -> bool:
	return ATTACH.has(id) and ATTACH[id]["for"].has(cls)

## A weapon's stats with its attachments applied (att: slot -> attachment id).
static func apply_attachments(w: Dictionary, att: Dictionary) -> Dictionary:
	var r := w.duplicate()
	for slot in att:
		var a: Dictionary = ATTACH.get(att[slot], {})
		if a.has("zoom"): r.zoom = maxf(float(a.zoom), float(w.zoom)) if w.cls in ["sr", "dmr"] else float(a.zoom)
		if a.has("recoil"): r.recoil = float(r.recoil) * float(a.recoil)
		if a.has("spread"): r.spread = float(r.spread) * float(a.spread)
		if a.has("reload"): r.reload = float(r.reload) * float(a.reload)
		if a.has("mag"): r.mag = int(round(float(w.mag) * float(a.mag)))
		if a.get("suppressed", false): r.suppressed = true
	r.sight = att.get("sight", "")
	return r

