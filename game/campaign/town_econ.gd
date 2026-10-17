class_name TownEcon
extends RefCounted
## The real town economy (docs/specs/economy-1-town.md, "Core with families"). Rule zero: every good is an
## integer count held by a town market (econ.stock), a barn (harvest stores of the landholders), the granary
## (the town's grain), a family, a caravan, a force or the company; gold is held by markets and businesses
## (tills), families (purses), treasuries, caravans and the company. Goods appear only by production and
## leave only by use, wear, spoilage, loss or raids; every trade moves gold.
##
## Layout: EconGen (world gen, econ dict layout), Families (records, weekly family turn), Businesses
## (rows, daily production), this file (daily town pass, market, prices, supply levels, arms stock API,
## weekly town and faction turns, load/migration). Goods (goods.gd) is the read side for menus and Food.
##
## Time: CampaignWorld._daily queues work jobs, one per map frame (big time jumps drain the queue):
##   ["econ", tid, day]  daily town pass (farms, barns, businesses, market clearing, spoilage, prices)
##   ["fam", tid, day]   family turns for families with id % 7 == day % 7 (each family weekly)
##   ["tturn", tid, day] weekly town turn (towns staggered by index), ["fturn", day] weekly faction turn, ["wed", tid, day] weddings (Persons.marriages, once in four weeks)
## Each job is a few hundred dictionary operations: cheap sums, no per-person objects.

static var _d: Dictionary = {}
## Coinage (docs/specs/barge/05-coinage.md): the old gold amounts of our own [ours] rules are counted in coins x20
## (100 coins = a labourer's day; the farmhand's 4.5 gold a day = 90 coins). Barge numbers are used as given.
const COIN := 20.0
## Gold that left the world (families leaving with their purse). Conservation tests read it.
static var gold_gone: float = 0.0
## Goods destroyed outside a town (caravans lost or raided: the share nobody took). {good|"arms": n}
static var goods_lost: Dictionary = {}

# ================================================================== data
static func data() -> Dictionary:
	if _d.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/economy.json"))
		if d is Dictionary:
			_d = d
			var g := {}
			for k in d["goods"]:
				if not String(k).begins_with("_"):
					g[k] = d["goods"][k]
			_d["goods"] = g
	return _d

static func has_econ(town: Dictionary) -> bool:
	return town.has("econ") and (town["econ"] as Dictionary).has("stock")

static func season_stamp(day: float) -> int:
	return Calendar.year(day) * 4 + Calendar.season_index(day)

static func led(e: Dictionary, kind: String, g: String, n: int) -> void:
	var l: Dictionary = e["led"][kind]
	l[g] = int(l.get(g, 0)) + n

static func gold_out(v: float) -> void:
	gold_gone += v

static func town_hist(e: Dictionary, line: String, day: float) -> void:
	var h: Array = e["hist"]
	h.append("%s: %s" % [Calendar.text(day).split(" - ")[0], line])
	while h.size() > 10:
		h.pop_front()

## "barley", "apples", "flax" (the town's own variety for a crop).
static func variety_word(e: Dictionary, crop: String) -> String:
	return String(e.get("crops", {}).get(crop, crop))

## "barley ale", "cider", "mutton": the label a good rides with in this town.
static func label(e: Dictionary, g: String) -> String:
	var V: Dictionary = data()["varieties"]
	match g:
		"grain": return V.get(e["crops"]["grain"], {}).get("food", "grain")
		"fruit": return V.get(e["crops"]["fruit"], {}).get("food", "fruit")
		"beer": return V.get(e["crops"]["grain"], {}).get("drink", "beer")
		"wine": return V.get(e["crops"]["fruit"], {}).get("drink", "wine")
		"meat":
			var hk: Array = e.get("herd_kinds", [])
			return V.get(hk[0], {}).get("food", "meat") if not hk.is_empty() else "meat"
	return data()["goods"].get(g, {}).get("name", g)

## Recounts population, adults, homes and the household goods totals from the family records.
static func recount(e: Dictionary) -> void:
	var pop := 0; var ad := 0; var homes := 0
	var hh := {}
	for f in e["fams"]:
		if f.get("gone", false):
			continue
		pop += Families.people(f)
		ad += Families.adults(f)
		homes += int(f["homes"]) if not f.has("lodging") else 0
	for h in e.get("lodgings", []): homes += int(h["buildings"])
	e["pop"] = pop; e["adults"] = ad; e["homes"] = homes
	if not e.has("hh"):
		e["hh"] = hh

## "1 acre", "12 acres", "a cow" -> "1 cow", "3 cattle", "1 pig": counts in running text.
const SINGULAR := {"acres": "acre", "cattle": "cow", "pigs": "pig", "goats": "goat", "sheep": "sheep", "horses": "horse", "donkeys": "donkey"}
static func n_of(n: int, plural: String) -> String:
	return ("one " + SINGULAR.get(plural, plural)) if n == 1 else "%d %s" % [n, plural]

## Acres in the town's land pool (every crop; families and the town estate).
static func land_total(e: Dictionary) -> int:
	var n := 0
	for c in e.get("land", {}):
		n += int(e["land"][c])
	return n

## {territory, families, estate, common}: territory is stored at world gen (the land pool then); land only moves
## between families and the estate, so common (unclaimed) is whatever of the territory nobody holds.
static func land_split(e: Dictionary) -> Dictionary:
	var fam := 0
	for f in e["fams"]:
		if not f.get("gone", false) and not f.has("estate"):
			fam += Families.acres(f)
	var est := Families.acres(e["fams"][0])
	var terr := int(e.get("territory", fam + est))
	return {"territory": terr, "families": fam, "estate": est, "common": maxi(0, terr - fam - est)}

## The town's land for the Town screen: land_split plus acres by crop for the resident families and for the
## estate, and herds by animal: {territory, families, estate, common, fam_crops {crop: acres}, est_crops,
## herds {animal: head}, fam_herd, est_herd}. Residents = families not gone.
static func land_summary(e: Dictionary) -> Dictionary:
	var s := land_split(e)
	var fl := {}; var fh := {}; var all_h := {}
	var fhn := 0; var ehn := 0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		for c in f["land"]:
			fl[c] = int(fl.get(c, 0)) + int(f["land"][c])
		for a in f["herd"]:
			fh[a] = int(fh.get(a, 0)) + int(f["herd"][a])
			fhn += int(f["herd"][a])
	var est: Dictionary = e["fams"][0]
	all_h = fh.duplicate()
	for a in est["herd"]:
		ehn += int(est["herd"][a])
		all_h[a] = int(all_h.get(a, 0)) + int(est["herd"][a])
	s["fam_crops"] = fl
	s["est_crops"] = (est["land"] as Dictionary).duplicate()
	s["herds"] = all_h
	s["fam_herd"] = fhn
	s["est_herd"] = ehn
	return s

## What befell the town (for its people's stories): e.tev = [[day, code, args...]], the newest TEV_MAX. Codes:
## famine (the granary opened for want of bread), sacked [by], war [declarer, enemy], peace [a, b],
## caravan_lost [taken by]. Backstory.story reads it (sacked, famine: a beat of a recruit's story).
const TEV_MAX := 10
static func town_event(e: Dictionary, code: String, args: Array, day: float) -> void:
	if not e.has("tev"):
		e["tev"] = []
	var a: Array = e["tev"]
	if code == "famine" and not a.is_empty():
		for x in a:
			if String(x[1]) == "famine" and day - float(x[0]) < 60.0:
				return   # one famine a season or two, not one a week
	a.append([int(day), code] + args)
	while a.size() > TEV_MAX:
		a.pop_front()

## town_event for every town of a faction (wars, peace).
static func faction_event(w: Dictionary, fid: String, code: String, args: Array, day: float) -> void:
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if String(t.get("faction", "")) == fid and has_econ(t):
			town_event(t["econ"], code, args, day)

static func culture_of(e: Dictionary) -> Dictionary:
	return data()["cultures"][e["culture"]]

## Gold from a family to the market (an exact transfer).
static func pay_market(e: Dictionary, f: Dictionary, cost: float) -> void:
	f["purse"] = float(f["purse"]) - cost
	var m: Dictionary = e["biz"][int(e["mkt"])]
	m["till"] = float(m["till"]) + cost
	e["stats"]["sales"] = float(e["stats"]["sales"]) + cost

## A family buys up to q of good g at today's price: the order counts toward demand (prices are the sum of
## the actors' orders against the stock), the market fills what its stock and the purse allow; the goods go
## into the household pool (a new home becomes the family's). Returns units bought.
static func family_buy(e: Dictionary, f: Dictionary, g: String, q: int) -> int:
	if q <= 0:
		return 0
	var st: Dictionary = e["stock"]
	var have := int(st.get(g, 0))
	# a short good is shared out: nobody takes more than a quarter of what is on the stalls at once
	var n0 := mini(q, have if have <= 8 or q * 4 <= have else maxi(1, have / 4))
	var n := n0
	var p := float(e["price"][g]) * markup()   # households pay the price x 1.1 (barge part 2 section 5)
	var purse := float(f["purse"]) - 1.0
	if float(n) * p > purse:
		n = int(maxf(0.0, purse) / p)
	Barge.add_demand(e, g, float(maxi(n, 0)), float(q - n0), float(n0 - maxi(n, 0)))
	if n <= 0:
		return 0
	st[g] = have - n
	pay_market(e, f, float(n) * p)
	if g == "home":
		f["homes"] = int(f["homes"]) + n
		e["homes"] = int(e["homes"]) + n
		led(e, "used", "home", n)
	else:
		var hh: Dictionary = e["hh"]
		hh[g] = int(hh.get(g, 0)) + n
	return n

