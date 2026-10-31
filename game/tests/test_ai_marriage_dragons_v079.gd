extends RefCounted
## v0.079: AI nobles marry across towns and realms, and an assault army marches an adult bonded dragon.
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL v079: ", why)
	print(("ok   " if ok else "FAIL ") + why)

func run(tree: SceneTree) -> int:
	await tree.process_frame
	if not await DevTools.start_world(tree, "user://v079-ai-marriage-dragons.json"):
		printerr("FAIL v079: the start world did not load")
		return 1
	check(DevTools.choose_house(Game) != "", "a player house is chosen so the campaign day can run")
	_marriages()
	_dragons()
	print("v0.079 AI marriage and dragons: %d checks, %d failures" % [checks, fails])
	return fails

func _marriages() -> void:
	var men := _people(0, true)
	var women := _people(1, true)
	check(not men.is_empty() and not women.is_empty(), "ruling houses have unmarried adults of both sexes")
	if men.is_empty() or women.is_empty(): return
	var same_town := _pair(men, women, "", true, "")
	if same_town.is_empty():
		check(false, "a same-town pair exists to refuse")
	else:
		_ready(same_town["man"]); _ready(same_town["woman"])
		var refused: Dictionary = Marriage.try_ai_match(Game, same_town["man"]["uid"], same_town["woman"]["uid"])
		check(not bool(refused.get("ok", false)) and "town" in str(refused.get("reason", "")).to_lower(), "same town is refused (%s)" % refused.get("reason", ""))
	var mixed := _pair(men, women, "", false, "")
	if mixed.is_empty():
		check(false, "a cross-town pair exists for the race refusal")
	else:
		var woman_f: Dictionary = mixed["woman"]["family"]
		var previous := str(woman_f.get("race", ""))
		woman_f["race"] = "troll" if str(mixed["man"]["race"]) != "troll" else "giant"
		_ready(mixed["man"]); _ready(mixed["woman"])
		var race_no: Dictionary = Marriage.try_ai_match(Game, mixed["man"]["uid"], mixed["woman"]["uid"])
		check(not bool(race_no.get("ok", false)) and "race" in str(race_no.get("reason", "")).to_lower(), "different races are refused (%s)" % race_no.get("reason", ""))
		if previous == "": woman_f.erase("race")
		else: woman_f["race"] = previous
	var used := {}
	if not same_town.is_empty():
		used[same_town["man"]["uid"]] = true
		used[same_town["woman"]["uid"]] = true
	var cross := _pair(men, women, "other", false, "")
	if cross.is_empty():
		check(false, "two realms have a same-race ruling pair")
	else:
		_wed(cross, true)
		used[cross["man"]["uid"]] = true
		used[cross["woman"]["uid"]] = true
	var local := _pair(men, women, "same", false, "")
	if local.is_empty():
		check(false, "one realm has ruling adults in two towns")
	else:
		if used.has(local["man"]["uid"]) or used.has(local["woman"]["uid"]):
			local = _pair(men, women, "same", false, "", used)
		if local.is_empty():
			check(false, "a second same-realm pair is still free")
		else:
			_wed(local, false)
			used[local["man"]["uid"]] = true
			used[local["woman"]["uid"]] = true
	var trolls := _pair(_people(0, false), _people(1, false), "", false, "", used)
	if trolls.is_empty():
		check(false, "another cross-town pair can stand in as trolls")
	else:
		trolls["man"]["family"]["race"] = "troll"
		trolls["woman"]["family"]["race"] = "troll"
		trolls["man"]["race"] = "troll"
		trolls["woman"]["race"] = "troll"
		_ready(trolls["man"]); _ready(trolls["woman"])
		_calm(str(trolls["man"]["faction"]), str(trolls["woman"]["faction"]))
		var troll_wed: Dictionary = Marriage.try_ai_match(Game, trolls["man"]["uid"], trolls["woman"]["uid"])
		check(bool(troll_wed.get("ok", false)), "troll marries troll across towns (%s)" % troll_wed.get("reason", ""))
		if bool(troll_wed.get("ok", false)):
			var bride := Dynasty._person(Game, trolls["woman"]["uid"])
			var groom := Dynasty._person(Game, trolls["man"]["uid"])
			check(not bride.is_empty() and not groom.is_empty() and is_same(bride["family"], groom["family"]), "the troll bride joins the groom's house")

