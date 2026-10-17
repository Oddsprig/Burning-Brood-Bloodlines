extends RefCounted
## Differential records checks: frozen v0.033 staff/non-Academy keepers, designated Academy heads.
## No performance gate is relaxed.
## Timings are diagnostic; test_ui_records and test_ui_load_times keep the existing device gates.

var fails := 0
var checks := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", text)

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.new_game(11)
	_census_reads()
	_academy_keeper_reads()
	var towns := 0
	var businesses := 0
	var old_us := 0
	var new_us := 0
	for t: Dictionary in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		towns += 1
		var e: Dictionary = t["econ"]
		var expected := []
		var started := Time.get_ticks_usec()
		for b: Dictionary in RecData.biz(e):
			expected.append([_expected_keeper(e, b), _old_staff(e, int(b["id"]))])
		old_us += Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		var context := RecData.work_context(e)
		var actual := []
		for i in RecData.biz(e).size():
			var b: Dictionary = RecData.biz(e)[i]
			var keeper := RecData.keeper(e, b, context)
			var staff := RecData.staff(e, int(b["id"]), context)
			actual.append([keeper, staff])
		new_us += Time.get_ticks_usec() - started
		for i in actual.size():
			check(actual[i][0] == expected[i][0], "every business keeps its expected keeper identity, name and explanation")
			check(actual[i][1] == expected[i][1], "every business keeps staff order, names, person IDs, titles and actual wages")
			businesses += 1
		# A fresh build in the same frame must observe ordinary edits, including legacy integer keys.
		for f: Dictionary in RecData.fams(e):
			if (f.get("jobs", {}) as Dictionary).is_empty(): continue
			var jobs: Dictionary = f["jobs"]
			var original := jobs.duplicate()
			var key: Variant = jobs.keys()[0]
			var bid := int(key)
			var b: Dictionary = RecData.biz(e)[bid]
			var wage := float(b["wage"])
			jobs.erase(key)
			jobs[bid] = original[key]
			b["wage"] = wage + 1.25
			var fresh := RecData.work_context(e)
			check(RecData.staff(e, bid, fresh) == _old_staff(e, bid), "same-frame build reads integer job keys and current wages")
			check(RecData.keeper(e, b, fresh) == _expected_keeper(e, b), "same-frame build keeps keeper precedence after job/wage edits")
			var states := []
			for p in Persons.pp(f):
				states.append(p[4])
				p[4] = "army"
			fresh = RecData.work_context(e)
			check(RecData.staff(e, bid, fresh) == _old_staff(e, bid) and RecData.keeper(e, b, fresh) == _expected_keeper(e, b), "fresh build observes real away service instead of cached household work")
			for i in Persons.pp(f).size(): Persons.pp(f)[i][4] = states[i]
			f["gone"] = true
			fresh = RecData.work_context(e)
			check(RecData.staff(e, bid, fresh) == _old_staff(e, bid), "fresh staff build excludes a departed family")
			f["gone"] = false
			jobs.clear()
			jobs.merge(original)
			b["wage"] = wage
			break
	_table_refresh()
	print("RECORDS LOOKUP towns=", towns, " businesses=", businesses, " old_ms=", old_us / 1000.0, " indexed_ms=", new_us / 1000.0)
	print("RECORDS PERFORMANCE checks=", checks, " failures=", fails)
	return fails

