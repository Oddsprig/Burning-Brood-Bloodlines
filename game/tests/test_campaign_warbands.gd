extends RefCounted
## v0.100 r2: native spawning, orders and full campaign time in every case.
## The original no-argument entry point selects movement, interaction and travel.
## docs/specs/monsters-wave1.md:45: "Animals roam near their lair; big ones mostly stay put".
## game/campaign/monsters.gd:296-302: "big beasts and camp garrisons stay put".
## Militia has its own off-duty/wall/pasture rules (militia.gd:157-175; town_defence.gd:147-169).
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.

const RunplanArgs: GDScript = preload("res://tests/fixtures/older_runplan_args_v100.gd")
const SpeedCheckpoint: GDScript = preload("res://tests/fixtures/older_speed_checkpoint_v100.gd")
const SpeedParts: GDScript = preload("res://tests/fixtures/older_speed_parts_v100.gd")
const CASE_MS: int = 135000
const PARTS: Array[String] = ["setup", "movement1", "movement2", "movement3", "movement4", "interaction", "travel_out", "travel_back", "weakening"]
const MOVEMENT_PART_STEPS: int = 25
const ROAMING: Array[String] = ["patrol", "raider", "contract", "assault", "bandit", "deserter", "beasts"]
var fails: int = 0
var checks: int = 0
var started: int = 0
var completed: Array[String] = []
var advanced: float = 0.0
var _chain_tag: String = ""
var _pending_receipt: Dictionary = {}

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL warbands: ", label)
	return ok

func _budget() -> bool:
	return check(Time.get_ticks_msec() - started < CASE_MS, "bounded case deadline")

func _path_ok(origin: Vector2, path: Array) -> bool:
	if path.is_empty(): return false
	var previous: Vector2 = origin
	for point: Vector2 in path:
		var samples: int = maxi(1, ceili(previous.distance_to(point) / 6.0))
		for i: int in range(samples + 1):
			if not CampaignWorld.passable(Game.world, previous.lerp(point, float(i) / samples)): return false
		previous = point
	return true

func _near(origin: Vector2, direction: Vector2, distance: float, fleeing: bool = false) -> Vector2:
	# v0.100: choose existing reachable ground; never install a path or move a band.
	for i: int in 16:
		var requested: Vector2 = origin + direction.rotated(float(i) * TAU / 16.0) * distance
		var point: Vector2 = CampaignWorld.nearest_passable(Game.world, requested)
		var path: Array = CampaignWorld.find_path(Game.world, origin, point)
		var separation: float = origin.distance_to(point)
		if separation <= 80.0 or separation >= CampaignWorld.WARBAND_SIGHT: continue
		if not _path_ok(origin, path) or CampaignWorld.path_length(origin, path) > 400.0: continue
		if not CampaignWorld._clear_line(Game.world, origin, point): continue
		if fleeing:
			var away: Vector2 = (point - origin).normalized()
			var end: Vector2 = point + away * 250.0
			if not CampaignWorld.passable(Game.world, end): continue
			var escape: Array = CampaignWorld.find_path(Game.world, point, end)
			if not _path_ok(point, escape) or not CampaignWorld._clear_line(Game.world, point, end): continue
			if (escape[-1] as Vector2).distance_to(origin) <= separation: continue
		return point
	return Vector2.INF

func _home(fid: String) -> Dictionary:
	var best: Dictionary = {}
	var available: int = 0
	for town: Dictionary in Game.world["towns"].values():
		if str(town["faction"]) != fid or not TownEcon.has_econ(town): continue
		var spare: int = Population.available(town)
		if spare > available:
			available = spare
			best = town
	return best

func _spawn(fid: String, count: int, pos: Vector2, kind: String, rng: RandomNumberGenerator) -> String:
	var home: Dictionary = _home(fid)
	if not check(not home.is_empty(), fid + ": a real home with spare residents"): return ""
	var wid: String = CampaignWorld.spawn_warband(Game, fid, pos, count, kind, rng, {"home": home["id"]})
	if not check(wid != "" and Game.world["warbands"].has(wid), fid + ": native draft accepted a force ID"): return ""
	var band: Dictionary = Game.world["warbands"][wid]
	var units: Array = band["units"]
	if not check(not units.is_empty() and units.size() <= count, fid + ": actual accepted nonempty roster"): return ""
	for unit: Unit in units:
		var family: Dictionary = People.fam_of(Game.world["towns"].get(unit.home_town, {}), unit.family)
		if not check(not family.is_empty() and not Persons.by_uid(family, unit.uid).is_empty()
				and Army.state(Game.world)["roll"].has(str(unit.uid)), fid + ": enlisted body is a registered resident"): return ""
	var payer: Dictionary = {"kind": "faction", "fac": Game.world["factions"][fid]}
	var paid: Dictionary = Army.pay_units(Game, units, payer, "army", TownEcon.culture_of(home["econ"]))
	Army._band_unpaid(Game.world, fid)
	Supplies.provision(Game, band, payer)
	if not check(float(paid["bill"]) > 0.0 and is_equal_approx(float(paid["paid"]), float(paid["bill"])) and int(paid["unpaid"]) == 0
			and int(band.get("unpaid_n", -1)) == 0, fid + ": native treasury paid the actual wage bill"): return ""
	if not check(Supplies.days(band) > 0.0 and CampaignWorld.band_power(units) > 0.0,
			fid + ": native market provisions and positive actual power"): return ""
	return wid

