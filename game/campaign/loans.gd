class_name Loans
extends RefCounted
## The head's loans (economy spec 1 section 7, extended by Douglas's playtest): one loop per family.
##
##   borrow   the head lends real coin from the treasury to a family short of food, rent, tools, seed or land
##            (and an unpaid tax becomes the same kind of debt, without coin moving). Credit is capped by what the
##            family owns and earns; no new loans while it is behind.
##   repay    weekly instalments from the purse (wages, harvest claims): interest first, then principal.
##   interest accrues weekly on the unpaid balance at the culture's rate (data/economy.json cultures[].loan_rate)
##            [ours]; a family that is behind pays more (x(1 + behind_mult x missed payments)).
##   default  missed default_after payments in a row: the family must sell its things, in order, every sale real
##            at going prices with the buyer paying: stores and spare household goods (to the market), tools (to
##            the market), livestock and land (to a family that can pay, else the head buys at the going price:
##            his last resort, the land goes to the town estate), then the house (to the market as a home for sale,
##            else the head), each sale paying the debt down until it is cleared or nothing is left.
##            Nothing left: the debt is written off, the family is destitute and homeless (Shelter, recruit pool).
##
## family["ln"] (only while in debt or after a default): {rate (per week), pay (instalment), miss (in a row),
##   lent, int (interest paid), sold [lines]}; family.debt is the balance (principal + unpaid interest).
## econ["stats"]: lent (coin lent out, total), int_earned, written_off; econ["loans"] book is the sum of debts.

static func L() -> Dictionary:
	return TownEcon.data()["loans"]

static func rate(e: Dictionary) -> float:
	return float(TownEcon.culture_of(e).get("loan_rate", L()["rate"]))

static func _ln(e: Dictionary, f: Dictionary) -> Dictionary:
	if not f.has("ln"):
		f["ln"] = {"rate": rate(e), "pay": 0.0, "miss": 0, "lent": 0.0, "int": 0.0, "sold": []}
	return f["ln"]

## What the head will still lend this family: a share of what it owns plus a few weeks of its labour.
static func credit_left(e: Dictionary, f: Dictionary) -> float:
	var C := L()
	var land: Dictionary = TownEcon.data()["land"]
	var worth := float(Families.acres(f)) * float(land["acre_price"]) + float(Families.heads(f)) * float(land["head_price"])
	worth += float(f["homes"]) * float(TownEcon.data()["shelter"]["estate_home"])
	var cap := float(C["per_adult"]) * float(Families.adults(f)) + worth * float(C["of_worth"])
	return maxf(0.0, cap - float(f["debt"]))

static func _reserve(e: Dictionary) -> float:
	return float(L()["treasury_reserve"]) * (1.0 + float(e["pop"]) / 300.0)

## Pure quote under the existing credit, arrears and treasury-reserve rules.
## Purchases can choose a feasible quantity before creating any real debt.
static func quote(e: Dictionary, f: Dictionary, amount: float) -> float:
	if f.get("gone", false) or f.has("estate") or f.get("destitute", false) or int(f.get("ln", {}).get("miss", 0)) > 0:
		return 0.0
	var a := floorf(minf(amount, minf(credit_left(e, f), float(e["treasury"]) - _reserve(e))))
	return a if a >= 1.0 else 0.0

## Lend up to `amount` of real coin (treasury -> purse). Returns what was lent.
static func lend(e: Dictionary, f: Dictionary, amount: float, why: String, day: float) -> float:
	if f.get("gone", false) or f.has("estate") or f.get("destitute", false):
		return 0.0
	var ln := _ln(e, f)
	if int(ln["miss"]) > 0:
		return 0.0   # no new money while behind
	var a := quote(e, f, amount)
	if a < 1.0:
		return 0.0
	e["treasury"] = float(e["treasury"]) - a
	f["purse"] = float(f["purse"]) + a
	_add_debt(e, f, a, day)
	ln["lent"] = float(ln["lent"]) + a
	e["stats"]["lent"] = float(e["stats"].get("lent", 0.0)) + a
	var head_title: String = e.get("head", {}).get("title", "head")
	Families.event(f, "borrow", [int(a), head_title, why], day)
	if f["named"]:
		Families.add_hist(f, "Borrowed %d coins from the %s for %s." % [int(a), head_title, why], day)
	return a

