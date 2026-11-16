extends RefCounted
## Real v0.030 campaign through the actual loader; every town is checked.
## No v0.031 commit exists; v0.030 has the same schema-1 household land/herd,
## plot ownership and work-assignment fields, without assigned_need/assigned_crop_year.
## It also covers all seven legacy cultures; reuse the authentic v0.030 fixture.

const LEGACY_V030_CULTURES := ["middle", "northern", "eastern", "orc", "goblin", "moon_elf", "dwarf"]
const NEW_V080_CULTURES := ["high_elf", "dark_elf"]

var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func quantities(values: Dictionary) -> Dictionary:
	# The raw JSON checkpoint has floats; the actual loader restores integer
	# counts. Compare the same quantities without treating that type repair as
	# a physical change, and without rounding any value away.
	var out := {}
	for key in values: out[String(key)] = float(values[key])
	return out

func physical(e: Dictionary) -> Dictionary:
	var owners := []
	for f in e["fams"]:
		owners.append([quantities(f["land"]), quantities(f["herd"]), int(f.get("ox", -1)), Families.people(f)])
	var plots: Dictionary = e.get("plots", {})
	var columns := {}
	for key in ["ac", "use", "sub", "own"]:
		var values := []
		for v in plots.get(key, []): values.append(int(v))
		columns[key] = values
	return {"owners": owners, "plots": columns, "barn": quantities(e["barn"]), "land": quantities(e["land"]), "territory": int(e["territory"])}

# v0.100: snapshot household work state and service rows before Game.load_game() so we can
# independently distinguish untouched legacy households from those deliberately reassigned by
# Academy.after_load / ServiceIdentity.after_load / Militia.trim_all and verify the migration rules on the latter.
func work_snapshot(e: Dictionary, f: Dictionary) -> Dictionary:
	var farm_id := int(f.get("farm", -1))
	var farm_cap := int(e["biz"][farm_id]["cap"]) if farm_id >= 0 and farm_id < (e["biz"] as Array).size() else -1
	var jobs := {}
	for k in f.get("jobs", {}):
		if int(f["jobs"][k]) > 0: jobs[int(k)] = int(f["jobs"][k])
	var cj := {}
	for k in f.get("cj", {}):
		if int(f["cj"][k]) > 0: cj[String(k)] = int(f["cj"][k])
	var keeps := []
	for k in f.get("keeps", []): keeps.append(int(k))
	return {"hands": int(f.get("hands", 0)), "farm": farm_id, "farm_cap": farm_cap, "idle": int(f.get("idle", 0)), "jobs": jobs, "cj": cj, "keeps": keeps}

