extends RefCounted
## Hard times (Douglas, economy spec 2 additions): HOMELESS (the head takes the house for debt, or it falls down;
## evicted renters) and DESTITUTE families raise hardship; the town shelter (poorhouse) feeds broth out of real
## granary/market stock at the treasury's cost and weakens those who live on it alone (real food heals); casual
## work goes to the homeless first; the way back (rent, buy) is paid for and can fail; recruits from hard-up rows
## are cheaper and weaker; backstories are built from each family's real history, different histories ->
## different, history-true text; gold conserved through it all.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	_test_homeless_and_shelter()
	_test_backstories()
	_test_conserved()
	return fails

func _town(w: Dictionary) -> Dictionary:
	var ids: Array = w["towns"].keys()
	ids.sort()
	for tid in ids:
		if String(w["towns"][tid]["faction"]) == "middle_kingdom":
			return w["towns"][tid]
	return w["towns"][ids[0]]

## A landless family of the town with one home and an old unpaid debt (the head will take the house).
func _debtor(e: Dictionary, day: float) -> Dictionary:
	for f in e["fams"]:
		if f.get("estate", false) or f["gone"] or not (f["owns"] as Array).is_empty() or Families.adults(f) < 1:
			continue
		var estate: Dictionary = e["fams"][0]
		for c in f["land"].keys():
			Families.move_land(e, f, estate, c, int(f["land"][c]))
		for a in f["herd"].keys():
			Families.move_herd(e, f, estate, a, int(f["herd"][a]))
		f["homes"] = 1
		f["purse"] = 0.0
		f["debt"] = 500.0 * TownEcon.COIN   # more than a week's wages can clear (coinage x20)
		f["loan_day"] = day - 60.0
		# economy (head's loans): already behind on a steep instalment; one more miss and he must sell
		f["ln"] = {"rate": 0.02, "pay": 250.0 * TownEcon.COIN, "miss": int(TownEcon.data()["loans"]["default_after"]) - 1, "lent": 500.0 * TownEcon.COIN, "int": 0.0, "sold": []}
		f["tax_season"] = int(e["tax"]["season"])
		# barge part 2 section 6: hunger is the family's own larder now; this test is about the debt and the house, so
		# the family has just eaten its last week's food (a family 40 days without food would starve or flee first)
		f["last"] = day - 7.0
		f["store"]["food"] = 7.0
		return f
	return {}

