extends RefCounted
const CohortAccounts = preload("res://tests/fixtures/cohort_accounts_v100.gd")
## Registered professional guards from an ordinary generated campaign only.
## Cohorts may name an existing anonymous worker during death-time reassignment.
## Serial parts retain the complete matrix and the native killed-guard roundtrip.
const CAUSES := ["sickness", "starved", "childbirth"]
const REQUIRED_CULTURES := ["dark_elf", "dwarf", "goblin", "high_elf", "middle", "moon_elf", "northern", "orc"]
const PARTS := ["generate", "prepare", "sickness-a", "sickness-b", "sickness-c",
	"starved-a", "starved-b", "starved-c", "childbirth-a", "childbirth-b", "childbirth-c", "roundtrip"]
var checks := 0
var fails := 0
var cases := 0
var original_save := ""
var base_save := ""
var killed_save := ""
var generated_save := ""
var progress_save := ""
var progress_oracle := ""
var receipt_path := ""
var oracle_path := ""
var part := ""
var run_id := ""
var source := ""
var started_msec := 0
var state: Dictionary = {}
var claimed := false
var case_cultures: Array = []
var error_counter: Object

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func near(a: float, b: float, message: String) -> void:
	check(absf(a - b) < 0.00001, "%s (%.9f versus %.9f)" % [message, a, b])

func identity(e: Dictionary, omit: int = -1) -> Dictionary:
	var out := {}
	var uids := {}
	for f in e["fams"]:
		for group in ["pp", "kp"]:
			for p in f.get(group, []):
				if int(p[0]) == omit: continue
				# Kinship, work history and sickness may legitimately change at death.
				var pid := str(int(p[0]))
				var uid := String(Persons.g(p, Persons.PERSON_UID, ""))
				check(not out.has(pid) and uid != "" and not uids.has(uid), "living register has unique PIDs and stable person UIDs")
				uids[uid] = true
				out[pid] = [int(f["id"]), p[1], p[2], p[3], p[4], p[5], p[6], Persons.g(p, 7, ""),
					uid, Persons.g(p, Persons.HOUSE_UID, ""), Persons.g(p, Persons.RACE, ""), Persons.person_race(e, f, p)]
	return out

func anonymous_bins(e: Dictionary) -> Dictionary:
	var out := {}
	for f in e["fams"]:
		out[str(int(f["id"]))] = f.get("age_bins", {}).duplicate(true)
	return out

## Capture anonymous residents' known identity anchors BEFORE native death.
func promotion_origin(e: Dictionary, f: Dictionary) -> Dictionary:
	var eligible := {}
	var counted_day := float(f.get("population_year", floor(Game.day / People.year_days()))) * People.year_days()
	for key in f.get("age_bins", {}):
		var current := Population.bin_category(e, f, String(key), Game.day)
		var counted := Population.bin_category(e, f, String(key), counted_day)
		if current < 2 and counted == current and int(f["age_bins"][key]) > 0:
			eligible[key] = int(f["age_bins"][key])
	return {"fid": int(f["id"]), "house": String(f.get("founding_house_uid", "")),
		"race": Persons.family_race(e, f), "scope": String(e.get("identity_scope", "")),
		"cohort": Population.is_cohort(f), "eligible": eligible}

