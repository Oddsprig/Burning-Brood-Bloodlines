class_name RecPages
extends RefCounted
## Detail pages of the records screen (tap any name): family, person, business, force on the map, a unit with
## no register record. Same rule: real fields only, "not tracked" for the rest.

static func _m(v: float) -> String:
	return RecData.money(v)

## Display getters may initialize absent book slots. Never commit those
## defaults, named flags or missing books merely by opening a record.
static func _detail_town(t: Dictionary) -> Dictionary:
	var view: Dictionary = t.duplicate()
	view["econ"] = RecData.econ(t).duplicate(true)
	return view

## "12 (3 bed-ridden)": the town's people at home in their sick phase (campaign/sickness.gd town_summary).
static func sick_count(t: Dictionary) -> String:
	var read_town := t
	if TownEcon.has_econ(t):
		var e: Dictionary = t["econ"]
		read_town = RecCivic._read_town(t, e)
	var s := Sickness.town_summary(read_town)
	if s.is_empty():
		return RecKit.NT
	return "%d (%d bed-ridden)" % [int(s["sick_now"]), int(s["bed_now"])]

## The town's open cases at home (caught: incubating or sick), from the sickness book's counter e.sk.act (cheap:
## the wide lists use it; one town's own pages count who is showing it with sick_count).
static func open_cases(t: Dictionary) -> String:
	if not TownEcon.has_econ(t):
		return RecKit.NT
	var act: Dictionary = (t["econ"] as Dictionary).get("sk", {}).get("act", {})
	var n := 0
	for dis in act:
		n += int(act[dis])
	return "%d" % n

