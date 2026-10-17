extends RefCounted
## Diagnostics for the herds (not in the suite: diag_ files): head against what the owners mean to keep, the week's
## offers, the grass and fodder, and the year's changes by kind and cause. tools/test.sh tests/diag_herds.gd

func run(_tree: SceneTree) -> int:
	Game.new_game(2026)
	var w: Dictionary = Game.world
	if OS.get_environment("HERDS_PROF") != "":
		CampaignWorld.presim_step(Game, 70)
		_prof(w)
		return 0
	for step in [7, 23, 30, 30, 30]:
		CampaignWorld.presim_step(Game, step)
		_report(w)
	return 0

## The parts of a herd week, timed over every town.
func _prof(w: Dictionary) -> void:
	var parts := {}
	var ids: Array = w["towns"].keys()
	ids.sort()
	var day := float(Game.day)
	var si := Calendar.season_index(day)
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		var e: Dictionary = t["econ"]
		var rng := RandomNumberGenerator.new()
		var P := Plots.of(t)
		var steps := {
			"life": func(): for hid in (e["hd"]["h"] as Dictionary).keys(): Herds._life(e, e["hd"]["h"][hid], si, day, rng),
			"orphans": func(): Herds._orphans(e, day),
			"feed": func(): Herds._feed_all(e, P, si, day, rng),
			"unsold": func(): Herds._unsold(e, si, day),
			"offers": func(): Herds._offers(e, si, day),
			"wants": func(): Herds._wants(Game, t, e, si, day),
			"drovers": func(): Herds._drovers(Game, t, e, day),
			"prices": func(): Herds._prices(e),
			"products": func(): Herds._products(e, si, day),
			"manure": func(): Herds._manure(e),
			"caps": func(): Herds._herder_caps(e),
			"assign": func(): Herds.assign_tiles(e, P)}
		for k in steps:
			var t0 := Time.get_ticks_usec()
			(steps[k] as Callable).call()
			parts[k] = int(parts.get(k, 0)) + Time.get_ticks_usec() - t0
	for k in parts:
		parts[k] = snappedf(float(parts[k]) / 1000.0 / float(ids.size()), 0.01)
	print("HERD WEEK parts, ms a town: %s" % str(parts))

func _report(w: Dictionary) -> void:
	var by := {}
	var ids: Array = w["towns"].keys()
	ids.sort()
	var pool := 0.0; var csum := 0.0; var fod := 0.0; var barn := 0
	for tid in ids:
		var e: Dictionary = w["towns"][tid]["econ"]
		if not e.has("hd"):
			continue
		barn += int(e["barn"].get("fodder", 0)) + int(e["stock"].get("fodder", 0))
		var offk: Dictionary = {}
		for o in e["hd"]["of"]:
			var h0: Dictionary = e["hd"]["h"].get(str(int(o[0])), {})
			if not h0.is_empty():
				var key := "%s:%s" % [h0["k"], o[3] if o.size() > 3 else ""]
				offk[key] = int(offk.get(key, 0)) + int(o[2])
		for k in offk:
			var kk := String(k).split(":")[0]
			if not by.has(kk):
				by[kk] = {"head": 0, "t": 0, "off": {}, "hun": 0, "fod": 0.0, "tiles": 0, "cs": 0.0}
			by[kk]["off"][k] = int(by[kk]["off"].get(k, 0)) + int(offk[k])
		for hid in e["hd"]["h"]:
			var h: Dictionary = e["hd"]["h"][hid]
			var k2 := String(h["k"])
			if not by.has(k2):
				by[k2] = {"head": 0, "t": 0, "off": {}, "hun": 0, "fod": 0.0, "tiles": 0, "cs": 0.0}
			by[k2]["head"] = int(by[k2]["head"]) + Herds.head(h)
			by[k2]["t"] = int(by[k2]["t"]) + int(h.get("t", 0))
			if int(h["hun"]) > 0:
				by[k2]["hun"] = int(by[k2]["hun"]) + Herds.head(h)
			by[k2]["fod"] = float(by[k2]["fod"]) + float(h["fod"])
			by[k2]["tiles"] = int(by[k2]["tiles"]) + (h.get("opl", []) as Array).size()
			by[k2]["cs"] = float(by[k2]["cs"]) + float(h.get("cs", 0.0))
	print("DAY %d (season %d): fodder in barns and market %d" % [int(Game.day), Calendar.season_index(Game.day), barn])
	var hung := {}
	for tid in ids:
		var e3: Dictionary = w["towns"][tid]["econ"]
		for hid in e3.get("hd", {}).get("h", {}):
			var h3: Dictionary = e3["hd"]["h"][hid]
			if int(h3["hun"]) > 0:
				var key := "%s/%s coin<%d" % [h3["ow"], h3["k"], 100 if Herds._coin(e3, h3) < 100.0 else (1000 if Herds._coin(e3, h3) < 1000.0 else 99999)]
				hung[key] = int(hung.get(key, 0)) + 1
		if e3.has("hd"):
			hung["price %s" % tid] = snappedf(float(e3["price"].get("fodder", 0.0)), 0.1)
	print("  hungry herds: %s" % str(hung))
	var made := {}; var used := {}; var biz := {}
	for tid in ids:
		var e4: Dictionary = w["towns"][tid]["econ"]
		for g in ["fresh_meat", "meat", "salt", "milk", "tallow", "candles", "fodder", "hides", "wool", "wax", "bones"]:
			made[g] = int(made.get(g, 0)) + int(e4["led"]["made"].get(g, 0))
			used[g] = int(used.get(g, 0)) + int(e4["led"]["used"].get(g, 0))
		for b in e4["biz"]:
			if String(b["type"]) in ["butcher", "salter", "dairy", "chandler", "saltworks", "herder", "drover"]:
				var k := "%s %s" % [b["type"], b["state"]]
				biz[k] = int(biz.get(k, 0)) + 1
				biz[String(b["type"]) + " staff"] = int(biz.get(String(b["type"]) + " staff", 0)) + int(b["workers"])
	print("  made %s\n  used %s\n  trades %s" % [str(made), str(used), str(biz)])
	for k in by:
		print("  %s: head %d, keep %d, hungry %d, hay %d, own plots %d, common share %.2f, offers %s" % [k, by[k]["head"], by[k]["t"], by[k]["hun"], int(by[k]["fod"]),
			by[k]["tiles"], by[k]["cs"], str(by[k]["off"])])
	var det := {}
	for tid in ids:
		var e2: Dictionary = w["towns"][tid]["econ"]
		for r in e2.get("hd", {}).get("log", []):
			var key2 := "%s %s %s" % [r[2], r[4], String(r[5]).split(" ")[0] if String(r[4]) != "died" else r[5]]
			det[key2] = int(det.get(key2, 0)) + absi(int(r[3]))
	var keys: Array = det.keys()
	keys.sort_custom(func(a, b): return int(det[a]) > int(det[b]))
	var parts := []
	for k3 in keys.slice(0, 18):
		parts.append("%s %d" % [k3, det[k3]])
	print("  log (last %d entries a town): %s" % [Herds.LOG_MAX, ", ".join(PackedStringArray(parts))])
