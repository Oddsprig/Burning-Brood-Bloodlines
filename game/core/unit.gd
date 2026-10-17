class_name Unit
extends RefCounted
## A person: attributes (DF scale, 1000 = average human), skills (levels 0-20 with XP, DF-style),
## equipped items, and a persistent tissue-level body.

var uid: int = 0
var name: String = ""
var race: String = "human"
var faction: String = ""         # faction id ("player" for the company)
var role: String = "troop"       # "captain" | "officer" | "troop"
var title: String = ""           # troop template name, e.g. "spearman"
var squad: int = -1              # officer uid this troop serves under (-1 none)
var attrs: Dictionary = {}       # "STR" -> int
var attr_xp: Dictionary = {}     # "STR" -> float (training toward next point)
var attr_base: Dictionary = {}   # "STR" -> int rolled at birth (DF-style race range)
var attr_cap: Dictionary = {}    # "STR" -> int trainable ceiling derived from the base (DB.attr_ceiling)
var talent: Dictionary = {}      # "STR" -> 0/1/2 (1-3 stars; DB.TALENT_LEVELS multiplier on growth room)
var personality: Dictionary = {} # trait -> int 0..100 (DB.TRAITS); not used by the AI yet
var size_h: int = 100            # height % of race size (DF roll)
var size_b: int = 100            # broadness % of race size (DF roll)
var arm_len: int = 100           # arm length % (+-10%, ours): reach, first strike
var leg_len: int = 100           # leg length % (+-10%, ours): gait
var skills: Dictionary = {}      # "sword" -> int level 0..20
var skill_xp: Dictionary = {}    # "sword" -> float xp toward next level
var equip: Dictionary = {}       # slot -> Item (only filled slots present)
var quiver: Dictionary = {}      # bows: arrow id -> count (real arrows, at most DB.QUIVER_MAX in all)
var overrides: Dictionary = {}   # slot -> template id; individual override of the squad uniform
var body: BodyState
var dragon_uid: String = ""       # original individual registry ID; never a humanoid person
var native_dragon_profile: Dictionary = {} # detached boundary snapshot, never DB-wide mutable data
var dead: bool = false
var kills: int = 0
var battles: int = 0
var look: Dictionary = {}        # sprite look: {"skin": "#hex", "hair": "#hex", "beard": bool, "seed": int}
var wage: int = 0                # gold per day
var backstory: String = ""      # recruit background (ui/recruits), shown before hiring
var hire_cost: int = 0
var home_town: String = ""       # town id this person comes from (campaign: warband home, recruit town)
var sex: int = 0                 # 0 male, 1 female: the register person's sex (Persons.bind); combat-log pronouns
var family: int = -1             # economy: family record id in home_town (town.econ.fams[family]); -1 none
var born: float = -1.0e9          # campaign day of birth (economy: ages advance with the calendar; -1e9 = not set yet)
var last_pay: float = 0.0         # gold a day he was last paid (economy: shown in his family record)
var unpaid_days: int = 0         # days in a row the company could not pay him (desertion/morale: economy spec 2)
var rank: int = 0                # economy spec 2: index into his culture's rank list for his force's tier (campaign/army.gd)
var renown: float = 0.0          # lifetime kill renown (campaign/renown.gd)
var notable: Array = []          # notable kills [[name, worth, day]] (best first)
var mind: Dictionary = {}         # DB.MIND_ATTRS -> int (rolled; most uses come later)
var values: Dictionary = {}       # DB.VALUES -> int 0..100
var ambition: String = ""
var needs: Dictionary = {}        # DB.NEEDS -> int weight 0..100
var stress: float = 0.0           # rises with deaths seen, wounds, routs, unpaid wages; falls with wins, met needs, pay
var hardness: int = 0             # combat hardness 0..100 (DF)
var pref_weapon: String = ""      # favoured weapon skill
var pref_material: String = ""
var age: int = 25
var kill_list: Array = []         # names of those this unit killed (the newest KILL_LIST_MAX; kills is the count)
const KILL_LIST_MAX := 40
var skill_idle: Dictionary = {}   # skill -> campaign days unused (DF rust stages)
# food and drink (core/food.gd)
var belly: float = 60.0           # 0..100 (Food.START_BELLY): Stuffed / Fed / Hungry / Starving
var buzz: float = 0.0             # 0..100: Sober / Tipsy / Drunk / Hammered
var hungover: bool = false        # buzz was 30+ at the evening tick; clears at the next evening tick
var drink_days: int = 0           # days in a row without a mug or cup (the "drink" need unmet)
var drank_today: bool = false
var drank_eq: float = 0.0         # mug-equivalents drunk today (rations)
var fav_drink: String = ""        # "beer" | "wine" (rolled at recruitment)
var fav_today: bool = false       # got his favourite today
var fav_bonus: bool = false       # got his favourite yesterday (morale until the next evening)
var mass_mult: float = 1.0        # body mass vs rolled mass (starving loses, eating regains; floor 0.85)
var merry_day: float = -1.0       # campaign day the "make merry" need was last met (town feast)
# sickness (campaign/sickness.gd): his open case mirrored from his family's register record
var sick: String = ""             # disease id ("" = none)
var sick_shed: float = 0.0        # day he starts passing it on
var sick_on: float = 0.0          # onset (the sick phase starts)
var sick_to: float = 0.0          # day he recovers or dies
var sick_bed: bool = false        # bed-ridden while sick
## Battle-only attribute multipliers from food and drink (Food.apply_battle); not saved.
var food_attr_mult: Dictionary = {}
var _food_attrs: Dictionary = {}
const BELLY_KG_PER_POINT := 0.5 / 35.0   # Food spec: +0.5 kg per 35 belly

