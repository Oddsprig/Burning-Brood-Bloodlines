extends RefCounted
## Focused native records, no world generation or combat simulation.
const NativeFixture = preload("res://tests/test_feudal_succession.gd")
var checks := 0
var fails := 0
var native: NativeFixture

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func empty_plots() -> Dictionary:
	# Valid zero-plot native columns, not a partial nonempty plot book. Ordinary
	# crop rotation may build its derived empty index during work reassignment.
	var plots := {"v": 1, "gw": 0, "gh": 0, "g": PackedInt32Array(), "st": PackedFloat32Array(),
		"h": [], "crops": [], "bld": [], "heads": {}, "clear": -1, "cl_done": 0.0,
		"overcut": 0.0, "wood_seen": 0, "dirty": true, "drift": 0}
	for column in Plots.COLS: plots[column] = PackedInt32Array()
	return plots

func fixture() -> void:
	native = NativeFixture.new()
	native.fixture()
	Game.contract = {}
	Game.world["militia"] = {}; Game.world["town_guards"] = {}
	for town in Game.world["towns"].values():
		var e: Dictionary = town["econ"]
		e.merge({"granary": 0.0, "barn": {}, "price": {"grain": 1.0, "fruit": 2.0, "meat": 3.0},
			"ruler": {"tribute": 0.05}, "plots": empty_plots(), "crops": {}, "wacres": {}, "wherd": {},
			"open": [], "hands": 0, "idle_n": 1, "homes": 1, "food_short": 0.0, "unrest": 0.0, "fstage": 0})
		var f: Dictionary = e["fams"][0]
		f["idle"] = 1; f["homes"] = 1

func cohort(town_id: String, race: String = "human") -> Dictionary:
	var e: Dictionary = Game.world["towns"][town_id]["econ"]
	var f: Dictionary = Families._blank(e["fams"].size())
	f["name"] = "Owned workforce"; f["m"] = 10; f["f"] = 5; f["homes"] = 5; f["households"] = 5
	f["purse"] = 10000.0; f["cul"] = e["culture"]
	Families.identity(e, f); Population.initialize(e, f); f["race"] = race
	e["fams"].append(f); e["pop"] += 15; e["adults"] += 15; e["homes"] += 5
	Families.reassign(e, f)
	return f

func bind_militia(town_id: String, f: Dictionary, p: Array, race: String = "human") -> Unit:
	var town: Dictionary = Game.world["towns"][town_id]
	var u: Unit = Unit.create(race, str(town["faction"]), false)
	u.home_town = town_id
	Persons.bind(town["econ"], f, p, u, "reserve", float(Game.day))
	var wid := "militia:" + town_id
	Game.world["warbands"][wid] = {"id": wid, "kind": "militia", "faction": str(town["faction"]), "home": town_id,
		"units": [u], "pos": town["pos"], "anchor": town["pos"], "path": [], "walls": false, "idle_until": 0.0, "mustered": false, "drill_today": false}
	Game.world["militia"][town_id] = wid
	return u

