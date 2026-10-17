extends RefCounted
## Actual household/property/save paths; no household names or generated IDs are targets.

var fails := 0
var checks := 0
var api

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", msg)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func owner(f: Dictionary) -> String:
	return "f:%d" % int(f["id"])

func towns() -> Array:
	var out := []
	for t in Game.world["towns"].values():
		if TownEcon.has_econ(t): out.append(t)
	return out

func household(e: Dictionary) -> Dictionary:
	for f in e["fams"]:
		if not f.get("gone", false) and not f.get("estate", false) and Families.serving(f) == 0 and Families.acres(f) > 0:
			return f
	return {}

func empty_barn(e: Dictionary) -> void:
	api.ensure(e)
	for g in e["barn"].keys(): api.lose(e, String(g), int(e["barn"][g]))

func fund_credit(e: Dictionary, shares: Dictionary, value: float) -> void:
	# Fund the receipt from a real existing purse, never compensation money.
	check(float(e["treasury"]) >= value, "generated treasury funds the controlled purchase")
	e["treasury"] = float(e["treasury"]) - value
	api.credit(e, shares, value)

func land_and_crop() -> void:
	Game.new_game(31031)
	var t: Dictionary = towns()[0]; var e: Dictionary = t["econ"]
	var f := household(e); check(not f.is_empty(), "generated land seller exists")
	if f.is_empty(): return
	var buyer: Dictionary = e["fams"][0]
	empty_barn(e)
	api.add(e, "grain", 20, {owner(f): 20.0}, int(e["day"]), "harvest")
	var old_id := owner(f)
	var crop: String = f["land"].keys()[0]
	var old_work := float(f["worked"])
	Families.move_land(e, f, buyer, crop, int(f["land"][crop]))
	Families.set_worked(e, f, 0.0)
	check(near(api.owned(e, old_id, "grain"), 20), "land transfer and work departure retain prior physical producer ownership")
	check(near(api.owned(e, owner(buyer), "grain"), 0), "land buyer receives no past harvest")
	# Selling all remaining land must not erase a stored claim or require new acres.
	for c in f["land"].keys(): Families.move_land(e, f, buyer, String(c), int(f["land"][c]))
	check(Families.acres(f) == 0, "seller is now landless")
	var cash := Barge.holdings(Game)
	var receipt: Dictionary = api.take(e, "grain", 5, false, old_id)
	fund_credit(e, receipt["shares"], 15.0)
	var before := float(f["purse"])
	Families.settle(e, f)
	var tribute := float(e.get("ruler", {}).get("tribute", 0)) if String(e.get("ruler", {}).get("kind", "")) == "coin" else 0.0
	check(near(float(f["purse"]) - before, 15.0 * (1.0 - tribute)), "landless actual producer receives its cash, with existing tribute")
	Families.settle(e, f)
	check(near(float(f["purse"]) - before, 15.0 * (1.0 - tribute)), "landless producer settlement is once-only")
	check(near(Barge.holdings(Game), cash), "sale and landless settlement conserve all campaign coins")
	api.reserve_food(e, f)
	var rate := float(Families.daily_rates(e, f)["food"])
	var kept := Families.keep_harvest(e, f, 10, rate)
	check(kept > 0 and kept <= 10, "landless former owner can retain its actual stored harvest")
	check(near(api.owned(e, old_id, "grain"), 15 - kept), "retention consumes only the owner's remaining physical claim")
	check(old_work >= 0, "generated staffing fraction was valid")