static var _next_uid: int = 1

## body false (Factory.make_troop, Recruits.make_recruit): the caller rolls his size next and builds the body at his
## own mass (Factory.roll_size), so the race-mass body is not built first only to be thrown away.
static func create(race_id: String, faction_id: String, body_now: bool = true) -> Unit:
	var u := Unit.new()
	u.uid = _next_uid
	_next_uid += 1
	u.race = race_id
	u.faction = faction_id
	u.body = BodyState.new()
	var r: Dictionary = DB.races.get(race_id, DB.races["human"])
	u.body.plan_id = r.get("body", "humanoid")
	if body_now:
		u.body.init_from_plan(DB.bodies[u.body.plan_id], r.get("mass", 70))
	for a in DB.ATTRS:
		u.attrs[a] = int(r["attrs"].get(a, 1000))
		u.attr_xp[a] = 0.0
		u.attr_base[a] = u.attrs[a]
		u.attr_cap[a] = DB.attr_ceiling(u.attrs[a], u.attrs[a])
	for s in DB.WEAPON_SKILLS + DB.COMBAT_SKILLS + DB.UTILITY_SKILLS + DB.RANGED_SKILLS:
		u.skills[s] = 0
		u.skill_xp[s] = 0.0
	return u

func race_def() -> Dictionary:
	return DB.races.get(race, DB.races["human"])

## Rolled body mass (race x height x broadness); the body plan is built from this.
func rolled_mass() -> float:
	if is_native_dragon(): return float(native_dragon_profile["body_mass_kg"])
	return float(race_def().get("mass", 70)) * size_h * size_b / 10000.0

## Current body mass for momentum, grab, stagger and encumbrance: rolled mass x mass_mult (hunger) + belly.
## Sprite scale does not use it.
func mass() -> float:
	if is_native_dragon(): return float(native_dragon_profile["body_mass_kg"])
	return rolled_mass() * mass_mult + belly * BELLY_KG_PER_POINT

func is_native_dragon() -> bool:
	return dragon_uid != "" and race == "dragon" and body != null and body.plan_id == "wyvern" \
		and bool(native_dragon_profile.get("active", false)) and float(native_dragon_profile.get("body_mass_kg", 0.0)) > 0.0

## Fractional authored strength plus real native training. The ordinary integer
## attribute API and all non-dragon calculations retain their original values.
func combat_strength() -> float:
	if not is_native_dragon(): return float(attr("STR"))
	var learned: float = float(attrs.get("STR", 1000)) - float(attr_base.get("STR", 1000))
	return (float(native_dragon_profile["strength"]) + learned) * float(food_attr_mult.get("STR", 1.0))

func skill(s: String) -> int:
	return int(skills.get(s, 0))

func attr(a: String) -> int:
	if food_attr_mult.is_empty():
		return int(attrs.get(a, 1000))
	return int(float(attrs.get(a, 1000)) * float(food_attr_mult.get(a, 1.0)))

