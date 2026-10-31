extends RefCounted
## v0.075 daily whole-world money-and-stock audit (campaign/world_audit.gd).
##   godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_world_audit_v075.gd --watchdog=180
## DevTools world, a chosen house with a raised army and an open supply order, then DAYS whole days. Every day the
## census before and after must balance against the named mints, harvests and sinks (coin, every counted good,
## armouries and caravan cargo). Failing identities print the holders that moved and the unrounded residual; the
## job trace (run_day_traced) prints any single work job whose coin or arms change was not booked.
## Self-checks first: an unbooked change planted in a census is reported (a harness that cannot fail proves nothing).

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
		DevTools.run_days(Game, 1)
		return
	var t0 := Time.get_ticks_msec()
	var odd := {}   # label -> [jobs, coin residual, arms residual]
	var q0 := WorldAudit.quick(Game)
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
		var n := CampaignWorld.work_slice(Game, 1)
		if n > 1: label += " +%d more" % (n - 1)
		var q2 := WorldAudit.quick(Game)
		_trace_note(odd, label, q1, q2)
		q1 = q2
	for label in odd:
		var r: Array = odd[label]
		print("    job trace: %s (x%d): coin residual %s, arms residual %+d" % [label, int(r[0]), String.num(r[1], 6), int(r[2])])
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
	for k in leaks:
		check(false, "%s leaks on %d of %d days, residual %s in all" % [k, int(leaks[k][0]), DAYS, String.num(leaks[k][1], 6)])
	var whole := WorldAudit.compare(c0, WorldAudit.census(Game))
	print("whole run, day %.2f to %.2f:" % [float(c0["day"]), Game.day])
	for line in WorldAudit.lines(whole, "  all days"): print(line)
	var tr: Dictionary = whole["treasure"]
	print("treasure pieces moved: %s" % JSON.stringify(tr))
	print("world_audit_v075: %d checks, %d fails, %.1f s" % [checks, fails, float(Time.get_ticks_msec() - started) / 1000.0])
	return fails
