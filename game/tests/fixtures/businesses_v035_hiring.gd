extends RefCounted
## Family-owned businesses (economy spec 1, section 5): rows with workers, a wage, a till (gold), tools, and
## recipes per worker-day from data/economy.json. Smiths spend bars and turn out real gear Items into the
## town's arms stock (town["shop"]); no bars = idle. Every business needs tools (output halves without them).
## Can't pay wages -> workers leave (at their family's turn).
##
## business = {id, type, owner (family id, -1 = the town), workers (hired hands and family staff), cap (places to
##   hire, the keeper not counted), kw (1 = a grown-up of the owning family keeps it and works it: barge part 3
##   section 4 "a family shop counts its keeper"; Families.reassign), wage, till, owed (unpaid wage_claims by
##   household plus preserved owed_unattributed from older saves), unpaid_d (last short payday), tools, tw,
##   state: busy | idle | short of inputs | can't pay wages | short-handed | market full, why (what is missing),
##   carry (part-made units), oc {good: part-made output}, skill (smiths 0-15), smith (name), ore, rich,
##   label (meat variety), spend (input gold per day, smoothed), closed, for_sale, p1 (yesterday's profit)}
##
## v0.014 (Douglas: "just one business doing actual production stuff - farming is a different matter"): a town has
## ONE business per production trade (one per ore for mines: each works its own deposit); more demand means more
## places in that shop, never a second shop. Farms (one per family short of hands) are the exception. The places come
## from the people: fit_to_people trims the trades to the grown-ups the families' own land does not need.

const STATE_WORDS := {"busy": "busy", "idle": "idle", "inputs": "short of inputs", "wages": "can't pay wages",
	"hands": "short-handed", "full": "market full", "nopay": "market can't pay"}

# ================================================================== generation
static func _row(e: Dictionary, type: String, owner: int, cap: int, D: Dictionary) -> Dictionary:
	var T: Dictionary = D["businesses"][type]
	var b := {"id": (e["biz"] as Array).size(), "type": type, "owner": owner, "workers": 0, "cap": maxi(0, cap),
		"wage": float(T["wage"]), "till": 0.0, "owed": 0.0, "tools": maxi(0, cap), "tw": 0.0, "state": "idle", "why": "",
		"carry": 0.0, "oc": {}, "spend": 0.0, "closed": false, "kw": 0, "made": int(e.get("day", 0))}
	if T.has("arms") and String(T["arms"]) != "bow" and not (T["recipes"] as Array).is_empty(): b["arms_carry"] = 0.0
	b["till"] = float(b["wage"]) * float(maxi(1, cap)) * 14.0
	(e["biz"] as Array).append(b)
	if owner >= 0:
		(e["fams"][owner]["owns"] as Array).append(b["id"])
	return b

static func generate(_w: Dictionary, town: Dictionary, e: Dictionary, D: Dictionary, rng: RandomNumberGenerator) -> void:
	e["biz"] = []
	var fams: Array = e["fams"]
	TownEcon.recount(e)
	var pop := float(e["pop"]); var ad := float(e["adults"]); var homes := float(e["homes"])
	var size := int(town["size"])
	var clim: Dictionary = D["climates"][e["climate"]]
	var terr: Dictionary = e["terrain"]
	var specs: Array = e["specialties"]
	var cul: Dictionary = D["cultures"][e["culture"]]
	var owners := _owner_pool(fams, rng)
	var oi := [0]
	var next_owner := func() -> int:
		var o: int = owners[oi[0] % owners.size()]
		oi[0] += 1
		return o
	# v0.014: one shop per trade, sized by the town's demand in hands (fit_to_people then trims it to the people and
	# counts the keeper as one of them). (Before: rows of 5-8 places each, so a town had two or three brewers, smelters
	# or woodcutters, each owned by another family: 50-60 rows with nobody to work them.)
	var add := func(type: String, total_cap: int, _per_row: int = 0) -> Dictionary:
		return _row(e, type, next_owner.call(), maxi(1, total_cap), D)
	var spec_biz := {}
	for s in specs:
		spec_biz[D["specialties"][s]["biz"]] = true
	var sm := func(type: String) -> float:
		return 1.5 if spec_biz.has(type) else 1.0
	# market first (the town's merchants)
	var m: Dictionary = _row(e, "market", next_owner.call(), 2 + size, D)
	m["till"] = pop * 2.2 * 18.0 * TownEcon.COIN   # coins (the old gold float x20)
	e["mkt"] = m["id"]
	# fuel and food beyond the fields
	var wood_day := homes * float(D["needs"]["firewood_home"]) * float(clim["firewood"]) * 1.05 * 1.5 + 6.0
	add.call("woodcutter", maxi(1, int(ceil(wood_day / 13.0 * sm.call("woodcutter")))), 8)
	if terr["forest"] or e["climate"] == "cold":
		add.call("hunter", clampi(2 + int(terr.get("forest_cells", 0)) / 10, 1, 6), 6)
	if terr["water"]:
		add.call("fishery", 2 + size, 6)
	if terr["hills"]:
		add.call("quarry", 1 + size / 2, 5)
	# ore and metal
	var ore_day := 0.0
	var deps: Dictionary = e["deposits"]
	for ore in deps:
		var rich := float(deps[ore])
		var spec_ore := false
		for s in specs:
			if D["specialties"][s].get("ore", "") == ore:
				spec_ore = true
		var mc := int(round((3.0 + 3.0 * rich) * (1.5 if spec_ore else 1.0)))
		var mb: Dictionary = _row(e, "mine", next_owner.call(), mc, D)
		mb["ore"] = ore
		mb["rich"] = rich
		mb["spec"] = spec_ore
		if ore != "flux":   # flux stone goes into the furnace as it is (steel): it needs no smelter of its own
			ore_day += float(mc) * float(D["mine_rate"]) * rich
	if ore_day > 0.0 or size >= 2:
		add.call("smelter", maxi(2, int(ceil(ore_day / 2.0 / 3.0)) + 1), 6)
	# smiths: the town's named smiths (crafters) run the first forge of each kind
	var cr: Dictionary = town.get("crafters", {})
	for kind in ["weaponsmith", "armorsmith"]:
		# v0.014: one forge of each kind; what used to be a second and third forge (a big town, the town's specialty)
		# is more places in the one forge
		var n := 1 + (1 if size >= 3 else 0) + (1 if spec_biz.has(kind) else 0)
		var b: Dictionary = _row(e, kind, next_owner.call(), n * (2 + (1 if size >= 2 else 0)), D)
		var c: Dictionary = cr.get(kind, {})
		b["skill"] = clampi(int(c.get("skill", 4)), 0, 15)
		if not c.is_empty():
			b["smith"] = c.get("name", "")
			fams[int(b["owner"])]["named"] = true
	add.call("carpenter", 2 + size, 6)
	add.call("weaver", maxi(1, int(ceil(pop / 270.0 * sm.call("weaver")))), 6)
	add.call("tailor", maxi(1, int(ceil(pop / 200.0))), 6)
	var hides_day := 0.0
	for a in e["herd"]:
		hides_day += float(e["herd"][a]) * float(D["herds"][a].get("hides", 0.0))
	var leather_homes := float(cul["home"]["materials"].get("leather", 0)) * float(cul["home"]["decay"]) * homes * 0.1 * 10.0
	add.call("tanner", maxi(1, int(ceil((hides_day + 1.0 + leather_homes) / 4.0))), 6)
	add.call("leatherworker", 1 + size / 2, 5)
	var bs := EconGen.beer_share_of(e)
	add.call("brewer", maxi(1, int(ceil(ad * bs * 1.05 / 30.0))), 8)
	add.call("vintner", maxi(1, int(ceil(ad * (1.0 - bs) * 1.05 / 12.0))), 8)
	add.call("builder", 2 + size / 2, 5)
	if size >= 2 or town.get("capital", false):
		add.call("jeweler", 1 + size / 3, 2)   # bars into jewelry for the wealthy families
	# town-owned rows: tax collectors and the town's own fields
	var col: Dictionary = _row(e, "collector", -1, int(ceil(float(fams.size()) / float(D["tax"]["collector_per"]))), D)
	col["till"] = float(col["wage"]) * float(col["cap"]) * 21.0
	var est: Dictionary = _row(e, "estate", -1, 0, D)
	est["till"] = 0.0
	e["estate_biz"] = est["id"]
	var works: Dictionary = _row(e, "works", -1, 0, D)   # the head hires idle hands when the treasury is flush
	works["till"] = 0.0
	e["works_biz"] = works["id"]
	e["fams"][0]["farm"] = est["id"]
	# big landholders hire farmhands
	for f in fams:
		if f.get("estate", false):
			continue
		var need := Families.need_hands(f, e)
		var short := int(ceil(need - float(Families.adults(f)) - 0.3))
		if short > 0:
			var fb: Dictionary = _row(e, "farm", int(f["id"]), short, D)
			f["farm"] = fb["id"]
	# labels: hunters' and fishers' meat variety
	for b in e["biz"]:
		var lab: Array = D["businesses"][b["type"]].get("meat_label", [])
		if not lab.is_empty():
			b["label"] = lab[rng.randi() % lab.size()]

