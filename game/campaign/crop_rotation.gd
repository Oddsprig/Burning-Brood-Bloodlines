class_name CropRotation
extends RefCounted
## Varieties remain physical fields; grain/fruit are the economy's meal-equivalent goods.
const ROWS := {
	"wheat": {"yield": 200, "group": "cereal", "soil": "loam", "climates": ["temperate", "hot"]},
	"barley": {"yield": 200, "group": "cereal", "soil": "light", "climates": ["cold", "temperate", "dry"]},
	"rye": {"yield": 170, "group": "cereal", "soil": "heavy", "climates": ["cold", "temperate"]},
	"oats": {"yield": 180, "group": "cereal", "soil": "heavy", "climates": ["cold", "temperate"]},
	"millet": {"yield": 170, "group": "cereal", "soil": "light", "climates": ["hot", "dry"]},
	"beans": {"yield": 180, "group": "legume", "soil": "loam", "climates": ["cold", "temperate", "hot", "dry"]},
	"peas": {"yield": 170, "group": "legume", "soil": "heavy", "climates": ["cold", "temperate"]},
	"vegetables": {"yield": 210, "group": "garden", "soil": "loam", "climates": ["cold", "temperate", "hot", "dry"]},
	"fallow": {"yield": 0, "group": "fallow", "soil": "", "climates": ["cold", "temperate", "hot", "dry"]}}
const SOIL_YIELDS := {"wheat": [200, 150, 160], "barley": [180, 200, 160], "rye": [160, 150, 170], "oats": [160, 145, 180], "millet": [160, 170, 120], "beans": [180, 140, 130], "peas": [150, 135, 170], "vegetables": [210, 160, 175]}
const RACE_CROPS := {
	"human": ["wheat", "barley", "rye", "oats", "millet", "beans", "peas", "vegetables"],
	"elf": ["wheat", "rye", "oats", "beans", "peas", "vegetables"],
	"moon_elf": ["wheat", "rye", "oats", "beans", "peas", "vegetables"],
	"dwarf": ["barley", "rye", "oats", "beans", "peas", "vegetables"],
	"orc": ["barley", "millet", "beans", "vegetables"],
	"goblin": ["barley", "rye", "millet", "beans", "vegetables"]}

## The same feasible crop and soil yield drive field rotation and new-town sizing.
## Every staple sells as grain, so price and plot area do not change this ordering.
static func choose_crop(race: String, climate: String, soil: String, phase: int) -> String:
	var group: String = ["cereal", "legume", "garden", "fallow"][posmod(phase, 4)]
	var best := "fallow"
	var value := -INF
	for crop in RACE_CROPS.get(race, RACE_CROPS["human"]):
		var row: Dictionary = ROWS[crop]
		if row["group"] != group or not row["climates"].has(climate): continue
		var yield_v := soil_yield(String(crop), soil)
		if yield_v > value:
			value = yield_v
			best = String(crop)
	return best

## Before physical plots exist, size land for the full rotation across the three
## generated soil textures. Climate's yield multiplier is applied by the caller,
## as it is for actual harvests. Existing maps keep their own acres and textures.
static func mean_yield(e: Dictionary, good: String = "grain") -> float:
	if good != "grain": return float(TownEcon.data()["land"]["yield"].get(good, 0))
	var total := 0.0
	var race := Persons.race_of(e)
	var climate := String(e.get("climate", "temperate"))
	for soil in ["loam", "light", "heavy"]:
		for phase in 4:
			total += soil_yield(choose_crop(race, climate, soil, phase), soil)
	return total / 12.0

