extends RefCounted
## Research presentation follows actual registered heads and faction progress.
## Fixtures copy generated capitals and people; report reads never repair the live world.

var fails := 0
var checks := 0
var unavailable := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", why)

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	Game.new_game(8263)
	var world: Dictionary = Game.world
	var ids: Array = world["factions"].keys()
	ids.sort()
	var cultures := {}
	var tested := 0
	for fid in ids:
		var tid := String(world["factions"][fid].get("capital", ""))
		var source: Dictionary = world["towns"].get(tid, {})
		if not TownEcon.has_econ(source) or Academy.biz_of(source["econ"]).is_empty():
			continue
		var fixture := _fixture(source, world["factions"][fid], world["research"][fid])
		check(not fixture.is_empty(), "capital supplies two distinct real civilian adults")
		if fixture.is_empty():
			continue
		tested += 1
		cultures[String(source["econ"]["culture"])] = true
		_check_report(fixture)
		_check_vacancies(fixture)
		_check_old_state(fixture)
		_check_missing_house(fixture)
	check(tested >= 3 and cultures.size() >= 3, "several real factions and cultures exercise research presentation")
	check(unavailable > 0, "generated factions include race-unavailable research lines")
	print("TOWN RESEARCH factions=", tested, " cultures=", cultures.keys(), " checks=", checks, " failures=", fails)
	return fails

func _fixture(source: Dictionary, faction: Dictionary, research: Dictionary) -> Dictionary:
	var town := source.duplicate(true)
	var e: Dictionary = town["econ"]
	var b := Academy.biz_of(e)
	var chosen := {}
	var people := []
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		var adults := []
		for p in f.get("pp", []):
			if int(p[6]) == 0 and String(p[4]) in ["", "hire"]:
				adults.append(p)
		if adults.size() < 2:
			continue
		adults.sort_custom(func(a, b): return float(a[3]) < float(b[3]) if float(a[3]) != float(b[3]) else int(a[0]) < int(b[0]))
		var first := Persons.name_of(f, adults[0], Persons.race_of(e))
		for p in adults.slice(1):
			if Persons.name_of(f, p, Persons.race_of(e)) != first:
				chosen = f
				people = [adults[0], p]
				break
		if not people.is_empty():
			break
	if people.is_empty():
		return {}
	# Two real registered employees of the house. The designated second person
	# must be the head even though the ordinary work assignment begins with the first.
	chosen["jobs"] = {str(int(b["id"])): 2}
	chosen["hands"] = 0
	chosen["keeps"] = []
	chosen["cj"] = {}
	b["lead"] = [int(chosen["id"]), int(people[1][0])]
	b["workers"] = 2
	b["cap"] = 3
	b["till"] = 54321.75
	b["state"] = "busy"
	b["why"] = ""
	b["closed"] = false
	var fid := String(town["faction"])
	var tid := String(town["id"])
	var w := {"factions": {fid: faction.duplicate(true)}, "towns": {tid: town}, "research": {fid: research.duplicate(true)}}
	var state: Dictionary = w["research"][fid]
	state["budget"] = 123.75
	state["paid"] = 456.25
	state["hist"] = [[7, 311.5], [14, 623.25]]
	state["out"] = 12.875
	for i in Academy.R()["lines"].size():
		var line: Dictionary = Academy.R()["lines"][i]
		var key := String(line["knowhow"])
		state["kh"][key] = 37.25 if Academy.race_may(key, Academy.faction_race(fid)) else Academy.start_kh(fid, key)
		state["pts"][key] = 12345.625 + i
	return {"world": w, "fid": fid, "tid": tid, "family": int(chosen["id"]),
		"pid": int(people[1][0]), "head": Persons.name_of(chosen, people[1], Persons.race_of(e)),
		"employee": Persons.name_of(chosen, people[0], Persons.race_of(e))}

func _report_read_only(w: Dictionary, fid: String) -> Dictionary:
	var before := w.duplicate(true)
	var report := Academy.report(w, fid)
	check(w == before, "research report leaves original progress, cash and person records unchanged")
	return report

