class_name DomesticAnimals
extends RefCounted
## Domestic work extends the counted Herds records; it never creates combat units.

## Family dogs eat real scraps, then food bought from the market above its human
## reserve. Whole purchased meals retain their uneaten kg on the owning record.
static func feed_dogs(e: Dictionary, day: float) -> void:
	var meal_kg := float(Herds.A()["kg_per_meal"])
	for h in Herds.herds(e).values():
		if String(h["k"]) != "dogs" or String(h["ow"]) == "d" or int(h.get("dog_feed_day", -1)) == int(day): continue
		if Herds.head(h) <= 0: continue
		var need := Herds.ge(h) * float(Herds.kind("dogs")["food_kg"]) * 7.0
		var stored := minf(need, float(h.get("dog_food_kg", 0.0)))
		h["dog_food_kg"] = maxf(0.0, float(h.get("dog_food_kg", 0.0)) - stored)
		var supplied := stored
		if String(h["ow"]) == "f":
			var f: Dictionary = e["fams"][int(h["oi"])]
			var scraps := minf(need - supplied, maxf(0.0, float(f.get("scraps_kg", 0.0))))
			f["scraps_kg"] = maxf(0.0, float(f.get("scraps_kg", 0.0)) - scraps)
			if e.has("sanitation"):
				e["sanitation"]["scraps_reused_kg"] = float(e["sanitation"].get("scraps_reused_kg", 0.0)) + scraps
			supplied += scraps
		for good in ["meat", "grain"]:
			var short := maxf(0.0, need - supplied)
			if short <= 0.000001: break
			var price := float(e["price"].get(good, 1.0)) * TownEcon.markup()
			var available := maxi(0, int(e["stock"].get(good, 0)) - int(ceil(float(e.get("need", {}).get(good, 0.0)))))
			var afford := int(maxf(0.0, Herds._coin(e, h) - float(Herds.A()["buy_reserve"])) / maxf(0.01, price))
			var bought := mini(int(ceil(short / meal_kg)), mini(available, afford))
			if bought <= 0: continue
			e["stock"][good] = int(e["stock"][good]) - bought
			var cost := float(bought) * price
			Herds._add_coin(e, h, -cost)
			var market: Dictionary = e["biz"][int(e["mkt"])]
			market["till"] = float(market["till"]) + cost
			e["stats"]["sales"] = float(e["stats"].get("sales", 0.0)) + cost
			TownEcon.led(e, "used", good, bought)
			var eaten := minf(short, float(bought) * meal_kg)
			supplied += eaten
			h["dog_food_kg"] = float(h["dog_food_kg"]) + float(bought) * meal_kg - eaten
		h["fed"] = minf(1.0, supplied / need) if need > 0.0 else 0.0
		h["dog_feed_day"] = int(day)
		h["dog_feed_owner"] = "%s:%d" % [h["ow"], int(h["oi"])]
		h["guard_heads"] = int(h["g"]) # buying more dogs cannot borrow their predecessors' feed
		h["hun"] = maxi(0, int(h["hun"]) - 7) if supplied + 0.000001 >= need else int(h["hun"]) + int(ceil(7.0 * (1.0 - float(h["fed"]))))
		if int(h["hun"]) > int(Herds.A()["starve_after"]):
			for age in ["y", "o", "g"]:
				var lost := int(ceil(float(h[age]) * (1.0 - float(h["fed"])) * float(Herds.A()["starve_k"])))
				Herds.change(e, h, age, -lost, "died", "starved", day)

## Guarding belongs to this exact owning household (including its herder's
## business), not the entire town. Hungry, sick, young or unfed dogs cannot guard.
static func raid_share(e: Dictionary, herd: Dictionary, day: float) -> float:
	var fid := Herds.grazer(e, herd)
	if fid < 0 or fid >= e["fams"].size() or e["fams"][fid].get("gone", false) or herd.has("work_band"): return 1.0
	var guards := 0.0
	for h in Herds.herds(e).values():
		if String(h["k"]) != "dogs" or String(h["ow"]) == "d" or h.has("work_band") or Herds.grazer(e, h) != fid: continue
		var fed_day := int(h.get("dog_feed_day", -999))
		if day < fed_day or day - fed_day >= 7.0 or int(h["hun"]) > 0: continue
		if String(h.get("dog_feed_owner", "")) != "%s:%d" % [h["ow"], int(h["oi"])]: continue
		guards += float(mini(int(h["g"]), int(h.get("guard_heads", 0)))) * float(h.get("fed", 0.0)) * (1.0 - Herds.sick(h))
	var cover := float(Herds.kind("dogs")["guard_head"])
	return 1.0 - minf(float(Herds.kind("dogs")["guard_max"]), guards * cover / maxf(1.0, float(Herds.head(herd))))

