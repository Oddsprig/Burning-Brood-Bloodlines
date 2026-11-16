class_name CampaignTurnJob
extends "res://campaign/campaign_checkpoint_job.gd"
## Independent town/household/realm continuations. Requires combined r5's shared
## frame, observer, RNG and save transaction; does not replace any economy worker.
const KINDS: Array = ["tturn", "fam", "fam2", "fturn"]
var header: Array = []
var checkpoints: int = 0
var visits: Dictionary = {}
var yielded_labels: Dictionary = {}
# Test-only forcing; zero keeps the production 750-us checkpoint policy.
var force_every: int = 0

func _init(job: Array) -> void:
	header = job.duplicate()

func step(game: Variant) -> bool:
	# r5 also dispatches prepared heads; retain the original pause state once.
	if budgeted and not holds_tree:
		hold(game)
	return super.step(game)

static func prepare_frame_head(w: Dictionary) -> void:
	var work: Array = w.get("work", [])
	if work.is_empty() or not (work[0] is Array):
		return
	var head: Array = work[0]
	if head.is_empty() or String(head[0]) not in KINDS or head[-1] is Object:
		return
	head.append(CampaignTurnJob.new(head))

static func reserve_frame_job(game: Variant, job: Array, budgeted: bool) -> bool:
	if not budgeted or String(job[0]) not in KINDS:
		return false
	assert(game.has_method("_day_job_claim"), "Town/household split requires combined r5's shared transaction.")
	var work: Array = game.world["work"]
	work.push_front(job)
	prepare_frame_head(game.world)
	var run: CampaignDayJob = job[-1]
	game._day_job_begin_dispatch()
	game._day_job_claim(run)
	run.hold(game)
	game._note_day_job_slice()
	game._day_job_cancel_dispatch()
	return true

func _checkpoint(label: String) -> void:
	checkpoints += 1
	visits[label] = int(visits.get(label, 0)) + 1
	if budgeted and force_every > 0 and checkpoints % force_every == 0:
		_deadline_usec = 0
	var before: int = yields
	await super._checkpoint(label)
	if yields > before:
		yielded_labels[label] = int(yielded_labels.get(label, 0)) + 1

func _step_label() -> String:
	return String(header[0]) + "/" + boundary

func _run(game: Variant) -> void:
	match String(header[0]):
		"tturn":
			if game.world["towns"].has(header[1]):
				await _town_econ_town_turn(game, game.world["towns"][header[1]], int(header[2]))
		"fam", "fam2":
			if game.world["towns"].has(header[1]):
				await _town_econ_family_batch(game, game.world["towns"][header[1]], int(header[2]), 0 if header[0] == "fam" else 1)
		"fturn":
			await _town_econ_faction_turn(game, int(header[1]))
	_finished = true

## Reuse the exact r5 canonical buy implementation, as its atomic wrapper does.
## This turns its existing single-iteration driver into awaited checkpoints.
func _loans_land_buys(e: Dictionary) -> void:
	await _checkpoint("Loans.land_buys:begin")
	var run: Variant = Loans.begin_land_buys(e)
	while not Loans.land_buys_step(run):
		await _checkpoint("Loans.land_buys:iteration")

## Native game/campaign/town_econ.gd:224; only qualification, types, awaits and checkpoints added.
func _town_econ_family_batch(game: Variant, town: Dictionary, day: int, half: int = -1) -> void:
	await _checkpoint("TownEcon.family_batch")
	await _checkpoint("TownEcon.family_batch:225")
	if not TownEcon.has_econ(town):
		return
	await _checkpoint("TownEcon.family_batch:227")
	var e: Dictionary = town["econ"]
	await _checkpoint("TownEcon.family_batch:228")
	var rng: Variant = RandomNumberGenerator.new()
	await _checkpoint("TownEcon.family_batch:229")
	rng.seed = hash([int(game.world.get("seed", 0)), town["id"], day, "fam", half])
	await _checkpoint("TownEcon.family_batch:230")
	var fams: Array = e["fams"]
	await _checkpoint("TownEcon.family_batch:231")
	var i: Variant = day % 7 + (7 * half if half >= 0 else 0)
	await _checkpoint("TownEcon.family_batch:232")
	var stepn: Variant = 14 if half >= 0 else 7
	await _checkpoint("TownEcon.family_batch:233")
	TownEcon.batch_open = true
	await _checkpoint("TownEcon.family_batch:234")
	while i < fams.size():
		await _checkpoint("TownEcon.family_batch:loop:234")
		Families.turn(game, town, e, fams[i], float(day), rng)
		i += stepn
	await _checkpoint("TownEcon.family_batch:237")
	TownEcon.batch_open = false
	await _checkpoint("TownEcon.family_batch:238")
	TownEcon.batch_half = half
	await _checkpoint("TownEcon.family_batch:239")
	var t0: Variant = Time.get_ticks_usec() if TownEcon.prof_on else 0
	await _checkpoint("TownEcon.family_batch:240")
	await _town_econ_clear_batch(e)
	await _checkpoint("TownEcon.family_batch:241")
	if TownEcon.prof_on: TownEcon._prof("f_clear_batch", t0)
	await _checkpoint("TownEcon.family_batch:242")
	TownEcon.batch_half = -1
	# An owner's ordinary turn can fund or expand private farm places after
	# idle civilians have already had their weekly turn. Complete this batch's
	# actual funded matching without advancing anyone's wages or payday.
	await _checkpoint("TownEcon.family_batch:246")
	await _families_match_idle(e)

## Native game/campaign/town_econ.gd:264; only qualification, types, awaits and checkpoints added.
func _town_econ_clear_batch(e: Dictionary) -> void:
	await _checkpoint("TownEcon.clear_batch")
	await _checkpoint("TownEcon.clear_batch:265")
	if TownEcon.batch_half != 0 and not (e.get("land_sell_q", []) as Array).is_empty():
		Loans.settle_land_sales(e)
	await _checkpoint("TownEcon.clear_batch:267")
	if TownEcon.batch.is_empty():
		return
	await _checkpoint("TownEcon.clear_batch:269")
	HarvestClaims.ensure(e)
	await _checkpoint("TownEcon.clear_batch:270")
	HarvestClaims.reserve_all(e)
	await _checkpoint("TownEcon.clear_batch:271")
	var prune_scope: Array[Dictionary] = [{}]
	await _checkpoint("TownEcon.clear_batch:272")
	e["_barn_available"] = {}
	await _checkpoint("TownEcon.clear_batch:273")
	var st: Dictionary = e["stock"]
	await _checkpoint("TownEcon.clear_batch:274")
	var barn: Dictionary = e["barn"]
	await _checkpoint("TownEcon.clear_batch:275")
	var price: Dictionary = e["price"]
	await _checkpoint("TownEcon.clear_batch:276")
	var hh: Dictionary = e["hh"]
	# orders the barns cannot fill go on to the market (the family buys the rest there)
	await _checkpoint("TownEcon.clear_batch:278")
	var bwant: Variant = {}
	await _checkpoint("TownEcon.clear_batch:279")
	if TownEcon.batch_barn:
		for o: Variant in TownEcon.batch:
			await _checkpoint("TownEcon.clear_batch:loop:280")
			if o.size() > 5:
				bwant[o[1]] = int(bwant.get(o[1], 0)) + int(o[2])
	await _checkpoint("TownEcon.clear_batch:283")
	TownEcon.batch_barn = false
	await _checkpoint("TownEcon.clear_batch:284")
	var bavail: Variant = {}
	await _checkpoint("TownEcon.clear_batch:285")
	if not bwant.is_empty():
		for g0: Variant in bwant:
			await _checkpoint("TownEcon.clear_batch:loop:286")
			bavail[g0] = HarvestClaims.available(e, String(g0))
		var extra: Variant = []
		for o: Variant in TownEcon.batch:
			await _checkpoint("TownEcon.clear_batch:loop:289")
			if o.size() <= 5:
				continue
			var g0: String = o[1]
			var r0: Variant = minf(1.0, float(bavail[g0]) / maxf(1.0, float(bwant[g0])))
			var take: Variant = int(float(o[2]) * r0)
			if take < int(o[2]):
				extra.append([o[0], g0, int(o[2]) - take, o[3], o[4]])
				o[2] = take
		TownEcon.batch.append_array(extra)
	await _checkpoint("TownEcon.clear_batch:299")
	var tot: Variant = {}
	await _checkpoint("TownEcon.clear_batch:300")
	var btot: Variant = {}
	await _checkpoint("TownEcon.clear_batch:301")
	for o: Variant in TownEcon.batch:
		await _checkpoint("TownEcon.clear_batch:loop:301")
		var g: String = o[1]
		if o.size() > 5:
			btot[g] = int(btot.get(g, 0)) + int(o[2])
		else:
			tot[g] = int(tot.get(g, 0)) + int(o[2])
	await _checkpoint("TownEcon.clear_batch:307")
	var ratio: Variant = {}
	await _checkpoint("TownEcon.clear_batch:308")
	for g: Variant in tot:
		await _checkpoint("TownEcon.clear_batch:loop:308")
		ratio[g] = minf(1.0, float(st.get(g, 0)) / maxf(1.0, float(tot[g])))
	await _checkpoint("TownEcon.clear_batch:310")
	var bratio: Variant = {}
	await _checkpoint("TownEcon.clear_batch:311")
	for g: Variant in btot:
		await _checkpoint("TownEcon.clear_batch:loop:311")
		var av: int = int(bavail[g]) if bavail.has(g) else HarvestClaims.available(e, String(g))
		bratio[g] = minf(1.0, float(av) / maxf(1.0, float(btot[g])))
	await _checkpoint("TownEcon.clear_batch:314")
	var paid: Variant = 0.0
	await _checkpoint("TownEcon.clear_batch:315")
	var mk: Variant = TownEcon.markup()
	await _checkpoint("TownEcon.clear_batch:316")
	var dm: Variant = {}   # good -> [bought, unmet, unaffordable] (barge demand)
	await _checkpoint("TownEcon.clear_batch:317")
	for o: Variant in TownEcon.batch:
		await _checkpoint("TownEcon.clear_batch:loop:317")
		var q: int = o[2]
		if q <= 0:
			continue
		var g: String = o[1]
		var from_barn: bool = o.size() > 5
		var n0: Variant = int(float(q) * float(bratio[g] if from_barn else ratio[g]))
		var n: Variant = n0
		var f: Dictionary = o[0]
		var p: float = float(price[g]) * (float(o[5]) if from_barn else mk)
		var purse: float = f["purse"]
		if float(n) * p > purse - 1.0:
			n = int(maxf(0.0, purse - 1.0) / p)
		var src: Dictionary = barn if from_barn else st
		var have: Variant = HarvestClaims.available(e, g) if from_barn else int(src.get(g, 0))
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
			var taken: Dictionary = HarvestClaims._take_available(e, g, n, float(have), true, "", prune_scope)
			HarvestClaims.credit(e, taken["shares"], float(n) * p)
		else:
			src[g] = have - n
			paid += float(n) * p
		match o[3]:
			"home":
				if f.has("lodging"): TownHousing.leave(e, f, float(e["day"]))
				f["homes"] = int(f["homes"]) + n
				e["homes"] = int(e["homes"]) + n
				TownEcon.led(e, "used", "home", n)
				if f["named"]:
					Families.add_hist(f, "Bought a new home.", float(e["day"]))
				continue
			"lux":
				TownEcon.led(e, "used", g, n)   # enjoyed at once
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
	await _checkpoint("TownEcon.clear_batch:371")
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	await _checkpoint("TownEcon.clear_batch:372")
	mkt["till"] = float(mkt["till"]) + paid
	await _checkpoint("TownEcon.clear_batch:373")
	e["stats"]["sales"] = float(e["stats"]["sales"]) + paid
	await _checkpoint("TownEcon.clear_batch:374")
	for g: Variant in dm:
		await _checkpoint("TownEcon.clear_batch:loop:374")
		Barge.add_demand(e, g, dm[g][0], dm[g][1], dm[g][2])
	await _checkpoint("TownEcon.clear_batch:376")
	e.erase("_barn_available")
	await _checkpoint("TownEcon.clear_batch:377")
	TownEcon.batch.clear()

