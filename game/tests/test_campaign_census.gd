extends RefCounted
## The census (campaign/census.gd; town screen spec part 2 section 7, world screen part 2 tests): every death has
## exactly one cause, and births - deaths + arrived - left = the change in people for every town, every faction
## and the world, for each season's census row and for the season so far. Runs a short stretch of the world's own
## sim (130 days: four census rows), hires a recruit (people leaving), and a company man dies in battle (a death
## outside the town's count).

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)
	else:
		print("ok: ", msg)

func run(_tree: SceneTree) -> int:
	Game.new_game(2026)
	var w: Dictionary = Game.world
	var tids: Array = w["towns"].keys()
	tids.sort()
	var start_people := 0
	for tid in tids:
		var e: Dictionary = w["towns"][tid]["econ"]
		if Census.rows(e).size() != 1:
			check(false, "%s: the first census at world gen (%d rows)" % [tid, Census.rows(e).size()])
		start_people += Census.people(e)
	# a stretch of the world's own sim (the company outside it)
	CampaignWorld.presim_step(Game, 130)
	# a recruit signs on (one person leaves his town)
	var hired_town := ""
	for tid in tids:
		var t: Dictionary = w["towns"][tid]
		if not (t.get("recruits", []) as Array).is_empty():
			Game.gold = 100000
			var r: Unit = t["recruits"][0]
			var before := Census.people(t["econ"])
			var lb := Census.sum(Census.current(t["econ"])["left"])
			if Roster.hire(Game, t, r, -1) == "":
				hired_town = tid
				var gone := before - Census.people(t["econ"])
				check(Census.sum(Census.current(t["econ"])["left"]) - lb == gone, "a hired recruit is counted as leaving (%d)" % gone)
				# he dies with the company: a death with one cause, outside the town's count
				r.dead = true
				var nd := (Census._book(t["econ"])["deaths"] as Array).size()
				CampaignWorld.on_battle_result(Game, {"winner": 1, "player_units": [r], "enemy_units": []})
				var dl: Array = Census._book(t["econ"])["deaths"]
				check(dl.size() == nd + 1 and String(dl[-1][5]) == "battle" and int(dl[-1][9]) == 0,
					"a company man's death: cause battle, not in the town's count (%s)" % [dl.slice(nd)])
			break
	check(hired_town != "", "a recruit was hired somewhere")
	CampaignWorld.presim_step(Game, 6)
	# ---------------------------------------------------------------- every death: exactly one real cause
	var deaths := 0
	var by_cause := {}
	var bad := []
	for tid in tids:
		for d in Census._book(w["towns"][tid]["econ"])["deaths"]:
			deaths += 1
			var c := String(d[5])
			if not c in Census.CAUSES or c == "":
				bad.append(d)
			by_cause[c] = int(by_cause.get(c, 0)) + 1
	print("deaths recorded: %d %s" % [deaths, by_cause])
	check(deaths > 0, "people died in 136 days (%d)" % deaths)
	check(bad.is_empty(), "every death has one of the causes (%s)" % [bad.slice(0, 3)])
	# ---------------------------------------------------------------- the balance, town by town and season by season
	var broken := []
	var rows_n := 0
	for tid in tids:
		var e: Dictionary = w["towns"][tid]["econ"]
		var rs := Census.rows(e)
		for i in range(1, rs.size()):
			rows_n += 1
			var rb := Census.row_balance(rs, i)
			if not Census.adds_up(rb):
				broken.append([tid, i, rb])
		var cb := Census.balance(e)
		if not Census.adds_up(cb):
			broken.append([tid, "now", cb])
	check(rows_n >= tids.size() * 4, "four seasons of census rows per town (%d rows)" % rows_n)
	check(broken.is_empty(), "births - deaths + arrived - left = change, every town and season (%s)" % [broken.slice(0, 3)])
	# ---------------------------------------------------------------- factions and the world
	var world_b := Census.balance_of(w, tids)
	check(Census.adds_up(world_b), "the world's balance adds up %s" % world_b)
	var people_now := 0
	for tid in tids:
		people_now += Census.people(w["towns"][tid]["econ"])
	check(int(world_b["people"]) == people_now, "world people = sum of towns")
	for fid in w["factions"]:
		var ft: Array = tids.filter(func(x): return String(w["towns"][x]["faction"]) == fid)
		if ft.is_empty():
			continue
		var fb := Census.balance_of(w, ft)
		check(Census.adds_up(fb), "%s's balance adds up %s" % [fid, fb])
	# the whole run, from the first census: every row's change chains to the people now
	var chained := 0
	var total := 0
	for tid in tids:
		var rs := Census.rows(w["towns"][tid]["econ"])
		total += int(rs[0]["people"])
		for i in range(1, rs.size()):
			var rb := Census.row_balance(rs, i)
			chained += int(rb["births"]) - int(rb["deaths"]) + int(rb["arrived"]) - int(rb["left"])
		var cb := Census.balance(w["towns"][tid]["econ"])
		chained += int(cb["births"]) - int(cb["deaths"]) + int(cb["arrived"]) - int(cb["left"])
	check(total + chained == people_now, "world: first census %d + births - deaths + arrived - left = %d now (%d)" % [total, people_now, total + chained])
	# the 60-day buffers and the world deaths by cause = sum of towns
	var buf: Dictionary = Census._book(w["towns"][tids[0]]["econ"])["buf"]
	check((buf["d"] as Array).size() >= 50 and (buf["d"] as Array).size() <= 61, "60-day daily buffer (%d)" % (buf["d"] as Array).size())
	var cw := Census.causes_of(w, tids)
	var town_sum := 0
	for tid in tids:
		town_sum += Census.sum(Census.current(w["towns"][tid]["econ"])["deaths"])
	check(Census.sum(cw["now"]) == town_sum, "world deaths by cause = sum of towns")
	# the register and the land add up (town spec part 3 tests)
	for tid in tids:
		var e: Dictionary = w["towns"][tid]["econ"]
		var c := People.census(e)
		if int(c["population"]) != Census.people(e):
			check(false, "%s: register people %d = census people %d" % [tid, int(c["population"]), Census.people(e)])
		var ls := TownEcon.land_summary(e)
		var fam_ac := 0
		for f in e["fams"]:
			if not f.get("gone", false) and not f.get("estate", false):
				fam_ac += Families.acres(f)
		if int(ls["families"]) != fam_ac or int(ls["estate"]) != Families.acres(e["fams"][0]):
			check(false, "%s: acres in Land = family acres + state acres (%d+%d vs %d+%d)" % [tid, int(ls["families"]), int(ls["estate"]), fam_ac, Families.acres(e["fams"][0])])
	print("register people = census people and land acres = family + state acres, every town checked")
	# The standing roster includes off-duty reserves and active/drilling militia.
	# Guards have a separate roster. Every living member must retain its own real
	# town/family person, and every active-household service record must map back.
	var miss := []
	for tid in tids:
		var t: Dictionary = w["towns"][tid]
		var on := {}
		for u in Militia.units_of(Game, tid):
			if on.has(u.uid):
				miss.append("%s: duplicate militia UID %d" % [tid, u.uid])
			on[u.uid] = u
			if u.family < 0 or u.home_town != tid:
				miss.append("%s: militia UID %d has invalid home/family" % [tid, u.uid])
				continue
			var f := People.fam_of(t, u.family)
			var p: Array = Persons.by_uid(f, u.uid) if not f.is_empty() else []
			if f.get("gone", false) or p.is_empty() or not String(p[4]) in ["reserve", "militia"]:
				miss.append("%s: militia UID %d lacks its real service record" % [tid, u.uid])
		var registered := {}
		for f in t["econ"]["fams"]:
			if f.get("gone", false):
				continue
			for p in f.get("pp", []):
				if not String(p[4]) in ["reserve", "militia"]:
					continue
				var uid := int(p[5])
				if uid < 0 or not on.has(uid):
					miss.append("%s: service person %d lacks a living militia unit" % [tid, int(p[0])])
					continue
				var u: Unit = on[uid]
				if registered.has(uid) or u.family != int(f["id"]) or u.home_town != tid:
					miss.append("%s: service UID %d has duplicate/wrong family binding" % [tid, uid])
				registered[uid] = true
	check(miss.is_empty(), "roster <-> register both ways (%d misses: %s)" % [miss.size(), miss.slice(0, 4)])
	# save and load keep the record
	Game.save_game()
	var keep := Census.rows(w["towns"][tids[0]]["econ"]).size()
	Game.load_game()
	check(Census.rows(Game.world["towns"][tids[0]]["econ"]).size() == keep, "census rows survive save/load")
	check(Census.adds_up(Census.balance(Game.world["towns"][tids[0]]["econ"])), "balance adds up after load")
	return fails
