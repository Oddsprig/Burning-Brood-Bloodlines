class_name CampaignRestJob
extends "res://campaign/campaign_turn_job.gd"
## Remaining measured daily kernels. Reuse the accepted frame/observer/save hold.
## Checkpoints retain native coroutine locals, iteration order and RNG streams.
const REST_KINDS: Array = ["econ", "bday"]
# Test-only exact boundaries; empty in production, never in world/save state.
var test_force_labels: Dictionary = {}
var test_forced_labels: Dictionary = {}

func _init(job: Array) -> void:
	super(job)

static func prepare_rest_head(w: Dictionary) -> void:
	var work: Array = w.get("work", [])
	if work.is_empty() or not (work[0] is Array):
		return
	var head: Array = work[0]
	if head.is_empty() or String(head[0]) not in REST_KINDS or head[-1] is Object:
		return
	head.append(CampaignRestJob.new(head))

static func reserve_rest_job(game: Variant, job: Array, budgeted: bool) -> bool:
	if not budgeted or String(job[0]) not in REST_KINDS:
		return false
	var work: Array = game.world["work"]
	work.push_front(job)
	prepare_rest_head(game.world)
	var run: CampaignDayJob = job[-1]
	game._day_job_begin_dispatch()
	game._day_job_claim(run)
	run.hold(game)
	game._note_day_job_slice()
	game._day_job_cancel_dispatch()
	return true

func _checkpoint(label: String) -> void:
	if budgeted and test_force_labels.has(label) and not test_forced_labels.has(label) and int(visits.get(label, 0)) + 1 >= int(test_force_labels[label]):
		test_forced_labels[label] = true
		_deadline_usec = 0
	await super._checkpoint(label)

func _run(game: Variant) -> void:
	var town: Dictionary = game.world["towns"].get(header[1], {})
	if not town.is_empty():
		if header[0] == "econ":
			await _rest_town_econ_daily_pass(game, town, int(header[2]), false)
		else:
			await _rest_town_econ_barge_day(game, town, int(header[2]))
	_finished = true

## Native game/campaign/town_econ.gd:400; operations retained in original order.
func _rest_town_econ_daily_pass(game: Variant, town: Dictionary, day: int, with_barge: bool = true) -> void:
	await _checkpoint("TownEcon.daily_pass")
	await _checkpoint("TownEcon.daily_pass:line:401")
	if not TownEcon.has_econ(town):
		return
	await _checkpoint("TownEcon.daily_pass:line:403")
	var e: Dictionary = town["econ"]
	await _checkpoint("TownEcon.daily_pass:line:404")
	if int(e.get("day", -1)) >= day:
		return
	await _checkpoint("TownEcon.daily_pass:line:406")
	await _rest_town_econ_market_day(game, town, e, day)
	await _checkpoint("TownEcon.daily_pass:line:407")
	if with_barge:
		await _rest_town_econ_barge_day(game, town, day)

## Native game/campaign/town_econ.gd:410; operations retained in original order.
func _rest_town_econ_market_day(game: Variant, town: Dictionary, e: Dictionary, day: int) -> void:
	await _checkpoint("TownEcon._market_day")
	await _checkpoint("TownEcon._market_day:line:411")
	var t0: int = Time.get_ticks_usec() if TownEcon.prof_on else 0
	await _checkpoint("TownEcon._market_day:line:412")
	e["day"] = day
	await _checkpoint("TownEcon._market_day:day_written")
	await _checkpoint("TownEcon._market_day:line:413")
	WageClaims.accrue_day(e, day)
	await _checkpoint("TownEcon._market_day:line:414")
	if TownEcon.prof_on: t0 = TownEcon._prof("wages", t0)
	await _checkpoint("TownEcon._market_day:line:415")
	await _rest_shelter_accrue_sanitation(e, float(day))
	await _checkpoint("TownEcon._market_day:line:416")
	if TownEcon.prof_on: t0 = TownEcon._prof("sanitation attendance", t0)
	await _checkpoint("TownEcon._market_day:line:417")
	var D: Variant = TownEcon.data()
	await _checkpoint("TownEcon._market_day:line:418")
	var si: Variant = Calendar.season_index(float(day))
	await _checkpoint("TownEcon._market_day:line:419")
	var clim: Dictionary = D["climates"][e["climate"]]
	await _checkpoint("TownEcon._market_day:line:420")
	var rng: Variant = RandomNumberGenerator.new()
	await _checkpoint("TownEcon._market_day:line:421")
	rng.seed = hash([int(game.world.get("seed", 0)), town["id"], day, "econ"])
	await _checkpoint("TownEcon._market_day:line:422")
	var nd: Dictionary = D["needs"]
	await _checkpoint("TownEcon._market_day:line:423")
	e["wf"] = float(nd["firewood_home"]) * float(nd["firewood_season"][si]) * float(clim["firewood"])   # firewood per home today
	await _checkpoint("TownEcon._market_day:line:424")
	e["hdecay"] = float(TownEcon.culture_of(e)["home"]["decay"])
	await _checkpoint("TownEcon._market_day:line:425")
	if TownEcon.prof_on: t0 = TownEcon._prof("day setup", t0)
	await _checkpoint("TownEcon._market_day:line:426")
	if not e.has("cin"):
		e["cin"] = {}
	await _checkpoint("TownEcon._market_day:line:428")
	e["hf_now"] = Barge.harvest_factor(game.world, e, String(town["id"]), float(day))
	await _checkpoint("TownEcon._market_day:line:429")
	var reservation_budgets: Array[Dictionary] = [{}]
	await _checkpoint("TownEcon._market_day:line:430")
	await _rest_town_econ_farms(e, D, si, clim, reservation_budgets)
	await _checkpoint("TownEcon._market_day:line:431")
	await _rest_town_econ_barn_sales(e, D, reservation_budgets)
	await _checkpoint("TownEcon._market_day:line:432")
	HarvestClaims.pay_departed(e)
	await _checkpoint("TownEcon._market_day:line:433")
	if TownEcon.prof_on: t0 = TownEcon._prof("farms+barns", t0)
	await _checkpoint("TownEcon._market_day:line:434")
	await _rest_businesses_daily(game, town, e, D, si, rng)
	await _checkpoint("TownEcon._market_day:line:435")
	WageClaims.pay_former(e)
	await _checkpoint("TownEcon._market_day:line:436")
	if TownEcon.prof_on: t0 = TownEcon._prof("businesses", t0)
	await _checkpoint("TownEcon._market_day:line:437")
	await _rest_town_econ_households(e, D, si, clim)
	await _checkpoint("TownEcon._market_day:line:438")
	if TownEcon.prof_on: t0 = TownEcon._prof("households", t0)
	await _checkpoint("TownEcon._market_day:line:439")
	if (day + absi(hash(String(town["id"])))) % TownEcon.SPOIL_EVERY == 0:   # spoilage in 3-day steps (same totals, a third of the work)
		await _rest_town_econ_spoil(e, D, si, clim, float(TownEcon.SPOIL_EVERY))
	# know-how fades slowly when nobody works the material
	await _checkpoint("TownEcon._market_day:line:442")
	for m: Variant in e["knowhow"]:
		await _checkpoint("TownEcon._market_day:loop:442")
		if int(e.get("kh_used", -99)) < day - 7:
			e["knowhow"][m] = maxf(0.0, float(e["knowhow"][m]) - float(D["knowhow"][m]["decay"]))
	await _checkpoint("TownEcon._market_day:line:445")
	if TownEcon.prof_on: t0 = TownEcon._prof("spoil", t0)
	await _checkpoint("TownEcon._market_day:line:446")
	await _rest_bows_econ_econ_daily(game, town, e, D)   # bows: staves season, fowl feathers, the head's armory (orders, buys, refills)
	await _checkpoint("TownEcon._market_day:line:447")
	if TownEcon.prof_on: t0 = TownEcon._prof("bows", t0)
	await _checkpoint("TownEcon._market_day:line:448")
	Shelter.daily(town, e)   # the poorhouse: broth, firewood and keepers, paid by the treasury
	await _checkpoint("TownEcon._market_day:line:449")
	await _rest_army_pay_town(game, town)   # militia / town guard: rank wages into their family purses (economy spec 2)
	await _checkpoint("TownEcon._market_day:line:450")
	await _rest_supply_orders_daily(game, town, day)
	await _checkpoint("TownEcon._market_day:line:451")
	if TownEcon.prof_on: t0 = TownEcon._prof("shelter+army", t0)

## Native game/campaign/town_econ.gd:488; operations retained in original order.
func _rest_town_econ_farms(e: Dictionary, D: Dictionary, si: int, clim: Dictionary, reservation_budgets: Array[Dictionary] = []) -> void:
	await _checkpoint("TownEcon._farms")
	await _checkpoint("TownEcon._farms:line:489")
	HarvestClaims.ensure(e)
	# Rotation can change base work without changing nominal acreage or rounded
	# hired capacity. Recompute future output from real existing hands before a
	# new year's harvest; ordinary family turns still perform funded matching.
	await _checkpoint("TownEcon._farms:line:493")
	for f: Variant in e["fams"]:
		await _checkpoint("TownEcon._farms:loop:493")
		if f.has("work_crop_year") and int(f["work_crop_year"]) != Calendar.year(float(e.get("day", 0))):
			Families.refresh_worked(e, f)
	await _checkpoint("TownEcon._farms:line:496")
	var L: Dictionary = D["land"]
	await _checkpoint("TownEcon._farms:line:497")
	var carry: Dictionary = e["carry"]
	await _checkpoint("TownEcon._farms:line:498")
	var hh: Dictionary = e["hh"]
	await _checkpoint("TownEcon._farms:line:499")
	var toolf: Variant = 0.75 + 0.25 * minf(1.0, float(hh.get("tools", 0)) / maxf(1.0, float(e.get("hands", 0)) + float(e["adults"]) * 0.3))
	await _checkpoint("TownEcon._farms:line:500")
	e["farm_toolf"] = toolf
	# barge part 2 section 4: two grain cuts a year (early grain in summer, autumn grain), fruit between; x the year's
	# harvest factor. The granary takes 5% of the grain and, where the ruler takes tribute in kind, that share too.
	await _checkpoint("TownEcon._farms:line:503")
	var HS: Dictionary = L["harvest_seasons"]
	await _checkpoint("TownEcon._farms:line:504")
	var hf: Variant = float(e.get("hf_now", 1.0))
	await _checkpoint("TownEcon._farms:line:505")
	var gtax: Variant = float(D["tax"]["grain_share"])
	await _checkpoint("TownEcon._farms:line:506")
	var ruler: Dictionary = e.get("ruler", {})
	await _checkpoint("TownEcon._farms:line:507")
	if String(ruler.get("kind", "coin")) == "kind":
		gtax += float(ruler.get("tribute", 0.0))
	await _checkpoint("TownEcon._farms:line:509")
	for crop: Variant in e["wacres"]:
		await _checkpoint("TownEcon._farms:loop:509")
		var cut: Variant = 0.0
		for s: Variant in HS.get(crop, [[int(L["harvest_season"]), 1.0]]):
			await _checkpoint("TownEcon._farms:loop:511")
			if int(s[0]) == si:
				cut += float(s[1])
		if cut <= 0.0:
			continue
		var y: Variant = CropRotation.harvest_yield(e, String(crop)) * cut * hf * Herds.manure_f(e)   # herds: the fields the dung covers yield more
		if crop == "grain":
			y *= float(clim["grain_yield"])
			Herds.straw(e, CropRotation.cereal_acres(e) * cut * hf / float(Calendar.DAYS_PER_SEASON))   # herds: the cut's straw is fodder (the year's weather too)
		elif crop == "fruit":
			y *= float(clim["fruit_yield"])
		var k: String = "h_" + crop
		var previous: Variant = float(carry.get(k, 0.0))
		# Incremental worked-acre updates can leave a negative floating residue
		# when the last real hand stops. Flooring that residue makes -1 and a
		# fictitious near-whole carry. Physical production cannot be negative.
		var produced: Variant = maxf(0.0, float(e["wacres"][crop])) * y * toolf / float(Calendar.DAYS_PER_SEASON)
		# Cumulative harvest-weighted acres: annual harvest / year-end acres is
		# not a yield when staffing changes between the cuts and winter.
		if not e["stats"].has("harvest_area"): e["stats"]["harvest_area"] = {}
		e["stats"]["harvest_area"][crop] = float(e["stats"]["harvest_area"].get(crop, 0.0)) + maxf(0.0, float(e["wacres"][crop])) * cut / float(Calendar.DAYS_PER_SEASON)
		var amt: Variant = produced + previous
		var n: Variant = int(floor(amt))
		carry[k] = amt - n
		var gt: Variant = int(floor(float(n) * gtax)) if crop == "grain" else 0
		if n > 0:
			TownEcon.led(e, "made", crop, n)
			e["granary"] = int(e["granary"]) + gt
		var contributions: Variant = {}
		for f: Variant in e["fams"]:
			await _checkpoint("TownEcon._farms:loop:540")
			if f.get("gone", false): continue
			var weight: Variant = float(f["land"].get(crop, 0.0)) * float(f.get("worked", 0.0)) * CropRotation.family_yield(e, f, String(crop))
			if weight > 0.0: contributions["f:%d" % int(f["id"])] = weight
		HarvestClaims.harvest(e, String(crop), k, contributions, produced, n, gt, previous, int(e.get("day", 0)))
	await _checkpoint("TownEcon._farms:line:545")
	HarvestClaims.reserve_all(e, reservation_budgets)
	await _checkpoint("TownEcon._farms:line:546")
	Herds.day(e)   # herds (addendum 1 B): the day's milk, wool, eggs, honey and wax the market paid the owners for this week

