class_name Factory
extends RefCounted
## Builds units, gear and warbands from faction data. Every call takes an explicit RNG so
## generation is reproducible from a seed.

## Crafter skill (0-15, DF-style) -> rolled quality level 0-5 (6 = legendary, only when can_legend).
## v0.014 refit (Douglas, docs/specs/next/03-legendary-items.md): P(masterwork) = 1.4% at skill 10 and 25% at skill 15,
## the same ratio per skill point between and below (R = (0.25 / 0.014)^(1/5) ~ x1.78: 11 2.5%, 12 4.4%, 13 7.9%,
## 14 14%; 9 0.8%, 8 0.4% ...). A constant ratio per point is an exponential tail, so the roll is a Laplace (double
## exponential) draw instead of the old normal one: quality = round(mu + L), L with scale B = (1/3) / ln R (~0.58; its
## spread, sd 0.82, is about the old 0.8), mu = skill / 3 less a shift set by the skill-15 anchor (~skill/3 - 0.90,
## was - 0.6). The lower qualities follow from the same curve (each level ~3 skill points below the next); above
## skill ~16 the tail fills and the chance flattens toward 100% smoothly. One randf a roll (deterministic per RNG).
## Legendary: a masterwork roll by a named smith (can_legend) is legendary 1 time in LEGEND_OF_MW (25), so
## P(legendary) = P(masterwork) / 25 at every skill (1% at 15). The caller (Legends.forge) checks the maker.
const MW_AT_10 := 0.014
const MW_AT_15 := 0.25
const LEGEND_OF_MW := 25.0
static var _qb := -1.0
static func _q_scale() -> float:
	if _qb < 0.0:
		_qb = (1.0 / 3.0) / log(pow(MW_AT_15 / MW_AT_10, 0.2))
	return _qb

## The centre (median) of the quality roll at this skill.
static func quality_center(crafter_skill: float) -> float:
	return 4.5 - _q_scale() * log(0.5 / MW_AT_15) + (crafter_skill - 15.0) / 3.0

## P(quality >= masterwork) at this skill (the curve the roll draws from).
static func masterwork_chance(crafter_skill: float) -> float:
	var d := 4.5 - quality_center(crafter_skill)
	if d >= 0.0:
		return 0.5 * exp(-d / _q_scale())
	return 1.0 - 0.5 * exp(d / _q_scale())

## P(legendary) for a named smith at this skill.
static func legend_chance(crafter_skill: float) -> float:
	return masterwork_chance(crafter_skill) / LEGEND_OF_MW

static func roll_quality(rng: RandomNumberGenerator, crafter_skill: float, can_legend: bool = false) -> int:
	var b := _q_scale()
	var u := rng.randf()
	var x := quality_center(crafter_skill)
	if u < 0.5:
		x += b * log(maxf(2.0 * u, 1.0e-12))
	else:
		x -= b * log(maxf(2.0 * (1.0 - u), 1.0e-12))
	var q := clampi(int(round(x)), 0, 5)
	if q == 5 and can_legend and rng.randf() < 1.0 / LEGEND_OF_MW:
		return DB.LEGEND
	return q

## Poorer factions field more tin (tuned).
static func roll_material(rng: RandomNumberGenerator, mats: Array, wealth: int) -> String:
	if mats.has("copper") and mats.has("tin"):
		var tin_chance: float = [0.0, 0.7, 0.5, 0.3, 0.15, 0.05][clampi(wealth, 0, 5)]
		return "tin" if rng.randf() < tin_chance else "copper"
	return mats[0]

## v0.014: the metal of a piece made or bought in this town: drawn from what the town's own smiths have actually
## turned out (the metal pieces on its stalls and in its armory, same kind first: weapons for a weapon, armour
## for armour). Their bars, skills and prices already decided that mix (campaign/businesses.gd _pick_metal), so
## a kit from here carries the town's real copper / tin / iron share instead of a fixed roll. A town with no
## metal gear on hand falls back to its metal bars in stock, then to the wealth roll. Cloth, leather and bows
## keep their own material.
static func town_metal(rng: RandomNumberGenerator, town: Dictionary, tid: String) -> String:
	if DB.is_bow(tid):
		return "wood"
	var mats: Array = [] if DB.is_weapon(tid) else DB.template(tid).get("materials", [])
	if not mats.is_empty() and not mats.has("copper"):
		return String(mats[0])   # linen and leather pieces
	var weapon := DB.is_weapon(tid)
	var same := {}
	var any := {}
	for src in [town.get("shop", []), town.get("armory_items", [])]:
		for it in src:
			if not (it is Item) or String(it.mat().get("kind", "")) != "metal":
				continue
			any[it.material] = int(any.get(it.material, 0)) + 1
			if it.is_weapon() == weapon:
				same[it.material] = int(same.get(it.material, 0)) + 1
	var pool: Dictionary = same if not same.is_empty() else any
	if pool.is_empty() and town.has("econ"):
		var st: Dictionary = town["econ"].get("stock", {})
		for m in ["copper", "tin", "bronze", "iron", "steel"]:
			var n := int(st.get(m + "_bars", 0))
			if n > 0:
				pool[m] = n
	if pool.is_empty():
		return roll_material(rng, ["copper", "tin"], int(town.get("wealth", 2)))
	var keys: Array = pool.keys()
	keys.sort()
	var tot := 0
	for k in keys:
		tot += int(pool[k])
	var r := rng.randi_range(1, tot)
	for k in keys:
		r -= int(pool[k])
		if r <= 0:
			return String(k)
	return String(keys[-1])

