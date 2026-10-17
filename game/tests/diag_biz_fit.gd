extends RefCounted
## Diagnostic (v0.014): per town, the business rows against the people: adults, land hands needed, trade places,
## open places, idle adults, empty tills, duplicate trades. DIAG_DAYS (default 0) days of sim after world gen.

func run(_tree: SceneTree) -> int:
	Game.new_game(2026)
	var days := int(OS.get_environment("DIAG_DAYS")) if OS.get_environment("DIAG_DAYS") != "" else 0
	_report("world gen")
	if days > 0:
		CampaignWorld.presim_step(Game, days)
		_report("after %d days" % days)
	return 0

func _report(label: String) -> void:
	var w: Dictionary = Game.world
	print("== ", label)
	var ids: Array = w["towns"].keys()
	ids.sort()
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		var ad := 0; var need := 0.0; var idle := 0; var hands := 0; var jobs := 0
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false):
				continue
			ad += Families.adults(f); need += Families.need_hands(f); idle += int(f.get("idle", 0)); hands += int(f.get("hands", 0))
			jobs += Families.job_total(f)
		var rows := 0; var farms := 0; var cap := 0; var open := 0; var dry := 0; var dry_open := 0; var kept := 0
		var seen := {}; var dups := []
		for b in e["biz"]:
			if b.get("closed", false):
				continue
			rows += 1
			if b["type"] == "farm":
				farms += 1
			else:
				var k := String(b["type"]) + ("|" + String(b.get("ore", "")) if b["type"] == "mine" else "")
				if seen.has(k):
					dups.append(k)
				seen[k] = true
			cap += int(b["cap"])
			var o := maxi(0, int(b["cap"]) - int(b["workers"]))
			open += o
			if float(b["till"]) < float(b["wage"]) * 2.0:
				dry += 1
				dry_open += o
			kept += int(b.get("kw", 0))
		var fdry := 0; var tdry := 0; var topen := 0
		for b in e["biz"]:
			if b.get("closed", false):
				continue
			var o2 := maxi(0, int(b["cap"]) - int(b["workers"]))
			if b["type"] != "farm":
				topen += o2
			if float(b["till"]) < float(b["wage"]) * 2.0:
				if b["type"] == "farm": fdry += o2
				else: tdry += o2
		print("  %s size %d: adults %d, land needs %.0f (on land %d), jobs %d, idle %d | rows %d (farms %d), places %d, open %d (trades %d), dry open: farms %d trades %d, kept %d, dup trades %s, fit %s" % [
			String(t["name"]), int(t["size"]), ad, need, hands, jobs, idle, rows, farms, cap, open, topen, fdry, tdry, kept, str(dups), str(e.get("fit", {}))])
		if String(OS.get_environment("DIAG_ROWS")) == String(t["name"]):
			for b in e["biz"]:
				if b.get("closed", false) or b["type"] == "farm":
					continue
				print("    %-12s own %3d kw %d %2d/%2d wage %6.1f till %8.1f owed %7.1f %-6s %-10s p14 %7.1f p1 %7.1f ld %d" % [b["type"], int(b["owner"]), int(b.get("kw", 0)),
					int(b["workers"]), int(b["cap"]), float(b["wage"]), float(b["till"]), float(b.get("owed", 0)), String(b["state"]), String(b.get("health", "-")),
					float(b.get("p14", 0)), float(b.get("p1", 0)), int(b.get("ld", 0))])