func finances() -> void:
	var town: Dictionary = Game.world["towns"]["county"]
	var e: Dictionary = town["econ"]
	var f: Dictionary = e["fams"][0]
	var pool: Dictionary = cohort("county")
	var u: Unit = bind_militia("county", f, f["pp"][0])
	var pure := JSON.stringify(Game._serialize(Game.world))
	var view: Dictionary = Feudal.budget(Game, "county")
	var preview: Dictionary = Feudal.governance_preview(Game, "county", "fund_garrison", 100.25)
	check(JSON.stringify(Game._serialize(Game.world)) == pure, "budget and governance preview are pure native-account reads")
	check(view["lord_household_uid"] == f["household_uid"] and view["payer_household_uid"] != f["household_uid"] and preview["recipient_account"] == "town_treasury", "vassal budget distinguishes local lord, selected payer and public recipient")
	check(float(view["tax_quote"]["monthly_due"]) > 0.0 and float(view["estate_tax_received"]) == 0.0, "current monthly quote is separate from actual received tax")
	var coin: float = native.total_coin(); var treasury := float(e["treasury"]); var company := int(Game.gold)
	var payer: Dictionary = Feudal._payer(Game); var purse := float(payer["purse"])
	check(Feudal.governance(Game, "county", "fund_garrison", 100.25)["ok"] and is_equal_approx(float(e["treasury"]), treasury + 100.25) and is_equal_approx(float(payer["purse"]), purse - 100.25), "fund garrison transfers exact fractional coin into native city treasury")
	check(absf(native.total_coin() - coin) < 0.000001 and int(Game.gold) == company, "garrison funding conserves all-owner coin without touching company wallet")
	var house_before := float(f["purse"]); treasury = float(e["treasury"])
	var pay: Dictionary = Army.pay_units(Game, [u], {"kind": "town", "e": e}, "militia", {"pay": {"coin": 1.0}})
	check(is_equal_approx(float(e["treasury"]), treasury - float(pay["paid"])) and is_equal_approx(float(f["purse"]), house_before + float(pay["paid"])) and absf(native.total_coin() - coin) < 0.000001, "native garrison wage spends that treasury into actual service household")
	check(Feudal.governance(Game, "county", "fund_realm_army", 300.0)["ok"] and absf(native.total_coin() - coin) < 0.000001 and float(Game.world["factions"]["middle_kingdom"]["treasury"]) == 3300.0, "selected sovereign funds existing realm treasury without minting")
	check(not Feudal.governance(Game, "foreign", "fund_garrison", 100.0)["ok"] and not Feudal.governance(Game, "county", "fund_garrison", INF)["ok"] and not Feudal.governance(Game, "county", "fund_garrison", 1e20)["ok"], "foreign authority, nonfinite and unaffordable transfers fail")
	check(Feudal.governance_preview(Game, "county", "fund_garrison", 1.0)["ok"], "review authorised settlement transfer")
	town["faction"] = "moon_court"
	check(not Feudal.governance(Game, "county", "fund_garrison", 1.0)["ok"], "actual changed ownership rejects confirmation even before stale hierarchy refresh")
	town["faction"] = "middle_kingdom"
	check(Feudal.governance_preview(Game, "county", "fund_garrison", 100.0)["ok"], "review affordable transfer")
	payer["purse"] = 0.0
	check(not Feudal.governance(Game, "county", "fund_garrison", 100.0)["ok"], "execution revalidates changed purse after preview")
	payer["purse"] = purse - 400.25
	check(not Feudal.governance(Game, "county", "tax_policy", 0.5)["ok"], "tax decree rejects unsupported rate")
	coin = native.total_coin()
	check(Feudal.governance(Game, "county", "tax_policy", 0.10)["ok"] and Barge.common_tax_rate(e) == 0.10 and absf(native.total_coin() - coin) < 0.000001, "decree changes real future rate without producing money")
	check(not Feudal.governance(Game, "county", "tax_policy", 0.02)["ok"], "one estate tax change per week")
	var pool_before := float(pool["purse"]); house_before = float(f["purse"])
	var quote: Dictionary = Barge.common_tax_budget(e)
	var actual := Barge.common_tax_month(Game, town, e, 0.0)
	check(is_equal_approx(actual, float(quote["monthly_due"])) and is_equal_approx(pool_before - float(pool["purse"]), actual) and is_equal_approx(float(f["purse"]) - house_before, actual) and absf(native.total_coin() - coin) < 0.000001, "native monthly estate tax debits actual common wealth and credits local ruling family")
	check(Barge.common_tax_month(Game, town, e, 0.0) == 0.0, "same monthly owner tax is never duplicated")
	var row: Dictionary = Game.world["feudal"]["towns"]["county"]
	var loyalty := float(row["loyalty"])
	Feudal.daily(Game, 1)
	check(float(row["tax_distress"]) > 0.0 and float(row["loyalty"]) < loyalty, "actual common tax burden feeds local oath loyalty")
	Feudal.daily(Game, 2)
	check(float(row["tax_distress"]) == 0.0, "same owner-month burden affects loyalty once")
	Game.day = 7.0
	check(Feudal.governance(Game, "county", "tax_policy", 0.02)["ok"], "weekly tax decree cooldown expires")
	# Adopt an actual county ruler to check rank authority, without a second selection.
	Game.world["player_house"] = {"town_id": "county", "house_uid": f["founding_house_uid"], "household_uid": f["household_uid"], "ruler_uid": f["pp"][0][Persons.PERSON_UID]}
	check(Feudal.can_act(Game, "village") and not Feudal.governance_preview(Game, "county", "fund_realm_army", 1.0)["ok"], "county lord can govern real vassals but cannot spend as sovereign")

