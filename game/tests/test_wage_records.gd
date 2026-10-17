extends RefCounted

var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func texts(node: Node) -> String:
	var out := ""
	if node is Label: out += (node as Label).text + "\n"
	for child in node.get_children(): out += texts(child)
	return out

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	Game.new_game(9832)
	var cultures := {}
	for town in Game.world["towns"].values():
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		var culture := String(e["culture"])
		if cultures.has(culture): continue
		var families := RecData.fams(e)
		if families.size() < 2: continue
		cultures[culture] = true
		var b: Dictionary = e["biz"][int(e["mkt"])]
		var fid := int(families[0]["id"])
		var fid2 := int(families[1]["id"])
		b["wage_claims"] = {str(fid): 150.25, str(fid2): 74.5}
		b["owed_unattributed"] = 300.0
		b["owed"] = 524.75
		var before := [b["till"], b["owed"], b["wage_claims"].duplicate(), b["owed_unattributed"]]
		var box := VBoxContainer.new()
		RecPages.business(null, town, int(b["id"]), box)
		var lines := texts(box)
		check(lines.contains("Wages still to pay") and lines.contains("the %s household" % families[0]["name"]) and lines.contains("the %s household" % families[1]["name"]), culture + ": owed wages identify the recorded households")
		check(lines.contains("Older wages without a named recipient") and lines.contains("did not save who earned it"), culture + ": legacy balance is explicitly unassigned")
		check(lines.contains(RecData.money(150.25)) and lines.contains(RecData.money(74.5)) and lines.contains(RecData.money(300)), culture + ": each amount is visible")
		check(before == [b["till"], b["owed"], b["wage_claims"], b["owed_unattributed"]], culture + ": opening records never settles or reallocates a claim")
		box.free()
		var report := EconomyAudit.town_report(Game, town)
		var rows: Array = report["businesses"].filter(func(row): return int(row["business"]) == int(b["id"]))
		check(rows.size() == 1 and rows[0]["wage_claims"] == b["wage_claims"] and float(rows[0]["owed_unattributed"]) == 300.0, culture + ": audit exposes the same recorded claims and legacy balance")
		b["owed"] += 1.0
		report = EconomyAudit.town_report(Game, town)
		check((report["issues"] as Array).any(func(row): return row["rule"] == "wage_claim_balance_mismatch" and row["business"] == b["id"]), culture + ": inconsistent total is reported, not hidden")
		b["owed"] -= 1.0
		b["closed"] = true
		report = EconomyAudit.town_report(Game, town)
		check((report["closed_wage_balances"] as Array).any(func(row): return row["business"] == b["id"] and float(row["owed"]) == 524.75), culture + ": closing a business does not hide its remaining wage balance")
		b["closed"] = false
		b.erase("wage_claims"); b.erase("owed_unattributed")
		box = VBoxContainer.new()
		RecPages.business(null, town, int(b["id"]), box)
		lines = texts(box)
		check(lines.contains("Older wages without a named recipient") and not lines.contains("Wages still to pay"), culture + ": raw old records do not guess beneficiaries")
		box.free()
	check(cultures.size() >= 4, "wage display checked across generated cultures")
	print("WAGE RECORDS checks=", checks, " failures=", fails)
	return fails