## Attributes as the battle sim counts them (food/drink multipliers applied).
func eff_attrs() -> Dictionary:
	return attrs if food_attr_mult.is_empty() else _food_attrs

func set_food_attr_mult(m: Dictionary) -> void:
	food_attr_mult = m
	_food_attrs = {}
	if not m.is_empty():
		for a in attrs:
			_food_attrs[a] = int(float(attrs[a]) * float(m.get(a, 1.0)))

func weapon() -> Item:
	return equip.get("main_hand", null)

## bows: the bow in the ranged slot (null = no bow).
func bow() -> Item:
	return equip.get("ranged", null)

## bows: real arrows in the quiver.
func arrows() -> int:
	var n := 0
	for k in quiver:
		n += int(quiver[k])
	return n

func shield() -> Item:
	var it: Item = equip.get("off_hand", null)
	if it != null and not it.is_weapon():
		return it
	return null

## Skill used by the equipped weapon ("brawler" when unarmed).
func weapon_skill() -> String:
	var w := weapon()
	if w == null:
		return "brawler"
	return w.tmpl().get("skill", "fighter")

func gear_mass() -> float:
	var m := 0.0
	for s in equip:
		m += (equip[s] as Item).mass()
	return m

func gear_value() -> int:
	var v := 0
	for s in equip:
		v += (equip[s] as Item).value()
	return v

func is_officer() -> bool:
	return role == "officer" or role == "captain"  # "captain" only in pre-v0.003 saves (migrated on load)

func display_name() -> String:
	return name

func can_fight() -> bool:
	return not dead

## Sickness: in the sick phase of a disease on `day` (not while it is still incubating).
func sick_now(day: float) -> bool:
	return sick != "" and day >= sick_on and day < sick_to

## Sickness: bed-ridden on `day` (off duty: no wage at home, no strength in a force).
func bedridden(day: float) -> bool:
	return sick_bed and sick_now(day)

func to_dict() -> Dictionary:
	var eq := {}
	for s in equip:
		eq[s] = (equip[s] as Item).to_dict()
	var out: Dictionary = {"uid": uid, "name": name, "race": race, "faction": faction, "role": role, "title": title,
		"squad": squad, "attrs": attrs.duplicate(), "attr_xp": attr_xp.duplicate(), "attr_base": attr_base.duplicate(), "attr_cap": attr_cap.duplicate(), "talent": talent.duplicate(), "personality": personality.duplicate(), "size_h": size_h, "size_b": size_b, "arm_len": arm_len, "leg_len": leg_len, "skills": skills.duplicate(),
		"skill_xp": skill_xp.duplicate(), "equip": eq, "overrides": overrides.duplicate(),
		"body": body.to_dict(), "dead": dead, "kills": kills, "battles": battles, "look": look.duplicate(), "wage": wage, "backstory": backstory, "hire_cost": hire_cost, "home_town": home_town, "sex": sex, "family": family, "unpaid_days": unpaid_days, "last_pay": last_pay, "born": born, "rank": rank, "renown": renown, "notable": notable.duplicate(true),
		"mind": mind.duplicate(), "values": values.duplicate(), "ambition": ambition, "needs": needs.duplicate(),
		"stress": stress, "hardness": hardness, "pref_weapon": pref_weapon, "pref_material": pref_material, "age": age,
		"kill_list": kill_list.duplicate(), "skill_idle": skill_idle.duplicate(),
		"belly": belly, "buzz": buzz, "hungover": hungover, "drink_days": drink_days, "drank_today": drank_today,
		"drank_eq": drank_eq, "fav_drink": fav_drink, "fav_today": fav_today, "fav_bonus": fav_bonus,
		"mass_mult": mass_mult, "merry_day": merry_day, "quiver": quiver.duplicate(),
		"sick": sick, "sick_shed": sick_shed, "sick_on": sick_on, "sick_to": sick_to, "sick_bed": sick_bed}
	if dragon_uid != "":
		out["dragon_uid"] = dragon_uid
		out["native_dragon_profile"] = native_dragon_profile.duplicate(true)
	return out