## Preserve every old named person exactly, including raw/effective race.
## New identities must consume distinct, already-counted adult slots in this house.
func survivors_preserved(e: Dictionary, before: Dictionary, bins: Dictionary, first_pid: int, origin: Dictionary, dead_pid: int, label: String) -> bool:
	var after := identity(e)
	var fid := int(origin["fid"])
	var family: Dictionary = e["fams"][fid]
	var ok := not after.has(str(dead_pid))
	# Empty personal race overrides inherit the CAPTURED household race.
	# Also reject a changed household anchor, which would alter inherited biology.
	if String(family.get("founding_house_uid", "")) != String(origin["house"]) or Persons.family_race(e, family) != String(origin["race"]):
		printerr("IDENTITY ", label, " household/race anchor changed")
		ok = false
	for pid in before:
		if not after.has(pid) or after[pid] != before[pid]:
			printerr("IDENTITY ", label, " pid=", pid, " before=", before[pid], " after=", after.get(pid, []))
			ok = false
	var remaining: Dictionary = bins.duplicate(true)
	var eligible: Dictionary = origin["eligible"].duplicate(true)
	var added := 0
	for pid in after:
		if before.has(pid): continue
		added += 1
		var row: Array = after[pid]
		var birth_year := int(round(float(row[3]) / People.year_days()))
		var key := "%d:%d" % [int(row[2]), birth_year]
		var pool: Dictionary = remaining.get(str(fid), {})
		var fresh := int(pid) >= first_pid and int(pid) < int(e["next_pid"])
		var adult := int(row[0]) == fid and String(row[4]) == "" and int(row[5]) == -1 and int(row[6]) == 0
		var exact_birth := float(row[3]) == float(birth_year) * People.year_days()
		var uid := "person:%s:%d" % [origin["scope"], int(pid)]
		var race := String(row[10])
		if race == "": race = String(origin["race"])
		var anchors := String(origin["house"]) != "" and String(row[9]) == String(origin["house"]) and String(origin["race"]) != "" and race == String(origin["race"]) and String(row[11]) == String(origin["race"])
		if not fresh or not adult or not exact_birth or String(row[8]) != uid or not anchors or not bool(origin["cohort"]) or int(pool.get(key, 0)) <= 0 or int(eligible.get(key, 0)) <= 0:
			printerr("IDENTITY ", label, " unexplained new pid=", pid, " row=", row, " anonymous bin=", key, " origin=", origin)
			ok = false
			continue
		pool[key] = int(pool[key]) - 1
		eligible[key] = int(eligible[key]) - 1
		if int(pool[key]) == 0: pool.erase(key)
	# Unique new PIDs inside this exact interval must fill it without gaps.
	if int(e["next_pid"]) != first_pid + added: ok = false
	if anonymous_bins(e) != remaining:
		printerr("IDENTITY ", label, " anonymous bins do not match exact new-person debits")
		ok = false
	return ok

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= 0.000001 + 0.0000000001 * maxf(absf(float(a)), absf(float(b)))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not equivalent(a[i], b[i]): return false
		return true
	return a == b

func dated_ownership(e: Dictionary) -> Dictionary:
	var out: Dictionary = e.get("harvest_book", {}).duplicate(true)
	# The real loader rebuilds derived balances and household food reserves.
	# Dates, production sources, owned quantities and pending receipts stay real.
	out.erase("balances")
	for rows in out.get("lots", {}).values():
		for row in rows: row.erase("reserve")
	return out

func unit_present(uid: int) -> bool:
	for band in Game.world.get("warbands", {}).values():
		for u in band.get("units", []):
			if u is Unit and u.uid == uid: return true
	return false

func registered_guards(f: Dictionary) -> int:
	var n := 0
	for p in f.get("pp", []):
		if String(p[4]) == "guard": n += 1
	return n