func _check_report(x: Dictionary) -> void:
	var w: Dictionary = x["world"]
	var fid := String(x["fid"])
	var town: Dictionary = w["towns"][x["tid"]]
	var e: Dictionary = town["econ"]
	var b := Academy.biz_of(e)
	var state: Dictionary = w["research"][fid]
	var report := _report_read_only(w, fid)
	check(bool(report["has"]) and report["lead"] == x["head"] and report["lead"] != x["employee"], "head follows the designated real person, not the first employee")
	var keeper := RecData.keeper(e, b)
	check(keeper.get("name", "") == x["head"] and int(keeper.get("fid", -1)) == int(x["family"]) and int(keeper.get("pid", -1)) == int(x["pid"]), "business Records resolve the same designated registered head")
	check(report["name"] == Academy.house_name(e) and report["title"] == Academy.lead_title(e), "house and head title retain their real culture wording")
	check(float(report["budget"]) == 123.75 and float(report["paid"]) == 456.25 and float(report["till"]) == 54321.75, "planned daily budget, actual transfer and current till remain distinct")
	check(float(report["current_week_output"]) == 12.875 and float(report["last_week_output"]) == 623.25 and float(report["funding_day"]) == 14.0, "weekly output and transfer date follow exact saved records")
	check(int(report["workers"]) == 2 and int(report["staff"]) == 1 and int(report["cap"]) == 3, "head is counted once among actual paid places")
	check(float(report["wage"]) == float(b["wage"]) and float(report["lead_wage"]) == float(b["wage"]) * (1.0 + float(Academy.R()["lead_pay"])), "staff offer and head's nominal supplement use actual rates")
	var eligible := ""
	for line in report["lines"]:
		var key := String(line["key"])
		check(float(line["pts"]) == float(state["pts"][key]) and float(line["kh"]) == float(state["kh"][key]), "progress displays exact accumulated points and faction know-how")
		var status := String(TownResearchTab.line_state(report, line)["text"]).to_lower()
		if float(line["kh"]) >= 100.0:
			check(status.contains("complete") and not status.contains("researching"), "starting knowledge at 100 remains completed even outside the race's learning lines")
		elif bool(line["open"]):
			eligible = key
			check(status.contains("researching"), "eligible line in a staffed busy house is researching")
		else:
			unavailable += 1
			check(status.contains("unavailable") and not status.contains("researching"), "race-unavailable line is not labelled researching")
	_work_head(town, String(x["head"]), Academy.lead_title(e))
	_research_view(town, report)
	# No new transfer is needed while a busy house still has actual cash.
	state["paid"] = 0.0
	state["budget"] = 0.0
	var funded := _report_read_only(w, fid)
	check(float(funded["paid"]) == 0.0 and float(funded["till"]) == 54321.75, "zero last transfer does not erase already funded cash")
	check(not String(TownResearchTab.house_state(funded)["text"]).to_lower().contains("unfunded"), "funded till is not called unfunded because transfer was zero")
	for line in funded["lines"]:
		if bool(line["open"]):
			check(String(TownResearchTab.line_state(funded, line)["text"]).to_lower().contains("researching"), "actual busy research is independent of the last transfer amount")
	state["budget"] = 123.75
	state["paid"] = 456.25
	if eligible != "":
		state["kh"][eligible] = 100.0
		var complete := _report_read_only(w, fid)
		for line in complete["lines"]:
			if String(line["key"]) == eligible:
				var status := String(TownResearchTab.line_state(complete, line)["text"]).to_lower()
				check(not bool(line["active"]) and status.contains("complete") and not status.contains("researching"), "completed research keeps its progress and stops its active label")
		_research_view(town, complete)
		state["kh"][eligible] = 37.25

func _check_vacancies(x: Dictionary) -> void:
	for cause in ["died", "service", "job", "town", "legacy_pp"]:
		var w: Dictionary = x["world"].duplicate(true)
		var town: Dictionary = w["towns"][x["tid"]]
		var e: Dictionary = town["econ"]
		var f: Dictionary = e["fams"][int(x["family"])]
		var p := Persons.by_pid(f, int(x["pid"]))
		match cause:
			"died":
				f["pp"].erase(p)
			"service":
				p[4] = "army"
			"job":
				f["jobs"].erase(str(int(e["academy"])))
			"town":
				f["gone"] = true
			"legacy_pp":
				f.erase("pp")
		var report := _report_read_only(w, String(x["fid"]))
		check(bool(report["has"]) and String(report["lead"]) == "", "real head departure leaves the post vacant: " + cause)
		check(String(TownResearchTab.house_state(report)["text"]).to_lower().contains("vacant"), "vacancy is visible rather than a generic keeper dash: " + cause)
		var before := w.duplicate(true)
		check(RecData.keeper(e, Academy.biz_of(e)).is_empty(), "business Records do not substitute a generic worker into a vacant head post: " + cause)
		check(w == before, "head lookup does not initialize missing legacy person arrays")
		for line in report["lines"]:
			check(not String(TownResearchTab.line_state(report, line)["text"]).to_lower().contains("researching"), "vacant house never labels a line researching")
		_work_head(town, "Post vacant", Academy.lead_title(e))