func _eligible(band: Dictionary) -> bool:
	if not str(band["kind"]) in ROAMING or Monsters.suspended_band(band) or band.has("raid"): return false
	if str(band["id"]) == str(Game.world.get("encounter", "")) or float(band["rest_until"]) > Game.day: return false
	if band["kind"] == "assault" and float(band["march_day"]) > Game.day: return false
	if str(band.get("war", {}).get("m", "")) == "home": return false
	var units: Array = band["units"]
	if units.is_empty(): return false
	var unpaid: int = 0
	for unit: Unit in units:
		if not unit.dead and unit.unpaid_days > 0: unpaid += 1
	if unpaid > 0 and unpaid >= units.size() * WarAI.UNPAID_SHARE: return false
	if units.size() < float(band.get("n0", units.size())) * WarAI.HOME_SHARE: return false
	return true

func _ground() -> bool:
	if not check(CampaignWorld.passable(Game.world, Game.world["party"]["pos"]), "party remains on passable ground"): return false
	for wid: String in Game.world["warbands"]:
		if not check(CampaignWorld.passable(Game.world, Game.world["warbands"][wid]["pos"]), wid + ": remains on passable ground"): return false
	return true

func _drain(tree: SceneTree) -> bool:
	while not Game.world.get("work", []).is_empty():
		if not _budget(): return false
		var before: float = Game.day
		# The same public clock drains ordered work without advancing campaign time.
		Game.advance_time(0.0, false, 0, 1000)
		if not check(Game.day == before, "pending-work drain advances zero campaign days"): return false
		await tree.process_frame
	return _budget()

func _advance(tree: SceneTree, days: float) -> bool:
	# A pending queue makes advance_time return early; drain it BEFORE requesting time.
	if not await _drain(tree): return false
	var before: float = Game.day
	Game.advance_time(days, false, 0, 1000)
	if not check(absf((Game.day - before) - days) < 1.0e-9, "public clock advanced the requested campaign days"): return false
	advanced += days
	if not await _drain(tree): return false
	return _budget() and _ground()

func _movement_begin(rng: RandomNumberGenerator) -> Dictionary:
	var start: Dictionary = {}
	var stationary: Dictionary = {}
	for wid: String in Game.world["warbands"]:
		var band: Dictionary = Game.world["warbands"][wid]
		if _eligible(band): start[wid] = band["pos"]
		if band["kind"] in ["den", "camp"] and not band.has("raid"):
			stationary[wid] = band["pos"]
	if not check(not start.is_empty(), "PREREQUISITE nonempty native eligible roaming cohort before fixture spawn"): return {}
	if not check(not stationary.is_empty(), "PREREQUISITE nonempty native den/camp stationary control"): return {}
	var home: Dictionary = _home("middle_kingdom")
	if not check(not home.is_empty(), "patrol fixture has a native home"): return {}
	var origin: Vector2 = home["pos"]
	var point: Vector2 = _near(origin, Vector2.RIGHT, 180.0)
	if not check(point != Vector2.INF, "patrol fixture has a real passable route"): return {}
	var fixtures: Array[String] = []
	var fixture_start: Dictionary = {}
	for position: Vector2 in [origin, point]:
		var wid: String = _spawn("middle_kingdom", 3, position, "patrol", rng)
		if wid == "": return {}
		fixtures.append(wid)
		fixture_start[wid] = Game.world["warbands"][wid]["pos"]
		if not check(_eligible(Game.world["warbands"][wid]), "paid native patrol qualifies before the movement window"): return {}
	if not _ground(): return {}
	var day0: float = Game.day
	return {"start": start, "stationary": stationary, "fixtures": fixtures, "fixture_start": fixture_start, "day0": day0, "steps_done": 0}

