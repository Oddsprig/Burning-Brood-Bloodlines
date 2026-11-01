extends RefCounted
## v0.075 daily whole-world money-and-stock audit (campaign/world_audit.gd).
##   godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_world_audit_v075.gd --watchdog=180
## DevTools world, a chosen house with a raised army and an open supply order, then DAYS whole days. Every day the
## census before and after must balance against the named mints, harvests and sinks (coin, every counted good,
## armouries and caravan cargo). Failing identities print the holders that moved and the unrounded residual; the
## job trace (run_day_traced) prints any single work job whose coin or arms change was not booked.
## Self-checks first: an unbooked change planted in a census is reported (a harness that cannot fail proves nothing).
## r7: the whole-run identity is a strict check from a census taken after the holder negatives (which must leave the
## world and its books as found); the treasure negative plants a real-category piece in the house's own room.

const DAYS := 8

var checks := 0
var fails := 0

var trace_ms := 0   # time spent in the job trace (it falls back to whole days past TRACE_MS)
const TRACE_MS := 60000

## One day as DevTools.run_days runs it (the clock, then every queued job), with the coin and arms totals taken
## after the clock and after each job: a job whose own change is not booked is printed by name. Same order and RNG
## as run_days (work_slice keeps the world RNG state between calls); only the slice size differs.
func run_day_traced() -> void:
	if trace_ms > TRACE_MS:
		WorldAudit.site = "a whole day (untraced)"
		DevTools.run_days(Game, 1)
		WorldAudit.site = ""
		return
	var t0 := Time.get_ticks_msec()
	var odd := {}   # label -> [jobs, coin residual, arms residual]
	var q0 := WorldAudit.quick(Game)
	WorldAudit.site = "the day's clock"   # r6: every Item.make is logged with the job that made it
	Game.advance_time(1.0, false, 0, 0)
	var q1 := WorldAudit.quick(Game)
	_trace_note(odd, "the day's clock", q0, q1)
	var work: Array = Game.world.get("work", [])
	while not (Game.world.get("work", []) as Array).is_empty():
		work = Game.world["work"]
		var job = work[0]
		var label := str(job[0]) if job is Array and not (job as Array).is_empty() else "?"
		if job is Array and (job as Array).size() > 2 and job[-1] is Dictionary and (job[-1] as Dictionary).has("stage"):
			label += " muster(%s, %s)" % [str(job[-1].get("kind", "?")), str(job[-1].get("stage", "?"))]
		WorldAudit.site = label
		var n := CampaignWorld.work_slice(Game, 1)
		if n > 1: label += " +%d more" % (n - 1)
		var q2 := WorldAudit.quick(Game)
		_trace_note(odd, label, q1, q2)
		q1 = q2
	for label in odd:
		var r: Array = odd[label]
		print("    job trace: %s (x%d): coin residual %s, arms residual %+d" % [label, int(r[0]), String.num(r[1], 6), int(r[2])])
	WorldAudit.site = ""
	trace_ms += Time.get_ticks_msec() - t0
	if trace_ms > TRACE_MS: print("    job trace: over %d s, later days run whole" % (TRACE_MS / 1000))

func _trace_note(odd: Dictionary, label: String, a: Dictionary, b: Dictionary) -> void:
	var coin := (float(b["coin"]) - float(a["coin"])) - (float(b["booked"]) - float(a["booked"]))
	var arms := (int(b["arms"]) - int(a["arms"])) - (int(b["arms_booked"]) - int(a["arms_booked"]))
	if absf(coin) <= maxf(0.01, 1e-9 * absf(float(b["coin"]))) and arms == 0: return
	if not odd.has(label): odd[label] = [0, 0.0, 0]
	odd[label][0] += 1
	odd[label][1] += coin
	odd[label][2] += arms

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL world_audit_v075: ", message)

