class_name Recruits
extends RefCounted
## Town recruit pools: people of the town's race with a generated backstory, background-driven skills
## and attributes, a few pieces of starting gear, a hire cost and a daily wage. No crafting skills:
## the company are mercenaries.
##
## Generation follows the DF order: race (town faction), attributes, height/broadness, personality,
## background (skills, wage, story, a +-1 DF tier nudge on 1-2 attributes), then a price from the rolls.


## Douglas: only real jobs. A recruit's title is his real job or state in the economy (Recruits.real_role); his
## starting skills, attribute nudges, gear and wage come from that job's kit below [ours]: what the work trains
## (a smith's hand swings a hammer, a hunter knows the knife and keeps watch, a guard holds spear and shield).
## skills {skill: [min, max]}, attrs {ATTR: >1 nudges up, <1 down}, gear: weapon-skill hints or "shield", "helm",
## "clothes", "shoes" resolved against the town culture; wage: multiplier.
const KITS := {
	"mine": {"skills": {"hammer": [1, 3], "mace": [0, 2], "wrestler": [1, 3]}, "attrs": {"STR": 1.12, "TOU": 1.1, "END": 1.12}, "gear": ["mace", "clothes"], "wage": 0.9},
	"quarry": {"skills": {"hammer": [1, 3], "wrestler": [0, 2]}, "attrs": {"STR": 1.12, "END": 1.1}, "gear": ["mace", "clothes"], "wage": 0.9},
	"smith": {"skills": {"hammer": [2, 4], "mace": [1, 2], "armor_user": [0, 1]}, "attrs": {"STR": 1.15, "TOU": 1.06}, "gear": ["mace", "clothes", "shoes"], "wage": 1.0},
	"hunter": {"skills": {"dagger": [1, 3], "spear": [1, 2], "observer": [1, 3], "dodger": [0, 2]}, "attrs": {"AGI": 1.1, "KIN": 1.1, "SPA": 1.05}, "gear": ["spear", "dagger", "clothes", "shoes"], "wage": 1.0},
	"wood": {"skills": {"axe": [2, 4], "wrestler": [0, 2]}, "attrs": {"STR": 1.1, "END": 1.08}, "gear": ["axe", "clothes", "shoes"], "wage": 0.8},
	"fisher": {"skills": {"spear": [1, 3], "dagger": [0, 2]}, "attrs": {"END": 1.06, "KIN": 1.06}, "gear": ["spear", "clothes"], "wage": 0.7},
	"carter": {"skills": {"dodger": [0, 2], "wrestler": [0, 2], "dagger": [0, 1]}, "attrs": {"END": 1.1, "STR": 1.05}, "gear": ["dagger", "clothes", "shoes"], "wage": 0.8},
	"guard": {"skills": {"spear": [1, 3], "shield_user": [1, 3], "discipline": [0, 2], "observer": [0, 2]}, "attrs": {"WIL": 1.06, "END": 1.05}, "gear": ["spear", "shield", "helm", "clothes", "shoes"], "wage": 1.2},
	"collector": {"skills": {"mace": [0, 2], "intimidator": [1, 2], "judge_of_intent": [0, 2]}, "attrs": {"WIL": 1.08}, "gear": ["mace", "clothes", "shoes"], "wage": 1.1},
	"craft": {"skills": {"dagger": [0, 2], "dodger": [0, 1]}, "attrs": {"KIN": 1.06, "FOC": 1.05}, "gear": ["dagger", "clothes", "shoes"], "wage": 0.8},
	"field": {"skills": {"spear": [0, 2], "wrestler": [1, 2], "axe": [0, 1]}, "attrs": {"STR": 1.08, "END": 1.1}, "gear": ["spear", "clothes"], "wage": 0.6},
	"herd": {"skills": {"spear": [0, 2], "dodger": [1, 3], "wrestler": [0, 2]}, "attrs": {"END": 1.12, "AGI": 1.06}, "gear": ["spear", "clothes"], "wage": 0.7},
	"casual": {"skills": {"dodger": [0, 2], "wrestler": [0, 2], "dagger": [0, 1]}, "attrs": {"END": 1.05}, "gear": ["clothes"], "wage": 0.6},
	"idle": {"skills": {"wrestler": [0, 1], "dodger": [0, 1]}, "attrs": {"WIL": 0.97}, "gear": ["clothes"], "wage": 0.6},
}
## Business type -> kit.
const JOB_KIT := {"mine": "mine", "quarry": "quarry", "smelter": "smith", "weaponsmith": "smith", "armorsmith": "smith", "jeweler": "craft",
	"hunter": "hunter", "woodcutter": "wood", "carpenter": "wood", "builder": "wood", "fishery": "fisher", "market": "carter",
	"collector": "collector", "estate": "field", "farm": "field", "works": "field", "tanner": "craft", "leatherworker": "craft",
	"tailor": "craft", "weaver": "craft", "brewer": "craft", "vintner": "craft"}