# ================================================================== family
static func family(scr, t: Dictionary, fid: int, box: VBoxContainer) -> void:
	t = _detail_town(t)
	var e := RecData.econ(t)
	var f := RecData.fam(e, fid)
	if f.is_empty():
		RecKit.line(box, "No such family.", "Muted")
		return
	# Opening records never changes naming/history policy.
	if f.get("estate", false):
		var ec := RecKit.card(box, "The town's own land")
		for l in Families.describe(t, e, f):
			RecKit.line(ec, String(l))
		return
	var st := RecData.state(f)
	var c := RecKit.card(box, "Condition")
	var sl := RecKit.line(c, "%s; hungry %d weeks in a row" % [st.capitalize(), RecData.hungry_weeks(f)])
	sl.add_theme_color_override("font_color", UiTheme.readable(RecData.state_color(st),UiTheme.PARCH_2))
	RecKit.kv(c, "Purse", _m(RecData.purse(f)))
	var inc: Variant = RecData.income_day(f)
	RecKit.kv(c, "Income before household expenses", (_m(float(inc)) + " a day (last week)") if inc != null else RecKit.NT)
	for part in f.get("income_parts", {}):
		RecKit.kv(c, String(part).capitalize(), _m(float(f["income_parts"][part]) / 7) + " a day (last week)")
	RecKit.kv(c, "Debt", _m(RecData.debt(f)) if RecData.debt(f) > 0.5 else "none")
	var s: Dictionary = f.get("store", {})
	RecKit.kv(c, "Stores", "food %d days, drink %d days, firewood %d days" % [int(s.get("food", 0)), int(s.get("drink", 0)), int(s.get("wood", 0))])
	var day := float(Game.day)
	var members := Persons.household(e, f, day)
	var sick := members.filter(func(m): return String(m.get("sick", "")) != "")
	RecKit.kv(c, "Sick today", "%d of %d at home and away" % [sick.size(), members.size()] if not sick.is_empty() else "nobody")
	for k in ["Hunger % of the last 14 days", "Cold days", "Winter clothing", "Pawned goods", "Mourning", "Spent today (and on food)",
			"Food in store by kind", "Seed kept for sowing", "Rent a month and payments missed"]:
		RecKit.nt(c, k)
	if f.has("lodging"):
		RecKit.kv(c, "Rented rooms", "%d; %.1f coins a week" % [f["lodging_rooms"], TownHousing.rent_week(e, f)])
	var dc := RecKit.card(box, "The record")
	for l in Families.describe(t, e, f):
		if String(l).begins_with("Purse:") or String(l).begins_with("Income last week:") or String(l).begins_with("Stores:") or String(l).begins_with("Hunger:"): continue
		RecKit.line(dc, String(l), "Small")
	# members, eldest first
	var mc := RecKit.card(box, "Members", "Eldest first. Tap anyone for their own page.")
	for m in members:
		var pid := int(m["pid"])
		var wage := int(m["wage"])
		var sk := String(m.get("sick", ""))
		mc.add_child(RecKit.row("%s, %d, %s" % [String(m["name"]), int(m["age"]), String(m["kind"])],
			(_m(wage / 7.0) + " a day") if wage >= 0 and String(m["work"]) != "child" else "",
			"%s%s; %s%s" % [(sk + "; ") if sk != "" else "", String(m["kin"]), String(m["work"]), ("; " + Persons.SERVICE_WORDS.get(String(m["state"]), String(m["state"]))) if String(m["state"]) != "" else ""],
			func(): scr.open_person(t, fid, pid), UiTheme.BAD if sk != "" else null))
	if not Persons.pp(f).is_empty() or f.has("dp"):
		var gone := remembered(e, f)
		if not gone.is_empty():
			var gc := RecKit.card(box, "Remembered (dead and departed)")
			for p in gone:
				var pid2 := int(p[0])
				gc.add_child(RecKit.row(Persons.name_of(f, p, Persons.race_of(e)), "", departure_text(e, p), func(): scr.open_person(t, fid, pid2)))
	# animals (addendum 1 B4): the family's herds, oxen and pens
	_animals(e, RecData.family_herds(e, fid), box, "Animals", "Its herds, plough oxen and pens: each a record with its ages, herders and plots.")
	if not f.get("hives", {}).is_empty():
		var hive_card := RecKit.card(box, "Beehives")
		RecKit.line(hive_card, "%d owned hives; produced %.2f kg honey and %.2f kg wax from flowering land." % [int(f["hives"]["count"]), float(f["hives"]["honey_kg"]), float(f["hives"]["wax_kg"])])
	# loans
	var lc := RecKit.card(box, "Loans")
	var ll := Loans.family_line(e, f)
	RecKit.line(lc, ll if ll != "" else "No debt.", "" if ll != "" else "Muted")
	RecKit.nt(lc, "Collateral and the clerk who made the loan")
	# businesses owned
	var owns: Array = f.get("owns", [])
	if not owns.is_empty():
		var bc := RecKit.card(box, "Businesses owned")
		for bid in owns:
			var b: Dictionary = RecData.biz(e)[int(bid)]
			var bi := int(bid)
			bc.add_child(RecKit.row(RecData.biz_title(e, b).capitalize(), RecData.biz_state(b), RecData.staff_text(b) + ", till " + _m(RecData.till(b)),
				func(): scr.open_business(t, bi)))
	# life
	var hc := RecKit.card(box, "Life", "Newest first.")
	for l in Backstory.recent_life(t, e, f):
		RecKit.line(hc, String(l), "Small")
	var hist: Array = f.get("hist", []) if f.get("ev", []).is_empty() else f.get("extra_history", [])
	for i in range(hist.size() - 1, -1, -1):
		RecKit.line(hc, String(hist[i]), "Small")
	# the census: the family's dead with their causes
	var dead := []
	for d in Census._book(e)["deaths"]:
		if d.size() > 7 and int(d[7]) == fid:
			dead.append(d)
	if not dead.is_empty():
		var kc := RecKit.card(box, "Deaths in the family (census)")
		for d in dead:
			RecKit.line(kc, "%s: %s, %s%s" % [RecTown._day_word(float(d[0])), String(d[2]) if String(d[2]) != "" else "an elder", String(d[5]),
				(" (" + String(d[6]) + ")") if String(d[6]) != "" else ""], "Small")