func defence() -> void:
	var town: Dictionary = Game.world["towns"]["county"]
	var e: Dictionary = town["econ"]; var f: Dictionary = e["fams"][0]; var p: Array = f["pp"][0]
	var u: Unit = bind_militia("county", f, p)
	var guard_p: Array = native.child(e, f, 2, 0, 30, p, "Actual guardsman")
	var guard: Unit = Unit.create("human", str(town["faction"]), false)
	guard.home_town = "county"
	Persons.bind(e, f, guard_p, guard, "guard", float(Game.day))
	f["serve"]["guard"] = 1; e["pop"] += 1; e["adults"] += 1
	Game.world["town_guards"]["county"] = "guard:county"
	Game.world["warbands"]["guard:county"] = {"id": "guard:county", "kind": "militia", "professional": true, "faction": str(town["faction"]),
		"home": "county", "units": [guard], "pos": town["pos"], "anchor": town["pos"], "path": [], "marching": false}
	var uid := str(p[Persons.PERSON_UID]); var unit_counter := Unit._next_uid; var population := int(e["pop"])
	var coin: float = native.total_coin(); var stock: Dictionary = e["stock"].duplicate(true)
	check(Feudal.governance(Game, "county", "muster")["ok"] and p[4] == "militia" and int(f["serve"].get("militia", 0)) == 1 and int(f["idle"]) == 0, "muster orders existing person into native service and releases civilian work")
	var rng := RandomNumberGenerator.new(); rng.seed = 33
	Militia.tick(Game, rng)
	check(Militia.band_of(Game, "county")["mustered"] and p[4] == "militia", "forced muster persists through native no-threat stand-down check")
	check(Feudal.governance(Game, "county", "stand_down")["ok"] and p[4] == "reserve" and int(f["serve"].get("militia", 0)) == 0 and int(f["idle"]) == 1, "stand-down restores same person's civilian work")
	Game.world["warbands"]["raid"] = {"id": "raid", "kind": "bandit", "faction": "bandit", "pos": town["pos"], "units": [], "raid": {"town": "county"}}
	Militia.tick(Game, rng)
	Game.day = 2.0 # county weekly drill day
	TownDefence.daily(Game, town)
	check(not Militia.band_of(Game, "county")["mustered"] and not Militia.band_of(Game, "county")["drill_today"] and p[4] == "reserve", "explicit stand-down survives actual raid threat and weekly drill")
	var view: Dictionary = Feudal.budget(Game, "county")
	check(guard_p[4] == "guard" and int(f["serve"].get("guard", 0)) == 1 and view["guard_count"] == 1 and float(view["garrison_wages_daily"]) > 0.0, "standing down militia leaves real professional guard duty and public wages intact")
	check(Diplomacy.assault_defence(Game, town) == 1, "settlement assault counts the actual guard without fictional stood-down militia")
	Game.world["lairs"] = {}
	Game.contract = {"kind": "defend", "target_id": "raid", "town_id": "county"}
	var battle := {"allies": [guard]}
	Monsters.battle_extras(Game, Game.world["warbands"]["raid"], battle)
	check(battle["allies"] == [guard] and not battle.has("militia_town") and p[4] == "reserve", "defend-contract battle cannot silently override militia stand-down or discard existing allies")
	# Round-trip the actual saved policy tree without reconstructing unrelated
	# Units; their native load constructor advances the global Unit UID counter.
	var saved: Dictionary = Game._serialize({"feudal": Game.world["feudal"]})
	var restored: Dictionary = Game._deserialize(JSON.parse_string(JSON.stringify(saved)))
	check(restored["feudal"]["towns"]["county"]["defence_policy"] == "stand_down", "defence decree persists in native world serialization")
	check(Feudal.governance(Game, "county", "auto_defence")["ok"], "restore native automatic defence")
	Militia.tick(Game, rng)
	check(Militia.band_of(Game, "county")["mustered"] and p[4] == "militia", "native raid callup works again under auto defence")
	check(Diplomacy.assault_defence(Game, town) == 2, "automatic assault defence counts only actual living militia and guard")
	Monsters.battle_extras(Game, Game.world["warbands"]["raid"], battle)
	check(battle["allies"] == [guard, u] and int(battle.get("militia_start", 0)) == 1, "restored automatic defence attaches the same real militia Unit to the native battle")
	Game.world["warbands"].erase("raid"); Militia.band_of(Game, "county")["drill_today"] = false
	Militia.tick(Game, rng)
	check(not Militia.band_of(Game, "county")["mustered"] and p[4] == "reserve", "native auto defence stands down when threat ends")
	check(str(p[Persons.PERSON_UID]) == uid and Persons.by_uid(f, u.uid) == p and Unit._next_uid == unit_counter and int(e["pop"]) == population and e["stock"] == stock and absf(native.total_coin() - coin) < 0.000001, "all defence orders retain identity, people, equipment stocks and coin")
	check(not Feudal.governance(Game, "foreign", "stand_down")["ok"] and not Feudal.governance(Game, "village", "muster")["ok"], "foreign commands and muster without existing people fail")