func _wed(pair: Dictionary, cross_realm: bool) -> void:
	var man: Dictionary = pair["man"]
	var woman: Dictionary = pair["woman"]
	_ready(man); _ready(woman)
	_calm(str(man["faction"]), str(woman["faction"]))
	var groom_f: Dictionary = man["family"]
	var bride_f: Dictionary = woman["family"]
	groom_f["purse"] = 1000.0 * Item.COIN
	bride_f["purse"] = 2000.0 * Item.COIN
	var purse_sum := float(groom_f["purse"]) + float(bride_f["purse"])
	var expected := floorf(2000.0 * Item.COIN * Marriage.DOWRY_SHARE)
	var bride_hh := str(bride_f.get("household_uid", ""))
	var had_alliance := Marriage.state(Game)["alliances"].has(bride_hh)
	var loyalty_row: Dictionary = Game.world.get("feudal", {}).get("towns", {}).get(str(woman["tid"]), {})
	if not loyalty_row.is_empty(): loyalty_row["loyalty"] = 40.0
	var before_loyalty := float(loyalty_row.get("loyalty", -1.0))
	var wed: Dictionary = Marriage.try_ai_match(Game, man["uid"], woman["uid"])
	check(bool(wed.get("ok", false)), ("cross-realm" if cross_realm else "cross-town") + " wedding (%s)" % wed.get("reason", ""))
	if not bool(wed.get("ok", false)): return
	var groom := Dynasty._person(Game, man["uid"])
	var bride := Dynasty._person(Game, woman["uid"])
	check(not groom.is_empty() and not bride.is_empty() and is_same(groom["family"], bride["family"]), "the bride moved into the groom's house")
	check(str(groom["person"][Persons.SPOUSE_UID]) == woman["uid"] and str(bride["person"][Persons.SPOUSE_UID]) == man["uid"], "spouse links point both ways")
	check(absf(float(groom_f["purse"]) + float(bride_f["purse"]) - purse_sum) < 0.01, "dowry moves coin and does not mint it")
	check(absf(float(groom_f["purse"]) - (1000.0 * Item.COIN + expected)) < 0.01, "the groom's house receives the dowry share")
	var links: Dictionary = Marriage.state(Game).get("ai_links", {})
	check(links.has(str(wed.get("key", ""))), "the match is stored on ai_links, apart from the player's alliances")
	check(had_alliance or not Marriage.state(Game)["alliances"].has(bride_hh), "an AI match does not take a player alliance row")
	var fa := str(man["faction"]); var fb := str(woman["faction"])
	if cross_realm:
		var rel := Diplomacy.relation(Game.world, fa, fb)
		check(bool(Game.world["diplo"]["pairs"][Diplomacy.pair_key(fa, fb)].get("dynasty", false)), "the ruling match sets the dynasty flag")
		check(Diplomacy.state(Game.world, fa, fb) == Diplomacy.ALLIANCE, "the realms are at peace while the marriage holds")
		check(absf(rel - Diplomacy.DYNASTY_RELATION) < 0.01, "relation includes the marriage standing bonus")
		Diplomacy.sync_dynasty(Game)
		check(bool(Game.world["diplo"]["pairs"][Diplomacy.pair_key(fa, fb)].get("dynasty", false)), "sync_dynasty keeps the dynasty flag")
		var mine := Diplomacy.player_realm(Game.world)
		if mine == fa or mine == fb:
			check(Diplomacy.dynasty_bonus(Game, fb if mine == fa else fa) == Diplomacy.DYNASTY_STANDING, "a marriage with your realm pays the standing bonus")
		else:
			check(Diplomacy.dynasty_bonus(Game, fa) == 0, "two other realms do not pay your standing bonus")
		groom["person"][Persons.SPOUSE_UID] = ""
		bride["person"][Persons.SPOUSE_UID] = ""
		groom["person"][Persons.SP] = -1
		bride["person"][Persons.SP] = -1
		Marriage.state(Game)["ai_next"] = int(Game.day) + 100
		Marriage.daily(Game)
		check(not Marriage.state(Game).get("ai_links", {}).has(str(wed.get("key", ""))), "ending the couple ends the link")
		check(not bool(Game.world["diplo"]["pairs"][Diplomacy.pair_key(fa, fb)].get("dynasty", false)), "ending the couple clears the dynasty flag")
		check(Diplomacy.state(Game.world, fa, fb) == Diplomacy.NEUTRAL, "peace from the marriage does not outlive the couple")
	elif loyalty_row.is_empty():
		check(false, "the bride's town has a feudal loyalty row")
	else:
		check(absf(float(loyalty_row["loyalty"]) - (before_loyalty + 15.0)) < 0.01, "a same-realm match raises the bride's town loyalty once")

