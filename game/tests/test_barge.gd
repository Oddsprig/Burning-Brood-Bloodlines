extends RefCounted
## The Barge economy model and the coinage (docs/specs/barge/01-05): the TESTS sections that are checkable headless.
##   part 1: coin conserved every day (cast - melted - drained = all holdings); a mint with no bars casts nothing;
##           melting only above 90% metal value and minting stops when bars cost more than the coin; PL rises past the
##           money need and with debasement; a town short of coin shows the coin shortage; world gen asymmetry report.
##   part 2: meat with no buyers falls in price; spoilage hot > cold; a full larder is Fed and does not flee; children
##           10-14 and elders work their shares, under 10 nothing.
##   part 3: every place is held by a register person; field hands are hired before porters; the labourer family of
##           5 covers staple, fuel and rent at base prices (margin by race); a Legendary footman earns base + 50.
##   part 4: no person appears without a birth; movers carry their purse and people to a real town.
## The 5-year sim report (per race, per year) is tests/diag_barge_years.gd (DIAG_DAYS=600).

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	_test_coin_conserved()
	_test_mint_and_melt()
	_test_price_level()
	_test_prices_spoilage()
	_test_households()
	_test_labour_and_pay()
	_test_people_and_movers()
	_test_world_gen()
	return fails

func _ids(w: Dictionary) -> Array:
	var ids: Array = w["towns"].keys()
	ids.sort()
	return ids

func _ledger_gap() -> float:
	var L: Dictionary = Game.world["coin"]
	return Barge.holdings(Game) - (float(L["cast"]) - float(L["melted"]) - float(L["drained"]))

# ---------------------------------------------------------------- part 1: coin
## The whole world (armies, caravans, wars, families, mints) for 60 days, checked every day.
func _test_coin_conserved() -> void:
	Game.new_game(2026)
	var worst := 0.0
	var worst_day := 0
	for d in 60:
		CampaignWorld.presim_step(Game, 1)
		var gap := absf(_ledger_gap())
		if gap > worst:
			worst = gap; worst_day = d + 1
	var L: Dictionary = Game.world["coin"]
	print("  coin over 60 days: cast %d, melted %d, drained %d, held %d; worst daily gap %.3f coins (day %d)" % [int(L["cast"]), int(L["melted"]),
		int(L["drained"]), int(Barge.holdings(Game)), worst, worst_day])
	check(worst < 1.0, "coin not conserved: cast - melted - drained differs from the holdings by %.2f on day %d" % [worst, worst_day])

func _mint_town(w: Dictionary) -> Dictionary:
	for tid in _ids(w):
		if w["towns"][tid]["econ"].has("mint_biz"):
			return w["towns"][tid]
	return {}

