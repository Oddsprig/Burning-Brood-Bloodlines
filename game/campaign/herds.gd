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
static func new_herd(e: Dictionary, k: String, ow: String, oi: int, day_v: float, ot: String = "") -> Dictionary:
	var hd := H(e)
	var id := int(hd["n"])
	hd["n"] = id + 1
	var h := {"id": id, "k": k, "y": 0, "g": 0, "o": 0, "ow": ow, "oi": oi, "fod": 0.0, "hun": 0, "lac": 0.0, "h0": 0, "d0": int(day_v),
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
static func change(e: Dictionary, h: Dictionary, age: String, dn: int, what: String, detail: String, day_v: float, mirror: bool = true) -> int:
	if dn == 0:
		return 0
	if dn < 0:
		dn = -mini(-dn, int(h[age]))
		if dn == 0:
			return 0
	h[age] = int(h[age]) + dn
	if String(h["k"]) == "horses" and age == "y" and dn < 0:
		LivestockCare.trim_foals(h)
	if String(h["k"]) == "horses" and age == "g" and dn < 0:
		LivestockCare.trim_mount_bodies(h)
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
	for book_d in [hd["tot"], hd["yr"]]:
		var b: Dictionary = book_d
		if not b.has(dkey):
			b[dkey] = {}
		b[dkey][k] = int(b[dkey].get(k, 0)) + absi(dn)
	var lg: Array = hd["log"]
	lg.append([int(day_v), int(h["id"]), k, dn, what, detail])
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
		det_from: String, det_to: String, day_v: float, mirror: bool = true) -> int:
	# Young horses retain their birth dates through the existing live-stock market.
	var foals: Array = []
	if String(from["k"]) == "horses" and age == "y":
		foals = LivestockCare.take_foals(from, mini(n, int(from["y"])))
	var mount_bodies: Array = []
	if String(from["k"]) == "horses" and age == "g":
		mount_bodies = LivestockCare.take_mount_bodies(from, mini(n, int(from["g"])))
	var got := -change(e, from, age, -n, what_from, det_from, day_v, mirror)
	if got > 0:
		var before := head(to)
		change(e, to, age, got, what_to, det_to, day_v, mirror)
		if not foals.is_empty():
			LivestockCare.ensure_foals(to, got)
			to["foals"].append_array(foals)
		if not mount_bodies.is_empty():
			if not to.has("mount_bodies"): to["mount_bodies"] = []
			to["mount_bodies"].append_array(mount_bodies)
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
static func herd_for(e: Dictionary, fid: int, k: String, day_v: float) -> Dictionary:
	var l := of_owner(e, "s" if fid == 0 else "f", fid, k)
	if not l.is_empty():
		return l[0]
	return new_herd(e, k, "s" if fid == 0 else "f", fid, day_v)

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
static func _records_from_totals(e: Dictionary, day_v: float, rng: RandomNumberGenerator) -> void:
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
			var h := new_herd(e, String(k), ow, fid, day_v)
			_seed_ages(h, n, rng)
		var ox := int(f.get("ox", 0))
		if ox > 0:
			var ho := new_herd(e, "oxen", ow, fid, day_v)
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
	for book_k in ["tot", "yr", "ly"]:
		var b: Dictionary = hd.get(book_k, {})
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
static func week(game, town: Dictionary, day_v: float) -> void:
	var e: Dictionary = town["econ"]
	if not e.has("hd"):
		migrate(game.world, town, e)
	var hd := H(e)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(game.world.get("seed", 0)), String(town["id"]), int(day_v), "herds"])
	var si := Calendar.season_index(day_v)
	var yr := Calendar.year(day_v)
	if yr != int(hd["y"]):
		hd["ly"] = hd["yr"]
		hd["yr"] = {}
		hd["y"] = yr
	hd.erase("_pg"); hd.erase("_pa")
	LivestockCare.feed_hens(e, day_v)
	_disease(e, rng, day_v)
	_males(e)
	_land_choice(e, Plots.of(town), day_v)
	var P := Plots.of(town)
	assign_tiles(e, P) # Returned/bought stock uses its current native pasture allocation.
	var ids: Array = (hd["h"] as Dictionary).keys()
	for hid in ids:
		var h: Dictionary = hd["h"][hid]
		_life(e, h, si, day_v, rng)
	_orphans(e, day_v)
	_feed_all(e, P, si, day_v, rng)
	HerdRaids.plan(game, town, day_v)
	_stockpile(e, si, day_v)
	_repay_loans(e)
	_unsold(e, si, day_v)
	_offers(e, si, day_v)
	_wants(game, town, e, si, day_v)
	_drovers(game, town, e, day_v)
	_prices(e)
	_products(e, si, day_v)
	LivestockCare.hive_week(e, day_v)
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
static func _predators(game, town: Dictionary, _e: Dictionary, day_v: float, _rng: RandomNumberGenerator) -> void:
	HerdRaids.plan(game, town, day_v)

