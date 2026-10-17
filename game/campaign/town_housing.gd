class_name TownHousing
extends RefCounted
## Two real building units, thirty rooms total, on one five-acre town lot.
const ROOMS := 30
const PEOPLE_PER_ROOM := 2
const NAMES := {"middle": "lodging houses", "northern": "guest hearths", "elf": "guest groves", "moon_elf": "moon guest halls", "dwarf": "lodging halls", "orc": "bunk lodges", "goblin": "rooming warrens"}

static func rows(e: Dictionary) -> Array:
	if not e.has("lodgings"): e["lodgings"] = []
	return e["lodgings"]

static func room_need(f: Dictionary) -> int:
	return int(ceil(float(Families.people(f)) / PEOPLE_PER_ROOM))

static func free_rooms(e: Dictionary, h: Dictionary) -> int:
	var used := 0
	for f in e["fams"]:
		if not f.get("gone", false) and int(f.get("lodging", -1)) == int(h["id"]) and int(f["homes"]) > 0: used += int(f.get("lodging_rooms", 0))
	return maxi(0, int(h["rooms"]) - used)

static func rent_week(e: Dictionary, f: Dictionary) -> float:
	# Two ordinary building units' rent split among the actual thirty rooms.
	return Barge.rent_week(e) * 2 * float(f.get("lodging_rooms", room_need(f))) / ROOMS

static func leave(e: Dictionary, f: Dictionary, day: float) -> void:
	if not f.has("lodging"): return
	f["homes"] = 0
	f.erase("lodging"); f.erase("lodging_rooms"); f.erase("landlord"); f.erase("rent_due"); f.erase("rent_late")
	Shelter.lost_home(e, f, "evicted", day)

static func try_rent(e: Dictionary, f: Dictionary, day: float) -> bool:
	if not Shelter.homeless(f): return false
	var need := room_need(f)
	for h in rows(e):
		if free_rooms(e, h) < need: continue
		var due := Barge.rent_week(e) * 2 * need / ROOMS
		var reserve := float(Families.daily_rates(e, f)["food"]) * float(e["price"].get("grain", 1)) * 7
		if float(f["purse"]) < due * 2 + reserve: continue
		f["lodging"] = h["id"]; f["lodging_rooms"] = need; f["landlord"] = h["owner"]
		f["homes"] = 1; f["cond"] = 1.0
		Shelter._housed(e, f, day)
		Families.add_hist(f, "Rented %d rooms in the %s." % [need, h["name"]], day)
		return true
	return false

static func weekly(e: Dictionary, day: float) -> void:
	var P: Dictionary = e.get("plots", {})
	if P.is_empty(): return
	var wanted := 0
	for f in e["fams"]:
		if f.has("lodging") and (f.get("gone", false) or int(f["homes"]) <= 0): leave(e, f, day)
		if Shelter.homeless(f): wanted += room_need(f)
	# As households grow or shrink, room claims stay physical and share the available vacancy.
	for f in e["fams"]:
		if not f.has("lodging") or f.get("gone", false): continue
		var h: Dictionary = rows(e)[int(f["lodging"])]
		var need := room_need(f)
		if need <= int(f["lodging_rooms"]) + free_rooms(e, h): f["lodging_rooms"] = need
	var free := 0
	for h in rows(e):
		var owner := int(h["owner"])
		if owner >= e["fams"].size() or e["fams"][owner].get("gone", false):
			h["owner"] = 0; P["own"][int(h["plot"])] = 0
			for f in e["fams"]:
				if int(f.get("lodging", -1)) == int(h["id"]): f["landlord"] = 0
		free += free_rooms(e, h)
	if wanted > free:
		var lot := -1
		for i in Plots.count(P):
			if int(P["use"][i]) == Plots.LOT and int(P["ac"][i]) >= 5: lot = i; break
		if lot >= 0:
			var price := 2 * float(e["price"].get("home", 200))
			var land_price := 5 * float(TownEcon.data()["land"]["acre_price"]) * Barge.pl(e)
			var lord: Dictionary = {}
			for f in e["fams"]:
				if f.get("gone", false) or f.get("estate", false) or float(f["purse"]) < price + land_price + float(Families.daily_rates(e, f)["food"]) * float(e["price"].get("grain", 1)) * 14: continue
				if lord.is_empty() or float(f["purse"]) > float(lord["purse"]): lord = f
			if not lord.is_empty():
				e["req"]["home"] = float(e["req"].get("home", 0)) + 2.0 / 7
				if int(e["stock"].get("home", 0)) >= 2:
					TownEcon.pay_market(e, lord, price)
					lord["purse"] = float(lord["purse"]) - land_price; e["treasury"] = float(e["treasury"]) + land_price
					e["stock"]["home"] = int(e["stock"]["home"]) - 2; TownEcon.led(e, "used", "home", 2)
					var h := {"id": rows(e).size(), "plot": lot, "owner": lord["id"], "rooms": ROOMS, "buildings": 2, "name": NAMES.get(String(e["culture"]), "lodging houses")}
					rows(e).append(h); P["use"][lot] = Plots.HOME; P["own"][lot] = lord["id"]
					if not P.has("lodging_plots"): P["lodging_plots"] = []
					P["lodging_plots"].append(lot)
					Plots._hist(P, lot, day, "Two %s built here: %d rooms." % [h["name"], ROOMS]); Plots._dirty(P)
	for f in e["fams"]:
		if Shelter.homeless(f): try_rent(e, f, day)

static func plot_info(e: Dictionary, plot: int) -> Dictionary:
	for h in rows(e):
		if int(h["plot"]) != plot: continue
		var tenants := []
		for f in e["fams"]:
			if int(f.get("lodging", -1)) == int(h["id"]) and not f.get("gone", false): tenants.append({"text": "%s: %d rooms, %.1f coins rent a week" % [f["name"], f["lodging_rooms"], rent_week(e, f)], "fid": f["id"]})
		return {"title": String(h["name"]).capitalize(), "lines": ["Two lodging houses on five acres; thirty rooms in total.", "%d rooms occupied, %d free." % [ROOMS - free_rooms(e, h), free_rooms(e, h)]], "taps": [{"text": "Landlord: " + Plots.owner_text(e, int(h["owner"])), "fid": h["owner"]}] + tenants}
	return {}
