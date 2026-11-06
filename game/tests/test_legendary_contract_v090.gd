extends RefCounted
## UNRUN: source-only v090 contract regression. Root/TestBridge executes this file.
## One Normal / one-day native setup supplies a genuine saved smith, market and ledgers.
## Settlement fixtures use 2-4 people and explicit winner 0/1/-1; no campaign turns or large battles.
## Target <60 s, hard cap 180 s. Fixed sample sizes and seed searches are bounded.

var fails := 0
var checks := 0
var town: Dictionary
var original_e: Dictionary
var forge_id := -1
var data: Dictionary
var group_completed := false

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL v090: ", message)

func _run_group(method: String) -> void:
	group_completed = false
	call(method)
	check(group_completed, method + " reaches its completion guard")

func run(_tree: SceneTree) -> int:
	_run_group("_test_curve")
	var old_size: String = WorldGen.gen_size
	var old_span: float = CampaignWorld.presim_span_days
	WorldGen.gen_size = WorldGen.WORLD_SIZE
	CampaignWorld.presim_span_days = 1.0
	Game.new_game(90090)
	WorldGen.gen_size = old_size
	CampaignWorld.presim_span_days = old_span
	data = TownEcon.data()
	if not _find_forge():
		check(false, "Normal one-day setup has a forge with a real register maker")
		return fails
	var audit := {"tracking": WorldAudit.tracking, "made": WorldAudit.made_log, "gone": WorldAudit.items_gone,
		"gone_by": WorldAudit.gone_by, "unmade": WorldAudit.unmade_ids, "unmade_by": WorldAudit.unmade_by}
	WorldAudit.tracking = true
	WorldAudit.made_log = {}; WorldAudit.unmade_ids = {}; WorldAudit.unmade_by = {}
	WorldAudit.items_gone = []; WorldAudit.gone_by = {}
	for method in ["_test_mining", "_test_saved_cap", "_test_paid_and_refused", "_test_family_stone",
			"_test_player_winner", "_test_ai_winner", "_test_ai_overflow", "_test_creature_winner", "_test_draw", "_test_fit"]:
		_run_group(method)
	WorldAudit.tracking = bool(audit["tracking"])
	WorldAudit.made_log = audit["made"]; WorldAudit.unmade_ids = audit["unmade"]
	WorldAudit.unmade_by = audit["unmade_by"]
	WorldAudit.items_gone = audit["gone"]; WorldAudit.gone_by = audit["gone_by"]
	print("v090 legendary contract: %d checks, %d failures" % [checks, fails])
	return fails

func _test_curve() -> void:
	check(absf(Factory.masterwork_chance(10.0) - 0.014) < 1.0e-10, "inclusive masterwork anchor: 1.4% at skill 10")
	check(absf(Factory.masterwork_chance(15.0) - 0.25) < 1.0e-10, "inclusive masterwork anchor: 25% at skill 15")
	check(absf(Factory.legend_chance(10.0) - 0.00056) < 1.0e-10, "legend anchor: 0.056% at skill 10")
	check(absf(Factory.legend_chance(15.0) - 0.01) < 1.0e-10, "legend anchor: 1% at skill 15")
	var ratio := pow(0.25 / 0.014, 0.2)
	for skill in range(0, 16):
		var expected := 0.014 * pow(ratio, skill - 10)
		check(absf(Factory.masterwork_chance(skill) - expected) < 1.0e-10, "same curve through skill %d" % skill)
		check(absf(Factory.legend_chance(skill) - expected / 25.0) < 1.0e-10, "legend subset at skill %d" % skill)
	for skill in [8, 10, 12, 15]:
		var rng := RandomNumberGenerator.new(); rng.seed = 90000 + skill
		var n := 100000
		var inclusive := 0; var final_masterwork := 0; var legends := 0
		for i in n:
			var q := Factory.roll_quality(rng, skill, true)
			if q >= 5: inclusive += 1
			if q == 5: final_masterwork += 1
			if q == DB.LEGEND: legends += 1
		var mw := Factory.masterwork_chance(skill)
		_sample(inclusive, n, mw, "inclusive masterwork at %d" % skill)
		_sample(final_masterwork, n, mw * 24.0 / 25.0, "final tier-5 at %d" % skill)
		_sample(legends, n, mw / 25.0, "legendary at %d" % skill)
		check(inclusive == final_masterwork + legends, "inclusive count = tier-5 + tier-6")
		print("v090 skill %d / %d: inclusive MW %d, final tier-5 %d, legendary %d" % [skill, n, inclusive, final_masterwork, legends])
	var a := RandomNumberGenerator.new(); a.seed = 90
	var b := RandomNumberGenerator.new(); b.seed = 90
	var same := true; var generic := true
	for i in 256:
		same = (Factory.roll_quality(a, 12.0, true) == Factory.roll_quality(b, 12.0, true)) and same
		generic = Factory.roll_quality(a, 15.0, false) <= 5 and generic
		Factory.roll_quality(b, 15.0, false) # keep the determinism streams aligned
	check(same and generic, "fixed-seed rolls repeat; anonymous production never rolls legendary")
	check(DB.quality_mult(DB.LEGEND) == 3.0 and DB.quality_mult(5) == 2.0, "native physical quality: artifact 3 vs masterwork 2")
	group_completed = true