static func knowhow_gain(e: Dictionary, mat: String, worker_days: float) -> void:
	var K: Dictionary = data()["knowhow"].get(mat, {})
	if K.is_empty():
		return
	var kh := float(e["knowhow"].get(mat, 0.0))
	e["knowhow"][mat] = minf(100.0, kh + float(K["gain"]) * worker_days * (1.0 - kh / 100.0))
	e["kh_used"] = int(e.get("day", 0))

# ================================================================== work queue (CampaignWorld)
## Queues the day's economy jobs: a market day per town, the families whose turn it is, the weekly town turns
## (staggered by town) and the weekly faction turn. Called from CampaignWorld._daily.
static func queue_day(w: Dictionary, d: int) -> void:
	var work: Array = w["work"]
	var ids: Array = w["towns"].keys()
	ids.sort()
	for i in ids.size():
		var t: Dictionary = w["towns"][ids[i]]
		if not has_econ(t):
			continue
		work.append(["econ", ids[i], d])
		work.append(["bday", ids[i], d])   # barge: the day wage, the coin pass
		work.append(["fam", ids[i], d])
		work.append(["fam2", ids[i], d])   # the family turns in two halves (each family still once a week)
		if (d + i) % 7 == 0:
			work.append(["tturn", ids[i], d])
		if (d + i) % 28 == 3:
			work.append(["wed", ids[i], d])   # weddings across the town's families, once in four weeks (own frame)
		if (d + i * 7) % 30 == 0 and d > 0:
			work.append(["tmonth", ids[i], d])   # barge part 4 section 1: the town's tax day (once in 30 days)
	if d % 7 == 3:
		work.append(["fturn", d])
	work.append(["coin", d])   # barge: the coin pass (drain, mints, melting, the price level, coin shortage)
	if d % 30 == 15:
		work.append(["movein", d])   # barge part 4 section 6: towns with empty homes and better wages draw families

## Runs one queued economy job. Returns false if the job is not an economy job.
static func do_job(game, job: Array) -> bool:
	var w: Dictionary = game.world
	match job[0]:
		"econ":
			if w["towns"].has(job[1]):
				daily_pass(game, w["towns"][job[1]], int(job[2]), false)
		"fam":
			if w["towns"].has(job[1]):
				family_batch(game, w["towns"][job[1]], int(job[2]), 0)
		"fam2":
			if w["towns"].has(job[1]):
				family_batch(game, w["towns"][job[1]], int(job[2]), 1)
		"bday":
			if w["towns"].has(job[1]):
				barge_day(game, w["towns"][job[1]], int(job[2]))
		"tmonth":
			if w["towns"].has(job[1]) and has_econ(w["towns"][job[1]]):
				Barge.treasury_month(game, w["towns"][job[1]], w["towns"][job[1]]["econ"], float(job[2]))
		"tturn":
			if w["towns"].has(job[1]):
				town_turn(game, w["towns"][job[1]], int(job[2]))
		"fturn":
			faction_turn(game, int(job[1]))
		"coin":
			Barge.coin_day(game, int(job[1]))
		"movein":
			Barge.move_in(game, float(job[1]))
		"wed":
			if w["towns"].has(job[1]) and has_econ(w["towns"][job[1]]):
				Persons.marriages(w["towns"][job[1]]["econ"], float(job[2]))
		_:
			return false
	return true

## The family turns of one day: families with id % 7 == day % 7 (each family once a week), in two halves (two work
## jobs: ids % 14 == day % 7 and day % 7 + 7) so a map frame does half of them.
static func family_batch(game, town: Dictionary, day: int, half: int = -1) -> void:
	if not has_econ(town):
		return
	var e: Dictionary = town["econ"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(game.world.get("seed", 0)), town["id"], day, "fam", half])
	var fams: Array = e["fams"]
	var i := day % 7 + (7 * half if half >= 0 else 0)
	var stepn := 14 if half >= 0 else 7
	batch_open = true
	while i < fams.size():
		Families.turn(game, town, e, fams[i], float(day), rng)
		i += stepn
	batch_open = false
	var t0 := Time.get_ticks_usec() if prof_on else 0
	clear_batch(e)
	if prof_on: _prof("f_clear_batch", t0)
	# An owner's ordinary turn can fund or expand private farm places after
	# idle civilians have already had their weekly turn. Complete this batch's
	# actual funded matching without advancing anyone's wages or payday.
	Families.match_idle(e)

## The day's family buy orders: [family, good, qty, store, rate]. They clear once against the market stock
## (spec 4: posted family buy orders vs stock); a short good is shared out pro rata.
static var batch: Array = []
static var batch_open := false
static var batch_barn := false   # an order on the batch buys straight from the barns

static var _markup := -1.0
static func markup() -> float:
	if _markup < 0.0:
		_markup = float(data()["barge"]["household"]["markup"])
	return _markup

## Orders: [family, good, qty, store, rate] bought at the market (price x markup); an order may carry a 6th element,
## a price factor for buying straight from the barns (the farms' own harvest: landholders at the broker's 0.75 x P,
## field hands' wages in grain at P; the coin goes to the farm till, paid to the owners of the goods).
static func clear_batch(e: Dictionary) -> void:
	if batch.is_empty():
		return
	HarvestClaims.ensure(e)
	HarvestClaims.reserve_all(e)
	var st: Dictionary = e["stock"]
	var barn: Dictionary = e["barn"]
	var price: Dictionary = e["price"]
	var hh: Dictionary = e["hh"]
	# orders the barns cannot fill go on to the market (the family buys the rest there)
	var bwant := {}
	if batch_barn:
		for o in batch:
			if o.size() > 5:
				bwant[o[1]] = int(bwant.get(o[1], 0)) + int(o[2])
	batch_barn = false
	if not bwant.is_empty():
		var extra := []
		for o in batch:
			if o.size() <= 5:
				continue
			var g0: String = o[1]
			var r0 := minf(1.0, float(HarvestClaims.available(e, g0)) / maxf(1.0, float(bwant[g0])))
			var take := int(float(o[2]) * r0)
			if take < int(o[2]):
				extra.append([o[0], g0, int(o[2]) - take, o[3], o[4]])
				o[2] = take
		batch.append_array(extra)
	var tot := {}
	var btot := {}
	for o in batch:
		var g: String = o[1]
		if o.size() > 5:
			btot[g] = int(btot.get(g, 0)) + int(o[2])
		else:
			tot[g] = int(tot.get(g, 0)) + int(o[2])
	var ratio := {}
	for g in tot:
		ratio[g] = minf(1.0, float(st.get(g, 0)) / maxf(1.0, float(tot[g])))
	var bratio := {}
	for g in btot:
		bratio[g] = minf(1.0, float(HarvestClaims.available(e, g)) / maxf(1.0, float(btot[g])))
	var paid := 0.0
	var mk := markup()
	var dm := {}   # good -> [bought, unmet, unaffordable] (barge demand)
	for o in batch:
		var q: int = o[2]
		if q <= 0:
			continue
		var g: String = o[1]
		var from_barn: bool = o.size() > 5
		var n0 := int(float(q) * float(bratio[g] if from_barn else ratio[g]))
		var n := n0
		var f: Dictionary = o[0]
		var p: float = float(price[g]) * (float(o[5]) if from_barn else mk)
		var purse: float = f["purse"]
		if float(n) * p > purse - 1.0:
			n = int(maxf(0.0, purse - 1.0) / p)
		var src: Dictionary = barn if from_barn else st
		var have := HarvestClaims.available(e, g) if from_barn else int(src.get(g, 0))
		if n > have:
			n = have
		n = maxi(n, 0)
		var a: Array = dm.get(g, [0.0, 0.0, 0.0])
		a[0] += float(n)
		if not from_barn:   # a family short at the barn buys the rest at the market (its own order)
			a[1] += float(q - n0); a[2] += float(n0 - n)
		dm[g] = a
		if n <= 0:
			continue
		f["purse"] = purse - float(n) * p
		if from_barn:
			var taken := HarvestClaims.take(e, g, n)
			HarvestClaims.credit(e, taken["shares"], float(n) * p)
		else:
			src[g] = have - n
			paid += float(n) * p
		match o[3]:
			"home":
				if f.has("lodging"): TownHousing.leave(e, f, float(e["day"]))
				f["homes"] = int(f["homes"]) + n
				e["homes"] = int(e["homes"]) + n
				led(e, "used", "home", n)
				if f["named"]:
					Families.add_hist(f, "Bought a new home.", float(e["day"]))
				continue
			"lux":
				led(e, "used", g, n)   # enjoyed at once
				continue
			"keep":   # v0.014: stones kept as stored wealth, the family's own (Legends.add_fam_gem; e.gh counts them)
				Legends.add_fam_gem(e, f, g, n)
				continue
			"wear":
				var w: Dictionary = f["wear"]
				w[g] = float(w[g]) - float(n)
			_:
				var s: Dictionary = f["store"]
				s[o[3]] = float(s[o[3]]) + float(n) / float(o[4])
		hh[g] = int(hh.get(g, 0)) + n
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	mkt["till"] = float(mkt["till"]) + paid
	e["stats"]["sales"] = float(e["stats"]["sales"]) + paid
	for g in dm:
		Barge.add_demand(e, g, dm[g][0], dm[g][1], dm[g][2])
	batch.clear()

## Coin for barn goods sold straight to families: to the farm till, legacy per-acre/head money-only settlement. Physical sales use HarvestClaims.
static func _barn_paid(e: Dictionary, g: String, val: float) -> void:
	if g == "fodder":
		Herds.fodder_paid(e, val)   # herds: hay to the meadows, straw to the grain land, by what each gives
		return
	var key: String = g if g in ["grain", "fruit", "flax"] else "herd"
	var wt := 0.0
	if key == "herd":
		for a in e["herd"]:
			wt += float(e["herd"][a])
	else:
		wt = float(e["land"].get(key, 0))
	if wt <= 0.0:
		e["treasury"] = float(e["treasury"]) + val
	else:
		e["farm_till"] = float(e["farm_till"]) + val
		e["cum"][key] = float(e["cum"].get(key, 0.0)) + val / wt

