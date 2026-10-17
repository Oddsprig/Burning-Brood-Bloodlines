extends RefCounted
## Pure map-selector comparisons against v0.033's original loops. These position/kind records are not
## actors inserted into a campaign. Combat/RNG/cadence stay covered by the ordinary campaign tests and
## complete before/after snapshots. Optional MAP_LOOKUP_BENCH=1 prints isolated selector timings, no gate.

var fails := 0
var checks := 0
var old_position_reads := 0
var new_position_reads := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func run(_tree: SceneTree) -> int:
	var rng := RandomNumberGenerator.new(); rng.seed = 34027
	for trial in 180:
		var w := _records(rng, trial % 3, rng.randi_range(0, 400))
		var ids: Array = w["warbands"].keys()
		var before := JSON.stringify(Game._serialize(w), "", true, true)
		var rng_state := rng.state
		check(_old_pairs(w, ids) == CampaignWorld._clash_pairs(w, ids), "contact pair order trial %d" % trial)
		check(_plain_pairs(w, ids) == CampaignWorld._clash_pairs(w, ids), "plain contact order trial %d" % trial)
		old_position_reads += _old_read_count(w, ids)
		new_position_reads += ids.size()
		var counts := CampaignWorld._patrol_counts(w)
		for fid in ["middle_kingdom", "orc_horde", "goblin_warren", "northern_clans", "moon_court", "outside"]:
			check(_old_count(w, fid) == int(counts.get(fid, 0)), "patrol count %s trial %d" % [fid, trial])
		check(before == JSON.stringify(Game._serialize(w), "", true, true) and rng.state == rng_state,
			"selectors leave records and RNG unchanged trial %d" % trial)
	# Exact contact boundary, duplicate positions, negative coordinates and tied x order.
	var w := {"warbands": {}}
	for p in [Vector2.ZERO, Vector2(CampaignWorld.CONTACT, 0), Vector2(CampaignWorld.CONTACT + 0.001, 0),
		Vector2(0, CampaignWorld.CONTACT), Vector2.ZERO, Vector2(-CampaignWorld.CONTACT, 0)]:
		var id := "p%d" % w["warbands"].size()
		w["warbands"][id] = {"pos": p, "faction": "middle_kingdom", "kind": "patrol"}
	var ids: Array = w["warbands"].keys()
	check(_old_pairs(w, ids) == CampaignWorld._clash_pairs(w, ids), "contact boundary/tied x order")
	check(_plain_pairs(w, ids) == CampaignWorld._clash_pairs(w, ids), "contact boundary/plain order")
	print("MAP LOOKUPS checks=%d failures=%d original_position_reads=%d staged_position_reads=%d" %
		[checks, fails, old_position_reads, new_position_reads])
	if OS.get_environment("MAP_LOOKUP_BENCH") != "":
		_bench(rng)
	return fails

func _records(rng: RandomNumberGenerator, layout: int, count: int) -> Dictionary:
	var w := {"warbands": {}}
	var kinds := ["patrol", "raider", "militia", "caravan", "beasts", "assault", "deserter"]
	var factions := ["middle_kingdom", "orc_horde", "goblin_warren", "northern_clans", "moon_court", "outside"]
	for i in count:
		var pos: Vector2
		if layout == 0:
			pos = Vector2(rng.randf_range(-200, 6200), rng.randf_range(-200, 4000))
		elif layout == 1:
			pos = Vector2(rng.randi_range(-3, 3) * CampaignWorld.CONTACT, rng.randi_range(-3, 3) * CampaignWorld.CONTACT)
		else:
			pos = Vector2(i % 4, rng.randi_range(-5, 5))   # dense columns and coincident points
		w["warbands"]["p%d" % i] = {"pos": pos, "kind": kinds[rng.randi() % kinds.size()],
			"faction": factions[rng.randi() % factions.size()]}
	return w

## Frozen v0.033 contact sweep, including native tie ordering. No extra counters inside measured calls.
func _old_pairs(w: Dictionary, ids: Array) -> Array:
	var xs := []
	for i in ids.size():
		xs.append(Vector2((w["warbands"][ids[i]]["pos"] as Vector2).x, i))
	xs.sort()
	var pairs := []
	for m in xs.size():
		var mi := int(xs[m].y)
		var pm: Vector2 = w["warbands"][ids[mi]]["pos"]
		for q in range(m + 1, xs.size()):
			if float(xs[q].x) - pm.x > CampaignWorld.CONTACT:
				break
			var qi := int(xs[q].y)
			if pm.distance_squared_to(w["warbands"][ids[qi]]["pos"]) <= CampaignWorld.CONTACT * CampaignWorld.CONTACT:
				pairs.append(Vector2i(mini(mi, qi), maxi(mi, qi)))
	pairs.sort()
	return pairs

func _old_read_count(w: Dictionary, ids: Array) -> int:
	var xs := []
	for i in ids.size(): xs.append(Vector2((w["warbands"][ids[i]]["pos"] as Vector2).x, i))
	xs.sort()
	var reads := ids.size() * 2   # initial x extraction and each outer-loop position
	for m in xs.size():
		for q in range(m + 1, xs.size()):
			if float(xs[q].x) - float(xs[m].x) > CampaignWorld.CONTACT: break
			reads += 1
	return reads

func _plain_pairs(w: Dictionary, ids: Array) -> Array:
	var pairs := []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if (w["warbands"][ids[i]]["pos"] as Vector2).distance_squared_to(w["warbands"][ids[j]]["pos"]) <= CampaignWorld.CONTACT * CampaignWorld.CONTACT:
				pairs.append(Vector2i(i, j))
	return pairs

func _old_count(w: Dictionary, fid: String) -> int:
	var have := 0
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["faction"] == fid and wb["kind"] in ["patrol", "raider"]:
			have += 1
	return have

func _bench(rng: RandomNumberGenerator) -> void:
	for layout in [0, 1]:
		var w := _records(rng, layout, 240)
		var ids: Array = w["warbands"].keys()
		var old_times := []; var new_times := []
		for repeat in 7:
			var t0 := Time.get_ticks_usec()
			for i in 100: _old_pairs(w, ids)
			old_times.append((Time.get_ticks_usec() - t0) / 100.0)
			t0 = Time.get_ticks_usec()
			for i in 100: CampaignWorld._clash_pairs(w, ids)
			new_times.append((Time.get_ticks_usec() - t0) / 100.0)
		old_times.sort(); new_times.sort()
		print("MAP SELECTOR ONLY layout=%d bands=240 median_us original=%.3f staged=%.3f; excludes combat/full frame/rendering" %
			[layout, old_times[3], new_times[3]])