## Families likely to own a business: richer and landless families first, never the estate.
static func _owner_pool(fams: Array, rng: RandomNumberGenerator) -> Array:
	var pool := []
	for f in fams:
		if f.get("estate", false):
			continue
		var wt := 1.0 + float(f["purse"]) / 60.0 + (1.0 if (f["land"] as Dictionary).is_empty() else 0.0)
		pool.append([wt * rng.randf_range(0.5, 1.5), int(f["id"])])
	pool.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for p in pool:
		out.append(p[1])
	return out

## v0.014: an owner pool with the families that own no business yet first (in the pool's order): every shop wants a
## keeper of its own family, so a second shop goes to a family only when every family already has one. (The herds'
## trades and the bowyer used to go to the town's richest families again, who then had no one free to keep them.)
static func free_first(e: Dictionary, pool: Array) -> Array:
	var a := []; var b := []
	for fid in pool:
		var f: Dictionary = e["fams"][int(fid)]
		if (f["owns"] as Array).is_empty() and not f.get("gone", false):
			a.append(fid)
		else:
			b.append(fid)
	return a + b

## The open places of b a hand would sign on for: already earned wages commit their coins before hiring.
## Remaining cash must cover the existing two-day reserve for current and new hands. (Before: any till over two days of ONE wage was open for all its places: a farm with 795 coins
## and 62 places to fill took on hands it could not pay, then read "can't pay wages".)
static func takeable(b: Dictionary) -> int:
	if b.get("closed", false) or float(b["wage"]) <= 0:
		return 0
	var w := maxf(0.01, float(b["wage"]))
	var available := maxf(0.0, float(b["till"]) - maxf(0.0, float(b.get("owed", 0.0))))
	var can := int(floor(available / (2.0 * w))) - int(b["workers"])
	return maxi(0, mini(int(b["cap"]) - int(b["workers"]), can))

## Rows that are not production trades: the town's fields, the families' farms, the market, the town's offices.
const NOT_TRADES := ["farm", "estate", "works", "market", "collector", "mint", "academy"]

## World gen, once every row is made (EconGen.generate, after the herds' trades and the herbalist; Douglas 21:13: "we
## got 50-60 businesses and nobody to work in them"): the trades get the hands the people can give. Each family trade
## was sized by its demand in hands; the keeper (a grown-up of the owning family who works it: Families.reassign) is
## one of them, so its places to hire are that less one. The grown-ups free for the trades are those the families'
## own land and herds do not need (fields hire first: barge part 3 section 1), less the market's and the town's own
## places; when the trades want more hands than that, every trade's hands are cut in the same proportion, never
## below its keeper. The tills are two weeks of the wages of the places left.
static func fit_to_people(e: Dictionary) -> void:
	var free := 0.0
	for f in e["fams"]:
		if f.get("estate", false) or f.get("gone", false):
			continue
		free += maxf(0.0, float(Families.adults(f)) - Families.need_hands(f, e))
	var rows := []
	var want := 0.0
	for b in e["biz"]:
		if b.get("closed", false):
			continue
		if String(b["type"]) in NOT_TRADES or int(b["owner"]) < 0:
			if String(b["type"]) in ["market", "collector", "mint", "academy"] or (int(b["owner"]) < 0 and not String(b["type"]) in NOT_TRADES):
				free -= float(b["cap"])
			continue
		rows.append(b)
		want += float(maxi(1, int(b["cap"])))
	if rows.is_empty():
		return
	free = maxf(float(rows.size()), free)
	var k := minf(1.0, free / maxf(1.0, want))
	for b in rows:
		var hands := maxi(1, int(round(float(maxi(1, int(b["cap"]))) * k)))
		b["cap"] = hands - 1
		b["tools"] = hands
		b["till"] = float(b["wage"]) * float(hands) * 14.0
	e["fit"] = {"free": snappedf(free, 0.1), "want": snappedf(want, 0.1), "k": snappedf(k, 0.001)}

## Current vacancies and funded offers. Family matching refreshes this small index;
## production indexes and market state still follow the existing daily/weekly passes.
static func refresh_hiring(e: Dictionary) -> void:
	var open := []
	for b in e["biz"]:
		if not b.get("closed", false) and int(b["cap"]) > int(b["workers"]) and b["type"] != "farm":
			open.append(b)
	# barge part 3 section 1 (FIX: land unworked): field hands are hired FIRST because the farms and the town's fields pay
	# 1.15 x the day wage; a trade whose goods are scarce may bid more (Businesses.bid_day), and then it comes first.
	# Places by their pay, the fields (the families' farms, then the town's) first at equal pay.
	open.sort_custom(func(a, b): return float(a["wage"]) > float(b["wage"]))
	var fields := []
	for b in e["biz"]:
		if b["type"] == "farm" and not b.get("closed", false) and int(b["cap"]) > int(b["workers"]):
			fields.append(b)
	for b in open:
		if b["type"] == "estate":
			fields.append(b)
	var rest := []
	for b in open:
		if b["type"] != "estate":
			rest.append(b)
	var fw := -1.0
	for b in fields:
		fw = maxf(fw, float(b["wage"]))
	var ids := []
	for b in rest:
		if float(b["wage"]) > fw:
			ids.append(int(b["id"]))
	for b in fields:
		ids.append(int(b["id"]))
	for b in rest:
		if float(b["wage"]) <= fw:
			ids.append(int(b["id"]))
	e["open"] = ids
	var open_n := 0
	var top := 0.0
	for bid in ids:
		var b: Dictionary = e["biz"][int(bid)]
		open_n += int(b["cap"]) - int(b["workers"])
		if takeable(b) > 0:
			top = maxf(top, float(b["wage"]))
	e["open_n"] = open_n
	e["open_top"] = top   # the best pay an open place whose till can pay it offers (a worse-paid hand looks again)

static func rebuild_open(e: Dictionary) -> void:
	refresh_hiring(e)
	# the rows the daily pass runs (everything that makes something)
	var prod := []
	for b in e["biz"]:
		if not b.get("closed", false) and not b["type"] in ["market", "collector", "estate", "farm", "works"]:
			prod.append(int(b["id"]))
	e["prod"] = prod
	# makers of each good (barge: makers aim at demand split among all makers)
	var BT: Dictionary = TownEcon.data()["businesses"]
	var makers := {}
	for bid in prod:
		var b: Dictionary = e["biz"][int(bid)]
		var seen := {}
		for r in BT[b["type"]]["recipes"]:
			for og in r["out"]:
				if not seen.has(og):
					seen[og] = true
					makers[og] = int(makers.get(og, 0)) + 1
	e["makers"] = makers
	prep_day(e)
	service_states(e)

static func title(e: Dictionary, b: Dictionary) -> String:
	var T: Dictionary = TownEcon.data()["businesses"][b["type"]]
	var owner := int(b["owner"])
	if b["type"] == "academy":
		return Academy.the_name(e)   # the research house: its culture's own name (the Academy, the Blood Forge ...)
	if owner < 0:
		return T["name"] if b["type"] in ["collector", "estate"] else "the town's %s" % T["name"]
	if b.has("smith") and String(b["smith"]) != "":
		# (v0.014: a weapon forge and an armour forge may have smiths of one name)
		return "%s's %s" % [b["smith"], {"weaponsmith": "weapon forge", "armorsmith": "armour forge"}.get(String(b["type"]), T["name"])]
	var who := String(_who(e).get(str(owner), "the %s family's" % String(e["fams"][owner]["name"])))
	if b["type"] == "mine":
		return "%s %s mine" % [who, String(b.get("ore", "copper_ore")).split("_")[0]]
	if b["type"] == "farm":
		return "%s %s" % [who, CropRotation.farm_name(e, e["fams"][owner])]
	return "%s %s" % [who, T["name"]]

## v0.014: how a family's businesses are named, {family id: "Aldric Blackmere's"}: by the head of the family, since a
## town of 100-150 families shares a culture's 20-odd surnames ("the Blackmere farm" named two or three farms of
## different Blackmere families). Families with heads of one name are told apart: the elder and the younger (by the
## head's birth), a third and more by number; a family with nobody at home: "the Blackmere family's". Worked out once
## a day per town (e._who).
static func _who(e: Dictionary) -> Dictionary:
	var day := int(e.get("day", 0))
	var fams: Array = e["fams"]
	var c: Dictionary = e.get("_who", {})
	var withp := 0   # (world gen names the register after the rows are made)
	for f in fams:
		if f.has("pp"):
			withp += 1
	if int(c.get("d", -1)) == day and int(c.get("n", -1)) == fams.size() and int(c.get("p", -1)) == withp:
		return c["m"]
	var race := Persons.race_of(e)
	var groups := {}
	for f in fams:
		if f.get("estate", false):
			continue
		var hp := Persons.head_of(f) if f.has("pp") else []
		var base := (Persons.name_of(f, hp, race) if not hp.is_empty() else "the %s family" % String(f["name"]))
		if not groups.has(base):
			groups[base] = []
		(groups[base] as Array).append([float(hp[3]) if not hp.is_empty() else 1.0e12, int(f["id"])])
	var m := {}
	for base in groups:
		var g: Array = groups[base]
		if g.size() == 1:
			m[str(int(g[0][1]))] = String(base) + "'s"   # (string keys: the cache rides in the save)
			continue
		g.sort_custom(func(a, b2): return float(a[0]) < float(b2[0]) if float(a[0]) != float(b2[0]) else int(a[1]) < int(b2[1]))
		for i in g.size():
			var tag: String = (["the elder", "the younger"][i] if g.size() == 2 else "of household %d" % (int(g[i][1]) + 1))
			m[str(int(g[i][1]))] = "%s %s's" % [base, tag]
	e["_who"] = {"d": day, "n": fams.size(), "p": withp, "m": m}
	return m

