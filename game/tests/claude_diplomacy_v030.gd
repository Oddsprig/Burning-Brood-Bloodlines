extends RefCounted
## v0.030: reviewed treaties, living dynasty ties, calls to war, battle support and real save/load.
var checks := 0
var fails := 0
const ALLY := "moon_court"
const PACT := "northern_clans"
const ENEMY := "orc_horde"

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL diplomacy030: ", what)

func _finish() -> int:
	print("diplomacy030: %d checks, %d failures" % [checks, fails])
	return fails

func _pair(a: String, b: String) -> Dictionary:
	return Game.world["diplo"]["pairs"][Diplomacy.pair_key(a, b)]

func _standing(fid: String, value: int) -> void:
	Game.world["diplo"]["player"][fid]["comp"] = 0
	Game.world["diplo"]["player"][fid]["earned"] = float(value)
	Diplomacy._mirror(Game, fid)

func _act(fid: String, action: String) -> Dictionary:
	var preview := Diplomacy.action_preview(Game, fid, action)
	check(bool(preview.get("ok", false)), "%s preview available for %s" % [action, fid])
	if not preview.get("ok", false): return preview
	return Diplomacy.act(Game, fid, action, preview["review"])

func run(tree: SceneTree) -> int:
	await tree.process_frame
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	var generation := Game.new_game_begin(4242)
	while not Game.new_game_slice(generation, 8000): await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 8000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	Game.new_game_finalize()
	var chosen := false
	for c: Dictionary in Dynasty.choices(Game):
		var town: Dictionary = Game.world["towns"][c["town_id"]]
		if town["faction"] != "middle_kingdom": continue
		if str(town.get("econ", {}).get("head", {}).get("household_uid", "")) != str(c["household_uid"]): continue
		chosen = bool(HouseOnboarding.begin(Game, str(c["town_id"]), str(c["household_uid"])).get("ok", false))
		if chosen: break
	check(chosen, "selected an existing ruling house")
	if not chosen: return _finish()
	# Isolate diplomatic conditions while retaining the native world, persons and save machinery.
	for p: Dictionary in Game.world["diplo"]["pairs"].values():
		p["state"] = Diplomacy.NEUTRAL; p["rel"] = 0.0
		p["truce"] = 0; p["past"] = 0; p["held"] = Diplomacy.HOLD_DAYS
	Diplomacy._sync_wars(Game.world)
	if not _proposals(): return _finish()
	_wars()
	if not _round_trip(): return _finish()
	_dynasty()
	_expiry()
	return _finish()

func _proposals() -> bool:
	var mine := Diplomacy.player_realm(Game.world)
	_standing(ALLY, -80)
	var rejected := _act(ALLY, "alliance")
	check(rejected.get("ok", false) and not rejected.get("accepted", false), "low standing refuses an alliance")
	check(not _pair(mine, ALLY).get("treaty_alliance", false), "refusal stores no alliance")
	_standing(ALLY, 80)
	var old := Diplomacy.action_preview(Game, ALLY, "alliance")
	if not old.get("ok", false): return false
	_standing(ALLY, 0)
	check(not Diplomacy.act(Game, ALLY, "alliance", old["review"]).get("ok", false), "stale confirmation rejected")
	_standing(ALLY, 80)
	check(_act(ALLY, "alliance").get("accepted", false), "alliance accepted at high standing")
	check(_pair(mine, ALLY).get("treaty_alliance", false), "alliance stored in world diplomacy")
	_standing(PACT, 80)
	check(_act(PACT, "pact").get("accepted", false), "non-aggression pact accepted")
	var pact := _pair(mine, PACT)
	check(int(pact.get("pact_until", 0)) == maxi(int(Game.day), int(Game.world["diplo"]["day"])) + 8 * Calendar.DAYS_PER_SEASON, "pact lasts two calendar years")
	Diplomacy._set_state(Game, pact, Diplomacy.WAR)
	check(not Diplomacy.at_war(Game.world, mine, PACT) and not Diplomacy.fights(Game.world, mine, PACT), "pact blocks war and hostile contact")
	check(Diplomacy.treaty_text(Game, ALLY) == "Allied to your realm", "map alliance line")
	check(Diplomacy.treaty_text(Game, PACT).begins_with("Pact with your realm until year "), "map pact line")
	check(not Diplomacy.action_preview(Game, mine, "alliance").get("ok", false), "cannot propose a treaty to your own realm")
	for town: Dictionary in Game.world["towns"].values():
		if town["faction"] == PACT:
			check(not Warfare.preview(Game, str(town["id"]), "raid").get("ok", false), "pact prevents settlement attacks")
			break
	return bool(_pair(mine, ALLY).get("treaty_alliance", false)) and int(pact.get("pact_until", 0)) > int(Game.day)

