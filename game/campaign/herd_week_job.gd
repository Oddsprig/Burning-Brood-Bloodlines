class_name HerdWeekJob
extends "res://campaign/campaign_checkpoint_job.gd"
## Exact native week order, now retaining loop locals inside the large phases.
## Native entry points remain unchanged for the independent equivalence oracle.
var day: float = 0.0
var _town: Dictionary = {}

func _init(_game_arg: Variant, town: Dictionary, day_v: float) -> void:
	_town = town
	day = day_v

func _run(game: Variant) -> void:
	await _herds_week(game, _town, day)
	_finished = true
	_checkpoint_game = null

func _step_label() -> String:
	return "herds/" + boundary

func _herds_week(game: Variant, town: Dictionary, day_v: float) -> void:
	await _checkpoint("Herds.week:enter")
	var e: Dictionary = town["econ"]
	if not e.has("hd"):
		Herds.migrate(game.world, town, e)
	var hd: Variant = Herds.H(e)
	var rng: Variant = RandomNumberGenerator.new()
	rng.seed = hash([int(game.world.get("seed", 0)), String(town["id"]), int(day_v), "herds"])
	var si: Variant = Calendar.season_index(day_v)
	var yr: Variant = Calendar.year(day_v)
	if yr != int(hd["y"]):
		hd["ly"] = hd["yr"]
		hd["yr"] = {}
		hd["y"] = yr
	hd.erase("_pg"); hd.erase("_pa")
	await _livestockcare_feed_hens(e, day_v)
	DomesticAnimals.feed_dogs(e, day_v)
	await _herds_disease(e, rng, day_v)
	await _herds_males(e)
	await _herdsmarket_land_choice(e, Plots.of(town), day_v)
	var P: Variant = Plots.of(town)
	await _herdsviews_assign_tiles(e, P) # Returned/bought stock uses its current native pasture allocation.
	var ids: Array = (hd["h"] as Dictionary).keys()
	for hid: Variant in ids:
		await _checkpoint("Herds.week:loop")
		var h: Dictionary = hd["h"][hid]
		if h.has("work_band"): continue
		Herds._life(e, h, si, day_v, rng)
	await _herds_orphans(e, day_v)
	await _herds_feed_all(e, P, si, day_v, rng)
	HerdRaids.plan(game, town, day_v)
	await _herdsmarket_stockpile(e, si, day_v)
	await _herdsmarket_repay_loans(e)
	await _herdsmarket_unsold(e, si, day_v)
	await _herdsmarket_offers(e, si, day_v)
	await _herdsmarket_wants(game, town, e, si, day_v)
	await _herdsmarket_drovers(game, town, e, day_v)
	await _herdsmarket_prices(e)
	await _herdsmarket_products(e, si, day_v)
	await _livestockcare_hive_week(e, day_v)
	await _herdsmarket_manure(e)
	await _herdsmarket_herder_caps(e)
	# empty records leave the list (their ledgers join the town's gone ledger; the log keeps what happened)
	for hid: Variant in (hd["h"] as Dictionary).keys():
		await _checkpoint("Herds.week:loop")
		var h2: Dictionary = hd["h"][hid]
		if Herds.head(h2) <= 0:
			Herds._retire(e, h2)

func _herds_disease(e: Dictionary, rng: RandomNumberGenerator, day_v: float) -> void:
	await _checkpoint("Herds._disease:enter")
	var DS: Dictionary = Herds.A()["diseases"]
	var hd: Variant = Herds.H(e)
	var wk: Variant = 7.0 / float(Herds.year_days())
	# the common's pressure by disease and kind: the sick share of the beasts of that kind grazing it
	var csum: Variant = {}; var ctot: Variant = {}
	var any: Variant = false
	for hid: Variant in hd["h"]:
		await _checkpoint("Herds._disease:loop")
		var h: Dictionary = hd["h"][hid]
		if h.has("work_band"): continue
		if float(h.get("cs", 0.0)) > 0.0:
			ctot[String(h["k"])] = float(ctot.get(String(h["k"]), 0.0)) + float(Herds.head(h))
			for d: Variant in h.get("inf", {}):
				await _checkpoint("Herds._disease:loop")
				var key: Variant = "%s|%s" % [d, h["k"]]
				csum[key] = float(csum.get(key, 0.0)) + float(h["inf"][d]) * float(Herds.head(h))
		if not (h.get("inf", {}) as Dictionary).is_empty() or not (h.get("imm", {}) as Dictionary).is_empty():
			any = true
	# outbreaks
	for d: Variant in DS:
		await _checkpoint("Herds._disease:loop")
		if rng.randf() >= float(DS[d]["chance"]) * wk:
			continue
		var pool: Variant = []
		for hid: Variant in hd["h"]:
			await _checkpoint("Herds._disease:loop")
			if not hd["h"][hid].has("work_band") and (DS[d]["kinds"] as Array).has(String(hd["h"][hid]["k"])) and Herds.head(hd["h"][hid]) > 0:
				pool.append(hid)
		if pool.is_empty():
			continue
		var h0: Dictionary = hd["h"][pool[rng.randi() % pool.size()]]
		if not h0.has("inf"):
			h0["inf"] = {}
		h0["inf"][d] = maxf(float(h0["inf"].get(d, 0.0)), float(Herds.A()["disease_seed"]))
		any = true
		TownEcon.town_hist(e, "%s broke out among %s." % [String(d).capitalize(), Herds.owner_text(e, h0)], day_v)
	if not any:
		return
	for hid: Variant in hd["h"].keys():
		await _checkpoint("Herds._disease:loop")
		var h: Dictionary = hd["h"][hid]
		var n: Variant = Herds.head(h)
		if n <= 0 or h.has("work_band"):
			continue
		var inf: Dictionary = h.get("inf", {})
		var imm: Dictionary = h.get("imm", {})
		for d: Variant in DS:
			await _checkpoint("Herds._disease:loop")
			var R: Dictionary = DS[d]
			if not (R["kinds"] as Array).has(String(h["k"])):
				continue
			var i: Variant = float(inf.get(d, 0.0))
			var im: Variant = float(imm.get(d, 0.0))
			var pres: Variant = 0.0
			if float(h.get("cs", 0.0)) > 0.0:
				pres = float(csum.get("%s|%s" % [d, h["k"]], 0.0)) / maxf(1.0, float(ctot.get(String(h["k"]), 1.0)))
			if i <= 0.0 and pres <= 0.0:
				continue
			var crowd: Variant = maxf(1.0, float(n) / maxf(1.0, float(h.get("t", n))))
			var hungry: Variant = float(Herds.A()["disease_hunger"]) if int(h["hun"]) > 0 else 1.0
			var s: Variant = maxf(0.0, 1.0 - i - im)
			i = minf(1.0 - im, i + s * (float(R["beta"]) * i + float(R["between"]) * pres) * crowd * hungry)
			var died: Variant = 0
			for age: Variant in Herds.AGES:
				await _checkpoint("Herds._disease:loop")
				var nd: Variant = Herds._whole(float(h[age]) * i * float(R["kill"]), rng)
				if nd > 0:
					died -= Herds.change(e, h, age, -nd, "died", "sickness: %s" % String(d), day_v)
			var rec: Variant = i / maxf(1.0, float(R["weeks"]))
			i = maxf(0.0, i - rec - float(died) / maxf(1.0, float(n)))
			im = minf(1.0, im + rec * float(R["immune"]))
			if i < 0.005:
				inf.erase(d)
			else:
				inf[d] = snappedf(i, 0.0001)
			imm[d] = snappedf(im, 0.0001)
		for d2: Variant in imm.keys():
			await _checkpoint("Herds._disease:loop")
			imm[d2] = float(imm[d2]) * (1.0 - float(Herds.A()["immune_fade"]) * wk)
			if float(imm[d2]) < 0.01:
				imm.erase(d2)
		if not inf.is_empty():
			h["inf"] = inf
		else:
			h.erase("inf")
		if not imm.is_empty():
			h["imm"] = imm
		else:
			h.erase("imm")

