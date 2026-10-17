extends RefCounted
var checks := 0
var fails := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL ", text)
func run(_tree: SceneTree) -> int:
	for seed_v in [713, 2026, 8801]:
		Game.new_game(seed_v)
		var town: Dictionary = {}
		for t in Game.world["towns"].values():
			if TownEcon.has_econ(t) and t["econ"]["fams"].size() > 4:
				for i in Plots.count(t["econ"]["plots"]):
					if int(t["econ"]["plots"]["use"][i]) == Plots.LOT and int(t["econ"]["plots"]["ac"][i]) >= 5: town = t; break
			if not town.is_empty(): break
		check(not town.is_empty(), "generated town has a physical vacant building plot")
		if town.is_empty(): continue
		var e: Dictionary = town["econ"]
		var fams: Array = RecData.fams(e)
		var tenant: Dictionary = fams[0]; var lord: Dictionary = fams[1]
		for f in fams:
			f["homes"] = maxi(1, int(f["homes"])); f["purse"] = 0.0
			f.erase("lodging"); f.erase("lodging_rooms"); f.erase("landlord")
		e["lodgings"] = []; e["stock"]["home"] = 2; e["surcharge"] = 0.0
		tenant["homes"] = 0; tenant["purse"] = 1000000.0; lord["purse"] = 10000000.0
		var money := Barge.holdings(Game)
		TownHousing.weekly(e, Game.day)
		check(e["lodgings"].size() == 1 and int(e["stock"]["home"]) == 0, "real construction uses exactly two building units")
		check(absf(Barge.holdings(Game) - money) < 0.01, "construction transfers existing coin to market and treasury")
		check(tenant.has("lodging") and int(tenant["landlord"]) == int(lord["id"]), "tenant occupies rooms owned by the actual funding family")
		if not tenant.has("lodging"): continue
		var h: Dictionary = e["lodgings"][int(tenant["lodging"])]
		check(int(h["rooms"]) == 30 and int(h["buildings"]) == 2 and TownHousing.free_rooms(e, h) == 30 - TownHousing.room_need(tenant), "room claims use the physical thirty-room building")
		var text := "\n".join(Families.describe(town, e, tenant))
		check(text.contains("rented room") and not text.contains("Rents its house"), "family occupancy marker displays rented rooms")
		check(text.contains("Room rent: %.1f coins a week." % TownHousing.rent_week(e, tenant)), "family rent description agrees with charged room base")
		var due := TownHousing.rent_week(e, tenant); var tp := float(tenant["purse"]); var lp := float(lord["purse"])
		Families._pay_rent(e, tenant, 7, Game.day)
		check(absf(tp - float(tenant["purse"]) - due) < 0.01 and absf(float(lord["purse"]) - lp - due) < 0.01, "room rent pays the real landlord exactly once")
		check(absf(Barge.holdings(Game) - money) < 0.01, "rent conserves existing coin")
		var old_rooms := int(tenant["lodging_rooms"])
		tenant["kids"] = int(tenant["kids"]) + 2
		TownHousing.weekly(e, Game.day + 7)
		check(int(tenant["lodging_rooms"]) == old_rooms + 1, "growing household claims one available physical room")
		check(TownHousing.free_rooms(e, h) == 30 - old_rooms - 1, "growth lowers vacancy without inventing capacity")
		tenant["purse"] = 1.0; var before_lord := float(lord["purse"])
		Families._pay_rent(e, tenant, 7, Game.day + 7)
		check(float(tenant.get("rent_due", 0)) > 0 and float(lord["purse"]) == before_lord, "unfunded rent creates arrears without landlord income")
		for week in int(Barge.B()["rent"]["evict_weeks"]):
			if tenant.has("lodging"): Families._pay_rent(e, tenant, 7, Game.day + 14 + week * 7)
		check(not tenant.has("lodging") and TownHousing.free_rooms(e, h) == 30, "eviction releases actual rooms")
		var p: Array = [999, "", 0, 0.0, "", -1, 0]
		var job := {999: {"kind": "job", "title": "keeper", "where": "shop", "wage": 0.0, "keeper": true}}
		var work := Persons._work_of(e, tenant, p, job)
		check(work[1] == -1 and String(work[0]).contains("business profit"), "keeper earnings are described without an invented fixed salary")
		for row in [{"type": "weaponsmith", "owner": 1, "workers": 0, "cap": 0, "kw": 1}, {"type": "weaponsmith", "owner": 1, "workers": 2, "cap": 3, "kw": 0}, {"type": "market", "owner": -1, "workers": 2, "cap": 3, "kw": 0}]:
			check(RecData.staff_text(row).contains("%d at work" % (int(row["workers"]) + int(row["kw"]))) and RecData.staff_text(row).contains("%d of %d paid staff places" % [row["workers"], row["cap"]]), "record distinguishes working keeper from paid staffing capacity")
		e["stock"]["tools"] = 0
		check(not TownEcon._reason(town, e, "tools", false, 0).contains("stalls full"), "falling quote cannot invent full stalls without stock")
		e["stock"]["tools"] = int(Businesses.stock_cap(e, "tools") * 2) + 1
		check(TownEcon._reason(town, e, "tools", false, 0).contains("stalls full"), "full-stalls explanation requires actual stock evidence")
		var report := EconomyAudit.town_report(Game, town)
		check(report["businesses"].size() > 0 and report["businesses"][0].has("funded_openings"), "audit exposes actual cash and staffing to explain residual cases")
	print("RECORDS/LODGING checks=", checks, " failures=", fails)
	return fails