## Usable know-how in a material: the faction's (e.fkh: steel, iron, bronze, mirrored from Academy each faction turn);
## for a material its smiths also practise town by town (data knowhow: bronze) the town's own practice under it, so a
## realm that may not know bronze (orcs, goblins) never smelts or works it whatever its towns have heard (v0.014).
static func kh_of(e: Dictionary, key: String) -> float:
	var fk: Dictionary = e.get("fkh", {})
	var practised: bool = TownEcon.data()["knowhow"].has(key)
	if fk.has(key):
		if practised:
			return minf(float(fk[key]), float(e["knowhow"].get(key, 0.0)))
		return float(fk[key])
	if not practised:
		return 100.0 if key == "iron" else 0.0   # (a town with no faction mirror yet: iron as before v0.014)
	return float(e["knowhow"].get(key, 0.0))

static func state_word(b: Dictionary) -> String:
	return STATE_WORDS.get(b.get("state", "idle"), String(b.get("state", "idle")))

# ================================================================== daily production
static func daily(game, town: Dictionary, e: Dictionary, D: Dictionary, si: int, rng: RandomNumberGenerator) -> void:
	var biz: Array = e["biz"]
	var n := biz.size()
	if n == 0:
		return
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var mkt: Dictionary = biz[int(e["mkt"])]
	var share := float(D["market"]["buy_share"])
	var bdem := {}
	var aimr: Dictionary = e.get("_aimrest", {})
	var specs := {}
	for s in e["specialties"]:
		specs[D["specialties"][s]["biz"]] = true
	if not e.has("prod"):
		rebuild_open(e)
	var prod: Array = e["prod"]
	var np := prod.size()
	if np == 0:
		return
	var start := int(e.get("day", 0)) % np
	var BT: Dictionary = D["businesses"]
	var gear_n := {}
	var tool_days := float(D["needs"]["wear_days"]["tools"])
	for j in np:
		var b: Dictionary = biz[int(prod[(start + j) % np])]
		if b["closed"]:
			continue
		var type: String = b["type"]
		if BT[type].has("arms") and String(BT[type]["arms"]) != "bow": _gear_carry_key(b, BT[type])
		var receipt_before := float(b["till"])
		var hired := maxi(0, int(b["workers"]) - int(b.get("sick", 0)))   # sickness: bed-ridden staff stay home (short-handed)
		# WageClaims closes all actual household jobs at the queued town day.
		# The keeper contributes work and takes profit, never employee wages.
		# v0.014: the keeper works his shop (barge part 3 section 4); he draws the keeper's take, not a wage
		var w := hired + int(b.get("kw", 0))
		if w <= 0:
			b["state"] = "hands" if int(b["cap"]) > 0 else "idle"
			continue
		# v0.014: weaponsmiths and armourers keep wanting their bars (data smith_bars) every working day, resting or not:
		# their stockpile target stands in the market, so the bars' price and the caravans follow it
		if type == "weaponsmith" or type == "armorsmith":
			smith_want(e, float(w), bdem)
		# a business that found the market full yesterday rests until its goods sell down (cheap check)
		if b["state"] in ["full", "wages"] and b.has("fg"):
			var fg: String = b["fg"]
			if fg == "arms":
				if (town["shop"] as Array).size() >= arms_cap(town) and not (type == "weaponsmith" and BowsEcon.tips_wanted(e)) \
						and not ArmsTrade.has_orders(e, String(BT[type].get("arms", ""))):   # v0.014: the armory's orders
					_finish_production_day(b, receipt_before, w, hired, 0.0)
					continue
			elif float(st.get(fg, 0)) >= stock_cap(e, fg) * 0.9 or aimr.has(fg):
				EconomyRules.clear_surplus(e, fg)
		# tools wear and replacement
		var tw := float(b["tw"]) + float(w) / tool_days
		if tw >= 1.0 and int(b["tools"]) > 0:
			b["tools"] = int(b["tools"]) - 1
			tw -= 1.0   # (tools left the goods ledger when bought; wear only empties the rack)
		b["tw"] = minf(tw, 2.0)
		if int(b["tools"]) < w and int(st.get("tools", 0)) > 0 and float(b["till"]) > float(price["tools"]) * 2.0:
			st["tools"] = int(st["tools"]) - 1
			b["tools"] = int(b["tools"]) + 1
			TownEcon.led(e, "used", "tools", 1)
			var tc := float(price["tools"])
			b["till"] = float(b["till"]) - tc
			mkt["till"] = float(mkt["till"]) + tc
			e["stats"]["sales"] = float(e["stats"]["sales"]) + tc
			bdem["tools"] = float(bdem.get("tools", 0.0)) + 1.0
		var toolf := 0.5 + 0.5 * minf(1.0, float(b["tools"]) / float(w))
		var spec := 2.0 if specs.has(type) else 1.0
		var T: Dictionary = BT[type]
		b["state"] = "busy"
		b["why"] = ""
		var spent := 0.0
		if T.has("arms"):
			var frac := 1.0
			if T["arms"] == "weapon" or T["arms"] == "bow":   # bows: smiths' arrowheads, bowyers' staves (campaign/bows_econ.gd)
				frac = BowsEcon.arms_share(town, e, T["arms"])
			elif not (T["recipes"] as Array).is_empty():
				if gear_n.is_empty():
					gear_n = _gear_counts(town)
				frac = 0.3 if int(gear_n[T["arms"]]) < 4 + int(town.get("size", 0)) else 0.0   # tailors/leatherworkers make gear part-time
			if frac > 0.0:
				spent += _arms(game, town, e, D, b, T, float(w) * frac, toolf, spec, rng, mkt, bdem)
			if frac < 1.0:
				spent += _recipes(e, D, b, T, float(w) * (1.0 - frac), toolf, spec, mkt, share, bdem)
		elif type == "mine":
			_mine(e, D, b, float(w), toolf, spec, mkt, share, rng)
		elif type == "butcher":
			spent += Herds.butcher_day(e, b, float(w), toolf, mkt, share, bdem)   # herds: beasts bought from their owners
		elif type == "academy":
			spent += Academy.day(game, town, e, b, float(w), mkt, bdem)   # v0.012: the research house's trials and research
		else:
			spent += _recipes(e, D, b, T, float(w), toolf, spec, mkt, share, bdem)
		TownSanitation.add_waste(e, float(w) * float(TownSanitation.D()["trade_waste_per_hand"].get(type, 0)) if b["state"] in ["busy", "hands"] else 0, "trade")
		_finish_production_day(b, receipt_before, w, hired, spent)
	# business input wants (per day) feed tomorrow's prices
	e["bdem"] = bdem

## Every staffed day, including a full-market rest, ages realised net receipts.
## Bookkeeping does not inject money or treat owner funding as sales.
static func _finish_production_day(b: Dictionary, before: float, working: int, hired: int, spent: float) -> void:
	EconomyRules.record_receipts(b, before, working)
	b["spend"] = float(b["spend"]) * 0.9 + spent * 0.1
	if b["state"] == "busy" and hired < int(int(b["cap"]) * 0.6): b["state"] = "hands"
	if hired > 0 and float(b["till"]) < float(b["owed"]) and float(b["owed"]) > float(b["wage"]) * float(hired) * 3.0:
		b["state"] = "wages"

## Every non-home recipe of the data with its goods as flat lists (once): recipe["_bc"] = [first output, its units,
## [outputs, units...], [inputs, units...], id]. The ids index the day's margin flags.
static var _all_recipes: Array = []
static func _recipe_index() -> Array:
	if not _all_recipes.is_empty():
		return _all_recipes
	var BT: Dictionary = TownEcon.data()["businesses"]
	for bt in BT:
		if String(bt).begins_with("_"):
			continue
		for r in BT[bt]["recipes"]:
			if r.get("home", false):
				continue
			var outs := []; var inl := []
			for og in r["out"]:
				outs.append(og); outs.append(float(r["out"][og]))
			for ig in r["in"]:
				inl.append(ig); inl.append(float(r["in"][ig]))
			r["_bc"] = [outs[0], outs[1], outs, inl, _all_recipes.size()]
			_all_recipes.append(r)
	return _all_recipes

