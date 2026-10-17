class_name Shelter
extends RefCounted
## Homeless families (Douglas, economy spec 2 additions). A family whose last home is taken by the head for a
## debt, or falls to ruin, or who are evicted from a rented house, is HOMELESS: they stay in town as squatters
## (history line). DESTITUTE = homeless + broke + no land. Both raise Families.hardship (more recruits, cheaper).
##
## - The town shelter (poorhouse): room for data.shelter base + per_size x size + per_wealth x wealth people.
##   The treasury pays its keep (cost per person per day, into the public works till: the keepers) and feeds broth
##   (low-grade grain out of the granary, else bought from the market) and a little firewood (bought).
##   Broth alone weakens them (f.weak up to 1); the real food they buy themselves heals it. Homeless without a
##   place in the shelter eat strain x faster (no hearth).
## - Casual work: day labourer, porter, rat catcher, kitchen hand (data.casual_jobs): places from what the town
##   really needs (homes, caravans out, granary, people), low wages from the treasury or the market till.
##   Homeless families take them first, before regular hiring (Families.reassign).
## - The way back (never scripted, no floor): what they earn buys real food first (Families._restock), then a
##   rented estate house when they hold two weeks' rent and the estate has an empty one (weekly rent to the
##   treasury; fall behind and they are evicted again), then buying it (or a market-built home), then land or
##   a trade through the ordinary town sales. Sickness, lost jobs and debt knock them back by the same rules
##   as everyone else.
## Per-family-row counts only: f.hl {how, d}, f.shel (in the shelter), f.broth (on broth alone), f.weak, f.cj
## {job: n}, f.rent (houses rented from the estate); town e.shel_n, e.broth_n, e.cjcap / e.cjused {job: n}.

## Rent for an empty estate house: the barge rent (value x 0.008 a month), Barge.rent_week.
static func rent_week(e: Dictionary) -> float:
	return Barge.rent_week(e)

static func D() -> Dictionary:
	return TownEcon.data()["shelter"]

static func cap(town: Dictionary) -> int:
	var s := D()
	return int(s["base"]) + int(s["per_size"]) * int(town.get("size", 0)) + int(s["per_wealth"]) * int(town.get("wealth", 1))

static func homeless(f: Dictionary) -> bool:
	return int(f["homes"]) <= 0 and not f.get("estate", false) and not f.get("gone", false) and Families.people(f) > 0

static func destitute(f: Dictionary) -> bool:
	return homeless(f) and float(f["purse"]) < float(TownEcon.data()["family"]["min_purse"]) \
		and Families.acres(f) == 0 and Families.heads(f) == 0

## The family's last roof is gone ("head": taken for debt, "ruin": fell down, "evicted": rent unpaid).
static func lost_home(e: Dictionary, f: Dictionary, how: String, day: float) -> void:
	if f.has("hl"):
		return
	f["hl"] = {"how": how, "d": int(day)}
	f["named"] = true
	var where := squat_word(e, f)
	Families.add_hist(f, "Homeless now; sleeping in %s." % where, day)
	TownEcon.town_hist(e, "The %s family is out on the street." % f["name"], day)