# Predict Academy transitions from saved employer/keeper/register and research
# records, before loading. Neither work marker nor a changed job is evidence.
# Contract: docs/specs/next/02-steel-assay-house.md:56-59;
# test_academy_v089.gd:429-463,535-545 covers both kinds of release.
func pre_academy_state(w: Dictionary, town: Dictionary) -> Dictionary:
	var snapshot: Dictionary = {"business": -1, "idle": false, "reassigned": {}, "released": {}}
	var e: Dictionary = town["econ"]
	var b: Dictionary = Academy.biz_of(e)
	if b.is_empty():
		return snapshot
	var bid: int = int(b["id"])
	snapshot["business"] = bid
	var affected: Dictionary = snapshot["reassigned"]
	var released: Dictionary = snapshot["released"]
	var owner: int = int(b.get("owner", -1))
	if owner >= 0 and owner < (e["fams"] as Array).size():
		var operator_family: Dictionary = e["fams"][owner]
		for kept_bid: Variant in operator_family.get("keeps", []):
			if int(kept_bid) == bid:
				affected[int(operator_family["id"])] = true
	var idle_repair: bool = not bool(b.get("research_idle", false)) or int(b["cap"]) != 0 or int(b["workers"]) > 0
	# active_lines initializes missing research keys; keep that write off the fixture.
	var research_world: Dictionary = {"research": (w.get("research", {}) as Dictionary).duplicate(true)}
	snapshot["idle"] = idle_repair and Academy.active_lines(research_world, String(town.get("faction", e.get("faction", "")))).is_empty()
	# Registration repair precedes the idle decision and can change jobs/idle
	# without reassigning or writing work markers, even at an active house.
	var staff_e: Dictionary = e.duplicate(true)
	TownEcon._fix_ints(staff_e)
	var staff_b: Dictionary = Academy.biz_of(staff_e)
	var named: Dictionary = {}
	for pair: Array in Academy._staff(staff_e, staff_b):
		var staff_family: Dictionary = pair[0]
		var staff_id: int = int(staff_family["id"])
		named[staff_id] = int(named.get(staff_id, 0)) + 1
	for staff_family: Dictionary in staff_e["fams"]:
		if staff_family.get("gone", false) or staff_family.get("estate", false): continue
		var staff_id: int = int(staff_family["id"])
		var saved_places: int = int(staff_family["jobs"].get(str(bid), 0))
		if saved_places <= 0: continue
		var named_places: int = int(named.get(staff_id, 0))
		# A mixed cohort's named tail may also be removed by _release_unregistered.
		if saved_places > named_places and named_places > 0 and Population.is_cohort(staff_family):
			if Academy._named_places(Academy._prospective_places(staff_e, staff_family, staff_b, named_places), bid) != named_places:
				named_places = 0
		if saved_places > named_places:
			# Permit exactly the recorded Academy cut and its civilian idle balance.
			# Other employers, casual places, keeper places and farms stay exact.
			var released_work: Dictionary = work_snapshot(e, e["fams"][staff_id])
			var remaining_jobs: Dictionary = released_work["jobs"]
			if named_places > 0: remaining_jobs[bid] = named_places
			else: remaining_jobs.erase(bid)
			var assigned: int = int(released_work["hands"]) + (released_work["keeps"] as Array).size()
			for places: Variant in remaining_jobs.values(): assigned += int(places)
			for places: Variant in (released_work["cj"] as Dictionary).values(): assigned += int(places)
			released_work["idle"] = maxi(0, Families.adults(staff_family) - Families.serving(staff_family) - assigned)
			released[staff_id] = released_work
		# Only surviving registered staff reach _idle_house's explicit reassign.
		if bool(snapshot["idle"]) and named_places > 0:
			affected[staff_id] = true
	return snapshot

func pre_service_state(f: Dictionary, live_militia_uids: Dictionary) -> Dictionary:
	var mil_rows := {}
	for p in f.get("pp", []):
		if int(p[5]) >= 0 and String(p[4]) in ["reserve", "militia"] and live_militia_uids.has(int(p[5])):
			mil_rows[int(p[5])] = String(p[4])
	var non_militia_serve := 0
	var sv: Dictionary = f.get("serve", {})
	for k in sv:
		if String(k) != "militia":
			non_militia_serve += maxi(0, int(sv[k]))
	return {"serve_militia": int(sv.get("militia", 0)), "non_militia_serve": non_militia_serve, "mil_rows": mil_rows, "idle": int(f.get("idle", 0))}

func was_militia_trimmed(f: Dictionary, pre_svc: Dictionary, town_trimmed: bool) -> bool:
	if not town_trimmed:
		return false
	var current_mil := {}
	for p in f.get("pp", []):
		if int(p[5]) >= 0 and String(p[4]) in ["reserve", "militia"]:
			current_mil[int(p[5])] = String(p[4])
	for uid in pre_svc["mil_rows"]:
		if not current_mil.has(int(uid)):
			return true
	return false

func was_direct_service_migrated(f: Dictionary, pre_svc: Dictionary, town_trimmed: bool) -> bool:
	if int(f.get("serve", {}).get("militia", 0)) != int(pre_svc["serve_militia"]):
		return true
	return was_militia_trimmed(f, pre_svc, town_trimmed)