## Native game/campaign/town_econ.gd:549; operations retained in original order.
func _rest_town_econ_barn_sales(e: Dictionary, D: Dictionary, reservation_budgets: Array[Dictionary] = []) -> void:
	await _checkpoint("TownEcon._barn_sales")
	await _checkpoint("TownEcon._barn_sales:line:550")
	var barn: Dictionary = e["barn"]
	await _checkpoint("TownEcon._barn_sales:line:551")
	var st: Dictionary = e["stock"]
	await _checkpoint("TownEcon._barn_sales:line:552")
	var price: Dictionary = e["price"]
	await _checkpoint("TownEcon._barn_sales:line:553")
	var need: Dictionary = e.get("need", {})
	await _checkpoint("TownEcon._barn_sales:line:554")
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	await _checkpoint("TownEcon._barn_sales:line:555")
	var share: Variant = float(D["market"]["broker_share"])   # barge part 4: the farms' surplus goes to a broker at 0.75 x P
	await _checkpoint("TownEcon._barn_sales:line:556")
	HarvestClaims.reserve_all(e, reservation_budgets)
	await _checkpoint("TownEcon._barn_sales:line:557")
	for g: Variant in barn:
		await _checkpoint("TownEcon._barn_sales:loop:557")
		var have: Variant = HarvestClaims.available(e, String(g))
		if have <= 0:
			continue
		var want: Variant = int(float(need.get(g, 0.0)) * 1.2) - int(st.get(g, 0))
		if want <= 0:
			continue
		var p: Variant = float(price[g]) * share
		var q: Variant = mini(have, want)
		q = mini(q, int(maxf(0.0, float(mkt["till"])) / p))
		if q <= 0:
			continue
		var taken: Variant = HarvestClaims.take(e, String(g), q)
		st[g] = int(st.get(g, 0)) + q
		var val: Variant = float(q) * p
		mkt["till"] = float(mkt["till"]) - val
		mkt["spend"] = float(mkt["spend"]) + val
		HarvestClaims.credit(e, taken["shares"], val)

## Native game/campaign/town_econ.gd:611; operations retained in original order.
func _rest_town_econ_households(e: Dictionary, D: Dictionary, si: int, clim: Dictionary) -> void:
	await _checkpoint("TownEcon._households")
	await _checkpoint("TownEcon._households:line:612")
	var nd: Dictionary = D["needs"]
	await _checkpoint("TownEcon._households:line:613")
	var hh: Dictionary = e["hh"]
	await _checkpoint("TownEcon._households:line:614")
	var carry: Dictionary = e["carry"]
	await _checkpoint("TownEcon._households:line:615")
	var lu: Dictionary = e["led"]["used"]
	await _checkpoint("TownEcon._households:line:616")
	var pop: Variant = float(e["pop"])
	# barge: children eat 0.6-0.8 of a grown-up's share; the meals come out of what the households hold, whatever
	# mix they bought (staples by their race's taste, meat and produce as they could afford)
	await _checkpoint("TownEcon._households:line:619")
	var food_need: Variant = Barge.household_eaters(e, float(e.get("day", 0))) * float(nd["food"])
	await _checkpoint("TownEcon._households:line:620")
	var have_all: Variant = 0.0
	await _checkpoint("TownEcon._households:line:621")
	for k: Variant in Families.HOUSEHOLD_FOOD:
		await _checkpoint("TownEcon._households:loop:621")
		have_all += float(hh.get(k, 0))
	await _checkpoint("TownEcon._households:line:623")
	var missing: Variant = maxf(0.0, food_need - have_all)
	await _checkpoint("TownEcon._households:line:624")
	if have_all > 0.0:
		for k: Variant in ["fresh_meat", "meat", "fruit", "grain"]:
			await _checkpoint("TownEcon._households:loop:625")
			var want: Variant = minf(food_need, have_all) * float(hh.get(k, 0)) / have_all + float(carry.get("eat" + k, 0.0))
			var n: Variant = mini(int(hh.get(k, 0)), int(floor(want)))
			carry["eat" + k] = clampf(want - float(n), 0.0, 1.0)
			if n > 0:
				hh[k] = int(hh[k]) - n
				lu[k] = int(lu.get(k, 0)) + n
	await _checkpoint("TownEcon._households:line:632")
	e["food_short"] = missing / maxf(1.0, food_need)
	# drink (the town's beer and its fruit drink), firewood
	await _checkpoint("TownEcon._households:line:634")
	var drink: Variant = float(e["adults"]) * float(nd["drink_adult"]) + float(carry.get("drink", 0.0))
	await _checkpoint("TownEcon._households:line:635")
	var dn: Variant = int(floor(drink))
	await _checkpoint("TownEcon._households:line:636")
	carry["drink"] = drink - dn
	await _checkpoint("TownEcon._households:line:637")
	var b: Variant = mini(dn, int(hh.get("beer", 0)))
	await _checkpoint("TownEcon._households:line:638")
	if b > 0:
		hh["beer"] = int(hh["beer"]) - b
		lu["beer"] = int(lu.get("beer", 0)) + b
	await _checkpoint("TownEcon._households:line:641")
	var wn: Variant = mini(dn - b, int(hh.get("wine", 0)))
	await _checkpoint("TownEcon._households:line:642")
	if wn > 0:
		hh["wine"] = int(hh["wine"]) - wn
		lu["wine"] = int(lu.get("wine", 0)) + wn
	await _checkpoint("TownEcon._households:line:645")
	var homes: Variant = float(e["homes"])
	await _checkpoint("TownEcon._households:line:646")
	var wood: Variant = homes * float(nd["firewood_home"]) * float(nd["firewood_season"][si]) * float(clim["firewood"]) + float(carry.get("fire", 0.0))
	await _checkpoint("TownEcon._households:line:647")
	var fn: Variant = int(floor(wood))
	await _checkpoint("TownEcon._households:line:648")
	carry["fire"] = wood - fn
	await _checkpoint("TownEcon._households:line:649")
	var fw: Variant = mini(fn, int(hh.get("wood", 0)))
	await _checkpoint("TownEcon._households:line:650")
	if fw > 0:
		hh["wood"] = int(hh["wood"]) - fw
		lu["wood"] = int(lu.get("wood", 0)) + fw
	await _checkpoint("TownEcon._households:line:653")
	e["cold"] = fn - fw
	# wear: clothes per person, tools per adult, blankets and household goods per home, jewelry of the rich
	await _checkpoint("TownEcon._households:line:655")
	var wd: Dictionary = nd["wear_days"]
	await _checkpoint("TownEcon._households:line:656")
	for g: Variant in wd:
		await _checkpoint("TownEcon._households:loop:656")
		var basis: Variant = pop if g == "clothing" else (float(e["adults"]) if g == "tools" else (float(e.get("rich", 0)) if g == "jewelry" else homes))
		var amt: Variant = basis / float(wd[g]) + float(carry.get("w" + g, 0.0))
		var n2: Variant = int(floor(amt))
		carry["w" + g] = minf(amt - n2, 2.0)
		var t: Variant = mini(n2, int(hh.get(g, 0)))
		if t > 0:
			hh[g] = int(hh[g]) - t
			lu[g] = int(lu.get(g, 0)) + t

## Native game/campaign/town_econ.gd:581; operations retained in original order.
func _rest_town_econ_spoil(e: Dictionary, D: Dictionary, si: int, _clim: Dictionary, step_days: float = 1.0) -> void:
	await _checkpoint("TownEcon._spoil")
	await _checkpoint("TownEcon._spoil:line:582")
	var G: Dictionary = D["goods"]
	await _checkpoint("TownEcon._spoil:line:583")
	var rate: Variant = Barge.spoil_rate(Barge.temp(e, si))
	await _checkpoint("TownEcon._spoil:line:584")
	var carry: Dictionary = e["carry"]
	await _checkpoint("TownEcon._spoil:line:585")
	if TownEcon._perish.is_empty():
		for g: Variant in G:
			await _checkpoint("TownEcon._spoil:loop:586")
			if float(Barge.cat(g)["perish"]) > 0.0:
				TownEcon._perish.append([g, 0.0, "stock" + g, "barn" + g, "hh" + g])
	await _checkpoint("TownEcon._spoil:line:589")
	for hi: Variant in 3:
		await _checkpoint("TownEcon._spoil:loop:589")
		var s: Dictionary = e[["stock", "barn", "hh"][hi]]
		for p: Variant in TownEcon._perish:
			await _checkpoint("TownEcon._spoil:loop:591")
			var g: String = p[0]
			var have: Variant = int(s.get(g, 0))
			if have <= 0:
				continue
			var fr: Variant = 1.0 - pow(1.0 - Barge.spoil_frac(g, rate), step_days)
			var k: String = p[2 + hi]
			var amt: Variant = float(have) * fr + float(carry.get(k, 0.0))
			var n: Variant = mini(have, int(floor(amt)))
			carry[k] = amt - n
			if n > 0:
				if hi == 1: HarvestClaims.lose(e, g, n)
				else: s[g] = have - n
				TownEcon.led(e, "spoil", g, n)
				if g in ["grain", "fruit", "meat", "fresh_meat", "milk"]: TownSanitation.add_waste(e, float(n) * float(Goods.table().get(g, {}).get("weight", 0.4)), "rotting")

## Native game/campaign/town_econ.gd:456; operations retained in original order.
func _rest_town_econ_barge_day(game: Variant, town: Dictionary, day: int) -> void:
	await _checkpoint("TownEcon.barge_day")
	await _checkpoint("TownEcon.barge_day:line:457")
	if not TownEcon.has_econ(town):
		return
	await _checkpoint("TownEcon.barge_day:line:459")
	var e: Dictionary = town["econ"]
	await _checkpoint("TownEcon.barge_day:line:460")
	if int(e.get("bday", -1)) >= day or int(e.get("day", -1)) < day:
		return
	await _checkpoint("TownEcon.barge_day:line:462")
	e["bday"] = day
	await _checkpoint("TownEcon.barge_day:bday_written")
	await _checkpoint("TownEcon.barge_day:line:463")
	var rng: Variant = RandomNumberGenerator.new()
	await _checkpoint("TownEcon.barge_day:line:464")
	rng.seed = hash([int(game.world.get("seed", 0)), town["id"], day, "barge"])
	await _checkpoint("TownEcon.barge_day:line:465")
	var t0: Variant = Time.get_ticks_usec() if TownEcon.prof_on else 0
	await _checkpoint("TownEcon.barge_day:line:466")
	Barge.town_stage_day(e)   # barge part 4 section 5: the town's famine stage (from the market day's food shortfall)
	await _checkpoint("TownEcon.barge_day:line:467")
	Barge.granary_day(game, town, e, float(day))
	await _checkpoint("TownEcon.barge_day:line:468")
	await _rest_barge_update_prices(town, rng)
	await _checkpoint("TownEcon.barge_day:line:469")
	if TownEcon.prof_on: t0 = TownEcon._prof("prices", t0)
	await _checkpoint("TownEcon.barge_day:line:470")
	await _rest_businesses_books_day(e)
	await _checkpoint("TownEcon.barge_day:line:471")
	await _rest_businesses_prep_day(e)   # tomorrow's margins and makers' aims from today's prices
	await _checkpoint("TownEcon.barge_day:line:472")
	if TownEcon.prof_on: t0 = TownEcon._prof("books", t0)
	await _checkpoint("TownEcon.barge_day:line:473")
	await _rest_barge_labour_day(e, Calendar.season_index(float(day)))
	await _checkpoint("TownEcon.barge_day:line:474")
	await _businesses_bid_day(e)   # retain each offer; review weekly against its own staffing
	await _checkpoint("TownEcon.barge_day:line:475")
	await _rest_barge_coin_town(game, town, e)
	await _checkpoint("TownEcon.barge_day:line:476")
	if TownEcon.prof_on: t0 = TownEcon._prof("labour+coin", t0)

