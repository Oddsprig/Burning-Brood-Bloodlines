extends RefCounted
var fails := 0
var checks := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL ", text)

func coins() -> float:
	var n := Barge.holdings(Game)
	for m in CampaignWorld.mustering(Game.world):
		n += float(m.get("wb", m.get("extra", {})).get("gold", 0))
	return n

# Count all owned Item occurrences, not just UID sets (duplicates must fail).
func item_ids() -> Array:
	var out := []
	for town in Game.world["towns"].values():
		for it in town.get("shop", []) + town.get("armory_items", []): out.append(it.uid)
	for lair in Game.world.get("lairs", {}).values():
		for it in lair.get("stock", []): out.append(it.uid)
	var forces: Array = Game.world["warbands"].values().duplicate()
	for m in CampaignWorld.mustering(Game.world):
		var wb: Dictionary = m.get("wb", m.get("extra", {})).duplicate()
		if not m.has("wb"): wb["units"] = m.get("units", [])
		forces.append(wb)
	for wb in forces:
		for u in wb.get("units", []):
			for it in u.equip.values(): out.append(it.uid)
		for it in wb.get("cargo", {}).get("items", []): out.append(it.uid)
	for c in Game.world.get("arms", {}).get("c", {}).values():
		for it in c.get("staged", []): out.append(it.uid)
	for u in Game.company:
		for it in u.equip.values(): out.append(it.uid)
	for it in Game.stash: out.append(it.uid)
	out.sort()
	return out

func people_ids() -> Array:
	var out := []
	for town in Game.world["towns"].values():
		if not TownEcon.has_econ(town): continue
		for f in town["econ"]["fams"]:
			for p in Persons.pp(f) + Persons.kp(f): out.append("%s:%d:%d" % [town["id"], int(f["id"]), int(p[0])])
	out.sort()
	return out

func towns() -> Array:
	var ids: Array = Game.world["towns"].keys(); ids.sort()
	var by_faction := {}
	for tid in ids:
		var t: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(t) or TownDefence.garrison(Game, String(tid)).is_empty(): continue
		var fid := String(t["faction"])
		if not by_faction.has(fid): by_faction[fid] = []
		(by_faction[fid] as Array).append(t)
	for fid in by_faction:
		if by_faction[fid].size() >= 3:
			for other in by_faction:
				if other != fid: return [by_faction[fid][0], by_faction[fid][1], by_faction[fid][2], by_faction[other][0]]
	return []

func fill(t: Dictionary) -> void:
	var target := ArmsTrade.targets(Game, t)
	var stock := ArmsTrade.armory(t); stock.clear()
	for c in target:
		var tid := ""
		for candidate in (DB.weapons.keys() + DB.armor.keys() + DB.bows.keys()):
			if ArmsTrade.cls(String(candidate)) == c: tid = String(candidate); break
		check(tid != "", "a template exists for every reserve class")
		for i in int(target[c]): stock.append(Item.make(tid, "wood" if DB.is_bow(tid) else "copper", 2))
	ArmsTrade.refresh_reserve(Game, t)

