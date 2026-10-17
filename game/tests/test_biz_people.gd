extends RefCounted
## v0.014, Douglas's Fenmere findings (two "Blackmere Bowyer" rows, every shop at 0 coins and 0/1 staff beside 46
## idle adults and 57 open places, "kept by: not tracked", farms without health or profit; "we got 50-60 businesses
## and nobody to work in them"; "just one business doing actual production stuff - farming is a different matter";
## "youd think people would be interested in higher paying jobs first"). Checked at world gen and after a year:
##   - one business per production trade per town (mines: one per ore); farms may be several; no two rows of a town
##     share a name;
##   - every family shop is kept by a grown-up of its family who works it (unless the family has nobody free), and
##     every business at work names a keeper on the records screen;
##   - the records screen's Businesses row reads the business's own till, staff and keeper; farms show health;
##   - idle grown-ups do not sit beside open places they could take, and a town has no crowd of empty shops;
##   - the free hand takes the better-paid of two openings; a hand in a worse-paid place moves to a better one.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	Game.new_game(2026)
	_check_world("world gen")
	_test_records_rows("world gen")
	var days := int(OS.get_environment("BIZ_DAYS")) if OS.get_environment("BIZ_DAYS") != "" else 365
	CampaignWorld.presim_step(Game, days)
	_capture_state()
	_check_world("after %d days" % days)
	_test_records_rows("after %d days" % days)
	_trace_captured_towns()
	_test_matching()
	return fails

func _towns() -> Array:
	var out := []
	var ids: Array = Game.world["towns"].keys()
	ids.sort()
	for tid in ids:
		if TownEcon.has_econ(Game.world["towns"][tid]):
			out.append(Game.world["towns"][tid])
	return out

func _check_world(label: String) -> void:
	var worst_pair := [0, ""]; var worst_empty := [0, ""]
	var dups := 0; var names := 0; var unkept := 0; var nokeeper := 0
	for t in _towns():
		var e: Dictionary = t["econ"]
		var seen := {}; var titles := {}
		var takeable := 0; var empty := 0
		for b in e["biz"]:
			if b.get("closed", false):
				continue
			# The real vacancies are the assertion input, including places that
			# reopened after the current hiring index was made.
			takeable += Businesses.takeable(b)
			var ty := String(b["type"])
			var listed := int(b["cap"]) > 0 or int(b["workers"]) > 0 or int(b.get("kw", 0)) > 0
			if ty != "farm":
				var key := ty + ("|" + String(b.get("ore", "")) if ty == "mine" else "")
				if seen.has(key):
					dups += 1
					check(false, "%s: %s has two %s businesses" % [label, t["name"], key])
				seen[key] = true
			if listed:
				var nm := Businesses.title(e, b)
				if titles.has(nm):
					names += 1
					if names <= 5:
						check(false, "%s: %s has two rows named %s" % [label, t["name"], nm])
				titles[nm] = true
			var owner := int(b["owner"])
			if owner >= 0 and ty != "farm":
				var f: Dictionary = e["fams"][owner]
				var free := Families.adults(f) - Families.serving(f)
				if int(b.get("kw", 0)) == 0 and (f.get("keeps", []) as Array).size() < free:
					unkept += 1
					if unkept <= 5:
						check(false, "%s: %s's %s has no keeper though its family has a grown-up free" % [label, t["name"], ty])
			if (int(b["workers"]) > 0 or int(b.get("kw", 0)) > 0) and RecData.keeper(e, b).is_empty():
				nokeeper += 1
				if nokeeper <= 5:
					check(false, "%s: %s's %s is at work but names no keeper" % [label, t["name"], Businesses.title(e, b)])
			if ty != "farm" and not ty in Businesses.NOT_TRADES and int(b["workers"]) == 0 and int(b.get("kw", 0)) == 0:
				empty += 1
		var idle := 0
		for f in e["fams"]:
			if not f.get("gone", false):
				idle += int(f.get("idle", 0))
		var pair := mini(idle, takeable)
		if OS.get_environment("BIZ_DEBUG") != "" and (pair > 10 or empty > 5):
			print("    DEBUG %s day %d open_n %d open_top %.1f" % [t["name"], int(e.get("day", 0)), int(e.get("open_n", -1)), float(e.get("open_top", -1))])
			for f in e["fams"]:
				if not f.get("gone", false) and int(f.get("idle", 0)) > 0:
					print("      idle fam %d %s idle %d adults %d serving %d hands %d jobs %s keeps %s hl %s hungry %d last %.0f" % [int(f["id"]), f["name"], int(f["idle"]),
						Families.adults(f), Families.serving(f), int(f["hands"]), str(f["jobs"]), str(f.get("keeps", [])), str(f.has("hl")), int(f.get("hungry", 0)), float(f.get("last", 0))])
			for bid in e.get("open", []):
				var db: Dictionary = e["biz"][int(bid)]
				if int(db["cap"]) > int(db["workers"]):
					print("      open %s %s own %d %d/%d wage %.1f till %.1f" % [db["type"], Businesses.title(e, db), int(db["owner"]), int(db["workers"]), int(db["cap"]), float(db["wage"]), float(db["till"])])
			for db in e["biz"]:
				var ty2 := String(db["type"])
				if not db.get("closed", false) and ty2 != "farm" and not ty2 in Businesses.NOT_TRADES and int(db["workers"]) == 0 and int(db.get("kw", 0)) == 0:
					var ow := int(db["owner"])
					print("      empty %s own %d sale %s owner adults %s owns %s" % [ty2, ow, str(db.get("for_sale", false)), str(Families.adults(e["fams"][ow]) if ow >= 0 else -1), str(e["fams"][ow]["owns"] if ow >= 0 else [])])
		if pair > 10:
			var snapshot: Dictionary = e.duplicate(true)
			var observed_idle := idle
			Families.assign_all(snapshot)
			var after_idle := 0; var after_places := 0
			for family in snapshot["fams"]:
				if not family.get("gone", false): after_idle += int(family.get("idle", 0))
			for business in snapshot["biz"]: after_places += Businesses.takeable(business)
			print("MATCHING DIAGNOSTIC ", label, " ", t["id"], " last turn range ", (e["fams"] as Array).map(func(f): return float(e.get("day", 0)) - float(f.get("last", 0))).max(), " idle ", observed_idle, " actual openings ", takeable, " after existing assignment pass idle ", after_idle, " actual openings ", after_places)
		if pair > int(worst_pair[0]):
			worst_pair = [pair, "%s (%d idle, %d places they could take)" % [t["name"], idle, takeable]]
		if empty > int(worst_empty[0]):
			worst_empty = [empty, String(t["name"])]
	print("  %s: duplicate trades %d, duplicate names %d, unkept family shops %d, at work without a keeper %d; worst idle-beside-open %s; most empty shops %d (%s)" % [
		label, dups, names, unkept, nokeeper, worst_pair[1], int(worst_empty[0]), worst_empty[1]])
	# a family's turn comes weekly: idle hands and a place opened since may meet for up to a week [ours: 10]
	check(int(worst_pair[0]) <= 10, "%s: idle grown-ups beside open places they could take: %s" % [label, worst_pair[1]])
	check(int(worst_empty[0]) <= 5, "%s: %s has %d shops with nobody at work" % [label, worst_empty[1], int(worst_empty[0])])

