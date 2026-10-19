class_name Herds
extends RefCounted
## Herds and their businesses (docs/specs/barge/13-addendum-1-state-buildings-herds.md part B; data economy.json
## "animals"). Every animal is counted in a herd RECORD: kind, head by age (young, grown, old), its owner (a family,
## a business, the state = the town estate, or a drover's walking herd) and the pasture or pen plots it uses. A herd
## changes ONLY through change() - births, deaths with a cause, slaughter, sale (bought / sold) and theft - and every
## change is written to the herd's own ledger, the town's tallies and the town's herd log.
##
## The economy's older per-family totals are MIRRORS of the records, kept by change(): f.herd {kind: head} for the
## grazing kinds (cattle, sheep, goats, pigs) of families and the town estate (so land, hands, loans, recruits and
## plots read the same numbers as before), f.ox for the draft oxen (barge part 3: 8 acres a hand with an ox), and the
## town's e.herd / e.wherd sums. Families.move_herd / move_land (the land market, forced sales, a house dying out)
## call moved() so the records follow (one line each).
##
## e["hd"] = {v, n (next id), h {str(id): herd}, pr {kind: price of a grown head}, of [[hid, age, n]] offers,
##   ofk / wak / sok {kind: head offered / wanted / sold last week}, log [[day, hid, kind, n, what, detail]],
##   tot / yr / ly {what: {kind: n}} all-time / this year / last year, y (the year), pc {str(plot): pasture condition},
##   tiles {str(plot): hid}, dd {good: a day} daily deliveries paid ahead, dc carry, man (manure factor),
##   mt (manure tonnes a year, smoothed), plague {name: weeks left}, fodd (fodder days left, the town)}
## herd = {id, k, y, g, o, ow f|b|s|d, oi (family / business id; origin town's business for d), ot (origin town),
##   fod (own hay, bales), hun (days short), lac (females in milk), h0 (head when the record began), d0,
##   led {b born, in bought, out sold, sl slaughtered, st stolen, d {cause: n}}, pl [plot ids], t (target head)}

const GRAZE := ["cattle", "sheep", "goats", "pigs", "horses", "donkeys"]   # the economy's herds (f.herd mirrors); v0.012: horses, donkeys and mules
const AGES := ["y", "g", "o"]
const LOG_MAX := 300
const WHATS := ["born", "bought", "sold", "slaughtered", "stolen", "died"]
const OWN_WORDS := {"f": "family", "b": "business", "s": "the town", "d": "drover"}

static var _A: Dictionary = {}
static func A() -> Dictionary:
	if _A.is_empty():
		_A = TownEcon.data()["animals"]
	return _A

static func kind(k: String) -> Dictionary:
	return A()["kinds"].get(k, {})

static func kinds() -> Array:
	return (A()["kinds"] as Dictionary).keys()

static func has(e: Dictionary) -> bool:
	return e.has("hd")

static func H(e: Dictionary) -> Dictionary:
	if not e.has("hd"):
		e["hd"] = {"v": 1, "n": 1, "h": {}, "pr": {}, "of": [], "ofk": {}, "wak": {}, "sok": {}, "log": [], "tot": {}, "yr": {}, "ly": {},
			"y": 0, "pc": {}, "tiles": {}, "dd": {}, "dc": {}, "man": 1.0, "mt": 0.0, "plague": {}, "fodd": 0.0}
	return e["hd"]

static func herds(e: Dictionary) -> Dictionary:
	return H(e)["h"]

static func head(h: Dictionary) -> int:
	return int(h["y"]) + int(h["g"]) + int(h["o"])

## Grown-head equivalents (young eat and count half).
static func ge(h: Dictionary) -> float:
	return float(h["g"]) + float(h["o"]) + 0.5 * float(h["y"])

## Care comes from actual age/species records, once for their direct owner.
## Business and drover herds use their existing paid jobs instead. This derived
## owner index rebuilds on herd changes and is discarded when loading a save.
static func labour_hands(e: Dictionary, fid: int) -> float:
	var hd := H(e)
	var version := int(hd.get("ver", 0))
	if int(hd.get("_labour_ver", -1)) != version:
		var hands := {}
		for h in (hd["h"] as Dictionary).values():
			if not String(h["ow"]) in ["f", "s"]: continue
			var per_hand := float(kind(String(h["k"])).get("per_hand", 0))
			if per_hand <= 0.0: continue
			var owner := str(int(h["oi"]))
			hands[owner] = float(hands.get(owner, 0.0)) + ge(h) / per_hand
		hd["_labour"] = hands
		hd["_labour_ver"] = version
	return float(hd["_labour"].get(str(fid), 0.0))

## The kind's word in this town ("boars" for an orc town's pigs, "cave goats" for goblins).
static func word(e: Dictionary, k: String) -> String:
	var nm: Dictionary = A()["names"].get(String(e.get("culture", "middle")), {})
	return String(nm.get(k, kind(k).get("name", k)))

static func n_word(e: Dictionary, n: int, k: String) -> String:
	if n == 1:
		var one := String(kind(k).get("one", k))
		var nm: Dictionary = A()["names"].get(String(e.get("culture", "middle")), {})
		if nm.has(k):
			one = String(nm[k]).trim_suffix("s")
		return "one " + one
	return "%d %s" % [n, word(e, k)]

static func year_days() -> int:
	return 4 * Calendar.DAYS_PER_SEASON

## Price of a head of kind k by age in this town (grown: the town's price; young and old at the data's shares).
static func price(e: Dictionary, k: String, age: String = "g") -> float:
	var p := float(H(e)["pr"].get(k, float(kind(k).get("price", 100.0)) * Barge.pl(e)))
	if age == "y":
		return p * float(A()["young_price"])
	if age == "o":
		return p * float(A()["old_price"])
	return p

# ================================================================== records
static func new_herd(e: Dictionary, k: String, ow: String, oi: int, day: float, ot: String = "") -> Dictionary:
	var hd := H(e)
	var id := int(hd["n"])
	hd["n"] = id + 1
	var h := {"id": id, "k": k, "y": 0, "g": 0, "o": 0, "ow": ow, "oi": oi, "fod": 0.0, "hun": 0, "lac": 0.0, "h0": 0, "d0": int(day),
		"led": {"b": 0, "in": 0, "out": 0, "sl": 0, "st": 0, "d": {}}, "pl": [], "t": 0}
	if ot != "":
		h["ot"] = ot
	hd["h"][str(id)] = h
	hd["ver"] = int(hd.get("ver", 0)) + 1
	return h

## Herds of an owner (optionally of one kind).
static func of_owner(e: Dictionary, ow: String, oi: int, k: String = "") -> Array:
	var out := []
	for hid in herds(e):
		var h: Dictionary = herds(e)[hid]
		if String(h["ow"]) == ow and int(h["oi"]) == oi and (k == "" or String(h["k"]) == k):
			out.append(h)
	return out

static func of_family(e: Dictionary, fid: int) -> Array:
	return of_owner(e, "s" if fid == 0 else "f", fid)

## The family (or the town estate) whose purse a herd's owner spends, and whose land its herders live on.
static func grazer(e: Dictionary, h: Dictionary) -> int:
	match String(h["ow"]):
		"f", "s":
			return int(h["oi"])
		"b":
			var biz: Array = e.get("biz", [])
			return int(biz[int(h["oi"])]["owner"]) if int(h["oi"]) < biz.size() else -1
	return -1

## The ONE place a herd's head count changes: dn head of age `age` by `what` (born, bought, sold, slaughtered,
## stolen, died) with a detail (the cause of a death, who bought or sold, who stole). Writes the herd's ledger, the
## town's tallies and log, and the families' mirrors (mirror false: Families.move_herd / move_land already did).
## Returns the head actually changed (a loss never takes more than the age class holds).
static func change(e: Dictionary, h: Dictionary, age: String, dn: int, what: String, detail: String, day: float, mirror: bool = true) -> int:
	if dn == 0:
		return 0
	if dn < 0:
		dn = -mini(-dn, int(h[age]))
		if dn == 0:
			return 0
	h[age] = int(h[age]) + dn
	e["hd"]["ver"] = int(e["hd"].get("ver", 0)) + 1   # (the screens' cached head counts)
	var L: Dictionary = h["led"]
	match what:
		"born": L["b"] = int(L["b"]) + dn
		"bought": L["in"] = int(L["in"]) + dn
		"sold": L["out"] = int(L["out"]) - dn
		"slaughtered": L["sl"] = int(L["sl"]) - dn
		"stolen":
			if dn < 0:
				L["st"] = int(L["st"]) - dn
			else:
				L["in"] = int(L["in"]) + dn   # loot driven home counts in with the bought (a gain by theft, detail says so)
		"died":
			var dd: Dictionary = L["d"]
			dd[detail] = int(dd.get(detail, 0)) - dn
	var hd := H(e)
	var k := String(h["k"])
	var tkey := what if not (what == "stolen" and dn > 0) else "looted"
	var dkey := tkey if what != "died" else "died:" + detail
	for book in [hd["tot"], hd["yr"]]:
		var b: Dictionary = book
		if not b.has(dkey):
			b[dkey] = {}
		b[dkey][k] = int(b[dkey].get(k, 0)) + absi(dn)
	var lg: Array = hd["log"]
	lg.append([int(day), int(h["id"]), k, dn, what, detail])
	while lg.size() > LOG_MAX:   # while: drove thefts and purchases append straight to the log (long histories)
		lg.pop_front()
	if mirror:
		_mirror(e, h, dn)
	return dn

## Families' and the town's running totals follow the records (grazing kinds -> f.herd, oxen -> f.ox).
static func _mirror(e: Dictionary, h: Dictionary, dn: int) -> void:
	var ow := String(h["ow"])
	if ow != "f" and ow != "s":
		return
	var fams: Array = e["fams"]
	var fid := int(h["oi"])
	if fid < 0 or fid >= fams.size():
		return
	var f: Dictionary = fams[fid]
	var k := String(h["k"])
	if k == "oxen":
		f["ox"] = maxi(0, int(f.get("ox", 0))) + dn
		return
	if not GRAZE.has(k):
		return
	var fh: Dictionary = f["herd"]
	var nv := int(fh.get(k, 0)) + dn
	if nv <= 0:
		fh.erase(k)
	else:
		fh[k] = nv
	if not e.has("herd"):
		e["herd"] = {}
	e["herd"][k] = maxi(0, int(e["herd"].get(k, 0)) + dn)
	if not e.has("wherd"):
		e["wherd"] = {}
	e["wherd"][k] = float(e["wherd"].get(k, 0.0)) + float(dn) * float(f.get("worked", 0.0))

## Moves head from one herd to another (a sale or a theft). The buyer's herd of the kind is found or made.
static func _transfer(e: Dictionary, from: Dictionary, to: Dictionary, age: String, n: int, what_from: String, what_to: String,
		det_from: String, det_to: String, day: float, mirror: bool = true) -> int:
	var got := -change(e, from, age, -n, what_from, det_from, day, mirror)
	if got > 0:
		var before := head(to)
		change(e, to, age, got, what_to, det_to, day, mirror)
		# sickness and immunity go with the beasts (sold, driven, left): mixed by head
		for key in ["inf", "imm"]:
			var src: Dictionary = from.get(key, {})
			var dst: Dictionary = to.get(key, {})
			if src.is_empty() and dst.is_empty():
				continue
			var ks := {}
			for d in src:
				ks[d] = true
			for d in dst:
				ks[d] = true
			for d in ks:
				dst[d] = snappedf((float(dst.get(d, 0.0)) * float(before) + float(src.get(d, 0.0)) * float(got)) / float(before + got), 0.0001)
			to[key] = dst
	return got

## The family or the estate's herd of a kind (made when it has none).
static func herd_for(e: Dictionary, fid: int, k: String, day: float) -> Dictionary:
	var l := of_owner(e, "s" if fid == 0 else "f", fid, k)
	if not l.is_empty():
		return l[0]
	return new_herd(e, k, "s" if fid == 0 else "f", fid, day)