# ================================================================== the daily town pass
## The town's market day. with_barge: also its barge day (prices, books, labour, coin: barge_day) at once, as a
## direct call wants; the work queue runs the barge day as its own job (one map frame each).
static func daily_pass(game, town: Dictionary, day: int, with_barge: bool = true) -> void:
	if not has_econ(town):
		return
	var e: Dictionary = town["econ"]
	if int(e.get("day", -1)) >= day:
		return
	_market_day(game, town, e, day)
	if with_barge:
		barge_day(game, town, day)

static func _market_day(game, town: Dictionary, e: Dictionary, day: int) -> void:
	e["day"] = day
	WageClaims.accrue_day(e, day)
	Shelter.accrue_sanitation(e, float(day))
	var D := data()
	var si := Calendar.season_index(float(day))
	var clim: Dictionary = D["climates"][e["climate"]]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(game.world.get("seed", 0)), town["id"], day, "econ"])
	var nd: Dictionary = D["needs"]
	e["wf"] = float(nd["firewood_home"]) * float(nd["firewood_season"][si]) * float(clim["firewood"])   # firewood per home today
	e["hdecay"] = float(culture_of(e)["home"]["decay"])
	var t0 := Time.get_ticks_usec() if prof_on else 0
	if not e.has("cin"):
		e["cin"] = {}
	e["hf_now"] = Barge.harvest_factor(game.world, e, String(town["id"]), float(day))
	_farms(e, D, si, clim)
	_barn_sales(e, D)
	HarvestClaims.pay_departed(e)
	if prof_on: t0 = _prof("farms+barns", t0)
	Businesses.daily(game, town, e, D, si, rng)
	WageClaims.pay_former(e)
	if prof_on: t0 = _prof("businesses", t0)
	_households(e, D, si, clim)
	if prof_on: t0 = _prof("households", t0)
	if (day + absi(hash(String(town["id"])))) % SPOIL_EVERY == 0:   # spoilage in 3-day steps (same totals, a third of the work)
		_spoil(e, D, si, clim, float(SPOIL_EVERY))
	# know-how fades slowly when nobody works the material
	for m in e["knowhow"]:
		if int(e.get("kh_used", -99)) < day - 7:
			e["knowhow"][m] = maxf(0.0, float(e["knowhow"][m]) - float(D["knowhow"][m]["decay"]))
	if prof_on: t0 = _prof("spoil", t0)
	BowsEcon.econ_daily(game, town, e, D)   # bows: staves season, fowl feathers, the head's armory (orders, buys, refills)
	if prof_on: t0 = _prof("bows", t0)
	Shelter.daily(town, e)   # the poorhouse: broth, firewood and keepers, paid by the treasury
	Army.pay_town(game, town)   # militia / town guard: rank wages into their family purses (economy spec 2)
	if prof_on: t0 = _prof("shelter+army", t0)

## The town's barge day (its own work job, right after its market day: the day's books close): the granary (barge
## part 4 section 2), the day's prices (part 2 section 2), the businesses' books (part 3 section 6), the labour market
## and the day wage (part 3 section 1), the coin pass (the drain on tills and the treasury, the mint, melting: part 1).
static func barge_day(game, town: Dictionary, day: int) -> void:
	if not has_econ(town):
		return
	var e: Dictionary = town["econ"]
	if int(e.get("bday", -1)) >= day or int(e.get("day", -1)) < day:
		return
	e["bday"] = day
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(game.world.get("seed", 0)), town["id"], day, "barge"])
	var t0 := Time.get_ticks_usec() if prof_on else 0
	Barge.town_stage_day(e)   # barge part 4 section 5: the town's famine stage (from the market day's food shortfall)
	Barge.granary_day(game, town, e, float(day))
	Barge.update_prices(town, rng)
	if prof_on: t0 = _prof("prices", t0)
	Businesses.books_day(e)
	Businesses.prep_day(e)   # tomorrow's margins and makers' aims from today's prices
	Businesses.bid_day(e)   # family trades' pay: the table, or a bid for hands when their goods are scarce
	if prof_on: t0 = _prof("books", t0)
	Barge.labour_day(e, Calendar.season_index(float(day)))
	Barge.coin_town(game, town, e)
	if prof_on: t0 = _prof("labour+coin", t0)