# v0.100: determine town-wide Militia.trim match_idle execution independently without inspecting f["assigned_need"].
func did_town_match_idle(e: Dictionary, pre_svc_map: Dictionary, pre_work_map: Dictionary, town_trimmed: bool) -> bool:
	if not town_trimmed:
		return false
	var any_touched := false
	var any_idle_job_changed := false
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		var fid := int(f["id"])
		var snap := work_snapshot(e, f)
		if was_militia_trimmed(f, pre_svc_map[fid], town_trimmed):
			any_touched = true
		if not was_direct_service_migrated(f, pre_svc_map[fid], town_trimmed) and int(pre_svc_map[fid]["idle"]) > 0:
			if snap["jobs"] != pre_work_map[fid]["jobs"] or snap["cj"] != pre_work_map[fid]["cj"]:
				any_idle_job_changed = true
	if not any_touched:
		return false
	if any_idle_job_changed:
		return true
	for b in e["biz"]:
		if Businesses.takeable(b, e) > 0:
			return true
	for job in e.get("cjcap", {}):
		if Families._available_casual(e, String(job)) > 0:
			return true
	return false

func was_load_service_migrated(f: Dictionary, pre_svc: Dictionary, town_trimmed: bool, town_match_idle: bool) -> bool:
	if was_direct_service_migrated(f, pre_svc, town_trimmed):
		return true
	if town_match_idle and int(pre_svc["idle"]) > 0:
		return true
	return false

func check_migrated_assignment(e: Dictionary, f: Dictionary, need: float, pre_svc: Dictionary) -> void:
	# v0.100: independently compute expected post-migration invariants without copying Families.reassign.
	var active_militia := 0
	for p in f.get("pp", []):
		if String(p[4]) == "militia" and int(p[5]) >= 0:
			active_militia += 1
	var sv: Dictionary = f.get("serve", {})
	var non_militia_now := 0
	for k in sv:
		if String(k) != "militia":
			non_militia_now += maxi(0, int(sv[k]))
	var serving := active_militia + int(pre_svc["non_militia_serve"])
	var avail_adults := maxi(0, int(f.get("m", 0)) + int(f.get("f", 0)) - serving)
	var assigned_adults := int(f.get("hands", 0)) + int(f.get("idle", 0)) + (f.get("keeps", []) as Array).size()
	for k in f.get("jobs", {}): assigned_adults += int(f["jobs"][k])
	for k in f.get("cj", {}): assigned_adults += int(f["cj"][k])
	var day := float(e.get("day", 0))
	var expected_year := 1 + (int(floor((day * 24.0 + 7.0) / 24.0)) / 30) / 4
	var work := Families.crop_work(f, e)
	var helpers := minf(need, Barge.helper_hands(e, f, day)) if need > 0.0 else 0.0
	var hneed := need + float(work["harvest"]) * (float(TownEcon.data()["barge"]["labour"]["harvest_hands"]) - 1.0)
	var gap := hneed - float(f.get("hands", 0)) - helpers
	var farm_id := int(f.get("farm", -1))
	var farm_cap_ok := (gap <= 0.7) if farm_id < 0 else (int(e["biz"][farm_id]["cap"]) == maxi(0, int(ceil(gap - 0.3))))
	check(int(sv.get("militia", 0)) == active_militia and non_militia_now == int(pre_svc["non_militia_serve"]), "load-migrated household militia count matches active militia person rows")
	check(assigned_adults == avail_adults and int(f.get("hands", 0)) >= 0 and int(f.get("idle", 0)) >= 0, "load-migrated household conserves available civilian adults")
	check(is_equal_approx(float(f.get("assigned_need", -1.0)), need) and int(f.get("assigned_crop_year", -1)) == expected_year and farm_cap_ok, "load-migrated household follows farm capacity and work marker migration rules")