## Barge part 3 section 4, once a day per town (the barge day, after the prices): which recipes do not pay (output
## at 0.92 x price under 1.03 x the inputs at price: they run at most 20% of capacity), and each maker's aim for a
## good: (today's demand + a tenth of the gap to the normal stock) / the makers of it, units a day.
static func prep_day(e: Dictionary) -> void:
	_recipe_index()
	if _bb_out < 0.0:
		var BB: Dictionary = Barge.B()["business"]
		_bb_out = float(BB["out_share"]); _bb_margin = float(BB["run_margin"]); _bb_idle = float(BB["idle_cap"]); _bb_gap = float(BB["aim_gap"])
	var price: Dictionary = e.get("price", {})
	var nm := []
	nm.resize(_all_recipes.size())
	nm.fill(false)
	for r in _all_recipes:
		var rc: Array = r["_bc"]
		var inl: Array = rc[3]
		if inl.is_empty():
			continue
		var ov := 0.0; var iv := 0.0
		var outs: Array = rc[2]
		for k in range(0, outs.size(), 2):
			ov += float(outs[k + 1]) * float(price.get(outs[k], 0.0))
		for k in range(0, inl.size(), 2):
			iv += float(inl[k + 1]) * float(price.get(inl[k], 0.0))
		if ov * _bb_out < _bb_margin * iv:
			nm[int(rc[4])] = true   # (a list by recipe id: survives the save as it is)
	e["_nomargin"] = nm
	var aimu := {}
	var rest := {}   # goods the market keeps a normal stock of and holds more than enough: their makers rest
	var mk: Dictionary = e.get("makers", {})
	var dem: Dictionary = e.get("dem", {}); var need: Dictionary = e.get("need", {}); var st: Dictionary = e.get("stock", {})
	for og in mk:
		var aim := float(dem.get(og, 0.0)) + _bb_gap * (float(need.get(og, 0.0)) - float(st.get(og, 0)))
		aimu[og] = maxf(0.0, aim) / maxf(1.0, float(mk[og]))
		if aim <= 0.0 and float(need.get(og, 0.0)) > 0.0:
			rest[og] = true
	e["_aimu"] = aimu
	e["_aimrest"] = rest

## Barge part 3 section 6, the business's books (yesterday's day, read at the start of today's): profit = the till's
## change less the day's wages owed; upkeep of the building (4 + 1.5 x staff a day, to the market: repairs); loss day
## +1 when profit < -0.3 x staff x wage or the 14-day average < -0.25 x wage, else -1; STRUGGLING above 12 loss days,
## THRIVING when the 14-day average > 0.4 x staff x wage, else STEADY.
## The day's books of every business that makes something (the town's barge day, after its market day).
static func books_day(e: Dictionary) -> void:
	if not e.has("prod"):
		return
	var biz: Array = e["biz"]
	var mkt: Dictionary = biz[int(e["mkt"])]
	var BB: Dictionary = Barge.B()["business"]
	var u0 := float(BB["upkeep"][0]); var u1 := float(BB["upkeep"][1])
	var lds := int(BB["struggling"]); var thr := float(BB["thriving"])
	for bid in e["prod"]:
		var b: Dictionary = biz[int(bid)]
		if not b["closed"]:
			_books(b, int(b["workers"]), mkt, u0, u1, lds, thr)

static func _books(b: Dictionary, w: int, mkt: Dictionary, u0: float, u1: float, lds: int, thr: float) -> void:
	var up := u0 + u1 * float(w)
	var pay := minf(up, maxf(0.0, float(b["till"])))
	b["till"] = float(b["till"]) - pay
	mkt["till"] = float(mkt["till"]) + pay
	var tl := float(b["till"])
	if b.has("t_prev"):
		var wage := float(b["wage"])
		var earned := float(b.get("wage_cost_day", float(w) * wage))
		var profit := tl - float(b["t_prev"]) - earned + float(b.get("t_paid", 0.0))
		var a14 := float(b.get("p14", 0.0))
		a14 += (profit - a14) / 14.0
		b["p14"] = a14
		var ld := int(b.get("ld", 0))
		# barge part 3 section 4: "a family shop counts its keeper" as staff. (v0.011: without him a shop with nobody
		# hired lost a day for its upkeep alone, every day, and its places fell to one: Grolruk's tanner and woodcutter.)
		# (v0.014: the keeper counts when he is really there and working: b.kw)
		var staff := float(w + int(b.get("kw", 0)))
		b["p1"] = profit   # yesterday's profit: barge part 3 section 5 hires when it "made over a day's wage yesterday"
		if profit < -0.3 * staff * wage or a14 < -0.25 * wage:
			ld += 1
		else:
			ld = maxi(0, ld - 1)
		b["ld"] = ld
		b["health"] = "struggling" if ld > lds else ("thriving" if a14 > thr * maxf(staff, 1.0) * wage else "steady")
	b["t_prev"] = tl
	b["t_paid"] = 0.0

## [what a hand makes a day at today's prices, the dearest of its goods over base]. Value per hand is barge part 3
## section 4: (outputs at 0.92 x price - inputs at price) x batches / hands, for the best recipe it can run (know-how).
## The batches are what it would really make: the recipe's rate a hand, but no more than its share of what the makers
## aim at (today's demand + a tenth of the gap to normal stock, split among the makers: prep_day) and of the inputs in
## the market, shared among its hands and the one it would take on (below its places). A mine: its ore at 0.92 x price
## x the mine rate while the market takes ore. The dearest good is how scarce its output is (section 5).
static func hand_value(e: Dictionary, b: Dictionary) -> Array:
	var D := TownEcon.data()
	var T: Dictionary = D["businesses"][b["type"]]
	var price: Dictionary = e.get("price", {})
	var st: Dictionary = e.get("stock", {})
	var G: Dictionary = D["goods"]
	if _bb_out < 0.0:
		var BB: Dictionary = Barge.B()["business"]
		_bb_out = float(BB["out_share"]); _bb_margin = float(BB["run_margin"]); _bb_idle = float(BB["idle_cap"]); _bb_gap = float(BB["aim_gap"])
	var kw := int(b.get("kw", 0))   # (the keeper is one of the hands sharing the aim and the inputs)
	var n := float(int(b["workers"]) + kw + 1) if int(b["workers"]) < int(b["cap"]) else float(maxi(1, int(b["workers"]) + kw))
	if b["type"] == "mine":
		var ore: String = b.get("ore", "copper_ore")
		var p := float(price.get(ore, 0.0))
		var full := float(st.get(ore, 0)) >= stock_cap(e, ore) * 2.0
		return [0.0 if full else _bb_out * p * float(D["mine_rate"]) * float(b.get("rich", 1.0)), p / float(G[ore]["price"])]
	var best := 0.0
	var dear := 0.0
	var mats: Dictionary = D["cultures"][e["culture"]]["home"]["materials"]
	var aimu: Dictionary = e.get("_aimu", {})
	var aimr: Dictionary = e.get("_aimrest", {})
	for r in T["recipes"]:
		if r.has("knowhow") and kh_of(e, String(r["knowhow"])) <= 0.0:
			continue
		var v := 0.0
		var units := float(r.get("rate", 1.0))
		var dr := 0.0
		for og in r["out"]:
			v += float(r["out"][og]) * float(price.get(og, 0.0)) * _bb_out
			dr = maxf(dr, float(price.get(og, 0.0)) / float(G[og]["price"]))
		var og0: String = (r["out"] as Dictionary).keys()[0]
		if aimr.has(og0):
			units = 0.0
		elif aimu.has(og0):
			units = minf(units, float(aimu[og0]) / maxf(0.001, float(r["out"][og0])) / n)
		var ins: Dictionary = mats if r.get("home", false) else r["in"]
		for ig in ins:
			v -= float(ins[ig]) * float(price.get(ig, 0.0))
			units = minf(units, float(st.get(ig, 0)) / maxf(0.001, float(ins[ig])) / n)
		if units > 0.0:
			dear = maxf(dear, dr)   # (scarce goods it cannot make for want of inputs do not count)
		best = maxf(best, v * units)
	return [best, dear]

## Daily (the barge day, after the prices): what a family business pays its hands. Barge part 3: the pay table x
## PL^0.8 (section 2). A business whose goods are scarce (the dearest over 1.25 x base: section 5's "output is scarce")
## and that is short of hands bids for them: its pay rises 10% a day (the cottage trades' pace, section 5) until it
## hires, never over 0.95 x what a hand makes there (hand_value: the cottage trades' members share 95% of the net).
## With its places filled it holds that pay while its goods stay scarce (never over what a hand makes); when they are
## scarce no more its pay moves back toward the table 10% a day. (v0.011: pay stood at the table while wood sold at
## 7 x base and copper bars at 3-5 x, so nobody left the land or the fields for a woodcutter or a smelter.) Field
## hands, builders and public works follow the day wage (labour_day); town rows (the mint, collectors) keep the table.
static func bid_day(e: Dictionary) -> void:
	if not e.has("prod"):
		return
	var BT: Dictionary = TownEcon.data()["businesses"]
	var BB: Dictionary = Barge.B()["business"]
	var scarce := float(BB.get("scarce", 1.25)); var share := float(BB.get("bid_share", 0.95)); var step := float(BB.get("bid_step", 0.1))
	var m := Barge.wage_mult(e)
	var biz: Array = e["biz"]
	for bid in e["prod"]:
		var b: Dictionary = biz[int(bid)]
		if b["closed"]:
			continue
		var T: Dictionary = BT[b["type"]]
		if T.get("day", false) or T.get("field", false):
			continue
		var base := float(T["wage"]) * m
		var w := maxf(base, float(b["wage"]))
		var hv := hand_value(e, b)
		if float(hv[1]) > scarce:
			var most := maxf(base, share * float(hv[0]))
			if int(b["workers"]) < int(b["cap"]):
				# v0.014: it bids up only with the cash to pay the new pay (barge part 3 section 5: "its output is scarce
				# and it has cash"): a till that cannot pay two days of it holds its pay. (Before: shops with empty tills
				# bid to 5-25 x the table - a chandler offering 2,271 a day - that nobody would sign on for.)
				var up_w := minf(w * (1.0 + step), most)
				if float(b["till"]) >= up_w * 2.0:
					w = up_w
			else:
				w = minf(w, most)
		else:
			w += (base - w) * step
		b["wage"] = EconomyRules.wage_limit(e, b, maxf(base, w))

