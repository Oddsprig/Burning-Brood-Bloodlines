extends RefCounted
## v0.033: prisoner ransom and exchange on a real generated world. Battle outcomes are given to the real
## capture paths (BattleRounds.take_one_clash / _take_prisoners); everything after that is the live game:
## weekly sweeps, family counts, house and realm coin, standing, save/load and death in captivity.
## Run with -- --test=res://tests/claude_prisoners_v033.gd.
var checks := 0
var fails := 0
var previous_save_path := ""

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL prisoners033: ", what)

func _finish() -> int:
	Game.wait_save()
	if previous_save_path != "": Game.SAVE_PATH = previous_save_path
	print("prisoners033: %d checks, %d failures" % [checks, fails])
	return fails

func _purse() -> float:
	return float(Feudal._payer(Game).get("purse", 0.0))

func _treasury(fid: String) -> float:
	return float(Game.world["factions"][fid].get("treasury", 0.0))

func _person(u: Unit) -> Array:
	var town: Dictionary = Game.world["towns"].get(u.home_town, {})
	var f: Dictionary = People.fam_of(town, u.family) if not town.is_empty() else {}
	return Persons.by_uid(f, u.uid) if not f.is_empty() else []

## The register state of a unit's person, or "missing" (never an index error).
func _st(u: Unit) -> String:
	var p := _person(u)
	return str(p[4]) if p.size() > 5 else "missing"

func _advance(days: int) -> void:
	for i in days:
		Game.day += 1.0
		Warfare.daily(Game, 1)

func _clash(winner: int, units: Array, states: Array, extra: Dictionary = {}) -> Dictionary:
	Game.pending_battle = {"warband_id": _band_id}
	Game.pending_battle.merge(extra)
	var result := {"winner": winner, "fighter_units": units, "fighter_states": states,
		"enemy_units": units.filter(func(u): return not Game.company.has(u))}
	BattleRounds.take_one_clash(Game, result)
	Game.pending_battle = {}
	return result