func _test_mint_and_melt() -> void:
	Game.new_game(4242)
	var w: Dictionary = Game.world
	var t := _mint_town(w)
	check(not t.is_empty(), "no mint in any realm's seat or mining town")
	if t.is_empty():
		return
	var e: Dictionary = t["econ"]
	var mb: Dictionary = e["biz"][int(e["mint_biz"])]
	mb["workers"] = int(mb["cap"])
	e["treasury"] = Barge.treasury_lines(e)["short"] * 0.5
	# This isolated mint fixture has an explicit world money deficit.
	w["coin"]["target"] = float(w["coin"]["cast"]) - float(w["coin"]["melted"]) - float(w["coin"]["drained"]) + 100000.0
	# no bars: nothing cast
	e["stock"]["copper_bars"] = 0
	e["stock"]["tin_bars"] = 0
	e["stock"]["bronze_bars"] = 0
	var c0 := float(w["coin"]["cast"])
	Barge.mint_day(Game, t, e)
	check(float(w["coin"]["cast"]) == c0, "a mint with zero bars cast coin")
	# bars and charcoal: it casts, the treasury keeps face minus metal
	e["stock"]["copper_bars"] = 200
	e["stock"]["tin_bars"] = 40
	e["stock"]["wood"] = 100
	var tr0 := float(e["treasury"])
	var g0 := _ledger_gap()
	Barge.mint_day(Game, t, e)
	var cast := float(w["coin"]["cast"]) - c0
	check(cast > 0.0, "a staffed mint with bars cast nothing")
	check(float(e["treasury"]) > tr0, "the treasury did not keep face minus metal")
	check(absf(_ledger_gap() - g0) < 0.01, "minting broke the coin ledger")
	print("  mint: cast %d coins for %d of metal (%.0f%% of face)" % [int(cast), int(cast / 1000.0 * Barge.metal_per_k(e)), Barge.metal_per_k(e) / 10.0])
	# bronze bars alone (coinage spec 2: "a mint takes real bronze bars plus charcoal"): it casts from them
	e["stock"]["copper_bars"] = 0
	e["stock"]["tin_bars"] = 0
	e["stock"]["bronze_bars"] = 60
	var cb := float(w["coin"]["cast"])
	var g2 := _ledger_gap()
	Barge.mint_day(Game, t, e)
	check(float(w["coin"]["cast"]) > cb and int(e["stock"]["bronze_bars"]) < 60, "a staffed mint with bronze bars cast nothing")
	check(absf(_ledger_gap() - g2) < 0.01, "minting from bronze broke the coin ledger")
	# bars dearer than the coin they make: no minting
	e["stock"]["copper_bars"] = 200
	e["stock"]["tin_bars"] = 40
	e["price"]["copper_bars"] = 400.0
	e["price"]["bronze_bars"] = 400.0
	var c1 := float(w["coin"]["cast"])
	Barge.mint_day(Game, t, e)
	check(float(w["coin"]["cast"]) == c1, "the mint cast though the metal cost more than the coin")
	e["price"]["bronze_bars"] = 180.0
	# melting only above 90% of face
	var m0 := float(w["coin"]["melted"])
	e["price"]["copper_bars"] = 140.0
	e["price"]["tin_bars"] = 160.0
	Barge.melt_day(Game, t, e)
	check(float(w["coin"]["melted"]) == m0, "coin melted at %.0f%% metal value" % (Barge.metal_per_k(e) / 10.0))
	e["price"]["copper_bars"] = 190.0   # 4.6 x 190 + 0.4 x 160 + 0.45 x 10 = 943 a thousand: over 90%
	var g1 := _ledger_gap()
	Barge.melt_day(Game, t, e)
	check(float(w["coin"]["melted"]) > m0, "no melting at %.0f%% metal value" % (Barge.metal_per_k(e) / 10.0))
	check(absf(_ledger_gap() - g1) < 0.01, "melting broke the coin ledger")

func _test_price_level() -> void:
	Game.new_game(777)
	var w: Dictionary = Game.world
	var fid := "middle_kingdom"
	var fac: Dictionary = w["factions"][fid]
	check(absf(float(fac["pl"]) - 1.0) < 0.001, "PL is not 1 at world start")
	# minting past the trade's need: twice the coin in the realm's towns -> the PL rises (2.5% a day toward index^0.6)
	for tid in fac["towns"]:
		var e: Dictionary = w["towns"][tid]["econ"]
		e["treasury"] = float(e["treasury"]) + float(e["cneed"])
		w["coin"]["cast"] = float(w["coin"]["cast"]) + float(e["cneed"])
		e["coin_now"] = TownEcon.town_gold(e)
	for d in 30:
		Barge.coin_day(Game, d)
	var pl1 := float(fac["pl"])
	check(pl1 > 1.2, "PL did not rise with twice the coin (%.2f)" % pl1)
	# debasement: trust falls, PL rises further
	var trust0 := float(fac["trust"])
	for tid in fac["towns"]:
		w["towns"][tid]["econ"]["debase"] = 0.3
	for d in 30:
		Barge.coin_day(Game, 30 + d)
	check(float(fac["trust"]) < trust0 and float(fac["pl"]) > pl1, "debasement did not lower trust / raise PL (trust %.2f, PL %.2f)" % [float(fac["trust"]), float(fac["pl"])])
	print("  price level: twice the coin -> PL %.2f after 30 days; debased 30%% -> trust %.2f, PL %.2f" % [pl1, float(fac["trust"]), float(fac["pl"])])
	# a town drained of coin: the coin shortage shows (labour demand and spending cut)
	var t: Dictionary = w["towns"][_ids(w)[0]]
	var e2: Dictionary = t["econ"]
	e2["coin_now"] = float(e2["cneed"]) * 0.5
	Barge.coin_day(Game, 61)
	check(Barge.shortage(e2) > 0.0, "a town with half its coin shows no coin shortage")
	print("  coin shortage at half the town's coin: %.2f" % Barge.shortage(e2))

