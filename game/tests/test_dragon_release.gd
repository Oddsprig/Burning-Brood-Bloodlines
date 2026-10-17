extends RefCounted
## One actual Normal campaign, one history day, native current save/load.
var checks := 0
var fails := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func run(_tree: SceneTree) -> int:
	var old_size := WorldGen.gen_size
	var old_stretch := WorldGen.gen_stretch
	var old_history := CampaignWorld.presim_span_days
	WorldGen.gen_size = "normal"
	WorldGen.gen_stretch = WorldGen.STRETCH
	CampaignWorld.presim_span_days = 1
	Game.new_game(10461)
	check(not Game.world.has("dragons"), "history generation does not mint premature dragon holdings")
	check(CampaignWorld.presim_step(Game, 1) == 0, "native campaign completes exactly one history day")
	CampaignWorld.presim_finish(Game)
	var rows := Dragons.records(Game)
	check(not rows.is_empty(), "history finish creates real ruler dragon and egg holdings")
	check(Game.company.size() == 100, "native 100-person starting company retained")
	var eggs := 0
	var adults := 0
	var unique := {}
	var palettes := {}
	var original_profiles := {}
	var original_types := {}
	var dragon_names := {}
	var prior_rng_state: int = Game.rng.state
	for row: Dictionary in rows:
		unique[row["id"]] = true
		var profile: Dictionary = Dragons.physical_profile(Game, row)
		original_profiles[row["id"]] = profile
		original_types[row["id"]] = Dragons.type_label(row)
		check(bool(profile.get("active", false)) == (row["stage"] != "egg"), "only living dragons expose active physical profiles")
		var owner := Dynasty.person(Game, String(row["owner_person_uid"]))
		check(not owner.is_empty() and bool(owner.get("alive", false)) and owner.get("house_uid") == row["owner_house_uid"], "generated holding has actual living owner and house")
		check(Game.world["towns"].has(String(row["location_town_id"])), "generated holding stays at an existing settlement")
		if row["stage"] == "egg":
			eggs += 1; palettes[row["gem_id"]] = true
			check(String(row["name"]).ends_with(" Egg"), "egg has a gem-colour name")
			check(not Dragons.get_record(Game, row["mother_uid"]).is_empty() and not Dragons.get_record(Game, row["father_uid"]).is_empty(), "egg parents resolve to individual records")
		else:
			adults += 1
			dragon_names[row["name"]] = true
			check(String(row["name"]) != String(original_types[row["id"]]) and String(row["name"]) != "", "generated personal name differs from gem Dragon type")
	check(dragon_names.size() == adults, "generated parent adults have distinct personal names")
	check(Game.rng.state == prior_rng_state, "physical and type readers do not consume campaign RNG")
	check(unique.size() == rows.size(), "all generated dragon and egg IDs are unique")
	check(eggs == Dynasty.choices(Game).size(), "one founding egg per valid existing ruling seat")
	check(adults > 0 and adults % 2 == 0 and palettes.size() >= 8, "bounded parent pairs and varied eggs generated")
	var book: Dictionary = Game.world["dragons"].duplicate(true)
	var wealth := Barge.holdings(Game)
	var next_unit := Unit._next_uid
	Dragons.init_world(Game)
	check(Game.world["dragons"] == book, "repeated initializer does not mint assets")
	var picks := Dynasty.choices(Game)
	check(Dynasty.select_city(Game, String(picks[0]["town_id"])), "existing ruler selected")
	check(Game.world["dragons"] == book, "player city selection leaves all holdings unchanged")
	var own := Dragons.records(Game, String(Dynasty.selected(Game)["house_uid"]))
	check(not own.is_empty(), "selected existing family can inspect its own holdings")
	if own.is_empty(): return fails + 1
	var source: Dictionary = own[0]
	var recipient := {}
	for pick: Dictionary in picks:
		if String(pick["ruler_uid"]) != String(source["owner_person_uid"]):
			recipient = Dynasty.person(Game, String(pick["ruler_uid"])); break
	check(not recipient.is_empty(), "different existing tracked recipient found")
	var preview := Dragons.transfer_preview(Game, String(source["id"]), String(recipient.get("person_uid", "")))
	check(bool(preview.get("ok", false)), "current native owner can review a gift")
	check(bool(Dragons.transfer(Game, String(source["id"]), String(recipient.get("person_uid", "")), preview).get("ok", false)), "reviewed gift transfers original holding")
	var gifted := Dragons.get_record(Game, String(source["id"]))
	check(gifted["owner_person_uid"] == recipient.get("person_uid") and gifted["id"] == source["id"], "gift changes actual owner while retaining identity")
	check(gifted["custodian_person_uid"] == source["custodian_person_uid"] and gifted["location_town_id"] == source["location_town_id"] and gifted["rider_person_uid"] == "", "gift retains custody and location without creating a rider")
	check(absf(Barge.holdings(Game) - wealth) < 0.001 and Unit._next_uid == next_unit, "dragon holdings do not debit coin or create people/Units")
	book = Game.world["dragons"].duplicate(true)
	var original_names := {}
	for row: Dictionary in Dragons.records(Game): original_names[row["id"]] = [row["name"], row["gem_id"], row["morph_id"], row["appearance_seed"], row["mother_uid"], row["father_uid"]]
	Game.save_game()
	Game.world = {}
	check(Game.load_game(), "actual current-version save loads")
	var comparison = load("res://tests/test_dynasty_release.gd").new()
	check(comparison.same(Game.world.get("dragons", {}), book), "all individual records, history, owner and custody survive native save/load")
	check(absf(Barge.holdings(Game) - wealth) < 0.001 and Unit._next_uid == next_unit, "save/load keeps real coin and native identity counters")
	check(Dragons.get_record(Game, String(source["id"]))["owner_person_uid"] == recipient.get("person_uid"), "gift persists through full campaign load")
	for row: Dictionary in Dragons.records(Game):
		check(original_names[row["id"]] == [row["name"], row["gem_id"], row["morph_id"], row["appearance_seed"], row["mother_uid"], row["father_uid"]], "identity appearance and parents remain exact")
		check(comparison.same(original_profiles[row["id"]], Dragons.physical_profile(Game, row)), "physical mass strength bite force geometry and gem materials survive native save/load")
		check(original_types[row["id"]] == Dragons.type_label(row), "gem Dragon or Egg type remains separate from personal identity after load")
	book = Game.world["dragons"].duplicate(true)
	Dragons.after_load(Game); Feudal.finish(Game)
	check(comparison.same(Game.world["dragons"], book), "repeated load reconciliation does not duplicate histories or holdings")
	check(not Game.world.get("lairs", {}).values().any(func(lair): return String(lair.get("kind", "")) == "dragon"), "individual dragon registry does not spawn moving creatures")
	print("Dragon release: %d checks, %d failures; %d towns, %d eggs, %d parent adults; one history day and native save/load." % [checks, fails, Game.world["towns"].size(), eggs, adults])
	WorldGen.gen_size = old_size
	WorldGen.gen_stretch = old_stretch
	CampaignWorld.presim_span_days = old_history
	MapTokens.clear_cache()
	return fails

