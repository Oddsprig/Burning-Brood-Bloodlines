extends RefCounted
## Herds and their businesses (docs/specs/barge/13-addendum-1-state-buildings-herds.md part B5, headless):
##   - every animal belongs to exactly one herd with an owner (records against the families' totals and oxen);
##   - herd counts change only by births, deaths with a cause, slaughter, sale or theft, and every change is logged
##     (each record's ledger closes on its head; the log's whats and causes);
##   - butcher output = animals slaughtered x yield;
##   - a pasture never carries more than it can feed; when fodder runs out, deaths are logged as starved;
##   - old saves get records from their totals; save/load keeps them; the plot card and the screens read them.
## Prints the herd numbers after a season and a year of the world's own sim (no tuning: rule zero).

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_save_herds_%d.json" % OS.get_process_id()
	_test_gen()
	_test_year()
	_test_butcher()
	_test_pasture_and_starving()
	_test_old_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	return fails

func _towns() -> Array:
	var ids: Array = Game.world["towns"].keys()
	ids.sort()
	return ids.map(func(i): return Game.world["towns"][i]).filter(func(t): return TownEcon.has_econ(t))

## Every record has a live owner; the families' grazing totals and oxen are the records' sums; no record is in two
## places (each id once per town; droves on the road are in no town).
func _owners_ok(t: Dictionary) -> String:
	var e: Dictionary = t["econ"]
	var fams: Array = e["fams"]
	var sums := {}
	for hid in Herds.herds(e):
		var h: Dictionary = Herds.herds(e)[hid]
		if str(int(h["id"])) != String(hid):
			return "%s record %s filed under %s" % [t["name"], str(h["id"]), hid]
		for a in Herds.AGES:
			if int(h[a]) < 0:
				return "%s record %s has %d %s" % [t["name"], hid, int(h[a]), a]
		match String(h["ow"]):
			"f", "s":
				var fid := int(h["oi"])
				if fid < 0 or fid >= fams.size():
					return "%s record %s owned by no family (%d)" % [t["name"], hid, fid]
				if String(h["ow"]) == "f" and fams[fid].get("gone", false) and Herds.head(h) > 0 and int(e["day"]) > 0:
					pass   # (a family that left this week: its beasts go to the town at the herd week)
				var key := "%d|%s" % [fid, String(h["k"])]
				sums[key] = int(sums.get(key, 0)) + Herds.head(h)
			"b":
				if int(h["oi"]) < 0 or int(h["oi"]) >= (e["biz"] as Array).size():
					return "%s record %s owned by no business" % [t["name"], hid]
			"d":
				if not Game.world["towns"].has(String(h.get("ot", ""))):
					return "%s drove herd %s of no town" % [t["name"], hid]
			_:
				return "%s record %s has no owner kind" % [t["name"], hid]
	for f in fams:
		if f.get("gone", false):
			continue
		var fid2 := int(f["id"])
		for k in Herds.GRAZE:
			var want := int(f["herd"].get(k, 0))
			var have := int(sums.get("%d|%s" % [fid2, k], 0))
			if want != have:
				return "%s family %d %s: total %d, records %d" % [t["name"], fid2, k, want, have]
		var ox := int(sums.get("%d|oxen" % fid2, 0))
		if maxi(0, int(f.get("ox", 0))) != ox:
			return "%s family %d oxen: f.ox %d, records %d" % [t["name"], fid2, int(f.get("ox", 0)), ox]
	return ""

## Each record's ledger closes on its head; the town's total does too (live records + the gone ledger).
func _ledgers_ok(t: Dictionary) -> String:
	var e: Dictionary = t["econ"]
	for hid in Herds.herds(e):
		var h: Dictionary = Herds.herds(e)[hid]
		if Herds.ledger_head(h) != Herds.head(h):
			return "%s record %s (%s): head %d, ledger %d" % [t["name"], hid, h["k"], Herds.head(h), Herds.ledger_head(h)]
	for r in e["hd"]["log"]:
		if not Herds.WHATS.has(String(r[4])):
			return "%s log entry with no known change: %s" % [t["name"], str(r)]
		if String(r[4]) == "died" and String(r[5]) == "":
			return "%s death logged without a cause: %s" % [t["name"], str(r)]
		if int(r[3]) == 0:
			return "%s empty log entry %s" % [t["name"], str(r)]
	return ""