## Owed without coin moving (an unpaid tax). Same loan, same schedule.
static func owe(e: Dictionary, f: Dictionary, amount: float, day: float) -> void:
	_add_debt(e, f, amount, day)

static func _add_debt(e: Dictionary, f: Dictionary, a: float, day: float) -> void:
	var ln := _ln(e, f)
	f["debt"] = float(f["debt"]) + a
	if float(f["loan_day"]) < 0.0:
		f["loan_day"] = day
	ln["rate"] = rate(e)
	ln["pay"] = maxf(float(ln["pay"]), ceilf(float(f["debt"]) / float(L()["term_weeks"])))

## The family turn asks for coin when it cannot buy a week of what it needs (food, drink, firewood), the rent,
## or (landholders, in spring) seed and tools. Returns what was lent.
static func maybe_borrow(e: Dictionary, f: Dictionary, day: float, rent_due: float = 0.0) -> float:
	if f.get("destitute", false) or int(f.get("ln", {}).get("miss", 0)) > 0:
		return 0.0
	var r := Families.daily_rates(e, f)
	var price: Dictionary = e["price"]
	var st: Dictionary = f["store"]
	var want := 0.0
	var why := ""
	if float(st["food"]) < 7.0:
		want += (14.0 - float(st["food"])) * float(r["food"]) * float(price["grain"])
		why = "food"
	if float(st["wood"]) < 3.0 and float(r["wood"]) > 0.0:
		want += 7.0 * float(r["wood"]) * float(price["wood"])
		if why == "": why = "firewood"
	if rent_due > 0.0:
		want += rent_due
		why = "the rent"
	if Families.acres(f) > 0 and Calendar.season_index(day) == 0 and float(f["wear"].get("tools", 0.0)) >= 0.5:
		want += float(Families.acres(f)) * float(L()["seed_per_acre"]) + float(price["tools"])
		if why == "": why = "seed and tools"
	var short := want - maxf(0.0, float(f["purse"]) - 2.0 * TownEcon.COIN)
	if short < 3.0 * TownEcon.COIN:
		return 0.0
	# barge part 2 section 7 (coping ladder 4): a county loan of up to 1,500 when a member earns and the treasury holds
	# over 150,000 [ours: scaled to the town's people / 8,000]
	var C := L()
	if float(f.get("inc", 0.0)) <= 0.0 and Families.job_total(f) <= 0 and int(f.get("hands", 0)) <= 0:
		return 0.0
	if float(e["treasury"]) < float(C.get("county_min", 0.0)) * maxf(1.0, float(e.get("pop0", e["pop"]))) / 8000.0:
		return 0.0
	return lend(e, f, minf(short, float(C.get("county_loan", short))), why, day)

## Weekly: interest on the balance, the instalment out of the purse, default when too many are missed.
static func weekly(e: Dictionary, f: Dictionary, day: float, days: float) -> void:
	var debt := float(f["debt"])
	if debt <= 0.0:
		return
	var C := L()
	var ln := _ln(e, f)
	if float(ln["pay"]) <= 0.0:
		ln["pay"] = ceilf(debt / float(C["term_weeks"]))   # a debt without a schedule (older saves) gets one
	var behind := 1.0 + float(C["behind_mult"]) * float(ln["miss"])
	var interest := debt * float(ln["rate"]) * behind * days / 7.0
	debt += interest
	ln["acc"] = float(ln.get("acc", 0.0)) + interest   # interest owed, not yet paid
	var due := maxf(float(ln["pay"]), float(ln["acc"])) * days / 7.0
	var can := maxf(0.0, float(f["purse"]) - float(TownEcon.data()["family"]["min_purse"]))
	var spare := maxf(0.0, float(f["purse"]) - float(C["prepay_above"]))
	var pay := minf(debt, minf(can, maxf(due, spare)))
	_pay(e, f, ln, pay)
	debt -= pay
	if pay >= due * 0.95 or debt <= 0.01:
		ln["miss"] = 0
		f["loan_day"] = day   # loan_day = the last full instalment (the term runs from there)
	else:
		ln["miss"] = int(ln["miss"]) + 1
	f["debt"] = maxf(0.0, debt)
	if debt <= 0.01:
		f["debt"] = 0.0
		f["loan_day"] = -1.0
		ln["pay"] = 0.0
		ln["acc"] = 0.0
		return
	# default: too many payments missed in a row, or (spec 7's rule) a debt unpaid past the loan term
	var overdue := float(f["loan_day"]) >= 0.0 and day - float(f["loan_day"]) >= float(TownEcon.data()["tax"]["loan_weeks"]) * 7.0
	if int(ln["miss"]) >= int(C["default_after"]) or (overdue and int(ln["miss"]) > 0):
		default(e, f, day)