static func make_item(rng: RandomNumberGenerator, tid: String, wealth: int) -> Item:
	var t := DB.template(tid)
	var mats: Array = t.get("materials", ["copper", "tin"]) if not DB.is_weapon(tid) else ["copper", "tin"]
	var crafter := 1.0 + wealth * 2.2
	var it := Item.make(tid, roll_material(rng, mats, wealth), roll_quality(rng, crafter))
	if DB.is_bow(tid):   # bows: +-5% item variance rolled once at making (draws only for bows)
		it.vr = roll_bow_variance(rng, crafter)
	return it

## bows: +-5% item variance of a bow, rolled once at making; a better bowyer centres it higher (spec 1) [ours].
static func roll_bow_variance(rng: RandomNumberGenerator, bowyer_skill: float) -> float:
	return snappedf(1.0 + clampf(rng.randfn(0.004 * (bowyer_skill - 5.0), 0.025), -0.05, 0.05), 0.001)

static func random_name(rng: RandomNumberGenerator, race_id: String) -> String:
	var n: Dictionary = DB.names.get(race_id, DB.names["human"])
	var first: Array = n["first"]
	var last: Array = n["last"]
	return "%s %s" % [first[rng.randi() % first.size()], last[rng.randi() % last.size()]]

## DF-style per-race attribute rolls. Each race names a DF tier per attribute (races[].tiers -> DB.ATTR_TIERS:
## seven breakpoints, the 4th is the median; src: df_wiki creature raws). Explicit "att_ranges" override.
## Roll: one of the six intervals at equal odds, then uniform inside it (src: df_wiki).
static func att_range(race_id: String, a: String) -> Array:
	var r: Dictionary = DB.races.get(race_id, DB.races["human"])
	var explicit: Dictionary = r.get("att_ranges", {})
	if explicit.has(a):
		return explicit[a]
	var tiers: Dictionary = r.get("tiers", {})
	return DB.ATTR_TIERS.get(tiers.get(a, "0"), DB.ATTR_TIERS["0"])

static func roll_interval(rng: RandomNumberGenerator, br: Array) -> int:
	var i := rng.randi_range(0, 5)
	return rng.randi_range(int(br[i]), int(br[i + 1]))

static func roll_attr(rng: RandomNumberGenerator, race_id: String, a: String) -> int:
	return clampi(roll_interval(rng, att_range(race_id, a)), DB.ATTR_MIN, DB.ATTR_HARD_CAP)

## Rolls base attributes and sets each trainable ceiling (Unit.attr_cap) from the rolled base.
static func roll_attrs(rng: RandomNumberGenerator, u: Unit) -> void:
	for a in DB.ATTRS:
		u.attrs[a] = roll_attr(rng, u.race, a)
		u.attr_base[a] = u.attrs[a]
		var roll := rng.randf()
		u.talent[a] = 0 if roll < DB.TALENT_ODDS[0] else (1 if roll < DB.TALENT_ODDS[0] + DB.TALENT_ODDS[1] else 2)
		u.attr_cap[a] = DB.attr_ceiling(u.attrs[a], int(att_range(u.race, a)[3]), DB.TALENT_LEVELS[u.talent[a]])

## Where a value lands within its race's range, 0..1 (0.5 = race median). For recruit/unit screens.
static func attr_percentile(race_id: String, a: String, value: int) -> float:
	var br := att_range(race_id, a)
	if value <= br[0]:
		return 0.0
	for i in 6:
		if value <= br[i + 1]:
			return (i + float(value - br[i]) / maxf(1.0, br[i + 1] - br[i])) / 6.0
	return 1.0