# ================================================================== person
static func person(scr, t: Dictionary, fid: int, pid: int, box: VBoxContainer) -> void:
	t = _detail_town(t)
	var e := RecData.econ(t)
	var f := RecData.fam(e, fid)
	var p: Array = Persons.any(f, pid) if not f.is_empty() else []
	if p.is_empty():
		RecKit.line(box, "No record of this person.", "Muted")
		return
	var race := Persons.race_of(e)
	var day := float(Game.day)
	var alive := not Persons.by_pid(f, pid).is_empty()
	var c := RecKit.card(box, Persons.name_of(f, p, race))
	RecKit.kv(c, "Sex", ["man", "woman"][int(p[2])] if int(p[2]) in [0, 1] else "?")
	RecKit.kv(c, "Age", "%d" % Persons.age_of(p, day) if alive else departure_text(e, p))
	c.add_child(RecKit.row("The %s family" % String(f.get("name", "?")), RecData.tname(String(t["id"])), ("her household" if int(p[2]) == 1 else "his household"), func(): scr.open_family(t, fid)))
	if alive:
		var h := Persons.head_of(f)
		RecKit.kv(c, "Kin", Persons.kin_of(e, f, p, h))
		for m in Persons.household(e, f, day):
			if int(m["pid"]) == pid:
				RecKit.kv(c, "Work", String(m["work"]) + ((", %s a day" % _m(int(m["wage"]) / 7.0)) if int(m["wage"]) >= 0 and String(m["work"]) != "child" else ""))
		var st := String(p[4])
		RecKit.kv(c, "Now", String(Persons.SERVICE_WORDS.get(st, st)))
		var sk := Sickness.person_text(f, pid, day)
		var cs := Sickness.case_of(f, pid)
		RecKit.kv(c, "Sick", (sk + ("; remedy given" if int(cs[Sickness.C_REM]) == 1 else "; no remedy") + ("; bed-ridden" if int(cs[Sickness.C_BED]) == 1 else "")) if sk != "" else "no")
	else:
		var died := []
		for d in Census._book(e)["deaths"]:
			if int(d[1]) == pid:
				died = d
		if not died.is_empty():
			RecKit.kv(c, "Died", "%s, aged %d: %s%s" % [RecTown._day_word(float(died[0])), int(died[3]), String(died[5]), (" (" + String(died[6]) + ")") if String(died[6]) != "" else ""])
		else:
			RecKit.kv(c, "Gone", "dead or departed (the family remembers; when and how: %s)" % RecKit.NT)
	# rosters: his unit on the map, if any
	var u := _unit(int(p[5]))
	if u != null:
		var rc := RecKit.card(box, "Rosters")
		var rr := Persons.roster_row(Game, u, String(p[4]))
		RecKit.line(rc, "%s: %s%s, %s, %s years served, %s a day" % [String(Persons.SERVICE_WORDS.get(String(p[4]), String(p[4]))).capitalize(),
			String(rr["rank"]), "" if String(rr["rank"]) == "" else ",", String(rr["weapon"]), RecKit.num(float(rr["years_served"])), _m(float(rr["pay_day"]))])
		_skills(u, rc)
	else:
		RecKit.nt(box, "Skills from work")
	# his own past
	var lc := RecKit.card(box, "Life history", "Places held, service, wounds; newest first.")
	var spans := Persons.life_spans(p)
	if spans.is_empty():
		RecKit.line(lc, "Nothing recorded.", "Muted")
	if Legends.made_by(p) > 0:   # v0.014
		RecKit.kv(c, "Legendary pieces made", "%d (at most %d in a life)" % [Legends.made_by(p), Legends.CAP])
	for s in spans:
		var to := float(s["to"])
		if String(s["code"]) == "legend":   # v0.014: a legendary piece he made
			RecKit.line(lc, "made %s (%s)" % [String(s["arg"]), RecTown._day_word(float(s["from"]))], "Small")
			continue
		RecKit.line(lc, "%s: %s (from %s%s)" % [String(s["code"]), Backstory.job_words(String(s["arg"])) if String(s["code"]) == "job" else String(s["arg"]),
			RecTown._day_word(float(s["from"])), (" to " + RecTown._day_word(to)) if to >= 0.0 else ", still"], "Small")