## Coin from the purse to the treasury, interest first.
static func _pay(e: Dictionary, f: Dictionary, ln: Dictionary, pay: float) -> void:
	if pay <= 0.0:
		return
	f["purse"] = float(f["purse"]) - pay
	e["treasury"] = float(e["treasury"]) + pay
	var to_int := minf(pay, float(ln.get("acc", 0.0)))
	ln["acc"] = float(ln.get("acc", 0.0)) - to_int
	ln["int"] = float(ln["int"]) + to_int
	e["stats"]["int_earned"] = float(e["stats"].get("int_earned", 0.0)) + to_int
	e["stats"]["repaid"] = float(e["stats"].get("repaid", 0.0)) + pay

## Sale proceeds pay the debt down at once (the rest stays in the purse).
static func _settle_from_sale(e: Dictionary, f: Dictionary, ln: Dictionary, got: float, what: String) -> void:
	f["purse"] = float(f["purse"]) + got
	var pay := minf(float(f["debt"]), float(f["purse"]))
	_pay(e, f, ln, pay)
	f["debt"] = maxf(0.0, float(f["debt"]) - pay)
	var sold: Array = ln["sold"]
	sold.append("%s (%d coins)" % [what, int(round(got))])
	while sold.size() > 12:
		sold.pop_front()