func _dragons() -> void:
	if not Game.world.has("dragons"):
		check(false, "the world has dragon records")
		return
	DragonCombat.prepare_world(Game)
	var player_hh := str(Game.world.get("player_house", {}).get("household_uid", ""))
	var row: Dictionary = {}
	var rider := ""
	for candidate: Dictionary in Game.world["dragons"].get("records", {}).values():
		if str(candidate.get("stage", "")) != "adult" or not bool(candidate.get("alive", false)): continue
		if player_hh != "" and str(candidate.get("owner_household_uid", "")) == player_hh: continue
		var tid0 := str(candidate.get("location_town_id", ""))
		if str(Game.world.get("towns", {}).get(tid0, {}).get("faction", "")) == "": continue
		if DragonCare.food_need_units(Game, candidate) <= 0: continue
		if DragonCombat._unit(Game, str(candidate.get("id", ""))) == null: continue
		var who := _rider(str(candidate.get("owner_household_uid", "")), str(candidate.get("id", "")))
		if who == "": continue
		row = candidate
		rider = who
		break
	check(not row.is_empty(), "an adult dragon of another house can march with a living body and a rider")
	if row.is_empty(): return
	var dragon_id := str(row.get("id", ""))
	var tid := str(row.get("location_town_id", ""))
	var fid := str(Game.world["towns"][tid].get("faction", ""))
	row["rider_person_uid"] = rider
	if not row.has("care") or not row["care"] is Dictionary:
		row["care"] = {"last_day": int(Game.day) - 1, "health": 1.0}
	row["care"]["health"] = 1.0
	var kept: Array = Game.company.duplicate()
	Game.company.clear()
	var stage := str(row.get("stage", ""))
	row["stage"] = "juvenile"
	var young: Dictionary = Warfare.set_dragon_march(Game, dragon_id, true, "v079-assault")
	check(not bool(young.get("ok", false)), "a juvenile is not marched (%s)" % young.get("reason", ""))
	row["stage"] = stage
	row["rider_person_uid"] = ""
	var loose: Dictionary = Warfare.set_dragon_march(Game, dragon_id, true, "v079-assault")
	check(not bool(loose.get("ok", false)) and "rider" in str(loose.get("reason", "")).to_lower(), "an unbonded dragon is not marched (%s)" % loose.get("reason", ""))
	row["rider_person_uid"] = rider
	var foot := _foot_person(rider)
	if foot.is_empty():
		check(false, "a person can stand in as a troll rider")
	else:
		var saved_race := str(foot["family"].get("race", ""))
		foot["family"]["race"] = "troll"
		row["rider_person_uid"] = foot["uid"]
		var on_foot: Dictionary = Warfare.set_dragon_march(Game, dragon_id, true, "v079-assault")
		check(not bool(on_foot.get("ok", false)) and "foot" in str(on_foot.get("reason", "")).to_lower(), "a troll is not marched as a rider (%s)" % on_foot.get("reason", ""))
		if saved_race == "": foot["family"].erase("race")
		else: foot["family"]["race"] = saved_race
		row["rider_person_uid"] = rider
	check(not row.has("ai_march"), "refused orders do not mark the dragon marching")
	var player_path: Dictionary = Warfare.set_dragon_march(Game, dragon_id, true, "")
	check(not bool(player_path.get("ok", false)), "an empty army id stays on the player march path (%s)" % player_path.get("reason", ""))
	check(not bool(row.get("campaign_march", {}).get("enabled", false)), "the refused player path does not set campaign_march")
	if not Game.world.has("warbands") or not Game.world["warbands"] is Dictionary:
		Game.world["warbands"] = {}
	var soldier := Unit.create(Persons.race_of(Game.world["towns"][tid]["econ"]), fid, true)
	var band := {"id": "v079-assault", "faction": fid, "pos": Game.world["towns"][tid].get("pos", Vector2.ZERO),
		"units": [soldier], "kind": "assault", "home": tid, "anchor": Game.world["towns"][tid].get("pos", Vector2.ZERO),
		"path": [], "mode": "wander", "march_day": 0.0, "target_town": "", "war_assault": true,
		"stores": {"grain": 200, "meat": 100000}}
	Game.world["warbands"]["v079-assault"] = band
	if not Game.world.has("factions"): Game.world["factions"] = {}
	if not Game.world["factions"].has(fid) or not Game.world["factions"][fid] is Dictionary:
		Game.world["factions"][fid] = {"treasury": 0.0}
	Game.world["factions"][fid]["treasury"] = 5000.0
	var marched: Dictionary = Warfare.set_dragon_march(Game, dragon_id, true, "v079-assault")
	check(bool(marched.get("ok", false)), "the assault army marches the bonded adult (%s)" % marched.get("reason", ""))
	if not bool(marched.get("ok", false)):
		_restore_company(kept)
		return
	check(bool(row.get("ai_march", {}).get("enabled", false)) and str(row["ai_march"].get("warband_id", "")) == "v079-assault", "ai_march names that army")
	check(not bool(row.get("campaign_march", {}).get("enabled", false)), "the AI march does not use the player's campaign_march")
	var body: Unit = DragonCombat._unit(Game, dragon_id)
	check(body == null or not Warfare.marching_units(Game).has(body), "an AI dragon is not added to the player's battle")
	var need := DragonCare.food_need_units(Game, row)
	check(need > 0, "the adult dragon has a real meat need (%d)" % need)
	var packed := Food.meat_units(Game)
	var meat_before := int(band["stores"].get("meat", 0))
	var treasury_before := float(Game.world["factions"][fid]["treasury"])
	row["care"]["last_day"] = int(Game.day) - 1
	check(DragonCare.settle(Game, row, int(Game.day), dragon_id), "the army feeds the dragon for the day")
	check(int(band["stores"].get("meat", 0)) < meat_before, "spare meat comes out of that army's stores")
	check(absf(float(Game.world["factions"][fid]["treasury"]) - treasury_before) < 0.01, "full spare meat does not spend the treasury")
	check(Food.meat_units(Game) == packed, "the player's packed meat is untouched")
	var meals := int(round(2.0 * Supplies.meal_shares(band)))
	band["stores"] = {"meat": meals}
	var cost := Warfare.feed_cost(row)
	Game.world["factions"][fid]["treasury"] = float(cost + 80)
	var coin_before := float(Game.world["factions"][fid]["treasury"])
	packed = Food.meat_units(Game)
	check(DragonCare.settle(Game, row, int(Game.day) + 1, dragon_id), "the next day still settles")
	check(int(band["stores"].get("meat", 0)) == meals, "meat the soldiers need for the day stays in the stores")
	check(absf(float(Game.world["factions"][fid]["treasury"]) - (coin_before - float(cost))) < 0.01, "the shortfall is paid from the realm treasury")
	check(Food.meat_units(Game) == packed, "a treasury day still leaves the player's provisions alone")
	Warfare.daily(Game, 0)
	check(bool(row.get("ai_march", {}).get("enabled", false)), "an empty player company does not recall the AI dragon")
	packed = Food.meat_units(Game)
	band["kind"] = "patrol"
	WarAI.march_dragons(Game)
	check(not row.has("ai_march"), "ending the assault recalls the dragon")
	check(Food.meat_units(Game) == packed, "the recall does not draw player provisions")
	_restore_company(kept)

