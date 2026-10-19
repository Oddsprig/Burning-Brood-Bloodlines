extends RefCounted

## Black-box estate sales use generated people, actual plots, animal records and
## existing coins. The oracle walks physical books, independently of sale previews.
var checks := 0
var fails := 0
var modes_seen := {}
var mask_seen := {}

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", why)

func near(a: float, b: float, why: String) -> void:
	check(absf(a - b) < 0.00001, "%s (%.8f versus %.8f)" % [why, a, b])

func keepers(e: Dictionary, f: Dictionary) -> int:
	var n := 0
	for bid in f.get("keeps", []):
		var b: Dictionary = e["biz"][int(bid)]
		if not b.get("closed", false) and int(b["owner"]) == int(f["id"]) and int(b.get("kw", 0)) > 0:
			n += 1
	return n

func capacity(e: Dictionary, f: Dictionary) -> float:
	var casual := 0
	for value in f.get("cj", {}).values(): casual += int(value)
	return float(maxi(0, Families.adults(f) - Families.serving(f) - keepers(e, f) - Families.job_total(f) - casual)) + Barge.helper_hands(e, f, float(e["day"]))

func physical_need(e: Dictionary, f: Dictionary) -> float:
	var P: Dictionary = e["plots"]
	CropRotation.ensure(e, P, float(e["day"]))
	var active := 0.0
	var fallow := 0.0
	for i in Plots.count(P):
		if int(P["own"][i]) != int(f["id"]) or not Plots.LAND_USES.has(int(P["use"][i])): continue
		if String(P["variety"][i]) == "fallow": fallow += float(P["ac"][i])
		else: active += float(P["ac"][i])
	var L: Dictionary = TownEcon.data()["land"]
	var aph := float(L["acres_per_hand"])
	var drafted := active if int(f.get("ox", -1)) < 0 else minf(active, float(f["ox"]) * aph)
	var result := drafted / aph + (active - drafted) / float(L["acres_no_ox"]) + fallow / aph * float(L.get("fallow_upkeep_share", 0.25))
	for h in Herds.of_family(e, int(f["id"])):
		var per_hand := float(Herds.kind(String(h["k"])).get("per_hand", 0))
		if per_hand > 0:
			result += (float(h["g"]) + float(h["o"]) + float(h["y"]) * 0.5) / per_hand
	return result

func property(e: Dictionary) -> Dictionary:
	var result := {"land": {}, "animals": {}}
	for f in e["fams"]:
		for good in f["land"]: result["land"][good] = int(result["land"].get(good, 0)) + int(f["land"][good])
	for h in Herds.herds(e).values():
		for age in ["y", "g", "o"]:
			var key := "%s:%s" % [h["k"], age]
			result["animals"][key] = int(result["animals"].get(key, 0)) + int(h[age])
	return result

func people(e: Dictionary) -> Array:
	var result := []
	for f in e["fams"]:
		var ids := []
		for p in f.get("pp", []): ids.append([p[0], p[2], p[3], p[4], p[5], p[6]])
		for p in f.get("kp", []): ids.append([p[0], p[2], p[3]])
		result.append([Families.people(f), f.get("serve", {}).duplicate(true), ids])
	return result

func creditors(e: Dictionary) -> Array:
	var result := []
	for b in e["biz"]: result.append([b.get("wage_claims", {}).duplicate(true), b.get("owed_unattributed", 0), b.get("owed", 0)])
	return result

func lots(e: Dictionary) -> Dictionary:
	return e.get("harvest_book", {}).get("lots", {}).duplicate(true)

func books(e: Dictionary, label: String) -> void:
	var P: Dictionary = e["plots"]
	var physical := {}
	for i in Plots.count(P):
		if not Plots.LAND_USES.has(int(P["use"][i])): continue
		var key := "%d:%s" % [int(P["own"][i]), P["crops"][int(P["sub"][i])]]
		physical[key] = int(physical.get(key, 0)) + int(P["ac"][i])
		check(int(P["ac"][i]) > 0 and int(P["ac"][i]) <= Plots.ACRES, label + ": partial plots retain valid physical bounds")
	for f in e["fams"]:
		for good in f["land"]:
			var key := "%d:%s" % [int(f["id"]), good]
			check(int(physical.get(key, 0)) == int(f["land"][good]), label + ": every owner crop mirror matches physical plots")
	for key in physical:
		var fid := int(String(key).get_slice(":", 0))
		var good := String(key).get_slice(":", 1)
		check(int(e["fams"][fid]["land"].get(good, 0)) == int(physical[key]), label + ": no unmirrored acreage")
	for f in e["fams"]:
		var ox := 0
		var heads := {}
		for h in Herds.of_family(e, int(f["id"])):
			if String(h["k"]) == "oxen": ox += Herds.head(h)
			elif Herds.GRAZE.has(String(h["k"])): heads[h["k"]] = int(heads.get(h["k"], 0)) + Herds.head(h)
		check(ox == maxi(0, int(f.get("ox", 0))), label + ": draft mirrors match actual animals")
		for kind in f["herd"]: check(int(f["herd"][kind]) == int(heads.get(kind, 0)), label + ": herd mirrors match actual species records")