## Native game/campaign/town_econ.gd:912; only qualification, types, awaits and checkpoints added.
func _town_econ_town_turn(game: Variant, town: Dictionary, day: int) -> void:
	await _checkpoint("TownEcon.town_turn")
	await _checkpoint("TownEcon.town_turn:913")
	if not TownEcon.has_econ(town):
		return
	await _checkpoint("TownEcon.town_turn:915")
	var e: Dictionary = town["econ"]
	await _checkpoint("TownEcon.town_turn:916")
	var D: Variant = TownEcon.data()
	await _checkpoint("TownEcon.town_turn:917")
	var w: Dictionary = game.world
	await _checkpoint("TownEcon.town_turn:918")
	var T: Dictionary = D["tax"]
	await _checkpoint("TownEcon.town_turn:919")
	var tx: Dictionary = e["tax"]
	await _checkpoint("TownEcon.town_turn:920")
	var stamp: Variant = TownEcon.season_stamp(float(day))
	await _checkpoint("TownEcon.town_turn:921")
	var biz: Array = e["biz"]
	await _checkpoint("TownEcon.town_turn:922")
	var mkt: Dictionary = biz[int(e["mkt"])]
	await _checkpoint("TownEcon.town_turn:923")
	var fams: Array = e["fams"]
	await _checkpoint("TownEcon.town_turn:924")
	await _town_sanitation_weekly(e, float(day))
	await _checkpoint("TownEcon.town_turn:925")
	await _town_housing_weekly(e, float(day))
	await _checkpoint("TownEcon.town_turn:926")
	await _shelter_weekly(game, town, e)   # poorhouse head count, casual places from what the town needs
	# a new tax season
	await _checkpoint("TownEcon.town_turn:928")
	if stamp != int(tx["season"]):
		tx["season"] = stamp
		tx["last_paid"] = float(tx.get("paid", 0.0))
		tx["paid"] = 0.0
		tx["owed"] = 0.0
		var ph: Array = e["stats"]["pop_hist"]
		ph.append(int(e["pop"]))
		while ph.size() > 8:
			await _checkpoint("TownEcon.town_turn:loop:935")
			ph.pop_front()
		# the season's census: births and deaths since the last one (People.census)
		var st: Dictionary = e["stats"]
		st["bd_last"] = [int(st.get("births", 0)) - int(st.get("births_at", 0)), int(st.get("deaths", 0)) - int(st.get("deaths_at", 0))]
		st["births_at"] = int(st.get("births", 0))
		st["deaths_at"] = int(st.get("deaths", 0))
	# collectors: the head hires one per collector_per families; missing ones leak tax
	await _checkpoint("TownEcon.town_turn:943")
	var live: Variant = int(Population.household_stats(e)["households"])
	await _checkpoint("TownEcon.town_turn:944")
	for b: Variant in biz:
		await _checkpoint("TownEcon.town_turn:loop:944")
		if b["type"] == "collector":
			b["cap"] = maxi(1, int(ceil(float(live) / float(T["collector_per"]))))
			tx["leak"] = float(T["leak_max"]) * (1.0 - minf(1.0, float(b["workers"]) / float(b["cap"])))
	# (barge part 4 section 1: the month's taxes run as their own job on the town's tax day: "tmonth")
	await _checkpoint("TownEcon.town_turn:949")
	await _businesses_bid_day(e)   # guarded employer reviews; never reset offers to a pay table
	# the market's sales tax (barge: 3% of shop takings)
	await _checkpoint("TownEcon.town_turn:951")
	var mtax: Variant = minf(float(e["stats"]["sales"]) * float(D["market"]["tax"]), maxf(0.0, float(mkt["till"])))
	await _checkpoint("TownEcon.town_turn:952")
	mkt["till"] = float(mkt["till"]) - mtax
	await _checkpoint("TownEcon.town_turn:953")
	e["treasury"] = float(e["treasury"]) + mtax
	await _checkpoint("TownEcon.town_turn:954")
	e["stats"]["mtax"] = mtax
	await _checkpoint("TownEcon.town_turn:955")
	e["stats"]["sales_week"] = float(e["stats"]["sales"])
	await _checkpoint("TownEcon.town_turn:956")
	e["stats"]["sales"] = 0.0
	# the town's own fields: claims to the treasury, hired hands work them
	await _checkpoint("TownEcon.town_turn:958")
	var est: Dictionary = fams[0]
	await _checkpoint("TownEcon.town_turn:959")
	Families.settle(e, est)
	# land and businesses for sale (the land loop: only if no family buys does the town work it)
	await _checkpoint("TownEcon.town_turn:961")
	await _loans_land_buys(e)
	await _checkpoint("TownEcon.town_turn:962")
	await _town_econ_sell_land(e, D, float(day))
	await _checkpoint("TownEcon.town_turn:963")
	await _town_econ_sell_businesses(e, float(day))
	await _checkpoint("TownEcon.town_turn:964")
	var eb: Dictionary = biz[int(e["estate_biz"])]
	await _checkpoint("TownEcon.town_turn:965")
	var seasonal_need: Variant = Families.seasonal_need_hands(est, float(day), e)
	await _checkpoint("TownEcon.town_turn:966")
	eb["cap"] = maxi(0, int(ceil(seasonal_need - 0.2)))
	await _checkpoint("TownEcon.town_turn:967")
	Families.refresh_worked(e, est)
	# public works: with money above its reserve the head takes on idle hands (walls, roads, wells) [ours]
	await _checkpoint("TownEcon.town_turn:969")
	if e.has("works_biz"):
		var wb2: Dictionary = biz[int(e["works_biz"])]
		var idle: Variant = 0
		for f: Variant in fams:
			await _checkpoint("TownEcon.town_turn:loop:972")
			if not f["gone"]:
				idle += int(f.get("idle", 0))
		var lines: Variant = Barge.treasury_lines(e)
		var afford: Variant = int(maxf(0.0, float(e["treasury"]) - float(lines["short"])) * 0.5 / maxf(1.0, float(wb2["wage"]) * 14.0))
		# barge part 4 section 1: "public works more when rich (a great work hires extra day labour)": over its full line
		# the treasury hires day labour beyond the idle with half of what it holds over the line (two weeks' wages);
		# the posts are day work in the labour market (Barge.labour_day), so the day wage feels them
		var great: Variant = int(maxf(0.0, float(e["treasury"]) - float(lines["full"])) * 0.5 / maxf(1.0, float(wb2["wage"]) * 14.0))
		wb2["cap"] = maxi(mini(idle + int(wb2["workers"]) + great, afford), 0)
	# Keep the small funded mint crew available. A full municipal chest does
	# not mean the world has enough coin; absent bars must still generate
	# input demand in mint_day rather than dismissing the entire crew.
	await _checkpoint("TownEcon.town_turn:985")
	if e.has("mint_biz"):
		var mbz: Dictionary = biz[int(e["mint_biz"])]
		mbz["cap"] = int(Barge.B()["coin"]["minters"])
	await _checkpoint("TownEcon.town_turn:988")
	await _town_econ_fund_public_services(e)
	# These capacity and real treasury transfers run after today's family
	# batches. Let idle civilians see their funded offers before the recount.
	await _checkpoint("TownEcon.town_turn:991")
	await _families_match_idle(e)
	await _checkpoint("TownEcon.town_turn:992")
	var wage_bill: Variant = 0.0
	await _checkpoint("TownEcon.town_turn:993")
	for b: Variant in biz:
		await _checkpoint("TownEcon.town_turn:loop:993")
		if TownEcon._town_funded(b) and not b.get("closed", false):
			wage_bill += float(b["workers"]) * float(b["wage"])
	await _checkpoint("TownEcon.town_turn:996")
	e["stats"]["town_wages"] = wage_bill
	# (the granary: barge part 4 section 2, daily: Barge.granary_day)
	# wealthy families (jewelry buyers); the poor's hunger (the gruel kitchen opens above 0.3)
	# and the counts the daily pass reads (idle grown-ups, children, the coin in purses: Barge.recount_week)
	await _checkpoint("TownEcon.town_turn:1000")
	var idle_n: Variant = 0; var kids_n: Variant = 0; var purses: Variant = 0.0
	await _checkpoint("TownEcon.town_turn:1001")
	for f: Variant in fams:
		await _checkpoint("TownEcon.town_turn:loop:1001")
		purses += float(f["purse"])
		if f["gone"] or f.has("estate"):
			continue
		idle_n += int(f.get("idle", 0))
		kids_n += int(f["kids"])
		Barge.klass(f)   # barge: the family's class follows its savings
	await _checkpoint("TownEcon.town_turn:1008")
	var households: Variant = Population.household_stats(e)
	await _checkpoint("TownEcon.town_turn:1009")
	e["rich"] = int(households["rich"])
	await _checkpoint("TownEcon.town_turn:1010")
	e["poor_hunger"] = float(households["poor_hungry"]) / maxf(1.0, float(households["poor"]))
	await _checkpoint("TownEcon.town_turn:1011")
	e["idle_n"] = idle_n
	await _checkpoint("TownEcon.town_turn:1012")
	e["kids_n"] = kids_n
	await _checkpoint("TownEcon.town_turn:1013")
	e["purses_n"] = purses
	# a new head if the old family is gone
	await _checkpoint("TownEcon.town_turn:1015")
	var hf: Dictionary = fams[int(e["head"]["fam"])]
	await _checkpoint("TownEcon.town_turn:1016")
	if hf.get("gone", false):
		var nh: Variant = Families.richest(e)
		var rr: Variant = RandomNumberGenerator.new(); rr.seed = hash([town["id"], day, "head"])
		var race: String = D["cultures"][e["culture"]]["race"]
		e["head"]["fam"] = nh
		e["head"]["name"] = Families.person_name(fams[nh], rr, race)
		fams[nh]["named"] = true
		TownEcon.town_hist(e, "%s of the %s family is the new %s." % [e["head"]["name"], fams[nh]["name"], e["head"]["title"]], float(day))
	# public works: the head spends a share of the treasury above its reserve on stone, wood and tools for
	# walls, roads and wells (bought at the market, used up) [ours]
	# barge: public works more when rich: a share of what the treasury holds above its full line
	await _checkpoint("TownEcon.town_turn:1027")
	var reserve: Variant = float(Barge.treasury_lines(e)["full"]) + float(e["stats"].get("town_wages", 0.0)) * 21.0
	await _checkpoint("TownEcon.town_turn:1028")
	var budget: Variant = (float(e["treasury"]) - reserve) * float(T.get("works_share", 0.2))
	await _checkpoint("TownEcon.town_turn:1029")
	e["stats"]["works"] = 0.0
	await _checkpoint("TownEcon.town_turn:1030")
	if budget > 200.0:
		var spent: Variant = 0.0
		for g: Variant in ["stone", "wood", "tools"]:
			await _checkpoint("TownEcon.town_turn:loop:1032")
			var p: Variant = float(e["price"][g])
			var q: Variant = mini(int(budget / 3.0 / p), int(e["stock"].get(g, 0)) / 4)
			if q <= 0:
				continue
			e["stock"][g] = int(e["stock"][g]) - q
			TownEcon.led(e, "used", g, q)
			e["req"][g] = float(e["req"].get(g, 0.0)) + float(q)
			spent += float(q) * p
		e["treasury"] = float(e["treasury"]) - spent
		mkt["till"] = float(mkt["till"]) + spent
		e["stats"]["works"] = spent
	await _checkpoint("TownEcon.town_turn:1044")
	SupplyOrders.ai_week(game, town, day)
	await _checkpoint("TownEcon.town_turn:1045")
	await _barge_release_surplus(game, town, e)
	# trade: send a caravan with the surplus where it is wanted
	await _checkpoint("TownEcon.town_turn:1047")
	await _town_econ_plan_trade(game, town, e, day)
	# reasons for the week's price moves, then the snapshot the arrows on the town screen compare against
	await _checkpoint("TownEcon.town_turn:1049")
	TownEcon.update_reasons(town, Calendar.season_index(float(day)))
	await _checkpoint("TownEcon.town_turn:1050")
	e["pweek"] = (e["price"] as Dictionary).duplicate()
	# the weekly hiring market: re-run the open-places list
	await _checkpoint("TownEcon.town_turn:1052")
	Businesses.rebuild_open(e)
	# the register against the map: people of this town whose unit is gone went home or died
	await _checkpoint("TownEcon.town_turn:1054")
	var live_for_sweep: Dictionary = await _persons_live_uids(game)
	await _checkpoint("TownEcon.town_turn:1055")
	await _persons_sweep_town(game, town, live_for_sweep)

