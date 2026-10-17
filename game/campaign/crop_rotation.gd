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
	while P["variety"].size() < n:
		var i: int = P["variety"].size()
		P["variety"].append("")
		# Soil texture belongs to the generated plot, independent of names and household IDs.
		P["soil"].append(["loam", "light", "heavy"][posmod(int(P["x"][i]) + 2 * int(P["y"][i]), 3)])
		P["rotation_phase"].append(posmod(int(P["x"][i]) + int(P["y"][i]), 4))
	var year := Calendar.year(day)
	if int(P.get("crop_year", -999)) == year and int(P.get("crop_count", -1)) == n and P.has("crop_work_acres"): return
	var climate := String(e.get("climate", "temperate"))
	var race := Persons.race_of(e)
	var counts := {}
	for i in n:
		if not int(P["use"][i]) in Plots.LAND_USES: P["variety"][i] = ""; continue
		var good := String(P["crops"][int(P["sub"][i])])
		if good != "grain":
			P["variety"][i] = String(e["crops"].get(good, good))
			continue
		var previous := String(P["variety"][i])
		var phase := posmod(int(P["rotation_phase"][i]) + year, 4)
		var best := choose_crop(race, climate, String(P["soil"][i]), phase)
		P["variety"][i] = best
		counts[best] = float(counts.get(best, 0)) + float(P["ac"][i])
		if previous != "" and previous != best: Plots._hist(P, i, day, "Rotated from %s to %s." % [previous, best])
	P["crop_year"] = year; P["crop_count"] = n
	var yields := {}
	var names := {}
	var work := {}
	# Build both read-only indices in one plot walk; quantities and accumulation order are unchanged.
	for i in n:
		if not int(P["use"][i]) in Plots.LAND_USES: continue
		var fid := str(int(P["own"][i]))
		var v := String(P["variety"][i])
		var good := String(P["crops"][int(P["sub"][i])])
		if not work.has(fid): work[fid] = {}
		if not work[fid].has(good): work[fid][good] = {"active": 0.0, "fallow": 0.0}
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
	e["crop_mix"] = counts
	e["crops"]["grain"] = "mixed crops"
	Plots._dirty(P)

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
