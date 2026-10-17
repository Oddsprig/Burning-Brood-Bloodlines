extends RefCounted
## The years before (Douglas: "their background needs to actually be a job they held - maybe we simulate 5 years
## on startup so there's actually backgrounds"): a new campaign runs the world's own sim five years before the
## player arrives (CampaignWorld.presim_step / presim_finish, ui/presim.gd). Tests: life histories are recorded
## as things happen (jobs taken and left, service, coming home); recruit titles and stories come from the
## history and the present; the run is deterministic per seed whatever the chunking; old saves never run it.
## Prints the wall time of the full five years and the world it leaves (no tuning: rule zero).

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_save_presim_%d.json" % OS.get_process_id()
	_test_deterministic()
	if OS.get_environment("PRESIM_ONLY") == "det":
		return fails
	_test_full()
	_test_old_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
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

func _test_deterministic() -> void:
	Game.new_game(777)
	CampaignWorld.presim_step(Game, 120)   # one big chunk
	var a := _digest(Game.world)
	Game.new_game(777)
	for i in 120:
		CampaignWorld.presim_step(Game, 1)   # a day a frame
	var b := _digest(Game.world)
	check(a == b, "the years before differ with the chunking (same seed)")
	check(float(Game.day) == 120.0, "presim day count (%.1f)" % Game.day)

func _test_full() -> void:
	Game.new_game(2026)
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
	while CampaignWorld.presim_left(Game) > 0:
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
	var ms := Time.get_ticks_msec() - t0
	CampaignWorld.presim_finish(Game, ms)
	var days := CampaignWorld.presim_total(Game)
	print("  PRESIM %d days (%d years) in %.1f s wall (%.1f ms a day, worst day %.1f ms)" % [days, days / 120, ms / 1000.0, float(ms) / days, worst / 1000.0])
	check(float(Game.day) == float(days), "the player arrives on day %d (got %.1f)" % [days, Game.day])
	for u in Game.company:
		check(u.age == int(ages0[u.uid]), "%s aged through the years before (%d -> %d)" % [u.name, int(ages0[u.uid]), u.age])
	check(float(Game.food_clock["last"]) == float(Game.day), "the company's food clock starts today")
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
	check(job_changes > 0, "nobody changed jobs in five years")
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
	print("  register in the save after five years: %d records (living, children, remembered dead), %.1f bytes each, %d KB" % [recs, float(bytes) / maxf(1.0, recs), bytes / 1024])
	_report(w, pop0)
	# sickness (docs/specs/barge/06-sickness.md section 9): five years leave no negative count and no NaN; the cases
	# and deaths per town per year are printed for Douglas (no tuning)
	var sk_bad := Sickness.check_counts(w)
	check(sk_bad.is_empty(), "sickness counts after five years: %s" % str(sk_bad.slice(0, 4)))
	for l in Sickness.report_lines(w):
		print("  SICKNESS ", l)
	# recruits: title = his place now, story = his own history + why now
	var cards := 0
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
			var role := Recruits.person_role(t["econ"], f, p)
			check(u.title == String(role["title"]), "%s: title %s, his place is %s" % [u.name, u.title, role["title"]])
			var own := Backstory.own_lines(t, t["econ"], f, p, Persons.first_of(t["econ"], p))
			for l in own:
				check(u.backstory.contains(String(l)), "%s: story lacks his history line '%s': %s" % [u.name, l, u.backstory])
			if cards < 2 and own.size() >= 2:
				print("  CARD %s, %s, age %d (%s)\n    %s" % [u.name, u.title, u.age, t["name"], u.backstory])
				print("    history: ", p[Persons.HIST])
				cards += 1
	check(cards > 0, "no recruit with a five-year history")

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
	Game.new_game(31337)   # a world made without the years before (every save older than this)
	Game.world["party"]["safe_until"] = 1.0e9
	Game.advance_time(2.0, false)
	Game.save_game()
	var d := Game.day
	check(Game.load_game(), "load")
	check(not Game.world.has("presim") and absf(Game.day - d) < 0.001, "an old save does not run the years before")
	Game.advance_time(1.0, false)
	check(not Game.world.has("presim"), "an old save never starts the years before")