# ---------------------------------------------------------------- part 2: prices, spoilage, households
func _test_prices_spoilage() -> void:
	Game.new_game(321)
	var w: Dictionary = Game.world
	var t: Dictionary = w["towns"][_ids(w)[0]]
	var e: Dictionary = t["econ"]
	# meat with no buyers falls in price
	e["stock"]["meat"] = 5000
	e["dem"]["meat"] = 0.0
	var p0 := float(e["price"]["meat"])
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	for i in 10:
		e["req"] = {}
		Barge.update_prices(t, rng, true)
	check(float(e["price"]["meat"]) < p0 * 0.8, "meat with no buyers did not fall (%.1f -> %.1f)" % [p0, float(e["price"]["meat"])])
	print("  meat with no buyers: %.1f -> %.1f coins a meal in 10 days" % [p0, float(e["price"]["meat"])])
	# spoilage: a hot town loses more of the same stock than a cold one
	var hot := Barge.spoil_frac("meat", Barge.spoil_rate(Barge.temp({"climate": "hot"}, 1)))
	var cold := Barge.spoil_frac("meat", Barge.spoil_rate(Barge.temp({"climate": "cold"}, 3)))
	check(hot > cold * 5.0, "hot summer spoilage %.4f not well above cold winter %.4f" % [hot, cold])
	check(Barge.spoil_frac("grain", 1.5) == 0.0, "grain (a staple) should keep")
	var c2 := e.duplicate(true)
	c2["climate"] = "cold"
	var h2 := e.duplicate(true)
	h2["climate"] = "hot"
	for x in [c2, h2]:
		x["stock"]["meat"] = 1000; x["barn"]["meat"] = 0; x["hh"]["meat"] = 0; x["carry"] = {}; x["led"]["spoil"] = {}
		TownEcon._spoil(x, TownEcon.data(), 1, {}, 3.0)
	var lc := int(c2["led"]["spoil"].get("meat", 0)); var lh := int(h2["led"]["spoil"].get("meat", 0))
	check(lh > lc, "the hot town's 1,000 meals of meat did not spoil faster than the cold town's (%d vs %d)" % [lh, lc])
	print("  spoilage of 1,000 meals of salted meat in 3 summer days: hot %d, cold %d" % [lh, lc])