## Who owns it, in words.
static func owner_text(e: Dictionary, h: Dictionary) -> String:
	match String(h["ow"]):
		"f":
			return Plots.owner_text(e, int(h["oi"]))
		"s":
			return "the town"
		"b":
			var biz: Array = e.get("biz", [])
			return Businesses.title(e, biz[int(h["oi"])]) if int(h["oi"]) < biz.size() else "a business"
		"d":
			var ot: Dictionary = Game.world.get("towns", {}).get(String(h.get("ot", "")), {})
			if TownEcon.has_econ(ot):
				var ob: Array = ot["econ"]["biz"]
				if int(h["oi"]) < ob.size():
					return "%s of %s" % [Businesses.title(ot["econ"], ob[int(h["oi"])]), String(ot["name"])]
			return "a drover"
	return "nobody"

## The coin purse a herd's owner spends from and earns into: [holder dict, key].
static func _acct(e: Dictionary, h: Dictionary) -> Array:
	match String(h["ow"]):
		"f":
			return [e["fams"][int(h["oi"])], "purse"]
		"s":
			return [e, "treasury"]
		"b":
			return [e["biz"][int(h["oi"])], "till"]
		"d":
			var ot: Dictionary = Game.world.get("towns", {}).get(String(h.get("ot", "")), {})
			if TownEcon.has_econ(ot) and int(h["oi"]) < (ot["econ"]["biz"] as Array).size():
				return [ot["econ"]["biz"][int(h["oi"])], "till"]
	return [e, "treasury"]

static func _coin(e: Dictionary, h: Dictionary) -> float:
	var a := _acct(e, h)
	return float(a[0][a[1]])

static func _add_coin(e: Dictionary, h: Dictionary, v: float) -> void:
	if v > 0.0 and String(h["ow"]) == "f":
		var f: Dictionary = e["fams"][int(h["oi"])]
		if not Businesses.farm_of(e, f).is_empty():
			var surplus: float = v - Businesses.receive_farm(e, f, v)
			f["purse"] = float(f["purse"]) + surplus
			f["harvest_receipts"] = float(f.get("harvest_receipts", 0.0)) + surplus
			f["harvest_gross"] = float(f.get("harvest_gross", 0.0)) + v
			return
	var a := _acct(e, h)
	a[0][a[1]] = float(a[0][a[1]]) + v

## Register persons who tend the herd: the family's own herd hands (oxen: its plough hands), a herder's
## herdsmen, the town fields' hands for the estate's herds. [{fid, pid, name}]
static func herders(e: Dictionary, h: Dictionary) -> Array:
	var out := []
	match String(h["ow"]):
		"f":
			var f: Dictionary = e["fams"][int(h["oi"])]
			var wk := Persons.work(e, f)
			# Oxen still serve the plough hands; dedicated animal-care roles are
			# backed by the same real owner records, including oxen and poultry.
			var ox := String(h["k"]) == "oxen"
			var race := Persons.race_of(e)
			for pid in wk:
				if String(wk[pid]["kind"]) == "herd" or (ox and String(wk[pid]["kind"]) == "land"):
					var p := Persons.by_pid(f, int(pid))
					if not p.is_empty():
						out.append({"fid": int(f["id"]), "pid": int(pid), "name": Persons.name_of(f, p, race)})
			if out.is_empty() and not GRAZE.has(String(h["k"])):   # hens and hives: the household keeps them
				var hp := Persons.head_of(f)
				if not hp.is_empty():
					out.append({"fid": int(f["id"]), "pid": int(hp[0]), "name": Persons.name_of(f, hp, race)})
		"s":
			return Plots.staff_of_biz(e, int(e.get("estate_biz", -1)))
		"b":
			return Plots.staff_of_biz(e, int(h["oi"]))
	return out

# ================================================================== world gen and old saves
## World gen (one line in EconGen.generate, after the jobs): a record for every family's herd and oxen (the
## economy's totals of pre-history), the households' small stock (hens; the goblins' rats, the moon elves' hives),
## the town's biggest herd kept as a herder's business, the trades that process them (butcher, salter, dairy,
## chandler, salt works, drover), the animal prices and a little hay left from the winter. Own rng stream.
static func gen_town(w: Dictionary, town: Dictionary, e: Dictionary, D: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), String(town.get("id", "")), "herds"])
	H(e)
	_records_from_totals(e, 0.0, rng)
	LivestockCare.init_hives(e, rng)
	# Households' small stock, by culture: poultry, the goblins' rats and the moon elves' hives.
	var row: Dictionary = A().get("start", {}).get(String(e.get("culture", "middle")), A().get("start", {}).get("middle", {}))
	var small: Dictionary = row.get("small", {})
	var sks: Array = small.keys()
	sks.sort()
	for f in e["fams"]:
		if f.get("estate", false) or f.get("gone", false):
			continue
		for sk in sks:
			var sr: Array = small[sk]
			if kind(String(sk)).is_empty() or rng.randf() >= float(sr[0]):
				continue
			var h := new_herd(e, String(sk), "f", int(f["id"]), 0.0)
			_seed_ages(h, rng.randi_range(int(sr[1]), int(sr[2])), rng)
	# the town's biggest family herd is kept as a herder's business (it hires herdsmen)
	var best: Dictionary = {}
	var bh := 0
	for hid in herds(e):
		var h2: Dictionary = herds(e)[hid]
		if String(h2["ow"]) == "f" and GRAZE.has(String(h2["k"])) and head(h2) > bh:
			bh = head(h2); best = h2
	if not best.is_empty() and bh >= int(A()["herder_min"]):
		var fid := int(best["oi"])
		var hb: Dictionary = Businesses._row(e, "herder", fid, maxi(1, int(ceil(ge(best) / float(kind(String(best["k"]))["per_hand"])))), D)
		_mirror(e, best, -head(best))   # the family's totals drop it: the business owns it now
		best["ow"] = "b"; best["oi"] = int(hb["id"])
		H(e)["ver"] = int(H(e).get("ver", 0)) + 1
	_gen_trades(town, e, D, true, rng)
	for k in kinds():
		H(e)["pr"][k] = float(kind(k)["price"])
	# a little hay left at the end of winter (pre-history)
	for hid in herds(e):
		var h3: Dictionary = herds(e)[hid]
		h3["fod"] = snappedf(feed_day(h3) * float(A()["start_hay_days"]), 0.1)
		h3["t"] = head(h3)

## Old saves (and towns made later): records from the families' totals, the trades with empty tills (their keepers
## put coin in at their turns: no coin from nothing), prices at base x PL. No small stock is made up.
static func migrate(w: Dictionary, town: Dictionary, e: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), String(town.get("id", "")), "herds-load"])
	H(e)
	_records_from_totals(e, float(e.get("day", 0)), rng)
	_gen_trades(town, e, TownEcon.data(), false, rng)
	for k in kinds():
		H(e)["pr"][k] = float(kind(k)["price"]) * Barge.pl(e)
	for hid in herds(e):
		herds(e)[hid]["t"] = head(herds(e)[hid])
	Businesses.rebuild_open(e)

## One record per family per grazing kind (f.herd) and per family with oxen (f.ox), ages by the kind's life.
static func _records_from_totals(e: Dictionary, day: float, rng: RandomNumberGenerator) -> void:
	for f in e["fams"]:
		if f.get("gone", false):
			continue
		var fid := int(f["id"])
		var ow := "s" if f.get("estate", false) else "f"
		var ks: Array = (f["herd"] as Dictionary).keys()
		ks.sort()
		for k in ks:
			var n := int(f["herd"][k])
			if n <= 0 or kind(String(k)).is_empty():
				continue
			var h := new_herd(e, String(k), ow, fid, day)
			_seed_ages(h, n, rng)
		var ox := int(f.get("ox", 0))
		if ox > 0:
			var ho := new_herd(e, "oxen", ow, fid, day)
			var old := int(round(float(ox) * float(kind("oxen")["start_old"])))
			ho["o"] = old; ho["g"] = ox - old; ho["h0"] = ox

static func _seed_ages(h: Dictionary, n: int, rng: RandomNumberGenerator) -> void:
	var K := kind(String(h["k"]))
	var ys := float(K.get("start_young", 0.3)); var os := float(K.get("start_old", 0.1))
	var y := int(round(float(n) * ys * rng.randf_range(0.85, 1.15)))
	var o := int(round(float(n) * os * rng.randf_range(0.8, 1.2)))
	y = mini(y, n); o = mini(o, n - y)
	h["y"] = y; h["o"] = o; h["g"] = n - y - o; h["h0"] = n

## The trades that process the herds, sized by what the herds give (rows owned by families; the herder above).
static func _gen_trades(town: Dictionary, e: Dictionary, D: Dictionary, gen: bool, rng: RandomNumberGenerator) -> void:
	var have := {}
	for b in e["biz"]:
		have[String(b["type"])] = true
	var kg := 0.0; var milk := 0.0; var tallow := 0.0; var wax := 0.0; var graze := 0.0
	for hid in herds(e):
		var h: Dictionary = herds(e)[hid]
		var K := kind(String(h["k"]))
		var born := float(h["g"]) * float(K.get("fem", 0.0)) * float(K.get("bear", 0.0)) * float(K.get("litter", 0.0))
		kg += born * float(K.get("meat", 0.0)) * 0.75 / float(year_days())
		tallow += born * float(K.get("tallow", 0.0)) * 0.75 / float(year_days())
		milk += float(h["g"]) * float(K.get("fem", 0.0)) * float(K.get("bear", 0.0)) * float(K.get("milk", 0.0)) * float(K.get("milk_days", 0)) / float(year_days())
		wax += float(h["g"]) * float(K.get("wax", 0.0))
		if GRAZE.has(String(h["k"])):
			graze += float(head(h))
	var pool := Businesses.free_first(e, Businesses._owner_pool(e["fams"], rng))
	var oi := [0]
	var add := func(type: String, cap: int) -> void:
		if have.has(type) or cap <= 0 or pool.is_empty():
			return
		# v0.014: one shop per trade (before: rows of 6, so a big herding town had two butchers or salters)
		var b: Dictionary = Businesses._row(e, type, int(pool[oi[0] % pool.size()]), cap, D)
		oi[0] += 1
		have[type] = true
		if not gen:
			b["till"] = 0.0
	var BT: Dictionary = D["businesses"]
	var fresh_meals := kg / float(A()["kg_per_meal"])
	if kg > 0.0:
		add.call("butcher", maxi(1, int(ceil(kg / float(BT["butcher"]["kg_day"])))))
		add.call("salter", maxi(1, int(ceil(fresh_meals / (10.0 * float(BT["salter"]["recipes"][0]["rate"]))))))
		var tr: Dictionary = e.get("terrain", {})
		if tr.get("water", false) or tr.get("hills", false):
			add.call("saltworks", maxi(1, int(ceil(fresh_meals / 10.0 / (6.0 * float(BT["saltworks"]["recipes"][0]["rate"]))))))
	if milk > 0.5:
		add.call("dairy", maxi(1, int(ceil(milk / (4.0 * float(BT["dairy"]["recipes"][0]["rate"]))))))
	if tallow + wax > 0.05:
		add.call("chandler", maxi(1, int(ceil((tallow + wax) / float(BT["chandler"]["recipes"][0]["rate"])))))
	if graze >= float(A()["drover_min"]) and int(town.get("size", 0)) >= 1:
		add.call("drover", int(A()["drove"]["hands"]))

## Opening stocks of the new goods (one line in EconGen.generate after the opening stocks; pre-history): salt for
## a month of salting, candles in the homes, a little tallow.
static func opening_stocks(_town: Dictionary, e: Dictionary) -> void:
	var st: Dictionary = e["stock"]
	var meals := 0.0
	for hid in herds(e):
		var h: Dictionary = herds(e)[hid]
		var K := kind(String(h["k"]))
		meals += float(h["g"]) * float(K.get("fem", 0.0)) * float(K.get("bear", 0.0)) * float(K.get("litter", 0.0)) * float(K.get("meat", 0.0)) / float(A()["kg_per_meal"]) / float(year_days())
	st["salt"] = int(meals * 0.1 * 30.0) + 20
	st["tallow"] = int(meals * 0.02) + 5
	st["candles"] = int(float(e.get("homes", 0)) * 0.2)
	var hh: Dictionary = e["hh"]
	hh["candles"] = int(hh.get("candles", 0)) + int(e.get("homes", 0))