## Weekly, from the family turn: into the shelter when there is room; a roof again when they can pay for it.
static func turn(town: Dictionary, e: Dictionary, f: Dictionary, day: float) -> void:
	var st := D()
	var days := 7.0
	if TownHousing.try_rent(e, f, day): return
	if int(f["homes"]) > 0:
		# housed: renting pays the treasury weekly; behind on rent -> out again; with savings, buy the house
		if int(f.get("rent", 0)) > 0:
			var due := rent_week(e) * days / 7.0
			if float(f["purse"]) < due:
				Loans.maybe_borrow(e, f, day, due)   # the head may lend the rent (campaign/loans.gd)
			if float(f["purse"]) >= due:
				f["purse"] = float(f["purse"]) - due
				e["treasury"] = float(e["treasury"]) + due
				if float(f["purse"]) >= float(st["estate_home"]) + rent_week(e) * 4.0:
					f["purse"] = float(f["purse"]) - float(st["estate_home"])
					e["treasury"] = float(e["treasury"]) + float(st["estate_home"])
					f["rent"] = 0
					Families.event(f, "owned", [], day)
					Families.add_hist(f, "Bought the house they rented from the town.", day)
			else:
				f["rent"] = 0
				f["homes"] = int(f["homes"]) - 1
				e["fams"][0]["homes"] = int(e["fams"][0]["homes"]) + 1
				Families.event(f, "evicted", [], day)
				Families.add_hist(f, "Fell behind on the rent and lost the house.", day)
				if int(f["homes"]) <= 0:
					lost_home(e, f, "evicted", day)
		if int(f["homes"]) > 0:
			_housed(e, f, day)
			f["weak"] = maxf(0.0, float(f.get("weak", 0.0)) - float(st["recover"]) * days)
			if float(f["weak"]) <= 0.0:
				f.erase("weak")
			return
	if not f.has("hl"):
		lost_home(e, f, "ruin", day)
	var ppl := Families.people(f)
	if not f.get("shel", false) and int(e.get("shel_n", 0)) + ppl <= cap(town):
		f["shel"] = true
		e["shel_n"] = int(e.get("shel_n", 0)) + ppl
		Families.event(f, "shelter", [], day)
		Families.add_hist(f, "Took a place in the town shelter.", day)
	# a roof: buy a market-built home when they can, else rent an empty estate house (not in the week they lost theirs)
	if int(f["hl"]["d"]) >= int(day) - 1:
		return
	var purse := float(f["purse"])
	var hp := float(e["price"].get("home", 200.0))
	var estate: Dictionary = e["fams"][0]
	if int(e["stock"].get("home", 0)) > 0 and purse > hp * 1.2:
		e["stock"]["home"] = int(e["stock"]["home"]) - 1
		TownEcon.led(e, "used", "home", 1)
		TownEcon.pay_market(e, f, hp)
		f["homes"] = 1
		f["cond"] = 1.0
		e["homes"] = int(e["homes"]) + 1
		Families.event(f, "housed", ["buy"], day)
		Families.add_hist(f, "Bought a new home and left the street.", day)
		_housed(e, f, day)
	elif int(estate["homes"]) > 0 and purse >= rent_week(e) * 2.0 + 5.0 * TownEcon.COIN:
		estate["homes"] = int(estate["homes"]) - 1
		f["homes"] = 1
		f["rent"] = 1
		f["cond"] = 0.7
		Families.event(f, "housed", ["rent"], day)
		Families.add_hist(f, "Rented an empty house from the town.", day)
		_housed(e, f, day)

static func _housed(e: Dictionary, f: Dictionary, _day: float) -> void:
	if f.get("shel", false):
		e["shel_n"] = maxi(0, int(e.get("shel_n", 0)) - Families.people(f))
		f.erase("shel")
	if f.get("broth", false):
		e["broth_n"] = maxi(0, int(e.get("broth_n", 0)) - Families.people(f))
		f.erase("broth")
	f.erase("hl")

## The family's food for the turn's days: returns the food store left (< 0 = went hungry). In the shelter the
## broth keeps them fed (unless the shelter ran short) but weakens them; real food of their own heals it.
static func eat(_town: Dictionary, e: Dictionary, f: Dictionary, days: float) -> float:
	var st := D()
	var s: Dictionary = f["store"]
	var food := float(s["food"])
	if f.get("shel", false):
		var was_broth: bool = f.get("broth", false)
		var ppl := Families.people(f)
		if food >= days * 0.5:   # mostly real food of their own
			if was_broth:
				f.erase("broth")
				e["broth_n"] = maxi(0, int(e.get("broth_n", 0)) - ppl)
			f["weak"] = maxf(0.0, float(f.get("weak", 0.0)) - float(st["recover"]) * days)
			return food - days
		if not was_broth:
			f["broth"] = true
			e["broth_n"] = int(e.get("broth_n", 0)) + ppl
		f["weak"] = minf(1.0, float(f.get("weak", 0.0)) + float(st["weaken"]) * days)
		# (one hunger truth: the days short are the share of the broth the kitchen could not serve; it was "a day short
		# when over 30% went unserved")
		return -days * clampf(float(e.get("shelter_short", 0.0)), 0.0, 1.0)
	return food - days * float(st["strain"])

