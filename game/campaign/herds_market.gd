class_name HerdsMarket
extends RefCounted
## Fodder buying/stockpiling/loans, home slaughter, livestock offers/wants/pot buys,
## weekly prices/products/manure/straw/crop switching/fees, butcher daily, herd transfers,
## and drovers split from Herds (game/campaign/herds.gd) to keep each file under the size threshold.
## Structure only; all Herds.* entry points delegate here with identical behavior.

const GRAZE := Herds.GRAZE
const AGES := Herds.AGES
const LOG_MAX := Herds.LOG_MAX
const WHATS := Herds.WHATS
const OWN_WORDS := Herds.OWN_WORDS

## Buys up to n bales: from the barns first (the field owners are paid per acre like any barn sale), then the
## market. Returns bales bought.
static func _buy_fodder(e: Dictionary, h: Dictionary, n: float, loan: bool = true, keep: float = 0.0) -> float:
	var want := int(ceil(n))
	var p := float(e["price"].get("fodder", 3.0)) * TownEcon.markup()
	var coin := Herds._coin(e, h) - keep
	var afford := int(maxf(0.0, coin) / maxf(0.01, p))
	var got := 0
	var barn: Dictionary = e["barn"]
	# Existing physical fodder remains its producer's property after land changes hands.
	var own := mini(mini(want, int(barn.get("fodder", 0))), int(straw_left(e, h)))
	if own > 0:
		own = int(HarvestClaims.take(e, "fodder", own, false, HarvestClaims.owner(h))["n"])
		got += own
	var q := mini(mini(want - got, HarvestClaims.available(e, "fodder")), afford)
	if q > 0:
		var sale := HarvestClaims.take(e, "fodder", q)
		q = int(sale["n"])
		var v := float(q) * p
		Herds._add_coin(e, h, -v)
		HarvestClaims.credit(e, sale["shares"], v)
		got += q
	var st: Dictionary = e["stock"]
	var q2 := mini(mini(want - got, int(st.get("fodder", 0))), afford - maxi(0, q))
	if q2 > 0:
		st["fodder"] = int(st["fodder"]) - q2
		var v2 := float(q2) * p
		Herds._add_coin(e, h, -v2)
		var mkt: Dictionary = e["biz"][int(e["mkt"])]
		mkt["till"] = float(mkt["till"]) + v2
		e["stats"]["sales"] = float(e["stats"].get("sales", 0.0)) + v2
		got += q2
	# barge part 2 section 7, the grain loan, for fodder [ours: the spec lends grain]: a family with no coin left
	# borrows straw from its well-off neighbours' barns, owed x1.5 in kind at its next cut (in coin when it has none)
	if loan and got < want and String(h["ow"]) == "f":
		var LN: Dictionary = Herds.A()["fodder_loan"]
		var key := str(int(h["oi"]))
		if not Herds.H(e).has("floan"):
			Herds.H(e)["floan"] = {}
		var owed := float(Herds.H(e)["floan"].get(key, 0.0))
		var room := int(maxf(0.0, Herds.feed_day(h) * float(LN["max_days"]) * float(LN["repay"]) - owed) / float(LN["repay"]))
		var lq := mini(mini(want - got, HarvestClaims.available(e, "fodder")), room)
		if lq > 0:
			var lent := HarvestClaims.take(e, "fodder", lq)
			lq = int(lent["n"])
			# Joint batches can include the borrower's sub-bale remainder. It is its
			# own feed, never an external loan or interest owed to itself.
			var lender_shares: Dictionary = lent["shares"]
			var self_owned := float(lender_shares.get(HarvestClaims.owner(h), 0.0))
			lender_shares.erase(HarvestClaims.owner(h))
			var external := maxf(0.0, float(lq) - self_owned)
			var total_owed := snappedf(owed + external * float(LN["repay"]), 0.01)
			Herds.H(e)["floan"][key] = total_owed
			if not Herds.H(e).has("floan_claims"): Herds.H(e)["floan_claims"] = {}
			var creditors: Dictionary = Herds.H(e)["floan_claims"].get(key, {})
			if not Herds.H(e).has("floan_unknown"): Herds.H(e)["floan_unknown"] = {}
			Herds.H(e)["floan_unknown"][key] = maxf(0.0, owed - _fodder_claim_total(creditors))
			for lender in lender_shares:
				# Attribute the existing rounded debt exactly; rounding cannot create
				# a new unknown creditor or overstate the retained known claims.
				creditors[lender] = float(creditors.get(lender, 0.0)) + float(lender_shares[lender]) / maxf(0.00000001, external) * (total_owed - owed)
			Herds.H(e)["floan_claims"][key] = creditors
			got += lq
	if got > 0:
		TownEcon.led(e, "used", "fodder", got)
		h["fod"] = float(h["fod"])   # (eaten at once)
	Barge.add_demand(e, "fodder", float(got) / 7.0, float(maxi(0, want - got)) / 7.0, 0.0)
	return float(got)

## Owners lay in their winter feed in summer and autumn: each herd's hay store toward its stockpile target (its feed
## for the town's winter_days, the days its pasture cannot carry it), a share of the gap a week until winter, from
## their own hay and straw first, then bought from the barns and the market at the day's price while they keep
## stock_reserve [ours] coins (no loans: those are for hunger). Their orders are the market's demand for hay and
## straw, so a short stock drives its price up and draws caravans before the beasts go hungry.
static func _stockpile(e: Dictionary, si: int, day: float) -> void:
	if si != 1 and si != 2:
		return
	var wd := Herds.winter_days(e)
	var weeks := maxf(1.0, (float((3 - si) * Calendar.DAYS_PER_SEASON) - float(Calendar.day_of_season(day))) / 7.0)
	for hid in Herds.herds(e):
		var h: Dictionary = Herds.herds(e)[hid]
		var fd := Herds.feed_day(h)
		if fd <= 0.0 or String(h["ow"]) == "d":
			continue
		var gap := fd * wd - float(h["fod"])
		if gap <= 1.0:
			continue
		var got := _buy_fodder(e, h, gap / weeks, false, float(Herds.A()["stock_reserve"]))
		h["fod"] = float(h["fod"]) + got

## Fodder loans repaid each herd week: in kind from the borrower's own straw (left in the barns for the lenders),
## else in coin at the fodder price above the buyer's reserve, to the retained lenders. A family
## gone from the town leaves its loan unpaid (hd.floan_lost).
static func _repay_loans(e: Dictionary) -> void:
	var hd := Herds.H(e)
	var fl: Dictionary = hd.get("floan", {})
	if not hd.has("floan_claims"): hd["floan_claims"] = {}
	if not hd.has("floan_unknown"): hd["floan_unknown"] = {}
	var claim_book: Dictionary = hd["floan_claims"]
	var unknown_book: Dictionary = hd["floan_unknown"]
	var fams: Array = e["fams"]
	var p := float(e["price"].get("fodder", 3.0))
	for key in fl.keys():
		var fid := int(key)
		var owed := float(fl[key])
		var creditors: Dictionary = claim_book.get(key, {})
		var known := _fodder_claim_total(creditors)
		var unknown := maxf(0.0, owed - known)
		unknown_book[key] = unknown
		if fid >= fams.size() or fams[fid].get("gone", false):
			hd["floan_lost"] = snappedf(float(hd.get("floan_lost", 0.0)) + owed, 0.01)
			if not creditors.is_empty():
				if not hd.has("floan_claims_lost"): hd["floan_claims_lost"] = {}
				hd["floan_claims_lost"][key] = creditors.duplicate()
			claim_book.erase(key)
			unknown_book.erase(key)
			fl.erase(key)
			continue
		var who := {"ow": "f", "oi": fid}
		var kind_n := mini(int(floor(owed)), int(straw_left(e, who)))
		if kind_n > 0:
			var kind_left := float(kind_n)
			var known_kind := minf(float(kind_n), known)
			if known_kind > 0.0:
				var moved := HarvestClaims.transfer_units(e, "fodder", HarvestClaims.owner(who), creditors, known_kind)
				_reduce_fodder_claims(creditors, moved)
				owed -= moved
				kind_left -= moved
			if kind_left > 0.0 and unknown > 0.0:
				var moved_unknown := HarvestClaims.transfer_units(e, "fodder", HarvestClaims.owner(who), {"?": 1.0}, minf(kind_left, unknown))
				owed -= moved_unknown
				unknown -= moved_unknown
		var f: Dictionary = fams[fid]
		var pay := minf(owed * p, maxf(0.0, float(f["purse"]) - float(Herds.A()["buy_reserve"])))
		if pay > 0.0:
			f["purse"] = float(f["purse"]) - pay
			var known_pay := minf(pay, _fodder_claim_total(creditors) * p)
			if known_pay > 0.0:
				HarvestClaims.credit(e, creditors, known_pay)
				_reduce_fodder_claims(creditors, known_pay / maxf(0.01, p))
			if pay > known_pay:
				# Older saves never retained the lenders. Their actual money stays unclaimed.
				HarvestClaims.credit(e, {"?": 1.0}, pay - known_pay)
				unknown = maxf(0.0, unknown - (pay - known_pay) / maxf(0.01, p))
			owed -= pay / maxf(0.01, p)
		if owed < 0.5:
			fl.erase(key)
			claim_book.erase(key)
			unknown_book.erase(key)
		else:
			fl[key] = snappedf(owed, 0.01)
			claim_book[key] = creditors
			unknown_book[key] = unknown