## The Businesses tab's row reads the business itself: cash = its till, staff = hands + keeper, the keeper by name.
func _test_records_rows(label: String) -> void:
	var n := 0; var farms_nt := 0; var farms := 0
	for t in _towns():
		var e: Dictionary = t["econ"]
		for b in e["biz"]:
			if b.get("closed", false):
				continue
			var r: Dictionary = RecTown.biz_row(null, t, e, b)
			n += 1
			check(absf(float(r["cash"]) - float(b["till"])) < 0.001, "%s: %s row cash %.1f, till %.1f" % [label, r["name"], float(r["cash"]), float(b["till"])])
			check(int(r["staff"]) == int(b["workers"]) + int(b.get("kw", 0)), "%s: %s row staff %d" % [label, r["name"], int(r["staff"])])
			if int(b["workers"]) > 0 or int(b.get("kw", 0)) > 0:
				check(not String(r["_d"]).contains("kept by: not tracked") and not (r["_keeper"] as Dictionary).is_empty(),
					"%s: %s row: no keeper" % [label, r["name"]])
			if String(b["type"]) == "farm" and int(b["owner"]) >= 0 and not e["fams"][int(b["owner"])].get("gone", false) \
					and int(e.get("day", 0)) - int(b.get("made", 0)) > 8:   # (its books start at the family's next turn)
				farms += 1
				if RecData.biz_health(b) == null:
					farms_nt += 1
	print("  %s: %d business rows read; %d of %d farms without health" % [label, n, farms_nt, farms])
	if not label.begins_with("world"):
		check(farms_nt == 0, "%s: %d farms show no health or profit" % [label, farms_nt])

