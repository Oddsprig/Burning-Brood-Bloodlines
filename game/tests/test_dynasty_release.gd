extends RefCounted
## One real normal-size world, one history day and current-build save/load.
## No old-save migration, long campaign or UI input automation.
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

## JSON reads numbers as floats and rounds the last binary fraction. Compare
## native values, keeping strings/identity exact and numeric tolerance <1e-6 coin.
func same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not same(a[i], b[i]): return false
		return true
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) < 0.000001
	return a == b

func run(_tree: SceneTree) -> int:
	var old_size := WorldGen.gen_size
	var old_stretch := WorldGen.gen_stretch
	var old_history := CampaignWorld.presim_span_days
	WorldGen.gen_size = "normal"
	WorldGen.gen_stretch = WorldGen.STRETCH
	CampaignWorld.presim_span_days = 1
	Game.new_game(10461)
	check(Game.company.size() == 100 and not Game.world.get("towns", {}).is_empty(), "native world contains the actual 100-person starting army and towns")
	check(CampaignWorld.presim_step(Game, 1) == 0, "native world completes exactly one history day")
	CampaignWorld.presim_finish(Game)
	Dynasty.prepare_world(Game)
	var picks := Dynasty.choices(Game)
	check(not picks.is_empty(), "generated history leaves real living city rulers to choose")
	if picks.is_empty(): return fails
	var wealth := Barge.holdings(Game)
	var unit_next := Unit._next_uid
	check(Dynasty.select_city(Game, String(picks[0]["town_id"])), "existing generated ruling family is selectable")
	check(absf(Barge.holdings(Game) - wealth) < 0.001 and Unit._next_uid == unit_next, "selection conserves all coin owners and creates no troops")
	var tid_selected := String(picks[0]["town_id"])
	var e_selected: Dictionary = Game.world["towns"][tid_selected]["econ"]
	var rate := 0.02 if not is_equal_approx(Barge.common_tax_rate(e_selected), 0.02) else 0.10
	check(Feudal.governance(Game, tid_selected, "tax_policy", rate)["ok"], "real generated lord can set future private estate tax")
	check(Feudal.governance(Game, tid_selected, "stand_down")["ok"], "real generated settlement accepts persistent militia stand-down")
	var funds := minf(25.0, floor(float(Feudal._payer(Game).get("purse", 0.0))))
	check(funds > 0.0 and Feudal.governance(Game, tid_selected, "fund_garrison", funds)["ok"], "actual generated house funds its existing public treasury")
	check(absf(Barge.holdings(Game) - wealth) < 0.001 and Unit._next_uid == unit_next, "generated governance orders preserve coin and do not create soldiers")
	var governance: Dictionary = Feudal.budget(Game, tid_selected).duplicate(true)
	var state := Dynasty.selected(Game)
	var ruler := Dynasty.ruler(Game)
	var accounts := Dynasty.accounts(Game)
	var members := Dynasty.living_members(Game)
	var army_ids := Game.company.map(func(u): return u.uid)
	var born := Game.company.map(func(u): return u.born)
	var population := {}
	var owners := {}
	for tid in Game.world["towns"]:
		var e: Dictionary = Game.world["towns"][tid]["econ"]
		population[tid] = {"summary": Population.summary(e), "bins": e["fams"].filter(func(f): return Population.is_cohort(f)).map(func(f): return [f["id"],f["age_bins"].duplicate(true),f["purse"]]), "death_ids": e.get("census",{}).get("death_ids",{}).duplicate(true)}
		owners[tid] = e["biz"].map(func(b): return [b["owner"], b.get("public_funding", ""), b.get("public_property", -1)])
	var feudal: Dictionary = Game.world["feudal"].duplicate(true)
	Game.save_game()
	check(Game.has_save() and Game.load_game(), "native current-build save loads successfully")
	check(same(Dynasty.selected(Game), state) and same(Dynasty.ruler(Game), ruler), "selected city and registered ruler survive current-build persistence")
	check(same(Dynasty.living_members(Game), members) and same(Dynasty.accounts(Game), accounts), "native family membership and separately owned money survive persistence")
	check(Game.company.map(func(u): return u.uid) == army_ids and Game.company.map(func(u): return u.born) == born, "original army identity and ages survive persistence")
	var population_ok := true; var owners_ok := true; var company_ok := true
	for tid in Game.world["towns"]:
		var e: Dictionary = Game.world["towns"][tid]["econ"]
		var current := {"summary": Population.summary(e), "bins": e["fams"].filter(func(f): return Population.is_cohort(f)).map(func(f): return [f["id"],f["age_bins"].duplicate(true),f["purse"]]), "death_ids": e.get("census",{}).get("death_ids",{}).duplicate(true)}
		if not same(population[tid],current): population_ok = false
		if not same(owners[tid],e["biz"].map(func(b): return [b["owner"], b.get("public_funding", ""), b.get("public_property", -1)])): owners_ok = false
	for u in Game.company:
		var town: Dictionary = Game.world["towns"].get(u.home_town,{})
		if Persons.by_uid(People.fam_of(town,u.family),u.uid).is_empty(): company_ok = false
	check(population_ok, "every real population/wealth pool and permanent death ledger survives persistence")
	check(owners_ok and company_ok, "native business operators, public funding/property and all company resident identities survive persistence")
	check(same(feudal, Game.world["feudal"]), "every settlement's hierarchy, allegiance, loyalty and tribute state survives persistence")
	check(same(governance, Feudal.budget(Game, tid_selected)) and is_equal_approx(float(Game.world["towns"][tid_selected]["econ"].get("lord_tax_rate", 0.0)), rate), "actual fiscal budgets, future tax policy and militia orders survive native current-build save/load")
	check(absf(Barge.holdings(Game) - wealth) < 0.001 and not Game.is_game_over(), "loaded living dynasty remains playable with conserved coin")
	check(ProjectSettings.get_setting("application/config/custom_user_dir_name") == "Burning Brood Bloodlines", "new game uses its own user-data namespace")
	# Optional isolated render fixture; never emitted into the shipped game folder.
	if OS.get_cmdline_user_args().has("--capture-world"):
		var file := FileAccess.open("res://../smoke_world.json", FileAccess.WRITE)
		if file != null: file.store_string(FileAccess.get_file_as_string(Game.SAVE_PATH)); file.close()
	WorldGen.gen_size = old_size
	WorldGen.gen_stretch = old_stretch
	CampaignWorld.presim_span_days = old_history
	print("Bloodlines release: %d checks; %d generated towns; one history day" % [checks, Game.world["towns"].size()])
	return fails