func _herds_males(e: Dictionary) -> void:
	await _checkpoint("Herds._males:enter")
	var m: Variant = {}; var f: Variant = {}
	for hid: Variant in Herds.herds(e):
		await _checkpoint("Herds._males:loop")
		var h: Dictionary = Herds.herds(e)[hid]
		var K: Variant = Herds.kind(String(h["k"]))
		if h.has("work_band"): continue
		if float(K.get("fpm", 0.0)) <= 0.0:
			continue
		var k: Variant = String(h["k"])
		m[k] = float(m.get(k, 0.0)) + float(h["g"]) * (1.0 - float(K["fem"])) * float(K["fpm"])   # (the grown males' share of the herd)
		f[k] = float(f.get(k, 0.0)) + float(h["g"]) * float(K["fem"])
	var out: Variant = {}
	for k: Variant in f:
		await _checkpoint("Herds._males:loop")
		out[k] = snappedf(minf(1.0, float(m.get(k, 0.0)) / maxf(1.0, float(f[k]))), 0.001)
	Herds.H(e)["_male"] = out

func _herds_orphans(e: Dictionary, day_v: float) -> void:
	await _checkpoint("Herds._orphans:enter")
	var fams: Array = e["fams"]
	for hid: Variant in (Herds.H(e)["h"] as Dictionary).keys():
		await _checkpoint("Herds._orphans:loop")
		var h: Dictionary = Herds.herds(e)[hid]
		if String(h["ow"]) != "f" or Herds.head(h) <= 0:
			continue
		var fid: Variant = int(h["oi"])
		if fid > 0 and fid < fams.size() and not fams[fid].get("gone", false):
			continue
		var to: Variant = Herds.herd_for(e, 0, String(h["k"]), day_v)
		for age: Variant in Herds.AGES:
			await _checkpoint("Herds._orphans:loop")
			if int(h[age]) > 0:
				Herds._transfer(e, h, to, age, int(h[age]), "sold", "bought", "left to the town", "left by %s" % Plots.owner_text(e, fid), day_v)

func _herds_feed_all(e: Dictionary, P: Dictionary, si: int, day_v: float, rng: RandomNumberGenerator) -> void:
	await _checkpoint("Herds._feed_all:enter")
	var hd: Variant = Herds.H(e)
	var pc: Dictionary = hd["pc"]
	var grazed: Variant = {}   # plot -> bales eaten a day
	var AA: Variant = Herds.A()
	var fod_need: Variant = 0.0; var fod_have: Variant = 0.0
	for hid: Variant in (hd["h"] as Dictionary).keys():
		await _checkpoint("Herds._feed_all:loop")
		var h: Dictionary = hd["h"][hid]
		var need: Variant = Herds.feed_day(h)
		if String(h["k"]) in ["hens", "dogs"] or h.has("work_band"): continue
		if need <= 0.0 or String(h["ow"]) == "d":
			continue
		var K: Variant = Herds.kind(String(h["k"]))
		var grass: Variant = 0.0
		var parts: Variant = []
		if K.get("fallow", false):
			grass = need * float(AA["fallow"][si])
		elif not P.is_empty():
			parts = Herds._graze_parts(e, P, h, si)
			for pp: Variant in parts:
				await _checkpoint("Herds._feed_all:loop")
				grass += float(pp[1])
		var eat: Variant = minf(need, grass)
		if grass > 0.0:
			for pp: Variant in parts:   # each plot (the common as one pool, -1) gives its share of what was eaten
				await _checkpoint("Herds._feed_all:loop")
				grazed[int(pp[0])] = float(grazed.get(int(pp[0]), 0.0)) + eat * float(pp[1]) / grass
		var short: Variant = (need - eat) * 7.0
		Herds._fees(e, P, h)
		if si <= 1 and grass > need:   # hay from the spare grass (spring and summer)
			var cap: Variant = need * maxf(float(AA["hay_cap_days"]), Herds.winter_days(e))
			h["fod"] = minf(cap, float(h["fod"]) + (grass - need) * 7.0 * float(AA["hay_share"]))
		if short > 0.0:
			var own: Variant = minf(float(h["fod"]), short)
			h["fod"] = float(h["fod"]) - own
			short -= own
		if short > 0.0:
			short -= Herds._buy_fodder(e, h, short)
		var fed: Variant = 1.0 - short / maxf(0.001, need * 7.0)
		if short > 0.01:
			h["hun"] = int(h["hun"]) + int(ceil(7.0 * (1.0 - fed)))
		else:
			h["hun"] = maxi(0, int(h["hun"]) - 7)
		if int(h["hun"]) > int(AA["starve_after"]) and fed < 1.0:
			for age: Variant in ["y", "o", "g"]:
				await _checkpoint("Herds._feed_all:loop")
				var n: Variant = Herds._whole(float(h[age]) * (1.0 - fed) * float(AA["starve_k"]), rng)
				if n > 0:
					Herds.change(e, h, age, -n, "died", "starved", day_v)
		fod_need += need; fod_have += float(h["fod"])
	# pasture condition: grazed to its growth it wears; lightly grazed it mends
	var pgz: Variant = {}   # the week's grazing a day per plot: [eaten, grown] (tests: never more eaten than grown)
	if not P.is_empty():
		var pool_g: Variant = 0.0
		for i0: Variant in hd.get("cpool", []):
			await _checkpoint("Herds._feed_all:loop")
			pool_g += Herds.grass_day(e, P, int(i0), si)
		var pool_ate: Variant = float(grazed.get(-1, 0.0))
		for i: Variant in Plots.count(P):
			await _checkpoint("Herds._feed_all:loop")
			if int(P["use"][i]) != Plots.PASTURE:
				continue
			var g: Variant = Herds.grass_day(e, P, i, si)
			var ate: Variant = float(grazed.get(i, 0.0))
			if int(P["own"][i]) <= 0 and pool_g > 0.0:   # the common: the pool's grazing by each plot's grass
				ate += pool_ate * g / pool_g
			if ate > 0.0:
				pgz[str(i)] = [ate, g]
			var c: Variant = Herds.cond(e, i)
			if si <= 1 and g > 0.0 and ate >= g * 0.999:   # grazed to the bone while it should be growing
				c = maxf(float(AA["cond_min"]), c - float(AA["wear"]))
			elif ate < g * 0.8 or si >= 2:   # lightly grazed, or resting through autumn and winter
				c = minf(1.0, c + float(AA["mend"]))
			if absf(c - 1.0) < 0.0001:
				pc.erase(str(i))
			else:
				pc[str(i)] = snappedf(c, 0.001)
	hd["pgz"] = pgz
	hd.erase("_pg")   # the common's grass changed with its condition
	var fodder: Variant = float(e["barn"].get("fodder", 0)) + float(e["stock"].get("fodder", 0))
	hd["fodd"] = snappedf((fod_have + fodder) / maxf(0.01, fod_need), 0.1) if fod_need > 0.0 else 0.0
	hd["fneed"] = snappedf(fod_need, 0.1)

