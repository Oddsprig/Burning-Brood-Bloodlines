extends RefCounted
## Differential checks against the frozen 4ae8f53 algorithms, including their tie behavior.
const Original = preload("res://tests/reference_smarter_loops.gd")
var fails := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", label)

func exact(a, b) -> bool:
	return JSON.stringify(Game._serialize(a), "", true, true) == JSON.stringify(Game._serialize(b), "", true, true)

func run(_tree: SceneTree) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 592026
	# Unique and tied ranking keys, many equal hardship scores, empty and tiny pools.
	for trial in 400:
		var cands := []
		var count := rng.randi_range(0, 500)
		var limit := rng.randi_range(7, 11)
		for i in count:
			cands.append([float(rng.randi_range(0, 12)) / 10.0,
				rng.randi_range(0, 12) if trial % 2 == 0 else i, i])
		var expected := cands.duplicate()
		expected.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
		var actual := Recruits._rank_pool_candidates(cands.duplicate(), limit)
		check(actual.slice(0, limit) == expected.slice(0, limit), "recruit ranking trial %d" % trial)
	WorldGen.gen_size = "normal"
	Game.new_game(314159)
	CampaignWorld.presim_step(Game, 7)
	var towns: Array = Game.world["towns"].values()
	for trial in 400:
		var town: Dictionary = towns[trial % towns.size()]
		var e: Dictionary = town["econ"].duplicate(true)
		for b in e["biz"]:
			b["wage"] = [0.01, 1.0, 12.5, 100.0, 110.0, 1000.0][rng.randi_range(0, 5)]
			b["cap"] = rng.randi_range(0, 12)
			b["workers"] = rng.randi_range(0, int(b["cap"]) + 2)
			b["closed"] = trial % 7 == 0
			b["till"] = float(b["wage"]) * rng.randi_range(0, 20)
		var f: Dictionary = e["fams"][rng.randi_range(1, e["fams"].size() - 1)]
		var ad := maxi(0, Families.adults(f) - Families.serving(f))
		var own := rng.randi_range(0, ad)
		var need := Families.need_hands(f)
		check(Families._to_trades(e, f, own, ad, need, e["biz"]) == Original.original_to_trades(e, f, own, ad, need, e["biz"]),
			"hiring wage-count trial %d" % trial)
	for town in towns:
		var a: Dictionary = town.duplicate(true)
		var b: Dictionary = town.duplicate(true)
		_seed_offers(a["econ"])
		_seed_offers(b["econ"])
		Original.original_wants(Game, a, a["econ"], 0, Game.day)
		Herds._wants(Game, b, b["econ"], 0, Game.day)
		check(exact(a, b), "live herd sales %s" % town["id"])
		for business in town["econ"]["biz"]:
			if String(business["type"]) != "butcher": continue
			var ea: Dictionary = town["econ"].duplicate(true)
			var eb: Dictionary = town["econ"].duplicate(true)
			for e in [ea, eb]:
				_seed_offers(e)
				e["biz"][int(business["id"])]["till"] = 1000000000.0
				e["biz"][int(e["mkt"])]["till"] = 1000000000.0
				e["dem"]["fresh_meat"] = 1000000.0
			var wd := rng.randf_range(0.25, 60.0)
			var share := float(TownEcon.data()["market"]["broker_share"])
			var paid_a := Original.original_butcher_day(ea, ea["biz"][int(business["id"])], wd, 1.0, ea["biz"][int(ea["mkt"])], share, {})
			var paid_b := Herds.butcher_day(eb, eb["biz"][int(business["id"])], wd, 1.0, eb["biz"][int(eb["mkt"])], share, {})
			check(paid_a == paid_b and exact(ea, eb), "butcher order and books %s" % town["id"])
		var pool_a: Dictionary = town.duplicate(true)
		var pool_b: Dictionary = town.duplicate(true)
		var first_uid := Unit._next_uid
		var first_item_uid := Item._next_uid
		var ra := RandomNumberGenerator.new(); ra.seed = 8192
		var rb := RandomNumberGenerator.new(); rb.seed = 8192
		var old := Original.original_family_pool(pool_a, ra)
		var after_uid := Unit._next_uid
		var after_item_uid := Item._next_uid
		Unit._next_uid = first_uid
		Item._next_uid = first_item_uid
		var fresh := Recruits._family_pool(pool_b, rb)
		check(ra.state == rb.state and Unit._next_uid == after_uid and Item._next_uid == after_item_uid and exact(old, fresh) and exact(pool_a, pool_b),
			"recruit identities, gear, records and RNG %s" % town["id"])
	print("smarter loops: %d differential checks, %d failures" % [checks, fails])
	return fails

func _seed_offers(e: Dictionary) -> void:
	var hd: Dictionary = e["hd"]
	hd["of"] = []
	for h in hd["h"].values():
		for age in ["y", "g", "o"]:
			if int(h[age]) > 0:
				hd["of"].append([int(h["id"]), age, mini(5, int(h[age])), "surplus"])
