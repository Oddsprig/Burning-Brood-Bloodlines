extends RefCounted
## Land plots (docs/specs/barge/07-land-map.md section 6; addendum A test): plot acres = every land total, on
## world gen and on every day; seizures and forced sales move whole plots with a history line and change the
## OWNER overlay the same day; odd-acre moves keep the books exact and the grid whole; felled woods regrow only
## over time; clearing needs real labour days; every town has its keep, hall, barracks, armory, granary, shelter
## and jail as state plots, with register persons as residents and staff; save/load; the daily pass stays cheap.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _towns() -> Array:
	var ids: Array = Game.world["towns"].keys()
	ids.sort()
	return ids.map(func(i): return Game.world["towns"][i])

## Plot acres by owner and crop against the families' and estate's land, and against TownEcon.land_summary.
func _books_match(t: Dictionary) -> String:
	var e: Dictionary = t["econ"]
	var tot := Plots.totals(e)
	var oc: Dictionary = tot["own_crop"]
	for f in e["fams"]:
		var want: Dictionary = {} if f.get("gone", false) else f["land"]
		var have: Dictionary = oc.get(int(f["id"]), {})
		for c in want:
			if int(want[c]) != int(have.get(c, 0)):
				return "%s fam %d %s: land %d plots %d" % [t["name"], int(f["id"]), c, int(want[c]), int(have.get(c, 0))]
		for c in have:
			if int(have[c]) != int(want.get(c, 0)):
				return "%s fam %d %s: plots %d land %d" % [t["name"], int(f["id"]), c, int(have[c]), int(want.get(c, 0))]
	var s := TownEcon.land_summary(e)
	var fam_sum := 0
	for o in oc:
		if int(o) > 0:
			for c in oc[o]:
				fam_sum += int(oc[o][c])
	if fam_sum != int(s["families"]):
		return "%s families %d vs plots %d" % [t["name"], int(s["families"]), fam_sum]
	if Plots.acres_of(e, 0) != int(s["estate"]):
		return "%s estate %d vs plots %d" % [t["name"], int(s["estate"]), Plots.acres_of(e, 0)]
	if int(tot["land"]) + int(tot["use_ac"][Plots.COMMON]) != int(s["territory"]):
		return "%s territory %d vs plots %d + common %d" % [t["name"], int(s["territory"]), int(tot["land"]), int(tot["use_ac"][Plots.COMMON])]
	for c in e["land"]:
		if int(e["land"][c]) != int(tot["crop"].get(c, 0)):
			return "%s town %s %d vs plots %d" % [t["name"], c, int(e["land"][c]), int(tot["crop"].get(c, 0))]
	return ""

## Every plot sits in exactly one grid cell and the grid points back at it; acres 1..5 on farm plots.
func _grid_ok(P: Dictionary) -> String:
	var S := int(P["gw"])
	var seen := {}
	for ci in (P["g"] as PackedInt32Array).size():
		var pid := int(P["g"][ci])
		if pid < 0:
			continue
		if seen.has(pid):
			return "plot %d twice in the grid" % pid
		seen[pid] = true
		if int(P["x"][pid]) != ci % S or int(P["y"][pid]) != ci / S:
			return "plot %d at %d,%d but grid cell %d" % [pid, int(P["x"][pid]), int(P["y"][pid]), ci]
	if seen.size() != Plots.count(P):
		return "grid holds %d of %d plots" % [seen.size(), Plots.count(P)]
	for i in Plots.count(P):
		if Plots.LAND_USES.has(int(P["use"][i])) and (int(P["ac"][i]) < 1 or int(P["ac"][i]) > Plots.ACRES):
			return "plot %d has %d acres" % [i, int(P["ac"][i])]
	return ""

