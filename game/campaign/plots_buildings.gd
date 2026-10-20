class_name PlotsBuildings
extends RefCounted
## Plot cards, worker reads (UI/text views), and town civic buildings split from Plots
## (game/campaign/plots.gd) to keep each file focused and under the size threshold.
## Structure only; all Plots.* entry points delegate here with identical behavior.

const FIELD := Plots.FIELD
const ORCHARD := Plots.ORCHARD
const VINEYARD := Plots.VINEYARD
const PASTURE := Plots.PASTURE
const WOOD := Plots.WOOD
const HOME := Plots.HOME
const YARD := Plots.YARD
const MINE := Plots.MINE
const WASTE := Plots.WASTE
const ROAD := Plots.ROAD
const STATE := Plots.STATE
const USE_NAMES := Plots.USE_NAMES
const LAND_USES := Plots.LAND_USES
const TOWN := Plots.TOWN
const MARKET := Plots.MARKET
const F_SEIZED := Plots.F_SEIZED
const F_CLEARING := Plots.F_CLEARING
const F_SALE := Plots.F_SALE
const LOADS_PER_ACRE := Plots.LOADS_PER_ACRE
const CLEAR_DAYS_ACRE := Plots.CLEAR_DAYS_ACRE

# ================================================================== reading a plot
static func owner_text(e: Dictionary, fid: int) -> String:
	if fid == MARKET:
		return "the market (for sale)"
	if fid == TOWN:
		return "the town"
	var fams: Array = e["fams"]
	if fid < 0 or fid >= fams.size():
		return "nobody"
	return "the %s" % Backstory.plural(String(fams[fid]["name"]))

## Words for what is on the plot: "barley field (ripe)", "dense wood", "home of the Marshes", "the Thorne tanner's yard".
static func use_text(e: Dictionary, P: Dictionary, i: int, day: float) -> String:
	var u := int(P["use"][i])
	match u:
		FIELD, ORCHARD, VINEYARD:
			var crop: String = P["crops"][int(P["sub"][i])]
			var v := String(P.get("variety", [])[i]) if P.has("variety") and P["variety"].size() > i and String(P["variety"][i]) != "" else TownEcon.variety_word(e, crop)
			return "%s %s (%s)" % [v, USE_NAMES[u], season_word(day)] if u == FIELD else "%s %s" % [v, USE_NAMES[u]]
		WOOD:
			var s := Plots.wood_stage(P, i)
			return {"dense": "dense wood", "thin": "thinned wood", "felled": "felled wood (stumps)", "regrowing": "regrowing wood"}[s] + \
				(" (being cleared)" if int(P["fl"][i]) & F_CLEARING else "")
		YARD, MINE:
			var b: Dictionary = (e["biz"] as Array)[int(P["sub"][i])] if int(P["sub"][i]) < (e["biz"] as Array).size() else {}
			return "yard of %s" % Businesses.title(e, b) if not b.is_empty() else USE_NAMES[u]
		STATE:
			var bl: Dictionary = P["bld"][int(P["sub"][i])]
			return String(bl["n"])
		WASTE:
			return "rough hills" if int(P["sub"][i]) == 1 else "rough ground"
		ROAD:
			return "town gate" if int(P["sub"][i]) == 1 else "road"
		HOME:
			return String(TownEcon.culture_of(e)["home"]["type"])
	return USE_NAMES[u]

## Fields by the season: sown, growing, ripe, stubble (after the harvest month's first two thirds), bare.
static func season_word(day: float) -> String:
	var si := Calendar.season_index(day)
	match si:
		0: return "sown"
		1: return "growing"
		2: return "ripe" if Calendar.day_of_season(day) <= 20 else "stubble"
	return "bare"

## Gold the plot is worth by the sim's own prices: land at the land price, a house at the market's price for
## a home, a business yard at the town's asking price for a business; -1 = not priced (town ground).
static func value(e: Dictionary, P: Dictionary, i: int) -> int:
	var u := int(P["use"][i])
	if LAND_USES.has(u):
		return int(P["ac"][i]) * int(TownEcon.data()["land"]["acre_price"])
	if u == HOME:
		return int(round(float(e.get("price", {}).get("home", 0.0))))
	if u == YARD or u == MINE:
		var b: Dictionary = (e["biz"] as Array)[int(P["sub"][i])]
		return int(80.0 + float(b["cap"]) * 25.0)   # what the town asks for a business (TownEcon._sell_businesses)
	return -1