static func _fodder_claim_total(creditors: Dictionary) -> float:
	var total := 0.0
	for lender in creditors: total += maxf(0.0, float(creditors[lender]))
	return total

static func _reduce_fodder_claims(creditors: Dictionary, amount: float) -> void:
	var total := _fodder_claim_total(creditors)
	if total <= 0.0: return
	var remaining := maxf(0.0, 1.0 - amount / total)
	for lender in creditors.keys():
		creditors[lender] = float(creditors[lender]) * remaining
		if float(creditors[lender]) < 0.000001: creditors.erase(lender)

## Actual fodder still owned in the barns. Land transfers never confer a past producer's straw.
static func straw_left(e: Dictionary, h: Dictionary) -> float:
	var ow := String(h["ow"])
	if ow != "f" and ow != "s":
		return 0.0
	return HarvestClaims.owned(e, HarvestClaims.owner(h), "fodder")

static func _straw_taken(e: Dictionary, h: Dictionary, n: int) -> void:
	var hd := Herds.H(e)
	if not hd.has("stw"):
		hd["stw"] = {}
	var day := float(e.get("day", 0))
	var key := str(int(h["oi"]))
	var row: Array = hd["stw"].get(key, [Calendar.year(day), 0])
	if int(row[0]) != Calendar.year(day):
		row = [Calendar.year(day), 0]
	row[1] = int(row[1]) + n
	hd["stw"][key] = row

## Last week's beasts nobody bought: a hungry herd's owner slaughters at home what his hands can (the meat to his
## larder, the rest to the market); the rest of the offers lapse.
static func _unsold(e: Dictionary, _si: int, day: float) -> void:
	var hd := Herds.H(e)
	var of: Array = hd["of"]
	var cap := {}
	for o in of:
		var h: Dictionary = hd["h"].get(str(int(o[0])), {})
		if h.is_empty() or int(o[2]) <= 0:
			continue
		# what the owners could not sell they slaughter only as far as it is eaten (their larder) or sells (the
		# market's want of fresh meat); the rest they keep. A starving herd's surplus is killed for its hides
		# (the meat not dressed). A drover waits his days at market, then sells for slaughter what the town wants.
		if String(h["ow"]) == "d" and day - float(h.get("da", day)) < float(Herds.A()["drove"]["sell_days"]):
			continue
		var key := str(int(h["id"]))
		if not cap.has(key):
			cap[key] = _home_cap(e, h)
		var n := mini(int(o[2]), int(cap[key]))
		var meals := float(yields(String(h["k"]), String(o[1])).get("fresh_meat", 0.0))
		if int(h["hun"]) <= int(Herds.A()["starve_after"]) / 2 and meals > 0.0:
			var use := 0
			if Herds.sick(h) <= float(Herds.A()["disease_no_sale"]):
				use = maxi(0, int(float(e.get("need", {}).get("fresh_meat", 0.0)) * 1.2) - int(e["stock"].get("fresh_meat", 0)))
				if String(h["ow"]) == "f":
					use += larder_room(e, e["fams"][int(h["oi"])])
			n = mini(n, int(floor(float(use) / meals + 0.5)))   # a carcass when at least half of it is used
		if n <= 0:
			continue
		var got := -Herds.change(e, h, String(o[1]), -n, "slaughtered", "at home by the owners", day)
		cap[key] = int(cap[key]) - got
		_carcass(e, h, String(o[1]), got, true)
	hd["of"] = []

## Head a herd's owners can slaughter and dress at home in a week (their hands x the data's rate; small stock any).
static func _home_cap(e: Dictionary, h: Dictionary) -> int:
	var K := Herds.kind(String(h["k"]))
	var cpw := float(Herds.A()["home_kill_week"]) / maxf(0.05, float(K.get("feed", 0.05)) if float(K.get("feed", 0.0)) > 0.0 else 0.05)
	var hands := 1
	match String(h["ow"]):
		"f":
			hands = maxi(1, int(e["fams"][int(h["oi"])].get("hands", 1)))
		"b":
			hands = maxi(1, int(e["biz"][int(h["oi"])].get("workers", 1)))
		"s":
			hands = maxi(1, int(e["biz"][int(e.get("estate_biz", 0))].get("workers", 1)))
		"d":
			return Herds.head(h)   # the drover sells his unsold herd to the town's butchers' block
	return int(cpw * float(hands))

## A slaughtered beast's yield: meat (fresh, meals' worth), hides, tallow, bones, horn, sinew. home: the owners
## did it (families keep meat for their larder - salted or smoked at home, our keeping meat - up to the data's days
## of food; the rest is sold to the market at the broker's share, or left in the barns when it cannot pay).
## Returns {good: n} made.
static func _carcass(e: Dictionary, h: Dictionary, age: String, n: int, home: bool) -> Dictionary:
	var out := {}
	if n <= 0:
		return out
	var yl := yields(String(h["k"]), age)
	for g in yl:
		var q := int(floor(float(n) * float(yl[g])))
		if q > 0:
			out[g] = q
	if not home:
		return out
	var D := TownEcon.data()
	# the meat: a sick herd's is not eaten nor sold (buried); else the owner family's larder first (as keeping meat),
	# then what the market wants; the rest is not dressed (the owners only slaughter what is eaten or sells: _unsold
	# decides how many, so this is the hide-only slaughter of starving beasts)
	if out.has("fresh_meat"):
		var meat := int(out["fresh_meat"])
		out.erase("fresh_meat")
		if Herds.sick(h) <= float(Herds.A()["disease_no_sale"]):
			if String(h["ow"]) == "f":
				meat -= _to_larder(e, e["fams"][int(h["oi"])], meat)
			var want := maxi(0, int(float(e.get("need", {}).get("fresh_meat", 0.0)) * 1.2) - int(e["stock"].get("fresh_meat", 0)))
			if mini(meat, want) > 0:
				out["fresh_meat"] = mini(meat, want)
	_sell(e, h, out, float(D["market"]["broker_share"]) * (1.0 - Herds.sick(h)))
	return out

## Meals of meat a family's larder has room for (larder_days of its food at its meat share, less what it holds).
static func larder_room(e: Dictionary, f: Dictionary) -> int:
	var r := Families.daily_rates(e, f)
	return int(maxf(0.0, float(Herds.A()["larder_days"]) - float(f["store"].get("food", 0.0))) * float(r["food"]) * float(TownEcon.data()["needs"]["food_mix"]["meat"]))

## Puts up to n meals of the family's own slaughter in its larder as keeping meat. Returns meals kept.
static func _to_larder(e: Dictionary, f: Dictionary, n: int) -> int:
	var keep := mini(n, larder_room(e, f))
	if keep <= 0:
		return 0
	var r := Families.daily_rates(e, f)
	e["hh"]["meat"] = int(e["hh"].get("meat", 0)) + keep
	f["store"]["food"] = float(f["store"].get("food", 0.0)) + float(keep) / maxf(0.1, float(r["food"]))
	TownEcon.led(e, "made", "meat", keep)
	return keep