func buyer(e: Dictionary, mode: String) -> Dictionary:
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false) or Families.adults(f) <= 0: continue
		if mode == "service" and Families.serving(f) > 0: return f
		if mode == "keeper" and keepers(e, f) > 0: return f
		if mode == "stale_keeper" and keepers(e, f) > 0 and Families.serving(f) == 0:
			var later_capacity := float(maxi(0, Families.adults(f) - keepers(e, f))) + Barge.helper_hands(e, f, float(e["day"]))
			if later_capacity >= 0.5:
				for bid in f["keeps"]:
					var shop: Dictionary = e["biz"][int(bid)]
					if not shop.get("closed", false) and int(shop["owner"]) == int(f["id"]) and int(shop.get("kw", 0)) > 0 and String(shop["type"]) != "herder": return f
		if mode == "occupied" and Families.job_total(f) > 0 and Families.serving(f) == 0 and keepers(e, f) == 0: return f
		if not mode in ["service", "keeper", "stale_keeper", "occupied"] and Families.serving(f) == 0 and keepers(e, f) == 0:
			if mode == "loan":
				# Select real credit after the intended native holding clearance.
				# A one-adult/one-home buyer has only 1,100 coin credit, below
				# the 1,199 gap for a second 1,200-coin acre in this control.
				var cleared: Dictionary = f.duplicate()
				cleared["land"] = {}; cleared["herd"] = {}
				if f.get("destitute", false) or f.has("estate") or float(f["debt"]) > 0.0 or int(f.get("ln", {}).get("miss", 0)) > 0: continue
				if Loans.credit_left(e, cleared) < float(TownEcon.data()["land"]["acre_price"]) - 1.0: continue
			return f
	return {}

func transfer_animals(e: Dictionary, source: Dictionary, target: Dictionary, kind: String, n: int) -> int:
	var destination := Herds.herd_for(e, int(target["id"]), kind, float(e["day"]))
	var left := n
	for h in Herds.of_family(e, int(source["id"])):
		if String(h["k"]) != kind or h == destination: continue
		for age in ["o", "y", "g"]:
			var q := mini(left, int(h[age]))
			if q > 0: left -= Herds._transfer(e, h, destination, age, q, "sold", "bought", "controlled property fixture", "controlled property fixture", float(e["day"]))
			if left <= 0: return n
	return n - left

