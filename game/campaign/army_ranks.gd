class_name ArmyRanks
extends RefCounted
## Rank tree math, promotions, noble call-up, orc succession duels, militia trees, and rank-tree views
## split from Army (game/campaign/army.gd) to keep each file focused and under the size threshold.
## Structure only; all Army.* entry points delegate here with identical behavior.

const NO_ARMY := Army.NO_ARMY

# ================================================================== tree math
static func ranks(cul: Dictionary, tier: String) -> Array:
	return cul.get("ranks", {}).get(tier, ["soldier"])

## First officer rank index: army lists keep two status ranks, militia/guard one.
static func first_officer(tier: String) -> int:
	return 2 if tier == "army" else 1

static func levels_for(n: int, span: int, n_off: int) -> int:
	var l := 0
	var p := 1
	while l < n_off:
		p *= span
		if p > n:
			break
		l += 1
	return l

static func offset(k: int, span: int) -> int:
	var o := 0
	var p := 1
	for i in k:
		o += p
		p *= span
	return o

## Posts at each level from the top (caps): [1, span, span^2 ...] for `levels` levels.
static func caps(levels: int, span: int) -> Array:
	var out := []
	var p := 1
	for i in levels:
		out.append(p)
		p *= span
	return out

static func level_of(idx: int, span: int) -> int:
	var k := 0
	while offset(k + 1, span) <= idx:
		k += 1
	return k

static func up_of(idx: int, span: int) -> int:
	var k := level_of(idx, span)
	if k == 0:
		return -1
	return offset(k - 1, span) + (idx - offset(k, span)) / span

static func children_of(idx: int, span: int, levels: int) -> Array:
	var k := level_of(idx, span)
	if k + 1 >= levels:
		return []
	var j := idx - offset(k, span)
	var s := offset(k + 1, span) + j * span
	return range(s, s + span)

## Rank index of a post at level k (top = last rank of the list).
static func rank_at(k: int, rl: Array) -> int:
	return rl.size() - 1 - k

## Rank and file report to a bottom post by uid (stable while the tree keeps its shape).
static func report_post(u: Unit, levels: int, span: int) -> int:
	if levels <= 0:
		return -1
	var b0 := offset(levels - 1, span)
	var bn := offset(levels, span) - b0
	return b0 + (u.uid % bn)

## Caller-local pure command plan from the real roster and authoritative posts.
## No ranks/officers are created here; duplicate UID/post claims fail closed.
static func command_plan(units: Array, posts: Array, levels: int, span: int, fid: String, protected_units: Array = []) -> Array:
	span = maxi(2, span)
	levels = maxi(0, levels)
	var protected_ids: Dictionary = {}
	for value: Variant in protected_units:
		if value is Unit: protected_ids[value.get_instance_id()] = true
	var by: Dictionary = {}
	var ambiguous: Dictionary = {}
	var seen: Dictionary = {}
	var roster: Array = []
	for value: Variant in units:
		if not value is Unit: continue
		var u: Unit = value
		var instance: int = u.get_instance_id()
		if seen.has(instance): continue
		seen[instance] = true
		if u.dead or u.faction != fid or u.faction == "player" or protected_ids.has(instance): continue
		roster.append(u)
		if u.uid <= 0 or ambiguous.has(u.uid): continue
		if by.has(u.uid):
			ambiguous[u.uid] = true
			by.erase(u.uid)
		else:
			by[u.uid] = u
	var count: int = mini(posts.size(), offset(levels,span))
	var holds: Dictionary = {}
	for p: int in count:
		var uid: int = int(posts[p])
		if uid <= 0 or not by.has(uid) or not (by[uid] as Unit).is_officer(): continue
		holds[uid] = -2 if holds.has(uid) else p
	# Parent posts precede children. Resolve vacant/dead/absent branches once,
	# instead of scanning officers or walking the whole tree for every man.
	var nearest: Array = []
	nearest.resize(count)
	for p: int in count:
		var uid: int = int(posts[p])
		var parent: int = up_of(p,span)
		nearest[p] = uid if int(holds.get(uid,-1)) == p else (nearest[parent] if parent >= 0 else -1)
	var plan: Array = []
	for u: Unit in roster:
		var commander: int = -1
		if by.get(u.uid) == u:
			var post: int = int(holds.get(u.uid,-1))
			var parent: int = up_of(post,span) if post >= 0 else (report_post(u,levels,span) if not u.is_officer() else -1)
			if parent >= 0 and parent < count:
				commander = int(nearest[parent])
			if commander == u.uid: commander = -1
		plan.append({"unit":u,"commander_uid":commander})
	return plan

