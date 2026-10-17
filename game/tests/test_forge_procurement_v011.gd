extends RefCounted
## Frozen per-item procurement versus the forge-local pass; no world generation.
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func _item(uid: int, tid: String) -> Item:
	var it := Item.new()
	it.uid = uid; it.tid = tid; it.material = "copper"; it.quality = 2
	it.mark = {"t": "forge_fixture", "n": "real fixture smith"}
	return it

func _fixture() -> Dictionary:
	var guards := []
	for i in 24:
		var u := Unit.new()
		u.uid = 1000 + i; u.race = "human"; u.faction = "middle_kingdom"
		u.title = "man-at-arms" if i % 3 != 2 else "spearman"
		u.dead = i == 23
		guards.append(u)
	var archer := Unit.new()
	archer.uid = 1100; archer.race = "human"; archer.faction = "middle_kingdom"
	archer.title = "spearman"; archer.equip["ranged"] = _item(2000, "longbow")
	var e := {"stock": {}, "price": {}, "pop0": 24, "treasury": 100000.0,
		"mkt": 0, "biz": [{"type": "market", "till": 77.0}],
		"stats": {"sales": 0.0, "militia_bill": 1.0}, "day": 4,
		# Deliberately old: the first template roll must precede the fresh quote.
		"arms_short": {"w_sword": 999}}
	var town := {"id": "forge_fixture", "econ": e, "shop": [],
		"armory_items": [_item(2001, "hacking_cleaver"), _item(2002, "nasal_helm")],
		"culture": "middle", "faction": "middle_kingdom", "size": 2, "wealth": 3}
	Game.world = {"towns": {"forge_fixture": town}, "town_guards": {"forge_fixture": "guards"},
		"warbands": {"guards": {"kind": "guards", "units": guards},
			"caravan_b": {"kind": "caravan", "origin": "forge_fixture", "units": [guards[1]]},
			"caravan_a": {"kind": "caravan", "origin": "forge_fixture", "units": [archer]}}}
	return town

## The original native transaction, before the pass-local context was added.
func _reference_buy(game, town: Dictionary, e: Dictionary, it: Item, p: float) -> bool:
	if game != null: ArmsTrade.refresh_equipment(game, town)
	var short: Dictionary = e.get("arms_short", {})
	var c := ArmsTrade.cls(it.tid)
	var wanted := ArmsTrade.shortage_class(short, c)
	if wanted == "": return false
	if float(e["treasury"]) - p < ArmsTrade.arms_reserve(game, town, e): return false
	e["treasury"] = float(e["treasury"]) - p
	ArmsTrade.armory(town).append(it)
	short[wanted] = int(short[wanted]) - 1
	if int(short[wanted]) <= 0: short.erase(wanted)
	ArmsTrade.led("ordered")
	return true

func _state(town: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var items := []
	for it in town["armory_items"]: items.append(it.to_dict())
	var e: Dictionary = town["econ"]
	return {"items": items, "treasury": e["treasury"], "till": e["biz"][0]["till"],
		"target": e.get("arms_tgt", {}).duplicate(), "have": e.get("arms_have", {}).duplicate(),
		"short": e["arms_short"].duplicate(), "ledger": ArmsTrade.ledger.duplicate(), "rng": rng.state}

func _sequence(cached: bool, funded: bool, offline: bool = false) -> Array:
	var town: Dictionary = _fixture()
	var e: Dictionary = town["econ"]
	var game = null if offline else Game
	if not funded: e["treasury"] = ArmsTrade.arms_reserve(game, town, e) + 12.0
	var money := float(e["treasury"]) + float(e["biz"][0]["till"])
	var rng := RandomNumberGenerator.new(); rng.seed = 711
	var pool := ["arming_sword", "boar_spear", "nasal_helm", "mail_shirt", "kite_shield"]
	var out := []
	ArmsTrade.ledger = {}
	for pass_index in 2:
		if pass_index == 1:
			# A different forge starts after native roster/stock changes. Its
			# context must be independent, never retained in the town or economy.
			Game.world["warbands"]["guards"]["units"][1].title = "spearman"
			town["armory_items"].pop_front()
		var context := {}
		for i in 96:
			var tid := ArmsTrade.pick_tid(e, pool, rng)
			if i % 11 == 0: tid = "hacking_cleaver" # foreign class, same melee role
			if i % 17 == 0: tid = "tunic" # unsupported output still refreshes stats
			var it := _item(3000 + pass_index * 96 + i, tid)
			var p := float(1 + i % 7)
			var bought := ArmsTrade.order_buy(game, town, e, it, p, context) if cached else _reference_buy(game, town, e, it, p)
			if bought: e["biz"][0]["till"] = float(e["biz"][0]["till"]) + p
			var state := _state(town, rng)
			state["bought"] = bought; state["rolled_tid"] = tid
			out.append(state)
	check(absf(float(e["treasury"]) + float(e["biz"][0]["till"]) - money) < 0.000001,
		"forge procurement transfers only actual treasury coin to the smith")
	return out

func _forge_differential(funded: bool, offline: bool = false) -> void:
	var old: Array = _sequence(false, funded, offline)
	var current: Array = _sequence(true, funded, offline)
	for i in old.size():
		check(current[i] == old[i], "same item/coin/shortfall/RNG checkpoint %d (funded=%s offline=%s)" % [i, funded, offline])
	var bought := 0; var refused := 0
	for state in current:
		if state["bought"]: bought += 1
		else: refused += 1
	check(bought > 0 and refused > 0, "fixture covers both paid orders and native refusals")
	if not offline:
		check(int(current[0]["target"].get("w_spear", 0)) > 0, "first attempted output lazily refreshes the old target")

func _reserve_differential() -> void:
	var town: Dictionary = _fixture()
	ArmsTrade.refresh_equipment(Game, town)
	town["econ"]["arrow_reserve"] = ArmsTrade.arrow_target(Game, town)
	var rng := RandomNumberGenerator.new(); rng.seed = 123
	var old := _state(town, rng)
	var arrows := int(town["econ"]["arrow_reserve"])
	town = _fixture()
	ArmsTrade.refresh_reserve(Game, town)
	check(_state(town, rng) == old and int(town["econ"]["arrow_reserve"]) == arrows,
		"shared reserve snapshot matches independent native target and arrow reads")
	check(arrows == ArmsTrade.reserve_amount(DB.QUIVER_MAX), "largest caravan tie retains sorted native winner")

func run(_tree: SceneTree) -> int:
	var world: Dictionary = Game.world
	var ledger: Dictionary = ArmsTrade.ledger
	var item_uid := Item._next_uid; var unit_uid := Unit._next_uid
	_reserve_differential()
	_forge_differential(true)
	_forge_differential(false)
	_forge_differential(true, true)
	check(Item._next_uid == item_uid and Unit._next_uid == unit_uid, "fixture creates no generated Item or person identity")
	Game.world = world; ArmsTrade.ledger = ledger
	print("Forge procurement v011: ", checks, " checks; ", fails, " failures")
	return fails