func policy_and_money(ts: Array) -> void:
	for t in ts:
		var need := ArmsTrade.role_counts(ArmsTrade.requirements(Game, t))
		var targets := ArmsTrade.role_counts(ArmsTrade.targets(Game, t))
		for role in need: check(int(targets[role]) == int(ceil(float(need[role]) * 2.5)), "reserve rounds once per actual role")
	var t: Dictionary = ts[0]
	# A dead member cannot inflate targets or the largest caravan's denominator.
	var g := TownDefence.garrison(Game, String(t["id"]))
	var living := ArmsTrade.supported_units(Game, t).size()
	g[0].dead = true
	check(ArmsTrade.supported_units(Game, t).size() == living - 1, "dead troops excluded")
	g[0].dead = false
	var e: Dictionary = t["econ"]
	var mk: Dictionary = e["biz"][int(e["mkt"])]
	var seller: Dictionary = {}
	for b in e["biz"]:
		if b["type"] == "weaponsmith": seller = b; break
	check(not seller.is_empty(), "existing smith owns production sales")
	if seller.is_empty(): return
	var tid := ""
	for c in ArmsTrade.targets(Game, t):
		if String(c).begins_with("w_") and c != "w_bow":
			for k in (DB.weapons.keys() + DB.armor.keys() + DB.bows.keys()):
				if ArmsTrade.cls(String(k)) == c: tid = String(k); break
			if tid != "": break
	check(tid != "", "a required weapon can be purchased")
	if tid == "": return
	ArmsTrade.armory(t).clear(); (t["shop"] as Array).clear()
	var old_equipped := []
	for u in TownDefence.garrison(Game, String(t["id"])):
		old_equipped.append([u, u.equip.duplicate()]); u.equip.clear()
	e["treasury"] = 10000000.0
	var it := Item.make(tid, "copper", 2)
	var price := Economy.base_value(t, it) * float(TownEcon.data()["market"]["arms_buy_share"])
	var c0 := coins(); var treasury := float(e["treasury"]); var receipt := float(seller["till"])
	var accepted := ArmsTrade.order_buy(Game, t, e, it, price)
	if accepted: seller["till"] = float(seller["till"]) + price # Businesses' existing caller owns this credit.
	check(accepted and ArmsTrade.armory(t).has(it), "real direct forge order enters armoury")
	check(absf(float(e["treasury"]) - treasury + price) < 0.001 and absf(float(seller["till"]) - receipt - price) < 0.001, "direct seller credited once")
	check(absf(coins() - c0) < 0.001, "direct procurement conserves coins")
	var market_item := Item.make(tid, "copper", 2); (t["shop"] as Array).append(market_item)
	var market_price := Economy.base_value(t, market_item)
	var market_cash := float(mk["till"]); var smith_cash := float(seller["till"])
	c0 = coins(); treasury = float(e["treasury"])
	ArmsTrade.econ_daily(Game, t, e, int(Game.day), false)
	check(absf(float(mk["till"]) - market_cash - market_price) < 0.001, "market-owned piece pays market once")
	check(float(seller["till"]) == smith_cash, "market resale does not pay smith twice")
	check(absf(coins() - c0) < 0.001 and absf(float(e["treasury"]) - treasury + market_price) < 0.001, "market procurement conserves coins")
	var refused := Item.make(tid, "copper", 2)
	e["treasury"] = ArmsTrade.arms_reserve(Game, t, e)
	c0 = coins(); receipt = float(seller["till"])
	check(not ArmsTrade.order_buy(Game, t, e, refused, price), "wage reserve prevents unaffordable purchase")
	check(coins() == c0 and float(seller["till"]) == receipt and not ArmsTrade.armory(t).has(refused), "refusal changes no ownership or money")
	for pair in old_equipped: pair[0].equip = pair[1]

