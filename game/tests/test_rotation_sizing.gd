extends RefCounted

var checks := 0
var fails := 0

# Golden soil-weighted annual means, including one zero-yield fallow phase.
# These values are fixtures, independent of the live selector and live tables.
const MEANS := {
	"human": {"cold": [142.5, 125.0, 131.25], "temperate": [147.5, 125.0, 131.25], "hot": [147.5, 117.5, 116.25], "dry": [142.5, 125.0, 116.25]},
	"moon_elf": {"cold": [137.5, 112.5, 131.25], "temperate": [147.5, 112.5, 131.25], "hot": [147.5, 112.5, 116.25], "dry": [97.5, 75.0, 76.25]},
	"dwarf": {"cold": [142.5, 125.0, 131.25], "temperate": [142.5, 125.0, 131.25], "hot": [97.5, 75.0, 76.25], "dry": [142.5, 125.0, 116.25]},
	"orc": {"cold": [142.5, 125.0, 116.25], "temperate": [142.5, 125.0, 116.25], "hot": [137.5, 117.5, 106.25], "dry": [142.5, 125.0, 116.25]},
	"goblin": {"cold": [142.5, 125.0, 118.75], "temperate": [142.5, 125.0, 118.75], "hot": [137.5, 117.5, 106.25], "dry": [142.5, 125.0, 116.25]}}
const CEREALS := {
	"human": {"cold": ["barley", "barley", "oats"], "temperate": ["wheat", "barley", "oats"], "hot": ["wheat", "millet", "wheat"], "dry": ["barley", "barley", "barley"]},
	"moon_elf": {"cold": ["rye", "rye", "oats"], "temperate": ["wheat", "wheat", "oats"], "hot": ["wheat", "wheat", "wheat"], "dry": ["fallow", "fallow", "fallow"]},
	"dwarf": {"cold": ["barley", "barley", "oats"], "temperate": ["barley", "barley", "oats"], "hot": ["fallow", "fallow", "fallow"], "dry": ["barley", "barley", "barley"]},
	"orc": {"cold": ["barley", "barley", "barley"], "temperate": ["barley", "barley", "barley"], "hot": ["millet", "millet", "millet"], "dry": ["barley", "barley", "barley"]},
	"goblin": {"cold": ["barley", "barley", "rye"], "temperate": ["barley", "barley", "rye"], "hot": ["millet", "millet", "millet"], "dry": ["barley", "barley", "barley"]}}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func equal(a: float, b: float) -> bool:
	return absf(a - b) <= 0.000001

# Keep the old release reachable: missing planning APIs are a counted failure,
# not a compile-error substitute for a regression baseline.
func planning_mean(e: Dictionary, good: String = "grain") -> float:
	var policy := CropRotation.new()
	return float(policy.call("mean_yield", e, good)) if policy.has_method("mean_yield") else float(TownEcon.data()["land"]["yield"][good])

func sizing_eaters(e: Dictionary) -> float:
	var gen := EconGen.new()
	if gen.has_method("food_eaters"): return float(gen.call("food_eaters", e))
	var people := 0
	for f in e["fams"]: people += Families.people(f)
	return float(people)

func expected_crop(race: String, climate: String, soil: int, phase: int) -> String:
	if phase == 0: return CEREALS[race][climate][soil]
	if phase == 1:
		return "peas" if soil == 2 and race in ["human", "moon_elf", "dwarf"] and climate in ["cold", "temperate"] else "beans"
	return "vegetables" if phase == 2 else "fallow"

