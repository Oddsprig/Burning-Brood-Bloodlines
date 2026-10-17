extends RefCounted
## Differential local armory procurement against the frozen pre-v009 uncached pass.
## No world generation, timing thresholds, or factory-created people/equipment.
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func _item(uid: int, tid: String) -> Item:
	var it := Item.new()
	it.uid = uid; it.tid = tid; it.material = "copper"; it.quality = 2
	it.mark = {"t": "arms_fixture", "n": "registered fixture smith"}
	return it

func _fixture(cash: float = 1000000.0) -> Dictionary:
	var units := []
	for i in 24:
		var u := Unit.new()
		u.uid = 1000 + i; u.race = "human"; u.faction = "middle_kingdom"
		u.title = "man-at-arms" if i % 3 != 2 else "spearman"
		u.home_town = "arms_fixture"; u.dead = i == 23
		units.append(u)
	# Preserve an existing two-handed weapon; its bearer must receive no shield.
	units[0].equip["main_hand"] = _item(2000, "dane_axe")
	var e := {"stock": {}, "price": {}, "pop": 24, "treasury": cash,
		"mkt": 0, "biz": [{"type": "market", "till": 77.0}],
		"stats": {"sales": 0.0, "militia_bill": 1.0}, "led": {"used": {}}, "day": 4}
	var town := {"id": "arms_fixture", "name": "Armory fixture", "culture": "middle",
		"faction": "middle_kingdom", "size": 2, "wealth": 3, "econ": e,
		"prices": {}, "material_prices": {}, "shop": [],
		"armory_items": [_item(2001, "hacking_cleaver"), _item(2002, "mail_coif"),
			_item(2003, "arming_sword"), _item(2004, "kite_shield"), _item(2005, "tunic")]}
	# These arrive only after the initial negative results; the second pass must reset them.
	town["shop"] = [_item(3000, "nasal_helm"), _item(3001, "mail_shirt"),
		_item(3002, "arming_sword"), _item(3003, "boar_spear")]
	Game.world = {"towns": {"arms_fixture": town}, "warbands": {"guard": {"units": units, "kind": "guards"}},
		"town_guards": {"arms_fixture": "guard"}}
	return town

func _ids(town: Dictionary) -> Array:
	var ids := []
	for it in town["shop"] + town["armory_items"]: ids.append(it.uid)
	for u in TownDefence.garrison(Game, "arms_fixture"):
		for it in u.equip.values(): ids.append(it.uid)
	ids.sort()
	return ids

func _snapshot(town: Dictionary) -> Dictionary:
	var kit := []
	for u in TownDefence.garrison(Game, "arms_fixture"):
		var slots := {}
		for slot in u.equip: slots[slot] = u.equip[slot].uid
		kit.append({"uid": u.uid, "dead": u.dead, "equip": slots})
	var arm := []; var shop := []
	for it in town["armory_items"]: arm.append(it.uid)
	for it in town["shop"]: shop.append(it.uid)
	var e: Dictionary = town["econ"]
	return {"kit": kit, "arm": arm, "shop": shop, "treasury": e["treasury"],
		"till": e["biz"][0]["till"], "sales": e["stats"]["sales"], "used": e["led"]["used"].duplicate(true),
		"ledger": ArmsTrade.ledger.duplicate(true), "target": e["arms_tgt"].duplicate(true),
		"have": e["arms_have"].duplicate(true), "short": e["arms_short"].duplicate(true),
		"short_days": e["arms_sd"].duplicate(true), "due": e["arms_due"], "log": e.get("arms_log", []).duplicate()}