func distribution(ts: Array) -> void:
	for t in Game.world["towns"].values():
		if TownEcon.has_econ(t):
			fill(t)
			ArmsTrade.rekit_units(Game, t, TownDefence.garrison(Game, String(t["id"])), false, null, true)
			fill(t)
			t["econ"]["armory"] = {}
	var a: Dictionary = ts[0]; var b: Dictionary = ts[1]; var c: Dictionary = ts[2]; var foreign: Dictionary = ts[3]
	# Take a required role from both recipients, leaving exact general shortages.
	var item: Item = ArmsTrade.armory(b)[0]
	var role := ArmsTrade.cls_role(ArmsTrade.cls(item.tid))
	for t in [b, c, foreign]:
		for it in ArmsTrade.armory(t).duplicate():
			if ArmsTrade.cls_role(ArmsTrade.cls(it.tid)) == role: ArmsTrade.armory(t).erase(it)
	var shortage := int(ArmsTrade.role_counts(ArmsTrade.targets(Game, b)).get(role, 0)) + int(ArmsTrade.role_counts(ArmsTrade.targets(Game, c)).get(role, 0))
	for i in shortage + 7: ArmsTrade.armory(a).append(Item.make(item.tid, item.material, 2))
	# An interchangeable foreign melee class must protect the donor reserve.
	var ids0 := item_ids(); var c0 := coins(); var foreign_before := ArmsTrade.armory(foreign).size()
	var arrow_kind: String = DB.arrows.keys()[0]
	a["econ"]["armory"][arrow_kind] = ArmsTrade.arrow_target(Game, a) + 5000
	var arrows0 := 0
	var arrow_ledgers := {}
	for t in Game.world["towns"].values():
		arrows0 += ArmsTrade.arrow_stock(t)
		if TownEcon.has_econ(t):
			var record := {}
			for kind in ["made", "used", "spoil"]:
				for k in DB.arrows: record[kind + String(k)] = int(t["econ"]["led"][kind].get(k, 0))
			arrow_ledgers[t["id"]] = record
	Game.world["arms"]["supply_day"] = -1
	check(ArmsTrade.redistribute(Game, 9) == 0 and item_ids() == ids0, "no transfer between ten-day checkpoints")
	var count := ArmsTrade.redistribute(Game, 10)
	check(count > 0, "real surplus reaches own-faction shortages")
	check(item_ids() == ids0 and absf(coins() - c0) < 0.001, "supply preserves every item occurrence and all money")
	check(ArmsTrade.armory(foreign).size() == foreign_before and ArmsTrade.arrow_stock(foreign) == 0, "foreign and allied-style separate factions get no internal supply")
	for t in [a, b, c]:
		var have := ArmsTrade.role_counts(ArmsTrade.class_counts(ArmsTrade.armory(t)))
		var target := ArmsTrade.role_counts(ArmsTrade.targets(Game, t))
		check(int(have.get(role, 0)) >= int(target.get(role, 0)), "donor reserve and receiver role coverage respected")
	check(ArmsTrade._short(ArmsTrade.targets(Game, b), ArmsTrade.class_counts(ArmsTrade.armory(b))).is_empty(), "first recipient reaches reserve")
	check(ArmsTrade._short(ArmsTrade.targets(Game, c), ArmsTrade.class_counts(ArmsTrade.armory(c))).is_empty(), "second recipient reaches reserve")
	var arrows1 := 0
	for t in Game.world["towns"].values(): arrows1 += ArmsTrade.arrow_stock(t)
	check(arrows1 == arrows0, "all arrow material quantities conserved")
	for tid in arrow_ledgers:
		var e: Dictionary = Game.world["towns"][tid]["econ"]
		for kind in ["made", "used", "spoil"]:
			for k in DB.arrows:
				check(int(e["led"][kind].get(k, 0)) == arrow_ledgers[tid][kind + String(k)], "each town's excluded reserve transfer leaves commodity ledger unchanged")
	check(int(a["econ"].get("supply_ledger", {}).get("out", {}).get(arrow_kind, 0)) == arrows0 - ArmsTrade.arrow_stock(a), "physical arrow transfer book records actual type and quantity")
	check(ArmsTrade.arrow_stock(a) >= ArmsTrade.arrow_target(Game, a), "arrow donor stays above reserve")
	check(ArmsTrade.redistribute(Game, 10) == 0, "checkpoint cannot execute twice")
	var stock0 := ArmsTrade.armory(a).size()
	(a["shop"] as Array).clear(); a["econ"]["treasury"] = 0.0
	ArmsTrade.econ_daily(Game, a, a["econ"], 12, false)
	check(ArmsTrade.armory(a).size() == stock0, "unmatched excess retained ahead of next distribution")
	var report := EconomyAudit.town_report(Game, a)
	check(not report["retained_surplus"].is_empty(), "audit reports retained real surplus separately")
	Game.day = 10
	Game.save_game(); check(Game.load_game(), "supply campaign save loads")
	check(ArmsTrade.redistribute(Game, 10) == 0, "loaded checkpoint cannot repeat")