func self_check(tid: String) -> void:
	var e: Dictionary = Game.world["towns"][tid]["econ"]
	var a := WorldAudit.census(Game)
	var same := WorldAudit.compare(a, WorldAudit.census(Game))
	check(same["ok"], "self-check: two censuses of one state balance")
	e["stock"]["grain"] = int(e["stock"].get("grain", 0)) + 7
	e["treasury"] = float(e["treasury"]) + 3.5
	var b := WorldAudit.census(Game)
	var planted := WorldAudit.compare(a, b)
	check(not planted["ok"] and int(planted["goods"]["grain"]["residual"]) == 7, "self-check: 7 unbooked grain are a leak of +7 (%d)" % int(planted["goods"]["grain"]["residual"]))
	check(not planted["coin"]["ok"] and absf(float(planted["coin"]["residual"]) - 3.5) < 1e-9, "self-check: 3.5 unbooked coins are a leak (%s)" % String.num(planted["coin"]["residual"], 9))
	TownEcon.led(e, "made", "grain", 7)
	var booked := WorldAudit.compare(a, WorldAudit.census(Game))
	check(int(booked["goods"]["grain"]["residual"]) == 0, "self-check: the same grain booked as made balances")
	# put the state back exactly
	e["stock"]["grain"] = int(e["stock"]["grain"]) - 7
	e["led"]["made"]["grain"] = int(e["led"]["made"]["grain"]) - 7
	e["treasury"] = float(e["treasury"]) - 3.5
	check(WorldAudit.compare(a, WorldAudit.census(Game))["ok"], "self-check: the planted changes are undone")
	# A piece moved from the armoury to the stalls stays in the town's holdings; one that leaves unbooked is a leak.
	var town: Dictionary = Game.world["towns"][tid]
	var arm: Array = ArmsTrade.armory(town)
	if not arm.is_empty():
		var it: Item = arm.pop_back()
		if not town.has("shop"): town["shop"] = []
		town["shop"].append(it)
		check(WorldAudit.compare(a, WorldAudit.census(Game))["arms"]["ok"], "self-check: armoury to stalls is not a leak")
		town["shop"].erase(it)
		var gone := WorldAudit.compare(a, WorldAudit.census(Game))
		check(not gone["arms"]["ok"] and int(gone["arms"]["residual"]) == -1, "self-check: a piece leaving unbooked is a leak of -1 (%d)" % int(gone["arms"]["residual"]))
		# Caravan cargo is a holding too; wagons destroyed with it balance once TownEcon.goods_lost books it.
		var wid := "audit_selfcheck_wagons"
		Game.world["warbands"][wid] = {"kind": "caravan", "gold": 0.0, "cargo": {"items": [it], "goods": {}}}
		check(WorldAudit.compare(a, WorldAudit.census(Game))["arms"]["ok"], "self-check: armoury to caravan cargo is not a leak")
		Game.world["warbands"].erase(wid)
		check(not WorldAudit.compare(a, WorldAudit.census(Game))["arms"]["ok"], "self-check: wagons gone with the piece unbooked are a leak")
		TownEcon.goods_lost["arms"] = int(TownEcon.goods_lost.get("arms", 0)) + 1
		check(WorldAudit.compare(a, WorldAudit.census(Game))["arms"]["ok"], "self-check: the piece booked lost with its wagons balances")
		TownEcon.goods_lost["arms"] = int(TownEcon.goods_lost["arms"]) - 1
		arm.append(it)
	check(not WorldAudit.scan(Game).has("/factions/%s/treasury" % str(Game.world.get("factions", {}).keys()[0]) if not Game.world.get("factions", {}).is_empty() else ""), "self-check: realm treasuries are counted holders (no scan note)")