func _test_households() -> void:
	Game.new_game(612)
	var w: Dictionary = Game.world
	var t: Dictionary = w["towns"][_ids(w)[0]]
	var e: Dictionary = t["econ"]
	var day := float(e.get("day", 0))
	# a full larder is Fed whatever the town's stage, and a fed family does not flee
	e["fstage"] = 4
	var f: Dictionary = {}
	for x in e["fams"]:
		if not x.has("estate") and Families.people(x) >= 3 and int(x["homes"]) > 0:
			f = x
			break
	f["store"]["food"] = 30.0
	f["hst"] = 0
	var st := Barge.family_stage(e, f, 7.0, 0.0, 30.0)
	check(st == 0, "a family with a full larder is not Fed in a town at stage 4 (stage %d)" % st)
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var left := false
	for i in 50:
		if Barge.maybe_flee(Game, t, e, f, 0, 7.0, rng, day):
			left = true
	check(not left, "a fed family fled")
	# the same family short for a week: Short at least; a hungry family may flee (0.4% x (stage - 1) a day)
	f["hst"] = 0; f["hacc"] = 0.0
	var st2 := Barge.family_stage(e, f, 7.0, 7.0, 0.0)
	check(st2 >= 3, "a week without staple is only stage %d" % st2)
	# children 10-14 work at 0.2 and elders at 0.15 of a hand; under 10 nothing
	var g: Dictionary = {}
	for x in e["fams"]:
		if not x.has("estate") and x.has("kp") and int(x["kids"]) >= 1:
			g = x
			break
	if not g.is_empty():
		var ab := People.ages(Persons.race_of(e))
		var sc := float(ab["adult"]) / 16.0
		var yd := People.year_days()
		g.erase("k1014")
		for p in Persons.kp(g):
			p[3] = int(day - 5.0 * sc * yd)   # all five years old
		var h0 := Barge.helper_hands(e, g, day)
		g.erase("k1014")
		Persons.kp(g)[0][3] = int(day - 12.0 * sc * yd)   # one twelve
		var h1 := Barge.helper_hands(e, g, day)
		check(absf(h1 - h0 - 0.2) < 0.001, "a child of 12 does not add 0.2 of a hand (%.2f -> %.2f)" % [h0, h1])
		check(absf(h0 - 0.15 * float(Persons.home_n(g, 2))) < 0.001, "children under 10 work or elders do not add 0.15 (%.2f)" % h0)
		var ea := Barge.eaters(e, g, day)
		check(float(ea[0]) < float(Families.people(g)), "children eat a full share")
	# the household's own share at the price: want multipliers
	var H: Dictionary = Barge.B()["household"]
	e["price"]["meat"] = 40.0
	e.erase("_wm")
	var dear := Barge.want_mult(e, "meat", H)
	check(absf(dear - 0.5) < 0.01, "meat at twice base: want x%.2f (expected 0.5, elasticity 1.0)" % dear)