static func _apply_commands(game, units: Array, posts: Array, levels: int, span: int, fid: String) -> void:
	for row: Dictionary in command_plan(units,posts,levels,span,fid,game.company):
		(row["unit"] as Unit).squad = int(row["commander_uid"])

static func _link_field_commands(game, fid: String) -> void:
	var r: Dictionary = Army.rec(game.world,fid)
	var span: int = maxi(2,int(Army.cul_of_faction(fid).get("span",5)))
	_apply_commands(game,Army.members(game,fid),r["posts"],int(r["levels"]),span,fid)

# ================================================================== ranks: the tree
## Rebuilds the tree's shape for the army's size, validates holders, gives the status ranks, fills vacancies.
## prehistory: world gen / old saves: posts filled by the rule's score without fights or thresholds.
static func update_tree(game, fid: String, units: Array, prehistory: bool, day: int) -> void:
	var w: Dictionary = game.world
	var r := Army.rec(w, fid)
	var cul := Army.cul_of_faction(fid)
	var rl := ranks(cul, "army")
	var span := maxi(2, int(cul.get("span", 5)))
	var fo := first_officer("army")
	var by := {}
	for u in units:
		by[u.uid] = u
	var posts: Array = r["posts"]
	var lv := levels_for(units.size(), span, maxi(0, rl.size() - fo))
	var old_lv := int(r["levels"])
	if lv != old_lv:
		var n := offset(lv, span)
		while posts.size() > n:
			var uid := int(posts.pop_back())
			if by.has(uid):
				_demote(by[uid])
		while posts.size() < n:
			posts.append(-1)
		r["levels"] = lv
		r["fights"] = (r["fights"] as Array).filter(func(x): return int(x["p"]) < n)
		if lv < old_lv:
			_hist(game, fid, "The army shrank; the %s posts are gone." % rl[rank_at(lv, rl)])
	# holders still alive and in the army, ranks matching their posts; anyone else above the status ranks steps down
	var holds := {}
	for i in posts.size():
		var uid := int(posts[i])
		if uid < 0:
			continue
		if not by.has(uid):
			posts[i] = -1
			continue
		var u: Unit = by[uid]
		if not house_born(u):   # older saves: a commoner officer steps down
			posts[i] = -1
			_demote(u)
			continue
		holds[uid] = i
		u.rank = rank_at(level_of(i, span), rl)
		u.role = "officer"
	for u in units:
		if not holds.has(u.uid):
			if u.rank >= fo:
				_demote(u)
			elif u.rank == 0 and u.battles >= 1:
				u.rank = 1   # survived a battle: veteran / blooded
	# officers come only from houses: with too few house men in the field, the realm calls up its nobles
	if not prehistory:
		var vacant := posts.filter(func(x): return int(x) < 0).size()
		var free_nobles := 0
		for u in units:
			if not holds.has(u.uid) and house_born(u): free_nobles += 1
		if vacant > free_nobles:
			for nu in call_up_nobles(game, fid, mini(10, vacant - free_nobles)):
				by[nu.uid] = nu; units.append(nu)
	# vacancies, top-down (a contest already running keeps its post)
	var busy := {}
	for fgt in r["fights"]:
		busy[int(fgt["p"])] = true
	for i in posts.size():
		if int(posts[i]) < 0 and not busy.has(i):
			fill(game, fid, i, by, prehistory, day, false)
	if not (r["fights"] as Array).is_empty() and not prehistory:
		_queue_fight(w, fid)
	_link_field_commands(game,fid)

static func _demote(u: Unit) -> void:
	u.rank = 1
	u.role = "troop"