func _test_homeless_and_shelter() -> void:
	Game.new_game(6060)
	var w: Dictionary = Game.world
	var town := _town(w)
	var e: Dictionary = town["econ"]
	Game.day = 40.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var f := _debtor(e, Game.day)
	check(not f.is_empty(), "no family to test")
	var h0 := Families.hardship(f)
	var est0 := int(e["fams"][0]["homes"])
	Families.turn(Game, town, e, f, Game.day, rng)
	# economy (head's loans): a landless debtor past the loan term sells what he has, the house last (to the market
	# as a home for sale, or to the head when the market cannot pay), and is out on the street
	check(int(f["homes"]) == 0 and f.has("hl") and String(f["hl"]["how"]) in ["head", "debt"], "the debtor did not lose the house for the debt")
	check(int(e["fams"][0]["homes"]) == est0 + 1 or int(e["stock"].get("home", 0)) > 0, "the house was not sold (market or town estate)")
	check(Shelter.destitute(f) and Families.hardship(f) > h0 + 0.5, "homeless + broke + landless is not destitute / hardship did not rise (%.2f -> %.2f)" % [h0, Families.hardship(f)])
	check(f.get("shel", false) and int(e["shel_n"]) >= Families.people(f), "the homeless family found no place in the shelter")
	var codes: Array = (f.get("ev", []) as Array).map(func(x): return str(x[1]))
	check((codes.has("home_head") or codes.has("sold_house")) and codes.has("shelter"), "history events missing: %s" % str(codes))
	var lines := Families.describe(town, e, f)
	check(" ".join(PackedStringArray(lines)).contains("DESTITUTE"), "the family record does not show DESTITUTE")
	print("  ", lines[1])
	# the shelter: broth out of the granary, the keepers and firewood paid by the treasury
	f["store"]["food"] = 0.0
	Shelter.eat(town, e, f, 7.0)   # nothing of their own left: broth
	Shelter.weekly(Game, town, e)
	var gr0 := int(e["granary"]) + int(e["stock"]["grain"])
	var tr0 := float(e["treasury"])
	Shelter.daily(town, e)
	check(int(e["broth_n"]) > 0 and int(e["granary"]) + int(e["stock"]["grain"]) < gr0, "the shelter served no broth from the granary")
	check(float(e["treasury"]) < tr0, "the treasury paid nothing for the shelter")
	# broth alone weakens; real food heals
	for i in 4:
		f["store"]["food"] = 0.0
		Shelter.eat(town, e, f, 7.0)
	var wk := float(f.get("weak", 0.0))
	check(wk > 0.2, "broth alone did not weaken them (%.2f)" % wk)
	f["store"]["food"] = 30.0
	Shelter.eat(town, e, f, 7.0)
	check(float(f.get("weak", 0.0)) < wk, "real food did not ease the weakness")
	# casual work goes to the homeless first, and is paid by the treasury / market
	Shelter.casual_caps(Game, town, e)
	var took := Shelter.claim_casual(e, f, 2)
	check(took > 0 and f.has("cj"), "no casual work for the homeless (caps %s)" % str(e["cjcap"]))
	var p0 := float(f["purse"])
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var g0 := float(e["treasury"]) + float(mkt["till"])
	Shelter.pay_casual(e, f, 7.0)
	var earned := float(f["purse"]) - p0
	check(earned > 0.0 and absf((g0 - float(e["treasury"]) - float(mkt["till"])) - earned) < 0.01, "casual wages not paid / not conserved")
	# the way back: two weeks' rent in hand and an empty estate house -> renting; rent unpaid -> evicted again
	f["purse"] = Shelter.rent_week(e) * 2.0 + 10.0 * TownEcon.COIN   # coinage: the barge rent, coins
	e["fams"][0]["homes"] = int(e["fams"][0]["homes"]) + 1   # an empty town house to rent (the debtor's own went to the market)
	Shelter.turn(town, e, f, Game.day + 7.0)
	check(int(f["homes"]) == 1 and int(f.get("rent", 0)) == 1 and not f.has("hl") and not f.get("shel", false), "a family with rent money did not rent a house")
	f["purse"] = 0.0
	Shelter.turn(town, e, f, Game.day + 14.0)
	check(int(f["homes"]) == 0 and f.has("hl") and String(f["hl"]["how"]) == "evicted", "unpaid rent did not end in eviction")
	# recruits from such a row: cheaper, weaker, and the card says why
	f["weak"] = 0.8
	var txt := Backstory.recruit_text(town, e, f, "Wil")
	print("  recruit card: ", txt)
	check(txt.contains("took the house") or txt.contains("took the roof") or txt.contains("the house itself"), "the card does not say the house was taken")
	check(txt.contains("broth") or txt.contains("poorhouse") or txt.contains("nothing left to lose") or txt.contains("sign for bread") or txt.contains("sold everything") or txt.contains("house went for the debt"), "the card does not say why he signs on now")