## Dev profiling of the daily pass (tests/test_econ_town.gd perf section prints it).
static var prof_on := false
static var prof: Dictionary = {}
static func _prof(k: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	prof[k] = int(prof.get(k, 0)) + t1 - t0
	return t1

## Fields give their harvest over the harvest season (a share of the grain goes to the granary as tax in
## kind); herds give meat (autumn slaughter peak), wool and hides every day. Everything goes to the barns.
static func _farms(e: Dictionary, D: Dictionary, si: int, clim: Dictionary) -> void:
	HarvestClaims.ensure(e)
	# Rotation can change base work without changing nominal acreage or rounded
	# hired capacity. Recompute future output from real existing hands before a
	# new year's harvest; ordinary family turns still perform funded matching.
	for f in e["fams"]:
		if f.has("work_crop_year") and int(f["work_crop_year"]) != Calendar.year(float(e.get("day", 0))):
			Families.refresh_worked(e, f)
	var L: Dictionary = D["land"]
	var carry: Dictionary = e["carry"]
	var hh: Dictionary = e["hh"]
	var toolf := 0.75 + 0.25 * minf(1.0, float(hh.get("tools", 0)) / maxf(1.0, float(e.get("hands", 0)) + float(e["adults"]) * 0.3))
	e["farm_toolf"] = toolf
	# barge part 2 section 4: two grain cuts a year (early grain in summer, autumn grain), fruit between; x the year's
	# harvest factor. The granary takes 5% of the grain and, where the ruler takes tribute in kind, that share too.
	var HS: Dictionary = L["harvest_seasons"]
	var hf := float(e.get("hf_now", 1.0))
	var gtax := float(D["tax"]["grain_share"])
	var ruler: Dictionary = e.get("ruler", {})
	if String(ruler.get("kind", "coin")) == "kind":
		gtax += float(ruler.get("tribute", 0.0))
	for crop in e["wacres"]:
		var cut := 0.0
		for s in HS.get(crop, [[int(L["harvest_season"]), 1.0]]):
			if int(s[0]) == si:
				cut += float(s[1])
		if cut <= 0.0:
			continue
		var y := CropRotation.harvest_yield(e, String(crop)) * cut * hf * Herds.manure_f(e)   # herds: the fields the dung covers yield more
		if crop == "grain":
			y *= float(clim["grain_yield"])
			Herds.straw(e, CropRotation.cereal_acres(e) * cut * hf / float(Calendar.DAYS_PER_SEASON))   # herds: the cut's straw is fodder (the year's weather too)
		elif crop == "fruit":
			y *= float(clim["fruit_yield"])
		var k: String = "h_" + crop
		var previous := float(carry.get(k, 0.0))
		# Incremental worked-acre updates can leave a negative floating residue
		# when the last real hand stops. Flooring that residue makes -1 and a
		# fictitious near-whole carry. Physical production cannot be negative.
		var produced := maxf(0.0, float(e["wacres"][crop])) * y * toolf / float(Calendar.DAYS_PER_SEASON)
		var amt := produced + previous
		var n := int(floor(amt))
		carry[k] = amt - n
		var gt := int(floor(float(n) * gtax)) if crop == "grain" else 0
		if n > 0:
			led(e, "made", crop, n)
			e["granary"] = int(e["granary"]) + gt
		var contributions := {}
		for f in e["fams"]:
			if f.get("gone", false): continue
			var weight := float(f["land"].get(crop, 0.0)) * float(f.get("worked", 0.0)) * CropRotation.family_yield(e, f, String(crop))
			if weight > 0.0: contributions["f:%d" % int(f["id"])] = weight
		HarvestClaims.harvest(e, String(crop), k, contributions, produced, n, gt, previous, int(e.get("day", 0)))
	HarvestClaims.reserve_all(e)
	Herds.day(e)   # herds (addendum 1 B): the day's milk, wool, eggs, honey and wax the market paid the owners for this week

## The market buys from the barns what it needs to stay stocked (the original producers are paid from their dated goods).
static func _barn_sales(e: Dictionary, D: Dictionary) -> void:
	var barn: Dictionary = e["barn"]
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var need: Dictionary = e.get("need", {})
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var share := float(D["market"]["broker_share"])   # barge part 4: the farms' surplus goes to a broker at 0.75 x P
	HarvestClaims.reserve_all(e)
	for g in barn:
		var have := HarvestClaims.available(e, String(g))
		if have <= 0:
			continue
		var want := int(float(need.get(g, 0.0)) * 1.2) - int(st.get(g, 0))
		if want <= 0:
			continue
		var p := float(price[g]) * share
		var q := mini(have, want)
		q = mini(q, int(maxf(0.0, float(mkt["till"])) / p))
		if q <= 0:
			continue
		var taken := HarvestClaims.take(e, String(g), q)
		st[g] = int(st.get(g, 0)) + q
		var val := float(q) * p
		mkt["till"] = float(mkt["till"]) - val
		mkt["spend"] = float(mkt["spend"]) + val
		HarvestClaims.credit(e, taken["shares"], val)

static var _perish: Array = []   # [good, spoil days, carry keys per holder]
const SPOIL_EVERY := 3
## Barge part 2 section 3 (FIX-1): each day stock x min(1, rate / perish days) spoils, the rate following the town's
## mean temperature (0.06 at -6 C .. 1.5 at 30 C): the cold north keeps meat, the hot south rots it. Market stalls,
## barns and households' larders alike (staples, drink and made goods keep). Run in 3-day steps.
static func _spoil(e: Dictionary, D: Dictionary, si: int, _clim: Dictionary, step_days: float = 1.0) -> void:
	var G: Dictionary = D["goods"]
	var rate := Barge.spoil_rate(Barge.temp(e, si))
	var carry: Dictionary = e["carry"]
	if _perish.is_empty():
		for g in G:
			if float(Barge.cat(g)["perish"]) > 0.0:
				_perish.append([g, 0.0, "stock" + g, "barn" + g, "hh" + g])
	for hi in 3:
		var s: Dictionary = e[["stock", "barn", "hh"][hi]]
		for p in _perish:
			var g: String = p[0]
			var have := int(s.get(g, 0))
			if have <= 0:
				continue
			var fr := 1.0 - pow(1.0 - Barge.spoil_frac(g, rate), step_days)
			var k: String = p[2 + hi]
			var amt := float(have) * fr + float(carry.get(k, 0.0))
			var n := mini(have, int(floor(amt)))
			carry[k] = amt - n
			if n > 0:
				if hi == 1: HarvestClaims.lose(e, g, n)
				else: s[g] = have - n
				led(e, "spoil", g, n)
				if g in ["grain", "fruit", "meat", "fresh_meat", "milk"]: TownSanitation.add_waste(e, float(n) * float(Goods.table().get(g, {}).get("weight", 0.4)), "rotting")

## Daily consumption over town totals (spec 4): the households eat, drink and burn firewood out of the
## household pool (e.hh: what the families have bought, summed), by the diet mix; a food that runs short is
## covered by the others at cover_eff. Clothes, blankets, tools and household goods wear out. The share of
## the need not met is e.food_short (families going hungry at their turns).
static func _households(e: Dictionary, D: Dictionary, si: int, clim: Dictionary) -> void:
	var nd: Dictionary = D["needs"]
	var hh: Dictionary = e["hh"]
	var carry: Dictionary = e["carry"]
	var lu: Dictionary = e["led"]["used"]
	var pop := float(e["pop"])
	# barge: children eat 0.6-0.8 of a grown-up's share; the meals come out of what the households hold, whatever
	# mix they bought (staples by their race's taste, meat and produce as they could afford)
	var food_need := Barge.household_eaters(e, float(e.get("day", 0))) * float(nd["food"])
	var have_all := 0.0
	for k in Families.HOUSEHOLD_FOOD:
		have_all += float(hh.get(k, 0))
	var missing := maxf(0.0, food_need - have_all)
	if have_all > 0.0:
		for k in ["fresh_meat", "meat", "fruit", "grain"]:
			var want := minf(food_need, have_all) * float(hh.get(k, 0)) / have_all + float(carry.get("eat" + k, 0.0))
			var n := mini(int(hh.get(k, 0)), int(floor(want)))
			carry["eat" + k] = clampf(want - float(n), 0.0, 1.0)
			if n > 0:
				hh[k] = int(hh[k]) - n
				lu[k] = int(lu.get(k, 0)) + n
	e["food_short"] = missing / maxf(1.0, food_need)
	# drink (the town's beer and its fruit drink), firewood
	var drink := float(e["adults"]) * float(nd["drink_adult"]) + float(carry.get("drink", 0.0))
	var dn := int(floor(drink))
	carry["drink"] = drink - dn
	var b := mini(dn, int(hh.get("beer", 0)))
	if b > 0:
		hh["beer"] = int(hh["beer"]) - b
		lu["beer"] = int(lu.get("beer", 0)) + b
	var wn := mini(dn - b, int(hh.get("wine", 0)))
	if wn > 0:
		hh["wine"] = int(hh["wine"]) - wn
		lu["wine"] = int(lu.get("wine", 0)) + wn
	var homes := float(e["homes"])
	var wood := homes * float(nd["firewood_home"]) * float(nd["firewood_season"][si]) * float(clim["firewood"]) + float(carry.get("fire", 0.0))
	var fn := int(floor(wood))
	carry["fire"] = wood - fn
	var fw := mini(fn, int(hh.get("wood", 0)))
	if fw > 0:
		hh["wood"] = int(hh["wood"]) - fw
		lu["wood"] = int(lu.get("wood", 0)) + fw
	e["cold"] = fn - fw
	# wear: clothes per person, tools per adult, blankets and household goods per home, jewelry of the rich
	var wd: Dictionary = nd["wear_days"]
	for g in wd:
		var basis := pop if g == "clothing" else (float(e["adults"]) if g == "tools" else (float(e.get("rich", 0)) if g == "jewelry" else homes))
		var amt := basis / float(wd[g]) + float(carry.get("w" + g, 0.0))
		var n2 := int(floor(amt))
		carry["w" + g] = minf(amt - n2, 2.0)
		var t := mini(n2, int(hh.get(g, 0)))
		if t > 0:
			hh[g] = int(hh[g]) - t
			lu[g] = int(lu.get(g, 0)) + t

## Daily household use of each good (people, adults, homes, season, climate): the opening demand, and the
## town screen's days-of-supply.
static func household_use(e: Dictionary, si: int, goods: Array = []) -> Dictionary:
	var D := data()
	var nd: Dictionary = D["needs"]
	var clim: Dictionary = D["climates"][e["climate"]]
	var pop := float(e["pop"]); var ad := float(e["adults"]); var homes := float(e["homes"])
	var bs := EconGen.beer_share_of(e)
	var wd: Dictionary = nd["wear_days"]
	var room := float(D["cultures"][e["culture"]]["home"]["room"])
	var out := {"beer": ad * float(nd["drink_adult"]) * bs, "wine": ad * float(nd["drink_adult"]) * (1.0 - bs),
		"wood": homes * float(nd["firewood_home"]) * float(nd["firewood_season"][si]) * float(clim["firewood"]),
		"clothing": pop / float(wd["clothing"]), "blankets": homes / float(wd["blankets"]), "tools": ad / float(wd["tools"]),
		"furniture": homes / float(wd["furniture"]), "jewelry": float(e.get("rich", 0)) / float(wd["jewelry"]),
		"home": maxf(0.0, pop - homes * room) / room / 14.0 + 0.02}
	if goods.is_empty() or goods.has("grain") or goods.has("fruit") or goods.has("meat"):
		var dt := Barge.diet(e)
		var meal_shares := Barge.household_eaters(e, float(e.get("day", 0)), false)
		var food := {}
		for good in ["grain", "fruit", "meat"]:
			food[good] = meal_shares * float(dt[good])
		food.merge(out)
		out = food
	if not goods.is_empty():
		for good in out.keys():
			if not goods.has(good): out.erase(good)
	return out

## Prices from the actors' orders against the stock (spec 4): demand = what families ordered today (their own
## targets: days of food, drink, firewood; their share of worn goods) + what businesses wanted for inputs
## (only businesses that run: a town without a smelter wants no ore) + the head's granary, smoothed over
## about a week. need = demand x the market's days of cover (goods row "target", else needs.target_days).
## price = base x clamp((need / stock)^0.5, min, max): below target the price rises, above it falls.
static func update_prices(town: Dictionary, _si: int) -> void:
	# barge part 2 section 2 (campaign/barge.gd); the old supply/need rule below stays only for world gen's first prices
	if town["econ"].has("dem") and town["econ"]["price"].size() > 0:
		var r := RandomNumberGenerator.new()
		r.seed = hash([String(town.get("id", "")), int(town["econ"].get("day", 0)), "prices"])
		Barge.update_prices(town, r, true)
		return
	_old_prices(town)

static func _old_prices(town: Dictionary) -> void:
	var e: Dictionary = town["econ"]
	if _pg.is_empty():
		var D := data()
		var G: Dictionary = D["goods"]
		var td := float(D["needs"]["target_days"])
		_pmin = float(D["price_min"]); _pmax = float(D["price_max"])
		for g in G:
			_pg.append(g); _pbase.append(float(G[g]["price"])); _ptd.append(float(G[g].get("target", td)))
	var req: Dictionary = e["req"]
	var bdem: Dictionary = e.get("bdem", {})
	var dem: Dictionary = e["dem"]
	var st: Dictionary = e["stock"]
	var barn: Dictionary = e["barn"]
	var price: Dictionary = e["price"]
	var need: Dictionary = e["need"]
	for i in _pg.size():
		var g: String = _pg[i]
		var d0: float = dem.get(g, 0.0)
		var d1: float = d0 + (float(req.get(g, 0.0)) + float(bdem.get(g, 0.0)) - d0) * 0.15
		dem[g] = d1
		var nd: float = d1 * _ptd[i]
		need[g] = nd
		var s: float = float(st.get(g, 0)) + float(barn.get(g, 0))
		price[g] = _pbase[i] * clampf(sqrt(maxf(nd, 0.5) / maxf(s, 0.5)), _pmin, _pmax)
	req.clear()

static var _pg: Array = []
static var _pbase := PackedFloat64Array()
static var _ptd := PackedFloat64Array()
static var _pmin := 0.5
static var _pmax := 3.0

## Weekly: one reason line per good whose price moved since last week ("swords up: smith idle, no bars").
static func update_reasons(town: Dictionary, si: int) -> void:
	var e: Dictionary = town["econ"]
	var why: Dictionary = e["why"]
	var pweek: Dictionary = e.get("pweek", {})
	var price: Dictionary = e["price"]
	for g in price:
		var p := float(price[g])
		var old := float(pweek.get(g, p))
		if p > old * 1.12:
			why[g] = _reason(town, e, g, true, si)
		elif p < old * 0.88:
			why[g] = _reason(town, e, g, false, si)
		elif absf(p - old) < old * 0.04:
			why.erase(g)

static func _producers(e: Dictionary, g: String) -> Array:
	var D := data()
	var out := []
	for b in e["biz"]:
		if b.get("closed", false):
			continue
		var T: Dictionary = D["businesses"][b["type"]]
		if b["type"] == "butcher" and g in ["fresh_meat", "hides", "tallow", "bones", "horn", "sinew"]:
			out.append(b)
			continue
		if b["type"] == "mine" and b.get("ore", "") == g:
			out.append(b)
			continue
		for r in T["recipes"]:
			if (r["out"] as Dictionary).has(g):
				out.append(b)
				break
	return out

static func _reason(town: Dictionary, e: Dictionary, g: String, up: bool, si: int) -> String:
	var name := label(e, g)
	var dir := "up" if up else "down"
	var hint: String = e.get("why_hint", {}).get(g, "")
	if hint != "" and up:
		e["why_hint"].erase(g)
		return "%s %s: %s" % [name, dir, hint]
	if g in ["grain", "fruit", "flax"]:
		if up:
			var w := float(e["wacres"].get(g, 0.0)) / maxf(1.0, float(e["land"].get(g, 0)))
			if w < 0.8:
				return "%s up: farms short-handed" % name
			return "%s up: waiting for the harvest" % name if si != int(data()["land"]["harvest_season"]) else "%s up: a thin harvest" % name
		return "%s down: the harvest is in" % name
	if g in ["meat", "wool", "hides"] and not up and si == 2:
		return "%s down: slaughtering season" % name
	var prods := _producers(e, g)
	if up:
		if prods.is_empty():
			return "%s up: nobody here makes it" % name
		for b in prods:
			match b["state"]:
				"inputs":
					var miss: String = b.get("why", "")
					return "%s up: %s idle, no %s" % [name, data()["businesses"][b["type"]]["name"], label(e, miss) if miss != "" else "materials"]
				"hands":
					return "%s up: %s short-handed" % [name, data()["businesses"][b["type"]]["name"]]
				"wages":
					return "%s up: %s can't pay wages" % [name, data()["businesses"][b["type"]]["name"]]
		return "%s up: more buyers than sellers" % name
	if float(e.get("stock", {}).get(g, 0)) >= Businesses.stock_cap(e, g) * 0.9:
		return "%s down: stalls full" % name
	return "%s down: market price fell" % name

# ================================================================== supply levels (food spec hook)
static func days_food(town: Dictionary) -> float:
	if not has_econ(town):
		return 30.0
	var e: Dictionary = town["econ"]
	var f := float(e["granary"])
	for g in ["grain", "fruit", "meat"]:
		f += float(e["stock"].get(g, 0)) + float(e["barn"].get(g, 0)) + float(e["hh"].get(g, 0))
	f += float(e["hh"].get("fresh_meat", 0))
	return f / maxf(1.0, float(e["pop"]) * float(data()["needs"]["food"]))

static func days_drink(town: Dictionary) -> float:
	if not has_econ(town):
		return 30.0
	var e: Dictionary = town["econ"]
	var d := 0.0
	for g in ["beer", "wine"]:
		d += float(e["stock"].get(g, 0)) + float(e["hh"].get(g, 0))
	return d / maxf(1.0, float(e["adults"]) * float(data()["needs"]["drink_adult"]))

## "well" (> 14 days of food and drink), "short" (3-14), "starving" (< 3). Food spec reads it at battle spawn
## for armies from this town and for its militia.
static func supply_level(town: Dictionary, food_days: Variant = null) -> String:
	if not has_econ(town):
		return "well"
	var D := data()
	# A records build may already have read this exact town's food days for its totals.
	var df := days_food(town) if food_days == null else float(food_days)
	var dd := days_drink(town)
	if df < float(D["supply_short"]):
		return "starving"
	if df <= float(D["supply_well"]) or dd < float(D["supply_short"]):
		return "short"
	return "well"

static func supply_word(level: String) -> String:
	return {"well": "well supplied", "short": "short", "starving": "starving"}.get(level, level)

## Supply level of a force: its home town's (forces carry no daily sim).
static func force_supply(w: Dictionary, wb: Dictionary) -> String:
	var t: Dictionary = w.get("towns", {}).get(str(wb.get("home", "")), {})
	return supply_level(t) if not t.is_empty() else "well"

# ================================================================== arms stock API (militia, forces, menus)
## The town's arms stock as a sparse dict {"tid|material|quality": count} (the Items themselves are town["shop"]).
static func arms_stock(town: Dictionary) -> Dictionary:
	var out := {}
	for it in town.get("shop", []):
		var k := "%s|%s|%d" % [it.tid, it.material, it.quality]
		out[k] = int(out.get(k, 0)) + 1
	return out

## Pieces in stock (optionally of one equip slot: main_hand, off_hand, helm, body, ...).
static func arms_count(town: Dictionary, slot: String = "", quality_min: int = 0) -> int:
	var n := 0
	for it in town.get("shop", []):
		if (slot == "" or it.slot() == slot) and it.quality >= quality_min:
			n += 1
	return n

## Takes up to n pieces out of the town's arms stock (best quality first), optionally only of one slot or
## template. The town treasury pays the market for them (pay = false: no gold moves, e.g. tests or loot).
## Returns the Items; they now belong to the caller (a militia, a force). Monsters own nothing.
static func take_arms(town: Dictionary, n: int, quality_min: int = 0, slot: String = "", tid: String = "", pay: bool = true) -> Array:
	var shop: Array = town.get("shop", [])
	var cands := []
	for it in shop:
		if it.quality < quality_min:
			continue
		if slot != "" and it.slot() != slot:
			continue
		if tid != "" and it.tid != tid:
			continue
		cands.append(it)
	cands.sort_custom(func(a, b): return a.quality > b.quality if a.quality != b.quality else a.material < b.material)
	var out := []
	var e: Dictionary = town.get("econ", {})
	for it in cands:
		if out.size() >= n:
			break
		if pay and has_econ(town):
			var p := Economy.base_value(town, it)
			if float(e["treasury"]) < p:
				break
			e["treasury"] = float(e["treasury"]) - p
			var mkt: Dictionary = e["biz"][int(e["mkt"])]
			mkt["till"] = float(mkt["till"]) + p
			e["stats"]["sales"] = float(e["stats"]["sales"]) + p
		shop.erase(it)
		out.append(it)
		if has_econ(town):
			led(e, "used", "arms", 1)
	return out

## Re-equips units from the town's arms stock: each unit keeps the template it was rolled with when the
## stock has one, else any piece for that slot, else goes without. Spawned gear is discarded (never existed).
## At most `share` of the stock goes to one force so the stalls are not stripped bare.
## Arms trade: a town force's men take from the head's armory first (armory_first; merchants' caravan guards buy
## off the stalls only), any piece for that slot and role when the template is short (foreign makes included).
## World size (CampaignWorld's muster, a few men a job): budget >= 0 is what is left of the force's share (set from the
## stalls when its first men were outfitted); quivers false leaves the arrows to the last call (all the men at once).
static func outfit_units(town: Dictionary, units: Array, share: float = 0.5, armory_first: bool = true, budget: int = -1, quivers: bool = true) -> int:
	if budget < 0:
		budget = int(floor(float((town.get("shop", []) as Array).size()) * share))
	var got := 0
	for u in units:
		for slot in u.equip.keys():
			var want: Item = u.equip[slot]
			u.equip.erase(slot)
			if armory_first:
				var ai := ArmsTrade.take_for(town, want.tid, slot)
				if ai != null:
					u.equip[slot] = ai
					continue
			if got >= budget:
				continue
			var picked := take_arms(town, 1, 0, "", want.tid)
			if picked.is_empty():
				picked = take_arms(town, 1, 0, slot)
			if not picked.is_empty():
				var it: Item = picked[0]
				if it.slot() == slot and not (slot == "off_hand" and u.weapon() != null and u.weapon().tmpl().get("two_handed", false)):
					u.equip[slot] = it
					got += 1
				else:
					(town["shop"] as Array).append(it)   # does not fit him: back on the stalls
	if quivers:
		BowsEcon.fill_quivers(town, units)   # bows: quivers from the town's arrows (shortfall ordered)
	return got

## Battle scrap (core/loot.gd result["scrap_kg"] {material: kg}) sold by the company's quartermaster: it lands
## in the nearest town's market stock as scrap metal (1 unit = 1 kg; smelters turn it back into bars).
## Returns the town id ("" when none).
static func add_scrap(w: Dictionary, scrap: Dictionary, pos: Vector2) -> String:
	if scrap.is_empty():
		return ""
	var best := ""; var bd := INF
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not has_econ(t):
			continue
		var d := (t["pos"] as Vector2).distance_to(pos)
		if d < bd:
			bd = d; best = tid
	if best == "":
		return ""
	var e: Dictionary = w["towns"][best]["econ"]
	for m in scrap:
		var g := "scrap_" + String(m)
		if not data()["goods"].has(g):
			continue   # cloth and leather rags are not worth carting
		var n := int(round(float(scrap[m])))
		if n > 0:
			e["stock"][g] = int(e["stock"].get(g, 0)) + n
			led(e, "made", g, n)   # an inflow from the battlefield
	return best

# ================================================================== weekly town turn
static func town_turn(game, town: Dictionary, day: int) -> void:
	if not has_econ(town):
		return
	var e: Dictionary = town["econ"]
	var D := data()
	var w: Dictionary = game.world
	var T: Dictionary = D["tax"]
	var tx: Dictionary = e["tax"]
	var stamp := season_stamp(float(day))
	var biz: Array = e["biz"]
	var mkt: Dictionary = biz[int(e["mkt"])]
	var fams: Array = e["fams"]
	TownSanitation.weekly(e, float(day))
	TownHousing.weekly(e, float(day))
	Shelter.weekly(game, town, e)   # poorhouse head count, casual places from what the town needs
	# a new tax season
	if stamp != int(tx["season"]):
		tx["season"] = stamp
		tx["last_paid"] = float(tx.get("paid", 0.0))
		tx["paid"] = 0.0
		tx["owed"] = 0.0
		var ph: Array = e["stats"]["pop_hist"]
		ph.append(int(e["pop"]))
		while ph.size() > 8:
			ph.pop_front()
		# the season's census: births and deaths since the last one (People.census)
		var st: Dictionary = e["stats"]
		st["bd_last"] = [int(st.get("births", 0)) - int(st.get("births_at", 0)), int(st.get("deaths", 0)) - int(st.get("deaths_at", 0))]
		st["births_at"] = int(st.get("births", 0))
		st["deaths_at"] = int(st.get("deaths", 0))
	# collectors: the head hires one per collector_per families; missing ones leak tax
	var live := int(Population.household_stats(e)["households"])
	for b in biz:
		if b["type"] == "collector":
			b["cap"] = maxi(1, int(ceil(float(live) / float(T["collector_per"]))))
			tx["leak"] = float(T["leak_max"]) * (1.0 - minf(1.0, float(b["workers"]) / float(b["cap"])))
	# (barge part 4 section 1: the month's taxes run as their own job on the town's tax day: "tmonth")
	Barge.pay_week(e)   # the pay table moves with PL^0.8
	# the market's sales tax (barge: 3% of shop takings)
	var mtax := minf(float(e["stats"]["sales"]) * float(D["market"]["tax"]), maxf(0.0, float(mkt["till"])))
	mkt["till"] = float(mkt["till"]) - mtax
	e["treasury"] = float(e["treasury"]) + mtax
	e["stats"]["mtax"] = mtax
	e["stats"]["sales_week"] = float(e["stats"]["sales"])
	e["stats"]["sales"] = 0.0
	# the town's own fields: claims to the treasury, hired hands work them
	var est: Dictionary = fams[0]
	Families.settle(e, est)
	var eb: Dictionary = biz[int(e["estate_biz"])]
	var need := Families.need_hands(est, e)
	var seasonal_need := Families.seasonal_need_hands(est, float(day), e)
	eb["cap"] = maxi(0, int(ceil(seasonal_need - 0.2)))
	Families.set_worked(e, est, minf(1.0, float(eb["workers"]) / need) if need > 0.0 else 0.0)
	# land and businesses for sale (the land loop: only if no family buys does the town work it)
	_sell_land(e, D, float(day))
	_sell_businesses(e, float(day))
	# public works: with money above its reserve the head takes on idle hands (walls, roads, wells) [ours]
	if e.has("works_biz"):
		var wb2: Dictionary = biz[int(e["works_biz"])]
		var idle := 0
		for f in fams:
			if not f["gone"]:
				idle += int(f.get("idle", 0))
		var lines := Barge.treasury_lines(e)
		var afford := int(maxf(0.0, float(e["treasury"]) - float(lines["short"])) * 0.5 / maxf(1.0, float(wb2["wage"]) * 14.0))
		# barge part 4 section 1: "public works more when rich (a great work hires extra day labour)": over its full line
		# the treasury hires day labour beyond the idle with half of what it holds over the line (two weeks' wages);
		# the posts are day work in the labour market (Barge.labour_day), so the day wage feels them
		var great := int(maxf(0.0, float(e["treasury"]) - float(lines["full"])) * 0.5 / maxf(1.0, float(wb2["wage"]) * 14.0))
		wb2["cap"] = maxi(mini(idle + int(wb2["workers"]) + great, afford), 0)
	# the mint keeps its minters while there are bars to cast (and the treasury is not full) [ours]
	if e.has("mint_biz"):
		var mbz: Dictionary = biz[int(e["mint_biz"])]
		mbz["cap"] = int(Barge.B()["coin"]["minters"]) if Barge.mint_bars(e) and float(e["treasury"]) < float(Barge.treasury_lines(e)["full"]) else 0
	fund_public_services(e)
	# These capacity and real treasury transfers run after today's family
	# batches. Let idle civilians see their funded offers before the recount.
	Families.match_idle(e)
	var wage_bill := 0.0
	for b in biz:
		if _town_funded(b) and not b.get("closed", false):
			wage_bill += float(b["workers"]) * float(b["wage"])
	e["stats"]["town_wages"] = wage_bill
	# (the granary: barge part 4 section 2, daily: Barge.granary_day)
	# wealthy families (jewelry buyers); the poor's hunger (the gruel kitchen opens above 0.3)
	# and the counts the daily pass reads (idle grown-ups, children, the coin in purses: Barge.recount_week)
	var idle_n := 0; var kids_n := 0; var purses := 0.0
	for f in fams:
		purses += float(f["purse"])
		if f["gone"] or f.has("estate"):
			continue
		idle_n += int(f.get("idle", 0))
		kids_n += int(f["kids"])
		Barge.klass(f)   # barge: the family's class follows its savings
	var households := Population.household_stats(e)
	e["rich"] = int(households["rich"])
	e["poor_hunger"] = float(households["poor_hungry"]) / maxf(1.0, float(households["poor"]))
	e["idle_n"] = idle_n
	e["kids_n"] = kids_n
	e["purses_n"] = purses
	# a new head if the old family is gone
	var hf: Dictionary = fams[int(e["head"]["fam"])]
	if hf.get("gone", false):
		var nh := Families.richest(e)
		var rr := RandomNumberGenerator.new(); rr.seed = hash([town["id"], day, "head"])
		var race: String = D["cultures"][e["culture"]]["race"]
		e["head"]["fam"] = nh
		e["head"]["name"] = Families.person_name(fams[nh], rr, race)
		fams[nh]["named"] = true
		town_hist(e, "%s of the %s family is the new %s." % [e["head"]["name"], fams[nh]["name"], e["head"]["title"]], float(day))
	# public works: the head spends a share of the treasury above its reserve on stone, wood and tools for
	# walls, roads and wells (bought at the market, used up) [ours]
	# barge: public works more when rich: a share of what the treasury holds above its full line
	var reserve := float(Barge.treasury_lines(e)["full"]) + float(e["stats"].get("town_wages", 0.0)) * 21.0
	var budget := (float(e["treasury"]) - reserve) * float(T.get("works_share", 0.2))
	e["stats"]["works"] = 0.0
	if budget > 200.0:
		var spent := 0.0
		for g in ["stone", "wood", "tools"]:
			var p := float(e["price"][g])
			var q := mini(int(budget / 3.0 / p), int(e["stock"].get(g, 0)) / 4)
			if q <= 0:
				continue
			e["stock"][g] = int(e["stock"][g]) - q
			led(e, "used", g, q)
			e["req"][g] = float(e["req"].get(g, 0.0)) + float(q)
			spent += float(q) * p
		e["treasury"] = float(e["treasury"]) - spent
		mkt["till"] = float(mkt["till"]) + spent
		e["stats"]["works"] = spent
	# trade: send a caravan with the surplus where it is wanted
	_plan_trade(game, town, e, day)
	# reasons for the week's price moves, then the snapshot the arrows on the town screen compare against
	update_reasons(town, Calendar.season_index(float(day)))
	e["pweek"] = (e["price"] as Dictionary).duplicate()
	# the weekly hiring market: re-run the open-places list
	Businesses.rebuild_open(e)
	# the register against the map: people of this town whose unit is gone went home or died
	Persons.sweep_town(game, town, Persons.live_uids(game))

## Hands available to a new holding, without borrowing serving people, real
## shop keepers or adults already earning wages elsewhere. Helpers retain the
## existing child/elder rules; purchased acres must fit full physical base work.
static func _property_hands(e: Dictionary, f: Dictionary) -> float:
	var keepers := 0
	for bid in f.get("keeps", []):
		var b: Dictionary = e["biz"][int(bid)]
		if not b.get("closed", false) and int(b["owner"]) == int(f["id"]) and int(b.get("kw", 0)) > 0:
			keepers += 1
	var casual := 0
	for n in f.get("cj", {}).values(): casual += int(n)
	var free := maxi(0, Families.adults(f) - Families.serving(f) - keepers - Families.job_total(f) - casual)
	return float(free) + Barge.helper_hands(e, f, float(e.get("day", 0)))

static func _town_funded(b: Dictionary) -> bool:
	var funding := String(b.get("public_funding", ""))
	return funding == "town" or (funding == "" and int(b["owner"]) < 0)

## Native service contracts retain their real private operator. This closes
## only their treasury reserve gap, including protected earned wage claims.
## Academy keeps its existing realm/capital funding pass as its sole payer.
static func fund_public_services(e: Dictionary) -> float:
	var paid := 0.0
	for b in e["biz"]:
		if not _town_funded(b) or b.get("closed", false): continue
		var want := maxf(0.0, float(b.get("owed", 0.0))) + float(maxi(int(b["workers"]), int(b["cap"]))) * float(b["wage"]) * 14.0
		var gap := maxf(0.0, want - float(b["till"]))
		var self_paying: bool = String(b["type"]) == "mint" and Barge.mint_bars(e)
		if gap > 0.0 and (float(e["treasury"]) > 3.0 * gap or self_paying):
			var top := minf(gap, maxf(0.0, float(e["treasury"])))
			b["till"] = float(b["till"]) + top
			b["t_paid"] = float(b.get("t_paid", 0.0)) - top
			b["public_paid"] = float(b.get("public_paid", 0.0)) + top
			e["treasury"] = float(e["treasury"]) - top
			paid += top
	return paid

static func _purchase_acres(e: Dictionary, a: Dictionary, b: Dictionary, crop: String, limit: int) -> int:
	if limit <= 0: return 0
	var L: Dictionary = data()["land"]
	var budget := _property_hands(e, b)
	var herd := Families.herd_hands(b, e)
	var rows := CropRotation.work_acres(e, b)
	var active := 0.0
	var physical := 0.0
	for good in rows:
		active += float(rows[good]["active"])
		physical += float(rows[good]["active"]) + float(rows[good]["fallow"])
	var upkeep := float(L.get("fallow_upkeep_share", 0.25)) / float(L["acres_per_hand"])
	var nominal := Families.acres(b)
	if absf(physical - float(nominal)) > 0.000000001: return 0
	var source_rows := CropRotation.work_acres(e, a)
	var source: Dictionary = source_rows.get(crop, {})
	if absf(float(source.get("active", 0)) + float(source.get("fallow", 0)) - float(a["land"].get(crop, 0))) > 0.000000001: return 0
	# Optimistic all-fallow work is only a rejection bound, never the reported
	# worked denominator or the actual purchase's required work.
	if upkeep > 0.0:
		limit = mini(limit, int(floor(maxf(0.0, budget - herd) / upkeep + 0.000000001)) - nominal)
	var P: Dictionary = e.get("plots", {})
	var mine := []
	if not P.is_empty():
		mine = Plots.move_candidates(P, int(a["id"]), (P["crops"] as Array).find(crop))
	# Ox rounding, full plots and partial boundaries make work non-monotone in
	# the quantity. Search descending; cheap lower bounds avoid oversized copies.
	for n in range(limit, 0, -1):
		var mo := Families.land_oxen(a, n)
		var ox_work := Herds.move_work(e, int(a["id"]), "oxen", mo)
		if int(ox_work["heads"]) != mo: continue
		var target: Dictionary = b.duplicate()
		# The physical move writes an explicit buyer ox count whenever the
		# donor has draft animals, even when this small transfer rounds to zero.
		if int(a.get("ox", -1)) > 0 and Families.acres(a) > 0:
			target["ox"] = maxi(0, int(b.get("ox", 0))) + mo
		var minimum_active := active
		if not P.is_empty():
			var rem := n
			for pi in mine:
				var ac := int(P["ac"][pi])
				if rem > 0 and ac <= rem:
					rem -= ac
					if String(P["variety"][pi]) != "fallow": minimum_active += ac
		else:
			minimum_active += n
		var lower := Families._cultivation_hands(target, minimum_active) + (float(nominal + n) - minimum_active) * upkeep + herd + float(ox_work["hands"])
		if lower > budget + 0.000000001: continue
		var work := Plots.purchase_work(e, a, b, crop, n)
		if absf(float(work["acres"]) - float(nominal + n)) > 0.000000001: continue
		var need := Families._cultivation_hands(target, float(work["active"])) + float(work["fallow"]) * upkeep + herd + float(ox_work["hands"])
		if need <= budget + 0.000000001: return n
	return 0

static func _purchase_heads(e: Dictionary, a: Dictionary, b: Dictionary, animal: String, limit: int) -> int:
	var spare := _property_hands(e, b) - Families.need_hands(b, e)
	var per_hand := float(Herds.kind(animal).get("per_hand", data()["land"]["head_per_hand"]))
	limit = mini(limit, int(floor(maxf(0.0, spare) * per_hand * 2.0 + 0.000000001)))
	for n in range(limit, 0, -1):
		var care := Herds.move_work(e, int(a["id"]), animal, n)
		if int(care["heads"]) == n and float(care["hands"]) <= spare + 0.000000001: return n
	return 0

static func _sell_land(e: Dictionary, D: Dictionary, day: float) -> void:
	var est: Dictionary = e["fams"][0]
	if (est["land"] as Dictionary).is_empty() and (est["herd"] as Dictionary).is_empty():
		return
	var L: Dictionary = D["land"]
	var buyers := []
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false) or Population.is_cohort(f):
			continue
		if Families.keeps_stale(e, f): continue
		var spare := _property_hands(e, f) - Families.need_hands(f, e)
		if float(f["purse"]) > float(L["acre_price"]) + 40.0 * COIN and spare >= 0.5 and float(f.get("debt", 0.0)) <= 0.0:
			buyers.append(f)
	buyers.sort_custom(func(a, b): return float(a["purse"]) > float(b["purse"]))
	for f in buyers.slice(0, 5):
		for crop in est["land"].keys():
			var want_n := _purchase_acres(e, est, f, String(crop), int(est["land"][crop]))
			if want_n <= 0: continue
			Families.settle(e, f)
			var short := float(want_n) * float(L["acre_price"]) - (float(f["purse"]) - 40.0 * COIN)
			var credit := Loans.quote(e, f, ceilf(short)) if short > 0.0 and float(f.get("debt", 0.0)) <= 0.0 else 0.0
			var afford := int((float(f["purse"]) + credit - 40.0 * COIN) / float(L["acre_price"]))
			var n := want_n if afford >= want_n else _purchase_acres(e, est, f, String(crop), afford)
			if n <= 0:
				continue
			var cost := float(n) * float(L["acre_price"])
			var gap := maxf(0.0, cost - (float(f["purse"]) - 40.0 * COIN))
			if gap > 0.0: Loans.lend(e, f, ceilf(gap), "land", day)
			if float(f["purse"]) - cost < 40.0 * COIN: continue
			Families.move_land(e, est, f, crop, n)
			f["purse"] = float(f["purse"]) - cost
			e["treasury"] = float(e["treasury"]) + cost
			Families.add_hist(f, "Bought %d acres of %s from the town." % [n, variety_word(e, crop)], day)
			Families.reassign(e, f)
		for a in est["herd"].keys():
			var want_h := _purchase_heads(e, est, f, String(a), int(est["herd"][a]))
			if want_h <= 0: continue
			Families.settle(e, f)
			var afford2 := int((float(f["purse"]) - 40.0 * COIN) / float(L["head_price"]))
			var n2 := want_h if afford2 >= want_h else _purchase_heads(e, est, f, String(a), afford2)
			if n2 <= 0:
				continue
			Families.move_herd(e, est, f, a, n2)
			f["purse"] = float(f["purse"]) - float(n2) * float(L["head_price"])
			e["treasury"] = float(e["treasury"]) + float(n2) * float(L["head_price"])
			Families.reassign(e, f)