## Sells goods to the market for the herd's owner at share x price, as much as the market wants (as for the barns:
## 1.2 x its normal stock less what it holds) and its till pays; the rest goes to the barns, where the market buys
## it as it needs (paid out per head of herd like any barn sale) or it spoils.
static func _sell(e: Dictionary, h: Dictionary, goods: Dictionary, share: float) -> void:
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var st: Dictionary = e["stock"]
	var need: Dictionary = e.get("need", {})
	for g in goods:
		var n := int(goods[g])
		if n <= 0:
			continue
		TownEcon.led(e, "made", g, n)
		var p := float(e["price"].get(g, 1.0)) * share
		var want := maxi(0, int(float(need.get(g, 0.0)) * 1.2) - int(st.get(g, 0)))
		var q := mini(mini(n, want), int(maxf(0.0, float(mkt["till"])) / maxf(0.01, p)))
		if q > 0:
			st[g] = int(st.get(g, 0)) + q
			mkt["till"] = float(mkt["till"]) - float(q) * p
			mkt["spend"] = float(mkt.get("spend", 0.0)) + float(q) * p
			Herds._add_coin(e, h, float(q) * p)
		if n - q > 0:
			HarvestClaims.add(e, String(g), n - q, {HarvestClaims.owner(h): 1.0}, int(e.get("day", 0)), "carcass")

## What each herd's owners offer this week (the market for live beasts): head beyond what the herd's pasture
## carries in summer (oxen beyond the family's plough; small stock beyond its start), the old in autumn and
## winter, and in autumn the head the winter fodder in reach cannot feed. Old first, then young, then grown.
static func _offers(e: Dictionary, si: int, day: float) -> void:
	var hd := Herds.H(e)
	var of := []
	var ofk := {}
	var P := Plots._p(e)
	var fod_in_reach := float(e["barn"].get("fodder", 0)) + float(e["stock"].get("fodder", 0))
	var town_need := float(hd.get("fneed", 0.0))
	# the autumn reckoning counts a family's own straw for the year (the autumn cut still to come) by its herds' feed
	var fam_feed := {}
	var own_year := {}
	var straw_due := 0.0   # the grain cuts still to come this year (their straw)
	for s in TownEcon.data()["land"]["harvest_seasons"].get("grain", []):
		if int(s[0]) >= si:
			straw_due += float(e.get("wacres", {}).get("grain", 0.0)) * float(Herds.A()["straw_acre"]) * float(s[1]) * (0.5 if int(s[0]) == si else 1.0)
	if si == 2:
		for hid0 in hd["h"]:
			var h0: Dictionary = hd["h"][hid0]
			if String(h0["ow"]) == "f" or String(h0["ow"]) == "s":
				fam_feed[int(h0["oi"])] = float(fam_feed.get(int(h0["oi"]), 0.0)) + Herds.feed_day(h0)
		for fid0 in fam_feed:
			var f0: Dictionary = e["fams"][int(fid0)]
			own_year[fid0] = float(f0["land"].get("grain", 0)) * float(Herds.A()["straw_acre"]) * float(f0.get("worked", 1.0))
	for hid in hd["h"]:
		var h: Dictionary = hd["h"][hid]
		var k := String(h["k"])
		var n := Herds.head(h)
		if n <= 0:
			continue
		if Herds.sick(h) > float(Herds.A()["disease_no_sale"]):   # nobody buys from a herd this sick
			continue
		if String(h["ow"]) == "d":   # a drover's herd at its market: every head is for sale
			for age0 in AGES:
				if int(h[age0]) > 0:
					of.append([int(h["id"]), age0, int(h[age0]), "d"])
					ofk[k] = int(ofk.get(k, 0)) + int(h[age0])
			continue
		var tgt := _target(e, h, P)
		h["t"] = tgt
		var surplus := maxi(0, n - tgt) if float(Herds.kind(k).get("meat", 0.0)) > 0.0 else 0   # swarms are kept (hives)
		# the old go in autumn and winter (an old ox ploughs on until a young one replaces it; old hives stay)
		var olds := int(h["o"]) if si >= 2 and k != "oxen" and float(Herds.kind(k).get("meat", 0.0)) > 0.0 else 0
		var flag := ""
		if si == 2 and Herds.feed_day(h) > 0.0 and k != "oxen":   # the autumn reckoning (the plough oxen are wintered first)
			# bales to winter the herd (autumn's shortfall and the winter), what it has (its hay, its owners' straw
			# for the year), what it can buy (its share of the town's hay and straw, now and the autumn cut to come,
			# paid from the purse and from selling the beasts it does not keep at half a grown head's price)
			var winter := Herds.feed_day(h) * Herds.winter_days(e)
			var per := winter / float(n)
			var share := (fod_in_reach + straw_due) * Herds.feed_day(h) / maxf(0.01, town_need)
			var pf := maxf(0.01, float(e["price"].get("fodder", 3.0)) * TownEcon.markup())
			var mine := 0.0
			if own_year.has(int(h["oi"])) and (String(h["ow"]) == "f" or String(h["ow"]) == "s"):
				mine = float(own_year[int(h["oi"])]) * Herds.feed_day(h) / maxf(0.01, float(fam_feed[int(h["oi"])]))
			var free := float(h["fod"]) + mine
			var v := Herds.price(e, k) * 0.5
			var keep_coin := (free * pf + maxf(0.0, Herds._coin(e, h)) + float(n) * v) / (per * pf + v)
			var keep_reach := (free + share) / maxf(0.001, per)
			var keep := int(floor(minf(float(n), minf(keep_coin, keep_reach))))
			if keep < n:
				var ws := n - keep
				if ws > surplus:
					surplus = ws
					flag = "w"
		var off := {"o": mini(int(h["o"]), maxi(olds, surplus)), "y": 0, "g": 0}
		var left := maxi(0, surplus - int(off["o"]))
		off["y"] = mini(int(h["y"]), left)
		left -= int(off["y"])
		off["g"] = mini(int(h["g"]), left)
		for age in AGES:
			if int(off[age]) > 0:
				of.append([int(h["id"]), age, int(off[age]), flag])
				ofk[k] = int(ofk.get(k, 0)) + int(off[age])
	hd["of"] = of
	hd["ofk"] = ofk
	hd["wak"] = {}
	hd["sok"] = {}

## Head the herd's owners mean to keep: grazing kinds what their plots carry in summer (at least what they hold
## when there are no plots to read), oxen the family's plough (one per acres_per_hand), small stock their start.
static func _target(e: Dictionary, h: Dictionary, P: Dictionary) -> int:
	var k := String(h["k"])
	var K := Herds.kind(k)
	if k == "oxen":
		if String(h["ow"]) == "f" or String(h["ow"]) == "s":
			var f: Dictionary = e["fams"][int(h["oi"])]
			return int(ceil(float(Families.acres(f)) / float(TownEcon.data()["land"]["acres_per_hand"])))
		return 0
	if float(K.get("feed", 0.0)) <= 0.0 or P.is_empty():
		return maxi(int(h.get("t", 0)), 1) if int(h.get("t", 0)) > 0 else Herds.head(h)
	var pk := Herds.peak_season(e)   # what the land carries at its best season (the lean ones are fed hay)
	var grass := float(h.get("cs", 0.0)) * Herds.pool_grass(e, P, pk)
	var n := Plots.count(P)
	for i in h.get("opl", []):
		if int(i) < n:
			grass += Herds.grass_day(e, P, int(i), pk)
	var per_head := float(K["feed"]) * (Herds.ge(h) / float(Herds.head(h)) if Herds.head(h) > 0 else 1.0)   # the herd's mix of young and grown
	return int(floor(grass / maxf(0.0001, per_head) * float(Herds.A()["keep_share"])))