static func _orphans(e: Dictionary, day_v: float) -> void:
	var fams: Array = e["fams"]
	for hid in (H(e)["h"] as Dictionary).keys():
		var h: Dictionary = herds(e)[hid]
		if String(h["ow"]) != "f" or head(h) <= 0:
			continue
		var fid := int(h["oi"])
		if fid > 0 and fid < fams.size() and not fams[fid].get("gone", false):
			continue
		var to := herd_for(e, 0, String(h["k"]), day_v)
		for age in AGES:
			if int(h[age]) > 0:
				_transfer(e, h, to, age, int(h[age]), "sold", "bought", "left to the town", "left by %s" % Plots.owner_text(e, fid), day_v)

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
static func _bred_share(e: Dictionary, h: Dictionary, day_v: float) -> float:
	var K := kind(String(h["k"]))
	var n := head(h)
	var life := float(K.get("grow", 0.0)) + float(K["prime"]) + 1.0 / maxf(0.05, float(K["old_die"]))
	var repl := float(n) * (1.0 / maxf(0.1, life) + float(K["die"]))
	# what the herd really lost a year since the owners last chose (died, slaughtered, sold, stolen: its own ledger)
	var L: Dictionary = h["led"]
	var lost := int(L["out"]) + int(L["sl"]) + int(L["st"])
	for c in L["d"]:
		lost += int(L["d"][c])
	var since := maxf(0.25, (day_v - float(h.get("ls_day", h.get("d0", day_v)))) / float(year_days()))
	repl = maxf(repl, float(lost - int(h.get("ls_n", 0))) / since)
	h["ls_n"] = lost
	h["ls_day"] = int(day_v)
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
static func _disease(e: Dictionary, rng: RandomNumberGenerator, day_v: float) -> void:
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
		TownEcon.town_hist(e, "%s broke out among %s." % [String(d).capitalize(), owner_text(e, h0)], day_v)
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
					died -= change(e, h, age, -nd, "died", "sickness: %s" % String(d), day_v)
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
static func _life(e: Dictionary, h: Dictionary, si: int, day_v: float, rng: RandomNumberGenerator) -> void:
	var K := kind(String(h["k"]))
	var wk := 7.0 / float(year_days())
	var horse := String(h["k"]) == "horses"
	if horse: LivestockCare.horse_life(e, h, Plots._p(e), day_v, rng)
	# growing up and growing old (same beasts; no change of head)
	if not horse and float(K.get("grow", 0.0)) > 0.0 and int(h["y"]) > 0:
		var up := mini(int(h["y"]), _whole(float(h["y"]) * wk / float(K["grow"]), rng))
		h["y"] = int(h["y"]) - up; h["g"] = int(h["g"]) + up
		if up > 0: H(e)["ver"] = int(H(e).get("ver", 0)) + 1
	if int(h["g"]) > 0:
		var ol := mini(int(h["g"]), _whole(float(h["g"]) * wk / float(K["prime"]), rng))
		h["g"] = int(h["g"]) - ol; h["o"] = int(h["o"]) + ol
	if horse: LivestockCare.trim_mount_bodies(h)
	# births by the kind's biology: in each of its breeding seasons (gestation decides how many a year fit), per grown
	# female the owners put to the male this year (h.bred, their choice), served by the town's males (each covers
	# the kind's females_per_male); a hungry herd bears fewer [ours: x0.5], a sick one by its healthy share
	var in_season := false
	for s0 in K.get("seasons", [0]):   # (JSON gives the seasons back as floats)
		if int(s0) == si:
			in_season = true
	if not horse and in_season and float(K.get("bear", 0.0)) > 0.0 and int(h["g"]) > 0:
		var stamp := Calendar.year(day_v) * 4 + si
		if int(h.get("bred_s", -1)) != stamp:
			h["bred"] = snappedf(_bred_share(e, h, day_v), 0.001)
			h["bred_s"] = stamp
		var mothers := float(h["g"]) * float(K["fem"]) * float(K["bear"]) * float(h["bred"]) * float(H(e).get("_male", {}).get(String(h["k"]), 1.0)) \
			* 7.0 / float(Calendar.DAYS_PER_SEASON)
		if int(h["hun"]) > 0:
			mothers *= 0.5
		mothers *= maxf(0.0, 1.0 - sick(h))
		var born := _whole(mothers * float(K["litter"]), rng)
		if born > 0:
			change(e, h, "y", born, "born", "", day_v)
			h["lac"] = float(h["lac"]) + mothers
	if float(h["lac"]) > 0.0:
		h["lac"] = maxf(0.0, float(h["lac"]) * (1.0 - 7.0 / maxf(7.0, float(K.get("milk_days", 7)))))
		h["lac"] = minf(float(h["lac"]), float(h["g"]) * float(K.get("fem", 0.0)))
	# deaths
	var pd := 1.0 - pow(1.0 - float(K["old_die"]), wk)
	var n_old := _whole(float(h["o"]) * pd, rng)
	if n_old > 0:
		change(e, h, "o", -n_old, "died", "old age", day_v)
	var pb := 1.0 - pow(1.0 - float(K["die"]), wk)
	for age in AGES:
		var n := _whole(float(h[age]) * pb, rng)
		if n > 0:
			change(e, h, age, -n, "died", "sickness: %s" % String(K.get("ail", "ailments")), day_v)
	if si == 3 and String(e.get("climate", "")) == "cold" and int(h["y"]) > 0:
		var n3 := _whole(float(h["y"]) * float(K.get("cold", 0.0)), rng)
		if n3 > 0:
			change(e, h, "y", -n3, "died", "cold", day_v)

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
static func _feed_all(e: Dictionary, P: Dictionary, si: int, day_v: float, rng: RandomNumberGenerator) -> void:
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
					change(e, h, age, -n, "died", "starved", day_v)
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