## After a load: JSON numbers back to ints, older saves migrated, prices for goods the save never had.
static func after_load(game) -> void:
	var w: Dictionary = game.world
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		var G: Dictionary = TownEcon.data()["goods"]
		for g in G:
			if not e["price"].has(g):
				e["price"][g] = float(G[g]["price"]) * Barge.pl(e)
			if not e["stock"].has(g):
				e["stock"][g] = 0
		if e.has("hd"):
			_fix(e["hd"])
			_remove_legacy_dogs(e["hd"])
		else:
			migrate(w, t, e)
	for did in w.get("droves", {}):
		var dv: Dictionary = w["droves"][did]
		_fix_herd(dv["h"])
		for k in ["d0", "days"]:
			dv[k] = int(dv[k])

## v0.020: dogs are no longer livestock. Drop their live records and market/plot references on load.
## Historical log entries and tallies remain history; no sale, death, money or replacement animals are invented.
static func _remove_legacy_dogs(hd: Dictionary) -> void:
	var removed := {}
	for hid in (hd["h"] as Dictionary).keys():
		if String(hd["h"][hid]["k"]) == "dogs":
			removed[int(hd["h"][hid]["id"])] = true
			hd["h"].erase(hid)
	for key in ["pr", "ofk", "wak", "sok", "_male"]:
		(hd.get(key, {}) as Dictionary).erase("dogs")
	(hd.get("plague", {}) as Dictionary).erase("distemper")
	var offers: Array = hd.get("of", [])
	for i in range(offers.size() - 1, -1, -1):
		if removed.has(int(offers[i][0])):
			offers.remove_at(i)
	var tiles: Dictionary = hd.get("tiles", {})
	for p in tiles.keys():
		if removed.has(int(tiles[p])):
			tiles.erase(p)
	var pens: Dictionary = hd.get("pens", {})
	for p in pens.keys():
		if String(pens[p]) == "dogs":
			pens.erase(p)

static func _fix(hd: Dictionary) -> void:
	hd["n"] = int(hd["n"]); hd["y"] = int(hd.get("y", 0)); hd["ver"] = int(hd.get("ver", 0))
	hd.erase("_th"); hd.erase("_thk"); hd.erase("_pg"); hd.erase("_pa")
	hd.erase("_labour"); hd.erase("_labour_ver")
	for hid in hd["h"]:
		_fix_herd(hd["h"][hid])
	var of: Array = hd.get("of", [])
	for o in of:
		o[0] = int(o[0]); o[2] = int(o[2])
	for r in hd.get("log", []):
		r[0] = int(r[0]); r[1] = int(r[1]); r[3] = int(r[3])
	for book in ["tot", "yr", "ly"]:
		var b: Dictionary = hd.get(book, {})
		for w2 in b:
			for k in b[w2]:
				b[w2][k] = int(b[w2][k])
	var tl: Dictionary = hd.get("tiles", {})
	for p in tl:
		tl[p] = int(tl[p])
	var cp: Array = hd.get("cpool", [])
	for i in cp.size():
		cp[i] = int(cp[i])
	for pk in hd.get("plague", {}):
		hd["plague"][pk] = int(hd["plague"][pk])

static func _fix_herd(h: Dictionary) -> void:
	for k in ["id", "y", "g", "o", "oi", "hun", "h0", "d0", "t"]:
		h[k] = int(h.get(k, 0))
	for k2 in ["da", "bred_s", "ls_n", "ls_day"]:
		if h.has(k2):
			h[k2] = int(h[k2])
	var L: Dictionary = h["led"]
	for k in ["b", "in", "out", "sl", "st"]:
		L[k] = int(L[k])
	for c in L["d"]:
		L["d"][c] = int(L["d"][c])
	for key in ["pl", "opl"]:
		var pl: Array = h.get(key, [])
		for i in pl.size():
			pl[i] = int(pl[i])

# ================================================================== the herds' week (a work job per town)
static func queue_day(w: Dictionary, d: int) -> void:
	var ids: Array = w["towns"].keys()
	ids.sort()
	for i in ids.size():
		if (d + i) % 7 == 5 and TownEcon.has_econ(w["towns"][ids[i]]):
			(w["work"] as Array).append(["herds", ids[i], d])
	if not (w.get("droves", {}) as Dictionary).is_empty():
		(w["work"] as Array).append(["droves", d])

static func do_job(game, job: Array) -> bool:
	var w: Dictionary = game.world
	match String(job[0]):
		"herds":
			if w["towns"].has(job[1]):
				week(game, w["towns"][job[1]], float(job[2]))
			return true
		"droves":
			droves_day(game, float(job[1]))
			return true
	return false

## The week: plague, ages, births, deaths, grazing and fodder, hunger, the unsold beasts, offers and live sales,
## drovers, prices, the products of the coming week, manure, the herders' places.
static func week(game, town: Dictionary, day: float) -> void:
	var e: Dictionary = town["econ"]
	if not e.has("hd"):
		migrate(game.world, town, e)
	var hd := H(e)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(game.world.get("seed", 0)), String(town["id"]), int(day), "herds"])
	var si := Calendar.season_index(day)
	var yr := Calendar.year(day)
	if yr != int(hd["y"]):
		hd["ly"] = hd["yr"]
		hd["yr"] = {}
		hd["y"] = yr
	hd.erase("_pg"); hd.erase("_pa")
	LivestockCare.feed_hens(e, day)
	_disease(e, rng, day)
	_males(e)
	_land_choice(e, Plots.of(town), day)
	var P := Plots.of(town)
	var ids: Array = (hd["h"] as Dictionary).keys()
	for hid in ids:
		var h: Dictionary = hd["h"][hid]
		_life(e, h, si, day, rng)
	_orphans(e, day)
	_feed_all(e, P, si, day, rng)
	HerdRaids.plan(game, town, day)
	_stockpile(e, si, day)
	_repay_loans(e)
	_unsold(e, si, day)
	_offers(e, si, day)
	_wants(game, town, e, si, day)
	_drovers(game, town, e, day)
	_prices(e)
	_products(e, si, day)
	LivestockCare.hive_week(e, day)
	_manure(e)
	_herder_caps(e)
	# empty records leave the list (their ledgers join the town's gone ledger; the log keeps what happened)
	for hid in (hd["h"] as Dictionary).keys():
		var h2: Dictionary = hd["h"][hid]
		if head(h2) <= 0:
			_retire(e, h2)

## Wolves and rustlers at the pastures (data animals.predators). Each
## wolf pack (a roaming band of wolves) within wolf_px of the town kills wolf_week head a wolf this week, each outlaw
## band within rustle_px drives off rustle_week head an outlaw (the beasts end in its stores as meat), from the herds
## out on the pastures (not drovers' herds, not pens, not the plough oxen on the fallow). A beast's chance to be taken
## by wolves goes as 1 / its feed (sheep, goats and pigs before cattle and horses; the young at half their kind's
## feed); rustlers take any head alike. Losses go through change() (died "wolves", stolen).
static func _predators(game, town: Dictionary, _e: Dictionary, day: float, _rng: RandomNumberGenerator) -> void:
	HerdRaids.plan(game, town, day)

static func _orphans(e: Dictionary, day: float) -> void:
	var fams: Array = e["fams"]
	for hid in (H(e)["h"] as Dictionary).keys():
		var h: Dictionary = herds(e)[hid]
		if String(h["ow"]) != "f" or head(h) <= 0:
			continue
		var fid := int(h["oi"])
		if fid > 0 and fid < fams.size() and not fams[fid].get("gone", false):
			continue
		var to := herd_for(e, 0, String(h["k"]), day)
		for age in AGES:
			if int(h[age]) > 0:
				_transfer(e, h, to, age, int(h[age]), "sold", "bought", "left to the town", "left by %s" % Plots.owner_text(e, fid), day)

## A finished record leaves the list; its ledger joins the town's gone ledger (the head sums still close).
static func _retire(e: Dictionary, h: Dictionary) -> void:
	var hd := H(e)
	if not hd.has("gone"):
		hd["gone"] = {"h0": 0, "b": 0, "in": 0, "out": 0, "sl": 0, "st": 0, "d": 0}
	var G: Dictionary = hd["gone"]
	var L: Dictionary = h["led"]
	G["h0"] = int(G["h0"]) + int(h["h0"])
	for k in ["b", "in", "out", "sl", "st"]:
		G[k] = int(G[k]) + int(L[k])
	for c in L["d"]:
		G["d"] = int(G["d"]) + int(L["d"][c])
	hd["h"].erase(str(int(h["id"])))

## Stochastic whole head from an expected number (seeded).
static func _whole(x: float, rng: RandomNumberGenerator) -> int:
	if x <= 0.0:
		return 0
	var n := int(floor(x))
	return n + (1 if rng.randf() < x - float(n) else 0)

## Share of a herd sick now (all its diseases).
static func sick(h: Dictionary) -> float:
	var s := 0.0
	var inf: Dictionary = h.get("inf", {})
	for d in inf:
		s += float(inf[d])
	return minf(1.0, s)

## The town's males of each kind against its females: the share of females they can serve (each male covers the
## kind's females_per_male; a herd without a male uses a neighbour's). hd._male {kind: 0..1}.
static func _males(e: Dictionary) -> void:
	var m := {}; var f := {}
	for hid in herds(e):
		var h: Dictionary = herds(e)[hid]
		var K := kind(String(h["k"]))
		if float(K.get("fpm", 0.0)) <= 0.0:
			continue
		var k := String(h["k"])
		m[k] = float(m.get(k, 0.0)) + float(h["g"]) * (1.0 - float(K["fem"])) * float(K["fpm"])   # (the grown males' share of the herd)
		f[k] = float(f.get(k, 0.0)) + float(h["g"]) * float(K["fem"])
	var out := {}
	for k in f:
		out[k] = snappedf(minf(1.0, float(m.get(k, 0.0)) / maxf(1.0, float(f[k]))), 0.001)
	H(e)["_male"] = out

## The owners' choice at each breeding season: how many females to put to the male. They breed to replace what
## dies and is used up in a year (one over the beast's life span, plus ailments) and to fill the room their pasture
## (or pen) has; when a young beast fetches less than the winter fodder to raise it, they breed only half the
## replacements [ours]. Returns the share of the herd's females bred (at least breed_min [ours]).
static func _bred_share(e: Dictionary, h: Dictionary, day: float) -> float:
	var K := kind(String(h["k"]))
	var n := head(h)
	var life := float(K.get("grow", 0.0)) + float(K["prime"]) + 1.0 / maxf(0.05, float(K["old_die"]))
	var repl := float(n) * (1.0 / maxf(0.1, life) + float(K["die"]))
	# what the herd really lost a year since the owners last chose (died, slaughtered, sold, stolen: its own ledger)
	var L: Dictionary = h["led"]
	var lost := int(L["out"]) + int(L["sl"]) + int(L["st"])
	for c in L["d"]:
		lost += int(L["d"][c])
	var since := maxf(0.25, (day - float(h.get("ls_day", h.get("d0", day)))) / float(year_days()))
	repl = maxf(repl, float(lost - int(h.get("ls_n", 0))) / since)
	h["ls_n"] = lost
	h["ls_day"] = int(day)
	var room := maxf(0.0, float(h.get("t", n)) - float(n))
	var raise := float(K.get("feed", 0.0)) * 0.5 * float(K.get("grow", 0.0)) * float(year_days()) * float(A()["winter_feed_share"]) \
		* float(e["price"].get("fodder", 3.0))
	var want := repl + room if price(e, String(h["k"]), "y") > raise else repl * 0.5
	var full := float(h["g"]) * float(K["fem"]) * float(K["bear"]) * float(K["litter"]) * float((K.get("seasons", [0]) as Array).size())
	return clampf(want / maxf(0.01, full), float(A()["breed_min"]), 1.0)