static func _skills(u: Unit, box: VBoxContainer) -> void:
	var ks := UnitSheet.known_skills(u)
	var sk := ks.map(func(s): return UnitSheet.skill_line(u, s))
	RecKit.kv(box, "Skills", ", ".join(PackedStringArray(sk)) if not sk.is_empty() else "nothing to speak of")
	RecKit.kv(box, "Battles, kills, renown", "%d, %d, %d" % [u.battles, u.kills, int(round(u.renown))])

static func _unit(uid: int) -> Unit:
	if uid < 0:
		return null
	for u in Game.company:
		if u.uid == uid:
			return u
	for wid in Game.world.get("warbands", {}):
		for u in Game.world["warbands"][wid].get("units", []):
			if u is Unit and u.uid == uid:
				return u
	for tid in Game.world.get("towns", {}):
		for u in Game.world["towns"][tid].get("recruits", []):
			if u is Unit and u.uid == uid:
				return u
	return null

## A unit with no register record (monsters, a world without towns).
static func unit_page(scr, u: Unit, box: VBoxContainer) -> void:
	var c := RecKit.card(box, u.name)
	RecKit.kv(c, "What", "%s %s" % [UiWords.race_name(u), u.title])
	RecKit.kv(c, "Age", "%d" % u.age)
	_skills(u, c)
	RecKit.nt(c, "Register record (family, history)")