## Default: sell everything in order until the debt is cleared. Every sale is real: the buyer pays the going price.
static func default(e: Dictionary, f: Dictionary, day: float) -> void:
	var ln := _ln(e, f)
	var head_title: String = e.get("head", {}).get("title", "head")
	var sold0: int = (ln["sold"] as Array).size()
	f["named"] = true
	# 1. stores, 2. spare household goods, 3. tools: out of the household pool into the market, the market pays
	for step in [["food", "drink", "wood"], ["jewelry", "furniture", "blankets", "clothing"], ["tools"]]:
		if float(f["debt"]) <= 0.01:
			break
		for g in step:
			if float(f["debt"]) <= 0.01:
				break
			_sell_goods(e, f, ln, g)
	# 4. livestock, 5. land: to a family that can pay, else the head buys at the going price (to the estate)
	var land: Dictionary = TownEcon.data()["land"]
	var lost_txt := []
	for a in (f["herd"] as Dictionary).keys():
		if float(f["debt"]) <= 0.01:
			break
		var n := mini(int(f["herd"][a]), int(ceil(float(f["debt"]) / float(land["head_price"]))))
		var got := _sell_holding(e, f, "herd", a, n, float(land["head_price"]))
		if got > 0.0:
			lost_txt.append(TownEcon.n_of(n, a))
			_settle_from_sale(e, f, ln, got, TownEcon.n_of(n, a))
	for c in (f["land"] as Dictionary).keys():
		if float(f["debt"]) <= 0.01:
			break
		var n2 := mini(int(f["land"][c]), int(ceil(float(f["debt"]) / float(land["acre_price"]))))
		var got2 := _sell_holding(e, f, "land", c, n2, float(land["acre_price"]))
		if got2 > 0.0:
			var w := "%s of %s" % [TownEcon.n_of(n2, "acres"), TownEcon.variety_word(e, c)]
			lost_txt.append(w)
			_settle_from_sale(e, f, ln, got2, w)
	if not lost_txt.is_empty():
		var what := " and ".join(PackedStringArray(lost_txt))
		f["lost"] = {"what": what, "to": head_title, "season": Calendar.season(day), "year": Calendar.year(day)}
		Families.event(f, "sold_land", [what, head_title], day)
		Families.add_hist(f, "Had to sell %s for the debt." % what, day)
	# 6. the house
	if float(f["debt"]) > 0.01 and int(f["homes"]) > 0:
		_sell_house(e, f, ln, day, head_title)
	# what was sold, in one line for the town
	var sold: Array = ln["sold"]
	if sold.size() > sold0:
		TownEcon.town_hist(e, "The %s family sold %s to pay the %s." % [f["name"], ", ".join(PackedStringArray(sold.slice(sold0).map(func(s): return String(s).split(" (")[0]))), head_title], day)
	ln["miss"] = 0
	if float(f["debt"]) <= 0.01:
		f["debt"] = 0.0
		f["loan_day"] = -1.0
		ln["pay"] = 0.0
		ln["acc"] = 0.0
		return
	# nothing left: destitute (the debt cannot be paid; the head writes it off), homeless when the house went
	e["stats"]["written_off"] = float(e["stats"].get("written_off", 0.0)) + float(f["debt"])
	f["debt"] = 0.0
	f["loan_day"] = -1.0
	ln["pay"] = 0.0
	ln["acc"] = 0.0
	f["destitute"] = true
	f["ruined"] = true
	Families.event(f, "destitute", [head_title], day)
	Families.add_hist(f, "Destitute: everything sold and still in debt; the %s wrote off the rest." % head_title, day)

## The family's share of a household-pool good: its stores (food, drink, firewood, in days) or its share of the
## pool's household goods. Sold into the market at the market's buying price (the market pays).
static func _sell_goods(e: Dictionary, f: Dictionary, ln: Dictionary, g: String) -> void:
	var hh: Dictionary = e["hh"]
	var have := 0
	var r := Families.daily_rates(e, f)
	var st: Dictionary = f["store"]
	if g == "food":
		have = int(float(st["food"]) * float(r["food"]))
	elif g == "drink":
		have = int(float(st["drink"]) * float(r["drink"]))
	elif g == "wood":
		have = int(float(st["wood"]) * float(r["wood"]))
	else:
		var basis := float(Families.people(f)) / maxf(1.0, float(e["pop"])) if g == "clothing" else \
			(float(Families.adults(f)) / maxf(1.0, float(e["adults"])) if g == "tools" else float(f["homes"]) / maxf(1.0, float(e["homes"])))
		have = int(float(hh.get(g, 0)) * basis)
	if have <= 0:
		return
	var goods: Array = ["grain", "fruit", "meat"] if g == "food" else (["beer", "wine"] if g == "drink" else [g])
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var share := float(TownEcon.data()["market"]["buy_share"])
	var got := 0.0
	var left := have
	for gg in goods:
		var q := mini(left, int(hh.get(gg, 0)))
		if q <= 0:
			continue
		var p := float(e["price"][gg]) * share
		q = mini(q, int(maxf(0.0, float(mkt["till"])) / maxf(0.01, p)))
		if q <= 0:
			continue
		hh[gg] = int(hh[gg]) - q
		e["stock"][gg] = int(e["stock"].get(gg, 0)) + q
		mkt["till"] = float(mkt["till"]) - float(q) * p
		got += float(q) * p
		left -= q
	if got <= 0.0:
		return
	if g in ["food", "drink", "wood"]:
		st[g] = maxf(0.0, float(st[g]) - float(have - left) / maxf(0.01, float(r[g])))
	var word: String = {"food": "the food stores", "drink": "the beer and wine", "wood": "the firewood"}.get(g, Goods.good_name(g))
	_settle_from_sale(e, f, ln, got, word)