func run(_tree: SceneTree) -> int:
	# v0.100: reuse bb-v030-save/game/tools/make_v030_checkpoint.gd's native save; keep the environment override.
	var path := OS.get_environment("LABOUR_LEGACY_SAVE")
	if path == "":
		path = ProjectSettings.globalize_path("res://tests/fixtures/harvest_legacy_v030_save.json")
	check(path != "" and FileAccess.file_exists(path), "actual delivered v0.030 checkpoint supplied")
	if path == "" or not FileAccess.file_exists(path): return fails
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved.has("world") and saved.has("day"), "fixture is a complete real campaign")
	if not saved.has("world"): return fails
	Game.world = Game._deserialize(saved["world"].duplicate(true)); Game.gold = int(saved["gold"])
	var coins := Barge.holdings(Game)
	var before := {}
	var pre_work := {}
	var pre_service := {}
	var pre_academy: Dictionary = {}
	var pre_militia_over_cap := {}
	var live_militia_uids := {}
	for wid in Game.world.get("warbands", {}):
		var wb: Dictionary = Game.world["warbands"][wid]
		if String(wb.get("kind", "")) != "militia": continue
		for u in wb.get("units", []):
			if u is Unit and not u.dead:
				live_militia_uids[u.uid] = true
	for tid in Game.world["towns"]:
		var town: Dictionary = Game.world["towns"][tid]
		if TownEcon.has_econ(town):
			var e0: Dictionary = town["econ"]
			before[tid] = physical(e0)
			pre_work[tid] = {}
			pre_service[tid] = {}
			pre_academy[tid] = pre_academy_state(Game.world, town)
			for f0 in e0["fams"]:
				if f0.get("gone", false) or f0.get("estate", false): continue
				var fid := int(f0["id"])
				pre_work[tid][fid] = work_snapshot(e0, f0)
				pre_service[tid][fid] = pre_service_state(f0, live_militia_uids)
			var mid := String(Game.world.get("militia", {}).get(tid, ""))
			var munits: Array = Game.world.get("warbands", {}).get(mid, {}).get("units", [])
			var mcap := 6 + 5 * clampi(int(town.get("size", 1)), 0, 4)
			pre_militia_over_cap[tid] = int(saved.get("militia_cap", 0)) < 1 and munits.size() > mcap
	var jobs: Array = Game.world.get("work", []).duplicate(true)
	Game._write_save(Game.SAVE_PATH, saved)
	check(Game.load_game(), "delivered v0.030 loads with the actual campaign loader")
	check(absf(Barge.holdings(Game) - coins) < 0.0001, "loading new work rules preserves all existing coins")
	check(Game.world.get("work", []) == jobs, "load preserves pending work without executing it")
	var cultures := {}
	for tid in before:
		var e: Dictionary = Game.world["towns"][tid]["econ"]
		var culture := String(e["culture"])
		cultures[culture] = int(cultures.get(culture, 0)) + 1
		check(physical(e) == before[tid], "load preserves every family's acres, livestock, population and physical food")
		var town_trimmed := bool(pre_militia_over_cap.get(tid, false))
		var town_match_idle := did_town_match_idle(e, pre_service[tid], pre_work[tid], town_trimmed)
		var academy_state: Dictionary = pre_academy[tid]
		if bool(academy_state["idle"]):
			var academy: Dictionary = e["biz"][int(academy_state["business"])]
			check(bool(academy.get("research_idle", false)) and int(academy["cap"]) == 0 and int(academy["workers"]) == 0, "completed/blocked loaded Academy has no paid places")
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false): continue
			var fid := int(f["id"])
			var day: float = f["last"]
			var need := Families.need_hands(f, e)
			check(need >= 0.0 and is_finite(need), "old physical fields and herds have finite real work requirements")
			# Academy layoffs/operator release are also deliberate native load migrations.
			# All other households keep the exact untouched-work assertion below.
			if bool(academy_state["idle"]):
				check(int(f.get("jobs", {}).get(str(int(academy_state["business"])), 0)) == 0, "idle loaded Academy retains no household paid jobs")
			if (academy_state["reassigned"] as Dictionary).has(fid) or was_load_service_migrated(f, pre_service[tid][fid], town_trimmed, town_match_idle):
				check(not Families.farm_capacity_stale(e, f) and not Families.assignments_stale(f), "load-migrated household has valid post-migration work markers")
				check_migrated_assignment(e, f, need, pre_service[tid][fid])
			elif (academy_state["released"] as Dictionary).has(fid):
				check(Families.farm_capacity_stale(e, f) and not f.has("assigned_need") and work_snapshot(e, f) == academy_state["released"][fid], "registration repair changes only Academy jobs and the exact civilian idle balance without fabricating work markers")
			else:
				check(Families.farm_capacity_stale(e, f) and not f.has("assigned_need") and work_snapshot(e, f) == pre_work[tid][fid], "old assignment has no fabricated new-rule marker before ordinary matching")
			Families.reassign(e, f)
			check(not Families.assignments_stale(f), "existing matcher assigns only actual available civilians")
			check(not Families.farm_capacity_stale(e, f), "existing matcher repairs old capacity and records current work need")
			check(float(f["last"]) == day, "work correction does not advance household spending or paydays")
		check(physical(e) == before[tid], "matching creates no land, people, livestock or stored crops")
	# v0.100: v0.030 had 7 cultures; v0.080+ added high_elf and dark_elf defaults in economy.json and migrated tables.
	var all_cultures: Dictionary = TownEcon.data()["cultures"]
	check(cultures.size() == LEGACY_V030_CULTURES.size(), "actual v0.030 checkpoint covers all 7 legacy economy cultures")
	for c in LEGACY_V030_CULTURES:
		var cd: Dictionary = all_cultures.get(c, {})
		check(int(cultures.get(c, 0)) > 0 and cd.has("race") and cd.has("household") and cd.has("home") and cd.has("ranks"), "legacy v0.030 culture %s survives in checkpoint with valid economy data" % c)
	check(all_cultures.size() == LEGACY_V030_CULTURES.size() + NEW_V080_CULTURES.size(), "registered economy cultures equal the 7 v0.030 cultures plus 2 v0.080+ elf cultures")
	for c in NEW_V080_CULTURES:
		var cd: Dictionary = all_cultures.get(c, {})
		check(not cultures.has(c) and String(cd.get("race", "")) == c and cd.has("household") and cd.has("home") and cd.has("ranks") and cd.has("research_name") and cd.has("research_lead") and TownEcon.data()["barge"]["tastes"].has(c) and TownEcon.data()["research"]["names"]["_race"].has(c) and TownEcon.data()["research"]["race_factor"].has(c), "new v0.080+ culture %s is present as valid default in economy and research data" % c)
	# Relations are diplo.pairs[key].rel; there is no top-level diplo.rel table.
	check(Game.world.get("research", {}).size() >= Game.world.get("factions", {}).size() and Game.world.get("diplo", {}).get("pairs", {}).size() >= Game.world.get("factions", {}).size(), "World.after_load populates migrated research and diplomacy tables")
	check(absf(Barge.holdings(Game) - coins) < 0.0001, "real owner funding and earned-wage settlement conserve existing world coins")
	# Once the legitimate legacy migrations and ordinary matching have completed,
	# a current save must preserve every work slot exactly, including the Academy families.
	var saved_work: Dictionary = {}
	for tid: Variant in before:
		var work_e: Dictionary = Game.world["towns"][tid]["econ"]
		var town_work: Dictionary = {}
		for saved_family: Dictionary in work_e["fams"]:
			if saved_family.get("gone", false) or saved_family.get("estate", false): continue
			town_work[int(saved_family["id"])] = work_snapshot(work_e, saved_family)
		saved_work[tid] = town_work
	Game.save_game(); check(Game.load_game(), "corrected assignments survive a real second load")
	check(absf(Barge.holdings(Game) - coins) < 0.0001, "second load preserves all real cash")
	for tid in before:
		var e: Dictionary = Game.world["towns"][tid]["econ"]
		check(physical(e) == before[tid], "repeated loading cannot resize an existing town or change its goods")
		var loaded_work: Dictionary = {}
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false): continue
			loaded_work[int(f["id"])] = work_snapshot(e, f)
			check(is_equal_approx(float(f["assigned_need"]), Families.need_hands(f, e)), "saved work markers refer to the same real acres and herds")
		check(loaded_work == saved_work[tid], "second load preserves the complete household set and exact hands, jobs, casual work, keepers, idle and farm capacity")
	print("FARM WORK SAVE towns=", before.size(), " checks=", checks, " failures=", fails)
	return fails