func _wars() -> void:
	var mine := Diplomacy.player_realm(Game.world)
	var war := _pair(mine, ENEMY)
	Diplomacy._set_state(Game, war, Diplomacy.WAR)
	Diplomacy._sync_wars(Game.world)
	_standing(ALLY, Diplomacy.CALL_STANDING)
	Diplomacy.call_allies(Game)
	check(not Diplomacy.at_war(Game.world, ALLY, ENEMY), "ally at the threshold does not answer")
	_standing(ALLY, 80)
	_pair(ALLY, ENEMY)["pact_until"] = int(Game.world["diplo"]["day"]) + 1
	Diplomacy.call_allies(Game)
	check(not Diplomacy.at_war(Game.world, ALLY, ENEMY), "ally respects its own non-aggression pact")
	_pair(ALLY, ENEMY)["pact_until"] = 0
	Diplomacy.call_allies(Game)
	check(Diplomacy.at_war(Game.world, ALLY, ENEMY), "willing ally joins the player's war")
	var serial := int(war["war_serial"])
	check(int(_pair(mine, ALLY).get("calls", {}).get(ENEMY, -1)) == serial, "call recorded against this war")
	var news_count: int = Game.world["diplo"]["news"].size()
	Diplomacy.call_allies(Game)
	check(Game.world["diplo"]["news"].size() == news_count, "repeated call adds no declaration")
	check(str(Game.world["diplo"]["news"][-1]["text"]).contains("answers"), "call to war is logged")
	var rng := RandomNumberGenerator.new(); rng.seed = 30
	var unit := Factory.make_troop(rng, ALLY, DB.factions[ALLY]["troops"][0], 1)
	var bands: Dictionary = Game.world["warbands"]
	Game.world["warbands"] = {"v030_ally": {"kind": "assault", "faction": ALLY, "pos": Vector2.ZERO, "units": [unit]}}
	var power := Diplomacy.ally_power(Game.world, mine, ENEMY, Vector2.ZERO, [])
	check(power > 0.0 and is_equal_approx(power, CampaignWorld.band_power([unit])), "nearby allied field army supplies battle power")
	check(Diplomacy.ally_power(Game.world, mine, ENEMY, Vector2.ZERO, ["v030_ally"]) == 0.0, "excluded armies do not join twice")
	check(Diplomacy.ally_power(Game.world, mine, ENEMY, Vector2(1000, 0), []) == 0.0, "distant armies do not join")
	Game.world["warbands"] = bands
	Diplomacy._set_state(Game, _pair(ALLY, ENEMY), Diplomacy.NEUTRAL)
	Diplomacy.call_allies(Game)
	check(not Diplomacy.at_war(Game.world, ALLY, ENEMY), "peace does not recall an ally into the same war")
	var pair := _pair(mine, ALLY)
	pair["state"] = Diplomacy.HOSTILE; pair["rel"] = -95.0
	Diplomacy._set_state(Game, pair, Diplomacy.WAR)
	check(not Diplomacy.at_war(Game.world, mine, ALLY), "sworn alliance blocks a declaration even at negative relations")
	for i in 14:
		Game.day = float(int(Game.world["diplo"]["day"]) + 1)
		Diplomacy.daily(Game, int(Game.day))
	check(Diplomacy.allied(Game.world, mine, ALLY) and not Diplomacy.fights(Game.world, mine, ALLY), "alliance holds through daily drift and weekly war rolls")

func _round_trip() -> bool:
	var mine := Diplomacy.player_realm(Game.world)
	var until := int(_pair(mine, PACT)["pact_until"])
	var serial := int(_pair(mine, ALLY).get("calls", {}).get(ENEMY, -1))
	Game.save_game()
	Game.wait_save()
	Game.world = {}; Game.rep = {}
	var loaded := Game.load_game()
	check(loaded, "real save reloads")
	if not loaded or Game.world.is_empty(): return false
	check(_pair(mine, ALLY).get("treaty_alliance", false), "alliance survives save/load")
	check(int(_pair(mine, PACT)["pact_until"]) == until and typeof(_pair(mine, PACT)["pact_until"]) == TYPE_INT, "pact and integer expiry survive save/load")
	check(int(_pair(mine, ALLY).get("calls", {}).get(ENEMY, -1)) == serial, "war call survives save/load")
	_standing(ALLY, -100)
	check(not CampaignWorld.is_hostile(Game, ALLY) and Diplomacy.friendly(Game, ALLY), "ally is non-hostile and supports battles despite low company standing")
	check(not Diplomacy.fights(Game.world, mine, ALLY), "loaded alliance prevents realm hostility")
	_standing(ALLY, 80)
	return true