func _census_reads() -> void:
	var w: Dictionary = Game.world
	check(Census.balance_of(w, w["towns"].keys()) == _old_census_balance_of(w, w["towns"].keys()), "world census preserves every current, prior and event total")
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t): continue
		check(Census.balance_of(w, [tid]) == _old_census_balance_of(w, [tid]), "each town census equals the original simulation book")
	var e := {"stock": {}, "fams": [
		{"m": 2, "f": 1, "kids": 3, "old": 1},
		{"m": 1, "f": 1, "kids": 9, "old": 0, "gone": true},
		{"m": 1, "f": 1, "kids": 4, "old": 0, "estate": true}]}
	var fixture := {"towns": {"a": {"econ": e}, "no_economy": {}}}
	var ids := ["a", "no_economy", "missing"]
	check(Census.balance_of(fixture, ids) == _old_census_balance_of(fixture, ids), "legacy empty census rows, gone/estate families and missing economies match")
	var book := Census._book(e)
	book["rows"] = [{"people": 12}]
	book["cur"]["births"] = 2
	book["cur"]["deaths"] = {"old age": 1, "sickness": 2}
	book["cur"]["arrived"] = {"work": 4}
	book["cur"]["left"] = {"war": 8}
	e["fams"][0]["kids"] = 4
	var fresh := Census.balance_of(fixture, ids)
	check(fresh == _old_census_balance_of(fixture, ids) and fresh["people"] == 8 and fresh["last"] == 12 and fresh["change"] == -4,
		"same-frame census refresh retains current children, exact dated baseline and all event causes")

# Frozen population/balance read, keeping the old dynamic per-family call as an independent oracle.
func _old_census_people(e: Dictionary) -> int:
	var n := 0
	for f in e.get("fams", []):
		if f.get("gone", false) or f.get("estate", false): continue
		n += Families.people(f)
	return n

func _old_census_balance_of(w: Dictionary, tids: Array) -> Dictionary:
	var out := {"births": 0, "deaths": 0, "arrived": 0, "left": 0, "people": 0, "last": 0, "change": 0}
	for tid in tids:
		var t: Dictionary = w["towns"].get(tid, {})
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		var b := Census._book(e)
		var cur: Dictionary = b["cur"]
		var rs: Array = b["rows"]
		var last := int(rs[-1]["people"]) if not rs.is_empty() else _old_census_people(e)
		var now := _old_census_people(e)
		var balance := {"births": int(cur["births"]), "deaths": Census.sum(cur["deaths"]), "arrived": Census.sum(cur["arrived"]), "left": Census.sum(cur["left"]),
			"people": now, "last": last, "change": now - last}
		for key in out: out[key] = int(out[key]) + int(balance[key])
	return out

func _table_refresh() -> void:
	var changed := ["old details"]
	var taps := [0, 0]
	var rows := []
	for i in 40:
		var id := i
		rows.append({"name": "Family %02d" % i, "n": i % 5,
			"_l": "Family %02d" % i, "_r": "%d coins" % i,
			"_d": func(): return changed[0] if id == 0 else "Record %d" % id,
			"_tap": func(): taps[0] += 1})
	var table := RecTable.make([{"k": "name", "t": "Family"}, {"k": "n", "t": "People", "num": true}], rows, "name", true,
		[{"t": "Group", "opts": ["all", "large"], "fn": func(r, _o): return int(r["n"]) >= 3}], true)
	var first: Button = table._rows_box.get_child(0)
	first.pressed.emit()
	check(taps == [1, 0], "initial native row performs its original action")
	var button: Button = table._rows_box.get_child(RecTable.LIMIT)
	var start := Time.get_ticks_usec()
	button.pressed.emit()
	print("RECORDS show_more_ms=", (Time.get_ticks_usec() - start) / 1000.0)
	check(table.limit == 30 and table._rows_box.get_child_count() == 31, "Show more keeps page size and next-page button")
	check(table._rows_box.get_child(0) == first, "Show more retains an identical visible native row")
	for i in 30:
		check(table._rows_box.get_child(i).get_meta("rec_row") == ["Family %02d" % i, "%d coins" % i, changed[0] if i == 0 else "Record %d" % i],
			"Show more displays every full record in its original order")
	changed[0] = "current details"
	table._refresh()
	var current: Button = table._rows_box.get_child(0)
	check(current != first and current.get_meta("rec_row")[2] == "current details", "refresh re-evaluates already displayed lazy details in the same frame")
	check(current.tooltip_text.contains("current details") and current.accessibility_description == "current details", "fresh details reach tooltip and accessibility text")
	rows[0]["_tap"] = func(): taps[1] += 1
	rows[0]["_col"] = UiTheme.BAD
	table._refresh()
	var actionable: RecRow = table._rows_box.get_child(0)
	actionable.pressed.emit()
	check(taps == [1, 1] and actionable.right_color == UiTheme.BAD, "same text with changed callback/color gets its current action and status")
	for key in ["name", "n"]:
		for direction in 2:
			table.sort_by(key)
			_compare_rendered(table)
	table.set_filter("Group", "large")
	_compare_rendered(table)
	table.search = "family 1"
	table._refresh()
	_compare_rendered(table)
	table.search = "absent"
	table._refresh()
	check(table._rows_box.get_child_count() == 1 and table._rows_box.get_child(0) is Label and table._rows_box.get_child(0).text == "Nothing to show.", "empty searches remove prior rows and retain the empty message")
	table.search = ""
	table.set_filter("Group", "all")
	_compare_rendered(table)
	table.free()