func inheritance(kind: String) -> void:
	Game.new_game(71031)
	var t: Dictionary = towns()[0]; var e: Dictionary = t["econ"]
	var f := household(e); check(not f.is_empty(), kind + ": actual household exists")
	if f.is_empty(): return
	empty_barn(e)
	api.add(e, "grain", 31, {owner(f): 31.0}, int(e["day"]), "harvest")
	api.reserve_food(e, f)
	var cash := Barge.holdings(Game)
	var receipt: Dictionary = api.take(e, "grain", 7, false, owner(f))
	fund_credit(e, receipt["shares"], 21.0)
	if kind == "extinct": Families.extinct(e, f, float(e["day"]))
	else: Families.leave_town(e, f, float(e["day"]))
	check(f.get("gone", false), kind + ": actual lifecycle closes the household")
	check(near(api.owned(e, owner(f), "grain"), 0), kind + ": former household owns no unsold inherited grain")
	check(near(api.owned(e, "f:0", "grain"), 24), kind + ": estate inherits exact unsold physical grain")
	check(int(e["barn"]["grain"]) == 24, kind + ": property transfer never duplicates or destroys grain")
	check(api.available(e, "grain") == 24, kind + ": departed household food reservation is released")
	check(near(Barge.holdings(Game), cash), kind + ": property and cash inheritance conserve coins")
	var state := JSON.stringify(e)
	if kind == "extinct": Families.extinct(e, f, float(e["day"]))
	else: Families.leave_town(e, f, float(e["day"]))
	check(JSON.stringify(e) == state, kind + ": repeating closed lifecycle is idempotent")

func migration() -> void:
	Game.new_game(81031)
	var all := towns(); check(all.size() > 1, "two actual towns exist for relocation")
	if all.size() < 2: return
	var t: Dictionary = all[0]; var e: Dictionary = t["econ"]
	var other: Dictionary = all[1]
	var f := household(e); check(not f.is_empty(), "actual migrant household exists")
	if f.is_empty(): return
	empty_barn(e)
	api.add(e, "grain", 30, {owner(f): 30.0}, int(e["day"]), "harvest")
	api.reserve_food(e, f)
	var old_id := int(f["id"])
	var nf := Barge.move_family(Game, t, f, other, "harvest test", float(e["day"]))
	check(near(api.owned(e, owner(f), "grain"), 30), "migration retains unsold producer ownership in origin barn")
	check(near(float(nf.get("hv", 0)), 0) and near(float(nf.get("legacy_hv", 0)), 0), "destination household cannot copy origin food entitlement")
	check(api.available(e, "grain") == 30, "migration releases origin own-food reservation")
	var middle := nf
	nf = Barge.move_family(Game, other, middle, t, "harvest test", float(e["day"]))
	var new_id := int(nf["id"])
	Persons.pack_gone(e, f, float(e["day"]))
	Persons.pack_gone(e, f, float(e["day"]) + Persons.GONE_PACK_DAYS + 1)
	check(f.get("packed", false), "real gone-record packing ran before deferred sale")
	var tid := String(t["id"])
	Game.save_game(); check(Game.load_game(), "two migrations and packed origin survive actual loader")
	e = Game.world["towns"][tid]["econ"]; f = e["fams"][old_id]; nf = e["fams"][new_id]
	check(near(api.owned(e, owner(f), "grain"), 30), "load retains packed origin's exact stored ownership")
	var cash := Barge.holdings(Game)
	var receipt: Dictionary = api.take(e, "grain", 10, false, owner(f))
	var before := float(nf["purse"])
	fund_credit(e, receipt["shares"], 30.0)
	api.pay_departed(e)
	var tribute := float(e.get("ruler", {}).get("tribute", 0)) if String(e.get("ruler", {}).get("kind", "")) == "coin" else 0.0
	check(near(float(nf["purse"]) - before, 30 * (1.0 - tribute)), "deferred sale follows repeated real moves to surviving household")
	check(near(float(f["purse"]), 0), "packed departed origin receives no duplicate purse")
	api.pay_departed(e)
	check(near(float(nf["purse"]) - before, 30 * (1.0 - tribute)), "deferred routed sale is paid once")
	check(near(Barge.holdings(Game), cash), "deferred routed sale conserves world money")
	var received := float(nf.get("harvest_receipts", 0))
	check(near(received, 30 * (1.0 - tribute)), "routed proceeds have a household income receipt")
	for job in nf["jobs"].keys(): Families.set_job(e, nf, int(job), 0)
	nf["store"] = {"food": 100.0, "drink": 100.0, "wood": 100.0}
	var rng := RandomNumberGenerator.new(); rng.seed = 19031
	var turn_day := float(nf["last"]) + 7.0; e["day"] = int(turn_day); Game.day = turn_day
	Families.turn(Game, Game.world["towns"][tid], e, nf, turn_day, rng)
	check(near(float(nf["income_parts"].get("land", 0)), received) and not nf.has("harvest_receipts"), "ordinary landless destination turn reports routed harvest receipt once")
	for job in nf["jobs"].keys(): Families.set_job(e, nf, int(job), 0)
	turn_day += 7.0; e["day"] = int(turn_day); Game.day = turn_day
	Families.turn(Game, Game.world["towns"][tid], e, nf, turn_day, rng)
	check(near(float(nf["income_parts"].get("land", 0)), 0), "next destination turn cannot report prior routed harvest twice")

