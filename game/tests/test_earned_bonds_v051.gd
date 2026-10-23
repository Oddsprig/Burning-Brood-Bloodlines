extends RefCounted
## v0.051 earned rider bonds. DevTools world. One care tick per checked day.
## Does not write user://save.json (the runner's SAVE_PATH is the test file).

var fails := 0
var checks := 0
var tid := ""
var household := ""
var progress_dragon := ""
var progress_person := ""
var other_person := ""
var accept_dragon := ""
var accept_person := ""
var refuse_dragon := ""
var refuse_person := ""
var day := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL earned bonds: " + message)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func live(uid: String) -> Dictionary:
	return Game.world["dragons"]["records"][uid]

func approach_of(uid: String) -> Dictionary:
	var stored: Variant = live(uid).get("approach", {})
	return stored if stored is Dictionary else {}

func sheet(person_uid: String) -> Array:
	# remembered=true still returns a person whose state was just set to dead.
	var found: Dictionary = Dynasty._person(Game, person_uid, true)
	var person: Variant = found.get("person", [])
	return person if person is Array else []

func adults_of(town_id: String, house: String) -> Array:
	var out: Array = []
	var town: Dictionary = Game.world["towns"].get(town_id, {})
	for family in town.get("econ", {}).get("fams", []):
		if str(family.get("household_uid", "")) != house: continue
		for person in family.get("pp", []):
			var uid := str(Persons.g(person, Persons.PERSON_UID, ""))
			var who: Dictionary = Dragons._person(Game, uid)
			if who.is_empty(): continue
			if str(who.get("town_id", "")) != town_id: continue
			if str(who.get("state", "")) not in ["", "hire", "reserve"]: continue
			if int(who.get("age", -1)) < int(People.ages(str(who.get("race", "human")))["adult"]): continue
			out.append(uid)
	out.sort()
	return out

func dragons_of(town_id: String, house: String) -> Array:
	var out: Array = []
	for uid in Game.world.get("dragons", {}).get("records", {}):
		var row: Dictionary = Game.world["dragons"]["records"][uid]
		if str(row.get("owner_household_uid", "")) != house: continue
		if str(row.get("location_town_id", "")) != town_id: continue
		if str(row.get("stage", "")) != "adult" or not bool(row.get("alive", false)): continue
		if str(row.get("rider_person_uid", "")) != "": continue
		out.append(str(uid))
	out.sort()
	return out

func child_of(town_id: String, house: String) -> String:
	var town: Dictionary = Game.world["towns"].get(town_id, {})
	for family in town.get("econ", {}).get("fams", []):
		if str(family.get("household_uid", "")) != house: continue
		for person in family.get("kp", []):
			var uid := str(Persons.g(person, Persons.PERSON_UID, ""))
			var who: Dictionary = Dragons._person(Game, uid)
			if who.is_empty(): continue
			if int(who.get("age", 99)) < int(People.ages(str(who.get("race", "human")))["adult"]):
				return uid
	return ""

func egg_of(town_id: String, house: String) -> String:
	for uid in Game.world.get("dragons", {}).get("records", {}):
		var row: Dictionary = Game.world["dragons"]["records"][uid]
		if str(row.get("owner_household_uid", "")) != house: continue
		if str(row.get("location_town_id", "")) != town_id: continue
		if str(row.get("stage", "")) == "egg" and bool(row.get("alive", false)):
			return str(uid)
	return ""

func feed(meat: int) -> void:
	var e: Dictionary = Game.world["towns"][tid]["econ"]
	for good in ["grain", "fruit", "wood"]:
		e["stock"][good] = 100000
	e["stock"]["meat"] = meat
	e["stock"]["fresh_meat"] = meat
	if float(e.get("price", {}).get("meat", 0.0)) <= 0.0: e["price"]["meat"] = 12.0
	if float(e.get("price", {}).get("fresh_meat", 0.0)) <= 0.0: e["price"]["fresh_meat"] = 14.0
	if float(e.get("price", {}).get("wood", 0.0)) <= 0.0: e["price"]["wood"] = 5.0
	for family in e["fams"]:
		if str(family.get("household_uid", "")) != household: continue
		family["purse"] = 100000000.0
		family["store"]["food"] = 40.0

func settle(uid: String, on_day: int) -> void:
	var row: Dictionary = live(uid)
	# A day already closed by care must stay closed. Rewinding it would apply the day twice.
	if int(row.get("care", {}).get("last_day", -1)) >= on_day:
		DragonCare.settle(Game, row, on_day, uid)
		return
	row["care"]["last_day"] = on_day - 1
	if row.has("approach") and row["approach"] is Dictionary:
		if int(row["approach"].get("last_day", -1)) < on_day:
			row["approach"]["last_day"] = on_day - 1
	DragonCare.settle(Game, row, on_day, uid)