## Live sales of the week: farm families short of oxen buy them (oxen offered, else grown cattle trained to the
## plough), herds far below what their pasture carries buy grown stock back; each at the town's price.
static func _wants(_game, _town: Dictionary, e: Dictionary, _si: int, day: float) -> void:
	var hd := Herds.H(e)
	var wak: Dictionary = hd["wak"]
	var aph := float(TownEcon.data()["land"]["acres_per_hand"])
	var reserve := float(Herds.A()["buy_reserve"])
	# These indices live only for this sales pass. References retain herd/offer order
	# and see head counts and offers change immediately as each purchase is made.
	var cattle := {}
	var oxen := {}
	for h in (hd["h"] as Dictionary).values():
		var fid := int(h["oi"])
		if String(h["ow"]) != ("s" if fid == 0 else "f"):
			continue
		if String(h["k"]) == "cattle":
			if not cattle.has(fid): cattle[fid] = []
			cattle[fid].append(h)
		elif String(h["k"]) == "oxen" and not oxen.has(fid):
			oxen[fid] = h
	var offers := {}
	for o in hd["of"]:
		var h: Dictionary = hd["h"].get(str(int(o[0])), {})
		if h.is_empty(): continue
		var k := String(h["k"])
		var age := String(o[1])
		if not offers.has(k): offers[k] = {}
		if not offers[k].has(age): offers[k][age] = []
		offers[k][age].append(o)
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		var ac := Families.acres(f)
		if ac <= 0:
			continue
		var short := int(ceil(float(ac) / aph)) - maxi(0, int(f.get("ox", 0)))
		if short <= 0:
			continue
		short = mini(short, 2)
		wak["oxen"] = int(wak.get("oxen", 0)) + short
		wak["cattle"] = int(wak.get("cattle", 0)) + short   # grown cattle are trained to the plough too
		# the family's own grown cattle first (trained to the plough: from its herd to its oxen, no coin)
		for own in cattle.get(int(f["id"]), []):
			while short > 0 and int(own["g"]) >= 2:
				var oxh0 := _indexed_oxen(e, oxen, int(f["id"]), day)
				if Herds._transfer(e, own, oxh0, "g", 1, "sold", "bought", "to the family's plough", "from the family's own herd", day) <= 0:
					break
				short -= 1
		for src in ["oxen", "cattle"]:
			if short <= 0:
				break
			var p := Herds.price(e, src)
			while short > 0 and float(f["purse"]) - p > reserve:
				var o := _take_offer(e, src, ["g"], int(f["id"]), -1, offers)
				if o.is_empty():
					break
				var seller: Dictionary = hd["h"][str(int(o[0]))]
				var oxh := _indexed_oxen(e, oxen, int(f["id"]), day)
				if Herds._transfer(e, seller, oxh, "g", 1, "sold", "bought", "to the %s for the plough" % Backstory.plural(String(f["name"])),
						"from %s" % Herds.owner_text(e, seller), day) > 0:
					f["purse"] = float(f["purse"]) - p
					Herds._add_coin(e, seller, p)
					hd["sok"][src] = int(hd["sok"].get(src, 0)) + 1
					short -= 1
	# restocking: a herd below half its keep buys grown stock of its kind
	for hid in (hd["h"] as Dictionary).keys():
		var h: Dictionary = hd["h"][hid]
		var k := String(h["k"])
		if not GRAZE.has(k) or String(h["ow"]) == "d":
			continue
		var need := int(float(h["t"]) * 0.5) - Herds.head(h)
		if need <= 0:
			continue
		need = mini(need, int(Herds.A()["restock_week"]))
		wak[k] = int(wak.get(k, 0)) + need
		var p2 := Herds.price(e, k)
		while need > 0 and Herds._coin(e, h) - p2 > reserve:
			var o2 := _take_offer(e, k, ["g"], -1, int(h["id"]), offers)
			if o2.is_empty():
				break
			var s2: Dictionary = hd["h"][str(int(o2[0]))]
			if Herds._transfer(e, s2, h, "g", 1, "sold", "bought", "to %s" % Herds.owner_text(e, h), "from %s" % Herds.owner_text(e, s2), day) > 0:
				Herds._add_coin(e, h, -p2)
				Herds._add_coin(e, s2, p2)
				hd["sok"][k] = int(hd["sok"].get(k, 0)) + 1
				need -= 1
	_pot_buys(e, day)

## Families buy a beast for their own larder when one offered costs less than the meat in it at the market's price
## of keeping meat (x pot_value [ours]), they have the room and the coin (keeping pot_reserve): live animals traded
## by families, so a glut of beasts feeds the town instead of rotting. The family slaughters it at once (logged:
## bought, then slaughtered for its pot). At most pot_week buys a town a week [ours].
static func _pot_buys(e: Dictionary, day: float) -> void:
	var hd := Herds.H(e)
	var mp := float(e["price"].get("meat", 20.0)) * float(Herds.A()["pot_value"])
	var cands := []
	for o in hd["of"]:
		if int(o[2]) <= 0:
			continue
		var h: Dictionary = hd["h"].get(str(int(o[0])), {})
		if h.is_empty() or GRAZE.find(String(h["k"])) < 0 and String(h["k"]) != "hens":
			continue
		var meals := float(yields(String(h["k"]), String(o[1])).get("fresh_meat", 0.0))
		var p := Herds.price(e, String(h["k"]), String(o[1]))
		if meals >= 1.0 and p < meals * mp:
			cands.append([p / meals, o, meals, p])
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var buys := 0
	var ci := 0
	var fams: Array = e["fams"]
	var start := int(day) % maxi(1, fams.size())
	for j in fams.size():
		if buys >= int(Herds.A()["pot_week"]) or ci >= cands.size():
			break
		var f: Dictionary = fams[(start + j) % fams.size()]
		if f.get("gone", false) or f.get("estate", false):
			continue
		var c: Array = cands[ci]
		var o: Array = c[1]
		if int(o[2]) <= 0:
			ci += 1
			continue
		if larder_room(e, f) < int(float(c[2]) * 0.5) or float(f["purse"]) - float(c[3]) < float(Herds.A()["pot_reserve"]):
			continue
		var seller: Dictionary = hd["h"][str(int(o[0]))]
		var k := String(seller["k"])
		var age := String(o[1])
		var mine := Herds.herd_for(e, int(f["id"]), k, day)
		if Herds._transfer(e, seller, mine, age, 1, "sold", "bought", "to the %s for their pot" % Backstory.plural(String(f["name"])),
				"from %s" % Herds.owner_text(e, seller), day) <= 0:
			ci += 1
			continue
		o[2] = int(o[2]) - 1
		f["purse"] = float(f["purse"]) - float(c[3])
		Herds._add_coin(e, seller, float(c[3]))
		hd["sok"][k] = int(hd["sok"].get(k, 0)) + 1
		Herds.change(e, mine, age, -1, "slaughtered", "for the family's pot", day)
		var yl := yields(k, age)
		_to_larder(e, f, int(floor(float(yl["fresh_meat"]))))
		var rest := {}
		for g in yl:
			if g != "fresh_meat" and int(floor(float(yl[g]))) > 0:
				rest[g] = int(floor(float(yl[g])))
		_sell(e, mine, rest, float(TownEcon.data()["market"]["broker_share"]))
		buys += 1

## Takes one head of kind k (ages in order) off the offers (not from the buyer's own herds). [hid, age] or [].
static func _take_offer(e: Dictionary, k: String, ages: Array, buyer_fid: int = -1, buyer_hid: int = -1, index: Dictionary = {}) -> Array:
	var hd := Herds.H(e)
	for age in ages:
		var offers: Array = hd["of"] if index.is_empty() else index.get(k, {}).get(String(age), [])
		for o in offers:
			if int(o[2]) <= 0 or String(o[1]) != String(age):
				continue
			var h: Dictionary = hd["h"].get(str(int(o[0])), {})
			if h.is_empty() or String(h["k"]) != k or int(h["id"]) == buyer_hid or int(h[String(age)]) <= 0:
				continue
			if buyer_fid >= 0 and Herds.grazer(e, h) == buyer_fid and String(h["ow"]) == "f":
				continue
			o[2] = int(o[2]) - 1
			return [int(o[0]), String(age)]
	return []

## _wants creates only new oxen records; add each to its pass-local index immediately.
static func _indexed_oxen(e: Dictionary, index: Dictionary, fid: int, day: float) -> Dictionary:
	if not index.has(fid):
		index[fid] = Herds.new_herd(e, "oxen", "s" if fid == 0 else "f", fid, day)
	return index[fid]