static func _sell_businesses(e: Dictionary, day: float) -> void:
	for b in e["biz"]:
		if not b.get("for_sale", false) or b.get("closed", false) or b["type"] == "farm":
			continue
		var price := (80.0 + float(b["cap"]) * 25.0) * COIN
		var best: Dictionary = {}
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false) or Population.is_cohort(f):
				continue
			if Families.adults(f) - Families.serving(f) <= (f.get("keeps", []) as Array).size():
				continue   # v0.014: a buyer needs a grown-up free to keep it
			if float(f["purse"]) > price + 40.0 * COIN and (best.is_empty() or float(f["purse"]) > float(best["purse"])):
				best = f
		if best.is_empty():
			continue
		best["purse"] = float(best["purse"]) - price
		e["treasury"] = float(e["treasury"]) + price
		b["owner"] = int(best["id"])
		b["for_sale"] = false
		(best["owns"] as Array).append(int(b["id"]))
		Families.add_hist(best, "Bought %s from the town." % Businesses.title(e, b), day)
		Families.reassign(e, best)   # v0.014: one of the buyers keeps it from today

## Reads shortages and surpluses: one caravan at a time per town, to the road partner where the margin on
## our surplus (and on what we lack, for the trip home) is best.
static func _plan_trade(game, town: Dictionary, e: Dictionary, day: int) -> void:
	var w: Dictionary = game.world
	if float(e["treasury"]) < 150.0 * COIN or Caravans.count(w) >= Caravans.max_caravans(w):
		return
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["kind"] == "caravan" and wb.get("origin", "") == town["id"]:
			return
	for job in w.get("work", []):
		if job[0] == "caravan" and job[1] == town["id"]:
			return
	var best := ""; var bv := 0.0
	for l in Caravans.trade_partners(w, town):
		var o: Dictionary = w["towns"].get(l["id"], {})
		if not has_econ(o):
			continue
		var v := Caravans.trade_value(town, o)
		if v > bv:
			bv = v; best = l["id"]
	if best != "" and bv > 40.0 * COIN:
		(w["work"] as Array).append(["caravan", town["id"], best])

