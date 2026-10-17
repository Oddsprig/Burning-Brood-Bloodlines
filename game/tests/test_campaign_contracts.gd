extends RefCounted
## Contracts: accept -> battle result -> pay and reputation; defend contract fails when the town is
## sacked; a hunt fails (or goes void) after its deadline.

func _find_offer(kind: String) -> Dictionary:
	var w: Dictionary = Game.world
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var ids: Array = w["towns"].keys(); ids.sort()
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		for c in t["contracts"]:
			# diplomacy: only offers this company may take (veteran's contracts need standing > 50)
			if c.get("state", "") == "offered" and c["kind"] == kind and Contracts.refusal(Game, c) == "":
				return c
	# none rolled: keep rolling offers in a friendly town
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if t["faction"] != "middle_kingdom":
			continue
		for i in 50:
			for c in Contracts.generate_offers(t, Game.day, rng):
				if c.get("state", "") == "offered" and c["kind"] == kind and Contracts.refusal(Game, c) == "":
					t["contracts"].append(c)
					return c
	return {}

# Acceptance is contingent on actual available people, rather than fabricated size.
func _accept_available(kind: String) -> Dictionary:
	for attempt in 80:
		var c := _find_offer(kind)
		if c.is_empty(): return {}
		if Contracts.accept(Game, c): return c
	return {}

func run(_tree: SceneTree) -> int:
	var fails := 0
	Game.new_game(77)
	var w: Dictionary = Game.world
	# ---------------------------------------------------------------- battle contract, won
	var c := _find_offer("battle")
	if c.is_empty():
		print("FAIL: no battle contract offered"); return 1
	print("offer: ", c["desc"])
	var gold0: int = Game.gold
	var rep0: int = Game.rep.get(c["employer"], 0)
	var str0: float = w["factions"][c["target_faction"]]["strength"]
	w["towns"][c["town_id"]]["econ"]["treasury"] = float(c["pay"]) * 2
	if not Contracts.accept(Game, c):
		print("FAIL: funded battle fixture cannot recruit"); return 1
	if Contracts.accept(Game, _find_offer("battle")):
		print("FAIL: second contract accepted while one is active"); fails += 1
	var wid: String = Game.contract["target_id"]
	if not w["warbands"].has(wid) or w["warbands"][wid]["units"].is_empty() or w["warbands"][wid]["units"].size() > int(c["size"]):
		print("FAIL: target warband not spawned within requested real-person capacity"); fails += 1
	print("status: ", Contracts.status_text(Game))
	var enemy: Array = w["warbands"][wid]["units"]
	for u in enemy:
		u.dead = true
	Game.pending_battle = {"warband_id": wid, "enemy": enemy}
	Game.finish_battle({"winner": 0, "player_units": Game.company, "enemy_units": enemy, "enemy_fallen": enemy, "events": []})
	var loot: int = Game.last_result.get("loot_gold", 0)
	if Game.gold != gold0 + int(c["pay"]) + loot:
		print("FAIL: pay %d + loot %d not received (gold %d -> %d)" % [c["pay"], loot, gold0, Game.gold]); fails += 1
	if not Game.contract.is_empty():
		print("FAIL: contract still active after success"); fails += 1
	if w["warbands"].has(wid):
		print("FAIL: beaten warband still on the map"); fails += 1
	if int(Game.rep[c["employer"]]) <= rep0:
		print("FAIL: employer reputation did not rise"); fails += 1
	if float(w["factions"][c["target_faction"]]["strength"]) >= str0:
		print("FAIL: losing faction not weakened"); fails += 1
	print("after win: gold %d, rep %s %d, %s strength %.2f, desired bands %d" % [Game.gold, c["employer"], Game.rep[c["employer"]],
		c["target_faction"], w["factions"][c["target_faction"]]["strength"], CampaignWorld.desired_bands(w, c["target_faction"])])
	# ---------------------------------------------------------------- defend contract, party far away -> sacked
	Game.new_game(78)
	w = Game.world
	var d := _accept_available("defend")
	if d.is_empty():
		print("FAIL: no defend contract"); return fails + 1
	var town: Dictionary = w["towns"][d["town_id"]]
	var wealth0: int = town["wealth"]
	var rep1: int = Game.rep.get(d["employer"], 0)
	var awid: String = Game.contract["target_id"]
	print("defend: ", d["desc"], " assault ", awid, " march day %.1f deadline %.1f" % [w["warbands"][awid]["march_day"], d["deadline_day"]])
	# send the party to the far corner of the map (not travelling, out of the way)
	w["party"]["pos"] = CampaignWorld.nearest_passable(w, Vector2(60, 60) if town["pos"].x > 1200 else Vector2(2300, 60))
	# Invoke the actual arrival event directly, isolating contract consequences
	# from random diplomacy and other forces on a long walk.
	Game.location = ""
	CampaignWorld._assault_arrives(Game, awid)
	print("defend ended day %.1f: log: %s" % [Game.day, w["log"].slice(-3)])
	if not Game.contract.is_empty():
		print("FAIL: defend contract never resolved"); fails += 1
	elif int(town["wealth"]) >= wealth0 and wealth0 > 1:
		print("FAIL: town not sacked"); fails += 1
	if int(Game.rep[d["employer"]]) >= rep1:
		print("FAIL: no reputation loss for failed defence"); fails += 1
	# ---------------------------------------------------------------- hunt left to expire
	Game.new_game(79)
	w = Game.world
	var h := _accept_available("battle")
	if h.is_empty(): print("FAIL: expiry fixture cannot recruit"); return fails + 1
	Game.day = float(h["deadline_day"]) + 1
	Contracts.daily_check(Game)
	if not Game.contract.is_empty():
		print("FAIL: expired hunt still active"); fails += 1
	print("hunt ended: ", w["log"].slice(-1))
	# Insufficient funds transfer only existing money and book the actual remainder.
	var payer: Dictionary = w["towns"][h["town_id"]]
	payer["econ"]["treasury"] = 100.0
	w["factions"][payer["faction"]]["treasury"] = 25.0
	var debt0 := float(payer["econ"].get("debt_to_company", 0))
	var paid := Contracts._draw_pay(Game, {"town_id": payer["id"], "pay": 1000})
	if paid != 125 or float(payer["econ"]["treasury"]) != 0 or float(w["factions"][payer["faction"]]["treasury"]) != 0 or absf(float(payer["econ"]["debt_to_company"]) - debt0 - 875) > 0.001:
		print("FAIL: contract short payment/debt conservation"); fails += 1
	# An actual empty draft pool withdraws the offer without cost or reputation loss.
	Game.new_game(77); w = Game.world
	var empty := _find_offer("battle")
	if empty.is_empty(): return fails + 1
	for t in w["towns"].values():
		if t["faction"] == empty["target_faction"]:
			for f in t["econ"]["fams"]: f["gone"] = true
	var g0 := Game.gold; var r0: Dictionary = Game.rep.duplicate()
	var bands0: Array = w["warbands"].keys()
	if Contracts.accept(Game, empty) or not Game.contract.is_empty() or Game.gold != g0 or Game.rep != r0 or empty.has("target_id") or w["warbands"].keys() != bands0 or (w["towns"][empty["town_id"]]["contracts"] as Array).has(empty):
		print("FAIL: unraised force should withdraw without payment, penalty or phantom target"); fails += 1
	return fails