func labour(e: Dictionary, label: String) -> void:
	var jobs := {}
	var population := 0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		var home := {}
		var registered: int = f.get("kp", []).size()
		for p in f.get("pp", []):
			if not String(p[4]) in Persons.AWAY: registered += 1
			if int(p[6]) == 0 and String(p[4]) in ["", "hire", "reserve"]: home[int(p[0])] = true
		var anonymous: Array[int] = CohortAccounts.bins(e, f)
		var anonymous_adults: int = anonymous[0] + anonymous[1]
		for count: int in anonymous:
			registered += count
		var available := maxi(0, Families.adults(f) - Families.serving(f))
		var assigned: int = int(f.get("hands", 0)) + int(f.get("idle", 0)) + f.get("keeps", []).size()
		for bid in f.get("jobs", {}):
			var n := int(f["jobs"][bid]); assigned += n
			jobs[int(bid)] = int(jobs.get(int(bid), 0)) + n
		for n in f.get("cj", {}).values(): assigned += int(n)
		check(available == home.size() + anonymous_adults, label + ": civilian register and anonymous bins equal available adult capacity")
		check(assigned == available, label + ": adult assignments cover capacity exactly once")
		var work := Persons.work(e, f)
		var work_adults := 0
		for p in f.get("pp", []):
			if int(p[6]) != 0: continue
			var pid := int(p[0])
			check(work.has(pid) == home.has(pid), label + ": native work includes exactly eligible civilian identities")
			if work.has(pid): work_adults += 1
		check(work_adults + anonymous_adults == available, label + ": native named work and anonymous slots equal available capacity")
		check(registered == Families.people(f), label + ": register population remains physical")
		population += Families.people(f)
	for b in e["biz"]:
		check(int(jobs.get(int(b["id"]), 0)) == int(b["workers"]), label + ": employer workers equal household job records")
	check(population == int(e["pop"]), label + ": town population equals surviving family rows")
	check(Census.adds_up(Census.balance(e)), label + ": native current census balance")

func candidates(cause: String) -> Dictionary:
	var out := {}
	var tids: Array = Game.world.get("town_guards", {}).keys(); tids.sort()
	for tid in tids:
		var town: Dictionary = Game.world["towns"][tid]
		var e: Dictionary = town["econ"]
		var culture := String(e["culture"])
		if out.has(culture): continue
		var band := TownDefence.guard_band(Game, String(tid))
		if not band.get("professional", false): continue
		for u in band.get("units", []):
			if not u is Unit or u.dead or u.family < 0 or u.family >= e["fams"].size(): continue
			var f: Dictionary = e["fams"][u.family]
			var p := Persons.by_uid(f, u.uid)
			if p.is_empty() or String(p[4]) != "guard" or int(p[6]) != 0: continue
			if cause == "childbirth" and int(p[2]) != 1: continue
			out[culture] = {"town": String(tid), "family": u.family, "pid": int(p[0]), "uid": u.uid}
			break
	return out