func _differential(cash: float) -> void:
	var town: Dictionary = _fixture(cash)
	var before := _ids(town)
	ArmsTrade.ledger = {}
	_old_econ_daily(Game, town, town["econ"], 4, false)
	var old: Dictionary = _snapshot(town)
	check(_ids(town) == before, "uncached reference conserves every Item occurrence")
	town = _fixture(cash)
	before = _ids(town)
	var money := float(town["econ"]["treasury"]) + float(town["econ"]["biz"][0]["till"])
	var next_item := Item._next_uid; var next_unit := Unit._next_uid
	ArmsTrade.ledger = {}
	ArmsTrade.econ_daily(Game, town, town["econ"], 4, false)
	var current: Dictionary = _snapshot(town)
	for key in old: check(current[key] == old[key], "cached local pass preserves " + str(key))
	check(_ids(town) == before, "cached procurement conserves every Item occurrence")
	check(Item._next_uid == next_item and Unit._next_uid == next_unit, "procurement creates no Items or Units")
	check(absf(float(current["treasury"]) + float(current["till"]) - money) < 0.000001, "treasury pays actual market without creating coin")
	var units: Array = TownDefence.garrison(Game, "arms_fixture")
	check(units[0].equip["main_hand"].uid == 2000 and not units[0].equip.has("off_hand"), "two-handed existing equipment retains native shield exclusion")
	check(units[23].equip.is_empty(), "dead guards receive no equipment")
	if cash > 0.0:
		check(int(current["ledger"].get("bought", 0)) == 4, "all four real affordable shop pieces purchased")
		check(units[1].equip.get("helm") != null and units[1].equip["helm"].uid == 3000, "post-purchase pass resets prior helm miss")
		check(units[0].equip.get("body") != null and units[0].equip["body"].uid == 3001, "post-purchase pass resets prior optional body miss")
	else:
		check(int(current["ledger"].get("bought", 0)) == 0 and float(current["sales"]) == 0.0, "unfunded treasury never buys equipment")

func _miss_scope() -> void:
	var town: Dictionary = _fixture()
	(town["shop"] as Array).clear(); (town["armory_items"] as Array).clear()
	# Nonempty incompatible stock makes failed lookups exercise the armory scan.
	town["armory_items"].append(_item(4000, "splint_greaves"))
	var units: Array = TownDefence.garrison(Game, "arms_fixture")
	var miss := {}
	ArmsTrade.rekit_units(Game, town, units, false, miss, true)
	var key := "middle_kingdom|man-at-arms|helm"
	check(miss.has(key), "first failed slot is registered for repeated actual troop loadouts")
	var previous: Dictionary = miss.duplicate()
	var before := _ids(town)
	ArmsTrade.rekit_units(Game, town, units, false, miss, true)
	check(miss == previous and _ids(town) == before, "same shrinking-pass failures reuse the cache without ownership changes")
	var arriving := _item(4001, "nasal_helm")
	town["armory_items"].append(arriving)
	ArmsTrade.rekit_units(Game, town, units, false, miss, true)
	check(town["armory_items"].has(arriving), "a deliberately reused stale pass cache demonstrates why stock arrival must reset it")
	ArmsTrade.rekit_units(Game, town, units, false, {}, true)
	check(units[0].equip.get("helm") == arriving and not town["armory_items"].has(arriving), "fresh independent pass finds the newly arrived exact Item")

func run(_tree: SceneTree) -> int:
	var saved_world: Dictionary = Game.world
	var saved_ledger: Dictionary = ArmsTrade.ledger
	_differential(1000000.0)
	_differential(0.0)
	_miss_scope()
	_selection_differential()
	_note_value_differential()
	Game.world = saved_world; ArmsTrade.ledger = saved_ledger
	print("Arms performance conservation: ", checks, " checks; ", fails, " failures")
	return fails

## Frozen original cost-note arithmetic, independent of the current note helper.
func _old_note_due(town: Dictionary, short: Dictionary, cant_pay: float, cant_n: int) -> float:
	var n := 0
	for c in short: n += int(short[c])
	if n <= 0: return 0.0
	var ref := cant_pay / float(cant_n) if cant_n > 0 else 0.0
	if ref <= 0.0:
		var vs := 0.0; var k := 0
		for it in ArmsTrade.armory(town):
			vs += Economy.base_value(town, it); k += 1
		ref = vs / float(k) if k > 0 else 0.0
	return ref * float(n)