## Herd or land to the best-off family that can pay and work it, else the head (treasury -> estate). Returns gold.
static func _sell_holding(e: Dictionary, f: Dictionary, kind: String, key: String, n: int, unit: float) -> float:
	if n <= 0:
		return 0.0
	var cost := float(n) * unit
	var buyer: Dictionary = {}
	for b in e["fams"]:
		if b == f or b.get("gone", false) or b.has("estate") or float(b.get("debt", 0.0)) > 0.0:
			continue
		if float(b["purse"]) >= cost + 40.0 * TownEcon.COIN and float(Families.adults(b)) - Families.need_hands(b, e) >= 0.5:
			if buyer.is_empty() or float(b["purse"]) > float(buyer["purse"]):
				buyer = b
	var est: Dictionary = e["fams"][0]
	if buyer.is_empty():
		if float(e["treasury"]) < cost:
			n = int(float(e["treasury"]) / unit)
			cost = float(n) * unit
			if n <= 0:
				return 0.0
		e["treasury"] = float(e["treasury"]) - cost
		buyer = est
	else:
		buyer["purse"] = float(buyer["purse"]) - cost
		Families.add_hist(buyer, "Bought %d %s from the %s family." % [n, key if kind == "herd" else "acres of " + TownEcon.variety_word(e, key), f["name"]], float(e["day"]))
	if kind == "herd":
		Families.move_herd(e, f, buyer, key, n)
	else:
		Families.move_land(e, f, buyer, key, n)
	if not buyer.has("estate"):
		Families.reassign(e, buyer)
	Families.reassign(e, f)
	return cost

## A cash-starved farm offers at most a quarter of one crop holding per week.
## Reuse the native purchase preview and physical land/ox/plot transfer.
## No public bailout: a buyer must own the coin AND have spare labour.
static func sell_for_payroll(e: Dictionary, f: Dictionary, farm: Dictionary) -> void:
	var day: int = int(e.get("day", 0))
	if day - int(farm.get("payroll_sale_day", day - 7)) < 7: return
	farm["payroll_sale_day"] = day
	var bill: float = float(maxi(int(farm["workers"]), int(farm["cap"]))) * float(farm["wage"])
	var gap: float = maxf(0.0, float(farm.get("owed", 0.0)) + bill * 8.0 - float(farm["till"]) - Businesses.farm_kind_value(e, farm))
	if gap <= 0.0: return
	var D: Dictionary = TownEcon.data()
	var buyers: Array = e["fams"].filter(func(b): return int(b["id"]) != int(f["id"]) and not b.get("gone", false) and not b.get("estate", false) and float(b.get("debt", 0.0)) <= 0.0)
	buyers.sort_custom(func(a, b): return float(a["purse"]) > float(b["purse"]))
	for crop in f["land"].keys():
		var base: float = maxf(0.01, float(D["goods"].get(crop, {}).get("price", 1.0)))
		var unit: float = float(D["land"]["acre_price"]) * maxf(0.01, float(e["price"].get(crop, base))) / base
		var limit: int = mini(int(ceil(float(f["land"][crop]) * 0.25)), int(ceil(gap / unit)))
		if limit <= 0: continue
		for buyer in buyers:
			var afford: int = maxi(0, int(floor((float(buyer["purse"]) - 40.0 * TownEcon.COIN) / unit)))
			# Sorted current purses: every remaining buyer is also unable to pay.
			if afford <= 0: break
			var n: int = TownEcon._purchase_acres(e, f, buyer, String(crop), mini(limit, afford))
			if n <= 0: continue
			Families.move_land(e, f, buyer, String(crop), n)
			var cost: float = float(n) * unit
			buyer["purse"] = float(buyer["purse"]) - cost
			f["purse"] = float(f["purse"]) + cost
			Families.add_hist(f, "Sold %d acres to %s for %d coins to fund the farm's wages." % [n, buyer["name"], int(cost)], float(day))
			Families.add_hist(buyer, "Bought %d acres from %s for %d coins." % [n, f["name"], int(cost)], float(day))
			Families.reassign(e, buyer)
			Families.reassign(e, f)
			return