## Native game/campaign/businesses.gd:520; operations retained in original order.
func _rest_businesses_daily(game: Variant, town: Dictionary, e: Dictionary, D: Dictionary, si: int, rng: RandomNumberGenerator) -> void:
	await _checkpoint("Businesses.daily")
	await _checkpoint("Businesses.daily:line:521")
	Metallurgy.recycle_stock(town)
	await _checkpoint("Businesses.daily:line:522")
	var biz: Array = e["biz"]
	await _checkpoint("Businesses.daily:line:523")
	var n: Variant = biz.size()
	await _checkpoint("Businesses.daily:line:524")
	if n == 0:
		return
	await _checkpoint("Businesses.daily:line:526")
	var st: Dictionary = e["stock"]
	await _checkpoint("Businesses.daily:line:527")
	var price: Dictionary = e["price"]
	await _checkpoint("Businesses.daily:line:528")
	var mkt: Dictionary = biz[int(e["mkt"])]
	await _checkpoint("Businesses.daily:line:529")
	var share: Variant = float(D["market"]["buy_share"])
	await _checkpoint("Businesses.daily:line:530")
	var bdem: Variant = {}
	await _checkpoint("Businesses.daily:line:531")
	var aimr: Dictionary = e.get("_aimrest", {})
	await _checkpoint("Businesses.daily:line:532")
	var specs: Variant = {}
	await _checkpoint("Businesses.daily:line:533")
	for s: Variant in e["specialties"]:
		await _checkpoint("Businesses.daily:loop:533")
		specs[D["specialties"][s]["biz"]] = true
	await _checkpoint("Businesses.daily:line:535")
	if not e.has("prod"):
		Businesses.rebuild_open(e)
	await _checkpoint("Businesses.daily:line:537")
	var prod: Array = e["prod"]
	await _checkpoint("Businesses.daily:line:538")
	var np: Variant = prod.size()
	await _checkpoint("Businesses.daily:line:539")
	if np == 0:
		return
	await _checkpoint("Businesses.daily:line:541")
	var start: Variant = int(e.get("day", 0)) % np
	await _checkpoint("Businesses.daily:line:542")
	var BT: Dictionary = D["businesses"]
	await _checkpoint("Businesses.daily:line:543")
	var gear_n: Variant = {}
	await _checkpoint("Businesses.daily:line:544")
	var tool_days: Variant = float(D["needs"]["wear_days"]["tools"])
	await _checkpoint("Businesses.daily:line:545")
	for j: Variant in np:
		await _checkpoint("Businesses.daily:loop:545")
		var b: Dictionary = biz[int(prod[(start + j) % np])]
		if b["closed"]:
			continue
		var type: String = b["type"]
		if BT[type].has("arms") and String(BT[type]["arms"]) != "bow": Businesses._gear_carry_key(b, BT[type])
		var receipt_before: Variant = float(b["till"])
		var hired: Variant = maxi(0, int(b["workers"]) - int(b.get("sick", 0)))   # sickness: bed-ridden staff stay home (short-handed)
		# WageClaims closes all actual household jobs at the queued town day.
		# The keeper contributes work and takes profit, never employee wages.
		# v0.014: the keeper works his shop (barge part 3 section 4); he draws the keeper's take, not a wage
		var w: Variant = hired + int(b.get("kw", 0))
		# Academy resolves its own named, paid workers. Idle/vacant houses must not buy tools or do keeper work.
		if type == "academy":
			var research_spent: Variant = Academy.day(game, town, e, b, float(hired), mkt, bdem)
			Businesses._finish_production_day(b, receipt_before, hired, hired, research_spent)
			continue
		if w <= 0:
			b["state"] = "hands" if int(b["cap"]) > 0 else "idle"
			continue
		# v0.014: weaponsmiths and armourers keep wanting their bars (data smith_bars) every working day, resting or not:
		# their stockpile target stands in the market, so the bars' price and the caravans follow it
		if type == "weaponsmith" or type == "armorsmith":
			Businesses.smith_want(e, float(w), bdem)
		# a business that found the market full yesterday rests until its goods sell down (cheap check)
		if b["state"] in ["full", "wages"] and b.has("fg"):
			var fg: String = b["fg"]
			if fg == "arms":
				if (town["shop"] as Array).size() >= Businesses.arms_cap(town) and not (type == "weaponsmith" and BowsEcon.tips_wanted(e)) \
						and not ArmsTrade.has_orders(e, String(BT[type].get("arms", ""))):   # v0.014: the armory's orders
					Businesses._finish_production_day(b, receipt_before, w, hired, 0.0)
					continue
			elif float(st.get(fg, 0)) >= Businesses.stock_cap(e, fg) * 0.9 or aimr.has(fg):
				EconomyRules.clear_surplus(e, fg)
		# tools wear and replacement
		var tw: Variant = float(b["tw"]) + float(w) / tool_days
		if tw >= 1.0 and int(b["tools"]) > 0:
			b["tools"] = int(b["tools"]) - 1
			tw -= 1.0   # (tools left the goods ledger when bought; wear only empties the rack)
		b["tw"] = minf(tw, 2.0)
		if int(b["tools"]) < w and int(st.get("tools", 0)) > 0 and float(b["till"]) > float(price["tools"]) * 2.0:
			st["tools"] = int(st["tools"]) - 1
			b["tools"] = int(b["tools"]) + 1
			TownEcon.led(e, "used", "tools", 1)
			var tc: Variant = float(price["tools"])
			b["till"] = float(b["till"]) - tc
			mkt["till"] = float(mkt["till"]) + tc
			e["stats"]["sales"] = float(e["stats"]["sales"]) + tc
			bdem["tools"] = float(bdem.get("tools", 0.0)) + 1.0
		var toolf: Variant = 0.5 + 0.5 * minf(1.0, float(b["tools"]) / float(w))
		var spec: Variant = 2.0 if specs.has(type) else 1.0
		var T: Dictionary = BT[type]
		b["state"] = "busy"
		b["why"] = ""
		var spent: Variant = 0.0
		if T.has("arms"):
			var frac: Variant = 1.0
			if T["arms"] == "weapon" or T["arms"] == "bow":   # bows: smiths' arrowheads, bowyers' staves (campaign/bows_econ.gd)
				frac = BowsEcon.arms_share(town, e, T["arms"])
			elif not (T["recipes"] as Array).is_empty():
				if gear_n.is_empty():
					gear_n = Businesses._gear_counts(town)
				frac = 0.3 if int(gear_n[T["arms"]]) < 4 + int(town.get("size", 0)) else 0.0   # tailors/leatherworkers make gear part-time
			if frac > 0.0:
				spent += await _rest_businesses_arms(game, town, e, D, b, T, float(w) * frac, toolf, spec, rng, mkt, bdem)
			if frac < 1.0:
				spent += Businesses._recipes(e, D, b, T, float(w) * (1.0 - frac), toolf, spec, mkt, share, bdem)
		elif type == "mine":
			Businesses._mine(e, D, b, float(w), toolf, spec, mkt, share, rng)
		elif type == "butcher":
			spent += Herds.butcher_day(e, b, float(w), toolf, mkt, share, bdem)   # herds: beasts bought from their owners
		else:
			spent += Businesses._recipes(e, D, b, T, float(w), toolf, spec, mkt, share, bdem)
		TownSanitation.add_waste(e, float(w) * float(TownSanitation.D()["trade_waste_per_hand"].get(type, 0)) if b["state"] in ["busy", "hands"] else 0, "trade")
		Businesses._finish_production_day(b, receipt_before, w, hired, spent)
	# business input wants (per day) feed tomorrow's prices
	await _checkpoint("Businesses.daily:line:621")
	e["bdem"] = bdem

