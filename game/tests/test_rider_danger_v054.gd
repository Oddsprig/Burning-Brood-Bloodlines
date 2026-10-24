extends RefCounted
## One DevTools start world; native bodies/casualty hooks, no campaign-day simulation.
## Run with --test=res://tests/test_rider_danger_v054.gd --watchdog=60.
const BattleScene = preload("res://battle/battle.gd")
var fails := 0
var checks := 0
var rider: Unit
var dragon: Unit
var other: Unit
var dragon_uid := ""
var person_uid := ""
var town_id := ""
var fresh_body: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL rider danger v054: " + message)

func suitable(choice: Dictionary) -> bool:
	var tid := str(choice["town_id"])
	var person := Dynasty.person(Game, str(choice["ruler_uid"]))
	return str(person.get("race", "")) == "human" and int(person.get("unit_uid", -1)) < 0 \
		and str(person.get("state", "")) == "" and not Dynasty.heir(Game, tid).is_empty()

func coins() -> float:
	var total := float(Game.gold)
	for town: Dictionary in Game.world["towns"].values():
		var e: Dictionary = town["econ"]
		total += float(e.get("treasury", 0.0)) + float(e.get("farm_till", 0.0))
		for family: Dictionary in e.get("fams", []): total += float(family.get("purse", 0.0))
		for business: Dictionary in e.get("biz", []): total += float(business.get("till", 0.0))
	for faction: Dictionary in Game.world["factions"].values(): total += float(faction.get("treasury", 0.0))
	for band: Dictionary in Game.world["warbands"].values(): total += float(band.get("gold", 0.0))
	return total

func grain() -> int:
	var total := int(TownEcon.goods_lost.get("grain", 0))
	for town: Dictionary in Game.world["towns"].values():
		if TownEcon.has_econ(town): total += TownEcon.town_total(town["econ"], "grain")
	for band: Dictionary in Game.world["warbands"].values():
		total += int(band.get("cargo", {}).get("goods", {}).get("grain", 0))
	return total + int(Game.world.get("company_goods", {}).get("grain", 0))

func seed_for(fate: String, downed: bool, damage: float, flying: bool = false) -> int:
	for battle_seed: int in 4096:
		if str(DragonCombat.rider_roll(battle_seed, dragon_uid, person_uid, downed, flying, damage, 0.0)["outcome"]) == fate:
			return battle_seed
	check(false, "a bounded seed search finds " + fate)
	return 0

func result_of(sim: BattleSim) -> Dictionary:
	var screen := BattleScene.new()
	screen.sim = sim
	var result: Dictionary = screen.build_result()
	screen.free()
	return result