# ================================================================== casual work
static func casual_caps(game, town: Dictionary, e: Dictionary) -> void:
	var cj: Dictionary = TownEcon.data()["casual_jobs"]
	var caps := {}
	var car := 0
	if game != null and game.world.has("warbands"):
		for wid in game.world["warbands"]:
			var wb: Dictionary = game.world["warbands"][wid]
			if wb.get("kind", "") == "caravan" and wb.get("origin", "") == town.get("id", ""):
				car += 1
	for j in cj:
		var per := 0.0
		match String(cj[j]["per"]):
			"homes": per = float(e["homes"])
			"pop": per = float(e["pop"])
			"granary": per = float(e["granary"])
			"caravans": per = float(car)
		caps[j] = int(per * float(cj[j]["k"]))
		if String(cj[j]["per"]) == "granary":
			caps[j] = mini(caps[j], int(float(e["pop"]) * 0.005))   # [ours] a granary needs only so many rat catchers
	TownSanitation.caps(e, caps)
	e["cjcap"] = caps
	if not e.has("cjused"):
		e["cjused"] = {}

## Homeless adults take free casual places (best wage first). Returns how many took work.
static func claim_casual(e: Dictionary, f: Dictionary, spare: int) -> int:
	release_casual(e, f)
	if spare <= 0:
		return 0
	if not e.has("cjcap"):
		casual_caps(null, {}, e)
	var cj: Dictionary = TownEcon.data()["casual_jobs"]
	var used: Dictionary = e["cjused"]
	var ids: Array = cj.keys()
	ids.sort_custom(func(a, b): return float(cj[a]["wage"]) > float(cj[b]["wage"]))
	var mine := {}
	var taken := 0
	var mkt: Dictionary = e["biz"][int(e["mkt"])] if e.has("mkt") else {}
	for j in ids:
		# nobody signs on where the payer cannot pay a week of it
		var fund := float(e.get("treasury", 0.0)) if cj[j]["payer"] == "treasury" else float(mkt.get("till", 0.0))
		if cj[j]["payer"] == "customers": fund = TownSanitation.customer_funds(e)
		if fund < Barge.casual_wage(e, j) * 7.0 * (float(used.get(j, 0)) + 1):
			continue
		var free := int(floor(float(e["cjcap"].get(j, 0)) - float(used.get(j, 0)) + 0.00001))
		var n := mini(free, spare - taken)
		if n <= 0:
			continue
		mine[j] = n
		used[j] = float(used.get(j, 0)) + n
		taken += n
		if taken >= spare:
			break
	if not mine.is_empty():
		f["cj"] = mine
	return taken

static func release_casual(e: Dictionary, f: Dictionary) -> void:
	if not f.has("cj"):
		return
	var used: Dictionary = e.get("cjused", {})
	for j in f["cj"]:
		used[j] = maxf(0, float(used.get(j, 0)) - int(f["cj"][j]))
	f.erase("cj")