## The price of a grown head each week: base x PL x (wanted / offered)^the data's power, stepped toward it.
static func _prices(e: Dictionary) -> void:
	var hd := Herds.H(e)
	var pr: Dictionary = hd["pr"]
	var PP: Dictionary = Herds.A()["price"]
	for k in Herds.kinds():
		var base := float(Herds.kind(k)["price"]) * Barge.pl(e)
		var s := float(hd["ofk"].get(k, 0)) + 1.0
		var d := float(hd["wak"].get(k, 0)) + float(hd.get("bk", {}).get(k, 0)) + 1.0
		var tgt := base * pow(clampf(d / s, float(PP["clamp"][0]), float(PP["clamp"][1])), float(PP["power"]))
		var p := float(pr.get(k, base))
		pr[k] = snappedf(p + (tgt - p) * float(PP["step"]), 0.01)
	hd["bk"] = {}

## The coming week's products (data per kind): milk from the females in milk, wool shorn in summer, eggs (our
## keeping protein food, eight to a meal), honey (the moon elves' honey is our staple) and wax. The market pays the
## owners now at the broker's share for what it wants of the week's yield (up to its till) and takes it day by day
## (day()); what it does not want of the keeping goods goes to the barns; unwanted milk is not milked.
static func _products(e: Dictionary, si: int, _day: float) -> void:
	var hd := Herds.H(e)
	var dd := {}
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var share := float(TownEcon.data()["market"]["broker_share"])
	var need: Dictionary = e.get("need", {})
	var st: Dictionary = e["stock"]
	var want := {}
	var per_owner := []
	for hid in hd["h"]:
		var h: Dictionary = hd["h"][hid]
		if String(h["ow"]) == "d":
			continue
		var K := Herds.kind(String(h["k"]))
		var out := {}
		if float(K.get("milk", 0.0)) > 0.0 and float(h["lac"]) > 0.0:
			out["milk"] = float(h["lac"]) * float(K["milk"]) * 7.0 * (1.0 - Herds.sick(h))
		if float(K.get("wool", 0.0)) > 0.0 and si == 1:
			out["wool"] = float(h["g"]) * float(K["wool"]) * 7.0 / float(Calendar.DAYS_PER_SEASON) * (1.0 - Herds.sick(h))
		if float(K.get("eggs", 0.0)) > 0.0 and si <= 2:
			out["meat"] = float(h["g"]) * float(K.get("fem", 1.0)) * float(K["eggs"]) * 7.0 / float(Herds.A()["eggs_per_meal"]) * float(h.get("fed", 0))
		if float(K.get("honey", 0.0)) > 0.0 and si <= 2:
			out["grain"] = float(h["g"]) * float(K["honey"]) * float(Herds.A()["honey_meals"]) * 7.0
		if float(K.get("wax", 0.0)) > 0.0 and si <= 2:
			out["wax"] = float(h["g"]) * float(K["wax"]) * 7.0
		if float(K.get("moult", 0.0)) > 0.0 and si <= 2:   # v0.012: feathers gathered from the living birds (geese moult)
			out["feathers"] = float(h["g"]) * float(K["moult"]) * 7.0
		if not out.is_empty():
			per_owner.append([h, out])
			for g in out:
				want[g] = float(want.get(g, 0.0)) + float(out[g])
	# how much of each the market takes this week (its want, as for the barns)
	var take := {}
	for g in want:
		var wq := maxf(0.0, float(need.get(g, 0.0)) * 1.2 - float(st.get(g, 0)) + float(e.get("dem", {}).get(g, 0.0)) * 7.0)
		take[g] = minf(1.0, wq / maxf(0.001, float(want[g])))
	for po in per_owner:
		var h2: Dictionary = po[0]
		var out2: Dictionary = po[1]
		var barn := {}
		for g in out2:
			var q := float(out2[g]) * float(take[g])
			var p := float(e["price"].get(g, 1.0)) * share
			var v := minf(q * p, maxf(0.0, float(mkt["till"])))
			q = v / maxf(0.01, p)
			if q > 0.0:
				mkt["till"] = float(mkt["till"]) - v
				mkt["spend"] = float(mkt.get("spend", 0.0)) + v
				Herds._add_coin(e, h2, v)
				dd[g] = float(dd.get(g, 0.0)) + q / 7.0
			var rest := int(floor(float(out2[g]) - q))
			if rest > 0 and g != "milk":
				barn[g] = rest
		for g2 in barn:
			HarvestClaims.add(e, String(g2), int(barn[g2]), {HarvestClaims.owner(h2): 1.0}, int(e.get("day", 0)), "herd products")
			TownEcon.led(e, "made", g2, int(barn[g2]))
	hd["dd"] = dd

## The day's deliveries of the week's paid products into the market (one line in TownEcon._farms).
static func day(e: Dictionary) -> void:
	if not e.has("hd"):
		return
	var hd: Dictionary = e["hd"]
	var dd: Dictionary = hd["dd"]
	if dd.is_empty():
		return
	var dc: Dictionary = hd["dc"]
	var st: Dictionary = e["stock"]
	for g in dd:
		var amt := float(dd[g]) + float(dc.get(g, 0.0))
		var n := int(floor(amt))
		dc[g] = amt - float(n)
		if n > 0:
			st[g] = int(st.get(g, 0)) + n
			TownEcon.led(e, "made", g, n)

## Dung of the herds over the year spread on the fields: the share of the field acres it covers (data tonnes an
## acre) raises their yield by the data's share.
static func _manure(e: Dictionary) -> void:
	var hd := Herds.H(e)
	var t := 0.0
	for hid in hd["h"]:
		var h: Dictionary = hd["h"][hid]
		t += Herds.ge(h) * float(Herds.kind(String(h["k"])).get("manure", 0.0))
	hd["mt"] = snappedf(float(hd["mt"]) + (t - float(hd["mt"])) * 0.1, 0.01)
	var acres := 0.0
	for c in e.get("land", {}):
		acres += float(e["land"][c])
	var recovered := float(hd.get("human_manure_week", 0)) / 1000 * EconGen.YEAR_DAYS / 7
	var share := minf(1.0, (float(hd["mt"]) + recovered) / maxf(1.0, acres * float(Herds.A()["manure_acre"])))
	hd["man"] = snappedf(1.0 + float(Herds.A()["manure_yield"]) * share, 0.0001)

## The field yield factor from manure (one line in TownEcon._farms).
static func manure_f(e: Dictionary) -> float:
	return float(e["hd"].get("man", 1.0)) if e.has("hd") else 1.0

## Straw: the cereal cut gives dated fodder to its producers. One line in _farms.
static func straw(e: Dictionary, acres_cut: float) -> void:
	var carry: Dictionary = e["carry"]
	var previous := float(carry.get("straw", 0.0))
	var produced := acres_cut * float(Herds.A()["straw_acre"])
	var amt := produced + previous
	var n := int(floor(amt))
	carry["straw"] = amt - float(n)
	var weights := {}
	var P: Dictionary = e.get("plots", {})
	if not P.is_empty():
		CropRotation.ensure(e, P, float(e.get("day", 0)))
		for key in P.get("crop_yields", {}):
			var fid := int(key)
			if fid < 0 or fid >= e["fams"].size(): continue
			weights["f:%d" % fid] = float(P["crop_yields"][key][2]) * float(e["fams"][fid].get("worked", 0.0))
	HarvestClaims.harvest(e, "fodder", "straw", weights, produced, n, 0, previous, int(e.get("day", 0)))
	if n > 0: TownEcon.led(e, "made", "fodder", n)

## Coin for hay and straw sold out of the barns: shared between the hay meadows and the grain land by what each gives
## in a year (meadow acres x the hay yield, grain acres x the straw), paid per acre like any barn sale. (Hook in
## TownEcon._barn_paid / _barn_sales.)
static func fodder_paid(e: Dictionary, val: float) -> void:
	var land: Dictionary = e.get("land", {})
	var hay := float(land.get("fodder", 0)) * float(TownEcon.data()["land"]["yield"].get("fodder", 0.0))
	var stw := float(land.get("grain", 0)) * float(Herds.A()["straw_acre"])
	if hay + stw <= 0.0:
		e["treasury"] = float(e["treasury"]) + val
		return
	e["farm_till"] = float(e["farm_till"]) + val
	if hay > 0.0:
		e["cum"]["fodder"] = float(e["cum"].get("fodder", 0.0)) + val * hay / (hay + stw) / float(land["fodder"])
	if stw > 0.0:
		e["cum"]["grain"] = float(e["cum"].get("grain", 0.0)) + val * stw / (hay + stw) / float(land["grain"])

