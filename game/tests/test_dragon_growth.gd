extends RefCounted
## Small record fixtures only. No world generation, art or battle resolver.
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon growth: " + why)

func dragon(size: String = "small") -> Dictionary:
	return {"id": "dragon:growth:1", "name": "Cinderwake", "gem_id": "ruby", "morph_id": "spirewing",
		"size_class": size, "appearance_seed": 37, "stage": "adult", "alive": true,
		"birth_day": -999999.0, "owner_person_uid": "person:owner", "rider_person_uid": ""}

func unchanged(row: Dictionary, days: float, food: float, care: float, health: float, reason: String) -> void:
	var before := row.duplicate(true)
	var result := DragonGrowth.advance(row, days, food, care, health)
	check(not result["changed"] and result["reason"] == reason and row == before, reason + " keeps full record untouched")

func run(_tree: SceneTree) -> int:
	var rng_state := Game.rng.state; var unit_uid := Unit._next_uid; var item_uid := Item._next_uid
	var native := var_to_bytes(Game._serialize({"world": Game.world, "company": Game.company, "gold": Game.gold, "day": Game.day}))
	check(DragonGrowth.DAYS_PER_BAND == DragonGrowth.YEARS_PER_BAND * People.year_days(), "one 120-day campaign year per complete band (Claude Edition pacing)")
	var catalog: Dictionary = Dragons.catalogs()
	for i in catalog["sizes"].size():
		var size: Dictionary = catalog["sizes"][i]
		var row := dragon(str(size["id"])); var before := row.duplicate(true)
		var metric := DragonGrowth.metrics(row)
		check(DragonGrowth.initial_points(row) == float(i), str(size["id"]) + " starts at its existing authored class")
		for key: String in ["body_mass_kg", "strength", "linear_scale"]:
			check(metric[key] == float(size["physical"][key]), str(size["id"]) + " integral base " + key + " exact")
		check(row == before and not row.has("growth_points"), str(size["id"]) + " legacy metric read is pure without catchup/init")
	var row := dragon(); row["growth_points"] = 0.5
	var midpoint := DragonGrowth.metrics(row)
	check(midpoint["body_mass_kg"] == 775.0 and midpoint["strength"] == 1075.0 and midpoint["linear_scale"] == 1.25, "continuous authored midpoint, with no morph/gem multiplier")
	for band in range(1, 4):
		row["growth_points"] = float(band) - 1.0e-8; var below := DragonGrowth.metrics(row)
		row["growth_points"] = float(band); var exact := DragonGrowth.metrics(row)
		row["growth_points"] = float(band) + 1.0e-8; var above := DragonGrowth.metrics(row)
		for key: String in ["body_mass_kg", "strength", "linear_scale"]:
			check(below[key] <= exact[key] and exact[key] <= above[key] and absf(above[key] - below[key]) < 0.002, "monotonic continuous band%d %s" % [band, key])
	row = dragon(); row["growth_points"] = 1.375
	var gem_copy := row.duplicate(true); gem_copy["gem_id"] = "black_diamond"; gem_copy["name"] = "Different personal name"; gem_copy["morph_id"] = "broadmantle"; gem_copy["appearance_seed"] = 899
	check(DragonGrowth.metrics(row) == DragonGrowth.metrics(gem_copy), "base growth independent of gem/proper name/morph/appearance")
	var red_growth := DragonGrowth.advance(row, 3.0, 1.0, 1.0, 1.0)
	var dark_growth := DragonGrowth.advance(gem_copy, 3.0, 1.0, 1.0, 1.0)
	check(red_growth["delta"] == dark_growth["delta"] and row["gem_id"] == "ruby" and gem_copy["gem_id"] == "black_diamond", "growth rate never depends on or changes gem hardness/type")
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(row))
	check(DragonGrowth.metrics(loaded) == DragonGrowth.metrics(row), "fractional points survive current JSON roundtrip")
	row = dragon(); var identity := row.duplicate(true)
	var full := DragonGrowth.advance(row, DragonGrowth.DAYS_PER_BAND, 1.0, 1.0, 1.0)
	check(full["changed"] and row["growth_points"] == 1.0 and row["size_class"] == "medium", "full20 years grows exactly one size band")
	var unchanged_identity := row.duplicate(true); unchanged_identity.erase("growth_points"); unchanged_identity["size_class"] = identity["size_class"]
	check(unchanged_identity == identity, "growth only changes stored points/size, never stage/identity/references")
	row = dragon(); var daily := DragonGrowth.advance(row, 1.0, 1.0, 1.0, 1.0)
	check(is_equal_approx(daily["delta"], 1.0 / DragonGrowth.DAYS_PER_BAND), "very old birth date produces only explicit one-day growth")
	var fresh := dragon(); fresh["birth_day"] = 0.0
	check(DragonGrowth.advance(fresh, 1.0, 1.0, 1.0, 1.0)["delta"] == daily["delta"], "no retrospective age catchup")
	row = dragon(); var partial := DragonGrowth.advance(row, 1.0, 0.8, 0.8, 0.5)
	check(partial["delta"] > 0.0 and partial["delta"] < daily["delta"] and partial["rate_per_day"] <= 1.0 / DragonGrowth.DAYS_PER_BAND, "threshold care/health allows slower bounded growth")
	unchanged(dragon(), 1.0, 0.799, 1.0, 1.0, "stalled_food")
	unchanged(dragon(), 1.0, 1.0, 0.799, 1.0, "stalled_care")
	unchanged(dragon(), 1.0, 1.0, 1.0, 0.499, "stalled_health")
	unchanged(dragon(), 1.0, -4.0, 1.0, 1.0, "stalled_food")
	row = dragon(); row["stage"] = "egg"; unchanged(row, 10000.0, 1.0, 1.0, 1.0, "inactive")
	check(DragonGrowth.metrics(row)["valid"], "egg may read bounds without active growth/attacks")
	row = dragon(); row["alive"] = false; unchanged(row, 10000.0, 1.0, 1.0, 1.0, "inactive")
	row = dragon(); row["stage"] = "juvenile"
	DragonGrowth.advance(row, DragonGrowth.DAYS_PER_BAND, 1.0, 1.0, 1.0)
	check(row["stage"] == "juvenile", "calendar maturity stays with caller")
	row = dragon("huge"); var giant := DragonGrowth.advance(row, 1.0e300, 50.0, 50.0, 50.0)
	check(row["growth_points"] == 4.0 and row["size_class"] == "colossal" and giant["rate_per_day"] == 1.0 / DragonGrowth.DAYS_PER_BAND, "finite huge duration/overfeeding bounded to colossal, no overflow")
	unchanged(row, 1000.0, 1.0, 1.0, 1.0, "at_limit")
	row = dragon(); row["growth_points"] = 1.0e30
	check(DragonGrowth.metrics(row)["body_mass_kg"] == 65000.0 and row["growth_points"] == 1.0e30, "pure stored upper-bound clamp")
	row["growth_points"] = -30.0
	check(DragonGrowth.metrics(row)["body_mass_kg"] == 350.0 and row["growth_points"] == -30.0, "pure stored lower-bound clamp")
	row = dragon("large"); row["growth_points"] = "bad"
	check(DragonGrowth.metrics(row)["body_mass_kg"] == 5000.0 and row["growth_points"] == "bad", "malformed stored points fall back exactly to existing class")
	row["growth_points"] = NAN
	check(DragonGrowth.metrics(row)["body_mass_kg"] == 5000.0 and is_nan(row["growth_points"]), "nonfinite stored points read safely without mutation")
	unchanged(dragon(), 0.0, 1.0, 1.0, 1.0, "no_elapsed_days")
	unchanged(dragon(), -1.0, 1.0, 1.0, 1.0, "invalid_inputs")
	unchanged(dragon(), INF, 1.0, 1.0, 1.0, "invalid_inputs")
	unchanged(dragon(), NAN, 1.0, 1.0, 1.0, "invalid_inputs")
	unchanged(dragon(), 1.0, NAN, 1.0, 1.0, "invalid_inputs")
	unchanged(dragon(), 1.0, 1.0, INF, 1.0, "invalid_inputs")
	unchanged(dragon(), 1.0, 1.0, 1.0, NAN, "invalid_inputs")
	row = dragon("unknown"); check(DragonGrowth.initial_points(row) == -1.0 and not DragonGrowth.metrics(row)["valid"], "unknown size fails closed")
	unchanged(row, 1.0, 1.0, 1.0, 1.0, "unknown_size")
	check(Dragons.catalogs() == catalog and Game.rng.state == rng_state and Unit._next_uid == unit_uid and Item._next_uid == item_uid, "catalog/RNG/Unit/Item identities conserved")
	check(var_to_bytes(Game._serialize({"world": Game.world, "company": Game.company, "gold": Game.gold, "day": Game.day})) == native, "campaign/food/coin state never touched")
	print("dragon growth: %d checks, %d failures" % [checks, fails])
	return fails