## For sale now: the town estate's land (the land loop sells it), a business up for sale or closed, a house
## at the market.
static func for_sale(P: Dictionary, i: int) -> bool:
	var u := int(P["use"][i])
	if LAND_USES.has(u):
		return int(P["own"][i]) == TOWN
	if u == YARD or u == MINE:
		return int(P["fl"][i]) & F_SALE != 0
	return u == HOME and int(P["own"][i]) == MARKET

## Worked today: farm plots by the holder's share of its land worked (f.worked), a family's plots in order;
## pasture by the grazing family; yards when the business has workers; the town's buildings always.
static func worked_mask(e: Dictionary, P: Dictionary) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(Plots.count(P))
	var per := {}
	for i in Plots.count(P):
		if LAND_USES.has(int(P["use"][i])):
			var o := int(P["own"][i])
			if not per.has(o):
				per[o] = []
			per[o].append(i)
	var fams: Array = e["fams"]
	for o in per:
		var f: Dictionary = fams[int(o)] if int(o) >= 0 and int(o) < fams.size() else {}
		var wk := float(f.get("worked", 0.0))
		var l: Array = per[o]
		var n := int(round(wk * float(l.size())))
		for k in mini(n, l.size()):
			m[l[k]] = 1
	for i in Plots.count(P):
		var u := int(P["use"][i])
		if u == PASTURE and int(P["ten"][i]) >= 0 and int(P["ten"][i]) < fams.size():
			m[i] = 1 if float(fams[int(P["ten"][i])].get("worked", 0.0)) > 0.0 else 0
		elif u == YARD or u == MINE:
			var b: Dictionary = (e["biz"] as Array)[int(P["sub"][i])]
			m[i] = 1 if (int(b.get("workers", 0)) > 0 or int(b.get("kw", 0)) > 0) and not b.get("closed", false) else 0
		elif u == STATE:
			m[i] = 1
	return m

## The people who work a farm plot: the holder family's members on its own land (Persons.work), or the hands
## hired on the town fields for the estate. [{fid, pid, name}]
static func workers(e: Dictionary, P: Dictionary, i: int) -> Array:
	var out := []
	var u := int(P["use"][i])
	var fams: Array = e["fams"]
	var race := Persons.race_of(e)
	if LAND_USES.has(u) or u == PASTURE:
		var fid := int(P["own"][i]) if u != PASTURE else int(P["ten"][i])
		if fid < 0 or fid >= fams.size():
			return out
		if fid == TOWN:
			return staff_of_biz(e, int(e.get("estate_biz", -1)))
		var f: Dictionary = fams[fid]
		var wk := Persons.work(e, f)
		for pid in wk:
			if String(wk[pid]["kind"]) == ("herd" if u == PASTURE else "land"):
				var p := Persons.by_pid(f, int(pid))
				if not p.is_empty():
					out.append({"fid": fid, "pid": int(pid), "name": Persons.name_of(f, p, race)})
	elif u == YARD or u == MINE:
		return staff_of_biz(e, int(P["sub"][i]))
	return out

## Register persons working at a business row (any family): [{fid, pid, name}].
static func staff_of_biz(e: Dictionary, bid: int) -> Array:
	var out := []
	if bid < 0:
		return out
	var race := Persons.race_of(e)
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		var jobs: Dictionary = f.get("jobs", {})
		if int(jobs.get(bid, jobs.get(str(bid), 0))) <= 0:
			continue
		var wk := Persons.work(e, f)
		for pid in wk:
			if int(wk[pid].get("biz", -1)) == bid:
				var p := Persons.by_pid(f, int(pid))
				if not p.is_empty():
					out.append({"fid": int(f["id"]), "pid": int(pid), "name": Persons.name_of(f, p, race)})
	return out