## The kit for a role (job, land, herd, casual work, service, or a state with no work) as a background dict for
## make_recruit: {id, name (= the real title), skills, attrs, gear, wage}.
static func kit_for(role: Dictionary) -> Dictionary:
	var k := "idle"
	match String(role.get("kind", "")):
		"job": k = JOB_KIT.get(String(role["key"]), "craft")
		"land": k = "field"
		"herd": k = "herd"
		"casual": k = "casual"
		"service": k = "guard"
	var kit: Dictionary = KITS[k].duplicate(true)
	kit["id"] = k
	kit["name"] = String(role.get("title", "out of work"))
	return kit

static func _pick_gear(rng: RandomNumberGenerator, culture: String, hint: String) -> String:
	var cands := []
	match hint:
		"clothes", "shoes":
			return ""
		"shield", "helm", "body":
			for c in [culture, "middle", "northern"]:
				for tid in DB.armor_by_culture.get(c, []):
					if DB.armor[tid].get("slot", "") == hint:
						cands.append(tid)
				if not cands.is_empty():
					break
		_:
			for c in [culture, "middle", "northern", "orc", "goblin", "moon_elf", "eastern", "dwarf"]:
				for tid in DB.weapons_by_culture.get(c, []):
					if DB.weapons[tid].get("skill", "") == hint and not DB.weapons[tid].get("two_handed", false):
						cands.append(tid)
				if not cands.is_empty():
					break
	if cands.is_empty():
		return ""
	return cands[rng.randi() % cands.size()]