## Two openings, one pays more: the free hand takes the better one; a hand in the worse-paid place moves when a
## better one opens.
func _test_matching() -> void:
	var t: Dictionary = _towns()[0]
	var e: Dictionary = t["econ"]
	var f: Dictionary = {}
	for x in e["fams"]:
		if x.get("gone", false) or x.get("estate", false):
			continue
		if Families.adults(x) - Families.serving(x) == 1 and Families.need_hands(x) <= 0.0 and (x["owns"] as Array).is_empty() and not x.has("hl") \
				and int(x.get("hungry", 0)) == 0 and float(x.get("debt", 0.0)) <= 0.5:
			f = x
			break
	if f.is_empty():
		print("  matching: no one-grown-up landless family in %s; skipped" % t["name"])
		return
	for k in f["jobs"].keys():
		Families.set_job(e, f, int(k), 0)
	if f.has("cj"):
		Shelter.release_casual(e, f)
	var D := TownEcon.data()
	var lo: Dictionary = Businesses._row(e, "carpenter", -1, 1, D)
	var hi: Dictionary = Businesses._row(e, "carpenter", -1, 1, D)
	lo["wage"] = 50000.0; hi["wage"] = 60000.0
	lo["till"] = 1.0e6; hi["till"] = 1.0e6
	Businesses.rebuild_open(e)
	Families.reassign(e, f)
	check(int(f["jobs"].get(str(int(hi["id"])), 0)) == 1 and int(f["jobs"].get(str(int(lo["id"])), 0)) == 0,
		"the free hand took %s, not the better-paid place" % str(f["jobs"]))
	# now he holds the worse-paid place and a better one opens
	Families.set_job(e, f, int(hi["id"]), 0)
	hi["closed"] = true
	Families.set_job(e, f, int(lo["id"]), 1)
	var better: Dictionary = Businesses._row(e, "carpenter", -1, 1, D)
	better["wage"] = 70000.0; better["till"] = 1.0e6
	Businesses.rebuild_open(e)
	check(Families._paid_worse(e, f, e["biz"]), "a hand in a worse-paid place is not told of the better one")
	Families.reassign(e, f)
	check(int(f["jobs"].get(str(int(better["id"])), 0)) == 1 and int(f["jobs"].get(str(int(lo["id"])), 0)) == 0,
		"the hand in the worse-paid place did not move to the better one: %s" % str(f["jobs"]))
	print("  matching: %s's one grown-up took the better of two places and moved when a better one opened" % f["name"])


var capture_towns: Array = []
var capture_trace: Array = []

func _capture_state() -> void:
	var path := OS.get_environment("BIZ_CAPTURE")
	if path == "": return
	var save := FileAccess.open(path.path_join("checkpoint-save.json"), FileAccess.WRITE)
	save.store_string(JSON.stringify(Game._save_tree()))
	save.close()
	for town in _towns():
		var econ: Dictionary = town["econ"]
		var idle := 0
		var open := 0
		for family in econ["fams"]:
			if not family.get("gone", false) and not family.get("estate", false): idle += int(family.get("idle", 0))
		for business in econ["biz"]: open += Businesses.takeable(business)
		if mini(idle, open) > 10: capture_towns.append(String(town["id"]))
	capture_trace.append(_capture_observation())
	print("EXACT CAPTURE day=", Game.day, " dynamically selected towns=", capture_towns)

func _capture_observation() -> Dictionary:
	var out := {"day": Game.day, "towns": [], "worst_overlap": 0}
	for town in _towns():
		var econ: Dictionary = town["econ"]
		var row := {"tid": town["id"], "idle": 0, "funded": 0, "families": [], "businesses": []}
		var current_idle := 0; var current_open := 0
		for family in econ["fams"]:
			if not family.get("gone", false) and not family.get("estate", false): current_idle += int(family.get("idle", 0))
		for business in econ["biz"]: current_open += Businesses.takeable(business)
		if mini(current_idle, current_open) > 10 and not capture_towns.has(String(town["id"])): capture_towns.append(String(town["id"]))
		for family in econ["fams"]:
			if family.get("gone", false) or family.get("estate", false): continue
			row["idle"] += int(family.get("idle", 0))
			if capture_towns.has(String(town["id"])):
				row["families"].append({"id": family["id"], "idle": family.get("idle", 0), "last": family.get("last", 0), "adults": Families.adults(family), "serving": Families.serving(family), "hands": family["hands"], "jobs": family["jobs"].duplicate(), "keeps": family.get("keeps", []).duplicate(), "casual": family.get("cj", {}).duplicate(), "hungry": family.get("hungry", 0)})
		for business in econ["biz"]:
			row["funded"] += Businesses.takeable(business)
			if capture_towns.has(String(town["id"])):
				row["businesses"].append({"id": business["id"], "type": business["type"], "owner": business["owner"], "workers": business["workers"], "cap": business["cap"], "till": business["till"], "wage": business["wage"], "owed": business.get("owed", 0), "funded": Businesses.takeable(business), "closed": business.get("closed", false)})
		out["worst_overlap"] = maxi(int(out["worst_overlap"]), mini(int(row["idle"]), int(row["funded"])))
		out["towns"].append(row)
	return out

func _trace_captured_towns() -> void:
	var path := OS.get_environment("BIZ_CAPTURE")
	if path == "": return
	for offset in 10:
		CampaignWorld.presim_step(Game, 1)
		capture_trace.append(_capture_observation())
	var file := FileAccess.open(path.path_join("ordinary-turn-trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"selected": capture_towns, "trace": capture_trace}))
	file.close()
	print("EXACT CAPTURE ordinary next-day overlaps=", capture_trace.map(func(row): return row["worst_overlap"]))