## Diseases of beasts at herd level (data animals.diseases): a herd has a share sick of each. A disease breaks out
## by the town's chance a year in a herd of its kinds; it spreads in the herd (faster crowded past what its land
## carries and hungry), to the herds grazing the common with it, and with beasts sold or driven (Herds._transfer).
## It kills a share of the sick a week (logged as sickness with its name); the sick get over it in the disease's
## weeks, a share of them immune after (immunity wanes over a year). Sick herds give less milk and wool, bear
## fewer young, and buyers pay less for them (none past no_sale).
static func _disease(e: Dictionary, rng: RandomNumberGenerator, day: float) -> void:
	var DS: Dictionary = A()["diseases"]
	var hd := H(e)
	var wk := 7.0 / float(year_days())
	# the common's pressure by disease and kind: the sick share of the beasts of that kind grazing it
	var csum := {}; var ctot := {}
	var any := false
	for hid in hd["h"]:
		var h: Dictionary = hd["h"][hid]
		if float(h.get("cs", 0.0)) > 0.0:
			ctot[String(h["k"])] = float(ctot.get(String(h["k"]), 0.0)) + float(head(h))
			for d in h.get("inf", {}):
				var key := "%s|%s" % [d, h["k"]]
				csum[key] = float(csum.get(key, 0.0)) + float(h["inf"][d]) * float(head(h))
		if not (h.get("inf", {}) as Dictionary).is_empty() or not (h.get("imm", {}) as Dictionary).is_empty():
			any = true
	# outbreaks
	for d in DS:
		if rng.randf() >= float(DS[d]["chance"]) * wk:
			continue
		var pool := []
		for hid in hd["h"]:
			if (DS[d]["kinds"] as Array).has(String(hd["h"][hid]["k"])) and head(hd["h"][hid]) > 0:
				pool.append(hid)
		if pool.is_empty():
			continue
		var h0: Dictionary = hd["h"][pool[rng.randi() % pool.size()]]
		if not h0.has("inf"):
			h0["inf"] = {}
		h0["inf"][d] = maxf(float(h0["inf"].get(d, 0.0)), float(A()["disease_seed"]))
		any = true
		TownEcon.town_hist(e, "%s broke out among %s." % [String(d).capitalize(), owner_text(e, h0)], day)
	if not any:
		return
	for hid in hd["h"].keys():
		var h: Dictionary = hd["h"][hid]
		var n := head(h)
		if n <= 0:
			continue
		var inf: Dictionary = h.get("inf", {})
		var imm: Dictionary = h.get("imm", {})
		for d in DS:
			var R: Dictionary = DS[d]
			if not (R["kinds"] as Array).has(String(h["k"])):
				continue
			var i := float(inf.get(d, 0.0))
			var im := float(imm.get(d, 0.0))
			var pres := 0.0
			if float(h.get("cs", 0.0)) > 0.0:
				pres = float(csum.get("%s|%s" % [d, h["k"]], 0.0)) / maxf(1.0, float(ctot.get(String(h["k"]), 1.0)))
			if i <= 0.0 and pres <= 0.0:
				continue
			var crowd := maxf(1.0, float(n) / maxf(1.0, float(h.get("t", n))))
			var hungry := float(A()["disease_hunger"]) if int(h["hun"]) > 0 else 1.0
			var s := maxf(0.0, 1.0 - i - im)
			i = minf(1.0 - im, i + s * (float(R["beta"]) * i + float(R["between"]) * pres) * crowd * hungry)
			var died := 0
			for age in AGES:
				var nd := _whole(float(h[age]) * i * float(R["kill"]), rng)
				if nd > 0:
					died -= change(e, h, age, -nd, "died", "sickness: %s" % String(d), day)
			var rec := i / maxf(1.0, float(R["weeks"]))
			i = maxf(0.0, i - rec - float(died) / maxf(1.0, float(n)))
			im = minf(1.0, im + rec * float(R["immune"]))
			if i < 0.005:
				inf.erase(d)
			else:
				inf[d] = snappedf(i, 0.0001)
			imm[d] = snappedf(im, 0.0001)
		for d2 in imm.keys():
			imm[d2] = float(imm[d2]) * (1.0 - float(A()["immune_fade"]) * wk)
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

## Ages, spring births, deaths by old age, ailments, plague and cold.
static func _life(e: Dictionary, h: Dictionary, si: int, day: float, rng: RandomNumberGenerator) -> void:
	var K := kind(String(h["k"]))
	var wk := 7.0 / float(year_days())
	# growing up and growing old (same beasts; no change of head)
	if float(K.get("grow", 0.0)) > 0.0 and int(h["y"]) > 0:
		var up := mini(int(h["y"]), _whole(float(h["y"]) * wk / float(K["grow"]), rng))
		h["y"] = int(h["y"]) - up; h["g"] = int(h["g"]) + up
		if up > 0: H(e)["ver"] = int(H(e).get("ver", 0)) + 1
	if int(h["g"]) > 0:
		var ol := mini(int(h["g"]), _whole(float(h["g"]) * wk / float(K["prime"]), rng))
		h["g"] = int(h["g"]) - ol; h["o"] = int(h["o"]) + ol
	# births by the kind's biology: in each of its breeding seasons (gestation decides how many a year fit), per grown
	# female the owners put to the male this year (h.bred, their choice), served by the town's males (each covers
	# the kind's females_per_male); a hungry herd bears fewer [ours: x0.5], a sick one by its healthy share
	var in_season := false
	for s0 in K.get("seasons", [0]):   # (JSON gives the seasons back as floats)
		if int(s0) == si:
			in_season = true
	if in_season and float(K.get("bear", 0.0)) > 0.0 and int(h["g"]) > 0:
		var stamp := Calendar.year(day) * 4 + si
		if int(h.get("bred_s", -1)) != stamp:
			h["bred"] = snappedf(_bred_share(e, h, day), 0.001)
			h["bred_s"] = stamp
		var mothers := float(h["g"]) * float(K["fem"]) * float(K["bear"]) * float(h["bred"]) * float(H(e).get("_male", {}).get(String(h["k"]), 1.0)) \
			* 7.0 / float(Calendar.DAYS_PER_SEASON)
		if int(h["hun"]) > 0:
			mothers *= 0.5
		mothers *= maxf(0.0, 1.0 - sick(h))
		var born := _whole(mothers * float(K["litter"]), rng)
		if born > 0:
			change(e, h, "y", born, "born", "", day)
			h["lac"] = float(h["lac"]) + mothers
	if float(h["lac"]) > 0.0:
		h["lac"] = maxf(0.0, float(h["lac"]) * (1.0 - 7.0 / maxf(7.0, float(K.get("milk_days", 7)))))
		h["lac"] = minf(float(h["lac"]), float(h["g"]) * float(K.get("fem", 0.0)))
	# deaths
	var pd := 1.0 - pow(1.0 - float(K["old_die"]), wk)
	var n_old := _whole(float(h["o"]) * pd, rng)
	if n_old > 0:
		change(e, h, "o", -n_old, "died", "old age", day)
	var pb := 1.0 - pow(1.0 - float(K["die"]), wk)
	for age in AGES:
		var n := _whole(float(h[age]) * pb, rng)
		if n > 0:
			change(e, h, age, -n, "died", "sickness: %s" % String(K.get("ail", "ailments")), day)
	if si == 3 and String(e.get("climate", "")) == "cold" and int(h["y"]) > 0:
		var n3 := _whole(float(h["y"]) * float(K.get("cold", 0.0)), rng)
		if n3 > 0:
			change(e, h, "y", -n3, "died", "cold", day)

## Where a herd's grass comes from this season: [[plot, bales a day]] for its own plots, [-1, its share of the
## common pool] (hd.cpool: the common plots; h.cs: the herd's share; h.opl: its owners' own plots).
static func _graze_parts(e: Dictionary, P: Dictionary, h: Dictionary, si: int) -> Array:
	var out := []
	var n := Plots.count(P)
	for i in h.get("opl", []):
		if int(i) < n and int(P["use"][int(i)]) == Plots.PASTURE:
			out.append([int(i), grass_day(e, P, int(i), si)])
	var cs := float(h.get("cs", 0.0))
	if cs > 0.0:
		out.append([-1, pool_grass(e, P, si) * cs])
	return out

## Bales a day the whole common grows this season (memo per season until the plots' condition changes).
static func pool_grass(e: Dictionary, P: Dictionary, si: int) -> float:
	var hd := H(e)
	if not hd.has("_pg"):
		hd["_pg"] = {}
	var key := str(si)
	if hd["_pg"].has(key):
		return float(hd["_pg"][key])
	var n := Plots.count(P)
	var pool := 0.0
	for i2 in hd.get("cpool", []):
		if int(i2) < n:
			pool += grass_day(e, P, int(i2), si)
	hd["_pg"][key] = pool
	return pool

## Bales a day the herd eats (grown head 1 x the kind's feed; young half).
static func feed_day(h: Dictionary) -> float:
	return ge(h) * float(kind(String(h["k"])).get("feed", 0.0))

## Bales a day a pasture plot grows this season (acres x season x its condition).
static func grass_day(e: Dictionary, P: Dictionary, i: int, si: int) -> float:
	return float(P["ac"][i]) * grass_of(e, si) * cond(e, i)

## Bales an acre of pasture grows a day this season in this town: the climate's grass by season (cold towns have a
## late spring and an early autumn, hot ones some winter grass) x the year's weather (the harvest factor: a drought
## year grows less grass as it grows less grain).
static func grass_of(e: Dictionary, si: int) -> float:
	var gc: Array = A()["grass_climate"].get(String(e.get("climate", "temperate")), A()["grass"])
	return float(gc[si]) * float(e.get("hf_now", 1.0))

## Days of the year a herd lives on stored feed in this town: each season's grass short of summer's, in days (the
## winter its owners stock hay for).
static func winter_days(e: Dictionary) -> float:
	var gc: Array = A()["grass_climate"].get(String(e.get("climate", "temperate")), A()["grass"])
	var pk := peak_season(e)
	var d := 0.0
	for s in 4:
		if s != pk:
			d += maxf(0.0, 1.0 - float(gc[s]) / maxf(0.01, float(gc[pk]))) * float(Calendar.DAYS_PER_SEASON)
	return d

## The season the town's grass grows most (summer in cold towns, spring where summer is dry): owners keep what
## their land carries then and stock hay for the leaner seasons.
static func peak_season(e: Dictionary) -> int:
	var gc: Array = A()["grass_climate"].get(String(e.get("climate", "temperate")), A()["grass"])
	var pk := 0
	for s in 4:
		if float(gc[s]) > float(gc[pk]):
			pk = s
	return pk

static func cond(e: Dictionary, i: int) -> float:
	return float(H(e)["pc"].get(str(i), 1.0))

## Head of kind k a plot can carry this season (its grass over a grown head's feed).
static func carry_head(e: Dictionary, P: Dictionary, i: int, k: String, si: int) -> int:
	var fd := float(kind(k).get("feed", 0.0))
	if fd <= 0.0:
		return 0
	return int(floor(grass_day(e, P, i, si) / fd))