## Register persons of the families holding a casual job (rat catchers keep the granary).
static func casual_staff(e: Dictionary, job: String) -> Array:
	var out := []
	var race := Persons.race_of(e)
	for f in e["fams"]:
		if f.get("gone", false) or (int(f.get("cj", {}).get(job, 0)) <= 0 and not f.get("child_cj", {}).values().has(job)):
			continue
		var wk := Persons.work(e, f)
		for pid in wk:
			if String(wk[pid].get("cj", "")) == job:
				var p := Persons.by_pid(f, int(pid))
				if not p.is_empty():
					out.append({"fid": int(f["id"]), "pid": int(pid), "name": Persons.name_of(f, p, race)})
	return out

## Everything the plot card shows (data only; ui/land_map.gd lays it out). Lines are plain text; `taps` are
## {text, fid} rows the card makes into buttons (a family record, a person's household).
static func card(game, town: Dictionary, i: int) -> Dictionary:
	var e: Dictionary = town["econ"]
	var P := Plots.of(town)
	var day := float(game.day)
	var u := int(P["use"][i])
	var lines := []
	var taps := []
	var title := Plots._cap(use_text(e, P, i, day))
	var lodging := TownHousing.plot_info(e, i)
	if not lodging.is_empty():
		lodging["plot"] = i; lodging["hist"] = P["h"][i]; return lodging
	if u == STATE:
		var info := building(game, town, int(P["sub"][i]))
		return {"title": Plots._cap(String(info["name"])), "lines": info["lines"], "taps": info["taps"], "plot": i, "hist": info["hist"]}
	lines.append("%s, %s." % [USE_NAMES[u].capitalize() if u != STATE else "Town building", TownEcon.n_of(int(P["ac"][i]), "acres")])
	var own := int(P["own"][i])
	if u == HOME:
		if int(P["ten"][i]) >= 0:
			lines.append("Held by the town, let to %s at %d coins a week." % [owner_text(e, int(P["ten"][i])), int(round(Shelter.rent_week(e)))])
			taps.append({"text": "The household: %s" % owner_text(e, int(P["ten"][i])), "fid": int(P["ten"][i])})
		elif own > 0:
			lines.append("Home of %s." % owner_text(e, own))
			taps.append({"text": "The household: %s" % owner_text(e, own), "fid": own})
		else:
			lines.append("Held by %s, standing empty." % owner_text(e, own))
	elif u == PASTURE and e.has("hd"):   # herds as records: owner, each herd, its herders, what the plot carries
		var hc := Herds.card_lines(game, town, P, i)
		lines.append_array(hc["lines"])
		taps.append_array(hc["taps"])
	elif u == PASTURE:
		lines.append("The town's common grazing.")
		if int(P["ten"][i]) > 0:
			var gf: Dictionary = e["fams"][int(P["ten"][i])]
			var hd := []
			for a in gf["herd"]:
				hd.append(TownEcon.n_of(int(gf["herd"][a]), String(a)))
			lines.append("Grazed by %s's herd (%s in all)." % [owner_text(e, int(P["ten"][i])), ", ".join(PackedStringArray(hd))])
			taps.append({"text": "Herd owners: %s" % owner_text(e, int(P["ten"][i])), "fid": int(P["ten"][i])})
	elif u == YARD or u == MINE:
		var b: Dictionary = (e["biz"] as Array)[int(P["sub"][i])]
		lines.append("%s: %s, %d of %d at work, %d coins a day%s." % [Plots._cap(Businesses.title(e, b)), "closed" if b.get("closed", false) else Businesses.state_word(b),
			int(b["workers"]), int(b["cap"]), int(round(float(b["wage"]))), ", for sale" if for_sale(P, i) else ""])
		if own > 0:
			taps.append({"text": "Owners: %s" % owner_text(e, own), "fid": own})
		else:
			lines.append("Owned by the town.")
	else:
		lines.append("Held by %s%s." % [owner_text(e, own), " (seized)" if int(P["fl"][i]) & F_SEIZED else ""])
		if own > 0:
			taps.append({"text": "Owner: %s" % owner_text(e, own), "fid": own})
	if u == WOOD:
		lines.append("Standing wood: %d%% of a full wood (about %d loads)." % [int(round(float(P["st"][i]) * 100.0)), int(float(P["st"][i]) * float(P["ac"][i]) * LOADS_PER_ACRE)])
		if int(P.get("clear", -1)) == i:
			lines.append("Being cleared: %d of %d worker-days done." % [int(P["cl_done"]), int(CLEAR_DAYS_ACRE * float(P["ac"][i]))])
	if u == HOME and e.has("hd"):   # herds: the household's pens (hens, rats, hives)
		var pc := Herds.card_lines(game, town, P, i)
		lines.append_array(pc["lines"])
	var ws := workers(e, P, i) if not (u == PASTURE and e.has("hd")) else []
	if not ws.is_empty():
		var nm := []
		for wp in ws.slice(0, 6):
			nm.append(String(wp["name"]))
		lines.append("Worked by %s%s." % [", ".join(PackedStringArray(nm)), (" and %d more" % (ws.size() - 6)) if ws.size() > 6 else ""])
		var seen := {}
		for wp in ws.slice(0, 4):
			if not seen.has(int(wp["fid"])):
				seen[int(wp["fid"])] = true
				taps.append({"text": "Worker: %s" % wp["name"], "fid": int(wp["fid"])})
	elif LAND_USES.has(u):
		lines.append("Nobody works it today.")
	var v := value(e, P, i)
	if v >= 0:
		lines.append("Value %d coins%s." % [v, (" (the land price, %d an acre)" % int(TownEcon.data()["land"]["acre_price"])) if LAND_USES.has(u) else ""])
	if for_sale(P, i) and v >= 0:
		lines.append("For sale: %d coins." % v)
	if own > 0 and LAND_USES.has(u):
		var of2: Dictionary = e["fams"][own]
		if float(of2.get("debt", 0.0)) > 0.01:
			lines.append("Loan: the %s owe %d coins to the %s; this land is their pledge." % [Backstory.plural(String(of2["name"])), int(round(float(of2["debt"]))),
				String(e["head"]["title"])])
	var h := Plots.hist_lines(P, i)
	if h.is_empty() and LAND_USES.has(u):
		h = ["Held by %s since before the land book was begun." % owner_text(e, own)]
	return {"title": title, "lines": lines, "taps": taps, "plot": i, "hist": h}

