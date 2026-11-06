extends RefCounted
## Native treaty/player-action boundaries and the existing wall-holding tick.
## Task-local Normal/one-day save only; no large battle or elapsed economy run.
const M = preload("res://tests/test_militia_tick_v011.gd")
var checks := 0
var fails := 0
var completed := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL v092: ", why)

func run(tree: SceneTree) -> int:
	var path := "user://truce_v092_%d.json" % OS.get_process_id()
	check(await DevTools.start_world(tree, path), "native task-local Normal one-day world")
	if fails > 0: return fails
	_treaty_and_player_guards()
	_saved_expiry(path)
	_wall_tick()
	check(completed == 3, "all three native groups finished")
	print("TRUCE/MILITIA v092 groups=", completed, "/3 checks=", checks, " failures=", fails)
	return fails

func _pair() -> Dictionary:
	return Game.world["diplo"]["pairs"][Diplomacy.pair_key("middle_kingdom", "northern_clans")]

func _treaty_and_player_guards() -> void:
	var w: Dictionary = Game.world
	var a := "middle_kingdom"; var b := "northern_clans"
	var home := str(w["factions"][a]["capital"])
	check(Dynasty.select_city(Game, home), "choose a real existing ruling household")
	check(DevTools.raise_army(Game, home, 2) > 0 and not Game.deployed_units().is_empty(),
		"native paid muster supplies actual deployed troops for the player guard")
	var p := _pair()
	p["state"] = Diplomacy.WAR; p["dynasty"] = false; p["treaty_alliance"] = false
	p["pact_until"] = 0; p["truce"] = 0; p["rel"] = -90.0
	Diplomacy._sync_wars(w)
	var d := int(w["diplo"]["day"])
	Diplomacy._set_state(Game, p, Diplomacy.HOSTILE)
	Diplomacy._sync_wars(w)
	var left := Diplomacy.truce_left(w, a, b)
	check(left >= 60 and left <= 120 and int(p["truce"]) == d + left, "native peace stores a 60-120 day deadline")
	check(left == Diplomacy.roll_truce(w, Diplomacy.pair_key(a, b), d), "treaty length uses its own repeatable native seed")
	var rng_state := Game.rng.state
	var lengths := {}
	for day in range(1, 41): lengths[Diplomacy.roll_truce(w, "fixture-a|fixture-b", day)] = true
	check(lengths.size() > 10 and Game.rng.state == rng_state, "different treaties vary without consuming campaign RNG")
	check(Diplomacy.truce_text(w, a, b) == "truce, %d days left" % left, "relations countdown reports the stored deadline")
	check(not Diplomacy.fights(w, a, b) and not Diplomacy.fights(w, b, a), "contact combat is suppressed in both directions")
	check(Diplomacy.peace_bound(w, a, b), "the player-action boundary includes a live truce")
	var before := p.duplicate(true)
	var news := (w["diplo"]["news"] as Array).size()
	Diplomacy._set_state(Game, p, Diplomacy.WAR)
	check(p == before and (w["diplo"]["news"] as Array).size() == news, "direct war transition cannot bypass or erase a live treaty")
	var u := Unit.create("human", b)
	var enemy := {"id": "truce092_enemy", "kind": "patrol", "faction": b, "units": [u], "pos": w["towns"][home]["pos"]}
	var car := {"id": "truce092_car", "kind": "caravan", "faction": b, "units": [u], "pos": enemy["pos"]}
	w["warbands"][enemy["id"]] = enemy; w["warbands"][car["id"]] = car
	check(not Militia.is_threat(Game, {"id": "fixture_militia", "faction": a}, enemy), "native militia does not attack a treaty partner")
	check(not Caravans.can_raid(Game, car["id"]), "player cannot raid the partner's caravan")
	var native_car := {"kind": "caravan", "faction": a}
	check(not Caravans.is_prey(w, enemy, native_car), "AI caravan attack predicate respects the same truce")
	var pending := Game.pending_battle.duplicate(true)
	var earned := float(w["diplo"]["player"][b]["earned"])
	CampaignWorld.engage(Game, enemy["id"])
	check(Game.pending_battle == pending and w.get("encounter", "") != enemy["id"]
		and float(w["diplo"]["player"][b]["earned"]) == earned, "actual player engage refuses before changing battle or reputation")
	var target := str(w["factions"][b]["capital"])
	for kind in ["raid", "siege"]:
		var preview := Warfare.preview(Game, target, kind)
		check(not bool(preview.get("ok", false)) and str(preview["reason"]).contains("truce"), "settlement " + kind + " reports the live treaty")
	w["diplo"]["player"][b]["earned"] = -100.0
	check(Diplomacy.standing(Game, b) <= -50 and not Diplomacy.player_hostile(Game, b), "negative standing cannot trigger player pursuit during the realm's truce")
	w["warbands"].erase(enemy["id"]); w["warbands"].erase(car["id"])
	completed += 1