# ================================================================== weekly faction turn
## Towns send a share of their treasury above a reserve to the faction; the faction's shortages and purse feed
## the existing diplomacy roll (spec 8): low treasury pushes toward peace, food or metal shortage toward a
## trade pact with a supplier or war on a weak holder. (Raided caravans already push via Diplomacy.)
static func faction_turn(game, day: int) -> void:
	var w: Dictionary = game.world
	var D := data()
	var T: Dictionary = D["tax"]
	var stats := {}
	for fid in w.get("factions", {}):
		var fac: Dictionary = w["factions"][fid]
		if not fac.has("treasury"):
			fac["treasury"] = 0.0
		var food := 0.0; var metal := 0.0; var n := 0
		# economy spec 2: the army levy. The realm asks its towns for what its field army will cost over the next
		# two weeks beyond what the war chest holds, by town size; each town pays what it can above a small
		# reserve (100 x (size + 1)). Short towns leave the army short: unpaid men walk home.
		var levy := maxf(0.0, Army.bill(game, fid) * 14.0 - float(fac["treasury"]))
		if levy > 0.0:
			var wsum := 0.0
			for tid in fac.get("towns", []):
				if has_econ(w["towns"].get(tid, {})):
					wsum += float(int(w["towns"][tid]["size"]) + 1)
			for tid in fac.get("towns", []):
				var tl: Dictionary = w["towns"].get(tid, {})
				if not has_econ(tl) or wsum <= 0.0:
					continue
				var el: Dictionary = tl["econ"]
				var ask := levy * float(int(tl["size"]) + 1) / wsum
				var can := minf(ask, maxf(0.0, float(el["treasury"]) - float(Barge.treasury_lines(el)["short"]) * 0.5))
				el["treasury"] = float(el["treasury"]) - can
				fac["treasury"] = float(fac["treasury"]) + can
				el["stats"]["army_levy"] = can
		for tid in fac.get("towns", []):
			var t: Dictionary = w["towns"].get(tid, {})
			if not has_econ(t):
				continue
			var e: Dictionary = t["econ"]
			n += 1
			# tribute to the realm: a share of what the treasury holds above its short line (barge part 4 section 1)
			var reserve := float(Barge.treasury_lines(e)["short"]) + float(e["stats"].get("town_wages", 0.0)) * 21.0
			var over := float(e["treasury"]) - reserve
			e["stats"]["to_faction"] = 0.0
			if over > 0.0:
				var send := over * float(T["faction_share"])
				e["treasury"] = float(e["treasury"]) - send
				fac["treasury"] = float(fac["treasury"]) + send
				e["stats"]["to_faction"] = send
			e["stats"]["to_faction_month"] = float(e["stats"].get("to_faction_month", 0.0)) * 0.75 + float(e["stats"]["to_faction"])
			food += days_food(t)
			var st: Dictionary = e["stock"]
			metal += float(st.get("copper_bars", 0) + st.get("tin_bars", 0) + st.get("bronze_bars", 0)) + float(st.get("copper_ore", 0) + st.get("tin_ore", 0)) * 0.5
		if n > 0:
			stats[fid] = {"food": food / n, "metal": metal / n, "treasury": float(fac["treasury"])}
			fac["econ"] = stats[fid]
	Academy.faction_turn(game, float(day))   # v0.012: each realm funds its research house (budget, staff, its lead)
	# the realm keeps a month of its army's pay (economy spec 2); a share of what is above that flows back to its
	# poorest towns [ours]
	for fid in w.get("factions", {}):
		var fac: Dictionary = w["factions"][fid]
		var keep := Army.bill(game, fid) * 30.0
		var give := maxf(0.0, float(fac.get("treasury", 0.0)) - keep) * float(T.get("faction_return", 0.25))
		var poor := []
		for tid in fac.get("towns", []):
			var t: Dictionary = w["towns"].get(tid, {})
			if has_econ(t):
				poor.append(t)
		if poor.is_empty() or give < 1.0:
			continue
		poor.sort_custom(func(a, b): return float(a["econ"]["treasury"]) < float(b["econ"]["treasury"]))
		var half := poor.slice(0, maxi(1, poor.size() / 2))
		for t in half:
			t["econ"]["treasury"] = float(t["econ"]["treasury"]) + give / half.size()
		fac["treasury"] = float(fac["treasury"]) - give
	_diplomacy_feed(w, stats)


