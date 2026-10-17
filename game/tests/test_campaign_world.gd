extends RefCounted
## Campaign world generation: deterministic per seed; five regions; 12-16 towns with crafters,
## shop, prices and recruits with backstories; roads; starting warbands; the 1.5x map (war pick 5).

func _fingerprint(w: Dictionary) -> String:
	var parts := [str((w["terrain"] as String).hash()), str((w["road"] as String).hash())]
	var ids: Array = w["towns"].keys()
	ids.sort()
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		parts.append("%s|%s|%s|%d|%d|%s|%s|%d|%d" % [tid, t["name"], str(t["pos"]), t["size"], t["wealth"], t["specialty"],
			t["crafters"]["weaponsmith"]["name"], t["crafters"]["weaponsmith"]["skill"], t["shop"].size()])
		for r in t["recruits"]:
			parts.append(r.name + r.title + str(r.skills.values()))
	var wids: Array = w["warbands"].keys()
	wids.sort()
	for wid in wids:
		parts.append("%s %s %d" % [wid, str(w["warbands"][wid]["pos"]), w["warbands"][wid]["units"].size()])
	return "\n".join(parts)

func run(_tree: SceneTree) -> int:
	var fails := 0
	var t0 := Time.get_ticks_msec()
	Game.new_game(1234)
	print("generation took %d ms" % (Time.get_ticks_msec() - t0))
	var w: Dictionary = Game.world
	var fp1 := _fingerprint(w)
	Game.new_game(1234)
	var fp2 := _fingerprint(Game.world)
	if fp1 != fp2:
		print("FAIL: world generation not deterministic per seed"); fails += 1
	Game.new_game(999)
	if _fingerprint(Game.world) == fp1:
		print("FAIL: different seeds gave the same world"); fails += 1
	Game.new_game(1234)
	w = Game.world
	var n: int = w["towns"].size()
	print("towns: ", n, " roads: ", w["roads"].size(), " warbands: ", w["warbands"].size())
	if n < 15 or n > 19:   # 18 planned since the goblins' 5 warrens (Douglas 12:45; was 15, range 12-16)
		print("FAIL: town count ", n); fails += 1
	var counts := {}
	for c in (w["terrain"] as String):
		counts[c] = counts.get(c, 0) + 1
	print("terrain counts: ", counts)
	for c in ["g", "f", "h", "m", "w", "b", "s"]:
		if counts.get(c, 0) < 10:
			print("FAIL: too little terrain ", c); fails += 1
	var factions_with_towns := {}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		factions_with_towns[t["faction"]] = true
		var ws: Dictionary = t["crafters"]["weaponsmith"]
		var ar: Dictionary = t["crafters"]["armorsmith"]
		if ws.get("name", "") == "" or int(ws["skill"]) < 0 or int(ws["skill"]) > 15:
			print("FAIL: bad weaponsmith in ", t["name"]); fails += 1
		if t["shop"].is_empty() or t["recruits"].is_empty():
			print("FAIL: empty shop/recruits in ", t["name"]); fails += 1
		for it in t["shop"]:
			if not (it is Item) or Economy.price(t, it) <= 0:
				print("FAIL: bad shop item"); fails += 1
		for r in t["recruits"]:
			if r.backstory.length() < 60 or r.wage <= 0 or r.hire_cost <= 0:
				print("FAIL: bad recruit ", r.name, " ", r.backstory); fails += 1
		if not CampaignWorld.passable(w, t["pos"]):
			print("FAIL: town on impassable ground ", t["name"]); fails += 1
		print("%-12s %-14s %-10s size %d wealth %d %-8s | %s | %s | shop %d recruits %d contracts %d" % [t["name"], t["faction"], t["region"],
			t["size"], t["wealth"], t["specialty"], Economy.describe_crafter(ws), Economy.describe_crafter(ar),
			t["shop"].size(), t["recruits"].size(), t["contracts"].size()])
	if factions_with_towns.size() != 5:
		print("FAIL: not every faction has towns"); fails += 1
	# sample output
	var t0d: Dictionary = w["towns"][w["start_town"]]
	print("start town: ", Economy.describe_town(t0d))
	for it in t0d["shop"].slice(0, 6):
		print("  shop: %s  %d gold" % [it.display_name(), Economy.price(t0d, it)])
	for r in t0d["recruits"].slice(0, 2):
		print("  recruit: %s, %s (wage %d, hire %d): %s" % [r.name, r.title, r.wage, r.hire_cost, r.backstory])
	for c in t0d["contracts"]:
		print("  contract: ", c["desc"])
	# every town reachable from the party
	for tid in w["towns"]:
		if CampaignWorld.find_path(w, w["party"]["pos"], w["towns"][tid]["pos"]).is_empty():
			print("FAIL: town unreachable ", w["towns"][tid]["name"]); fails += 1
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		var rep := CampaignWorld.scout_report(Game, wid)
		print("  %s %s %s: %s, %s, %s" % [wid, wb["faction"], wb["kind"], rep["count_text"], rep["gear_text"], rep["strength_text"]])
	fails += _stretch()
	return fails

