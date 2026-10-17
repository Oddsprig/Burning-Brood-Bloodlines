class_name UiWords
extends RefCounted
## Dwarf Fortress-style descriptive words for menus: attributes, skill levels, crafters, towns, slots.

## Full attribute name (from DB.ATTR_NAMES, capitalised).
static func attr_name(a: String) -> String:
	return String(DB.ATTR_NAMES.get(a, DB.MIND_NAMES.get(a, a))).capitalize()

## Per attribute: [strongest .. mildest positive], [mildest .. strongest negative] (4 DF bands each side).
const ATTR_WORDS := {
	"STR": [["unbelievably strong", "mighty", "very strong", "strong"], ["weak", "very weak", "unquestionably weak", "pitifully weak"]],
	"AGI": [["amazingly agile", "extremely agile", "very agile", "agile"], ["clumsy", "quite clumsy", "totally clumsy", "abysmally clumsy"]],
	"TOU": [["basically unbreakable", "incredibly tough", "quite durable", "tough"], ["flimsy", "very flimsy", "remarkably flimsy", "shockingly fragile"]],
	"END": [["absolutely inexhaustible", "indefatigable", "very slow to tire", "slow to tire"], ["quick to tire", "very quick to tire", "extremely quick to tire", "truly quick to tire"]],
	"REC": [["amazingly quick to heal", "incredibly quick to heal", "quite quick to heal", "quick to heal"], ["slow to heal", "very slow to heal", "really slow to heal", "shockingly slow to heal"]],
	"WIL": [["unbreakable of will", "iron-willed", "strong-willed", "firm of will"], ["weak-willed", "very weak-willed", "lacking all will", "utterly will-less"]],
	"FOC": [["unshakeably focused", "greatly focused", "very focused", "focused"], ["easily distracted", "quite distractible", "badly unfocused", "hopelessly unfocused"]],
	"SPA": [["of stunning spatial sense", "of great spatial sense", "of good spatial sense", "spatially aware"], ["poor at judging space", "very poor at judging space", "lost in space", "without spatial sense"]],
	"KIN": [["of astounding body sense", "of great body sense", "of very good body sense", "of good body sense"], ["awkward", "very awkward", "quite uncoordinated", "totally uncoordinated"]],
	"LIN": [["astonishingly eloquent", "great with words", "very good with words", "good with words"], ["poor with words", "very poor with words", "nearly tongue-tied", "tongue-tied"]],
	"SOC": [["uncannily socially aware", "greatly socially aware", "very socially aware", "socially aware"], ["socially awkward", "very socially awkward", "oblivious to others", "utterly oblivious"]],
	"EMP": [["of boundless empathy", "of great empathy", "very empathetic", "empathetic"], ["a little callous", "callous", "quite callous", "without empathy"]],
	"INT": [["of uncanny intuition", "of great intuition", "very intuitive", "intuitive"], ["poor of intuition", "very poor of intuition", "lacking intuition", "without intuition"]],
	"PAT": [["of endless patience", "of great patience", "very patient", "patient"], ["impatient", "very impatient", "quite impatient", "utterly impatient"]],
	"MEM": [["of astonishing memory", "of great memory", "of very good memory", "of good memory"], ["forgetful", "very forgetful", "quite forgetful", "hopelessly forgetful"]],
}

## Race median of an attribute (DF: 4th of the seven range breakpoints).
static func race_median(race: String, a: String) -> int:
	return int(Factory.att_range(race, a)[3])

## Band vs the race, -4..4, from the SAME 0-100 race score the sheet shows (Factory.attr_percentile), so the
## word, the colour and the number always agree (playtest: "21" in red labelled "typical" under the old
## +-250-point bands). 40-60 = typical.
static func attr_band(race: String, a: String, v: int) -> int:
	var p := Factory.attr_percentile(race, a, v) * 100.0
	if p >= 98.0: return 4
	if p >= 90.0: return 3
	if p >= 75.0: return 2
	if p >= 60.0: return 1
	if p < 2.0: return -4
	if p < 10.0: return -3
	if p < 25.0: return -2
	if p < 40.0: return -1
	return 0