## Native game/campaign/town_econ.gd:1077; only qualification, types, awaits and checkpoints added.
func _town_econ_fund_public_services(e: Dictionary) -> float:
	await _checkpoint("TownEcon.fund_public_services")
	await _checkpoint("TownEcon.fund_public_services:1078")
	var paid: Variant = 0.0
	await _checkpoint("TownEcon.fund_public_services:1079")
	for b: Variant in e["biz"]:
		await _checkpoint("TownEcon.fund_public_services:loop:1079")
		if not TownEcon._town_funded(b) or b.get("closed", false): continue
		var want: Variant = maxf(0.0, float(b.get("owed", 0.0))) + float(maxi(int(b["workers"]), int(b["cap"]))) * float(b["wage"]) * 14.0
		var gap: Variant = maxf(0.0, want - float(b["till"]))
		var self_paying: bool = String(b["type"]) == "mint" and Barge.mint_bars(e)
		if gap > 0.0 and (float(e["treasury"]) > 3.0 * gap or self_paying):
			var top: Variant = minf(gap, maxf(0.0, float(e["treasury"])))
			b["till"] = float(b["till"]) + top
			b["t_paid"] = float(b.get("t_paid", 0.0)) - top
			b["public_paid"] = float(b.get("public_paid", 0.0)) + top
			e["treasury"] = float(e["treasury"]) - top
			paid += top
	await _checkpoint("TownEcon.fund_public_services:1091")
	return paid

## Native game/campaign/town_econ.gd:1297; only qualification, types, awaits and checkpoints added.
func _town_econ_sell_land(e: Dictionary, D: Dictionary, day: float) -> void:
	await _checkpoint("TownEcon._sell_land")
	await _checkpoint("TownEcon._sell_land:1298")
	var est: Dictionary = e["fams"][0]
	await _checkpoint("TownEcon._sell_land:1299")
	if (est["land"] as Dictionary).is_empty() and (est["herd"] as Dictionary).is_empty():
		return
	await _checkpoint("TownEcon._sell_land:1301")
	var has_est_land: bool = not (est["herd"] as Dictionary).is_empty()
	await _checkpoint("TownEcon._sell_land:1302")
	if not has_est_land:
		var lm: Dictionary = e.get("land_market", {})
		for crop: Variant in est["land"]:
			await _checkpoint("TownEcon._sell_land:loop:1304")
			if int(est["land"][crop]) > int(lm.get(crop, 0)):
				has_est_land = true
				break
		if not has_est_land:
			return
	await _checkpoint("TownEcon._sell_land:1310")
	var L: Dictionary = D["land"]
	await _checkpoint("TownEcon._sell_land:1311")
	var buyers: Variant = []
	await _checkpoint("TownEcon._sell_land:1312")
	for f: Variant in e["fams"]:
		await _checkpoint("TownEcon._sell_land:loop:1312")
		if f.get("gone", false) or f.get("estate", false) or Population.is_cohort(f):
			continue
		if Families.keeps_stale(e, f): continue
		var spare: Variant = TownEcon._property_hands(e, f) - Families.need_hands(f, e)
		if float(f["purse"]) > float(L["acre_price"]) + 40.0 * TownEcon.COIN and spare >= 0.5 and float(f.get("debt", 0.0)) <= 0.0:
			buyers.append(f)
	await _checkpoint("TownEcon._sell_land:1319")
	buyers.sort_custom(func(a: Variant, b: Variant) -> bool: return float(a["purse"]) > float(b["purse"]))
	await _checkpoint("TownEcon._sell_land:1320")
	for f: Variant in buyers.slice(0, 5):
		await _checkpoint("TownEcon._sell_land:loop:1320")
		for crop: Variant in est["land"].keys():
			await _checkpoint("TownEcon._sell_land:loop:1321")
			var est_avail: Variant = int(est["land"][crop]) - int(e.get("land_market", {}).get(crop, 0))
			if est_avail <= 0: continue
			# Lazily quote after the native buyer prelude; settlement changes coin only.
			var seller: Dictionary = {"buyers": {}}
			var want_n: int = TownEcon._purchase_acres(e, est, f, String(crop), est_avail, seller)
			if want_n <= 0: continue
			Families.settle(e, f)
			var short: Variant = float(want_n) * float(L["acre_price"]) - (float(f["purse"]) - 40.0 * TownEcon.COIN)
			var credit: Variant = Loans.quote(e, f, ceilf(short)) if short > 0.0 and float(f.get("debt", 0.0)) <= 0.0 else 0.0
			var afford: Variant = int((float(f["purse"]) + credit - 40.0 * TownEcon.COIN) / float(L["acre_price"]))
			var n: int = want_n if afford >= want_n else TownEcon._purchase_acres(e, est, f, String(crop), afford, seller)
			if n <= 0:
				continue
			var cost: Variant = float(n) * float(L["acre_price"])
			var gap: Variant = maxf(0.0, cost - (float(f["purse"]) - 40.0 * TownEcon.COIN))
			if gap > 0.0: Loans.lend(e, f, ceilf(gap), "land", day)
			if float(f["purse"]) - cost < 40.0 * TownEcon.COIN: continue
			Families.move_land(e, est, f, crop, n)
			f["purse"] = float(f["purse"]) - cost
			e["treasury"] = float(e["treasury"]) + cost
			Families.add_hist(f, "Bought %d acres of %s from the town." % [n, TownEcon.variety_word(e, crop)], day)
			Families.reassign(e, f)
		for a: Variant in est["herd"].keys():
			await _checkpoint("TownEcon._sell_land:loop:1344")
			var want_h: Variant = TownEcon._purchase_heads(e, est, f, String(a), int(est["herd"][a]))
			if want_h <= 0: continue
			Families.settle(e, f)
			var afford2: Variant = int((float(f["purse"]) - 40.0 * TownEcon.COIN) / float(L["head_price"]))
			var n2: Variant = want_h if afford2 >= want_h else TownEcon._purchase_heads(e, est, f, String(a), afford2)
			if n2 <= 0:
				continue
			Families.move_herd(e, est, f, a, n2)
			f["purse"] = float(f["purse"]) - float(n2) * float(L["head_price"])
			e["treasury"] = float(e["treasury"]) + float(n2) * float(L["head_price"])
			Families.reassign(e, f)