func _movement_steps(tree: SceneTree, move_state: Dictionary, step_count: int) -> bool:
	var stationary: Dictionary = move_state["stationary"]
	# Keep the original 100 x 0.05 days, including native AI clashes and daily jobs.
	# The party stays in its fixture town; no encounters, orders or wage flags are cleared.
	for i: int in step_count:
		if not await _advance(tree, 0.05): return false
		if not check(Game.world["encounter"] == "", "in-town observation has no suppressed encounter"): return false
		for wid: String in stationary:
			if Game.world["warbands"].has(wid):
				if not check(Game.world["warbands"][wid]["pos"] == stationary[wid], wid + ": den/camp stays exactly at its spawn"): return false
	move_state["steps_done"] = int(move_state.get("steps_done", 0)) + step_count
	return fails == 0

func _movement_finish(move_state: Dictionary) -> void:
	var start: Dictionary = move_state["start"]
	var stationary: Dictionary = move_state["stationary"]
	var fixtures: Array[String] = []
	for wid_var: Variant in move_state["fixtures"]:
		fixtures.append(str(wid_var))
	var fixture_start: Dictionary = move_state["fixture_start"]
	var day0: float = float(move_state["day0"])
	if not check(int(move_state.get("steps_done", 0)) == 100, "movement completed all 100 native steps"): return
	if not check(absf(Game.day - day0 - 5.0) < 1.0e-9, "movement advanced five actual campaign days"): return
	var moved: int = 0
	var survived: int = 0
	var fixture_survivors: int = 0
	var fixture_moved: int = 0
	for wid: String in start:
		if not Game.world["warbands"].has(wid): continue
		survived += 1
		if (Game.world["warbands"][wid]["pos"] as Vector2).distance_to(start[wid]) > 30.0:
			moved += 1
	for wid: String in fixtures:
		if not Game.world["warbands"].has(wid): continue
		fixture_survivors += 1
		if (Game.world["warbands"][wid]["pos"] as Vector2).distance_to(fixture_start[wid]) > 30.0:
			fixture_moved += 1
	if not check(survived > 0 and 2 * moved >= survived, ">30px for at least half of surviving pre-existing eligible roaming bands"): return
	if not check(fixture_survivors > 0 and 2 * fixture_moved >= fixture_survivors, "native paid patrol fixture itself moves >30px for at least half its survivors"): return
	var stationary_survivors: int = 0
	for wid: String in stationary:
		if Game.world["warbands"].has(wid): stationary_survivors += 1
	if not check(stationary_survivors > 0, "stationary-role observation has actual survivors"): return
	print("five native days: %d bands; log tail: %s" % [Game.world["warbands"].size(), Game.world["log"].slice(-3)])
	print("warbands movement: %d/%d eligible survivors, %d/%d fixture survivors moved >30px" % [moved, survived, fixture_moved, fixture_survivors])

func _movement(tree: SceneTree, rng: RandomNumberGenerator) -> void:
	var move_state: Dictionary = _movement_begin(rng)
	if move_state.is_empty(): return
	if not await _movement_steps(tree, move_state, 100): return
	_movement_finish(move_state)