# ================================================================== fodder, market, butcher & drovers (campaign/herds_market.gd)
static func _buy_fodder(e: Dictionary, h: Dictionary, n: float, loan: bool = true, keep: float = 0.0) -> float: return HerdsMarket._buy_fodder(e, h, n, loan, keep)
static func _stockpile(e: Dictionary, si: int, day_v: float) -> void: HerdsMarket._stockpile(e, si, day_v)
static func _repay_loans(e: Dictionary) -> void: HerdsMarket._repay_loans(e)
static func _fodder_claim_total(creditors: Dictionary) -> float: return HerdsMarket._fodder_claim_total(creditors)
static func _reduce_fodder_claims(creditors: Dictionary, amount: float) -> void: HerdsMarket._reduce_fodder_claims(creditors, amount)
static func straw_left(e: Dictionary, h: Dictionary) -> float: return HerdsMarket.straw_left(e, h)
static func _straw_taken(e: Dictionary, h: Dictionary, n: int) -> void: HerdsMarket._straw_taken(e, h, n)
static func _unsold(e: Dictionary, si: int, day_v: float) -> void: HerdsMarket._unsold(e, si, day_v)
static func _home_cap(e: Dictionary, h: Dictionary) -> int: return HerdsMarket._home_cap(e, h)
static func _carcass(e: Dictionary, h: Dictionary, age: String, n: int, home: bool) -> Dictionary: return HerdsMarket._carcass(e, h, age, n, home)
static func larder_room(e: Dictionary, f: Dictionary) -> int: return HerdsMarket.larder_room(e, f)
static func _to_larder(e: Dictionary, f: Dictionary, n: int) -> int: return HerdsMarket._to_larder(e, f, n)
static func _sell(e: Dictionary, h: Dictionary, goods: Dictionary, share: float) -> void: HerdsMarket._sell(e, h, goods, share)
static func _offers(e: Dictionary, si: int, day_v: float) -> void: HerdsMarket._offers(e, si, day_v)
static func _target(e: Dictionary, h: Dictionary, P: Dictionary) -> int: return HerdsMarket._target(e, h, P)
static func _wants(game, town: Dictionary, e: Dictionary, si: int, day_v: float) -> void: HerdsMarket._wants(game, town, e, si, day_v)
static func _pot_buys(e: Dictionary, day_v: float) -> void: HerdsMarket._pot_buys(e, day_v)
static func _take_offer(e: Dictionary, k: String, ages: Array, buyer_fid: int = -1, buyer_hid: int = -1, index: Dictionary = {}) -> Array: return HerdsMarket._take_offer(e, k, ages, buyer_fid, buyer_hid, index)
static func _indexed_oxen(e: Dictionary, index: Dictionary, fid: int, day_v: float) -> Dictionary: return HerdsMarket._indexed_oxen(e, index, fid, day_v)
static func _prices(e: Dictionary) -> void: HerdsMarket._prices(e)
static func _products(e: Dictionary, si: int, day_v: float) -> void: HerdsMarket._products(e, si, day_v)
static func day(e: Dictionary) -> void: HerdsMarket.day(e)
static func _manure(e: Dictionary) -> void: HerdsMarket._manure(e)
static func manure_f(e: Dictionary) -> float: return HerdsMarket.manure_f(e)
static func straw(e: Dictionary, acres_cut: float) -> void: HerdsMarket.straw(e, acres_cut)
static func fodder_paid(e: Dictionary, val: float) -> void: HerdsMarket.fodder_paid(e, val)
static func _land_choice(e: Dictionary, P: Dictionary, day_v: float) -> void: HerdsMarket._land_choice(e, P, day_v)
static func change_crop(e: Dictionary, P: Dictionary, f: Dictionary, i: int, a: String, b: String, day_v: float) -> void: HerdsMarket.change_crop(e, P, f, i, a, b, day_v)
static func _herder_caps(e: Dictionary) -> void: HerdsMarket._herder_caps(e)
static func _fees(e: Dictionary, P: Dictionary, h: Dictionary) -> void: HerdsMarket._fees(e, P, h)
static func butcher_day(e: Dictionary, b: Dictionary, wd: float, toolf: float, mkt: Dictionary, share: float, bdem: Dictionary) -> float: return HerdsMarket.butcher_day(e, b, wd, toolf, mkt, share, bdem)
static func yields(k: String, age: String) -> Dictionary: return HerdsMarket.yields(k, age)
static func _carcass_value(e: Dictionary, h: Dictionary, age: String) -> float: return HerdsMarket._carcass_value(e, h, age)
static func _chain(b: Dictionary, way: String, who: String, n: int, what: String) -> void: HerdsMarket._chain(b, way, who, n, what)
static func move_work(e: Dictionary, fid: int, k: String, n: int) -> Dictionary: return HerdsMarket.move_work(e, fid, k, n)
static func moved(e: Dictionary, a: Dictionary, b: Dictionary, k: String, n: int, why: String = "") -> void: HerdsMarket.moved(e, a, b, k, n, why)
static func on_sack(w: Dictionary, town: Dictionary, att: String) -> void: HerdsMarket.on_sack(w, town, att)
static func _drovers(game, town: Dictionary, e: Dictionary, day_v: float) -> void: HerdsMarket._drovers(game, town, e, day_v)
static func droves_day(game, day_v: float) -> void: HerdsMarket.droves_day(game, day_v)

