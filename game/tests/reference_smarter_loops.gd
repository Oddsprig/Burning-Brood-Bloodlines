extends RefCounted

## Frozen algorithms from baseline 4ae8f53 for differential tests. No production code loads this file.

static func original_to_trades(e: Dictionary, f: Dictionary, own: int, ad: int, need: float, biz: Array) -> int:
	var pay := []
	for k in f["jobs"]:
		var b: Dictionary = biz[int(k)]
		if not String(b["type"]) in ["farm", "estate", "works"]:
			for i in int(f["jobs"][k]):
				pay.append(float(b["wage"]))
	for bid in e.get("open", []):
		var b: Dictionary = biz[int(bid)]
		if String(b["type"]) in ["farm", "estate", "works"] or b.get("closed", false):
			continue
		var n := int(b["cap"]) - int(b["workers"]) if int(b["owner"]) == int(f["id"]) else Businesses.takeable(b)
		if n <= 0:
			continue
		for i in mini(n, own):
			pay.append(float(b["wage"]))
	var k0 := ad - own
	if pay.size() <= k0:
		return 0
	pay.sort()
	pay.reverse()
	var worth := Families.land_worth(e, f, need)
	var out := 0
	while own - out > 0 and k0 + out < pay.size():
		if float(pay[k0 + out]) <= worth:
			break
		out += 1
	return out

## Generation: everyone finds work in family order.

static func original_wants(_game, _town: Dictionary, e: Dictionary, _si: int, day: float) -> void:
	var hd := Herds.H(e)
	var wak: Dictionary = hd["wak"]
	var aph := float(TownEcon.data()["land"]["acres_per_hand"])
	var reserve := float(Herds.A()["buy_reserve"])
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
		for own in Herds.of_owner(e, "s" if int(f["id"]) == 0 else "f", int(f["id"]), "cattle"):
			while short > 0 and int(own["g"]) >= 2:
				var oxh0 := Herds.herd_for(e, int(f["id"]), "oxen", day)
				if Herds._transfer(e, own, oxh0, "g", 1, "sold", "bought", "to the family's plough", "from the family's own herd", day) <= 0:
					break
				short -= 1
		for src in ["oxen", "cattle"]:
			if short <= 0:
				break
			var p := Herds.price(e, src)
			while short > 0 and float(f["purse"]) - p > reserve:
				var o := Herds._take_offer(e, src, ["g"], int(f["id"]))
				if o.is_empty():
					break
				var seller: Dictionary = hd["h"][str(int(o[0]))]
				var oxh := Herds.herd_for(e, int(f["id"]), "oxen", day)
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
		if not Herds.GRAZE.has(k) or String(h["ow"]) == "d":
			continue
		var need := int(float(h["t"]) * 0.5) - Herds.head(h)
		if need <= 0:
			continue
		need = mini(need, int(Herds.A()["restock_week"]))
		wak[k] = int(wak.get(k, 0)) + need
		var p2 := Herds.price(e, k)
		while need > 0 and Herds._coin(e, h) - p2 > reserve:
			var o2 := Herds._take_offer(e, k, ["g"], -1, int(h["id"]))
			if o2.is_empty():
				break
			var s2: Dictionary = hd["h"][str(int(o2[0]))]
			if Herds._transfer(e, s2, h, "g", 1, "sold", "bought", "to %s" % Herds.owner_text(e, h), "from %s" % Herds.owner_text(e, s2), day) > 0:
				Herds._add_coin(e, h, -p2)
				Herds._add_coin(e, s2, p2)
				hd["sok"][k] = int(hd["sok"].get(k, 0)) + 1
				need -= 1
	Herds._pot_buys(e, day)

## Families buy a beast for their own larder when one offered costs less than the meat in it at the market's price
## of keeping meat (x pot_value [ours]), they have the room and the coin (keeping pot_reserve): live animals traded
## by families, so a glut of beasts feeds the town instead of rotting. The family slaughters it at once (logged:
## bought, then slaughtered for its pot). At most pot_week buys a town a week [ours].