## One recruit of the town's race with the kit of his real job (kit_for). Without a kit (towns without an economy,
## dev stand-ins) he is out of work.
static func make_recruit(rng: RandomNumberGenerator, town: Dictionary, bg: Dictionary = {}) -> Unit:
	var fid: String = town["faction"]
	var race: String = Persons.race_of(town["econ"]) if TownEcon.has_econ(town) else String(DB.factions[fid]["race"])
	if bg.is_empty():
		bg = kit_for({})
	# DF order: 1 race/region (town faction), 2 attributes, 3 height/broadness, 4 personality, 5 background, 6 price
	var u := Unit.create(race, fid, false)   # (roll_size builds his body)
	u.name = Factory.random_name(rng, race)
	u.title = bg["name"]
	Factory.roll_attrs(rng, u)
	Factory.roll_size(rng, u)
	Factory.roll_personality(rng, u)
	Factory.roll_mind(rng, u)
	Factory.roll_look(rng, u)
	# the work: +-1 tier nudge on 1-2 of its attributes (re-rolled from the neighbouring DF tier)
	var nudges: Array = bg["attrs"].keys()
	for _k in nudges.size() - rng.randi_range(1, mini(2, nudges.size())):
		nudges.remove_at(rng.randi() % nudges.size())
	for a in nudges:
		_nudge_attr(rng, u, a, 1 if float(bg["attrs"][a]) >= 1.0 else -1)
	var skill_total := 0
	for s in bg["skills"]:
		var r: Array = bg["skills"][s]
		u.skills[s] = rng.randi_range(int(r[0]), int(r[1]))
	if rng.randf() < 0.5:
		var pool: Array = DB.COMBAT_SKILLS
		var s2: String = pool[rng.randi() % pool.size()]
		u.skills[s2] = int(u.skills.get(s2, 0)) + 1
	for s in u.skills:
		skill_total += int(u.skills[s])
	# starting gear: worn and cheap, in the metals this town's smiths actually work (Factory.town_metal)
	var culture: String = town.get("culture", "middle")
	for hint in bg["gear"]:
		if hint == "clothes":
			u.equip["clothing"] = Item.make("tunic", "linen", 0)
			u.equip["legs_under"] = Item.make("trousers", "linen", 0)
			continue
		if hint == "shoes":
			u.equip["feet"] = Item.make("shoes", "leather", 0)
			continue
		var tid := _pick_gear(rng, culture, hint)
		if tid == "":
			continue
		var it := Item.make(tid, Factory.town_metal(rng, town, tid), 1 if rng.randf() < 0.15 else 0)   # v0.014: the town's own metal mix (was 75% tin, fixed)
		it.wear = rng.randi_range(0, 2)
		u.equip[it.slot()] = it
	# a plain line until the family register's story replaces it (Backstory)
	var first: String = u.name.split(" ")[0]
	var own := _personality_line(u).replace("{first}", first).replace("{town}", String(town["name"]))
	u.backstory = ("%s of %s, %s." % [first, town["name"], bg["name"]]) + (" " + own if own != "" else "")
	# pay: the job sets the wage; better rolls (attributes vs race, size) cost more to hire
	var quality := 0.0   # 0 = race-typical
	for a in ["STR", "AGI", "TOU", "END", "WIL", "FOC"]:
		quality += Factory.attr_percentile(race, a, int(u.attrs[a])) - 0.5
	quality += (u.size_h + u.size_b - 200) / 100.0
	var greed := (float(u.personality.get("greed", 50)) - 50.0) / 200.0   # greedy recruits ask up to +25%
	var wage := (3.0 + skill_total * 0.35 + quality * 2.0) * float(bg["wage"]) * (1.0 + greed) * TownEcon.COIN   # coins
	u.wage = maxi(2 * int(TownEcon.COIN), int(round(wage)))
	var cost := u.wage * 10.0 * clampf(1.0 + quality * 0.35, 0.6, 2.0) * (1.0 + greed) + u.gear_value() * 0.5
	u.hire_cost = maxi(10 * int(TownEcon.COIN), int(round(cost / 5.0)) * 5)
	return u


const TIER_ORDER := ["---", "--", "-", "0", "+", "++"]

## Shift one attribute a DF tier up or down: re-roll from the neighbouring tier, keep the race median for the ceiling.
static func _nudge_attr(rng: RandomNumberGenerator, u: Unit, a: String, dir: int) -> void:
	var r := u.race_def()
	var med := int(Factory.att_range(u.race, a)[3])
	var br: Array
	if r.get("att_ranges", {}).has(a):
		var f := 1.15 if dir > 0 else 0.87
		br = (r["att_ranges"][a] as Array).map(func(v): return int(v * f))
	else:
		var tier: String = r.get("tiers", {}).get(a, "0")
		var i := clampi(TIER_ORDER.find(tier) + dir, 0, TIER_ORDER.size() - 1)
		br = DB.ATTR_TIERS[TIER_ORDER[i]]
	var v := clampi(Factory.roll_interval(rng, br), DB.ATTR_MIN, DB.ATTR_HARD_CAP)
	# a nudge never moves against its direction
	v = maxi(v, int(u.attrs[a])) if dir > 0 else mini(v, int(u.attrs[a]))
	u.attrs[a] = v
	u.attr_base[a] = v
	u.attr_cap[a] = DB.attr_ceiling(v, med, DB.TALENT_LEVELS[int(u.talent.get(a, 1))])

static func _personality_line(u: Unit) -> String:
	var best := ""; var dev := 30
	for t in u.personality:
		var d := absi(int(u.personality[t]) - 50)
		if d > dev:
			dev = d; best = t
	if best == "":
		return ""
	var word := Factory.trait_word(best, int(u.personality[best]))
	if word == "":
		return ""
	# not hired yet: town wording ("around camp" only once he is in the company)
	var ws := word.split(" ")
	if ws.size() >= 3 and ws[0] != "a" and ws[0] != "very" and ws[0].ends_with("s"):   # a verb phrase: "sticks with the squad"
		return ["Around {town}, {first} %s.", "In {town} they say {first} %s."][absi(hash(u.name)) % 2] % word
	return ["Known around {town} as %s.", "Folk in {town} call {first} %s.", "Neighbours in {town} would say {first} is %s.",
		"Ask anyone in {town}: {first} is %s."][absi(hash(u.name)) % 4] % word