func _note_value_differential() -> void:
	var town: Dictionary = _fixture()
	var arm := []
	for i in 20:
		var it: Item = _item(7000 + i, "arming_sword")
		it.wear = float(i) / 25.0; it.mark["n"] = "Distinct real owner " + str(i)
		arm.append(it)
	var different_quality: Item = _item(7020, "arming_sword"); different_quality.quality = 3; arm.append(different_quality)
	var different_material: Item = _item(7021, "arming_sword"); different_material.material = "tin"; arm.append(different_material)
	for gem in ["ruby", "sapphire", "", "ruby"]:
		var it: Item = _item(7022 + arm.size(), "arming_sword")
		it.quality = DB.LEGEND; it.legend = {"gem": gem, "name": "Individual legend " + str(it.uid)}; arm.append(it)
	for vr in [1.0, 1.00000000001, 1.25, 1.25]:
		var it: Item = _item(7050 + arm.size(), "self_bow")
		it.material = "wood"; it.vr = vr; arm.append(it)
	town["armory_items"] = arm
	# Native ignored metadata must not affect the key or force a bad conversion.
	arm[0].legend = {"gem": 0}; arm[0].broken = true; arm[0].dull = 0.5
	town["econ"]["bow_target"] = 7
	town["shop"].append(_item(7100, "self_bow"))
	var before: String = JSON.stringify(Game._serialize(town))
	var owned_before: Array = _ids(town)
	var rng_state: int = Game.rng.state; var next_unit: int = Unit._next_uid; var next_item: int = Item._next_uid
	var values := {}; var old_sum := 0.0; var current_sum := 0.0
	for it in arm:
		var expected: float = Economy.base_value(town, it)
		var current: float = ArmsTrade._note_value(town, it, values)
		check(current == expected, "unchanged-town note price exactly matches native valuation for Item %d" % it.uid)
		old_sum += expected; current_sum += current
	check(current_sum == old_sum, "cached prices preserve original floating addition order and total")
	check(values.size() == 9, "duplicate values share keys while material, quality, exact vr and legendary gems remain separate")
	check(JSON.stringify(Game._serialize(town)) == before and _ids(town) == owned_before and Game.rng.state == rng_state and Unit._next_uid == next_unit and Item._next_uid == next_item,
		"note price reads preserve real items, stock, owners, accounts, RNG and allocation counters")
	var e: Dictionary = town["econ"]; var short := {"w_sword": 3, "a_helm": 2}
	for refusal in [[0.0, 0], [125.25, 3], [0.0, 2]]:
		var expected: float = _old_note_due(town, short, float(refusal[0]), int(refusal[1]))
		ArmsTrade._arms_note(null, town, e, short, float(refusal[0]), int(refusal[1]))
		check(float(e["arms_due"]) == expected, "native arms due matches frozen original average/refusal arithmetic")
	ArmsTrade._arms_note(null, town, e, {}, 0.0, 0)
	check(float(e["arms_due"]) == _old_note_due(town, {}, 0.0, 0), "full-stock note still clears the actual arms bill")
	var prior: float = Economy.base_value(town, arm[-1])
	# A later read gets a fresh cache after native market price/stall changes.
	town["shop"].clear(); e["bow_target"] = 2
	check(ArmsTrade._note_value(town, arm[-1], {}) == Economy.base_value(town, arm[-1]) and Economy.base_value(town, arm[-1]) != prior,
		"later price context resets note cache and reads actual changed bow scarcity")

func _selection_sequence(indexed: bool) -> Dictionary:
	var town: Dictionary = _fixture()
	(town["shop"] as Array).clear()
	town["armory_items"] = [_item(6000, "hacking_cleaver"), _item(6001, "crescent_sabre"),
		_item(6002, "flanged_mace"), _item(6003, "arming_sword"), _item(6004, "nasal_helm"),
		_item(6005, "mail_coif"), _item(6006, "kite_shield"), _item(6007, "war_maul"),
		_item(6008, "steppe_sabre"), _item(6009, "boar_spear")]
	town["econ"]["arms_tgt"] = {"w_sword": 1}
	var before: Array = _ids(town)
	var requests := [
		[["arming_sword", "flanged_mace"], "main_hand", true],
		[["arming_sword"], "main_hand", false],
		[["arming_sword"], "main_hand", true],
		[["arming_sword"], "main_hand", true],
		[["arming_sword"], "main_hand", false],
		[["arming_sword"], "main_hand", false],
		[["nasal_helm"], "helm", false],
		[["nasal_helm"], "helm", false],
		[["kite_shield"], "off_hand", false],
		[["war_maul"], "main_hand", false],
		[["boar_spear"], "main_hand", false],
		[["arming_sword"], "main_hand", false]]
	var stock := {}; var picked := []; var checkpoints := []; var issued := []
	for request in requests:
		var it: Item = ArmsTrade._take_fit(town, request[0], request[1], request[2], stock) if indexed else _old_take_fit(town, request[0], request[1], request[2], stock)
		picked.append(it.uid if it != null else -1)
		if it != null: issued.append(it)
		var remaining := []
		for owned in town["armory_items"]: remaining.append(owned.uid)
		checkpoints.append({"remaining": remaining, "counts": stock.get("counts", {}).duplicate(),
			"used": town["econ"]["led"]["used"].duplicate()})
	var after: Array = _ids(town)
	for it in issued: after.append(it.uid)
	after.sort()
	check(after == before, "indexed or frozen linear selector conserves consumed Item occurrences")
	return {"picked": picked, "checkpoints": checkpoints, "issued": issued, "town": town, "stock": stock}