func _herdsmarket_stockpile(e: Dictionary, si: int, day: float) -> void:
	await _checkpoint("HerdsMarket._stockpile:enter")
	if si != 1 and si != 2:
		return
	var wd: Variant = Herds.winter_days(e)
	var weeks: Variant = maxf(1.0, (float((3 - si) * Calendar.DAYS_PER_SEASON) - float(Calendar.day_of_season(day))) / 7.0)
	for hid: Variant in Herds.herds(e):
		await _checkpoint("HerdsMarket._stockpile:loop")
		var h: Dictionary = Herds.herds(e)[hid]
		var fd: Variant = Herds.feed_day(h)
		if fd <= 0.0 or String(h["ow"]) == "d" or h.has("work_band"):
			continue
		var gap: Variant = fd * wd - float(h["fod"])
		if gap <= 1.0:
			continue
		var got: Variant = HerdsMarket._buy_fodder(e, h, gap / weeks, false, float(Herds.A()["stock_reserve"]))
		h["fod"] = float(h["fod"]) + got

func _herdsmarket_repay_loans(e: Dictionary) -> void:
	await _checkpoint("HerdsMarket._repay_loans:enter")
	var hd: Variant = Herds.H(e)
	var fl: Dictionary = hd.get("floan", {})
	if not hd.has("floan_claims"): hd["floan_claims"] = {}
	if not hd.has("floan_unknown"): hd["floan_unknown"] = {}
	var claim_book: Dictionary = hd["floan_claims"]
	var unknown_book: Dictionary = hd["floan_unknown"]
	var fams: Array = e["fams"]
	var p: Variant = float(e["price"].get("fodder", 3.0))
	for key: Variant in fl.keys():
		await _checkpoint("HerdsMarket._repay_loans:loop")
		var fid: Variant = int(key)
		var owed: Variant = float(fl[key])
		var creditors: Dictionary = claim_book.get(key, {})
		var known: Variant = HerdsMarket._fodder_claim_total(creditors)
		var unknown: Variant = maxf(0.0, owed - known)
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
		var who: Variant = {"ow": "f", "oi": fid}
		var kind_n: Variant = mini(int(floor(owed)), int(HerdsMarket.straw_left(e, who)))
		if kind_n > 0:
			var kind_left: Variant = float(kind_n)
			var known_kind: Variant = minf(float(kind_n), known)
			if known_kind > 0.0:
				var moved: Variant = HarvestClaims.transfer_units(e, "fodder", HarvestClaims.owner(who), creditors, known_kind)
				HerdsMarket._reduce_fodder_claims(creditors, moved)
				owed -= moved
				kind_left -= moved
			if kind_left > 0.0 and unknown > 0.0:
				var moved_unknown: Variant = HarvestClaims.transfer_units(e, "fodder", HarvestClaims.owner(who), {"?": 1.0}, minf(kind_left, unknown))
				owed -= moved_unknown
				unknown -= moved_unknown
		var f: Dictionary = fams[fid]
		var pay: Variant = minf(owed * p, maxf(0.0, float(f["purse"]) - float(Herds.A()["buy_reserve"])))
		if pay > 0.0:
			f["purse"] = float(f["purse"]) - pay
			var known_pay: Variant = minf(pay, HerdsMarket._fodder_claim_total(creditors) * p)
			if known_pay > 0.0:
				HarvestClaims.credit(e, creditors, known_pay)
				HerdsMarket._reduce_fodder_claims(creditors, known_pay / maxf(0.01, p))
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

func _herdsmarket_unsold(e: Dictionary, _si: int, day: float) -> void:
	await _checkpoint("HerdsMarket._unsold:enter")
	var hd: Variant = Herds.H(e)
	var of: Array = hd["of"]
	var cap: Variant = {}
	for o: Variant in of:
		await _checkpoint("HerdsMarket._unsold:loop")
		var h: Dictionary = hd["h"].get(str(int(o[0])), {})
		if h.is_empty() or int(o[2]) <= 0 or float(Herds.kind(String(h["k"])).get("meat", 0.0)) <= 0.0:
			continue
		# what the owners could not sell they slaughter only as far as it is eaten (their larder) or sells (the
		# market's want of fresh meat); the rest they keep. A starving herd's surplus is killed for its hides
		# (the meat not dressed). A drover waits his days at market, then sells for slaughter what the town wants.
		if String(h["ow"]) == "d" and day - float(h.get("da", day)) < float(Herds.A()["drove"]["sell_days"]):
			continue
		var key: Variant = str(int(h["id"]))
		if not cap.has(key):
			cap[key] = HerdsMarket._home_cap(e, h)
		var n: Variant = mini(int(o[2]), int(cap[key]))
		var meals: Variant = float(HerdsMarket.yields(String(h["k"]), String(o[1])).get("fresh_meat", 0.0))
		if int(h["hun"]) <= int(Herds.A()["starve_after"]) / 2 and meals > 0.0:
			var use: Variant = 0
			if Herds.sick(h) <= float(Herds.A()["disease_no_sale"]):
				use = maxi(0, int(float(e.get("need", {}).get("fresh_meat", 0.0)) * 1.2) - int(e["stock"].get("fresh_meat", 0)))
				if String(h["ow"]) == "f":
					use += HerdsMarket.larder_room(e, e["fams"][int(h["oi"])])
			n = mini(n, int(floor(float(use) / meals + 0.5)))   # a carcass when at least half of it is used
		if n <= 0 or h.has("work_band"):
			continue
		var got: Variant = -Herds.change(e, h, String(o[1]), -n, "slaughtered", "at home by the owners", day)
		cap[key] = int(cap[key]) - got
		HerdsMarket._carcass(e, h, String(o[1]), got, true)
	hd["of"] = []