func queue_save() -> void:
	Game.new_game(91031)
	var t: Dictionary = towns()[0]; var e: Dictionary = t["econ"]
	var f := household(e); check(not f.is_empty(), "queued-save owner exists")
	if f.is_empty(): return
	var tid := String(t["id"]); var fid := int(f["id"])
	empty_barn(e)
	api.add(e, "grain", 40, {owner(f): 40.0}, int(e["day"]), "harvest")
	var receipt: Dictionary = api.take(e, "grain", 3, false, owner(f))
	fund_credit(e, receipt["shares"], 9)
	var d := int(e["day"]) + 1
	Game.world["work"] = [["econ", tid, d], ["fam", tid, d], ["fam2", tid, d]]
	var jobs: Array = Game.world["work"].duplicate(true)
	var before_goods := int(e["barn"]["grain"])
	var cash := Barge.holdings(Game)
	Game.save_game(); check(Game.load_game(), "actual save restores pending harvest receipt and queued days")
	e = Game.world["towns"][tid]["econ"]; f = e["fams"][fid]
	check(Game.world["work"] == JSON.parse_string(JSON.stringify(jobs)), "actual load retains queued econ/fam/fam2 day jobs")
	check(near(api.owned(e, owner(f), "grain"), 37), "save/load preserves unsold attributed physical grain")
	check(near(Barge.holdings(Game), cash), "save/load preserves cash backing pending claims")
	check(int(e["barn"]["grain"]) == before_goods, "save/load does not replay past physical harvest")
	var before := float(f["purse"])
	Families.settle(e, f)
	check(float(f["purse"]) > before, "restored pending harvest receipt remains payable")
	var paid := float(f["purse"])
	Game.save_game(); check(Game.load_game(), "settled harvest save loads again")
	e = Game.world["towns"][tid]["econ"]; f = e["fams"][fid]
	Families.settle(e, f)
	check(near(float(f["purse"]), paid), "repeat load cannot replay already settled harvest receipt")
	# Close an actual queued day once, then verify its retained job is harmless on replay.
	t = Game.world["towns"][tid]
	TownEcon.do_job(Game, jobs[0])
	var barn: Dictionary = e["barn"].duplicate(true)
	var owned := float(api.owned(e, owner(f), "grain"))
	TownEcon.do_job(Game, jobs[0])
	check(e["barn"] == barn and near(api.owned(e, owner(f), "grain"), owned), "replayed queued econ day does not add a second harvest")

func invariant(e: Dictionary, label: String) -> void:
	for g in e["barn"]:
		var attributed := float(api.owned(e, "?", String(g)))
		for f in e["fams"]: attributed += float(api.owned(e, owner(f), String(g)))
		for b in e["biz"]: attributed += float(api.owned(e, "b:%d" % int(b["id"]), String(g)))
		check(near(attributed, float(e["barn"][g])), label + ": claims plus unknown exactly back physical " + String(g))
		check(api.available(e, String(g)) >= 0 and api.available(e, String(g)) <= int(e["barn"][g]), label + ": sale availability bounded by physical " + String(g))