func _check_old_state(x: Dictionary) -> void:
	var fid := String(x["fid"])
	for mode in ["missing_all", "missing_faction", "missing_line"]:
		var w: Dictionary = x["world"].duplicate(true)
		var missing := String(Academy.R()["lines"][0]["knowhow"])
		match mode:
			"missing_all": w.erase("research")
			"missing_faction": w["research"].erase(fid)
			"missing_line":
				w["research"][fid]["kh"].erase(missing)
				w["research"][fid]["pts"].erase(missing)
		var report := _report_read_only(w, fid)
		for line in report["lines"]:
			if mode != "missing_line" or String(line["key"]) == missing:
				check(float(line["kh"]) == Academy.start_kh(fid, String(line["key"])) and float(line["pts"]) == 0.0, "old missing research reads start defaults without writing them")

func _check_missing_house(x: Dictionary) -> void:
	var fid := String(x["fid"])
	for mode in ["captured", "owner_fallback", "missing_house", "missing_capital"]:
		var w: Dictionary = x["world"].duplicate(true)
		var town: Dictionary = w["towns"][x["tid"]]
		match mode:
			"captured": town["faction"] = fid + "_other_realm"
			"owner_fallback":
				town.erase("faction")
				town["econ"]["faction"] = fid + "_other_realm"
			"missing_house": town["econ"].erase("academy")
			"missing_capital": w["towns"].erase(x["tid"])
		var report := _report_read_only(w, fid)
		check(not bool(report["has"]), "no owned research house is exposed: " + mode)
		for field in ["name", "title", "lead", "till", "workers", "bid"]:
			check(not report.has(field), "foreign or absent house does not leak its " + field)
		for line in report["lines"]:
			check(not String(TownResearchTab.line_state(report, line)["text"]).to_lower().contains("researching"), "unheld house cannot claim actual research")
		_research_view(town, report)

func _research_view(town: Dictionary, report: Dictionary) -> void:
	var host := Control.new()
	var body := VBoxContainer.new()
	var before := report.duplicate(true)
	TownResearchTab.build_report(host, town, body, report)
	check(report == before, "native Research view leaves its snapshot unchanged")
	var texts := _texts(body)
	var budget := _field_value(body, "Planned budget")
	var transfer := _field_value(body, "Last state transfer")
	check(budget.begins_with("%.1f" % float(report["budget"])) and budget.contains("/day"), "native funding row displays the planned daily budget")
	check(transfer.begins_with("%.1f" % float(report["paid"])), "native transfer row displays actual paid coins separately")
	if int(report["funding_day"]) >= 0:
		check(transfer.contains("Day %d" % (int(report["funding_day"]) + 1)), "transfer row uses the recorded day in player-facing day numbering")
	if bool(report["has"]):
		check(texts.has(String(report["title"])) and texts.has(String(report["lead"]) if String(report["lead"]) != "" else "Post vacant"), "native Research card shows actual culture head/title")
		check(_field_value(body, "Cash in till") == "%.1f coins" % float(report["till"]), "native till card displays the actual cash separately from state funding")
	else:
		check(_field_value(body, "Cash in till") == "" and _field_value(body, "State-funded house") == "", "absent or foreign capital exposes no house or till card")
	for line in report["lines"]:
		var key := String(line["key"])
		var box := body.find_child("Knowledge_" + key, true, false)
		check(box != null and _texts(box).has("%.1f%%" % float(line["kh"])), "native knowledge number comes from the faction's actual saved know-how")
		var progress := body.find_child("KnowHow_" + key, true, false) as ProgressBar
		if bool(line["open"]):
			check(progress != null and progress.value == float(line["kh"]), "native progress bar preserves exact know-how, including completed lines")
		else:
			check(progress == null, "unavailable learning line has no misleading learning bar")
		check(texts.has("%.1f" % float(line["pts"])), "native point cell displays the saved accumulated points")
	body.free()
	host.free()

func _field_value(node: Node, key: String) -> String:
	if node.get_child_count() >= 2 and node.get_child(0) is Label and node.get_child(1) is Label:
		if (node.get_child(0) as Label).text == key:
			return (node.get_child(1) as Label).text
	for child in node.get_children():
		var value := _field_value(child, key)
		if value != "":
			return value
	return ""

func _work_head(town: Dictionary, expected: String, title: String) -> void:
	var host := Control.new()
	var body := VBoxContainer.new()
	TownEconTab._work(host, town, body)
	var texts := _texts(body)
	check(texts.has(title + "\n" + expected), "Work table shows the actual research head/title or vacancy")
	body.free()
	host.free()

func _texts(node: Node) -> Array:
	var texts := []
	if node is Label:
		texts.append((node as Label).text)
	for child in node.get_children():
		texts.append_array(_texts(child))
	return texts