func _selection_differential() -> void:
	var old: Dictionary = _selection_sequence(false)
	var current: Dictionary = _selection_sequence(true)
	check(current["picked"] == old["picked"], "indexed selector preserves every frozen linear Item UID choice")
	for i in old["checkpoints"].size():
		check(current["checkpoints"][i] == old["checkpoints"][i], "optional counts, stock order and used ledger match after selection %d" % i)
	check(current["picked"] == [6002, 6003, 6001, -1, 6008, 6000, 6004, 6005, 6006, 6007, 6009, -1], "earliest exact across tids beats class/foreign; class beats foreign; protected optional reserve remains")
	check(int(current["checkpoints"][0]["counts"]["w_sword"]) == 3 and int(current["checkpoints"][0]["counts"]["w_mace"]) == 0, "mixed exact templates debit the actual consumed class")
	check(current["town"]["armory_items"].is_empty() and current["stock"]["fit_index"]["live"].is_empty(), "all consumed physical Items leave stock and transient live index")
	# Expired cursors must never hide new arrivals in the next shrinking pass.
	var town: Dictionary = current["town"]
	var arriving := _item(6010, "arming_sword")
	town["armory_items"].append(arriving)
	var fresh := {}
	var selected: Item = ArmsTrade._take_fit(town, ["arming_sword"], "main_hand", false, fresh)
	check(selected == arriving and town["armory_items"].is_empty(), "new purchase pass rebuilds index and selects the real arriving Item")
	check(fresh["fit_index"] != current["stock"]["fit_index"], "successful rekit indexes expire between stock-changing passes")

## Frozen old local rekit: no failed-slot cache, full slots, armory only.
func _old_local_rekit(town: Dictionary, units: Array) -> int:
	var n := 0
	var stock := {}
	for u in units:
		if not ArmsTrade._is_person(u): continue
		var lo: Dictionary = ArmsTrade.loadout_of(u)
		for slot in lo:
			if u.equip.has(slot): continue
			if slot == "off_hand" and u.weapon() != null and u.weapon().tmpl().get("two_handed", false): continue
			var row: Dictionary = lo[slot]
			var it: Item = _old_take_fit(town, row["tids"], str(slot), false, stock)
			if it != null:
				u.equip[slot] = it; n += 1; ArmsTrade.led("rekit")
	return n