func run(_tree: SceneTree) -> int:
	Game.new_game(4711)
	var towns := _towns()
	# ---------------------------------------------------------------- world gen
	for t in towns:
		var P := Plots.of(t)
		check(not P.is_empty(), "%s has plots" % t["name"])
		var m := _books_match(t)
		check(m == "", "world gen books: " + m)
		var g := _grid_ok(P)
		check(g == "", "%s grid: %s" % [t["name"], g])
		check(Plots.count(P) <= Plots.PLOT_CAP + 200, "%s plot count %d near the cap" % [t["name"], Plots.count(P)])
		# the town's own buildings
		var kinds := {}
		for b in P["bld"]:
			var p := int(b["p"])
			check(p >= 0 and int(P["use"][p]) == Plots.STATE and int(P["own"][p]) == Plots.TOWN, "%s %s is a state plot" % [t["name"], b["k"]])
			kinds[String(b["k"])] = true
		for k in ["keep", "hall", "barracks", "armory", "granary", "shelter", "jail"]:
			check(kinds.has(k), "%s has its %s" % [t["name"], k])
		if t.get("capital", false) or String(t.get("specialty", "")) == "mining":
			check(kinds.has("mint"), "%s (seat or mining) has a mint" % t["name"])
	# residents and staff are register persons
	var barracks_people := 0
	var keep_people := 0
	for t in towns:
		var e: Dictionary = t["econ"]
		for b in Plots.buildings(Game, t):
			for p in (b["residents"] as Array) + (b["staff"] as Array) + ([b["runner"]] if not (b["runner"] as Dictionary).is_empty() else []):
				var f: Dictionary = e["fams"][int(p["fid"])]
				check(not Persons.by_pid(f, int(p["pid"])).is_empty(), "%s %s: %s is a register person" % [t["name"], b["kind"], p["name"]])
			if b["kind"] == "barracks":
				barracks_people += (b["residents"] as Array).size()
				check((b["residents"] as Array).size() <= Militia.units_of(Game, String(t["id"])).size(), "%s barracks holds no more than its militia" % t["name"])
			if b["kind"] == "keep":
				keep_people += (b["residents"] as Array).size()
				check(not (b["runner"] as Dictionary).is_empty(), "%s keep has its head" % t["name"])
	check(barracks_people > 0, "barracks residents are the militia (%d)" % barracks_people)
	check(keep_people > 0, "the head's households live in the keeps (%d)" % keep_people)
	# ---------------------------------------------------------------- a seizure: owner, history, overlay, same day
	var t0: Dictionary = towns[0]
	var e0: Dictionary = t0["econ"]
	var victim: Dictionary = {}
	for f in e0["fams"]:
		if not f.get("estate", false) and not f.get("gone", false) and Families.acres(f) >= 7:
			victim = f
			break
	check(not victim.is_empty(), "a landholding family to seize from")
	if not victim.is_empty():
		var P0 := Plots.of(t0)
		var crop: String = (victim["land"] as Dictionary).keys()[0]
		var mine := []
		for i in Plots.count(P0):
			if int(P0["own"][i]) == int(victim["id"]) and Plots.LAND_USES.has(int(P0["use"][i])) and P0["crops"][int(P0["sub"][i])] == crop:
				mine.append(i)
		var pick: int = mine[0]
		var at := Vector2i(int(P0["x"][pick]) * LandMap.TILE + 1, int(P0["y"][pick]) * LandMap.TILE + 1)
		var before: Color = (LandMap.compose(t0, "OWNER")["img"] as Image).get_pixelv(at)
		for f in e0["fams"]:   # nobody can buy: the head takes it (the treasury pays)
			if f != victim and not f.get("estate", false):
				f["purse"] = 0.0
		e0["treasury"] = 1.0e6
		victim["debt"] = 500.0
		var n_all := int(victim["land"][crop])
		var got := Loans._sell_holding(e0, victim, "land", crop, n_all, float(TownEcon.data()["land"]["acre_price"]))
		check(got > 0.0, "the forced sale went through")
		check(int(P0["own"][pick]) == Plots.TOWN, "seized plot now the town's")
		check(int(P0["fl"][pick]) & Plots.F_SEIZED != 0, "seized plot flagged")
		var hl := Plots.hist_lines(P0, pick)
		check(not hl.is_empty() and String(hl[-1]).to_lower().contains("seized by the town") and String(hl[-1]).contains(victim["name"]), "seizure history line: %s" % str(hl))
		var after: Color = (LandMap.compose(t0, "OWNER")["img"] as Image).get_pixelv(at)
		check(not before.is_equal_approx(after), "OWNER overlay changed the same day (%s -> %s)" % [before, after])
		var spr: Color = LandMap.sprite(LandMap.sprite_key(e0, P0, pick, Game.day)).get_pixel(1, 1)
		var white := spr.blend(Color(1, 1, 1, 0.55))
		check(absf(after.r - white.r) < 0.03 and absf(after.g - white.g) < 0.03 and absf(after.b - white.b) < 0.03,
			"seized plot shows as town (white) land (%s vs %s)" % [after, white])
		check(Plots.for_sale(P0, pick), "seized land is offered for sale")
		check(_books_match(t0) == "", "books after seizure: " + _books_match(t0))
		# a forced sale to a family that can pay
		var buyer: Dictionary = {}
		for f in e0["fams"]:
			if f != victim and not f.get("estate", false) and not f.get("gone", false) and float(Families.adults(f)) - Families.need_hands(f) >= 0.5:
				buyer = f
				break
		var seller: Dictionary = {}
		for f in e0["fams"]:
			if f != victim and f != buyer and not f.get("estate", false) and not f.get("gone", false) and Families.acres(f) >= 3:
				seller = f
				break
		if not buyer.is_empty() and not seller.is_empty():
			buyer["purse"] = 1.0e5
			buyer["debt"] = 0.0
			seller["debt"] = 90.0
			var c2: String = (seller["land"] as Dictionary).keys()[0]
			var got2 := Loans._sell_holding(e0, seller, "land", c2, 3, float(TownEcon.data()["land"]["acre_price"]))
			check(got2 > 0.0, "forced sale to a family")
			var found := false
			for i in Plots.count(P0):
				if int(P0["own"][i]) == int(buyer["id"]):
					for l in Plots.hist_lines(P0, i):
						if String(l).contains("for their debt"):
							found = true
			check(found, "forced-sale history line on the buyer's plot")
			check(_books_match(t0) == "", "books after forced sale: " + _books_match(t0))
	# ---------------------------------------------------------------- odd acres, many times: books and grid stay whole
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var t1: Dictionary = towns[1]
	var e1: Dictionary = t1["econ"]
	var live: Array = (e1["fams"] as Array).filter(func(f): return not f.get("gone", false))
	var n0 := Plots.count(Plots.of(t1))
	for k in 400:
		var a: Dictionary = live[rng.randi() % live.size()]
		var b: Dictionary = live[rng.randi() % live.size()]
		if a == b or (a["land"] as Dictionary).is_empty():
			continue
		var cs: Array = (a["land"] as Dictionary).keys()
		var c3: String = cs[rng.randi() % cs.size()]
		Families.move_land(e1, a, b, c3, rng.randi_range(1, mini(23, int(a["land"][c3]))))
		if k % 40 == 0:
			var m2 := _books_match(t1)
			check(m2 == "", "books during 400 random moves: " + m2)
	check(_books_match(t1) == "", "books after 400 random moves: " + _books_match(t1))
	check(_grid_ok(Plots.of(t1)) == "", "grid after 400 random moves: " + _grid_ok(Plots.of(t1)))
	print("400 odd-acre moves: plots %d -> %d, drift %d" % [n0, Plots.count(Plots.of(t1)), int(Plots.of(t1)["drift"])])
	check(int(Plots.of(t1)["drift"]) == 0, "no drift between plots and land records")
	# ---------------------------------------------------------------- felling and regrowth
	var t2: Dictionary = towns[2]
	var e2: Dictionary = t2["econ"]
	var P2 := Plots.of(t2)
	var made := int(e2["led"]["made"].get("wood", 0))
	P2["wood_seen"] = made
	var nearest := -1
	var woods := []
	for i in Plots.count(P2):
		if int(P2["use"][i]) == Plots.WOOD and Plots.wood_stage(P2, i) in ["dense", "thin"]:
			woods.append(i)
	check(not woods.is_empty(), "the town has standing woods")
	e2["led"]["made"]["wood"] = made + 50000   # the cutters bring in a great deal of wood
	Plots.fell(e2, P2, Game.day)
	var felled := []
	for i in woods:
		if Plots.wood_stage(P2, i) == "felled":
			felled.append(i)
	check(not felled.is_empty(), "wood cut comes out of the woods (%d felled)" % felled.size())
	if not felled.is_empty():
		var fp: int = felled[0]
		check(String(Plots.hist_lines(P2, fp)[-1]).contains("Felled"), "felling history line")
		var s0 := float(P2["st"][fp])
		Plots.regrow(P2, Game.day, 7)
		check(absf(float(P2["st"][fp]) - (s0 + Plots.REGROW_DAY * 7.0)) < 0.0001, "a week's regrowth is a week's worth")
		check(Plots.wood_stage(P2, fp) == "felled", "a felled wood is still felled after a week")
		Plots.regrow(P2, Game.day, 120)
		check(Plots.wood_stage(P2, fp) in ["felled", "regrowing"], "still not wood after a year (%s)" % Plots.wood_stage(P2, fp))
		Plots.regrow(P2, Game.day, 400)
		check(Plots.wood_stage(P2, fp) in ["thin", "regrowing"] and float(P2["st"][fp]) < Plots.DENSE, "thin wood again only after years")
	# ---------------------------------------------------------------- clearing needs real labour days
	e2["led"]["made"]["wood"] = int(e2["led"]["made"]["wood"]) + 50000
	Plots.fell(e2, P2, Game.day)
	var cl := -1
	for i in Plots.count(P2):
		if int(P2["use"][i]) == Plots.WOOD and Plots.wood_stage(P2, i) == "felled":
			cl = i
			break
	check(cl >= 0, "a felled plot to clear")
	if cl >= 0:
		var wb: Dictionary = e2["biz"][int(e2["works_biz"])]
		var w0 := int(wb["workers"])
		wb["workers"] = 0
		P2["clear"] = -1
		Plots.clear_step(e2, P2, Game.day, 30)
		check(int(P2["clear"]) == -1 or float(P2["cl_done"]) == 0.0, "no crew, no clearing")
		Plots.start_clearing(e2, P2, cl, Game.day)
		var need := Plots.CLEAR_DAYS_ACRE * float(P2["ac"][cl])
		var est_before := int(e2["fams"][0]["land"].get("grain", 0))
		var terr_before := int(e2["territory"])
		Plots.work_clearing(e2, P2, need * 0.5, Game.day)
		check(int(P2["use"][cl]) == Plots.WOOD, "half the worker-days: still stumps")
		wb["workers"] = 4
		Plots.clear_step(e2, P2, Game.day, 7)
		var done_after := float(P2["cl_done"])
		check(absf(done_after - (need * 0.5 + 4.0 * Plots.CLEAR_SHARE * 7.0)) < 0.01 or int(P2["use"][cl]) == Plots.FIELD, "a week of a crew of 4 adds their days")
		Plots.work_clearing(e2, P2, need, Game.day)
		check(int(P2["use"][cl]) == Plots.FIELD and int(P2["own"][cl]) == Plots.TOWN, "cleared: a field of the town")
		check(int(e2["fams"][0]["land"].get("grain", 0)) == est_before + int(P2["ac"][cl]), "the estate holds the cleared acres")
		check(int(e2["territory"]) == terr_before + int(P2["ac"][cl]), "the territory grew by them")
		check(_books_match(t2) == "", "books after clearing: " + _books_match(t2))
		wb["workers"] = w0
	# ---------------------------------------------------------------- the card
	for t in [t0, t1]:
		var P3 := Plots.of(t)
		for i in range(0, Plots.count(P3), 37):
			var c := Plots.card(Game, t, i)
			check(String(c["title"]) != "" and not (c["lines"] as Array).is_empty(), "%s plot %d has a card" % [t["name"], i])
	# ---------------------------------------------------------------- every day: the books match (a stretch of the real sim)
	var bad := ""
	var tday := 0.0
	for d in 35:
		var t00 := Time.get_ticks_usec()
		CampaignWorld.presim_step(Game, 1)
		tday += float(Time.get_ticks_usec() - t00)
		for t in towns:
			var m3 := _books_match(t)
			if m3 != "" and bad == "":
				bad = "day %d: %s" % [d, m3]
	check(bad == "", "books match on every day: " + bad)
	for t in towns:
		check(_grid_ok(Plots.of(t)) == "", "%s grid after 35 days: %s" % [t["name"], _grid_ok(Plots.of(t))])
	# ---------------------------------------------------------------- the daily pass is cheap
	var us := 0
	var worst := 0
	for d in 14:
		var a0 := Time.get_ticks_usec()
		Plots.daily(Game, 1000 + d)
		var dt := Time.get_ticks_usec() - a0
		us += dt
		worst = maxi(worst, dt)
	print("plots daily pass: avg %.2f ms, worst %.2f ms (%d towns); a whole sim day avg %.1f ms" % [float(us) / 14000.0, float(worst) / 1000.0, towns.size(), tday / 35000.0])
	check(float(worst) / 1000.0 < 25.0, "plots daily pass worst %.2f ms < 25 ms" % (float(worst) / 1000.0))
	# ---------------------------------------------------------------- save / load
	var counts := towns.map(func(t): return Plots.count(Plots.of(t)))
	var h0 := Plots.hist_lines(Plots.of(t0), 0)
	Game.save_game()
	Game.load_game()
	var towns2 := _towns()
	for k in towns2.size():
		var P4 := Plots.of(towns2[k])
		check(P4["x"] is PackedInt32Array and P4["st"] is PackedFloat32Array, "columns packed again after load")
		check(Plots.count(P4) == int(counts[k]), "%s keeps its %d plots after load" % [towns2[k]["name"], int(counts[k])])
		check(_books_match(towns2[k]) == "", "books after load: " + _books_match(towns2[k]))
		check(_grid_ok(P4) == "", "grid after load: " + _grid_ok(P4))
	check(Plots.hist_lines(Plots.of(towns2[0]), 0) == h0, "history survives the save")
	CampaignWorld.presim_step(Game, 3)
	for t in towns2:
		check(_books_match(t) == "", "books after load and 3 days: " + _books_match(t))
	return fails
