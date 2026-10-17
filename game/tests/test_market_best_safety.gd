extends RefCounted
## Small controlled inventories exercise real Market/Outfit APIs, without generating a world.

class Fixture:
	extends RefCounted
	signal changed
	var squads := {}
	var stash := []
	var company := []
	var gold := 1000000
	var world := {}
	var rep := {}
	var notifications := [0]
	# Market.price is the menu wrapper around Game's appraiser. Match that same price
	# context during Economy.buy, rather than making this fixture disagree with it.
	func best_skill(skill: String) -> int:
		return Game.best_skill(skill)

var fails := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", message)
	else:
		print("ok: ", message)

func _fixture(u: Unit) -> Fixture:
	var f := Fixture.new()
	f.company = [u]
	var tally := f.notifications
	f.changed.connect(func(): tally[0] += 1)
	return f

func _scenario() -> Dictionary:
	var u := Unit.new()
	u.uid = 1
	u.equip = {"body": Item.make("mail_shirt", "copper", 0), "helm": Item.make("nasal_helm", "copper", 0)}
	var f := _fixture(u)
	var town := {"shop": [Item.make("mail_shirt", "copper", 2), Item.make("nasal_helm", "copper", 2)]}
	var plan := Market.plan_best_for_unit(f, town, u)
	check(plan["buys"].size() == 2, "rejection fixture offers two actual upgrades")
	return {"game": f, "town": town, "unit": u, "plan": plan}

func _unchanged_rejection(s: Dictionary, reason: String) -> void:
	var f: Fixture = s["game"]
	var town: Dictionary = s["town"]
	var u: Unit = s["unit"]
	var coins := f.gold
	var shop: Array = town["shop"].duplicate()
	var stash: Array = f.stash.duplicate()
	var equipment := u.equip.duplicate()
	var notifications: int = f.notifications[0]
	var bought := Market.buy_best_for_unit(f, town, u, s["plan"])
	check(bought == 0 and f.gold == coins and town["shop"] == shop and f.stash == stash and u.equip == equipment and f.notifications[0] == notifications,
		"whole-plan rejection preserves coins, physical items and equipment: " + reason)