## Attribute word relative to the race ("typical" inside +-250 of the race median).
static func attr_word(a: String, v: int, race: String = "human") -> String:
	var w: Array = ATTR_WORDS.get(a, [["exceptional", "superb", "great", "good"], ["poor", "very poor", "awful", "dreadful"]])
	var b := attr_band(race, a, v)
	if b > 0: return w[0][4 - b]
	if b < 0: return w[1][-b - 1]
	return "typical"

## "strong for an orc" / "typical for a goblin".
static func attr_phrase(a: String, v: int, race: String) -> String:
	var rn := String(DB.races.get(race, {}).get("name", race))
	var art := "an" if "aeiou".contains(rn.substr(0, 1)) else "a"
	return "%s for %s %s" % [attr_word(a, v, race), art, rn]

## -1 below typical, 0 typical, 1 above (for colouring).
static func attr_tone(race: String, a: String, v: int) -> int:
	return signi(attr_band(race, a, v))

## Height / build words from Unit.size_h / size_b (% of race size).
static func size_words(u: Unit) -> String:
	var h := u.size_h
	var b := u.size_b
	var hw := "very short" if h <= 84 else ("short" if h <= 94 else ("very tall" if h >= 116 else ("tall" if h >= 106 else "")))
	var bw := "slight" if b <= 84 else ("lean" if b <= 94 else ("massive" if b >= 116 else ("broad" if b >= 106 else "")))
	if hw == "" and bw == "":
		return "of ordinary height and build"
	if hw == "":
		return bw
	if bw == "":
		return hw
	return "%s and %s" % [hw, bw]

## Arm / leg length words, only when notable (Unit.arm_len / leg_len, % of normal, 90-110).
static func limb_words(u: Unit) -> String:
	var out := []
	if u.arm_len >= 106: out.append("long-armed")
	elif u.arm_len <= 94: out.append("short-armed")
	if u.leg_len >= 106: out.append("long-legged")
	elif u.leg_len <= 94: out.append("short-legged")
	return ", ".join(PackedStringArray(out))

const WEAPON_PLURALS := {"sword": "swords", "axe": "axes", "mace": "maces", "hammer": "hammers",
	"spear": "spears", "polearm": "polearms", "dagger": "knives"}

## Value 0-100 -> DF-style stance ("" for indifferent).
static func value_line(v: String, n: int) -> String:
	var name := String(DB.VALUE_NAMES.get(v, v))
	if n >= 85: return "holds %s above all" % name
	if n >= 65: return "values %s" % name
	if n <= 15: return "despises %s" % name
	if n <= 35: return "cares little for %s" % name
	return ""

## Stress (provisional 0-100 scale until the stress model lands).
static func stress_word(s: float) -> String:
	if s < 10: return "content"
	if s < 30: return "a little on edge"
	if s < 55: return "stressed"
	if s < 80: return "badly stressed"
	return "close to breaking"

static func hardness_word(h: int) -> String:
	if h >= 90: return "utterly hardened to killing"
	if h >= 60: return "hardened to battle"
	if h >= 30: return "growing used to bloodshed"
	if h > 0: return "has seen a little blood"
	return "green, never hardened by battle"

static func preference_line(u: Unit) -> String:
	var parts := []
	if u.pref_weapon != "":
		parts.append(WEAPON_PLURALS.get(u.pref_weapon, u.pref_weapon))
	if u.pref_material != "":
		parts.append(u.pref_material)
	var drink := "Favourite drink: %s" % u.fav_drink if u.fav_drink != "" else ""
	if parts.is_empty():
		return drink
	return "Likes " + " and ".join(PackedStringArray(parts)) + ((". " + drink) if drink != "" else "")