# ================================================================== the town's own buildings (addendum A)
## Live record of one of the town's buildings: who runs it, staff and residents (register persons), capacity,
## stock, upkeep a day (what the treasury really pays for it now) and what it is doing. Reads the economy's own
## data (militia, shelter, armory, granary, collectors); nothing is copied.
## {kind, name, plot, runner {fid, pid, name} | {}, staff [...], residents [...], cap, used, stock, upkeep, now, lines, taps, hist}
static func building(game, town: Dictionary, bi: int) -> Dictionary:
	var e: Dictionary = town["econ"]
	var P := Plots.of(town)
	var bl: Dictionary = P["bld"][bi]
	var k := String(bl["k"])
	var race := Persons.race_of(e)
	var head: Dictionary = e.get("head", {})
	var hf: Dictionary = e["fams"][int(head.get("fam", 0))]
	var hp := Persons.head_of(hf)
	var head_ref := {} if hp.is_empty() else {"fid": int(hf["id"]), "pid": int(hp[0]), "name": Persons.name_of(hf, hp, race),
		"role": String(head.get("title", "head"))}
	var out := {"kind": k, "name": String(bl["n"]), "plot": int(bl["p"]), "runner": {}, "staff": [], "residents": [], "cap": 0, "used": 0,
		"stock": "", "upkeep": 0.0, "now": "", "cond": 1.0}
	match k:
		"keep":
			out["runner"] = head_ref
			out["residents"] = _household(e, hf)
			out["cap"] = maxi(1, int(hf.get("homes", 1))) * int(TownEcon.culture_of(e)["home"]["room"])
			out["used"] = (out["residents"] as Array).size()
			out["now"] = "Seat of the %s; the household of %d lives here." % [String(head.get("title", "head")), int(out["used"])]
		"hall":
			out["runner"] = head_ref
			var col := -1
			for b in e["biz"]:
				if String(b["type"]) == "collector":
					col = int(b["id"])
			out["staff"] = staff_of_biz(e, col)
			if col >= 0:
				var cb: Dictionary = e["biz"][col]
				out["cap"] = int(cb["cap"])
				out["used"] = int(cb["workers"])
				out["upkeep"] = float(cb["workers"]) * float(cb["wage"])
			var lent := 0
			var debt := 0.0
			for f in e["fams"]:
				if float(f.get("debt", 0.0)) > 0.01 and not f.get("gone", false):
					lent += 1; debt += float(f["debt"])
			out["stock"] = "chest %d coins" % int(float(e.get("treasury", 0.0)))
			out["now"] = "The chest holds %d coins; %d loans out (%d coins); the land book has %d plots." % [int(float(e.get("treasury", 0.0))), lent, int(debt), Plots.count(P)]
		"barracks":
			var mil := _militia(game, town)
			out["residents"] = mil["people"]
			out["runner"] = mil["captain"]
			out["cap"] = int(e.get("barracks_beds", Militia.target_size(town)))
			out["used"] = (mil["people"] as Array).size()
			out["upkeep"] = mil["pay"]
			out["now"] = "Beds %d / %d." % [int(out["used"]), int(out["cap"])]
		"armory":
			out["runner"] = head_ref
			var have := (town.get("armory_items", []) as Array).size()
			var tgt := 0
			for c in e.get("arms_tgt", {}):
				tgt += int(e["arms_tgt"][c])
			out["cap"] = tgt
			out["used"] = have
			out["stock"] = "%d pieces of arms" % have
			out["now"] = "Arms %d against a target of %d." % [have, tgt]
		"granary":
			out["runner"] = head_ref
			out["staff"] = casual_staff(e, "rat_catcher")
			var cjw := float(TownEcon.data().get("casual_jobs", {}).get("rat_catcher", {}).get("wage", 0.0))
			out["upkeep"] = cjw * float((out["staff"] as Array).size())
			var gr := int(e.get("granary", 0))
			var per_day := maxf(1.0, float(e.get("pop", 1)) * float(TownEcon.data()["needs"]["food"]))
			out["used"] = gr
			out["stock"] = "%d grain" % gr
			out["now"] = "%d grain stored: %d days of bread for the town." % [gr, int(float(gr) / per_day)]
		"shelter":
			var wb := int(e.get("works_biz", -1))
			out["staff"] = staff_of_biz(e, wb)
			var keeper: Array = out["staff"]
			out["runner"] = keeper[0] if not keeper.is_empty() else head_ref
			var res := []
			for f in e["fams"]:
				if f.get("shel", false) and not f.get("gone", false):
					res.append_array(_household(e, f))
			out["residents"] = res
			out["cap"] = Shelter.cap(town)
			out["used"] = res.size()
			var S: Dictionary = TownEcon.data()["shelter"]
			out["upkeep"] = float(e.get("stats", {}).get("shelter_cost", 0.0))
			var bed := float(S.get("bed_price", 0.0))
			var meal := float(S.get("meal_price", 0.0))
			var gruel := bool(e.get("gruel", e.get("gruel_open", false)))
			var terms := []
			terms.append("a bed %s" % ("%d coins a night" % int(bed) if bed > 0.0 else "free (the treasury pays)"))
			terms.append(("meals %d coins" % int(meal)) if meal > 0.0 else "broth from the granary")
			terms.append("free gruel today" if gruel else "the gruel kitchen closed")
			out["now"] = "Beds %d / %d; %d on broth; %s." % [res.size(), int(out["cap"]), int(e.get("broth_n", 0)), ", ".join(PackedStringArray(terms))]
		"jail":
			var mil2 := _militia(game, town)
			out["runner"] = mil2["captain"] if not (mil2["captain"] as Dictionary).is_empty() else head_ref
			out["cap"] = 2 + int(town.get("size", 0))
			out["now"] = "Empty: nobody is held."
		"academy":   # v0.012: the research house (campaign/academy.gd)
			var ab := Academy.biz_of(e)
			if not ab.is_empty():
				var L: Array = ab.get("lead", [])
				var ln := Academy.lead_name(e, ab)
				if ln != "":
					out["runner"] = {"fid": int(L[0]), "pid": int(L[1]), "name": ln, "role": Academy.lead_title(e)}
				out["staff"] = staff_of_biz(e, int(ab["id"]))
				out["cap"] = int(ab["cap"])
				out["used"] = int(ab["workers"])
				out["upkeep"] = float(ab["workers"]) * float(ab["wage"])
				var S := Academy.state(game.world, String(e.get("faction", town.get("faction", ""))))
				var parts := []
				for kk in S["kh"]:
					parts.append("%s know-how %.1f%%" % [kk, float(S["kh"][kk])])
				out["now"] = "%s: %s; %s." % [Academy.house_name(e), Businesses.state_word(ab), ", ".join(PackedStringArray(parts))]
		"mint":
			out["now"] = "Cold: no coin is cast here yet."
			out["stock"] = "%d bronze bars in the town" % int(e.get("stock", {}).get("bronze_bars", 0))
	var lines := []
	lines.append(String(out["now"]))
	var r: Dictionary = out["runner"]
	lines.append("Run by %s." % (("%s (%s)" % [r["name"], r.get("role", "")]) if not r.is_empty() and String(r.get("role", "")) != "" else (String(r["name"]) if not r.is_empty() else "nobody")))
	if not (out["staff"] as Array).is_empty():
		lines.append("Staff: %s." % _names(out["staff"]))
	if not (out["residents"] as Array).is_empty():
		lines.append("Residents: %s." % _names(out["residents"]))
	if float(out["upkeep"]) > 0.0:
		lines.append("Upkeep: %d coins a day from the treasury." % int(round(float(out["upkeep"]))))
	var taps := []
	if not r.is_empty():
		taps.append({"text": "Runs it: %s" % r["name"], "fid": int(r["fid"])})
	var seen := {}
	for p in (out["staff"] as Array) + (out["residents"] as Array):
		if seen.size() >= 4:
			break
		if not seen.has(int(p["fid"])):
			seen[int(p["fid"])] = true
			taps.append({"text": "%s's household" % p["name"], "fid": int(p["fid"])})
	out["lines"] = lines
	out["taps"] = taps
	out["hist"] = Plots.hist_lines(P, int(bl["p"])) if int(bl["p"]) >= 0 else []
	return out