## Casual wages for the turn's days, from the treasury or the market till (what they can pay).
static func pay_casual(e: Dictionary, f: Dictionary, days: float) -> void:
	var cj: Dictionary = TownEcon.data()["casual_jobs"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var short := false
	var keys: Array = f.get("cj", {}).keys()
	for j in f.get("cjearned", {}):
		if not keys.has(j): keys.append(j)
	for j in keys:
		var real_service := String(j) in ["rat_catcher", "street_sweeper", "night_soil_man"]
		var earned: Array = f.get("cjearned", {}).get(j, [0.0, 0.0])
		var due := float(earned[1]) if real_service else float(f.get("cj", {}).get(j, 0)) * Barge.casual_wage(e, j) * days
		var pay := 0.0
		if cj[j]["payer"] == "treasury":
			pay = minf(due, maxf(0.0, float(e["treasury"])))
			e["treasury"] = float(e["treasury"]) - pay
		elif cj[j]["payer"] == "customers":
			pay = TownSanitation.collect(e, due)
		else:
			pay = minf(due, maxf(0.0, float(mkt["till"])))
			mkt["till"] = float(mkt["till"]) - pay
		f["purse"] = float(f["purse"]) + pay
		if String(j) in ["rat_catcher", "street_sweeper", "night_soil_man"]:
			var paid: Dictionary = TownSanitation.book(e)["paid_days"]
			paid[j] = float(paid.get(j, 0)) + float(earned[0]) * pay / maxf(0.01, due)
			f.get("cjearned", {}).erase(j)
		if pay < due * 0.5:
			short = true
	if short:
		var released := 0
		for j in f.get("cj", {}): released += int(f["cj"][j])
		release_casual(e, f)   # unpaid day labour: they look for other work at the next reassign
		# Only assigned adult places become idle. Child attendance can be owed
		# without any adult casual job, and several adult places can end together.
		f["idle"] = int(f.get("idle", 0)) + released
		e["idle_n"] = int(e.get("idle_n", 0)) + released

## The family leaves town or dies out: its shelter place and casual work are free again; a rented house goes
## back to the town estate.
static func forget(e: Dictionary, f: Dictionary) -> void:
	release_casual(e, f)
	TownHousing.leave(e, f, float(e.get("day", 0)))
	_housed(e, f, 0.0)
	if int(f.get("rent", 0)) > 0 and int(f["homes"]) > 0:
		f["homes"] = int(f["homes"]) - 1
		e["fams"][0]["homes"] = int(e["fams"][0]["homes"]) + 1
		f["rent"] = 0

# ================================================================== the daily shelter (town pass)
## Broth for those living on it, the keepers' wages and a little firewood, all paid by the treasury out of real
## stock: granary grain first (the town's own), then market grain and wood bought at the price.
static func daily(_town: Dictionary, e: Dictionary) -> void:
	var sn := int(e.get("shel_n", 0))
	if sn <= 0:
		e["shelter_short"] = 0.0
		return
	var st := D()
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var stock: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var lu: Dictionary = e["led"]["used"]
	var need := int(ceil(float(e.get("broth_n", 0)) * float(st["broth"])))
	var got := mini(need, int(e["granary"]))
	e["granary"] = int(e["granary"]) - got
	if got > 0:
		lu["grain"] = int(lu.get("grain", 0)) + got
	var rest := need - got
	if rest > 0:
		var p := float(price.get("grain", 0.5))
		var n := mini(rest, mini(int(stock.get("grain", 0)), int(maxf(0.0, float(e["treasury"])) / maxf(0.01, p))))
		if n > 0:
			stock["grain"] = int(stock["grain"]) - n
			lu["grain"] = int(lu.get("grain", 0)) + n
			e["treasury"] = float(e["treasury"]) - float(n) * p
			mkt["till"] = float(mkt["till"]) + float(n) * p
			got += n
	e["shelter_short"] = 1.0 - float(got) / float(need) if need > 0 else 0.0
	# firewood (fractional carry)
	var wc := float(e.get("shel_wood", 0.0)) + float(sn) * float(st["wood"])
	var wn := int(floor(wc))
	if wn > 0:
		var pw := float(price.get("wood", 0.5))
		var k := mini(wn, mini(int(stock.get("wood", 0)), int(maxf(0.0, float(e["treasury"])) / maxf(0.01, pw))))
		if k > 0:
			stock["wood"] = int(stock["wood"]) - k
			lu["wood"] = int(lu.get("wood", 0)) + k
			e["treasury"] = float(e["treasury"]) - float(k) * pw
			mkt["till"] = float(mkt["till"]) + float(k) * pw
		wc -= float(wn)
	e["shel_wood"] = wc
	# the keepers: wages into the public works till (which pays its hired hands)
	var cost := minf(float(sn) * float(st["cost"]), maxf(0.0, float(e["treasury"])))
	if cost > 0.0:
		e["treasury"] = float(e["treasury"]) - cost
		var keep: Dictionary = e["biz"][int(e["works_biz"])] if e.has("works_biz") else mkt
		keep["till"] = float(keep["till"]) + cost
	e["stats"]["shelter_cost"] = cost

## Weekly (town turn): recount the shelter (people come and go) and the casual places.
static func weekly(game, town: Dictionary, e: Dictionary) -> void:
	var sn := 0; var bn := 0; var away := 0
	var used := {}
	for f in e["fams"]:
		if f.get("gone", false):
			continue
		if not f.get("child_cj", {}).is_empty(): f["child_work_changed"] = true
		var sv: Dictionary = f.get("serve", {})
		for k in sv:
			if k in ["army", "bandit", "deserter"]:   # soldiers and outlaws eat out of their force's stores, not at home
				away += int(sv[k])
		if f.get("shel", false):
			sn += Families.people(f)
			if f.get("broth", false):
				bn += Families.people(f)
		f.erase("child_cj") # Recheck age, health and funded places each week. Earned pay remains due.
		for j in f.get("cj", {}):
			used[j] = float(used.get(j, 0)) + int(f["cj"][j])
	e["shel_n"] = sn
	e["broth_n"] = bn
	e["away_n"] = away
	e["cjused"] = used
	casual_caps(game, town, e)
	assign_child_cleanup(e, float(game.day) if game != null else 0.0)

# ================================================================== words
## Where a homeless family sleeps: the shelter, or a corner of some business of the town (seeded per family).
static func squat_word(e: Dictionary, f: Dictionary) -> String:
	if f.get("shel", false):
		return "the town poorhouse"
	var spots := []
	for b in e.get("biz", []):
		if not b.get("closed", false) and b["type"] in ["brewer", "smelter", "carpenter", "tanner", "weaver", "vintner", "market"]:
			spots.append(b["type"])
	if spots.is_empty():
		return "the lee of the town wall"
	var t: String = spots[absi(int(f.get("seed", 0))) % spots.size()]
	return {"brewer": "the brewery's malt loft", "smelter": "the warm ash pit behind the smelter", "carpenter": "the carpenter's woodshed",
		"tanner": "the tannery shed", "weaver": "the weaver's back room", "vintner": "the press house", "market": "the market stalls"}.get(t, "a shed")

## Family record line: "Sleeping in the town poorhouse on bone broth since the spring of year 1; weakened."
static func state_line(e: Dictionary, f: Dictionary) -> String:
	var hl: Dictionary = f.get("hl", {})
	var since := ""
	if not hl.is_empty():
		since = " since the %s of year %d" % [Calendar.season(float(hl["d"])), Calendar.year(float(hl["d"]))]
	var how: String = {"head": "The %s took their house" % e.get("head", {}).get("title", "head"), "ruin": "Their house fell to ruin",
		"evicted": "Evicted for unpaid rent", "debt": "Their house was sold for debt", "moved": "Came to town with no house to go to"}.get(String(hl.get("how", "")), "Homeless")
	var where := ""
	if f.get("shel", false):
		where = "living in the town poorhouse%s" % (" on bone broth" if f.get("broth", false) else ", buying what food they can")
	else:
		where = "sleeping in %s (no room in the poorhouse)" % squat_word(e, f)
	var w := float(f.get("weak", 0.0))
	return "%s; %s%s%s." % [how, where, since, "; weakened" if w >= 0.3 else ""]

## All spare adults compare casual work with other vacancies by its real wage.
static func available_casual(e: Dictionary, job: String) -> int:
	var cj: Dictionary = TownEcon.data()["casual_jobs"][job]
	var used := float(e.get("cjused", {}).get(job, 0))
	var places := maxi(0, int(floor(float(e.get("cjcap", {}).get(job, 0)) - used + 0.00001)))
	if places <= 0: return 0
	var funds := float(e.get("treasury", 0)) if cj["payer"] == "treasury" else float(e["biz"][int(e["mkt"])]["till"])
	if cj["payer"] == "customers": funds = TownSanitation.customer_funds(e)
	var funded := int(floor(funds / maxf(0.01, Barge.casual_wage(e, job) * 7) - used + 0.00001))
	return mini(places, maxi(0, funded))

## Daily attendance is counted from registered people, including bed rest and militia service.
static func accrue_sanitation(e: Dictionary, day: float) -> void:
	for f in e["fams"]:
		if f.get("gone", false) or (f.get("cj", {}).is_empty() and f.get("child_cj", {}).is_empty()): continue
		var work := Persons.work(e, f)
		for pid in work:
			var j := String(work[pid].get("cj", ""))
			if not j in ["rat_catcher", "street_sweeper", "night_soil_man"]: continue
			var c := Sickness.case_of(f, int(pid))
			if not c.is_empty() and int(c[Sickness.C_BED]) == 1 and Sickness.sick_phase(c, day): continue
			if not f.has("cjearned"): f["cjearned"] = {}
			var earned: Array = f["cjearned"].get(j, [0.0, 0.0])
			var share := float(work[pid].get("share", 1.0))
			earned[0] += share; earned[1] += Barge.casual_wage(e, j) * share
			f["cjearned"][j] = earned


## Children of the existing helper age do short cleanup shifts, never a full adult shift.
static func cleanup_child_eligible(e: Dictionary, p: Array, day: float) -> bool:
	var sc := float(People.ages(Persons.race_of(e))["adult"]) / 16.0
	var years := (day - float(p[3])) / People.year_days()
	return int(p[6]) == 2 and String(p[4]) == "" and years >= float(Barge.B()["labour"]["kid_from"]) * sc and years < float(People.ages(Persons.race_of(e))["adult"])

static func assign_child_cleanup(e: Dictionary, day: float) -> void:
	var share := float(Barge.B()["labour"]["kid_share"])
	var jobs := ["street_sweeper", "rat_catcher", "night_soil_man"]
	jobs.sort_custom(func(a, b): return Barge.casual_wage(e, a) > Barge.casual_wage(e, b))
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		for p in Persons.kp(f):
			if not cleanup_child_eligible(e, p, day): continue
			var c := Sickness.case_of(f, int(p[0]))
			if not c.is_empty() and int(c[Sickness.C_BED]) == 1 and Sickness.sick_phase(c, day): continue
			for j in jobs:
				var used := float(e["cjused"].get(j, 0))
				if float(e["cjcap"].get(j, 0)) - used + 0.00001 < share: continue
				var payer := String(TownEcon.data()["casual_jobs"][j]["payer"])
				var fund := TownSanitation.customer_funds(e) if payer == "customers" else float(e["treasury"])
				if fund + 0.00001 < Barge.casual_wage(e, j) * 7 * (used + share): continue
				if not f.has("child_cj"): f["child_cj"] = {}
				f["child_cj"][str(int(p[0]))] = j
				f["child_work_changed"] = true
				e["cjused"][j] = used + share
				break
	# Refresh the farm's actual output fraction as well as its helper count.
	for f in e["fams"]:
		if f.get("child_work_changed", false):
			Families.reassign(e, f)
			f.erase("child_work_changed")