## Barge part 3 section 5 (the cottage trades): a trade whose goods are scarce (over 1.25 x base) and where one more
## hand would earn at least the pay table gains a place (weekly here, the owner's turn). (v0.011: a full business grew
## only while "thriving", and a business that pays its hands what they make never thrives.)
static func _gains_hand(e: Dictionary, b: Dictionary) -> bool:
	var BB: Dictionary = Barge.B()["business"]
	var T: Dictionary = TownEcon.data()["businesses"][b["type"]]
	var c0 := int(b["cap"])
	b["cap"] = c0 + 1   # (the hand it would take on: its share of the aim and the inputs)
	var hv := hand_value(e, b)
	b["cap"] = c0
	return float(hv[1]) > float(BB.get("scarce", 1.25)) and float(BB.get("bid_share", 0.95)) * float(hv[0]) >= float(T["wage"]) * Barge.wage_mult(e)

## A family business that would hire (barge part 3 section 5: below its places, and thriving, or it made over a day's
## wage yesterday (v0.014: this clause was missing), or its goods scarce).
static func hiring(e: Dictionary, b: Dictionary) -> bool:
	if float(b.get("wage", 0)) <= 0: return false
	if b["closed"] or int(b["workers"]) >= int(b["cap"]):
		return false
	if String(b.get("health", "")) == "thriving" or float(b.get("p1", 0.0)) > float(b["wage"]):
		return true
	return float(hand_value(e, b)[1]) > float(Barge.B()["business"].get("scarce", 1.25))

## Stock cap: producers stop when the market already holds this much (stock_cap_mult x the need it prices on).
static var _cap_mult := -1.0
static func stock_cap(e: Dictionary, g: String) -> float:
	if _cap_mult < 0.0:
		_cap_mult = float(TownEcon.data()["market"]["stock_cap_mult"])
	return maxf(20.0, float(e["need"].get(g, 0.0)) * _cap_mult)

## Weekly state tags of the rows that make nothing (market, collectors, town fields, hired farmhands).
static func service_states(e: Dictionary) -> void:
	for b in e["biz"]:
		if b["closed"] or not b["type"] in ["market", "collector", "estate", "farm", "works"]:
			continue
		var w := int(b["workers"])
		b["state"] = "hands" if w < int(b["cap"]) else ("busy" if w > 0 else "idle")
		# can't pay wages: a hand of it was paid short this past week (b.unpaid_d: Families.turn). (Before v0.014: the
		# till under one day's bill at the moment of this check, which runs at odd times; a farm with 677 coins and a
		# day's bill of 656 read "can't pay wages" from a check made before its keeper topped it up.)
		if w > 0 and float(e.get("day", 0)) - float(b.get("unpaid_d", -100.0)) < 7.0:
			b["state"] = "wages"

static var _bb_out := -1.0
static var _bb_margin := 1.03
static var _bb_idle := 0.2
static var _bb_gap := 0.1

static func _recipe_inputs(e: Dictionary, D: Dictionary, r: Dictionary) -> Dictionary:
	return D["cultures"][e["culture"]]["home"]["materials"] if r.get("home", false) else r["in"]

## The same selected recipe is used for production and its owner's cash quote.
## A quote does not clear prices, set state, or add demand to the live economy.
static func _recipe_choice(e: Dictionary, D: Dictionary, b: Dictionary, T: Dictionary, wd: float, bdem: Dictionary, producing: bool) -> Dictionary:
	var recs: Array = T["recipes"]
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var G: Dictionary = D["goods"]
	var aimr: Dictionary = e.get("_aimrest", {})
	# the most wanted feasible recipe (price over base of its output)
	var best: Dictionary = {}
	var bw := -1.0
	var missing := ""
	var full := false
	for r in recs:
		var ins := _recipe_inputs(e, D, r)
		if r.has("knowhow") and kh_of(e, String(r["knowhow"])) <= 0.0:
			continue
		var ok := true
		for ig in ins:
			if float(st.get(ig, 0)) < float(ins[ig]):
				ok = false
				missing = ig
				bdem[ig] = float(bdem.get(ig, 0.0)) + float(ins[ig]) * wd * float(r.get("rate", 1.0)) * 0.5
				break
		if not ok:
			continue
		var want := 0.0
		var all_full := true
		for og in r["out"]:
			var cap := 2.0 if og == "home" else stock_cap(e, og)
			# (barge part 3 section 4: a maker whose aim for the good is nothing - the market holds more than today's
			# demand and the gap to normal stock - makes none of it; it rests like a full market)
			if float(st.get(og, 0)) < cap and not aimr.has(og):
				all_full = false
			want = maxf(want, float(price[og]) / float(G[og]["price"]))
		if all_full:
			if producing:
				for og in r["out"]: EconomyRules.clear_surplus(e, og)
				b["fg"] = (r["out"] as Dictionary).keys()[0]
			full = true
			continue
		if want > bw:
			bw = want; best = r
	return {"best": best, "full": full, "missing": missing}

static func _recipe_units(e: Dictionary, D: Dictionary, b: Dictionary, best: Dictionary, wd: float, toolf: float, spec: float) -> float:
	var ins2 := _recipe_inputs(e, D, best)
	var khf := 1.0
	var kh_key: String = best.get("knowhow", "")
	if kh_key != "" and D["knowhow"].has(kh_key):   # (a faction's know-how alone - steel, iron - gates, not output)
		khf = maxf(float(D["knowhow"][kh_key]["min_out"]), kh_of(e, kh_key) / 100.0)
	var units := wd * float(best.get("rate", 1.0)) * toolf * spec * khf
	if b["type"] == "woodcutter":
		units = minf(units, EconomyRules.wood_available(e) / maxf(0.01, float(best["out"].get("wood", 1))))
		if units <= 0:
			b["state"] = "inputs"; b["why"] = "standing woods"
	# barge part 3 section 4: output valued at 0.92 x price, inputs at price; a recipe runs fully only if output >= 1.03
	# x inputs, else at most 20% of capacity. Makers aim at today's demand + a tenth of the gap to normal stock, split
	# among all makers of the good.
	if _bb_out < 0.0:
		var BB: Dictionary = Barge.B()["business"]
		_bb_out = float(BB["out_share"]); _bb_margin = float(BB["run_margin"]); _bb_idle = float(BB["idle_cap"]); _bb_gap = float(BB["aim_gap"])
	# (the margins and each maker's aim are worked out once a day for the town, after the day's prices: prep_day)
	var rc: Array = best.get("_bc", [])
	if not rc.is_empty():
		var nmf: Array = e.get("_nomargin", [])
		if not ins2.is_empty() and int(rc[4]) < nmf.size() and bool(nmf[int(rc[4])]):
			units *= _bb_idle
			b["why"] = "no margin"
		if e.has("_aimu"):
			units = minf(units, float(e["_aimu"].get(rc[0], INF)) / maxf(0.001, float(rc[1])) + 0.25)
	return units

static func _recipe_scale(e: Dictionary, b: Dictionary, best: Dictionary, ins2: Dictionary, units: float, mkt: Dictionary, share: float, bdem: Dictionary) -> float:
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var scale := 1.0
	var in_cost := 0.0
	for ig in ins2:
		var need := units * float(ins2[ig])
		bdem[ig] = float(bdem.get(ig, 0.0)) + need
		scale = minf(scale, float(st.get(ig, 0)) / need)
		in_cost += need * float(price[ig])
	if in_cost > 0.0 and float(b["till"]) < in_cost * scale:
		scale = maxf(0.0, float(b["till"])) / in_cost
		if scale < 0.05:
			b["state"] = "wages"
			b["why"] = "money for materials"
	var out_val := 0.0
	for og in best["out"]:
		out_val += units * float(best["out"][og]) * float(price[og]) * share
	if out_val > 0.0 and float(mkt["till"]) < out_val * scale:
		scale = maxf(0.0, float(mkt["till"])) / out_val
		b["state"] = "nopay"
	return scale

static func _batch_cost(e: Dictionary, ins: Dictionary) -> float:
	var cost := 0.0
	for g in ins: cost += int(ins[g]) * float(e["price"][g])
	return cost

static func _batch_quote(e: Dictionary, recipe: Dictionary, share: float) -> float:
	var quote := 0.0
	for g in recipe["out"]: quote += float(recipe["out"][g]) * float(e["price"][g]) * share
	return quote

## Carry is work, never unpaid materials or a market advance. Used by both
## the actual purchase and the owner's read-only one-complete-batch quote.
static func _recipe_batch_limit(e: Dictionary, b: Dictionary, best: Dictionary, ins: Dictionary, whole: int, mkt: Dictionary, share: float) -> int:
	for ig in ins:
		var available := int(e["stock"].get(ig, 0)) / maxi(1, int(ins[ig]))
		if available < whole:
			whole = available; b["state"] = "inputs"; b["why"] = ig
	var cost := _batch_cost(e, ins)
	if cost > 0.0:
		var affordable := int(maxf(0.0, float(b["till"])) / cost)
		if affordable < whole:
			whole = affordable; b["state"] = "wages"; b["why"] = "money for materials"
	var quote := _batch_quote(e, best, share)
	# Input payments enter the market before it buys the completed output.
	if quote > cost:
		var market_batches := int(maxf(0.0, float(mkt["till"])) / (quote - cost))
		if market_batches < whole:
			whole = market_batches; b["state"] = "nopay"
	return whole

