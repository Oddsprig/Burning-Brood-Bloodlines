extends RefCounted
## Generic physical variants and existing outfit rules, without generating a world.

class Fixture:
	extends RefCounted
	var squads := {}
	var stash := []
	var company := []
	var gold := 1000000

var fails := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", message)
	else:
		print("ok: ", message)

func run(_tree: SceneTree) -> int:
	var a := Item.make("mail_shirt", "copper", 1)
	var b := Item.make("mail_shirt", "copper", 1)
	a.mark = {"n": "Forge", "b": 1, "t": "origin", "tn": "Origin", "r": "human"}
	b.mark = {"r": "human", "tn": "Origin", "t": "origin", "b": 1, "n": "Forge"}
	check(TownMarketTab.variant_key(a) == TownMarketTab.variant_key(b), "identical variants ignore UID and metadata insertion order")
	var items := [a, b]
	for field in ["wear", "q", "mat", "vr", "dull", "brk", "mk"]:
		var distinct := Item.make(a.tid, a.material, a.quality)
		distinct.mark = a.mark.duplicate()
		match field:
			"wear": distinct.wear = 1
			"q": distinct.quality = 2
			"mat": distinct.material = "tin"
			"vr": distinct.vr = 1.02
			"dull": distinct.dull = 0.25
			"brk": distinct.broken = true
			"mk": distinct.mark = {"n": "Forge", "b": 2, "t": "other", "tn": "Other", "r": "human"}
		check(TownMarketTab.variant_key(a) != TownMarketTab.variant_key(distinct), "physical variant retained: " + field)
		items.append(distinct)
	var town := {"shop": items}
	var before := items.duplicate()
	var groups := TownMarketTab.grouped_stock(town)
	check(groups.size() == 8, "only the two identical physical variants consolidate")
	var count := 0
	for group in groups:
		count += group["items"].size()
	check(count == items.size() and town["shop"] == before, "grouping retains each physical item and shop order")
	check(TownMarketTab.grouped_stock(town, "Bows").is_empty(), "category filter excludes armor from bows")
	check(TownMarketTab.grouped_stock(town, "Armor", "other").size() == 1, "search finds an actual maker origin")
	var fixture := Fixture.new()
	var u := Unit.new()
	u.uid = 1
	u.squad = 9
	fixture.company = [u]
	fixture.squads[9] = {"uniform": {"body": "mail_shirt", "helm": "nasal_helm"}, "material": "copper"}
	u.overrides["helm"] = ""
	var old := Item.make("mail_shirt", "copper", 0)
	var helm := Item.make("nasal_helm", "copper", 0)
	u.equip = {"body": old, "helm": helm}
	var better := Item.make("mail_shirt", "copper", 3)
	var wrong_material := Item.make("mail_shirt", "tin", 5)
	var broken := Item.make("mail_shirt", "copper", 5)
	broken.broken = true
	fixture.stash = [better, wrong_material, broken]
	var plan := TownMarketTab.stash_plan(fixture, u)
	check(plan["take"].get("body") == better and plan["take"].has("helm") and plan["take"]["helm"] == null, "stash best respects material and explicit empty override; excludes broken pieces")
	check(u.equip["body"] == old and fixture.stash.size() == 3, "stash preview does not mutate ownership")
	Outfit.execute(u, plan["take"], fixture.stash)
	check(u.equip["body"] == better and not u.equip.has("helm") and fixture.stash.has(old) and fixture.stash.has(helm), "existing Outfit execution returns replaced and stripped identities to stash")
	fixture.squads.clear()
	u.overrides.clear()
	var copper_candidate := Item.make("mail_shirt", "copper", 4)
	fixture.stash.append(copper_candidate)
	plan = TownMarketTab.stash_plan(fixture, u)
	# Clearing the squad removes its copper restriction. The retained quality-5 tin shirt
	# now outranks the quality-4 copper candidate, while the broken shirt remains unusable.
	check(plan["take"].get("body") == wrong_material and not plan["take"].has("main_hand") and not plan["take"].has("helm"), "unspecified gear upgrades its existing template without inventing new outfit rules")
	var shop_upgrade := Item.make("mail_shirt", "copper", 5)
	var shop := {"shop": [shop_upgrade]}
	var preview := Market.plan_best_for_unit(fixture, shop, u)
	preview["variants"] = [TownMarketTab.variant_key(shop_upgrade)]
	check(preview["buys"].size() == 1 and TownMarketTab._valid_plan(fixture, shop, u, preview), "exact buy preview is valid while stock and coins match")
	fixture.gold = 0
	check(not TownMarketTab._valid_plan(fixture, shop, u, preview), "insufficient coins invalidate the whole preview")
	fixture.gold = 1000000
	shop["shop"].clear()
	check(not TownMarketTab._valid_plan(fixture, shop, u, preview), "removed physical stock invalidates the preview")
	shop["shop"].append(shop_upgrade)
	shop_upgrade.wear = 1
	check(not TownMarketTab._valid_plan(fixture, shop, u, preview), "physical condition changed since preview invalidates purchase")
	shop_upgrade.wear = 0
	u.dead = true
	check(not TownMarketTab._valid_plan(fixture, shop, u, preview), "dead or departed members cannot execute a preview")
	return fails