static func roll_look(rng: RandomNumberGenerator, u: Unit) -> void:
	var r := u.race_def()
	var skins: Array = r.get("skin", ["#e8c4a0"])
	var hairs: Array = r.get("hair", ["#3a2a1a"])
	var skin := Color(skins[rng.randi() % skins.size()])
	# Per-individual shade variation within the faction's colour family.
	skin = skin.lightened(rng.randf_range(-0.08, 0.1)) if rng.randf() < 0.5 else skin.darkened(rng.randf_range(0.0, 0.12))
	u.look = {"skin": skin.to_html(false), "hair": hairs[rng.randi() % hairs.size()],
		"beard": (u.race in ["human", "orc"] and rng.randf() < 0.55) or bool(u.race_def().get("beard", false)), "seed": rng.randi()}

## A bound recruit keeps the household race. Retarget only when it differs, on a
## private RNG. Trolls and giants lose any mount and fight with a heavy weapon.
static func adopt_family_race(u: Unit, race: String) -> void:
	if u == null or race == "":
		return
	var foot := Horses.fights_on_foot_only(race)
	if u.race == race:
		if foot:
			u.horse = null
			u.horse_care = {}
		return
	var prev_wage := u.wage
	var prev_hire := u.hire_cost
	u.race = race
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([u.uid, race, "family-body"])
	var rd: Dictionary = DB.races.get(race, DB.races["human"])
	if u.body == null:
		u.body = BodyState.new()
	u.body.plan_id = rd.get("body", "humanoid")
	roll_attrs(rng, u)
	roll_size(rng, u)
	roll_look(rng, u)
	if foot:
		var wid := "war_maul" if rng.randi() % 2 == 0 else "dane_axe"
		var wealth := int(DB.factions.get(u.faction, {}).get("wealth", 2))
		u.equip["main_hand"] = make_item(rng, wid, wealth)
		u.equip.erase("off_hand")
		u.equip.erase("ranged")
		u.quiver.clear()
		var skill := "hammer" if wid == "war_maul" else "axe"
		if int(u.skills.get(skill, 0)) < 2:
			u.skills[skill] = 3
		var title := String(u.title).to_lower()
		if title.contains("caval") or title.contains("lancer") or title.contains("rider") or title.contains("horse"):
			u.title = "heavy foot"
		u.horse = null
		u.horse_care = {}
		var mult := float(rd.get("food_mult", 1.0))
		if mult > 1.0:
			if prev_wage > 0:
				u.wage = maxi(1, int(round(float(prev_wage) * mult)))
			if prev_hire > 0:
				u.hire_cost = maxi(1, int(round(float(prev_hire) * mult)))

## One troop from a faction troop template (uniform rule), equipped from its loadout choices.
static func make_troop(rng: RandomNumberGenerator, faction_id: String, troop: Dictionary, wealth: int = -1) -> Unit:
	if troop.has("creature"):   # monsters wave 1: creature "troops" (faction beasts) are animals, not people
		return Creatures.make(rng, String(troop["creature"]), faction_id)
	var f: Dictionary = DB.factions[faction_id]
	if wealth < 0:
		wealth = int(f.get("wealth", 2))
	var u := Unit.create(f["race"], faction_id, false)   # (roll_size builds his body)
	u.name = random_name(rng, f["race"])
	u.title = troop.get("name", "warrior")
	roll_attrs(rng, u)
	roll_size(rng, u)
	roll_personality(rng, u)
	roll_mind(rng, u)
	roll_look(rng, u)
	for s in troop.get("skills", {}):
		var rr: Array = troop["skills"][s]
		u.skills[s] = rng.randi_range(int(rr[0]), int(rr[1]))
	var lo: Dictionary = troop.get("loadout", {})
	for slot in lo:
		var choices: Array = lo[slot]
		var tid: String = choices[rng.randi() % choices.size()]
		if tid == "":
			continue
		var it := make_item(rng, tid, wealth)
		if it.material in ["linen", "leather"]:
			it.quality = 0
		u.equip[slot] = it
	# bows: a bow user's quiver (troop "arrows": {arrow id: count}, at most DB.QUIVER_MAX real arrows)
	var arw: Dictionary = troop.get("arrows", {})
	var room := DB.QUIVER_MAX
	for k in arw:
		var n := mini(int(arw[k]), room)
		if n > 0 and DB.arrows.has(k):
			u.quiver[k] = n
			room -= n
	# Two-handed weapons preclude a shield.
	var w := u.weapon()
	if w != null and w.tmpl().get("two_handed", false):
		u.equip.erase("off_hand")
	return u