## Grazing on the herd's own plots (oxen on their family's fallow and stubble), hay made of the spare grass in
## spring and summer, the shortfall from the herd's hay then bought fodder (barn, then market); what is still
## short is hunger. A pasture is never eaten past what it grows; grazed to the full it loses condition (it grows
## less next season), grazed lightly it recovers. Hungry past the data's days, the unfed share starves.
static func _feed_all(e: Dictionary, P: Dictionary, si: int, day: float, rng: RandomNumberGenerator) -> void:
	var hd := H(e)
	var pc: Dictionary = hd["pc"]
	var grazed := {}   # plot -> bales eaten a day
	var AA := A()
	var fod_need := 0.0; var fod_have := 0.0
	for hid in (hd["h"] as Dictionary).keys():
		var h: Dictionary = hd["h"][hid]
		var need := feed_day(h)
		if String(h["k"]) == "hens": continue
		if need <= 0.0 or String(h["ow"]) == "d":
			continue
		var K := kind(String(h["k"]))
		var grass := 0.0
		var parts := []
		if K.get("fallow", false):
			grass = need * float(AA["fallow"][si])
		elif not P.is_empty():
			parts = _graze_parts(e, P, h, si)
			for pp in parts:
				grass += float(pp[1])
		var eat := minf(need, grass)
		if grass > 0.0:
			for pp in parts:   # each plot (the common as one pool, -1) gives its share of what was eaten
				grazed[int(pp[0])] = float(grazed.get(int(pp[0]), 0.0)) + eat * float(pp[1]) / grass
		var short := (need - eat) * 7.0
		_fees(e, P, h)
		if si <= 1 and grass > need:   # hay from the spare grass (spring and summer)
			var cap := need * maxf(float(AA["hay_cap_days"]), winter_days(e))
			h["fod"] = minf(cap, float(h["fod"]) + (grass - need) * 7.0 * float(AA["hay_share"]))
		if short > 0.0:
			var own := minf(float(h["fod"]), short)
			h["fod"] = float(h["fod"]) - own
			short -= own
		if short > 0.0:
			short -= _buy_fodder(e, h, short)
		var fed := 1.0 - short / maxf(0.001, need * 7.0)
		if short > 0.01:
			h["hun"] = int(h["hun"]) + int(ceil(7.0 * (1.0 - fed)))
		else:
			h["hun"] = maxi(0, int(h["hun"]) - 7)
		if int(h["hun"]) > int(AA["starve_after"]) and fed < 1.0:
			for age in ["y", "o", "g"]:
				var n := _whole(float(h[age]) * (1.0 - fed) * float(AA["starve_k"]), rng)
				if n > 0:
					change(e, h, age, -n, "died", "starved", day)
		fod_need += need; fod_have += float(h["fod"])
	# pasture condition: grazed to its growth it wears; lightly grazed it mends
	var pgz := {}   # the week's grazing a day per plot: [eaten, grown] (tests: never more eaten than grown)
	if not P.is_empty():
		var pool_g := 0.0
		for i0 in hd.get("cpool", []):
			pool_g += grass_day(e, P, int(i0), si)
		var pool_ate := float(grazed.get(-1, 0.0))
		for i in Plots.count(P):
			if int(P["use"][i]) != Plots.PASTURE:
				continue
			var g := grass_day(e, P, i, si)
			var ate := float(grazed.get(i, 0.0))
			if int(P["own"][i]) <= 0 and pool_g > 0.0:   # the common: the pool's grazing by each plot's grass
				ate += pool_ate * g / pool_g
			if ate > 0.0:
				pgz[str(i)] = [ate, g]
			var c := cond(e, i)
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
	var fodder := float(e["barn"].get("fodder", 0)) + float(e["stock"].get("fodder", 0))
	hd["fodd"] = snappedf((fod_have + fodder) / maxf(0.01, fod_need), 0.1) if fod_need > 0.0 else 0.0
	hd["fneed"] = snappedf(fod_need, 0.1)

## Buys up to n bales: from the barns first (the field owners are paid per acre like any barn sale), then the
## market. Returns bales bought.
static func _buy_fodder(e: Dictionary, h: Dictionary, n: float, loan: bool = true, keep: float = 0.0) -> float:
	var want := int(ceil(n))
	var p := float(e["price"].get("fodder", 3.0)) * TownEcon.markup()
	var coin := _coin(e, h) - keep
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
		_add_coin(e, h, -v)
		HarvestClaims.credit(e, sale["shares"], v)
		got += q
	var st: Dictionary = e["stock"]
	var q2 := mini(mini(want - got, int(st.get("fodder", 0))), afford - maxi(0, q))
	if q2 > 0:
		st["fodder"] = int(st["fodder"]) - q2
		var v2 := float(q2) * p
		_add_coin(e, h, -v2)
		var mkt: Dictionary = e["biz"][int(e["mkt"])]
		mkt["till"] = float(mkt["till"]) + v2
		e["stats"]["sales"] = float(e["stats"].get("sales", 0.0)) + v2
		got += q2
	# barge part 2 section 7, the grain loan, for fodder [ours: the spec lends grain]: a family with no coin left
	# borrows straw from its well-off neighbours' barns, owed x1.5 in kind at its next cut (in coin when it has none)
	if loan and got < want and String(h["ow"]) == "f":
		var LN: Dictionary = A()["fodder_loan"]
		var key := str(int(h["oi"]))
		if not H(e).has("floan"):
			H(e)["floan"] = {}
		var owed := float(H(e)["floan"].get(key, 0.0))
		var room := int(maxf(0.0, feed_day(h) * float(LN["max_days"]) * float(LN["repay"]) - owed) / float(LN["repay"]))
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
			H(e)["floan"][key] = total_owed
			if not H(e).has("floan_claims"): H(e)["floan_claims"] = {}
			var creditors: Dictionary = H(e)["floan_claims"].get(key, {})
			if not H(e).has("floan_unknown"): H(e)["floan_unknown"] = {}
			H(e)["floan_unknown"][key] = maxf(0.0, owed - _fodder_claim_total(creditors))
			for lender in lender_shares:
				# Attribute the existing rounded debt exactly; rounding cannot create
				# a new unknown creditor or overstate the retained known claims.
				creditors[lender] = float(creditors.get(lender, 0.0)) + float(lender_shares[lender]) / maxf(0.00000001, external) * (total_owed - owed)
			H(e)["floan_claims"][key] = creditors
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
	var wd := winter_days(e)
	var weeks := maxf(1.0, (float((3 - si) * Calendar.DAYS_PER_SEASON) - float(Calendar.day_of_season(day))) / 7.0)
	for hid in herds(e):
		var h: Dictionary = herds(e)[hid]
		var fd := feed_day(h)
		if fd <= 0.0 or String(h["ow"]) == "d":
			continue
		var gap := fd * wd - float(h["fod"])
		if gap <= 1.0:
			continue
		var got := _buy_fodder(e, h, gap / weeks, false, float(A()["stock_reserve"]))
		h["fod"] = float(h["fod"]) + got

## Fodder loans repaid each herd week: in kind from the borrower's own straw (left in the barns for the lenders),
## else in coin at the fodder price above the buyer's reserve, to the retained lenders. A family
## gone from the town leaves its loan unpaid (hd.floan_lost).
static func _repay_loans(e: Dictionary) -> void:
	var hd := H(e)
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
		var pay := minf(owed * p, maxf(0.0, float(f["purse"]) - float(A()["buy_reserve"])))
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
	var hd := H(e)
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
	var hd := H(e)
	var of: Array = hd["of"]
	var cap := {}
	for o in of:
		var h: Dictionary = hd["h"].get(str(int(o[0])), {})
		if h.is_empty() or int(o[2]) <= 0:
			continue
		# what the owners could not sell they slaughter only as far as it is eaten (their larder) or sells (the
		# market's want of fresh meat); the rest they keep. A starving herd's surplus is killed for its hides
		# (the meat not dressed). A drover waits his days at market, then sells for slaughter what the town wants.
		if String(h["ow"]) == "d" and day - float(h.get("da", day)) < float(A()["drove"]["sell_days"]):
			continue
		var key := str(int(h["id"]))
		if not cap.has(key):
			cap[key] = _home_cap(e, h)
		var n := mini(int(o[2]), int(cap[key]))
		var meals := float(yields(String(h["k"]), String(o[1])).get("fresh_meat", 0.0))
		if int(h["hun"]) <= int(A()["starve_after"]) / 2 and meals > 0.0:
			var use := 0
			if sick(h) <= float(A()["disease_no_sale"]):
				use = maxi(0, int(float(e.get("need", {}).get("fresh_meat", 0.0)) * 1.2) - int(e["stock"].get("fresh_meat", 0)))
				if String(h["ow"]) == "f":
					use += larder_room(e, e["fams"][int(h["oi"])])
			n = mini(n, int(floor(float(use) / meals + 0.5)))   # a carcass when at least half of it is used
		if n <= 0:
			continue
		var got := -change(e, h, String(o[1]), -n, "slaughtered", "at home by the owners", day)
		cap[key] = int(cap[key]) - got
		_carcass(e, h, String(o[1]), got, true)
	hd["of"] = []

## Head a herd's owners can slaughter and dress at home in a week (their hands x the data's rate; small stock any).
static func _home_cap(e: Dictionary, h: Dictionary) -> int:
	var K := kind(String(h["k"]))
	var cpw := float(A()["home_kill_week"]) / maxf(0.05, float(K.get("feed", 0.05)) if float(K.get("feed", 0.0)) > 0.0 else 0.05)
	var hands := 1
	match String(h["ow"]):
		"f":
			hands = maxi(1, int(e["fams"][int(h["oi"])].get("hands", 1)))
		"b":
			hands = maxi(1, int(e["biz"][int(h["oi"])].get("workers", 1)))
		"s":
			hands = maxi(1, int(e["biz"][int(e.get("estate_biz", 0))].get("workers", 1)))
		"d":
			return head(h)   # the drover sells his unsold herd to the town's butchers' block
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
		if sick(h) <= float(A()["disease_no_sale"]):
			if String(h["ow"]) == "f":
				meat -= _to_larder(e, e["fams"][int(h["oi"])], meat)
			var want := maxi(0, int(float(e.get("need", {}).get("fresh_meat", 0.0)) * 1.2) - int(e["stock"].get("fresh_meat", 0)))
			if mini(meat, want) > 0:
				out["fresh_meat"] = mini(meat, want)
	_sell(e, h, out, float(D["market"]["broker_share"]) * (1.0 - sick(h)))
	return out

## Meals of meat a family's larder has room for (larder_days of its food at its meat share, less what it holds).
static func larder_room(e: Dictionary, f: Dictionary) -> int:
	var r := Families.daily_rates(e, f)
	return int(maxf(0.0, float(A()["larder_days"]) - float(f["store"].get("food", 0.0))) * float(r["food"]) * float(TownEcon.data()["needs"]["food_mix"]["meat"]))

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
			_add_coin(e, h, float(q) * p)
		if n - q > 0:
			HarvestClaims.add(e, String(g), n - q, {HarvestClaims.owner(h): 1.0}, int(e.get("day", 0)), "carcass")

