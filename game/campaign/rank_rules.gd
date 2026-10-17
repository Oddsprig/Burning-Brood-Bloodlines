class_name RankRules
extends RefCounted
## Rank rules per faction (economy spec 2, section 4; culture row field rank_rule). Adding a rule = one score
## function + one match arm + the data name. Kill renown is one weighted term (army.renown_weight) in every
## weighted rule; strength (orcs) is decided by the fight alone (campaign/army.gd fight_step).
##   strength  free-for-all in the combat sim (army.gd)
##   wealth    the richest family's candidate gets the post; his family buys the commission from the treasury
##   politics  Social awareness + Negotiator + Leader, plus favour with the head
##   renown    the men who report to the post vote, weighted by battles survived; a close vote -> duel to yield
##   cunning   a backstab roll; losers may die
##   lineage   seniority (battles, age), then bloodline (a named house, the head's own family)
## Weights are ours [tuned].

static func renown_term(u: Unit) -> float:
	return float(Army.A()["renown_weight"]) * u.renown

static func _fam(u: Unit) -> Dictionary:
	return People.fam_of(Game.world.get("towns", {}).get(u.home_town, {}), u.family)

static func score(game, rule: String, u: Unit, fid: String) -> float:
	var s := renown_term(u)
	match rule:
		"wealth":
			var f := _fam(u)
			if not f.is_empty():
				s += float(f["purse"]) / (50.0 * TownEcon.COIN) + float(Families.acres(f)) * 0.05
		"politics":
			var head := String(game.world["factions"].get(fid, {}).get("war_leader", {}).get("name", fid))
			var favour := float(absi(hash([head, u.uid])) % 100) / 100.0 * 2.0
			s += float(u.mind.get("SOC", 1000)) / 1000.0 * 2.0 + u.skill("negotiator") * 0.3 + u.skill("leader") * 0.4 + favour
		"lineage":
			var f2 := _fam(u)
			s += float(u.battles) + float(u.age) / 10.0
			if not f2.is_empty() and f2.get("named", false):
				s += 1.0
			var t: Dictionary = game.world["towns"].get(u.home_town, {})
			if TownEcon.has_econ(t) and int(t["econ"]["head"]["fam"]) == u.family:
				s += 3.0
		"cunning":
			s += float(u.attr("AGI")) / 1000.0 + float(u.mind.get("SOC", 1000)) / 1000.0 + u.skill("dagger") * 0.2
		"renown":
			s += float(u.battles) * 0.5
		_:
			s += CampaignWorld.unit_power(u)
	return s

## The winner among the candidates for post p (side effects: commissions paid, backstab deaths, duels).
static func pick(game, fid: String, rule: String, p: int, cands: Array, by: Dictionary, rng: RandomNumberGenerator, prehistory: bool) -> Unit:
	if cands.is_empty():
		return null
	if cands.size() == 1:
		return cands[0]
	match rule:
		"renown":
			return _vote(game, fid, p, cands, by, rng, prehistory)
		"cunning":
			return _backstab(game, fid, cands, rng, prehistory)
	var best: Unit = null
	var bv := -INF
	for u in cands:
		var v := score(game, rule, u, fid) + rng.randf() * 0.01
		if v > bv:
			bv = v; best = u
	if rule == "wealth" and not prehistory:
		_commission(game, fid, p, best)
	return best

## Wealth: the commission (army.commission x the post's level from the bottom + 1) leaves the family purse for
## the faction treasury, as far as the purse goes.
static func _commission(game, fid: String, p: int, u: Unit) -> void:
	var f := _fam(u)
	var fac: Dictionary = game.world["factions"].get(fid, {})
	if f.is_empty() or fac.is_empty():
		return
	var r := Army.rec(game.world, fid)
	var span := maxi(2, int(Army.cul_of_faction(fid).get("span", 5)))
	var lvl := int(r["levels"]) - Army.level_of(p, span)
	var price := float(Army.A()["commission"]) * float(lvl)
	var paid := minf(price, maxf(0.0, float(f["purse"])))
	f["purse"] = float(f["purse"]) - paid
	fac["treasury"] = float(fac.get("treasury", 0.0)) + paid
	Families.add_hist(f, "Paid %d coins for %s's commission." % [int(paid), u.name], float(game.day))

## Renown: every man under the post votes (weight 1 + battles survived) for the candidate he rates best
## (renown + battles, a personal leaning); when the top two are within 10% they duel to yield in the sim.
static func _vote(game, fid: String, p: int, cands: Array, by: Dictionary, rng: RandomNumberGenerator, prehistory: bool) -> Unit:
	var votes := {}
	for c in cands:
		votes[c.uid] = 0.0
	var voters := []
	for uid in by:
		var v: Unit = by[uid]
		if not cands.has(v):
			voters.append(v)
	if voters.is_empty():
		voters = cands
	for v in voters:
		var best: Unit = null
		var bv := -INF
		for c in cands:
			if c == v:
				continue
			var s := score(game, "renown", c, fid) + rng.randf() * 3.0
			if s > bv:
				bv = s; best = c
		if best != null:
			votes[best.uid] = float(votes[best.uid]) + 1.0 + float(v.battles)
	var order := cands.duplicate()
	order.sort_custom(func(a, b): return float(votes[a.uid]) > float(votes[b.uid]))
	var top: Unit = order[0]
	var second: Unit = order[1]
	if prehistory or float(votes[second.uid]) < float(votes[top.uid]) * 0.9:
		return top
	var res := Army.duel(top, second, rng.randi())   # contested: a duel to yield
	var lose: Unit = res["lose"]
	if lose.dead:
		Army._bury(game, lose)
	return res["win"]

## Cunning: everyone rolls; the best roll takes the post, and each loser may get a knife in the back.
static func _backstab(game, fid: String, cands: Array, rng: RandomNumberGenerator, prehistory: bool) -> Unit:
	var best: Unit = null
	var bv := -INF
	for u in cands:
		var v := score(game, "cunning", u, fid) * rng.randf_range(0.5, 1.5)
		if v > bv:
			bv = v; best = u
	if prehistory:
		return best
	for u in cands:
		if u != best and rng.randf() < float(Army.A()["backstab_death"]):
			u.dead = true
			Census.note_fate(game.world, u.uid, "murdered", "a knife in the back over a post in the %s" % CampaignWorld.faction_name(fid))   # the census
			Army._bury(game, u)
			Army._hist(game, fid, "%s was found with a knife in his back." % u.name)
	return best