## Native game/campaign/town_econ.gd:1357; only qualification, types, awaits and checkpoints added.
func _town_econ_sell_businesses(e: Dictionary, day: float) -> void:
	await _checkpoint("TownEcon._sell_businesses")
	await _checkpoint("TownEcon._sell_businesses:1358")
	for b: Variant in e["biz"]:
		await _checkpoint("TownEcon._sell_businesses:loop:1358")
		if not b.get("for_sale", false) or b.get("closed", false) or b["type"] == "farm":
			continue
		var price: Variant = (80.0 + float(b["cap"]) * 25.0) * TownEcon.COIN
		var best: Dictionary = {}
		for f: Variant in e["fams"]:
			await _checkpoint("TownEcon._sell_businesses:loop:1363")
			if f.get("gone", false) or f.get("estate", false) or Population.is_cohort(f):
				continue
			if Families.adults(f) - Families.serving(f) <= (f.get("keeps", []) as Array).size():
				continue   # v0.014: a buyer needs a grown-up free to keep it
			if float(f["purse"]) > price + 40.0 * TownEcon.COIN and (best.is_empty() or float(f["purse"]) > float(best["purse"])):
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

## Native game/campaign/town_econ.gd:1382; only qualification, types, awaits and checkpoints added.
func _town_econ_plan_trade(game: Variant, town: Dictionary, e: Dictionary, day: int) -> void:
	await _checkpoint("TownEcon._plan_trade")
	await _checkpoint("TownEcon._plan_trade:1383")
	var w: Dictionary = game.world
	await _checkpoint("TownEcon._plan_trade:1384")
	if float(e["treasury"]) < 150.0 * TownEcon.COIN or Caravans.count(w) >= Caravans.max_caravans(w):
		return
	await _checkpoint("TownEcon._plan_trade:1386")
	for wid: Variant in w["warbands"]:
		await _checkpoint("TownEcon._plan_trade:loop:1386")
		var wb: Dictionary = w["warbands"][wid]
		if wb["kind"] == "caravan" and wb.get("origin", "") == town["id"]:
			return
	await _checkpoint("TownEcon._plan_trade:1390")
	for job: Variant in w.get("work", []):
		await _checkpoint("TownEcon._plan_trade:loop:1390")
		if job[0] == "caravan" and job[1] == town["id"]:
			return
	await _checkpoint("TownEcon._plan_trade:1393")
	var route_previous: Dictionary = Caravans.begin_route_batch(w, String(town["id"]))
	await _checkpoint("TownEcon._plan_trade:1394")
	var best: Variant = ""; var bv: Variant = 0.0
	await _checkpoint("TownEcon._plan_trade:1395")
	for l: Variant in Caravans.trade_partners(w, town):
		await _checkpoint("TownEcon._plan_trade:loop:1395")
		var o: Dictionary = w["towns"].get(l["id"], {})
		if not TownEcon.has_econ(o):
			continue
		var v: Variant = Caravans.trade_value(town, o, w)
		if v > bv:
			bv = v; best = l["id"]
	await _checkpoint("TownEcon._plan_trade:1402")
	Caravans.finish_route_batch(route_previous)
	await _checkpoint("TownEcon._plan_trade:1403")
	if best != "" and bv > 0.0:
		(w["work"] as Array).append(["caravan", town["id"], best])

## Native game/campaign/town_econ.gd:1410; only qualification, types, awaits and checkpoints added.
func _town_econ_faction_turn(game: Variant, day: int) -> void:
	await _checkpoint("TownEcon.faction_turn")
	await _checkpoint("TownEcon.faction_turn:1411")
	var w: Dictionary = game.world
	await _checkpoint("TownEcon.faction_turn:1412")
	var D: Variant = TownEcon.data()
	await _checkpoint("TownEcon.faction_turn:1413")
	var T: Dictionary = D["tax"]
	await _checkpoint("TownEcon.faction_turn:1414")
	var stats: Variant = {}
	# This synchronous turn changes town cash/jobs/research, never field-unit
	# membership, rank, kit or skills. Reuse each native ordered bill sum.
	await _checkpoint("TownEcon.faction_turn:1417")
	var army_bills: Dictionary = {}
	await _checkpoint("TownEcon.faction_turn:1418")
	for fid: Variant in w.get("factions", {}):
		await _checkpoint("TownEcon.faction_turn:loop:1418")
		var fac: Dictionary = w["factions"][fid]
		if not fac.has("treasury"):
			fac["treasury"] = 0.0
		var food: Variant = 0.0; var metal: Variant = 0.0; var n: Variant = 0
		# economy spec 2: the army levy. The realm asks its towns for what its field army will cost over the next
		# two weeks beyond what the war chest holds, by town size; each town pays what it can above a small
		# reserve (100 x (size + 1)). Short towns leave the army short: unpaid men walk home.
		var army_bill: float = Army.bill(game, fid)
		army_bills[fid] = army_bill
		var levy: float = maxf(0.0, army_bill * 14.0 - float(fac["treasury"]))
		if levy > 0.0:
			var wsum: Variant = 0.0
			for tid: Variant in fac.get("towns", []):
				await _checkpoint("TownEcon.faction_turn:loop:1431")
				if TownEcon.has_econ(w["towns"].get(tid, {})):
					wsum += float(int(w["towns"][tid]["size"]) + 1)
			for tid: Variant in fac.get("towns", []):
				await _checkpoint("TownEcon.faction_turn:loop:1434")
				var tl: Dictionary = w["towns"].get(tid, {})
				if not TownEcon.has_econ(tl) or wsum <= 0.0:
					continue
				var el: Dictionary = tl["econ"]
				var ask: Variant = levy * float(int(tl["size"]) + 1) / wsum
				var can: Variant = minf(ask, maxf(0.0, float(el["treasury"]) - float(Barge.treasury_lines(el)["short"]) * 0.5))
				el["treasury"] = float(el["treasury"]) - can
				fac["treasury"] = float(fac["treasury"]) + can
				el["stats"]["army_levy"] = can
		for tid: Variant in fac.get("towns", []):
			await _checkpoint("TownEcon.faction_turn:loop:1444")
			var t: Dictionary = w["towns"].get(tid, {})
			if not TownEcon.has_econ(t):
				continue
			var e: Dictionary = t["econ"]
			n += 1
			# tribute to the realm: a share of what the treasury holds above its short line (barge part 4 section 1)
			var reserve: Variant = float(Barge.treasury_lines(e)["short"]) + float(e["stats"].get("town_wages", 0.0)) * 21.0
			var over: Variant = float(e["treasury"]) - reserve
			e["stats"]["to_faction"] = 0.0
			if over > 0.0:
				var send: Variant = over * float(T["faction_share"])
				e["treasury"] = float(e["treasury"]) - send
				fac["treasury"] = float(fac["treasury"]) + send
				e["stats"]["to_faction"] = send
			e["stats"]["to_faction_month"] = float(e["stats"].get("to_faction_month", 0.0)) * 0.75 + float(e["stats"]["to_faction"])
			food += TownEcon.days_food(t)
			var st: Dictionary = e["stock"]
			metal += float(st.get("copper_bars", 0) + st.get("tin_bars", 0) + st.get("bronze_bars", 0)) + float(st.get("copper_ore", 0) + st.get("tin_ore", 0)) * 0.5
		if n > 0:
			stats[fid] = {"food": food / n, "metal": metal / n, "treasury": float(fac["treasury"])}
			fac["econ"] = stats[fid]
	await _checkpoint("TownEcon.faction_turn:1466")
	await _academy_faction_turn(game, float(day), army_bills)   # v0.012: each realm funds its research house (budget, staff, its lead)
	# the realm keeps a month of its army's pay (economy spec 2); a share of what is above that flows back to its
	# poorest towns [ours]
	await _checkpoint("TownEcon.faction_turn:1469")
	for fid: Variant in w.get("factions", {}):
		await _checkpoint("TownEcon.faction_turn:loop:1469")
		var fac: Dictionary = w["factions"][fid]
		var keep: float = float(army_bills[fid]) * 30.0
		var give: Variant = maxf(0.0, float(fac.get("treasury", 0.0)) - keep) * float(T.get("faction_return", 0.25))
		var poor: Variant = []
		for tid: Variant in fac.get("towns", []):
			await _checkpoint("TownEcon.faction_turn:loop:1474")
			var t: Dictionary = w["towns"].get(tid, {})
			if TownEcon.has_econ(t):
				poor.append(t)
		if poor.is_empty() or give < 1.0:
			continue
		poor.sort_custom(func(a: Variant, b: Variant) -> bool: return float(a["econ"]["treasury"]) < float(b["econ"]["treasury"]))
		var half: Variant = poor.slice(0, maxi(1, poor.size() / 2))
		for t: Variant in half:
			await _checkpoint("TownEcon.faction_turn:loop:1482")
			t["econ"]["treasury"] = float(t["econ"]["treasury"]) + give / half.size()
		fac["treasury"] = float(fac["treasury"]) - give
	await _checkpoint("TownEcon.faction_turn:1485")
	TownEcon._diplomacy_feed(w, stats)

