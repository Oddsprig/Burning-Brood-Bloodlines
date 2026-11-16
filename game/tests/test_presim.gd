extends RefCounted
## v0.100: one-day startup history (user direction 2026-10-17): native atomic/sliced determinism, recorded
## v0.100: work/service, recruit titles/stories, protected company arrival and saves that never restart history.
## v0.100: a detached recorded-history fixture exercises multi-event stories without simulating five years.

const RunplanArgs: GDScript = preload("res://tests/fixtures/older_runplan_args_v100.gd")
const SpeedParts: GDScript = preload("res://tests/fixtures/older_speed_parts_v100.gd")
const SpeedCheckpoint: GDScript = preload("res://tests/fixtures/older_speed_checkpoint_v100.gd")
const PRESIM_PARTS: Array[String] = ["atomic", "sliced", "full", "old_save"]
var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _det_receipt_path() -> String:
	return "user://test_presim_det_v100_%s.var" % ProjectSettings.globalize_path("res://").sha256_text().substr(0, 12)

func _write_atomic_digest(digest_val: String) -> bool:
	var f: FileAccess = FileAccess.open(_det_receipt_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_var({"source": str(SpeedParts.call("source_stamp")), "atomic_digest": digest_val}, false)
	f.flush()
	var ok: bool = f.get_error() == OK
	f.close()
	return ok

func _read_atomic_digest() -> String:
	var f: FileAccess = FileAccess.open(_det_receipt_path(), FileAccess.READ)
	if f == null:
		return ""
	var raw: Variant = f.get_var(false)
	var ok: bool = f.get_error() == OK
	f.close()
	if not ok or not raw is Dictionary:
		return ""
	var data: Dictionary = raw
	if str(data.get("source", "")) != str(SpeedParts.call("source_stamp")):
		return ""
	return str(data.get("atomic_digest", ""))

func _select_part() -> String:
	var selected: String = OS.get_environment("PRESIM_PART")
	var seen: bool = not selected.is_empty()
	for arg: String in RunplanArgs.arguments():
		var val: String = ""
		if arg.begins_with("--part="):
			val = arg.trim_prefix("--part=")
		elif arg.begins_with("--speed-part="):
			val = arg.trim_prefix("--speed-part=")
		elif arg == "--part" or arg == "--speed-part":
			printerr("FAIL: choose one --part=atomic|sliced|full|old_save")
			return ""
		else:
			continue
		if seen and val != selected:
			printerr("FAIL: conflicting presim part selectors")
			return ""
		seen = true
		selected = val
	if selected == "" or not selected in PRESIM_PARTS:
		printerr("choose one --part=atomic|sliced|full|old_save; every part is required in order")
		return ""
	return selected

func run(_tree: SceneTree) -> int:
	var part: String = _select_part()
	if part == "":
		return 1
	# v0.100: use the authorized small default and restore settings even for the deterministic-only entry.
	var previous_size := WorldGen.gen_size
	var previous_span := CampaignWorld.presim_span_days
	var previous_save: String = Game.SAVE_PATH
	check(WorldGen.WORLD_SIZE == "normal" and CampaignWorld.PRESIM_DEFAULT_DAYS == 1,
		"startup defaults remain Normal and one history day")
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Game.SAVE_PATH = "user://test_save_presim_%d.json" % OS.get_process_id()
	var checkpoint: RefCounted = SpeedCheckpoint.new("presim_v100")
	if part == "atomic":
		_test_atomic()
	elif part == "sliced":
		_test_sliced()
	elif part == "full":
		_test_full()
		if fails == 0:
			check(bool(checkpoint.call("save_step", 0)), "post-full presim checkpoint saved for old_save")
	elif part == "old_save":
		check(bool(checkpoint.call("load_step", 0)), "post-full presim checkpoint loaded; run --part=full first")
		if fails == 0:
			_test_old_save()
	WorldGen.gen_size = previous_size
	CampaignWorld.presim_span_days = previous_span
	Game.SAVE_PATH = previous_save
	return fails

func _ids(w: Dictionary) -> Array:
	var ids: Array = w["towns"].keys()
	ids.sort()
	return ids

## A digest of the world: people, purses, treasuries, the register's next id, every army's size.
func _digest(w: Dictionary) -> String:
	var parts := []
	for tid in _ids(w):
		var e: Dictionary = w["towns"][tid]["econ"]
		var purse := 0.0
		for f in e["fams"]:
			purse += float(f["purse"])
		parts.append("%s:%d:%d:%.2f:%.2f:%d" % [tid, int(e["pop"]), int(e["adults"]), purse, float(e["treasury"]), int(e.get("next_pid", 0))])
	var fids: Array = w["factions"].keys()
	fids.sort()
	for fid in fids:
		parts.append("%s:%.2f" % [fid, float(w["factions"][fid].get("treasury", 0.0))])
	var wids: Array = w["warbands"].keys()
	wids.sort()
	parts.append(str(wids.size()))
	return "|".join(PackedStringArray(parts))

## Herds (addendum 1 B): head by kind across the world, and the herd books so far (no tuning: printed for Douglas).
func _herd_year(w: Dictionary, yr: int) -> void:
	var heads := {}
	var bk := {"died": {}}
	for tid in _ids(w):
		var e: Dictionary = w["towns"][tid]["econ"]
		var th := Herds.town_heads(e)
		for k in th:
			heads[k] = int(heads.get(k, 0)) + int(th[k])
		var b := Herds.book(e, "tot")
		for k in b:
			if k == "died":
				for c in b["died"]:
					bk["died"][c] = int(bk["died"].get(c, 0)) + int(b["died"][c])
			else:
				bk[k] = int(bk.get(k, 0)) + int(b[k])
	var sp_f := 0; var sp_m := 0; var mk_f := 0; var mk_m := 0; var loans := 0.0
	for tid in _ids(w):
		var e2: Dictionary = w["towns"][tid]["econ"]
		sp_f += int(e2["led"]["spoil"].get("fresh_meat", 0)); sp_m += int(e2["led"]["spoil"].get("meat", 0))
		mk_f += int(e2["led"]["made"].get("fresh_meat", 0)); mk_m += int(e2["led"]["made"].get("meat", 0))
		for k2 in e2.get("hd", {}).get("floan", {}):
			loans += float(e2["hd"]["floan"][k2])
	print("  year %d meat so far: fresh meat made %d, spoiled %d; keeping meat made %d, spoiled %d; straw owed on fodder loans now %d bales" % [yr,
		mk_f, sp_f, mk_m, sp_m, int(loans)])
	var starved := int(bk["died"].get("starved", 0))
	var ill := 0
	for c in bk["died"]:
		if String(c).begins_with("sickness"):
			ill += int(bk["died"][c])
	print("  year %d herds: %s; so far born %d, slaughtered %d, sold %d, stolen %d, starved %d, old age %d, sickness %d, cold %d" % [yr, str(heads),
		int(bk.get("born", 0)), int(bk.get("slaughtered", 0)), int(bk.get("sold", 0)), int(bk.get("stolen", 0)), starved, int(bk["died"].get("old age", 0)), ill,
		int(bk["died"].get("cold", 0))])

func _test_atomic() -> void:
	Game.new_game(777)
	# v0.100: an oversized request must clamp to the selected day; compare native atomic and resumable paths.
	CampaignWorld.presim_step(Game, 120)
	check(Game.day == 1.0 and CampaignWorld.presim_total(Game) == 1 and CampaignWorld.presim_left(Game) == 0,
		"atomic history clamps oversized work to exactly one day")
	var a := _digest(Game.world)
	check(_write_atomic_digest(a), "atomic presim digest receipt written")

func _test_sliced() -> void:
	var a: String = _read_atomic_digest()
	check(a != "", "atomic presim digest available on current source; run --part=atomic first")
	if a == "":
		return
	Game.new_game(777)
	var pending := {}
	var start := Time.get_ticks_msec()
	while CampaignWorld.presim_left(Game) > 0 and Time.get_ticks_msec() - start < 60000:
		CampaignWorld.presim_slice(Game, pending, 12000)
	var b := _digest(Game.world)
	check(a == b, "the years before differ with the chunking (same seed)")
	check(Game.day == 1.0 and CampaignWorld.presim_left(Game) == 0 and pending.is_empty(),
		"resumable history completes exactly one day")

func _test_full() -> void:
	Game.new_game(2026)
	# v0.100: v0.017 (e460f8b) removed free starters; make a small funded army so arrival checks are nonvacuous.
	check(Game.company.is_empty() and Game.gold == 0, "history fixture starts with the native unraised army")
	var town_id := DevTools.choose_house(Game)
	var raised := DevTools.raise_army(Game, town_id, 2) if town_id != "" else 0
	check(raised == 2 and Game.company.size() == 2, "arrival fixture explicitly musters two real residents")
	if fails > 0:
		return
	var army_gold := Game.gold
	var army_meals := Food.stock(Game, "meal")
	var w: Dictionary = Game.world
	var pop0 := {}
	for tid in _ids(w):
		pop0[tid] = int(w["towns"][tid]["econ"]["pop"])
	var ages0 := {}
	for u in Game.company:
		ages0[u.uid] = u.age
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var worst := 0
	while CampaignWorld.presim_left(Game) > 0 and Time.get_ticks_msec() - t0 < 60000:
		var f0 := Time.get_ticks_usec()
		CampaignWorld.presim_step(Game, 1)
		worst = maxi(worst, Time.get_ticks_usec() - f0)
		frames += 1
		if frames % 120 == 0:   # the year's people: how many, born, died (old age and in service), left
			var pp := 0; var b := 0; var dd := 0; var lf := 0; var fams := 0; var lh := 0; var lc := 0; var hung := 0; var tre := 0.0
			for tid in _ids(w):
				var e: Dictionary = w["towns"][tid]["econ"]
				pp += int(e["pop"]); b += int(e["stats"].get("births", 0)); dd += int(e["stats"].get("deaths", 0)); lf += int(e["stats"].get("left", 0))
				lh += int(e["stats"].get("left_hunger", 0)); lc += int(e["stats"].get("left_crowd", 0)); tre += float(e["treasury"])
				for f in e["fams"]:
					if not f.get("gone", false) and not f.get("estate", false):
						fams += 1
						if int(f["hungry"]) > 0:
							hung += 1
			print("  year %d: population %d in %d households (%d hungry now); so far %d born, %d died, %d left town (%d for hunger, %d crowded out); town treasuries %d" % [
				frames / 120, pp, fams, hung, b, dd, lf, lh, lc, int(tre)])
			_herd_year(w, frames / 120)
	check(CampaignWorld.presim_left(Game) == 0 and frames == 1, "full selected history completes exactly one native day")
	if fails > 0:
		return
	var ms := Time.get_ticks_msec() - t0
	CampaignWorld.presim_finish(Game, ms)
	var days := CampaignWorld.presim_total(Game)
	print("  PRESIM %d days (%d years) in %.1f s wall (%.1f ms a day, worst day %.1f ms)" % [days, days / 120, ms / 1000.0, float(ms) / days, worst / 1000.0])
	check(float(Game.day) == float(days), "the player arrives on day %d (got %.1f)" % [days, Game.day])
	for u in Game.company:
		check(u.age == int(ages0[u.uid]), "%s aged through the years before (%d -> %d)" % [u.name, int(ages0[u.uid]), u.age])
	check(float(Game.food_clock["last"]) == float(Game.day), "the company's food clock starts today")
	check(Game.gold == army_gold and Food.stock(Game, "meal") == army_meals, "startup history consumes no company wages or provisions")
	# histories were recorded as they happened
	var with_job := 0; var job_changes := 0; var served := 0; var people := 0
	var bad_serve := []
	for tid in _ids(w):
		var e: Dictionary = w["towns"][tid]["econ"]
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false):
				continue
			for p in Persons.pp(f):
				people += 1
				var h: Array = p[Persons.HIST]
				var jobs := h.filter(func(x): return String(x[1]) == "job")
				if not jobs.is_empty():
					with_job += 1
				job_changes += jobs.filter(func(x): return int(x[0]) > 0).size()
				if h.any(func(x): return String(x[1]) == "serve"):
					served += 1
				var st := String(p[4])
				if st in ["militia", "army", "caravan", "bandit", "company"] and Persons.served_since(p, st) < 0.0:
					bad_serve.append("%s (%s)" % [Persons.name_of(f, p, Persons.race_of(e)), st])
				if st == "" and int(p[6]) == 0 and String(p[Persons.JOB]) != "" and (jobs.is_empty() or String(jobs[-1][2]) != String(p[Persons.JOB])):
					bad_serve.append("%s: job %s not in his history" % [Persons.name_of(f, p, Persons.race_of(e)), p[Persons.JOB]])
	check(job_changes > 0, "nobody changed jobs during the selected history day")
	check(served > 0, "nobody's history shows service")
	check(bad_serve.is_empty(), "service or work missing from the history: %s" % str(bad_serve.slice(0, 4)))
	print("  histories: %d grown-ups, %d with a job on record, %d job changes after day 0, %d with service" % [people, with_job, job_changes, served])
	var bytes := 0; var recs := 0
	for tid in _ids(w):
		for f in w["towns"][tid]["econ"]["fams"]:
			for key in ["pp", "kp", "dp"]:
				for p in f.get(key, []):
					bytes += JSON.stringify(p).length() + 1
					recs += 1
	print("  register after one history day: %d records (living, children, remembered dead), %.1f bytes each, %d KB" % [recs, float(bytes) / maxf(1.0, recs), bytes / 1024])
	_report(w, pop0)
	# v0.100: retain native sickness-count validation after the selected one-day history.
	var sk_bad := Sickness.check_counts(w)
	check(sk_bad.is_empty(), "sickness counts after one history day: %s" % str(sk_bad.slice(0, 4)))
	for l in Sickness.report_lines(w):
		print("  SICKNESS ", l)
	# recruits: title = his place now, story = his own history + why now
	var cards := 0
	var history_fixture := false
	for tid in _ids(w):
		var t: Dictionary = w["towns"][tid]
		var pool := Recruits.generate_pool(t, RandomNumberGenerator.new())
		t["recruits"] = pool
		for u in pool:
			var f := People.fam_of(t, u.family)
			var p := Persons.by_uid(f, u.uid)
			check(not p.is_empty(), "recruit %s is not a register person" % u.name)
			if p.is_empty():
				continue
			cards += 1
			var role := Recruits.person_role(t["econ"], f, p)
			check(u.title == String(role["title"]), "%s: title %s, his place is %s" % [u.name, u.title, role["title"]])
			var own := Backstory.own_lines(t, t["econ"], f, p, Persons.first_of(t["econ"], p))
			for l in own:
				check(u.backstory.contains(String(l)), "%s: story lacks his history line '%s': %s" % [u.name, l, u.backstory])
			if not history_fixture:
				_test_history_card(t, f, u)
				history_fixture = true
			if cards <= 2:
				print("  CARD %s, %s, age %d (%s)\n    %s" % [u.name, u.title, u.age, t["name"], u.backstory])
				print("    history: ", p[Persons.HIST])
	check(cards > 0 and history_fixture, "one-day recruits and the recorded multi-event story fixture are exercised")