func substitutes(ts: Array) -> void:
	var t: Dictionary = ts[0]
	var e: Dictionary = t["econ"]
	var target := ArmsTrade.role_counts(ArmsTrade.targets(Game, t))
	var preferred := []
	for c in ArmsTrade.targets(Game, t): preferred.append(String(c))
	var substitute := ""
	for tid in DB.weapons:
		var c := ArmsTrade.cls(String(tid))
		if ArmsTrade.cls_role(c) == "main_hand" and not preferred.has(c): substitute = String(tid); break
	check(substitute != "", "foreign substitute fixture exists")
	if substitute != "":
		ArmsTrade.armory(t).clear(); (t["shop"] as Array).clear()
		e["treasury"] = 10000000.0
		for i in int(target.get("main_hand", 0)) + TownDefence.garrison(Game, String(t["id"])).size() + 10:
			(t["shop"] as Array).append(Item.make(substitute, "copper", 2))
		var cash := coins()
		for i in 3: ArmsTrade.econ_daily(Game, t, e, int(Game.day), false)
		var held := ArmsTrade.role_counts(ArmsTrade.class_counts(ArmsTrade.armory(t)))
		check(int(held.get("main_hand", 0)) == int(target.get("main_hand", 0)), "market substitutes fill but never exceed role reserve")
		check(not (t["shop"] as Array).is_empty() and absf(coins() - cash) < 0.001, "excess substitute stays market-owned and coins balance")
	# Give one living garrison member an actual bow; count only actual archers.
	var g := TownDefence.garrison(Game, String(t["id"]))
	var archer: Unit = g[0]
	archer.equip["ranged"] = Item.make(String(DB.bows.keys()[0]), "wood", 2)
	archer.quiver = {}
	var cultural := BowsEcon.culture_arrows(t)
	var foreign := ""
	for k in DB.arrows:
		if not cultural.has(k): foreign = String(k); break
	check(foreign != "", "foreign arrow fixture exists")
	if foreign == "": return
	for k in DB.arrows: e["stock"][k] = 0; e["carry"]["bows_use_" + String(k)] = 0.0
	e["armory"] = {foreign: ArmsTrade.arrow_target(Game, t)}
	Militia.band_of(Game, String(t["id"]))["drill_today"] = false
	var arrows := ArmsTrade.arrow_stock(t)
	BowsEcon._armory(Game, t, e)
	check(archer.arrows() == DB.QUIVER_MAX, "foreign arrows actually refill a cultural garrison quiver")
	check(ArmsTrade.arrow_stock(t) + archer.arrows() <= arrows, "refill consumes actual stored ammunition")
	for u in g:
		if u.equip.has("ranged"): u.quiver = {foreign: DB.QUIVER_MAX}
	e["armory"] = {}; e["stock"][foreign] = 100000; e["treasury"] = 10000000.0
	var before := coins(); var stock := int(e["stock"][foreign]); var required := ArmsTrade.arrow_target(Game, t)
	BowsEcon._armory(Game, t, e)
	check(ArmsTrade.arrow_stock(t) == required, "single valid market arrow type fills complete aggregate reserve")
	check(stock - int(e["stock"][foreign]) == required and absf(coins() - before) < 0.001, "arrow purchase transfers actual goods and money")
	# Current ownership controls recipients at the scheduled checkpoint.
	var dest: Dictionary = ts[1]
	ArmsTrade.armory(dest).clear()
	var old_faction := String(dest["faction"]); dest["faction"] = ts[3]["faction"]
	ArmsTrade.redistribute(Game, 20)
	check(ArmsTrade.armory(dest).is_empty(), "changed faction cannot receive its former faction's surplus")
	dest["faction"] = old_faction