func physical_cycle(culture: String, climate: String) -> void:
	var race := String(TownEcon.data()["cultures"][culture]["race"])
	var family := Families._blank(1); family["m"] = 1; family["land"] = {"grain": 10}; family["worked"] = 1.0
	var estate := Families._blank(0); estate["estate"] = true
	var P := {"x": PackedInt32Array([0, 1, 2]), "y": PackedInt32Array([0, 0, 0]), "ac": PackedInt32Array([2, 3, 5]),
		"use": PackedInt32Array([Plots.FIELD, Plots.FIELD, Plots.FIELD]), "sub": PackedInt32Array([0, 0, 0]), "own": PackedInt32Array([1, 1, 1]),
		"crops": ["grain"], "variety": ["", "", ""], "soil": ["loam", "light", "heavy"], "rotation_phase": [0, 1, 2], "h": [[], [], []]}
	var e := {"culture": culture, "climate": climate, "price": {"grain": 3.6}, "crops": {"grain": "wheat"}, "fams": [estate, family], "plots": P, "day": 0}
	var weighted_sum := 0.0
	for year in 4:
		e["day"] = year * EconGen.YEAR_DAYS
		CropRotation.ensure(e, P, float(e["day"]))
		for i in 3:
			var phase := posmod(int(P["rotation_phase"][i]) + Calendar.year(float(e["day"])), 4)
			check(P["variety"][i] == expected_crop(race, climate, i, phase), "physical crop agrees with independent rotation fixture")
		var row: Array = P["crop_yields"]["1"]
		check(equal(float(row[0]), 10.0) and Families.acres(family) == 10, "rotation preserves every physical owned acre including fallow")
		check(equal(CropRotation.family_yield(e, family, "grain") * 10.0, float(row[1])), "family yield matches physical owned output")
		weighted_sum += float(row[1])
	var expected: Array = MEANS[race][climate]
	check(equal(weighted_sum / 4.0, float(expected[0]) * 2.0 + float(expected[1]) * 3.0 + float(expected[2]) * 5.0), "four-year output matches independent soil-weighted golden sum")

func policy_matrix() -> void:
	var soils := ["loam", "light", "heavy"]
	var policy := CropRotation.new()
	check(policy.has_method("choose_crop") and policy.has_method("mean_yield"), "generation exposes the shared physical rotation planner")
	for culture in TownEcon.data()["cultures"]:
		var race := String(TownEcon.data()["cultures"][culture]["race"])
		for climate in TownEcon.data()["climates"]:
			if String(climate).begins_with("_"): continue
			var e := {"culture": culture, "climate": climate}
			var fixture: Array = MEANS[race][climate]
			check(equal(planning_mean(e), (float(fixture[0]) + float(fixture[1]) + float(fixture[2])) / 3.0), "generation mean includes soil, fallow, culture and feasible climates")
			for good in ["fruit", "flax", "fodder"]:
				check(equal(planning_mean(e, good), float(TownEcon.data()["land"]["yield"][good])), "non-grain yield retains existing crop policy")
			for si in 3:
				for phase in 4:
					if policy.has_method("choose_crop"):
						check(policy.call("choose_crop", race, climate, soils[si], phase) == expected_crop(race, climate, si, phase), "selector matches independent permitted-crop fixture")
			physical_cycle(culture, climate)

func independent_eaters(e: Dictionary) -> float:
	var race := String(TownEcon.data()["cultures"][e["culture"]]["race"])
	var threshold := float(People.ages(race)["adult"]) / 16.0 * 10.0 * People.year_days()
	var shares := 0.0
	for f in e["fams"]:
		if f.get("estate", false) or f.get("gone", false): continue
		shares += float(Families.adults(f) + int(f["old"]))
		for kid in f.get("kp", []): shares += 0.8 if -float(kid[3]) >= threshold else 0.6
	return shares