## Native game/campaign/town_sanitation.gd:63; only qualification, types, awaits and checkpoints added.
func _town_sanitation_weekly(e: Dictionary, day: float) -> void:
	await _checkpoint("TownSanitation.weekly")
	await _checkpoint("TownSanitation.weekly:64")
	var s: Variant = TownSanitation.book(e)
	# Preserve the service actually consumed by this completed period separately
	# from wages settled after this close. The queued town turn supplies its day.
	await _checkpoint("TownSanitation.weekly:67")
	s["completed_paid_days"] = (s["paid_days"] as Dictionary).duplicate()
	await _checkpoint("TownSanitation.weekly:68")
	s["closed_day"] = day
	await _checkpoint("TownSanitation.weekly:69")
	var pop: Variant = maxf(0, float(e["pop"]) - float(e.get("away_n", 0)))
	await _checkpoint("TownSanitation.weekly:70")
	var start: Variant = float(s["filth_kg"])
	await _checkpoint("TownSanitation.weekly:71")
	var people: Variant = pop * (float(TownSanitation.D()["waste_kg_day"]) + float(TownSanitation.D()["refuse_kg_day"])) * 7
	await _checkpoint("TownSanitation.weekly:72")
	var animals: Variant = 0.0
	# Household poultry stay in town; grazing animals' dung is already accounted for by Herds._manure.
	await _checkpoint("TownSanitation.weekly:74")
	for h: Variant in Herds.herds(e).values():
		await _checkpoint("TownSanitation.weekly:loop:74")
		if String(h["k"]) == "hens": animals += Herds.ge(h) * float(Herds.A()["kinds"]["hens"]["manure"]) * 1000 * 7 / EconGen.YEAR_DAYS
	await _checkpoint("TownSanitation.weekly:76")
	var incoming: Variant = maxf(0, people + animals + float(s["rotting_kg"]) + float(s["trade_kg"]) - float(s.get("scraps_reused_kg", 0)))
	await _checkpoint("TownSanitation.weekly:77")
	var filth: Variant = start + incoming
	await _checkpoint("TownSanitation.weekly:78")
	var urine_in: Variant = pop * float(TownSanitation.D()["urine_l_day"]) * 7
	await _checkpoint("TownSanitation.weekly:79")
	var urine: Variant = float(s["urine_litres"]) + urine_in
	await _checkpoint("TownSanitation.weekly:80")
	var swept: Variant = minf(filth, TownSanitation.paid_days(e, "street_sweeper") * float(TownSanitation.D()["sweep_kg_day"]))
	await _checkpoint("TownSanitation.weekly:81")
	filth -= swept
	await _checkpoint("TownSanitation.weekly:82")
	var night: Variant = minf(urine, TownSanitation.paid_days(e, "night_soil_man") * float(TownSanitation.D()["night_soil_l_day"]))
	await _checkpoint("TownSanitation.weekly:83")
	urine -= night
	# The existing field-manure book receives only the recovered solids; never create a second fertiliser good.
	await _checkpoint("TownSanitation.weekly:85")
	var recovered: Variant = 0.0
	await _checkpoint("TownSanitation.weekly:86")
	var offered: Variant = swept
	await _checkpoint("TownSanitation.weekly:87")
	var acres_total: Variant = maxf(1, float(e.get("land", {}).get("grain", 0)))
	await _checkpoint("TownSanitation.weekly:88")
	var tonnes_acre: Variant = float(Herds.A()["manure_acre"])
	await _checkpoint("TownSanitation.weekly:89")
	var price_kg: Variant = float(TownEcon.data()["land"]["yield"]["grain"]) * float(Herds.A()["manure_yield"]) * float(e["price"].get("grain", 1)) / maxf(1, tonnes_acre * 1000)
	# Field holders buy collected dung out of their purses; its price is the additional crop value per kg.
	await _checkpoint("TownSanitation.weekly:91")
	for f: Variant in e["fams"]:
		await _checkpoint("TownSanitation.weekly:loop:91")
		if f.get("gone", false) or f.get("estate", false): continue
		var acreage: Variant = float(f["land"].get("grain", 0))
		var amount: Variant = minf(swept * acreage / acres_total, acreage * tonnes_acre * 1000 * 7 / EconGen.YEAR_DAYS)
		amount = minf(amount, maxf(0, float(f["purse"])) / maxf(0.001, price_kg))
		var cost: Variant = amount * price_kg
		f["purse"] = float(f["purse"]) - cost; e["treasury"] = float(e["treasury"]) + cost
		recovered += amount; offered -= amount
	await _checkpoint("TownSanitation.weekly:99")
	if e.has("hd"): e["hd"]["human_manure_week"] = recovered
	await _checkpoint("TownSanitation.weekly:100")
	var river: Variant = 0.0
	await _checkpoint("TownSanitation.weekly:101")
	if e.get("terrain", {}).get("water", false):
		river = urine; urine = 0 # liquid drains to the actual watercourse; it remains a foul-water exposure
	await _checkpoint("TownSanitation.weekly:103")
	var season: Variant = Calendar.season_index(day)
	await _checkpoint("TownSanitation.weekly:104")
	var decay: Variant = minf(filth, pop * float(TownSanitation.D()["decay_kg_person_day"][season]) * 7)
	await _checkpoint("TownSanitation.weekly:105")
	filth -= decay
	await _checkpoint("TownSanitation.weekly:106")
	s["filth_kg"] = filth; s["urine_litres"] = urine
	await _checkpoint("TownSanitation.weekly:107")
	s["incoming_kg"] = incoming; s["people_kg"] = people; s["animal_kg"] = animals
	await _checkpoint("TownSanitation.weekly:108")
	s["swept_kg"] = swept; s["farm_manure_kg"] = recovered; s["decayed_kg"] = decay
	await _checkpoint("TownSanitation.weekly:109")
	s["urine_in_l"] = urine_in; s["night_soil_l"] = night; s["river_l"] = river
	await _checkpoint("TownSanitation.weekly:110")
	s["change_kg"] = filth - start
	await _checkpoint("TownSanitation.weekly:111")
	s["cleaners"] = int(ceil(TownSanitation.paid_days(e, "street_sweeper") / 7))
	await _checkpoint("TownSanitation.weekly:112")
	var kg: Variant = float(Herds.A()["kg_per_meal"])
	await _checkpoint("TownSanitation.weekly:113")
	var food: Variant = float(TownSanitation.reachable_meals(e)) * kg
	await _checkpoint("TownSanitation.weekly:114")
	var capacity: Variant = int(floor(food / (float(TownSanitation.D()["rat_grain_kg_day"]) * 7)))
	await _checkpoint("TownSanitation.weekly:115")
	var rats: Variant = int(s["rats"])
	await _checkpoint("TownSanitation.weekly:116")
	var caught: Variant = mini(rats, int(floor(TownSanitation.paid_days(e, "rat_catcher") * float(TownSanitation.D()["rats_caught_day"]))))
	await _checkpoint("TownSanitation.weekly:117")
	rats -= caught
	# Breeding pairs require both reachable food and actual nesting refuse. Winter permits fewer litters.
	await _checkpoint("TownSanitation.weekly:119")
	var nests: Variant = int(floor(filth / float(TownSanitation.D()["nest_kg_pair"])))
	await _checkpoint("TownSanitation.weekly:120")
	var pairs: Variant = mini(rats / 2, nests)
	await _checkpoint("TownSanitation.weekly:121")
	var births: Variant = int(floor(float(pairs) * float(TownSanitation.D()["litters_week"][season]) * float(TownSanitation.D()["litter_size"])))
	await _checkpoint("TownSanitation.weekly:122")
	var before_starve: Variant = rats + births
	await _checkpoint("TownSanitation.weekly:123")
	rats = mini(before_starve, capacity)
	await _checkpoint("TownSanitation.weekly:124")
	var grain_kg: Variant = rats * float(TownSanitation.D()["rat_grain_kg_day"]) * 7 + float(s["rat_carry"])
	await _checkpoint("TownSanitation.weekly:125")
	var meals: Variant = mini(TownSanitation.reachable_meals(e), int(floor(grain_kg / kg)))
	await _checkpoint("TownSanitation.weekly:126")
	s["rat_carry"] = grain_kg - meals * kg
	await _checkpoint("TownSanitation.weekly:127")
	var left: Variant = meals
	await _checkpoint("TownSanitation.weekly:128")
	for holder: Variant in ["barn", "stock", "granary", "hh"]:
		await _checkpoint("TownSanitation.weekly:loop:128")
		var have: Variant = int(e.get("granary", 0)) if holder == "granary" else int(e[holder].get("grain", 0))
		var n: Variant = mini(left, have)
		if holder == "granary": e["granary"] = have - n
		elif holder == "barn": HarvestClaims.lose(e, "grain", n)
		else: e[holder]["grain"] = have - n
		if holder == "hh" and n > 0:
			for f: Variant in e["fams"]:
				await _checkpoint("TownSanitation.weekly:loop:135")
				if f.get("gone", false) or f.get("estate", false): continue
				var rate: Variant = float(Families.daily_rates(e, f)["food"])
				f["store"]["food"] = maxf(0, float(f["store"]["food"]) - float(n) / maxf(1, pop) / maxf(0.01, rate) * Families.people(f))
		left -= n
	await _checkpoint("TownSanitation.weekly:140")
	TownEcon.led(e, "spoil", "grain", meals - left)
	await _checkpoint("TownSanitation.weekly:141")
	s["rats"] = rats; s["food_capacity"] = capacity; s["caught"] = caught; s["births"] = births
	await _checkpoint("TownSanitation.weekly:142")
	s["starved"] = before_starve - rats; s["grain_eaten_kg"] = (meals - left) * kg
	await _checkpoint("TownSanitation.weekly:143")
	s["hygiene"] = (filth + urine + river) / maxf(1, pop)
	await _checkpoint("TownSanitation.weekly:144")
	s["rats_per_person"] = float(rats) / maxf(1, pop)
	await _checkpoint("TownSanitation.weekly:145")
	s["rotting_kg"] = 0.0; s["trade_kg"] = 0.0; s["scraps_reused_kg"] = 0.0; s["paid_days"] = {}
	await _checkpoint("TownSanitation.weekly:146")
	Sickness.book(e)["tf"] = {} # risk changes feed the existing weekly disease sampler