## Native game/campaign/businesses.gd:1264; operations retained in original order.
func _rest_businesses_arms(_game: Variant, town: Dictionary, e: Dictionary, D: Dictionary, b: Dictionary, T: Dictionary, wd: float, toolf: float,
		spec: float, rng: RandomNumberGenerator, mkt: Dictionary, bdem: Dictionary) -> float:
	await _checkpoint("Businesses._arms")
	await _checkpoint("Businesses._arms:line:1266")
	if T["arms"] == "bow":   # bows: the bowyer's bows (campaign/bows_econ.gd)
		return BowsEcon.make_bows(town, e, D, b, wd, toolf, spec, rng, mkt, bdem)
	# Gear items and recipe batches have different units. A mixed trade keeps
	# its recipe work in carry; stopping gear must not erase that work or use
	# it toward an item. Pure gear makers retain their existing saved channel.
	await _checkpoint("Businesses._arms:line:1271")
	var carry_key: Variant = Businesses._gear_carry_key(b, T)
	await _checkpoint("Businesses._arms:line:1272")
	var shop: Array = town.get("shop", [])
	await _checkpoint("Businesses._arms:line:1273")
	var orders_only: Variant = false   # v0.014: stalls full, but the head's armory has orders (ArmsTrade.order_buy)
	await _checkpoint("Businesses._arms:line:1274")
	if T["arms"] in ["weapon", "armor"] and shop.size() >= Businesses.arms_cap(town):
		if not ArmsTrade.has_orders(e, T["arms"]):
			b["state"] = "full"
			b["fg"] = "arms"
			b[carry_key] = 0.0
			return 0.0
		orders_only = true
	await _checkpoint("Businesses._arms:line:1281")
	var st: Dictionary = e["stock"]
	await _checkpoint("Businesses._arms:line:1282")
	var price: Dictionary = e["price"]
	await _checkpoint("Businesses._arms:line:1283")
	var kh: Variant = Businesses.kh_of(e, "bronze")   # v0.014: the town's practice under the faction's know-how (0 for orcs and goblins)
	await _checkpoint("Businesses._arms:line:1284")
	var skh: Variant = Businesses.kh_of(e, "steel")   # v0.012: the faction's steel know-how caps the best steel its smiths can make
	await _checkpoint("Businesses._arms:line:1285")
	var ikh: Variant = Businesses.kh_of(e, "iron")    # v0.014: the faction's iron know-how gates working iron
	await _checkpoint("Businesses._arms:line:1286")
	var kind: String = T["arms"]
	# (v0.014: the bars smiths keep wanting go to the market in Businesses.daily: smith_want)
	await _checkpoint("Businesses._arms:line:1288")
	if kind in ["weapon", "armor"] and int(st.get("copper_bars", 0)) + int(st.get("tin_bars", 0)) + (int(st.get("bronze_bars", 0)) if kh > 0.0 else 0) \
			+ (int(st.get("iron_bars", 0)) if ikh > 0.0 else 0) + (int(st.get("steel_bars", 0)) if skh > 0.0 else 0) <= 0:
		b["state"] = "inputs"   # smiths spend bars; no bars = idle
		b["why"] = "bars"
		b[carry_key] = 0.0
		for bg: Variant in ["copper_bars", "tin_bars"]:
			await _checkpoint("Businesses._arms:loop:1293")
			bdem[bg] = float(bdem.get(bg, 0.0)) + 3.0 * wd
		return 0.0
	await _checkpoint("Businesses._arms:line:1296")
	var pool: Variant = Businesses.gear_pool(town.get("culture", "middle"), kind)
	await _checkpoint("Businesses._arms:line:1297")
	if pool.is_empty():
		b["state"] = "idle"
		return 0.0
	await _checkpoint("Businesses._arms:line:1300")
	var f: Variant = wd * float(T["rate"]) * toolf * spec + float(b.get(carry_key, 0.0))
	await _checkpoint("Businesses._arms:line:1301")
	var whole: Variant = int(floor(f))
	await _checkpoint("Businesses._arms:line:1302")
	b[carry_key] = minf(f - whole, 1.0)
	await _checkpoint("Businesses._arms:line:1303")
	var spent: Variant = 0.0
	await _checkpoint("Businesses._arms:line:1304")
	var bronze_days: Variant = 0.0
	await _checkpoint("Businesses._arms:line:1305")
	var share: Variant = float(D["market"]["arms_buy_share"])
	await _checkpoint("Businesses._arms:line:1306")
	var made_any: Variant = false
	# Fresh for this forge only; no other trade, troop issue or roster change
	# can interleave with its synchronous native item/coin transactions.
	await _checkpoint("Businesses._arms:line:1309")
	var forge_pass: Dictionary = {}
	await _checkpoint("Businesses._arms:line:1310")
	var maker_scope: Array[Dictionary] = [{}]
	await _checkpoint("Businesses._arms:line:1311")
	var input_scope: Dictionary = {}
	await _checkpoint("Businesses._arms:line:1312")
	for i: Variant in whole:
		await _checkpoint("Businesses._arms:loop:1312")
		var tid: Variant = ""
		if orders_only:
			var op: Variant = ArmsTrade.order_pool(e, pool)
			if op.is_empty():
				b["state"] = "full"
				b["fg"] = "arms"
				break
			tid = op[rng.randi() % op.size()]
		else:
			tid = ArmsTrade.pick_tid(e, pool, rng) if kind in ["weapon", "armor"] else pool[rng.randi() % pool.size()]   # arms trade: the armory's shortfall first
		var mat: Variant = ""
		if kind == "cloth":
			mat = "linen"
		elif kind == "leather":
			mat = "leather"
		else:
			mat = Businesses._pick_metal(e, tid, kh, int(town.get("wealth", 2)), rng, skh, ikh, input_scope)
		if mat == "":
			b["state"] = "inputs"
			b["why"] = "bars"
			for bg: Variant in ["copper_bars", "tin_bars"]:
				await _checkpoint("Businesses._arms:loop:1333")
				bdem[bg] = float(bdem.get(bg, 0.0)) + 3.0
			b[carry_key] = 0.0
			break
		var ins: Dictionary = Businesses._forge_inputs(tid, mat, input_scope)
		var cost: Variant = 0.0
		var ok: Variant = true
		for ig: Variant in ins:
			await _checkpoint("Businesses._arms:loop:1340")
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
		var skill: Variant = float(b.get("skill", 3)) + (3.0 if spec > 1.0 else 0.0)
		if mat == "bronze":
			skill -= 4.0 * (1.0 - kh / 100.0)
		elif mat in ["linen", "leather"]:
			skill *= 0.5
		var q: Variant = Factory.roll_quality(rng, skill, true)   # v0.014: a real forge: its masterwork rolls may be legendary
		if mat == "steel":
			var bq: Variant = maxi(0, Academy.best_quality(skh))
			if not (q == DB.LEGEND and bq >= 5):
				q = mini(q, bq)   # the smith's skill on top, never past the faction's know-how
		var it: Variant = Item.make(tid, mat, q)
		ArmsTrade.mark(it, town, b)   # arms trade: the maker's mark
		if it.is_legend():   # v0.014: a real maker of this forge and a real stone, else it stays masterwork
			Legends.forge(_game if _game != null else Game, town, e, b, it, rng, float(e.get("day", 0)), cost, maker_scope)
		var value: Variant = Economy.base_value(town, it) * share
		# v0.014: a piece the armory has an order for goes to the head (the treasury pays the smith), else the market
		var to_arm: Variant = kind in ["weapon", "armor"] and ArmsTrade.order_buy(_game, town, e, it, value, forge_pass)
		if not to_arm:
			if it.is_legend():
				value = minf(value, maxf(0.0, float(mkt["till"])))   # never left unmade: the market pays what its till holds
			elif orders_only:
				b["state"] = "full"   # the head cannot pay for his orders and the stalls are full
				b["fg"] = "arms"
				WorldAudit.unmade(it, "-forge piece priced, never made (stalls full)")   # v0.075 r6: priced only
				break
			if float(mkt["till"]) < value:
				b["state"] = "nopay"
				WorldAudit.unmade(it, "-forge piece priced, never made (market cannot pay)")   # v0.075 r6
				break
		for ig: Variant in ins:
			await _checkpoint("Businesses._arms:loop:1382")
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
	await _checkpoint("Businesses._arms:line:1397")
	town["shop"] = shop
	await _checkpoint("Businesses._arms:line:1398")
	if bronze_days > 0.0:
		TownEcon.knowhow_gain(e, "bronze", bronze_days)
	await _checkpoint("Businesses._arms:line:1400")
	if not made_any and whole == 0 and b["state"] == "busy":
		b["state"] = "busy"
	await _checkpoint("Businesses._arms:line:1402")
	return spent

## Native game/campaign/businesses.gd:697; operations retained in original order.
func _rest_businesses_books_day(e: Dictionary) -> void:
	await _checkpoint("Businesses.books_day")
	await _checkpoint("Businesses.books_day:line:698")
	if not e.has("prod"):
		return
	await _checkpoint("Businesses.books_day:line:700")
	var biz: Array = e["biz"]
	await _checkpoint("Businesses.books_day:line:701")
	var mkt: Dictionary = biz[int(e["mkt"])]
	await _checkpoint("Businesses.books_day:line:702")
	var BB: Dictionary = Barge.B()["business"]
	await _checkpoint("Businesses.books_day:line:703")
	var u0: Variant = float(BB["upkeep"][0]); var u1: Variant = float(BB["upkeep"][1])
	await _checkpoint("Businesses.books_day:line:704")
	var lds: Variant = int(BB["struggling"]); var thr: Variant = float(BB["thriving"])
	await _checkpoint("Businesses.books_day:line:705")
	for bid: Variant in e["prod"]:
		await _checkpoint("Businesses.books_day:loop:705")
		var b: Dictionary = biz[int(bid)]
		# No eligible line means no spending, including the ordinary building bill.
		if String(b["type"]) == "academy" and bool(b.get("research_idle", false)):
			continue
		if not b["closed"]:
			Businesses._books(b, int(b["workers"]), mkt, u0, u1, lds, thr)

## Native game/campaign/businesses.gd:657; operations retained in original order.
func _rest_businesses_prep_day(e: Dictionary) -> void:
	await _checkpoint("Businesses.prep_day")
	await _checkpoint("Businesses.prep_day:line:658")
	Businesses._recipe_index()
	await _checkpoint("Businesses.prep_day:line:659")
	if Businesses._bb_out < 0.0:
		var BB: Dictionary = Barge.B()["business"]
		Businesses._bb_out = float(BB["out_share"]); Businesses._bb_margin = float(BB["run_margin"]); Businesses._bb_idle = float(BB["idle_cap"]); Businesses._bb_gap = float(BB["aim_gap"])
	await _checkpoint("Businesses.prep_day:line:662")
	var price: Dictionary = e.get("price", {})
	await _checkpoint("Businesses.prep_day:line:663")
	var nm: Variant = []
	await _checkpoint("Businesses.prep_day:line:664")
	nm.resize(Businesses._all_recipes.size())
	await _checkpoint("Businesses.prep_day:line:665")
	nm.fill(false)
	await _checkpoint("Businesses.prep_day:line:666")
	for r: Variant in Businesses._all_recipes:
		await _checkpoint("Businesses.prep_day:loop:666")
		var rc: Array = r["_bc"]
		var inl: Array = rc[3]
		if inl.is_empty():
			continue
		var ov: Variant = 0.0; var iv: Variant = 0.0
		var outs: Array = rc[2]
		for k: Variant in range(0, outs.size(), 2):
			await _checkpoint("Businesses.prep_day:loop:673")
			ov += float(outs[k + 1]) * float(price.get(outs[k], 0.0))
		for k: Variant in range(0, inl.size(), 2):
			await _checkpoint("Businesses.prep_day:loop:675")
			iv += float(inl[k + 1]) * float(price.get(inl[k], 0.0))
		if ov * Businesses._bb_out < Businesses._bb_margin * iv:
			nm[int(rc[4])] = true   # (a list by recipe id: survives the save as it is)
	await _checkpoint("Businesses.prep_day:line:679")
	e["_nomargin"] = nm
	await _checkpoint("Businesses.prep_day:line:680")
	var aimu: Variant = {}
	await _checkpoint("Businesses.prep_day:line:681")
	var rest: Variant = {}   # goods the market keeps a normal stock of and holds more than enough: their makers rest
	await _checkpoint("Businesses.prep_day:line:682")
	var mk: Dictionary = e.get("makers", {})
	await _checkpoint("Businesses.prep_day:line:683")
	var dem: Dictionary = e.get("dem", {}); var need: Dictionary = e.get("need", {}); var st: Dictionary = e.get("stock", {})
	await _checkpoint("Businesses.prep_day:line:684")
	for og: Variant in mk:
		await _checkpoint("Businesses.prep_day:loop:684")
		var aim: Variant = float(dem.get(og, 0.0)) + Businesses._bb_gap * (float(need.get(og, 0.0)) - float(st.get(og, 0)))
		aimu[og] = maxf(0.0, aim) / maxf(1.0, float(mk[og]))
		if aim <= 0.0 and float(need.get(og, 0.0)) > 0.0:
			rest[og] = true
	await _checkpoint("Businesses.prep_day:line:689")
	e["_aimu"] = aimu
	await _checkpoint("Businesses.prep_day:line:690")
	e["_aimrest"] = rest

## Native game/campaign/shelter.gd:384; operations retained in original order.
func _rest_shelter_accrue_sanitation(e: Dictionary, day: float) -> void:
	await _checkpoint("Shelter.accrue_sanitation")
	# Attendance writes only earned amounts; names, ages and service stay fixed.
	# Keep the first native title lookup lazy, and reuse it for this scan only.
	await _checkpoint("Shelter.accrue_sanitation:line:387")
	var owner_names_scope: Array[Dictionary] = [{}]
	await _checkpoint("Shelter.accrue_sanitation:line:388")
	var wages: Dictionary = {}
	await _checkpoint("Shelter.accrue_sanitation:line:389")
	for f: Variant in e["fams"]:
		await _checkpoint("Shelter.accrue_sanitation:loop:389")
		if f.get("gone", false) or (f.get("cj", {}).is_empty() and f.get("child_cj", {}).is_empty()): continue
		var work: Dictionary = await _rest_persons_sanitation_work(e, f, owner_names_scope)
		for pid: Variant in work:
			await _checkpoint("Shelter.accrue_sanitation:loop:392")
			var j: Variant = String(work[pid].get("cj", ""))
			if not j in ["rat_catcher", "street_sweeper", "night_soil_man"]: continue
			var c: Variant = Sickness.case_of(f, int(pid))
			if not c.is_empty() and int(c[Sickness.C_BED]) == 1 and Sickness.sick_phase(c, day): continue
			if not f.has("cjearned"): f["cjearned"] = {}
			var earned: Array = f["cjearned"].get(j, [0.0, 0.0])
			var share: Variant = float(work[pid].get("share", 1.0))
			if not wages.has(j): wages[j] = Barge.casual_wage(e, j)
			# Keep each ordered floating addition; only the unchanged wage is shared.
			earned[0] += share; earned[1] += float(wages[j]) * share
			f["cjearned"][j] = earned