static func original_butcher_day(e: Dictionary, b: Dictionary, wd: float, toolf: float, mkt: Dictionary, share: float, _bdem: Dictionary) -> float:
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
	while kgcap > 1.0 and guard < 200:
		guard += 1
		var best := -1; var bv := 0.0
		var of: Array = hd["of"]
		for j in of.size():
			var o: Array = of[j]
			if int(o[2]) <= 0:
				continue
			var h: Dictionary = hd["h"].get(str(int(o[0])), {})
			if h.is_empty() or int(h[String(o[1])]) <= 0:
				continue
			var K := Herds.kind(String(h["k"]))
			var kg := float(K.get("meat", 0.0)) * float(Herds.A()["yield_age"][Herds.AGES.find(String(o[1]))])
			if kg <= 0.0:
				continue
			var v := Herds._carcass_value(e, h, String(o[1])) * share - Herds.price(e, String(h["k"]), String(o[1]))
			var per := v / kg
			if best < 0 or per > bv:
				best = j; bv = per
		if best < 0:
			break
		var o2: Array = hd["of"][best]
		var h2: Dictionary = hd["h"][str(int(o2[0]))]
		var age := String(o2[1])
		var p := Herds.price(e, String(h2["k"]), age) * (1.0 - Herds.sick(h2))   # a sick herd's beasts fetch less
		var val := Herds._carcass_value(e, h2, age) * share
		if val * float(Barge.B()["business"]["out_share"]) < float(Barge.B()["business"]["run_margin"]) * p:
			b["why"] = "no margin"
			break
		if float(b["till"]) < p:
			b["state"] = "wages"; b["why"] = "money for beasts"
			break
		var kg2 := float(Herds.kind(String(h2["k"])).get("meat", 0.0)) * float(Herds.A()["yield_age"][Herds.AGES.find(age)])
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
		var yl := Herds.yields(String(h2["k"]), age)
		var oc: Dictionary = b["oc"]
		for g in yl:
			oc[g] = float(oc.get(g, 0.0)) + float(yl[g])
		Herds._chain(b, "from", Herds.owner_text(e, h2), 1, String(h2["k"]))
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
		Herds._chain(b, "to", "the market", n, g)
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

static func original_family_pool(town: Dictionary, rng: RandomNumberGenerator) -> Array:
	var e: Dictionary = town["econ"]
	var day := float(Game.day)
	# last pool's people go home (the recruits not hired are replaced)
	var cands := []
	var hard_sum := 0.0
	var nf := 0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		if not f.has("pp"):
			Persons.sync(e, f, day)   # (the weekly family turn keeps the records level)
		for p in Persons.pp(f):
			if String(p[4]) == "hire":
				Persons.set_home(p)
		var d := Recruits.desperation(f)
		hard_sum += minf(1.0, Families.hardship(f))
		nf += 1
		if d <= 0.0:
			continue
		# equally desperate: one from each family first, then the second of each (a hard-up house does not send
		# all its grown-ups at once while its neighbours are just as badly off)
		var mine := []
		for p in Persons.pp(f):
			if String(p[4]) == "" and int(p[5]) < 0:
				mine.append([absi(hash([int(p[0]), int(day)])), p])
		mine.sort_custom(func(a, b): return a[0] < b[0])
		for i in mine.size():
			cands.append([d, i * 1000000000 + int(mine[i][0]) % 1000000000, mine[i][1], f])
	cands.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var avg_hard := hard_sum / maxf(1.0, float(nf))
	var n := 2 + int(town["size"]) + int(round(avg_hard * 4.0)) + rng.randi_range(0, 1)
	var out := []
	var cut := float(TownEcon.data()["family"]["recruit_hardship"])
	for c in cands.slice(0, n):
		var p: Array = c[2]
		var pick: Dictionary = c[3]
		# his trade is what he really does: a job the family holds, its own fields or herd, casual work, or his
		# real state (out of work, in the poorhouse); his skills and kit come from that work (kit_for)
		var role := Recruits.person_role(e, pick, p)
		var u := Recruits.make_recruit(rng, town, Recruits.kit_for(role))
		u.title = role["title"]
		Persons.bind(e, pick, p, u, "hire", day)   # he is the register person: name, birth day, age
		u.home_town = town["id"]
		var first: String = Persons.first_of(e, p)
		# an elder carries his years
		if int(p[6]) == 1:
			for a in ["STR", "AGI", "END"]:
				u.attrs[a] = maxi(DB.ATTR_MIN, int(round(float(u.attrs[a]) * 0.85)))
		# Douglas: the story is his real record (Backstory.story): where he comes from, what happened in time order,
		# why he is for hire now; his temper, his dream and a fitting like are woven in (v0.014: a story, not a list)
		u.backstory = Backstory.recruit_text(town, e, pick, first, u.name, role, u)
		# the poorhouse broth leaves its mark: weakened families' people come in thinner and slower
		var weak := float(pick.get("weak", 0.0))
		if weak > 0.0:
			for a in ["STR", "TOU", "END", "AGI"]:
				u.attrs[a] = maxi(DB.ATTR_MIN, int(round(float(u.attrs[a]) * (1.0 - 0.2 * weak))))
		# desperate people ask less and take worse terms: hardship cuts the price and the wage
		var h2 := Families.hardship(pick)
		u.hire_cost = maxi(5 * int(TownEcon.COIN), int(round(u.hire_cost * maxf(0.3, 1.0 - cut * h2) / 5.0)) * 5)
		u.wage = maxi(int(TownEcon.COIN), int(round(u.wage * maxf(0.5, 1.0 - 0.25 * h2))))
		out.append(u)
	return out

## Trades from what a family really does in the economy: a job at a business -> that trade; hands on the family
## land -> its crop; the family herd -> its animal; homeless casual work -> that work; nothing -> his real state.