func familiarity(uid: String) -> float:
	return float(approach_of(uid).get("familiarity", 0.0))

func roundtrip() -> void:
	Game.save_game()
	check(Game.load_game(), "save reloads")

func run(tree: SceneTree) -> int:
	if not await DevTools.start_world(tree, "user://test_earned_bonds_v051.json"):
		check(false, "start world")
		return fails
	Game.world["work"] = []
	var chosen := {}
	for group_uid in Game.world.get("dragons", {}).get("records", {}):
		var sample: Dictionary = Game.world["dragons"]["records"][group_uid]
		if str(sample.get("stage", "")) != "adult" or not bool(sample.get("alive", false)): continue
		var town_id := str(sample.get("location_town_id", ""))
		var house := str(sample.get("owner_household_uid", ""))
		if house == "" or chosen.has(house + "|" + town_id): continue
		if not bool(HouseOnboarding.preview(Game, town_id, house).get("ok", false)): continue
		var dragons: Array = dragons_of(town_id, house)
		var adults: Array = adults_of(town_id, house)
		if dragons.size() < 2 or adults.size() < 2: continue
		var accept := {}
		var refuse := {}
		for dragon_uid in dragons:
			var row: Dictionary = Game.world["dragons"]["records"][dragon_uid]
			for person_uid in adults:
				if DragonBond.will_accept(row, str(person_uid)):
					if accept.is_empty(): accept = {"dragon": str(dragon_uid), "person": str(person_uid)}
				elif refuse.is_empty():
					refuse = {"dragon": str(dragon_uid), "person": str(person_uid)}
		if accept.is_empty() or refuse.is_empty(): continue
		if str(accept["dragon"]) == str(refuse["dragon"]):
			var moved := false
			for dragon_uid in dragons:
				if str(dragon_uid) == str(refuse["dragon"]): continue
				var row: Dictionary = Game.world["dragons"]["records"][dragon_uid]
				for person_uid in adults:
					if DragonBond.will_accept(row, str(person_uid)):
						accept = {"dragon": str(dragon_uid), "person": str(person_uid)}
						moved = true
						break
				if moved: break
			if str(accept["dragon"]) == str(refuse["dragon"]): continue
		chosen = {"tid": town_id, "household": house, "adults": adults, "dragons": dragons, "accept": accept, "refuse": refuse}
		break
	check(not chosen.is_empty(), "a household has two adult dragons and both an accepting and a refusing pair")
	if chosen.is_empty():
		print("Earned bonds v0.051: %d checks, %d fails" % [checks, fails])
		return fails
	tid = str(chosen["tid"])
	household = str(chosen["household"])
	var began: Dictionary = HouseOnboarding.begin(Game, tid, household)
	check(bool(began.get("ok", false)), "owning household can be selected: " + str(began.get("reason", "")))
	if not bool(began.get("ok", false)): return fails
	var adults: Array = chosen["adults"]
	var dragons: Array = chosen["dragons"]
	progress_dragon = str(dragons[0])
	progress_person = str(adults[0])
	other_person = str(adults[1])
	accept_dragon = str(chosen["accept"]["dragon"])
	accept_person = str(chosen["accept"]["person"])
	refuse_dragon = str(chosen["refuse"]["dragon"])
	refuse_person = str(chosen["refuse"]["person"])
	check(DragonBond.APPROACH_PACE_DAYS == 90, "pace constant is 90 days, three months")
	var pace := DragonBond.pace_days(live(progress_dragon))
	check(pace >= 60 and pace <= 120, "temperament stays inside two to four months (%d)" % pace)
	check(DragonBond.will_accept(live(accept_dragon), accept_person), "accept pair is stable")
	check(not DragonBond.will_accept(live(refuse_dragon), refuse_person), "refuse pair is stable")
	check(DragonBond.will_accept(live(accept_dragon), accept_person) == DragonBond.will_accept(live(accept_dragon), accept_person), "verdict does not change between calls")
	for uid in [progress_dragon, accept_dragon, refuse_dragon]:
		live(uid).erase("campaign_march")
		if not bool(Dragons.authority(Game, live(uid)).get("ok", false)):
			check(false, "authority missing for " + uid)
			return fails
	feed(100000)
	var egg := egg_of(tid, household)
	if egg != "":
		check(not bool(DragonBond.approach(Game, egg, progress_person).get("ok", false)), "an egg cannot be approached")
	var child := child_of(tid, household)
	if child != "":
		check(not bool(DragonBond.approach(Game, progress_dragon, child).get("ok", false)), "a child cannot approach")
	sheet(progress_person)[4] = "militia"
	check(not bool(DragonBond.approach(Game, progress_dragon, progress_person).get("ok", false)), "an absent adult cannot start an approach")
	sheet(progress_person)[4] = ""
	var first: Dictionary = DragonBond.approach(Game, progress_dragon, progress_person)
	check(bool(first.get("ok", false)), "present adult can approach: " + str(first.get("reason", "")))
	var blocked: Dictionary = DragonBond.approach(Game, progress_dragon, other_person)
	check(not bool(blocked.get("ok", false)), "a second person cannot approach the same dragon")
	var other_dragon := str(dragons[1])
	var second: Dictionary = DragonBond.approach(Game, other_dragon, progress_person)
	check(not bool(second.get("ok", false)), "one person cannot approach two dragons")
	check(bool(DragonBond.stop_approach(Game, progress_dragon).get("ok", false)), "stop ends the approach")
	check(str(approach_of(progress_dragon).get("person_uid", "")) == "", "stop clears the approacher")
	day = int(floor(Game.day)) + 1
	live(progress_dragon)["custodian_person_uid"] = other_person
	live(progress_dragon)["care"]["health"] = 1.0
	var begun: Dictionary = DragonBond.approach(Game, progress_dragon, progress_person)
	check(bool(begun.get("ok", false)), "approach restarts: " + str(begun.get("reason", "")))
	var before_click := familiarity(progress_dragon)
	var click: Dictionary = DragonBond.approach(Game, progress_dragon, progress_person)
	check(not bool(click.get("ok", false)) and near(familiarity(progress_dragon), before_click), "repeated approach clicks add no familiarity")
	settle(progress_dragon, day)
	var gained := familiarity(progress_dragon)
	var one := float(approach_of(progress_dragon).get("last_gain", 0.0))
	check(gained > before_click and near(gained - before_click, one), "a present day raises familiarity by that day's gain")
	check(float(live(progress_dragon).get("care", {}).get("last", {}).get("food_ratio", 0.0)) >= DragonBond.HUNGRY_FOOD, "the fed day actually feeds")
	check(not bool(approach_of(progress_dragon).get("keeper", false)), "the first day is not the keeper")
	DragonBond.approach_day(Game, live(progress_dragon), day)
	settle(progress_dragon, day)
	check(near(familiarity(progress_dragon), gained), "the same care day does not apply twice")
	var kept_fam := familiarity(progress_dragon)
	check(bool(DragonBond.stop_approach(Game, progress_dragon).get("ok", false)), "stop after progress")
	check(near(familiarity(progress_dragon), kept_fam), "stopping keeps familiarity")
	check(bool(DragonBond.approach(Game, progress_dragon, progress_person).get("ok", false)), "the same person resumes")
	check(near(familiarity(progress_dragon), kept_fam), "resuming does not reset familiarity")
	day += 1
	live(progress_dragon)["custodian_person_uid"] = progress_person
	live(progress_dragon)["care"]["health"] = 1.0
	feed(100000)
	settle(progress_dragon, day)
	var keeper_gain := float(approach_of(progress_dragon).get("last_gain", 0.0))
	check(bool(approach_of(progress_dragon).get("keeper", false)), "keeper day is marked")
	check(keeper_gain > one and near(keeper_gain, one * DragonBond.KEEPER_MULT), "keeper care quickens the same dragon (%s vs %s)" % [keeper_gain, one])
	day += 1
	live(progress_dragon)["care"]["health"] = 1.0
	feed(0)
	settle(progress_dragon, day)
	var hungry_gain := float(approach_of(progress_dragon).get("last_gain", 0.0))
	check(bool(approach_of(progress_dragon).get("hungry", false)) and not bool(approach_of(progress_dragon).get("hurt", false)), "hunger is recorded without counting as injury")
	check(hungry_gain < keeper_gain and near(hungry_gain, keeper_gain * DragonBond.HUNGRY_MULT), "hunger slows familiarity (%s vs %s)" % [hungry_gain, keeper_gain])
	day += 1
	live(progress_dragon)["care"]["health"] = 0.5
	feed(100000)
	settle(progress_dragon, day)
	var hurt_gain := float(approach_of(progress_dragon).get("last_gain", 0.0))
	check(bool(approach_of(progress_dragon).get("hurt", false)) and not bool(approach_of(progress_dragon).get("hungry", false)), "injury is recorded on a fed day")
	check(hurt_gain < keeper_gain and near(hurt_gain, keeper_gain * DragonBond.HURT_MULT), "injury slows familiarity")
	var saved_fam := familiarity(progress_dragon)
	var saved_cool := int(approach_of(progress_dragon).get("cooldown_until", 0))
	var saved_person := str(approach_of(progress_dragon).get("person_uid", ""))
	roundtrip()
	check(near(familiarity(progress_dragon), saved_fam) and int(approach_of(progress_dragon).get("cooldown_until", 0)) == saved_cool, "save/load keeps familiarity and cooldown")
	check(str(approach_of(progress_dragon).get("person_uid", "")) == saved_person, "save/load keeps the approacher")
	var stalled := familiarity(progress_dragon)
	sheet(progress_person)[4] = "militia"
	day += 1
	live(progress_dragon)["care"]["health"] = 1.0
	settle(progress_dragon, day)
	check(str(approach_of(progress_dragon).get("person_uid", "")) == "" and near(familiarity(progress_dragon), stalled), "leaving cancels the approach without a day's gain")
	sheet(progress_person)[4] = ""
	check(bool(DragonBond.approach(Game, progress_dragon, progress_person).get("ok", false)), "they can approach again after returning")
	var owner_house := str(live(progress_dragon).get("owner_household_uid", ""))
	live(progress_dragon)["owner_household_uid"] = "other-household"
	DragonBond.reconcile(Game)
	check(str(approach_of(progress_dragon).get("person_uid", "")) == "", "an ownership change cancels the approach")
	live(progress_dragon)["owner_household_uid"] = owner_house
	check(bool(DragonBond.approach(Game, progress_dragon, progress_person).get("ok", false)), "approach resumes after ownership is restored")
	sheet(progress_person)[4] = "dead"
	DragonBond.reconcile(Game)
	check(str(approach_of(progress_dragon).get("person_uid", "")) == "", "the approacher's death cancels the approach")
	sheet(progress_person)[4] = ""
	check(bool(DragonBond.approach(Game, progress_dragon, other_person).get("ok", false)), "another adult can approach after the death cancel")
	live(progress_dragon)["alive"] = false
	DragonBond.reconcile(Game)
	check(str(approach_of(progress_dragon).get("person_uid", "")) == "", "the dragon's death cancels the approach")
	live(progress_dragon)["alive"] = true
	if str(approach_of(other_dragon).get("person_uid", "")) != "":
		DragonBond.stop_approach(Game, other_dragon)
	# Refusal and acceptance use the searched pairs. Clear any leftover approach first.
	for uid in [refuse_dragon, accept_dragon]:
		if str(approach_of(uid).get("person_uid", "")) != "":
			DragonBond.stop_approach(Game, uid)
		live(uid)["alive"] = true
		live(uid)["rider_person_uid"] = ""
		live(uid)["owner_household_uid"] = household
		live(uid).erase("campaign_march")
	feed(100000)
	live(refuse_dragon)["custodian_person_uid"] = refuse_person
	live(refuse_dragon)["care"]["health"] = 1.0
	var refuse_start: Dictionary = DragonBond.approach(Game, refuse_dragon, refuse_person)
	check(bool(refuse_start.get("ok", false)), "refusing pair can approach: " + str(refuse_start.get("reason", "")))
	if bool(refuse_start.get("ok", false)):
		live(refuse_dragon)["approach"]["familiarity"] = DragonBond.FAMILIARITY_CAP - 0.01
		day += 1
		settle(refuse_dragon, day)
		check(str(live(refuse_dragon).get("rider_person_uid", "")) == "", "refusal does not write a rider")
		check(str(approach_of(refuse_dragon).get("person_uid", "")) == "", "refusal ends the approach")
		check(int(approach_of(refuse_dragon).get("cooldown_until", 0)) == day + DragonBond.REFUSAL_COOLDOWN_DAYS, "refusal sets a 30-day cooldown")
		check(near(familiarity(refuse_dragon), DragonBond.FAMILIARITY_CAP * DragonBond.REFUSAL_KEEP), "refusal drops familiarity")
		var during: Dictionary = DragonBond.approach(Game, refuse_dragon, refuse_person)
		check(not bool(during.get("ok", false)) and "refused" in str(during.get("reason", "")).to_lower(), "cooldown blocks another approach")
		var line := str(DragonBond.approach_status(Game, refuse_dragon).get("line", ""))
		check("Familiarity" in line and "Cooldown" in line, "status shows familiarity and the cooldown")
		var cool_fam := familiarity(refuse_dragon)
		var cool_until := int(approach_of(refuse_dragon).get("cooldown_until", 0))
		roundtrip()
		check(near(familiarity(refuse_dragon), cool_fam) and int(approach_of(refuse_dragon).get("cooldown_until", -1)) == cool_until, "save/load keeps the refusal cooldown")
	var owner_before := str(live(accept_dragon).get("owner_person_uid", ""))
	live(accept_dragon)["custodian_person_uid"] = accept_person
	live(accept_dragon)["care"]["health"] = 1.0
	feed(100000)
	var accept_start: Dictionary = DragonBond.approach(Game, accept_dragon, accept_person)
	check(bool(accept_start.get("ok", false)), "accepting pair can approach: " + str(accept_start.get("reason", "")))
	if bool(accept_start.get("ok", false)):
		live(accept_dragon)["approach"]["familiarity"] = DragonBond.FAMILIARITY_CAP - 0.01
		day += 1
		settle(accept_dragon, day)
		check(str(live(accept_dragon).get("rider_person_uid", "")) == accept_person, "acceptance writes the rider through the bond")
		check(bool(DragonBond.status(Game, accept_dragon).get("bonded", false)), "the existing bond status sees the new rider")
		check(str(live(accept_dragon).get("owner_person_uid", "")) == owner_before, "acceptance leaves the owner in place")
		var bonded := false
		for event in live(accept_dragon).get("history", []):
			if event is Dictionary and str(event.get("kind", "")) == "bonded": bonded = true
		check(bonded, "acceptance records the existing bonded history entry")
		var denied: Dictionary = DragonBond.approach(Game, refuse_dragon, accept_person)
		check(not bool(denied.get("ok", false)), "a bonded person cannot approach another dragon")
	var raised := DevTools.raise_army(Game, tid, 6)
	check(raised > 0 and not Game.company.is_empty(), "a field army can be raised")
	# Town muster raises levy, not the owning household. Enlist one of its adults into that army.
	var soldier := ""
	var enlist_reason := ""
	for person_uid in adults_of(tid, household):
		var enlisted: Dictionary = Mobilization.enlist_household(Game, str(person_uid))
		if bool(enlisted.get("ok", false)):
			soldier = str(person_uid)
			break
		enlist_reason = str(enlisted.get("reason", ""))
	check(soldier != "", "the army includes an adult of the owning household: " + enlist_reason)
	if soldier != "" and str(live(accept_dragon).get("rider_person_uid", "")) != "":
		var released: Dictionary = DragonBond.release(Game, accept_dragon, DragonBond.release_preview(Game, accept_dragon))
		check(bool(released.get("ok", false)), "the earned bond can be released for the march check: " + str(released.get("reason", "")))
	if soldier != "" and str(live(accept_dragon).get("rider_person_uid", "")) == "":
		if str(approach_of(accept_dragon).get("person_uid", "")) != "":
			DragonBond.stop_approach(Game, accept_dragon)
		if not (live(accept_dragon).get("approach") is Dictionary):
			live(accept_dragon)["approach"] = {}
		live(accept_dragon)["approach"]["cooldown_until"] = 0
		live(accept_dragon)["approach"]["person_uid"] = ""
		live(accept_dragon)["campaign_march"] = {"enabled": true, "day": float(Game.day)}
		var away := ""
		for person_uid in adults_of(tid, household):
			if str(person_uid) == soldier: continue
			away = str(person_uid)
			break
		if away != "":
			var away_try: Dictionary = DragonBond.approach(Game, accept_dragon, away)
			check(not bool(away_try.get("ok", false)), "someone left at the roost cannot approach a marching dragon")
		var march_try: Dictionary = DragonBond.approach(Game, accept_dragon, soldier)
		check(bool(march_try.get("ok", false)), "a soldier with the army can approach the marching dragon: " + str(march_try.get("reason", "")))
		if bool(march_try.get("ok", false)):
			var march_before := familiarity(accept_dragon)
			day += 1
			live(accept_dragon)["care"]["health"] = 1.0
			settle(accept_dragon, day)
			check(familiarity(accept_dragon) > march_before and str(approach_of(accept_dragon).get("person_uid", "")) == soldier, "familiarity rises while both are with the army")
	print("Earned bonds v0.051: %d checks, %d fails" % [checks, fails])
	return fails