## Candidates for post p: the officers who reported to it; for a bottom post the rank and file reporting to it
## (blooded/veterans first). A new post nobody reports to yet: the faction's men past the promotion threshold.
static func candidates(game, fid: String, p: int, by: Dictionary, prehistory: bool) -> Array:
	var r := Army.rec(game.world, fid)
	var cul := Army.cul_of_faction(fid)
	var span := maxi(2, int(cul.get("span", 5)))
	var lv := int(r["levels"])
	var posts: Array = r["posts"]
	var fo := first_officer("army")
	var out := []
	var kids := children_of(p, span, lv)
	for c in kids:
		var uid := int(posts[c])
		if uid >= 0 and by.has(uid):
			out.append(by[uid])
	if kids.is_empty():
		var vets := []; var raw := []
		# One pass over the army per tree update, not one per post (a 1000-man army has hundreds of posts).
		for u in _reports(by, lv, span, fo).get(p, []):
			if u.rank >= fo:
				continue
			(vets if u.rank >= 1 else raw).append(u)
		out = vets if not vets.is_empty() else raw
	if out.is_empty():
		# a post nobody reports to yet (the tree grew): men past the threshold for that level
		var need: Array = Army.A()["promote_battles"]
		var lvl_from_bottom := lv - 1 - level_of(p, span)
		var nb := int(need[clampi(lvl_from_bottom, 0, need.size() - 1)])
		# The most renowned men past the threshold (at most 64): a big army's whole rank and file is not a
		# candidate list for every new post.
		for u in _reports(by, lv, span, fo).get(-2, []):
			if u.rank < fo and not u.dead and (prehistory or u.battles >= nb):
				out.append(u)
				if out.size() >= 64: break
	out = out.filter(func(u): return not u.dead)
	out.sort_custom(func(a, b): return a.uid < b.uid)
	return out

## A man of a house family (named, landed or ruling, not common folk): the only men who can hold rank in an army.
static func house_born(u: Unit) -> bool:
	if u == null or u.family < 0: return false
	var town: Dictionary = Game.world.get("towns", {}).get(u.home_town, {})
	if town.is_empty(): return false
	var f: Dictionary = People.fam_of(town, u.family)
	return not f.is_empty() and not f.get("cohort", false) and not f.get("estate", false) and not f.get("gone", false) and str(f.get("household_uid", "")) != ""

## Realms call up their own nobles to lead: adults of house families in the realm's towns who are at home
## join its largest field band (a person of the register, never invented) until the officer posts can be filled.
## At most `most` a day per realm, so a big tree fills over days. Returns the men called up.
static func call_up_nobles(game, fid: String, most: int) -> Array:
	var w: Dictionary = game.world
	var out: Array = []
	if most <= 0: return out
	var band: Dictionary = {}
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["faction"] == fid and Army.is_field(wb) and Army.is_people_band(wb) and (band.is_empty() or (wb["units"] as Array).size() > (band["units"] as Array).size()):
			band = wb
	if band.is_empty(): return out
	var roll: Dictionary = Army.state(w)["roll"]
	for tid in w["towns"]:
		var town: Dictionary = w["towns"][tid]
		if str(town.get("faction", "")) != fid or not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		var ab := People.ages(Persons.race_of(e))
		var head_uid := str(e.get("head", {}).get("person_uid", ""))
		for f in e.get("fams", []):
			if f.get("cohort", false) or f.get("estate", false) or f.get("gone", false) or str(f.get("household_uid", "")) == "": continue
			for p in Persons.pp(f):
				if out.size() >= most: return out
				if str(p[4]) != "" or int(p[5]) >= 0 or int(p[6]) != 0: continue
				if str(Persons.g(p, Persons.PERSON_UID, "")) == head_uid: continue   # the ruler governs; his kin ride
				var age := Persons.age_of(p, float(e.get("day", game.day)))
				if age < int(ab["adult"]) or age >= int(ab["elder"]): continue
				var u: Unit = CampaignWorld.make_resident_troop(game.rng, fid, town)
				Persons.log_life(p, float(game.day), "serve", "army")
				p[4] = "army"
				var sv: Dictionary = f["serve"]; sv["army"] = int(sv.get("army", 0)) + 1
				People.last_person = p
				People.bind(town, int(f["id"]), u, "army")
				u.family = int(f["id"]); u.home_town = str(tid); u.faction = fid
				roll[str(u.uid)] = [str(tid), int(f["id"]), "army", u.name]
				(band["units"] as Array).append(u)
				Families.event(f, "joined", [u.name, "army", Army.force_word(w, band)], float(game.day))
				out.append(u)
	return out

## Rank-and-file grouped by the post they report to (key -1: every man below officer rank), built once per roster.
static func _reports(by: Dictionary, lv: int, span: int, fo: int) -> Dictionary:
	var key := [lv, span, by.size()]
	if is_same(Army._rep_by, by) and Army._rep_key == key:
		return Army._rep_map
	Army._rep_by = by; Army._rep_key = key; Army._rep_map = {-1: []}
	for uid in by:
		var u: Unit = by[uid]
		if u.rank >= fo or not house_born(u): continue   # only house members can rise; the plebs stay plebs
		(Army._rep_map[-1] as Array).append(u)
		var rp := report_post(u, lv, span)
		if not Army._rep_map.has(rp): Army._rep_map[rp] = []
		(Army._rep_map[rp] as Array).append(u)
	var ranked: Array = (Army._rep_map[-1] as Array).duplicate()
	ranked.sort_custom(func(a, b): return a.renown > b.renown if a.renown != b.renown else (a.battles > b.battles if a.battles != b.battles else a.uid < b.uid))
	Army._rep_map[-2] = ranked
	return Army._rep_map