## Native game/campaign/persons.gd:1244; operations retained in original order.
func _rest_persons_sanitation_work(e: Dictionary, f: Dictionary, owner_names_scope: Array[Dictionary] = []) -> Dictionary:
	await _checkpoint("Persons.sanitation_work")
	await _checkpoint("Persons.sanitation_work:line:1245")
	if not f.has("pp"): return {}
	await _checkpoint("Persons.sanitation_work:line:1246")
	var compact: bool = Population.is_cohort(f)
	# The non-cohort research lead can exchange a casual slot with a paid one.
	# Keep its complete native path, including legacy register initialization.
	await _checkpoint("Persons.sanitation_work:line:1249")
	if not compact and e.has("academy") and (f["jobs"] as Dictionary).has(str(int(e["academy"]))):
		return await _rest_persons_work(e, f, owner_names_scope)
	await _checkpoint("Persons.sanitation_work:line:1251")
	var home: Array = Population.home_workers(f)
	await _checkpoint("Persons.sanitation_work:line:1252")
	if compact and home.is_empty(): return {}
	await _checkpoint("Persons.sanitation_work:line:1253")
	var places: Array = []
	await _checkpoint("Persons.sanitation_work:line:1254")
	var counts: Array[int] = []
	await _checkpoint("Persons.sanitation_work:line:1255")
	var names_scope: Array[Dictionary] = owner_names_scope
	await _checkpoint("Persons.sanitation_work:line:1256")
	if names_scope.is_empty(): names_scope = [{}]
	await _checkpoint("Persons.sanitation_work:line:1257")
	var biz: Array = e.get("biz", [])
	await _checkpoint("Persons.sanitation_work:line:1258")
	for kb: Variant in f.get("keeps", []):
		await _checkpoint("Persons.sanitation_work:loop:1258")
		if int(kb) >= biz.size(): continue
		Businesses.title(e, biz[int(kb)], names_scope)
		places.append({"biz": int(kb), "keeper": true})
		counts.append(1)
	await _checkpoint("Persons.sanitation_work:line:1263")
	var hands: int = int(f.get("hands", 0))
	await _checkpoint("Persons.sanitation_work:line:1264")
	if hands > 0:
		# These are the only saved preparation effects of crop_hands/herd_hands.
		# Draught, herd ranking and descriptive formatting are read-only.
		CropRotation.work_acres(e, f)
		if e.has("hd"): Herds.labour_hands(e, int(f["id"]))
		places.append({})
		counts.append(hands)
	await _checkpoint("Persons.sanitation_work:line:1271")
	var keys: Array = (f["jobs"] as Dictionary).keys()
	await _checkpoint("Persons.sanitation_work:line:1272")
	if not compact:
		keys.sort_custom(func(x: Variant,  y: Variant) -> bool:
			var bx: Dictionary = biz[int(x)]
			var by: Dictionary = biz[int(y)]
			var ox: bool = int(bx["owner"]) == int(f["id"])
			var oy: bool = int(by["owner"]) == int(f["id"])
			if ox != oy: return ox
			if float(bx["wage"]) != float(by["wage"]): return float(bx["wage"]) > float(by["wage"])
			return int(x) < int(y))
	await _checkpoint("Persons.sanitation_work:line:1281")
	for key: Variant in keys:
		await _checkpoint("Persons.sanitation_work:loop:1281")
		var count: int = int(f["jobs"][key])
		if count <= 0: continue
		Businesses.title(e, biz[int(key)], names_scope)
		places.append({"biz": int(key)})
		counts.append(count)
	await _checkpoint("Persons.sanitation_work:line:1287")
	for key: Variant in f.get("cj", {}):
		await _checkpoint("Persons.sanitation_work:loop:1287")
		var count: int = int(f["cj"][key])
		if count <= 0: continue
		places.append({"cj": String(key)})
		counts.append(count)
	# Keep the original cohort prefix rotation, anonymous offset, academy
	# reservations and responsibility swaps; only unused descriptions differ.
	await _checkpoint("Persons.sanitation_work:line:1294")
	if compact: return Population.named_work(e, f, home, places, counts)
	await _checkpoint("Persons.sanitation_work:line:1295")
	var out: Dictionary = {}
	await _checkpoint("Persons.sanitation_work:line:1296")
	var block: int = 0
	await _checkpoint("Persons.sanitation_work:line:1297")
	var first: int = 0
	await _checkpoint("Persons.sanitation_work:line:1298")
	for i: int in home.size():
		await _checkpoint("Persons.sanitation_work:loop:1298")
		while block < places.size() and i >= first + counts[block]:
			await _checkpoint("Persons.sanitation_work:loop:1299")
			first += counts[block]
			block += 1
		# Keep empty writes and native PID order, including duplicate overrides.
		out[int(home[i][0])] = places[block] if block < places.size() else {}
	await _checkpoint("Persons.sanitation_work:line:1304")
	for p: Array in Persons.kp(f):
		await _checkpoint("Persons.sanitation_work:loop:1304")
		var job: String = String(f.get("child_cj", {}).get(str(int(p[0])), ""))
		if job == "" or not Shelter.cleanup_child_eligible(e, p, float(Game.day), f): continue
		out[int(p[0])] = {"cj": job, "share": float(Barge.B()["labour"]["kid_share"])}
	await _checkpoint("Persons.sanitation_work:line:1308")
	return out

## Native game/campaign/persons.gd:1120; operations retained in original order.
func _rest_persons_work(e: Dictionary, f: Dictionary, owner_names_scope: Array[Dictionary] = []) -> Dictionary:
	await _checkpoint("Persons.work")
	await _checkpoint("Persons.work:line:1121")
	var out: Variant = {}
	await _checkpoint("Persons.work:line:1122")
	if not f.has("pp"):
		return out
	await _checkpoint("Persons.work:line:1124")
	var home: Array = Population.home_workers(f)
	await _checkpoint("Persons.work:line:1125")
	var compact: bool = Population.is_cohort(f)
	await _checkpoint("Persons.work:line:1126")
	if compact and home.is_empty(): return out
	# Describe each contiguous block once; named workers still get independent
	# dictionaries below, in the same PID/slot order as the expanded places.
	await _checkpoint("Persons.work:line:1129")
	var places: Array = []
	await _checkpoint("Persons.work:line:1130")
	var counts: Array[int] = []
	# v0.014: the keepers of the family's shops first (Families._keep: the eldest at home keep them)
	await _checkpoint("Persons.work:line:1132")
	var biz0: Array = e.get("biz", [])
	# This read cannot change head-selection inputs. A caller may share the
	# same lazy name snapshot across a synchronous, read-only family scan.
	await _checkpoint("Persons.work:line:1135")
	var names_scope: Array[Dictionary] = owner_names_scope
	await _checkpoint("Persons.work:line:1136")
	if names_scope.is_empty(): names_scope = [{}]
	await _checkpoint("Persons.work:line:1137")
	for kb: Variant in f.get("keeps", []):
		await _checkpoint("Persons.work:loop:1137")
		if int(kb) < biz0.size():
			var b0: Dictionary = biz0[int(kb)]
			places.append({"kind": "job", "keeper": true, "title": "keeper of the %s" % String(TownEcon.data()["businesses"][b0["type"]]["name"]),
				"where": Businesses.title(e, b0, names_scope), "wage": 0.0, "biz": int(kb)})
			counts.append(1)
	# own land and herds
	await _checkpoint("Persons.work:line:1144")
	var hands: Variant = int(f.get("hands", 0))
	await _checkpoint("Persons.work:line:1145")
	if hands > 0:
		var ac: Variant = Families.acres(f)
		var ln: Variant = Families.crop_hands(f, e); var hn: Variant = Families.herd_hands(f, e)
		var animal: Variant = Persons._biggest(f["herd"])
		var animal_n: Variant = int(f["herd"].get(animal, 0))
		if e.has("hd"):
			var animal_work: Variant = -1.0
			for h: Variant in Herds.of_family(e, int(f["id"])):
				await _checkpoint("Persons.work:loop:1152")
				var per_hand: Variant = float(Herds.kind(String(h["k"])).get("per_hand", 0))
				if per_hand <= 0.0 or Herds.head(h) <= 0: continue
				var care: Variant = Herds.ge(h) / per_hand
				if care > animal_work:
					animal_work = care; animal = String(h["k"]); animal_n = Herds.head(h)
		var herd_h: Variant = 0
		if hn > 0.0:
			herd_h = hands if ac == 0 else clampi(int(round(float(hands) * hn / maxf(0.001, ln + hn))), 1, maxi(1, hands - 1))
		var crop: Variant = Persons._biggest(f["land"])
		# Both register forms use the same ordered herd/land blocks.
		var batches: Array[int] = [herd_h, hands - herd_h]
		for i: int in batches.size():
			await _checkpoint("Persons.work:loop:1164")
			var count: int = batches[i]
			if count <= 0: continue
			counts.append(count)
			var is_herd: bool = i == 0
			if is_herd:
				places.append({"kind": "herd", "title": "%s on the family herd" % Recruits.HERD_TITLES.get(animal, "%s herder" % animal),
					"where": TownEcon.n_of(animal_n, animal), "wage": 0.0})
			else:
				var v: String = TownEcon.variety_word(e, crop)
				places.append({"kind": "land", "title": "farmhand on the family %s" % v,
					"where": "%s of %s" % [TownEcon.n_of(int(f["land"].get(crop, 0)), "acres"), v], "wage": 0.0})
	# jobs: the family's own business first, then the best wage
	await _checkpoint("Persons.work:line:1177")
	var keys: Array = (f["jobs"] as Dictionary).keys()
	await _checkpoint("Persons.work:line:1178")
	var biz: Array = e["biz"]
	await _checkpoint("Persons.work:line:1179")
	if not compact:
		keys.sort_custom(func(x: Variant, y: Variant):
			var bx: Dictionary = biz[int(x)]; var by: Dictionary = biz[int(y)]
			var ox: bool = int(bx["owner"]) == int(f["id"]); var oy: bool = int(by["owner"]) == int(f["id"])
			if ox != oy:
				return ox
			if float(bx["wage"]) != float(by["wage"]):
				return float(bx["wage"]) > float(by["wage"])
			return int(x) < int(y))
	await _checkpoint("Persons.work:line:1188")
	for kk: Variant in keys:
		await _checkpoint("Persons.work:loop:1188")
		var b: Dictionary = biz[int(kk)]
		var job_count: int = int(f["jobs"][kk])
		if job_count <= 0: continue
		counts.append(job_count)
		# No simulation mutation interleaves with one employer's repeated slots.
		# Keep the first title lookup at its native position, including farm ensure.
		var job_title: String = Recruits.job_title(e, b)
		var workplace: String = Businesses.title(e, b, names_scope)
		var job_wage: float = float(b["wage"])
		places.append({"kind": "job", "title": job_title, "where": workplace, "wage": job_wage, "biz": int(kk)})
	await _checkpoint("Persons.work:line:1199")
	var CJ: Dictionary = TownEcon.data()["casual_jobs"]
	await _checkpoint("Persons.work:line:1200")
	for j: Variant in f.get("cj", {}):
		await _checkpoint("Persons.work:loop:1200")
		var casual_count: int = int(f["cj"][j])
		if casual_count <= 0: continue
		counts.append(casual_count)
		var casual_title: String = String(CJ[j]["name"])
		var casual_wage: float = Barge.casual_wage(e, String(j))
		places.append({"kind": "casual", "title": casual_title, "where": "casual work", "wage": casual_wage, "cj": String(j)})
	await _checkpoint("Persons.work:line:1207")
	if compact: return Population.named_work(e, f, home, places, counts)
	await _checkpoint("Persons.work:line:1208")
	var block: int = 0
	await _checkpoint("Persons.work:line:1209")
	var first: int = 0
	await _checkpoint("Persons.work:line:1210")
	for i: int in home.size():
		await _checkpoint("Persons.work:loop:1210")
		var p: Array = home[i]
		while block < counts.size() and i >= first + counts[block]:
			await _checkpoint("Persons.work:loop:1212")
			first += counts[block]
			block += 1
		if block < places.size():
			# The first slot owns its template; later slots copy before any
			# Academy title/swap processing can mutate a person's dictionary.
			out[int(p[0])] = places[block] if i == first else (places[block] as Dictionary).duplicate()
		else:
			var st: Variant = "poorhouse" if f.get("shel", false) else ("homeless" if int(f.get("homes", 1)) <= 0 else "idle")
			out[int(p[0])] = {"kind": "none", "title": {"poorhouse": "in the poorhouse, no work", "homeless": "sleeping rough, no work",
				"idle": "out of work"}[st], "where": "", "wage": 0.0}
	await _checkpoint("Persons.work:line:1223")
	if e.has("academy") and (f["jobs"] as Dictionary).has(str(int(e["academy"]))):
		Academy.mark_lead(e, f, out)   # v0.012: the research house's lead holds his family's place there, under his title
		var research: Variant = Academy.biz_of(e)
		for p: Variant in home:
			await _checkpoint("Persons.work:loop:1226")
			var job: Dictionary = out.get(int(p[0]), {})
			if int(job.get("biz", -1)) != int(e["academy"]) or bool(job.get("keeper", false)) or String(job.get("title", "")) == Academy.lead_title(e):
				continue
			var fallback: Variant = float(Academy.R()["new_skill"]) if bool(research.get("personal_training", false)) else float(research.get("skill", 0.0))
			var title: Variant = "chemist" if Academy._skill(p, fallback) >= 3.0 else "apprentice"
			out[int(p[0])] = job.duplicate()
			out[int(p[0])]["title"] = title
	await _checkpoint("Persons.work:line:1234")
	for p: Variant in Persons.kp(f):
		await _checkpoint("Persons.work:loop:1234")
		var job: Variant = String(f.get("child_cj", {}).get(str(int(p[0])), ""))
		if job == "" or not Shelter.cleanup_child_eligible(e, p, float(Game.day), f): continue
		var share: Variant = float(Barge.B()["labour"]["kid_share"])
		out[int(p[0])] = {"kind": "casual", "title": String(CJ[job]["name"]), "where": "short child shift", "wage": Barge.casual_wage(e, job) * share, "cj": job, "share": share}
	await _checkpoint("Persons.work:line:1239")
	return out