var _band_id := ""

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.wait_save()
	previous_save_path = Game.SAVE_PATH
	if not await DevTools.start_world(tree, "user://prisoners033-test.json"):
		check(false, "the shared test world loads")
		return _finish()
	var seat := ""
	var by_pop: Array = Dynasty.choices(Game)
	by_pop.sort_custom(func(a, b): return int(Game.world["towns"][a["town_id"]]["econ"]["pop"]) > int(Game.world["towns"][b["town_id"]]["econ"]["pop"]))
	for choice: Dictionary in by_pop:   # the most populous seat has men and arms to raise
		if bool(HouseOnboarding.begin(Game, str(choice["town_id"]), str(choice["household_uid"])).get("ok", false)):
			seat = str(choice["town_id"]); break
	check(seat != "", "selected a native ruling house")
	if seat == "": return _finish()
	var mine := Diplomacy.player_realm(Game.world)
	Game.location = seat
	Feudal._payer(Game)["purse"] = 1000.0 * Item.COIN
	Mobilization.fund(Game, 600 * Item.COIN)
	# Household officers and a few registered men of the seat ride with the army.
	# A seated ruler may ride, and is priced as a ruler. This noble is another adult of the house.
	var noble: Unit = null
	var seats := Prisoners.ruling(Game)
	var taken := 0
	for row in Mobilization.household_candidates(Game):
		if seats["people"].has(str(row.get("person_uid", ""))): continue
		var er: Dictionary = Mobilization.enlist_household(Game, str(row["person_uid"]))
		if not er.get("ok", false): continue
		taken += 1
		if noble == null: noble = er["unit"]
		if taken >= 3: break
	check(noble != null, "a member of your house rides with the army")
	var quote := Mobilization.quote(Game, seat, 12)
	print("prisoners033: quote ", quote.get("ok", false), " ", quote.get("reason", ""), " planned ", quote.get("planned", 0))
	if quote.get("ok", false): print("prisoners033: muster ", Mobilization.muster(Game, seat, 12, quote["review"]).get("reason", ""))
	print("prisoners033: company ", Game.company.size(), " registered ", Game.company.filter(func(u): return u.family >= 0 and not _person(u).is_empty()).size())
	var men: Array = Game.company.filter(func(u): return u != noble and u.family >= 0 and not _person(u).is_empty() and not u.has_meta("house_member"))
	men.append_array(Game.company.filter(func(u): return u != noble and u.has_meta("house_member")))
	check(noble != null and men.size() >= 3, "registered men were raised (%d)" % men.size())
	if noble == null or men.size() < 3: return _finish()
	# A real enemy field band of another realm whose men have family records.
	for key in Game.world["warbands"]:
		var band: Dictionary = Game.world["warbands"][key]
		if str(band.get("faction", "")) == mine or not Army.is_people_band(band) or Monsters.suspended_band(band): continue
		if str(band.get("kind", "")) in ["caravan", "militia"]: continue
		var reg: Array = (band["units"] as Array).filter(func(u): return u.family >= 0 and not _person(u).is_empty() and Army.state(Game.world)["roll"].has(str(u.uid)))
		if reg.size() >= 4: _band_id = str(key); break
	check(_band_id != "", "an enemy field band with registered soldiers exists")
	if _band_id == "": return _finish()
	var wb: Dictionary = Game.world["warbands"][_band_id]
	var enemy := str(wb["faction"])
	var foes: Array = (wb["units"] as Array).filter(func(u): return u.family >= 0 and not _person(u).is_empty() and Army.state(Game.world)["roll"].has(str(u.uid))).slice(0, 4)
	Game.world["factions"][enemy]["treasury"] = 500.0 * Item.COIN

	# --- Capture, one-clash: you win; two downed foes are taken, a fleeing one and your downed man are not.
	var band_size := (wb["units"] as Array).size()
	var r := _clash(0, [foes[0], foes[1], foes[2], men[0]], ["unconscious", "prone", "fled", "unconscious"])
	check(Prisoners.held(Game).size() == 2, "the beaten band's two downed men are taken prisoner")
	check((wb["units"] as Array).size() == band_size - 2 and not (wb["units"] as Array).has(foes[0]), "prisoners leave their band")
	check(not (r["enemy_units"] as Array).has(foes[0]) and (r["enemy_units"] as Array).has(foes[2]), "prisoners are kept out of the loot; the fled are not")
	check(Game.company.has(men[0]) and Prisoners.captives(Game).is_empty(), "the winner's downed men are not taken")
	var rec0: Dictionary = Prisoners._find(Prisoners.held(Game), foes[0].uid)
	check(rec0.get("unit") == foes[0] and str(rec0.get("faction", "")) == enemy, "the record keeps the actual Unit and realm")
	# A raid or siege does not take a town's defenders.
	_clash(0, [foes[3]], ["unconscious"], {"assault": {"kind": "raid"}})
	check(Prisoners.held(Game).size() == 2 and (wb["units"] as Array).has(foes[3]), "assault defenders are not taken")
	_clash(-1, [foes[3]], ["unconscious"])
	check(Prisoners.held(Game).size() == 2, "a drawn fight takes nobody")

	# --- Capture: you lose; your downed house member and one man are taken.
	var noble_person := _person(noble)
	var fam_town: Dictionary = Game.world["towns"][men[1].home_town]
	var fam: Dictionary = People.fam_of(fam_town, men[1].family)
	var pop := int(fam_town["econ"]["pop"])
	var recs := (fam["pp"] as Array).size()
	_clash(1, [noble, men[1], men[2], foes[3]], ["unconscious", "prone", "fled", "unconscious"])
	check(Prisoners.captives(Game).size() == 2 and not Game.company.has(noble) and not Game.company.has(men[1]), "your downed men are taken by the winner")
	check(Game.company.has(men[2]), "your fleeing man is not taken")
	check(str(noble_person[4]) == "captive" and _st(men[1]) == "captive", "their register rows say captive")
	var cap_noble: Dictionary = Prisoners._find(Prisoners.captives(Game), noble.uid)
	check(str(cap_noble.get("held_by", "")) == enemy and cap_noble.get("unit") == noble, "the captive record keeps the Unit and captor")
	check(Prisoners.kind_of(Game, cap_noble) == "noble" and Prisoners.price(Game, cap_noble) == 60 * Item.COIN, "a house member is priced as a noble")
	check(Prisoners.price(Game, rec0) == 6 * Item.COIN or Prisoners.price(Game, rec0) == 20 * Item.COIN, "a soldier is priced by rank")

	# --- Held prisoners stay alive through the weekly sweeps and the daily family sync.
	Persons.sweep(Game); Army.sweep(Game)
	Persons.sync(fam_town["econ"], fam, float(Game.day))
	check(not Dynasty._person(Game, str(noble_person[Persons.PERSON_UID])).is_empty(), "a captive house member is still alive after the sweep")
	check(_st(men[1]) == "captive", "a captive man keeps his register row")
	check(Army.state(Game.world)["roll"].has(str(foes[0].uid)) and not _person(foes[0]).is_empty(), "an enemy prisoner stays on his realm's roll")
	check(int(fam_town["econ"]["pop"]) == pop and (fam["pp"] as Array).size() == recs, "the family sync deletes nobody at home for a captive")
	_advance(8)
	check(Prisoners.held(Game).size() == 2 and Prisoners.captives(Game).size() == 2, "prisoners on both sides survive a week")
	check(Persons._unit(noble.uid) == noble, "the captive's Unit can be found by its person")
	check(not Mobilization.household_candidates(Game).any(func(row): return str(row["person_uid"]) == str(noble_person[Persons.PERSON_UID])), "a captive cannot be enlisted again")

	# --- Ransom: their realm pays your house purse; the prisoner goes home through the native release.
	var standing := Diplomacy.earned(Game, enemy)
	var price := Prisoners.price(Game, rec0)
	var purse := _purse(); var treasury := _treasury(enemy)
	var pid0 := int(_person(foes[0])[0]) if not _person(foes[0]).is_empty() else -1   # home again he is found by register id; the unit link is cleared
	var fam0: Dictionary = People.fam_of(Game.world["towns"][foes[0].home_town], foes[0].family)
	var offer := Prisoners.preview(Game, "ransom", foes[0].uid)
	check(offer.get("ok", false), "ransom offer: " + str(offer.get("text", "")))
	var done := Prisoners.confirm(Game, "ransom", foes[0].uid, -1, offer.get("review", {}))
	check(done.get("ok", false), "ransom confirmed")
	check(is_equal_approx(_purse(), purse + price) and is_equal_approx(_treasury(enemy), treasury - price), "ransom coin moves from their realm to your house purse exactly once")
	check(Diplomacy.earned(Game, enemy) == standing + Diplomacy.RANSOM, "ransom improves standing")
	check(Prisoners._find(Prisoners.held(Game), foes[0].uid).is_empty() and not Army.state(Game.world)["roll"].has(str(foes[0].uid)), "the ransomed man leaves your prisons and his realm's roll")
	var home0 := Persons.by_pid(fam0, pid0)
	check(home0.size() > 5 and str(home0[4]) == "" and int(home0[5]) == -1, "the ransomed man is home with his family")
	check(not Prisoners.confirm(Game, "ransom", foes[0].uid).get("ok", false), "a ransom cannot be taken twice")
	# A realm that cannot pay is refused; nothing moves.
	Game.world["factions"][enemy]["treasury"] = 0.0
	purse = _purse()
	check(not Prisoners.preview(Game, "ransom", foes[1].uid).get("ok", false), "a realm without coin cannot ransom")
	check(not Prisoners.confirm(Game, "ransom", foes[1].uid).get("ok", false) and is_equal_approx(_purse(), purse) and Prisoners.held(Game).size() == 1, "a refused ransom changes nothing")
	Game.world["factions"][enemy]["treasury"] = 500.0 * Item.COIN

	# --- Exchange: they will not trade your noble for a soldier, only for someone worth as much.
	check(not Prisoners.preview(Game, "exchange", noble.uid, foes[1].uid).get("ok", false), "a noble is not traded for a soldier")
	var rec1: Dictionary = Prisoners._find(Prisoners.held(Game), foes[1].uid)
	print("prisoners033: kinds ", Prisoners.kind_of(Game, rec0), " ", Prisoners.kind_of(Game, rec1), " ", Prisoners.kind_of(Game, Prisoners._find(Prisoners.captives(Game), men[1].uid)))
	var cap_man1: Dictionary = Prisoners._find(Prisoners.captives(Game), men[1].uid)
	var stale := Prisoners.preview(Game, "pay", men[1].uid)
	check(stale.get("ok", false), "a ransom can be offered for your man: " + str(stale.get("text", "")))
	var was := bool(cap_man1.get("household", false))
	cap_man1["household"] = not was   # the terms change (his worth) after the review was shown
	purse = _purse()
	check(not Prisoners.confirm(Game, "pay", men[1].uid, -1, stale["review"]).get("ok", false) and is_equal_approx(_purse(), purse), "a changed review is rejected")
	cap_man1["household"] = was
	rec1["noble"] = true
	check(Prisoners.price(Game, rec1) == 60 * Item.COIN, "a noble prisoner is worth a noble")
	check(Prisoners.exchange_pick(Game, noble.uid) == foes[1].uid, "the fair default pick for your noble is their noble")

	# --- Save and load keep both sides' records and their actual bodies.
	noble.body.blood = noble.body.blood_max * 0.6   # a hurt captive: his body must reload as it was
	var blood := noble.body.blood
	Game.save_game(); Game.wait_save()
	Game.world = {}; Game.rep = {}
	check(Game.load_game(), "real save reloads")
	var held_after: Array = Prisoners.held(Game)
	var caps_after: Array = Prisoners.captives(Game)
	check(held_after.size() == 1 and caps_after.size() == 2, "prisoner and captive records survive save/load")
	cap_noble = Prisoners._find(caps_after, noble.uid)
	var noble2 = cap_noble.get("unit")
	check(noble2 is Unit and noble2.uid == noble.uid and noble2.name == noble.name, "the captive's Unit reloads with its identity")
	if noble2 is Unit: check(is_equal_approx(noble2.body.blood, blood), "the captive's body reloads as it was")
	check(bool(Prisoners._find(held_after, foes[1].uid).get("noble", false)), "record fields reload")
	var noble_uid := str(noble_person[Persons.PERSON_UID])
	var man_uid: int = men[1].uid
	var other_uid: int = foes[1].uid

	# --- Exchange your noble for their noble: both go home.
	standing = Diplomacy.earned(Game, enemy)
	purse = _purse()
	offer = Prisoners.preview(Game, "exchange", noble2.uid, other_uid)
	check(offer.get("ok", false), "noble for noble exchange: " + str(offer.get("text", "")))
	done = Prisoners.confirm(Game, "exchange", noble2.uid, other_uid, offer.get("review", {}))
	check(done.get("ok", false), "exchange confirmed")
	check(Prisoners.held(Game).is_empty() and Prisoners.captives(Game).size() == 1, "an exchange frees one on each side")
	check(Mobilization.reserves(Game).any(func(u): return u.uid == noble2.uid), "your noble is home as a reserve, the same Unit")
	var home := Dynasty._person(Game, noble_uid)
	check(not home.is_empty() and str(home["person"][4]) == "reserve", "your noble's register row says reserve")
	check(is_equal_approx(_purse(), purse) and Diplomacy.earned(Game, enemy) == standing, "an exchange moves no coin or standing")

	# --- Pay a ransom for your own man; a short purse is refused first.
	var cap_man: Dictionary = Prisoners._find(Prisoners.captives(Game), man_uid)
	price = Prisoners.price(Game, cap_man)
	var unit_man: Unit = cap_man["unit"]
	var town2: Dictionary = Game.world["towns"][unit_man.home_town]
	var pop2 := int(town2["econ"]["pop"])
	var saved_purse := _purse()
	Feudal._payer(Game)["purse"] = float(price - 1)
	check(not Prisoners.confirm(Game, "pay", man_uid).get("ok", false) and Prisoners.captives(Game).size() == 1, "a short house purse cannot pay a ransom")
	Feudal._payer(Game)["purse"] = saved_purse
	treasury = _treasury(enemy)
	offer = Prisoners.preview(Game, "pay", man_uid)
	check(offer.get("ok", false), "pay ransom offer: " + str(offer.get("text", "")))
	done = Prisoners.confirm(Game, "pay", man_uid, -1, offer.get("review", {}))
	check(done.get("ok", false), "paid ransom confirmed")
	check(is_equal_approx(_purse(), saved_purse - price) and is_equal_approx(_treasury(enemy), treasury + price), "your ransom coin goes to the captor's treasury exactly once")
	check(Prisoners.captives(Game).is_empty() and Mobilization.reserves(Game).has(unit_man), "your man is home as a reserve")
	check(int(town2["econ"]["pop"]) == pop2 + 1 and _st(unit_man) == "reserve", "he is counted at home again")

	# --- Release, death in captivity, and a record from before v0.033.
	var wb2: Dictionary = Game.world["warbands"].get(_band_id, {})
	var survivors: Array = (wb2.get("units", []) as Array).filter(func(u): return u.family >= 0 and not _person(u).is_empty())
	check(survivors.size() >= 2, "the band still has registered men to take")
	if survivors.size() < 2: return _finish()
	var third: Array = survivors.slice(2, 3)
	_clash(0, [survivors[0], survivors[1]] + third, ["unconscious", "unconscious", "unconscious"].slice(0, 2 + third.size()))
	check(Prisoners.held(Game).size() == 2 + third.size(), "a second fight takes more prisoners")
	standing = Diplomacy.earned(Game, enemy)
	purse = _purse()
	done = Prisoners.confirm(Game, "release", survivors[0].uid)
	check(done.get("ok", false) and Prisoners.held(Game).size() == 1 + third.size(), "release frees a prisoner")
	check(Diplomacy.earned(Game, enemy) == standing + Diplomacy.RELEASE and is_equal_approx(_purse(), purse), "release improves standing and costs nothing")
	if not third.is_empty():   # a mass release is one gesture: standing rises once per realm per day
		check(Prisoners.preview(Game, "release", third[0].uid)["text"].contains("already rose"), "the review says standing already rose today")
		check(Prisoners.confirm(Game, "release", third[0].uid).get("ok", false) and Diplomacy.earned(Game, enemy) == standing + Diplomacy.RELEASE, "a second release the same day adds no standing")
	survivors[1].dead = true
	_advance(1)
	check(Prisoners.held(Game).is_empty(), "a prisoner who died is dropped from the list")
	check(str(Prisoners.state(Game)["log"][-1]["text"]).contains("died in captivity"), "a death in captivity is logged")
	# An enemy prisoner whose register row cannot be found (his family moved) is still held, not dead.
	if (wb2.get("units", []) as Array).size() > 0:
		var mover: Unit = (wb2["units"] as Array)[0]
		_clash(0, [mover], ["unconscious"])
		var moved_rec := Prisoners._find(Prisoners.held(Game), mover.uid)
		if not moved_rec.is_empty():
			moved_rec["family"] = 99999   # the address no longer resolves
			_advance(1)
			check(not Prisoners._find(Prisoners.held(Game), mover.uid).is_empty(), "an enemy prisoner without a register row is still held")
			check(Prisoners.confirm(Game, "release", mover.uid).get("ok", false), "and can still be released")
	Prisoners.held(Game).append({"uid": 999999, "name": "Old Record", "faction": enemy, "home_town": "", "family": -1, "day": 0.0})
	check(not Prisoners.preview(Game, "ransom", 999999).get("ok", false), "a pre-v0.033 record without a Unit cannot be bargained for")
	Prisoners.held(Game).clear()
	check((Game.world["log"] as Array).any(func(line): return str(line).contains("ransomed")), "ransoms reach the campaign log")
	return _finish()