func _herdsmarket_offers(e: Dictionary, si: int, day: float) -> void:
	await _checkpoint("HerdsMarket._offers:enter")
	var hd: Variant = Herds.H(e)
	var of: Variant = []
	var ofk: Variant = {}
	var P: Variant = Plots._p(e)
	var fod_in_reach: Variant = float(e["barn"].get("fodder", 0)) + float(e["stock"].get("fodder", 0))
	var town_need: Variant = float(hd.get("fneed", 0.0))
	# the autumn reckoning counts a family's own straw for the year (the autumn cut still to come) by its herds' feed
	var fam_feed: Variant = {}
	var own_year: Variant = {}
	var straw_due: Variant = 0.0   # the grain cuts still to come this year (their straw)
	for s: Variant in TownEcon.data()["land"]["harvest_seasons"].get("grain", []):
		await _checkpoint("HerdsMarket._offers:loop")
		if int(s[0]) >= si:
			straw_due += float(e.get("wacres", {}).get("grain", 0.0)) * float(Herds.A()["straw_acre"]) * float(s[1]) * (0.5 if int(s[0]) == si else 1.0)
	if si == 2:
		for hid0: Variant in hd["h"]:
			await _checkpoint("HerdsMarket._offers:loop")
			var h0: Dictionary = hd["h"][hid0]
			if h0.has("work_band"): continue
			if String(h0["ow"]) == "f" or String(h0["ow"]) == "s":
				fam_feed[int(h0["oi"])] = float(fam_feed.get(int(h0["oi"]), 0.0)) + Herds.feed_day(h0)
		for fid0: Variant in fam_feed:
			await _checkpoint("HerdsMarket._offers:loop")
			var f0: Dictionary = e["fams"][int(fid0)]
			own_year[fid0] = float(f0["land"].get("grain", 0)) * float(Herds.A()["straw_acre"]) * float(f0.get("worked", 1.0))
	for hid: Variant in hd["h"]:
		await _checkpoint("HerdsMarket._offers:loop")
		var h: Dictionary = hd["h"][hid]
		var k: Variant = String(h["k"])
		var n: Variant = Herds.head(h)
		if n <= 0 or h.has("work_band"):
			continue
		if Herds.sick(h) > float(Herds.A()["disease_no_sale"]):   # nobody buys from a herd this sick
			continue
		if String(h["ow"]) == "d":   # a drover's herd at its market: every head is for sale
			for age0: Variant in HerdsMarket.AGES:
				await _checkpoint("HerdsMarket._offers:loop")
				if int(h[age0]) > 0:
					of.append([int(h["id"]), age0, int(h[age0]), "d"])
					ofk[k] = int(ofk.get(k, 0)) + int(h[age0])
			continue
		var tgt: Variant = HerdsMarket._target(e, h, P)
		h["t"] = tgt
		var surplus: Variant = maxi(0, n - tgt) if k == "dogs" or float(Herds.kind(k).get("meat", 0.0)) > 0.0 else 0
		# the old go in autumn and winter (an old ox ploughs on until a young one replaces it; old hives stay)
		var olds: Variant = int(h["o"]) if si >= 2 and k != "oxen" and float(Herds.kind(k).get("meat", 0.0)) > 0.0 else 0
		var flag: Variant = ""
		if si == 2 and Herds.feed_day(h) > 0.0 and k != "oxen":   # the autumn reckoning (the plough oxen are wintered first)
			# bales to winter the herd (autumn's shortfall and the winter), what it has (its hay, its owners' straw
			# for the year), what it can buy (its share of the town's hay and straw, now and the autumn cut to come,
			# paid from the purse and from selling the beasts it does not keep at half a grown head's price)
			var winter: Variant = Herds.feed_day(h) * Herds.winter_days(e)
			var per: Variant = winter / float(n)
			var share: Variant = (fod_in_reach + straw_due) * Herds.feed_day(h) / maxf(0.01, town_need)
			var pf: Variant = maxf(0.01, float(e["price"].get("fodder", 3.0)) * TownEcon.markup())
			var mine: Variant = 0.0
			if own_year.has(int(h["oi"])) and (String(h["ow"]) == "f" or String(h["ow"]) == "s"):
				mine = float(own_year[int(h["oi"])]) * Herds.feed_day(h) / maxf(0.01, float(fam_feed[int(h["oi"])]))
			var free: Variant = float(h["fod"]) + mine
			var v: Variant = Herds.price(e, k) * 0.5
			var keep_coin: Variant = (free * pf + maxf(0.0, Herds._coin(e, h)) + float(n) * v) / (per * pf + v)
			var keep_reach: Variant = (free + share) / maxf(0.001, per)
			var keep: Variant = int(floor(minf(float(n), minf(keep_coin, keep_reach))))
			if keep < n:
				var ws: Variant = n - keep
				if ws > surplus:
					surplus = ws
					flag = "w"
		var off: Variant = {"o": mini(int(h["o"]), maxi(olds, surplus)), "y": 0, "g": 0}
		var left: Variant = maxi(0, surplus - int(off["o"]))
		off["y"] = mini(int(h["y"]), left)
		left -= int(off["y"])
		off["g"] = mini(int(h["g"]), left)
		for age: Variant in HerdsMarket.AGES:
			await _checkpoint("HerdsMarket._offers:loop")
			if int(off[age]) > 0:
				of.append([int(h["id"]), age, int(off[age]), flag])
				ofk[k] = int(ofk.get(k, 0)) + int(off[age])
	hd["of"] = of
	hd["ofk"] = ofk
	hd["wak"] = {}
	hd["sok"] = {}

func _herdsmarket_wants(_game: Variant, _town: Dictionary, e: Dictionary, _si: int, day: float) -> void:
	await _checkpoint("HerdsMarket._wants:enter")
	var hd: Variant = Herds.H(e)
	var wak: Dictionary = hd["wak"]
	var aph: Variant = float(TownEcon.data()["land"]["acres_per_hand"])
	var reserve: Variant = float(Herds.A()["buy_reserve"])
	# These indices live only for this sales pass. References retain herd/offer order
	# and see head counts and offers change immediately as each purchase is made.
	var cattle: Variant = {}
	var oxen: Variant = {}
	for h: Variant in (hd["h"] as Dictionary).values():
		await _checkpoint("HerdsMarket._wants:loop")
		var fid: Variant = int(h["oi"])
		if String(h["ow"]) != ("s" if fid == 0 else "f"):
			continue
		if String(h["k"]) == "cattle":
			if not cattle.has(fid): cattle[fid] = []
			cattle[fid].append(h)
		elif String(h["k"]) == "oxen" and not oxen.has(fid):
			oxen[fid] = h
	var offers: Variant = {}
	for o: Variant in hd["of"]:
		await _checkpoint("HerdsMarket._wants:loop")
		var h: Dictionary = hd["h"].get(str(int(o[0])), {})
		if h.is_empty(): continue
		var k: Variant = String(h["k"])
		var age: Variant = String(o[1])
		if not offers.has(k): offers[k] = {}
		if not offers[k].has(age): offers[k][age] = []
		offers[k][age].append(o)
	for f: Variant in e["fams"]:
		await _checkpoint("HerdsMarket._wants:loop")
		if f.get("gone", false) or f.get("estate", false):
			continue
		var ac: Variant = Families.acres(f)
		if ac <= 0:
			continue
		var short: Variant = int(ceil(float(ac) / aph - DomesticAnimals.draught(e, int(f["id"])))) - maxi(0, int(f.get("ox", 0)))
		if short <= 0:
			continue
		short = mini(short, 2)
		wak["oxen"] = int(wak.get("oxen", 0)) + short
		wak["cattle"] = int(wak.get("cattle", 0)) + short   # grown cattle are trained to the plough too
		# the family's own grown cattle first (trained to the plough: from its herd to its oxen, no coin)
		for own: Variant in cattle.get(int(f["id"]), []):
			await _checkpoint("HerdsMarket._wants:loop")
			while short > 0 and int(own["g"]) >= 2:
				await _checkpoint("HerdsMarket._wants:loop")
				var oxh0: Variant = HerdsMarket._indexed_oxen(e, oxen, int(f["id"]), day)
				if Herds._transfer(e, own, oxh0, "g", 1, "sold", "bought", "to the family's plough", "from the family's own herd", day) <= 0:
					break
				short -= 1
		for src: Variant in ["oxen", "cattle"]:
			await _checkpoint("HerdsMarket._wants:loop")
			if short <= 0:
				break
			var p: Variant = Herds.price(e, src)
			while short > 0 and float(f["purse"]) - p > reserve:
				await _checkpoint("HerdsMarket._wants:loop")
				var o: Variant = HerdsMarket._take_offer(e, src, ["g"], int(f["id"]), -1, offers)
				if o.is_empty():
					break
				var seller: Dictionary = hd["h"][str(int(o[0]))]
				var oxh: Variant = HerdsMarket._indexed_oxen(e, oxen, int(f["id"]), day)
				if Herds._transfer(e, seller, oxh, "g", 1, "sold", "bought", "to the %s for the plough" % Backstory.plural(String(f["name"])),
						"from %s" % Herds.owner_text(e, seller), day) > 0:
					f["purse"] = float(f["purse"]) - p
					Herds._add_coin(e, seller, p)
					hd["sok"][src] = int(hd["sok"].get(src, 0)) + 1
					short -= 1
	# restocking: a herd below half its keep buys grown stock of its kind
	for hid: Variant in (hd["h"] as Dictionary).keys():
		await _checkpoint("HerdsMarket._wants:loop")
		var h: Dictionary = hd["h"][hid]
		var k: Variant = String(h["k"])
		if not HerdsMarket.GRAZE.has(k) or String(h["ow"]) == "d" or h.has("work_band"):
			continue
		var need: Variant = int(float(h["t"]) * 0.5) - Herds.head(h)
		if need <= 0:
			continue
		need = mini(need, int(Herds.A()["restock_week"]))
		wak[k] = int(wak.get(k, 0)) + need
		var p2: Variant = Herds.price(e, k)
		while need > 0 and Herds._coin(e, h) - p2 > reserve:
			await _checkpoint("HerdsMarket._wants:loop")
			var o2: Variant = HerdsMarket._take_offer(e, k, ["g"], -1, int(h["id"]), offers)
			if o2.is_empty():
				break
			var s2: Dictionary = hd["h"][str(int(o2[0]))]
			if Herds._transfer(e, s2, h, "g", 1, "sold", "bought", "to %s" % Herds.owner_text(e, h), "from %s" % Herds.owner_text(e, s2), day) > 0:
				Herds._add_coin(e, h, -p2)
				Herds._add_coin(e, s2, p2)
				hd["sok"][k] = int(hd["sok"].get(k, 0)) + 1
				need -= 1
	await _herdsmarket_pot_buys(e, day)
	DomesticAnimals.buy_dogs(e, day)

