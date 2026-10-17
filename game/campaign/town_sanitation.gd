class_name TownSanitation
extends RefCounted
## Town aggregates only. Every week's incoming and outgoing mass is shown in the books.
static func D() -> Dictionary:
	return TownEcon.data()["sanitation"]

static func book(e: Dictionary) -> Dictionary:
	if not e.has("sanitation"):
		var capacity := int(floor(float(reachable_meals(e)) * float(Herds.A()["kg_per_meal"]) / (float(D()["rat_grain_kg_day"]) * 7)))
		e["sanitation"] = {"rats": mini(capacity, int(float(e["pop"]) * float(D()["rats_initial_per_person"]))), "food_capacity": capacity, "filth_kg": 0.0, "urine_litres": 0.0, "rotting_kg": 0.0, "trade_kg": 0.0, "paid_days": {}, "rat_carry": 0.0}
	return e["sanitation"]

static func reachable_meals(e: Dictionary) -> int:
	var n := int(e.get("granary", 0))
	for holder in ["stock", "barn", "hh"]: n += int(e.get(holder, {}).get("grain", 0))
	return n

static func paid_days(e: Dictionary, job: String) -> float:
	return float(book(e)["paid_days"].get(job, 0))

static func add_waste(e: Dictionary, kg: float, kind: String) -> void:
	var s := book(e)
	var key := "rotting_kg" if kind == "rotting" else "trade_kg"
	s[key] = float(s[key]) + maxf(0, kg)

static func customer_funds(e: Dictionary) -> float:
	var funds := 0.0
	for f in e["fams"]:
		if not f.get("gone", false) and not f.get("estate", false): funds += maxf(0, float(f["purse"]) - float(Families.daily_rates(e, f)["food"]) * float(e["price"].get("grain", 1)) * 7)
	for b in e["biz"]:
		if not b.get("closed", false): funds += maxf(0, float(b["till"]) - float(b["owed"]))
	return funds

static func collect(e: Dictionary, due: float) -> float:
	var left := due
	# All occupied homes and open shops share the service charge in proportion to people or working hands.
	var payers := []
	var weight := 0.0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		var w := float(Families.people(f)); weight += w
		payers.append([f, "purse", w, maxf(0, float(f["purse"]) - float(Families.daily_rates(e, f)["food"]) * float(e["price"].get("grain", 1)) * 7)])
	for b in e["biz"]:
		if b.get("closed", false): continue
		var w := float(int(b["workers"]) + int(b.get("kw", 0))); weight += w
		payers.append([b, "till", w, maxf(0, float(b["till"]) - float(b["owed"]))])
	for p in payers:
		var charge := minf(float(p[3]), due * float(p[2]) / maxf(1, weight))
		p[0][p[1]] = float(p[0][p[1]]) - charge; left -= charge
	return due - left

static func caps(e: Dictionary, out: Dictionary) -> void:
	var s := book(e)
	var daily := float(e["pop"]) * (float(D()["waste_kg_day"]) + float(D()["refuse_kg_day"]))
	var backlog := maxf(0, float(s["filth_kg"]) - daily * 7)
	out["street_sweeper"] = int(ceil((daily * 7 + backlog) / float(D()["sweep_kg_day"]) / 7))
	out["night_soil_man"] = int(ceil((float(e["pop"]) * float(D()["urine_l_day"]) * 7 + float(s["urine_litres"])) / float(D()["night_soil_l_day"]) / 7))
	out["rat_catcher"] = int(ceil(float(s["rats"]) / float(D()["rats_caught_day"]) / 7))
	s["cleaners_required"] = out["street_sweeper"]