static func _recipes(e: Dictionary, D: Dictionary, b: Dictionary, T: Dictionary, wd: float, toolf: float, spec: float,
		mkt: Dictionary, share: float, bdem: Dictionary) -> float:
	if (T["recipes"] as Array).is_empty() or wd <= 0.0: return 0.0
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var choice := _recipe_choice(e, D, b, T, wd, bdem, true)
	var best: Dictionary = choice["best"]
	if best.is_empty():
		if bool(choice["full"]): b["state"] = "full"
		else: b["state"] = "inputs"; b["why"] = choice["missing"]
		b["carry"] = 0.0
		return 0.0
	var ins2 := _recipe_inputs(e, D, best)
	var kh_key: String = best.get("knowhow", "")
	var units := _recipe_units(e, D, b, best, wd, toolf, spec)
	var scale := _recipe_scale(e, b, best, ins2, units, mkt, share, bdem)
	var u := units * scale + float(b["carry"])
	var whole := 0 if ins2.is_empty() else _recipe_batch_limit(e, b, best, ins2, int(floor(u)), mkt, share)
	b["carry"] = minf(1.0, u - whole) if not ins2.is_empty() else 0.0
	var spent := 0.0
	var made := units * scale
	for ig in ins2:
		var q := whole * int(ins2[ig])
		if q <= 0:
			continue
		q = mini(q, int(st[ig]))
		st[ig] = int(st[ig]) - q
		TownEcon.led(e, "used", ig, q)
		var c := float(q) * float(price[ig])
		spent += c
	b["till"] = float(b["till"]) - spent
	mkt["till"] = float(mkt["till"]) + spent
	e["stats"]["sales"] = float(e["stats"]["sales"]) + spent
	var oc: Dictionary = b["oc"]
	var got := 0.0
	for og in best["out"]:
		var amt := (float(whole) if not ins2.is_empty() else made) * float(best["out"][og]) + float(oc.get(og, 0.0))
		var nn := int(floor(amt))
		oc[og] = amt - nn
		if nn <= 0:
			continue
		st[og] = int(st.get(og, 0)) + nn
		TownEcon.led(e, "made", og, nn)
		got += float(nn) * float(price[og]) * share
	got = minf(got, maxf(0.0, float(mkt["till"])))
	mkt["till"] = float(mkt["till"]) - got
	b["till"] = float(b["till"]) + got
	mkt["spend"] = float(mkt["spend"]) + got
	if kh_key != "" and made > 0.0:
		TownEcon.knowhow_gain(e, kh_key, wd * scale)
	return spent

## A target for actual operating cash, separate from accrued/future wages.
## No output, input, person, payment or price is changed by this quote. The
## owner may cover only part of this target under the existing half-purse cap;
## actual production and hiring still require their own real cash checks.
static func operating_cash(e: Dictionary, b: Dictionary, reserved: float) -> float:
	# Payroll-only callers/older incomplete books have no verifiable recipe quote.
	for key in ["stock", "price", "culture", "biz"]:
		if not e.has(key): return 0.0
	var D := TownEcon.data()
	var T: Dictionary = D["businesses"][b["type"]]
	if T.has("arms") or (T["recipes"] as Array).is_empty(): return 0.0
	var hired := maxi(0, int(b["workers"]) - int(b.get("sick", 0)))
	var working := hired + int(b.get("kw", 0))
	if working <= 0: return 0.0
	var quoted := b.duplicate()
	var choice := _recipe_choice(e, D, quoted, T, float(working), {}, false)
	var best: Dictionary = choice["best"]
	if best.is_empty(): return 0.0
	var first_good: String = (best["out"] as Dictionary).keys()[0]
	if float(e.get("_aimu", {}).get(first_good, 0.0)) <= 0.0: return 0.0
	var ins := _recipe_inputs(e, D, best)
	if ins.is_empty(): return 0.0
	var cost := _batch_cost(e, ins)
	if cost <= 0.0: return 0.0
	var share := float(D["market"]["buy_share"])
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	quoted["till"] = cost
	if _recipe_batch_limit(e, quoted, best, ins, 1, mkt, share) < 1: return 0.0
	var BB: Dictionary = Barge.B()["business"]
	var upkeep := float(BB["upkeep"][0]) + float(BB["upkeep"][1]) * float(b["workers"])
	# The ordinary weekly owner turn keeps a complete batch affordable while
	# slow recipes retain work across weeks and the daily building bill is paid.
	var capital := cost + upkeep * 7.0
	var tool_cost := 0.0
	# Tomorrow's actual sequence is wear, optional one-tool purchase, then
	# throughput. Only copied scalar counts are used by this read-only quote.
	var tools := int(b["tools"])
	var wear := float(b["tw"]) + float(working) / float(D["needs"]["wear_days"]["tools"])
	if wear >= 1.0 and tools > 0: tools -= 1
	if tools < working and int(e["stock"].get("tools", 0)) > 0:
		var tp := float(e["price"]["tools"])
		if maxf(float(b["till"]), reserved + capital) > tp * 2.0: tool_cost = tp; tools += 1
	var toolf := 0.5 + 0.5 * minf(1.0, float(tools) / float(working))
	var spec := 1.0
	for specialty in e["specialties"]:
		if D["specialties"][specialty]["biz"] == b["type"]: spec = 2.0; break
	var units := _recipe_units(e, D, quoted, best, float(working), toolf, spec)
	if units <= 0.0: return 0.0
	# Wage reserves are never used as hypothetical material money in this quote.
	quoted["till"] = capital
	var scale := _recipe_scale(e, quoted, best, ins, units, mkt, share, {})
	var net := units * scale * (_batch_quote(e, best, share) - cost)
	# Incumbents can recover or have earned a partial day before illness.
	# Viability therefore covers their full ordinary bill, as the reserve does.
	if net <= upkeep + float(b["workers"]) * float(b["wage"]) + 0.00001: return 0.0
	return capital + tool_cost

static func _mine(e: Dictionary, D: Dictionary, b: Dictionary, wd: float, toolf: float, spec: float, mkt: Dictionary, share: float, rng: RandomNumberGenerator = null) -> void:
	var ore: String = b.get("ore", "copper_ore")
	var st: Dictionary = e["stock"]
	if float(st.get(ore, 0)) >= stock_cap(e, ore) * 2.0:
		b["state"] = "full"
		b["fg"] = ore
		return
	var amt := wd * float(D["mine_rate"]) * float(b.get("rich", 1.0)) * toolf * (1.5 if b.get("spec", false) else spec) + float(b["oc"].get(ore, 0.0))
	var nn := int(floor(amt))
	var p := float(e["price"][ore]) * share
	if float(nn) * p > float(mkt["till"]):
		nn = int(maxf(0.0, float(mkt["till"])) / p)
		b["state"] = "nopay"
	b["oc"][ore] = minf(amt - nn, 1.0)
	if nn <= 0:
		return
	st[ore] = int(st.get(ore, 0)) + nn
	TownEcon.led(e, "made", ore, nn)
	mkt["till"] = float(mkt["till"]) - float(nn) * p
	b["till"] = float(b["till"]) + float(nn) * p
	mkt["spend"] = float(mkt["spend"]) + float(nn) * p
	if rng != null:
		Legends.mine_day(e, b, ore, nn, mkt, share, rng)   # v0.014: now and then the miners hit a gem pocket

# ------------------------------------------------------------------ gear
## Cloth and leather gear on the stalls (one scan per market day).
static func _gear_counts(town: Dictionary) -> Dictionary:
	var c := 0; var l := 0
	for it in town.get("shop", []):
		var m: String = it.material
		if m == "linen":
			c += 1
		elif m == "leather":
			l += 1
	return {"cloth": c, "leather": l}

static func _gear_short(town: Dictionary, kind: String) -> bool:
	var n := 0
	for it in town.get("shop", []):
		var m: String = it.material
		if (kind == "cloth" and m == "linen") or (kind == "leather" and m == "leather"):
			n += 1
	return n < 4 + int(town.get("size", 0))

static func arms_cap(town: Dictionary) -> int:
	var M: Dictionary = TownEcon.data()["market"]
	return int(M["arms_cap_base"]) + int(M["arms_cap_size"]) * int(town.get("size", 0))

## Templates a smith of this kind may make for the town's culture.
static var _pools: Dictionary = {}
static func gear_pool(culture: String, kind: String) -> Array:
	var key := culture + "|" + kind
	if not _pools.has(key):
		_pools[key] = _gear_pool(culture, kind)
	return _pools[key]

static func _gear_pool(culture: String, kind: String) -> Array:
	var out := []
	match kind:
		"weapon":
			out = DB.weapons_by_culture.get(culture, DB.weapons_by_culture.get("middle", [])).duplicate()
		"armor":
			for tid in DB.armor_by_culture.get(culture, []):
				if (DB.armor[tid].get("materials", []) as Array).has("copper"):
					out.append(tid)
		"cloth", "leather":
			var mat := "linen" if kind == "cloth" else "leather"
			for c in [culture, "common"]:
				for tid in DB.armor_by_culture.get(c, []):
					if (DB.armor[tid].get("materials", []) as Array).has(mat):
						out.append(tid)
		"bow":   # bows: each race's bowyers make their own styles
			out = DB.bows_by_culture.get(culture, DB.bows_by_culture.get("middle", [])).duplicate()
	return out