func _restore_company(kept: Array) -> void:
	for unit in kept:
		Game.company.append(unit)

func _ready(who: Dictionary) -> void:
	var race := Persons.family_race(who["econ"], who["family"])
	who["race"] = race
	var adult := int(People.ages(race)["adult"])
	who["person"][3] = float(Game.day) - float(adult + 4) * People.year_days()
	who["person"][6] = 0
	who["person"][4] = ""
	Game.world["towns"][who["tid"]]["size"] = 4
	var feudal: Dictionary = Game.world.get("feudal", {}).get("towns", {}).get(who["tid"], {})
	if not feudal.is_empty(): feudal["tier"] = "village"

func _calm(a: String, b: String) -> void:
	if a == "" or b == "" or a == b or not Game.world.has("diplo"): return
	var key := Diplomacy.pair_key(a, b)
	if not Game.world["diplo"]["pairs"].has(key): return
	var pair: Dictionary = Game.world["diplo"]["pairs"][key]
	pair["rel"] = 0.0
	pair["state"] = Diplomacy.NEUTRAL
	pair["dynasty"] = false
	pair["treaty_alliance"] = false

func _people(sex: int, ruling_only: bool) -> Array:
	var out: Array = []
	var player_hh := str(Game.world.get("player_house", {}).get("household_uid", ""))
	var player_house := str(Game.world.get("player_house", {}).get("house_uid", ""))
	for tid in Game.world.get("towns", {}).keys():
		var town: Dictionary = Game.world["towns"][tid]
		var e: Dictionary = town.get("econ", {})
		var head: Dictionary = e.get("head", {})
		var ruling_hh := str(head.get("household_uid", ""))
		var heir := str(Dynasty.heir(Game, str(tid)).get("person_uid", ""))
		for f in e.get("fams", []):
			if not f is Dictionary: continue
			if f.get("cohort", false) or f.get("estate", false) or f.get("gone", false): continue
			var hh := str(f.get("household_uid", ""))
			if hh == "" or hh == player_hh: continue
			if ruling_only and hh != ruling_hh: continue
			for p in Persons.pp(f):
				if int(p[2]) != sex: continue
				var uid := str(Persons.g(p, Persons.PERSON_UID, ""))
				if uid == "" or uid == str(head.get("person_uid", "")) or uid == heir: continue
				if player_house != "" and str(Persons.g(p, Persons.HOUSE_UID, "")) == player_house: continue
				if String(p[4]) != "" or int(p[5]) >= 0 or int(p[6]) != 0: continue
				var loc := {"town": town, "econ": e, "family": f, "person": p, "alive": true}
				if Marriage._married(loc) or Marriage._betrothed(Game, uid): continue
				out.append({"uid": uid, "town": town, "econ": e, "family": f, "person": p,
					"race": Persons.family_race(e, f), "faction": str(town.get("faction", "")), "tid": str(tid)})
	return out