## Native game/campaign/army.gd:743; operations retained in original order.
func _rest_army_pay_town(game: Variant, town: Dictionary) -> float:
	await _checkpoint("Army.pay_town")
	await _checkpoint("Army.pay_town:line:744")
	if not TownEcon.has_econ(town):
		return 0.0
	await _checkpoint("Army.pay_town:line:746")
	var e: Dictionary = town["econ"]
	await _checkpoint("Army.pay_town:line:747")
	await _rest_town_defence_daily(game, town)
	await _checkpoint("Army.pay_town:line:748")
	var wb: Variant = Militia.band_of(game, town["id"])
	await _checkpoint("Army.pay_town:line:749")
	if wb.is_empty():
		e["stats"]["militia_wages"] = 0.0
		e["stats"]["militia_bill"] = 0.0
		return 0.0
	await _checkpoint("Army.pay_town:line:753")
	if not wb.get("mustered", false) and not wb.get("drill_today", false):
		e["stats"]["militia_wages"] = 0.0; e["stats"]["militia_bill"] = 0.0
		return 0.0
	await _checkpoint("Army.pay_town:line:756")
	var units: Array = (wb["units"] as Array).filter(func(u: Variant): return not u.dead)
	await _checkpoint("Army.pay_town:line:757")
	units.sort_custom(func(a: Variant, b: Variant): return a.rank > b.rank if a.rank != b.rank else a.uid < b.uid)
	await _checkpoint("Army.pay_town:line:758")
	var tier: Variant = Army.town_tier(town)
	# barge part 4 section 1: the garrison is paid when the treasury holds the bill and a reserve (a quarter of its short
	# line [ours]); else the day's pay is owed, and repaid when the treasury can (the owed coin goes to the men's homes)
	await _checkpoint("Army.pay_town:line:761")
	var bill: Variant = Army.town_bill(game, town)
	await _checkpoint("Army.pay_town:line:762")
	var reserve: Variant = float(Barge.treasury_lines(e)["short"]) * 0.25
	await _checkpoint("Army.pay_town:line:763")
	var res: Variant = {}
	await _checkpoint("Army.pay_town:line:764")
	if float(e["treasury"]) >= bill + reserve:
		res = await _rest_army_pay_units(game, units, {"kind": "town", "e": e}, tier, TownEcon.culture_of(e))
		var owed: Variant = float(e.get("garrison_owed", 0.0))
		if owed > 0.0 and float(e["treasury"]) > owed + reserve + bill * 7.0 and not units.is_empty():
			var each: Variant = owed / float(units.size())
			for u: Variant in units:
				await _checkpoint("Army.pay_town:loop:769")
				var f: Variant = People.fam_of(town, u.family)
				if not f.is_empty() and not f["gone"]:
					f["purse"] = float(f["purse"]) + each
					e["treasury"] = float(e["treasury"]) - each
					e["garrison_owed"] = float(e["garrison_owed"]) - each
	else:
		for u: Variant in units:
			await _checkpoint("Army.pay_town:loop:776")
			u.unpaid_days += 1
			u.last_pay = 0.0
		e["garrison_owed"] = float(e.get("garrison_owed", 0.0)) + bill
		res = {"bill": bill, "paid": 0.0, "unpaid": units.size()}
	await _checkpoint("Army.pay_town:line:781")
	e["stats"]["militia_wages"] = res["paid"]
	await _checkpoint("Army.pay_town:line:782")
	e["stats"]["militia_bill"] = res["bill"]
	await _checkpoint("Army.pay_town:line:783")
	e["stats"]["militia_unpaid"] = res["unpaid"]
	await _checkpoint("Army.pay_town:line:784")
	wb["unpaid_n"] = res["unpaid"]
	# (militiamen live and eat at home: no field stores; what they win in a fight they hold for the town)
	# the unpaid walk home; the rest keep their ranks (the tree is per band)
	# barge part 4 section 8: unpaid militia desert 12% a day (each man his own roll, seeded)
	await _checkpoint("Army.pay_town:line:788")
	var gone: Variant = []
	await _checkpoint("Army.pay_town:line:789")
	var md: Variant = float(Army.A().get("militia_desert", 0.12))
	await _checkpoint("Army.pay_town:line:790")
	for u: Variant in units:
		await _checkpoint("Army.pay_town:loop:790")
		if u.unpaid_days > 0:
			var r: Variant = float(absi(hash([u.uid, int(game.day), "mdesert"])) % 10000) / 10000.0
			if r < md:
				gone.append(u)
	await _checkpoint("Army.pay_town:line:795")
	for u: Variant in gone:
		await _checkpoint("Army.pay_town:loop:795")
		(wb["units"] as Array).erase(u)
		ArmsTrade.kit_home(game, u)   # arms trade: his kit stays in the town's armory
		People.release(town, u.family, "militia", u.uid)
		var f: Variant = People.fam_of(town, u.family)
		if not f.is_empty():
			Families.event(f, "deserted", [u.name, "the militia"], float(game.day))
	await _checkpoint("Army.pay_town:line:802")
	if not gone.is_empty():
		CampaignWorld.log_event(game, "%d of the militia of %s went home unpaid." % [gone.size(), town["name"]])
	await _checkpoint("Army.pay_town:line:804")
	Army.update_band_tree(game, town, wb, tier)
	await _checkpoint("Army.pay_town:line:805")
	return float(res["paid"])

## Native game/campaign/army.gd:631; operations retained in original order.
func _rest_army_pay_units(game: Variant, units: Array, payer: Dictionary, tier: String, cul: Dictionary, lo_override: int = -2) -> Dictionary:
	await _checkpoint("Army.pay_units")
	await _checkpoint("Army.pay_units:line:632")
	var w: Dictionary = game.world
	await _checkpoint("Army.pay_units:line:633")
	var mix: Dictionary = cul.get("pay", {"coin": 1.0})
	await _checkpoint("Army.pay_units:line:634")
	if String(payer["kind"]) == "camp":
		mix = {"coin": 1.0}
	await _checkpoint("Army.pay_units:line:636")
	var lo: Variant = lo_override if lo_override >= -1 else Army.low_officer(units, tier)
	await _checkpoint("Army.pay_units:line:637")
	var bill: Variant = 0.0; var paid: Variant = 0.0; var unpaid: Variant = 0
	await _checkpoint("Army.pay_units:line:638")
	for u: Variant in units:
		await _checkpoint("Army.pay_units:loop:638")
		if u.dead:
			continue
		var wg: Variant = Army.wage(tier, u.rank, lo, u)
		bill += wg
		var town: Dictionary = w["towns"].get(u.home_town, {})
		var f: Variant = People.fam_of(town, u.family)
		if f.is_empty() or f["gone"]:
			u.unpaid_days = 0   # nobody at home to pay (an orphaned record): he serves for his keep
			continue
		var e: Dictionary = town["econ"]
		var coin: Variant = wg * float(mix.get("coin", 0.0))
		var loot: Variant = wg * float(mix.get("loot", 0.0))
		var took_loot: Variant = 0.0
		if loot > 0.0 and String(payer["kind"]) == "faction":
			took_loot = minf(loot, float(payer["fac"].get("loot", 0.0)))
		coin += loot - took_loot
		# kind: food (grain, then meat) and beer from the home market
		var buys: Variant = []
		var kind_cost: Variant = 0.0
		for part: Variant in [["food", ["grain", "meat"]], ["beer", ["beer"]]]:
			await _checkpoint("Army.pay_units:loop:658")
			var val: Variant = wg * float(mix.get(part[0], 0.0))
			if val <= 0.0:
				continue
			for g: Variant in part[1]:
				await _checkpoint("Army.pay_units:loop:662")
				if val <= 0.01:
					break
				var p: Variant = float(e["price"].get(g, 1.0))
				var q: Variant = mini(int(val / p), int(e["stock"].get(g, 0)))
				if q > 0:
					buys.append([g, q, part[0]])
					kind_cost += float(q) * p
					val -= float(q) * p
			coin += val   # what the market could not supply comes as coin
		var need: Variant = coin + kind_cost
		if Army._funds(payer) < need:
			u.unpaid_days += 1
			u.last_pay = 0.0
			unpaid += 1
			continue
		Army._spend(payer, need)
		if String(payer["kind"]) == "camp":
			TownEcon.gold_out(-need)   # stolen coin comes back into a town purse
		if took_loot > 0.0:
			payer["fac"]["loot"] = float(payer["fac"]["loot"]) - took_loot
			TownEcon.gold_out(-took_loot)   # loot comes back into a town purse
		f["purse"] = float(f["purse"]) + coin + took_loot
		if kind_cost > 0.0:
			var mkt: Dictionary = e["biz"][int(e["mkt"])]
			mkt["till"] = float(mkt["till"]) + kind_cost
			var rates: Variant = Families.daily_rates(e, f)
			for b: Variant in buys:
				await _checkpoint("Army.pay_units:loop:689")
				e["stock"][b[0]] = int(e["stock"][b[0]]) - int(b[1])
				e["hh"][b[0]] = int(e["hh"].get(b[0], 0)) + int(b[1])
				var key: Variant = "food" if b[2] == "food" else "drink"
				f["store"][key] = float(f["store"][key]) + float(b[1]) / maxf(0.5, float(rates[key]))
		u.unpaid_days = 0
		u.last_pay = need + took_loot
		paid += need + took_loot
	await _checkpoint("Army.pay_units:line:697")
	return {"bill": bill, "paid": paid, "unpaid": unpaid}

