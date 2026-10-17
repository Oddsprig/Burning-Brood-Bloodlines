extends RefCounted
## Native transfers and physical materials; no long campaign or complete battle.
const PoliticsFixture = preload("res://tests/test_feudal_succession.gd")
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", why)

func near(a: float, b: float) -> bool:
	return absf(a-b) < 0.000001

func levy() -> void:
	PoliticsFixture.new().fixture()
	var town: Dictionary = Game.world["towns"]["seat"]
	var e: Dictionary = town["econ"]
	var lord := Feudal.tax_recipient(Game, "seat")
	var common := Families._blank(1)
	common["cohort"] = true; common["households"] = 10; common["race"] = "human"
	common["m"] = 10; common["f"] = 10; common["purse"] = 100000.0
	common["pp"] = []; common["kp"] = []
	common["age_bins"] = {"0:-20": 10, "1:-20": 10}
	e["fams"].append(common); Families.identity(e, common)
	e["pop"] += 20; e["adults"] += 20
	e["price"] = {"grain": 1.0}; e["tax"] = {"leak": 0.0}
	e["ruler"] = {"tribute": 0.05, "temper": "steady"}
	var money := float(common["purse"]) + float(lord["purse"]) + float(e["treasury"])
	var private_before := float(common["purse"])
	var lord_before := float(lord["purse"])
	var public_before := float(e["treasury"])
	Barge.treasury_month(Game, town, e, 30.0)
	var paid := private_before - float(common["purse"])
	check(paid > 0 and near(paid, float(e["stats"]["estate_tax_received"])), "common wealth really pays the reported local lord levy")
	check(near(float(lord["purse"])-lord_before + float(e["treasury"])-public_before, paid), "lord receives common levy; city receives only separate native owner tax")
	check(near(money, float(common["purse"])+float(lord["purse"])+float(e["treasury"])), "private estate levy conserves actual coin")
	check(float(common["purse"]) >= float(Families.daily_rates(e,common)["food"])*7.0, "wealth levy protects seven days of food")
	var after := float(common["purse"])
	Barge.treasury_month(Game,town,e,30.0)
	check(near(after,float(common["purse"])) and near(paid,float(e["stats"]["estate_tax_received"])), "same-month cohort levy cannot charge twice")
	check(Game.gold == 50 and Game.world["factions"]["middle_kingdom"]["treasury"] == 3000.0, "estate levy cannot credit army or faction public wallet")

func metallurgy() -> void:
	var d := TownEcon.data()
	var e := {"culture":"middle", "knowhow":{"bronze":100.0}, "fkh":{"bronze":100.0,"iron":0.0,"steel":0.0},
		"stock":{},"price":{},"need":{},"stats":{"sales":0.0},"led":{"made":{},"used":{}},"treasury":111.0}
	for good in d["goods"]:
		e["stock"][good] = 0; e["price"][good] = float(d["goods"][good]["price"]); e["need"][good] = 10000.0
	var copper := Item.make("arming_sword","copper")
	var tin := Item.make("nasal_helm","tin")
	var legend := Item.make("arming_sword","copper",DB.LEGEND)
	var issued := Item.make("arming_sword","copper")
	var bronze := Item.make("arming_sword","bronze")
	# Native data: 300 cm3 copper at 8930 kg/m3 + 220 cm3 tin at 7280.
	var mass := 4.2806
	var town := {"econ":e,"shop":[copper,tin,legend,bronze],"armory_items":[issued]}
	check(Metallurgy.recycle_stock(town) == 2, "ordinary copper/tin market gear recycled")
	check(town["shop"] == [legend,bronze] and town["armory_items"] == [issued], "legendary and issued reserve identities preserved")
	check(near(float(Metallurgy.summary(e)["scrap_kg"]),mass), "metal mass including fractional remainder conserved")
	check(Metallurgy.recycle_stock(town) == 0 and near(float(Metallurgy.summary(e)["scrap_kg"]),mass), "recycling cannot consume or create the same material twice")
	check(e["treasury"] == 111.0, "recycling creates no coins")
	var r := RandomNumberGenerator.new(); r.seed = 7
	e["stock"]["copper_bars"] = 100; e["stock"]["tin_bars"] = 50
	check(Businesses._pick_metal(e,"arming_sword",100.0,3,r,0.0,0.0) == "", "bronze-unlocked forge waits for usable alloy rather than copper/tin fallback")
	e["stock"]["bronze_bars"] = 40
	for i in 10: check(Businesses._pick_metal(e,"arming_sword",100.0,3,r,0.0,0.0) == "bronze", "bronze-unlocked smith uses alloy equipment")
	e["stock"]["bronze_bars"] = 0; e["stock"]["wood"] = 100; e["stock"]["copper_ore"] = 100
	var b := {"type":"smelter","till":100000.0,"state":"busy","why":"","carry":0.0,"oc":{}}
	var mkt := {"till":200000.0,"spend":0.0}
	var coins := float(b["till"])+float(mkt["till"])
	var bdem := {}
	Businesses._recipes(e,d,b,d["businesses"]["smelter"],12.0,1.0,1.0,mkt,0.92,bdem)
	var batches := int(e["stock"]["bronze_bars"])/25
	check(batches > 0 and int(e["stock"]["copper_ore"]) == 100, "native smelter prefers feasible bronze alloy over extra copper refining")
	check(int(e["stock"]["copper_bars"]) == 100-22*batches and int(e["stock"]["tin_bars"]) == 50-3*batches and int(e["stock"]["wood"]) == 100-10*batches, "native alloy spends actual copper/tin/fuel inputs")
	check(near(coins,float(b["till"])+float(mkt["till"])), "native smelter purchases/output conserve owner and market coin")
	e["knowhow"]["bronze"] = 0.0
	check(Metallurgy.alloy_recipe(e,d["businesses"]["smelter"]["recipes"]).is_empty(), "locked bronze cannot alloy without knowledge")
	check(Metallurgy.recycle_stock({"econ":e,"shop":[issued]}) == 0, "locked town keeps existing primitive market equipment")

func run(_tree: SceneTree) -> int:
	levy(); metallurgy()
	print("Feudal metallurgy: %d checks, %d failures" % [checks,fails])
	return fails
