extends RefCounted
## Native mint transactions: rounded actual goods and payments must be profitable.
class MintGame extends RefCounted:
	var world: Dictionary = {}
	var gold: float = 0.0
	var day: float = 1.0
	var company: Array = []
	var stash: Array = []
	var provisions: Dictionary = {}

var fails: int = 0
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL: ", label)

func _case(label: String, stock: Dictionary, prices: Dictionary, debase: float, room: float, expected_cast: float) -> void:
	var game := MintGame.new()
	var minter: Dictionary = {"type": "mint", "workers": 1, "kw": 0, "cap": 1, "wage": 90.0, "till": 0.0, "closed": false}
	var market: Dictionary = {"type": "market", "till": 0.0, "spend": 0.0}
	var e: Dictionary = {"mint_biz": 0, "mkt": 1, "biz": [minter, market], "stock": stock.duplicate(true), "price": prices.duplicate(true),
		"treasury": 2.0, "farm_till": 0.0, "land_fund": 0.0, "pop0": 8000, "pop": 8000, "debase": debase,
		"req": {}, "stats": {}, "fams": [], "barn": {}, "hh": {}, "granary": 0}
	var town: Dictionary = {"id": "mint094", "econ": e, "shop": [], "armory_items": []}
	game.world = {"towns": {"mint094": town}, "coin": {"cast": 0.0, "melted": 0.0, "drained": 0.0, "target": room}}
	var recipe: Dictionary = Barge.B()["coin"]["mint_recipe"].duplicate(true)
	var before: Dictionary = WorldAudit.census(game)
	Barge.mint_day(game, town, e)
	var after: Dictionary = WorldAudit.census(game)
	var cast: float = float(game.world["coin"]["cast"])
	var actual_cost: float = 0.0
	for good in stock:
		var used: int = int(stock[good]) - int(e["stock"].get(good, 0))
		check(used >= 0 and int(e["stock"].get(good, 0)) >= 0, label + ": real input stock remains nonnegative")
		actual_cost += float(used) * float(prices.get(good, 1.0))
	check(float(e["treasury"]) >= 0.0, label + ": treasury cannot overdraw")
	check(cast == 0.0 or actual_cost < cast, label + ": accepted whole-input batch is actually profitable")
	check(cast == expected_cast, label + ": largest profitable native batch within capacity/room")
	check(absf(float(market["till"]) - actual_cost) < 1e-8, label + ": market receives exact actual input payment")
	check(absf(float(e["treasury"]) + float(minter["till"]) - (2.0 + cast - actual_cost)) < 1e-8, label + ": no clamp, unbooked cash or hidden subsidy")
	check(WorldAudit.compare(before, after)["ok"], label + ": native coin/goods/items conservation gates")
	check(Barge.B()["coin"]["mint_recipe"] == recipe, label + ": recipe policy data unchanged")
	if cast > 0.0 and debase > 0.0:
		for good in recipe:
			var used: int = int(stock.get(good, 0)) - int(e["stock"].get(good, 0))
			var expected: int = mini(int(stock.get(good, 0)), int(ceil(cast / 1000.0 * float(recipe[good]) * (1.0 - debase))))
			check(used == expected, label + ": actual debased input agrees with native quoted recipe for " + str(good))
	print("MINT_V094 ", label, " cast=", cast, " actual_inputs=", actual_cost, " treasury=", e["treasury"])

func run(_tree: SceneTree) -> int:
	_case("rounded_loss", {"copper_bars": 1, "tin_bars": 1, "bronze_bars": 0, "wood": 1},
		{"copper_bars": 140.0, "tin_bars": 160.0, "bronze_bars": 1000.0, "wood": 10.0}, 0.0, 100000.0, 0.0)
	_case("debased_real_inputs", {"copper_bars": 46, "tin_bars": 4, "bronze_bars": 0, "wood": 5},
		{"copper_bars": 220.0, "tin_bars": 100.0, "bronze_bars": 1000.0, "wood": 10.0}, 0.3, 100000.0, 2200.0)
	_case("profitable_smaller_batch", {"copper_bars": 20, "tin_bars": 10, "bronze_bars": 0, "wood": 10},
		{"copper_bars": 160.0, "tin_bars": 100.0, "bronze_bars": 1000.0, "wood": 10.0}, 0.0, 750.0, 600.0)
	_case("normal_profitable", {"copper_bars": 46, "tin_bars": 4, "bronze_bars": 0, "wood": 5},
		{"copper_bars": 50.0, "tin_bars": 20.0, "bronze_bars": 1000.0, "wood": 10.0}, 0.0, 100000.0, 2200.0)
	_case("all_inputs_dear", {"copper_bars": 46, "tin_bars": 4, "bronze_bars": 0, "wood": 5},
		{"copper_bars": 400.0, "tin_bars": 400.0, "bronze_bars": 1000.0, "wood": 10.0}, 0.0, 100000.0, 0.0)
	print("Mint affordability v094: ", checks - fails, "/", checks, " checks passed")
	return fails