func _herdsmarket_pot_buys(e: Dictionary, day: float) -> void:
	await _checkpoint("HerdsMarket._pot_buys:enter")
	var hd: Variant = Herds.H(e)
	var mp: Variant = float(e["price"].get("meat", 20.0)) * float(Herds.A()["pot_value"])
	var cands: Variant = []
	for o: Variant in hd["of"]:
		await _checkpoint("HerdsMarket._pot_buys:loop")
		if int(o[2]) <= 0:
			continue
		var h: Dictionary = hd["h"].get(str(int(o[0])), {})
		if h.is_empty() or h.has("work_band") or HerdsMarket.GRAZE.find(String(h["k"])) < 0 and String(h["k"]) != "hens":
			continue
		var meals: Variant = float(HerdsMarket.yields(String(h["k"]), String(o[1])).get("fresh_meat", 0.0))
		var p: Variant = Herds.price(e, String(h["k"]), String(o[1]))
		if meals >= 1.0 and p < meals * mp:
			cands.append([p / meals, o, meals, p])
	if cands.is_empty():
		return
	cands.sort_custom(func(a: Variant, b: Variant) -> bool: return float(a[0]) < float(b[0]))
	var buys: Variant = 0
	var ci: Variant = 0
	var fams: Array = e["fams"]
	var start: Variant = int(day) % maxi(1, fams.size())
	for j: Variant in fams.size():
		await _checkpoint("HerdsMarket._pot_buys:loop")
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
		if HerdsMarket.larder_room(e, f) < int(float(c[2]) * 0.5) or float(f["purse"]) - float(c[3]) < float(Herds.A()["pot_reserve"]):
			continue
		var seller: Dictionary = hd["h"][str(int(o[0]))]
		var k: Variant = String(seller["k"])
		var age: Variant = String(o[1])
		var mine: Variant = Herds.herd_for(e, int(f["id"]), k, day)
		if Herds._transfer(e, seller, mine, age, 1, "sold", "bought", "to the %s for their pot" % Backstory.plural(String(f["name"])),
				"from %s" % Herds.owner_text(e, seller), day) <= 0:
			ci += 1
			continue
		o[2] = int(o[2]) - 1
		f["purse"] = float(f["purse"]) - float(c[3])
		Herds._add_coin(e, seller, float(c[3]))
		hd["sok"][k] = int(hd["sok"].get(k, 0)) + 1
		Herds.change(e, mine, age, -1, "slaughtered", "for the family's pot", day)
		var yl: Variant = HerdsMarket.yields(k, age)
		HerdsMarket._to_larder(e, f, int(floor(float(yl["fresh_meat"]))))
		var rest: Variant = {}
		for g: Variant in yl:
			await _checkpoint("HerdsMarket._pot_buys:loop")
			if g != "fresh_meat" and int(floor(float(yl[g]))) > 0:
				rest[g] = int(floor(float(yl[g])))
		HerdsMarket._sell(e, mine, rest, float(TownEcon.data()["market"]["broker_share"]))
		buys += 1

func _herdsmarket_prices(e: Dictionary) -> void:
	await _checkpoint("HerdsMarket._prices:enter")
	var hd: Variant = Herds.H(e)
	var pr: Dictionary = hd["pr"]
	var PP: Dictionary = Herds.A()["price"]
	for k: Variant in Herds.kinds():
		await _checkpoint("HerdsMarket._prices:loop")
		var base: Variant = float(Herds.kind(k)["price"]) * Barge.pl(e)
		var s: Variant = float(hd["ofk"].get(k, 0)) + 1.0
		var d: Variant = float(hd["wak"].get(k, 0)) + float(hd.get("bk", {}).get(k, 0)) + 1.0
		var tgt: Variant = base * pow(clampf(d / s, float(PP["clamp"][0]), float(PP["clamp"][1])), float(PP["power"]))
		var p: Variant = float(pr.get(k, base))
		pr[k] = snappedf(p + (tgt - p) * float(PP["step"]), 0.01)
	hd["bk"] = {}

func _herdsmarket_products(e: Dictionary, si: int, _day: float) -> void:
	await _checkpoint("HerdsMarket._products:enter")
	var hd: Variant = Herds.H(e)
	var dd: Variant = {}
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var share: Variant = float(TownEcon.data()["market"]["broker_share"])
	var need: Dictionary = e.get("need", {})
	var st: Dictionary = e["stock"]
	var want: Variant = {}
	var per_owner: Variant = []
	for hid: Variant in hd["h"]:
		await _checkpoint("HerdsMarket._products:loop")
		var h: Dictionary = hd["h"][hid]
		if String(h["ow"]) == "d" or h.has("work_band"):
			continue
		var K: Variant = Herds.kind(String(h["k"]))
		var out: Variant = {}
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
			out["feathers"] = float(h["g"]) * float(K["moult"]) * 7.0 + float(h.get("feather_carry", 0.0))
		if not out.is_empty():
			per_owner.append([h, out])
			for g: Variant in out:
				await _checkpoint("HerdsMarket._products:loop")
				want[g] = float(want.get(g, 0.0)) + float(out[g])
	# how much of each the market takes this week (its want, as for the barns)
	var take: Variant = {}
	for g: Variant in want:
		await _checkpoint("HerdsMarket._products:loop")
		var wq: Variant = maxf(0.0, float(need.get(g, 0.0)) * 1.2 - float(st.get(g, 0)) + float(e.get("dem", {}).get(g, 0.0)) * 7.0)
		take[g] = minf(1.0, wq / maxf(0.001, float(want[g])))
	for po: Variant in per_owner:
		await _checkpoint("HerdsMarket._products:loop")
		var h2: Dictionary = po[0]
		var out2: Dictionary = po[1]
		var barn: Variant = {}
		for g: Variant in out2:
			await _checkpoint("HerdsMarket._products:loop")
			var q: Variant = float(out2[g]) * float(take[g])
			var p: Variant = float(e["price"].get(g, 1.0)) * share
			var v: Variant = minf(q * p, maxf(0.0, float(mkt["till"])))
			q = v / maxf(0.01, p)
			if q > 0.0:
				mkt["till"] = float(mkt["till"]) - v
				mkt["spend"] = float(mkt.get("spend", 0.0)) + v
				Herds._add_coin(e, h2, v)
				dd[g] = float(dd.get(g, 0.0)) + q / 7.0
			var rest: Variant = int(floor(float(out2[g]) - q))
			if g == "feathers": h2["feather_carry"] = maxf(0.0, float(out2[g]) - q - float(rest))
			if rest > 0 and g != "milk":
				barn[g] = rest
		for g2: Variant in barn:
			await _checkpoint("HerdsMarket._products:loop")
			HarvestClaims.add(e, String(g2), int(barn[g2]), {HarvestClaims.owner(h2): 1.0}, int(e.get("day", 0)), "herd products")
			TownEcon.led(e, "made", g2, int(barn[g2]))
	hd["dd"] = dd

