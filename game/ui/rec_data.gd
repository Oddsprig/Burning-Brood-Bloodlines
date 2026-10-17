class_name RecData
extends RefCounted
## Every economy read the records screen makes goes through here (town_econ.gd, families.gd, businesses.gd,
## loans.gd, shelter.gd, goods.gd are being rebuilt by the economy work: bronze coins, wages, treasury, granary).
## When those land, this file is the one place to fix: field names, the money word, new fields that replace a
## "not tracked" line. Read-only: nothing here changes the sim.

const MONEY := "coins"   # the coinage spec (05-coinage.md): bronze coins, 100 a labourer's day

static func money(v: float) -> String:
	return "%s %s" % [RecKit.num(v), MONEY]

static func D() -> Dictionary:
	return TownEcon.data()

static func econ(t: Dictionary) -> Dictionary:
	return t.get("econ", {}) if TownEcon.has_econ(t) else {}

static func town(tid: String) -> Dictionary:
	return Game.world.get("towns", {}).get(tid, {})

static func tname(tid: String) -> String:
	return String(town(tid).get("name", tid))

# ---------------------------------------------------------------- families
## Families still in town (not gone, not the town estate).
static func fams(e: Dictionary) -> Array:
	return (e.get("fams", []) as Array).filter(func(f): return not f.get("gone", false) and not f.get("estate", false))

static func fam(e: Dictionary, fid: int) -> Dictionary:
	var a: Array = e.get("fams", [])
	return a[fid] if fid >= 0 and fid < a.size() else {}

static func purse(f: Dictionary) -> float:
	return float(f.get("purse", 0.0))

static func debt(f: Dictionary) -> float:
	return float(f.get("debt", 0.0))

## Income last week (wages, land, casual work, own business), per day.
static func income_day(f: Dictionary) -> Variant:
	return float(f["inc"]) / 7.0 if f.has("inc") else null

static func staff_text(b: Dictionary) -> String:
	var kw := int(b.get("kw", 0))
	var keeper_place := 1 if int(b.get("owner", -1)) >= 0 and not String(b["type"]) in ["farm", "estate"] else 0
	return "%d at work: %d of %d paid staff places%s" % [int(b["workers"]) + kw, int(b["workers"]), int(b["cap"]), "; keeper working for business profit" if kw > 0 else ("; keeper absent" if keeper_place > 0 else "")]

static func hungry_weeks(f: Dictionary) -> int:
	return int(f.get("hungry", 0))

static func homeless(f: Dictionary) -> bool:
	return int(f.get("homes", 1)) <= 0

static func poorhouse(f: Dictionary) -> bool:
	return bool(f.get("shel", false))

static func destitute(f: Dictionary) -> bool:
	return Shelter.destitute(f)

static func hardship(f: Dictionary) -> float:
	return Families.hardship(f)

static func rich_purse() -> float:
	return float(D()["family"]["rich_purse"])

static func min_purse() -> float:
	return float(D()["family"]["min_purse"])

## Class: the barge economy's own (f.cls, set weekly from savings and holdings: poor / middling / rich); older
## records without it by purse: rich above the economy's rich line, poor below its broke line, middling.
static func wealth_class(f: Dictionary) -> String:
	if f.has("cls"):
		return ["poor", "middling", "rich"][clampi(int(f["cls"]), 0, 2)]
	var p := purse(f)
	if p > rich_purse():
		return "rich"
	if p < min_purse():
		return "poor"
	return "middling"

## The family's state, worst real one first: poorhouse, homeless, destitute, hungry, indebted, getting by
## (any hardship), comfortable.
const STATES := ["poorhouse", "homeless", "destitute", "hungry", "indebted", "getting by", "comfortable"]
static func state(f: Dictionary) -> String:
	if poorhouse(f): return "poorhouse"
	if destitute(f): return "destitute"
	if homeless(f): return "homeless"
	if hungry_weeks(f) > 0: return "hungry"
	if debt(f) > 0.5: return "indebted"
	if hardship(f) > 0.0: return "getting by"
	return "comfortable"

static func state_color(s: String) -> Color:
	return {"comfortable": UiTheme.GOOD, "getting by": UiTheme.INK, "indebted": UiTheme.WARN, "hungry": UiTheme.BAD,
		"homeless": UiTheme.BAD, "destitute": UiTheme.BAD, "poorhouse": UiTheme.WARN}.get(s, UiTheme.INK)