func _interaction(tree: SceneTree, rng: RandomNumberGenerator) -> void:
	var tid: String = str(Game.world["start_town"])
	if not check(tid != "", "native selectable house"): return
	if not check(str(Game.location) == tid and Mobilization._here(Game, tid), "PREREQUISITE party is physically at its original house town"): return
	var purse: float = float(Feudal._payer(Game).get("purse", 0.0))
	var amount: float = floor(purse * 0.6)
	if not check(amount > 0.0, "PREREQUISITE actual house purse can fund its army"): return
	var funding: Dictionary = Mobilization.fund(Game, amount)
	if not check(bool(funding.get("ok", false)), "PREREQUISITE native house funding: " + str(funding.get("reason", ""))): return
	var quote: Dictionary = Mobilization.quote(Game, tid, 4)
	if not check(bool(quote.get("ok", false)), "PREREQUISITE native muster quote: " + str(quote.get("reason", ""))): return
	var company0: int = Game.company.size()
	var raised: Dictionary = Mobilization.muster(Game, tid, 4, quote["review"])
	if not check(bool(raised.get("ok", false)) and int(raised.get("raised", 0)) == int(quote["planned"])
			and Game.company.size() == company0 + int(raised.get("raised", 0))
			and int(raised.get("raised", 0)) > 0 and CampaignWorld.party_power(Game) > 0.0,
			"PREREQUISITE native funded muster raises the actual quoted company"): return
	# The five actual campaign days naturally outlive startup protection.
	if not check(float(Game.world["party"]["safe_until"]) <= Game.day, "PREREQUISITE native startup protection expired during movement"): return
	if not _leave_town(): return
	Diplomacy.add_earned(Game, "orc_horde", -100, "test")
	Diplomacy.add_earned(Game, "goblin_warren", -100, "test")
	if not check(CampaignWorld.is_hostile(Game, "orc_horde") and CampaignWorld.is_hostile(Game, "goblin_warren"), "both native standings are hostile"): return
	var ppos: Vector2 = Game.world["party"]["pos"]
	var near_big: Vector2 = _near(ppos, Vector2.RIGHT, 180.0)
	var near_small: Vector2 = _near(ppos, Vector2.LEFT, 160.0, true)
	if not check(near_big != Vector2.INF and near_small != Vector2.INF, "reachable chase and flee sites inside native sight"): return
	if not check(near_big.distance_to(near_small) > 2.0 * CampaignWorld.WARBAND_SPEED * 0.6 + CampaignWorld.CONTACT,
			"PREREQUISITE opposing fixture bands start outside mutual clash reach"): return
	var big: String = _spawn("orc_horde", 40, near_big, "raider", rng)
	if big == "": return
	var small: String = _spawn("goblin_warren", 2, near_small, "raider", rng)
	if small == "": return
	var bands: Dictionary = Game.world["warbands"]
	var party_power: float = CampaignWorld.party_power(Game)
	var big_power: float = CampaignWorld.band_power(bands[big]["units"])
	var small_power: float = CampaignWorld.band_power(bands[small]["units"])
	if not check(big_power >= party_power and small_power < party_power * 0.6,
			"PREREQUISITE actual accepted powers meet native chase/flee thresholds: orcs=%.6f company=%.6f goblins=%.6f" % [big_power, party_power, small_power]): return
	var d_big0: float = (bands[big]["pos"] as Vector2).distance_to(ppos)
	var d_small0: float = (bands[small]["pos"] as Vector2).distance_to(ppos)
	# Full campaign integration: the clock owns steering, contact, clashes and daily work.
	var contact: bool = false
	var chase_seen: bool = false
	var flee_seen: bool = false
	var day0: float = Game.day
	var steps: int = 0
	for i: int in 30:
		if not _budget(): return
		if not await _advance(tree, 0.02): return
		if not check(bands.has(big) and bands.has(small), "both interaction bands survive actual campaign time"): return
		if not check(str(Game.world["encounter"]) in ["", big], "no unrelated encounter interrupts interaction"): return
		steps += 1
		chase_seen = chase_seen or bands[big]["mode"] == "chase"
		flee_seen = flee_seen or bands[small]["mode"] == "flee"
		if Game.world["encounter"] == big:
			contact = true
			break
	if not check(bands.has(big) and bands.has(small), "both accepted interaction forces still exist"): return
	var d_big1: float = (bands[big]["pos"] as Vector2).distance_to(ppos)
	var d_small1: float = (bands[small]["pos"] as Vector2).distance_to(ppos)
	if not check(absf(Game.day - day0 - steps * 0.02) < 1.0e-9 and (contact or steps == 30), "interaction retains the original thirty campaign steps unless actual contact occurs"): return
	print("big orc band: %.2f -> %.2f px (contact %s); small goblin band: %.2f -> %.2f px" % [d_big0, d_big1, contact, d_small0, d_small1])
	if not check(contact or d_big1 < d_big0, "strong hostile band chases"): return
	if not check(d_small1 > d_small0, "weak hostile band flees"): return
	if not check(chase_seen and flee_seen, "both production steering branches executed during real campaign time"): return
	var report: Dictionary = CampaignWorld.scout_report(Game, big)
	if not check(report.get("id", "") == big and str(report.get("count_text", "")) != "" and str(report.get("gear_text", "")) != ""
			and str(report.get("strength_text", "")) != "", "native scouting describes the accepted force"): return
	print("scouting the orcs: ", report["count_text"], "; ", report["gear_text"], "; ", report["strength_text"])
	CampaignWorld.retreat(Game, big)
	check(Game.world["encounter"] == "" and float(Game.world["party"]["safe_until"]) == Game.day + 0.5
			and float(bands[big]["rest_until"]) == Game.day + 0.5, "native retreat clears contact and grants the exact half-day safe/rest window")