static func fill(game, fid: String, p: int, by: Dictionary, prehistory: bool, day: int, relink: bool = true) -> void:
	var w: Dictionary = game.world
	var r := Army.rec(w, fid)
	var cul := Army.cul_of_faction(fid)
	var span := maxi(2, int(cul.get("span", 5)))
	var cands := candidates(game, fid, p, by, prehistory)
	if cands.is_empty():
		return
	var rule := String(cul.get("rank_rule", "renown"))
	if rule == "strength":
		# orcs: high renown lets a man two levels down join the free-for-all
		var lv := int(r["levels"])
		for c in children_of(p, span, lv):
			for gc in children_of(c, span, lv):
				var uid := int(r["posts"][gc])
				if uid >= 0 and by.has(uid) and (by[uid] as Unit).renown >= float(Army.A()["renown_join"]) and not cands.has(by[uid]):
					cands.append(by[uid])
		if cands.size() == 1 or prehistory:
			var best: Unit = cands[0]
			for c2 in cands:
				if CampaignWorld.unit_power(c2) > CampaignWorld.unit_power(best):
					best = c2
			assign(game, fid, p, best, by, prehistory, day, [], relink)
			return
		var uids := []
		for c3 in cands:
			uids.append(c3.uid)
		(r["fights"] as Array).append({"p": p, "c": uids, "beat": []})
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), fid, p, day, "rank"])
	var pick := RankRules.pick(game, fid, rule, p, cands, by, rng, prehistory)
	if pick != null:
		assign(game, fid, p, pick, by, prehistory, day, [], relink)

## The post goes to u; the post he held opens and is filled the same way (the cascade).
static func assign(game, fid: String, p: int, u: Unit, by: Dictionary, prehistory: bool, day: int, beat: Array, relink: bool = true) -> void:
	var w: Dictionary = game.world
	var r := Army.rec(w, fid)
	var cul := Army.cul_of_faction(fid)
	var rl := ranks(cul, "army")
	var span := maxi(2, int(cul.get("span", 5)))
	var posts: Array = r["posts"]
	var old := posts.find(u.uid)
	if old >= 0:
		posts[old] = -1
	posts[p] = u.uid
	u.rank = rank_at(level_of(p, span), rl)
	u.role = "officer"
	var title: String = rl[u.rank]
	if not prehistory:
		var txt := ""
		var dead := beat.filter(func(b): return b[1])
		if not dead.is_empty():
			txt = "%s took the %s post over %s's corpse." % [u.name, title, String(dead[-1][0])]
		elif not beat.is_empty():
			txt = "%s took the %s post, beating %s." % [u.name, title, ", ".join(PackedStringArray(beat.map(func(b): return String(b[0]))))]
		else:
			txt = "%s was made %s." % [u.name, title]
		_hist(game, fid, txt)
		var f := People.fam_of(w["towns"].get(u.home_town, {}), u.family)
		if not f.is_empty():
			f["named"] = true
			Families.event(f, "officer", [u.name, title], float(game.day))
			Families.add_hist(f, "%s rose to %s." % [u.name, title], float(game.day))
	else:
		var f2 := People.fam_of(w["towns"].get(u.home_town, {}), u.family)
		if not f2.is_empty():
			f2["named"] = true   # named officers: full family records
	if p == 0:
		_war_leader(game, fid, u, title)
	if old >= 0:
		fill(game, fid, old, by, prehistory, day, false)
	if relink: _link_field_commands(game,fid)

## The top post is the faction's war leader; for orcs the warlord is also head of state (the capital's head).
static func _war_leader(game, fid: String, u: Unit, title: String) -> void:
	var w: Dictionary = game.world
	var fac: Dictionary = w["factions"].get(fid, {})
	fac["war_leader"] = {"name": u.name, "uid": u.uid, "title": title}
	if String(Army.cul_of_faction(fid).get("rank_rule", "")) != "strength":
		return
	Dynasty.bind_war_leader(game, fid, u, title)

