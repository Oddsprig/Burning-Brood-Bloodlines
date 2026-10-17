extends RefCounted
## Frozen v0.034 references; all physical force units come from generated campaign state.
const OldTracks = preload("res://tests/fixtures/tracks_v034.gd")
const OldGeometry = preload("res://tests/fixtures/map_tracks_geometry_v034.gd")
const NewGeometry = preload("res://campaign/map_tracks.gd")
var fails := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", label)
func frozen(w: Dictionary) -> String:
	return JSON.stringify(Game._serialize(w), "", false, true)
func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	Game.new_game(35035)
	var w: Dictionary = Game.world
	var original := frozen(w)
	var rng_state := Game.rng.state
	var a := w.duplicate(true); var b := w.duplicate(true)
	var sa := OldTracks.state(a); var sb := Tracks.state(b)
	for tick in 28:
		for wid in a["warbands"]:
			# Same positions/paths on the real registered forces; no units/items/cash are invented.
			var p: Vector2 = w["warbands"][wid]["pos"] + Vector2(tick * 13, tick * 3)
			a["warbands"][wid]["pos"] = p; b["warbands"][wid]["pos"] = p
			a["warbands"][wid]["path"] = [p + Vector2(100, 0)]
			b["warbands"][wid]["path"] = [p + Vector2(100, 0)]
		OldTracks._drop(a, sa, tick * Tracks.DROP_EVERY)
		Tracks._drop(b, sb, tick * Tracks.DROP_EVERY)
		check(frozen(sa) == frozen(sb), "drop full state and insertion order tick %d" % tick)
		OldTracks._expire(a, sa, tick * Tracks.DROP_EVERY)
		Tracks._expire(b, sb, tick * Tracks.DROP_EVERY)
		check(frozen(sa) == frozen(sb), "expiry/ring state tick %d" % tick)
	# Force removal and expired/empty trails preserve the original selector.
	var ids: Array = a["warbands"].keys()
	if not ids.is_empty():
		a["warbands"].erase(ids[0]); b["warbands"].erase(ids[0])
	OldTracks._drop(a, sa, 4.0); Tracks._drop(b, sb, 4.0)
	OldTracks._expire(a, sa, 7.0); Tracks._expire(b, sb, 7.0)
	check(frozen(sa) == frozen(sb), "removed force and empty trails")
	_geometry_checks(sb)
	check(original == frozen(w) and rng_state == Game.rng.state, "selectors do not mutate original actors/state/RNG")
	if OS.get_environment("MAP_V035_BENCH") == "1": _bench(w)
	print("MAP V035 checks=%d failures=%d" % [checks, fails])
	return fails

func _geometry_checks(st: Dictionary) -> void:
	var old := OldGeometry.new(); var candidate := NewGeometry.new()
	var fixture := st.duplicate(true)
	# Refill after expiry with real force identities; display records are selectors, not campaign actors.
	if fixture["forces"].is_empty():
		for wid in Game.world["warbands"]:
			var wb: Dictionary = Game.world["warbands"][wid]
			fixture["forces"][wid] = {"r": Tracks._race_of(wb), "mark": false, "c": [10.0, 20.0, 1.0, 3.0, 0.0, 0.0]}
	var first: String = fixture["forces"].keys()[0]
	var idx := 0
	for wid in fixture["forces"]:
		var rec: Dictionary = fixture["forces"][wid]
		rec["mark"] = idx % 2 == 0
		rec["c"] = [10.0, 20.0, 1.0, 3.0, 0.0, 1.0,
			-30.0, 0.0, 1.125, 4.0, PI / 4.0, 0.0,
			10.0, 20.0, 1.25, 4.0, -PI, 1.0]
		idx += 1
	for day in [0.0, 1.0, 2.0, 3.0, 3.125, 3.25, 4.0]:
		for target in ["", first, "missing"]:
			var before := frozen(fixture)
			var x: Array = old.geometry(fixture, day, target)
			var y: Array = candidate.geometry(fixture, day, target)
			for i in 4: check(x[i] == y[i], "exact geometry/colours buffer %d day %.3f target %s" % [i, day, target])
			check(before == frozen(fixture), "geometry read only")
	check(old.geometry({"forces": {}}, 1.0, "") == candidate.geometry({"forces": {}}, 1.0, ""), "empty geometry")
	candidate.free()

func _bench(w: Dictionary) -> void:
	for kind in ["drop", "geometry"]:
		var old_times := []; var new_times := []
		for sample in 7:
			var paired := []
			for candidate in ([false, true] if sample % 2 == 0 else [true, false]):
				var copy := w.duplicate(true)
				var st := Tracks.state(copy)
				for wid in copy["warbands"]:
					var wb: Dictionary = copy["warbands"][wid]
					wb["path"] = [wb["pos"] + Vector2(100, 0)]
					Tracks.add_crumb(copy, wid, {"f": wb["faction"], "k": wb["kind"], "r": Tracks._race_of(wb)}, wb["pos"], 0.0, wb["units"].size(), 0.0)
					st["forces"][wid]["c"][5] = 1.0
					wb["pos"] += Vector2(20, 0)
				if kind == "geometry":
					for wid in copy["warbands"]:
						var wb: Dictionary = copy["warbands"][wid]
						for crumb in 15:
							Tracks.add_crumb(copy, wid, {}, wb["pos"] + Vector2(crumb * 13, 0), crumb * 0.01, wb["units"].size(), crumb * 0.1)
						for ci in range(5, st["forces"][wid]["c"].size(), Tracks.STRIDE): st["forces"][wid]["c"][ci] = 1.0
				var geom: Object = NewGeometry.new() if candidate else OldGeometry.new()
				var count := 100
				var t0 := Time.get_ticks_usec()
				for i in count:
					if kind == "drop":
						for wb in copy["warbands"].values(): wb["pos"] += Vector2(13, 0)
						if candidate: Tracks._drop(copy, st, i * 0.125)
						else: OldTracks._drop(copy, st, i * 0.125)
					else:
						geom.geometry(st, 0.5, "")
				var us := (Time.get_ticks_usec() - t0) / float(count)
				if candidate: new_times.append(us)
				else: old_times.append(us)
				paired.append(frozen(copy))
				if candidate: geom.free()
			check(paired[0] == paired[1], "bench pair full state/order %s sample %d" % [kind, sample])
		old_times.sort(); new_times.sort()
		print("MAP V035 BENCH %s median_us old=%.3f candidate=%.3f old_samples=%s candidate_samples=%s" % [kind, old_times[3], new_times[3], str(old_times), str(new_times)])
