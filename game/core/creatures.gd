class_name Creatures
extends RefCounted
## Monsters wave 1: creature units built from data/creatures.json (merged into DB.races by core/db.gd).
## A creature is an ordinary Unit on the existing tissue sim: body plan + coat layers + natural attacks +
## tokens + size + rarity. No HP, no special-case combat (sim/natural_attacks.gd picks and swings the attacks).

const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]

static func is_creature(race_id: String) -> bool:
	return DB.is_creature(race_id)

static func def(cid: String) -> Dictionary:
	return DB.races.get(cid, {}) if DB.is_creature(cid) else {}

## Every creature type in the data (enabled ones only unless all = true).
static func ids(all: bool = false) -> Array:
	var out := []
	for cid in DB.creature_data.get("creatures", {}):
		if all or bool(DB.races[cid].get("enabled", true)):
			out.append(cid)
	out.sort()
	return out

static func rarity(cid: String) -> String:
	return String(def(cid).get("rarity", "common"))

static func rarity_info(r: String) -> Dictionary:
	return DB.creature_data.get("rarity", {}).get(r, {"weight": 1, "bounty": 1.0})

static func spawning() -> Dictionary:
	return DB.creature_data.get("spawning", {})

static func tun(key: String, dflt):
	return spawning().get(key, dflt)

static func has_token(u: Unit, token: String) -> bool:
	return token in u.race_def().get("tokens", [])

## One creature. Attributes roll on the creature's DF tiers; skills from its ranges; personality from its medians.
## look.skin = coat colour (CreaturePainter reads it), look.seed varies markings.
static func make(rng: RandomNumberGenerator, cid: String, faction_id: String = "beasts") -> Unit:
	var d := def(cid)
	var u := Unit.create(cid, faction_id)
	u.name = ""
	var titles: Array = d.get("titles", [])
	u.title = ("%s %s" % [titles[rng.randi() % titles.size()], d.get("name", cid)]) if not titles.is_empty() else String(d.get("name", cid))
	Factory.roll_attrs(rng, u)
	Factory.roll_size(rng, u)
	Factory.roll_personality(rng, u)
	var sk: Dictionary = d.get("skills", {})
	for s in sk:
		u.skills[s] = rng.randi_range(int(sk[s][0]), int(sk[s][1]))
	var cols: Array = d.get("art", {}).get("colors", ["#888888"])
	var c := Color(cols[rng.randi() % cols.size()])
	c = c.lightened(rng.randf_range(0.0, 0.08)) if rng.randf() < 0.5 else c.darkened(rng.randf_range(0.0, 0.1))
	u.look = {"skin": c.to_html(false), "hair": d.get("art", {}).get("belly", "#cccccc"), "beard": false, "seed": rng.randi()}
	u.age = rng.randi_range(2, 12)
	return u

## A group of one creature type: size from its group range unless n > 0. The first is the leader (biggest).
static func make_group(rng: RandomNumberGenerator, cid: String, n: int = 0, faction_id: String = "beasts") -> Array:
	var g: Array = def(cid).get("group", [1, 1])
	if n <= 0:
		n = rng.randi_range(int(g[0]), int(g[1]))
	var out := []
	for i in n:
		out.append(make(rng, cid, faction_id))
	if n > 1:
		var lead: Unit = out[0]
		lead.size_h = maxi(lead.size_h, 108)
		lead.size_b = maxi(lead.size_b, 108)
		lead.body.init_from_plan(DB.bodies[lead.body.plan_id], lead.mass())
		lead.title = String(def(cid).get("leader_title", "leader"))
		if not lead.title.contains(String(def(cid).get("name", cid))):
			lead.title = "%s %s" % [def(cid).get("name", cid), lead.title]
		for s in ["brawler", "wrestler", "fighter"]:
			lead.skills[s] = int(lead.skills.get(s, 0)) + 1
	return out

## Named bounty target: bigger, tougher, a proper name ("Greymuzzle").
static func make_named(rng: RandomNumberGenerator, cid: String) -> Unit:
	var u := make(rng, cid)
	var names: Array = DB.names.get("beast_names", {}).get(cid, [])
	u.name = names[rng.randi() % names.size()] if not names.is_empty() else "Old One"
	u.title = "great %s" % def(cid).get("name", cid)
	u.size_h = 118; u.size_b = 118
	u.body.init_from_plan(DB.bodies[u.body.plan_id], u.mass())
	for s in u.skills:
		if int(u.skills[s]) > 0:
			u.skills[s] = int(u.skills[s]) + 2
	for a in ["STR", "TOU", "END", "WIL"]:
		u.attrs[a] = mini(DB.ATTR_HARD_CAP, int(u.attrs[a] * 1.15))
	return u

## Rough map strength of one creature (world.gd unit_power hook): data "power" x attributes.
static func power(u: Unit) -> float:
	if u.dead:
		return 0.0
	var a := (u.attr("STR") + u.attr("AGI") + u.attr("TOU") + u.attr("END")) / 4000.0
	return float(u.race_def().get("power", 1.0)) * a * sqrt(u.mass() / maxf(1.0, float(u.race_def().get("mass", 70))))

## Trophies from slain creatures (auto-sold as gold in the aftermath). A trophy tied to a part is lost with that
## part (a severed head yields no head trophy... unless it is picked up: [ours] it is lost); coat trophies lose value
## with the damage to the coat.
static func trophies(units: Array) -> Array:
	var out := []
	for u in units:
		if not u.dead or not is_creature(u.race):
			continue
		for t in u.race_def().get("trophies", []):
			var gold := float(t.get("gold", 0)) * Item.COIN   # coinage: data in gold, x20 coins
			var part := String(t.get("part", ""))
			if part != "" and u.body.has_part(part) and u.body.is_lost(part):
				continue
			if bool(t.get("coat", false)):
				gold *= 1.0 - 0.6 * _coat_damage(u)
			if u.name != "":
				gold *= 2.0   # a named beast's trophies fetch more
			var g := int(round(gold * u.mass() / maxf(1.0, float(u.race_def().get("mass", 70)))))
			if g > 0:
				out.append({"name": String(t.get("name", "trophy")), "gold": g, "from": u.title})
	return out

static func _coat_damage(u: Unit) -> float:
	# every outer part of the plan counts (the body stores only wounded parts; the coat covers no inner part)
	var n := 0
	var dmg := 0.0
	var defs: Dictionary = u.body.defs()
	for pid in defs:
		var dl: Array = defs[pid].get("layers", [])
		if dl.is_empty() or not (String(dl[0]["tissue"]) in ["fur", "thick_hide", "scale", "hide"]):
			continue   # only the parts the coat lies over (not teeth, eyes, the mouth or anything inside)
		n += 1
		var p = u.body.parts.get(pid)
		if p != null and not (p["layers"] as Array).is_empty():
			dmg += 1.0 if p["severed"] else float(p["layers"][0]["dmg"])
	return dmg / maxf(1.0, n)