## The house: into the market as a home for sale (the market pays its buying price), else the head takes it at
## the estate's price. The family is homeless after.
static func _sell_house(e: Dictionary, f: Dictionary, ln: Dictionary, day: float, head_title: String) -> void:
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var p := float(e["price"]["home"]) * float(TownEcon.data()["market"]["buy_share"])
	var got := 0.0
	if float(mkt["till"]) >= p:
		mkt["till"] = float(mkt["till"]) - p
		e["stock"]["home"] = int(e["stock"].get("home", 0)) + 1
		TownEcon.led(e, "made", "home", 1)   # back on the market as a home for sale
		got = p
	else:
		var p2 := minf(float(TownEcon.data()["shelter"]["estate_home"]), maxf(0.0, float(e["treasury"])))
		e["treasury"] = float(e["treasury"]) - p2
		e["fams"][0]["homes"] = int(e["fams"][0]["homes"]) + 1
		got = p2
	f["homes"] = int(f["homes"]) - 1
	e["homes"] = int(e["homes"]) - 1
	var ht: String = TownEcon.culture_of(e)["home"]["type"]
	Families.event(f, "sold_house", [ht, head_title], day)
	Families.add_hist(f, "Had to sell the family's %s for the debt." % ht, day)
	_settle_from_sale(e, f, ln, got, "the %s" % ht)
	if int(f["homes"]) <= 0:
		Shelter.lost_home(e, f, "debt", day)

# ================================================================== reports
static func book(e: Dictionary) -> Dictionary:
	var out := 0.0; var arrears := 0; var n := 0
	for f in e["fams"]:
		if f.get("gone", false):
			continue
		var d := float(f.get("debt", 0.0))
		if d > 0.0:
			out += d
			n += 1
			if int(f.get("ln", {}).get("miss", 0)) > 0:
				arrears += 1
	return {"owed": out, "debtors": n, "arrears": arrears, "lent": float(e["stats"].get("lent", 0.0)),
		"interest": float(e["stats"].get("int_earned", 0.0)), "written_off": float(e["stats"].get("written_off", 0.0))}

## "Owes the reeve 120 gold at 2% a week, 2 payments missed; sold: 4 sheep, 6 acres of barley."
static func family_line(e: Dictionary, f: Dictionary) -> String:
	var ln: Dictionary = f.get("ln", {})
	var head_title: String = e.get("head", {}).get("title", "head")
	var parts := []
	if float(f.get("debt", 0.0)) > 0.5:
		parts.append("owes the %s %d coins at %s a week (instalment %d)" % [head_title, int(f["debt"]),
			_pct(float(ln.get("rate", rate(e)))), int(ln.get("pay", 0.0))])
		if int(ln.get("miss", 0)) > 0:
			parts.append("%d payment%s missed" % [int(ln["miss"]), "" if int(ln["miss"]) == 1 else "s"])
	if float(ln.get("lent", 0.0)) > 0.0:
		parts.append("borrowed %d in all, %d paid in interest" % [int(ln["lent"]), int(ln.get("int", 0.0))])
	if not (ln.get("sold", []) as Array).is_empty():
		parts.append("sold: " + ", ".join(PackedStringArray(ln["sold"])))
	if f.get("destitute", false):
		parts.append("destitute")
	return "" if parts.is_empty() else "Debt: " + "; ".join(PackedStringArray(parts)) + "."

static func _pct(r: float) -> String:
	return ("%.1f%%" % (r * 100.0)).replace(".0%", "%")

static func town_line(e: Dictionary) -> String:
	var b := book(e)
	return "Loans: %d coins owed by %d families (%d in arrears); %d coins lent out in all, %d earned in interest, %d written off; rate %s a week." % [
		int(b["owed"]), int(b["debtors"]), int(b["arrears"]), int(b["lent"]), int(b["interest"]), int(b["written_off"]), _pct(rate(e))]