static func buildings(game, town: Dictionary) -> Array:
	var out := []
	var P := Plots.of(town)
	if P.is_empty():
		return out
	for bi in (P["bld"] as Array).size():
		out.append(building(game, town, bi))
	return out

static func _names(l: Array) -> String:
	var nm := []
	for p in l.slice(0, 8):
		nm.append(String(p["name"]))
	return ", ".join(PackedStringArray(nm)) + ((" and %d more" % (l.size() - 8)) if l.size() > 8 else "")

## A household's people at home (grown-ups and children): [{fid, pid, name}].
static func _household(e: Dictionary, f: Dictionary) -> Array:
	var out := []
	var race := Persons.race_of(e)
	for p in (f.get("pp", []) as Array) + (f.get("kp", []) as Array):
		if String(p[4]) in ["", "hire"]:
			out.append({"fid": int(f["id"]), "pid": int(p[0]), "name": Persons.name_of(f, p, race)})
	return out

## The town militia (a city's guard) as register persons, its captain (the highest rank) and its pay a day.
static func _militia(game, town: Dictionary) -> Dictionary:
	var e: Dictionary = town["econ"]
	var race := Persons.race_of(e)
	var people := []
	var cap := {}
	var best := -1
	var pay := 0.0
	for u in TownDefence.garrison(game, String(town["id"])):
		var fid: int = u.family
		if u.home_town != String(town["id"]) or fid < 0 or fid >= (e["fams"] as Array).size():
			continue
		var f: Dictionary = e["fams"][fid]
		var p := Persons.by_uid(f, u.uid)
		if p.is_empty():
			continue
		var ref := {"fid": fid, "pid": int(p[0]), "name": Persons.name_of(f, p, race), "role": Army.rank_title(u)}
		people.append(ref)
		pay += u.last_pay
		if u.rank > best:
			best = u.rank
			cap = ref
	return {"people": people, "captain": cap, "pay": pay}
