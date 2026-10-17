extends RefCounted
## The records screen (ui/records.gd; town spec 08-10, world spec 11-12, addendum 13), headless on a generated world
## after a short stretch of its own sim: every town tab, every world tab and every faction tab builds without a
## SCRIPT ERROR (tools/test.sh fails the run on one) at phone size 720x1280, where every button is >= 48 px tall,
## list rows >= 64 px, and nothing but the tab bar runs wider than the screen. Detail pages (family, person,
## business, force, the dead of a cause), the selector (every town once, under its faction) and sorting
## (every column, again reverses, filters) are checked too. Tab build times are printed (spec: < 16 ms).

const PHONE := Vector2(720, 1280)
const TOL := 1.5

var fails := 0
var tree: SceneTree
var times := {}
var _rows_seen := 0
var _bad_num := RegEx.create_from_string("\\b(nan|inf|-nan|-inf)\\b")

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)

func run(st: SceneTree) -> int:
	tree = st
	await tree.process_frame
	Game.new_game(11)
	CampaignWorld.presim_step(Game, 40)
	_sort_test()
	_data_reads_test()
	var w: Dictionary = Game.world
	var tid := ""
	for k in w["towns"]:
		if not (w["towns"][k].get("recruits", []) as Array).is_empty() and Militia.units_of(Game, k).size() > 0:
			tid = k
			break
	check(tid != "", "a town with recruits and militia")
	Game.location = tid
	var sv := SubViewport.new()
	sv.size = Vector2i(PHONE)
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(sv)
	Game.screen_params = {"back": "town"}
	var s: Node = (load("res://ui/records.tscn") as PackedScene).instantiate()
	sv.add_child(s)
	await _settle()
	check(String(s.view) == "town" and String(s.sel) == tid, "opens on the town the company is in (%s %s)" % [s.view, s.sel])
	# ---------------------------------------------------------------- every town tab
	for tb in s.TOWN_TABS:
		await _tab(s, tb, "town " + tb)
		_check_fit(sv, "town " + tb)
		if tb == "Garrison":
			var roster := _find_table(s)
			var units := TownDefence.garrison(Game, tid)
			check(roster != null and roster.rows.size() == units.size(), "Garrison retains every defender")
			if roster != null:
				for i in roster.rows.size():
					var row: Dictionary = roster.rows[i]
					var real := Persons.roster_row(Game, units[i], "militia")
					check(int((row["age"] as Callable).call()) == int(real["age"]) and float((row["years"] as Callable).call()) == float(real["years_served"]),
						"lazy Garrison sort values retain the person's real age and service")
					check(String((row["_d"] as Callable).call()).contains(String(real["weapon"])) and float(row["pay"]) == float(real["pay_day"]),
						"lazy Garrison details retain equipment and exact current pay")
				roster.sort_by("age")
				var sorted := roster.shown()
				for i in range(1, sorted.size()):
					check(int((sorted[i-1]["age"] as Callable).call()) >= int((sorted[i]["age"] as Callable).call()), "Garrison sorts live ages largest first")
				_more_rows(roster)
	# detail pages from the town
	var t: Dictionary = w["towns"][tid]
	var e: Dictionary = t["econ"]
	var fam: Dictionary = RecData.fams(e)[0]
	s.open_family(t, int(fam["id"]))
	await _settle()
	_check_fit(sv, "family page")
	var pp: Array = Persons.pp(fam)
	if not pp.is_empty():
		s.open_person(t, int(fam["id"]), int(pp[0][0]))
		await _settle()
		_check_fit(sv, "person page")
	s.go_back(); s.go_back()
	for b in RecData.biz(e):
		if int(b.get("workers", 0)) > 0:
			s.open_business(t, int(b["id"]))
			break
	await _settle()
	_check_fit(sv, "business page")
	s.go_back()
	var mil := Militia.band_of(Game, tid)
	if not mil.is_empty():
		s.open_force(String(mil["id"]))
		await _settle()
		_check_fit(sv, "force page")
		s.go_back()
	s.open_unit(t["recruits"][0])
	await _settle()
	_check_fit(sv, "recruit page")
	s.go_back()
	s.page("dead", func(b): RecTown.dead_list(s, w, [tid], "old age", b))
	await _settle()
	_check_fit(sv, "dead list")
	s.go_back()
	# the Sickness tab reads campaign/sickness.gd (06-sickness.md 7): its header numbers are the sim's
	s.show_tab("Sickness")
	await _settle()
	var sm := Sickness.town_summary(t)
	check(_has_text(s, "Sick now: %d" % int(sm["sick_now"])) and _has_text(s, "Bed-ridden: %d" % int(sm["bed_now"])),
		"Sickness tab header reads town_summary (%s)" % str(sm.get("sick_now")))
	check(not _has_text(s, "does not read it yet"), "Sickness tab no longer says it does not read the sim")
	s.page("sick", func(b): RecTown.sick_list(s, t, "", b))
	await _settle()
	_check_fit(sv, "sick list")
	s.go_back()
	s.show_tab("Overview")
	await _settle()
	check(_has_text(s, "Sick now"), "Overview shows sick now")
	# Overview -> Register filtered by state
	s.goto_tab("Register", {"State": "comfortable"})
	await _settle()
	var tbl := _find_table(s)
	check(tbl != null and String(tbl.fsel.get("State", "")) == "comfortable", "the Register opens filtered from the Overview")
	if tbl != null:
		for r in tbl.shown():
			if String(r["state"]) != "comfortable":
				check(false, "filtered Register shows only comfortable families")
				break
		tbl.sort_by("purse")
		var sh := tbl.shown()
		for i in range(1, sh.size()):
			if float(sh[i - 1]["purse"]) < float(sh[i]["purse"]):
				check(false, "Register sorted by purse, biggest first")
				break
	# ---------------------------------------------------------------- the selector: every town once, under its faction
	var ents: Array = s.selector_entries("")
	var seen := {}
	var cur_fac := ""
	for en in ents:
		if en["view"] == "faction":
			cur_fac = String(en["id"])
		elif en["view"] == "town" and not String(en["text"]).begins_with("Here"):
			seen[en["id"]] = int(seen.get(en["id"], 0)) + 1
			check(String(w["towns"][en["id"]]["faction"]) == cur_fac, "%s listed under its own faction" % en["id"])
	for k in w["towns"]:
		check(int(seen.get(k, 0)) == 1, "selector lists %s exactly once (%d)" % [k, int(seen.get(k, 0))])
	check(not s.selector_entries(RecData.tname(tid).substr(0, 4)).is_empty(), "selector search finds the town")
	s.open_selector()
	await _settle()
	_check_fit(sv, "selector")
	while s.has_node("Modal"):
		s.get_node("Modal").free()
	# ---------------------------------------------------------------- the whole world and a faction
	s.set_view("world")
	for tb in s.WORLD_TABS:
		await _tab(s, tb, "world " + tb)
		_check_fit(sv, "world " + tb)
		if tb == "Fights":
			var legends_button: Button = _find_button(s, "View legendary arms")
			check(legends_button != null, "Fights offers legendary arms detail")
			if legends_button != null:
				legends_button.pressed.emit()
				await _settle()
				check(_has_text(s, "Unique pieces made by real smiths"), "legendary arms button opens the actual detail")
				s.go_back()
				await _settle()
				check(_find_button(s, "View legendary arms") != null, "legendary arms Back returns to Fights")

		if tb == "On the move":   # every force on the map exactly once
			var mt := _find_table(s)
			check(mt != null and mt.rows.size() == (w["warbands"] as Dictionary).size(), "On the move lists every force once (%d of %d)" % [
				mt.rows.size() if mt != null else -1, (w["warbands"] as Dictionary).size()])
			if mt != null:
				for row in mt.rows:
					check(row["_d"] is Callable, "force details use the list's lazy row renderer")
				var first: Dictionary = mt.shown()[0]
				var detail := String((first["_d"] as Callable).call())
				check(detail.contains("near ") and detail.contains("supply "), "lazy force row retains location and supply information")
				_more_rows(mt)
		if tb == "Towns":
			await _detail(s, sv, "View town price and wealth spreads", ["Food price index", "Copper bar price", "Wealth a person", "Food days", "Families in hardship %"])
		if tb == "Goods":
			var ht := _find_table(s)
			check(ht != null and ht.rows.size() == s.tids().size(), "Goods keeps every town's herd row available")
			if ht != null:
				for row in ht.rows:
					var he := RecData.econ(RecData.town(String(row["tid"])))
					check(String((row["_d"] as Callable).call()).begins_with(RecTown.herd_text(he, RecData.herds(he))), "paged herd row retains its live head counts")
				_more_rows(ht)
		if tb == "Mines & land":
			var family_acres := 0; var estate_acres := 0
			for town_id in s.tids():
				var land := RecData.land(RecData.econ(RecData.town(town_id)))
				family_acres += int(land["families"]); estate_acres += int(land["estate"])
			await _detail(s, sv, "View land and herds", ["Acres: %d held by families, %d by the towns" % [family_acres, estate_acres], "Pasture, woodland"])
		if tb == "Census":
			await _detail(s, sv, "View census by race", ["By race", "This year = the year now", "hungry households", "homeless households"])
			var before_people := Census.people(e)
			var child_count := int(fam["kids"])
			var before_box := RecWorld.build(s, [tid], "", "Food flows")
			fam["kids"] = child_count + 1
			var after_box := RecWorld.build(s, [tid], "", "Food flows")
			check(_has_text(before_box, "%d people;" % before_people) and _has_text(after_box, "%d people;" % (before_people + 1)), "rebuilding records in one frame reads fresh live population")
			fam["kids"] = child_count
			before_box.free(); after_box.free()
	s.set_view("faction", String(t["faction"]))
	for tb in s.FACTION_TABS:
		await _tab(s, tb, "faction " + tb)
		_check_fit(sv, "faction " + tb)
	s.set_view("town", tid)
	check(String(s.view) == "town", "back to a town from the selector")
	var worst := ""; var wt := 0.0
	for k in times:
		if float(times[k]) > wt:
			wt = float(times[k]); worst = k
	print("tab build times (ms): ", times)
	print("slowest tab: %s %.1f ms (spec: < 16 ms on the laptop)" % [worst, wt])
	check(wt < 16.0, "tab switch < 16 ms (slowest: %s %.1f ms; rerun alone if the machine is busy)" % [worst, wt])
	sv.queue_free()
	await tree.process_frame
	Game.location = ""
	return fails