static func people(f: Dictionary) -> int:
	return Families.people(f)

## Fresh population for a records build, through the census's authoritative typed read.
static func live_people(e: Dictionary) -> int:
	return Census.people(e)

static func acres(f: Dictionary) -> int:
	return Families.acres(f)

static func heads(f: Dictionary) -> int:
	return Families.heads(f)

## Members of the family in a service state ("hire" = in the recruit pool).
static func n_state(f: Dictionary, st: String) -> int:
	var n := 0
	for p in f.get("pp", []):
		if String(p[4]) == st:
			n += 1
	return n

# ---------------------------------------------------------------- the town
static func treasury(e: Dictionary) -> float:
	return float(e.get("treasury", 0.0))

static func stats(e: Dictionary) -> Dictionary:
	return e.get("stats", {})

static func head(e: Dictionary) -> Dictionary:
	return e.get("head", {})

## The labourer's day wage (barge part 3 section 1: set each day by the work there is for the hands there are);
## older towns: the town fields' hired hands (the estate row).
static func day_wage(e: Dictionary) -> Variant:
	if e.has("dwage"):
		return Barge.day_wage(e)
	var bi := int(e.get("estate_biz", -1))
	var biz: Array = e.get("biz", [])
	return float(biz[bi]["wage"]) if bi >= 0 and bi < biz.size() else null

static func price(t: Dictionary, g: String) -> float:
	return Goods.price_f(t, g)

# ---------------------------------------------------------------- the barge economy's own fields
## This year's harvest factor (weather: 1 = a normal year), null before the town's first harvest roll.
static func harvest_factor(e: Dictionary) -> Variant:
	return float(e["hf"]) if e.has("hf") else null

## The realm's price level (1 = the coin as the world began) and money index (coin held over the coin needed).
static func price_level(e: Dictionary) -> float:
	return Barge.pl(e)

static func money_index(fid: String) -> Variant:
	var fac: Dictionary = Game.world.get("factions", {}).get(fid, {})
	return float(fac["mindex"]) if fac.has("mindex") else null

## The town's coin shortage (0 = coin enough for its trade, 1 = none).
static func coin_short(e: Dictionary) -> float:
	return Barge.shortage(e)

## Famine stages (barge part 4 section 5): the town's and each family's (0 fed .. 5 collapse).
static func stage_word(s: int) -> String:
	return String(Barge.STAGES[clampi(s, 0, Barge.STAGES.size() - 1)])

static func town_stage(e: Dictionary) -> int:
	return int(e.get("fstage", 0))

static func fam_stage(f: Dictionary) -> int:
	return int(f.get("hungry", 0))

## Days the family went short of food at its last turn (the one hunger number: Sickness reads it too).
static func days_short(f: Dictionary) -> float:
	return float(f.get("fshort", 0.0))

## The granary today: [day, grain sold (-) or bought (+), price a meal] ([] before its first barge day).
static func granary_today(e: Dictionary) -> Array:
	return e.get("gran_today", [])

## Treasury lines (start / short / full, scaled by the town's people), this month's taxes and the change over the
## month, the levers (service money scale, house tax surcharge), the garrison owed.
static func treasury_lines(e: Dictionary) -> Dictionary:
	return Barge.treasury_lines(e) if e.has("ruler") else {}

static func ruler(e: Dictionary) -> Dictionary:
	return e.get("ruler", {})

## A business's books (barge part 3 section 6): health word, the 14-day average profit a day, loss days.
static func biz_health(b: Dictionary) -> Variant:
	return String(b["health"]) if b.has("health") else null

static func biz_profit(b: Dictionary) -> Variant:
	return float(b["p14"]) if b.has("p14") else null

static func biz_loss_days(b: Dictionary) -> int:
	return int(b.get("ld", 0))

static func base_price(g: String) -> float:
	return float(D()["goods"].get(g, {}).get("price", 1.0))

static func price_week_ago(e: Dictionary, g: String) -> Variant:
	var pw: Dictionary = e.get("pweek", {})
	return float(pw[g]) if pw.has(g) else null

static func stock(e: Dictionary, g: String) -> int:
	return int(e.get("stock", {}).get(g, 0))