func configure(town: Dictionary, original: Dictionary, mode: String, draft: String, fallow: bool) -> Array:
	var e: Dictionary = original.duplicate(true)
	var f := buyer(e, mode)
	if f.is_empty(): return []
	town["econ"] = e
	var estate: Dictionary = e["fams"][0]
	# Move existing holdings; do not replace land or herd mirrors independently.
	for good in f["land"].keys(): Families.move_land(e, f, estate, String(good), int(f["land"][good]))
	for kind in f["herd"].keys(): Families.move_herd(e, f, estate, String(kind), int(f["herd"][kind]))
	transfer_animals(e, f, estate, "oxen", maxi(0, int(f.get("ox", 0))))
	# Direct-owner hens, bees and other nongrazing kinds have actual records
	# without f.herd mirrors. Empty those real holdings through the same ledger.
	var remaining_animals := {}
	for h in Herds.of_family(e, int(f["id"])):
		var kind := String(h["k"])
		remaining_animals[kind] = int(remaining_animals.get(kind, 0)) + Herds.head(h)
	for kind in remaining_animals:
		var n := int(remaining_animals[kind])
		if n > 0: check(transfer_animals(e, f, estate, String(kind), n) == n, "controlled empty holding transfers every actual direct-owner animal")
	if mode != "occupied":
		for k in f["jobs"].keys(): Families.set_job(e, f, int(k), 0)
		Shelter.release_casual(e, f)
	# Freeze other offers, retaining incumbent jobs and actual keepers.
	for b in e["biz"]: b["cap"] = int(b["workers"])
	for job in e.get("cjcap", {}): e["cjcap"][job] = float(e.get("cjused", {}).get(job, 0))
	var physical = load("res://tests/farm_fixture_tools.gd").new()
	if int(estate["land"].get("grain", 0)) < 24:
		check(physical.grain(e, estate, 24), "generated registry supplies actual estate cereal plots")
	var P: Dictionary = e["plots"]
	for i in Plots.count(P):
		if int(P["own"][i]) == 0 and Plots.LAND_USES.has(int(P["use"][i])) and String(P["crops"][int(P["sub"][i])]) == "grain":
			P["rotation_phase"][i] = posmod((3 if fallow else 0) - Calendar.year(float(e["day"])), 4)
	P["crop_count"] = -1
	CropRotation.ensure(e, P, float(e["day"]))
	# The spare draft animals still exist on another generated household.
	var storage: Dictionary = {}
	for other in e["fams"]:
		if other != f and other != estate and not other.get("gone", false): storage = other; break
	check(not storage.is_empty(), "generated animal owner available")
	if storage.is_empty(): return []
	transfer_animals(e, estate, storage, "oxen", maxi(0, int(estate.get("ox", 0))))
	if draft != "none":
		var desired := 1 if draft == "partial" else int(ceil(float(Families.acres(estate)) / float(TownEcon.data()["land"]["acres_per_hand"])))
		var left := desired
		for other in e["fams"]:
			if other == estate or other == f: continue
			left -= transfer_animals(e, other, estate, "oxen", mini(left, maxi(0, int(other.get("ox", 0)))))
			if left <= 0: break
		check(int(estate.get("ox", 0)) > 0, "draft control uses existing actual oxen")
	Families.reassign(e, f)
	# Isolate affordability using only transfers of existing coins.
	for other in e["fams"]:
		if other.get("estate", false): continue
		e["treasury"] = float(e["treasury"]) + float(other["purse"])
		other["purse"] = 0.0
	var wanted := 40.0 * TownEcon.COIN + 12000.0
	if mode == "budget" or mode == "loan" or mode == "denied": wanted = 40.0 * TownEcon.COIN + float(TownEcon.data()["land"]["acre_price"]) + 1.0
	if mode == "reserve": wanted = 40.0 * TownEcon.COIN
	var moved := minf(wanted, maxf(0.0, float(e["treasury"])))
	e["treasury"] = float(e["treasury"]) - moved
	f["purse"] = moved
	if mode == "debt": Loans.owe(e, f, 1.0, float(e["day"]))
	if mode in ["budget", "denied"]:
		# Preserve existing treasury coins in a noncandidate business till.
		var market: Dictionary = e["biz"][int(e["mkt"])]
		market["till"] = float(market["till"]) + float(e["treasury"])
		e["treasury"] = 0.0
	WageClaims.accrue_day(e, int(e["day"]) + 1)
	return [e, f]

## Retain the original physical preview as an independent oracle for the fast
## owner-index path, including small splits and whole-plus-part transfers.
func preview_equivalence(e: Dictionary, a: Dictionary, b: Dictionary) -> void:
	var P: Dictionary = e["plots"]
	var before: Dictionary = P.duplicate(true)
	for n in [1, 4, 5, 6, 9, 11]:
		if n > int(a["land"].get("grain", 0)): continue
		var fast: Dictionary = Plots.purchase_work(e, a, b, "grain", n)
		check(P == before, "purchase preview leaves live plots and indices untouched")
		var control: Dictionary = {"plots": P.duplicate(true), "crops": e["crops"].duplicate(true),
			"day": e["day"], "culture": e["culture"], "climate": e["climate"], "head": e.get("head", {})}
		Plots.land_moved(control, a, b, "grain", n)
		var active: float = 0.0
		var fallow: float = 0.0
		for row in CropRotation.work_acres(control, b).values():
			active += float(row["active"])
			fallow += float(row["fallow"])
		check(fast == {"acres": active + fallow, "active": active, "fallow": fallow},
			"indexed preview matches native boundaries and split rotation: %s %d" % [e["culture"], n])