func _test_gen() -> void:
	Game.new_game(2026)
	var n := 0; var kinds := {}; var trades := {}
	for t in _towns():
		var e: Dictionary = t["econ"]
		check(Herds.has(e), "%s has no herd records" % t["name"])
		var why := _owners_ok(t)
		check(why == "", "gen: " + why)
		var why2 := _ledgers_ok(t)
		check(why2 == "", "gen: " + why2)
		n += (Herds.herds(e) as Dictionary).size()
		for k in Herds.town_heads(e):
			kinds[k] = int(kinds.get(k, 0)) + int(Herds.town_heads(e)[k])
		for b in e["biz"]:
			if String(b["type"]) in ["herder", "butcher", "salter", "dairy", "chandler", "saltworks", "drover"]:
				trades[String(b["type"])] = int(trades.get(String(b["type"]), 0)) + 1
		# pasture plots go to herds: a tile maps to a live herd of the family P.ten names
		var P := Plots.of(t)
		for i in Plots.count(P):
			if int(P["use"][i]) != Plots.PASTURE:
				continue
			var hid := int(e["hd"]["tiles"].get(str(i), -1))
			if hid >= 0:
				var h: Dictionary = Herds.herds(e).get(str(hid), {})
				check(not h.is_empty() and Herds.grazer(e, h) == int(P["ten"][i]), "%s pasture %d: tile and tenant differ" % [t["name"], i])
	check(int(kinds.get("oxen", 0)) > 0 and int(kinds.get("hens", 0)) > 0, "world gen made no oxen or hens records: %s" % str(kinds))
	for k in ["butcher", "salter", "chandler", "herder"]:
		check(int(trades.get(k, 0)) > 0, "no %s anywhere at world gen" % k)
	print("  world gen: %d herd records; head %s; trades %s" % [n, str(kinds), str(trades)])

## A year of the world's own sim: the books close every season; the herd numbers.
func _test_year() -> void:
	var w: Dictionary = Game.world
	for season in 4:
		CampaignWorld.presim_step(Game, Calendar.DAYS_PER_SEASON)
		for t in _towns():
			var why := _owners_ok(t)
			check(why == "", "season %d: %s" % [season, why])
			var why2 := _ledgers_ok(t)
			check(why2 == "", "season %d: %s" % [season, why2])
	var heads := {}; var book := {"died": {}}
	var bk := 0
	for t in _towns():
		var e: Dictionary = t["econ"]
		for k in Herds.town_heads(e):
			heads[k] = int(heads.get(k, 0)) + int(Herds.town_heads(e)[k])
		var b := Herds.book(e, "tot")
		for k in b:
			if k == "died":
				for c in b["died"]:
					book["died"][c] = int(book["died"].get(c, 0)) + int(b["died"][c])
			else:
				book[k] = int(book.get(k, 0)) + int(b[k])
		for x in e["biz"]:
			if String(x["type"]) == "butcher":
				bk += int(x.get("kills", 0))
	# the cost of a town's herd week (one work job = one map frame): printed
	var worst := 0; var sum := 0; var n := 0
	for t in _towns():
		var t0 := Time.get_ticks_usec()
		Herds.week(Game, t, Game.day)
		var dt := Time.get_ticks_usec() - t0
		worst = maxi(worst, dt); sum += dt; n += 1
	print("  PERF herd week job: mean %.2f ms, worst %.2f ms over %d towns" % [float(sum) / maxf(1.0, n) / 1000.0, worst / 1000.0, n])
	check(int(book.get("born", 0)) > 0, "no beast born in a year")
	check(int(book.get("slaughtered", 0)) > 0, "no beast slaughtered in a year")
	print("  after a year: head %s" % str(heads))
	print("  the year's herd book: %s (butchers' kills %d; droves on the road %d)" % [str(book), bk, (w.get("droves", {}) as Dictionary).size()])