func _dynasty() -> void:
	var mine := Diplomacy.player_realm(Game.world)
	var before := Diplomacy.earned(Game, ALLY)
	check(_act(ALLY, "break").get("accepted", false), "realm alliance can be broken")
	check(not _pair(mine, ALLY).get("treaty_alliance", false) and Diplomacy.earned(Game, ALLY) == before - Diplomacy.BREAK_STANDING, "breaking alliance removes treaty and costs standing")
	var town: Dictionary = {}
	for t: Dictionary in Game.world["towns"].values():
		if t["faction"] == ALLY and not Dynasty._person(Game, str(t.get("econ", {}).get("head", {}).get("person_uid", ""))).is_empty():
			town = t; break
	check(not town.is_empty(), "foreign ruling house available for marriage fixture")
	if town.is_empty(): return
	var head: Dictionary = town["econ"]["head"]
	var member_uid := str(Game.world["player_house"]["ruler_uid"])
	var spouse_uid := str(head["person_uid"])
	var a := Dynasty._person(Game, member_uid)
	var b := Dynasty._person(Game, spouse_uid)
	if a.is_empty() or b.is_empty():
		check(false, "both native marriage persons are living"); return
	# Link real native persons only for this lifecycle fixture; restore their previous links below.
	var old_a := str(Persons.g(a["person"], Persons.SPOUSE_UID, ""))
	var old_b := str(Persons.g(b["person"], Persons.SPOUSE_UID, ""))
	var old_state := str(b["person"][4])
	a["person"][Persons.SPOUSE_UID] = spouse_uid; b["person"][Persons.SPOUSE_UID] = member_uid
	var hh := str(head["household_uid"])
	var house := str(head["house_uid"])
	var al := {"member_uid": member_uid, "spouse_uid": spouse_uid, "town_id": str(town["id"]), "house_uid": house, "house_name": "Test dynasty"}
	Marriage.state(Game)["alliances"][hh] = al
	var pair := _pair(mine, ALLY)
	pair["state"] = Diplomacy.NEUTRAL; pair["rel"] = 0.0
	_standing(ALLY, 0)
	Diplomacy.sync_dynasty(Game)
	check(Diplomacy.standing(Game, ALLY) == Diplomacy.DYNASTY_STANDING and Diplomacy.earned(Game, ALLY) == 0, "marriage supplies a separate lasting standing bonus")
	check(is_equal_approx(Diplomacy.relation(Game.world, mine, ALLY), Diplomacy.DYNASTY_RELATION), "marriage supplies a separate realm relation bonus")
	check(not CampaignWorld.is_hostile(Game, ALLY) and not Diplomacy.fights(Game.world, mine, ALLY), "living ruling-house marriage prevents hostility")
	head["household_uid"] = "v030_other"; head["house_uid"] = "v030_other"
	Diplomacy.sync_dynasty(Game)
	check(Diplomacy.dynasty_bonus(Game, ALLY) == 0, "a house which no longer rules loses the realm bonus")
	_standing(ALLY, 40)
	var offer := Diplomacy.action_preview(Game, ALLY, "alliance")
	check(offer.get("accepts", false) and str(offer.get("reason", "")).contains("marriage ties +20"), "non-ruling marriage ties help acceptance")
	head["household_uid"] = hh; head["house_uid"] = house
	_standing(ALLY, 0)
	Diplomacy.sync_dynasty(Game)
	check(_act(ALLY, "break").get("accepted", false) and Diplomacy.dynasty_bonus(Game, ALLY) == 0, "breaking a marriage alliance removes its realm protection")
	Marriage.state(Game)["alliances"][hh] = al
	Diplomacy.sync_dynasty(Game)
	b["person"][4] = "dead"
	Marriage.daily(Game)
	check(not Marriage.state(Game)["alliances"].has(hh) and Diplomacy.dynasty_bonus(Game, ALLY) == 0, "spouse death dissolves the marriage alliance")
	check(Diplomacy.standing(Game, ALLY) == Diplomacy.earned(Game, ALLY) and is_equal_approx(Diplomacy.relation(Game.world, mine, ALLY), float(pair["rel"])), "death removes both bonuses without leaving accumulated reputation")
	a["person"][Persons.SPOUSE_UID] = old_a; b["person"][Persons.SPOUSE_UID] = old_b
	b["person"][4] = old_state

func _expiry() -> void:
	var mine := Diplomacy.player_realm(Game.world)
	var p := _pair(mine, PACT)
	var until := int(p["pact_until"])
	p["state"] = Diplomacy.HOSTILE; p["rel"] = -90.0; p["truce"] = 0
	Game.day = float(until - 1); Game.world["diplo"]["day"] = until - 1
	check(Diplomacy.pact_left(Game.world, mine, PACT) == 1 and not Diplomacy.fights(Game.world, mine, PACT), "pact protects its final day")
	Game.day = float(until); Game.world["diplo"]["day"] = until
	check(Diplomacy.pact_left(Game.world, mine, PACT) == 0 and Diplomacy.fights(Game.world, mine, PACT), "pact expires exactly at its saved day")
	Diplomacy._set_state(Game, p, Diplomacy.WAR)
	check(Diplomacy.at_war(Game.world, mine, PACT), "war is possible after pact expiry")