## Demand per day the market prices on (households' orders + businesses' inputs + the granary), smoothed.
static func demand(e: Dictionary, g: String) -> float:
	return float(e.get("dem", {}).get(g, 0.0))

## A category's market stock and smoothed demand: look up each ledger once for the whole group.
static func market_totals(e: Dictionary, goods: Array) -> Array:
	var stock_ledger: Dictionary = e.get("stock", {})
	var demand_ledger: Dictionary = e.get("dem", {})
	var stock_n := 0
	var demand_n := 0.0
	for g in goods:
		stock_n += int(stock_ledger.get(g, 0))
		demand_n += float(demand_ledger.get(g, 0.0))
	return [stock_n, demand_n]

static func price_why(e: Dictionary, g: String) -> String:
	return String(e.get("why", {}).get(g, ""))

static func goods_cat(g: String) -> String:
	return String(D()["goods"].get(g, {}).get("cat", ""))

static func good_name(e: Dictionary, g: String) -> String:
	return TownEcon.label(e, g) if not e.is_empty() else Goods.good_name(g)

## Food price index (x1.00 = normal): the three foods' prices over base, averaged by the diet mix.
static func food_index(t: Dictionary) -> float:
	var mix: Dictionary = D()["needs"]["food_mix"]
	var s := 0.0
	for g in mix:
		s += float(mix[g]) * price(t, g) / base_price(g)
	return s

static func staple_index(t: Dictionary) -> float:
	return price(t, "grain") / base_price("grain")

static func days_food(t: Dictionary) -> float:
	return TownEcon.days_food(t)

static func granary(e: Dictionary) -> int:
	return int(e.get("granary", 0))

## The head's granary target: granary_days of the town's food.
static func granary_target(e: Dictionary) -> int:
	return int(float(e.get("pop", 0)) * float(D()["needs"]["food"]) * float(D()["needs"]["granary_days"]))

static func granary_days(e: Dictionary) -> float:
	var use := float(e.get("pop", 0)) * float(D()["needs"]["food"])
	return float(granary(e)) / use if use > 0.0 else 0.0

static func barn(e: Dictionary, g: String) -> int:
	return int(e.get("barn", {}).get(g, 0))

## Days a household good lasts: market + household stores over the households' use this season.
static func days_of(e: Dictionary, g: String) -> float:
	var use := TownEcon.household_use(e, Calendar.season_index(float(e.get("day", 0))), [g])
	var have := float(e.get("stock", {}).get(g, 0)) + float(e.get("hh", {}).get(g, 0))
	return have / maxf(0.1, float(use.get(g, 0.1)))

static func household_use(e: Dictionary, g: String) -> float:
	return float(TownEcon.household_use(e, Calendar.season_index(float(e.get("day", 0))), [g]).get(g, 0.0))

static func homes_for_sale(e: Dictionary) -> int:
	return stock(e, "home")

static func empty_homes(e: Dictionary) -> int:
	var a: Array = e.get("fams", [])
	return int(a[0].get("homes", 0)) if not a.is_empty() else 0

static func land(e: Dictionary) -> Dictionary:
	return TownEcon.land_summary(e)

## Head by kind in the town, read from the herd records (every owner: families, herders, the town, drovers' herds
## waiting to be sold; oxen and small stock included). Older towns without records: the economy's totals.
## Herd totals and labour reads cache derived values in hd. The UI shares records
## but owns the shallow cache container; no simulation cache or herd is changed.
static func _herd_read(e: Dictionary) -> Dictionary:
	if not e.has("hd"):
		return e
	var read_e := e.duplicate()
	read_e["hd"] = (e["hd"] as Dictionary).duplicate()
	return read_e

static func herds(e: Dictionary) -> Dictionary:
	return Herds.town_heads(_herd_read(e))

## Herds (addendum 1 B): the records, ages, the kind's word, prices, the week's market and the books.
static func herd_records(e: Dictionary) -> Array:
	if not Herds.has(e):
		return []
	return (Herds.herds(e) as Dictionary).values()

static func herd_ages(e: Dictionary) -> Dictionary:
	return Herds.town_ages(e)

static func herd_word(e: Dictionary, k: String) -> String:
	return Herds.word(e, k)