static func _hist(game, fid: String, text: String) -> void:
	var r := Army.rec(game.world, fid)
	var h: Array = r["hist"]
	h.append("Day %d: %s" % [int(game.day) + 1, text])
	while h.size() > 20:
		h.pop_front()
	CampaignWorld.log_event(game, text)

# ================================================================== succession fights (orcs)
static func _queue_fight(w: Dictionary, fid: String) -> void:
	if not w.has("work"):
		w["work"] = []
	for j in w["work"]:
		if j[0] == "army_fight" and j[1] == fid:
			return
	# Succession duels run in the background (CampaignWorld.work_slice): they never hold the world clock.
	if not w.has("fight_work"): w["fight_work"] = []
	if not (w["fight_work"] as Array).has(fid): (w["fight_work"] as Array).append(fid)

## One duel of the first open contest (one work job, one frame): two candidates fight in the real combat sim on a
## tiny map with their own gear; real wounds and deaths. The winner meets the next; the last one standing takes
## the post, and the post he held opens (the cascade queues its own contest).
static func fight_step(game, fid: String, budget_usec: int = 4000) -> void:
	var w: Dictionary = game.world
	var r := Army.rec(w, fid)
	var fights: Array = r["fights"]
	if fights.is_empty():
		return
	var by := {}
	for u in Army.members(game, fid):
		by[u.uid] = u
	# Several duels per job within a small budget: a big army opens many posts at once, and one roster scan per
	# duel (with the world clock held for each job) stalled the map.
	var started := Time.get_ticks_usec()
	while not fights.is_empty():
		_fight_one(game, fid, by)
		if Time.get_ticks_usec() - started > budget_usec: break
	if not fights.is_empty():
		_queue_fight(w, fid)

static func _fight_one(game, fid: String, by: Dictionary) -> void:
	var w: Dictionary = game.world
	var r := Army.rec(w, fid)
	var fights: Array = r["fights"]
	var fgt: Dictionary = fights[0]
	var alive: Array = (fgt["c"] as Array).filter(func(uid): return by.has(int(uid)))
	fgt["c"] = alive
	if alive.size() >= 2:
		var a: Unit = by[int(alive[0])]
		var b: Unit = by[int(alive[1])]
		var res := duel(a, b, hash([int(w.get("seed", 0)), fid, int(fgt["p"]), int(game.day), a.uid, b.uid]))
		var lose: Unit = res["lose"]
		(fgt["c"] as Array).erase(lose.uid)
		(fgt["beat"] as Array).append([lose.name, lose.dead])
		# the winner fights the next man fresh off his last fight (to the back of the line)
		(fgt["c"] as Array).erase((res["win"] as Unit).uid)
		(fgt["c"] as Array).append((res["win"] as Unit).uid)
		if lose.dead:
			Census.note_fate(w, lose.uid, "battle", "a fight for a post in the %s" % CampaignWorld.faction_name(fid))   # the census
			_bury(game, lose)
	alive = (fgt["c"] as Array).filter(func(uid): return by.has(int(uid)) and not (by[int(uid)] as Unit).dead)
	if alive.size() <= 1:
		fights.pop_front()
		if alive.size() == 1:
			var wu: Unit = by[int(alive[0])]
			var p := int(fgt["p"])
			if p < (r["posts"] as Array).size() and int(r["posts"][p]) < 0:
				assign(game, fid, p, wu, by, false, int(game.day), fgt["beat"])

## A man killed in a succession fight leaves his band now (the sweep takes him off his family row).
static func _bury(game, u: Unit) -> void:
	for wid in game.world["warbands"]:
		var wb: Dictionary = game.world["warbands"][wid]
		if (wb["units"] as Array).has(u):
			ArmsTrade.field(game, [u], {"band": wb}, wb["pos"])   # arms trade: his kit stays with his band
			(wb["units"] as Array).erase(u)
			if (wb["units"] as Array).is_empty():
				CampaignWorld.remove_warband(game, wid)
			return