func _herdsmarket_manure(e: Dictionary) -> void:
	await _checkpoint("HerdsMarket._manure:enter")
	var hd: Variant = Herds.H(e)
	var t: Variant = 0.0
	for hid: Variant in hd["h"]:
		await _checkpoint("HerdsMarket._manure:loop")
		var h: Dictionary = hd["h"][hid]
		if h.has("work_band"): continue
		t += Herds.ge(h) * float(Herds.kind(String(h["k"])).get("manure", 0.0))
	hd["mt"] = snappedf(float(hd["mt"]) + (t - float(hd["mt"])) * 0.1, 0.01)
	var acres: Variant = 0.0
	for c: Variant in e.get("land", {}):
		await _checkpoint("HerdsMarket._manure:loop")
		acres += float(e["land"][c])
	var recovered: Variant = float(hd.get("human_manure_week", 0)) / 1000 * EconGen.YEAR_DAYS / 7
	var share: Variant = minf(1.0, (float(hd["mt"]) + recovered) / maxf(1.0, acres * float(Herds.A()["manure_acre"])))
	hd["man"] = snappedf(1.0 + float(Herds.A()["manure_yield"]) * share, 0.0001)

func _herdsmarket_land_choice(e: Dictionary, P: Dictionary, day: float) -> void:
	await _checkpoint("HerdsMarket._land_choice:enter")
	if P.is_empty():
		return
	var L: Dictionary = TownEcon.data()["land"]
	var clim: Dictionary = TownEcon.data()["climates"].get(String(e.get("climate", "temperate")), {})
	var gv: Variant = float(L["yield"]["grain"]) * float(clim.get("grain_yield", 1.0)) * float(e["price"].get("grain", 3.6))
	gv += float(Herds.A()["straw_acre"]) * float(e["price"].get("fodder", 3.0))   # grain land gives straw too
	var fv: Variant = float(L["yield"].get("fodder", 0.0)) * float(e["price"].get("fodder", 3.0))
	var m: Variant = float(Herds.A()["land_switch"])
	var short: Variant = Herds.fodder_days(e) >= 0.0 and Herds.fodder_days(e) < float(Herds.A()["fodder_days_want"])
	var from: Variant = ""; var to: Variant = ""
	if fv > gv * m and short:
		from = "grain"; to = "fodder"
	elif gv > fv * m and int(e.get("land", {}).get("fodder", 0)) > 0:
		from = "fodder"; to = "grain"
	else:
		return
	var best: Dictionary = {}
	var ba: Variant = 0
	for f: Variant in e["fams"]:
		await _checkpoint("HerdsMarket._land_choice:loop")
		if f.get("gone", false) or f.get("estate", false):
			continue
		var a: Variant = int(f["land"].get(from, 0))
		if a > ba:
			ba = a; best = f
	if best.is_empty():
		return
	var ci: Variant = Plots._crop_index(P, from)
	for i: Variant in Plots.count(P):
		await _checkpoint("HerdsMarket._land_choice:loop")
		if int(P["own"][i]) == int(best["id"]) and int(P["use"][i]) == Plots.FIELD and int(P["sub"][i]) == ci:
			HerdsMarket.change_crop(e, P, best, i, from, to, day)
			return

func _herdsmarket_herder_caps(e: Dictionary) -> void:
	await _checkpoint("HerdsMarket._herder_caps:enter")
	var biz: Array = e["biz"]
	var need: Variant = {}
	for hid: Variant in Herds.herds(e):
		await _checkpoint("HerdsMarket._herder_caps:loop")
		var h: Dictionary = Herds.herds(e)[hid]
		if String(h["ow"]) == "b":
			need[int(h["oi"])] = float(need.get(int(h["oi"]), 0.0)) + Herds.ge(h) / float(Herds.kind(String(h["k"])).get("per_hand", 25))
	for b: Variant in biz:
		await _checkpoint("HerdsMarket._herder_caps:loop")
		if String(b["type"]) == "herder" and not b.get("closed", false):
			# cap is paid places, excluding the actual working family keeper.
			b["cap"] = maxi(0, int(ceil(float(need.get(int(b["id"]), 0.0)) - int(b.get("kw", 0)))))

func _herdsmarket_drovers(game: Variant, town: Dictionary, e: Dictionary, day: float) -> void:
	await _checkpoint("HerdsMarket._drovers:enter")
	var w: Dictionary = game.world
	if not w.has("droves"):
		w["droves"] = {}
	var DV: Dictionary = Herds.A()["drove"]
	for b: Variant in e["biz"]:
		await _checkpoint("HerdsMarket._drovers:loop")
		if String(b["type"]) != "drover" or b.get("closed", false) or int(b["workers"]) <= 0:
			continue
		var busy: Variant = false
		for did: Variant in w["droves"]:
			await _checkpoint("HerdsMarket._drovers:loop")
			var dv: Dictionary = w["droves"][did]
			if String(dv["from"]) == String(town["id"]) and int(dv["b"]) == int(b["id"]):
				busy = true
		if busy:
			continue
		var best: Array = []
		var bv: Variant = 0.0
		for l: Variant in Caravans.trade_partners(w, town):
			await _checkpoint("HerdsMarket._drovers:loop")
			var o: Dictionary = w["towns"].get(String(l["id"]), {})
			if not TownEcon.has_econ(o) or not o["econ"].has("hd"):
				continue
			for k: Variant in HerdsMarket.GRAZE + ["oxen"]:
				await _checkpoint("HerdsMarket._drovers:loop")
				var have: Variant = int(Herds.H(e)["ofk"].get(k, 0))
				if have <= 0:
					continue
				var ph: Variant = Herds.price(e, k); var pd: Variant = Herds.price(o["econ"], k)
				if pd < ph * float(DV["margin"]):
					continue
				var n: Variant = mini(have, int(DV["head_hand"]) * int(b["workers"]))
				var v: Variant = float(n) * (pd - ph)
				if v > bv:
					bv = v; best = [String(l["id"]), k, float(l.get("dist", (o["pos"] as Vector2).distance_to(town["pos"])))]
		if best.is_empty():
			continue
		var k2: Variant = String(best[1])
		var dh: Variant = {"id": -1, "k": k2, "y": 0, "g": 0, "o": 0, "ow": "d", "oi": int(b["id"]), "ot": String(town["id"]), "fod": 0.0, "hun": 0,
			"lac": 0.0, "h0": 0, "d0": int(day), "led": {"b": 0, "in": 0, "out": 0, "sl": 0, "st": 0, "d": {}}, "pl": [], "t": 0}
		var cap: Variant = int(DV["head_hand"]) * int(b["workers"])
		var p: float = Herds.price(e, k2)
		var owner_names_scope: Array[Dictionary] = [{}]
		var other_owner_names: Dictionary = {}
		while cap > 0 and float(b["till"]) >= p:
			await _checkpoint("HerdsMarket._drovers:loop")
			var o2: Variant = HerdsMarket._take_offer(e, k2, ["g", "y"])
			if o2.is_empty():
				break
			var s: Dictionary = Herds.herds(e)[str(int(o2[0]))]
			var pa: Variant = Herds.price(e, k2, String(o2[1]))
			if Herds._transfer(e, s, dh, String(o2[1]), 1, "sold", "bought", "to %s, for %s" % [Businesses.title(e, b, owner_names_scope), String(w["towns"][String(best[0])]["name"])],
					"from %s of %s" % [Herds.owner_text(e, s, HerdsMarket._herd_owner_names(s, owner_names_scope, other_owner_names)), String(town["name"])], day) > 0:
				b["till"] = float(b["till"]) - pa
				Herds._add_coin(e, s, pa)
				Herds.H(e)["sok"][k2] = int(Herds.H(e)["sok"].get(k2, 0)) + 1
				cap -= 1
		if Herds.head(dh) <= 0:
			continue
		var did2: Variant = "dv%d" % int(w.get("drove_n", 1))
		w["drove_n"] = int(w.get("drove_n", 1)) + 1
		w["droves"][did2] = {"id": did2, "h": dh, "from": String(town["id"]), "to": String(best[0]), "b": int(b["id"]), "d0": int(day),
			"days": maxi(1, int(ceil(float(best[2]) / float(DV["px_day"]))))}
		HerdsMarket._chain(b, "to", String(w["towns"][String(best[0])]["name"]), Herds.head(dh), k2)