## Shows a tab twice (the second build is warm: scripts compiled, fonts cached) and keeps the faster time.
func _tab(s: Node, tb: String, key: String) -> void:
	s.show_tab(tb)
	var a := float(s.tab_ms)
	await _settle()
	s.show_tab(tb)
	times[key] = minf(a, float(s.tab_ms))
	await _settle()

func _settle() -> void:
	for i in 2:
		await tree.process_frame

## Any Label under n (or a row's first line) containing txt.
func _has_text(n: Node, txt: String) -> bool:
	if n is Label and (n as Label).text.contains(txt):
		return true
	if n.has_meta("rec_row"):
		for value in n.get_meta("rec_row"):
			if String(value).contains(txt): return true
	for c in n.get_children():
		if _has_text(c, txt):
			return true
	return false

func _find_table(n: Node) -> RecTable:
	if n is RecTable:
		return n
	for c in n.get_children():
		var r := _find_table(c)
		if r != null:
			return r
	return null

## Nothing wider than the phone (the tab bar scrolls sideways and is skipped); buttons >= 48 px, rows >= 64 px.
func _check_fit(sv: SubViewport, label: String) -> void:
	var bad := []
	_rows_seen = 0
	_walk(sv, bad)
	if _rows_seen == 0 and label.begins_with("town ") and not label in ["town Sickness", "town Books"]:
		bad.append("no tappable rows built")
	if not bad.is_empty():
		fails += 1
		printerr("FAIL: %s at 720x1280: %d problems:" % [label, bad.size()])
		for i in mini(bad.size(), 6):
			printerr("    ", bad[i])

