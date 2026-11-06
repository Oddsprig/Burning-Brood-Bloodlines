extends RefCounted
## SOURCE DELIVERY: execution UNRUN. One fresh Normal world, one history day;
## detached deterministic cases call native feed, raid, market and pack paths.
## No battles, seasonal waits, personal saves, or file cleanup.
var fails := 0
var checks := 0
var template: Dictionary = {}
var raider_faction := ""

class Harness extends RefCounted:
	var world: Dictionary = {}
	var day := 1.0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL V086: ", label)

func exact(a, b) -> bool:
	return JSON.stringify(Game._serialize(a), "", true, true) == JSON.stringify(Game._serialize(b), "", true, true)

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_domestic_v086_%d.json" % OS.get_process_id()
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Monsters.new_world_creatures = false
	Game.new_game(8606)
	CampaignWorld.presim_step(Game, 1)
	var towns: Array = Game.world["towns"].values().filter(func(t): return TownEcon.has_econ(t))
	check(not towns.is_empty(), "Normal world has economy towns")
	if towns.is_empty(): return fails
	template = towns[0]["econ"].duplicate(true)
	for t in towns:
		if Persons.race_of(t["econ"]) == "human":
			raider_faction = String(t["faction"])
			break
	check(raider_faction != "", "native human faction available for the raid fixture")
	if raider_faction == "": return fails
	_cultures(towns)
	_feed()
	_raids()
	_guard_receipts()
	_breeding()
	_no_dog_meat()
	_feathers()
	_pack()
	_load_twice(towns[0])
	Game.wait_save()
	print("DOMESTIC V086 checks=%d failures=%d" % [checks, fails])
	return fails

func _econ() -> Dictionary:
	var e := template.duplicate(true)
	# Retire the template's physical barn stock through its native ownership book.
	for g in (e["barn"] as Dictionary).keys():
		HarvestClaims.lose(e, String(g), int(e["barn"][g]))
	e.erase("hd")
	Herds.H(e)
	e["fams"] = []
	for fid in 3:
		var f := Families._blank(fid)
		f["name"] = "GuardFixture%d" % fid
		f["m"] = 1; f["purse"] = 100000.0; f["worked"] = 1.0; f["ox"] = 0
		f["estate"] = fid == 0
		e["fams"].append(f)
	e["mkt"] = 0
	e["biz"] = [{"id": 0, "type": "market", "owner": 2, "till": 1000000.0, "spend": 0.0}]
	e["treasury"] = 100000.0
	e["herd"] = {}; e["wherd"] = {}
	e["stock"] = {}; e["barn"] = {}; e["need"] = {}; e["dem"] = {}
	e["stats"] = {"sales": 0.0}
	e["led"] = {"made": {}, "used": {}, "spoil": {}, "in": {}, "out": {}}
	for g in TownEcon.data()["goods"]:
		e["stock"][g] = 0; e["barn"][g] = 0
	return e

func _herd(e: Dictionary, k: String, grown: int, fid: int = 1, ow: String = "f") -> Dictionary:
	var h := Herds.new_herd(e, k, ow, fid, 1.0)
	Herds.change(e, h, "g", grown, "bought", "counted test fixture", 1.0)
	h["t"] = grown
	return h

func _coins(e: Dictionary) -> float:
	var out := float(e["treasury"])
	for f in e["fams"]: out += float(f["purse"])
	for b in e["biz"]: out += float(b["till"])
	return out

func _cultures(towns: Array) -> void:
	for k in ["cattle", "horses", "sheep", "goats", "pigs", "hens", "dogs", "donkeys"]:
		check(not Herds.kind(k).is_empty(), "domestic species: " + k)
	check(Herds.kinds().size() == 9, "eight domestic species plus the native oxen work group")
	var rows: Dictionary = Herds.A()["start"]
	check(float(rows["middle"]["small"]["dogs"][0]) > 0.0, "Middle households start with dogs")
	check(float(rows["northern"]["graze"]["sheep"]) > float(rows["northern"]["graze"]["pigs"]), "Northern sheep before pigs")
	check(float(rows["eastern"]["graze"]["horses"]) + float(rows["eastern"]["graze"]["goats"]) > 0.6, "Eastern horse/goat emphasis")
	check(float(rows["orc"]["graze"]["pigs"]) > 0.5 and rows["orc"]["small"].has("dogs"), "Orc pig/dog opening mix")
	check(not rows["goblin"]["graze"].has("cattle") and not rows["goblin"]["graze"].has("horses"), "Goblins start without cattle/horses")
	check(float(rows["moon_elf"]["head_mult"]) < 1.0 and rows["moon_elf"]["graze"].has("horses"), "Moon elves keep fewer meat beasts and horses")
	check(rows["dwarf"]["graze"].has("donkeys") and rows["dwarf"]["valley"].has("cattle"), "Dwarf donkeys and valley cattle")
	var dogs := 0
	for t in towns:
		var e: Dictionary = t["econ"]
		var row: Dictionary = rows.get(String(e["culture"]), rows["middle"])
		for h in Herds.herds(e).values():
			check(Herds.ledger_head(h) == Herds.head(h), "opening herd ledger closes")
			if String(h["k"]) == "dogs":
				dogs += Herds.head(h)
				check(row["small"].has("dogs") and String(h["ow"]) == "f", "opening dogs belong to a configured household")
			elif Herds.GRAZE.has(String(h["k"])):
				check(row["graze"].has(String(h["k"])), "worldgen respects its culture's grazing mix")
	check(dogs > 0, "fresh native generation actually creates dogs")
	check(not Herds.GRAZE.has("dogs"), "dogs stay outside pasture raid selection")