static func herd_n(e: Dictionary, n: int, k: String) -> String:
	return Herds.n_word(e, n, k)

static func herd_line(e: Dictionary, h: Dictionary) -> String:
	return Herds.line(e, h)

static func herd_head(h: Dictionary) -> int:
	return Herds.head(h)

static func herd_owner(e: Dictionary, h: Dictionary) -> String:
	return Herds.owner_text(e, h)

## The family whose record a tap on a herd opens (owners, a herder's keepers, the town = -1).
static func herd_owner_fid(e: Dictionary, h: Dictionary) -> int:
	var f := Herds.grazer(e, h)
	return f if f > 0 else -1

## "; 20% sick (swine fever); 60% of the sows bred this season" (empty when well and not breeding).
static func herd_state(h: Dictionary) -> String:
	var out := ""
	var inf: Dictionary = h.get("inf", {})
	if not inf.is_empty():
		out += "; %d%% sick (%s)" % [int(round(Herds.sick(h) * 100.0)), ", ".join(PackedStringArray(inf.keys()))]
	if h.has("bred"):
		out += "; %d%% of the females put to the male this season" % int(round(float(h["bred"]) * 100.0))
	return out

static func herders(e: Dictionary, h: Dictionary) -> Array:
	return Herds.herders(_herd_read(e), h)

## Days of winter fodder in reach of the town's herds (own hay + barns + market) at their feed; null = none kept.
static func fodder_days(e: Dictionary) -> Variant:
	var d := Herds.fodder_days(e)
	return d if d >= 0.0 else null

static func animal_kinds() -> Array:
	return Herds.kinds()

## The price of a grown head in this town (coins).
static func animal_price(e: Dictionary, k: String) -> float:
	return Herds.price(e, k)

static func animal_base(k: String) -> float:
	return float(Herds.kind(k).get("price", 0.0))

## Head offered, wanted (oxen, restocking) and sold last week, by kind.
static func animals_week(e: Dictionary) -> Dictionary:
	if not Herds.has(e):
		return {}
	var hd: Dictionary = e["hd"]
	return {"offered": hd.get("ofk", {}), "wanted": hd.get("wak", {}), "sold": hd.get("sok", {})}

## The herd book: {born, bought, sold, slaughtered, stolen, looted, died {cause: n}}; which: tot | yr | ly.
static func herd_book(e: Dictionary, which: String = "yr") -> Dictionary:
	return Herds.book(e, which)

static func herd_log(e: Dictionary) -> Array:
	return e.get("hd", {}).get("log", [])

## A family's herds and the beasts in its pens (records owned by the family; the town estate's for fid 0).
static func family_herds(e: Dictionary, fid: int) -> Array:
	return Herds.of_family(e, fid) if Herds.has(e) else []

## A business's own herds (a herder's flock, a drover's herd waiting to be sold).
static func biz_herds(e: Dictionary, bid: int) -> Array:
	return Herds.of_owner(e, "b", bid) if Herds.has(e) else []

## A business's chain this season and last: [[from|to, who, what, n, this season]].
static func biz_chain(b: Dictionary) -> Array:
	return Herds.chain_rows(b)

static func manure_factor(e: Dictionary) -> float:
	return Herds.manure_f(e)

## Herds on the roads (droves): [{from, to, kind, head}].
static func droves() -> Array:
	var out := []
	for did in Game.world.get("droves", {}):
		var dv: Dictionary = Game.world["droves"][did]
		out.append({"from": String(dv["from"]), "to": String(dv["to"]), "kind": String(dv["h"]["k"]), "head": Herds.head(dv["h"])})
	return out

static func crop_word(e: Dictionary, crop: String) -> String:
	return TownEcon.variety_word(e, crop)

static func loan_rate(e: Dictionary) -> float:
	return Loans.rate(e)

static func loans_book(e: Dictionary) -> Dictionary:
	if e.has("stats"):
		return Loans.book(e)
	var read := e.duplicate()
	read["stats"] = {}
	return Loans.book(read)

static func tax(e: Dictionary) -> Dictionary:
	return e.get("tax", {})

static func tax_rules() -> Dictionary:
	return D()["tax"]

static func shelter_cap(t: Dictionary) -> int:
	return Shelter.cap(t)

