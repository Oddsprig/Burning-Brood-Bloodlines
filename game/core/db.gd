extends Node
## Autoload "DB": read-only game data loaded from res://data/*.json.
## Weapons and armor are stored per culture in the JSON; here they are also
## flattened into lookup tables keyed by template id (ids are unique across cultures).

var materials: Dictionary = {}
var bodies: Dictionary = {}
var races: Dictionary = {}
var factions: Dictionary = {}
var names: Dictionary = {}
var weapons: Dictionary = {}   # id -> template (with "id" and "culture" added)
var armor: Dictionary = {}     # id -> template (with "id" and "culture" added)
var weapons_by_culture: Dictionary = {}  # culture -> [ids]
var armor_by_culture: Dictionary = {}    # culture -> [ids]

const QUALITY_NAMES := ["", "well-crafted", "finely-crafted", "superior", "exceptional", "masterful", "legendary"]
const QUALITY_MARKS := [["", ""], ["-", "-"], ["+", "+"], ["*", "*"], ["≡", "≡"], ["☼", "☼"], ["", ""]]
## v0.014 (docs/specs/next/03-legendary-items.md): the legendary tier, one above masterful (5). Quality value 3.0 (DF
## artifact) against masterwork's 2.0, through the same physics (quality_mult). Only a real smith makes one.
const LEGEND := 6
const LEGEND_MULT := 3.0
## Item quality multiplier: +20% per level (handoff decision; single secondary source, uncertain).
const QUALITY_STEP := 0.2

const EQUIP_SLOTS := ["main_hand", "off_hand", "helm", "body", "legs", "hands", "feet", "clothing", "legs_under", "ranged"]   # bows: "ranged" = the bow (sidearm stays in main_hand)
const ATTRS := ["STR", "AGI", "TOU", "END", "REC", "WIL", "FOC", "SPA", "KIN"]
const ATTR_NAMES := {"STR": "strength", "AGI": "agility", "TOU": "toughness", "END": "endurance", "REC": "recuperation",
	"WIL": "willpower", "FOC": "focus", "SPA": "spatial sense", "KIN": "kinesthetic sense"}
const WEAPON_SKILLS := ["sword", "axe", "mace", "hammer", "spear", "polearm", "dagger"]
## bows: the ranged weapon skill (DF Bowman: AGI + spatial A, KIN B, WIL C). Kept apart from WEAPON_SKILLS so
## rolls that pick from that list (favourite weapon) stay as they were.
const RANGED_SKILLS := ["bow"]
## bows: max real arrows a quiver holds (spec).
const QUIVER_MAX := 50
## Attribute scale (provisional, Douglas: DF-inspired wide integer scale, human median ~1000).
const ATTR_MIN := 200   # Douglas scale 200-4000; tier breakpoints below 200 are lifted to 200
const ATTR_HARD_CAP := 4000  # Douglas scale (DF itself caps at 5000)
## Trainable ceiling from the rolled base (src: df_wiki "Attribute": max = start + max(start, race median)),
## never above the hard cap. A weak roll can improve but never reaches a naturally strong individual's peak.
## Talent (DF survey part 4, ours, ON): growth room x0.75 / x1.0 / x1.25 at 30/50/20%, shown as 1-3 stars.
## Set TALENT_ENABLED = false to restore strict DF ceilings.
const TALENT_ENABLED := true
const TALENT_LEVELS := [0.75, 1.0, 1.25]
const TALENT_ODDS := [0.3, 0.5, 0.2]
static func attr_ceiling(base: int, race_median: int = 1000, talent: float = 1.0) -> int:
	var t := talent if TALENT_ENABLED else 1.0
	return mini(ATTR_HARD_CAP, base + int(round(maxi(base, race_median) * t)))