## Native game/campaign/town_housing.gd:46; only qualification, types, awaits and checkpoints added.
func _town_housing_weekly(e: Dictionary, day: float) -> void:
	await _checkpoint("TownHousing.weekly")
	await _checkpoint("TownHousing.weekly:47")
	var P: Dictionary = e.get("plots", {})
	await _checkpoint("TownHousing.weekly:48")
	if P.is_empty(): return
	await _checkpoint("TownHousing.weekly:49")
	var wanted: Variant = 0
	await _checkpoint("TownHousing.weekly:50")
	for f: Variant in e["fams"]:
		await _checkpoint("TownHousing.weekly:loop:50")
		if f.has("lodging") and (f.get("gone", false) or int(f["homes"]) <= 0): TownHousing.leave(e, f, day)
		if Shelter.homeless(f): wanted += TownHousing.room_need(f)
	# As households grow or shrink, room claims stay physical and share the available vacancy.
	await _checkpoint("TownHousing.weekly:54")
	for f: Variant in e["fams"]:
		await _checkpoint("TownHousing.weekly:loop:54")
		if not f.has("lodging") or f.get("gone", false): continue
		var h: Dictionary = TownHousing.rows(e)[int(f["lodging"])]
		var need: Variant = TownHousing.room_need(f)
		if need <= int(f["lodging_rooms"]) + TownHousing.free_rooms(e, h): f["lodging_rooms"] = need
	await _checkpoint("TownHousing.weekly:59")
	var free: Variant = 0
	await _checkpoint("TownHousing.weekly:60")
	for h: Variant in TownHousing.rows(e):
		await _checkpoint("TownHousing.weekly:loop:60")
		var owner: Variant = int(h["owner"])
		if owner >= e["fams"].size() or e["fams"][owner].get("gone", false):
			h["owner"] = 0; P["own"][int(h["plot"])] = 0
			for f: Variant in e["fams"]:
				await _checkpoint("TownHousing.weekly:loop:64")
				if int(f.get("lodging", -1)) == int(h["id"]): f["landlord"] = 0
		free += TownHousing.free_rooms(e, h)
	await _checkpoint("TownHousing.weekly:67")
	if wanted > free:
		var lot: Variant = -1
		for i: Variant in Plots.count(P):
			await _checkpoint("TownHousing.weekly:loop:69")
			if int(P["use"][i]) == Plots.LOT and int(P["ac"][i]) >= 5: lot = i; break
		if lot >= 0:
			var price: Variant = 2 * float(e["price"].get("home", 200))
			var land_price: Variant = 5 * float(TownEcon.data()["land"]["acre_price"]) * Barge.pl(e)
			var lord: Dictionary = {}
			for f: Variant in e["fams"]:
				await _checkpoint("TownHousing.weekly:loop:75")
				if f.get("gone", false) or f.get("estate", false) or float(f["purse"]) < price + land_price + float(Families.daily_rates(e, f)["food"]) * float(e["price"].get("grain", 1)) * 14: continue
				if lord.is_empty() or float(f["purse"]) > float(lord["purse"]): lord = f
			if not lord.is_empty():
				e["req"]["home"] = float(e["req"].get("home", 0)) + 2.0 / 7
				if int(e["stock"].get("home", 0)) >= 2:
					TownEcon.pay_market(e, lord, price)
					lord["purse"] = float(lord["purse"]) - land_price; e["treasury"] = float(e["treasury"]) + land_price
					e["stock"]["home"] = int(e["stock"]["home"]) - 2; TownEcon.led(e, "used", "home", 2)
					var h: Variant = {"id": TownHousing.rows(e).size(), "plot": lot, "owner": lord["id"], "rooms": TownHousing.ROOMS, "buildings": 2, "name": TownHousing.NAMES.get(String(e["culture"]), "lodging houses")}
					TownHousing.rows(e).append(h); P["use"][lot] = Plots.HOME; P["own"][lot] = lord["id"]
					if not P.has("lodging_plots"): P["lodging_plots"] = []
					P["lodging_plots"].append(lot)
					Plots._hist(P, lot, day, "Two %s built here: %d rooms." % [h["name"], TownHousing.ROOMS]); Plots._dirty(P)
	await _checkpoint("TownHousing.weekly:89")
	for f: Variant in e["fams"]:
		await _checkpoint("TownHousing.weekly:loop:89")
		if Shelter.homeless(f): TownHousing.try_rent(e, f, day)

## Native game/campaign/shelter.gd:316; only qualification, types, awaits and checkpoints added.
func _shelter_weekly(game: Variant, town: Dictionary, e: Dictionary) -> void:
	await _checkpoint("Shelter.weekly")
	await _checkpoint("Shelter.weekly:317")
	var sn: Variant = 0; var bn: Variant = 0; var away: Variant = 0
	await _checkpoint("Shelter.weekly:318")
	var used: Variant = {}
	await _checkpoint("Shelter.weekly:319")
	for f: Variant in e["fams"]:
		await _checkpoint("Shelter.weekly:loop:319")
		if f.get("gone", false):
			continue
		if not f.get("child_cj", {}).is_empty(): f["child_work_changed"] = true
		var sv: Dictionary = f.get("serve", {})
		for k: Variant in sv:
			await _checkpoint("Shelter.weekly:loop:324")
			if k in ["army", "bandit", "deserter"]:   # soldiers and outlaws eat out of their force's stores, not at home
				away += int(sv[k])
		if f.get("shel", false):
			sn += Families.people(f)
			if f.get("broth", false):
				bn += Families.people(f)
		f.erase("child_cj") # Recheck age, health and funded places each week. Earned pay remains due.
		for j: Variant in f.get("cj", {}):
			await _checkpoint("Shelter.weekly:loop:332")
			used[j] = float(used.get(j, 0)) + int(f["cj"][j])
	await _checkpoint("Shelter.weekly:334")
	e["shel_n"] = sn
	await _checkpoint("Shelter.weekly:335")
	e["broth_n"] = bn
	await _checkpoint("Shelter.weekly:336")
	e["away_n"] = away
	await _checkpoint("Shelter.weekly:337")
	e["cjused"] = used
	await _checkpoint("Shelter.weekly:338")
	await _shelter_casual_caps(game, town, e)
	await _checkpoint("Shelter.weekly:339")
	await _shelter_assign_child_cleanup(e, float(game.day) if game != null else 0.0)

## Native game/campaign/shelter.gd:152; only qualification, types, awaits and checkpoints added.
func _shelter_casual_caps(game: Variant, town: Dictionary, e: Dictionary) -> void:
	await _checkpoint("Shelter.casual_caps")
	await _checkpoint("Shelter.casual_caps:153")
	var cj: Dictionary = TownEcon.data()["casual_jobs"]
	await _checkpoint("Shelter.casual_caps:154")
	var caps: Variant = {}
	await _checkpoint("Shelter.casual_caps:155")
	var car: Variant = 0
	await _checkpoint("Shelter.casual_caps:156")
	if game != null and game.world.has("warbands"):
		for wid: Variant in game.world["warbands"]:
			await _checkpoint("Shelter.casual_caps:loop:157")
			var wb: Dictionary = game.world["warbands"][wid]
			if wb.get("kind", "") == "caravan" and wb.get("origin", "") == town.get("id", ""):
				car += 1
	await _checkpoint("Shelter.casual_caps:161")
	for j: Variant in cj:
		await _checkpoint("Shelter.casual_caps:loop:161")
		var per: Variant = 0.0
		match String(cj[j]["per"]):
			"homes": per = float(e["homes"])
			"pop": per = float(e["pop"])
			"granary": per = float(e["granary"])
			"caravans": per = float(car)
		caps[j] = int(per * float(cj[j]["k"]))
		if String(cj[j]["per"]) == "granary":
			caps[j] = mini(caps[j], int(float(e["pop"]) * 0.005))   # [ours] a granary needs only so many rat catchers
	await _checkpoint("Shelter.casual_caps:171")
	TownSanitation.caps(e, caps)
	await _checkpoint("Shelter.casual_caps:172")
	e["cjcap"] = caps
	await _checkpoint("Shelter.casual_caps:173")
	if not e.has("cjused"):
		e["cjused"] = {}