func legacy_checkpoint() -> void:
	var path := OS.get_environment("HARVEST_LEGACY_SAVE")
	if path == "": path = ProjectSettings.globalize_path("res://../../evidence/v0.030-final-labour/checkpoint-save.json")
	check(FileAccess.file_exists(path), "real isolated v0.030 campaign checkpoint exists")
	if not FileAccess.file_exists(path): return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(d.has("world") and d.has("day"), "legacy fixture is an actual complete game save")
	if not d.has("world"): return
	# _deserialize consumes its argument in place; preserve the original tagged save.
	Game.world = Game._deserialize(d["world"].duplicate(true)); Game.gold = int(d["gold"])
	var before_money := Barge.holdings(Game)
	var before := {}
	var old_hv := {}
	for t in towns():
		var goods: Dictionary = t["econ"]["barn"].duplicate(true)
		for g in goods: goods[g] = int(goods[g])
		before[String(t["id"])] = goods
		var entitlements := {}
		for f in t["econ"]["fams"]: entitlements[str(int(f["id"]))] = float(f.get("hv", 0))
		old_hv[String(t["id"])] = entitlements
	var jobs: Array = Game.world.get("work", []).duplicate(true)
	Game._write_save(Game.SAVE_PATH, d)
	check(Game.load_game(), "real old campaign loads through actual migration")
	check(near(Barge.holdings(Game), before_money), "old-save ownership migration makes and loses no money")
	check(Game.world.get("work", []) == jobs, "old-save migration preserves every pending campaign job")
	for t in towns():
		var e: Dictionary = t["econ"]
		check(e["barn"] == before[String(t["id"])], "old-save migration preserves every physical barn quantity")
		for f in e["fams"]:
			var old := float(old_hv[String(t["id"])][str(int(f["id"]))])
			check(near(float(f.get("legacy_hv", 0)), old), "old-save preserves each original numeric food entitlement as legacy metadata")
			var reserved := float(api.owned(e, owner(f), "grain", true)) + float(api.owned(e, owner(f), "fruit", true))
			check(near(float(f.get("hv", 0)), reserved), "loaded hv equals physically backed own-food reservation")
		invariant(e, "legacy loaded town")
	var after := Game._save_tree()
	Game.save_game(); check(Game.load_game(), "migrated actual old save loads a second time")
	check(near(Barge.holdings(Game), before_money), "second old-save load leaves world money unchanged")
	for t in towns():
		check(t["econ"]["barn"] == before[String(t["id"])], "second old-save load leaves physical barn inventory unchanged")
		for f in t["econ"]["fams"]:
			check(near(float(f.get("legacy_hv", 0)), float(old_hv[String(t["id"])][str(int(f["id"]))])), "repeat old-save load preserves original legacy metadata")
		invariant(t["econ"], "legacy repeated load")
	check(Game.world.get("work", []) == jobs, "second old-save load keeps pending campaign jobs")
	# Continue real town time, avoiding presim's history-limit early return.
	var day := int(Game.day) + 1
	for t in towns():
		TownEcon.daily_pass(Game, t, day, false)
		check(int(t["econ"]["day"]) == day, "real legacy town continuation advances one actual day")
		invariant(t["econ"], "legacy continued town")
	check(after.has("world"), "migrated checkpoint remains saveable as a full campaign")

func legacy_boundaries() -> void:
	Game.new_game(11031)
	var e: Dictionary = towns()[0]["econ"].duplicate(true)
	var first := Families._blank(1); first["m"] = 1; first["land"] = {"grain": 1}; first["hv"] = 80.0
	var second := Families._blank(2); second["m"] = 1; second["land"] = {"grain": 1}; second["hv"] = 20.0
	var estate := Families._blank(0); estate["estate"] = true
	e["fams"] = [estate, first, second]; e["barn"] = {"grain": 20}; e["farm_till"] = 321.5; e["cum"] = {"grain": 7.25}
	e.erase("harvest_book")
	api.ensure(e)
	check(near(float(first["legacy_hv"]), 80) and near(float(second["legacy_hv"]), 20), "legacy metadata preserves original numerical entitlements")
	check(near(float(first["hv"]), 16) and near(float(second["hv"]), 4), "short old food allocates saved retention proportionally and physically")
	check(near(float(e["farm_till"]), 321.5) and near(float(e["cum"]["grain"]), 7.25), "ownership migration preserves old cash and cumulative books")
	check(api.available(e, "grain") == 0, "bounded old physical food reserve is excluded from broker sale")
	api.lose(e, "grain", 20)
	api.add(e, "grain", 6, {"f:2": 6.0}, int(e["day"]) + 1, "harvest")
	var kept := Families.keep_harvest(e, first, 6, float(Families.daily_rates(e, first)["food"]))
	check(kept == 0 and near(api.owned(e, "f:2", "grain"), 6), "unbacked legacy metadata never claims another producer's future harvest")
	check(near(float(first["legacy_hv"]), 80), "physical legacy loss does not rewrite historical entitlement metadata")
	# Unattributed goods remain anonymous after sale and their money stays backed.
	api.add(e, "fruit", 7, {"?": 7.0}, int(e["day"]), "legacy")
	var sold: Dictionary = api.take(e, "fruit", 3, true)
	var purse := float(first["purse"]) + float(second["purse"])
	var cash := float(e["farm_till"])
	api.credit(e, sold["shares"], 9.0)
	check(near(float(e["farm_till"]), cash + 9) and near(float(e["harvest_book"]["unattributed_cash"]), 9), "unknown old-goods sale preserves separately backed unattributed proceeds")
	check(near(float(first["purse"]) + float(second["purse"]), purse), "unknown old-goods sale invents no household creditor")
	invariant(e, "legacy boundary fixture")