func _feed() -> void:
	var e := _econ()
	var h := _herd(e, "dogs", 2)
	e["fams"][1]["scraps_kg"] = 0.5
	e["stock"]["meat"] = 100; e["need"]["meat"] = 10.0
	var coins := _coins(e)
	var purse := float(e["fams"][1]["purse"])
	DomesticAnimals.feed_dogs(e, 1.0)
	var bought := 100 - int(e["stock"]["meat"])
	var need := 2.0 * float(Herds.kind("dogs")["food_kg"]) * 7.0
	check(bought > 0 and is_equal_approx(0.5 + bought * float(Herds.A()["kg_per_meal"]), need + float(h["dog_food_kg"])), "dog meals conserve scraps, paid food and remainder")
	check(is_equal_approx(_coins(e), coins) and float(e["fams"][1]["purse"]) < purse, "dog payer debited and seller credited")
	check(int(e["led"]["used"].get("meat", 0)) == bought and int(h["hun"]) == 0, "purchased dog food booked once")
	var once := e.duplicate(true)
	DomesticAnimals.feed_dogs(e, 1.0)
	check(exact(e, once), "same-day feed cannot charge or reuse scraps twice")
	e = _econ(); h = _herd(e, "dogs", 2)
	e["stock"]["meat"] = 10; e["need"]["meat"] = 10.0
	e["stock"]["grain"] = 10; e["need"]["grain"] = 10.0
	DomesticAnimals.feed_dogs(e, 1.0)
	check(int(e["stock"]["meat"]) == 10 and int(e["stock"]["grain"]) == 10 and int(h["hun"]) > 0, "dogs cannot eat the market's human reserve")
	e = _econ(); h = _herd(e, "dogs", 2)
	e["fams"][1]["purse"] = 0.0; e["stock"]["meat"] = 100
	h["hun"] = int(Herds.A()["starve_after"]) + 1
	DomesticAnimals.feed_dogs(e, 1.0)
	check(int(e["stock"]["meat"]) == 100 and int(h["led"]["d"].get("starved", 0)) > 0, "no purse means no free feed; starvation is a counted death")

func _raid_case(mode: String, wolves: bool) -> Dictionary:
	var e := _econ()
	var prey := _herd(e, "goats", 20)
	if mode != "absent":
		var dog := _herd(e, "dogs", 2, 2 if mode == "other owner" else 1)
		e["fams"][int(dog["oi"])]["scraps_kg"] = 10.0
		if mode != "unfed": DomesticAnimals.feed_dogs(e, 1.0)
		if mode == "starved": dog["hun"] = 1
		if mode == "sick": dog["inf"] = {"distemper": 1.0}
		if mode == "dead": Herds.change(e, dog, "g", -2, "died", "test death", 1.0)
		if mode == "young":
			Herds.change(e, dog, "g", -2, "sold", "test age fixture", 1.0)
			Herds.change(e, dog, "y", 2, "bought", "puppies", 1.0)
	var game := Harness.new()
	game.day = 8.0 if mode == "expired" else 1.0
	var units := []
	for _i in 8: units.append(Unit.create("human", raider_faction))
	var wb := {"id": "v086_raider", "kind": "bandit", "faction": raider_faction, "units": units,
		"raid": {"wolves": wolves}, "stores": {}, "last_fed": -99.0}
	HerdRaids.take(game, wb, {"econ": e}, prey)
	var lost := 20 - Herds.head(prey)
	var made := int(e["led"]["made"].get("fresh_meat", 0))
	var expected := lost * int(floor(float(Herds.yields("goats", "g")["fresh_meat"])))
	check(made == expected and int(prey["led"]["st"]) == lost and Herds.ledger_head(prey) == Herds.head(prey), mode + ": real raid debit and carcass meat agree")
	var consumed := int(e["led"]["used" if wolves else "out"].get("fresh_meat", 0))
	check(made == consumed + int(e["led"]["spoil"].get("fresh_meat", 0)), mode + ": every carcass meal is eaten/carried/left")
	check(int(wb["stores"].get("meat", 0)) == (0 if wolves else consumed), mode + ": wolves eat, thieves carry actual meals")
	return {"lost": lost, "made": made}