## Personality (our own trait set, DF survey part 2; 0-100, triangular roll, range = median +-50 clipped).
## Morale uses courage/nerve/loyalty/cohesion/temper now; trait-driven targeting waits for Douglas.
## Medians: races[].personality, overridden per faction by factions[].personality (unlisted = 50).
const TRAITS := ["courage", "nerve", "aggression", "caution", "temper", "protectiveness", "loyalty", "cohesion",
	"glory", "cruelty", "greed", "appetite", "scruples"]
const BATTLE_TRAITS := ["courage", "nerve", "aggression", "caution", "temper", "protectiveness", "loyalty", "cohesion", "glory", "cruelty"]
const CAMP_TRAITS := ["greed", "appetite", "scruples"]
const TRAIT_NAMES := {"courage": "courage", "nerve": "nerve", "aggression": "aggression", "caution": "caution",
	"temper": "temper", "protectiveness": "protectiveness", "loyalty": "loyalty", "cohesion": "cohesion",
	"glory": "glory-seeking", "cruelty": "cruelty", "greed": "greed", "appetite": "appetite", "scruples": "scruples"}
const TRAIT_WORDS := {
	"courage": ["cowardly", "brave"], "nerve": ["jumpy", "steady-nerved"], "aggression": ["passive", "aggressive"],
	"caution": ["reckless", "cautious"], "temper": ["even-tempered", "hot-tempered"], "protectiveness": ["selfish", "protective"],
	"loyalty": ["fickle", "loyal"], "cohesion": ["a true loner", "a loner", "sticks with the squad", "lives for the squad"], "glory": ["modest", "glory-hungry"],
	"cruelty": ["merciful", "cruel"], "greed": ["generous", "greedy"], "appetite": ["abstemious", "temperate", "a big eater", "a glutton"],
	"scruples": ["unscrupulous", "principled"]}

## DF attribute tiers (src: df_wiki creature raws): seven breakpoints = six intervals; 4th = median.
const ATTR_TIERS := {
	"---": [200, 200, 200, 300, 400, 450, 500],
	"--": [200, 400, 600, 750, 800, 900, 1100],
	"-": [200, 600, 800, 900, 1000, 1100, 1500],
	"0": [200, 700, 900, 1000, 1100, 1300, 2000],
	"+": [450, 950, 1150, 1250, 1350, 1550, 2250],
	"++": [700, 1200, 1400, 1500, 1600, 1800, 2500]}
## Height and broadness roll (% of race size), same interval method (src: df_wiki).
const SIZE_RANGE := [75, 95, 98, 100, 102, 105, 125]

const COMBAT_SKILLS := ["fighter", "dodger", "shield_user", "armor_user", "discipline", "brawler", "wrestler", "observer"]
## Utility skills (DF survey part 3). v0.001 mechanics: leader, intimidator, appraiser, negotiator (+ observer above).
## The rest are stored now and used later. Map/economy skills use the company's best member.
const UTILITY_SKILLS := ["leader", "intimidator", "appraiser", "negotiator", "tactician", "judge_of_intent", "tracker",
	"teacher", "consoler", "pacifier", "entertainer", "organizer", "ambusher", "crutch_walker"]
const UTILITY_SKILLS_V1 := ["leader", "intimidator", "appraiser", "negotiator"]
const SKILL_NAMES := {"dagger": "knife", "polearm": "polearm", "shield_user": "shield user", "armor_user": "armor user",
	"judge_of_intent": "judge of intent", "crutch_walker": "crutch-walker"}

## Mind attributes (15 attributes in all with ATTRS; DF survey part 3). Rolled now at tier 0 unless the race
## sets "tiers" for them; most feed skills that arrive later.
const MIND_ATTRS := ["LIN", "SOC", "EMP", "INT", "PAT", "MEM"]
const MIND_NAMES := {"LIN": "linguistic ability", "SOC": "social awareness", "EMP": "empathy", "INT": "intuition",
	"PAT": "patience", "MEM": "memory"}