func settle(battle_seed: int, downed: bool, damage: float = 0.0, killed: bool = false, earlier_round: bool = false) -> Dictionary:
	# Restore only the dragon fixture, without advancing the world or replacing its saved Unit.
	dragon.body = BodyState.from_dict(fresh_body.duplicate(true))
	DragonCombat.sync_profile(Game, dragon_uid)
	Game.pending_battle = {"seed": battle_seed}
	var receipt := DragonCombat.admission_receipt(Game, [dragon])
	check(not receipt.is_empty(), "actual reviewed native dragon is admitted")
	var sim := BattleSim.new()
	sim.setup([dragon, rider], [other], battle_seed, {"w": 12, "h": 7, "verbose": false, "history_events": 1})
	if damage > 0.0:
		var part := dragon.body.wound_part("torso_upper")
		for layer: Dictionary in part["layers"]:
			if str(layer["tissue"]) != "muscle": continue
			var f: Fighter = sim.fighters[0]
			sim._wound_layer(f, "torso_upper", dragon.body.part_def("torso_upper"), layer,
				sim._ldef("torso_upper", dragon.body.part_def("torso_upper"), str(layer["name"])), damage, "bruised", false, false)
			break
	if downed:
		sim._fall(sim.fighters[0], "pain", 1)
		sim._knock_out(sim.fighters[0], "pain")
		if killed: sim._kill(sim.fighters[0], -1, "native fixture collapse")
		else:
			# The dragon recovers its feet: final state alone would lose this fall.
			sim.fighters[0].state = "ready"
			sim.fighters[0].prone = false
	sim._trim_history()
	var result := result_of(sim)
	if earlier_round:
		# final_result retains all fought side rosters, but only the last round's fighter list.
		result["fighter_units"] = [rider, other]
		result["fighter_states"] = ["ready", "ready"]
	var coin_before := coins()
	var grain_before := grain()
	var campaign_rng := Game.rng.state
	var sim_rng := sim.rng.state
	var applied := DragonCombat.on_battle_result(Game, result, receipt)
	check(bool(applied["applied"]), "native issued receipt settles")
	check(absf(coins() - coin_before) < 0.001 and grain() == grain_before, "rider outcome balances coins and grain")
	check(Game.rng.state == campaign_rng and sim.rng.state == sim_rng, "danger does not consume campaign/combat RNG streams")
	var outcomes: Array = result.get("rider_outcomes", [])
	check(outcomes.size() == 1, "down/wound produces exactly one mounted rider outcome")
	if not outcomes.is_empty():
		var outcome: Dictionary = outcomes[0]
		check(str(outcome["rider_person_uid"]) == person_uid and rider.name in str(outcome["text"]) and dragon.name in str(outcome["text"]), "report names the original rider and mount")
		var logs: Array = sim.combat_journal.page(0, -1, 64)
		check(logs.any(func(log: Dictionary): return str(log["event_type"]) == "rider_danger" and BattleSim.render_entry(log["entry"])["text"] == outcome["text"]), "full battle journal names the same outcome")
	var event_count: int = result["events"].size()
	var death_count: int = Census._book(Game.world["towns"][town_id]["econ"])["deaths"].size()
	check(not bool(DragonCombat.on_battle_result(Game, result, receipt)["applied"]), "receipt cannot apply a second time")
	check(result["events"].size() == event_count and Census._book(Game.world["towns"][town_id]["econ"])["deaths"].size() == death_count, "replay adds no event or death")
	sim.combat_journal.dispose()
	return result

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "DevTools start world loads")
		return fails
	town_id = DevTools.choose_house(Game, suitable)
	check(town_id != "", "native human ruler with a lawful heir is available")
	if town_id == "": return fails
	DevTools.stand_at(Game, town_id)
	person_uid = str(Dynasty.selected(Game)["ruler_uid"])
	var enlisted := Mobilization.enlist_household(Game, person_uid)
	check(bool(enlisted.get("ok", false)), "real ruler enlists through native service")
	if not bool(enlisted.get("ok", false)): return fails
	rider = enlisted["unit"]
	rider.equip.clear() # Fixture: compare no armour with actual v0.029 body/helm templates below.
	var owner := Dragons._person(Game, person_uid)
	Game.world["dragons"] = {"schema": 1, "next_id": 1, "records": {}, "pairs": {}, "initialized": true}
	var mounted := Dragons._make(Game, "adult", town_id, owner, "v054:mounted", 0, "female")
	var unmounted := Dragons._make(Game, "adult", town_id, owner, "v054:unmounted", 0, "male")
	dragon_uid = str(mounted["id"])
	mounted["rider_person_uid"] = person_uid
	DragonCombat.prepare_world(Game)
	dragon = DragonCombat._unit(Game, dragon_uid)
	other = DragonCombat._unit(Game, str(unmounted["id"]))
	fresh_body = dragon.body.to_dict()
	check(bool(DragonCombat.participation_order(Game, dragon_uid, true, DragonCombat.participation_preview(Game, dragon_uid, true)).get("ok", false)), "native defence order admits the bonded dragon")
	var unhurt_seed := seed_for("unhurt", true, 0.0)
	var first := settle(unhurt_seed, true, 0.0, false, true)
	var again := settle(unhurt_seed, true, 0.0, false, true)
	check(first.get("rider_outcomes", []) == again.get("rider_outcomes", []), "same battle seed produces identical actual rider outcome across different receipts")

	var sim := BattleSim.new()
	sim.setup([other], [dragon], 54, {"combat_journal": false})
	sim._fall(sim.fighters[0], "pain", 1)
	var result := result_of(sim)
	Game.pending_battle = {"seed": 54}
	var no_rider := DragonCombat.admission_receipt(Game, [other])
	DragonCombat.on_battle_result(Game, result, no_rider)
	check(no_rider.is_empty() and (result.get("rider_outcomes", []) as Array).is_empty(), "unmounted native dragon produces no rider outcome")

	var bare := DragonCombat.rider_protection(rider)
	rider.equip["body"] = Item.make("mail_shirt", "copper")
	rider.equip["helm"] = Item.make("closed_helm", "copper")
	var armoured := DragonCombat.rider_protection(rider)
	check(armoured > bare, "real v0.029 refit slots provide protection")
	var bare_hurt := 0
	var safe_hurt := 0
	var bare_dead := 0
	var safe_dead := 0
	for battle_seed: int in 512:
		var a := DragonCombat.rider_roll(battle_seed, dragon_uid, person_uid, true, true, 0.8, bare)
		var b := DragonCombat.rider_roll(battle_seed, dragon_uid, person_uid, true, true, 0.8, armoured)
		if str(a["outcome"]) != "unhurt": bare_hurt += 1
		if str(b["outcome"]) != "unhurt": safe_hurt += 1
		if str(a["outcome"]) == "killed": bare_dead += 1
		if str(b["outcome"]) == "killed": safe_dead += 1
		var ranks := {"unhurt": 0, "wounded": 1, "killed": 2}
		check(int(ranks[b["outcome"]]) <= int(ranks[a["outcome"]]), "armour never worsens the same seeded fall")
		var light := DragonCombat.rider_roll(battle_seed, dragon_uid, person_uid, false, true, 0.8, bare)
		check(str(light["outcome"]) != "killed" and float(light["wound_damage"]) < float(a["wound_damage"]) and float(light["wound_chance"]) < float(a["wound_chance"]), "upright wound is less likely, lighter and cannot kill")
	check(safe_hurt < bare_hurt and safe_dead < bare_dead, "armour lowers wound/death rates across 512 seeded trials")
	var ground := DragonCombat.rider_roll(1, dragon_uid, person_uid, true, false, 0.0, bare)
	var damaged := DragonCombat.rider_roll(1, dragon_uid, person_uid, true, false, 1.0, bare)
	var air := DragonCombat.rider_roll(1, dragon_uid, person_uid, true, true, 1.0, bare)
	check(float(damaged["kill_chance"]) > float(ground["kill_chance"]) and float(air["kill_chance"]) > float(damaged["kill_chance"]), "native damage and flight each increase fall risk")
	rider.equip["body"].broken = true
	rider.equip["helm"].broken = true
	check(DragonCombat.rider_protection(rider) == bare, "broken armour offers no protection")
	rider.equip.clear()
	rider.equip["clothing"] = Item.make("gambeson", "linen")
	check(DragonCombat.rider_protection(rider) > bare, "v0.029 padded fallback also protects the rider")
	rider.equip.clear()

	var wounded := settle(seed_for("wounded", false, 0.25), false, 0.25)
	check(str(wounded.get("rider_outcomes", [{}])[0].get("outcome", "")) == "wounded" and rider.body.is_wounded(), "light wound persists on the rider's actual native body")
	var loc := Dynasty._person(Game, person_uid)
	check((loc["person"][Persons.HIST] as Array).any(func(event: Array): return str(event[1]) == "wound" and dragon.name in str(event[2])), "rider record contains the existing person-wound history")
	check(float(HealthReport.describe(rider).get("heal_days", 0.0)) > 0.0, "native recovery timer assesses the rider wound")

	var heir := Dynasty.selected_heir(Game)
	var book := Census._book(Game.world["towns"][town_id]["econ"])
	var before_deaths: int = book["deaths"].size()
	var coin_before := coins()
	var grain_before := grain()
	var killed := settle(seed_for("killed", true, 0.0), true, 0.0, true)
	check(rider.dead and Dynasty._person(Game, person_uid).is_empty(), "killed rider leaves the living register through normal casualties")
	check(book["deaths"].size() == before_deaths + 1 and book["death_ids"].has(person_uid), "normal census death is recorded exactly once")
	CampaignWorld.on_battle_result(Game, killed)
	check(book["deaths"].size() == before_deaths + 1, "ordinary battle death callback cannot count the rider again")
	Feudal.finish(Game)
	check(not heir.is_empty() and str(Game.world["player_house"]["ruler_uid"]) == str(heir.get("person_uid", "")), "normal lawful succession installs the rider's heir")
	check(absf(coins() - coin_before) < 0.001 and grain() == grain_before, "death and succession conserve native coins and grain")
	check(Time.get_ticks_msec() - started < 60000, "whole DevTools test completes under 60 seconds")
	print("Rider danger v054: %d checks, %d failures." % [checks, fails])
	rider = null
	dragon = null
	other = null
	return fails
