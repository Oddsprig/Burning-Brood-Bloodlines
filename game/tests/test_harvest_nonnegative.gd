extends RefCounted

var checks := 0
var fails := 0
var helper = load("res://tests/test_harvest_ownership.gd").new()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func pending(e: Dictionary, channel: String) -> float:
	var total := 0.0
	for row in e["harvest_book"]["carry"].get(channel, []):
		for amount in row["shares"].values(): total += float(amount)
	return total

func production_boundary(culture: String, good: String, day: float, previous: float) -> void:
	var e: Dictionary = helper.fixture(culture, [[1, 1.0]])
	var f: Dictionary = e["fams"][1]
	f["land"] = {good: 1}; e["land"] = {good: 1}; e["wacres"] = {good: 1.0}
	e["day"] = day
	# Real incremental updates: (1 - .9) - .1 is mathematically zero but
	# leaves a negative floating residue. There is no worked field remaining.
	Families.set_worked(e, f, 0.1)
	Families.set_worked(e, f, 0.0)
	check(float(f["worked"]) == 0.0 and float(e["wacres"][good]) < 0.0, "ordinary weighted-acre updates reproduce cancellation residue")
	var channel := "h_" + good
	HarvestClaims.harvest(e, good, channel, {"f:1": 1.0}, previous, 0, 0, 0.0, int(day) - 1)
	e["carry"][channel] = previous
	var dated: Array = e["harvest_book"]["carry"][channel].duplicate(true)
	var coins: float = helper.cash(e)
	for offset in 3:
		e["day"] = day + float(offset)
		TownEcon._farms(e, TownEcon.data(), Calendar.season_index(day), TownEcon.data()["climates"]["temperate"])
		check(float(e["carry"][channel]) == previous, "zero actual output preserves the previous physical fraction exactly")
		check(absf(pending(e, channel) - previous) < 0.000000000001, "all remaining carry retains its dated owner")
		check(e["harvest_book"]["carry"][channel] == dated, "zero output preserves the exact existing owner shares and dates")
		check(int(e["barn"].get(good, 0)) == 0 and int(e["led"]["made"].get(good, 0)) == 0 and int(e["granary"]) == 0, "unworked land creates no crops or grain tax")
		check(float(helper.cash(e)) == coins, "unworked field bookkeeping cannot create payments")
	# A positive real fraction still advances output; the boundary is zero,
	# not a rounded threshold that discards small legitimate harvests.
	f["worked"] = 0.000001; e["wacres"][good] = 0.000001
	TownEcon._farms(e, TownEcon.data(), Calendar.season_index(day), TownEcon.data()["climates"]["temperate"])
	check(float(e["carry"][channel]) > previous, "small positive production is retained without yield tuning")
	check(absf(pending(e, channel) - float(e["carry"][channel])) < 0.000000000001, "positive fractional output stays fully attributed")

func run(_tree: SceneTree) -> int:
	for culture in TownEcon.data()["cultures"]:
		for good in ["grain", "fruit", "flax", "fodder"]:
			for cut in TownEcon.data()["land"]["harvest_seasons"][good]:
				for previous in [0.0, 0.25, 0.6]:
					production_boundary(culture, good, float(cut[0]) * Calendar.DAYS_PER_SEASON, previous)
	print("NONNEGATIVE HARVEST checks=", checks, " failures=", fails)
	return fails