static func _diplomacy_feed(w: Dictionary, stats: Dictionary) -> void:
	var dp = w.get("diplo")
	if dp == null:
		return
	var fl: Array = dp.get("factions", [])
	for a in stats:
		if not fl.has(a):
			continue
		var s: Dictionary = stats[a]
		var ntowns := maxf(1.0, float((w["factions"][a].get("towns", []) as Array).size()))
		# an empty purse makes peace look better
		if float(s["treasury"]) < 150.0 * COIN * ntowns:
			for b in Diplomacy.enemies_at_war(w, a):
				Diplomacy._push(w, a, b, 2.0)
		# shortages: court a supplier, or eye a weak holder
		for kind in ["food", "metal"]:
			var short: bool = float(s[kind]) < (10.0 if kind == "food" else 25.0)
			if not short:
				continue
			var best := ""; var bv := 0.0
			for b in stats:
				if b == a or not fl.has(b):
					continue
				var v := float(stats[b][kind])
				if v > bv:
					bv = v; best = b
			if best == "" or bv < float(s[kind]) * 1.5:
				continue
			var stt := Diplomacy.state(w, a, best)
			if stt in [Diplomacy.NEUTRAL, Diplomacy.TRADE_PACT, Diplomacy.ALLIANCE]:
				Diplomacy._push(w, a, best, 1.5)
			elif stt == Diplomacy.HOSTILE and Diplomacy.strength(w, best) < Diplomacy.strength(w, a) * 0.8:
				Diplomacy._push(w, a, best, -1.5)