static func dog_target(e: Dictionary, fid: int) -> int:
	var stock := 0
	for h in Herds.herds(e).values():
		if Herds.GRAZE.has(String(h["k"])) and Herds.grazer(e, h) == fid:
			stock += Herds.head(h)
	return clampi(int(ceil(float(stock) / float(Herds.kind("dogs")["guard_head"]))), 0, 4)

## Existing live-market offers and actual purses supply guard dogs. Culture
## selects opening stock only; any owner can subsequently buy them.
static func buy_dogs(e: Dictionary, day: float) -> void:
	var hd := Herds.H(e)
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		var fid := int(f["id"])
		var own := Herds.of_family(e, fid).filter(func(h): return String(h["k"]) == "dogs")
		var have := 0
		for h in own: have += Herds.head(h)
		var short := maxi(0, dog_target(e, fid) - have)
		hd["wak"]["dogs"] = int(hd["wak"].get("dogs", 0)) + short
		var price := Herds.price(e, "dogs")
		while short > 0 and float(f["purse"]) - price > float(Herds.A()["buy_reserve"]):
			var offer := Herds._take_offer(e, "dogs", ["g", "y"], fid)
			if offer.is_empty(): break
			var seller: Dictionary = hd["h"][str(int(offer[0]))]
			var age := String(offer[1])
			var paid := Herds.price(e, "dogs", age)
			var buyer := Herds.herd_for(e, fid, "dogs", day)
			if Herds._transfer(e, seller, buyer, age, 1, "sold", "bought", "guard dog sold", "guard dog bought", day) <= 0: break
			f["purse"] = float(f["purse"]) - paid
			Herds._add_coin(e, seller, paid)
			hd["sok"]["dogs"] = int(hd["sok"].get("dogs", 0)) + 1
			short -= 1

## Donkeys/mules use the existing farm draught calculation, with half an ox's
## coverage per healthy adult. Pack animals away with a caravan are unavailable.
static func draught(e: Dictionary, fid: int) -> float:
	if not e.has("hd"): return 0.0
	var out := 0.0
	for h in Herds.of_family(e, fid):
		if String(h["k"]) != "donkeys" or h.has("work_band") or int(h["hun"]) > 0: continue
		out += float(int(h["g"]) + int(h["o"])) * float(Herds.kind("donkeys")["draught"]) * (1.0 - Herds.sick(h))
	return out

## A sailing caravan buys surplus adults through the native live-stock offers,
## or assigns its own estate's adults. The estate keeps the same counted record
## while its saved work_band identifies the animals' actual location/custody.
## This adds pack space to return trade; existing outgoing wagon loads stay valid.
static func prepare_pack(e: Dictionary, wb: Dictionary, day: float, trip: float) -> void:
	if not e.has("hd") or wb.has("pack_herd"): return
	var hd := Herds.H(e)
	var K := Herds.kind("donkeys")
	var days := maxf(14.0, trip * 2.0 + 7.0)
	var feed_per := float(K["feed"]) * days
	var price_feed := float(e["price"].get("fodder", 3.0)) * TownEcon.markup()
	var candidates := []
	for h in Herds.of_family(e, 0):
		if String(h["k"]) == "donkeys": candidates.append([h, int(h["g"]), []])
	for offer in hd["of"]:
		var h: Dictionary = hd["h"].get(str(int(offer[0])), {})
		if h.is_empty() or String(h["k"]) != "donkeys" or String(offer[1]) != "g" or String(h["ow"]) in ["s", "d"]: continue
		if int(offer[2]) > 0: candidates.append([h, int(offer[2]), offer])
	var pack: Dictionary = {}
	for candidate in candidates:
		var source: Dictionary = candidate[0]
		if source.has("work_band") or int(source["hun"]) > 0 or Herds.sick(source) > 0.0: continue
		for _i in mini(int(candidate[1]), int(source["g"])):
			if not pack.is_empty() and Herds.head(pack) >= int(K["pack_max"]): break
			var price := 0.0 if String(source["ow"]) == "s" else Herds.price(e, "donkeys")
			var own_feed := minf(feed_per, float(source["fod"]) / maxf(1.0, Herds.ge(source)))
			var buy_feed := int(ceil(maxf(0.0, feed_per - own_feed)))
			var available := int(e["barn"].get("fodder", 0)) + int(e["stock"].get("fodder", 0))
			if available < buy_feed or float(e["treasury"]) < price + float(buy_feed) * price_feed: break
			if pack.is_empty():
				pack = Herds.new_herd(e, "donkeys", "s", 0, day)
				pack["work_band"] = String(wb["id"])
				pack["pack_feed_day"] = int(day)
				wb["pack_herd"] = str(int(pack["id"]))
			if Herds._transfer(e, source, pack, "g", 1, "sold", "bought", "assigned to caravan pack work", "caravan pack animal", day) <= 0: break
			source["fod"] = float(source["fod"]) - own_feed
			pack["fod"] = float(pack["fod"]) + own_feed
			if price > 0.0:
				e["treasury"] = float(e["treasury"]) - price
				Herds._add_coin(e, source, price)
				candidate[2][2] = maxi(0, int(candidate[2][2]) - 1)
				hd["sok"]["donkeys"] = int(hd["sok"].get("donkeys", 0)) + 1
			if buy_feed > 0:
				pack["fod"] = float(pack["fod"]) + Herds._buy_fodder(e, pack, float(buy_feed), false)
	if not pack.is_empty():
		# Custody changes also invalidate the estate's cached care requirement.
		hd["ver"] = int(hd.get("ver", 0)) + 1