# ---------------------------------------------------------------- part 3: labour and pay
func _test_labour_and_pay() -> void:
	Game.new_game(733)
	var w: Dictionary = Game.world
	for tid in _ids(w):
		var e: Dictionary = w["towns"][tid]["econ"]
		# every place held belongs to a register person at home: hands + jobs + casual <= adults at home
		var bad := 0
		for f in e["fams"]:
			if f["gone"] or f.has("estate") or not f.has("pp"):
				continue
			var at_home := 0   # grown-ups at home (for hire at the tavern still works at home)
			for p in Persons.pp(f):
				if int(p[6]) == 0 and String(p[4]) in ["", "hire", "reserve"]:
					at_home += 1
			var held: int = int(f["hands"]) + Families.job_total(f) + f.get("keeps", []).size()
			for j in f.get("cj", {}):
				held += int(f["cj"][j])
			if held > at_home:
				bad += 1
		check(bad == 0, "%s: %d families hold more places than they have people at home" % [w["towns"][tid]["name"], bad])
		# field hands are hired first (they pay 1.15 x the day wage): farm places lead the open list, ahead of every
		# trade that pays them no more; only a trade bidding more than the fields (scarce goods, v0.011) comes before
		Businesses.rebuild_open(e)
		var field_w := -1.0
		for bid in e["open"]:
			var b0: Dictionary = e["biz"][int(bid)]
			if b0["type"] == "farm" or b0["type"] == "estate":
				field_w = maxf(field_w, float(b0["wage"]))
		var seen_trade := false
		var order_ok := true
		for bid in e["open"]:
			var b1: Dictionary = e["biz"][int(bid)]
			var tp: String = b1["type"]
			if tp == "farm" or tp == "estate":
				if seen_trade:
					order_ok = false
			elif float(b1["wage"]) <= field_w:
				seen_trade = true
		check(order_ok, "%s: a trade paying no more than the fields is offered before the field hands" % w["towns"][tid]["name"])
	# the labourer family of 5 (1 earner at the day wage + spinning 20) covers staple, fuel and rent at base prices
	var G: Dictionary = TownEcon.data()["goods"]
	var lines := []
	for cul in ["middle", "northern", "orc", "goblin", "moon_elf"]:
		var e2 := {"culture": cul, "price": {}}
		var meal := 0.0
		var sh := Barge.staple_shares(e2, true)
		for g in sh:
			meal += float(sh[g]) * float(G[g]["price"])
		var eaters := 2.0 + 3.0 * 0.6   # two grown-ups, three children under 10
		var staple := eaters * 2.0 * meal * TownEcon.markup()
		var fuel := 0.5 * float(G["wood"]["price"]) * TownEcon.markup()
		var rent := Barge.rent_week({"price": {}}) / 7.0
		var income := float(Barge.B()["labour"]["base"]) + 20.0
		var margin := income - staple - fuel - rent
		lines.append("%s %d" % [cul, int(round(margin))])
		check(margin > 0.0, "%s labourer family of 5 short at base prices (margin %.1f)" % [cul, margin])
	print("  labourer family of 5 (day wage 100 + spinning 20) after staple, fuel and rent at base prices, coins a day: " + ", ".join(PackedStringArray(lines)))
	# a Legendary footman earns rank base + 50
	var u := Unit.create("human", "middle_kingdom")
	var it := Item.make("spear", "copper", 0) if DB.weapons.has("spear") else null
	if it != null:
		u.equip["main_hand"] = it
		var sk := String(it.tmpl().get("skill", "spear"))
		u.skills[sk] = 15
		var wg := Army.wage("army", 1, -1, u)
		check(absf(wg - 150.0) < 0.001, "a Legendary footman earns %.0f (soldier 100 + 50)" % wg)
		u.skills[sk] = 0
		check(absf(Army.wage("army", 1, -1, u) - 100.0) < 0.001, "an unskilled soldier does not earn 100")
		check(absf(Army.wage("army", 0, -1, u) - 70.0) < 0.001, "a recruit does not earn 70")
		print("  soldier pay: recruit %d, soldier %d, Legendary footman %d, sergeant %d coins a day" % [int(Army.wage("army", 0, -1, u)), int(Army.wage("army", 1, -1, u)),
			int(wg), int(Army.wage("army", 2, 2, u))])

# ---------------------------------------------------------------- part 4: people and movers
func _quiet(w: Dictionary) -> void:
	# This scenario runs only TownEcon's queue, so bands cannot move or fight.
	# Keep their real units: the weekly register sweep treats missing forces as
	# casualties, including off-duty militia who still work civilian jobs.
	w["work"] = []

