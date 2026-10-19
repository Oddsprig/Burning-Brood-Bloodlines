extends RefCounted
## Diagnostic only: where are the working adults? Loads one checkpoint (PROBE_SAVE) or the DevTools start world,
## and prints adults, hands needed on family land, farm/trade business workers and caps, idle and service counts.
func run(tree: SceneTree) -> int:
	var path: String = OS.get_environment("PROBE_SAVE")
	if path != "":
		var old: String = Game.SAVE_PATH
		Game.SAVE_PATH = path
		var ok: bool = Game.load_game()
		Game.SAVE_PATH = old
		if not ok: print("LAB missing ", path); return 0
	else:
		await DevTools.start_world(tree, "user://diag_labour.save")
	var adults: float = 0.0; var need: float = 0.0; var hands: float = 0.0; var idle: float = 0.0; var jobs: float = 0.0
	var by: Dictionary = {}
	for town: Dictionary in Game.world.get("towns", {}).values():
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		for f: Dictionary in e.get("fams", []):
			if f.get("gone", false) or f.get("estate", false): continue
			adults += float(Families.adults(f)); need += Families.need_hands(f, e)
			hands += float(f.get("hands", 0)); idle += float(f.get("idle", 0)); jobs += float(Families.job_total(f))
		for b: Dictionary in e.get("biz", []):
			if b.get("closed", false): continue
			var t: String = String(b.get("type", ""))
			if not by.has(t): by[t] = [0, 0, 0]
			by[t][0] += 1; by[t][1] += int(b.get("workers", 0)); by[t][2] += int(b.get("cap", 0))
	print("LAB day=%d adults=%.0f land_hands_needed=%.0f own_hands=%.0f jobs_held=%.0f idle=%.0f" % [int(Game.day), adults, need, hands, jobs, idle])
	var keys: Array = by.keys(); keys.sort_custom(func(a, b): return int(by[a][1]) > int(by[b][1]))
	for t in keys: print("LAB biz %s n=%d workers=%d cap=%d" % [t, by[t][0], by[t][1], by[t][2]])
	return 0