static func pack_herd(e: Dictionary, wb: Dictionary) -> Dictionary:
	if not e.has("hd") or not wb.has("pack_herd"): return {}
	var h: Dictionary = e["hd"]["h"].get(str(int(wb["pack_herd"])), {})
	return h if String(h.get("k", "")) == "donkeys" and String(h.get("ow", "")) == "s" and int(h.get("oi", -1)) == 0 \
		and String(h.get("work_band", "")) == String(wb.get("id", "")) else {}

static func pack_capacity(e: Dictionary, wb: Dictionary) -> float:
	var h := pack_herd(e, wb)
	if h.is_empty() or int(h["hun"]) > 0: return Caravans.CAPACITY_KG
	return Caravans.CAPACITY_KG + float(h["g"]) * float(Herds.kind("donkeys")["pack_kg"]) * (1.0 - Herds.sick(h))

## Only the carried, already paid hay feeds animals away on roads, including
## escort delays. They cannot also graze, plough, breed or be sold at home.
static func pack_tick(game, wb: Dictionary, trim_cargo: bool = true) -> void:
	var town: Dictionary = game.world.get("towns", {}).get(String(wb.get("origin", "")), {})
	if not TownEcon.has_econ(town): return
	var e: Dictionary = town["econ"]
	var h := pack_herd(e, wb)
	if h.is_empty(): return
	var days := maxi(0, int(game.day) - int(h["pack_feed_day"]))
	if days <= 0: return
	var need := Herds.feed_day(h) * float(days)
	var supplied := minf(need, float(h["fod"]))
	h["fod"] = float(h["fod"]) - supplied
	h["pack_feed_day"] = int(game.day)
	if supplied + 0.000001 >= need:
		h["hun"] = maxi(0, int(h["hun"]) - days)
	else:
		h["hun"] = int(h["hun"]) + days
		if int(h["hun"]) > int(Herds.A()["starve_after"]):
			var lost := int(ceil(float(h["g"]) * (1.0 - supplied / maxf(0.001, need)) * float(Herds.A()["starve_k"]) * float(days) / 7.0))
			Herds.change(e, h, "g", -lost, "died", "starved on the pack road", float(game.day))
	# Failed pack capacity cannot keep carrying an overfull return load. Any
	# abandoned counted goods use the caravan's existing loss book.
	if not trim_cargo: return # lost/plundered cargo is already settled by Caravans
	var excess := Caravans.cargo_weight(wb["cargo"]) - pack_capacity(e, wb)
	var cargo: Dictionary = wb["cargo"].get("goods", {})
	for good in cargo.keys():
		if excess <= 0.000001: break
		var kg := float(Goods.table().get(good, {}).get("weight", 0.5))
		if kg <= 0.0: continue
		var lost := mini(int(cargo[good]), int(ceil(excess / kg)))
		cargo[good] = int(cargo[good]) - lost
		TownEcon.goods_lost[good] = int(TownEcon.goods_lost.get(good, 0)) + lost
		excess -= float(lost) * kg

static func finish_pack(game, wb: Dictionary, lost: bool = false) -> void:
	var town: Dictionary = game.world.get("towns", {}).get(String(wb.get("origin", "")), {})
	if not TownEcon.has_econ(town): return
	var e: Dictionary = town["econ"]
	var h := pack_herd(e, wb)
	if h.is_empty(): return
	pack_tick(game, wb, not lost)
	if lost:
		Herds.change(e, h, "g", -int(h["g"]), "died", "lost with plundered caravan", float(game.day))
		h["fod"] = 0.0
	h.erase("work_band"); h.erase("pack_feed_day")
	Herds.H(e)["ver"] = int(Herds.H(e).get("ver", 0)) + 1
	wb.erase("pack_herd")
