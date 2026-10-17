extends RefCounted
var fails := 0
var checks := 0
func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL ", msg)
func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	for seed_v in [713, 2026, 8801]:
		Game.new_game(seed_v)
		for town in Game.world["towns"].values():
			if not TownEcon.has_econ(town): continue
			var e: Dictionary = town["econ"]
			var P: Dictionary = e["plots"]
			var before: Array = P["variety"].duplicate()
			CropRotation.ensure(e, P, 120)
			var rotated := false
			var areas := 0.0
			for i in Plots.count(P):
				if int(P["use"][i]) == Plots.FIELD and String(P["crops"][int(P["sub"][i])]) == "grain":
					areas += float(P["ac"][i])
					if String(before[i]) != String(P["variety"][i]): rotated = true
					check(CropRotation.ROWS.has(P["variety"][i]), "every staple field has a real variety or fallow")
			check(areas == 0 or rotated, "staple fields rotate between years")
			check(not Herds.A()["kinds"].has("rats") and not Herds.A()["kinds"].has("bees") and not Herds.A()["kinds"].has("dogs"), "household small stock excludes rats, dogs and hive animals")
			var coins := Barge.holdings(Game)
			TownDefence.daily(Game, town)
			check(absf(Barge.holdings(Game) - coins) < 0.01, "professional guard wages conserve coins")
			var units := TownDefence.garrison(Game, String(town["id"]))
			check(int(e["barracks_beds"]) >= units.size(), "beds cover actual garrison")
			for u in units:
				check(u.family >= 0 and not Persons.by_uid(e["fams"][u.family], u.uid).is_empty(), "every garrison member is registered")
			TownDefence.set_muster(Game, town, false)
			for f in e["fams"]:
				if f.get("gone", false) or f.get("estate", false): continue
				var available := Persons.pp(f).filter(func(p): return int(p[6]) == 0 and String(p[4]) in ["", "hire", "reserve"]).size()
				var held: int = int(f["hands"]) + Families.job_total(f) + f.get("keeps", []).size()
				for j in f.get("cj", {}): held += int(f["cj"][j])
				check(held <= available, "civilian jobs, shop keepers and casual work fit the actual people")
			for u in Militia.units_of(Game, String(town["id"])):
				check(String(Persons.by_uid(e["fams"][u.family], u.uid)[4]) == "reserve", "off-duty militia return to civilian status")
			TownDefence.set_muster(Game, town, true)
			for u in Militia.units_of(Game, String(town["id"])):
				check(String(Persons.by_uid(e["fams"][u.family], u.uid)[4]) == "militia", "threat removes militia from civilian availability")
			TownDefence.set_muster(Game, town, false)
			var livestock := 0
			for h in Herds.herds(e).values(): livestock += Herds.head(h)
			HerdRaids.plan(Game, town, 14)
			var after := 0
			for h in Herds.herds(e).values(): after += Herds.head(h)
			check(livestock == after, "planning a distant raid never removes livestock")
			var hive_owner: Dictionary = e["fams"][1]
			hive_owner["hives"] = {"count": 2, "honey_kg": 0.0, "wax_kg": 0.0, "carry_honey": 0.0, "carry_wax": 0.0}
			LivestockCare.hive_week(e, 95)
			check(float(hive_owner["hives"]["honey_kg"]) == 0, "winter hives produce no honey")
	print("Fields/defence: %d checks, %d failures" % [checks, fails])
	return fails