static func ensure(e: Dictionary, P: Dictionary, day: float) -> void:
	if P.is_empty(): return
	var n := Plots.count(P)
	if not P.has("variety"):
		P["variety"] = []; P["soil"] = []; P["rotation_phase"] = []
	var year := Calendar.year(day)
	if P["variety"].size() == n and int(P.get("crop_year", -999)) == year and int(P.get("crop_count", -1)) == n and P.has("crop_work_acres") and P.has("crop_work_plots"): return
	var climate := String(e.get("climate", "temperate"))
	var race := Persons.race_of(e)
	var counts := {}
	for i in n:
		_ensure_plot(e, P, i, year, race, climate, day)
		if int(P["use"][i]) in Plots.LAND_USES and String(P["crops"][int(P["sub"][i])]) == "grain":
			var best := String(P["variety"][i])
			counts[best] = float(counts.get(best, 0)) + float(P["ac"][i])
	P["crop_year"] = year; P["crop_count"] = n
	var yields := {}
	var names := {}
	var work := {}
	var plots: Dictionary = {}
	# Build read-only indices together; purchase previews need only the two owners.
	for i in n:
		if not int(P["use"][i]) in Plots.LAND_USES: continue
		var fid := str(int(P["own"][i]))
		var v := String(P["variety"][i])
		var good := String(P["crops"][int(P["sub"][i])])
		if not work.has(fid):
			work[fid] = {}
			plots[fid] = {}
		if not work[fid].has(good):
			work[fid][good] = {"active": 0.0, "fallow": 0.0}
			plots[fid][good] = []
		plots[fid][good].append(i)
		var task := "fallow" if v == "fallow" else "active"
		work[fid][good][task] += float(P["ac"][i])
		if int(P["use"][i]) == Plots.FIELD and String(P["crops"][int(P["sub"][i])]) == "grain":
			if not yields.has(fid): yields[fid] = [0.0, 0.0, 0.0]
			yields[fid][0] += float(P["ac"][i])
			yields[fid][1] += float(P["ac"][i]) * soil_yield(v, String(P["soil"][i]))
			if ROWS.get(v, {}).get("group", "") == "cereal": yields[fid][2] += float(P["ac"][i])
		if v == "" or v == "fallow": continue
		if not names.has(fid): names[fid] = {}
		names[fid][v] = float(names[fid].get(v, 0)) + float(P["ac"][i])
	P["crop_names"] = names
	P["crop_yields"] = yields
	P["crop_work_acres"] = work
	P["crop_work_plots"] = plots
	e["crop_mix"] = counts
	e["crops"]["grain"] = "mixed crops"
	Plots._dirty(P)
	P["_crop_work_plots_valid"] = true

## Shared per-plot soil, rotation_phase, and variety rule used by ensure() and split moves.
static func _ensure_plot(e: Dictionary, P: Dictionary, i: int, year: int, race: String, climate: String, day: float) -> void:
	if not P.has("variety"):
		P["variety"] = []; P["soil"] = []; P["rotation_phase"] = []
	while P["variety"].size() <= i:
		var k: int = P["variety"].size()
		P["variety"].append("")
		# Soil texture belongs to the generated plot, independent of names and household IDs.
		P["soil"].append(["loam", "light", "heavy"][posmod(int(P["x"][k]) + 2 * int(P["y"][k]), 3)])
		P["rotation_phase"].append(posmod(int(P["x"][k]) + int(P["y"][k]), 4))
	if not int(P["use"][i]) in Plots.LAND_USES:
		P["variety"][i] = ""
		return
	var good := String(P["crops"][int(P["sub"][i])])
	if good != "grain":
		P["variety"][i] = String(e["crops"].get(good, good))
		return
	var previous := String(P["variety"][i])
	var phase := posmod(int(P["rotation_phase"][i]) + year, 4)
	var best := choose_crop(race, climate, String(P["soil"][i]), phase)
	P["variety"][i] = best
	if previous != "" and previous != best:
		Plots._hist(P, i, day, "Rotated from %s to %s." % [previous, best])