## r5 (QC 122fabf8): an unbooked loss planted in each holder class is a leak of that class; a move between holders,
## a booked loss and a new Item.make are not. Every plant is undone and the undone state balances again.
## r6: run after the house's muster (Mobilization.muster: real company men, and meal lots the company bought), and
## each holder's loss is measured from a census taken with the piece in that holder (where it was last held).
func holder_checks(house_tid: String) -> void:
	var w: Dictionary = Game.world
	var base := WorldAudit.census(Game)
	check(WorldAudit.compare(base, WorldAudit.census(Game))["ok"], "holders self-check: two censuses balance (items, rations, treasure too)")
	# --- band stores: 100 grain gone from a band without a booking (QC's example), then booked
	var band := {}
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		if int(wb.get("stores", {}).get("grain", 0)) >= 100: band = wb; break
	check(not band.is_empty(), "holders self-check: a band carries 100 grain in its stores")
	if not band.is_empty():
		band["stores"]["grain"] = int(band["stores"]["grain"]) - 100
		var c := WorldAudit.compare(base, WorldAudit.census(Game))
		check(not c["ok"] and int(c["rations"]["food"]["residual"]) == -100, "holders self-check: 100 grain gone from a band's stores unbooked is a leak of -100 (%d)" % int(c["rations"]["food"]["residual"]))
		WorldAudit.ration("grain", "-self-check", -100)
		check(WorldAudit.compare(base, WorldAudit.census(Game))["rations"]["food"]["ok"], "holders self-check: the same grain booked out balances")
		band["stores"]["grain"] = int(band["stores"]["grain"]) + 100
		WorldAudit.ration("grain", "+self-check", 100)
		var beer := int(band["stores"].get("beer", 0))
		if beer > 0:
			band["stores"]["beer"] = beer - 1
			check(not WorldAudit.compare(base, WorldAudit.census(Game))["rations"]["beer"]["ok"], "holders self-check: a mug gone from a band's stores unbooked is a leak")
			band["stores"]["beer"] = beer
	# --- the company's provisions (the muster bought them in the town: Mobilization._food_order, Food.add_stock)
	var meals: Array = Game.provisions.get("meal", []) if Game.provisions is Dictionary else []
	check(not meals.is_empty() and int(meals[0][0]) >= 3, "holders self-check: the muster bought the company meal lots")
	if not meals.is_empty() and int(meals[0][0]) >= 3:
		meals[0][0] = int(meals[0][0]) - 3
		var c2 := WorldAudit.compare(base, WorldAudit.census(Game))
		check(not c2["ok"] and int(c2["rations"]["food"]["residual"]) == -3, "holders self-check: 3 meals gone from the company's provisions unbooked are a leak of -3 (%d)" % int(c2["rations"]["food"]["residual"]))
		meals[0][0] = int(meals[0][0]) + 3
	check(WorldAudit.compare(base, WorldAudit.census(Game))["ok"], "holders self-check: stores and provisions put back balance")
	# --- items: one soldier's piece through every holder class
	var man: Unit = null
	var man_band := {}
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		if str(wb.get("kind", "")) == "caravan": continue
		for u in wb.get("units", []):
			if u is Unit and not u.dead and u.equip.has("main_hand"): man = u; man_band = wb; break
		if man != null: break
	check(man != null, "holders self-check: a band soldier carries a weapon")
	if man == null: return
	var it: Item = man.equip["main_hand"]
	var kind := str(man_band.get("kind", "band")) + " men's kit"
	man.equip.erase("main_hand")
	var gone := WorldAudit.compare(base, WorldAudit.census(Game))
	check(not gone["ok"] and int(gone["items"]["gone_unbooked"].get(kind, 0)) == 1, "holders self-check: a soldier's weapon gone unbooked is a leak of his band's kit (%s)" % JSON.stringify(gone["items"]["gone_unbooked"]))
	# the same piece moved into each other holder is a transfer; removed from it unbooked, a leak of that holder
	var places: Array = []   # [label, put Callable, take Callable]
	places.append(["company stash", func(): Game.stash.append(it), func(): Game.stash.erase(it)])
	var cu: Unit = null
	for u in Game.company:
		if u is Unit and not u.dead and not u.equip.has("main_hand"): cu = u; break
	if cu == null:
		for u in Game.company:
			if u is Unit and not u.dead: cu = u; break
	if cu != null:
		var slot := "audit_selfcheck"
		places.append(["company kit", func(): cu.equip[slot] = it, func(): cu.equip.erase(slot)])
	var lair := {}
	for lid in w.get("lairs", {}):
		if w["lairs"][lid].has("stock"): lair = w["lairs"][lid]; break
	if not lair.is_empty():
		places.append(["lair stock", func(): (lair["stock"] as Array).append(it), func(): (lair["stock"] as Array).erase(it)])
	var town: Dictionary = {}
	for tid in w.get("towns", {}):
		if TownEcon.has_econ(w["towns"][tid]): town = w["towns"][tid]; break
	if not town.is_empty():
		places.append(["town armoury", func(): ArmsTrade.armory(town).append(it), func(): ArmsTrade.armory(town).erase(it)])
	# a prisoner (planted record, his Unit carrying the piece)
	var pu := Unit.new()
	pu.uid = -991
	var prec := {"uid": -991, "unit": pu, "audit_selfcheck": true}
	Prisoners.held(Game).append(prec)   # (no kit yet: holds nothing)
	places.append(["prisoners' kit", func(): pu.equip["main_hand"] = it, func(): pu.equip.erase("main_hand")])
	places.append(["caravan cargo", func(): w["warbands"]["audit_selfcheck_cargo"] = {"kind": "caravan", "gold": 0.0, "cargo": {"items": [it], "goods": {}}},
		func(): (w["warbands"]["audit_selfcheck_cargo"]["cargo"]["items"] as Array).clear()])
	for p in places:
		(p[1] as Callable).call()
		var inp := WorldAudit.census(Game)   # r6: the piece held in this holder
		var where := str(((inp["items"]["held"] as Dictionary).get(it.uid, ["nowhere"]) as Array)[0])
		check(where == str(p[0]), "holders self-check: the census finds the piece in %s (%s)" % [p[0], where])
		var moved := WorldAudit.compare(base, inp)
		check(moved["items"]["ok"], "holders self-check: the piece moved into %s is a transfer (%s)" % [p[0], JSON.stringify(moved["items"]["samples"])])
		(p[2] as Callable).call()
		var lost := WorldAudit.compare(inp, WorldAudit.census(Game))
		check(not lost["ok"] and int(lost["items"]["gone_unbooked"].get(p[0], 0)) == 1, "holders self-check: the piece gone from %s unbooked is a leak of that holder (%s)" % [p[0], JSON.stringify(lost["items"]["gone_unbooked"])])
	Prisoners.held(Game).erase(prec)
	w["warbands"].erase("audit_selfcheck_cargo")
	man.equip["main_hand"] = it
	check(WorldAudit.compare(base, WorldAudit.census(Game))["ok"], "holders self-check: the piece back on its soldier balances")
	# a booked loss balances; booked but still held, a copy with an old uid and a new Item.make put nowhere are leaks
	var b2 := WorldAudit.census(Game)
	man.equip.erase("main_hand")
	var gone_at := WorldAudit.items_gone.size()
	WorldAudit.lose_item(it, "-self-check")
	check(WorldAudit.compare(b2, WorldAudit.census(Game))["items"]["ok"], "holders self-check: a piece booked gone where it was dropped balances")
	man.equip["main_hand"] = it
	var held_again := WorldAudit.compare(b2, WorldAudit.census(Game))
	check(not held_again["items"]["ok"] and int(held_again["items"]["booked_but_held"]) == 1, "holders self-check: a piece booked gone but still held is a leak")
	# r7: the plant is undone in the books too. The soldier's real weapon is back on him, so the self-check's loss
	# booking of it is withdrawn (r6 left #it booked gone for the rest of the run: the whole-run "booked but held").
	check(WorldAudit.items_gone.size() == gone_at + 1 and int(WorldAudit.items_gone[gone_at][0]) == int(it.uid), "holders self-check: the weapon's self-check booking is the one entry to withdraw")
	WorldAudit.items_gone.remove_at(gone_at)
	var gb := int(WorldAudit.gone_by.get("-self-check", 0)) - 1
	if gb <= 0: WorldAudit.gone_by.erase("-self-check")
	else: WorldAudit.gone_by["-self-check"] = gb
	var unbooked_back := WorldAudit.compare(b2, WorldAudit.census(Game))
	check(unbooked_back["items"]["ok"] and int(unbooked_back["items"]["booked_but_held"]) == 0, "holders self-check: the weapon back on its soldier with the booking withdrawn balances (%s)" % JSON.stringify(unbooked_back["items"]["samples"]))
	var b3 := WorldAudit.census(Game)
	var copy := Item.from_dict(it.to_dict())
	Game.stash.append(copy)
	var dup := WorldAudit.compare(b3, WorldAudit.census(Game))
	check(not dup["items"]["ok"] and int(dup["items"]["dupes"]) == 1, "holders self-check: a copy of a held piece (same uid) is a leak")
	Game.stash.erase(copy)
	var fresh := Item.make("tunic", "linen", 0)
	var made_gone := WorldAudit.compare(b3, WorldAudit.census(Game))
	check(not made_gone["items"]["ok"] and int(made_gone["items"]["gone_unbooked"].get("made and gone in the window", 0)) == 1, "holders self-check: an Item made and dropped unbooked is a leak")
	Game.stash.append(fresh)
	check(WorldAudit.compare(b3, WorldAudit.census(Game))["items"]["ok"], "holders self-check: a new Item.make kept in a holder balances")
	Game.stash.erase(fresh)
	WorldAudit.lose_item(fresh, "-self-check")
	# r6: a piece priced and never made (booked unmade) balances apart from the losses; the same uid held is a leak
	var b5 := WorldAudit.census(Game)
	var priced := Item.make("tunic", "linen", 0)
	WorldAudit.unmade(priced, "-self-check priced only")
	var pc := WorldAudit.compare(b5, WorldAudit.census(Game))
	check(pc["items"]["ok"] and int(pc["items"]["unmade"]) == 1 and int(pc["items"]["booked"]) == 0, "holders self-check: a piece booked unmade balances apart from the losses (%s)" % JSON.stringify(pc["items"]["samples"]))
	Game.stash.append(priced)
	var ph := WorldAudit.compare(b5, WorldAudit.census(Game))
	check(not ph["items"]["ok"] and int(ph["items"]["booked_but_held"]) == 1, "holders self-check: a piece booked unmade but held is a leak")
	Game.stash.erase(priced)
	# a rolled template dropped is unmade; a piece that was not rolled, dropped the same way, stays a leak
	var b6 := WorldAudit.census(Game)
	var tmpl := Item.make("tunic", "linen", 0)
	WorldAudit.rolled(tmpl)
	WorldAudit.drop_rolled(tmpl, "-self-check rolled")
	var real := Item.make("tunic", "linen", 0)
	WorldAudit.drop_rolled(real, "-self-check not rolled")
	var rc := WorldAudit.compare(b6, WorldAudit.census(Game))
	check(not rc["items"]["ok"] and int(rc["items"]["unmade"]) == 1 and int(rc["items"]["gone_unbooked"].get("made and gone in the window", 0)) == 1, "holders self-check: a dropped rolled template is unmade, a dropped real piece a leak (%s)" % JSON.stringify(rc["items"]["gone_unbooked"]))
	WorldAudit.lose_item(real, "-self-check")
	# A rolled piece that reached an owning holder is real. Its earlier template origin cannot pardon loss.
	var issued := Item.make("tunic", "linen", 0)
	WorldAudit.rolled(issued)
	Game.stash.append(issued)
	var issued_before := WorldAudit.census(Game)
	Game.stash.erase(issued)
	WorldAudit.drop_rolled(issued, "-self-check already owned")
	var issued_loss := WorldAudit.compare(issued_before, WorldAudit.census(Game))
	check(not issued_loss["items"]["ok"] and int(issued_loss["items"]["gone_unbooked"].get("company stash", 0)) == 1, "holders self-check: a previously owned rolled piece cannot be excused as never made")
	WorldAudit.lose_item(issued, "-self-check")
	# --- treasure (r7: executed, not skipped). The DevTools world starts with no treasure rooms, so the plant does not
	# wait for one: a test-local piece of a real CourtEvents.TREASURE category (row shape as CourtEvents.hold
	# "treasure" writes it) goes into the chosen house's own treasure room, booked as that commission books it. One
	# piece then leaves unbooked (a leak of -1), and booked out it balances. The room, the piece and the treasure book
	# are put back exactly; no coin, purse or prestige is touched (the commission's payment is not part of this plant).
	var b4 := WorldAudit.census(Game)
	var tb0: Dictionary = WorldAudit.treasure_book.duplicate()
	var huid := str(w.get("player_house", {}).get("household_uid", ""))
	var hl: Dictionary = CourtEvents._loc(Game, huid) if huid != "" else {}
	var fam: Dictionary = hl.get("family", {}) if not hl.is_empty() else Feudal.tax_recipient(Game, house_tid)
	check(not fam.is_empty(), "holders self-check: the chosen house has a household to hold a treasure room (%s)" % huid)
	if not fam.is_empty():
		var had_room := fam.has("hoard")
		if not had_room: fam["hoard"] = []
		var cat := "gold"
		var piece := {"category": cat, "gem_id": "", "quantity": 2, "unit_cost": int(CourtEvents.TREASURE[cat]),
			"id": "%s:treasure:audit_selfcheck" % huid}
		(fam["hoard"] as Array).append(piece)
		WorldAudit.treasure("+self-check commissioned", 2)
		var tin := WorldAudit.census(Game)
		var tc := WorldAudit.compare(b4, tin)
		check(tc["ok"] and int(tc["treasure"].get("treasure room", 0)) == 2, "holders self-check: 2 pieces booked into the house's treasure room are counted and balance (%s, %s)" % [JSON.stringify(tc["treasure"]), JSON.stringify(tc["treasure_gate"])])
		piece["quantity"] = 1
		var tg := WorldAudit.compare(tin, WorldAudit.census(Game))
		check(not tg["ok"] and int(tg["treasure_gate"]["residual"]) == -1, "holders self-check: a treasure piece gone unbooked is a leak of -1 (%d)" % int(tg["treasure_gate"]["residual"]))
		WorldAudit.treasure("-self-check sold", -1)
		check(WorldAudit.compare(tin, WorldAudit.census(Game))["treasure_gate"]["ok"], "holders self-check: the same piece booked out balances")
		(fam["hoard"] as Array).erase(piece)
		if not had_room: fam.erase("hoard")
		WorldAudit.treasure_book = tb0
	check(WorldAudit.compare(b4, WorldAudit.census(Game))["ok"], "holders self-check: every plant undone balances")
	var as_found := WorldAudit.compare(base, WorldAudit.census(Game))
	check(as_found["ok"], "holders self-check: all holder plants together leave the world and its books as found (%s)" % JSON.stringify(as_found["items"]["samples"]))

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "the DevTools start world loads")
		return fails
	TownEcon.goods_lost.clear()
	var tid := DevTools.choose_house(Game)
	check(tid != "", "a house can be chosen")
	if tid == "": return fails
	self_check(tid)
	var c0 := WorldAudit.census(Game)
	check(absf(WorldAudit.total(c0["coin"]) - BargeViews.holdings(Game)) <= 0.01, "the census counts the same coin as Barge holdings (%s vs %s)" % [String.num(WorldAudit.total(c0["coin"]), 6), String.num(BargeViews.holdings(Game), 6)])
	var uncounted := WorldAudit.scan(Game)
	for path in uncounted:
		print("audit note: money-looking field not in the census: %s (%d fields, %s total)" % [path, int(uncounted[path][0]), String.num(uncounted[path][1], 3)])
	# Activity the audit must follow: an army on the house's coin and a supply order on its treasury.
	var a := WorldAudit.census(Game)
	check(DevTools.raise_army(Game, tid, 10) > 0, "the house raises an army")
	if SupplyOrders.can_manage(Game, tid):
		var town: Dictionary = Game.world["towns"][tid]
		var cap := floorf(minf(float(town["econ"]["treasury"]) * 0.25, 4000.0))
		if cap >= 1.0: SupplyOrders.place(Game, tid, "grain", 10, 1000.0, cap, "best")
	var b := WorldAudit.census(Game)
	var setup := WorldAudit.compare(a, b)
	for line in WorldAudit.lines(setup, "muster+order"): print(line)
	check(setup["ok"], "raising the army and placing the order balance")
	holder_checks(tid)   # r6: after the muster (real company men and meal lots); every plant is undone
	# r7: the whole-run window starts here, after the holder negatives (r6 took it at c0, before them, so the
	# self-check's own booking of the soldier's weapon showed as a whole-run leak). The setup before it is not
	# left unchecked: c0 -> the muster+order is its own strict gate above, and the holder negatives must leave the
	# world and its books exactly as found (the last holders check). From w0 the 8 daily gates and the whole gate run.
	var w0 := WorldAudit.census(Game)
	var leaks := {}   # identity -> [days failed, total residual]
	for d in DAYS:
		a = WorldAudit.census(Game)
		run_day_traced()
		b = WorldAudit.census(Game)
		var c := WorldAudit.compare(a, b)
		for line in WorldAudit.lines(c, "day %d" % int(floor(float(b["day"])))): print(line)
		if not c["coin"]["ok"]:
			if not leaks.has("coin"): leaks["coin"] = [0, 0.0]
			leaks["coin"][0] += 1
			leaks["coin"][1] += float(c["coin"]["residual"])
		for g in WorldAudit.GOODS:
			if c["goods"][g]["ok"]: continue
			if not leaks.has(g): leaks[g] = [0, 0.0]
			leaks[g][0] += 1
			leaks[g][1] += float(c["goods"][g]["residual"])
		if not c["arms"]["ok"]:
			if not leaks.has("arms"): leaks["arms"] = [0, 0.0]
			leaks["arms"][0] += 1
			leaks["arms"][1] += float(c["arms"]["residual"])
		# r5: every held Item by identity, band stores + company provisions, treasure
		var ic: Dictionary = c["items"]
		if not ic["ok"]:
			if not leaks.has("items"): leaks["items"] = [0, 0.0]
			leaks["items"][0] += 1
			for k in ic["gone_unbooked"]: leaks["items"][1] -= float(ic["gone_unbooked"][k])
			for k in ic["appeared"]: leaks["items"][1] += float(ic["appeared"][k])
		for row in c["rations"]:
			if c["rations"][row]["ok"]: continue
			var key := "rations " + str(row)
			if not leaks.has(key): leaks[key] = [0, 0.0]
			leaks[key][0] += 1
			leaks[key][1] += float(c["rations"][row]["residual"])
		if not c["treasure_gate"]["ok"]:
			if not leaks.has("treasure"): leaks["treasure"] = [0, 0.0]
			leaks["treasure"][0] += 1
			leaks["treasure"][1] += float(c["treasure_gate"]["residual"])
		if d == 0:
			var ib: Dictionary = c["items"]
			print("day 0 items: %d made, %d booked gone %s, by holder %s" % [int(ib["made"]), int(ib["booked"]), JSON.stringify(ib["booked_by"]), JSON.stringify(ib["by_holder"])])
	for k in leaks:
		check(false, "%s leaks on %d of %d days, residual %s in all" % [k, int(leaks[k][0]), DAYS, String.num(leaks[k][1], 6)])
	var whole := WorldAudit.compare(w0, WorldAudit.census(Game))
	print("whole run, day %.2f to %.2f:" % [float(w0["day"]), Game.day])
	for line in WorldAudit.lines(whole, "  all days"): print(line)
	# r7: strict. Every identity over the whole window (coin, goods, arms, items by uid, rations, treasure) must balance:
	# drift that no single day shows (a booking in one day for a piece that is still held later) fails here.
	check(whole["ok"], "the whole %d-day window balances in every identity (coin %s, arms %s, items %s, treasure %s, samples %s)" % [DAYS,
		str(whole["coin"]["ok"]), str(whole["arms"]["ok"]), str(whole["items"]["ok"]), str(whole["treasure_gate"]["ok"]), JSON.stringify(whole["items"]["samples"])])
	var tr: Dictionary = whole["treasure"]
	print("treasure pieces moved: %s" % JSON.stringify(tr))
	print("world_audit_v075: %d checks, %d fails, %.1f s" % [checks, fails, float(Time.get_ticks_msec() - started) / 1000.0])
	return fails