func sales(town: Dictionary, original: Dictionary, mode: String, draft: String = "none", fallow: bool = false) -> void:
	var setup := configure(town, original, mode, draft, fallow)
	if setup.is_empty(): return
	modes_seen[mode] = true
	var e: Dictionary = setup[0]
	var f: Dictionary = setup[1]
	var label := "%s %s %s %s" % [e["culture"], mode, draft, "fallow" if fallow else "active"]
	if mode == "free" and draft == "none": preview_equivalence(e, e["fams"][0], f)
	var old_property := property(e)
	var old_people := people(e)
	var old_lots := lots(e)
	var old_creditors := creditors(e)
	var gold := TownEcon.town_gold(e)
	var old_jobs: Dictionary = f["jobs"].duplicate(true)
	var old_casual: Dictionary = f.get("cj", {}).duplicate(true)
	var old_keeper_count := keepers(e, f)
	var old_last := float(f["last"])
	var old_wage_day := int(e["wage_day"])
	var reserve := 40.0 * TownEcon.COIN
	var old_purse := float(f["purse"])
	var old_debt := float(f["debt"])
	var old_ox := int(f.get("ox", 0))
	var opening_need := physical_need(e, f)
	var opening_capacity := capacity(e, f)
	var opening_acres := Families.acres(f)
	var opening_herd_care := Families.herd_hands(f, e)
	check(opening_need <= opening_capacity + 0.00001, label + ": controlled empty holding begins within real available labour (need=%.8f capacity=%.8f acres=%d ox=%d herd_care=%.8f)" % [opening_need, opening_capacity, opening_acres, old_ox, opening_herd_care])
	var opening_credit := maxf(0.0, floorf(minf(Loans.credit_left(e, f), float(e["treasury"]) - Loans._reserve(e))))
	var opening_treasury := float(e["treasury"])
	if mode == "loan":
		var two_acre_gap := maxf(0.0, 2.0 * float(TownEcon.data()["land"]["acre_price"]) - (old_purse - reserve))
		check(opening_credit >= ceilf(two_acre_gap), label + ": ordinary loan control has existing treasury and real household credit for two acres (credit=%.8f gap=%.8f treasury=%.8f treasury_reserve=%.8f adults=%d homes=%d)" % [opening_credit, two_acre_gap, opening_treasury, Loans._reserve(e), Families.adults(f), int(f["homes"])])
		check(opening_capacity >= 2.0 / float(TownEcon.data()["land"]["acres_no_ox"]) and int(e["fams"][0]["land"].get("grain", 0)) >= 2, label + ": ordinary loan control offers two actual acres within real capacity")
	for repeat in 3:
		TownEcon._sell_land(e, TownEcon.data(), float(e["day"]))
		var actual_herds := []
		for h in Herds.of_family(e, int(f["id"])):
			if Herds.head(h) > 0: actual_herds.append([h["k"], h["y"], h["g"], h["o"]])
		check(physical_need(e, f) <= capacity(e, f) + 0.00001, label + ": repeated native estate sale stays within real available labour (repeat=%d need=%.8f capacity=%.8f acres=%d ox=%d herd_care=%.8f helpers=%.8f adults=%d serving=%d keepers=%d jobs=%d casual=%s opening_need=%.8f opening_capacity=%.8f opening_acres=%d opening_ox=%d opening_herd_care=%.8f actual_herds[k,y,g,o]=%s)" % [repeat, physical_need(e, f), capacity(e, f), Families.acres(f), int(f.get("ox", 0)), Families.herd_hands(f, e), Barge.helper_hands(e, f, float(e["day"])), Families.adults(f), Families.serving(f), keepers(e, f), Families.job_total(f), JSON.stringify(f.get("cj", {})), opening_need, opening_capacity, opening_acres, old_ox, opening_herd_care, JSON.stringify(actual_herds)])
		check(f["jobs"] == old_jobs and f.get("cj", {}) == old_casual, label + ": purchased holding never displaces occupied paid jobs")
		check(keepers(e, f) == old_keeper_count, label + ": real shop keepers remain at work")
		near(TownEcon.town_gold(e), gold, label + ": sale, funding and loan conserve existing coins")
		check(property(e) == old_property, label + ": physical acres and every animal age conserved")
		check(people(e) == old_people, label + ": registry identities and registered service conserved")
		check(lots(e) == old_lots, label + ": earlier dated food ownership stays with its producer")
		check(creditors(e) == old_creditors, label + ": earned creditors survive sale without new historical wages")
		check(float(f["last"]) == old_last and int(e["wage_day"]) == old_wage_day, label + ": sale does not advance payday or wage close")
		check(float(f["purse"]) >= reserve - 0.00001, label + ": purchase retains existing household reserve")
	books(e, label)
	var purchased := Families.acres(f)
	if mode in ["reserve", "debt"]: check(purchased == 0 and Families.heads(f) == 0, label + ": reserve-only or indebted buyer purchases no new property")
	if mode in ["budget", "denied"]:
		check(purchased <= int(floor((old_purse - reserve) / float(TownEcon.data()["land"]["acre_price"]))), label + ": denied credit cannot buy unpriced acreage")
		near(float(f["debt"]), old_debt, label + ": denied loan adds no debt")
	if mode == "loan": check(purchased > 0 and float(f["debt"]) > old_debt, label + ": available ordinary credit buys feasible physical acres from real treasury coins (acres=%d debt=%.8f opening_debt=%.8f capacity=%.8f need=%.8f purse=%.8f opening_purse=%.8f opening_credit=%.8f opening_treasury=%.8f adults=%d homes=%d)" % [purchased, float(f["debt"]), old_debt, capacity(e, f), physical_need(e, f), float(f["purse"]), old_purse, opening_credit, opening_treasury, Families.adults(f), int(f["homes"])])
	if mode == "free": check(purchased > 0, label + ": genuinely free adult control can buy property")
	if draft != "none" and purchased > 0:
		check(int(f.get("ox", 0)) >= old_ox, label + ": real draft transfer keeps actual mirror coherent")
		modes_seen["draft_purchase"] = true
	if fallow and purchased > 0: modes_seen["fallow_purchase"] = true
	if purchased > 0:
		for i in Plots.count(e["plots"]):
			if int(e["plots"]["own"][i]) == int(f["id"]) and Plots.LAND_USES.has(int(e["plots"]["use"][i])) and int(e["plots"]["ac"][i]) < Plots.ACRES: modes_seen["partial_purchase"] = true