## Shifts grain variety acres in e["crop_mix"] when acres move between plots.
static func _move_mix_acres(e: Dictionary, P: Dictionary, from_plot: int, to_plot: int, acres: int) -> void:
	if acres <= 0 or not e.has("crop_mix"): return
	if not int(P["use"][from_plot]) in Plots.LAND_USES: return
	if String(P["crops"][int(P["sub"][from_plot])]) != "grain": return
	var mix: Dictionary = e["crop_mix"]
	var vf := String(P["variety"][from_plot])
	var vt := String(P["variety"][to_plot])
	mix[vf] = float(mix.get(vf, 0)) - float(acres)
	mix[vt] = float(mix.get(vt, 0)) + float(acres)

## Per-owner derived crop rows in ascending plot order from candidate indices, matching ensure().
static func _owner_index(P: Dictionary, fid_str: String, candidates = null) -> Array:
	var fid := int(fid_str)
	var n := Plots.count(P)
	var idxs: Array = []
	if candidates == null:
		for i in n:
			if int(P["own"][i]) == fid and int(P["use"][i]) in Plots.LAND_USES:
				idxs.append(i)
	else:
		for raw in candidates:
			var i := int(raw)
			if i >= 0 and i < n and int(P["own"][i]) == fid and int(P["use"][i]) in Plots.LAND_USES:
				idxs.append(i)
		idxs.sort()
	var work_row := {}
	var plots_row := {}
	var yields_row = null
	var names_row = null
	var prev := -1
	for idx in idxs:
		var i := int(idx)
		if i == prev: continue
		prev = i
		var v := String(P["variety"][i])
		var good := String(P["crops"][int(P["sub"][i])])
		if not work_row.has(good):
			work_row[good] = {"active": 0.0, "fallow": 0.0}
			plots_row[good] = []
		plots_row[good].append(i)
		var task := "fallow" if v == "fallow" else "active"
		work_row[good][task] += float(P["ac"][i])
		if int(P["use"][i]) == Plots.FIELD and good == "grain":
			if yields_row == null: yields_row = [0.0, 0.0, 0.0]
			yields_row[0] += float(P["ac"][i])
			yields_row[1] += float(P["ac"][i]) * soil_yield(v, String(P["soil"][i]))
			if ROWS.get(v, {}).get("group", "") == "cereal": yields_row[2] += float(P["ac"][i])
		if v == "" or v == "fallow": continue
		if names_row == null: names_row = {}
		names_row[v] = float(names_row.get(v, 0)) + float(P["ac"][i])
	return [work_row, plots_row, yields_row, names_row]

## Incrementally refreshes derived indices for fids over their prior plots and touched indices.
static func reindex_owners(e: Dictionary, P: Dictionary, fids: Array, touched: Array = []) -> bool:
	if P.is_empty(): return false
	var n := Plots.count(P)
	var year := Calendar.year(float(e.get("day", 0)))
	var cc := int(P.get("crop_count", -1))
	if not bool(P.get("_crop_work_plots_valid", false)) or int(P.get("crop_year", -999)) != year or cc < 0 or cc > n:
		return false
	if not P.has("crop_work_acres") or not P.has("crop_work_plots") or not P.has("crop_yields") or not P.has("crop_names"):
		return false
	if not P.has("variety") or P["variety"].size() != n or not P.has("soil") or P["soil"].size() != n or not P.has("rotation_phase") or P["rotation_phase"].size() != n:
		return false
	var work: Dictionary = P["crop_work_acres"]
	var plots: Dictionary = P["crop_work_plots"]
	var yields: Dictionary = P["crop_yields"]
	var names: Dictionary = P["crop_names"]
	var candidates: Array = []
	var seen_fids := {}
	for fid in fids:
		var fid_str := str(int(fid))
		if seen_fids.has(fid_str): continue
		seen_fids[fid_str] = true
		var by_good: Dictionary = plots.get(fid_str, {})
		for good in by_good:
			candidates.append_array(by_good[good])
	candidates.append_array(touched)
	var seen := {}
	for fid in fids:
		var fid_str := str(int(fid))
		if seen.has(fid_str): continue
		seen[fid_str] = true
		var row := _owner_index(P, fid_str, candidates)
		if (row[0] as Dictionary).is_empty():
			work.erase(fid_str)
			plots.erase(fid_str)
		else:
			work[fid_str] = row[0]
			plots[fid_str] = row[1]
		if row[2] == null: yields.erase(fid_str)
		else: yields[fid_str] = row[2]
		if row[3] == null: names.erase(fid_str)
		else: names[fid_str] = row[3]
	P["crop_count"] = n
	return true