## Native game/campaign/shelter.gd:419; only qualification, types, awaits and checkpoints added.
func _shelter_assign_child_cleanup(e: Dictionary, day: float) -> void:
	await _checkpoint("Shelter.assign_child_cleanup")
	await _checkpoint("Shelter.assign_child_cleanup:420")
	var share: Variant = float(Barge.B()["labour"]["kid_share"])
	await _checkpoint("Shelter.assign_child_cleanup:421")
	var jobs: Variant = ["street_sweeper", "rat_catcher", "night_soil_man"]
	await _checkpoint("Shelter.assign_child_cleanup:422")
	jobs.sort_custom(func(a: Variant, b: Variant) -> bool: return Barge.casual_wage(e, a) > Barge.casual_wage(e, b))
	await _checkpoint("Shelter.assign_child_cleanup:423")
	var funds_previous: Dictionary = TownSanitation.begin_customer_batch(e)
	await _checkpoint("Shelter.assign_child_cleanup:424")
	for f: Variant in e["fams"]:
		await _checkpoint("Shelter.assign_child_cleanup:loop:424")
		if f.get("gone", false) or f.get("estate", false): continue
		for p: Variant in Persons.kp(f):
			await _checkpoint("Shelter.assign_child_cleanup:loop:426")
			if not Shelter.cleanup_child_eligible(e, p, day, f): continue
			var c: Variant = Sickness.case_of(f, int(p[0]))
			if not c.is_empty() and int(c[Sickness.C_BED]) == 1 and Sickness.sick_phase(c, day): continue
			for j: Variant in jobs:
				await _checkpoint("Shelter.assign_child_cleanup:loop:430")
				var used: Variant = float(e["cjused"].get(j, 0))
				if float(e["cjcap"].get(j, 0)) - used + 0.00001 < share: continue
				var payer: Variant = String(TownEcon.data()["casual_jobs"][j]["payer"])
				var fund: Variant = TownSanitation.customer_funds(e) if payer == "customers" else float(e["treasury"])
				if fund + 0.00001 < Barge.casual_wage(e, j) * 7 * (used + share): continue
				if not f.has("child_cj"): f["child_cj"] = {}
				f["child_cj"][str(int(p[0]))] = j
				f["child_work_changed"] = true
				e["cjused"][j] = used + share
				break
	await _checkpoint("Shelter.assign_child_cleanup:441")
	TownSanitation.finish_customer_batch(funds_previous)
	# Refresh the farm's actual output fraction as well as its helper count.
	await _checkpoint("Shelter.assign_child_cleanup:443")
	for f: Variant in e["fams"]:
		await _checkpoint("Shelter.assign_child_cleanup:loop:443")
		if f.get("child_work_changed", false):
			Families.reassign(e, f)
			f.erase("child_work_changed")

## Native offer order and checkpoints; household policy is shared with Families.match_idle.
func _families_match_idle(e: Dictionary) -> void:
	await _checkpoint("Families.match_idle")
	await _checkpoint("Families.match_idle:1124")
	var funded: Variant = false
	await _checkpoint("Families.match_idle:1125")
	for b: Variant in e["biz"]:
		await _checkpoint("Families.match_idle:loop:1125")
		if Businesses.takeable(b, e) > 0:
			funded = true; break
	# Paid casual work uses the same idle adults even when every regular shop
	# is full. Keep the existing funding and fractional-shift capacity rules.
	await _checkpoint("Families.match_idle:1130")
	if not funded:
		for job: Variant in e.get("cjcap", {}):
			await _checkpoint("Families.match_idle:loop:1131")
			if Families._available_casual(e, String(job)) > 0:
				funded = true; break
	await _checkpoint("Families.match_idle:1134")
	if not funded: return
	await _checkpoint("Families.match_idle:1135")
	for f: Variant in e["fams"]:
		await _checkpoint("Families.match_idle:loop:1135")
		if Families.match_idle_household(e, f):
			return

## Native game/campaign/businesses.gd:800; only qualification, types, awaits and checkpoints added.
func _businesses_bid_day(e: Dictionary) -> void:
	await _checkpoint("Businesses.bid_day")
	await _checkpoint("Businesses.bid_day:801")
	var day: int = int(e.get("day", 0))
	await _checkpoint("Businesses.bid_day:802")
	for b: Variant in e["biz"]:
		await _checkpoint("Businesses.bid_day:loop:802")
		if b.get("closed", false): continue
		b["wage"] = EconomyRules.wage_limit(e, b, float(b["wage"]))
		if day - int(b.get("wage_review_day", day - 7)) < 7: continue
		b["wage_review_day"] = day
		var cap: int = int(b["cap"])
		var workers: int = int(b["workers"])
		var wage: float = float(b["wage"])
		if workers < cap:
			var gap: float = float(cap - workers) / float(maxi(1, cap))
			wage *= 1.08 + 0.08 * gap
			if String(b["type"]) in ["farm", "estate"]:
				var fid: int = int(b.get("public_property", maxi(0, int(b["owner"]))))
				var value: float = EconomyRules.farm_hand_value(e, e["fams"][fid])
				b["revenue_hand"] = value
				# Dear crops can win hands back immediately within the adult band.
				# Low crop value must never force adult pay below that band.
				wage = maxf(wage, value * 0.9)
		elif not EconomyRules.skilled_work(b) and cap > 0:
			if workers > cap:
				wage *= 0.94
			elif day - int(b.get("staff_left_day", day - 7)) >= 7:
				wage *= 0.97
		b["wage"] = EconomyRules.wage_limit(e, b, wage)
		if String(b["type"]) == "farm" and int(b["owner"]) >= 0:
			var owner: Dictionary = e["fams"][int(b["owner"])]
			var funded: float = Businesses.fund_farm(owner, b, e)
			owner["farm_funding_pending"] = float(owner.get("farm_funding_pending", 0.0)) + funded
	await _checkpoint("Businesses.bid_day:830")
	Businesses.refresh_hiring(e)

## Native game/campaign/persons.gd:1060; only qualification, types, awaits and checkpoints added.
func _persons_live_uids(game: Variant) -> Dictionary:
	await _checkpoint("Persons.live_uids")
	await _checkpoint("Persons.live_uids:1061")
	var out: Variant = {}
	await _checkpoint("Persons.live_uids:1062")
	for u: Variant in game.company:
		await _checkpoint("Persons.live_uids:loop:1062")
		if not u.dead:
			out[u.uid] = true
	await _checkpoint("Persons.live_uids:1065")
	for wid: Variant in game.world.get("warbands", {}):
		await _checkpoint("Persons.live_uids:loop:1065")
		for u: Variant in game.world["warbands"][wid].get("units", []):
			await _checkpoint("Persons.live_uids:loop:1066")
			if u is Unit and not u.dead:
				out[u.uid] = true
	await _checkpoint("Persons.live_uids:1069")
	for tid: Variant in game.world.get("towns", {}):
		await _checkpoint("Persons.live_uids:loop:1069")
		for u: Variant in game.world["towns"][tid].get("recruits", []):
			await _checkpoint("Persons.live_uids:loop:1070")
			if u is Unit:
				out[u.uid] = true
	await _checkpoint("Persons.live_uids:1073")
	for u: Variant in CampaignWorld.mustering_units(game.world):
		await _checkpoint("Persons.live_uids:loop:1073")
		if u is Unit and not u.dead: out[u.uid] = true
	await _checkpoint("Persons.live_uids:1075")
	for u: Unit in Mobilization.reserves(game):
		await _checkpoint("Persons.live_uids:loop:1075")
		if not u.dead: out[u.uid] = true
	await _checkpoint("Persons.live_uids:1077")
	for u: Unit in Prisoners.units(game):   # v0.033: held prisoners on both sides are alive, not lost with a force
		await _checkpoint("Persons.live_uids:loop:1077")
		out[u.uid] = true
	await _checkpoint("Persons.live_uids:1079")
	return out

## Native game/campaign/persons.gd:1088; only qualification, types, awaits and checkpoints added.
func _persons_sweep_town(game: Variant, t: Dictionary, live: Dictionary) -> void:
	await _checkpoint("Persons.sweep_town")
	await _checkpoint("Persons.sweep_town:1089")
	if not TownEcon.has_econ(t):
		return
	await _checkpoint("Persons.sweep_town:1091")
	var e: Dictionary = t["econ"]
	await _checkpoint("Persons.sweep_town:1092")
	var sweep_previous: Dictionary = TownSweep.begin(e)
	await _checkpoint("Persons.sweep_town:1093")
	for f: Variant in e["fams"]:
		await _checkpoint("Persons.sweep_town:loop:1093")
		if not f.has("pp"):
			continue
		if f.get("gone", false):
			for p: Variant in f["pp"]:   # a house that is gone keeps its records; the dead just lose their unit
				await _checkpoint("Persons.sweep_town:loop:1097")
				if int(p[5]) >= 0 and not live.has(int(p[5])):
					p[5] = -1
			Persons.pack_gone(e, f, float(game.day))
			continue
		for p: Variant in (f["pp"] as Array).duplicate():
			await _checkpoint("Persons.sweep_town:loop:1102")
			var uid: Variant = int(p[5])
			if uid < 0 or live.has(uid):
				continue
			var st: Variant = String(p[4])
			if st == "hire" or st == "":
				Persons.set_home(p)
				TownSweep.returned(f, p, st)
			else:
				People.casualty_rec(game, String(t["id"]), int(f["id"]), Persons.name_of(f, p, Persons.race_of(e)), "dead", st, p)
	await _checkpoint("Persons.sweep_town:1112")
	TownSweep.finish(sweep_previous)