func death(row: Dictionary, culture: String, cause: String) -> Dictionary:
	var town: Dictionary = Game.world["towns"][row["town"]]
	var e: Dictionary = town["econ"]
	var f: Dictionary = e["fams"][int(row["family"])]
	var p := Persons.by_uid(f, int(row["uid"]))
	var unit: Unit = null
	for u in TownDefence.guards(Game, String(row["town"])):
		if u.uid == int(row["uid"]): unit = u; break
	var label := "%s %s" % [culture, cause]
	check(unit != null and not p.is_empty(), label + ": selected real guard exists at native death boundary")
	if unit == null or p.is_empty(): return {}
	labour(e, label + " before")
	var before_people := Families.people(f)
	var before_adults := Families.adults(f)
	var before_pop := int(e["pop"])
	var before_town_adults := int(e["adults"])
	var before_guard := int(f.get("serve", {}).get("guard", 0))
	check(before_guard == registered_guards(f), label + ": opening guard places match actual registered guards")
	check(Army.state(Game.world)["roll"].has(str(int(row["uid"]))), label + ": selected real guard has an Army roll entry")
	var before_deaths := Census.sum(Census.current(e)["deaths"])
	var before_total := int(Census._book(e).get("dt", 0))
	var before_stats := int(e["stats"].get("deaths", 0))
	var survivors := identity(e, int(p[0]))
	var bins := anonymous_bins(e)
	var origin := promotion_origin(e, f)
	var first_pid := int(e["next_pid"])
	var harvest: Dictionary = e.get("harvest_book", {}).duplicate(true)
	var cash := Barge.holdings(Game)
	var town_cash := TownEcon.town_gold(e)
	Sickness.kill(Game, town, f, p, Game.day, cause, "guard death regression")
	cases += 1
	check(Families.people(f) == before_people - 1 and Families.adults(f) == before_adults - 1, label + ": one actual adult leaves its family row")
	check(int(e["pop"]) == before_pop - 1 and int(e["adults"]) == before_town_adults - 1, label + ": one actual adult leaves town counts")
	check(int(f.get("serve", {}).get("guard", 0)) == before_guard - 1, label + ": native death releases exactly one guard service place")
	check(int(f.get("serve", {}).get("guard", 0)) == registered_guards(f), label + ": guard count matches surviving registered guards")
	check(unit.dead and not unit_present(int(row["uid"])), label + ": actual Unit is dead and removed from its force")
	check(not Army.state(Game.world)["roll"].has(str(int(row["uid"]))), label + ": dead guard leaves Army roll")
	check(Persons.by_pid(f, int(row["pid"])).is_empty(), label + ": deceased identity leaves living register")
	check(survivors_preserved(e, survivors, bins, first_pid, origin, int(row["pid"]), label), label + ": every surviving identity is preserved")
	check(e.get("harvest_book", {}) == harvest, label + ": native death leaves dated harvest book unchanged")
	near(Barge.holdings(Game), cash, label + ": native death creates or destroys no ledger coins")
	near(TownEcon.town_gold(e), town_cash, label + ": reassignment conserves existing town coins")
	# Exercise the normal cleanup readers after removal: they cannot book it twice.
	Army.sweep(Game)
	Persons.sweep_town(Game, town, Persons.live_uids(Game))
	check(Census.sum(Census.current(e)["deaths"]) == before_deaths + 1 and int(Census._book(e)["dt"]) == before_total + 1, label + ": census records exactly one counted death")
	check(int(e["stats"]["deaths"]) == before_stats + 1, label + ": native death statistic increases once")
	var entries := 0
	for d in Census._book(e)["deaths"]:
		if int(d[1]) != int(row["pid"]): continue
		entries += 1
		check(String(d[5]) == cause and float(d[0]) == Game.day and int(d[9]) == 1, label + ": death retains actual cause, day and census inclusion")
	check(entries == 1, label + ": deceased PID has exactly one census death entry")
	labour(e, label + " after")
	print("GUARD DEATH case culture=", culture, " cause=", cause, " town=", row["town"], " family=", row["family"], " pid=", row["pid"])
	return row

func save_at(path: String) -> bool:
	Game.SAVE_PATH = path
	var saved := Game.save_game()
	var exists := FileAccess.file_exists(path)
	check(saved and exists, "native isolated guard checkpoint is saved")
	return saved and exists

## Each split continues the SAME cause's native world, not a fresh partial case set.
## Keep a pre-save oracle for each handoff; sickness-c retains the final roundtrip.
func checkpoint(row: Dictionary, path: String, sidecar: String) -> bool:
	var e: Dictionary = Game.world["towns"][row["town"]]["econ"]
	var expected := {"row": row, "identity": identity(e), "book": dated_ownership(e),
		"pop": int(e["pop"]), "adults": int(e["adults"]), "deaths": int(Census._book(e)["dt"]),
		"guards": int(e["fams"][int(row["family"])].get("serve", {}).get("guard", 0)), "cash": Barge.holdings(Game)}
	# A Variant sidecar preserves the pre-save oracle's exact numeric keys/types.
	var file := FileAccess.open(sidecar, FileAccess.WRITE)
	check(file != null, "pre-save roundtrip oracle opens")
	if file == null: return false
	file.store_var(expected)
	file.flush()
	check(file.get_error() == OK, "pre-save roundtrip oracle is written")
	var ok := file.get_error() == OK
	file.close()
	if not ok: return false
	return save_at(path)