func run(_tree: SceneTree) -> int:
	# A superior piece exceeds the budget, but a smaller real upgrade is affordable.
	var u := Unit.new()
	u.uid = 1
	var old := Item.make("mail_shirt", "copper", 0)
	u.equip["body"] = old
	var cheap := Item.make("mail_shirt", "copper", 1)
	var expensive := Item.make("mail_shirt", "copper", 5)
	var f := _fixture(u)
	var town := {"shop": [expensive, cheap]}
	f.gold = Market.price(town, cheap)
	var plan := Market.plan_best_for_unit(f, town, u)
	check(Market.price(town, expensive) > f.gold and plan["buys"].size() == 1 and plan["buys"][0]["item"] == cheap,
		"best affordable alternative is offered when the highest quality costs too much")
	var coins := f.gold
	var bought := Market.buy_best_for_unit(f, town, u, plan)
	check(bought == 1 and f.gold == coins - int(plan["total"]) and u.equip["body"] == cheap and f.stash.has(old) and town["shop"] == [expensive] and f.notifications[0] == 1,
		"affordable upgrade purchases the exact Item and returns replaced gear")

	# A high-gain slot goes first; the next slot can fall back to a cheaper choice
	# using the remaining coins, rather than skipping an available upgrade entirely.
	u = Unit.new()
	u.uid = 2
	u.equip = {"main_hand": Item.make("dane_axe", "copper", 0), "body": Item.make("mail_shirt", "copper", 0)}
	var axe := Item.make("dane_axe", "copper", 5)
	var shirt_high := Item.make("mail_shirt", "copper", 4)
	var shirt_low := Item.make("mail_shirt", "copper", 1)
	f = _fixture(u)
	town = {"shop": [axe, shirt_high, shirt_low], "prices": {"mail_shirt": 0.1}}
	f.gold = Market.price(town, axe) + Market.price(town, shirt_low)
	plan = Market.plan_best_for_unit(f, town, u)
	var selected := []
	for b in plan["buys"]:
		selected.append(b["item"])
	check(Market.price(town, shirt_high) <= f.gold and selected.has(axe) and selected.has(shirt_low) and not selected.has(shirt_high) and int(plan["total"]) <= f.gold,
		"greedy remaining budget chooses the cheaper upgrade in a later slot")

	# Mutate the last planned purchase: even an earlier valid entry must not spend.
	for reason in ["price changed", "stock removed", "item broke", "current gear upgraded", "rule changed", "coins decreased"]:
		var scenario := _scenario()
		var owner: Fixture = scenario["game"]
		var shop_town: Dictionary = scenario["town"]
		var member: Unit = scenario["unit"]
		var preview: Dictionary = scenario["plan"]
		var last: Dictionary = preview["buys"].back()
		var item: Item = last["item"]
		match reason:
			"price changed": shop_town["prices"] = {item.tid: 2.0}
			"stock removed": shop_town["shop"].erase(item)
			"item broke": item.broken = true
			"current gear upgraded":
				owner.stash.append(member.equip[last["slot"]])
				member.equip[last["slot"]] = Item.make(item.tid, item.material, 5)
			"rule changed": member.overrides[last["slot"]] = ""
			"coins decreased": owner.gold = int(preview["total"]) - 1
		_unchanged_rejection(scenario, reason)

	# Only the off-hand is an explicit override. The two-hander is inferred from
	# current equipment, exercising Market's final-weapon check independently of
	# Outfit.wanted's explicit two-handed uniform handling.
	u = Unit.new()
	u.uid = 3
	var old_axe := Item.make("dane_axe", "copper", 0)
	u.equip["main_hand"] = old_axe
	u.overrides["off_hand"] = "kite_shield"
	var upgraded_axe := Item.make("dane_axe", "copper", 3)
	var shield := Item.make("kite_shield", "copper", 3)
	f = _fixture(u)
	town = {"shop": [shield, upgraded_axe]}
	plan = Market.plan_best_for_unit(f, town, u)
	check(plan["buys"].size() == 1 and plan["buys"][0]["item"] == upgraded_axe and int(plan["total"]) == Market.price(town, upgraded_axe),
		"final two-handed weapon excludes shield purchase and shield cost")
	var unsafe := {"buys": plan["buys"].duplicate(), "total": int(plan["total"]) + Market.price(town, shield)}
	unsafe["buys"].append({"slot": "off_hand", "item": shield, "price": Market.price(town, shield)})
	_unchanged_rejection({"game": f, "town": town, "unit": u, "plan": unsafe}, "shield conflicts with final two-handed weapon")
	bought = Market.buy_best_for_unit(f, town, u, plan)
	check(bought == 1 and u.equip["main_hand"] == upgraded_axe and not u.equip.has("off_hand") and town["shop"] == [shield] and f.stash.has(old_axe),
		"two-handed execution leaves unbought shield in actual shop")

	# The greedy preview can select a high-quality shield before a lower-quality
	# replacement sword. Execution must first free the current two-handed weapon.
	u = Unit.new()
	u.uid = 5
	var former_axe := Item.make("dane_axe", "copper", 0)
	u.equip["main_hand"] = former_axe
	u.overrides = {"main_hand": "arming_sword", "off_hand": "kite_shield"}
	var sword := Item.make("arming_sword", "copper", 1)
	var fine_shield := Item.make("kite_shield", "copper", 5)
	f = _fixture(u)
	town = {"shop": [sword, fine_shield]}
	plan = Market.plan_best_for_unit(f, town, u)
	check(plan["buys"].size() == 2 and plan["buys"][0]["item"] == fine_shield and plan["buys"][1]["item"] == sword,
		"one-handed replacement preview retains greedy shield-first selection")
	coins = f.gold
	bought = Market.buy_best_for_unit(f, town, u, plan)
	check(bought == 2 and u.equip.get("main_hand") == sword and u.equip.get("off_hand") == fine_shield and f.gold == coins - int(plan["total"])
		and town["shop"].is_empty() and f.stash == [former_axe] and f.notifications[0] == 2,
		"two-handed to sword-and-shield purchase equips both actual items and reports two successful pieces")
	check(plan["buys"][0]["item"] == fine_shield and plan["buys"][1]["item"] == sword,
		"execution does not rewrite the preview's greedy item order")

	# An impossible inferred shield must not consume the upgrade's provisional budget.
	u = Unit.new()
	u.uid = 8
	u.equip["main_hand"] = Item.make("dane_axe", "copper", 0)
	u.overrides["off_hand"] = "kite_shield"
	var affordable_axe := Item.make("dane_axe", "copper", 1)
	var impossible_shield := Item.make("kite_shield", "copper", 5)
	f = _fixture(u)
	town = {"shop": [impossible_shield, affordable_axe]}
	f.gold = maxi(Market.price(town, impossible_shield), Market.price(town, affordable_axe))
	plan = Market.plan_best_for_unit(f, town, u)
	check(plan["buys"].size() == 1 and plan["buys"][0]["item"] == affordable_axe and int(plan["total"]) == Market.price(town, affordable_axe),
		"inferred two-hander excludes impossible shield before budgeting and retains affordable axe upgrade")

	# Each requested piece is affordable alone, but together they exceed the purse.
	# Defer the dependent shield so its higher score cannot block the usable sword.
	u = Unit.new()
	u.uid = 9
	u.equip["main_hand"] = Item.make("dane_axe", "copper", 0)
	u.overrides = {"main_hand": "arming_sword", "off_hand": "kite_shield"}
	var affordable_sword := Item.make("arming_sword", "copper", 1)
	var dependent_shield := Item.make("kite_shield", "copper", 5)
	f = _fixture(u)
	town = {"shop": [dependent_shield, affordable_sword]}
	f.gold = maxi(Market.price(town, dependent_shield), Market.price(town, affordable_sword))
	plan = Market.plan_best_for_unit(f, town, u)
	check(plan["buys"].size() == 1 and plan["buys"][0]["item"] == affordable_sword and int(plan["total"]) == Market.price(town, affordable_sword),
		"shield dependent on one-handed replacement waits for weapon budget and yields a usable sword-only plan")
	coins = f.gold
	bought = Market.buy_best_for_unit(f, town, u, plan)
	check(bought == 1 and u.equip.get("main_hand") == affordable_sword and not u.equip.has("off_hand") and town["shop"] == [dependent_shield]
		and f.gold == coins - int(plan["total"]) and f.stash.size() == 1 and f.stash[0].tid == "dane_axe",
		"limited-budget one-handed replacement equips sword and leaves the shield unpurchased")

	# Broken high-quality gear is not a usable current item or a usable stash choice.
	u = Unit.new()
	u.uid = 4
	var broken_current := Item.make("mail_shirt", "copper", 5)
	broken_current.broken = true
	u.equip["body"] = broken_current
	var usable := Item.make("mail_shirt", "copper", 1)
	var broken_stash := Item.make("mail_shirt", "copper", 5)
	broken_stash.broken = true
	f = _fixture(u)
	f.stash = [broken_stash, usable]
	var outfit := Outfit.plan_unit(u, {"body": "mail_shirt"}, "any", f.stash.duplicate())
	check(outfit["take"].get("body") == usable and outfit["missing"].is_empty(), "usable lower-quality stash gear replaces broken higher-quality current gear")
	Outfit.execute(u, outfit["take"], f.stash)
	check(u.equip["body"] == usable and f.stash.has(broken_current) and f.stash.has(broken_stash) and not f.stash.has(usable),
		"broken replacement preserves all actual item ownership")

	# Filling a squad must not spend on broken shop stock that Outfit cannot use.
	var leader := Unit.new()
	leader.uid = 6
	leader.role = "officer"
	u = Unit.new()
	u.uid = 7
	u.squad = leader.uid
	f = _fixture(u)
	f.company = [leader, u]
	f.squads[leader.uid] = {"uniform": {"body": "mail_shirt"}, "material": "any"}
	var broken_sale := Item.make("mail_shirt", "copper", 0)
	broken_sale.broken = true
	town = {"shop": [broken_sale]}
	coins = f.gold
	var filled := Market.buy_to_fill(f, town)
	check(filled["bought"].is_empty() and int(filled["spent"]) == 0 and filled["short"].size() == 1 and f.gold == coins
		and town["shop"] == [broken_sale] and f.stash.is_empty() and u.equip.is_empty() and f.notifications[0] == 0,
		"fill uniforms spends nothing when the only matching stock is broken")
	var usable_sale := Item.make("mail_shirt", "copper", 1)
	town["shop"].append(usable_sale)
	var usable_cost := Market.price(town, usable_sale)
	filled = Market.buy_to_fill(f, town)
	check(Market.price(town, broken_sale) < usable_cost and filled["bought"].size() == 1 and int(filled["spent"]) == usable_cost and filled["short"].is_empty()
		and f.gold == coins - usable_cost and u.equip.get("body") == usable_sale and town["shop"] == [broken_sale] and f.stash.is_empty() and f.notifications[0] == 1,
		"fill uniforms skips cheaper broken stock and equips the exact usable purchase")
	return fails