## Bars (or bolts/skins) and wood one piece of `tid` in `mat` takes: {good: n}.
static func gear_inputs(tid: String, mat: String) -> Dictionary:
	var t := DB.template(tid)
	if DB.is_bow(tid):   # bows: seasoned staves (composites: wood, horn, sinew, glue)
		var bi := {}
		var ins: Dictionary = t.get("inputs", {"staves": 1})
		for g in ins:
			bi[g] = int(ins[g])
		return bi
	var dens := float(DB.materials.get(mat, {}).get("density", 1000))
	var D := TownEcon.data()
	if DB.is_weapon(tid):
		var kg := float(t.get("head_cm3", 0)) * dens / 1.0e6
		var o := {D["metal_bars"][mat]: maxi(1, int(ceil(kg)))}
		if float(t.get("haft_kg", 0.0)) > 0.0:
			o["wood"] = 1
		return o
	var kg2 := float(t.get("cm3", 0)) * dens / 1.0e6
	match mat:
		"linen": return {"linen": maxi(1, int(ceil(kg2)))}
		"leather": return {"leather": maxi(1, int(ceil(kg2)))}
	return {D["metal_bars"][mat]: maxi(1, int(ceil(kg2)))}

## v0.014: a weaponsmith's or armourer's standing want for bars (data smith_bars), wd worker-days: per x wd x the
## town's usable know-how in the metal / 100, added to the day's business demand (bdem). The market keeps a normal
## stock of demand x its days of cover (TownEcon / Barge prices): that is the smiths' stockpile target, and the price
## and the caravans follow it. No know-how, no want (orcs and goblins place none for bronze).
static func smith_want(e: Dictionary, wd: float, bdem: Dictionary) -> void:
	var SB: Dictionary = TownEcon.data().get("smith_bars", {})
	for g in SB:
		var r: Dictionary = SB[g]
		var k := String(r.get("knowhow", ""))
		var f := 1.0 if k == "" else kh_of(e, k) / 100.0
		if f > 0.0:
			bdem[g] = float(bdem.get(g, 0.0)) + float(r["per"]) * wd * f

## Older mixed trades used one untyped fraction for item and recipe units.
## Preserve that evidence, but never guess it into either output channel. New
## rows and already split saves have explicit channels; migration is one-time.
static func _gear_carry_key(b: Dictionary, T: Dictionary) -> String:
	if (T["recipes"] as Array).is_empty(): return "carry"
	if not b.has("arms_carry"):
		var legacy := float(b.get("carry", 0.0))
		if legacy != 0.0: b["legacy_mixed_carry_untyped"] = legacy
		b["carry"] = 0.0
		b["arms_carry"] = 0.0
	return "arms_carry"

static func _arms(_game, town: Dictionary, e: Dictionary, D: Dictionary, b: Dictionary, T: Dictionary, wd: float, toolf: float,
		spec: float, rng: RandomNumberGenerator, mkt: Dictionary, bdem: Dictionary) -> float:
	if T["arms"] == "bow":   # bows: the bowyer's bows (campaign/bows_econ.gd)
		return BowsEcon.make_bows(town, e, D, b, wd, toolf, spec, rng, mkt, bdem)
	# Gear items and recipe batches have different units. A mixed trade keeps
	# its recipe work in carry; stopping gear must not erase that work or use
	# it toward an item. Pure gear makers retain their existing saved channel.
	var carry_key := _gear_carry_key(b, T)
	var shop: Array = town.get("shop", [])
	var orders_only := false   # v0.014: stalls full, but the head's armory has orders (ArmsTrade.order_buy)
	if T["arms"] in ["weapon", "armor"] and shop.size() >= arms_cap(town):
		if not ArmsTrade.has_orders(e, T["arms"]):
			b["state"] = "full"
			b["fg"] = "arms"
			b[carry_key] = 0.0
			return 0.0
		orders_only = true
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var kh := kh_of(e, "bronze")   # v0.014: the town's practice under the faction's know-how (0 for orcs and goblins)
	var skh := kh_of(e, "steel")   # v0.012: the faction's steel know-how caps the best steel its smiths can make
	var ikh := kh_of(e, "iron")    # v0.014: the faction's iron know-how gates working iron
	var kind: String = T["arms"]
	# (v0.014: the bars smiths keep wanting go to the market in Businesses.daily: smith_want)
	if kind in ["weapon", "armor"] and int(st.get("copper_bars", 0)) + int(st.get("tin_bars", 0)) + (int(st.get("bronze_bars", 0)) if kh > 0.0 else 0) \
			+ (int(st.get("iron_bars", 0)) if ikh > 0.0 else 0) + (int(st.get("steel_bars", 0)) if skh > 0.0 else 0) <= 0:
		b["state"] = "inputs"   # smiths spend bars; no bars = idle
		b["why"] = "bars"
		b[carry_key] = 0.0
		for bg in ["copper_bars", "tin_bars"]:
			bdem[bg] = float(bdem.get(bg, 0.0)) + 3.0 * wd
		return 0.0
	var pool := gear_pool(town.get("culture", "middle"), kind)
	if pool.is_empty():
		b["state"] = "idle"
		return 0.0
	var f := wd * float(T["rate"]) * toolf * spec + float(b.get(carry_key, 0.0))
	var whole := int(floor(f))
	b[carry_key] = minf(f - whole, 1.0)
	var spent := 0.0
	var bronze_days := 0.0
	var share := float(D["market"]["arms_buy_share"])
	var made_any := false
	for i in whole:
		var tid := ""
		if orders_only:
			var op := ArmsTrade.order_pool(e, pool)
			if op.is_empty():
				b["state"] = "full"
				b["fg"] = "arms"
				break
			tid = op[rng.randi() % op.size()]
		else:
			tid = ArmsTrade.pick_tid(e, pool, rng) if kind in ["weapon", "armor"] else pool[rng.randi() % pool.size()]   # arms trade: the armory's shortfall first
		var mat := ""
		if kind == "cloth":
			mat = "linen"
		elif kind == "leather":
			mat = "leather"
		else:
			mat = _pick_metal(e, tid, kh, int(town.get("wealth", 2)), rng, skh, ikh)
		if mat == "":
			b["state"] = "inputs"
			b["why"] = "bars"
			for bg in ["copper_bars", "tin_bars"]:
				bdem[bg] = float(bdem.get(bg, 0.0)) + 3.0
			b[carry_key] = 0.0
			break
		var ins := gear_inputs(tid, mat)
		var cost := 0.0
		var ok := true
		for ig in ins:
			bdem[ig] = float(bdem.get(ig, 0.0)) + float(ins[ig])
			if int(st.get(ig, 0)) < int(ins[ig]):
				ok = false
			cost += float(ins[ig]) * float(price[ig])
		if not ok:
			b["state"] = "inputs"
			b["why"] = "wood" if mat != "linen" and mat != "leather" else mat
			break
		if float(b["till"]) < cost:
			b["state"] = "wages"
			b["why"] = "money for bars"
			break
		var skill := float(b.get("skill", 3)) + (3.0 if spec > 1.0 else 0.0)
		if mat == "bronze":
			skill -= 4.0 * (1.0 - kh / 100.0)
		elif mat in ["linen", "leather"]:
			skill *= 0.5
		var q := Factory.roll_quality(rng, skill, true)   # v0.014: a real forge: its masterwork rolls may be legendary
		if mat == "steel":
			var bq := maxi(0, Academy.best_quality(skh))
			if not (q == DB.LEGEND and bq >= 5):
				q = mini(q, bq)   # the smith's skill on top, never past the faction's know-how
		var it := Item.make(tid, mat, q)
		ArmsTrade.mark(it, town, b)   # arms trade: the maker's mark
		if it.is_legend():   # v0.014: a real maker of this forge and a real stone, else it stays masterwork
			Legends.forge(_game if _game != null else Game, town, e, b, it, rng, float(e.get("day", 0)))
		var value := Economy.base_value(town, it) * share
		# v0.014: a piece the armory has an order for goes to the head (the treasury pays the smith), else the market
		var to_arm := kind in ["weapon", "armor"] and ArmsTrade.order_buy(_game, town, e, it, value)
		if not to_arm:
			if it.is_legend():
				value = minf(value, maxf(0.0, float(mkt["till"])))   # never left unmade: the market pays what its till holds
			elif orders_only:
				b["state"] = "full"   # the head cannot pay for his orders and the stalls are full
				b["fg"] = "arms"
				break
			if float(mkt["till"]) < value:
				b["state"] = "nopay"
				break
		for ig in ins:
			st[ig] = int(st[ig]) - int(ins[ig])
			TownEcon.led(e, "used", ig, int(ins[ig]))
		b["till"] = float(b["till"]) - cost + value
		mkt["till"] = float(mkt["till"]) + cost - (0.0 if to_arm else value)
		if not to_arm:
			mkt["spend"] = float(mkt["spend"]) + value
			shop.append(it)
		e["stats"]["sales"] = float(e["stats"]["sales"]) + cost
		spent += cost
		TownEcon.led(e, "made", "arms", 1)
		if mat == "bronze":
			TownEcon.led(e, "made", "arms_bronze", 1)
			bronze_days += 1.0 / maxf(0.05, float(T["rate"]))
		made_any = true
	town["shop"] = shop
	if bronze_days > 0.0:
		TownEcon.knowhow_gain(e, "bronze", bronze_days)
	if not made_any and whole == 0 and b["state"] == "busy":
		b["state"] = "busy"
	return spent