func roundtrip(expected: Dictionary, path: String) -> void:
	var row: Dictionary = expected["row"]
	Game.SAVE_PATH = path
	var loaded := Game.load_game()
	check(loaded, "native killed-guard checkpoint loads")
	if not loaded: return
	var e: Dictionary = Game.world["towns"][row["town"]]["econ"]
	var f: Dictionary = e["fams"][int(row["family"])]
	var guards := int(expected["guards"])
	check(int(e["pop"]) == int(expected["pop"]) and int(e["adults"]) == int(expected["adults"]) and int(Census._book(e)["dt"]) == int(expected["deaths"]), "killed-guard load preserves actual counts and records no second death")
	check(Persons.by_pid(f, int(row["pid"])).is_empty() and not unit_present(int(row["uid"])), "killed guard cannot return through register or force load")
	check(not Army.state(Game.world)["roll"].has(str(int(row["uid"]))), "killed guard cannot return through Army roll load")
	check(int(f.get("serve", {}).get("guard", 0)) == guards and guards == registered_guards(f), "native load preserves absence of phantom guard service")
	check(equivalent(identity(e), expected["identity"]), "native save/load preserves surviving identities")
	check(equivalent(dated_ownership(e), expected["book"]), "native save/load preserves dated ownership and pending harvest receipts")
	check(absf(Barge.holdings(Game) - float(expected["cash"])) < 1.0, "native save/load conserves global coins at unchanged ledger tolerance")
	labour(e, "killed-guard loaded boundary")