func _test_people_and_movers() -> void:
	Game.new_game(901)
	var w: Dictionary = Game.world
	var live_before := Persons.live_uids(Game)
	_quiet(w)
	check(Persons.live_uids(Game) == live_before, "town-only isolation removed real registered units")
	var pop0 := 0; var b0 := 0; var d0 := 0
	for tid in w["towns"]:
		var e: Dictionary = w["towns"][tid]["econ"]
		pop0 += int(e["pop"]); b0 += int(e["stats"].get("births", 0)); d0 += int(e["stats"].get("deaths", 0))
	for i in 60:
		var d := int(w.get("last_day", 0)) + 1
		w["last_day"] = d
		Game.day = float(d)
		w["work"] = []
		TownEcon.queue_day(w, d)
		while not (w["work"] as Array).is_empty():
			var job: Array = w["work"].pop_front()
			TownEcon.do_job(Game, job)
	var pop1 := 0; var b1 := 0; var d1 := 0; var rows := 0
	var battle_deaths := 0
	for tid in w["towns"]:
		var e: Dictionary = w["towns"][tid]["econ"]
		battle_deaths += int(Census.deaths_by_cause(e).get("battle", 0))
		pop1 += int(e["pop"]); b1 += int(e["stats"].get("births", 0)); d1 += int(e["stats"].get("deaths", 0))
		for f in e["fams"]:
			if not f["gone"]:
				rows += Families.people(f)
	print("  60 days of the towns alone: population %d -> %d, births %d, deaths %d (rows hold %d)" % [pop0, pop1, b1 - b0, d1 - d0, rows])
	check(battle_deaths == 0, "town-only history recorded %d battle deaths without moving or fighting forces" % battle_deaths)
	# barge part 3 section 7: "land worked >= 90% in a normal year" is a measured outcome of the rules, reported here
	# (not tuned toward): the share of the towns' acres worked after these 60 days
	var land := 0.0; var worked := 0.0
	for tid in w["towns"]:
		var e2: Dictionary = w["towns"][tid]["econ"]
		for c in e2["land"]:
			land += float(e2["land"][c]); worked += float(e2["wacres"].get(c, 0.0))
	_land_capture(w)
	print("  land worked after 60 days: %.0f%% of %d acres (barge part 3 target: 90%% in a normal year%s)" % [100.0 * worked / maxf(1.0, land), int(land),
		"" if worked >= 0.9 * land else "; NOT MET"])
	check(pop1 - pop0 == (b1 - b0) - (d1 - d0), "people appeared or vanished without a birth or a death (%d -> %d, +%d -%d)" % [pop0, pop1, b1 - b0, d1 - d0])
	check(rows == pop1, "the towns' head counts (%d) and the family rows (%d) differ" % [pop1, rows])
	# a family moves: its people, purse and stores go with it to a real town; nothing made or lost
	var ids := _ids(w)
	var a: Dictionary = w["towns"][ids[0]]
	var b: Dictionary = {}
	for tid in ids:
		if tid != ids[0] and w["towns"][tid]["faction"] == a["faction"]:
			b = w["towns"][tid]
			break
	if b.is_empty():
		b = w["towns"][ids[1]]
	var f: Dictionary = {}
	for x in a["econ"]["fams"]:
		if not x.has("estate") and not x["gone"] and Families.serving(x) == 0 and Families.people(x) >= 2 and not Barge._away(x):
			f = x
			break
	var g0 := _ledger_gap()
	Families.settle(a["econ"], f)   # (move_family settles first: its land's earnings due so far go into the purse it carries)
	var purse := float(f["purse"])
	var exit_wages := 0.0
	for bid in f["jobs"]:
		var employer: Dictionary = a["econ"]["biz"][int(bid)]
		exit_wages += minf(maxf(0.0, float(employer["till"])), float(employer.get("wage_claims", {}).get(str(int(f["id"])), 0.0)))
	var n := Families.people(f)
	var pa := int(a["econ"]["pop"]); var pb := int(b["econ"]["pop"])
	var nf := Barge.move_family(Game, a, f, b, "hunger", Game.day)
	check(f["gone"] and not nf["gone"] and absf(float(nf["purse"]) - purse - exit_wages) < 0.001, "the moving family carries its purse and the earned wages paid by employers on departure")
	check(int(a["econ"]["pop"]) == pa - n and int(b["econ"]["pop"]) == pb + n and Families.people(nf) == n, "people lost or made on the road")
	check(Persons.pp(nf).size() + Persons.kp(nf).size() >= n, "the movers' person records did not come along")
	check(absf(_ledger_gap() - g0) < 0.01, "moving broke the coin ledger")
	print("  movers: the %s family (%d people, %d coins) walked from %s to %s" % [nf["name"], n, int(purse), a["name"], b["name"]])