func masks(original: Dictionary) -> void:
	var e: Dictionary = original.duplicate(true)
	var P: Dictionary = e["plots"]
	var local_seen := {}
	for i in Plots.count(P):
		var use := int(P["use"][i])
		if not use in [Plots.YARD, Plots.MINE] or local_seen.has(use): continue
		var b: Dictionary = e["biz"][int(P["sub"][i])]
		if b.get("closed", false) or int(b.get("kw", 0)) != 1 or int(b["workers"]) != 0: continue
		var owner := int(b["owner"])
		if owner < 0 or not e["fams"][owner].get("keeps", []).has(int(b["id"])): continue
		mask_seen[use] = true
		local_seen[use] = true
		var before := JSON.stringify(e)
		var mask := Plots.worked_mask(e, P)
		check(int(mask[i]) == 1, "keeper-only generated business plot is worked")
		check(JSON.stringify(e) == before, "worked mask is read-only for physical books, cash and registries")
		b["kw"] = 0
		before = JSON.stringify(e)
		check(int(Plots.worked_mask(e, P)[i]) == 0, "business without hired hands or actual working keeper is unworked")
		check(JSON.stringify(e) == before, "absent keeper mask is pure")
		b["kw"] = 1
		b["closed"] = true
		before = JSON.stringify(e)
		check(int(Plots.worked_mask(e, P)[i]) == 0, "closed business cannot appear worked through stale keeper flag")
		check(JSON.stringify(e) == before, "closed business mask is pure")

func animal_sales(town: Dictionary, original: Dictionary, kind: String, age: String) -> void:
	var setup := configure(town, original, "free", "none", false)
	if setup.is_empty(): return
	var e: Dictionary = setup[0]
	var f: Dictionary = setup[1]
	var estate: Dictionary = e["fams"][0]
	var storage: Dictionary = {}
	for other in e["fams"]:
		if other != f and other != estate and not other.get("gone", false): storage = other; break
	if storage.is_empty(): return
	# Offer only one observed species/age, moving all other estate property to
	# another existing owner. No animal is born or assigned a fabricated age.
	for good in estate["land"].keys(): Families.move_land(e, estate, storage, String(good), int(estate["land"][good]))
	for animal in estate["herd"].keys(): Families.move_herd(e, estate, storage, String(animal), int(estate["herd"][animal]))
	var source: Dictionary = {}
	for h in Herds.herds(e).values():
		if String(h["ow"]) == "f" and int(h["oi"]) != int(f["id"]) and String(h["k"]) == kind and int(h[age]) > 0:
			source = h
			break
	if source.is_empty(): return
	var target := Herds.herd_for(e, 0, kind, float(e["day"]))
	var amount := mini(int(source[age]), int(ceil(capacity(e, f) * float(Herds.kind(kind)["per_hand"]) * (2.0 if age == "y" else 1.0))) + 1)
	check(Herds._transfer(e, source, target, age, amount, "sold", "bought", "actual age sale fixture", "actual age sale fixture", float(e["day"])) == amount, "actual observed animals populate the estate offer")
	var before_property := property(e)
	var before_people := people(e)
	var before_lots := lots(e)
	var before_creditors := creditors(e)
	var gold := TownEcon.town_gold(e)
	var last := float(f["last"])
	var wage_day := int(e["wage_day"])
	var before_age := {}
	for a in ["y", "g", "o"]:
		var n := 0
		for h in Herds.of_family(e, int(f["id"])):
			if String(h["k"]) == kind: n += int(h[a])
		before_age[a] = n
	var label := "%s native %s %s" % [e["culture"], kind, age]
	for repeat in 3:
		TownEcon._sell_land(e, TownEcon.data(), float(e["day"]))
		check(physical_need(e, f) <= capacity(e, f) + 0.00001, label + ": age-specific care fits real spare work after repeated purchases")
		check(property(e) == before_property, label + ": every physical animal age remains conserved")
		check(people(e) == before_people and lots(e) == before_lots, label + ": people and dated harvest ownership remain unchanged")
		check(creditors(e) == before_creditors, label + ": sale neither pays unrelated creditors nor backdates wages")
		near(TownEcon.town_gold(e), gold, label + ": exact head price moves existing coins only")
		check(float(f["last"]) == last and int(e["wage_day"]) == wage_day, label + ": no extra payroll interval")
	var purchased := 0
	for a in ["y", "g", "o"]:
		var n := 0
		for h in Herds.of_family(e, int(f["id"])):
			if String(h["k"]) == kind: n += int(h[a])
		var gain := n - int(before_age[a])
		if a == age: purchased += gain
		else: check(gain == 0, label + ": sold heads retain their real saved age class")
	check(purchased > 0, label + ": a feasible positive real-animal sale occurs")
	if purchased > 0: modes_seen["animal:" + kind + ":" + age] = true
	books(e, label)