func _raids() -> void:
	for wolves in [false, true]:
		var unguarded := _raid_case("absent", wolves)
		var guarded := _raid_case("fed", wolves)
		check(int(unguarded["lost"]) > 0 and int(guarded["lost"]) < int(unguarded["lost"]), "fed owner's dogs reduce ACTUAL predator/thief head losses")
		check(int(guarded["made"]) < int(unguarded["made"]), "saved animals cannot still produce carcasses")
		for mode in ["unfed", "starved", "other owner", "dead", "young", "sick", "expired"]:
			check(_raid_case(mode, wolves) == unguarded, mode + ": no phantom protection")
	var e := _econ()
	var prey := _herd(e, "goats", 1)
	_herd(e, "dogs", 2)
	e["fams"][1]["scraps_kg"] = 10.0
	DomesticAnimals.feed_dogs(e, 1.0)
	var game := Harness.new()
	var wb := {"id": "v086_deterred", "kind": "bandit", "faction": raider_faction,
		"units": [Unit.create("human", raider_faction)], "raid": {"wolves": true}, "stores": {}, "last_fed": -99.0}
	HerdRaids.take(game, wb, {"econ": e}, prey)
	check(Herds.head(prey) == 1 and e["led"]["made"].is_empty() and float(wb["last_fed"]) == -99.0, "fully deterred raid grants neither carcasses nor free predator feeding")

func _guard_receipts() -> void:
	var e := _econ()
	var prey := _herd(e, "goats", 20)
	var dog := _herd(e, "dogs", 2)
	e["fams"][1]["scraps_kg"] = 10.0
	DomesticAnimals.feed_dogs(e, 1.0)
	check(DomesticAnimals.raid_share(e, prey, 1.0) < 1.0, "fed receipt initially protects its owner")
	Herds.change(e, dog, "g", -2, "died", "test death", 1.0)
	Herds.change(e, dog, "g", 2, "bought", "unfed replacements", 1.0)
	check(DomesticAnimals.raid_share(e, prey, 1.0) == 1.0, "replacements cannot reuse dead dogs' feed receipts")
	DomesticAnimals.feed_dogs(e, 2.0)
	var buyer := _herd(e, "dogs", 0, 2)
	Herds._transfer(e, dog, buyer, "g", 2, "sold", "bought", "sold", "bought", 2.0)
	check(DomesticAnimals.raid_share(e, prey, 2.0) == 1.0, "sold dogs no longer protect the seller")
	var other := _herd(e, "goats", 20, 2)
	check(DomesticAnimals.raid_share(e, other, 2.0) == 1.0, "buyer must feed newly acquired dogs")
	e["fams"][2]["scraps_kg"] = 10.0
	DomesticAnimals.feed_dogs(e, 3.0)
	check(DomesticAnimals.raid_share(e, other, 3.0) < 1.0, "buyer obtains protection by actually feeding its dogs")
	var business := _herd(e, "goats", 20, 0, "b")
	check(DomesticAnimals.raid_share(e, business, 3.0) < 1.0, "owner's business shares that owner's fed guards")
	check(Herds.head(dog) + Herds.head(buyer) == 2 and Herds.ledger_head(dog) == 0 and Herds.ledger_head(buyer) == 2, "dog sale conserves counted heads and ledgers")

func _breeding() -> void:
	for mode in ["breeding adults", "no sire", "no grown females", "wrong season"]:
		var e := _econ()
		var dog := _herd(e, "dogs", 100 if mode != "no grown females" else 0)
		dog["bred"] = 1.0; dog["bred_s"] = 0
		Herds._males(e)
		if mode == "no sire": e["hd"]["_male"]["dogs"] = 0.0
		var rng := RandomNumberGenerator.new(); rng.seed = 86
		Herds._life(e, dog, 1 if mode == "wrong season" else 0, 1.0, rng)
		check((int(dog["led"]["b"]) > 0) == (mode == "breeding adults"), mode + ": native age/female-share/sire-coverage/season gates")
		check(Herds.ledger_head(dog) == Herds.head(dog), mode + ": births and deaths close")