# ================================================================== tile assignment & reads (campaign/herds_views.gd)
static func assign_tiles(e: Dictionary, P: Dictionary) -> void: HerdsViews.assign_tiles(e, P)
static func _give_tile(hl: Array, i: int, tiles: Dictionary, own: bool = false) -> void: HerdsViews._give_tile(hl, i, tiles, own)
static func _tiles_done(hd: Dictionary, tiles: Dictionary) -> void: HerdsViews._tiles_done(hd, tiles)
static func _pens(e: Dictionary, P: Dictionary) -> void: HerdsViews._pens(e, P)
static func graze_acres(e: Dictionary) -> float: return HerdsViews.graze_acres(e)
static func pen_herds(e: Dictionary, fid: int) -> Array: return HerdsViews.pen_herds(e, fid)
static func town_heads(e: Dictionary) -> Dictionary: return HerdsViews.town_heads(e)
static func town_ages(e: Dictionary) -> Dictionary: return HerdsViews.town_ages(e)
static func fodder_days(e: Dictionary) -> float: return HerdsViews.fodder_days(e)
static func line(e: Dictionary, h: Dictionary) -> String: return HerdsViews.line(e, h)
static func on_plot(e: Dictionary, P: Dictionary, i: int) -> Array: return HerdsViews.on_plot(e, P, i)
static func plot_kind(e: Dictionary, P: Dictionary, i: int) -> String: return HerdsViews.plot_kind(e, P, i)
static func card_lines(game, town: Dictionary, P: Dictionary, i: int) -> Dictionary: return HerdsViews.card_lines(game, town, P, i)
static func _cap(s: String) -> String: return HerdsViews._cap(s)
static func num(v: float) -> String: return HerdsViews.num(v)
static func book(e: Dictionary, which: String = "tot") -> Dictionary: return HerdsViews.book(e, which)
static func ledger_head(h: Dictionary) -> int: return HerdsViews.ledger_head(h)
static func chain_rows(b: Dictionary) -> Array: return HerdsViews.chain_rows(b)