func legacy_zero_ox(town: Dictionary, original: Dictionary, missing: bool) -> void:
	var setup := configure(town, original, "budget", "none", false)
	if setup.is_empty(): return
	var e: Dictionary = setup[0]
	var f: Dictionary = setup[1]
	var estate: Dictionary = e["fams"][0]
	var L: Dictionary = TownEcon.data()["land"]
	var cap := capacity(e, f)
	var owned := int(floor(cap * float(L["acres_no_ox"])))
	var label := "%s legacy ox %s zero-head one-acre transfer" % [e["culture"], "missing" if missing else "-1"]
	check(float(owned) / float(L["acres_per_hand"]) <= cap - 0.5 and float(owned + 1) / float(L["acres_no_ox"]) > cap, label + ": real household supplies a causal draft-fallback boundary")
	var storage: Dictionary = {}
	var ox_owner: Dictionary = {}
	for other in e["fams"]:
		if other == f or other == estate or other.get("gone", false): continue
		if storage.is_empty(): storage = other
		else: ox_owner = other; break
	check(not storage.is_empty() and not ox_owner.is_empty(), label + ": existing owners can hold real fixture property")
	if storage.is_empty() or ox_owner.is_empty(): return
	if int(estate["land"].get("grain", 0)) < owned + 3:
		var physical = load("res://tests/farm_fixture_tools.gd").new()
		check(physical.grain(e, estate, owned + 3), label + ": native property transfers supply actual cereal acres")
	var old_gold := TownEcon.town_gold(e)
	var old_property := property(e)
	# A native grain fixture can bring real oxen with it; move them away before
	# preparing the genuinely undrafted buyer's existing physical holding.
	transfer_animals(e, estate, ox_owner, "oxen", maxi(0, int(estate.get("ox", 0))))
	Families.move_land(e, estate, f, "grain", owned)
	# Make a real one-acre estate parcel through native whole-plot transfers.
	# This avoids an incidental new split's fallow phase hiding the regression.
	Families.move_land(e, storage, estate, "grain", int(storage["land"].get("grain", 0)))
	transfer_animals(e, estate, ox_owner, "oxen", maxi(0, int(estate.get("ox", 0))))
	transfer_animals(e, storage, ox_owner, "oxen", maxi(0, int(storage.get("ox", 0))))
	Families.move_land(e, estate, storage, "grain", 1)
	Families.move_land(e, storage, estate, "grain", 1)
	for kind in estate["herd"].keys(): Families.move_herd(e, estate, storage, String(kind), int(estate["herd"][kind]))
	var got := 0
	for other in e["fams"]:
		if other == estate or other == f: continue
		got = transfer_animals(e, other, estate, "oxen", 1)
		if got == 1: break
	check(got == 1 and int(estate.get("ox", 0)) == 1, label + ": donor has exactly one actual draft animal")
	check(Families.acres(estate) > 2 and int(round(1.0 / float(Families.acres(estate)))) == 0, label + ": native proportional one-acre draft transfer rounds to zero")
	var P: Dictionary = e["plots"]
	for i in Plots.count(P):
		if int(P["own"][i]) in [0, int(f["id"])] and Plots.LAND_USES.has(int(P["use"][i])) and String(P["crops"][int(P["sub"][i])]) == "grain":
			P["rotation_phase"][i] = posmod(-Calendar.year(float(e["day"])), 4)
	P["crop_count"] = -1
	CropRotation.ensure(e, P, float(e["day"]))
	var actual_ox := 0
	for h in Herds.of_family(e, int(f["id"])):
		if String(h["k"]) == "oxen": actual_ox += Herds.head(h)
	check(actual_ox == 0, label + ": legacy buyer owns no actual draft animals")
	if missing: f.erase("ox")
	else: f["ox"] = -1
	near(TownEcon.town_gold(e), old_gold, label + ": native fixture transfers conserve coins")
	check(property(e) == old_property, label + ": native fixture transfers conserve every acre and animal age")
	check(physical_need(e, f) <= cap and cap - physical_need(e, f) >= 0.5, label + ": opening legacy holding fits and passes the unchanged spare-work shortlist")
	var prospective: Dictionary = e.duplicate(true)
	var pa: Dictionary = prospective["fams"][0]
	var pb: Dictionary = prospective["fams"][int(f["id"])]
	var source_acres := Plots.acres_of(prospective, 0)
	var buyer_acres := Plots.acres_of(prospective, int(f["id"]))
	Families.move_land(prospective, pa, pb, "grain", 1)
	check(Plots.acres_of(prospective, 0) == source_acres - 1 and Plots.acres_of(prospective, int(f["id"])) == buyer_acres + 1, label + ": native prospective consumption transfers exactly one physical acre")
	check(int(pb.get("ox", -1)) == 0 and int(pa["ox"]) == 1, label + ": native zero-head transfer makes the legacy buyer explicitly undrafted")
	check(physical_need(prospective, pb) > capacity(prospective, pb), label + ": actual native one-acre holding would exceed real labour")
	check(property(prospective) == old_property, label + ": prospective physical consumption preserves all animals and acres")
	near(TownEcon.town_gold(prospective), old_gold, label + ": prospective native transfer conserves coins")
	books(prospective, label + " prospective")
	var old_people := people(e)
	var old_lots := lots(e)
	var old_creditors := creditors(e)
	var old_jobs: Dictionary = f["jobs"].duplicate(true)
	var old_casual: Dictionary = f.get("cj", {}).duplicate(true)
	var old_purse := float(f["purse"])
	var old_debt := float(f["debt"])
	var old_last := float(f["last"])
	var old_wage_day := int(e["wage_day"])
	for repeat in 3:
		TownEcon._sell_land(e, TownEcon.data(), float(e["day"]))
		check(Families.acres(f) == owned and Plots.acres_of(e, int(f["id"])) == owned, label + ": repeated native sale rejects the infeasible physical acre")
		check(physical_need(e, f) <= capacity(e, f) + 0.00001, label + ": real prospective crop work remains feasible")
		check(property(e) == old_property and people(e) == old_people, label + ": rejected sale preserves physical property and people")
		check(lots(e) == old_lots and creditors(e) == old_creditors, label + ": rejected sale preserves dated food and earned creditors")
		check(f["jobs"] == old_jobs and f.get("cj", {}) == old_casual, label + ": rejected sale retains occupied paid places")
		near(TownEcon.town_gold(e), old_gold, label + ": rejected sale conserves coins")
		near(float(f["purse"]), old_purse, label + ": rejected sale spends no household reserve")
		near(float(f["debt"]), old_debt, label + ": rejected sale creates no unused loan")
		check(float(f["last"]) == old_last and int(e["wage_day"]) == old_wage_day, label + ": rejected sale never backdates payroll")
	books(e, label)
	modes_seen["legacy_missing" if missing else "legacy_negative"] = true

