extends RefCounted
## Separate fresh processes compare one native synchronous or budgeted day.
## No loading, cache reset, prior-release fixture or player save access.
const PRIVATE_WORK := "C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"
const MAX_GENERATION_SLICES := 20000
const MAX_HISTORY_SLICES := 20000
const MAX_WORK_SLICES := 20000
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL work budget: ", message)

func _hash_state() -> String:
	return JSON.stringify(Game._save_tree(), "", true, true).sha256_text()

func _job_counts() -> Dictionary:
	var counts := {}
	for kind in CampaignWorld.job_total:
		counts[String(kind)] = int(CampaignWorld.job_total[kind][1])
	return counts

func _executed(before: Dictionary) -> Dictionary:
	var counts := {}
	for kind in _job_counts():
		var delta: int = int(CampaignWorld.job_total[kind][1]) - int(before.get(kind, 0))
		if delta != 0: counts[kind] = delta
	return counts

func _private_path(path: String) -> String:
	var normalized: String = path.replace("\\", "/").simplify_path()
	if not normalized.is_absolute_path() or not normalized.to_lower().begins_with(PRIVATE_WORK.to_lower()):
		return ""
	return normalized

func run(tree: SceneTree) -> int:
	var mode := "budgeted"
	var report_path := ""
	var reference_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--reference="): reference_path = argument.trim_prefix("--reference=")
	check(mode in ["sync", "budgeted"], "mode is sync or budgeted")
	report_path = _private_path(report_path)
	check(report_path != "", "report has an absolute private workspace path")
	var reference: Dictionary = {}
	if reference_path != "":
		reference_path = _private_path(reference_path)
		check(reference_path != "" and reference_path.to_lower() != report_path.to_lower(), "reference is a separate private workspace report")
		if reference_path != "":
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(reference_path)) if FileAccess.file_exists(reference_path) else null
			check(parsed is Dictionary and not parsed.is_empty(), "reference report parses and contains control evidence")
			if parsed is Dictionary: reference = parsed
	check(Game.world.is_empty() and Game.company.is_empty(), "gate starts in a fresh process before any campaign")
	if fails > 0: return fails
	# Do not yield between native slices: no screen/background update can drain a
	# queue before this gate records its completed operations.
	WorldGen.gen_size = "normal"
	WorldGen.gen_stretch = WorldGen.STRETCH
	CampaignWorld.presim_span_days = 1
	var began: int = Time.get_ticks_usec()
	var generation: Dictionary = Game.new_game_begin(777)
	var generation_slices := 0
	var generated := false
	while not generated and generation_slices < MAX_GENERATION_SLICES:
		generated = Game.new_game_slice(generation, 4000)
		generation_slices += 1
	check(generated and not Game.world.get("towns", {}).is_empty(), "fresh native Normal world generation completes")
	check(Game.seed_value == 777 and Game.day == 0.0, "fresh world has seed 777 and no elapsed history")
	if not generated: return fails
	var history_state: Dictionary = {}
	var history_slices := 0
	while CampaignWorld.presim_left(Game) > 0 and history_slices < MAX_HISTORY_SLICES:
		CampaignWorld.presim_slice(Game, history_state, 4000)
		history_slices += 1
	check(CampaignWorld.presim_left(Game) == 0 and history_state.is_empty(), "exactly one history day completes through native slices")
	check(Game.day == 1.0 and int(Game.world.get("presim", {}).get("done", 0)) == 1, "history calendar advances exactly once")
	if CampaignWorld.presim_left(Game) > 0: return fails
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	check(Game.world.get("work", []).is_empty() and Game.world["presim"].get("finished", false), "history finishes before subsequent campaign work")
	check(int(Game.world["presim"].get("wall_ms", -1)) == 0, "history finish records deterministic wall time")
	check(Game.company.size() == Game.START_COMPANY_SIZE, "native starting company is retained")
	if fails > 0: return fails
	var generation_us: int = Time.get_ticks_usec() - began
	var initial_sha: String = _hash_state()
	var jobs_before: Dictionary = _job_counts()
	var start_day: float = Game.day
	var campaign_started: int = Time.get_ticks_usec()
	var work_slices := 0
	if mode == "sync":
		Game.advance_time(1.0, true)
	else:
		Game.advance_time(1.0, true, 0, 1)
		check(not Game.world.get("work", []).is_empty(), "one-microsecond allowance yields with native jobs retained")
		var calendar_correct: bool = Game.day == start_day + 1.0
		while not Game.world.get("work", []).is_empty() and work_slices < MAX_WORK_SLICES:
			CampaignWorld.work_slice(Game, 1)
			work_slices += 1
			calendar_correct = calendar_correct and Game.day == start_day + 1.0
		check(calendar_correct, "every work slice retains one calendar advance, without repeated wages/healing/time")
	var campaign_us: int = Time.get_ticks_usec() - campaign_started
	check(Game.world.get("work", []).is_empty(), "all ordered native campaign jobs complete within bounded slices")
	check(Game.day == start_day + 1.0 and int(Game.world.get("last_day", -1)) == int(Game.day), "one subsequent native campaign midnight settles exactly once")
	var executed: Dictionary = _executed(jobs_before)
	var job_count := 0
	for kind in executed: job_count += int(executed[kind])
	check(job_count > 0 and int(executed.get("dragon_care", 0)) == 1 and int(executed.get("feudal", 0)) == 1, "native care and succession jobs execute once in the counted midnight")
	var final_sha: String = _hash_state()
	var company_rng: String = str(Game.rng.state)
	var next_unit: int = Unit._next_uid
	var next_item: int = Item._next_uid
	check(CampaignWorld.work_slice(Game, 1) == 0 and CampaignWorld.work_slice(Game, 1) == 0, "empty retries execute zero jobs")
	check(_hash_state() == final_sha and str(Game.rng.state) == company_rng and Unit._next_uid == next_unit and Item._next_uid == next_item and _executed(jobs_before) == executed, "empty retries preserve full state, RNG, counters and job counts")
	var report: Dictionary = {"schema": 1, "seed": 777, "size": "normal", "history_days": 1, "mode": mode,
		"initial_sha256": initial_sha, "state_sha256": final_sha, "company_rng": company_rng,
		"next_unit_uid": next_unit, "next_item_uid": next_item, "start_day": start_day, "day": Game.day,
		"job_counts": executed, "job_count": job_count, "generation_slices": generation_slices,
		"history_slices": history_slices, "work_slices": work_slices,
		"generation_us": generation_us, "campaign_us": campaign_us}
	if not reference.is_empty():
		check(int(reference.get("schema", -1)) == 1 and int(reference.get("seed", -1)) == 777 and reference.get("size", "") == "normal" and int(reference.get("history_days", -1)) == 1 and int(reference.get("failures", -1)) == 0, "control is a successful current-build fresh-world gate")
		check(reference.get("initial_sha256", "") == initial_sha, "fresh-process initial native worlds match exactly")
		check(reference.get("state_sha256", "") == final_sha, "full sorted native save-tree state matches control")
		check(str(reference.get("company_rng", "")) == company_rng and int(reference.get("next_unit_uid", -1)) == next_unit and int(reference.get("next_item_uid", -1)) == next_item, "company RNG and both identity counters match control")
		var reference_counts: Dictionary = reference.get("job_counts", {})
		var normalized_counts := {}
		for kind in reference_counts: normalized_counts[String(kind)] = int(reference_counts[kind])
		check(normalized_counts == executed and int(reference.get("job_count", -1)) == job_count, "every executed native job kind/count matches control")
		check(float(reference.get("start_day", -1)) == start_day and float(reference.get("day", -1)) == Game.day, "control and candidate calendars match")
	var directory_error: int = DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	check(directory_error == OK, "private report directory is available")
	var output: FileAccess = FileAccess.open(report_path, FileAccess.WRITE) if directory_error == OK else null
	check(output != null, "private report opens for writing")
	if output != null:
		report["checks"] = checks; report["failures"] = fails
		output.store_string(JSON.stringify(report, "\t", true, true)); output.close()
	print("WORK BUDGET fresh seed777 mode=%s checks=%d failures=%d jobs=%d slices=%d campaign_ms=%.3f SHA=%s report=%s" % [mode, checks, fails, job_count, work_slices, campaign_us / 1000.0, final_sha, report_path])
	await tree.process_frame
	return fails