## Butcher output = animals slaughtered x yield (the kinds' data rows by age).
func _test_butcher() -> void:
	var t: Dictionary = {}
	var b: Dictionary = {}
	for tt in _towns():
		for x in tt["econ"]["biz"]:
			if String(x["type"]) == "butcher" and not x.get("closed", false):
				t = tt; b = x
				break
		if not b.is_empty():
			break
	check(not b.is_empty(), "no butcher to test")
	if b.is_empty():
		return
	var e: Dictionary = t["econ"]
	# one herd offers its grown beasts; the market and the butcher can pay
	var h: Dictionary = {}
	for hid in Herds.herds(e):
		var x2: Dictionary = Herds.herds(e)[hid]
		if Herds.GRAZE.has(String(x2["k"])) and int(x2["g"]) >= 4:
			h = x2
			break
	if h.is_empty():
		h = Herds.new_herd(e, "pigs", "s", 0, float(e["day"]))
		Herds.change(e, h, "g", 6, "bought", "a test pen", float(e["day"]))
	e["hd"]["of"] = [[int(h["id"]), "g", 3, ""]]
	b["till"] = 1.0e7
	e["biz"][int(e["mkt"])]["till"] = 1.0e7
	e["dem"]["fresh_meat"] = 1.0e5   # the salters want all of it
	e["price"]["fresh_meat"] = 40.0
	var made0 := (e["led"]["made"] as Dictionary).duplicate()
	var oc0 := (b["oc"] as Dictionary).duplicate()
	var sl0 := int(h["led"]["sl"])
	Herds.butcher_day(e, b, 5.0, 1.0, e["biz"][int(e["mkt"])], 0.9, {})
	var killed := int(h["led"]["sl"]) - sl0
	check(killed == 3, "the butcher killed %d of the 3 offered" % killed)
	var yl := Herds.yields(String(h["k"]), "g")
	check(yl.has("fresh_meat"), "no meat in a %s" % h["k"])
	var made := {}
	for g in yl:
		var got := int(e["led"]["made"].get(g, 0)) - int(made0.get(g, 0))
		var want := int(floor(float(oc0.get(g, 0.0)) + float(killed) * float(yl[g]) + 0.000001))
		check(got == want, "butcher %s: made %d, want %d (%d slaughtered x %.2f)" % [g, got, want, killed, float(yl[g])])
		made[g] = got
	print("  butcher: %d %s slaughtered -> %s (yield a head %s)" % [killed, h["k"], str(made), str(yl)])

## The controlled fodder fixture records a real external lender when ownership
## accounts exist; directly replacing the count would leave claims for other goods.
func _set_test_fodder(e: Dictionary, amount: int) -> void:
	if ResourceLoader.exists("res://campaign/harvest_claims.gd"):
		var claims = load("res://campaign/harvest_claims.gd")
		claims.lose(e, "fodder", int(e["barn"].get("fodder", 0)))
		claims.add(e, "fodder", amount, {"f:0": 1.0}, int(e["day"]), "test lender")
	else:
		e["barn"]["fodder"] = amount