# ================================================================== business
static func business(scr, t: Dictionary, bid: int, box: VBoxContainer) -> void:
	t = _detail_town(t)
	var e := RecData.econ(t)
	var context := {"work": {}}
	var b: Dictionary = RecData.biz(e)[bid]
	var house := RecData.is_house(b)
	var c := RecKit.card(box, RecData.biz_title(e, b).capitalize())
	RecKit.kv(c, "Trade", RecData.biz_trade(b))
	var reason := String(b.get("why", ""))
	var state_text := RecData.biz_state(b)
	if house and not reason.is_empty():
		state_text += " - " + reason
	elif String(b.get("state", "")) == "inputs" and not reason.is_empty():
		state_text += ", no " + RecData.good_name(e, reason)
	RecKit.kv(c, "State", state_text)
	var owner := int(b.get("owner", -1))
	if owner >= 0:
		var of := RecData.fam(e, owner)
		c.add_child(RecKit.row("Owned by the %s family" % String(of.get("name", "?")), "", "tap for the household", func(): scr.open_family(t, owner)))
	elif house:
		RecKit.kv(c, "Funding", "State-funded research house")
	else:
		RecKit.kv(c, "Owner", "the town" + (" (for sale)" if b.get("for_sale", false) else ""))
	var hl: Variant = RecData.biz_health(b)
	if hl != null:
		var pf: Variant = RecData.biz_profit(b)
		RecKit.kv(c, "Health (the books)", "%s; profit %s a day over the last 14 days; %d loss days" % [String(hl), _m(float(pf)) if pf != null else "-", RecData.biz_loss_days(b)])
	var kp := RecData.keeper(e, b, context)
	if not kp.is_empty():
		var kf := int(kp["fid"]); var kpid := int(kp["pid"])
		c.add_child(RecKit.row((Academy.lead_title(e) + ": " if house else "Kept by ") + String(kp["name"]), "", "%s; tap for the person" % String(kp["how"]), func(): scr.open_person(t, kf, kpid)))
	else:
		RecKit.kv(c, Academy.lead_title(e) if house else "Kept by", "Head post vacant" if house else "nobody at work there")
	if b.has("p1"):
		RecKit.kv(c, "Profit yesterday", _m(float(b["p1"])) + (" (a day, this week)" if String(b["type"]) == "farm" else ""))
	RecKit.nt(c, "Address, rent")
	RecKit.kv(c, "Cash in the till", _m(RecData.till(b)))
	RecKit.kv(c, "Staff wage", _m(RecData.biz_wage(b)) + " a day")
	if house:
		RecKit.kv(c, "Head supplement", _m(RecData.biz_wage(b) * float(Academy.R().get("lead_pay", 1.0))) + " a day when the till can pay")
	RecKit.kv(c, "Owed in wages", _m(float(b.get("owed", 0.0))))
	var claims: Dictionary = b.get("wage_claims", {})
	var named_total := 0.0
	for fid in claims: named_total += float(claims[fid])
	var older := float(b.get("owed_unattributed", maxf(0.0, float(b.get("owed", 0.0)) - named_total)))
	if older > 0.005:
		RecKit.kv(c, "Older wages without a named recipient", _m(older))
		RecKit.line(c, "This balance is preserved from older records, which did not save who earned it.", "Muted")
	if not claims.is_empty():
		var wc := RecKit.card(box, "Wages still to pay", "Earned wages remain due after a worker leaves. Payments come from the business till.")
		for fid in claims:
			var household := RecData.fam(e, int(fid))
			var who := "the %s household" % String(household.get("name", "unidentified"))
			if household.get("extinct", false): who += " (estate)"
			elif household.has("moved"): who += " (moved away)"
			RecKit.kv(wc, who, _m(float(claims[fid])))
	RecKit.kv(c, "Inputs bought a day (smoothed)", _m(float(b.get("spend", 0.0))))
	RecKit.kv(c, "Tools", "%d sets; %d working hands (paid staff and keeper)" % [int(b.get("tools", 0)), int(b.get("workers", 0)) + int(b.get("kw", 0))])
	if house:   # v0.012: the state's research house - its lead, lines, materials and log
		var fid := String(t.get("faction", ""))
		var hc := RecKit.card(box, "Research", "Funded by the state each faction turn; staff hired by the normal rules; trials burn iron bars, flux stone and wood bought at the market.")
		for ln in RecData.research_lines(fid):
			RecKit.line(hc, ln, "Small")
		var lg: Array = RecData.research_log(fid)
		if not lg.is_empty():
			var lc := RecKit.card(box, "Log book", "The house's last events, newest last.")
			for ln in lg:
				RecKit.line(lc, String(ln), "Small")
	elif b.has("skill"):
		RecKit.kv(c, "Smith's skill", "%d of 15" % int(b["skill"]))
	RecKit.nt(c, "Cash chart, yesterday's ledger")
	var rc := RecKit.card(box, "Recipes", "Per worker-day, from the trade's data row. Cost per unit at today's prices: inputs only (labour and fuel per unit: not tracked).")
	for r in RecData.recipes(b):
		var ins := []; var outs := []; var cost := 0.0; var outn := 0.0; var sell := 0.0
		for g in r.get("in", {}):
			ins.append("%s %s" % [RecKit.num(float(r["in"][g])), RecData.good_name(e, g)])
			cost += float(r["in"][g]) * RecData.price(t, g)
		for g in r.get("out", {}):
			outs.append("%s %s" % [RecKit.num(float(r["out"][g])), RecData.good_name(e, g)])
			outn += float(r["out"][g]); sell += float(r["out"][g]) * RecData.price(t, g)
		var BB: Dictionary = Barge.B()["business"]
		var mg := ""
		if cost > 0.0:   # barge part 3 section 4: output at 0.92 x price against 1.03 x the inputs
			mg = "; margin %+d%%: %s" % [int(round(100.0 * (sell * float(BB["out_share"]) / cost - 1.0))),
				"pays" if sell * float(BB["out_share"]) >= float(BB["run_margin"]) * cost else "does not pay (at most %d%% of capacity)" % int(round(100.0 * float(BB["idle_cap"])))]
		RecKit.line(rc, "%s -> %s, %s a worker-day; inputs %s against %s at today's prices%s" % [", ".join(PackedStringArray(ins)) if not ins.is_empty() else "work",
			", ".join(PackedStringArray(outs)), RecKit.num(float(r.get("rate", 1.0))), _m(cost), _m(sell), mg], "Small")
	if RecData.recipes(b).is_empty():
		RecKit.line(rc, "No recipe: a service (the market, collectors, fields, works).", "Muted")
	var sc := RecKit.card(box, "Staff", RecData.staff_text(b))
	for s in RecData.staff(e, bid, context):
		var sfid := int(s["fid"]); var spid := int(s["pid"])
		sc.add_child(RecKit.row(String(s["name"]), _m(float(s["wage"])) + " a day", String(s["title"]), func(): scr.open_person(t, sfid, spid)))
	RecKit.nt(sc, "Hiring: open posts, hired, quit and let go this month")
	# herds' trades (addendum 1 B3): its own herds and its chain (where its beasts came from, where its output went)
	var bh := RecData.biz_herds(e, bid)
	if not bh.is_empty():
		_animals(e, bh, box, "Its herds", "Kept by its herdsmen (the staff above).")
	var ch := RecData.biz_chain(b)
	if not ch.is_empty() or b.has("kills"):
		var cc := RecKit.card(box, "The chain", "This season first, then last season: who it bought beasts from and where its output went.")
		if b.has("kills"):
			RecKit.kv(cc, "Beasts slaughtered since the books began", "%d" % int(b["kills"]))
		for r in ch:
			var what := String(r[2])
			var wword := RecData.herd_word(e, what) if RecData.animal_kinds().has(what) else RecData.good_name(e, what)
			RecKit.line(cc, "%s%s %s: %d %s" % ["" if bool(r[4]) else "(last season) ", "From" if String(r[0]) == "from" else "To", String(r[1]), int(r[3]), wword], "Small")
	RecKit.nt(box, "Last 10 events of the business")

