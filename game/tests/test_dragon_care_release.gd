extends RefCounted
## One real Normal/one-history-day campaign, its queued care midnight and
## current native save/load. Whole economy-day processing is a separate check.
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon care release: ", message)

func run(tree: SceneTree) -> int:
	var saved_fixture := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture-save="): saved_fixture = argument.substr(15)
	if saved_fixture == "":
		var base: RefCounted = load("res://tests/test_dragon_release.gd").new()
		var prerequisite: int = await base.run(tree)
		checks += int(base.checks)
		if prerequisite != 0: return prerequisite
	else:
		# Primary supplies a private copy of this version's already-generated
		# campaign. Reuse it instead of regenerating a world for every check.
		Game.SAVE_PATH = saved_fixture
		check(Game.load_game(), "actual current-version saved fixture loads")
		check(Game.company.size() == 100 and Game.world["towns"].size() == 23, "actual Normal campaign and native company restored")
		check(Dragons.records(Game).all(func(row): return row.has("care") and row.has("growth_points")), "fixture already contains current care/growth data")
	var before: Dictionary = Game.world["dragons"].duplicate(true)
	var midnight := int(floor(Game.day)) + 1
	Game.day = float(midnight) + 0.5
	Game.world["work"] = [["dragon_care", midnight]]
	CampaignWorld._do_work(Game, Game.rng)
	check(Game.world.get("work", []).is_empty(), "native queued care job completes")
	check(Game.world["dragons"]["next_id"] == before["next_id"] and Game.world["dragons"]["records"].size() == before["records"].size(), "care does not mint identities or hatch/breed records")
	var actual_cost := 0.0; var active := 0; var interrupted := 0
	for row: Dictionary in Dragons.records(Game):
		var original: Dictionary = before["records"][row["id"]]
		var care: Dictionary = row["care"]
		check(int(care["last_day"]) == midnight and int(care["last"].get("day", -1)) == midnight, "native queued midnight records exactly one care receipt")
		check(row["name"] == original["name"] and row["gem_id"] == original["gem_id"] and row["mother_uid"] == original["mother_uid"] and row["father_uid"] == original["father_uid"], "daily care retains personal name, gem and bloodline parents")
		check(row["rider_person_uid"] == "", "care creates no rider bond")
		var last: Dictionary = care["last"]
		actual_cost += float(last["food_cost"]) + float(last["upkeep_cost"])
		if float(last["care_ratio"]) >= 0.8: active += 1
		else: interrupted += 1
		var profile := Dragons.physical_profile(Game, row)
		check(profile.get("hardness_index") == Dragons.physical_profile(Game, original).get("hardness_index"), "growth and health retain gem hardness")
		check(float(care["health"]) >= 0.0 and float(care["health"]) <= 1.0 and float(row["growth_points"]) >= 0.0 and float(row["growth_points"]) <= 4.0, "live campaign condition and growth remain bounded")
		if row["stage"] == "egg": check(int(last["food_units"]) == 0 and float(last["food_cost"]) == 0, "real egg upkeep consumes no meat")
	var book: Dictionary = Game.world["dragons"].duplicate(true)
	Game.save_game(); Game.world = {}
	check(Game.load_game(), "full current campaign save loads after actual care")
	var compare: RefCounted = load("res://tests/test_dynasty_release.gd").new()
	check(compare.same(Game.world["dragons"], book), "native save/load retains actual charges, health, growth and midnight guards")
	var state := JSON.stringify(Game._serialize(Game.world))
	DragonCare.daily(Game, midnight); DragonCare.daily(Game, midnight - 1)
	check(JSON.stringify(Game._serialize(Game.world)) == state, "loaded same and previous day retries debit nothing")
	print("Dragon care release: %d checks, %d failures; %d towns, %d holdings, %d supplied, %d interrupted; actual upkeep %.2f native coins; one care midnight and full save/load." % [checks, fails, Game.world["towns"].size(), book["records"].size(), active, interrupted, actual_cost])
	return fails
