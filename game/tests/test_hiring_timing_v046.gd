extends RefCounted

var fails := 0
var checks := 0
func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", msg)

# Companion to unchanged test_hiring_timing.gd; all 54 assertions and wage timing are retained.
# Move the selected adult's actual plots and age-specific animals to the estate.
# Native ownership transfers preserve the holdings; no physical records are erased.
func fixture() -> Array:
	for t in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false) or Families.adults(f) != 1 or Families.serving(f) != 0: continue
			if int(f["kids"]) > 0 or int(f["old"]) > 0: continue
			for family in e["fams"]:
				for k in family["jobs"].keys(): Families.set_job(e, family, int(k), 0)
				Shelter.release_casual(e, family)
			for b in e["biz"]: b["closed"] = true
			var estate: Dictionary = e["fams"][0]
			for crop in f["land"].keys():
				Families.move_land(e, f, estate, String(crop), int(f["land"][crop]))
			for animal in f["herd"].keys():
				Families.move_herd(e, f, estate, String(animal), int(f["herd"][animal]))
			for source in Herds.of_family(e, int(f["id"])):
				var destination := Herds.herd_for(e, 0, String(source["k"]), float(e["day"]))
				for age in ["o", "y", "g"]:
					var n := int(source[age])
					if n > 0:
						Herds._transfer(e, source, destination, age, n, "sold", "bought",
							"controlled hiring fixture", "controlled hiring fixture", float(e["day"]))
			assert(Families.need_hands(f, e) == 0.0, "native holding transfers free the selected adult")
			f["owns"] = []; f["keeps"] = []; f["farm"] = -1
			f["hands"] = 0; f["idle"] = 1; f["unpaid"] = 0; f["hungry"] = 0; f["debt"] = 0.0
			f["purse"] = 100000.0; f["homes"] = 1; f["cond"] = 1.0
			f["store"] = {"food": 100.0, "drink": 100.0, "wood": 100.0}
			for key in ["hl", "rent", "landlord", "cjearned"]: f.erase(key)
			e["cjcap"] = {}; e["cjused"] = {}; e["treasury"] = 1000000.0
			var b := Businesses._row(e, "carpenter", -1, 1, TownEcon.data())
			b["wage"] = 100.0; b["till"] = 100000.0
			return [t, e, f, b]
	return []

func ordinary_turn(t: Dictionary, e: Dictionary, f: Dictionary) -> void:
	var day := float(f["last"]) + 7.0
	# Advance the actual employer days rather than asking a payday to invent
	# a preceding week at today's advertised wage. Expected pay stays 700.
	for d in range(int(e["day"]) + 1, int(day) + 1):
		e["day"] = d
		WageClaims.accrue_day(e, d)
	e["day"] = int(day); Game.day = day
	var rng := RandomNumberGenerator.new(); rng.seed = 9981
	Families.turn(Game, t, e, f, day, rng)

func reopened_place(rows: Array) -> void:
	var t: Dictionary = rows[0]; var e: Dictionary = rows[1]; var f: Dictionary = rows[2]; var b: Dictionary = rows[3]
	var other: Dictionary = {}
	for family in e["fams"]:
		if family != f and not family.get("estate", false) and not family.get("gone", false) and Families.adults(family) > 0:
			other = family; break
	check(not other.is_empty(), "a second real household can vacate the funded job")
	if other.is_empty(): return
	Families.set_job(e, other, int(b["id"]), 1)
	Businesses.rebuild_open(e)
	check(not e["open"].has(int(b["id"])), "full employer is absent from the old hiring list")
	Families.set_job(e, other, int(b["id"]), 0)
	check(Businesses.takeable(b) == 1, "released job is actually funded")
	var till := float(b["till"])
	ordinary_turn(t, e, f)
	check(int(f["jobs"].get(str(int(b["id"])), 0)) == 1, "ordinary family turn sees a job reopened after the hiring list")
	check(float(f["income_parts"]["staff wages"]) == 0.0 and float(b["till"]) == till, "joining does not pay wages for the preceding unemployed week")
	ordinary_turn(t, e, f)
	check(absf(float(f["income_parts"]["staff wages"]) - 700.0) < 0.001, "the following ordinary turn pays the actual worked week")
	check(absf(till - float(b["till"]) - 700.0) < 0.001, "wages come from the employer's existing till")

func better_current_offer(rows: Array) -> void:
	var e: Dictionary = rows[1]; var f: Dictionary = rows[2]; var held: Dictionary = rows[3]
	var better := Businesses._row(e, "carpenter", -1, 1, TownEcon.data())
	better["wage"] = 1000.0; better["till"] = 0.0
	Businesses.rebuild_open(e)
	check(not Families._paid_worse(e, f, e["biz"]), "unfunded higher advertised wage is not an available offer")
	better["till"] = 2000.0
	check(Families._paid_worse(e, f, e["biz"]), "new funding is visible without waiting for the weekly highest-offer cache")
	# An additional paid relative is a wage earner, separately from the keeper.
	held["owner"] = int(f["id"])
	check(Families._paid_worse(e, f, e["biz"]), "paid relatives see better external offers too")
	held["owner"] = -1
	Families.reassign(e, f)
	check(int(f["jobs"].get(str(int(better["id"])), 0)) == 1, "matching chooses the actually funded higher offer")
	check(int(held["workers"]) == 0 and int(better["workers"]) == 1, "the move releases the old place without duplicating its worker")
	better["closed"] = true
	Families.set_job(e, f, int(better["id"]), 0)

func casual_only(rows: Array) -> void:
	var t: Dictionary = rows[0]; var e: Dictionary = rows[1]; var f: Dictionary = rows[2]
	for b in e["biz"]: b["closed"] = true
	f["idle"] = 1
	e["cjcap"] = {"street_sweeper": 1}; e["cjused"] = {}
	Businesses.rebuild_open(e)
	check(int(e["open_n"]) == 0 and Shelter.available_casual(e, "street_sweeper") == 1, "only a funded cleanup vacancy exists")
	ordinary_turn(t, e, f)
	check(int(f.get("cj", {}).get("street_sweeper", 0)) == 1 and int(f["idle"]) == 0, "housed idle adult finds cleanup work through the ordinary family turn")
	var offer := Businesses._row(e, "carpenter", -1, 1, TownEcon.data())
	offer["wage"] = 1000.0; offer["till"] = 2000.0
	check(Families._paid_worse(e, f, e["biz"]), "casual worker sees a better funded ordinary job")
	Families.reassign(e, f)
	check(not f.has("cj") and int(f["jobs"].get(str(int(offer["id"])), 0)) == 1, "casual worker can change job and releases the old cleanup place")
	check(float(e["cjused"].get("street_sweeper", 0)) == 0.0, "casual occupancy releases exactly once")

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	for seed_v in [713, 2026, 8801]:
		Game.new_game(seed_v)
		var rows := fixture(); check(rows.size() == 4, "generated labour fixture exists")
		if rows.size() == 4: reopened_place(rows); better_current_offer(rows); casual_only(rows)
	print("HIRING TIMING checks=", checks, " failures=", fails)
	return fails