## Strongest needs (weight >= 60), strongest first.
static func needs_line(u: Unit) -> String:
	var ns: Array = u.needs.keys().filter(func(n): return int(u.needs[n]) >= 60)
	ns.sort_custom(func(a, b): return int(u.needs[a]) > int(u.needs[b]))
	if ns.is_empty():
		return "Wants for little"
	return "Needs to " + ", ".join(PackedStringArray(ns.map(func(n): return String(DB.NEED_NAMES.get(n, n)))))

const SKILL_LEVELS := ["Dabbling", "Novice", "Adequate", "Competent", "Skilled", "Proficient", "Talented",
	"Adept", "Expert", "Professional", "Accomplished", "Great", "Master", "High Master", "Grand Master", "Legendary"]

const SLOT_NAMES := {"main_hand": "Weapon", "off_hand": "Shield", "helm": "Helm", "body": "Body armour",
	"legs": "Leg armour", "hands": "Hands", "feet": "Feet", "clothing": "Clothing", "legs_under": "Trousers", "ranged": "Bow"}   # bows: ranged slot

const SIZE_WORDS := ["hamlet", "village", "town", "large town", "city"]
const WEALTH_WORDS := ["destitute", "poor", "modest", "comfortable", "prosperous", "rich"]

## Skill display name from DB.SKILL_NAMES ("dagger" -> "Knife"), else the id in words.
static func skill_name(s: String) -> String:
	var n := String(DB.SKILL_NAMES.get(s, s.replace("_", " ")))
	return n.substr(0, 1).to_upper() + n.substr(1)

static func skill_level(level: int) -> String:
	if level < SKILL_LEVELS.size():
		return SKILL_LEVELS[maxi(level, 0)]
	return "Legendary+%d" % (level - SKILL_LEVELS.size() + 1)

## XP needed to reach the next level. Uses sim/learning.gd if it exposes xp_to_next(level), else DF's 500+100*lvl.
static func xp_needed(level: int) -> float:
	var L = UiCompat.script("res://sim/learning.gd")
	if L != null and L.has_method("xp_to_next"):
		return float(L.xp_to_next(level))
	return 500.0 + 100.0 * level

## Crafter skill 0-15 -> a reputation word.
static func crafter_word(skill: int) -> String:
	if skill <= 1: return "hedge tinker"
	if skill <= 3: return "village smith"
	if skill <= 5: return "journeyman"
	if skill <= 8: return "skilled smith"
	if skill <= 11: return "master smith"
	if skill <= 14: return "grand master"
	return "legendary smith"

static func size_word(size: int) -> String:
	return SIZE_WORDS[clampi(size, 0, SIZE_WORDS.size() - 1)]

static func wealth_word(wealth: int) -> String:
	return WEALTH_WORDS[clampi(wealth, 0, WEALTH_WORDS.size() - 1)]

static func slot_name(slot: String) -> String:
	return SLOT_NAMES.get(slot, slot.capitalize())

static func role_word(u: Unit) -> String:
	match u.role:
		"captain": return "Captain"
		"officer": return "Officer"
	return "Troop"

static func race_name(u: Unit) -> String:
	return String(u.race_def().get("name", u.race))

static func faction_name(fid: String) -> String:
	return String(DB.factions.get(fid, {}).get("name", fid.capitalize()))

static func faction_color(fid: String) -> Color:
	var c = DB.factions.get(fid, {}).get("colors", {}).get("primary", "")
	return Color(c) if c != "" else Color("6b4f33")

static func kg(m: float) -> String:
	return "%.1f kg" % m

## Total body weight load words, a la DF (relative to body mass).
static func load_word(gear_kg: float, body_kg: float) -> String:
	var r := gear_kg / maxf(body_kg, 1.0)
	if r < 0.08: return "lightly burdened"
	if r < 0.18: return "comfortably burdened"
	if r < 0.3: return "heavily burdened"
	return "overburdened"