func _test_history_card(town: Dictionary, family: Dictionary, unit: Unit) -> void:
	# v0.100: anonymous recruits need not have years of named history; supply two dated native records on a copy.
	var fixture: Dictionary = family.duplicate(true)
	var person := Persons.by_uid(fixture, unit.uid)
	check(not person.is_empty(), "history fixture retains the recruit's real registered identity")
	if person.is_empty():
		return
	person[Persons.HIST] = []
	fixture["ev"] = []
	var e: Dictionary = town["econ"].duplicate()
	e["tev"] = []
	var day := 28.0
	e["day"] = day
	Persons.log_life(person, day - 21, "job", "farmhand on the family grain fields")
	Persons.log_life(person, day - 14, "left_job", "farmhand on the family grain fields")
	Persons.log_life(person, day - 14, "serve", "militia")
	Persons.log_life(person, day - 7, "home", "militia")
	var first := Persons.first_of(e, person)
	var role := Recruits.person_role(e, fixture, person)
	var text := Backstory.recruit_text(town, e, fixture, first, unit.name, role, unit)
	var own := Backstory.own_lines(town, e, fixture, person, first)
	check(own.size() >= 2, "recorded job and militia service both produce history lines")
	for line in own:
		check(text.contains(String(line)), "fixture recruit story contains its recorded history: " + String(line))