## What each herd's owners offer this week (the market for live beasts): head beyond what the herd's pasture
## carries in summer (oxen beyond the family's plough; small stock beyond its start), the old in autumn and
## winter, and in autumn the head the winter fodder in reach cannot feed. Old first, then young, then grown.
static func _offers(e: Dictionary, si: int, day: float) -> void:
	var hd := H(e)
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
			straw_due += float(e.get("wacres", {}).get("grain", 0.0)) * float(A()["straw_acre"]) * float(s[1]) * (0.5 if int(s[0]) == si else 1.0)
	if si == 2:
		for hid0 in hd["h"]:
			var h0: Dictionary = hd["h"][hid0]
			if String(h0["ow"]) == "f" or String(h0["ow"]) == "s":
				fam_feed[int(h0["oi"])] = float(fam_feed.get(int(h0["oi"]), 0.0)) + feed_day(h0)
		for fid0 in fam_feed:
			var f0: Dictionary = e["fams"][int(fid0)]
			own_year[fid0] = float(f0["land"].get("grain", 0)) * float(A()["straw_acre"]) * float(f0.get("worked", 1.0))
	for hid in hd["h"]:
		var h: Dictionary = hd["h"][hid]
		var k := String(h["k"])
		var n := head(h)
		if n <= 0:
			continue
		if sick(h) > float(A()["disease_no_sale"]):   # nobody buys from a herd this sick
			continue
		if String(h["ow"]) == "d":   # a drover's herd at its market: every head is for sale
			for age0 in AGES:
				if int(h[age0]) > 0:
					of.append([int(h["id"]), age0, int(h[age0]), "d"])
					ofk[k] = int(ofk.get(k, 0)) + int(h[age0])
			continue
		var tgt := _target(e, h, P)
		h["t"] = tgt
		var surplus := maxi(0, n - tgt) if float(kind(k).get("meat", 0.0)) > 0.0 else 0   # swarms are kept (hives)
		# the old go in autumn and winter (an old ox ploughs on until a young one replaces it; old hives stay)
		var olds := int(h["o"]) if si >= 2 and k != "oxen" and float(kind(k).get("meat", 0.0)) > 0.0 else 0
		var flag := ""
		if si == 2 and feed_day(h) > 0.0 and k != "oxen":   # the autumn reckoning (the plough oxen are wintered first)
			# bales to winter the herd (autumn's shortfall and the winter), what it has (its hay, its owners' straw
			# for the year), what it can buy (its share of the town's hay and straw, now and the autumn cut to come,
			# paid from the purse and from selling the beasts it does not keep at half a grown head's price)
			var winter := feed_day(h) * winter_days(e)
			var per := winter / float(n)
			var share := (fod_in_reach + straw_due) * feed_day(h) / maxf(0.01, town_need)
			var pf := maxf(0.01, float(e["price"].get("fodder", 3.0)) * TownEcon.markup())
			var mine := 0.0
			if own_year.has(int(h["oi"])) and (String(h["ow"]) == "f" or String(h["ow"]) == "s"):
				mine = float(own_year[int(h["oi"])]) * feed_day(h) / maxf(0.01, float(fam_feed[int(h["oi"])]))
			var free := float(h["fod"]) + mine
			var v := price(e, k) * 0.5
			var keep_coin := (free * pf + maxf(0.0, _coin(e, h)) + float(n) * v) / (per * pf + v)
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
	var K := kind(k)
	if k == "oxen":
		if String(h["ow"]) == "f" or String(h["ow"]) == "s":
			var f: Dictionary = e["fams"][int(h["oi"])]
			return int(ceil(float(Families.acres(f)) / float(TownEcon.data()["land"]["acres_per_hand"])))
		return 0
	if float(K.get("feed", 0.0)) <= 0.0 or P.is_empty():
		return maxi(int(h.get("t", 0)), 1) if int(h.get("t", 0)) > 0 else head(h)
	var pk := peak_season(e)   # what the land carries at its best season (the lean ones are fed hay)
	var grass := float(h.get("cs", 0.0)) * pool_grass(e, P, pk)
	var n := Plots.count(P)
	for i in h.get("opl", []):
		if int(i) < n:
			grass += grass_day(e, P, int(i), pk)
	var per_head := float(K["feed"]) * (ge(h) / float(head(h)) if head(h) > 0 else 1.0)   # the herd's mix of young and grown
	return int(floor(grass / maxf(0.0001, per_head) * float(A()["keep_share"])))

## Live sales of the week: farm families short of oxen buy them (oxen offered, else grown cattle trained to the
## plough), herds far below what their pasture carries buy grown stock back; each at the town's price.
static func _wants(_game, _town: Dictionary, e: Dictionary, _si: int, day: float) -> void:
	var hd := H(e)
	var wak: Dictionary = hd["wak"]
	var aph := float(TownEcon.data()["land"]["acres_per_hand"])
	var reserve := float(A()["buy_reserve"])
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
				if _transfer(e, own, oxh0, "g", 1, "sold", "bought", "to the family's plough", "from the family's own herd", day) <= 0:
					break
				short -= 1
		for src in ["oxen", "cattle"]:
			if short <= 0:
				break
			var p := price(e, src)
			while short > 0 and float(f["purse"]) - p > reserve:
				var o := _take_offer(e, src, ["g"], int(f["id"]), -1, offers)
				if o.is_empty():
					break
				var seller: Dictionary = hd["h"][str(int(o[0]))]
				var oxh := _indexed_oxen(e, oxen, int(f["id"]), day)
				if _transfer(e, seller, oxh, "g", 1, "sold", "bought", "to the %s for the plough" % Backstory.plural(String(f["name"])),
						"from %s" % owner_text(e, seller), day) > 0:
					f["purse"] = float(f["purse"]) - p
					_add_coin(e, seller, p)
					hd["sok"][src] = int(hd["sok"].get(src, 0)) + 1
					short -= 1
	# restocking: a herd below half its keep buys grown stock of its kind
	for hid in (hd["h"] as Dictionary).keys():
		var h: Dictionary = hd["h"][hid]
		var k := String(h["k"])
		if not GRAZE.has(k) or String(h["ow"]) == "d":
			continue
		var need := int(float(h["t"]) * 0.5) - head(h)
		if need <= 0:
			continue
		need = mini(need, int(A()["restock_week"]))
		wak[k] = int(wak.get(k, 0)) + need
		var p2 := price(e, k)
		while need > 0 and _coin(e, h) - p2 > reserve:
			var o2 := _take_offer(e, k, ["g"], -1, int(h["id"]), offers)
			if o2.is_empty():
				break
			var s2: Dictionary = hd["h"][str(int(o2[0]))]
			if _transfer(e, s2, h, "g", 1, "sold", "bought", "to %s" % owner_text(e, h), "from %s" % owner_text(e, s2), day) > 0:
				_add_coin(e, h, -p2)
				_add_coin(e, s2, p2)
				hd["sok"][k] = int(hd["sok"].get(k, 0)) + 1
				need -= 1
	_pot_buys(e, day)

## Families buy a beast for their own larder when one offered costs less than the meat in it at the market's price
## of keeping meat (x pot_value [ours]), they have the room and the coin (keeping pot_reserve): live animals traded
## by families, so a glut of beasts feeds the town instead of rotting. The family slaughters it at once (logged:
## bought, then slaughtered for its pot). At most pot_week buys a town a week [ours].
static func _pot_buys(e: Dictionary, day: float) -> void:
	var hd := H(e)
	var mp := float(e["price"].get("meat", 20.0)) * float(A()["pot_value"])
	var cands := []
	for o in hd["of"]:
		if int(o[2]) <= 0:
			continue
		var h: Dictionary = hd["h"].get(str(int(o[0])), {})
		if h.is_empty() or GRAZE.find(String(h["k"])) < 0 and String(h["k"]) != "hens":
			continue
		var meals := float(yields(String(h["k"]), String(o[1])).get("fresh_meat", 0.0))
		var p := price(e, String(h["k"]), String(o[1]))
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
		if buys >= int(A()["pot_week"]) or ci >= cands.size():
			break
		var f: Dictionary = fams[(start + j) % fams.size()]
		if f.get("gone", false) or f.get("estate", false):
			continue
		var c: Array = cands[ci]
		var o: Array = c[1]
		if int(o[2]) <= 0:
			ci += 1
			continue
		if larder_room(e, f) < int(float(c[2]) * 0.5) or float(f["purse"]) - float(c[3]) < float(A()["pot_reserve"]):
			continue
		var seller: Dictionary = hd["h"][str(int(o[0]))]
		var k := String(seller["k"])
		var age := String(o[1])
		var mine := herd_for(e, int(f["id"]), k, day)
		if _transfer(e, seller, mine, age, 1, "sold", "bought", "to the %s for their pot" % Backstory.plural(String(f["name"])),
				"from %s" % owner_text(e, seller), day) <= 0:
			ci += 1
			continue
		o[2] = int(o[2]) - 1
		f["purse"] = float(f["purse"]) - float(c[3])
		_add_coin(e, seller, float(c[3]))
		hd["sok"][k] = int(hd["sok"].get(k, 0)) + 1
		change(e, mine, age, -1, "slaughtered", "for the family's pot", day)
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
	var hd := H(e)
	for age in ages:
		var offers: Array = hd["of"] if index.is_empty() else index.get(k, {}).get(String(age), [])
		for o in offers:
			if int(o[2]) <= 0 or String(o[1]) != String(age):
				continue
			var h: Dictionary = hd["h"].get(str(int(o[0])), {})
			if h.is_empty() or String(h["k"]) != k or int(h["id"]) == buyer_hid or int(h[String(age)]) <= 0:
				continue
			if buyer_fid >= 0 and grazer(e, h) == buyer_fid and String(h["ow"]) == "f":
				continue
			o[2] = int(o[2]) - 1
			return [int(o[0]), String(age)]
	return []

## _wants creates only new oxen records; add each to its pass-local index immediately.
static func _indexed_oxen(e: Dictionary, index: Dictionary, fid: int, day: float) -> Dictionary:
	if not index.has(fid):
		index[fid] = new_herd(e, "oxen", "s" if fid == 0 else "f", fid, day)
	return index[fid]

## The price of a grown head each week: base x PL x (wanted / offered)^the data's power, stepped toward it.
static func _prices(e: Dictionary) -> void:
	var hd := H(e)
	var pr: Dictionary = hd["pr"]
	var PP: Dictionary = A()["price"]
	for k in kinds():
		var base := float(kind(k)["price"]) * Barge.pl(e)
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
	var hd := H(e)
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
		var K := kind(String(h["k"]))
		var out := {}
		if float(K.get("milk", 0.0)) > 0.0 and float(h["lac"]) > 0.0:
			out["milk"] = float(h["lac"]) * float(K["milk"]) * 7.0 * (1.0 - sick(h))
		if float(K.get("wool", 0.0)) > 0.0 and si == 1:
			out["wool"] = float(h["g"]) * float(K["wool"]) * 7.0 / float(Calendar.DAYS_PER_SEASON) * (1.0 - sick(h))
		if float(K.get("eggs", 0.0)) > 0.0 and si <= 2:
			out["meat"] = float(h["g"]) * float(K.get("fem", 1.0)) * float(K["eggs"]) * 7.0 / float(A()["eggs_per_meal"]) * float(h.get("fed", 0))
		if float(K.get("honey", 0.0)) > 0.0 and si <= 2:
			out["grain"] = float(h["g"]) * float(K["honey"]) * float(A()["honey_meals"]) * 7.0
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
				_add_coin(e, h2, v)
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
	var hd := H(e)
	var t := 0.0
	for hid in hd["h"]:
		var h: Dictionary = hd["h"][hid]
		t += ge(h) * float(kind(String(h["k"])).get("manure", 0.0))
	hd["mt"] = snappedf(float(hd["mt"]) + (t - float(hd["mt"])) * 0.1, 0.01)
	var acres := 0.0
	for c in e.get("land", {}):
		acres += float(e["land"][c])
	var recovered := float(hd.get("human_manure_week", 0)) / 1000 * EconGen.YEAR_DAYS / 7
	var share := minf(1.0, (float(hd["mt"]) + recovered) / maxf(1.0, acres * float(A()["manure_acre"])))
	hd["man"] = snappedf(1.0 + float(A()["manure_yield"]) * share, 0.0001)

## The field yield factor from manure (one line in TownEcon._farms).
static func manure_f(e: Dictionary) -> float:
	return float(e["hd"].get("man", 1.0)) if e.has("hd") else 1.0

## Straw: the cereal cut gives dated fodder to its producers. One line in _farms.
static func straw(e: Dictionary, acres_cut: float) -> void:
	var carry: Dictionary = e["carry"]
	var previous := float(carry.get("straw", 0.0))
	var produced := acres_cut * float(A()["straw_acre"])
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
	var stw := float(land.get("grain", 0)) * float(A()["straw_acre"])
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
	gv += float(A()["straw_acre"]) * float(e["price"].get("fodder", 3.0))   # grain land gives straw too
	var fv := float(L["yield"].get("fodder", 0.0)) * float(e["price"].get("fodder", 3.0))
	var m := float(A()["land_switch"])
	var short := fodder_days(e) >= 0.0 and fodder_days(e) < float(A()["fodder_days_want"])
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
	for hid in herds(e):
		var h: Dictionary = herds(e)[hid]
		if String(h["ow"]) == "b":
			need[int(h["oi"])] = float(need.get(int(h["oi"]), 0.0)) + ge(h) / float(kind(String(h["k"])).get("per_hand", 25))
	for b in biz:
		if String(b["type"]) == "herder" and not b.get("closed", false):
			# cap is paid places, excluding the actual working family keeper.
			b["cap"] = maxi(0, int(ceil(float(need.get(int(b["id"]), 0.0)) - int(b.get("kw", 0)))))