func _sample(got: int, n: int, p: float, label: String) -> void:
	check(absf(got - n * p) <= 5.0 * sqrt(n * p * (1.0 - p)) + 2.0, label + " within fixed five-sigma count bound")

func _find_forge() -> bool:
	var ids: Array = Game.world["towns"].keys(); ids.sort()
	for tid in ids:
		var t: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(t) or t.get("culture", "") != "middle": continue
		for b in t["econ"]["biz"]:
			if b["type"] != "weaponsmith": continue
			for m in Legends.makers(t["econ"], b):
				if Population.is_cohort(m["f"]): continue
				town = t; original_e = (t["econ"] as Dictionary).duplicate(true)
				forge_id = int(b["id"])
				return true
	return false

func _fresh() -> Dictionary:
	var e := original_e.duplicate(true)
	var b: Dictionary = e["biz"][forge_id]
	var m: Dictionary = Legends.makers(e, b).filter(func(x): return not Population.is_cohort(x["f"]))[0]
	var f: Dictionary = m["f"]; var p: Array = m["p"]
	f["id"] = 0; f["pp"] = [p]; f["kp"] = []; f["keeps"] = [forge_id]
	f["jobs"] = {}; f["cj"] = {}; f["hands"] = 0; f["gems"] = {}
	p[4] = ""; p[6] = 0
	while p.size() <= Persons.LEG: p.append(0)
	p[Persons.LEG] = 0; p[Persons.HIST] = []
	e["fams"] = [f]; e["gh"] = {}; e["arms_short"] = {}
	e["fkh"] = {"bronze": 0.0, "iron": 0.0, "steel": 0.0}; e["knowhow"] = {"bronze": 0.0}
	for good in e["stock"]: e["stock"][good] = 0
	e["stock"]["copper_bars"] = 1000; e["stock"]["wood"] = 1000
	e["led"] = {"made": {}, "used": {}, "spoil": {}}
	b["owner"] = 0; b["smith"] = "V090 Contract Smith"; b["skill"] = 15
	b["till"] = 1000000.0; b["carry"] = 0.0; b["arms_carry"] = 0.0; b["state"] = "busy"
	var market: Dictionary = e["biz"][int(e["mkt"])]
	market["till"] = 100000000.0; market["spend"] = 0.0
	town["econ"] = e; town["shop"] = []; town["armory_items"] = []
	Game.company = []; Game.stash = []
	return {"e": e, "b": b, "f": f, "p": p, "market": market}