func local_orc() -> void:
	for tid in ["seat", "county", "village"]:
		var home: Dictionary = Game.world["towns"][tid]
		home["faction"] = "orc_horde"; home["econ"]["faction"] = "orc_horde"; home["econ"]["culture"] = "orc"
	Game.world["factions"]["orc_horde"] = {"capital": "seat", "towns": ["seat", "county", "village"], "treasury": 3000.0}
	Game.world["factions"].erase("middle_kingdom")
	var town: Dictionary = Game.world["towns"]["county"]; var e: Dictionary = town["econ"]
	var old: Dictionary = e["fams"][0]; var old_p: Array = old["pp"][0]
	var anchor := str(e["head"]["household_uid"]); var estate_index := int(e["head"]["fam"])
	Persons.remove(old, old_p, e); old["m"] = 0; old["gone"] = true; e["pop"] -= 1; e["adults"] -= 1
	var pool: Dictionary = cohort("county", "orc")
	var rng := RandomNumberGenerator.new(); rng.seed = 44
	var p: Array = Population.promote(e, pool, 0.0, rng, true)
	check(not p.is_empty(), "native orc common pool yields an actual detailed militia resident")
	if p.is_empty(): return
	var u: Unit = bind_militia("county", pool, p, "orc")
	var uid := str(p[Persons.PERSON_UID]); var pool_house := str(p[Persons.HOUSE_UID])
	var before := int(e["pop"]); var people := Census.people(e); var stock: Dictionary = e["stock"].duplicate(true)
	var coin: float = native.total_coin(); var units := Unit._next_uid
	var name_before := u.name; var body_before: Dictionary = u.body.to_dict(); var homes := int(e["homes"])
	Feudal.prepare_world(Game); Dynasty.succession_day(Game)
	var office: Dictionary = Dynasty.town_office(Game, "county")
	var lord: Dictionary = Feudal.tax_recipient(Game, "county")
	check(office.get("person_uid", "") == uid and not Population.is_cohort(lord) and u.family == int(lord.get("id", -1)), "local orc winner becomes actual individual household before office appointment")
	check(str(p[Persons.PERSON_UID]) == uid and str(p[Persons.HOUSE_UID]) != pool_house and str(pool["founding_house_uid"]) == pool_house and Persons.by_uid(lord, u.uid) == p, "only actual winner founds noble lineage, preserving person and workforce pool")
	check(u.name == name_before and u.body.to_dict() == body_before and Unit._next_uid == units and int(e["pop"]) == before and Census.people(e) == people and int(e["homes"]) == homes and e["stock"] == stock and absf(native.total_coin() - coin) < 0.000001, "local office promotion preserves combat body, name, population, homes, stocks and coin")
	check(str(e["head"]["household_uid"]) == anchor and int(e["head"]["fam"]) == estate_index, "local political appointment preserves original estate and loan anchors")
	var treasury := float(e["treasury"]); var purse := float(lord["purse"])
	var paid := Barge.common_tax_month(Game, town, e, 0.0)
	check(paid > 0.0 and is_equal_approx(float(lord["purse"]), purse + paid) and float(e["treasury"]) == treasury and absf(native.total_coin() - coin) < 0.000001, "remaining common folk pay actual new local lord, never entire cohort or public fallback")

func run(_tree: SceneTree) -> int:
	fixture(); finances(); fixture(); defence(); fixture(); local_orc()
	print("Feudal governance: %d checks, %d failures" % [checks, fails])
	return fails