func _pair(men: Array, women: Array, faction_mode: String, same_town: bool, _unused: String, skip: Dictionary = {}) -> Dictionary:
	for man: Dictionary in men:
		if skip.has(man["uid"]): continue
		for woman: Dictionary in women:
			if skip.has(woman["uid"]) or man["uid"] == woman["uid"]: continue
			var shares_town := str(man["tid"]) == str(woman["tid"])
			if same_town != shares_town: continue
			if str(man["race"]) != str(woman["race"]): continue
			if faction_mode == "same" and str(man["faction"]) != str(woman["faction"]): continue
			if faction_mode == "other" and str(man["faction"]) == str(woman["faction"]): continue
			return {"man": man, "woman": woman}
	return {}

func _rider(household: String, dragon_id: String) -> String:
	var taken := {}
	for other: Dictionary in Game.world["dragons"].get("records", {}).values():
		if str(other.get("id", "")) == dragon_id: continue
		var uid := str(other.get("rider_person_uid", ""))
		if uid != "": taken[uid] = true
	for tid in Game.world["towns"].keys():
		var e: Dictionary = Game.world["towns"][tid].get("econ", {})
		for f in e.get("fams", []):
			if not f is Dictionary or str(f.get("household_uid", "")) != household: continue
			if Horses.fights_on_foot_only(Persons.family_race(e, f)): continue
			for p in Persons.pp(f):
				var uid := str(Persons.g(p, Persons.PERSON_UID, ""))
				if uid == "" or taken.has(uid) or int(p[6]) != 0 or String(p[4]) != "": continue
				var race := Persons.family_race(e, f)
				if Persons.age_of(p, float(Game.day)) < int(People.ages(race)["adult"]): continue
				return uid
	return ""

func _foot_person(except_uid: String) -> Dictionary:
	var riding := {except_uid: true}
	for other: Dictionary in Game.world.get("dragons", {}).get("records", {}).values():
		var rider := str(other.get("rider_person_uid", ""))
		if rider != "": riding[rider] = true
	for tid in Game.world["towns"].keys():
		var town: Dictionary = Game.world["towns"][tid]
		var e: Dictionary = town.get("econ", {})
		for f in e.get("fams", []):
			if not f is Dictionary or f.get("cohort", false) or f.get("gone", false) or f.get("estate", false): continue
			if str(f.get("household_uid", "")) == "": continue
			for p in Persons.pp(f):
				var uid := str(Persons.g(p, Persons.PERSON_UID, ""))
				if uid == "" or riding.has(uid) or int(p[6]) != 0 or String(p[4]) != "": continue
				return {"uid": uid, "family": f, "person": p}
	return {}