static func from_dict(d: Dictionary) -> Unit:
	var u := Unit.new()
	u.uid = int(d["uid"])
	_next_uid = maxi(_next_uid, u.uid + 1)
	u.name = d.get("name", "")
	u.race = d.get("race", "human")
	u.dragon_uid = str(d.get("dragon_uid", ""))
	u.native_dragon_profile = (d.get("native_dragon_profile", {}) as Dictionary).duplicate(true)
	u.faction = d.get("faction", "")
	u.role = d.get("role", "troop")
	u.title = d.get("title", "")
	u.squad = int(d.get("squad", -1))
	u.attrs = d.get("attrs", {})
	u.attr_xp = d.get("attr_xp", {})
	u.attr_base = d.get("attr_base", u.attrs.duplicate())
	u.attr_cap = d.get("attr_cap", {})
	u.talent = d.get("talent", {})
	u.personality = d.get("personality", {})
	u.size_h = int(d.get("size_h", 100))
	u.size_b = int(d.get("size_b", 100))
	u.arm_len = int(d.get("arm_len", 100))
	u.leg_len = int(d.get("leg_len", 100))
	for a in u.attr_base:
		if not u.attr_cap.has(a):
			u.attr_cap[a] = DB.attr_ceiling(int(u.attr_base[a]), int(Factory.att_range(u.race, a)[3]), DB.TALENT_LEVELS[int(u.talent.get(a, 1))])
	u.skills = d.get("skills", {})
	u.skill_xp = d.get("skill_xp", {})
	for s in d.get("equip", {}):
		u.equip[s] = Item.from_dict(d["equip"][s])
	u.overrides = d.get("overrides", {})
	u.body = BodyState.from_dict(d.get("body", {}))
	var rbody := String(u.race_def().get("body", "humanoid"))
	if u.body.plan_id == "humanoid" and rbody.begins_with("humanoid_"):
		u.body.plan_id = rbody   # v0.013: a race with its own relative sizes (dwarf liver) has its own plan (same part ids)
	u.dead = d.get("dead", false)
	u.kills = int(d.get("kills", 0))
	u.battles = int(d.get("battles", 0))
	u.look = d.get("look", {})
	u.wage = int(d.get("wage", 0))
	u.backstory = d.get("backstory", "")
	u.hire_cost = int(d.get("hire_cost", 0))
	u.home_town = str(d.get("home_town", ""))
	u.sex = int(d.get("sex", 0))
	u.family = int(d.get("family", -1))
	u.unpaid_days = int(d.get("unpaid_days", 0))
	u.last_pay = float(d.get("last_pay", 0.0))
	u.born = float(d.get("born", -1.0e9))
	u.rank = int(d.get("rank", 0)); u.renown = float(d.get("renown", 0.0)); u.notable = d.get("notable", [])
	u.mind = d.get("mind", {}); u.values = d.get("values", {}); u.ambition = d.get("ambition", "")
	u.needs = d.get("needs", {}); u.stress = float(d.get("stress", 0.0)); u.hardness = int(d.get("hardness", 0))
	u.pref_weapon = d.get("pref_weapon", ""); u.pref_material = d.get("pref_material", ""); u.age = int(d.get("age", 25))
	u.kill_list = d.get("kill_list", []); u.skill_idle = d.get("skill_idle", {})
	u.belly = float(d.get("belly", 60.0)); u.buzz = float(d.get("buzz", 0.0)); u.hungover = bool(d.get("hungover", false))
	u.drink_days = int(d.get("drink_days", 0)); u.drank_today = bool(d.get("drank_today", false))
	u.drank_eq = float(d.get("drank_eq", 0.0))
	u.fav_today = bool(d.get("fav_today", false)); u.fav_bonus = bool(d.get("fav_bonus", false))
	u.mass_mult = float(d.get("mass_mult", 1.0)); u.merry_day = float(d.get("merry_day", -1.0))
	u.fav_drink = str(d.get("fav_drink", ""))
	u.sick = str(d.get("sick", "")); u.sick_shed = float(d.get("sick_shed", 0.0)); u.sick_on = float(d.get("sick_on", 0.0))
	u.sick_to = float(d.get("sick_to", 0.0)); u.sick_bed = bool(d.get("sick_bed", false))
	var qv: Dictionary = d.get("quiver", {})   # bows
	for k in qv:
		u.quiver[str(k)] = int(qv[k])
	if u.fav_drink == "":
		Food.roll_fav_drink(u, hash([u.uid, u.name]))   # saves from before food and drink: seeded roll
	return u