## Native game/campaign/academy.gd:722; only qualification, types, awaits and checkpoints added.
func _academy_faction_turn(game: Variant, day: float, army_bills: Dictionary = {}) -> void:
	await _checkpoint("Academy.faction_turn")
	await _checkpoint("Academy.faction_turn:723")
	var w: Dictionary = game.world
	await _checkpoint("Academy.faction_turn:724")
	var RR: Variant = Academy.R()
	await _checkpoint("Academy.faction_turn:725")
	var I: Dictionary = RR["interest"]
	await _checkpoint("Academy.faction_turn:726")
	for fid: Variant in w.get("factions", {}):
		await _checkpoint("Academy.faction_turn:loop:726")
		var fac: Dictionary = w["factions"][fid]
		var S: Variant = Academy.state(w, fid)
		if float(S.get("turn_day", -1.0)) >= day:
			continue
		var cap: Dictionary = w["towns"].get(String(fac.get("capital", "")), {})
		if not TownEcon.has_econ(cap) or Academy.biz_of(cap["econ"]).is_empty() or String(cap.get("faction", "")) != String(fid):
			Academy.sync_towns(w, fid)
			continue
		var e: Dictionary = cap["econ"]
		var b: Variant = Academy.biz_of(e)
		S["turn_day"] = day
		var wage: Variant = float(b["wage"])
		var act: Variant = Academy.active_lines(w, fid)
		b["research_idle"] = act.is_empty()
		# interest from real conditions: the treasury against the army's keep, war, steel met, the ruler's temper
		var army_bill: float = float(army_bills[fid]) if army_bills.has(fid) else Army.bill(game, fid)
		var keep: float = maxf(1.0, army_bill * float(I["keep_days"]))
		var tre: Variant = float(fac.get("treasury", 0.0))
		var it: Variant = float(I["base"]) + float(I["treasury"]) * clampf(tre / keep - 1.0, -1.0, 1.0)
		for pr: Variant in w.get("wars", []):
			await _checkpoint("Academy.faction_turn:loop:746")
			if String(pr[0]) == fid or String(pr[1]) == fid:
				it += float(I["war"])
				break
		var met: Variant = Academy._steel_met(w, fid)
		S["met"] = met
		it += float(I["met"]) * minf(1.0, float(met) / maxf(1.0, float(I["met_items"])))
		it += float(I["temper"].get(Barge.temper(e), 0.0))
		it = clampf(it, 0.0, 1.0)
		S["interest"] = snappedf(it, 0.01)
		# No active line: the post and unspent cash wait, without payroll or fresh transfers.
		var budget: Variant = 0.0
		var places: Variant = 0
		if not act.is_empty():
			var per: Variant = wage * (1.0 + float(RR["mat_share"]))
			budget = it * float(RR["places_full"]) * per + wage * float(RR["lead_pay"])
			places = clampi(int(floor(it * float(RR["places_full"]))), 0, int(RR["places_max"]))
			if places <= 0:
				budget = 0.0
		S["budget"] = snappedf(budget, 0.1)
		S["places"] = places
		# the coin: two weeks of the budget in the till, from the realm's treasury, then the capital's chest
		var want: Variant = budget * 14.0 - float(b["till"])
		var paid: Variant = 0.0
		if want > 0.0:
			var a: Variant = minf(want, maxf(0.0, tre) * float(RR["treasury_share"]))
			fac["treasury"] = tre - a
			paid += a
			if paid < want:
				var spare: Variant = maxf(0.0, float(e["treasury"]) - float(Barge.treasury_lines(e)["short"]))
				var a2: Variant = minf(want - paid, spare * float(RR["treasury_share"]))
				e["treasury"] = float(e["treasury"]) - a2
				paid += a2
			b["till"] = float(b["till"]) + paid
		S["paid"] = paid   # the receipt is the exact debit, formatting belongs to the view
		if paid < want * 0.5 and budget > 0.0 and int(S.get("short_wk", 0)) == 0:
			Academy._log(S, day, "the treasury could not fund %s's budget in full." % Academy.house_name(e))
		S["short_wk"] = 1 if paid < want * 0.5 and budget > 0.0 else 0
		# Planned interest cannot hire people on an empty treasury. Existing till money can still fund work.
		var available: Variant = maxf(0.0, float(b["till"]) - float(b.get("owed", 0.0)))
		var weekly_wage: Variant = maxf(0.01, wage * 7.0)
		var affordable: Variant = maxi(0, int(floor((available / weekly_wage - float(RR["lead_pay"])) / (1.0 + float(RR["mat_share"])))))
		places = mini(places, affordable)
		S["places"] = places
		# places: a cut lays off the staff at once (the lead keeps his place while there is one)
		var affected: Variant = {}
		var old_cap: Variant = int(b["cap"])
		b["cap"] = places
		if int(b["workers"]) > places:
			var laid: Variant = Academy._lay_off(e, b, int(b["workers"]) - places, affected)
			if laid > 0:
				Academy._log(S, day, "a smaller budget: %d of %s's staff laid off." % [laid, Academy.house_name(e)])
		elif places > old_cap:
			Businesses.rebuild_open(e)
		# an empty post: the state names a successor
		var why: Variant = Academy.lead_gone(e, b)
		if why != "" and why != "none":
			Academy.vacate(w, fid, e, b, why, day)
		if (b.get("lead", []) as Array).size() < 2 and places >= 1:
			var rng: Variant = RandomNumberGenerator.new()
			rng.seed = hash([int(w.get("seed", 0)), fid, "lead", int(day)])
			if not Academy.appoint(w, fid, e, b, day, rng) and not b.has("vac"):
				b["vac"] = day
		# Finish every place and lead transition before households choose again.
		# set_job settles earned claims, but their idle places need the ordinary
		# matcher even when there is no funded alternative. An idle appointee has
		# likewise gained a job since his household's last turn.
		var lead: Array = b.get("lead", [])
		if lead.size() >= 2 and Families.assignments_stale(e["fams"][int(lead[0])]):
			affected[int(lead[0])] = true
		for family: Variant in affected:
			await _checkpoint("Academy.faction_turn:loop:816")
			Families.reassign(e, e["fams"][int(family)])
		await _families_match_idle(e)
		# Normal matching can move a lead's last place to better paid work.
		# His departure must stop this turn's study as well as the next day.
		why = Academy.lead_gone(e, b)
		if why != "" and why != "none":
			Academy.vacate(w, fid, e, b, why, day)
		if act.is_empty():
			if (b.get("lead", []) as Array).is_empty():
				var idle_rng: Variant = RandomNumberGenerator.new()
				idle_rng.seed = hash([int(w.get("seed", 0)), fid, "idle head", int(day)])
				Academy.appoint(w, fid, e, b, day, idle_rng)
			b["state"] = "idle"
			b["why"] = "no line it can take"
		# study: one steel piece a week from the town's stalls, bought and used up
		for Ln: Variant in act:
			await _checkpoint("Academy.faction_turn:loop:832")
			if String(Ln["knowhow"]) == "steel":
				Academy._study(cap, e, b, S, fid, day)
		# the week's research
		var hist: Array = S["hist"]
		hist.append([int(day), snappedf(float(S.get("out", 0.0)), 0.1)])
		while hist.size() > 26:
			await _checkpoint("Academy.faction_turn:loop:838")
			hist.pop_front()
		S["out"] = 0.0
		Academy.sync_towns(w, fid)

## Native game/campaign/barge.gd:1188; only qualification, types, awaits and checkpoints added.
func _barge_release_surplus(game: Variant, town: Dictionary, e: Dictionary) -> void:
	await _checkpoint("Barge.release_surplus")
	await _checkpoint("Barge.release_surplus:1189")
	var target: float = Barge.treasury_target(game, town, e)
	await _checkpoint("Barge.release_surplus:1190")
	var surplus: float = maxf(0.0, float(e.get("treasury", 0.0)) - target)
	await _checkpoint("Barge.release_surplus:1191")
	e["stats"]["treasury_target"] = target
	await _checkpoint("Barge.release_surplus:1192")
	if surplus <= 0.0: return
	# An allowance is distinct from tax; tax still credits the actual local ruler.
	# A vacant seat funds local households instead. One debit, one equal credit.
	await _checkpoint("Barge.release_surplus:1195")
	Barge._repay_forced(e, target)
	await _checkpoint("Barge.release_surplus:1196")
	surplus = maxf(0.0, float(e["treasury"]) - target)
	await _checkpoint("Barge.release_surplus:1197")
	var ruler: Dictionary = Feudal.tax_recipient(game, str(town["id"]))
	await _checkpoint("Barge.release_surplus:1198")
	e["treasury"] = float(e["treasury"]) - surplus
	await _checkpoint("Barge.release_surplus:1199")
	if ruler.is_empty():
		HouseUpkeep._pay_town_folk(e, {}, surplus)
	else:
		ruler["purse"] = float(ruler.get("purse", 0.0)) + surplus
		e["stats"]["allowance_uid"] = str(ruler.get("household_uid", ""))
		e["stats"]["allowance_total"] = float(e["stats"].get("allowance_total", 0.0)) + surplus