## Find an inspired seed without creating items, charging anyone or altering the production function.
func _candidate(seed_value: int, e: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value
	var tid := ArmsTrade.pick_tid(e, Businesses.gear_pool(String(town["culture"]), "weapon"), rng)
	var mat := Businesses._pick_metal(e, tid, 0.0, int(town.get("wealth", 2)), rng, 0.0, 0.0)
	return [tid, mat, Factory.roll_quality(rng, 15.0, true)]

func _legend_seed(e: Dictionary) -> int:
	for seed_value in range(1, 4097):
		if int(_candidate(seed_value, e)[2]) == DB.LEGEND: return seed_value
	check(false, "bounded inspired-seed search found a real legendary quality roll")
	return 1

func _forge(seed_value: int) -> Dictionary:
	var e: Dictionary = town["econ"]; var b: Dictionary = e["biz"][forge_id]
	var before: int = town["shop"].size()
	b["arms_carry"] = 0.0; b["state"] = "busy"
	var recipe: Dictionary = data["businesses"]["weaponsmith"]
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value
	var spent := Businesses._arms(null, town, e, data, b, recipe, (1.0 + 1.0e-8) / float(recipe["rate"]),
		1.0, 1.0, rng, e["biz"][int(e["mkt"])], {})
	return {"spent": spent, "item": town["shop"][-1] if town["shop"].size() > before else null}

func _coin(c: Dictionary) -> float:
	return float(c["b"]["till"]) + float(c["market"]["till"]) + float(c["f"]["purse"])

func _test_mining() -> void:
	var c := _fresh(); var e: Dictionary = c["e"]
	var mine := {"ore": "copper_ore", "rich": 1.0, "spec": false, "oc": {}, "till": 0.0, "state": "busy"}
	e["need"]["copper_ore"] = 1000.0
	var rng := RandomNumberGenerator.new(); rng.seed = 90
	var initial_state: int = rng.state
	Businesses._mine(e, data, mine, 0.0, 1.0, 1.0, c["market"], 0.9, rng)
	check(rng.state == initial_state and int(e["stock"].get("copper_ore", 0)) == 0, "no ore work: no pocket or RNG draw")
	c["market"]["till"] = 0.0
	Businesses._mine(e, data, mine, 4.0, 1.0, 1.0, c["market"], 0.9, rng)
	check(int(mine.get("gems", 0)) == 0 and rng.state == initial_state, "unpaid ore production cannot create gems")
	mine["oc"] = {}; c["market"]["till"] = 10000.0
	var baskets := int(floor(4.0 * float(data["mine_rate"])))
	var chance := 1.0 - pow(1.0 - float(Legends.G()["chance"]), baskets)
	var seed_value := -1; var expected_gem := ""
	for candidate in range(1, 4097):
		rng.seed = candidate
		if rng.randf() < chance:
			seed_value = candidate; expected_gem = Legends.mine_gem(e, "copper_ore", rng); break
	check(seed_value >= 0, "bounded mine-pocket seed found")
	var coins := float(mine["till"]) + float(c["market"]["till"])
	rng.seed = maxi(0, seed_value)
	Businesses._mine(e, data, mine, 4.0, 1.0, 1.0, c["market"], 0.9, rng)
	check(int(e["stock"].get("copper_ore", 0)) == baskets and int(e["led"]["made"].get("copper_ore", 0)) == baskets, "native mine produces and books actual ore")
	check(int(mine.get("gems", 0)) == 1 and int(e["stock"].get(expected_gem, 0)) == 1 and int(e["led"]["made"].get(expected_gem, 0)) == 1, "ore work produces exactly one counted geological gem pocket")
	check(absf(coins - float(mine["till"]) - float(c["market"]["till"])) < 1.0e-6 and float(c["market"]["till"]) >= 0.0, "mine/market transfers conserve finite coins")
	var flat := RandomNumberGenerator.new(); flat.seed = 91
	var rocky := RandomNumberGenerator.new(); rocky.seed = 91
	var different := 0; var common := 0; var rare := 0
	for i in 1024:
		var a := Legends.mine_gem({"terrain": {"hill_cells": 0}}, "copper_ore", flat)
		var b := Legends.mine_gem({"terrain": {"hill_cells": 8}}, "tin_ore", rocky)
		if a != b: different += 1
		if a in ["quartz", "amethyst"]: common += 1
		if a in ["ruby", "sapphire", "emerald"]: rare += 1
	check(different > 0 and common > rare, "real ore/hills affect gem selection; common stones dominate")
	var standalone := false
	for trade in data["businesses"]:
		if String(trade).contains("gem") and String(trade).contains("mine"): standalone = true
	check(not standalone, "ore pockets reuse existing mines")
	group_completed = true

func _test_saved_cap() -> void:
	var c := _fresh(); var e: Dictionary = c["e"]
	e["stock"]["ruby"] = 10
	var seed_value := _legend_seed(e); var coins := _coin(c)
	var maker_uid := str(Persons.g(c["p"], Persons.PERSON_UID, ""))
	check(maker_uid not in ["", "0"], "cap belongs to a real identified register person")
	var names := {}; var made := 0
	for i in 6:
		if i == 2:
			var saved: Dictionary = JSON.parse_string(JSON.stringify(c["f"]))
			e["fams"] = [saved]; c["f"] = saved; c["p"] = saved["pp"][0]
			check(str(Persons.g(c["p"], Persons.PERSON_UID, "")) == maker_uid and Legends.made_by(c["p"]) == 2, "cold same-maker restore retains identity and two lifetime makings")
		var before: int = e["stock"]["ruby"]
		var result := _forge(seed_value); var it: Item = result["item"]
		if i < 5:
			check(it != null and it.is_legend(), "actual paid forge creates legendary piece %d" % (i + 1))
			if it == null: continue
			made += int(it.is_legend()); names[it.legend.get("nm", "")] = true
			check(int(e["stock"]["ruby"]) == before - 1 and it.gem_name() == "ruby", "one real ruby debited per artifact")
			check(String(it.legend.get("by", "")) == Persons.name_of(c["f"], c["p"], Persons.race_of(e)) and String(it.mark.get("t", "")) == str(town["id"]), "real maker and town provenance")
		else:
			check((it == null or not it.is_legend()) and int(e["stock"]["ruby"]) == before, "sixth same-maker roll consumes no gem and is not legendary")
	check(made == 5 and names.size() == 5 and Legends.made_by(c["p"]) == 5, "one saved smith makes at most five uniquely named artifacts")
	check(int(e["led"]["used"].get("ruby", 0)) == 5 and absf(_coin(c) - coins) < 1.0e-4, "lifetime-cap path has real gem and coin accounting")
	group_completed = true

func _test_paid_and_refused() -> void:
	var c := _fresh(); var e: Dictionary = c["e"]
	var seed_value := _legend_seed(e)
	e["stock"]["ruby"] = 1; c["market"]["till"] = 7.0
	var stock: Dictionary = e["stock"].duplicate(); var coins := _coin(c)
	var till := float(c["b"]["till"]); var market_till := float(c["market"]["till"])
	var result := _forge(seed_value); var it: Item = result["item"]
	check(it != null and it.is_legend(), "085 safeguard: actual artifact remains made despite a tiny market till")
	if it != null:
		var inputs := Businesses.gear_inputs(it.tid, it.material); var cost := 0.0
		for good in inputs:
			cost += float(inputs[good]) * float(e["price"][good])
			check(int(e["stock"][good]) == int(stock[good]) - int(inputs[good]) and int(e["led"]["used"].get(good, 0)) == int(inputs[good]), "paid forge debits and books " + str(good))
		var gem_price := float(e["price"]["ruby"])
		var paid := float(c["market"]["spend"])
		check(absf(float(result["spent"]) - cost) < 1.0e-6 and absf(float(c["b"]["till"]) - (till - gem_price - cost + paid)) < 1.0e-6, "forge pays the real gem and complete input bill")
		check(paid <= market_till + gem_price and absf(_coin(c) - coins) < 1.0e-6 and float(c["market"]["till"]) >= 0.0 and not WorldAudit.unmade_ids.has(it.uid), "finite payment conserves coin; held artifact is never booked unmade")
		var shape := ItemIcon.shape_of(it.tid)
		check(it.display_name().begins_with(str(it.legend["nm"]) + ", legendary copper ") and String(it.legend_lines()[0]).contains("ruby") and it.legend["at"] == Item.gem_spot(it.tid), "named gem-set description uses native fitting metadata")
		check(ItemIcon.THING_COLORS.has("ruby") and ItemIcon.GEM_SPOTS.get(shape, Vector2i(16, 16)) is Vector2i and it.mass() > 0.0, "native gem icon metadata and physical template remain available")
	c = _fresh(); e = c["e"]; e["stock"]["ruby"] = 1
	var candidate := _candidate(seed_value, e)
	var required := Businesses.gear_inputs(String(candidate[0]), "copper"); var input_cost := 0.0
	for good in required: input_cost += float(required[good]) * float(e["price"][good])
	c["b"]["till"] = input_cost + float(e["price"]["ruby"]) - 1.0; c["market"]["till"] = 0.0
	stock = e["stock"].duplicate(); coins = _coin(c)
	var uid := Item._next_uid; var history := JSON.stringify(c["p"][Persons.HIST])
	result = _forge(seed_value)
	check(result["item"] == null and float(result["spent"]) == 0.0 and e["stock"] == stock and _coin(c) == coins, "refused piece consumes no gem, bars, wood or coin")
	check(Legends.made_by(c["p"]) == 0 and JSON.stringify(c["p"][Persons.HIST]) == history and (e["led"]["used"] as Dictionary).is_empty(), "gem cannot spend reserved inputs or create a phantom maker history")
	check(WorldAudit.unmade_ids.has(uid) and not WorldAudit.items_gone.any(func(row): return int(row[0]) == uid), "085 refusal is unmade, not a destroyed real item")
	e["stock"]["copper_bars"] = 0; uid = Item._next_uid
	result = _forge(seed_value)
	check(result["item"] == null and Item._next_uid == uid and int(e["stock"]["ruby"]) == 1, "missing inputs stop before making an item or setting a gem")
	group_completed = true

func _test_family_stone() -> void:
	var c := _fresh(); var e: Dictionary = c["e"]
	Legends.add_fam_gem(e, c["f"], "sapphire", 1)
	var p := float(e["price"]["sapphire"]); var purse := float(c["f"]["purse"])
	c["b"]["till"] = p + 100.0 - 1.0
	var it := Item.make("arming_sword", "copper", DB.LEGEND)
	var rng := RandomNumberGenerator.new(); rng.seed = 90
	check(not Legends.forge(Game, town, e, c["b"], it, rng, Game.day, 100.0) and Legends.made_by(c["p"]) == 0 and float(c["f"]["purse"]) == purse and int(e["gh"]["sapphire"]) == 1, "family stone respects the input reserve without side effects")
	it = Item.make("arming_sword", "copper", DB.LEGEND); ArmsTrade.mark(it, town, c["b"])
	c["b"]["till"] = p + 100.0
	check(Legends.forge(Game, town, e, c["b"], it, rng, Game.day, 100.0) and it.gem_name() == "sapphire" and float(c["b"]["till"]) == 100.0 and float(c["f"]["purse"]) == purse + p and not e["gh"].has("sapphire") and (c["f"]["gems"] as Dictionary).is_empty(), "family receives the exact stone price; household gem totals fall once")
	town["shop"].append(it)
	group_completed = true

func _artifact() -> Item:
	var c := _fresh(); c["e"]["stock"]["ruby"] = 2
	var it: Item = _forge(_legend_seed(c["e"]))["item"]
	check(it != null and it.is_legend(), "custody fixture uses a genuinely forged artifact")
	if it == null or not it.is_legend(): return null
	town["shop"].erase(it)
	return it

func _person(name_value: String, faction: String, skill: int = 0) -> Unit:
	var u := Unit.create("human", faction)
	u.name = name_value; u.title = "fighter"; u.skills["sword"] = skill
	u.home_town = str(town["id"])
	return u

func _band(units: Array, own_home: bool = true) -> Dictionary:
	var faction := str(town["faction"]) if own_home else "orc_horde"
	var band := {"id": "v090_winner", "kind": "army", "home": str(town["id"]), "faction": faction,
		"units": units, "pos": town["pos"], "gold": 0.0, "stores": {}}
	Game.world["warbands"] = {"v090_winner": band}
	return band

func _copies(it: Item, units: Array, band: Dictionary) -> int:
	var count := 0
	for u in units:
		for held in u.equip.values():
			if held is Item and held.uid == it.uid: count += 1
	for source in [Game.stash, town["shop"], ArmsTrade.armory(town), band.get("cargo", {}).get("items", [])]:
		for held in source:
			if held is Item and held.uid == it.uid: count += 1
	return count

func _saved_state(it: Item) -> Dictionary:
	return JSON.parse_string(JSON.stringify(it.to_dict()))

func _same_provenance(it: Item, before: Dictionary) -> bool:
	var current := _saved_state(it); var expected := before.duplicate(true)
	for key in ["h", "cu"]: # only custody history and the current carrier may change on transfer
		current["lg"].erase(key); expected["lg"].erase(key)
	return current == expected

func _test_player_winner() -> void:
	var it := _artifact()
	if it == null: return
	var player := _person("Player victor", "player", 12)
	var fallen := _person("Enemy carrier", "orc_horde")
	fallen.equip["main_hand"] = it; Legends.touch(it, fallen); fallen.dead = true
	Game.company = [player]
	var band := _band([fallen], false)
	ArmsSalvage.after_company_battle(Game, {"winner": 0, "player_units": [player]}, band, {}, [])
	check(fallen.equip.get("main_hand") == it and not Game.stash.has(it), "player victory cannot award the artifact to the defeated AI")
	var spoils := Loot.spoils([fallen], [], 90, 0.0, "your company")
	check((spoils["items"] as Array).has(it) and fallen.equip.is_empty(), "native player harvest retains the artifact even with loot fraction zero")
	Game.stash.append_array(spoils["items"])
	check(_copies(it, [player, fallen], band) == 1 and Game.stash.has(it), "exact UID has one player custody destination")
	var restored := Item.from_dict(JSON.parse_string(JSON.stringify(it.to_dict())))
	check(restored.uid == it.uid and _saved_state(restored) == _saved_state(it), "cold player item retains UID, maker, gem and capture history")
	group_completed = true

func _test_ai_winner() -> void:
	var it := _artifact()
	if it == null: return
	var fallen := _person("Player carrier", "player")
	var junior := _person("Junior victor", str(town["faction"]), 2)
	var best := _person("Best victor", str(town["faction"]), 15)
	best.skills[String(it.tmpl().get("skill", ""))] = 15
	fallen.equip["main_hand"] = it; Legends.touch(it, fallen)
	var victim := _person("Remembered victim", "orc_horde"); victim.dead = true
	Legends.on_kill(fallen, victim); fallen.dead = true
	Game.company = [fallen]
	var band := _band([junior, best])
	ArmsSalvage.after_company_battle(Game, {"winner": 1, "player_units": [fallen]}, band, {}, [])
	check(best.equip.get(Legends.slot_of(it)) == it and fallen.equip.is_empty() and not Game.stash.has(it), "actual AI winner equips its best fitting fighter; defeated company receives nothing")
	check(_copies(it, [fallen, junior, best], band) == 1 and int(it.legend.get("cu", -1)) == best.uid, "AI transfer preserves one exact UID and updates carrier")
	check(int(it.legend.get("k", 0)) == 1 and (it.legend.get("kl", []) as Array).has(victim.name) and (it.legend.get("h", []) as Array).size() >= 4, "maker, former carrier, capture, new carrier and kills remain real")
	check(not (town["econ"].get("legends_lost", []) as Array).is_empty(), "the former carrier's town records the loss")
	var snapshot := it.to_dict()
	var prior_floor := Item._next_uid
	Item._next_uid = 1 # a cold process has not allocated this saved UID yet
	var cold := Unit.from_dict(JSON.parse_string(JSON.stringify(best.to_dict())))
	var restored_floor := Item._next_uid
	Item._next_uid = maxi(prior_floor, restored_floor)
	check(restored_floor > it.uid, "cold native item restoration raises a fresh allocation floor")
	band["units"] = [junior, cold]
	var restored: Item = cold.equip.get(Legends.slot_of(it), null)
	check(restored != null and restored.uid == it.uid and _saved_state(restored) == _saved_state(it) and _copies(it, [fallen, junior, cold], band) == 1, "cold AI unit restores exact custody, provenance and complete item history")
	if restored != null:
		Legends.note(restored, Game.day, "Cold history isolation probe.")
		check(restored.legend["h"].size() == snapshot["lg"]["h"].size() + 1 and it.legend == snapshot["lg"], "restored history is detached from the serialized source")
	var next := Item.make(it.tid, it.material, 0)
	check(next.uid > it.uid, "cold item restoration preserves the allocation floor")
	WorldAudit.unmade(next, "-v090 UID allocation probe")
	group_completed = true

func _test_ai_overflow() -> void:
	var it := _artifact()
	if it == null: return
	var fallen := _person("Overflow carrier", "player"); fallen.dead = true; fallen.equip["main_hand"] = it
	var victor := _person("Homeless victor", "orc_horde", 15)
	# Every legal slot is occupied; the old home now belongs to another faction.
	var occupied := Item.make(it.tid, it.material, DB.LEGEND); occupied.legend = it.legend.duplicate(true)
	occupied.legend["nm"] = "Existing victor's artifact"; victor.equip["main_hand"] = occupied
	var band := _band([victor], false)
	var refused := ArmsSalvage.field(Game, [fallen], {"band": {}}, town["pos"])
	check(int(refused["kept"]) == 0 and fallen.equip.get("main_hand") == it and not Game.stash.has(it), "missing actual winner cannot conjure a custody transfer")
	var booked := int(WorldAudit.flows(Game.world)["goods"].get("arms", {}).get("+legend in victorious band cargo", 0))
	ArmsSalvage.after_company_battle(Game, {"winner": 1, "player_units": [fallen]}, band, {}, [])
	check(fallen.equip.is_empty() and victor.equip.get("main_hand") == occupied and (band.get("cargo", {}).get("items", []) as Array).has(it), "no home/hoard or free slot: actual winner keeps overflow in native cargo")
	check(not Game.stash.has(it) and not ArmsTrade.armory(town).has(it) and _copies(it, [fallen, victor], band) == 1, "overflow never goes to the company or the enemy-held old home")
	check(int(WorldAudit.flows(Game.world)["goods"].get("arms", {}).get("+legend in victorious band cargo", 0)) == booked + 1, "newly counted band cargo has one native arms inflow booking")
	var restored := Item.from_dict(JSON.parse_string(JSON.stringify(it.to_dict())))
	band["cargo"]["items"] = [restored]
	check(restored.uid == it.uid and _saved_state(restored) == _saved_state(it) and _copies(it, [fallen, victor], band) == 1, "cold cargo item retains one UID and all provenance")
	group_completed = true

func _test_creature_winner() -> void:
	var it := _artifact()
	if it == null: return
	var cid := ""
	for candidate in Creatures.ids():
		if DB.is_creature(String(candidate)):
			cid = String(candidate); break
	check(cid != "", "known creature fixture has an enabled native creature ID")
	if cid == "": return
	var rng := RandomNumberGenerator.new(); rng.seed = 90091
	var beast := Creatures.make(rng, cid)
	check(beast.race == cid and bool(beast.race_def().get("creature", false)), "known winner is a genuine native creature, with no human fallback")
	var fallen := _person("Known creature's fallen carrier", "player")
	fallen.equip["main_hand"] = it; Legends.touch(it, fallen); fallen.dead = true
	Game.company = [fallen]
	var band := _band([beast], false)
	band["kind"] = "beasts"; band["faction"] = beast.faction
	check(Monsters.is_monster_band(band) and band["faction"] != town["faction"], "known creature band has an enemy-held old home")
	# A second genuine forge output starts in counted caravan cargo. It must join, not replace, the first prize.
	var cargo_it: Item = _forge(_legend_seed(town["econ"]))["item"]
	check(cargo_it != null and cargo_it.is_legend() and cargo_it.uid != it.uid, "overflow fixture uses a second genuinely forged artifact")
	if cargo_it == null or not cargo_it.is_legend(): return
	town["shop"].erase(cargo_it)
	var caravan := {"id": "v090_creature_caravan", "kind": "caravan", "faction": town["faction"],
		"home": town["id"], "units": [], "pos": town["pos"], "gold": 0.0, "cargo": {"items": [cargo_it]}}
	Game.world["warbands"][caravan["id"]] = caravan
	# Preserve native integer day rows for an exact prefix check. The JSON
	# provenance snapshot below intentionally reconstructs numbers as floats.
	var prior_history: Array = (it.legend["h"] as Array).duplicate(true)
	var prior_cargo_history: Array = (cargo_it.legend["h"] as Array).duplicate(true)
	var before_item := _saved_state(it); var before_cargo := _saved_state(cargo_it)
	var before := WorldAudit.census(Game)
	ArmsSalvage.after_company_battle(Game, {"winner": 1, "player_units": [fallen]}, band, {}, [])
	check(fallen.equip.is_empty() and beast.equip.is_empty() and (band.get("cargo", {}).get("items", []) as Array).has(it), "known creature winner keeps the fallen carrier's exact artifact in its own cargo")
	check(_copies(it, [fallen, beast], band) == 1 and not Game.stash.has(it) and not ArmsTrade.armory(town).has(it) and not town["shop"].has(it), "known creature prize has exactly one destination, outside the company and enemy-held home")
	var history: Array = it.legend["h"]
	check(_same_provenance(it, before_item) and int(it.legend.get("cu", -1)) == -1, "known creature capture preserves exact UID, maker, gem, kills and physical provenance without inventing a wearer")
	check(history.size() == prior_history.size() + 2 and history.slice(0, prior_history.size()) == prior_history
		and String(history[-2][1]).contains(fallen.name) and String(history[-2][1]).contains(ArmsSalvage.holder_name({"band": band}))
		and String(history[-1][1]).contains("baggage"), "known creature capture and baggage custody append once each, preserving earlier history")
	var captured := WorldAudit.census(Game)
	var capture_audit := WorldAudit.compare(before, captured)
	check(bool(capture_audit["ok"]) and int(capture_audit["arms"]["held"]) == 1 and int(capture_audit["arms"]["book"]) == 1
		and int(capture_audit["arms"]["made"]) == 0 and int(capture_audit["items"]["made"]) == 0, "strict native census: equipped corpse to counted creature cargo is one inflow, never another creation")
	ArmsSalvage.plunder_cargo(Game, band, caravan)
	check((caravan["cargo"]["items"] as Array).is_empty() and (band["cargo"]["items"] as Array).size() == 2
		and _copies(it, [fallen, beast], band) == 1 and _copies(cargo_it, [fallen, beast], band) == 1, "known creature caravan overflow retains both exact prizes once")
	check(_same_provenance(cargo_it, before_cargo) and cargo_it.legend["h"].size() == before_cargo["lg"]["h"].size() + 2
		and (cargo_it.legend["h"] as Array).slice(0, prior_cargo_history.size()) == prior_cargo_history
		and not Game.stash.has(cargo_it) and not ArmsTrade.armory(town).has(cargo_it), "caravan prize keeps its provenance and records one capture and one baggage transfer at the real winner")
	var plundered := WorldAudit.census(Game)
	var plunder_audit := WorldAudit.compare(captured, plundered)
	check(bool(plunder_audit["ok"]) and int(plunder_audit["arms"]["held"]) == 0 and int(plunder_audit["arms"]["book"]) == 0
		and int(plunder_audit["arms"]["made"]) == 0 and int(plunder_audit["items"]["made"]) == 0, "strict native census: counted caravan cargo to creature cargo has zero net inflow and zero creation")
	# Cold native Unit/Item decoding, installed back into the actual winning band's saved holders.
	var saved_items := {}; var encoded := []
	for held: Item in band["cargo"]["items"]:
		saved_items[held.uid] = _saved_state(held); encoded.append(held.to_dict())
	var payload: Dictionary = JSON.parse_string(JSON.stringify({"unit": beast.to_dict(), "items": encoded}))
	var cold_beast := Unit.from_dict(payload["unit"]); var cold_items := []
	for row in payload["items"]:
		var restored := Item.from_dict(row); cold_items.append(restored)
		check(saved_items.has(restored.uid) and _saved_state(restored) == saved_items[restored.uid], "cold creature cargo preserves each exact UID and complete provenance/history")
	band["units"] = [cold_beast]; band["cargo"]["items"] = cold_items
	var cold := WorldAudit.census(Game)
	check(cold_beast.race == cid and bool(cold_beast.race_def().get("creature", false)) and cold_beast.equip.is_empty()
		and _copies(it, [fallen, cold_beast], band) == 1 and _copies(cargo_it, [fallen, cold_beast], band) == 1, "cold native creature holder retains both prizes exactly once")
	check(bool(WorldAudit.compare(plundered, cold)["ok"]) and (cold["items"]["dupes"] as Array).is_empty(), "cold native holder census preserves strict coin, arms and Item identity accounting")
	group_completed = true

func _test_draw() -> void:
	var it := _artifact()
	if it == null: return
	var other := Item.make(it.tid, it.material, DB.LEGEND); other.legend = it.legend.duplicate(true)
	other.legend["nm"] = "Enemy's retained artifact"
	var mine := _person("Own fallen", "player"); mine.dead = true; mine.equip["main_hand"] = it
	var theirs := _person("Other fallen", str(town["faction"])); theirs.dead = true; theirs.equip["main_hand"] = other
	var survivor := _person("Other survivor", str(town["faction"]), 10)
	Game.company = [mine]
	var band := _band([theirs, survivor])
	var losses: int = town["econ"].get("legends_lost", []).size()
	ArmsSalvage.after_company_battle(Game, {"winner": -1, "player_units": [mine]}, band, {}, [])
	check(Game.stash.has(it) and survivor.equip.get("main_hand") == other and mine.equip.is_empty() and theirs.equip.is_empty(), "draw recovers each side's own fallen artifacts without inventing an AI winner")
	check(town["econ"].get("legends_lost", []).size() == losses and _copies(it, [mine, theirs, survivor], band) == 1 and _copies(other, [mine, theirs, survivor], band) == 1, "draw has no false town loss or duplicated UID")
	group_completed = true

func _test_fit() -> void:
	var shield := Item.make("round_shield", "copper", DB.LEGEND)
	shield.legend = {"nm": "Fit shield", "gem": "ruby", "at": "boss"}
	var heavy := Item.make("dane_axe", "copper", DB.LEGEND)
	heavy.legend = {"nm": "Fit axe", "gem": "ruby", "at": "socket"}
	var blocked := _person("Shield carrier", "orc_horde", 15)
	blocked.equip["main_hand"] = Item.make("dane_axe", "copper", 0)
	check(not bool(Legends.give([blocked], shield)[0]) and not blocked.equip.has("off_hand"), "legendary shield cannot coexist with a two-handed weapon")
	blocked.equip["main_hand"] = Item.make("arming_sword", "copper", 0); blocked.equip["off_hand"] = shield
	blocked.skills["axe"] = 15
	var fits := _person("Fitting axe fighter", "orc_horde"); fits.skills["axe"] = 2
	var given := Legends.give([blocked, fits], heavy)
	check(bool(given[0]) and fits.equip.get("main_hand") == heavy and blocked.equip.get("off_hand") == shield, "best fitting fighter keeps both artifacts in compatible slots")
	group_completed = true