func generation_signature() -> Dictionary:
	var out := {}
	for tid in Game.world["towns"]:
		var e: Dictionary = Game.world["towns"][tid]["econ"]
		var P: Dictionary = e["plots"]
		out[tid] = {"land": e["land"].duplicate(true), "own": P["own"].duplicate(), "ac": P["ac"].duplicate(), "soil": P["soil"].duplicate(), "phase": P["rotation_phase"].duplicate()}
		var total := 0
		var yards := {}
		for i in Plots.count(P):
			if int(P["use"][i]) in [Plots.YARD, Plots.MINE]: yards[int(P["sub"][i])] = true
		for business in e["biz"]:
			if business.get("closed", false) or String(business["type"]) in Plots.NO_YARD: continue
			check(yards.has(int(business["id"])), "every initial business has its physical yard after work assignment")
		var books: Dictionary = Plots.totals(e)["own_crop"]
		for f in e["fams"]:
			total += Families.acres(f)
			for crop in f["land"]:
				check(int(f["land"][crop]) == int(books.get(int(f["id"]), {}).get(crop, 0)), "generated physical plots preserve each owner's crop holding")
		check(total == int(Plots.totals(e)["land"]) and total == int(e["territory"]), "generated town denominator includes its actual physical holdings")
		check(equal(sizing_eaters(e), independent_eaters(e)), "sizing helper uses actual child register meal shares")
	return out

func direct_sizing() -> void:
	for culture in TownEcon.data()["cultures"]:
		var source: Dictionary = Game.world["towns"].values()[0]
		var town: Dictionary = source.duplicate(true)
		town["culture"] = culture
		var rng := RandomNumberGenerator.new(); rng.seed = 4096
		EconGen.generate(Game.world, town, rng)
		var e: Dictionary = town["econ"]
		var eaters := independent_eaters(e)
		check(equal(eaters, sizing_eaters(e)), "persons exist before direct generation's food sizing")
		check(eaters < float(e["pop"]), "children reduce meal demand while adults and elders keep full shares")
		var soil_means: Array = MEANS[String(TownEcon.data()["cultures"][culture]["race"])][e["climate"]]
		var mean := (float(soil_means[0]) + float(soil_means[1]) + float(soil_means[2])) / 3.0 * float(TownEcon.data()["climates"][e["climate"]]["grain_yield"])
		var diet := Barge.diet(e)
		var beer_input := float(e["adults"]) * float(TownEcon.data()["needs"]["drink_adult"]) * EconGen.YEAR_DAYS * EconGen.beer_share_of(e) * 0.5
		var grain_need := eaters * float(diet["grain"]) * EconGen.YEAR_DAYS + beer_input
		var grain_actual := float(e["land"].get("grain", 0))
		var multiplier: float = {"farming": 1.35, "herding": 1.0, "timber": 0.95, "trade": 0.85, "mining": 0.8, "military": 0.9}.get(town.get("specialty", ""), 1.0)
		# Holder rounding adds at most half an acre per household. The broad but
		# quantitative range fails the old flat200 sizing, including child overcount.
		var tolerance := float(e["fams"].size()) * 0.5
		check(grain_actual * mean + tolerance * mean >= grain_need * multiplier * 0.95 * 1.45, "direct acreage covers the rotation-aware intended output at minimum generation roll")
		check(grain_actual * mean - tolerance * mean <= grain_need * multiplier * 1.2 * 1.45, "generation retains bounded specialty/random/surplus policy")
		var repeated: Dictionary = source.duplicate(true); repeated["culture"] = culture
		var repeat_rng := RandomNumberGenerator.new(); repeat_rng.seed = 4096
		EconGen.generate(Game.world, repeated, repeat_rng)
		check(e["land"] == repeated["econ"]["land"], "equal direct generation seed preserves land sizing")
	var fallback: Dictionary = Game.world["towns"].values()[0].duplicate(true); fallback["culture"] = "unsupported-fixture-culture"
	var fallback_rng := RandomNumberGenerator.new(); fallback_rng.seed = 4096
	EconGen.generate(Game.world, fallback, fallback_rng)
	check(fallback["econ"]["culture"] == "middle" and sizing_eaters(fallback["econ"]) > 0.0, "generation normalizes unsupported culture before person and crop planning")

func run(_tree: SceneTree) -> int:
	policy_matrix()
	Game.new_game(901)
	var first := generation_signature()
	direct_sizing()
	Game.new_game(901)
	var second := generation_signature()
	check(first == second, "same campaign seed preserves physical ownership and rotation deterministically")
	print("ROTATION SIZING checks=", checks, " failures=", fails)
	return fails
