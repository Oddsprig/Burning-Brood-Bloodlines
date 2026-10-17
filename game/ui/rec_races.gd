class_name RecRaces
extends RefCounted
## "By race": the census read per race (a card at the top of the world and faction Census tab). One row per race:
## people now, towns, births and deaths this year, growth over the last year, hungry and homeless households.
## Every number from the towns' census rows and live families; what the sim lacks reads "not tracked".
## A town's race is its culture's race (Persons.race_of). "This year" = the calendar year now, counting the
## season so far; a census row belongs to the year its season began in.

static func _year_of(day: float) -> int:
	return Calendar.year(day)

## {race: {towns: [tid], people, hungry, fams, homeless, back_n, back_people, years: {year: {...}}}}
static func gather(tids: Array) -> Dictionary:
	var out := {}
	var now_year := _year_of(float(Game.day))
	var back_day := float(Game.day) - 4.0 * float(Calendar.DAYS_PER_SEASON)
	for tid in tids:
		var t := RecData.town(tid)
		if not t.has("econ"):
			continue
		var e: Dictionary = RecCivic._read_town(t, RecData.econ(t))["econ"]
		var race := Persons.race_of(e)
		if not out.has(race):
			out[race] = {"towns": [], "people": 0, "hungry": 0, "fams": 0, "homeless": 0, "back_n": 0, "back_people": 0, "back_now": 0, "years": {}}
		var d: Dictionary = out[race]
		(d["towns"] as Array).append(String(tid))
		var ppl := Census.people(e)
		d["people"] += ppl
		for f in RecData.fams(e):
			d["fams"] += 1
			if RecData.hungry_weeks(f) > 0: d["hungry"] += 1
			if RecData.homeless(f): d["homeless"] += 1
		var rs: Array = Census.rows(e)
		var back: Variant = null
		var yrs: Dictionary = d["years"]
		for r in rs:
			if float(r["day"]) <= back_day:
				back = r
			var y := _year_of(float(r.get("since", r["day"])))
			var yd := _yr(yrs, y)
			_fold(yd, r["births"], r["deaths"], r["arrived"], r["left"])
			_set_people(yd, tid, float(r["day"]), int(r["people"]))
		var cur := Census.current(e)
		var cy := _yr(yrs, now_year)
		_fold(cy, cur["births"], cur["deaths"], cur["arrived"], cur["left"])
		_set_people(cy, tid, INF, ppl)
		if back != null:
			d["back_n"] += 1
			d["back_people"] += int(back["people"])
			d["back_now"] += ppl
	return out

static func _yr(yrs: Dictionary, y: int) -> Dictionary:
	if not yrs.has(y):
		yrs[y] = {"births": 0, "deaths": {}, "arrived": 0, "left": 0, "_p": {}}
	return yrs[y]

static func _fold(yd: Dictionary, births, deaths: Dictionary, arrived: Dictionary, left: Dictionary) -> void:
	yd["births"] += int(births)
	for c in deaths:
		yd["deaths"][c] = int(yd["deaths"].get(c, 0)) + int(deaths[c])
	yd["arrived"] += Census.sum(arrived)
	yd["left"] += Census.sum(left)

## The year's people = each town's latest count within it, summed.
static func _set_people(yd: Dictionary, tid, day: float, n: int) -> void:
	var p: Dictionary = yd["_p"]
	var k := String(tid)
	if not p.has(k) or day >= float(p[k][0]):
		p[k] = [day, n]

static func _yr_people(yd: Dictionary) -> int:
	var n := 0
	for k in yd["_p"]:
		n += int(yd["_p"][k][1])
	return n

static func _top(deaths: Dictionary, n: int) -> String:
	var ks: Array = deaths.keys().filter(func(c): return int(deaths[c]) > 0)
	ks.sort_custom(func(a, b): return int(deaths[a]) > int(deaths[b]))
	var out := []
	for c in ks.slice(0, n):
		out.append("%s %d" % [String(c), int(deaths[c])])
	return ", ".join(PackedStringArray(out)) if not out.is_empty() else "none"

static func _growth(d: Dictionary) -> Variant:
	if int(d["back_n"]) <= 0 or int(d["back_people"]) <= 0:
		return null
	return 100.0 * float(int(d["back_now"]) - int(d["back_people"])) / float(d["back_people"])

static func _gtxt(g: Variant) -> String:
	return RecKit.NT if g == null else "%+.1f%%" % float(g)