## A crowded pasture: what is eaten never passes what grows; the unfed starve once fodder runs out (logged).
func _test_pasture_and_starving() -> void:
	var t: Dictionary = {}
	var h: Dictionary = {}
	for tt in _towns():
		for hid in Herds.herds(tt["econ"]):
			var x: Dictionary = Herds.herds(tt["econ"])[hid]
			if String(x["k"]) == "cattle" or String(x["k"]) == "sheep":
				if not (x.get("opl", []) as Array).is_empty() and String(x["ow"]) == "f":   # a herd on its owners' own pasture
					t = tt; h = x
					break
		if not h.is_empty():
			break
	check(not h.is_empty(), "no grazing family herd with pasture")
	if h.is_empty():
		return
	var e: Dictionary = t["econ"]
	var P := Plots.of(t)
	Herds.change(e, h, "g", Herds.head(h) * 4 + 50, "bought", "a test crowd", float(e["day"]))
	h["fod"] = 0.0
	e["fams"][int(h["oi"])]["purse"] = 0.0
	_set_test_fodder(e, 0)
	e["stock"]["fodder"] = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# no coin but straw in the barns: the family borrows it (the grain loan, for fodder), owed x1.5
	_set_test_fodder(e, 100000)
	Herds._feed_all(e, P, 3, float(e["day"]), RandomNumberGenerator.new())
	var owed := float(e["hd"].get("floan", {}).get(str(int(h["oi"])), 0.0))
	check(owed > 0.0 and int(h["hun"]) == 0, "a family with no coin did not borrow straw from the barns (owed %.1f, hungry %d days)" % [owed, int(h["hun"])])
	print("  fodder loan: the %s owe %.0f bales" % [e["fams"][int(h["oi"])]["name"], owed])
	_set_test_fodder(e, 0)
	e["hd"]["floan"] = {}
	e["hd"]["floan_claims"] = {}; e["hd"]["floan_unknown"] = {}
	var died0 := int(h["led"]["d"].get("starved", 0))
	for wk in 4:   # winter: no grass, no hay, no coin: the herd goes hungry, then starves
		Herds._feed_all(e, P, 3, float(e["day"]) + wk * 7.0, rng)
	check(int(h["led"]["d"].get("starved", 0)) > died0, "a herd with no fodder and no grass did not starve (hungry %d days)" % int(h["hun"]))
	var logged := 0
	for r in e["hd"]["log"]:
		if int(r[1]) == int(h["id"]) and String(r[4]) == "died" and String(r[5]) == "starved":
			logged -= int(r[3])
	check(logged == int(h["led"]["d"].get("starved", 0)) - died0 or logged > 0, "starved deaths not in the log")
	for wk2 in 2:   # summer: the crowd grazes what grows and no more
		Herds._feed_all(e, P, 1, float(e["day"]) + 28.0 + wk2 * 7.0, rng)
		for k in e["hd"]["pgz"]:
			var g: Array = e["hd"]["pgz"][k]
			check(float(g[0]) <= float(g[1]) + 0.0001, "plot %s grazed %.2f a day, grows %.2f" % [k, float(g[0]), float(g[1])])
	var c := Herds.cond(e, int(h["opl"][0]))
	check(c < 1.0, "a pasture grazed to the full kept its condition (%.2f)" % c)
	check(Herds.ledger_head(h) == Herds.head(h), "the crowded herd's ledger does not close")
	# the plot card reads the herd
	var card := Plots.card(Game, t, int(h["opl"][0]))
	var txt := "\n".join(PackedStringArray(card["lines"]))
	check(txt.contains("carries") and txt.contains("grown"), "the pasture card shows no herd: " + txt)
	print("  crowded pasture: %d starved, condition %.2f; card: %s" % [int(h["led"]["d"].get("starved", 0)) - died0, c, txt.replace("\n", " | ")])

## Old saves: the records come from the families' totals; save/load keeps the records and their ints.
func _test_old_save() -> void:
	Game.new_game(321)
	var w: Dictionary = Game.world
	CampaignWorld.presim_step(Game, 14)
	var t: Dictionary = _towns()[0]
	var e: Dictionary = t["econ"]
	var heads0 := Herds.town_heads(e)
	Game.save_game()
	check(Game.load_game(), "load failed")
	var t2: Dictionary = Game.world["towns"][String(t["id"])]
	var e2: Dictionary = t2["econ"]
	check(Herds.town_heads(e2) == heads0, "herds changed over save/load: %s -> %s" % [str(heads0), str(Herds.town_heads(e2))])
	for hid in Herds.herds(e2):
		check(typeof(Herds.herds(e2)[hid]["g"]) == TYPE_INT, "herd counts not ints after load")
		break
	CampaignWorld.presim_step(Game, 7)   # a herd week runs on the loaded records
	check(_ledgers_ok(t2) == "", "after load: " + _ledgers_ok(t2))
	# an old save: no records at all
	for tid in Game.world["towns"]:
		var tt: Dictionary = Game.world["towns"][tid]
		if TownEcon.has_econ(tt):
			tt["econ"].erase("hd")
	Herds.after_load(Game)
	for tt2 in _towns():
		var why := _owners_ok(tt2)
		check(why == "", "old save migration: " + why)
		check(Herds.has(tt2["econ"]), "old save: %s got no records" % tt2["name"])
	CampaignWorld.presim_step(Game, 7)
	for tt3 in _towns():
		check(_ledgers_ok(tt3) == "", "old save, a week on: " + _ledgers_ok(tt3))
	print("  save/load and an old save: records rebuilt from the totals (%s)" % str(Herds.town_heads(_towns()[0]["econ"])))