func stale_keeper_sale(town: Dictionary, original: Dictionary) -> void:
	var setup := configure(town, original, "stale_keeper", "none", false)
	if setup.is_empty(): return
	var e: Dictionary = setup[0]
	var f: Dictionary = setup[1]
	var label := "%s claimed inactive keeper estate sale" % e["culture"]
	var keeper: Dictionary = {}
	for bid in f["keeps"]:
		var b: Dictionary = e["biz"][int(bid)]
		# A shop keeper isolates this flag repair from herder-capacity changes.
		if not b.get("closed", false) and int(b["owner"]) == int(f["id"]) and int(b.get("kw", 0)) > 0 and String(b["type"]) != "herder": keeper = b; break
	check(not keeper.is_empty(), label + ": native property-selected family has a real keeper")
	if keeper.is_empty(): return
	var old_property := property(e)
	var old_people := people(e)
	var old_lots := lots(e)
	var old_creditors := creditors(e)
	var gold := TownEcon.town_gold(e)
	var old_jobs: Dictionary = f["jobs"].duplicate(true)
	var old_casual: Dictionary = f.get("cj", {}).duplicate(true)
	var old_keeps: Array = f["keeps"].duplicate()
	var old_purse := float(f["purse"])
	var old_debt := float(f["debt"])
	var old_credit := Loans.credit_left(e, f)
	var old_treasury := float(e["treasury"])
	var old_last := float(f["last"])
	var old_wage_day := int(e["wage_day"])
	keeper["kw"] = 0
	for repeat in 3:
		TownEcon._sell_land(e, TownEcon.data(), float(e["day"]))
		check(Families.acres(f) == 0 and Families.heads(f) == 0 and property(e) == old_property, label + ": stale keeper defers every physical purchase")
		check(int(keeper["kw"]) == 0 and f["keeps"] == old_keeps, label + ": sale leaves ordinary keeper repair to native reassignment")
		check(f["jobs"] == old_jobs and f.get("cj", {}) == old_casual, label + ": deferred sale retains all occupied paid places")
		near(float(f["purse"]), old_purse, label + ": deferral spends no household coins")
		near(float(f["debt"]), old_debt, label + ": deferral creates no debt")
		near(Loans.credit_left(e, f), old_credit, label + ": deferred purchase retains existing credit")
		near(float(e["treasury"]), old_treasury, label + ": deferral moves no treasury coins")
		near(TownEcon.town_gold(e), gold, label + ": deferral conserves town coins")
		check(people(e) == old_people and lots(e) == old_lots and creditors(e) == old_creditors, label + ": deferral preserves people, dated food and earned creditors")
		check(float(f["last"]) == old_last and int(e["wage_day"]) == old_wage_day, label + ": deferral does not backdate wages")
	Families.reassign(e, f)
	check(int(keeper["kw"]) == 1 and keepers(e, f) > 0, label + ": existing native reassignment repairs the claimed keeper")
	check(physical_need(e, f) <= capacity(e, f), label + ": repaired opening holding fits actual keeper-adjusted capacity")
	for repeat in 3:
		TownEcon._sell_land(e, TownEcon.data(), float(e["day"]))
		check(physical_need(e, f) <= capacity(e, f) + 0.00001, label + ": later repeated purchase fits real capacity with the repaired keeper")
		check(int(keeper["kw"]) == 1 and f["jobs"] == old_jobs and f.get("cj", {}) == old_casual, label + ": later purchase preserves the working keeper and occupied paid places")
		check(property(e) == old_property and people(e) == old_people, label + ": later sale conserves physical acres, animal ages and people")
		check(lots(e) == old_lots and creditors(e) == old_creditors, label + ": later purchase preserves dated food ownership and earned creditors")
		near(TownEcon.town_gold(e), gold, label + ": later native sale moves only existing coins")
		check(float(f["purse"]) >= 40.0 * TownEcon.COIN - 0.00001, label + ": later purchase retains the household reserve")
		check(float(f["last"]) == old_last and int(e["wage_day"]) == old_wage_day, label + ": later sale does not change payroll timing")
	check(Families.acres(f) > 0, label + ": repaired property-selected keeper family can make a feasible positive purchase")
	books(e, label)
	modes_seen["stale_keeper"] = true