func _test_backstories() -> void:
	Game.new_game(6061)
	var w: Dictionary = Game.world
	var town := _town(w)
	var e: Dictionary = town["econ"]
	var a: Dictionary = e["fams"][3]
	var b: Dictionary = e["fams"][4]
	a["ev"] = []; b["ev"] = []
	Families.event(a, "loan", [12, "reeve"], 35.0)
	Families.event(a, "land", ["8 acres of wheat", "reeve"], 70.0)
	Families.event(a, "hunger", [3], 100.0)
	a["debt"] = 30.0
	Families.event(b, "died", ["Aldo " + String(b["name"]), "militia", "m"], 50.0)
	Families.event(b, "unpaid", ["the Tull brewer"], 80.0)
	b["unpaid"] = 2
	var ta := Backstory.recruit_text(town, e, a, "Wil")
	var tb := Backstory.recruit_text(town, e, b, "Wil")
	print("  A: ", ta)
	print("  B: ", tb)
	check(ta != tb, "different histories, same story")
	check(ta.contains("12") and ta.contains("8 acres of wheat") and ta.contains("reeve"), "story A not true to its history")
	# (Douglas: a recruit card is about him; a relative's death is told on the family record, not his card)
	check(tb.contains("Tull brewer") and not tb.contains("Aldo"), "story B not true to its history")
	check(Backstory.family_text(town, e, b).contains("defending the town"), "family record story missing how Aldo died")
	# time order: the loan before the land
	check(ta.find("12") < ta.find("8 acres"), "events out of time order")
	var ns := ta.count(". ") + 1
	check(ns >= 2 and ns <= 6, "story length %d sentences" % ns)
	# same family, same text
	check(Backstory.recruit_text(town, e, a, "Wil") == ta, "a family's story is not stable")
	# family record story
	check(Backstory.family_text(town, e, b).contains("Aldo"), "family record story missing the death")
	# a pool from the town: every family recruit has a history story, ending in a reason
	var pool := Recruits.generate_pool(town, RandomNumberGenerator.new())
	for r in pool:
		check(r.backstory.length() > 40, "a recruit without a story: %s" % r.backstory)

func _gold(w: Dictionary) -> float:
	var g := 0.0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t):
			g += TownEcon.town_gold(t["econ"])
	for fid in w["factions"]:
		g += float(w["factions"][fid].get("treasury", 0.0))
	return g

## The economy alone (no forces) for 40 days with a dozen families thrown out on the street: gold conserved.
func _test_conserved() -> void:
	Game.new_game(6062)
	var w: Dictionary = Game.world
	for wid in w["warbands"].keys():
		CampaignWorld.remove_warband(Game, wid)
	var town := _town(w)
	var e: Dictionary = town["econ"]
	var n := 0
	for f in e["fams"]:
		if not f.get("estate", false) and n < 12 and Families.acres(f) == 0:
			e["fams"][0]["homes"] = int(e["fams"][0]["homes"]) + int(f["homes"])
			f["homes"] = 0
			f["purse"] = 0.0
			Shelter.lost_home(e, f, "ruin", 1.0)
			n += 1
	var g0 := _gold(w)
	var gone0 := TownEcon.gold_gone
	var L0: Dictionary = (w["coin"] as Dictionary).duplicate()   # coinage: coin cast, melted and drained meanwhile
	var sheltered := 0; var back := 0
	for d in range(1, 41):
		Game.day = float(d)
		var work := []
		w["work"] = work
		TownEcon.queue_day(w, d)
		while not work.is_empty():
			var job: Array = work.pop_front()
			TownEcon.do_job(Game, job)
	for f in e["fams"]:
		if f.get("shel", false):
			sheltered += 1
	for f in e["fams"]:
		for ev in f.get("ev", []):
			if str(ev[1]) == "housed":
				back += 1
	var g1 := _gold(w)
	var gone := TownEcon.gold_gone - gone0
	var L1: Dictionary = w["coin"]
	var minted := (float(L1["cast"]) - float(L0["cast"])) - (float(L1["melted"]) - float(L0["melted"])) - (float(L1["drained"]) - float(L0["drained"]))
	check(absf(g1 + gone - g0 - minted) < 0.01 * maxf(1.0, g0 / 1000.0), "coin not conserved with the shelter: %.2f -> %.2f (+%.2f gone, %+.2f cast - melted - drained)" % [g0, g1, gone, minted])
	print("  40 days, %d families put out: %d in the shelter, %d found a roof again; shelter cost %.1f gold/day; gold %.0f -> %.0f" % [n, sheltered, back,
		float(e["stats"].get("shelter_cost", 0.0)), g0, g1])