static func generate_pool(town: Dictionary, rng: RandomNumberGenerator) -> Array:
	if TownEcon.has_econ(town):
		return _family_pool(town, rng)
	var n := 2 + int(town["size"]) + rng.randi_range(0, 2)
	var out := []
	for i in n:
		out.append(make_recruit(rng, town))
	return out

## Douglas: the pool is filled ONLY from the town's register persons (Persons), adults and elders at home, never
## children, ranked by real desperation (hunger, homelessness, the poorhouse, debt and arrears, land or house
## lost, wages unpaid, no work); the most desperate first, up to the town's pool size. A family that is getting
## by (desperation 0) never sends anyone. The recruit IS that person: his name, sex and birth day; his title and
## kit from his real work; his story from the register. Hard times bring more and cheaper recruits.
static func desperation(f: Dictionary) -> float:
	var d := Families.hardship(f)
	var ln: Dictionary = f.get("ln", {})
	d += 0.3 * minf(3.0, float(ln.get("miss", 0)))
	if not (ln.get("sold", []) as Array).is_empty():
		d += 0.2
	if f.get("destitute", false):
		d += 0.5
	if f.has("lost"):
		d += 0.2
	# plain poverty counts a little: no land of their own, a thin purse (a family with land and money that is
	# getting by scores 0 and sends nobody)
	if (f.get("land", {}) as Dictionary).is_empty() and (f.get("herd", {}) as Dictionary).is_empty():
		d += 0.1
	d += 0.1 * maxf(0.0, 1.0 - float(f.get("purse", 0.0)) / (60.0 * TownEcon.COIN))
	return d

static func _family_pool(town: Dictionary, rng: RandomNumberGenerator) -> Array:
	var e: Dictionary = town["econ"]
	var day := float(Game.day)
	# last pool's people go home (the recruits not hired are replaced)
	var cands := []
	var hard_sum := 0.0
	var nf := 0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		if not f.has("pp"):
			Persons.sync(e, f, day)   # (the weekly family turn keeps the records level)
		for p in Persons.pp(f):
			if String(p[4]) == "hire":
				Persons.set_home(p)
		var d := desperation(f)
		hard_sum += minf(1.0, Families.hardship(f))
		nf += 1
		if d <= 0.0:
			continue
		# equally desperate: one from each family first, then the second of each (a hard-up house does not send
		# all its grown-ups at once while its neighbours are just as badly off)
		if Population.is_cohort(f):
			for i in mini(7 + int(town["size"]), Population.eligible_slots(e, f, day)):
				cands.append([d, i * 1000000000 + absi(hash([f["id"], i, int(day)])) % 1000000000, [], f])
		var mine := []
		for p in Persons.pp(f):
			if String(p[4]) == "" and int(p[5]) < 0:
				mine.append([absi(hash([int(p[0]), int(day)])), p])
		mine.sort_custom(func(a, b): return a[0] < b[0])
		for i in mine.size():
			cands.append([d, i * 1000000000 + int(mine[i][0]) % 1000000000, mine[i][1], f])
	# At most 2 + size + 4 hardship + 1 random places. Keep that many, using the
	# original complete sort if any ranking keys tie (Godot's sort is unstable).
	cands = _rank_pool_candidates(cands, 7 + int(town["size"]))
	var avg_hard := hard_sum / maxf(1.0, float(nf))
	var n := 2 + int(town["size"]) + int(round(avg_hard * 4.0)) + rng.randi_range(0, 1)
	var out := []
	var cut := float(TownEcon.data()["family"]["recruit_hardship"])
	for c in cands.slice(0, n):
		var p: Array = c[2]
		var pick: Dictionary = c[3]
		if p.is_empty(): p = Population.promote(e, pick, day, rng)
		if p.is_empty(): continue
		# his trade is what he really does: a job the family holds, its own fields or herd, casual work, or his
		# real state (out of work, in the poorhouse); his skills and kit come from that work (kit_for)
		var role := person_role(e, pick, p)
		var u := make_recruit(rng, town, kit_for(role))
		u.title = role["title"]
		Persons.bind(e, pick, p, u, "hire", day)   # he is the register person: name, birth day, age
		u.home_town = town["id"]
		var first: String = Persons.first_of(e, p)
		# an elder carries his years
		if int(p[6]) == 1:
			for a in ["STR", "AGI", "END"]:
				u.attrs[a] = maxi(DB.ATTR_MIN, int(round(float(u.attrs[a]) * 0.85)))
		# Douglas: the story is his real record (Backstory.story): where he comes from, what happened in time order,
		# why he is for hire now; his temper, his dream and a fitting like are woven in (v0.014: a story, not a list)
		u.backstory = Backstory.recruit_text(town, e, pick, first, u.name, role, u)
		# the poorhouse broth leaves its mark: weakened families' people come in thinner and slower
		var weak := float(pick.get("weak", 0.0))
		if weak > 0.0:
			for a in ["STR", "TOU", "END", "AGI"]:
				u.attrs[a] = maxi(DB.ATTR_MIN, int(round(float(u.attrs[a]) * (1.0 - 0.2 * weak))))
		# desperate people ask less and take worse terms: hardship cuts the price and the wage
		var h2 := Families.hardship(pick)
		u.hire_cost = maxi(5 * int(TownEcon.COIN), int(round(u.hire_cost * maxf(0.3, 1.0 - cut * h2) / 5.0)) * 5)
		u.wage = maxi(int(TownEcon.COIN), int(round(u.wage * maxf(0.5, 1.0 - 0.25 * h2))))
		out.append(u)
	return out