func _herdsviews_assign_tiles(e: Dictionary, P: Dictionary) -> void:
	await _checkpoint("HerdsViews.assign_tiles:enter")
	var past: Variant = []
	for i: Variant in Plots.count(P):
		await _checkpoint("HerdsViews.assign_tiles:loop")
		if int(P["use"][i]) == Plots.PASTURE:
			past.append(i)
	var hd: Variant = Herds.H(e)
	var tiles: Variant = {}
	for hid: Variant in hd["h"]:
		await _checkpoint("HerdsViews.assign_tiles:loop")
		hd["h"][hid]["pl"] = []
		hd["h"][hid]["opl"] = []
		hd["h"][hid]["cs"] = 0.0
	await _herdsviews_pens(e, P)
	var fams: Array = e["fams"]
	# the acres each grazing family's herds need
	var need: Variant = {}   # fid -> acres
	var by_f: Variant = {}   # fid -> [herds]
	for hid: Variant in hd["h"]:
		await _checkpoint("HerdsViews.assign_tiles:loop")
		var h: Dictionary = hd["h"][hid]
		var k: Variant = String(h["k"])
		if not HerdsViews.GRAZE.has(k) or Herds.head(h) <= 0 or h.has("work_band"):
			continue
		var fid: Variant = Herds.grazer(e, h)
		if fid < 0:
			continue
		need[fid] = float(need.get(fid, 0.0)) + Herds.ge(h) * float(Herds.kind(k)["feed"])
		if not by_f.has(fid):
			by_f[fid] = []
		by_f[fid].append(h)
	var cap: Variant = float(Herds.A()["common_cap"])
	if not P.get("past_own", false):
		P["past_own"] = true
		if int(e.get("day", 0)) <= 0:   # world gen only: the big herds' families own their pasture
			var fids: Array = need.keys()
			fids.sort()
			var at: Variant = 0
			for fid: Variant in fids:
				await _checkpoint("HerdsViews.assign_tiles:loop")
				if int(fid) == 0 or float(need[fid]) <= cap:
					continue
				var nt: Variant = int(round(float(need[fid]) / float(Plots.ACRES)))
				for j: Variant in nt:
					await _checkpoint("HerdsViews.assign_tiles:loop")
					if at >= past.size():
						break
					P["own"][past[at]] = int(fid)
					at += 1
	for i: Variant in past:
		await _checkpoint("HerdsViews.assign_tiles:loop")
		var o: Variant = int(P["own"][i])
		if o > 0 and (o >= fams.size() or fams[o].get("gone", false)):
			P["own"][i] = Plots.TOWN
	var own_ac: Variant = {}
	var common: Variant = []
	for i: Variant in past:
		await _checkpoint("HerdsViews.assign_tiles:loop")
		P["ten"][i] = -1
		var o2: Variant = int(P["own"][i])
		if o2 > 0:
			if by_f.has(o2):
				P["ten"][i] = o2
				own_ac[o2] = float(own_ac.get(o2, 0.0)) + float(P["ac"][i])
				await _herdsviews_give_tile(by_f[o2], i, tiles, true)
		else:
			common.append(i)
	# common plots: each family's stint (its right to graze, in acres: what its herds needed when it was first
	# counted, at most the cap; the town's own herds what they need), shared out by largest remainder
	if not hd.has("stint"):
		hd["stint"] = {}
	var stint: Dictionary = hd["stint"]
	for sk: Variant in stint.keys():
		await _checkpoint("HerdsViews.assign_tiles:loop")
		var sf0: Variant = int(sk)
		if sf0 >= fams.size() or fams[sf0].get("gone", false):
			stint.erase(sk)
	var rows: Variant = []
	var tot: Variant = 0.0
	var fids2: Array = need.keys()
	fids2.sort()
	var stot: Variant = 0.0
	for fid: Variant in fids2:
		await _checkpoint("HerdsViews.assign_tiles:loop")
		var left: Variant = float(need[fid]) - float(own_ac.get(fid, 0.0))
		if int(fid) != 0:
			if not stint.has(str(int(fid))):
				stint[str(int(fid))] = snappedf(clampf(left, 0.0, cap), 0.01)
			left = minf(left, cap)
		var stv: Variant = float(stint.get(str(int(fid)), maxf(0.0, left)))
		if left > 0.0:
			rows.append([int(fid), left, stv])
			tot += left
			stot += stv
	hd["cpool"] = common
	hd.erase("_pg"); hd.erase("_pa")
	var cac: Variant = 0.0
	for i: Variant in common:
		await _checkpoint("HerdsViews.assign_tiles:loop")
		cac += float(P["ac"][i])
	if tot > cac and stot > 0.0:   # more wanted than the common grows: each family by its stint
		for r0: Variant in rows:
			await _checkpoint("HerdsViews.assign_tiles:loop")
			r0[1] = float(r0[2]) * cac / stot
		tot = cac
	# each family's share of the common's grass (its capped need over the common, all of it when there is room),
	# split among its herds by their need
	for r: Variant in rows:
		await _checkpoint("HerdsViews.assign_tiles:loop")
		var sf: Variant = float(r[1]) / maxf(tot, maxf(1.0, cac))
		var fneed: Variant = 0.0
		for h2: Variant in by_f[int(r[0])]:
			await _checkpoint("HerdsViews.assign_tiles:loop")
			fneed += Herds.ge(h2) * float(Herds.kind(String(h2["k"]))["feed"])
		for h3: Variant in by_f[int(r[0])]:
			await _checkpoint("HerdsViews.assign_tiles:loop")
			h3["cs"] = snappedf(sf * Herds.ge(h3) * float(Herds.kind(String(h3["k"]))["feed"]) / maxf(0.0001, fneed), 0.000001)
	if common.is_empty() or tot <= 0.0:
		HerdsViews._tiles_done(hd, tiles)
		return
	var n_t: Variant = float(common.size()) * minf(1.0, tot / maxf(1.0, cac))
	var share: Variant = []
	var given: Variant = 0
	for r: Variant in rows:
		await _checkpoint("HerdsViews.assign_tiles:loop")
		var q: Variant = n_t * float(r[1]) / tot
		share.append([r[0], int(floor(q)), q - floor(q)])
		given += int(floor(q))
	var order: Variant = range(share.size())
	order.sort_custom(func(a: Variant, b: Variant) -> bool: return float(share[a][2]) > float(share[b][2]) if float(share[a][2]) != float(share[b][2]) else int(share[a][0]) < int(share[b][0]))
	for k: Variant in mini(int(round(n_t)) - given, order.size()):
		await _checkpoint("HerdsViews.assign_tiles:loop")
		share[order[k]][1] = int(share[order[k]][1]) + 1
	var at2: Variant = 0
	for s: Variant in share:
		await _checkpoint("HerdsViews.assign_tiles:loop")
		for j: Variant in int(s[1]):
			await _checkpoint("HerdsViews.assign_tiles:loop")
			if at2 < common.size():
				var i2: int = common[at2]
				P["ten"][i2] = int(s[0])
				await _herdsviews_give_tile(by_f[int(s[0])], i2, tiles)
				at2 += 1
	HerdsViews._tiles_done(hd, tiles)