func _no_dog_meat() -> void:
	var e := _econ()
	var dog := _herd(e, "dogs", 4)
	check(Herds.yields("dogs", "g").is_empty() and Herds._carcass(e, dog, "g", 1, false).is_empty(), "dogs yield neither meat nor carcass goods")
	e["hd"]["of"] = [[int(dog["id"]), "g", 4, ""]]
	dog["hun"] = 100
	Herds._unsold(e, 3, 1.0)
	check(Herds.head(dog) == 4 and int(dog["led"]["sl"]) == 0, "unsold hungry dogs are never slaughtered")
	e["hd"]["of"] = [[int(dog["id"]), "g", 4, ""]]
	var b := {"id": 1, "type": "butcher", "owner": 2, "workers": 1, "till": 100000.0, "oc": {}, "state": "busy", "why": ""}
	e["biz"].append(b); e["dem"]["fresh_meat"] = 10000.0
	Herds.butcher_day(e, b, 5.0, 1.0, e["biz"][0], 0.9, {})
	check(Herds.head(dog) == 4 and not e["led"]["made"].has("fresh_meat"), "butcher cannot turn dog offers into meat")

func _feathers() -> void:
	var e := _econ()
	var hens := _herd(e, "hens", 10)
	hens["fed"] = 1.0
	# A retained fractional bundle plus this week's real flock make one bundle.
	hens["feather_carry"] = 0.95
	Herds._products(e, 0, 1.0)
	check(int(e["barn"].get("feathers", 0)) == 1 and int(e["led"]["made"].get("feathers", 0)) == 1, "real poultry moult delivers counted feather bundles")
	var once := e.duplicate(true)
	BowsEcon._fowl(e)
	check(exact(e, once), "legacy farm feather stand-in cannot double-count real poultry")
	for recipe in TownEcon.data()["businesses"]["fletcher"]["recipes"]:
		check(float(recipe["in"].get("feathers", 0.0)) > 0.0 and not recipe["out"].is_empty(), "native arrow recipe requires consumed feathers")