func _compare_rendered(table: RecTable) -> void:
	var expected := table.shown()
	for i in mini(expected.size(), table.limit):
		var r: Dictionary = expected[i]
		check(table._rows_box.get_child(i).get_meta("rec_row") == [r["_l"], r["_r"], (r["_d"] as Callable).call()], "sort, reverse, filter and search keep displayed row information")
	check(table._count.text == "%d shown of %d" % [mini(expected.size(), table.limit), table.rows.size()], "count agrees with current filter, search and page")

# Only the Academy expectation changed after v0.033: its registered head is a state post.
# Read the register and paid household place directly; never derive an expectation from
# RecData.keeper, Academy.lead_name/lead_gone, or whichever employee comes first.
func _expected_keeper(e: Dictionary, b: Dictionary) -> Dictionary:
	if String(b.get("type", "")) != "academy":
		return _old_keeper(e, b)
	var lead: Array = b.get("lead", [])
	var families: Array = e.get("fams", [])
	if lead.size() < 2 or int(lead[0]) < 0 or int(lead[0]) >= families.size():
		return {}
	var f: Dictionary = families[int(lead[0])]
	if f.get("gone", false):
		return {}
	var person: Array = []
	for slots in [f.get("pp", []), f.get("kp", [])]:
		for p: Array in slots:
			if int(p[0]) == int(lead[1]) and int(lead[1]) >= 0:
				person = p
				break
		if not person.is_empty(): break
	if person.is_empty() or int(person[6]) == 1 or not String(person[4]) in ["", "hire"]:
		return {}
	# Academy's saved paid-place contract uses the canonical string business key.
	if int((f.get("jobs", {}) as Dictionary).get(str(int(b["id"])), 0)) <= 0:
		return {}
	return {"fid": int(lead[0]), "pid": int(lead[1]), "name": Persons.name_of(f, person, Persons.race_of(e)),
		"how": _academy_head_title(e) + " (state-funded head)"}

func _academy_head_title(e: Dictionary) -> String:
	var culture := String(e.get("culture", "middle"))
	var data := TownEcon.data()
	var row: Dictionary = data["cultures"].get(culture, {})
	var names: Dictionary = data["research"]["names"]
	var fallback: Array = names.get(culture, names["_race"].get(Persons.race_of(e), names["_default"])) if culture != "_race" else names["_default"]
	return String(row.get("research_lead", fallback[1]))

