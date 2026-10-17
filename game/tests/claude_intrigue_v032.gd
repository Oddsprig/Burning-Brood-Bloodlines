extends RefCounted
## v0.032: native campaign persons, house coin, schemes, hostile plots and real
## save/load. Run with -- --test=res://tests/claude_intrigue_v032.gd.
var checks := 0
var fails := 0
var previous_save_path := ""

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL intrigue032: ", what)

func _finish() -> int:
	Game.wait_save()
	if previous_save_path != "": Game.SAVE_PATH = previous_save_path
	print("intrigue032: %d checks, %d failures" % [checks, fails])
	return fails

func _find(id: int) -> Dictionary:
	for plot: Dictionary in Intrigue.state(Game)["plots"]:
		if int(plot["id"]) == id: return plot
	return {}

func _hostile() -> Dictionary:
	for plot: Dictionary in Intrigue.state(Game)["plots"]:
		if bool(plot.get("ai", false)): return plot
	return {}

func _advance(days: int, protect_house: bool = true) -> void:
	for i in days:
		# Keep unrelated hostile plots from interfering with scheme assertions.
		if protect_house:
			var hostile := _hostile()
			if not hostile.is_empty(): hostile["discovery"] = 1.0
		Game.day += 1.0
		Warfare.daily(Game, 1)

func _start(uid: String, kind: String, discovery: float = 0.0) -> Dictionary:
	var offer := Intrigue.preview(Game, uid, kind)
	check(offer.get("ok", false), kind + " preview: " + str(offer.get("text", "")))
	if not offer.get("ok", false): return {}
	check(float(offer["chance"]) > 0.0 and float(offer["chance"]) < 1.0, kind + " has a bounded success chance")
	check(float(offer["discovery"]) > 0.0 and float(offer["discovery"]) < 1.0, kind + " has discovery risk")
	var purse := float(Feudal._payer(Game)["purse"])
	var wallet := Game.gold
	var city := float(Dynasty.accounts(Game)["city_treasury"])
	var realm := float(Dynasty.accounts(Game)["faction_treasury"])
	var result := Intrigue.start(Game, uid, kind, offer["review"])
	check(result.get("ok", false), kind + " starts")
	if not result.get("ok", false): return {}
	check(is_equal_approx(float(Feudal._payer(Game)["purse"]), purse - float(offer["cost"])), kind + " charges the house purse exactly once")
	check(Game.gold == wallet and is_equal_approx(float(Dynasty.accounts(Game)["city_treasury"]), city) \
		and is_equal_approx(float(Dynasty.accounts(Game)["faction_treasury"]), realm), kind + " leaves other accounts alone")
	var plot: Dictionary = result["plot"]
	# Explicit deterministic outcome hooks; production uses the saved probabilities.
	plot["chance"] = 1.0; plot["discovery"] = discovery
	return plot

func _logged(part: String) -> bool:
	for entry: Dictionary in Intrigue.state(Game)["log"]:
		if str(entry["text"]).contains(part): return true
	return false