func damaged_book() -> void:
	Game.new_game(12031)
	var e: Dictionary = towns()[0]["econ"].duplicate(true)
	var f := Families._blank(1); f["m"] = 1
	var estate := Families._blank(0); estate["estate"] = true
	e["fams"] = [estate, f]; e["barn"] = {"grain": 10}; e["cum"] = {}; e["ruler"] = {}
	# Missing reserve/source/carry/cache/version fields and oversized claim.
	e["harvest_book"] = {"lots": {"grain": [{"day": 3.0, "shares": {"f:1": 20.0}}]}, "cash": {"f:bad": 3.0, "b:bad": 4.0, "d:": 5.0, "d:missing:5": 6.0}, "unattributed_cash": 7.0}
	e["farm_till"] = 20.0
	var money := TownEcon.town_gold(e)
	api.after_load(e)
	check(int(e["barn"]["grain"]) == 10 and near(api.owned(e, "f:1", "grain"), 10), "damaged oversized claim scales to physical stock without extra goods")
	check(typeof(e["harvest_book"]["version"]) == TYPE_INT and typeof(e["harvest_book"]["lots"]["grain"][0]["day"]) == TYPE_INT, "recovery normalizes saved book version and lot day")
	api.pay_departed(e)
	check(near(TownEcon.town_gold(e), money) and e["harvest_book"]["cash"].size() == 4, "invalid family/business/drover IDs create no creditors and retain unpaid claims")
	# Identified short backing remains unpaid, and protected unknown money is not used.
	e["harvest_book"]["cash"]["f:1"] = 30.0
	var paid := Families.settle(e, f)
	check(near(paid, 13) and near(float(f["purse"]), 13) and near(float(e["farm_till"]), 7), "settlement spends only real backing above unknown proceeds")
	check(near(float(e["harvest_book"]["cash"]["f:1"]), 17), "unsupported remainder stays owed to the identified household")
	check(near(TownEcon.town_gold(e), money), "damaged cash recovery invents no compensation coins")
	var again := Families.settle(e, f)
	check(near(again, 0) and near(float(e["harvest_book"]["cash"]["f:1"]), 17), "repeated underbacked settlement preserves unknown cash and unpaid balance")
	e["harvest_book"]["lots"] = {}
	api.after_load(e)
	check(near(api.owned(e, "?", "grain"), 10) and near(api.owned(e, "f:1", "grain"), 0), "missing provenance preserves actual goods as unknown without rebuilding owners from current records")
	invariant(e, "damaged book fixture")

func run(_tree: SceneTree) -> int:
	if not ResourceLoader.exists("res://campaign/harvest_claims.gd"):
		check(false, "baseline lacks persistent harvest ownership needed for lifecycle/save behavior")
		print("HARVEST LIFECYCLE checks=", checks, " failures=", fails)
		return fails
	api = load("res://campaign/harvest_claims.gd")
	WorldGen.gen_size = "normal"
	land_and_crop()
	for kind in ["extinct", "leave"]: inheritance(kind)
	migration()
	queue_save()
	legacy_boundaries()
	damaged_book()
	legacy_checkpoint()
	print("HARVEST LIFECYCLE checks=", checks, " failures=", fails)
	return fails