func _academy_keeper_reads() -> void:
	var first := {"id": 0, "name": "Earlier staff household", "jobs": {"0": 1}, "kp": [],
		"pp": [[4, 0, 0, -15000, "", -1, 0, "Earlier Employee"]]}
	var head := {"id": 1, "name": "Designated household", "jobs": {"0": 1}, "kp": [],
		"pp": [[16, 0, 0, -12000, "", -1, 0, "Other Adult"], [17, 0, 0, -10000, "", -1, 0, "Registered Head"]]}
	var b := {"id": 0, "type": "academy", "owner": -1, "kw": 0, "wage": 12.5, "skill": 1.0, "lead": [1, 17]}
	var e := {"culture": "middle", "academy": 0, "biz": [b], "fams": [first, head]}
	check(_expected_keeper(e, b) == {"fid": 1, "pid": 17, "name": "Registered Head", "how": "Master (state-funded head)"},
		"Academy oracle requires the exact registered head and state-funded title")
	check(_old_keeper(e, b)["pid"] == 4, "Academy fixture has an earlier employee who is not its designated head")
	_academy_reads_match(e, "designated younger adult, after another household's employee")
	var initial_staff := _old_staff(e, 0)
	check(initial_staff.size() == 2 and initial_staff[0]["pid"] == 4 and initial_staff[1]["pid"] == 17,
		"Academy staff retains household order and the designated person's actual paid place")

	b["lead"] = []
	check(_expected_keeper(e, b).is_empty() and not _old_staff(e, 0).is_empty(), "vacant Academy has paid employees but no replacement head")
	_academy_reads_match(e, "empty head post with other paid staff")
	b["lead"] = [1, 17]
	for service in ["army", "reserve", "hire", ""]:
		head["pp"][1][4] = service
		check(_expected_keeper(e, b).is_empty() == (service in ["army", "reserve"]), "Academy head eligibility follows the current service role: " + service)
		_academy_reads_match(e, "same-frame head service role " + service)
	head["pp"][1][6] = 1
	_academy_reads_match(e, "retired head with another working adult")
	check(_expected_keeper(e, b).is_empty(), "retired registered head cannot be replaced by a working adult")
	head["pp"][1][6] = 0
	head["pp"][1][7] = "Renamed Head"
	b["wage"] = 18.75
	b["skill"] = 4.0
	_academy_reads_match(e, "same-frame name, actual wage and staff trade-title edits")
	check(_expected_keeper(e, b)["name"] == "Renamed Head", "head read observes the current registered name")
	var paid_staff := RecData.staff(e, 0, RecData.work_context(e))
	check(paid_staff.all(func(row): return float(row["wage"]) == 18.75) and paid_staff[0]["title"] == "chemist",
		"same-frame staff reads current wages and learned trade without losing any row")
	b["lead"] = [1, 16]
	_academy_reads_match(e, "same-frame designation changes to another registered person")
	check(_expected_keeper(e, b)["pid"] == 16 and _expected_keeper(e, b)["name"] == "Other Adult", "new designation changes both exact person ID and name")
	b["lead"] = [1, 17]
	for paid_places in [0, 1]:
		head["jobs"]["0"] = paid_places
		check(_expected_keeper(e, b).is_empty() == (paid_places == 0), "head requires a current paid Academy household place")
		_academy_reads_match(e, "same-frame paid head place count %d" % paid_places)
	head["jobs"].erase("0")
	head["jobs"][0] = 1
	_academy_reads_match(e, "legacy integer paid job remains staff, without canonical head place")
	check(_expected_keeper(e, b).is_empty() and _old_staff(e, 0).size() == 2, "legacy integer job does not invent a canonical Academy head appointment")
	head["jobs"].erase(0)
	head["jobs"]["0"] = 1
	head["gone"] = true
	_academy_reads_match(e, "departed designated household")
	check(_expected_keeper(e, b).is_empty(), "departed household cannot retain the head post")
	head.erase("gone")
	for designation in [[1, 999], [-1, 17], [99, 17], [1]]:
		b["lead"] = designation
		_academy_reads_match(e, "missing person or invalid family/designation %s" % str(designation))
		check(_expected_keeper(e, b).is_empty(), "invalid head identity never falls back to another employee")
	b["lead"] = [1, 17]
	var registered: Array = head["pp"].pop_back()
	_academy_reads_match(e, "head removed from live register")
	check(_expected_keeper(e, b).is_empty(), "a removed head's colleague does not inherit the post")
	head["pp"].append(registered)
	b["owner"] = 0
	b["kw"] = 1
	first["keeps"] = [0]
	check(_old_keeper(e, b)["how"] == "of the owning family", "owner fixture exercises actual private-keeper precedence")
	_academy_reads_match(e, "legacy owner metadata cannot override a designated state head")
	b["lead"] = []
	_academy_reads_match(e, "legacy owner at work cannot fill a vacant state head post")
	check(_expected_keeper(e, b).is_empty(), "Academy vacancy remains empty even with an owning-family keeper")
	b["owner"] = -1
	b["kw"] = 0
	first.erase("keeps")
	b["lead"] = [1, 17]
	head.erase("kp")
	_academy_keeper_matches(e, "old save missing children array")
	check(not head.has("kp"), "head lookup does not initialize missing legacy children")
	head.erase("pp")
	_academy_reads_match(e, "old save missing both register arrays")
	check(not head.has("pp") and not head.has("kp"), "vacant old-save reads do not materialize person arrays")
	b.erase("lead")
	_academy_reads_match(e, "old Academy save without a designated head field")
	check(not b.has("lead"), "browsing an old Academy does not create an appointment")