## Hay meadows against grain (the land's choice, a plot a town a week): when an acre of hay sells for more than an
## acre of grain by land_switch [ours] and the herds have fewer than fodder_days_want [ours] days of fodder in reach,
## the biggest grain holder puts one of its grain plots down to hay; when grain pays that much more, the biggest hay
## holder ploughs one back. The family's land and the plots change together (land values and wages follow the crop).
static func _land_choice(e: Dictionary, P: Dictionary, day: float) -> void:
	if P.is_empty():
		return
	var L: Dictionary = TownEcon.data()["land"]
	var clim: Dictionary = TownEcon.data()["climates"].get(String(e.get("climate", "temperate")), {})
	var gv := float(L["yield"]["grain"]) * float(clim.get("grain_yield", 1.0)) * float(e["price"].get("grain", 3.6))
	gv += float(Herds.A()["straw_acre"]) * float(e["price"].get("fodder", 3.0))   # grain land gives straw too
	var fv := float(L["yield"].get("fodder", 0.0)) * float(e["price"].get("fodder", 3.0))
	var m := float(Herds.A()["land_switch"])
	var short := Herds.fodder_days(e) >= 0.0 and Herds.fodder_days(e) < float(Herds.A()["fodder_days_want"])
	var from := ""; var to := ""
	if fv > gv * m and short:
		from = "grain"; to = "fodder"
	elif gv > fv * m and int(e.get("land", {}).get("fodder", 0)) > 0:
		from = "fodder"; to = "grain"
	else:
		return
	var best: Dictionary = {}
	var ba := 0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		var a := int(f["land"].get(from, 0))
		if a > ba:
			ba = a; best = f
	if best.is_empty():
		return
	var ci := Plots._crop_index(P, from)
	for i in Plots.count(P):
		if int(P["own"][i]) == int(best["id"]) and int(P["use"][i]) == Plots.FIELD and int(P["sub"][i]) == ci:
			change_crop(e, P, best, i, from, to, day)
			return

## One plot of family f from crop a to crop b: its land, the town's land and worked acres, the claim marks, the plot.
static func change_crop(e: Dictionary, P: Dictionary, f: Dictionary, i: int, a: String, b: String, day: float) -> void:
	var ac := int(P["ac"][i])
	Families.settle(e, f)
	f["land"][a] = int(f["land"].get(a, 0)) - ac
	if int(f["land"][a]) <= 0:
		f["land"].erase(a)
	f["land"][b] = int(f["land"].get(b, 0)) + ac
	f["cum"][b] = float(e["cum"].get(b, 0.0))
	e["land"][a] = int(e["land"].get(a, 0)) - ac
	e["land"][b] = int(e["land"].get(b, 0)) + ac
	var wk := float(f.get("worked", 0.0))
	e["wacres"][a] = float(e["wacres"].get(a, 0.0)) - float(ac) * wk
	e["wacres"][b] = float(e["wacres"].get(b, 0.0)) + float(ac) * wk
	if not e["cum"].has(b):
		e["cum"][b] = 0.0
	if not (e["crops"] as Dictionary).has("fodder"):
		e["crops"]["fodder"] = "hay"
	P["sub"][i] = Plots._crop_index(P, b)
	P["crop_count"] = -1
	Plots._hist(P, i, day, "Put down to %s by its owners." % ("hay meadow" if b == "fodder" else TownEcon.variety_word(e, b)))
	Plots._dirty(P)
	Families.refresh_worked(e, f)

## Herders' places follow their herds (a herdsman per the kind's head per hand).
static func _herder_caps(e: Dictionary) -> void:
	var biz: Array = e["biz"]
	var need := {}
	for hid in Herds.herds(e):
		var h: Dictionary = Herds.herds(e)[hid]
		if String(h["ow"]) == "b":
			need[int(h["oi"])] = float(need.get(int(h["oi"]), 0.0)) + Herds.ge(h) / float(Herds.kind(String(h["k"])).get("per_hand", 25))
	for b in biz:
		if String(b["type"]) == "herder" and not b.get("closed", false):
			# cap is paid places, excluding the actual working family keeper.
			b["cap"] = maxi(0, int(ceil(float(need.get(int(b["id"]), 0.0)) - int(b.get("kw", 0)))))

## The common pasture's fee: grazing acres a herd uses on the town's common plots, a week, to the treasury.
static func _fees(e: Dictionary, P: Dictionary, h: Dictionary) -> void:
	if P.is_empty() or String(h["ow"]) == "s" or float(h.get("cs", 0.0)) <= 0.0:
		return
	var hd := Herds.H(e)
	if not hd.has("_pa"):   # the common's acres (memo for the week)
		var pa := 0.0
		var n := Plots.count(P)
		for i in hd.get("cpool", []):
			if int(i) < n:
				pa += float(P["ac"][int(i)])
		hd["_pa"] = pa
	var ac := float(hd["_pa"]) * float(h["cs"])
	if ac <= 0.0:
		return
	var fee := minf(ac * float(Herds.A()["fee_acre_week"]) * Barge.pl(e), maxf(0.0, Herds._coin(e, h)))
	if fee > 0.0:
		Herds._add_coin(e, h, -fee)
		e["treasury"] = float(e["treasury"]) + fee
		h["fee"] = snappedf(float(h.get("fee", 0.0)) + fee, 0.01)