const VALUES := ["martial", "loyalty", "peace", "law"]
const VALUE_NAMES := {"martial": "martial prowess", "loyalty": "loyalty", "peace": "peace", "law": "law"}
const NEEDS := ["drink", "fight", "pray", "merry", "acquire", "rest"]
const NEED_NAMES := {"drink": "drink", "fight": "fight", "pray": "pray", "merry": "make merry", "acquire": "acquire wealth", "rest": "take it easy"}
const AMBITIONS := ["become a legendary warrior", "get rich", "see the world", "avenge their home", "earn a name", "buy land and settle", "command a company"]

func _init() -> void:
	load_all()

func load_all() -> void:
	materials = _strip(_load("res://data/materials.json"))
	bodies = _strip(_load("res://data/bodies.json"))
	var f := _load("res://data/factions.json")
	races = f.get("races", {})
	factions = f.get("factions", {})
	names = f.get("names", {})
	weapons.clear(); armor.clear(); weapons_by_culture.clear(); armor_by_culture.clear()
	var w := _strip(_load("res://data/weapons.json"))
	for culture in w:
		weapons_by_culture[culture] = []
		for id in w[culture]:
			var t: Dictionary = w[culture][id]
			t["id"] = id
			t["culture"] = culture
			weapons[id] = t
			weapons_by_culture[culture].append(id)
	var a := _strip(_load("res://data/armor.json"))
	for culture in a:
		armor_by_culture[culture] = []
		for id in a[culture]:
			var t: Dictionary = a[culture][id]
			t["id"] = id
			t["culture"] = culture
			armor[id] = t
			armor_by_culture[culture].append(id)
	_merge_creatures()
	_load_bows()

# ---- bows (additive): data/bows.json -> bows (Item templates, slot "ranged"), arrows, shapes, culture arrows
var bows: Dictionary = {}              # id -> bow template (with "id", "culture", "slot": "ranged", "skill": "bow")
var bows_by_culture: Dictionary = {}   # culture -> [ids]
var arrows: Dictionary = {}            # arrow id -> def (+ "mass" kg, "tip_mat" material dict)
var arrow_shapes: Dictionary = {}
var culture_arrows: Dictionary = {}

func _load_bows() -> void:
	bows.clear(); bows_by_culture.clear(); arrows.clear()
	var d := _load("res://data/bows.json")
	var bw: Dictionary = d.get("bows", {})
	for culture in bw:
		bows_by_culture[culture] = []
		for id in bw[culture]:
			var t: Dictionary = bw[culture][id]
			t["id"] = id
			t["culture"] = culture
			t["slot"] = "ranged"
			t["skill"] = "bow"
			t["materials"] = ["wood"]
			t["plain_name"] = true
			bows[id] = t
			bows_by_culture[culture].append(id)
	arrow_shapes = d.get("shapes", {})
	culture_arrows = d.get("culture_arrows", {})
	var ar: Dictionary = d.get("arrows", {})
	for id in ar:
		var a: Dictionary = ar[id]
		a["id"] = id
		var tm: Dictionary = materials.get(String(a.get("tip", "wood")), materials.get("wood", {}))
		a["mass"] = float(a.get("shaft_kg", 0.04)) + float(a.get("tip_cm3", 0.0)) * float(tm.get("density", 500)) / 1.0e6
		arrows[id] = a

func is_bow(id: String) -> bool:
	return bows.has(id)

## Arrow display name ("copper bodkin arrow").
func arrow_name(id: String) -> String:
	return String(arrows.get(id, {}).get("name", id.replace("_", " ")))

# ---- monsters wave 1 (additive): data/creatures.json -> materials, bodies, races (creature:true), factions, names
var creature_data: Dictionary = {}   # the raw creatures.json (rarity, lairs, spawning tunables ...)