func _pack() -> void:
	var e := _econ()
	var source := _herd(e, "donkeys", 2)
	source["fod"] = 100.0
	check(DomesticAnimals.draught(e, 1) == 1.0, "two healthy donkeys supply one ox-equivalent of farm work")
	var unassisted := Families._cultivation_hands(e["fams"][1], 8.0)
	check(Families._cultivation_hands(e["fams"][1], 8.0, e) < unassisted, "donkey draught affects native crop labour")
	e["hd"]["of"] = [[int(source["id"]), "g", 2, ""]]
	var wb := {"id": "v086_pack", "origin": "home", "cargo": {"goods": {}, "items": []}}
	var coins := _coins(e)
	DomesticAnimals.prepare_pack(e, wb, 1.0, 3.0)
	var pack := DomesticAnimals.pack_herd(e, wb)
	check(not pack.is_empty(), "pack work assigns actual live-market donkeys")
	if pack.is_empty(): return
	check(Herds.head(source) == 0 and Herds.head(pack) == 2 and is_equal_approx(_coins(e), coins), "pack purchase transfers heads and pays the seller")
	check(is_equal_approx(float(source["fod"]) + float(pack["fod"]), 100.0), "pack hay moves from its counted owner without duplication")
	check(DomesticAnimals.draught(e, 1) == 0.0 and DomesticAnimals.draught(e, 0) == 0.0, "travelling animals cannot plough at home")
	check(DomesticAnimals.pack_capacity(e, wb) == Caravans.CAPACITY_KG + 160.0, "actual assigned adults add pack capacity")
	e["hd"]["of"].append([int(pack["id"]), "g", 1, ""])
	check(Herds._take_offer(e, "donkeys", ["g"]).is_empty(), "stale offers cannot sell animals already on the road")
	check(int(Herds.herd_for(e, 0, "donkeys", 1.0)["id"]) != int(pack["id"]), "home receipts cannot be merged into an away herd")
	var game := Harness.new(); game.world = {"towns": {"home": {"econ": e}}}; game.day = 2.0
	var hay := float(pack["fod"])
	DomesticAnimals.pack_tick(game, wb)
	check(is_equal_approx(hay - float(pack["fod"]), 1.2), "road feed consumes exactly one day's carried hay")
	var after := float(pack["fod"])
	DomesticAnimals.pack_tick(game, wb)
	check(float(pack["fod"]) == after, "road feed is idempotent on the same day")
	pack["hun"] = 1
	var kg := float(Goods.table()["grain"]["weight"])
	wb["cargo"]["goods"]["grain"] = int(Caravans.CAPACITY_KG / kg) + 10
	var loss0 := int(TownEcon.goods_lost.get("grain", 0))
	game.day = 3.0; pack["fod"] = 0.0
	DomesticAnimals.pack_tick(game, wb)
	check(Caravans.cargo_weight(wb["cargo"]) <= DomesticAnimals.pack_capacity(e, wb), "failed pack capacity drops real excess cargo")
	check(int(TownEcon.goods_lost.get("grain", 0)) - loss0 == 10, "dropped cargo booked exactly once")
	game.day = 4.0
	loss0 = int(TownEcon.goods_lost.get("grain", 0))
	DomesticAnimals.finish_pack(game, wb, true)
	check(Herds.head(pack) == 0 and Herds.ledger_head(pack) == 0 and not wb.has("pack_herd"), "lost caravan debits its actual pack animals and clears custody")
	check(int(TownEcon.goods_lost.get("grain", 0)) == loss0, "lost/plundered settlement cannot double-book already settled cargo")
	# A healthy homecoming retains the same counted record. JSON + the native
	# herd loader must also retain the custody link and the feed clock twice.
	e = _econ(); source = _herd(e, "donkeys", 2, 0, "s"); source["fod"] = 100.0
	wb = {"id": "v086_return", "origin": "home", "cargo": {"goods": {}, "items": []}}
	DomesticAnimals.prepare_pack(e, wb, 1.0, 3.0)
	var pack_id := str(int(DomesticAnimals.pack_herd(e, wb)["id"]))
	for _load in 2:
		var saved: Dictionary = JSON.parse_string(Game.save_text(Game._serialize({"econ": e, "band": wb})))
		Game.restore_exact(saved)
		var restored: Dictionary = Game._deserialize(saved)
		e = restored["econ"]; wb = restored["band"]
		Herds._fix(e["hd"])
		pack = DomesticAnimals.pack_herd(e, wb)
		check(not pack.is_empty() and str(int(pack["id"])) == pack_id and int(pack["pack_feed_day"]) == 1, "load retains pack identity, custody and feed clock")
	game.world = {"towns": {"home": {"econ": e}}}; game.day = 1.0
	DomesticAnimals.finish_pack(game, wb)
	pack = e["hd"]["h"][pack_id]
	check(Herds.head(pack) == 2 and not pack.has("work_band") and not wb.has("pack_herd"), "healthy return releases the same animals to their estate")
	var returned := e.duplicate(true)
	DomesticAnimals.finish_pack(game, wb)
	check(exact(e, returned), "duplicate homecoming creates no animals or hay")
	e = _econ(); source = _herd(e, "donkeys", 2)
	e["hd"]["of"] = [[int(source["id"]), "g", 2, ""]]
	wb = {"id": "v086_no_feed", "origin": "home", "cargo": {"goods": {}, "items": []}}
	DomesticAnimals.prepare_pack(e, wb, 1.0, 3.0)
	check(not wb.has("pack_herd") and Herds.head(source) == 2, "no available hay means no free pack animals/capacity")

func _load_twice(town: Dictionary) -> void:
	var tid := String(town["id"])
	var e: Dictionary = town["econ"]
	var dog := _herd(e, "dogs", 2)
	var dog_id := str(int(dog["id"]))
	e["fams"][1]["scraps_kg"] = float(e["fams"][1].get("scraps_kg", 0.0)) + 10.0
	DomesticAnimals.feed_dogs(e, float(Game.day))
	var records: Dictionary = e["hd"]["h"].duplicate(true)
	var heads := Herds.town_heads(e).duplicate(true)
	var coins := Barge.holdings(Game)
	Game.save_game(); Game.wait_save()
	for iteration in 2:
		check(Game.load_game(), "native saved world loads #%d" % (iteration + 1))
		e = Game.world["towns"][tid]["econ"]
		check(exact(e["hd"]["h"], records) and exact(Herds.town_heads(e), heads), "load preserves every herd identity, age count, feed receipt and total")
		check(Barge.holdings(Game) == coins and e["hd"]["h"].has(dog_id), "load does not manufacture money or remove dogs")
		var once := e.duplicate(true)
		DomesticAnimals.feed_dogs(e, float(Game.day))
		check(exact(e, once), "loaded same-day feed remains idempotent")