# ================================================================== totals (tests, ledgers)
## Every unit of good `g` the town holds: market, barns, granary (grain), households.
static func town_total(e: Dictionary, g: String) -> int:
	var n := int(e["stock"].get(g, 0)) + int(e["barn"].get(g, 0)) + int(e["hh"].get(g, 0)) + int(e.get("gh", {}).get(g, 0))   # (gh: families' stones)
	if g == "grain":
		n += int(e["granary"])
	return n

## Every coin the town holds: treasury, tills, purses and unclaimed barn sales.
static func town_gold(e: Dictionary) -> float:
	var g := float(e["treasury"]) + float(e["farm_till"])
	for b in e["biz"]:
		g += float(b["till"])
	for f in e["fams"]:
		g += float(f["purse"])
	return g

# ================================================================== load / migration
## Saves from before the economy get one generated for each town (seeded from the world seed and town id);
## their shop Items become the town's arms stock and the old food/ale supply goes into the market.
static func after_load(game) -> void:
	var w: Dictionary = game.world
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not has_econ(t):
			migrate(w, t)
		else:
			_fix_ints(t["econ"])
			BowsEcon.after_load(w, t)   # bows: bowyers/fletchers and the armory for older saves
		# Older saves may retain farm employers after their land joined the town
		# estate. Close only those obsolete hiring rows, retaining their books.
		for b in t["econ"]["biz"]:
			if String(b["type"]) == "farm" and int(b["owner"]) < 0:
				Businesses.town_inherits(b)
		WageClaims.after_load(t["econ"])
		HarvestClaims.after_load(t["econ"])
		t["econ"]["faction"] = String(t["faction"])
		for f in t["econ"]["fams"]:   # register person records (older saves get them made from the rows)
			if not f.has("pp"):
				Persons.generate(t["econ"], f, float(game.day))
			else:
				Persons.upgrade(t["econ"], f)   # older records keep the names they had
		if not t["econ"].has("territory"):
			t["econ"]["territory"] = land_total(t["econ"])   # older saves: the land pool as it is now
	for fid in w.get("factions", {}):
		var fac: Dictionary = w["factions"][fid]
		if not fac.has("treasury"):
			fac["treasury"] = 0.0
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		if wb.get("kind", "") == "caravan":
			var cg: Dictionary = wb.get("cargo", {}).get("goods", {})
			for g in cg.keys():
				if not Goods.table().has(g):
					cg.erase(g)   # pre-economy goods (food sacks, ale casks) are gone with the old carts
				else:
					cg[g] = int(cg[g])
			if not wb.has("gold"):
				wb["gold"] = 0.0
				wb["leg"] = "out"

static func migrate(w: Dictionary, t: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), t["id"], "econ-migrate"])
	if (t.get("crafters", {}) as Dictionary).is_empty():
		Economy.make_crafters(t, rng)
	var legacy: Dictionary = t.get("goods", {})
	EconGen.generate(w, t, rng)
	var e: Dictionary = t["econ"]
	e["day"] = int(w.get("last_day", 0))
	if legacy.has("food"):
		e["stock"]["grain"] = int(e["stock"]["grain"]) + int(float(legacy["food"]) * 4.0)
	if legacy.has("alcohol"):
		e["stock"]["beer"] = int(e["stock"]["beer"]) + int(float(legacy["alcohol"]) * 12.0)
	t.erase("goods")
	for f in e["fams"]:
		f["last"] = float(e["day"])
	e["tax"]["season"] = season_stamp(float(e["day"]))

const _FAM_INTS := ["id", "m", "f", "kids", "old", "homes", "hands", "idle", "unpaid", "hungry", "tax_season", "farm", "seed"]
const _BIZ_INTS := ["id", "owner", "workers", "cap", "tools", "skill", "unpaid_n"]

static func _fix_ints(e: Dictionary) -> void:
	for k in ["day", "mkt", "estate_biz", "pop", "adults", "homes", "granary", "hands", "rep", "shel_n", "broth_n", "away_n", "works_biz"]:
		if e.has(k):
			e[k] = int(e[k])
	var casual_caps: Dictionary = e.get("cjcap", {})
	for j in casual_caps: casual_caps[j] = int(casual_caps[j])
	# Children reserve fractional shifts. Truncating these reservations during
	# load made occupied cleanup capacity appear available to another worker.
	var casual_used: Dictionary = e.get("cjused", {})
	for j in casual_used: casual_used[j] = float(casual_used[j])
	for k in ["stock", "barn", "hh", "land", "herd"]:
		var d: Dictionary = e.get(k, {})
		for g in d:
			d[g] = int(d[g])
	e["tax"]["season"] = int(e["tax"]["season"])
	e["head"]["fam"] = int(e["head"]["fam"])
	for o in e.get("orders", []):
		o[0] = int(o[0]); o[2] = int(o[2])
	for f in e["fams"]:
		for k in _FAM_INTS:
			if f.has(k):
				f[k] = int(f[k])
		for k in ["land", "herd", "jobs", "serve"]:
			if not f.has(k):
				f[k] = {}
			var d2: Dictionary = f[k]
			for g in d2:
				d2[g] = int(d2[g])
		var ow: Array = f["owns"]
		for i in ow.size():
			ow[i] = int(ow[i])
		if f.has("cj"):   # economy spec 2 additions: casual work, rent, history events
			for j in f["cj"]:
				f["cj"][j] = int(f["cj"][j])
		if f.has("rent"):
			f["rent"] = int(f["rent"])
		if f.has("hl"):
			f["hl"]["d"] = int(f["hl"]["d"])
		for ev in f.get("ev", []):
			ev[0] = int(ev[0])
		if f.has("lost"):
			f["lost"]["year"] = int(f["lost"]["year"])
	for b in e["biz"]:
		for k in _BIZ_INTS:
			if b.has(k):
				b[k] = int(b[k])
	var ph: Array = e["stats"].get("pop_hist", [])
	for i in ph.size():
		ph[i] = int(ph[i])