func _academy_keeper_matches(e: Dictionary, label: String) -> void:
	var before := var_to_bytes(e)
	var b: Dictionary = e["biz"][0]
	var expected := _expected_keeper(e, b)
	check(RecData.keeper(e, b) == expected, "Academy direct keeper: " + label)
	check(RecData.keeper(e, b, RecData.work_context(e)) == expected, "Academy fresh-context keeper: " + label)
	check(var_to_bytes(e) == before, "Academy keeper read is pure: " + label)

func _academy_reads_match(e: Dictionary, label: String) -> void:
	_academy_keeper_matches(e, label)
	var before := var_to_bytes(e)
	# The frozen staff oracle may initialize old person arrays; isolate its read,
	# preserving its exact output while testing production reads for mutation.
	var expected := _old_staff(e.duplicate(true), 0)
	check(RecData.staff(e, 0) == expected, "Academy direct staff preserves every ordered field: " + label)
	check(RecData.staff(e, 0, RecData.work_context(e)) == expected, "Academy fresh-context staff preserves every ordered field: " + label)
	check(var_to_bytes(e) == before, "Academy staff read is pure: " + label)

# Frozen v0.033 lookup, deliberately unchanged for every non-Academy business.
func _old_keeper(e: Dictionary, b: Dictionary) -> Dictionary:
	var bid := int(b["id"])
	var owner := int(b.get("owner", -1))
	var race := Persons.race_of(e)
	if owner >= 0:
		var f := RecData.fam(e, owner)
		if not f.is_empty():
			if String(b["type"]) == "farm":
				var hp := Persons.head_of(f)
				if not hp.is_empty():
					return {"fid": owner, "pid": int(hp[0]), "name": Persons.name_of(f, hp, race), "how": "head of the family"}
			elif int(b.get("kw", 0)) > 0:
				var wk := Persons.work(e, f)
				for pid in wk:
					var j: Dictionary = wk[pid]
					if j.get("keeper", false) and int(j.get("biz", -1)) == bid:
						var p := Persons.by_pid(f, int(pid))
						return {"fid": owner, "pid": int(pid), "name": Persons.name_of(f, p, race) if not p.is_empty() else String(f["name"]), "how": "of the owning family"}
	var st := _old_staff(e, bid)
	if not st.is_empty():
		return {"fid": int(st[0]["fid"]), "pid": int(st[0]["pid"]), "name": String(st[0]["name"]), "how": "of the staff"}
	return {}

func _old_staff(e: Dictionary, bid: int) -> Array:
	var out := []
	var race := Persons.race_of(e)
	for f in RecData.fams(e):
		if not (f.get("jobs", {}) as Dictionary).has(bid) and not (f.get("jobs", {}) as Dictionary).has(str(bid)):
			continue
		var wk := Persons.work(e, f)
		for pid in wk:
			var j: Dictionary = wk[pid]
			if int(j.get("biz", -1)) == bid and not j.get("keeper", false):
				var p := Persons.by_pid(f, int(pid))
				out.append({"fid": int(f["id"]), "pid": int(pid), "name": Persons.name_of(f, p, race) if not p.is_empty() else String(f["name"]), "title": String(j["title"]), "wage": float(j["wage"])})
	return out