static func weekly(e: Dictionary, day: float) -> void:
	var s := book(e)
	# Preserve the service actually consumed by this completed period separately
	# from wages settled after this close. The queued town turn supplies its day.
	s["completed_paid_days"] = (s["paid_days"] as Dictionary).duplicate()
	s["closed_day"] = day
	var pop := maxf(0, float(e["pop"]) - float(e.get("away_n", 0)))
	var start := float(s["filth_kg"])
	var people := pop * (float(D()["waste_kg_day"]) + float(D()["refuse_kg_day"])) * 7
	var animals := 0.0
	# Household poultry stay in town; grazing animals' dung is already accounted for by Herds._manure.
	for h in Herds.herds(e).values():
		if String(h["k"]) == "hens": animals += Herds.ge(h) * float(Herds.A()["kinds"]["hens"]["manure"]) * 1000 * 7 / EconGen.YEAR_DAYS
	var incoming := maxf(0, people + animals + float(s["rotting_kg"]) + float(s["trade_kg"]) - float(s.get("scraps_reused_kg", 0)))
	var filth := start + incoming
	var urine_in := pop * float(D()["urine_l_day"]) * 7
	var urine := float(s["urine_litres"]) + urine_in
	var swept := minf(filth, paid_days(e, "street_sweeper") * float(D()["sweep_kg_day"]))
	filth -= swept
	var night := minf(urine, paid_days(e, "night_soil_man") * float(D()["night_soil_l_day"]))
	urine -= night
	# The existing field-manure book receives only the recovered solids; never create a second fertiliser good.
	var recovered := 0.0
	var offered := swept
	var acres_total := maxf(1, float(e.get("land", {}).get("grain", 0)))
	var tonnes_acre := float(Herds.A()["manure_acre"])
	var price_kg := float(TownEcon.data()["land"]["yield"]["grain"]) * float(Herds.A()["manure_yield"]) * float(e["price"].get("grain", 1)) / maxf(1, tonnes_acre * 1000)
	# Field holders buy collected dung out of their purses; its price is the additional crop value per kg.
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		var acreage := float(f["land"].get("grain", 0))
		var amount := minf(swept * acreage / acres_total, acreage * tonnes_acre * 1000 * 7 / EconGen.YEAR_DAYS)
		amount = minf(amount, maxf(0, float(f["purse"])) / maxf(0.001, price_kg))
		var cost := amount * price_kg
		f["purse"] = float(f["purse"]) - cost; e["treasury"] = float(e["treasury"]) + cost
		recovered += amount; offered -= amount
	if e.has("hd"): e["hd"]["human_manure_week"] = recovered
	var river := 0.0
	if e.get("terrain", {}).get("water", false):
		river = urine; urine = 0 # liquid drains to the actual watercourse; it remains a foul-water exposure
	var season := Calendar.season_index(day)
	var decay := minf(filth, pop * float(D()["decay_kg_person_day"][season]) * 7)
	filth -= decay
	s["filth_kg"] = filth; s["urine_litres"] = urine
	s["incoming_kg"] = incoming; s["people_kg"] = people; s["animal_kg"] = animals
	s["swept_kg"] = swept; s["farm_manure_kg"] = recovered; s["decayed_kg"] = decay
	s["urine_in_l"] = urine_in; s["night_soil_l"] = night; s["river_l"] = river
	s["change_kg"] = filth - start
	s["cleaners"] = int(ceil(paid_days(e, "street_sweeper") / 7))
	var kg := float(Herds.A()["kg_per_meal"])
	var food := float(reachable_meals(e)) * kg
	var capacity := int(floor(food / (float(D()["rat_grain_kg_day"]) * 7)))
	var rats := int(s["rats"])
	var caught := mini(rats, int(floor(paid_days(e, "rat_catcher") * float(D()["rats_caught_day"]))))
	rats -= caught
	# Breeding pairs require both reachable food and actual nesting refuse. Winter permits fewer litters.
	var nests := int(floor(filth / float(D()["nest_kg_pair"])))
	var pairs := mini(rats / 2, nests)
	var births := int(floor(float(pairs) * float(D()["litters_week"][season]) * float(D()["litter_size"])))
	var before_starve := rats + births
	rats = mini(before_starve, capacity)
	var grain_kg := rats * float(D()["rat_grain_kg_day"]) * 7 + float(s["rat_carry"])
	var meals := mini(reachable_meals(e), int(floor(grain_kg / kg)))
	s["rat_carry"] = grain_kg - meals * kg
	var left := meals
	for holder in ["barn", "stock", "granary", "hh"]:
		var have := int(e.get("granary", 0)) if holder == "granary" else int(e[holder].get("grain", 0))
		var n := mini(left, have)
		if holder == "granary": e["granary"] = have - n
		elif holder == "barn": HarvestClaims.lose(e, "grain", n)
		else: e[holder]["grain"] = have - n
		if holder == "hh" and n > 0:
			for f in e["fams"]:
				if f.get("gone", false) or f.get("estate", false): continue
				var rate := float(Families.daily_rates(e, f)["food"])
				f["store"]["food"] = maxf(0, float(f["store"]["food"]) - float(n) / maxf(1, pop) / maxf(0.01, rate) * Families.people(f))
		left -= n
	TownEcon.led(e, "spoil", "grain", meals - left)
	s["rats"] = rats; s["food_capacity"] = capacity; s["caught"] = caught; s["births"] = births
	s["starved"] = before_starve - rats; s["grain_eaten_kg"] = (meals - left) * kg
	s["hygiene"] = (filth + urine + river) / maxf(1, pop)
	s["rats_per_person"] = float(rats) / maxf(1, pop)
	s["rotting_kg"] = 0.0; s["trade_kg"] = 0.0; s["scraps_reused_kg"] = 0.0; s["paid_days"] = {}
	Sickness.book(e)["tf"] = {} # risk changes feed the existing weekly disease sampler

static func exposure(e: Dictionary, r: Dictionary) -> float:
	var s := book(e)
	return float(r.get("hyg_k", 0)) * float(s.get("hygiene", 0)) + float(r.get("rat_k", 0)) * float(s.get("rats_per_person", 0))