func _walk(n: Node, bad: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Label and _bad_num.search((n as Label).text) != null:   # every number reads a real field: never NaN or infinite
		bad.append("bad number in '%s'" % (n as Label).text.substr(0, 80))
	if n is ScrollContainer and (n as ScrollContainer).horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		var r0 := (n as Control).get_global_rect()
		if r0.end.x > PHONE.x + TOL:
			bad.append("tab bar wider than the screen %s" % r0)
		for c in n.get_children():
			_buttons_only(c, bad)
		return
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		if r.size.x > 0.5 and (r.end.x > PHONE.x + TOL or r.position.x < -TOL):
			if not _child_over(c):
				bad.append("too wide: %s '%s' %s" % [c.get_class(), String(c.get("text")) if "text" in c else "", r])
		if c is Button and r.size.y < 48.0 - TOL:
			bad.append("button under 48 px: '%s' %s" % [(c as Button).text, r])
		if c.has_meta("rec_row"):
			_rows_seen += 1
			for value in c.get_meta("rec_row"):
				if _bad_num.search(String(value)) != null:
					bad.append("bad number in row '%s'" % String(value).substr(0, 80))
			if r.size.y < 64.0 - TOL:
				bad.append("row under 64 px: %s" % [c.get_meta("rec_row")])
	for ch in n.get_children():
		_walk(ch, bad)

## Only report the deepest offender.
func _child_over(c: Control) -> bool:
	for ch in c.get_children():
		if ch is Control and (ch as Control).visible:
			var r := (ch as Control).get_global_rect()
			if r.size.x > 0.5 and r.end.x > PHONE.x + TOL:
				return true
	return false

func _buttons_only(n: Node, bad: Array) -> void:
	if n is Button and (n as Button).get_global_rect().size.y < 48.0 - TOL:
		bad.append("tab under 48 px: %s" % (n as Button).text)
	for c in n.get_children():
		_buttons_only(c, bad)

## RecTable sorting: every column, the same column again reverses, numbers biggest first, names A-Z, filters, search.
func _sort_test() -> void:
	var rows := []
	var data := [["Cobb", 3, 10.0], ["abel", 1, null], ["Bram", 2, 5.5], ["Dane", 2, 7.0]]
	for d in data:
		rows.append({"name": d[0], "n": d[1], "x": d[2], "_l": d[0], "_s": d[0]})
	var tb := RecTable.make([{"k": "name", "t": "Name"}, {"k": "n", "t": "N", "num": true}, {"k": "x", "t": "X", "num": true}], rows, "name", true,
		[{"t": "Big", "opts": ["all", "big"], "fn": func(r, o): return int(r["n"]) >= 2}], true)
	var names := func() -> Array: return tb.shown().map(func(r): return r["name"])
	check(names.call() == ["abel", "Bram", "Cobb", "Dane"], "sort by name A-Z: %s" % [names.call()])
	tb.sort_by("name")
	check(names.call() == ["Dane", "Cobb", "Bram", "abel"], "same column again reverses: %s" % [names.call()])
	tb.sort_by("n")
	check(names.call() == ["Cobb", "Bram", "Dane", "abel"], "numbers biggest first, ties by name: %s" % [names.call()])
	tb.sort_by("n")
	check(names.call() == ["abel", "Bram", "Dane", "Cobb"], "numbers reversed: %s" % [names.call()])
	tb.sort_by("x")
	check(names.call() == ["Cobb", "Dane", "Bram", "abel"], "a not-tracked value sorts last: %s" % [names.call()])
	tb.set_filter("Big", "big")
	check(names.call() == ["Cobb", "Dane", "Bram"], "filter: %s" % [names.call()])
	tb.search = "br"
	check(names.call() == ["Bram"], "search: %s" % [names.call()])
	tb.free()
	# Lazy columns still resolve exact values for sorting, including missing values, in both directions.
	var lazy_rows := [
		{"name": "A", "n": func(): return 2, "place": func(): return "ridge", "_l": "A"},
		{"name": "B", "n": func(): return null, "place": func(): return "Coast", "_l": "B"},
		{"name": "C", "n": func(): return 5, "place": func(): return "plain", "_l": "C"}]
	var lazy := RecTable.make([{"k": "name", "t": "Name"}, {"k": "n", "t": "N", "num": true}, {"k": "place", "t": "Near"}], lazy_rows, "name")
	lazy.sort_by("n")
	check(lazy.shown().map(func(r): return r["name"]) == ["C", "A", "B"], "lazy numeric column sorts resolved values, missing last")
	lazy.sort_by("n")
	check(lazy.shown().map(func(r): return r["name"]) == ["A", "C", "B"], "lazy numeric column reverses with missing values last")
	lazy.sort_by("place")
	check(lazy.shown().map(func(r): return r["name"]) == ["B", "C", "A"], "lazy text column sorts resolved names A-Z without case bias")
	lazy.sort_by("place")
	check(lazy.shown().map(func(r): return r["name"]) == ["A", "C", "B"], "lazy text column reverses its resolved names")
	lazy.free()

func _find_button(n: Node, txt: String) -> Button:
	if n is Button and (n as Button).text == txt: return n as Button
	for child in n.get_children():
		var found := _find_button(child, txt)
		if found != null: return found
	return null

func _data_reads_test() -> void:
	var families := {"fams": [
		{"m": 2, "f": 1, "kids": 3, "old": 1},
		{"m": 1, "f": 1, "kids": 9, "old": 0, "gone": true},
		{"m": 1, "f": 1, "kids": 4, "old": 0, "estate": true}]}
	check(RecData.live_people(families) == Census.people(families) and RecData.live_people(families) == 7,
		"records live population uses the census's four counters and excludes gone families and estate")
	families["fams"][0]["kids"] = 4
	check(RecData.live_people(families) == Census.people(families) and RecData.live_people(families) == 8,
		"records live population reads edits immediately without a frame cache")
	var tapped := [0]
	var row := RecKit.row("A long household name", "12 people", "Food, work and health details", func(): tapped[0] += 1, UiTheme.BAD)
	row.size = Vector2(200, 64)
	row._fit_lines()
	row.pressed.emit()
	check(tapped[0] == 1 and row.get_meta("rec_row") == ["A long household name", "12 people", "Food, work and health details"],
		"drawn row keeps the full information and native button action")
	check(row is Button and row.focus_mode == Control.FOCUS_NONE and row.tooltip_text == "A long household name\n12 people\nFood, work and health details",
		"drawn row keeps the original native focus behavior and full text tooltip")
	check(row.accessibility_name == "A long household name 12 people" and row.accessibility_description == "Food, work and health details",
		"drawn row exposes both title values and full details to assistive apps")
	check(row.lines.size() == 3 and row.lines[0].width + row.lines[1].width <= 176.0 and row.lines[2].width == 176.0,
		"drawn row fits both first-line values and details inside its margins")
	for line in row.lines:
		check(line.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "drawn row retains ellipsis clipping")
	check(row.right_color == UiTheme.BAD, "drawn row retains the value's status color")
	row.free()
	var market := {"stock": {"grain": 9, "fruit": 4}, "dem": {"grain": 1.5, "fruit": 0.25}}
	check(RecData.market_totals(market, ["grain", "fruit", "missing"]) == [13, 1.75], "category totals use real ledgers and absent goods contribute zero")
	check(RecData.market_totals({}, ["grain"]) == [0, 0.0], "empty market ledgers have no stock or demand")
	var books := {"towns": {
		"first": {"econ": {"census": {"cur": {}, "buf": {"d": [1, 2, 4], "dt": [0, 2, 3]}}}},
		"second": {"econ": {"census": {"cur": {}, "buf": {"d": [2, 3, 4], "dt": [10, 11, 11]}}}}}}
	check(RecTown._daily(books, ["first", "second"]) == {"d": [2, 3, 4], "deaths": [2, 1, 1]}, "daily deaths combine actual counter increments even when town sample days differ")

## Opening substantial detail keeps its content and the original tab's Back destination.
func _detail(s: Node, sv: SubViewport, button_text: String, expected: Array) -> void:
	var button := _find_button(s, button_text)
	check(button != null, "records offers " + button_text)
	if button == null: return
	button.pressed.emit()
	await _settle()
	for text in expected:
		check(_has_text(s, String(text)), button_text + " retains " + String(text))
	if button_text == "View census by race":
		var race_people := {}
		for tid in s.tids():
			var e := RecData.econ(RecData.town(tid))
			var race := Persons.race_of(e).capitalize()
			race_people[race] = int(race_people.get(race, 0)) + Census.people(e)
		var table := _find_table(s)
		check(table != null and table.rows.size() == race_people.size(), "race detail retains every race in view")
		if table != null:
			for row in table.rows:
				check(int(row["people"]) == int(race_people.get(String(row["name"]), -1)), "race detail's people match its live families")
	_check_fit(sv, button_text)
	s.go_back()
	await _settle()
	check(_find_button(s, button_text) != null, button_text + " Back returns to its tab")

## Paged tables retain all records and expose another full batch using the existing Show more control.
func _more_rows(table: RecTable) -> void:
	if table.shown().size() <= table.limit: return
	var before := table.limit
	var more := _find_button(table, "Show %d more" % mini(RecTable.LIMIT, table.shown().size() - before))
	check(more != null, "paged records have a Show more control")
	if more != null:
		more.pressed.emit()
		check(table.limit == before + RecTable.LIMIT, "Show more exposes the next full records batch")