## War pick 5: the map is 1.5x the old one in each direction; every town is on the road network; march days between
## neighbouring towns grow about 1.5x against the same seed built at the old size; a save keeps its map size.
func _stretch() -> int:
	var f := 0
	Game.new_game(1234)
	var w: Dictionary = Game.world
	var want := Vector2i(roundi(WorldGen.BASE_W * 1.5), roundi(WorldGen.BASE_H * 1.5))
	if int(w["w"]) != want.x or int(w["h"]) != want.y or WorldGen.map_px() != Vector2(want) * WorldGen.CELL \
			or (w["terrain"] as String).length() != want.x * want.y:
		print("FAIL: map not 1.5x: %d x %d cells, %s px" % [int(w["w"]), int(w["h"]), str(WorldGen.map_px())]); f += 1
	# every town joined to every other by roads (the road links form one network), and each road walks road cells
	var net := {w["towns"].keys()[0]: true}
	var grew := true
	while grew:
		grew = false
		for r in w["roads"]:
			if net.has(r["a"]) != net.has(r["b"]):
				net[r["a"]] = true; net[r["b"]] = true; grew = true
	if net.size() != w["towns"].size():
		print("FAIL: %d of %d towns on the road network" % [net.size(), w["towns"].size()]); f += 1
	for r in w["roads"]:
		var p0: Vector2 = r["pts"][0]; var p1: Vector2 = r["pts"][-1]
		if not CampaignWorld.on_road(w, p0) or not CampaignWorld.on_road(w, p1) or not CampaignWorld.on_road(w, r["pts"][r["pts"].size() / 2]):
			print("FAIL: road %s-%s off its road cells" % [r["a"], r["b"]]); f += 1
	var big := _neighbour_days(w)
	# the same seed at the old size, for comparison
	WorldGen.gen_stretch = 1.0
	Game.new_game(1234)
	var small := _neighbour_days(Game.world)
	var old_px := WorldGen.map_px()
	WorldGen.gen_stretch = WorldGen.STRETCH
	Game.new_game(1234)
	var ratio: float = big[0] / maxf(0.01, small[0])
	print("map %s px (old %s): towns %d vs %d; mean march days to the nearest town %.2f vs %.2f (x%.2f), longest %.1f vs %.1f" % [
		str(WorldGen.map_px()), str(old_px), int(big[1]), int(small[1]), big[0], small[0], ratio, big[2], small[2]])
	if int(big[1]) != int(small[1]) or ratio < 1.3 or ratio > 1.7:
		print("FAIL: march days between neighbouring towns grew x%.2f (want about 1.5)" % ratio); f += 1
	# a save keeps its grid: an old 100 x 64 world loads at its own size
	WorldGen.use_world({"w": 100, "h": 64})
	if WorldGen.W != 100 or WorldGen.H != 64 or not is_equal_approx(WorldGen.K, 1.0):
		print("FAIL: an old world's map size not kept"); f += 1
	WorldGen.use_world(Game.world)
	return f

## [mean march days from each town to its nearest town by path, towns, the longest of those]
func _neighbour_days(w: Dictionary) -> Array:
	var tot := 0.0; var worst := 0.0
	for tid in w["towns"]:
		var a: Vector2 = w["towns"][tid]["pos"]
		var best := INF
		for oid in w["towns"]:
			if oid == tid:
				continue
			var b: Vector2 = w["towns"][oid]["pos"]
			if a.distance_to(b) > best * CampaignWorld.WARBAND_SPEED * 1.5:
				continue   # cannot beat the best on a road at full speed
			var p := CampaignWorld.find_path(w, a, b)
			if p.is_empty():
				continue
			var days := 0.0
			var cur := a
			for q in p:
				var seg: float = cur.distance_to(q)
				var n := maxi(1, int(seg / 6.0))
				for i in n:
					days += (seg / n) / (CampaignWorld.WARBAND_SPEED * CampaignWorld.speed_mult(w, cur.lerp(q, (i + 0.5) / n)))
				cur = q
			best = minf(best, days)
		tot += best
		worst = maxf(worst, best)
	return [tot / maxf(1, w["towns"].size()), w["towns"].size(), worst]