# ================================================================== the butcher (one line in Businesses.daily)
## A butcher's day: buys the beasts offered (cheapest meat first) at the town's price from their owners, up to
## his hands' kilos a day and the fresh meat the salters and the market want, and turns each into meat, hide,
## tallow, bones, horn and sinew (the data's yields), sold to the market. Returns coin spent on beasts.
static func butcher_day(e: Dictionary, b: Dictionary, wd: float, toolf: float, mkt: Dictionary, share: float, _bdem: Dictionary) -> float:
	if not e.has("hd"):
		b["state"] = "inputs"; b["why"] = "beasts"
		return 0.0
	var hd: Dictionary = e["hd"]
	var kgcap := wd * float(TownEcon.data()["businesses"]["butcher"]["kg_day"]) * toolf + float(b.get("carry", 0.0))
	# the aim: the day's want of fresh meat (salters' orders and the gap to a normal stock), shared among butchers
	var nb := 0
	for x in e["biz"]:
		if String(x["type"]) == "butcher" and not x.get("closed", false) and int(x["workers"]) > 0:
			nb += 1
	var aim := (float(e.get("dem", {}).get("fresh_meat", 0.0)) + 0.1 * (float(e.get("need", {}).get("fresh_meat", 0.0)) - float(e["stock"].get("fresh_meat", 0)))) / float(maxi(1, nb))
	var aim_kg := maxf(0.0, aim) * float(Herds.A()["kg_per_meal"]) + 1.0
	kgcap = minf(kgcap, aim_kg)
	var spent := 0.0
	var made := {}
	var kills := 0
	var guard := 0
	# Prices/yields do not change inside this butcher's pass. Rank offers once;
	# equal values keep the original first-offer priority. Availability stays live.
	var ranked := []
	var of: Array = hd["of"]
	if kgcap > 1.0:
		for j in of.size():
			var o: Array = of[j]
			if int(o[2]) <= 0: continue
			var h: Dictionary = hd["h"].get(str(int(o[0])), {})
			if h.is_empty() or int(h[String(o[1])]) <= 0: continue
			var K := Herds.kind(String(h["k"]))
			var kg := float(K.get("meat", 0.0)) * float(Herds.A()["yield_age"][AGES.find(String(o[1]))])
			if kg <= 0.0: continue
			var v := _carcass_value(e, h, String(o[1])) * share - Herds.price(e, String(h["k"]), String(o[1]))
			ranked.append([v / kg, j])
		ranked.sort_custom(func(a, b2): return a[0] > b2[0] if a[0] != b2[0] else a[1] < b2[1])
	var next_offer := 0
	while kgcap > 1.0 and guard < 200:
		guard += 1
		var best := -1
		while next_offer < ranked.size():
			var j := int(ranked[next_offer][1])
			var o: Array = of[j]
			var h: Dictionary = hd["h"].get(str(int(o[0])), {})
			if int(o[2]) > 0 and not h.is_empty() and int(h[String(o[1])]) > 0:
				best = j
				break
			next_offer += 1
		if best < 0:
			break
		var o2: Array = hd["of"][best]
		var h2: Dictionary = hd["h"][str(int(o2[0]))]
		var age := String(o2[1])
		var p := Herds.price(e, String(h2["k"]), age) * (1.0 - Herds.sick(h2))   # a sick herd's beasts fetch less
		var val := _carcass_value(e, h2, age) * share
		if val * float(Barge.B()["business"]["out_share"]) < float(Barge.B()["business"]["run_margin"]) * p:
			b["why"] = "no margin"
			break
		if float(b["till"]) < p:
			b["state"] = "wages"; b["why"] = "money for beasts"
			break
		var kg2 := float(Herds.kind(String(h2["k"])).get("meat", 0.0)) * float(Herds.A()["yield_age"][AGES.find(age)])
		if Herds.change(e, h2, age, -1, "slaughtered", "by %s" % Businesses.title(e, b), float(e.get("day", 0))) == 0:
			o2[2] = 0
			continue
		o2[2] = int(o2[2]) - 1
		b["till"] = float(b["till"]) - p
		Herds._add_coin(e, h2, p)
		spent += p
		kgcap -= kg2
		kills += 1
		hd["sok"][String(h2["k"])] = int(hd["sok"].get(String(h2["k"]), 0)) + 1
		if not hd.has("bk"):
			hd["bk"] = {}
		hd["bk"][String(h2["k"])] = int(hd["bk"].get(String(h2["k"]), 0)) + 1
		var yl := yields(String(h2["k"]), age)
		var oc: Dictionary = b["oc"]
		for g in yl:
			oc[g] = float(oc.get(g, 0.0)) + float(yl[g])
		_chain(b, "from", Herds.owner_text(e, h2), 1, String(h2["k"]))
	b["carry"] = 0.0
	for g in (b["oc"] as Dictionary).keys():   # whole units out; the part-units carry to the next beast
		var whole := int(floor(float(b["oc"][g])))
		if whole > 0:
			made[g] = whole
			b["oc"][g] = float(b["oc"][g]) - float(whole)
	# the yield goes to the market at the buy share
	var st: Dictionary = e["stock"]
	var got := 0.0
	for g in made:
		var n := int(made[g])
		st[g] = int(st.get(g, 0)) + n
		TownEcon.led(e, "made", g, n)
		got += float(n) * float(e["price"].get(g, 1.0)) * share
		_chain(b, "to", "the market", n, g)
	got = minf(got, maxf(0.0, float(mkt["till"])))
	mkt["till"] = float(mkt["till"]) - got
	mkt["spend"] = float(mkt.get("spend", 0.0)) + got
	b["till"] = float(b["till"]) + got
	b["kills"] = int(b.get("kills", 0)) + kills
	if kills == 0 and b["state"] == "busy":
		b["state"] = "inputs"
		if String(b.get("why", "")) == "":
			b["why"] = "beasts"
	return spent

## A carcass of kind k and age: {good: units} (meat in meals' worth of fresh meat; tallow and bones by the age's
## carcass share; a hide, horns and sinew whole).
static func yields(k: String, age: String) -> Dictionary:
	var K := Herds.kind(k)
	var af := float(Herds.A()["yield_age"][AGES.find(age)])
	var out := {}
	var meals := float(K.get("meat", 0.0)) * af / float(Herds.A()["kg_per_meal"])
	if meals > 0.0:
		out["fresh_meat"] = meals
	for g in ["hides", "tallow", "bones", "horn", "sinew", "feathers"]:   # (v0.012: poultry's feathers, for fletching)
		var q := float(K.get(g, 0.0)) * (af if g in ["tallow", "bones"] else 1.0)
		if q > 0.0:
			out[g] = q
	return out

static func _carcass_value(e: Dictionary, h: Dictionary, age: String) -> float:
	var K := Herds.kind(String(h["k"]))
	var af := float(Herds.A()["yield_age"][AGES.find(age)])
	var price_d: Dictionary = e["price"]
	var v := float(K.get("meat", 0.0)) * af / float(Herds.A()["kg_per_meal"]) * float(price_d.get("fresh_meat", 16.0))
	for g in ["hides", "tallow", "bones", "horn", "sinew", "feathers"]:
		v += float(K.get(g, 0.0)) * (af if g in ["tallow", "bones"] else 1.0) * float(price_d.get(g, 1.0))
	return v

## A business's chain (the page shows it): where its beasts or inputs came from and where its output went, this
## season: b.chain {from|to: {who|good: n}}.
static func _chain(b: Dictionary, way: String, who: String, n: int, what: String) -> void:
	var day := int(Game.world.get("last_day", 0)) if Game.world.has("last_day") else 0
	var st := TownEcon.season_stamp(float(day))
	if int(b.get("chain_s", -1)) != st:
		b["chain_last"] = b.get("chain", {})
		b["chain"] = {"from": {}, "to": {}}
		b["chain_s"] = st
	var c: Dictionary = b["chain"][way]
	var key := "%s|%s" % [who, what]
	c[key] = int(c.get(key, 0)) + n

# ================================================================== herds change hands outside the week
## Work attached to the actual heads that moved() would transfer, in its saved
## herd order and old/young/grown order. Previewing never transfers an animal.
static func move_work(e: Dictionary, fid: int, k: String, n: int) -> Dictionary:
	var per_hand := float(Herds.kind(k).get("per_hand", TownEcon.data()["land"]["head_per_hand"]))
	if not e.has("hd"):
		return {"heads": n, "hands": float(n) / per_hand}
	var left := n
	var work := 0.0
	for src in Herds.of_family(e, fid):
		if left <= 0: break
		if String(src["k"]) != k: continue
		for age in ["o", "y", "g"]:
			var q := mini(left, int(src[age]))
			left -= q
			work += float(q) * (0.5 if age == "y" else 1.0) / per_hand
	return {"heads": n - left, "hands": work}

## Hook from Families.move_herd (land sales, loan courts, a house dying out,
## movers leaving) and Families.move_land (oxen go with the fields). The families' totals were already moved; the
## records follow (a sale on both sides).
static func moved(e: Dictionary, a: Dictionary, b: Dictionary, k: String, n: int, why: String = "") -> void:
	if not e.has("hd") or n <= 0:
		return
	var day := float(e.get("day", 0))
	var fa := int(a["id"]); var fb := int(b["id"])
	var to := Herds.herd_for(e, fb, k, day)
	var left := n
	var det := why if why != "" else ("with the land" if k == "oxen" else "the town's land book")
	for src in Herds.of_family(e, fa):
		if left <= 0:
			break
		if String(src["k"]) != k or int(src["id"]) == int(to["id"]):
			continue
		for age in ["o", "y", "g"]:
			var q := mini(left, int(src[age]))
			if q > 0:
				left -= Herds._transfer(e, src, to, age, q, "sold", "bought", "%s to %s" % [det, Plots.owner_text(e, fb)],
					"%s from %s" % [det, Plots.owner_text(e, fa)], day, false)
	if left > 0:   # the family's total ran ahead of its records (an old save): the records take the total's word
		Herds.H(e)["drift"] = int(Herds.H(e).get("drift", 0)) + left