## Native game/campaign/town_defence.gd:132; operations retained in original order.
func _rest_town_defence_daily(game: Variant, town: Dictionary) -> void:
	await _checkpoint("TownDefence.daily")
	await _checkpoint("TownDefence.daily:line:133")
	var e: Dictionary = town["econ"]
	await _checkpoint("TownDefence.daily:line:134")
	var tid: Variant = String(town["id"])
	await _checkpoint("TownDefence.daily:line:135")
	var w: Dictionary = game.world
	await _checkpoint("TownDefence.daily:line:136")
	if not w.has("town_guards"): w["town_guards"] = {}
	await _checkpoint("TownDefence.daily:line:137")
	var P: Dictionary = e.get("plots", {})
	await _checkpoint("TownDefence.daily:line:138")
	var posts: int = int(TownDefence._pay_plot_layout(tid, P)["gates"])
	await _checkpoint("TownDefence.daily:line:139")
	var affordable: Variant = int(maxf(0, float(e["treasury"])) / maxf(1, Army.wage("guard", 0)) / 14)
	await _checkpoint("TownDefence.daily:line:140")
	var target: Variant = mini(posts * 3, affordable) # three eight-hour watches at each actual gate
	await _checkpoint("TownDefence.daily:line:141")
	var gb: Variant = TownDefence.guard_band(game, tid)
	await _checkpoint("TownDefence.daily:line:142")
	if gb.is_empty() and target > 0:
		var rng: Variant = RandomNumberGenerator.new(); rng.seed = hash([w.get("seed", 0), tid, "guards"])
		var units: Array = []
		# Only gear withdrawals/returns interleave here; share one ephemeral stock index.
		var guard_stock: Dictionary = {}
		for i: int in mini(target, TownDefence.eligible(town)):
			await _checkpoint("TownDefence.daily:loop:147")
			var fid: Variant = People.draw(town, rng, "guard")
			if fid < 0: break
			var u: Variant = CampaignWorld.make_resident_troop(rng, String(town["faction"]), town, int(town["wealth"]))
			People.bind(town, fid, u, "guard")
			u.home_town = tid; u.title = "town guard"
			ArmsTrade.outfit_guard(town, u, guard_stock)
			units.append(u)
			Army.state(w)["roll"][str(u.uid)] = [tid, fid, "guard", u.name]
		if not units.is_empty():
			var wid: Variant = CampaignWorld.spawn_warband(game, String(town["faction"]), town["pos"], units.size(), "militia", rng,
				{"units": units, "home": tid, "anchor": town["pos"], "professional": true, "marching": false})
			w["town_guards"][tid] = wid
			gb = TownDefence.guard_band(game, tid)
	await _checkpoint("TownDefence.daily:line:161")
	if not gb.is_empty():
		var living: Array = gb["units"].filter(func(u: Variant): return not u.dead)
		var paid: Variant = await _rest_army_pay_units(game, living, {"kind": "town", "e": e}, "guard", TownEcon.culture_of(e))
		e["stats"]["guard_wages"] = paid["paid"]
		var leaving: Variant = []
		for u: Variant in living:
			await _checkpoint("TownDefence.daily:loop:166")
			if u.unpaid_days >= int(Army.A()["desert_days"]): leaving.append(u)
		for u: Variant in leaving:
			await _checkpoint("TownDefence.daily:loop:168")
			Army.release(game, u, "deserted", "the town guard")
			gb["units"].erase(u)
		gb["units"] = gb["units"].filter(func(u: Variant): return not u.dead)
		# A patrol visits the real pasture plots, returning to the gate between rounds.
		if not gb.get("marching", false) and not gb["units"].is_empty():
			# Revalidate after native recruitment/pay/release, before reading indices.
			var pastures: Array = TownDefence._pay_plot_layout(tid, P)["pastures"]
			if not pastures.is_empty():
				var index: Variant = posmod(int(game.day), pastures.size())
				gb["patrol_goal"] = HerdRaids.plot_pos(town, P, int(pastures[index]))
				gb["path"] = CampaignWorld.find_path(w, gb["pos"], gb["patrol_goal"])
				gb["marching"] = not gb["path"].is_empty()
	await _checkpoint("TownDefence.daily:line:181")
	var mil: Variant = Militia.band_of(game, tid)
	await _checkpoint("TownDefence.daily:line:182")
	if not mil.is_empty():
		var drill: Variant = TownDefence.defence_policy(game, town) != "stand_down" and posmod(int(game.day), 7) == posmod(int(town.get("size", 0)), 7)
		TownDefence.set_muster(game, town, bool(mil.get("mustered", false)), drill)
		if drill: mil["drill_days"] = int(mil.get("drill_days", 0)) + 1
	await _checkpoint("TownDefence.daily:line:186")
	e["barracks_beds"] = maxi(TownDefence.garrison(game, tid).size(), TownDefence.militia_target(town) + target)

## Native game/campaign/bows_econ.gd:118; operations retained in original order.
func _rest_bows_econ_econ_daily(game: Variant, town: Dictionary, e: Dictionary, _D: Dictionary) -> void:
	await _checkpoint("BowsEcon.econ_daily")
	await _checkpoint("BowsEcon.econ_daily:line:119")
	BowsEcon._season(e)
	await _checkpoint("BowsEcon.econ_daily:line:120")
	await _rest_bows_econ_fowl(e)
	await _checkpoint("BowsEcon.econ_daily:line:121")
	await _rest_bows_econ_armory(game, town, e)
	await _checkpoint("BowsEcon.econ_daily:line:122")
	BowsEcon._wood_hint(e)

## Native game/campaign/bows_econ.gd:168; operations retained in original order.
func _rest_bows_econ_armory(game: Variant, town: Dictionary, e: Dictionary) -> void:
	await _checkpoint("BowsEcon._armory")
	await _checkpoint("BowsEcon._armory:line:169")
	if not e.has("armory"):
		e["armory"] = {}
	await _checkpoint("BowsEcon._armory:line:171")
	var arm: Dictionary = e["armory"]
	await _checkpoint("BowsEcon._armory:line:172")
	var tid: Variant = String(town.get("id", ""))
	await _checkpoint("BowsEcon._armory:line:173")
	var n: Variant = BowsEcon.archers(game, tid) if game != null and game.get("world") != null else 0
	await _checkpoint("BowsEcon._armory:line:174")
	var kinds: Variant = BowsEcon.culture_arrows(town)
	await _checkpoint("BowsEcon._armory:line:175")
	var st: Dictionary = e["stock"]
	await _checkpoint("BowsEcon._armory:line:176")
	var price: Dictionary = e["price"]
	await _checkpoint("BowsEcon._armory:line:177")
	var req: Dictionary = e["req"]
	await _checkpoint("BowsEcon._armory:line:178")
	var carry: Dictionary = e["carry"]
	await _checkpoint("BowsEcon._armory:line:179")
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	await _checkpoint("BowsEcon._armory:line:180")
	var G: Dictionary = TownEcon.data()["goods"]
	await _checkpoint("BowsEcon._armory:line:181")
	var tgt_total: Variant = ArmsTrade.reserve_amount(n * DB.QUIVER_MAX)
	await _checkpoint("BowsEcon._armory:line:182")
	e["arrow_reserve"] = tgt_total
	await _checkpoint("BowsEcon._armory:line:183")
	var remaining: Variant = maxi(0, tgt_total - ArmsTrade.arrow_stock(town))
	await _checkpoint("BowsEcon._armory:line:184")
	var budget: Variant = maxf(0.0, float(e["treasury"]) - ArmsTrade.arms_reserve(game, town, e)) * BowsEcon.ARMORY_SPEND
	await _checkpoint("BowsEcon._armory:line:185")
	var preferences: Array = kinds.duplicate()
	await _checkpoint("BowsEcon._armory:line:186")
	var other: Array = DB.arrows.keys(); other.sort()
	await _checkpoint("BowsEcon._armory:line:187")
	for k: Variant in other:
		await _checkpoint("BowsEcon._armory:loop:187")
		if not preferences.has(k): preferences.append(k)
	# Prefer the cultural mix, then fill any remaining aggregate reserve with
	# valid arrows actually available. Foreign arrows work in the same quiver.
	await _checkpoint("BowsEcon._armory:line:191")
	for pass_no: Variant in 2:
		await _checkpoint("BowsEcon._armory:loop:191")
		for i: Variant in preferences.size():
			await _checkpoint("BowsEcon._armory:loop:192")
			var k: String = preferences[i]
			var have: Variant = int(arm.get(k, 0))
			var sh: float = BowsEcon.KIND_SHARES[mini(i, BowsEcon.KIND_SHARES.size() - 1)] if i < kinds.size() else 0.0
			var wanted: Variant = remaining if pass_no == 1 else mini(remaining, maxi(0, int(ceil(float(tgt_total) * sh)) - have))
			if pass_no == 0 and i < kinds.size(): req[k] = float(req.get(k, 0.0)) + float(wanted) / 7.0
			var p: Variant = maxf(0.01, float(price.get(k, G.get(k, {}).get("price", 0.4))))
			var q: Variant = mini(wanted, mini(int(st.get(k, 0)), int(budget / p)))
			if q > 0:
				st[k] = int(st[k]) - q; arm[k] = have + q; remaining -= q
				var cost: Variant = float(q) * p
				budget -= cost; e["treasury"] = float(e["treasury"]) - cost
				ArmsTrade.note_arms_spend(e, cost)
				mkt["till"] = float(mkt["till"]) + cost
				e["stats"]["sales"] = float(e["stats"]["sales"]) + cost
				TownEcon.led(e, "used", k, q)
	# Existing drill consumption uses the preferred mix and actual stored stock.
	await _checkpoint("BowsEcon._armory:line:209")
	var mil: Variant = Militia.band_of(game, tid) if game != null else {}
	await _checkpoint("BowsEcon._armory:line:210")
	for i: Variant in kinds.size():
		await _checkpoint("BowsEcon._armory:loop:210")
		var k: String = kinds[i]
		var sh: float = BowsEcon.KIND_SHARES[mini(i, BowsEcon.KIND_SHARES.size() - 1)]
		var ck: String = "bows_use_" + k
		var practice: Variant = float(n) * BowsEcon.ARROW_USE_DAY * sh if mil.get("drill_today", false) else 0.0
		var amt: Variant = practice + float(carry.get(ck, 0.0))
		var use: Variant = mini(int(floor(amt)), int(arm.get(k, 0)))
		carry[ck] = minf(amt - use, 5.0)
		if use > 0: arm[k] = int(arm[k]) - use
	await _checkpoint("BowsEcon._armory:line:219")
	if game != null and game.get("world") != null:
		for u: Variant in TownDefence.garrison(game, tid):
			await _checkpoint("BowsEcon._armory:loop:220")
			if u.dead or not u.equip.has("ranged"): continue
			for k: Variant in preferences:
				await _checkpoint("BowsEcon._armory:loop:222")
				var room: int = DB.QUIVER_MAX - u.arrows()
				if room <= 0: break
				var q: Variant = mini(room, int(arm.get(k, 0)))
				if q > 0:
					arm[k] = int(arm[k]) - q; u.quiver[k] = int(u.quiver.get(k, 0)) + q
	# spare bows the town wants on its stalls
	await _checkpoint("BowsEcon._armory:line:229")
	e["bow_target"] = int(ceil(float(n) * BowsEcon.BOW_SPARE)) + 1 + int(town.get("size", 0)) / 2

## Native game/campaign/bows_econ.gd:143; operations retained in original order.
func _rest_bows_econ_fowl(e: Dictionary) -> void:
	await _checkpoint("BowsEcon._fowl")
	await _checkpoint("BowsEcon._fowl:line:144")
	if Herds.has(e):
		return
	await _checkpoint("BowsEcon._fowl:line:146")
	var acres: Variant = float(e.get("wacres", {}).get("grain", 0.0))
	await _checkpoint("BowsEcon._fowl:line:147")
	if acres <= 0.0:
		return
	await _checkpoint("BowsEcon._fowl:line:149")
	var carry: Dictionary = e["carry"]
	await _checkpoint("BowsEcon._fowl:line:150")
	var previous: Variant = float(carry.get("bows_fowl", 0.0))
	await _checkpoint("BowsEcon._fowl:line:151")
	var produced: Variant = acres * BowsEcon.FOWL_FEATHERS
	await _checkpoint("BowsEcon._fowl:line:152")
	var amt: Variant = produced + previous
	await _checkpoint("BowsEcon._fowl:line:153")
	var n: Variant = int(floor(amt))
	await _checkpoint("BowsEcon._fowl:line:154")
	carry["bows_fowl"] = amt - n
	await _checkpoint("BowsEcon._fowl:line:155")
	var weights: Variant = {}
	await _checkpoint("BowsEcon._fowl:line:156")
	for f: Variant in e.get("fams", []):
		await _checkpoint("BowsEcon._fowl:loop:156")
		weights["f:%d" % int(f["id"])] = float(f.get("land", {}).get("grain", 0)) * float(f.get("worked", 0.0))
	await _checkpoint("BowsEcon._fowl:line:158")
	HarvestClaims.harvest(e, "feathers", "bows_fowl", weights, produced, n, 0, previous, int(e.get("day", 0)))
	await _checkpoint("BowsEcon._fowl:line:159")
	if n > 0: TownEcon.led(e, "made", "feathers", n)