static func shelter_n(e: Dictionary) -> int:
	return int(e.get("shel_n", 0))

# ---------------------------------------------------------------- businesses
static func biz(e: Dictionary) -> Array:
	return e.get("biz", [])

static func biz_title(e: Dictionary, b: Dictionary) -> String:
	# The title helper refreshes its per-day name cache; keep that UI read local.
	var read := e.duplicate()
	read["fams"] = (e.get("fams", []) as Array).map(func(f: Dictionary): return f if f.has("pp") and f.has("kp") else f.duplicate())
	return Businesses.title(read, b)

static func biz_trade(b: Dictionary) -> String:
	return String(D()["businesses"].get(String(b["type"]), {}).get("name", String(b["type"])))

static func biz_state(b: Dictionary) -> String:
	return Businesses.state_word(b)

static func till(b: Dictionary) -> float:
	return float(b.get("till", 0.0))

static func biz_wage(b: Dictionary) -> float:
	return float(b.get("wage", 0.0))

static func recipes(b: Dictionary) -> Array:
	return D()["businesses"].get(String(b["type"]), {}).get("recipes", [])

## Who keeps business b (v0.014; town spec 08 "every business is held by a real family member"): {fid, pid, name,
## how} - a family shop's keeper (the owner family's grown-up who works it: Families._keep); a farm's, the head of
## the family whose land it is; a town row's (or a family shop whose family has nobody free), the first of its staff.
## Empty when nobody is there.
static func keeper(e: Dictionary, b: Dictionary, context: Dictionary = {}) -> Dictionary:
	# The state house has a designated, paid head; another employee cannot stand in for that post.
	if String(b.get("type", "")) == "academy":
		var lead := Academy.lead_name(e, b)
		if lead.is_empty():
			return {}
		var person: Array = b["lead"]
		return {"fid": int(person[0]), "pid": int(person[1]), "name": lead, "how": Academy.lead_title(e) + " (state-funded head)"}
	var bid := int(b["id"])
	var owner := int(b.get("owner", -1))
	var race := Persons.race_of(e)
	if owner >= 0:
		var f := fam(e, owner)
		if not f.is_empty():
			if String(b["type"]) == "farm":
				# Legacy person getters create missing slots; keep those slots local.
				var read_f := f if f.has("pp") and f.has("kp") else f.duplicate()
				var hp := Persons.head_of(read_f)
				if not hp.is_empty():
					return {"fid": owner, "pid": int(hp[0]), "name": Persons.name_of(f, hp, race), "how": "head of the family"}
			elif int(b.get("kw", 0)) > 0:
				var wk := _family_work(e, f, context)
				for pid in wk:
					var j: Dictionary = wk[pid]
					if j.get("keeper", false) and int(j.get("biz", -1)) == bid:
						var p := Persons.by_pid(f, int(pid))
						return {"fid": owner, "pid": int(pid), "name": Persons.name_of(f, p, race) if not p.is_empty() else String(f["name"]), "how": "of the owning family"}
	var st := staff(e, bid, context)
	if not st.is_empty():
		return {"fid": int(st[0]["fid"]), "pid": int(st[0]["pid"]), "name": String(st[0]["name"]), "how": "of the staff"}
	return {}

## Who works at business bid: [{fid, pid, name, title, wage}] (the register's own place-holders, Persons.work).
static func staff(e: Dictionary, bid: int, context: Dictionary = {}) -> Array:
	var out := []
	var race := Persons.race_of(e)
	var families: Array = context["job_fams"].get(bid, []) if context.has("job_fams") else fams(e)
	for f in families:
		if not (f.get("jobs", {}) as Dictionary).has(bid) and not (f.get("jobs", {}) as Dictionary).has(str(bid)):
			continue
		var wk := _family_work(e, f, context)
		for pid in wk:
			var j: Dictionary = wk[pid]
			if int(j.get("biz", -1)) == bid and not j.get("keeper", false):
				var p := Persons.by_pid(f, int(pid))
				out.append({"fid": int(f["id"]), "pid": int(pid), "name": Persons.name_of(f, p, race) if not p.is_empty() else String(f["name"]),
					"title": String(j["title"]), "wage": float(j["wage"])})
	return out