static func pick_troop(rng: RandomNumberGenerator, faction_id: String) -> Dictionary:
	var troops: Array = DB.factions[faction_id]["troops"]
	var total := 0
	for t in troops:
		total += int(t.get("w", 1))
	var roll := rng.randi() % maxi(total, 1)
	for t in troops:
		roll -= int(t.get("w", 1))
		if roll < 0:
			return t
	return troops[0]

## A warband of `count` units. Gear quality and material follow faction wealth, so gear IS difficulty.
static func make_warband(rng: RandomNumberGenerator, faction_id: String, count: int, wealth: int = -1) -> Array:
	var out := []
	for i in count:
		out.append(make_troop(rng, faction_id, pick_troop(rng, faction_id), wealth))
	return out

## Personality: each trait is a triangular roll on median +-50 clipped to 0..100 (races[].personality medians,
## overridden per faction by factions[].personality; unlisted = 50). Our own trait set (DF survey part 2).
static func roll_personality(rng: RandomNumberGenerator, u: Unit) -> void:
	var ranges: Dictionary = u.race_def().get("personality", {}).duplicate()
	var f: Dictionary = DB.factions.get(u.faction, {})
	ranges.merge(f.get("personality", {}), true)
	for t in DB.TRAITS:
		var m: float = float(ranges.get(t, 50))
		var r: Array = [maxf(0.0, m - 50.0), m, minf(100.0, m + 50.0)]
		u.personality[t] = clampi(int(round(triangular(rng, r[0], r[1], r[2]))), 0, 100)

static func triangular(rng: RandomNumberGenerator, lo: float, mode: float, hi: float) -> float:
	var x := rng.randf()
	var c := (mode - lo) / maxf(0.001, hi - lo)
	if x < c:
		return lo + sqrt(x * (hi - lo) * (mode - lo))
	return hi - sqrt((1.0 - x) * (hi - lo) * (hi - mode))

## Height and broadness (% of race size), DF interval roll on DB.SIZE_RANGE. Sets Unit.size_h/size_b
## and rebuilds the body at the individual's mass.
static func roll_size(rng: RandomNumberGenerator, u: Unit) -> void:
	u.size_h = roll_interval(rng, DB.SIZE_RANGE)
	u.size_b = roll_interval(rng, DB.SIZE_RANGE)
	var lm: Dictionary = u.race_def().get("limbs", {})   # v0.012: a race's mean limb length (dwarves: short arms and legs)
	var am := float(lm.get("arm", 100.0)); var lgm := float(lm.get("leg", 100.0))
	u.arm_len = clampi(int(round(rng.randfn(am, 4.0))), int(am) - 10, int(am) + 10)
	u.leg_len = clampi(int(round(rng.randfn(lgm, 4.0))), int(lgm) - 10, int(lgm) + 10)
	u.body.init_from_plan(DB.bodies[u.body.plan_id], u.rolled_mass())

## Words for a trait level. Entries with 4 words give [very low, low, high, very high] phrasings (for phrases
## that cannot take "very", e.g. "sticks with the squad"); 2-word entries are adjectives and take "very".
static func trait_word(t: String, v: int) -> String:
	var w: Array = DB.TRAIT_WORDS.get(t, ["low", "high"])
	var four := w.size() >= 4
	if v <= 15: return w[0] if four else "very " + w[0]
	if v <= 35: return w[1] if four else w[0]
	if v >= 85: return w[3] if four else "very " + w[1]
	if v >= 65: return w[2] if four else w[1]
	return ""

## The rest of the unit sheet: mind attributes, values, ambition, needs, preferences, age.
static func roll_mind(rng: RandomNumberGenerator, u: Unit) -> void:
	for a in DB.MIND_ATTRS:
		u.mind[a] = roll_attr(rng, u.race, a)
	for v in DB.VALUES:
		u.values[v] = clampi(int(round(triangular(rng, 0, 50, 100))), 0, 100)
	u.ambition = DB.AMBITIONS[rng.randi() % DB.AMBITIONS.size()]
	for n in DB.NEEDS:
		u.needs[n] = rng.randi_range(0, 100)
	u.pref_weapon = DB.WEAPON_SKILLS[rng.randi() % DB.WEAPON_SKILLS.size()]
	u.pref_material = ["copper", "tin", "bronze", "iron", "steel"][rng.randi() % 5]
	u.age = rng.randi_range(17, 45)
	# favourite drink: seeded from the rng state without drawing from it (no other roll shifts)
	Food.roll_fav_drink(u, int(rng.state))