func _wait_for_ai() -> Dictionary:
	for i in 1200:
		var plot := _hostile()
		if not plot.is_empty(): return plot
		_advance(1, false)
	return _hostile()

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.wait_save()
	previous_save_path = Game.SAVE_PATH
	Game.SAVE_PATH = "user://intrigue032-test.json"
	if not await DevTools.start_world(tree, "user://claude_intrigue_v032-test.json"):
		printerr("FAIL: the start world did not load")
		return 1
	var chosen := false
	for choice: Dictionary in Dynasty.choices(Game):
		var town: Dictionary = Game.world["towns"][choice["town_id"]]
		if str(town["faction"]) != "middle_kingdom": continue
		chosen = bool(HouseOnboarding.begin(Game, str(choice["town_id"]), str(choice["household_uid"])).get("ok", false))
		if chosen: break
	check(chosen, "selected a native ruling house")
	if not chosen: return _finish()
	Feudal._payer(Game)["purse"] = 1000.0 * Item.COIN
	var target_uid := ""
	for choice: Dictionary in Dynasty.choices(Game):
		if str(choice["house_uid"]) == Intrigue._house(Game) or str(choice["faction_id"]) == Diplomacy.player_realm(Game.world): continue
		if Intrigue.preview(Game, str(choice["ruler_uid"]), "sway").get("ok", false):
			target_uid = str(choice["ruler_uid"]); break
	check(target_uid != "", "living person of another realm available")
	if target_uid == "": return _finish()
	var target := Dynasty._person(Game, target_uid)
	var tid := str(target["town"]["id"])
	var fid := str(target["town"]["faction"])
	check(not Intrigue.preview(Game, str(Game.world["player_house"]["ruler_uid"]), "assassinate").get("ok", false), "cannot plot against own house")
	check(not Intrigue.preview(Game, "missing-person", "sway").get("ok", false), "missing target rejected")
	check(not Intrigue.preview(Game, target_uid, "unknown").get("ok", false), "unknown scheme rejected")
	var payer := Feudal._payer(Game)
	var saved_purse := float(payer["purse"])
	payer["purse"] = 0.0
	var count: int = Intrigue.state(Game)["plots"].size()
	check(not Intrigue.start(Game, target_uid, "sway").get("ok", false), "insufficient house coin rejected")
	check(float(payer["purse"]) == 0.0 and Intrigue.state(Game)["plots"].size() == count, "rejected scheme neither spends nor queues")
	payer["purse"] = saved_purse
	# Sway completes on its final day, never earlier or twice in one day.
	Game.world["feudal"]["towns"][tid]["loyalty"] = 65.0
	var standing := Diplomacy.earned(Game, fid)
	var sway := _start(target_uid, "sway")
	if sway.is_empty(): return _finish()
	check(not Intrigue.start(Game, target_uid, "sway").get("ok", false), "duplicate active scheme rejected")
	Game.day += 3.0
	Warfare.daily(Game, 3)
	check(int(sway["left"]) == int(sway["days"]) - 3, "batched campaign advance ticks every day")
	_advance(int(sway["days"]) - 4)
	check(int(sway["left"]) == 1 and float(Game.world["feudal"]["towns"][tid]["loyalty"]) == 65.0, "sway waits for its full duration")
	Intrigue.daily(Game)
	check(int(sway["left"]) == 1, "repeated daily call cannot advance a plot twice")
	_advance(1)
	check(_find(int(sway["id"])).is_empty() and str(sway["status"]) == "succeeded", "resolved sway leaves the active list")
	check(is_equal_approx(float(Game.world["feudal"]["towns"][tid]["loyalty"]), 50.0), "sway reduces town loyalty")
	check(Diplomacy.earned(Game, fid) == standing + 8, "sway improves standing with target realm")
	# Save an active claim plot with forced success and discovery, then finish it.
	var claim := _start(target_uid, "fabricate_claim", 1.0)
	if claim.is_empty(): return _finish()
	_advance(3)
	var saved := claim.duplicate(true)
	var saved_log := JSON.stringify(Intrigue.state(Game)["log"])
	saved_purse = float(Feudal._payer(Game)["purse"])
	Game.save_game(); Game.wait_save()
	Game.world = {}; Game.rep = {}
	var loaded := Game.load_game()
	check(loaded, "real save reloads")
	if not loaded: return _finish()
	claim = _find(int(saved["id"]))
	check(not claim.is_empty(), "active claim plot survives save/load")
	if claim.is_empty(): return _finish()
	check(str(claim["target_uid"]) == target_uid and str(claim["kind"]) == "fabricate_claim" \
		and int(claim["left"]) == int(saved["left"]) and int(claim["seed"]) == int(saved["seed"]) \
		and float(claim["chance"]) == 1.0 and float(claim["discovery"]) == 1.0, "plot target, countdown and deterministic rolls survive reload")
	check(JSON.stringify(Intrigue.state(Game)["log"]) == saved_log, "intrigue log survives reload")
	check(is_equal_approx(float(Feudal._payer(Game)["purse"]), saved_purse), "loading an active plot does not charge again")
	standing = Diplomacy.earned(Game, fid)
	_advance(int(claim["left"]))
	check(Marriage.has_claim(Game, tid), "fabricated claim uses Marriage.has_claim storage")
	check(bool(Marriage.state(Game)["claims"].get(tid, {}).get("fabricated", false)), "claim is marked as fabricated")
	check(Diplomacy.earned(Game, fid) == standing - Intrigue.DISCOVERY_LOSS, "discovery costs realm standing")
	check(_logged("was discovered"), "discovery is logged")
	check((Game.world["log"] as Array).any(func(line): return str(line).contains("fabricated a claim")), "scheme results reach campaign log")
	# Assassination uses the native casualty path, not a second death registry.
	target = Dynasty._person(Game, target_uid)
	var econ: Dictionary = target["econ"]
	var pid := int(target["person"][0])
	var pop := int(econ["pop"])
	var deaths: int = Census._book(econ)["deaths"].size()
	var bound: Unit = Dynasty.bound_unit(Game, Dynasty._row(target, float(Game.day)))
	var assassination := _start(target_uid, "assassinate")
	if assassination.is_empty(): return _finish()
	_advance(int(assassination["days"]))
	check(Dynasty._person(Game, target_uid).is_empty() and not Dynasty.person(Game, target_uid).get("alive", true), "assassination kills the exact native person")
	check(int(econ["pop"]) == pop - 1, "assassination removes one resident")
	check(Census._book(econ)["deaths"].size() == deaths + 1, "assassination records exactly one census death")
	var death: Array = Census._book(econ)["deaths"][-1]
	check(int(death[1]) == pid and str(death[5]) == "murdered", "census records the victim with cause murdered")
	if bound != null: check(bound.dead, "a bound physical unit also dies")
	check(not Intrigue.preview(Game, target_uid, "assassinate").get("ok", false), "dead person cannot be targeted again")
	_child_target()
	# An actual seeded AI operation can target the player's house. Detection
	# foils it even with forced success; an undetected success kills its victim.
	var hostile := _wait_for_ai()
	check(not hostile.is_empty(), "AI occasionally starts a plot")
	if hostile.is_empty(): return _finish()
	var victim := str(hostile["target_uid"])
	check(str(hostile["source_house_uid"]) != Intrigue._house(Game) \
		and str(Dynasty.person(Game, victim).get("house_uid", "")) == Intrigue._house(Game), "AI targets a member of the player's house")
	check(not Intrigue.active(Game).has(hostile), "undiscovered hostile plot stays out of the court list")
	hostile["chance"] = 1.0; hostile["discovery"] = 1.0
	_advance(int(hostile["left"]), false)
	check(str(hostile["status"]) == "foiled" and not Dynasty._person(Game, victim).is_empty(), "discovered AI assassination is foiled")
	check(str(Intrigue.state(Game)["log"][-1]["text"]).contains("uncovered and foiled"), "discovered AI plot is reported")
	hostile = _wait_for_ai()
	check(not hostile.is_empty(), "another seeded AI plot is possible")
	if hostile.is_empty(): return _finish()
	victim = str(hostile["target_uid"])
	var home := Dynasty._person(Game, victim)
	var victim_pid := int(home["person"][0])
	hostile["chance"] = 1.0; hostile["discovery"] = 0.0
	_advance(int(hostile["left"]), false)
	check(str(hostile["status"]) == "succeeded" and Dynasty._person(Game, victim).is_empty(), "undiscovered successful AI plot kills a player-house member")
	death = Census._book(home["econ"])["deaths"][-1]
	check(int(death[1]) == victim_pid and str(death[5]) == "murdered", "AI assassination uses the same murdered census path")
	return _finish()

func _child_target() -> void:
	var uid := ""
	for town: Dictionary in Game.world["towns"].values():
		for family: Dictionary in town.get("econ", {}).get("fams", []):
			if family.get("gone", false) or family.get("cohort", false): continue
			for child: Array in family.get("kp", []):
				if str(Persons.g(child, Persons.HOUSE_UID, "")) == Intrigue._house(Game): continue
				var candidate := str(Persons.g(child, Persons.PERSON_UID, ""))
				if Intrigue.preview(Game, candidate, "assassinate").get("ok", false): uid = candidate; break
			if uid != "": break
		if uid != "": break
	check(uid != "", "native child target available")
	if uid == "": return
	var loc := Dynasty._person(Game, uid)
	var kids := int(loc["family"]["kids"])
	var adults := int(loc["econ"]["adults"])
	var plot := _start(uid, "assassinate")
	if plot.is_empty(): return
	_advance(int(plot["days"]))
	check(Dynasty._person(Game, uid).is_empty() and int(loc["family"]["kids"]) == kids - 1, "child death removes the child record and counter")
	check(int(loc["econ"]["adults"]) == adults, "child death leaves the adult census count intact")