## A small worst-first heap avoids sorting every eligible person for a handful of places.
## Duplicate keys take the original path, preserving its exact equal-key permutation.
static func _rank_pool_candidates(cands: Array, limit: int) -> Array:
	if cands.size() <= limit:
		cands.sort_custom(_pool_precedes)
		return cands
	var seen := {}
	var heap := []
	for c in cands:
		if not seen.has(c[0]):
			seen[c[0]] = {}
		if seen[c[0]].has(c[1]):
			cands.sort_custom(_pool_precedes)
			return cands
		seen[c[0]][c[1]] = true
		if heap.size() < limit:
			heap.append(c)
			var at := heap.size() - 1
			while at > 0:
				var parent := (at - 1) / 2
				if not _pool_precedes(heap[parent], heap[at]):
					break
				var tmp = heap[parent]; heap[parent] = heap[at]; heap[at] = tmp
				at = parent
		elif _pool_precedes(c, heap[0]):
			heap[0] = c
			var at := 0
			while at * 2 + 1 < heap.size():
				var worst := at * 2 + 1
				if worst + 1 < heap.size() and _pool_precedes(heap[worst], heap[worst + 1]):
					worst += 1
				if not _pool_precedes(heap[at], heap[worst]):
					break
				var tmp = heap[at]; heap[at] = heap[worst]; heap[worst] = tmp
				at = worst
	heap.sort_custom(_pool_precedes)
	return heap

static func _pool_precedes(a: Array, b: Array) -> bool:
	return a[0] > b[0] if a[0] != b[0] else a[1] < b[1]

## Trades from what a family really does in the economy: a job at a business -> that trade; hands on the family
## land -> its crop; the family herd -> its animal; homeless casual work -> that work; nothing -> his real state.
const JOB_TITLES := {"mine": "%s miner", "smelter": "smelter's hand", "weaponsmith": "smith's striker", "armorsmith": "armourer's striker",
	"hunter": "hunter", "woodcutter": "woodcutter", "carpenter": "carpenter's hand", "fishery": "fisher", "quarry": "quarryman",
	"weaver": "weaver", "tailor": "tailor's hand", "tanner": "tanner's hand", "leatherworker": "leatherworker's hand",
	"brewer": "brewer's hand", "vintner": "vintner's hand", "builder": "builder's labourer", "market": "market porter",
	"collector": "tax collector's man", "estate": "hand on the town fields", "farm": "hired farmhand", "works": "labourer on the town works",
	"jeweler": "jeweler's apprentice"}