func _report(w: Dictionary, pop0: Dictionary) -> void:
	var by_race := {}
	var fam_live := 0; var fam_gone := 0; var homes := 0; var pop := 0; var pop_start := 0
	print("  WORLD after the years before:")
	for tid in _ids(w):
		var t: Dictionary = w["towns"][tid]
		var e: Dictionary = t["econ"]
		var race := Persons.race_of(e)
		var c := People.census(e)
		by_race[race] = int(by_race.get(race, 0)) + int(e["pop"])
		pop += int(e["pop"]); pop_start += int(pop0[tid])
		homes += int(e["homes"])
		for f in e["fams"]:
			if f.get("estate", false):
				continue
			if f.get("gone", false):
				fam_gone += 1
			else:
				fam_live += 1
		print("    %s (%s, %s): pop %d (was %d), %d households, %d children / %d adults / %d elders, treasury %d" % [t["name"], race,
			CampaignWorld.faction_name(String(t["faction"])), int(e["pop"]), int(pop0[tid]), int(c["households"]), int(c["children"]),
			int(c["adults"]), int(c["elders"]), int(e["treasury"])])
	print("    population %d (was %d); by race %s" % [pop, pop_start, str(by_race)])
	print("    families %d living, %d gone (left or died out); %d houses" % [fam_live, fam_gone, homes])
	var fids: Array = w["factions"].keys()
	fids.sort()
	var coffers := []
	for fid in fids:
		coffers.append("%s %d" % [fid, int(float(w["factions"][fid].get("treasury", 0.0)))])
	print("    faction coffers: ", ", ".join(PackedStringArray(coffers)))
	var st: Dictionary = w.get("diplo", {}).get("stats", {})
	var armies := 0; var men := 0
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if Army.is_field(wb):
			armies += 1
			men += (wb["units"] as Array).filter(func(u): return not u.dead).size()
	print("    wars declared %d, peaces %d; armies in the field %d (%d men)" % [int(st.get("wars", 0)), int(st.get("peaces", 0)), armies, men])

func _test_old_save() -> void:
	# v0.100: reuse the generated world as a pre-history-save fixture instead of generating a fourth world.
	Game.world.erase("presim")
	Game.world["party"]["safe_until"] = 1.0e9
	Game.advance_time(2.0, false)
	Game.save_game()
	var d := Game.day
	check(Game.load_game(), "load")
	check(not Game.world.has("presim") and absf(Game.day - d) < 0.001, "an old save does not run the years before")
	Game.advance_time(1.0, false)
	check(not Game.world.has("presim"), "an old save never starts the years before")