## Native game/campaign/barge.gd:166; operations retained in original order.
func _rest_barge_update_prices(town: Dictionary, rng: RandomNumberGenerator, every: bool = false) -> void:
	await _checkpoint("Barge.update_prices")
	await _checkpoint("Barge.update_prices:line:167")
	Barge._init_prices()
	await _checkpoint("Barge.update_prices:line:168")
	var e: Dictionary = town["econ"]
	await _checkpoint("Barge.update_prices:line:169")
	var Bd: Variant = Barge.B()
	await _checkpoint("Barge.update_prices:line:170")
	var de: Variant = float(Bd["demand_ema"]); var se: Variant = float(Bd["supply_ema"]); var noise: Variant = float(Bd["noise"])
	await _checkpoint("Barge.update_prices:line:171")
	var req: Dictionary = e["req"]
	await _checkpoint("Barge.update_prices:line:172")
	var bdem: Dictionary = e.get("bdem", {})
	await _checkpoint("Barge.update_prices:line:173")
	var dem: Dictionary = e["dem"]
	await _checkpoint("Barge.update_prices:line:174")
	if not e.has("sup"):
		e["sup"] = {}
	await _checkpoint("Barge.update_prices:line:176")
	var sup: Dictionary = e["sup"]
	await _checkpoint("Barge.update_prices:line:177")
	if not e.has("pmade"):
		e["pmade"] = {}
	await _checkpoint("Barge.update_prices:line:179")
	var pmade: Dictionary = e["pmade"]
	await _checkpoint("Barge.update_prices:line:180")
	var made: Dictionary = e["led"]["made"]
	await _checkpoint("Barge.update_prices:line:181")
	var st: Dictionary = e["stock"]
	await _checkpoint("Barge.update_prices:line:182")
	var barn: Dictionary = e["barn"]
	await _checkpoint("Barge.update_prices:line:183")
	var price: Dictionary = e["price"]
	await _checkpoint("Barge.update_prices:line:184")
	var need: Dictionary = e["need"]
	await _checkpoint("Barge.update_prices:line:185")
	var P: Variant = Barge.pl(e)
	await _checkpoint("Barge.update_prices:line:186")
	var cin: Dictionary = e.get("cin", {})
	# staples together: the town's staple days (all staple goods' stock over their demand)
	await _checkpoint("Barge.update_prices:line:188")
	var sst: Variant = 0.0; var sdm: Variant = 0.0
	await _checkpoint("Barge.update_prices:line:189")
	for i: Variant in Barge._pg.size():
		await _checkpoint("Barge.update_prices:loop:189")
		if Barge._pstaple[i]:
			var g0: String = Barge._pg[i]
			sst += float(st.get(g0, 0)) + float(barn.get(g0, 0))
			sdm += float(dem.get(g0, 0.0))
	await _checkpoint("Barge.update_prices:line:194")
	var staple_days: Variant = sst / maxf(0.01, sdm)
	await _checkpoint("Barge.update_prices:line:195")
	var mf: Variant = float(Bd["made_floor"])
	await _checkpoint("Barge.update_prices:line:196")
	var de2: Variant = 1.0 - pow(1.0 - de, 2.0)
	await _checkpoint("Barge.update_prices:line:197")
	var se2: Variant = 1.0 - pow(1.0 - se, 2.0)
	await _checkpoint("Barge.update_prices:line:198")
	var par: Variant = int(e.get("day", 0)) % 2
	await _checkpoint("Barge.update_prices:line:199")
	for i: Variant in Barge._pg.size():
		await _checkpoint("Barge.update_prices:loop:199")
		var g: String = Barge._pg[i]
		# keeping goods other than staples are worked in 2-day steps (the same daily rates; half the work, like the
		# spoilage's 3-day steps); staples and fresh food every day
		var two: bool = not every and not Barge._pfresh[i] and not Barge._pstaple[i]
		if two and i % 2 != par:
			continue
		var dt: Variant = 2.0 if two else 1.0
		var base: float = Barge._pbase[i]
		var el: float = Barge._pel[i]
		var tg: float = Barge._ptgt[i]
		var d1: float = dem.get(g, 0.0)
		d1 += (float(req.get(g, 0.0)) / dt + float(bdem.get(g, 0.0)) - d1) * (de2 if two else de)
		req.erase(g)
		dem[g] = d1
		var mnow: Variant = float(made.get(g, 0)) + float(cin.get(g, 0))
		var inflow: Variant = maxf(0.0, mnow - float(pmade.get(g, mnow))) / dt
		pmade[g] = mnow
		var s1: float = sup.get(g, d1)
		s1 += (inflow - s1) * (se2 if two else se)
		sup[g] = s1
		need[g] = d1 * tg
		var stock: Variant = float(st.get(g, 0)) + float(barn.get(g, 0))
		var sc: Variant = 1.0
		if Barge._pfresh[i]:
			sc = pow(maxf(d1, 0.0001) / maxf(0.0001, s1 + 0.35 * stock), 1.4 * el)
		else:
			sc = pow(tg * maxf(d1, 0.0001) / maxf(0.0001, stock), el)
		sc = clampf(sc, 0.2, 40.0)
		var tgt: Variant = base * P * sc
		if Barge._pstaple[i]:
			tgt = sqrt(tgt * base * P * pow(40.0 / maxf(0.01, staple_days), 0.8))
		var rl: Array = Barge._precs[i]
		if not rl.is_empty():
			var lo: Variant = INF
			for pairs: Variant in rl:
				await _checkpoint("Barge.update_prices:loop:234")
				var c: Variant = 0.0
				for pr: Variant in pairs:
					await _checkpoint("Barge.update_prices:loop:236")
					c += float(pr[1]) * float(price.get(pr[0], 1.0))
				lo = minf(lo, c)
			tgt = maxf(tgt, mf * lo)
		var p0: float = price.get(g, base * P)
		var stp: float = Barge._pstep[i]
		if two:
			stp = 1.0 - (1.0 - stp) * (1.0 - stp)
		var p1: Variant = p0 + (tgt - p0) * stp
		p1 *= 1.0 + noise * (rng.randf() * 2.0 - 1.0)
		if g in ["grain", "fruit", "meat", "fresh_meat"]:
			price[g] = maxf(p1, Barge._pfloor[i] * base * P)
		else:
			price[g] = clampf(p1, Barge._pfloor[i] * base * P, Barge._pceil[i] * base * P)

## Native game/campaign/barge.gd:454; operations retained in original order.
func _rest_barge_labour_day(e: Dictionary, si: int) -> void:
	await _checkpoint("Barge.labour_day")
	await _checkpoint("Barge.labour_day:line:455")
	var L: Dictionary = Barge.B()["labour"]
	await _checkpoint("Barge.labour_day:line:456")
	if not e.has("idle_n"):
		Barge.recount_week(e)
	await _checkpoint("Barge.labour_day:line:458")
	var dem: Variant = 0.0; var sup: Variant = 0.0
	await _checkpoint("Barge.labour_day:line:459")
	var bs: Variant = float(L["builder_season"][si])
	await _checkpoint("Barge.labour_day:line:460")
	for b: Variant in e["biz"]:
		await _checkpoint("Barge.labour_day:loop:460")
		var lk: int = b.get("lk", -1)
		if lk < 0:
			lk = Barge.labour_kind(b)
		if b["closed"]:
			continue
		var cap: Variant = float(b["cap"]); var w: Variant = float(b["workers"])
		match lk:
			1:
				# Family and estate capacities include their seasonal crop hands on
				# ordinary turns. Count real places once, including filled ones.
				dem += cap
				sup += w
			2:
				dem += cap * (bs if b["type"] == "builder" else 1.0)
				sup += w
			0:
				dem += maxf(0.0, cap - w)
	await _checkpoint("Barge.labour_day:line:478")
	var cjc: Dictionary = e.get("cjcap", {})
	await _checkpoint("Barge.labour_day:line:479")
	for j: Variant in cjc:
		await _checkpoint("Barge.labour_day:loop:479")
		dem += float(cjc[j])
	await _checkpoint("Barge.labour_day:line:481")
	var cju: Dictionary = e.get("cjused", {})
	await _checkpoint("Barge.labour_day:line:482")
	for j: Variant in cju:
		await _checkpoint("Barge.labour_day:loop:482")
		sup += float(cju[j])
	await _checkpoint("Barge.labour_day:line:484")
	sup += float(e.get("idle_n", 0))
	await _checkpoint("Barge.labour_day:line:485")
	dem *= 1.0 - float(L["shortage_cut"]) * Barge.shortage(e)
	await _checkpoint("Barge.labour_day:line:486")
	var wage: Variant = clampf(float(L["base"]) * pow(maxf(dem, 0.5) / maxf(sup, 1.0), float(L["power"])), float(L["min"]), float(L["max"])) * Barge.wage_mult(e)
	await _checkpoint("Barge.labour_day:line:487")
	e["dwage"] = snappedf(wage, 0.01)
	await _checkpoint("Barge.labour_day:line:488")
	e["ldem"] = snappedf(dem, 0.1)
	await _checkpoint("Barge.labour_day:line:489")
	e["lsup"] = snappedf(sup, 0.1)

## Native game/campaign/barge.gd:939; operations retained in original order.
func _rest_barge_coin_town(game: Variant, t: Dictionary, e: Dictionary) -> void:
	await _checkpoint("Barge.coin_town")
	await _checkpoint("Barge.coin_town:line:940")
	var dr: Variant = float(Barge.B()["coin"]["drain"])
	await _checkpoint("Barge.coin_town:line:941")
	var lost: Variant = 0.0
	await _checkpoint("Barge.coin_town:line:942")
	var held: Variant = 0.0
	await _checkpoint("Barge.coin_town:line:943")
	var k: Variant = 1.0 - dr
	# (family purses lose theirs at the family's weekly turn: purse_drain)
	await _checkpoint("Barge.coin_town:line:945")
	for b: Variant in e["biz"]:
		await _checkpoint("Barge.coin_town:loop:945")
		var tl: float = b["till"]
		if tl > 0.0:
			b["till"] = tl * k
			lost += tl * dr
			held += tl * k
	await _checkpoint("Barge.coin_town:line:951")
	var tr: Variant = float(e["treasury"])
	await _checkpoint("Barge.coin_town:line:952")
	if tr > 0.0:
		e["treasury"] = tr * k
		lost += tr * dr
	await _checkpoint("Barge.coin_town:line:955")
	var lf: Variant = float(e.get("land_fund", 0.0))
	await _checkpoint("Barge.coin_town:line:956")
	if lf > 0.0:
		e["land_fund"] = lf * k
		lost += lf * dr
	await _checkpoint("Barge.coin_town:line:959")
	Barge.drained(game.world, lost)
	await _checkpoint("Barge.coin_town:line:960")
	Barge.mint_day(game, t, e)
	await _checkpoint("Barge.coin_town:line:961")
	Barge.melt_day(game, t, e)
	await _checkpoint("Barge.coin_town:line:962")
	e["coin_now"] = held + float(e["treasury"]) + float(e["farm_till"]) + float(e.get("land_fund", 0.0)) + float(e.get("purses_n", 0.0))   # (purses: as of the town's weekly turn)

## Native game/campaign/supply_orders.gd:264; operations retained in original order.
func _rest_supply_orders_daily(game: Variant, town: Dictionary, day: int) -> void:
	await _checkpoint("SupplyOrders.daily")
	await _checkpoint("SupplyOrders.daily:line:265")
	if SupplyOrders.orders(town).is_empty() or int(town["econ"].get("supply_day", -1)) >= day: return
	await _checkpoint("SupplyOrders.daily:line:266")
	town["econ"]["supply_day"] = day
	await _checkpoint("SupplyOrders.daily:line:267")
	for order: Dictionary in SupplyOrders.orders(town):
		await _checkpoint("SupplyOrders.daily:loop:267")
		if not order.get("closed", false) and str(order["caravan"]) == "":
			SupplyOrders.depart(game, str(town["id"]), str(order["id"]))