const HERD_TITLES := {"sheep": "shepherd", "cattle": "cattle herder", "pigs": "swineherd", "goats": "goatherd"}
## Titles for a state with no work (still real: the register says so).
const STATE_TITLES := {"poorhouse": "in the poorhouse", "homeless": "casual labourer", "idle": "out of work"}

## "copper miner", "tanner's hand": the title of a worker at this business.
static func job_title(_e: Dictionary, b: Dictionary) -> String:
	var t: String = b["type"]
	if t == "academy":
		return Academy.staff_title(b)   # v0.012: the research house's chemists and apprentices
	# Dictionary.get evaluates its fallback even for a known title; avoid that work in hiring loops.
	var title: String = JOB_TITLES[t] if JOB_TITLES.has(t) else "%s's hand" % TownEcon.data()["businesses"].get(t, {}).get("name", t)
	if t == "mine":
		title = title % String(b.get("ore", "copper_ore")).split("_")[0]
	return title

## Every real trade this family's people have now: [{title, kind (job|land|herd|casual|state), key, where, w}].
static func real_roles(e: Dictionary, f: Dictionary) -> Array:
	var out := []
	for k in f.get("jobs", {}):
		var b: Dictionary = e["biz"][int(k)]
		out.append({"title": job_title(e, b), "kind": "job", "key": String(b["type"]), "where": Businesses.title(e, b), "w": float(f["jobs"][k])})
	if int(f.get("hands", 0)) > 0:
		var best := ""; var most := 0
		for c in f.get("land", {}):
			if int(f["land"][c]) > most:
				most = int(f["land"][c]); best = c
		if best != "":
			var v := TownEcon.variety_word(e, best)
			out.append({"title": "farmhand on the %s" % v, "kind": "land", "key": best, "where": "%s of %s" % [TownEcon.n_of(most, "acres"), v], "w": float(f["hands"])})
		var ha := ""; var hn := 0
		for a in f.get("herd", {}):
			if int(f["herd"][a]) > hn:
				hn = int(f["herd"][a]); ha = a
		if ha != "":
			out.append({"title": HERD_TITLES.get(ha, "%s herder" % ha), "kind": "herd", "key": ha, "where": TownEcon.n_of(hn, ha), "w": 1.0})
	for j in f.get("cj", {}):
		var cj: Dictionary = TownEcon.data()["casual_jobs"].get(j, {})
		out.append({"title": String(cj.get("name", j)), "kind": "casual", "key": j, "where": "", "w": float(f["cj"][j])})
	# the ones without work: idle hands, the homeless, the poorhouse
	if int(f.get("idle", 0)) > 0 or out.is_empty():
		var st := "poorhouse" if f.get("shel", false) else ("homeless" if int(f.get("homes", 1)) <= 0 else "idle")
		out.append({"title": STATE_TITLES[st], "kind": "state", "key": st, "where": "", "w": maxf(1.0, float(f.get("idle", 0)))})
	return out

## This person's own trade (Persons.work: the place he holds in the family's work), as a role dict
## {title, kind (job|land|herd|casual|state), key, where, w}. Elders: "past working age". Never empty.
static func person_role(e: Dictionary, f: Dictionary, p: Array) -> Dictionary:
	if int(p[6]) == 1:
		return {"title": "past working age", "kind": "state", "key": "elder", "where": "", "w": 1.0}
	var j: Dictionary = Persons.work(e, f).get(int(p[0]), {})
	if j.is_empty() or String(j["kind"]) == "none":
		var st := "poorhouse" if f.get("shel", false) else ("homeless" if int(f.get("homes", 1)) <= 0 else "idle")
		return {"title": STATE_TITLES[st], "kind": "state", "key": st, "where": "", "w": 1.0}
	match String(j["kind"]):
		"job":
			var b: Dictionary = e["biz"][int(j["biz"])]
			return {"title": String(j["title"]), "kind": "job", "key": String(b["type"]), "where": String(j["where"]), "w": 1.0}
		"land":
			return {"title": "farmhand on the %s" % TownEcon.variety_word(e, _biggest_key(f["land"])), "kind": "land", "key": _biggest_key(f["land"]), "where": String(j["where"]), "w": 1.0}
		"herd":
			var a := _biggest_key(f["herd"])
			return {"title": HERD_TITLES.get(a, "%s herder" % a), "kind": "herd", "key": a, "where": String(j["where"]), "w": 1.0}
	return {"title": String(j["title"]), "kind": "casual", "key": String(j.get("cj", "")), "where": "", "w": 1.0}