## A list of herd records: kind and head, ages, owner, herders (register persons), plots, hay, hunger.
static func _animals(e: Dictionary, hl: Array, box: VBoxContainer, title: String, note: String) -> void:
	if hl.is_empty():
		return
	var ac := RecKit.card(box, title, note)
	for h in hl:
		var hh: Dictionary = h
		var nm := []
		for p in RecData.herders(e, hh).slice(0, 3):
			nm.append(String(p["name"]))
		RecKit.kv(ac, RecData.herd_n(e, RecData.herd_head(hh), String(hh["k"])).capitalize(), "%d young, %d grown, %d old; herded by %s; %d plots; %s bales of hay%s" % [
			int(hh["y"]), int(hh["g"]), int(hh["o"]), ", ".join(PackedStringArray(nm)) if not nm.is_empty() else "nobody named", (hh["pl"] as Array).size(),
			RecKit.num(float(hh["fod"])), (("; short of feed %d days" % int(hh["hun"])) if int(hh["hun"]) > 0 else "") + RecData.herd_state(hh)])

# ================================================================== forces on the map
static func force_name(wb: Dictionary) -> String:
	var kind := String(wb.get("kind", ""))
	var fid := String(wb.get("faction", ""))
	match kind:
		"caravan": return "Caravan of %s" % RecData.tname(String(wb.get("origin", wb.get("home", ""))))
		"militia": return "The militia of %s" % RecData.tname(String(wb.get("home", "")))
	var mk := Monsters.kind_text(wb)
	if mk != "":
		return mk.capitalize()
	return "%s %s" % [UiWords.faction_name(fid), kind]