## A single records build's lookup. Keep family/work order and the integer/string job-key rules;
## resolve work only for families actually read. The caller discards this after building its list/page.
static func work_context(e: Dictionary) -> Dictionary:
	var by_job := {}
	for f: Dictionary in fams(e):
		var seen := {}
		for key in f.get("jobs", {}):
			var bid := int(key)
			if not (key is int or key is String and key == str(bid)) or seen.has(bid):
				continue
			seen[bid] = true
			if not by_job.has(bid): by_job[bid] = []
			by_job[bid].append(f)
	return {"job_fams": by_job, "work": {}}

static func _family_work(e: Dictionary, f: Dictionary, context: Dictionary) -> Dictionary:
	if not context.has("work"):
		return Persons.work(_herd_read(e), f)
	var fid := int(f["id"])
	if not context["work"].has(fid):
		# One read container per existing page-build context retains derived lookup
		# reuse while keeping Persons.work's herd-labour cache outside saved state.
		if not context.has("herd_read"):
			context["herd_read"] = _herd_read(e)
		context["work"][fid] = Persons.work(context["herd_read"], f)
	return context["work"][fid]

# ------------------------------------------------------------------ the research house (campaign/academy.gd, v0.012)
const QUALITY_WORDS := ["poor", "fair", "good", "fine", "superior", "masterwork"]

static func research(fid: String) -> Dictionary:
	return Academy.report(Game.world, fid)

static func is_house(b: Dictionary) -> bool:
	return String(b.get("type", "")) == "academy"

## The faction's research house in plain lines: name and town, the lead (title), staff, budget, each line.
static func research_lines(fid: String) -> Array:
	var r := research(fid)
	var out := []
	if r["has"]:
		out.append("%s in %s: %s." % [r["name"], r["town"], r["state"]])
		out.append(("%s: %s, skill %d of 15." % [r["title"], r["lead"], int(r["lskill"])]) if String(r["lead"]) != "" else "%s: the post stands empty." % r["title"])
		out.append("Staff %d (skill %.1f of 15) of %d places with the lead; till %s." % [int(r["staff"]), float(r["skill"]), int(r["cap"]), money(float(r["till"]))])
	else:
		out.append("No research house (the realm holds no capital).")
	out.append("The state's interest %d%%; budget %s a day; paid in at the last faction turn %s; steel pieces in its towns %d." % [
		int(round(100.0 * float(r["interest"]))), money(float(r["budget"])), money(float(r["paid"])), int(r["met"])])
	for L in r["lines"]:
		var q := int(L["best_q"])
		var qw: String = "no steel" if q < 0 else String(QUALITY_WORDS[q]) + " at best"
		if not bool(L.get("caps", true)):   # v0.014: bronze and iron - know-how gates smelting and smithing, not quality
			qw = ("its smiths may smelt and work %s" % L["name"]) if float(L["kh"]) > 0.0 else ("its smiths cannot smelt or work %s; bought, looted and repaired pieces are used" % L["name"])
		if bool(L["open"]) and float(L.get("factor", 1.0)) != 1.0:
			qw += ", learns at %s x" % RecKit.num(float(L["factor"]))
		if not bool(L["open"]) and float(L["kh"]) >= 100.0:
			out.append("Line %s: not a line here; this race knows it in full (know-how 100%%, %s)." % [L["name"], qw])
		elif not bool(L["open"]):
			out.append("Line %s: closed to this race for good (know-how %d%%, %s)." % [L["name"], int(L["kh"]), qw])
		elif not bool(L["active"]):
			out.append("Line %s: mastered (know-how %d%%, %s); not worked." % [L["name"], int(L["kh"]), qw])
		else:
			out.append("Line %s: know-how %.1f%% (%s), research %d; %d%% of the budget (%s a day), %.1f staff on it." % [L["name"], float(L["kh"]), qw,
				int(L["pts"]), int(round(100.0 * float(L["share"]))), money(float(L["budget_on"])), float(L["staff_on"])])
	var h: Array = r["hist"]
	if not h.is_empty():
		var wk := []
		for x in h.slice(maxi(0, h.size() - 6)):
			wk.append("%d" % int(x[1]))
		out.append("Research a week, the last %d weeks: %s." % [wk.size(), ", ".join(PackedStringArray(wk))])
	return out

static func research_log(fid: String) -> Array:
	return research(fid)["log"]
