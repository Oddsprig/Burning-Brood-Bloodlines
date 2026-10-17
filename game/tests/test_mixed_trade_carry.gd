extends "res://tests/test_keeper_operating_cash.gd"
var baseline_script: GDScript

func producer_daily(town: Dictionary, e: Dictionary, rng: RandomNumberGenerator) -> void:
	if baseline_script != null: baseline_script.daily(Game, town, e, TownEcon.data(), 0, rng)
	else: Businesses.daily(Game, town, e, TownEcon.data(), 0, rng)

func mixed_full_stalls(culture: String, hired: int = 0) -> void:
	var rows := fixture(culture, "weaponsmith")
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]
	e["barn"] = {}
	b["till"] = 10000.0; b["workers"] = hired; b["cap"] = hired + 1
	b["tools"] = hired + 1
	if hired > 0:
		b["owed"] = 83.0; b["wage_claims"] = {"1": 83.0}; b["owed_unattributed"] = 0.0
	e["price"]["heads_copper"] = 10.0; e["price"]["copper_bars"] = 1.0
	e["stock"]["tin_bars"] = 0
	Businesses.prep_day(e)
	var town := {"id": "fixture", "culture": culture, "size": 0, "econ": e, "shop": []}
	for i in Businesses.arms_cap(town): town["shop"].append(Item.make("arming_sword", "copper", 2))
	var cash := coins(rows)
	var copper := int(e["stock"]["copper_bars"])
	var rng := RandomNumberGenerator.new(); rng.seed = 941
	for day in 8:
		e["day"] = day
		producer_daily(town, e, rng)
	var batches := 2 * (hired + 1)
	check(int(e["led"]["made"].get("heads_copper", 0)) == 80 * batches,
		culture + ": eight partial days at full gear stalls complete two paid head batches per hand")
	check(copper - int(e["stock"]["copper_bars"]) == batches and int(e["led"]["used"].get("copper_bars", 0)) == batches,
		culture + ": completed head batches consume exactly their real bars")
	check(town["shop"].size() == Businesses.arms_cap(town) and int(e["led"]["made"].get("arms", 0)) == 0,
		culture + ": full gear stalls create no unwanted weapon items")
	check(absf(coins(rows) - cash) < 0.00001 and float(b["owed"]) == (83.0 if hired > 0 else 0.0),
		culture + ": production conserves real cash and creates no synthetic wage claim")
	if hired > 0: check(b["wage_claims"] == {"1": 83.0}, "existing earned staff claim remains with its actual creditor")

func recipe_rest_keeps_gear_work(culture: String) -> void:
	var rows := fixture(culture, "weaponsmith")
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]
	e["barn"] = {}
	b["till"] = 10000.0; b["arms_carry"] = 0.9; b["carry"] = 0.75
	e["stock"]["tin_bars"] = 0; e["stock"]["wood"] = 10000
	e["price"]["heads_copper"] = 10.0; e["price"]["copper_bars"] = 1.0
	Businesses.prep_day(e)
	var town := {"id": "fixture", "name": "Fixture", "culture": culture, "size": 0, "econ": e, "shop": []}
	var rng := RandomNumberGenerator.new(); rng.seed = 991
	var cash := coins(rows)
	# An unavailable recipe resets only recipe batches; enough independently
	# earned gear fraction plus today's gear work completes one real item.
	e["_aimrest"]["heads_copper"] = true
	producer_daily(town, e, rng)
	check(town["shop"].size() == 1 and int(e["led"]["made"].get("arms", 0)) == 1,
		culture + ": gear work completes independently while tip recipes rest")
	check(int(e["led"]["made"].get("heads_copper", 0)) == 0 and float(b["carry"]) == 0.0,
		culture + ": resting recipe work cannot become gear items or head output")
	check(absf(float(b["arms_carry"]) - 0.2) < 0.00001 and absf(coins(rows) - cash) < 0.00001,
		culture + ": unused gear fraction remains in gear units with conserved cash")
	# Round-trip scalar fractional work, then reopen the recipe with gear still
	# below a whole piece: neither fraction may be converted to the other unit.
	var restored: Dictionary = JSON.parse_string(JSON.stringify(b))
	b["carry"] = 0.75; b["arms_carry"] = restored["arms_carry"]
	e["_aimrest"].erase("heads_copper")
	producer_daily(town, e, rng)
	check(town["shop"].size() == 1 and int(e["led"]["made"].get("heads_copper", 0)) == 80,
		culture + ": saved recipe fraction completes one batch while gear fraction stays partial")
	check(absf(float(b["arms_carry"]) - 0.5) < 0.00001 and float(b["carry"]) == 0.0,
		culture + ": transitions retain separate fractional units without duplicate output")