## Metal for one piece: bronze by know-how, copper or tin by what the bins hold (richer towns like copper); iron
## when there are iron bars (v0.012); steel only where the faction knows it (skh = its steel know-how, 0 = none);
## v0.014: iron only where the faction knows it (ikh), bronze only with usable bronze know-how (kh, 0 = none).
static func _pick_metal(e: Dictionary, tid: String, kh: float, wealth: int, rng: RandomNumberGenerator, skh: float = 0.0, ikh: float = 100.0) -> String:
	var st: Dictionary = e["stock"]
	var opts := []
	var tot := 0.0
	for m in ["copper", "tin", "bronze", "iron", "steel"]:
		if (m == "steel" and skh <= 0.0) or (m == "iron" and ikh <= 0.0) or (m == "bronze" and kh <= 0.0):
			continue
		var ins := gear_inputs(tid, m)
		var bars: String = TownEcon.data()["metal_bars"][m]
		if int(st.get(bars, 0)) < int(ins[bars]):
			continue
		var wt := 1.0
		match m:
			"copper": wt = 0.6 + 0.15 * wealth
			"tin": wt = 0.8
			"bronze": wt = 1.5 * kh / 100.0
			"iron": wt = 1.2   # [ours] smiths take iron over copper and tin when they have it
			"steel": wt = 0.5 + 1.5 * skh / 100.0   # [ours] more as the faction masters it
		if wt <= 0.0:
			continue
		opts.append([m, wt])
		tot += wt
	if opts.is_empty():
		return ""
	var r := rng.randf() * tot
	for o in opts:
		r -= float(o[1])
		if r <= 0.0:
			return o[0]
	return opts[-1][0]

# ================================================================== owners
## Land left by a household joins the existing town estate. Its old farm row
## cannot offer another set of jobs on that same land. Keep its till, wage debt,
## tools and incumbent assignments for the ordinary final payday/closed-job exit.
static func town_inherits(b: Dictionary) -> void:
	b["owner"] = -1
	b["kw"] = 0
	b["for_sale"] = String(b["type"]) != "farm"
	if String(b["type"]) == "farm":
		b["cap"] = 0
		b["closed"] = true

## Move the existing owner's coins into the existing farm reserve. Funding is
## separate from the weekly books and cannot pay or erase earned wage claims.
static func fund_farm(f: Dictionary, b: Dictionary) -> float:
	if b.get("closed", false) or String(b.get("type", "")) != "farm":
		return 0.0
	var owed := maxf(0.0, float(b.get("owed", 0.0)))
	var need := owed + float(maxi(int(b["workers"]), int(b["cap"]))) * float(b["wage"]) * 8.0
	var inj := minf(maxf(0.0, need - float(b["till"])), maxf(0.0, float(f["purse"]) - 5.0 * TownEcon.COIN))
	if inj > 0.0:
		b["till"] = float(b["till"]) + inj
		f["purse"] = float(f["purse"]) - inj
		b["t_paid"] = float(b.get("t_paid", 0.0)) - inj
	return inj

## The owner's weekly look at a business: take profit above a reserve, put money in when the till runs dry,
## hire when busy and flush, let people go when the market is full or the inputs run out.
static func owner_turn(e: Dictionary, f: Dictionary, b: Dictionary, days: float = 7.0) -> void:
	if b["closed"]:
		return
	var bill := float(b["workers"]) * float(b["wage"])
	# Accrued wages, including retained older claims, are separate from the
	# operating reserve. They cannot also fund future jobs or an owner's take.
	var owed := maxf(0.0, float(b.get("owed", 0.0)))
	if b["type"] == "farm":
		fund_farm(f, b)
		_farm_books(f, b, days)
		return
	var BB: Dictionary = Barge.B()["business"]
	# barge part 3 section 6: the keeper's take: above 60 days of (wages + upkeep) he draws 8% of the excess a day
	var up := float(BB["upkeep"][0]) + float(BB["upkeep"][1]) * float(b["workers"])
	# v0.014: the wages are those of its places (its target staff), not only of the hands it has now. (Before: a shop
	# with nobody hired kept 60 days of its upkeep alone, about 240 coins; its keeper drew the rest, the upkeep ate the
	# 240, and then nobody would sign on at the empty till: every unstaffed shop in Fenmere showed 0 coins.)
	var bill_places := float(maxi(int(b["workers"]), int(b["cap"]))) * float(b["wage"])
	var reserve := (bill_places + up) * float(BB["take_days"]) + float(b["spend"]) * 14.0
	if b["type"] == "market":
		# the market's "spend" counts the week's purchases from producers and barns: keep ~2.5 weeks of them
		reserve = float(b["spend"]) * 2.5 + (bill + up) * float(BB["take_days"])
		b["spend"] = 0.0
	reserve += owed
	# a business that would hire (below its places, thriving or its goods scarce: barge part 3 section 5) is funded for
	# one hand more: nobody signs on at an empty till, and a business with nobody had no wage bill to fund (v0.011: every
	# empty smelter, mine and woodcutter stayed empty with ore at 0.3 x base and bars at 3-5 x)
	var fund := bill
	if b["type"] != "market" and hiring(e, b):
		fund = float(int(b["workers"]) + 1) * float(b["wage"])
	var funded_need := owed + fund * 7.0
	if b["type"] != "market": funded_need += operating_cash(e, b, funded_need)
	# Batch capital must not become the owner's take before slow work completes.
	reserve = maxf(reserve, funded_need)
	if float(b["till"]) > reserve:
		var take := (float(b["till"]) - reserve) * (1.0 - pow(1.0 - float(BB["take_share"]), 7.0))
		b["till"] = float(b["till"]) - take
		f["purse"] = float(f["purse"]) + take
		b["t_paid"] = float(b.get("t_paid", 0.0)) + take
	elif float(b["till"]) < funded_need and float(f["purse"]) > 20.0 * TownEcon.COIN:
		var inj2 := minf(funded_need - float(b["till"]), float(f["purse"]) * 0.5)
		b["till"] = float(b["till"]) + inj2
		f["purse"] = float(f["purse"]) - inj2
		b["t_paid"] = float(b.get("t_paid", 0.0)) - inj2
	var st: String = b["state"]
	# v0.014: no ceiling on one shop's places. The old 14 assumed a town had several shops of a trade; with one shop
	# per trade, more demand is more places in it (the growth rules below still decide when it takes one on).
	var max_cap: int = 1 << 20
	# hiring and laying off (barge part 3 section 5): below its places a business hires if thriving or its goods sell;
	# loss days > 20 (> 10 when the till is empty) with more than one hand: the last hand taken on goes
	var ld := int(b.get("ld", 0))
	var lim := int(BB["loss_days_broke"]) if float(b["till"]) < float(b["wage"]) else int(BB["loss_days"])
	if ld > lim and int(b["cap"]) > 1:
		b["cap"] = int(b["cap"]) - 1
		b["ld"] = ld - 5
	elif st == "busy" and (String(b.get("health", "")) == "thriving" or float(b["till"]) > reserve) and int(b["workers"]) >= int(b["cap"]) and int(b["cap"]) < max_cap:
		b["cap"] = int(b["cap"]) + 1
	elif st == "busy" and int(b["workers"]) >= int(b["cap"]) and int(b["cap"]) < max_cap and _gains_hand(e, b):
		b["cap"] = int(b["cap"]) + 1
	elif st in ["full", "inputs", "wages", "nopay"] and int(b["cap"]) > 1:
		b["cap"] = int(b["cap"]) - 1

## v0.014: a farm's books (barge part 3 section 6, the same rule as the trades'), weekly at the owner's turn: a farm
## row is the family's land with its hired hands, and what the land and herds earn goes to the family's purse (f.lpay,
## a week's worth: Families.turn), not to the farm's till. Profit a day = the land's earnings a day - the hired hands'
## wages; staff = the family's own hands + the hired. The 14-day average and the loss days move a week at a time.
## [ours] the weekly step (the farm has no daily pass).
static func _farm_books(f: Dictionary, b: Dictionary, days: float = 7.0) -> void:
	var BB: Dictionary = Barge.B()["business"]
	var wage := float(b["wage"])
	var hired := int(b["workers"])
	# Expense is the work actually earned during this owner's reporting period;
	# paying an old claim later does not charge the same work a second time.
	var earned := float(b.get("wage_cost_period", float(hired) * wage * days))
	var profit := float(f.get("lpay", 0.0)) / 7.0 - earned / maxf(1.0, days)
	b["wage_cost_period"] = 0.0
	var a14 := float(b.get("p14", profit))
	a14 += (profit - a14) * (1.0 - pow(13.0 / 14.0, 7.0))
	b["p14"] = a14
	b["p1"] = profit
	var staff := float(hired + int(f.get("hands", 0)))
	var ld := int(b.get("ld", 0))
	if profit < -0.3 * staff * wage or a14 < -0.25 * wage:
		ld += 7
	else:
		ld = maxi(0, ld - 7)
	b["ld"] = ld
	b["health"] = "struggling" if ld > int(BB["struggling"]) else ("thriving" if a14 > float(BB["thriving"]) * maxf(staff, 1.0) * wage else "steady")