static func force(scr, wid: String, box: VBoxContainer) -> void:
	var w: Dictionary = Game.world
	var wb: Dictionary = w["warbands"].get(wid, {})
	if wb.is_empty():
		RecKit.line(box, "Gone from the map.", "Muted")
		return
	var c := RecKit.card(box, force_name(wb))
	var units: Array = (wb["units"] as Array).filter(func(u): return not u.dead)
	RecKit.kv(c, "Kind", String(wb.get("kind", "")))
	RecKit.kv(c, "Owner", UiWords.faction_name(String(wb.get("faction", ""))))
	var home := String(wb.get("home", ""))
	if RecData.town(home).has("econ"):
		c.add_child(RecKit.row("Home: %s" % RecData.tname(home), "", "tap for the town", func(): scr.open_town(home)))
	RecKit.kv(c, "Near", CampaignWorld.nearest_town_name(w, wb["pos"]))
	RecKit.kv(c, "Men", "%d" % units.size())
	RecKit.kv(c, "Strength", RecKit.num(CampaignWorld.band_power(units)))
	if String(wb.get("kind", "")) == "caravan":
		RecKit.line(c, Caravans.describe(w, wb))
		caravan_receipt(box, wb.get("receipt", {}))
	RecKit.kv(c, "Doing", WarAI.mode_text(wb) if wb.has("mode") else String(wb.get("state", "")))
	var bl := ArmyPanel.band_line(wb)
	if bl != "":
		RecKit.line(c, bl, "Small")
	var rows := []
	var role := String({"caravan": "caravan", "militia": "militia"}.get(String(wb.get("kind", "")), "army"))
	for u in units:
		var uu: Unit = u
		var rr := Persons.roster_row(Game, uu, role)
		rows.append({"name": uu.name, "rk": uu.rank, "age": int(rr["age"]), "renown": float(uu.renown),
			"_l": ("%s %s" % [String(rr["rank"]).capitalize(), uu.name]).strip_edges(), "_r": String(rr["weapon"]),
			"_d": "%s; age %d; %s" % [("the %s of %s" % [rr["household"], rr["town"]]) if String(rr["household"]) != "" else "no register record", int(rr["age"]),
				("%s a day" % _m(float(rr["pay_day"]))) if float(rr["pay_day"]) > 0.0 else "unpaid or no pay"],
			"_s": uu.name, "_tap": func(): scr.open_unit(uu)})
	var rc := RecKit.card(box, "Roster")
	rc.add_child(RecTable.make([{"k": "rk", "t": "Rank", "num": true}, {"k": "name", "t": "Name"}, {"k": "age", "t": "Age", "num": true},
		{"k": "renown", "t": "Renown", "num": true}], rows, "rk", false, [], true))

## Shared by the live caravan and the town's bounded history of closed trips.
static func caravan_receipt(box: VBoxContainer, receipt: Dictionary) -> void:
	if receipt.is_empty(): return
	var c := RecKit.card(box, "Caravan receipt", "%s -> %s; %s" % [
		RecData.tname(String(receipt.get("origin", ""))), RecData.tname(String(receipt.get("destination", ""))),
		String(receipt.get("status", "out"))])
	RecKit.kv(c, "Departed", Calendar.text(float(receipt.get("depart_day", 0.0))))
	var expected: Dictionary = receipt.get("expected", {})
	var realized: Dictionary = receipt.get("realized", {})
	var rows := []
	for entry in [["buy_cost", "Buy cost"], ["sale_value", "Sale value"], ["duties", "Duties"], ["crew", "Crew"], ["lost_coin", "Lost purse"], ["net", "Net"]]:
		rows.append({"values": [entry[1], _m(float(expected.get(entry[0], 0.0))), _m(float(realized.get(entry[0], 0.0)))]})
	RecKit.grid(c, ["Coins", "Expected", "Realized"], rows, [1.4, 1, 1])
	RecKit.line(c, "Crew: the home market pays wages to real households; their existing food budget feeds them. Treasury funds cargo. Expected prices are held at departure.", "Small")
	if String(receipt.get("unpaid_cargo", "")) != "":
		RecKit.kv(c, "Unpaid cargo still on the wagons", String(receipt["unpaid_cargo"]))

static func remembered(e: Dictionary, f: Dictionary) -> Array:
	var out := []
	var living := {}
	for family in e.get("fams", []):
		if family.get("gone", false): continue
		for p in Persons.pp(family) + Persons.kp(family): living[int(p[0])] = true
	for p in f.get("dp", []):
		if not living.has(int(p[0])): out.append(p)
	return out

static func departure_text(e: Dictionary, p: Array) -> String:
	for d in Census._book(e)["deaths"]:
		if int(d[1]) == int(p[0]):
			return "died aged %d, %s: %s" % [int(d[3]), RecTown._day_word(float(d[0])), String(d[5])]
	return "departed; aged %d at the current date" % Persons.age_of(p, float(Game.day))
