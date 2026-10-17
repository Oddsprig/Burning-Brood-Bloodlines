extends RefCounted
## Marriage loop: fresh world, house, find a match, propose (with gift), wedding moves the spouse into your
## household, dowry/alliance/claim recorded, children are born to the couple over time, save/reload keeps it.
var checks := 0
var fails := 0
func check(ok: bool, m: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL marriage: ", m)
	print(("ok   " if ok else "FAIL ") + m)
func run(tree: SceneTree) -> int:
	await tree.process_frame
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var g := Game.new_game_begin(777)
	while not Game.new_game_slice(g, 0): pass
	var h := {}
	while CampaignWorld.presim_left(Game) > 0: CampaignWorld.presim_slice(Game, h, 0)
	CampaignWorld.presim_finish(Game, 0); Dynasty.prepare_world(Game); Game.new_game_finalize()
	var pick: Dictionary = {}
	for c: Dictionary in Dynasty.choices(Game):
		var home: Dictionary = Dynasty._household(Game, str(c["household_uid"]))
		if home.is_empty(): continue
		var ab := People.ages(Persons.race_of(home["town"]["econ"]))
		for p in Persons.pp(home["family"]):
			var loc := {"town": home["town"], "econ": home["town"]["econ"], "family": home["family"], "person": p, "alive": true}
			if str(Persons.g(p, Persons.PERSON_UID, "")) != str(c["ruler_uid"]) and int(p[6]) == 0 and Persons.age_of(p, Game.day) >= int(ab["adult"]) and not Marriage._married(loc) and str(p[4]) == "":
				pick = c; break
		if not pick.is_empty(): break
	check(not pick.is_empty(), "found a house with an unmarried adult")
	if pick.is_empty(): return fails
	check(HouseOnboarding.begin(Game, str(pick["town_id"]), str(pick["household_uid"])).get("ok", false), "house chosen")
	var fam: Array = Marriage.family(Game)
	check(fam.size() > 0, "family listed (%d members)" % fam.size())
	var member := {}
	var best := {}
	for row: Dictionary in fam:
		var cc: Array = Marriage.candidates(Game, str(row["person_uid"]))
		print("  member %s age %d sex %d married %s betrothable %s adult %s candidates %d top %s" % [row["name"], row["age"], row["sex"], row["married"], row["can_betroth"], row["adult"], cc.size(), cc[0]["score"] if not cc.is_empty() else "-"])
		if not cc.is_empty(): print("    ", cc[0]["reasons"])
		if not bool(row["can_betroth"]) or not bool(row["adult"]): continue
		var c: Array = cc
		if c.is_empty(): continue
		for o: Dictionary in c:
			var o2 := Marriage.offer(Game, str(row["person_uid"]), str(o["person_uid"]), 2)
			if bool(o2["accepts"]): member = row; best = o2; break
		if not best.is_empty(): break
	check(not best.is_empty(), "an unmarried adult has a match that would accept with a generous gift")
	if best.is_empty(): return fails
	var purse_before := float(Feudal._payer(Game).get("purse", 0.0))
	var coin_before := Barge.holdings(Game)
	var r := Marriage.propose(Game, str(member["person_uid"]), str(best["person_uid"]), 2)
	print("  ", r.get("text", ""))
	check(bool(r.get("accepted", false)), "proposal accepted and the wedding held")
	var sp := Dynasty._person(Game, str(best["person_uid"]))
	var me := Dynasty._person(Game, str(member["person_uid"]))
	check(not sp.is_empty() and is_same(sp["family"], me["family"]), "spouse now lives in your member's household")
	check(str(sp["person"][Persons.SPOUSE_UID]) == str(member["person_uid"]) and str(me["person"][Persons.SPOUSE_UID]) == str(best["person_uid"]), "spouse links set both ways")
	check(absf(Barge.holdings(Game) - coin_before) < 0.01, "gift and dowry move real coin, none created (%.2f -> %.2f)" % [coin_before, Barge.holdings(Game)])
	check(Marriage.state(Game)["alliances"].has(str(best["household_uid"])), "alliance recorded with House %s" % best["house_name"])
	var fam2: Array = Marriage.family(Game)
	var married := false
	for row: Dictionary in fam2:
		if str(row["person_uid"]) == str(member["person_uid"]): married = bool(row["married"])
	check(married, "member shows as married on the Court screen data")
	# Children over time (the native childbearing rules).
	var kids0 := Marriage.children_of(Game, str(member["person_uid"])).size()
	var wife_uid := str(member["person_uid"]) if int(member["sex"]) == 1 else str(best["person_uid"])
	for d in 400:
		Game.advance_time(1.0, false, 0, 0)
		while not Game.world.get("work", []).is_empty(): CampaignWorld.work_slice(Game, 50000)
		if Marriage.children_of(Game, str(member["person_uid"])).size() > kids0: break
	var kids := Marriage.children_of(Game, str(member["person_uid"]))
	check(kids.size() > kids0, "the couple had a child of your house within %d days (%d)" % [int(Game.day), kids.size()])
	if kids.size() > 0:
		check(str(kids[0]["house_uid"]) == Marriage._house(Game), "the child belongs to your house")
	Game.save_game(); Game.wait_save()
	check(Game.load_game(), "save reloads")
	check(Marriage.state(Game)["alliances"].has(str(best["household_uid"])) and str(Dynasty._person(Game, str(best["person_uid"]))["person"][Persons.SPOUSE_UID]) == str(member["person_uid"]), "marriage and alliance survive reload")
	print("Marriage test: %d checks, %d failures" % [checks, fails])
	return fails