func real_funding_and_batches() -> void:
	var rows := fixture("middle", "weaponsmith")
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]
	e["barn"] = {}; e["stock"]["tin_bars"] = 0
	e["price"]["heads_copper"] = 10.0; e["price"]["copper_bars"] = 35.0
	b["carry"] = 0.75; b["owed"] = 83.0; b["wage_claims"] = {"1": 83.0}; b["owed_unattributed"] = 0.0
	Businesses.prep_day(e)
	var town := {"id": "fixture", "culture": "middle", "size": 0, "econ": e, "shop": []}
	for i in Businesses.arms_cap(town): town["shop"].append(Item.make("arming_sword", "copper", 2))
	var cash := coins(rows); var bars := int(e["stock"]["copper_bars"])
	var rng := RandomNumberGenerator.new(); rng.seed = 937
	producer_daily(town, e, rng)
	check(int(e["led"]["made"].get("heads_copper", 0)) == 0 and int(e["stock"]["copper_bars"]) == bars,
		"unfunded partial work cannot complete unpaid materials")
	var purse := float(rows[2]["purse"])
	owner(rows)
	check(float(rows[2]["purse"]) < purse and absf(coins(rows) - cash) < 0.00001,
		"existing owner turn transfers real coins for current viable work")
	producer_daily(town, e, rng)
	check(int(e["led"]["made"].get("heads_copper", 0)) == 80 and bars - int(e["stock"]["copper_bars"]) == 1,
		"funding completes exactly one retained partial batch with one actual bar")
	check(float(b["owed"]) == 83.0 and b["wage_claims"] == {"1": 83.0} and absf(coins(rows) - cash) < 0.00001,
		"input payments and output receipts conserve cash and preserve earned creditor debt")

func pure_gear_legacy() -> void:
	var rows := fixture("middle", "armorsmith")
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]
	e["barn"] = {}; e["stock"]["copper_bars"] = 100000; e["stock"]["wood"] = 100000
	b["till"] = 10000.0; b["carry"] = 0.99
	var town := {"id": "fixture", "name": "Fixture", "culture": "middle", "size": 0, "econ": e, "shop": []}
	var rng := RandomNumberGenerator.new(); rng.seed = 99
	var cash := coins(rows)
	producer_daily(town, e, rng)
	check(town["shop"].size() == 1 and not b.has("arms_carry") and absf(coins(rows) - cash) < 0.00001,
		"pure gear maker completes its legacy item fraction in the unchanged saved channel")

func ambiguous_legacy(culture: String, old_state: String) -> void:
	var rows := fixture(culture, "weaponsmith")
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]
	e["barn"] = {}; e["stock"]["tin_bars"] = 0
	e["price"]["heads_copper"] = 10.0; e["price"]["copper_bars"] = 1.0
	Businesses.prep_day(e)
	b.erase("arms_carry"); b["carry"] = 0.99; b["state"] = old_state; b["fg"] = "arms"; b["till"] = 10000.0
	b["owed"] = 83.0; b["wage_claims"] = {"1": 83.0}; b["owed_unattributed"] = 0.0
	var town := {"id": "fixture", "culture": culture, "size": 0, "econ": e, "shop": []}
	for i in Businesses.arms_cap(town): town["shop"].append(Item.make("arming_sword", "copper", 2))
	var rng := RandomNumberGenerator.new(); rng.seed = 719
	var cash := coins(rows); var bars := int(e["stock"]["copper_bars"])
	producer_daily(town, e, rng)
	check(float(b.get("legacy_mixed_carry_untyped", -1.0)) == 0.99 and int(e["led"]["made"].get("heads_copper", 0)) == 0,
		culture + " " + old_state + ": unlabeled legacy work is retained as inert evidence and cannot become goods")
	check(int(e["stock"]["copper_bars"]) == bars and float(b["owed"]) == 83.0 and absf(coins(rows) - cash) < 0.00001,
		culture + " " + old_state + ": one-time work migration preserves material stock, coins and debt")
	producer_daily(town, e, rng)
	check(absf(float(b["carry"]) - 0.5) < 0.00001 and float(b["legacy_mixed_carry_untyped"]) == 0.99,
		culture + " " + old_state + ": later production retains only newly earned typed work")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(b))
	e["biz"][int(b["id"])] = restored; b = restored; rows[1] = restored
	producer_daily(town, e, rng); producer_daily(town, e, rng)
	check(int(e["led"]["made"].get("heads_copper", 0)) == 80 and bars - int(e["stock"]["copper_bars"]) == 1,
		culture + " " + old_state + ": save and repeated days complete one batch from four fresh partial days")
	check(float(b["legacy_mixed_carry_untyped"]) == 0.99 and float(b["wage_claims"]["1"]) == 83.0 and absf(coins(rows) - cash) < 0.00001,
		culture + " " + old_state + ": round-trip leaves inert history, creditor and cash unchanged")
	# Existing explicitly typed saves do not pass through legacy migration.
	b["carry"] = 0.35; b["arms_carry"] = 0.6
	Businesses._gear_carry_key(b, TownEcon.data()["businesses"]["weaponsmith"])
	check(float(b["carry"]) == 0.35 and float(b["arms_carry"]) == 0.6,
		culture + " " + old_state + ": already split saved fractions survive without a repeated reset")

func run(_tree: SceneTree) -> int:
	Game.world = {"warbands": {}, "towns": {}}
	var baseline := OS.get_environment("MIXED_BASELINE_SOURCE")
	if baseline != "":
		baseline_script = GDScript.new()
		baseline_script.source_code = FileAccess.get_file_as_string(baseline).replace("class_name Businesses", "")
		if baseline_script.reload() != OK: return 1
	for culture in TownEcon.data()["cultures"]:
		mixed_full_stalls(culture)
		recipe_rest_keeps_gear_work(culture)
		if baseline_script == null:
			ambiguous_legacy(culture, "full"); ambiguous_legacy(culture, "busy")
	mixed_full_stalls("middle", 1)
	real_funding_and_batches(); pure_gear_legacy()
	print("MIXED TRADE CARRY checks=", checks, " failures=", fails)
	return fails