## The common pasture's fee: grazing acres a herd uses on the town's common plots, a week, to the treasury.
static func _fees(e: Dictionary, P: Dictionary, h: Dictionary) -> void:
	if P.is_empty() or String(h["ow"]) == "s" or float(h.get("cs", 0.0)) <= 0.0:
		return
	var hd := H(e)
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
	var fee := minf(ac * float(A()["fee_acre_week"]) * Barge.pl(e), maxf(0.0, _coin(e, h)))
	if fee > 0.0:
		_add_coin(e, h, -fee)
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
	var aim_kg := maxf(0.0, aim) * float(A()["kg_per_meal"]) + 1.0
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
			var K := kind(String(h["k"]))
			var kg := float(K.get("meat", 0.0)) * float(A()["yield_age"][AGES.find(String(o[1]))])
			if kg <= 0.0: continue
			var v := _carcass_value(e, h, String(o[1])) * share - price(e, String(h["k"]), String(o[1]))
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
		var p := price(e, String(h2["k"]), age) * (1.0 - sick(h2))   # a sick herd's beasts fetch less
		var val := _carcass_value(e, h2, age) * share
		if val * float(Barge.B()["business"]["out_share"]) < float(Barge.B()["business"]["run_margin"]) * p:
			b["why"] = "no margin"
			break
		if float(b["till"]) < p:
			b["state"] = "wages"; b["why"] = "money for beasts"
			break
		var kg2 := float(kind(String(h2["k"])).get("meat", 0.0)) * float(A()["yield_age"][AGES.find(age)])
		if change(e, h2, age, -1, "slaughtered", "by %s" % Businesses.title(e, b), float(e.get("day", 0))) == 0:
			o2[2] = 0
			continue
		o2[2] = int(o2[2]) - 1
		b["till"] = float(b["till"]) - p
		_add_coin(e, h2, p)
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
		_chain(b, "from", owner_text(e, h2), 1, String(h2["k"]))
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
	var K := kind(k)
	var af := float(A()["yield_age"][AGES.find(age)])
	var out := {}
	var meals := float(K.get("meat", 0.0)) * af / float(A()["kg_per_meal"])
	if meals > 0.0:
		out["fresh_meat"] = meals
	for g in ["hides", "tallow", "bones", "horn", "sinew", "feathers"]:   # (v0.012: poultry's feathers, for fletching)
		var q := float(K.get(g, 0.0)) * (af if g in ["tallow", "bones"] else 1.0)
		if q > 0.0:
			out[g] = q
	return out

static func _carcass_value(e: Dictionary, h: Dictionary, age: String) -> float:
	var K := kind(String(h["k"]))
	var af := float(A()["yield_age"][AGES.find(age)])
	var price_d: Dictionary = e["price"]
	var v := float(K.get("meat", 0.0)) * af / float(A()["kg_per_meal"]) * float(price_d.get("fresh_meat", 16.0))
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
	var per_hand := float(kind(k).get("per_hand", TownEcon.data()["land"]["head_per_hand"]))
	if not e.has("hd"):
		return {"heads": n, "hands": float(n) / per_hand}
	var left := n
	var work := 0.0
	for src in of_family(e, fid):
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
	var to := herd_for(e, fb, k, day)
	var left := n
	var det := why if why != "" else ("with the land" if k == "oxen" else "the town's land book")
	for src in of_family(e, fa):
		if left <= 0:
			break
		if String(src["k"]) != k or int(src["id"]) == int(to["id"]):
			continue
		for age in ["o", "y", "g"]:
			var q := mini(left, int(src[age]))
			if q > 0:
				left -= _transfer(e, src, to, age, q, "sold", "bought", "%s to %s" % [det, Plots.owner_text(e, fb)],
					"%s from %s" % [det, Plots.owner_text(e, fa)], day, false)
	if left > 0:   # the family's total ran ahead of its records (an old save): the records take the total's word
		H(e)["drift"] = int(H(e).get("drift", 0)) + left

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
	var share := float(A()["sack_share"])
	var day := float(e.get("day", 0))
	var thief := CampaignWorld.faction_the(att)
	for hid in (H(e)["h"] as Dictionary).keys():
		var h: Dictionary = herds(e)[hid]
		if not GRAZE.has(String(h["k"])) and String(h["k"]) != "oxen":
			continue
		for age in AGES:
			var n := int(floor(float(h[age]) * share))
			if n <= 0:
				continue
			var got := -change(e, h, age, -n, "stolen", "driven off by %s" % thief, day)
			if got > 0 and home != "":
				var he: Dictionary = w["towns"][home]["econ"]
				var to := herd_for(he, 0, String(h["k"]), float(he.get("day", 0)))
				change(he, to, age, got, "stolen", "driven home from %s" % String(town["name"]), float(he.get("day", 0)))

# ================================================================== drovers (B2)
## A drover with hands and no herd on the road buys beasts where they are cheap and walks them to a road partner
## where they fetch the data's margin more. The walking herd is a record of its own (owner: the drover).
static func _drovers(game, town: Dictionary, e: Dictionary, day: float) -> void:
	var w: Dictionary = game.world
	if not w.has("droves"):
		w["droves"] = {}
	var DV: Dictionary = A()["drove"]
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
				var have := int(H(e)["ofk"].get(k, 0))
				if have <= 0:
					continue
				var ph := price(e, k); var pd := price(o["econ"], k)
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
		var p := price(e, k2)
		while cap > 0 and float(b["till"]) >= p:
			var o2 := _take_offer(e, k2, ["g", "y"])
			if o2.is_empty():
				break
			var s: Dictionary = herds(e)[str(int(o2[0]))]
			var pa := price(e, k2, String(o2[1]))
			if _transfer(e, s, dh, String(o2[1]), 1, "sold", "bought", "to %s, for %s" % [Businesses.title(e, b), String(w["towns"][String(best[0])]["name"])],
					"from %s of %s" % [owner_text(e, s), String(town["name"])], day) > 0:
				b["till"] = float(b["till"]) - pa
				_add_coin(e, s, pa)
				H(e)["sok"][k2] = int(H(e)["sok"].get(k2, 0)) + 1
				cap -= 1
		if head(dh) <= 0:
			continue
		var did2 := "dv%d" % int(w.get("drove_n", 1))
		w["drove_n"] = int(w.get("drove_n", 1)) + 1
		w["droves"][did2] = {"id": did2, "h": dh, "from": String(town["id"]), "to": String(best[0]), "b": int(b["id"]), "d0": int(day),
			"days": maxi(1, int(ceil(float(best[2]) / float(DV["px_day"]))))}
		_chain(b, "to", String(w["towns"][String(best[0])]["name"]), head(dh), k2)

## The droves' day (a world work job): each walks on; bandits or a realm at war with its town close by drive it off
## (theft; the beasts end in their stores as meat); at its end the herd joins the town's herds, all of it offered.
static func droves_day(game, day: float) -> void:
	var w: Dictionary = game.world
	var dvs: Dictionary = w.get("droves", {})
	var DV: Dictionary = A()["drove"]
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
					meals += int(float(n) * float(kind(String(h["k"])).get("meat", 0.0)) * float(A()["yield_age"][AGES.find(age)]) / float(A()["kg_per_meal"]))
			var st := Supplies.stores(wb)
			st["meat"] = int(st.get("meat", 0)) + meals
			var fe: Dictionary = from["econ"]
			var book: Dictionary = H(fe)["tot"]
			if not book.has("stolen"):
				book["stolen"] = {}
			book["stolen"][String(h["k"])] = int(book["stolen"].get(String(h["k"]), 0)) + int(h["led"]["st"])
			(H(fe)["log"] as Array).append([int(day), -1, String(h["k"]), -int(h["led"]["st"]), "stolen", "a drove to %s, by %s" % [String(to["name"]), "outlaws" if kd == "bandit" else CampaignWorld.faction_the(String(wb["faction"]))]])
			TownEcon.town_hist(fe, "A drove of %s bound for %s was driven off on the road." % [word(fe, String(h["k"])), String(to["name"])], day)
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
				migrate(w, to, te)
			var hd := H(te)
			var id := int(hd["n"])
			hd["n"] = id + 1
			h["id"] = id
			h["h0"] = 0
			h["led"]["in"] = head(h)
			h["led"]["out"] = 0
			h["da"] = int(day)
			hd["h"][str(id)] = h
			for age in AGES:
				if int(h[age]) > 0:
					(hd["of"] as Array).append([id, age, int(h[age])])
					hd["ofk"][String(h["k"])] = int(hd["ofk"].get(String(h["k"]), 0)) + int(h[age])
			(hd["log"] as Array).append([int(day), id, String(h["k"]), head(h), "bought", "a drove from %s" % String(from["name"])])
			dvs.erase(did)

# ================================================================== tile assignment (Plots._sync_grazing)
## Pasture plots shared among the grazing herds: a family's OWN pasture plots go to its herds; the common plots
## (held by the town) are shared out among the rest by the acres their herds need, each family at most the data's
## common cap (largest remainder). At world gen the families whose herds need more than the cap own the plots
## their herds need (owned pasture, B2). P.ten = the family whose herd grazes it.
static func assign_tiles(e: Dictionary, P: Dictionary) -> void:
	var past := []
	for i in Plots.count(P):
		if int(P["use"][i]) == Plots.PASTURE:
			past.append(i)
	var hd := H(e)
	var tiles := {}
	for hid in hd["h"]:
		hd["h"][hid]["pl"] = []
		hd["h"][hid]["opl"] = []
		hd["h"][hid]["cs"] = 0.0
	_pens(e, P)
	var fams: Array = e["fams"]
	# the acres each grazing family's herds need
	var need := {}   # fid -> acres
	var by_f := {}   # fid -> [herds]
	for hid in hd["h"]:
		var h: Dictionary = hd["h"][hid]
		var k := String(h["k"])
		if not GRAZE.has(k) or head(h) <= 0:
			continue
		var fid := grazer(e, h)
		if fid < 0:
			continue
		need[fid] = float(need.get(fid, 0.0)) + ge(h) * float(kind(k)["feed"])
		if not by_f.has(fid):
			by_f[fid] = []
		by_f[fid].append(h)
	var cap := float(A()["common_cap"])
	if not P.get("past_own", false):
		P["past_own"] = true
		if int(e.get("day", 0)) <= 0:   # world gen only: the big herds' families own their pasture
			var fids: Array = need.keys()
			fids.sort()
			var at := 0
			for fid in fids:
				if int(fid) == 0 or float(need[fid]) <= cap:
					continue
				var nt := int(round(float(need[fid]) / float(Plots.ACRES)))
				for j in nt:
					if at >= past.size():
						break
					P["own"][past[at]] = int(fid)
					at += 1
	for i in past:
		var o := int(P["own"][i])
		if o > 0 and (o >= fams.size() or fams[o].get("gone", false)):
			P["own"][i] = Plots.TOWN
	var own_ac := {}
	var common := []
	for i in past:
		P["ten"][i] = -1
		var o2 := int(P["own"][i])
		if o2 > 0:
			if by_f.has(o2):
				P["ten"][i] = o2
				own_ac[o2] = float(own_ac.get(o2, 0.0)) + float(P["ac"][i])
				_give_tile(by_f[o2], i, tiles, true)
		else:
			common.append(i)
	# common plots: each family's stint (its right to graze, in acres: what its herds needed when it was first
	# counted, at most the cap; the town's own herds what they need), shared out by largest remainder
	if not hd.has("stint"):
		hd["stint"] = {}
	var stint: Dictionary = hd["stint"]
	for sk in stint.keys():
		var sf0 := int(sk)
		if sf0 >= fams.size() or fams[sf0].get("gone", false):
			stint.erase(sk)
	var rows := []
	var tot := 0.0
	var fids2: Array = need.keys()
	fids2.sort()
	var stot := 0.0
	for fid in fids2:
		var left := float(need[fid]) - float(own_ac.get(fid, 0.0))
		if int(fid) != 0:
			if not stint.has(str(int(fid))):
				stint[str(int(fid))] = snappedf(clampf(left, 0.0, cap), 0.01)
			left = minf(left, cap)
		var stv := float(stint.get(str(int(fid)), maxf(0.0, left)))
		if left > 0.0:
			rows.append([int(fid), left, stv])
			tot += left
			stot += stv
	hd["cpool"] = common
	hd.erase("_pg"); hd.erase("_pa")
	var cac := 0.0
	for i in common:
		cac += float(P["ac"][i])
	if tot > cac and stot > 0.0:   # more wanted than the common grows: each family by its stint
		for r0 in rows:
			r0[1] = float(r0[2]) * cac / stot
		tot = cac
	# each family's share of the common's grass (its capped need over the common, all of it when there is room),
	# split among its herds by their need
	for r in rows:
		var sf := float(r[1]) / maxf(tot, maxf(1.0, cac))
		var fneed := 0.0
		for h2 in by_f[int(r[0])]:
			fneed += ge(h2) * float(kind(String(h2["k"]))["feed"])
		for h3 in by_f[int(r[0])]:
			h3["cs"] = snappedf(sf * ge(h3) * float(kind(String(h3["k"]))["feed"]) / maxf(0.0001, fneed), 0.000001)
	if common.is_empty() or tot <= 0.0:
		_tiles_done(hd, tiles)
		return
	var n_t := float(common.size()) * minf(1.0, tot / maxf(1.0, cac))
	var share := []
	var given := 0
	for r in rows:
		var q := n_t * float(r[1]) / tot
		share.append([r[0], int(floor(q)), q - floor(q)])
		given += int(floor(q))
	var order := range(share.size())
	order.sort_custom(func(a, b): return float(share[a][2]) > float(share[b][2]) if float(share[a][2]) != float(share[b][2]) else int(share[a][0]) < int(share[b][0]))
	for k in mini(int(round(n_t)) - given, order.size()):
		share[order[k]][1] = int(share[order[k]][1]) + 1
	var at2 := 0
	for s in share:
		for j in int(s[1]):
			if at2 < common.size():
				var i2: int = common[at2]
				P["ten"][i2] = int(s[0])
				_give_tile(by_f[int(s[0])], i2, tiles)
				at2 += 1
	_tiles_done(hd, tiles)