static func card(scr, tids: Array, v: VBoxContainer) -> void:
	var g := gather(tids)
	var c := RecKit.card(v, "By race", "One row per race, from the towns' census. This year = the year now, season so far included. Tap a race for its years and towns.")
	if g.is_empty():
		RecKit.line(c, "No towns in view.", "Muted")
		return
	var now_year := _year_of(float(Game.day))
	var rows := []
	for race in g:
		var d: Dictionary = g[race]
		var rr := String(race)
		var yd: Dictionary = (d["years"] as Dictionary).get(now_year, {"births": 0, "deaths": {}})
		var dt := Census.sum(yd["deaths"])
		var gr: Variant = _growth(d)
		var hp := 100.0 * float(d["hungry"]) / maxf(1.0, float(d["fams"]))
		var nt: int = (d["towns"] as Array).size()
		rows.append({"name": rr.capitalize(), "people": int(d["people"]), "towns": nt, "births": int(yd["births"]), "deaths": dt,
			"growth": gr if gr != null else -INF, "hungry": hp, "homeless": int(d["homeless"]),
			"_l": rr.capitalize(), "_r": "%d people" % int(d["people"]),
			"_d": "%d towns and villages; born %d, died %d this year (top: %s); growth %s over the last year; hungry households %d%%; homeless households %d" % [
				nt, int(yd["births"]), dt, _top(yd["deaths"], 3), _gtxt(gr), int(round(hp)), int(d["homeless"])],
			"_s": rr, "_tap": func(): scr.page(rr.capitalize(), func(b): _page(scr, rr, tids, b))})
	var table := RecTable.make([{"k": "name", "t": "Race"}, {"k": "people", "t": "People", "num": true}, {"k": "towns", "t": "Towns", "num": true},
		{"k": "births", "t": "Births", "num": true}, {"k": "deaths", "t": "Deaths", "num": true}, {"k": "growth", "t": "Growth", "num": true},
		{"k": "hungry", "t": "Hungry %", "num": true}, {"k": "homeless", "t": "Homeless", "num": true}], rows, "people", false)
	table.display_cells([{"k": "name", "t": "Race", "w": 1.4}, {"k": "people", "t": "People"}, {"k": "towns", "t": "Towns"},
		{"k": "births", "t": "Born"}, {"k": "deaths", "t": "Died"},
		{"k": "growth", "t": "Year growth", "w": 1.2, "format": func(value): return "-" if is_inf(float(value)) else "%+.1f%%" % float(value)}])
	c.add_child(table)
	RecKit.nt(c, "Growth for a race with no census a year old (shown last when sorted)")

static func _page(scr, race: String, tids: Array, box: VBoxContainer) -> void:
	var g := gather(tids)
	if not g.has(race):
		RecKit.line(box, "No towns of this race in view.", "Muted")
		return
	var d: Dictionary = g[race]
	var now_year := _year_of(float(Game.day))
	var c := RecKit.card(box, "%s now" % race.capitalize())
	RecKit.kv(c, "People, towns and villages", "%d, %d" % [int(d["people"]), (d["towns"] as Array).size()])
	RecKit.kv(c, "Growth over the last year", _gtxt(_growth(d)))
	RecKit.kv(c, "Hungry households", "%d of %d" % [int(d["hungry"]), int(d["fams"])])
	RecKit.kv(c, "Homeless households", "%d" % int(d["homeless"]))
	var ys: Array = (d["years"] as Dictionary).keys()
	ys.sort()
	var xs := []; var pp := []; var bb := []; var dd := []
	var rows := []
	for y in ys:
		var yd: Dictionary = d["years"][y]
		xs.append(int(y)); pp.append(_yr_people(yd)); bb.append(int(yd["births"])); dd.append(Census.sum(yd["deaths"]))
		var yy := int(y)
		rows.append({"year": yy, "people": _yr_people(yd), "births": int(yd["births"]), "deaths": Census.sum(yd["deaths"]),
			"arrived": int(yd["arrived"]), "left": int(yd["left"]),
			"_l": "Year %d%s" % [yy, " (so far)" if yy == now_year else ""], "_r": "%d people" % _yr_people(yd),
			"_d": "born %d, died %d (%s), arrived %d, left %d" % [int(yd["births"]), Census.sum(yd["deaths"]), _top(yd["deaths"], 10),
				int(yd["arrived"]), int(yd["left"])],
			"_tap": func(): pass})
	var tc := RecKit.card(box, "Trend by year", "People at the year's last census; the rest summed over its seasons.")
	RecKit.chart(tc, "People", xs, pp, "", "years")
	RecKit.chart(tc, "Births", xs, bb, "", "years")
	RecKit.chart(tc, "Deaths", xs, dd, "", "years")
	tc.add_child(RecTable.make([{"k": "year", "t": "Year", "num": true}, {"k": "people", "t": "People", "num": true},
		{"k": "births", "t": "Births", "num": true}, {"k": "deaths", "t": "Deaths", "num": true}, {"k": "arrived", "t": "Arrived", "num": true},
		{"k": "left", "t": "Left", "num": true}], rows, "year", false))
	var trows := []
	for tid in d["towns"]:
		var tt := String(tid)
		var e := RecData.econ(RecData.town(tt))
		var n := Census.people(e)
		trows.append({"name": RecData.tname(tt), "people": n, "_l": RecData.tname(tt), "_r": "%d people" % n,
			"_d": "tap to open the town", "_s": RecData.tname(tt), "_tap": func(): scr.open_town(tt)})
	var tw := RecKit.card(box, "Its towns")
	tw.add_child(RecTable.make([{"k": "name", "t": "Town"}, {"k": "people", "t": "People", "num": true}], trows, "people", false, [], true))