func run(_tree: SceneTree) -> int:
	Game.new_game(901)
	var seen := {}
	for town in Game.world["towns"].values():
		var original: Dictionary = town["econ"].duplicate(true)
		masks(original)
		var culture := String(original["culture"])
		if seen.has(culture): continue
		seen[culture] = true
		for mode in ["service", "keeper", "occupied", "free", "reserve", "debt", "budget", "loan", "denied"]:
			sales(town, original, mode)
		for draft in ["partial", "full"]: sales(town, original, "free", draft)
		sales(town, original, "free", "none", true)
		for missing in [true, false]: legacy_zero_ox(town, original, missing)
		stale_keeper_sale(town, original)
		for kind in Herds.GRAZE:
			for age in ["y", "g", "o"]: animal_sales(town, original, String(kind), age)
		town["econ"] = original
	check(seen.size() == TownEcon.data()["cultures"].size(), "estate sale controls cover all generated cultures")
	for mode in ["service", "keeper", "occupied", "free", "reserve", "debt", "budget", "loan", "denied", "draft_purchase", "fallow_purchase", "partial_purchase", "legacy_missing", "legacy_negative", "stale_keeper"]:
		check(modes_seen.has(mode), "property-selected native suite reaches " + mode)
	check(mask_seen.has(Plots.YARD) and mask_seen.has(Plots.MINE), "actual keeper-only yards and mines both exercised")
	for age in ["y", "g", "o"]:
		var observed := false
		for key in modes_seen:
			if String(key).begins_with("animal:") and String(key).ends_with(":" + age): observed = true
		check(observed, "native herd purchases exercise actual " + age + " age class")
	print("LAND CAPACITY v046 checks=", checks, " failures=", fails)
	return fails