func option(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return arg.substr(prefix.length())
	return ""

## Bind cross-process fixtures to the exact GDScript/data tree, not just a version.
func source_stamp() -> String:
	var pending: Array[String] = ["res://"]
	var rows := PackedStringArray()
	while not pending.is_empty():
		var folder: String = pending.pop_back()
		for sub in DirAccess.get_directories_at(folder):
			if not sub.begins_with("."): pending.append(folder.path_join(sub))
		for file in DirAccess.get_files_at(folder):
			if file.get_extension() in ["gd", "json", "godot"]:
				var path := folder.path_join(file)
				rows.append(path + ":" + FileAccess.get_sha256(path))
	rows.sort()
	return "\n".join(rows).sha256_text()

func write_receipt(data: Dictionary) -> bool:
	data["source"] = source
	data["run"] = run_id
	var file := FileAccess.open(receipt_path, FileAccess.WRITE)
	check(file != null, "isolated part receipt opens")
	if file == null: return false
	file.store_string(JSON.stringify(data, "", false, true))
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	check(ok, "isolated part receipt is written")
	return ok

func hash_matches(path: String, expected: String) -> bool:
	return expected != "" and FileAccess.file_exists(path) and FileAccess.get_sha256(path) == expected

func read_receipt() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	var valid := data is Dictionary
	if valid:
		valid = String(data.get("source", "")) == source and String(data.get("run", "")) == run_id
		valid = valid and String(data.get("inflight", "")) == "" and int(data.get("next", -1)) == PARTS.find(part)
		valid = valid and data.get("done") is Dictionary and not bool(data.get("complete", false))
	if valid:
		var done: Dictionary = data["done"]
		valid = done.size() == PARTS.find(part)
		for i in PARTS.find(part):
			valid = valid and done.get(PARTS[i]) is Dictionary
			if done.get(PARTS[i]) is Dictionary:
				valid = valid and bool(done[PARTS[i]].get("passed", false))
		if part == "prepare":
			valid = valid and hash_matches(generated_save, String(data.get("generated_sha", "")))
		else:
			valid = valid and data.get("pools") is Dictionary and hash_matches(base_save, String(data.get("base_sha", "")))
	check(valid, "same-source checkpoint requires every predecessor; failed, interrupted, stale or out-of-order parts refuse")
	return data if valid else {}

func load_oracle(path: String, digest: String) -> Dictionary:
	if not hash_matches(path, digest):
		check(false, "native checkpoint requires its exact pre-save oracle")
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var expected: Variant = file.get_var() if file != null else null
	if file != null: file.close()
	check(expected is Dictionary and not expected.is_empty(), "pre-save oracle loads with exact native values")
	return expected if expected is Dictionary else {}

## Split generation from day one rather than guessing they jointly fit one row.
## Native sliced generation consumes the same seed and generates every town.
func generate(tree: SceneTree) -> void:
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Game.SAVE_PATH = generated_save
	var generation := Game.new_game_begin(901)
	while not Game.new_game_slice(generation, 8000):
		if Time.get_ticks_msec() >= 50000:
			check(false, "native generation exceeded this part's admission budget")
			return
		await tree.process_frame
	Game.new_game_finalize()
	check(Game.day == 0.0 and not Game.world.get("towns", {}).is_empty(), "ordinary Normal seed901 generation completes")
	if fails == 0 and save_at(generated_save):
		state["generated_sha"] = FileAccess.get_sha256(generated_save)

func prepare() -> void:
	Game.SAVE_PATH = generated_save
	var loaded := Game.load_game()
	check(loaded and Game.day == 0.0, "native generated-world checkpoint loads before actual day1")
	if not loaded or fails > 0: return
	Game.advance_time(1.0, true)
	check(Game.day == 1.0 and (Game.world.get("work", []) as Array).is_empty(), "ordinary campaign completes actual day1 guard instantiation")
	var pools := {}
	for cause in CAUSES:
		var pool := candidates(String(cause))
		check(not pool.is_empty(), String(cause) + ": at least one actual registered eligible professional guard")
		for culture in REQUIRED_CULTURES:
			check(pool.has(culture), "%s %s: original race x cause coverage remains available" % [culture, cause])
		pools[cause] = pool
	if fails == 0 and save_at(base_save):
		state["base_sha"] = FileAccess.get_sha256(base_save)
		state["pools"] = pools

func cultures_for(cause: String, shard: String) -> Array:
	var cultures: Array = state["pools"][cause].keys()
	cultures.sort()
	var width := ceili(float(cultures.size()) / 3.0)
	var first := ["a", "b", "c"].find(shard) * width
	return cultures.slice(first, mini(first + width, cultures.size()))

func cause_part() -> void:
	var cause := part.get_slice("-", 0)
	var shard := part.get_slice("-", 1)
	if shard == "a":
		Game.SAVE_PATH = base_save
		check(Game.load_game(), "actual generated control checkpoint loads")
	else:
		check(hash_matches(progress_save, String(state.get("progress_sha", ""))), "preceding race group's native world is intact")
		if fails > 0: return
		var expected := load_oracle(progress_oracle, String(state.get("progress_oracle_sha", "")))
		if fails == 0: roundtrip(expected, progress_save)
	if fails > 0: return
	var pool := candidates(cause)
	var selected := cultures_for(cause, shard)
	check(not selected.is_empty(), part + ": this registered part has real cases")
	# Already killed cultures can now nominate another guard. Only untouched
	# selected guards must equal the original native candidates exactly.
	for culture in selected:
		check(pool.has(culture) and equivalent(pool.get(culture), state["pools"][cause][culture]), "%s %s: native load retains the prepared eligible guard" % [culture, cause])
	if fails > 0: return
	var last := {}
	for culture in selected:
		last = death(pool[culture], String(culture), cause)
		if not last.is_empty(): case_cultures.append(culture)
	check(cases == selected.size() and case_cultures == selected, part + ": every assigned race case reaches native death")
	print("GUARD DEATH coverage part=", part, " actual_eligible_cultures=", selected)
	if fails > 0 or last.is_empty(): return
	if shard != "c":
		if checkpoint(last, progress_save, progress_oracle):
			state["progress_sha"] = FileAccess.get_sha256(progress_save)
			state["progress_oracle_sha"] = FileAccess.get_sha256(progress_oracle)
	elif cause == "sickness":
		if checkpoint(last, killed_save, oracle_path):
			state["killed_sha"] = FileAccess.get_sha256(killed_save)
			state["oracle_sha"] = FileAccess.get_sha256(oracle_path)

func complete_matrix() -> void:
	var total := 0
	for cause in CAUSES:
		var seen := []
		for shard in ["a", "b", "c"]:
			var key := "%s-%s" % [cause, shard]
			var expected := cultures_for(cause, shard)
			var receipt: Dictionary = state["done"].get(key, {})
			check(bool(receipt.get("passed", false)) and int(receipt.get("cases", -1)) == expected.size() and receipt.get("cultures", []) == expected, key + ": exact successful native race-case receipt is required")
			seen.append_array(receipt.get("cultures", []))
		var all: Array = state["pools"][cause].keys()
		all.sort()
		check(seen == all, String(cause) + ": every naturally eligible culture is covered exactly once")
		for culture in REQUIRED_CULTURES:
			check(seen.has(culture), "%s %s: original required race x cause executed" % [culture, cause])
		total += seen.size()
	check(total >= REQUIRED_CULTURES.size() * CAUSES.size(), "complete original 24-case matrix, plus any additional native candidates")
	check(hash_matches(killed_save, String(state.get("killed_sha", ""))), "killed checkpoint matches its pre-save identity and ownership oracle")
	if fails > 0: return
	var expected := load_oracle(oracle_path, String(state.get("oracle_sha", "")))
	if fails == 0: roundtrip(expected, killed_save)
	print("GUARD DEATH complete native cases=", total)

func finish() -> int:
	Game.wait_save()
	# Absolute engine ticks include startup/script loading before run(), unlike r1.
	# Full OS-process time still needs external measurement; this is not a hard
	# interrupt for synchronous native calls, and no unmeasured pass is implied.
	check(Time.get_ticks_msec() < 55000, "guard-death part stays below 55 seconds since engine initialization")
	if error_counter != null:
		check(int(error_counter.call("total")) == 0, "no runner-counted script error can publish a successful predecessor")
	if claimed and fails == 0:
		state["done"][part] = {"passed": true, "cases": cases, "cultures": case_cultures, "engine_ms": Time.get_ticks_msec()}
		state["next"] = PARTS.find(part) + 1
		state["inflight"] = ""
		state["complete"] = part == "roundtrip"
		write_receipt(state)
	# Failed work leaves the on-disk inflight marker, so later rows refuse.
	# Isolated fixtures/receipts remain as evidence; never delete a user's files.
	Game.SAVE_PATH = original_save
	print("GUARD DEATH v046 part=", part, " cases=", cases, " checks=", checks, " failures=", fails, " elapsed_ms=", Time.get_ticks_msec() - started_msec)
	return fails

func run(tree: SceneTree) -> int:
	started_msec = Time.get_ticks_msec()
	original_save = Game.SAVE_PATH
	error_counter = tree.current_scene.get("script_errors")
	check(error_counter != null and error_counter.has_method("total"), "serial parts require the existing error-counting runner")
	part = option("--guard-death-part=")
	run_id = option("--guard-death-run=")
	check(part in PARTS and run_id.is_valid_identifier(), "pass a registered guard-death part and the same fresh --guard-death-run=identifier for ALL twelve serial rows")
	if fails > 0: return finish()
	var prefix := "user://test_guard_death_v046_" + run_id
	generated_save = prefix + "_generated.json"
	base_save = prefix + "_base.json"
	killed_save = prefix + "_killed.json"
	progress_save = prefix + "_progress.json"
	progress_oracle = prefix + "_progress.dat"
	receipt_path = prefix + "_receipt.json"
	oracle_path = prefix + "_oracle.dat"
	source = source_stamp()
	if part == "generate":
		for path in [receipt_path, generated_save, base_save, killed_save, progress_save, progress_oracle, oracle_path]:
			check(not FileAccess.file_exists(path), "fresh run identifier must not reuse any earlier artifact")
		if fails > 0: return finish()
		state = {"next": 0, "done": {}, "inflight": part, "complete": false}
	else:
		state = read_receipt()
		if state.is_empty(): return finish()
		state["inflight"] = part
	# Claim BEFORE any load/generation/death: a crashed process cannot leave a pass.
	if not write_receipt(state): return finish()
	claimed = true
	if part == "generate":
		await generate(tree)
	elif part == "prepare":
		prepare()
	elif part == "roundtrip":
		complete_matrix()
	else:
		cause_part()
	return finish()