func _travel_to(tree: SceneTree, target: Vector2, tid: String = "") -> bool:
	var origin: Vector2 = Game.world["party"]["pos"]
	if not check(CampaignWorld.set_travel(Game, target, tid), "native travel order accepted"): return false
	if not check(_path_ok(origin, Game.world["party"]["path"]), "native travel path is passable"): return false
	for i: int in 200:
		if not await _advance(tree, 0.05): return false
		var encounter: String = str(Game.world["encounter"])
		if encounter != "":
			# Real contact pauses travel. Use the player's native retreat and re-order,
			# never clear contact or manufacture protection to make travel pass.
			if not check(Game.world["warbands"].has(encounter), "contact names a real surviving band"): return false
			CampaignWorld.retreat(Game, encounter)
			if not check(Game.world["encounter"] == "" and float(Game.world["party"]["safe_until"]) == Game.day + 0.5,
					"travel retreat supplies the actual native safe window"): return false
			var here: Vector2 = Game.world["party"]["pos"]
			if not check(CampaignWorld.set_travel(Game, target, tid), "native destination re-order after actual retreat"): return false
			if not check(_path_ok(here, Game.world["party"]["path"]), "re-ordered native path stays passable"): return false
		if tid != "" and Game.world["party"]["arrived"] == tid:
			return check(Game.world["party"]["pos"] == target, "arrival reaches the actual town position")
		if tid == "" and not CampaignWorld.is_travelling(Game):
			return check(Game.world["party"]["pos"] == target, "outward order reaches its actual destination")
	return check(false, "party did not reach its destination within the original 200 campaign steps")

func _travel_out(tree: SceneTree) -> Dictionary:
	var town: Dictionary = Game.world["towns"][Game.world["start_town"]]
	var origin: Vector2 = Game.world["party"]["pos"]
	var target: Vector2 = town["pos"]
	if not check(Game.location == "" and CampaignWorld.passable(Game.world, target), "PREREQUISITE party is on the map and its town is passable"): return {}
	var point: Vector2 = _near(origin, Vector2.RIGHT, 100.0)
	if not check(point != Vector2.INF and point.distance_to(target) > 30.0, "PREREQUISITE nonzero reachable outward travel"): return {}
	var day0: float = Game.day
	if not await _travel_to(tree, point): return {}
	if not check((Game.world["party"]["pos"] as Vector2).distance_to(origin) > 30.0, "party actually travelled away through the public clock"): return {}
	var return_day: float = Game.day
	return {"town_id": str(town["id"]), "target": target, "day0": day0, "return_day": return_day}

func _travel_back(tree: SceneTree, travel_state: Dictionary) -> void:
	var town_id: String = str(travel_state["town_id"])
	var town: Dictionary = Game.world["towns"][town_id]
	var target: Vector2 = travel_state["target"]
	var day0: float = float(travel_state["day0"])
	var return_day: float = float(travel_state["return_day"])
	if not await _travel_to(tree, target, str(town["id"])): return
	check(Game.world["party"]["arrived"] == town["id"] and Game.world["party"]["pos"] == target
			and Game.day > return_day and return_day > day0, "party arrives at the actual town after nonzero outward and return campaign time")

func _travel(tree: SceneTree) -> void:
	var travel_state: Dictionary = await _travel_out(tree)
	if travel_state.is_empty() or fails > 0: return
	await _travel_back(tree, travel_state)

func _weakening() -> void:
	var fid: String = "goblin_warren"
	if not check(Game.world["factions"].has(fid), "PREREQUISITE goblin faction exists"): return
	var before: int = CampaignWorld.desired_bands(Game.world, fid)
	if not check(before > 0 and float(Game.world["factions"][fid]["strength"]) > 0.2, "PREREQUISITE goblin faction has bands and is above the native defeat floor"): return
	for i: int in 4: CampaignWorld.weaken_faction(Game.world, fid, 8)
	var after: int = CampaignWorld.desired_bands(Game.world, fid)
	print("goblin bands wanted: %d -> %d after four defeats" % [before, after])
	check(after < before, "four actual defeats strictly reduce desired faction bands")

func _leave_town() -> bool:
	if not check(Game.main == null, "headless fixture has no live UI controller"): return false
	var town_script: GDScript = load("res://ui/town.gd")
	if not check(town_script != null and town_script.can_instantiate(), "PREREQUISITE native town departure script loads"): return false
	var town_screen: Node = town_script.new()
	town_screen.call("_leave")
	town_screen.free()
	return check(Game.location == "", "native town departure accepted")