## Two men fight in the real sim (tiny open map, own gear, story text off). Ends when one goes down, dies or
## yields (routs); after fight_ticks the one hurt worse (less blood) yields. Returns {win, lose, ticks, ms}.
static func duel(a: Unit, b: Unit, seed: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var sim := BattleSim.new()
	sim.setup([a], [b], seed, {"w": 6, "h": 3, "terrain": "plains", "log_moves": false, "verbose": false,
		"combat_journal":false, "max_ticks": int(Army.A()["fight_ticks"])})
	while not sim.is_over():
		sim.step()
	var win: Unit = a
	if sim.winner == 1:
		win = b
	elif sim.winner == -1:
		win = a if a.body.blood >= b.body.blood else b
	if win.dead:
		win = b if win == a else a
	return {"win": win, "lose": b if win == a else a, "ticks": sim.tick, "ms": (Time.get_ticks_usec() - t0) / 1000.0}

# ================================================================== militia trees (per band)
## Militia / guard ranks: one tree per town band, the culture's rule by score (no sim fights for town posts).
static func update_band_tree(game, town: Dictionary, wb: Dictionary, tier: String) -> void:
	var cul := TownEcon.culture_of(town["econ"])
	var rl := ranks(cul, tier)
	var span := maxi(2, int(cul.get("span", 5)))
	var units: Array = (wb["units"] as Array).filter(func(u): return not u.dead)
	var lv := levels_for(units.size(), span, maxi(0, rl.size() - 1))
	var n := offset(lv, span)
	if not wb.has("posts"):
		wb["posts"] = []
	var posts: Array = wb["posts"]
	var by := {}
	for u in units:
		by[u.uid] = u
	while posts.size() > n:
		var uid := int(posts.pop_back())
		if by.has(uid):
			(by[uid] as Unit).rank = 0
			(by[uid] as Unit).role = "troop"
	while posts.size() < n:
		posts.append(-1)
	var holds := {}
	for i in posts.size():
		if int(posts[i]) >= 0 and not by.has(int(posts[i])):
			posts[i] = -1
		if int(posts[i]) >= 0:
			holds[int(posts[i])] = true
			(by[int(posts[i])] as Unit).rank = rank_at(level_of(i, span), rl)
			(by[int(posts[i])] as Unit).role = "officer"
	for u in units:
		if not holds.has(u.uid) and u.rank > 0:
			u.rank = 0
			u.role = "troop"
	var rule := String(cul.get("rank_rule", "renown"))
	for i in posts.size():
		if int(posts[i]) >= 0:
			continue
		var cands := units.filter(func(u): return not holds.has(u.uid))
		if cands.is_empty():
			break
		var best: Unit = null
		var bv := -INF
		for u in cands:
			var v := RankRules.score(game, rule, u, String(town["faction"])) if rule != "strength" else CampaignWorld.unit_power(u)
			if v > bv:
				bv = v; best = u
		posts[i] = best.uid
		holds[best.uid] = true
		best.rank = rank_at(level_of(i, span), rl)
		best.role = "officer"
	if String(wb.get("kind","militia")) in ["militia","guard"]:
		_apply_commands(game,units,posts,lv,span,String(town["faction"]))

# ================================================================== views (UI)
## Rows of the faction's rank tree, top-down: {rank, title, count, cap, officers: [Unit]}; then the status ranks
## with their counts (no cap).
static func tree_rows(game, fid: String) -> Array:
	var r := Army.rec(game.world, fid)
	var cul := Army.cul_of_faction(fid)
	var rl := ranks(cul, "army")
	var span := maxi(2, int(cul.get("span", 5)))
	var units := Army.members(game, fid)
	var by := {}
	for u in units:
		by[u.uid] = u
	var out := []
	var posts: Array = r["posts"]
	var cp := caps(int(r["levels"]), span)
	for k in cp.size():
		var offs := []
		for i in range(offset(k, span), offset(k + 1, span)):
			if i < posts.size() and by.has(int(posts[i])):
				offs.append(by[int(posts[i])])
		out.append({"rank": rank_at(k, rl), "title": rl[rank_at(k, rl)], "count": offs.size(), "cap": cp[k], "officers": offs})
	for s in [1, 0]:
		var n := 0
		for u in units:
			if u.rank == s:
				n += 1
		out.append({"rank": s, "title": rl[s], "count": n, "cap": -1, "officers": []})
	return out

## A man's rank title in his own force ("blooded", "watch sergeant"), "" for the company and beasts.
static func rank_title(u: Unit) -> String:
	if u.faction == "player" or u.race_def().get("creature", false) or not DB.factions.has(u.faction):
		return ""
	var cul := Army.cul_of_faction(u.faction)
	var tier := "army"
	if u.title.begins_with("militia"):
		tier = "militia"
		var t: Dictionary = Game.world.get("towns", {}).get(u.home_town, {})
		if not t.is_empty():
			tier = Army.town_tier(t)
	var rl := ranks(cul, tier)
	return String(rl[clampi(u.rank, 0, rl.size() - 1)])