## Frozen complete old procurement pass, with only uncached local helper names changed.
func _old_econ_daily(game, town: Dictionary, e: Dictionary, day: int = -1, every: bool = true) -> void:
	var stock := ArmsTrade.armory(town)
	for i in range(stock.size() - 1, -1, -1):
		if ArmsTrade.cls(stock[i].tid) == "" and not stock[i].is_legend():
			(town["shop"] as Array).append(stock[i])
			stock.remove_at(i)
	var tid := String(town["id"])
	if every and ((day if day >= 0 else int(e.get("day", 0))) + absi(tid.hash())) % ArmsTrade.ARMORY_EVERY != 0:
		return   # the head looks at his armory every few days (towns staggered)
	var mil: Array = TownDefence.garrison(game, tid) if game != null else []
	if game != null:
		# Frozen uncached local pass.
		_old_local_rekit(town, mil)   # first what the armory already holds
	var tgt := ArmsTrade.targets(game, town)
	var arm := ArmsTrade.armory(town)
	var have := ArmsTrade.class_counts(arm)
	var short := ArmsTrade._short(tgt, have)
	var cant_pay := 0.0   # stall pieces of a short class the treasury could not pay for (their value, how many)
	var cant_n := 0
	var bought := 0
	var budget := 0.0
	if not short.is_empty():
		# v0.014: the arms bill comes out of the treasury above what the garrison's pay needs (arms_reserve), not a
		# tenth of whatever is in the chest; what it cannot pay goes on the month's budget (Barge.treasury_month)
		budget = maxf(0.0, float(e["treasury"]) - ArmsTrade.arms_reserve(game, town, e))
		var shop: Array = town.get("shop", [])
		var mkt: Dictionary = e["biz"][int(e["mkt"])]
		var i := 0
		while i < shop.size() and not short.is_empty():
			var it: Item = shop[i]
			var c := ArmsTrade.cls(it.tid)
			var wanted := ArmsTrade.shortage_class(short, c)
			if wanted != "":
				var p := Economy.base_value(town, it)
				if p <= budget and float(e["treasury"]) >= p:
					shop.remove_at(i)
					arm.append(it)
					budget -= p
					bought += 1
					e["treasury"] = float(e["treasury"]) - p
					mkt["till"] = float(mkt["till"]) + p
					e["stats"]["sales"] = float(e["stats"]["sales"]) + p
					have[c] = int(have.get(c, 0)) + 1
					short[wanted] = int(short[wanted]) - 1
					if int(short[wanted]) <= 0:
						short.erase(wanted)
					ArmsTrade.led("bought")
					continue
				cant_pay += p
				cant_n += 1
			i += 1
		if bought > 0 and game != null:
			# Frozen uncached local pass after actual purchases.
			_old_local_rekit(town, mil)   # the new pieces to the men who lack them
			tgt = ArmsTrade.targets(game, town)
			have = ArmsTrade.class_counts(arm)
			short = ArmsTrade._short(tgt, have)
	e["arms_tgt"] = tgt
	e["arms_short"] = short
	ArmsTrade._arms_note(game, town, e, short, cant_pay, cant_n)
	# Retain unmatched physical surplus. The ten-day own-faction pass gets it;
	# ordinary commercial trade still uses the market's goods and smith output.
	var sd: Dictionary = e.get("arms_sd", {})
	for c in sd.keys():
		if not short.has(c):
			sd.erase(c)
	for c in short:
		sd[c] = int(sd.get(c, 0)) + ArmsTrade.ARMORY_EVERY
	e["arms_sd"] = sd
	e["arms_short"] = short
	e["arms_have"] = have



## Frozen old linear exact/class/role selector, including optional reserve counts.
func _old_take_fit(town: Dictionary, tids: Array, slot: String, opt: bool, stock = null) -> Item:
	var arm := ArmsTrade.armory(town)
	if arm.is_empty():
		return null
	var c := ArmsTrade.cls(String(tids[0]))
	if opt:
		var target := int(town.get("econ", {}).get("arms_tgt", {}).get(c, 0))
		var have := 0
		if stock != null:
			# This re-kit pass only removes armory Items. Count once on its first
			# optional slot, then subtract each actual selected piece's own class.
			if not (stock as Dictionary).has("counts"):
				var counts := {}
				for it in arm:
					var item_class := ArmsTrade.cls(it.tid)
					counts[item_class] = int(counts.get(item_class, 0)) + 1
				stock["counts"] = counts
			have = int(stock["counts"].get(c, 0))
		else:
			for it in arm:
				if ArmsTrade.cls(it.tid) == c:
					have += 1
					if have > target:
						break
		if have <= target:
			return null
	var pick := -1
	var alt := -1
	var r := ArmsTrade.role(String(tids[0]))
	for i in arm.size():
		var it: Item = arm[i]
		if tids.has(it.tid):
			pick = i
			break
		if pick < 0 and ArmsTrade.cls(it.tid) == c and it.slot() == slot:
			pick = i
		elif not opt and pick < 0 and alt < 0 and it.slot() == slot and ArmsTrade.role(it.tid) == r:
			alt = i
	if pick < 0 and not opt:
		pick = alt   # Douglas: own make short -> any piece for the same role (a looted orc axe for a sword arm)
	if pick < 0:
		return null
	var got: Item = arm[pick]
	arm.remove_at(pick)
	if stock != null and (stock as Dictionary).has("counts"):
		var taken_class := ArmsTrade.cls(got.tid)
		stock["counts"][taken_class] = int(stock["counts"].get(taken_class, 0)) - 1
	if TownEcon.has_econ(town):
		TownEcon.led(town["econ"], "used", "arms", 1)
	return got