## Real active and fallow acres by good, from the same physical owner/rotation
## index as harvest attribution. Older plot books rebuild this derived index;
## a town without physical plots retains its prior crop-work fallback.
static func work_acres(e: Dictionary, f: Dictionary) -> Dictionary:
	var P: Dictionary = e.get("plots", {})
	if P.is_empty():
		var out := {}
		for good in f["land"]:
			out[good] = {"active": float(f["land"][good]), "fallow": 0.0}
		return out
	ensure(e, P, float(e.get("day", 0)))
	return P.get("crop_work_acres", {}).get(str(int(f["id"])), {})

static func harvest_yield(e: Dictionary, good: String) -> float:
	var P: Dictionary = e.get("plots", {})
	if P.is_empty() or not P.has("variety") or good != "grain": return float(TownEcon.data()["land"]["yield"].get(good, 0))
	ensure(e, P, float(e.get("day", 0)))
	var output := 0.0
	var acres := 0.0
	for key in P.get("crop_yields", {}):
		var fid := int(key)
		var worked := float(e["fams"][fid].get("worked", 0)) if fid >= 0 and fid < e["fams"].size() else 0.0
		var row: Array = P["crop_yields"][key]
		acres += float(row[0]) * worked; output += float(row[1]) * worked
	return output / maxf(0.001, acres)

static func family_yield(e: Dictionary, f: Dictionary, good: String) -> float:
	if good != "grain": return float(TownEcon.data()["land"]["yield"].get(good, 0))
	var P: Dictionary = e.get("plots", {})
	if P.is_empty(): return float(TownEcon.data()["land"]["yield"].get(good, 0))
	ensure(e, P, float(e.get("day", 0)))
	var row: Array = P.get("crop_yields", {}).get(str(int(f["id"])), [0, 0, 0])
	return float(row[1]) / maxf(1, float(row[0]))

static func farm_name(e: Dictionary, f: Dictionary) -> String:
	var P: Dictionary = e.get("plots", {})
	if not P.is_empty(): ensure(e, P, float(e.get("day", 0)))
	var areas: Dictionary = P.get("crop_names", {}).get(str(int(f["id"])), {})
	if areas.is_empty(): return "Livestock Farm" if not f["herd"].is_empty() else "Farm"
	var keys: Array = areas.keys()
	keys.sort_custom(func(a, b): return areas[a] > areas[b] if areas[a] != areas[b] else a < b)
	var name := String(keys[0])
	if name in ["apples", "pears", "figs"]: return name.trim_suffix("s").capitalize() + " Orchard"
	if name == "grapes": return "Vineyard"
	if keys.size() > 1 and float(areas[keys[1]]) == float(areas[keys[0]]): name += " and " + String(keys[1])
	return name.capitalize() + " Farm"

static func soil_yield(crop: String, soil: String) -> float:
	return float(SOIL_YIELDS.get(crop, [0, 0, 0])[["loam", "light", "heavy"].find(soil)])

static func cereal_acres(e: Dictionary) -> float:
	var P: Dictionary = e.get("plots", {})
	if P.is_empty(): return 0
	ensure(e, P, float(e.get("day", 0)))
	var acres := 0.0
	for key in P.get("crop_yields", {}):
		var fid := int(key)
		if fid >= 0 and fid < e["fams"].size(): acres += float(P["crop_yields"][key][2]) * float(e["fams"][fid].get("worked", 0))
	return acres