func _saved_expiry(path: String) -> void:
	var a := "middle_kingdom"; var b := "northern_clans"
	var until := int(_pair()["truce"])
	var left := Diplomacy.truce_left(Game.world, a, b)
	Game.SAVE_PATH = path; Game.save_game(); Game.wait_save()
	check(Game.load_game(), "native disk save reloads the treaty")
	check(typeof(_pair()["truce"]) == TYPE_INT and int(_pair()["truce"]) == until and Diplomacy.truce_left(Game.world, a, b) == left, "saved deadline and exact countdown survive native load")
	var w: Dictionary = Game.world
	var first := int(w["diplo"]["day"])
	for d in range(first + 1, until):
		_pair()["rel"] = -90.0
		Game.day = float(d); Diplomacy.daily(Game, d)
		check(_pair()["state"] != Diplomacy.WAR and not Diplomacy.fights(w, a, b), "daily war picker respects day %d before expiry" % d)
	check(Diplomacy.truce_left(w, a, b) == 1 and Diplomacy.truce_text(w, a, b) == "truce, 1 day left", "last protected day has singular countdown")
	w["diplo"]["day"] = until; Game.day = float(until)
	check(not Diplomacy.in_truce(w, a, b) and Diplomacy.truce_text(w, a, b) == "" and Diplomacy.fights(w, a, b), "hostile contact resumes at the exact stored expiry")
	check(not Diplomacy.peace_bound(w, a, b), "expiry releases the shared player-action guard")
	Diplomacy._set_state(Game, _pair(), Diplomacy.WAR)
	check(_pair()["state"] == Diplomacy.WAR and int(_pair()["truce"]) == 0, "new war is possible after expiry and clears the elapsed treaty")
	check(Caravans.is_prey(w, {"kind": "patrol", "faction": b}, {"kind": "caravan", "faction": a}), "AI war raids resume after expiry")
	# Positive control: the same native player entry point can start a battle
	# once the treaty expires. No BattleSim or engagement is executed here.
	check(not Game.deployed_units().is_empty(), "saved paid muster still supplies the positive engagement control")
	var enemy := {"id": "truce092_expired", "kind": "patrol", "faction": b,
		"home": str(w["factions"][b]["capital"]), "units": [Unit.create("human", b)], "pos": w["party"]["pos"]}
	var bands: Dictionary = w["warbands"]
	w["warbands"] = {enemy["id"]: enemy} # bounded entry-point fixture, no nearby allied reinforcements
	var pending := Game.pending_battle
	var screen: String = Game._active_screen
	CampaignWorld.engage(Game, enemy["id"])
	check(str(Game.pending_battle.get("warband_id", "")) == enemy["id"] and w["encounter"] == enemy["id"]
		and Game._active_screen == "battle", "actual player engage succeeds at the expired treaty boundary")
	check((Game.pending_battle.get("enemy", []) as Array).size() == 1
		and (Game.pending_battle.get("allies", []) as Array).is_empty(), "positive control remains a bounded one-enemy handoff")
	Game.pending_battle = pending; w["encounter"] = ""
	Game.goto(screen)
	w["warbands"] = bands
	completed += 1

func _wall_tick() -> void:
	for power in [0.1, 1.0, 100.0, 10000.0]:
		check(not Militia.sallies(power * 1.24999, power), "militia holds below the actual 1.25 ratio")
		check(Militia.sallies(power * 1.25, power) and Militia.sallies(power * 1.25001, power), "exact threshold and above permit a native sally")
	var saved: Dictionary = Game.world
	var day := Game.day
	var old_contract: Dictionary = Game.contract
	Game.day = 1.0; Game.contract = {}
	var control := M.new()
	var w: Dictionary = control._fixture(false)
	var militia: Dictionary = w["warbands"]["mil_a"]
	militia["units"] = militia["units"].slice(0, 4)
	var enemy: Dictionary = w["warbands"]["main"]
	var counts := [militia["units"].size(), enemy["units"].size()]
	var rng := RandomNumberGenerator.new(); rng.seed = 92092
	Militia.tick(Game, rng)
	check(bool(militia["walls"]) and militia["path"] == [militia["anchor"]], "actual below-threshold tick holds inside the gate")
	check([militia["units"].size(), enemy["units"].size()] == counts, "wall hold does not resolve an outside battle")
	check(not WarAI.target_kind(militia), "field hunters never select the sheltered militia")
	Game.world = saved; Game.day = day; Game.contract = old_contract
	completed += 1