func _herdsviews_give_tile(hl: Array, i: int, tiles: Dictionary, own: bool = false) -> void:
	await _checkpoint("HerdsViews._give_tile:enter")
	var best: Dictionary = {}
	var bv: Variant = INF
	for h: Variant in hl:
		await _checkpoint("HerdsViews._give_tile:loop")
		var have: Variant = float((h["pl"] as Array).size()) * float(Plots.ACRES)
		var v: Variant = have / maxf(0.01, Herds.ge(h) * float(Herds.kind(String(h["k"]))["feed"]))
		if v < bv:
			bv = v; best = h
	if not best.is_empty():
		(best["pl"] as Array).append(i)
		if own:
			(best["opl"] as Array).append(i)
		tiles[str(i)] = int(best["id"])

func _herdsviews_pens(e: Dictionary, P: Dictionary) -> void:
	await _checkpoint("HerdsViews._pens:enter")
	var hd: Variant = Herds.H(e)
	var first: Variant = {}
	for i: Variant in Plots.count(P):
		await _checkpoint("HerdsViews._pens:loop")
		if int(P["use"][i]) != Plots.HOME:
			continue
		var fid: Variant = int(P["ten"][i]) if int(P["ten"][i]) > 0 else int(P["own"][i])
		if fid > 0 and not first.has(fid):
			first[fid] = i
	var pens: Variant = {}
	for hid: Variant in hd["h"]:
		await _checkpoint("HerdsViews._pens:loop")
		var h: Dictionary = hd["h"][hid]
		if HerdsViews.GRAZE.has(String(h["k"])) or String(h["k"]) == "oxen" or String(h["ow"]) != "f" or Herds.head(h) <= 0:
			continue
		var p: Variant = int(first.get(int(h["oi"]), -1))
		if p >= 0:
			h["pl"] = [p]
			if not pens.has(str(p)):
				pens[str(p)] = String(h["k"])
	hd["pens"] = pens

func _livestockcare_feed_hens(e: Dictionary, day: float) -> void:
	await _checkpoint("LivestockCare.feed_hens:enter")
	for h: Variant in Herds.herds(e).values():
		await _checkpoint("LivestockCare.feed_hens:loop")
		if String(h["k"]) != "hens" or String(h["ow"]) != "f": continue
		var f: Dictionary = e["fams"][int(h["oi"])]
		var need: Variant = Herds.ge(h) * 0.12 * 7 # kg of grain/scraps per adult bird-day
		var scraps: Variant = minf(need, float(f.get("scraps_kg", 0)))
		f["scraps_kg"] = maxf(0, float(f.get("scraps_kg", 0)) - scraps)
		if e.has("sanitation"): e["sanitation"]["scraps_reused_kg"] = float(e["sanitation"].get("scraps_reused_kg", 0)) + scraps
		var rate: Variant = float(Families.daily_rates(e, f)["food"])
		var meal_kg: Variant = float(Herds.A()["kg_per_meal"])
		var requested: Variant = (need - scraps) / meal_kg
		var available: Variant = minf(float(e["hh"].get("grain", 0)), maxf(0, float(f["store"]["food"])) * rate)
		var meals: Variant = minf(requested, available)
		var carry: Variant = meals + float(h.get("grain_carry", 0))
		var taken: Variant = mini(int(floor(carry)), int(e["hh"].get("grain", 0)))
		h["grain_carry"] = carry - taken
		e["hh"]["grain"] = int(e["hh"].get("grain", 0)) - taken
		TownEcon.led(e, "used", "grain", taken)
		f["store"]["food"] = maxf(0, float(f["store"]["food"]) - meals / maxf(0.01, rate))
		var supplied: Variant = scraps + meals * meal_kg
		h["fed"] = minf(1, supplied / maxf(0.01, need))
		h["hun"] = maxi(0, int(h["hun"]) - 7) if supplied >= need else int(h["hun"]) + int(ceil(7 * (1 - float(h["fed"]))))
		if int(h["hun"]) > int(Herds.A()["starve_after"]):
			var supported: Variant = int(floor(supplied / (0.12 * 7)))
			var deaths: Variant = maxi(0, Herds.head(h) - supported)
			for age: Variant in Herds.AGES:
				await _checkpoint("LivestockCare.feed_hens:loop")
				var died: Variant = mini(deaths, int(h[age]))
				Herds.change(e, h, age, -died, "died", "starvation", day)
				deaths -= died

func _livestockcare_hive_week(e: Dictionary, day: float) -> void:
	await _checkpoint("LivestockCare.hive_week:enter")
	var season: Variant = Calendar.season_index(day)
	var flowers: Variant = float(e.get("land", {}).get("fruit", 0)) + float(e.get("crop_mix", {}).get("beans", 0)) + float(e.get("crop_mix", {}).get("peas", 0))
	var count: Variant = 0
	for f: Variant in e["fams"]:
		await _checkpoint("LivestockCare.hive_week:loop")
		count += int(f.get("hives", {}).get("count", 0))
	if count == 0 or season == 3: return
	# Each acre can supply one hive's weekly forage. Actual flowering land bounds production.
	var active: Variant = minf(float(count), flowers)
	for f: Variant in e["fams"]:
		await _checkpoint("LivestockCare.hive_week:loop")
		var h: Dictionary = f.get("hives", {})
		if h.is_empty() or f.get("gone", false): continue
		var forage: Variant = float(h["count"]) / count * active
		var honey: Variant = forage * 0.04 * 7
		var wax: Variant = forage * 0.004 * 7
		h["honey_kg"] += honey; h["wax_kg"] += wax
		var honey_meals: Variant = honey * float(Herds.A()["honey_meals"]) + float(h["carry_honey"])
		var wax_units: Variant = wax + float(h["carry_wax"])
		var out: Variant = {"grain": int(floor(honey_meals)), "wax": int(floor(wax_units))}
		h["carry_honey"] = honey_meals - int(out["grain"])
		h["carry_wax"] = wax_units - int(out["wax"])
		# Use the same owner-payment and goods ledger as herd products; hives themselves are never herd animals.
		var owner: Variant = {"ow": "f", "oi": f["id"], "k": "hens"}
		Herds._sell(e, owner, out, float(TownEcon.data()["market"]["broker_share"]))