## Hook from Army.on_sack: the raiders drive off a share of every grazing herd home to their nearest town of the
## realm (its estate's herds); the town's herds log the theft.
static func on_sack(w: Dictionary, town: Dictionary, att: String) -> void:
	if not TownEcon.has_econ(town) or not town["econ"].has("hd"):
		return
	var e: Dictionary = town["econ"]
	var home := ""
	var bd := INF
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if String(t.get("faction", "")) == att and TownEcon.has_econ(t):
			var d := (t["pos"] as Vector2).distance_to(town["pos"])
			if d < bd:
				bd = d; home = tid
	var share := float(Herds.A()["sack_share"])
	var day := float(e.get("day", 0))
	var thief := CampaignWorld.faction_the(att)
	for hid in (Herds.H(e)["h"] as Dictionary).keys():
		var h: Dictionary = Herds.herds(e)[hid]
		if not GRAZE.has(String(h["k"])) and String(h["k"]) != "oxen":
			continue
		for age in AGES:
			var n := int(floor(float(h[age]) * share))
			if n <= 0:
				continue
			var got := -Herds.change(e, h, age, -n, "stolen", "driven off by %s" % thief, day)
			if got > 0 and home != "":
				var he: Dictionary = w["towns"][home]["econ"]
				var to := Herds.herd_for(he, 0, String(h["k"]), float(he.get("day", 0)))
				Herds.change(he, to, age, got, "stolen", "driven home from %s" % String(town["name"]), float(he.get("day", 0)))

# ================================================================== drovers (B2)
## A drover with hands and no herd on the road buys beasts where they are cheap and walks them to a road partner
## where they fetch the data's margin more. The walking herd is a record of its own (owner: the drover).
static func _drovers(game, town: Dictionary, e: Dictionary, day: float) -> void:
	var w: Dictionary = game.world
	if not w.has("droves"):
		w["droves"] = {}
	var DV: Dictionary = Herds.A()["drove"]
	for b in e["biz"]:
		if String(b["type"]) != "drover" or b.get("closed", false) or int(b["workers"]) <= 0:
			continue
		var busy := false
		for did in w["droves"]:
			var dv: Dictionary = w["droves"][did]
			if String(dv["from"]) == String(town["id"]) and int(dv["b"]) == int(b["id"]):
				busy = true
		if busy:
			continue
		var best: Array = []
		var bv := 0.0
		for l in Caravans.trade_partners(w, town):
			var o: Dictionary = w["towns"].get(String(l["id"]), {})
			if not TownEcon.has_econ(o) or not o["econ"].has("hd"):
				continue
			for k in GRAZE + ["oxen"]:
				var have := int(Herds.H(e)["ofk"].get(k, 0))
				if have <= 0:
					continue
				var ph := Herds.price(e, k); var pd := Herds.price(o["econ"], k)
				if pd < ph * float(DV["margin"]):
					continue
				var n := mini(have, int(DV["head_hand"]) * int(b["workers"]))
				var v := float(n) * (pd - ph)
				if v > bv:
					bv = v; best = [String(l["id"]), k, float(l.get("dist", (o["pos"] as Vector2).distance_to(town["pos"])))]
		if best.is_empty():
			continue
		var k2 := String(best[1])
		var dh := {"id": -1, "k": k2, "y": 0, "g": 0, "o": 0, "ow": "d", "oi": int(b["id"]), "ot": String(town["id"]), "fod": 0.0, "hun": 0,
			"lac": 0.0, "h0": 0, "d0": int(day), "led": {"b": 0, "in": 0, "out": 0, "sl": 0, "st": 0, "d": {}}, "pl": [], "t": 0}
		var cap := int(DV["head_hand"]) * int(b["workers"])
		var p := Herds.price(e, k2)
		while cap > 0 and float(b["till"]) >= p:
			var o2 := _take_offer(e, k2, ["g", "y"])
			if o2.is_empty():
				break
			var s: Dictionary = Herds.herds(e)[str(int(o2[0]))]
			var pa := Herds.price(e, k2, String(o2[1]))
			if Herds._transfer(e, s, dh, String(o2[1]), 1, "sold", "bought", "to %s, for %s" % [Businesses.title(e, b), String(w["towns"][String(best[0])]["name"])],
					"from %s of %s" % [Herds.owner_text(e, s), String(town["name"])], day) > 0:
				b["till"] = float(b["till"]) - pa
				Herds._add_coin(e, s, pa)
				Herds.H(e)["sok"][k2] = int(Herds.H(e)["sok"].get(k2, 0)) + 1
				cap -= 1
		if Herds.head(dh) <= 0:
			continue
		var did2 := "dv%d" % int(w.get("drove_n", 1))
		w["drove_n"] = int(w.get("drove_n", 1)) + 1
		w["droves"][did2] = {"id": did2, "h": dh, "from": String(town["id"]), "to": String(best[0]), "b": int(b["id"]), "d0": int(day),
			"days": maxi(1, int(ceil(float(best[2]) / float(DV["px_day"]))))}
		_chain(b, "to", String(w["towns"][String(best[0])]["name"]), Herds.head(dh), k2)

## The droves' day (a world work job): each walks on; bandits or a realm at war with its town close by drive it off
## (theft; the beasts end in their stores as meat); at its end the herd joins the town's herds, all of it offered.
static func droves_day(game, day: float) -> void:
	var w: Dictionary = game.world
	var dvs: Dictionary = w.get("droves", {})
	var DV: Dictionary = Herds.A()["drove"]
	for did in dvs.keys():
		var dv: Dictionary = dvs[did]
		var from: Dictionary = w["towns"].get(String(dv["from"]), {})
		var to: Dictionary = w["towns"].get(String(dv["to"]), {})
		if from.is_empty() or to.is_empty():
			dvs.erase(did)
			continue
		var t := clampf((day - float(dv["d0"])) / float(dv["days"]), 0.0, 1.0)
		var pos: Vector2 = (from["pos"] as Vector2).lerp(to["pos"] as Vector2, t)
		dv["pos"] = pos
		var h: Dictionary = dv["h"]
		for wid in w.get("warbands", {}):
			var wb: Dictionary = w["warbands"][wid]
			var kd := String(wb.get("kind", ""))
			if not (kd == "bandit" or (kd in ["raider", "patrol"] and Diplomacy.at_war(w, String(wb["faction"]), String(from["faction"])))):
				continue
			if (wb["pos"] as Vector2).distance_to(pos) > float(DV["raid_px"]):
				continue
			var meals := 0
			for age in AGES:
				var n := int(h[age])
				if n > 0:
					h[age] = 0
					h["led"]["st"] = int(h["led"]["st"]) + n
					meals += int(float(n) * float(Herds.kind(String(h["k"])).get("meat", 0.0)) * float(Herds.A()["yield_age"][AGES.find(age)]) / float(Herds.A()["kg_per_meal"]))
			var st := Supplies.stores(wb)
			st["meat"] = int(st.get("meat", 0)) + meals
			var fe: Dictionary = from["econ"]
			var book: Dictionary = Herds.H(fe)["tot"]
			if not book.has("stolen"):
				book["stolen"] = {}
			book["stolen"][String(h["k"])] = int(book["stolen"].get(String(h["k"]), 0)) + int(h["led"]["st"])
			(Herds.H(fe)["log"] as Array).append([int(day), -1, String(h["k"]), -int(h["led"]["st"]), "stolen", "a drove to %s, by %s" % [String(to["name"]), "outlaws" if kd == "bandit" else CampaignWorld.faction_the(String(wb["faction"]))]])
			TownEcon.town_hist(fe, "A drove of %s bound for %s was driven off on the road." % [Herds.word(fe, String(h["k"])), String(to["name"])], day)
			var bz: Array = fe["biz"]
			if int(dv["b"]) < bz.size():
				_chain(bz[int(dv["b"])], "to", "stolen on the road", int(h["led"]["st"]), String(h["k"]))
			dvs.erase(did)
			break
		if not dvs.has(did):
			continue
		if t >= 1.0:
			var te: Dictionary = to["econ"]
			if not te.has("hd"):
				Herds.migrate(w, to, te)
			var hd := Herds.H(te)
			var id := int(hd["n"])
			hd["n"] = id + 1
			h["id"] = id
			h["h0"] = 0
			h["led"]["in"] = Herds.head(h)
			h["led"]["out"] = 0
			h["da"] = int(day)
			hd["h"][str(id)] = h
			for age in AGES:
				if int(h[age]) > 0:
					(hd["of"] as Array).append([id, age, int(h[age])])
					hd["ofk"][String(h["k"])] = int(hd["ofk"].get(String(h["k"]), 0)) + int(h[age])
			(hd["log"] as Array).append([int(day), id, String(h["k"]), Herds.head(h), "bought", "a drove from %s" % String(from["name"])])
			dvs.erase(did)