func _merge_creatures() -> void:
	creature_data = _strip(_load("res://data/creatures.json"))
	for k in creature_data.get("materials", {}):
		materials[k] = creature_data["materials"][k]
	for k in creature_data.get("bodies", {}):
		bodies[k] = creature_data["bodies"][k]
	for cid in creature_data.get("creatures", {}):
		var c: Dictionary = creature_data["creatures"][cid]
		c["creature"] = true
		c["beast"] = true   # core/food.gd: beasts get belly only (hungry packs), no buzz
		if "NOFEAR" in c.get("tokens", []):
			c["nofear"] = true   # BattleSim._shock reads races[].nofear
		# per-creature body plan: the base plan with the creature's coat laid over every outer part that starts with
		# skin (not inside the body, not the mouth or tongue), less the parts it does not have (drop_parts: toes, eye teeth)
		var base: Dictionary = bodies.get(c.get("body", "quadruped"), {})
		var coat: Array = c.get("coat", [])
		var drop: Array = c.get("drop_parts", [])
		if not base.is_empty() and (not coat.is_empty() or not drop.is_empty()):
			var plan := {"parts": []}
			for p in base["parts"]:
				if String(p["id"]) in drop:
					continue
				var np: Dictionary = p.duplicate(true)
				if not coat.is_empty() and not np["layers"].is_empty() and np["layers"][0]["tissue"] == "skin" \
						and not np.get("internal", false) and not np.get("no_coat", false):
					np["layers"] = coat.duplicate(true) + np["layers"]
				plan["parts"].append(np)
			var pid := "%s_%s" % [c.get("body", "quadruped"), cid]
			bodies[pid] = plan
			c["body"] = pid
		races[cid] = c
	# a race's own relative sizes over its base plan (DF: the dwarf raw sets [RELSIZE:BY_CATEGORY:LIVER:300]):
	# races[].relsize {part id: relsize} -> plan "<base>_<race>"
	for rid in races:
		var r: Dictionary = races[rid]
		var rs: Dictionary = r.get("relsize", {})
		if rs.is_empty():
			continue
		var base_id := String(r.get("body", "humanoid"))
		var plan2 := {"parts": []}
		for p in bodies.get(base_id, {}).get("parts", []):
			var np: Dictionary = p.duplicate(true)
			if rs.has(np["id"]):
				np["relsize"] = rs[np["id"]]
			plan2["parts"].append(np)
		bodies["%s_%s" % [base_id, rid]] = plan2
		r["body"] = "%s_%s" % [base_id, rid]
	# per-plan layer-def cache key for BattleSim._ldef (part ids repeat across plans; humanoid keeps the bare id)
	for plan_id in bodies:
		if plan_id == "humanoid":
			continue
		for p in bodies[plan_id].get("parts", []):
			p["_ck"] = "%s:%s" % [plan_id, p["id"]]
	for fid in creature_data.get("factions", {}):
		factions[fid] = creature_data["factions"][fid]
	for k in creature_data.get("names", {}):
		names[k] = creature_data["names"][k]
	# Individual dragon bodies use native definitions before current saves load.
	# This does not activate creature spawning or alter existing humanoid data.
	DragonCombat.register_definitions(self)

func is_creature(race_id: String) -> bool:
	return bool(races.get(race_id, {}).get("creature", false))

func _load(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if parsed == null:
		push_error("DB: failed to parse " + path)
		return {}
	return parsed

func _strip(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		if not String(k).begins_with("_"):
			out[k] = d[k]
	return out

func template(id: String) -> Dictionary:
	if weapons.has(id):
		return weapons[id]
	if bows.has(id):   # bows
		return bows[id]
	return armor.get(id, {})

func is_weapon(id: String) -> bool:
	return weapons.has(id)

func quality_mult(q: int) -> float:
	if q >= LEGEND:
		return LEGEND_MULT
	return 1.0 + QUALITY_STEP * q

func body_plan(race_id: String) -> Dictionary:
	var r: Dictionary = races.get(race_id, races["human"])
	return bodies[r.get("body", "humanoid")]