static func _biggest_key(d: Dictionary) -> String:
	var best := ""; var most := -1
	for k in d:
		if int(d[k]) > most:
			most = int(d[k]); best = String(k)
	return best

## One of them for this recruit (weighted by how many of the family do it). Never empty.
static func real_role(e: Dictionary, f: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var roles := real_roles(e, f)
	var tot := 0.0
	for r in roles:
		tot += float(r["w"])
	var x := rng.randf() * tot
	for r in roles:
		x -= float(r["w"])
		if x <= 0.0:
			return r
	return roles[-1]

## Every title the economy can give (tests: a recruit's title is always one of these for his family).
static func titles_for(e: Dictionary, f: Dictionary) -> Array:
	var out: Array = real_roles(e, f).map(func(r): return String(r["title"]))
	if int(f.get("old", 0)) > 0:
		out.append("past working age")
	return out


## What this recruit asks of this company: the company's best Negotiator talks the price and the wage
## down (1% per level, tuned); greed is already in the recruit's own asking price. Menus show these numbers.
static func offer(game, u: Unit) -> Dictionary:
	var neg: int = game.best_skill("negotiator") if game.has_method("best_skill") else 0
	var f := clampf(1.0 - 0.01 * neg, 0.75, 1.0)
	return {"hire_cost": maxi(5 * int(TownEcon.COIN), int(round(u.hire_cost * f / 5.0)) * 5), "wage": maxi(int(TownEcon.COIN), int(round(u.wage * f)))}

## Hire a recruit from a town pool into the company at offer() terms. Returns false if gold is short.
static func hire(game, town: Dictionary, u: Unit) -> bool:
	if game.company.filter(func(member): return not member.dead).size() >= Roster.MAX_COMPANY:
		return false
	var o := offer(game, u)
	if game.gold < int(o["hire_cost"]) or not town["recruits"].has(u):
		return false
	if not Diplomacy.visible_recruits(game, town).has(u):
		return false   # diplomacy: below -20 standing half the faction's own race won't sign, below -50 none
	game.gold -= int(o["hire_cost"])
	u.wage = int(o["wage"])
	town["recruits"].erase(u)
	# economy: the person leaves the family row; the family is named from now on (its record is kept)
	if u.family >= 0 and TownEcon.has_econ(town) and u.family < (town["econ"]["fams"] as Array).size():
		var fam: Dictionary = town["econ"]["fams"][u.family]
		# his own record: out of the row's counts (his sex / an elder), state "with your company"
		var p := Persons.by_uid(fam, u.uid)
		if not p.is_empty():
			var s := "old" if int(p[6]) == 1 else ("m" if int(p[2]) == 0 else "f")
			Persons.log_life(p, float(game.day), "serve", "company")
			p[4] = "company"
			if int(fam[s]) > 0:
				fam[s] = int(fam[s]) - 1
				town["econ"]["pop"] = int(town["econ"]["pop"]) - 1
				if s != "old":
					town["econ"]["adults"] = int(town["econ"]["adults"]) - 1
				Census.record_move(town["econ"], int(p[0]), "out", "", float(game.day), "joined the company")   # the census
			Families.reassign(town["econ"], fam)
		elif Families.remove_member(town["econ"], fam):
			Census.record_move(town["econ"], -1, "out", "", float(game.day), "joined the company")   # the census
		fam["named"] = true
		fam["purse"] = float(fam["purse"]) + float(o["hire_cost"])   # coinage: the hiring money goes home (no coin vanishes)
		TownEcon.gold_out(-float(o["hire_cost"]))
		Families.add_hist(fam, "%s left to serve with a mercenary company." % u.name, float(game.day))
		Families.event(fam, "company", [u.name], float(game.day))
	u.faction = "player"
	u.role = "troop"
	u.squad = -1
	game.company.append(u)
	if game.get("world") is Dictionary:
		Mobilization.register_company(game, u) # exact native person/private kit, no new people/payment
		Diplomacy.roster_changed(game)   # diplomacy: band make-up offset follows the roster
	game.changed.emit()
	return true