func _select_part() -> String:
	var env_part: String = OS.get_environment("WARBANDS_PART")
	var selected: String = env_part if not env_part.is_empty() else "all"
	var seen_part: bool = not env_part.is_empty()
	_chain_tag = OS.get_environment("WARBANDS_CHAIN")
	var seen_chain: bool = not _chain_tag.is_empty()
	for arg: String in RunplanArgs.arguments():
		if arg == "--part" or arg == "--speed-part" or arg == "--chain":
			check(false, "supply explicit --part=<stage> and optional --chain=<id>")
			return ""
		if arg.begins_with("--chain="):
			var chain_val: String = arg.trim_prefix("--chain=")
			if chain_val.is_empty() or (seen_chain and chain_val != _chain_tag):
				check(false, "nonempty non-conflicting warbands --chain required")
				return ""
			seen_chain = true
			_chain_tag = chain_val
			continue
		var val: String = ""
		if arg.begins_with("--part="):
			val = arg.trim_prefix("--part=")
		elif arg.begins_with("--speed-part="):
			val = arg.trim_prefix("--speed-part=")
		else:
			continue
		if val.is_empty() or (seen_part and val != selected):
			check(false, "nonempty non-conflicting warbands --part required")
			return ""
		seen_part = true
		selected = val
	if _chain_tag != "":
		if not check(_chain_tag.length() <= 48, "bounded warbands --chain length"): return ""
		for ch: String in _chain_tag:
			if not check(ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-", "safe warbands --chain character"): return ""
	if selected != "all" and not selected in PARTS:
		check(false, "choose --part=" + "|".join(PackedStringArray(PARTS)) + " in order")
		return ""
	return selected

func _write_receipt_json(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	return ok

func _read_receipt_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _begin_warbands_step(checkpoint: RefCounted, step: int) -> bool:
	var path: String = str(checkpoint.call("_path", step))
	return check(_write_receipt_json(path + ".complete.json", {"complete": false, "passed": false, "step": step, "run": _chain_tag}), "warbands step %d marker initialized" % step)

func _save_warbands_step(tree: SceneTree, checkpoint: RefCounted, step: int, rng: RandomNumberGenerator, extra: Dictionary = {}) -> void:
	if fails > 0: return
	if not await _drain(tree): return
	if fails > 0: return
	var heal_acc: float = float(Game._heal_acc)
	var ctx: Dictionary = (checkpoint.get("context") as Dictionary).duplicate(true)
	ctx["rng_state"] = int(rng.state)
	ctx["heal_acc"] = heal_acc
	var done_list: Array = []
	for item: String in completed:
		done_list.append(item)
	ctx["completed"] = done_list
	ctx["advanced"] = advanced
	ctx["checks"] = checks
	ctx["fails"] = 0
	ctx["passed"] = true
	ctx["step"] = step
	ctx["run"] = _chain_tag
	for key_var: Variant in extra.keys():
		var key: String = str(key_var)
		ctx[key] = extra[key]
	checkpoint.set("context", ctx)
	var ok: bool = bool(checkpoint.call("save_step", step))
	Game._heal_acc = heal_acc
	if not check(ok, "warbands checkpoint step %d saved" % step): return
	var saved_ctx: Dictionary = checkpoint.get("context")
	var path: String = str(checkpoint.call("_path", step))
	var receipt: Dictionary = {
		"complete": true, "passed": true, "fails": 0, "step": step, "run": _chain_tag,
		"chain_id": str(saved_ctx.get("chain_id", "")),
		"source": SpeedParts.source_stamp(),
		"save_sha256": FileAccess.get_sha256(path),
		"expected_sha256": FileAccess.get_sha256(path + ".expected"),
	}
	# Publish only after run() has checked its final deadline and terminal predicates.
	_pending_receipt = {"path": path + ".complete.json", "data": receipt}

func _load_warbands_step(checkpoint: RefCounted, step: int, rng: RandomNumberGenerator) -> Dictionary:
	var path: String = str(checkpoint.call("_path", step))
	var receipt: Dictionary = _read_receipt_json(path + ".complete.json")
	if not check(receipt.get("complete") == true and receipt.get("passed") == true and receipt.get("fails") == 0, "warbands predecessor step %d completed without failure" % step): return {}
	if not check(receipt.get("step") == step and str(receipt.get("run", "")) == _chain_tag and str(receipt.get("source", "")) == SpeedParts.source_stamp(), "warbands predecessor step %d matches current source and chain" % step): return {}
	if not check(str(receipt.get("save_sha256", "")) == FileAccess.get_sha256(path) and str(receipt.get("expected_sha256", "")) == FileAccess.get_sha256(path + ".expected"), "warbands predecessor step %d files match completion hashes" % step): return {}
	var first_path: String = str(checkpoint.call("_path", 0))
	var first_receipt: Dictionary = _read_receipt_json(first_path + ".complete.json")
	if not check(first_receipt.get("complete") == true and first_receipt.get("passed") == true and str(first_receipt.get("chain_id", "")) != "" and str(first_receipt.get("chain_id", "")) == str(receipt.get("chain_id", "")), "warbands predecessor step %d belongs to active setup chain" % step): return {}
	if not bool(checkpoint.call("load_step", step)):
		check(false, "warbands checkpoint step %d loaded" % step)
		return {}
	var ctx: Dictionary = checkpoint.get("context")
	if not check(ctx.get("passed") == true and int(ctx.get("fails", 1)) == 0 and int(ctx.get("step", -1)) == step, "warbands predecessor step %d context verified" % step): return {}
	rng.seed = 9
	rng.state = int(ctx["rng_state"])
	Game._heal_acc = float(ctx.get("heal_acc", 0.0))
	completed.clear()
	for item_var: Variant in ctx.get("completed", []):
		completed.append(str(item_var))
	advanced = float(ctx.get("advanced", 0.0))
	checks = int(ctx.get("checks", 0))
	fails += int(ctx.get("fails", 1))
	return ctx

func _scenario(tree: SceneTree, part: String, checkpoint: RefCounted) -> void:
	Game.settings["autosave"] = "off"
	var cache: String = DevTools.world_path(true)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9
	if part == "all":
		if not check(FileAccess.file_exists(cache), "PREREQUISITE missing cached native creatures world: " + cache): return
		var all_path: String = "user://test_warbands_r2_%d.json" % OS.get_process_id()
		if not check(await DevTools.start_world(tree, all_path, true), "native seed4242 one-day start world loaded"): return
		if not await _drain(tree): return
		if not check(int(Game.world.get("seed", 0)) == DevTools.WORLD_SEED and CampaignWorld.presim_total(Game) == 1
				and CampaignWorld.presim_left(Game) == 0 and Game.world.get("player_house", {}).is_empty()
				and Game.world.get("encounter", "") == "", "PREREQUISITE completed native seed4242 one-day unselected start"): return
		var all_tid: String = DevTools.choose_house(Game, func(choice: Dictionary) -> bool: return str(Game.world["towns"][choice["town_id"]]["faction"]) == "middle_kingdom")
		if not check(all_tid != "", "native onboarding spawns the party at its first chosen house"): return
		await _movement(tree, rng)
		if fails > 0: return
		completed.append("movement")
		await _interaction(tree, rng)
		if fails > 0: return
		completed.append("interaction")
		await _travel(tree)
		if fails > 0: return
		completed.append("travel")
		_weakening()
		if fails > 0: return
		completed.append("weakening")
		return
	var stage_index: int = PARTS.find(part)
	if stage_index < PARTS.size() - 1:
		if not _begin_warbands_step(checkpoint, stage_index): return
	if part == "setup":
		if not check(FileAccess.file_exists(cache), "PREREQUISITE missing cached native creatures world: " + cache): return
		var path: String = "user://test_warbands_r2_%d.json" % OS.get_process_id()
		if not check(await DevTools.start_world(tree, path, true), "native seed4242 one-day start world loaded"): return
		if not await _drain(tree): return
		if not check(int(Game.world.get("seed", 0)) == DevTools.WORLD_SEED and CampaignWorld.presim_total(Game) == 1
				and CampaignWorld.presim_left(Game) == 0 and Game.world.get("player_house", {}).is_empty()
				and Game.world.get("encounter", "") == "", "PREREQUISITE completed native seed4242 one-day unselected start"): return
		var tid: String = DevTools.choose_house(Game, func(choice: Dictionary) -> bool: return str(Game.world["towns"][choice["town_id"]]["faction"]) == "middle_kingdom")
		if not check(tid != "", "native onboarding spawns the party at its first chosen house"): return
		await _save_warbands_step(tree, checkpoint, 0, rng)
		return
	if part == "movement1":
		if not check(FileAccess.file_exists(cache), "PREREQUISITE missing cached native creatures world: " + cache): return
		var ctx0: Dictionary = _load_warbands_step(checkpoint, 0, rng)
		if ctx0.is_empty() or fails > 0: return
		if not check(completed.is_empty(), "movement1 begins after setup before cases complete"): return
		var move_state1: Dictionary = _movement_begin(rng)
		if move_state1.is_empty() or fails > 0: return
		if not await _movement_steps(tree, move_state1, MOVEMENT_PART_STEPS): return
		await _save_warbands_step(tree, checkpoint, 1, rng, {"move_state": move_state1})
		return
	if part in ["movement2", "movement3", "movement4"]:
		var prev_step: int = stage_index - 1
		var ctx_m: Dictionary = _load_warbands_step(checkpoint, prev_step, rng)
		if ctx_m.is_empty() or fails > 0: return
		var move_state: Dictionary = (ctx_m.get("move_state", {}) as Dictionary).duplicate(true)
		var expected_done: int = prev_step * MOVEMENT_PART_STEPS
		if not check(completed.is_empty() and int(move_state.get("steps_done", -1)) == expected_done
				and absf(Game.day - float(move_state.get("day0", -100.0)) - float(expected_done) * 0.05) < 1.0e-9,
				"%s resumes exact movement progress at step %d" % [part, expected_done]): return
		if not await _movement_steps(tree, move_state, MOVEMENT_PART_STEPS): return
		if part == "movement4":
			_movement_finish(move_state)
			if fails > 0: return
			completed.append("movement")
			await _save_warbands_step(tree, checkpoint, 4, rng)
		else:
			await _save_warbands_step(tree, checkpoint, stage_index, rng, {"move_state": move_state})
		return
	if part == "interaction":
		var ctx4: Dictionary = _load_warbands_step(checkpoint, 4, rng)
		if ctx4.is_empty() or fails > 0: return
		if not check(completed == ["movement"], "interaction resumes completed movement"): return
		await _interaction(tree, rng)
		if fails > 0: return
		completed.append("interaction")
		await _save_warbands_step(tree, checkpoint, 5, rng)
		return
	if part == "travel_out":
		var ctx5: Dictionary = _load_warbands_step(checkpoint, 5, rng)
		if ctx5.is_empty() or fails > 0: return
		if not check(completed == ["movement", "interaction"], "travel_out resumes completed interaction"): return
		var travel_state: Dictionary = await _travel_out(tree)
		if travel_state.is_empty() or fails > 0: return
		await _save_warbands_step(tree, checkpoint, 6, rng, {"travel_state": travel_state})
		return
	if part == "travel_back":
		var ctx6: Dictionary = _load_warbands_step(checkpoint, 6, rng)
		if ctx6.is_empty() or fails > 0: return
		if not check(completed == ["movement", "interaction"], "travel_back resumes completed outward travel"): return
		var travel_state_back: Dictionary = (ctx6.get("travel_state", {}) as Dictionary).duplicate(true)
		if not check(not travel_state_back.is_empty(), "travel_back has outward travel observations"): return
		await _travel_back(tree, travel_state_back)
		if fails > 0: return
		completed.append("travel")
		await _save_warbands_step(tree, checkpoint, 7, rng)
		return
	if part == "weakening":
		var ctx7: Dictionary = _load_warbands_step(checkpoint, 7, rng)
		if ctx7.is_empty() or fails > 0: return
		if not check(completed == ["movement", "interaction", "travel"], "weakening resumes completed travel"): return
		_weakening()
		if fails > 0: return
		completed.append("weakening")

func run(tree: SceneTree) -> int:
	fails = 0
	checks = 0
	advanced = 0.0
	completed.clear()
	_pending_receipt.clear()
	started = Time.get_ticks_msec()
	if not check(DisplayServer.get_name() == "headless" and Game.main == null, "PREREQUISITE isolated headless runner"): return fails
	var part: String = _select_part()
	if part == "":
		return fails
	var keep_save: String = Game.SAVE_PATH
	var keep_heal_acc: float = float(Game._heal_acc)
	var had_autosave: bool = Game.settings.has("autosave")
	var keep_autosave: Variant = Game.settings.get("autosave", null)
	var case_name: String = "campaign_warbands_r4" + (("_" + _chain_tag) if _chain_tag != "" else "")
	var checkpoint: RefCounted = SpeedCheckpoint.new(case_name)
	await _scenario(tree, part, checkpoint)
	Game.SAVE_PATH = keep_save
	Game._heal_acc = keep_heal_acc
	if had_autosave:
		Game.settings["autosave"] = keep_autosave
	else:
		Game.settings.erase("autosave")
	_budget()
	var all_cases: bool = completed == ["movement", "interaction", "travel", "weakening"] and fails == 0
	if fails == 0 and part in ["weakening", "all"]:
		check(all_cases, "every original case completed in the default entry point")
	if fails == 0 and not _pending_receipt.is_empty():
		check(_write_receipt_json(str(_pending_receipt["path"]), _pending_receipt["data"]), "warbands verified step completion receipt written")
	print("WARBANDS_V100_R2 cases=%s checks=%d fails=%d elapsed_ms=%d campaign_days=%.6f all_cases_complete=%s" %
		[completed, checks, fails, Time.get_ticks_msec() - started, advanced, str(all_cases)])
	return fails