# ---------------------------------------------------------------- part 1: world gen asymmetry (report)
func _test_world_gen() -> void:
	Game.new_game(2026)
	var w: Dictionary = Game.world
	var rows := []
	for tid in _ids(w):
		var t: Dictionary = w["towns"][tid]
		var e: Dictionary = t["econ"]
		var cls := [0, 0, 0]
		var purses := []
		for f in e["fams"]:
			if f.has("estate"):
				continue
			cls[int(f.get("cls", 0))] += 1
			purses.append(float(f["purse"]))
		purses.sort()
		rows.append("    %-14s %-8s sz%d %-9s deposits %s classes poor/mid/rich %d/%d/%d purse p50 %d treasury %d mint %s ruler %s/%s" % [t["name"],
			e["climate"], int(t["size"]), String(TownEcon.culture_of(e)["race"]), str((e["deposits"] as Dictionary).keys()), cls[0], cls[1], cls[2],
			int(purses[purses.size() / 2]), int(e["treasury"]), "yes" if e.has("mint_biz") else "no", e["ruler"]["temper"], e["ruler"]["kind"]])
		check(cls[2] >= 1 and cls[0] > cls[1], "%s: class mix" % t["name"])
	print("  world gen (seed 2026):")
	for r in rows:
		print(r)


func _land_capture(w: Dictionary) -> void:
	if OS.get_environment("LAND_CAPTURE") == "": return
	var data := {"day": Game.day, "towns": []}
	for tid in w["towns"]:
		var e: Dictionary = w["towns"][tid]["econ"]
		var town := {"id": tid, "land": e["land"], "worked": e["wacres"], "families": [], "adults": 0, "serving": 0, "need_hands": 0.0, "own_hands": 0, "hired": 0, "helpers": 0.0, "keepers": 0, "idle": 0, "paid_other": 0, "casual": 0}
		for f in e["fams"]:
			if f.get("gone", false): continue
			town["adults"] += Families.adults(f); town["serving"] += Families.serving(f)
			town["need_hands"] += Families.need_hands(f); town["own_hands"] += int(f["hands"])
			town["keepers"] += f.get("keeps", []).size(); town["idle"] += int(f.get("idle", 0))
			for j in f.get("cj", {}): town["casual"] += int(f["cj"][j])
			for k in f["jobs"]:
				var job: Dictionary = e["biz"][int(k)]
				town["hired" if job["type"] in ["farm", "estate"] else "paid_other"] += int(f["jobs"][k])
			if not f.get("estate", false): town["helpers"] += minf(Families.need_hands(f), Barge.helper_hands(e, f, float(e["day"])))
			var acres := Families.acres(f)
			if acres <= 0: continue
			var need := Families.need_hands(f)
			var helpers := 0.0 if f.get("estate", false) else minf(need, Barge.helper_hands(e, f, float(e["day"])))
			var bid := int(f.get("farm", -1))
			var b: Dictionary = e["biz"][bid] if bid >= 0 else {}
			var hired := int(b.get("workers", 0))
			var own := int(f["hands"])
			if not f.get("estate", false): hired = mini(hired, maxi(0, int(ceil(need - own - helpers - 0.3))))
			var full := minf(1.0, (own + hired + helpers) / need) if need > 0 else 0.0
			var expected := full * (1.0 if f.get("estate", false) else Barge.output_mult(int(f.get("hungry", 0))))
			town["families"].append({"id": f["id"], "estate": f.get("estate", false), "acres": acres, "need": need, "own": own, "helpers": helpers, "hired": hired, "worked": f["worked"], "expected": expected, "unfed": f.get("hungry", 0), "adults": Families.adults(f), "idle": f.get("idle", 0), "serving": Families.serving(f), "cap": b.get("cap", 0), "till": b.get("till", 0), "funded": Businesses.takeable(b) if not b.is_empty() else 0, "wage": b.get("wage", 0)})
		data["towns"].append(town)
	var file := FileAccess.open(OS.get_environment("LAND_CAPTURE"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data)); file.close()