func migration(seed_v: int) -> void:
	Game.new_game(seed_v)
	var ts := towns(); check(ts.size() == 4, "generated migration towns exist")
	if ts.size() != 4: return
	var a: Dictionary = ts[0]; var b: Dictionary = ts[1]
	var staged := Item.make("arming_sword", "copper", 2)
	Game.world["arms"] = {"v": 1, "c": {"old": {"state": "active", "stown": a["id"], "staged": [staged], "escort_id": "special", "paid": 250.0}}, "offers": {}, "hist": ["Historical agreement"], "stats": {"delivered": 4}}
	a["contracts"] = [{"id": "special", "kind": "escort", "arms_cid": "old"}, {"id": "ordinary", "kind": "escort"}]
	Game.contract = {"id": "special", "kind": "escort", "arms_cid": "old", "state": "active"}
	var rng := RandomNumberGenerator.new(); rng.seed = seed_v
	var cargo := {"items": [Item.make("nasal_helm", "copper", 2)], "goods": {}}
	var extra := {"origin": a["id"], "home": a["id"], "dest": b["id"], "cargo": cargo, "gold": 777.0, "escort": "special", "state": "waiting", "away": 0.0, "leg": "out"}
	Game.world["work"] = [["arms_day", 1], ["arms_week", 1], ["arms_spawn", "old"]]
	CampaignWorld.muster_start(Game, ["arms_spawn", "old"], a["faction"], a["pos"], 12, "caravan", extra, rng, true, {"then": "arms", "cid": "old", "items": 1})
	var jobs: Array = Game.world["work"]
	var pending: Array = []
	for j in jobs:
		if j[-1] is Dictionary: pending = j; break
	check(not pending.is_empty(), "real partial muster created")
	if pending.is_empty(): return
	if seed_v % 2 == 0:
		# Caravan guards enlist in Caravans.sail, not Army's draft stage.
		# Exercise a later partial make with nine of twelve rolled guards.
		for step in 2:
			jobs.erase(pending); CampaignWorld.muster_step(Game, pending, rng)
			for j in jobs:
				if j[-1] is Dictionary: pending = j; break
	# A second already-travelling convoy keeps its physical holdings and route.
	var wb := {"id": "legacy_road", "kind": "caravan", "faction": a["faction"], "origin": a["id"], "home": a["id"], "dest": b["id"], "units": [], "cargo": {"items": [Item.make("arming_sword", "copper", 2)], "goods": {}}, "gold": 888.0, "pos": a["pos"], "anchor": a["pos"], "path": [b["pos"]], "state": "waiting", "escort": "special", "arms_contract": "old", "leg": "out"}
	Game.world["warbands"]["legacy_road"] = wb
	var items0 := item_ids(); var cash0 := coins(); var persons0 := people_ids()
	var diplo0: Dictionary = Game.world["diplo"].duplicate(true)
	ArmsTrade.retire_contracts(Game)
	check(item_ids() == items0 and absf(coins() - cash0) < 0.001 and people_ids() == persons0, "migration preserves goods, funded purse and all named people")
	check(Game.world["diplo"] == diplo0 and Game.contract.is_empty(), "special company job cancels without pay or standing penalty")
	check(a["contracts"].size() == 1 and a["contracts"][0]["id"] == "ordinary", "ordinary escort remains on board")
	check(ArmsTrade.armory(a).has(staged) and Game.world["arms"]["c"]["old"]["staged"].is_empty(), "staged goods returned once")
	check(Game.world["arms"]["hist"] == ["Historical agreement"] and float(Game.world["arms"]["c"]["old"]["paid"]) == 250.0, "past history and payments retained")
	check(wb["cargo"]["items"].size() == 1 and not wb.has("arms_contract") and wb["escort"] == "" and wb["state"] == "travel", "on-road convoy becomes ordinary trade without cargo loss")
	check(not jobs.any(func(j): return String(j[0]) in ["arms_day", "arms_week", "arms_spawn"]), "obsolete metadata jobs removed and muster converted")
	var m: Dictionary = CampaignWorld.mustering(Game.world)[0]
	check(m["then"] == "caravan" and float(m.get("wb", m.get("extra", {}))["gold"]) == 777.0 and m.has("rs"), "muster keeps real purse, people and random state")
	ArmsTrade.retire_contracts(Game)
	check(item_ids() == items0 and absf(coins() - cash0) < 0.001, "repeat migration is idempotent")
	Game.save_game(); check(Game.load_game(), "legacy conversion survives save/load")
	check(item_ids() == items0 and absf(coins() - cash0) < 0.001 and people_ids() == persons0, "loaded converted muster preserves all holdings")
	Game.world["work"] = []; ArmsTrade.queue_day(Game.world, 10)
	check(Game.world["work"].any(func(j): return String(j[0]) == "arms_supply"), "existing work queue schedules internal supply")
	check(not Game.world["work"].any(func(j): return String(j[0]) in ["arms_day", "arms_week", "arms_spawn"]), "special arms contracts cannot regenerate")

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_military_supply_%d.json" % OS.get_process_id()
	WorldGen.gen_size = "normal"
	for seed_v in [713, 2026, 8801]:
		Game.new_game(seed_v)
		var ts := towns(); check(ts.size() == 4, "generated supply towns exist")
		if ts.size() == 4:
			policy_and_money(ts); distribution(ts)
			var loaded_towns := towns()
			if loaded_towns.size() == 4: substitutes(loaded_towns)
	for seed_v in [713, 2026]: migration(seed_v)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	print("MILITARY SUPPLY checks=", checks, " failures=", fails)
	return fails
