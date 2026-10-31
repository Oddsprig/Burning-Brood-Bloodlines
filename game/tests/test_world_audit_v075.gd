extends RefCounted
## v0.075 daily whole-world money-and-stock audit (campaign/world_audit.gd).
##   godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_world_audit_v075.gd --watchdog=180
## DevTools world, a chosen house with a raised army and an open supply order, then DAYS whole days. Every day the
## census before and after must balance against the named mints, harvests and sinks (coin, every counted good,
## armouries). Failing identities print the holders that moved and the unrounded residual.
## Self-checks first: an unbooked change planted in a census is reported (a harness that cannot fail proves nothing).

const DAYS := 8

var checks := 0
var fails := 0

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
		DevTools.run_days(Game, 1)
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