## A plot to the family's herd that has the least grass for its need.
static func _give_tile(hl: Array, i: int, tiles: Dictionary, own: bool = false) -> void:
	var best: Dictionary = {}
	var bv := INF
	for h in hl:
		var have := float((h["pl"] as Array).size()) * float(Plots.ACRES)
		var v := have / maxf(0.01, ge(h) * float(kind(String(h["k"]))["feed"]))
		if v < bv:
			bv = v; best = h
	if not best.is_empty():
		(best["pl"] as Array).append(i)
		if own:
			(best["opl"] as Array).append(i)
		tiles[str(i)] = int(best["id"])

static func _tiles_done(hd: Dictionary, tiles: Dictionary) -> void:
	hd["tiles"] = tiles

## Pens: a family's small stock lives at its first home plot (hd.pens {str(plot): kind}, the herds' pl).
static func _pens(e: Dictionary, P: Dictionary) -> void:
	var hd := H(e)
	var first := {}
	for i in Plots.count(P):
		if int(P["use"][i]) != Plots.HOME:
			continue
		var fid := int(P["ten"][i]) if int(P["ten"][i]) > 0 else int(P["own"][i])
		if fid > 0 and not first.has(fid):
			first[fid] = i
	var pens := {}
	for hid in hd["h"]:
		var h: Dictionary = hd["h"][hid]
		if GRAZE.has(String(h["k"])) or String(h["k"]) == "oxen" or String(h["ow"]) != "f" or head(h) <= 0:
			continue
		var p := int(first.get(int(h["oi"]), -1))
		if p >= 0:
			h["pl"] = [p]
			if not pens.has(str(p)):
				pens[str(p)] = String(h["k"])
	hd["pens"] = pens

## Acres of pasture the town's grazing herds need at a full season's grass (head x the kind's feed; land layout).
static func graze_acres(e: Dictionary) -> float:
	var a := 0.0
	for hid in herds(e):
		var h: Dictionary = herds(e)[hid]
		if GRAZE.has(String(h["k"])):
			a += float(head(h)) * float(kind(String(h["k"]))["feed"])
	return a

## Records whose pens are a family's home plot (hens, rats, hives; pigs kept at home have pasture here too).
static func pen_herds(e: Dictionary, fid: int) -> Array:
	var out := []
	for h in of_family(e, fid):
		if not GRAZE.has(String(h["k"])) and String(h["k"]) != "oxen":
			out.append(h)
	return out

# ================================================================== reads (records screens, land map, tests)
## Head by kind in the town (every record, every owner; drovers' herds waiting to be sold included).
static func town_heads(e: Dictionary) -> Dictionary:
	var out := {}
	if not e.has("hd"):
		return e.get("herd", {})
	var hd: Dictionary = e["hd"]
	var key := "%d|%d" % [int(hd.get("ver", 0)), (hd["h"] as Dictionary).size()]
	if String(hd.get("_thk", "")) == key:
		return hd["_th"]
	hd["_thk"] = key
	hd["_th"] = out
	var records: Dictionary = hd["h"]
	for hid in records:
		var h: Dictionary = records[hid]
		var n := int(h["y"]) + int(h["g"]) + int(h["o"])
		if n > 0:
			var kind := String(h["k"])
			out[kind] = int(out.get(kind, 0)) + n
	return out

## {kind: [young, grown, old]} for the town.
static func town_ages(e: Dictionary) -> Dictionary:
	var out := {}
	if not e.has("hd"):
		return out
	for hid in herds(e):
		var h: Dictionary = herds(e)[hid]
		var k := String(h["k"])
		if not out.has(k):
			out[k] = [0, 0, 0]
		for i in 3:
			out[k][i] = int(out[k][i]) + int(h[AGES[i]])
	return out

## Days of winter fodder the town's herds have in reach (their own hay + the barns' and market's fodder) at the
## herds' last week's feed, or -1 when the town keeps no grazing beasts.
static func fodder_days(e: Dictionary) -> float:
	if not e.has("hd") or float(e["hd"].get("fneed", 0.0)) <= 0.0:
		return -1.0
	return float(e["hd"].get("fodd", 0.0))

## The herd's one-line text: "40 sheep (8 young, 28 grown, 4 old) of the Marsh family".
static func line(e: Dictionary, h: Dictionary) -> String:
	return "%s (%d young, %d grown, %d old) of %s" % [n_word(e, head(h), String(h["k"])), int(h["y"]), int(h["g"]), int(h["o"]), owner_text(e, h)]

## Herds on a plot: pasture by the tile map, a home plot's pens (its family's small stock).
static func on_plot(e: Dictionary, P: Dictionary, i: int) -> Array:
	var out := []
	if not e.has("hd"):
		return out
	var u := int(P["use"][i])
	if u == Plots.PASTURE:
		var hid := int(H(e)["tiles"].get(str(i), -1))
		if hid >= 0 and herds(e).has(str(hid)):
			out.append(herds(e)[str(hid)])
	elif u == Plots.HOME and H(e).get("pens", {}).has(str(i)):
		var fid := int(P["ten"][i]) if int(P["ten"][i]) > 0 else int(P["own"][i])
		out = pen_herds(e, fid)
	return out

## The kind drawn on a plot (land map sprites): the herd grazing a pasture, a home's small stock ("" = none).
static func plot_kind(e: Dictionary, P: Dictionary, i: int) -> String:
	if not e.has("hd"):
		return ""
	var hd: Dictionary = e["hd"]
	var u := int(P["use"][i])
	if u == Plots.PASTURE:
		var hid := str(int(hd["tiles"].get(str(i), -1)))
		return String(hd["h"][hid]["k"]) if hd["h"].has(hid) else ""
	if u == Plots.HOME:
		return String(hd.get("pens", {}).get(str(i), ""))
	return ""

## The plot card's herd lines (Plots.card): who owns the pasture (the common's fee), each herd on it with its
## owner and herders, what the plot carries this season and its condition; a home's pens. {lines, taps}
static func card_lines(game, town: Dictionary, P: Dictionary, i: int) -> Dictionary:
	var e: Dictionary = town["econ"]
	var lines := []
	var taps := []
	var si := Calendar.season_index(float(game.day))
	var u := int(P["use"][i])
	if u == Plots.PASTURE:
		var own := int(P["own"][i])
		if own > 0:
			lines.append("Pasture owned by %s." % Plots.owner_text(e, own))
			taps.append({"text": "Owners: %s" % Plots.owner_text(e, own), "fid": own})
		else:
			lines.append("The town's common pasture: %s coins an acre a week to the treasury for grazing it." % num(float(A()["fee_acre_week"]) * Barge.pl(e)))
		lines.append("Grass this %s: %s bales a day (condition %d%%%s)." % [Calendar.SEASONS[si], num(grass_day(e, P, i, si)),
			int(round(cond(e, i) * 100.0)), ", overgrazed" if cond(e, i) < 0.95 else ""])
	for h in on_plot(e, P, i):
		var k := String(h["k"])
		lines.append("%s." % _cap(line(e, h)))
		if int(h["hun"]) > 0:
			lines.append("Short of feed: %d days in the last weeks." % int(h["hun"]))
		var hs := herders(e, h)
		if not hs.is_empty():
			var nm := []
			for p in hs.slice(0, 4):
				nm.append(String(p["name"]))
			lines.append("Herded by %s%s." % [", ".join(PackedStringArray(nm)), (" and %d more" % (hs.size() - 4)) if hs.size() > 4 else ""])
			taps.append({"text": "Herder: %s" % hs[0]["name"], "fid": int(hs[0]["fid"])})
		var gf := grazer(e, h)
		if gf > 0:
			taps.append({"text": "Herd owners: %s" % Plots.owner_text(e, gf), "fid": gf})
		if u == Plots.PASTURE:
			lines.append("This plot carries %s this season (the herd has %d plots of pasture, %s bales of hay)." % [n_word(e, carry_head(e, P, i, k, si), k),
				(h["pl"] as Array).size(), num(float(h["fod"]))])
	if u == Plots.PASTURE and on_plot(e, P, i).is_empty():
		lines.append("No herd grazes it this week.")
	return {"lines": lines, "taps": taps}

static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s

static func num(v: float) -> String:
	return str(int(round(v))) if absf(v) >= 10.0 else ("%.1f" % v)

## The town's herd ledger as a whole: {born, bought, sold, slaughtered, stolen, looted, died {cause: n}} all-time
## or this year ("yr") or last ("ly"), summed over kinds; by_kind gives {what: {kind: n}}.
static func book(e: Dictionary, which: String = "tot") -> Dictionary:
	var out := {"died": {}}
	if not e.has("hd"):
		return out
	var b: Dictionary = H(e).get(which, {})
	for key in b:
		var n := 0
		for k in b[key]:
			n += int(b[key][k])
		if String(key).begins_with("died:"):
			out["died"][String(key).substr(5)] = n
		else:
			out[key] = n
	return out

## Sum of every record's head by its ledger: h0 + born + bought - sold - slaughtered - stolen - died (tests).
static func ledger_head(h: Dictionary) -> int:
	var L: Dictionary = h["led"]
	var d := 0
	for c in L["d"]:
		d += int(L["d"][c])
	return int(h["h0"]) + int(L["b"]) + int(L["in"]) - int(L["out"]) - int(L["sl"]) - int(L["st"]) - d

## The page lines of a business's chain: [[way, who, what, n]] this season (and last).
static func chain_rows(b: Dictionary) -> Array:
	var out := []
	for src in ["chain", "chain_last"]:
		var c: Dictionary = b.get(src, {})
		for way in ["from", "to"]:
			var d: Dictionary = c.get(way, {})
			var keys: Array = d.keys()
			keys.sort_custom(func(x, y): return int(d[x]) > int(d[y]))
			for key in keys:
				var parts := String(key).split("|")
				out.append([way, parts[0], parts[1] if parts.size() > 1 else "", int(d[key]), src == "chain"])
	return out
