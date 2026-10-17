class_name LivestockCare
extends RefCounted

static func init_hives(e: Dictionary, rng: RandomNumberGenerator) -> void:
	if String(e.get("culture", "")) != "moon_elf": return
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		if rng.randf() < 0.6:
			f["hives"] = {"count": rng.randi_range(1, 3), "honey_kg": 0.0, "wax_kg": 0.0, "carry_honey": 0.0, "carry_wax": 0.0}

static func feed_hens(e: Dictionary, day: float) -> void:
	for h in Herds.herds(e).values():
		if String(h["k"]) != "hens" or String(h["ow"]) != "f": continue
		var f: Dictionary = e["fams"][int(h["oi"])]
		var need := Herds.ge(h) * 0.12 * 7 # kg of grain/scraps per adult bird-day
		var scraps := minf(need, float(f.get("scraps_kg", 0)))
		f["scraps_kg"] = maxf(0, float(f.get("scraps_kg", 0)) - scraps)
		if e.has("sanitation"): e["sanitation"]["scraps_reused_kg"] = float(e["sanitation"].get("scraps_reused_kg", 0)) + scraps
		var rate := float(Families.daily_rates(e, f)["food"])
		var meal_kg := float(Herds.A()["kg_per_meal"])
		var requested := (need - scraps) / meal_kg
		var available := minf(float(e["hh"].get("grain", 0)), maxf(0, float(f["store"]["food"])) * rate)
		var meals := minf(requested, available)
		var carry := meals + float(h.get("grain_carry", 0))
		var taken := mini(int(floor(carry)), int(e["hh"].get("grain", 0)))
		h["grain_carry"] = carry - taken
		e["hh"]["grain"] = int(e["hh"].get("grain", 0)) - taken
		TownEcon.led(e, "used", "grain", taken)
		f["store"]["food"] = maxf(0, float(f["store"]["food"]) - meals / maxf(0.01, rate))
		var supplied := scraps + meals * meal_kg
		h["fed"] = minf(1, supplied / maxf(0.01, need))
		h["hun"] = maxi(0, int(h["hun"]) - 7) if supplied >= need else int(h["hun"]) + int(ceil(7 * (1 - float(h["fed"]))))
		if int(h["hun"]) > int(Herds.A()["starve_after"]):
			var supported := int(floor(supplied / (0.12 * 7)))
			var deaths := maxi(0, Herds.head(h) - supported)
			for age in Herds.AGES:
				var died := mini(deaths, int(h[age]))
				Herds.change(e, h, age, -died, "died", "starvation", day)
				deaths -= died

static func hive_week(e: Dictionary, day: float) -> void:
	var season := Calendar.season_index(day)
	var flowers := float(e.get("land", {}).get("fruit", 0)) + float(e.get("crop_mix", {}).get("beans", 0)) + float(e.get("crop_mix", {}).get("peas", 0))
	var count := 0
	for f in e["fams"]: count += int(f.get("hives", {}).get("count", 0))
	if count == 0 or season == 3: return
	# Each acre can supply one hive's weekly forage. Actual flowering land bounds production.
	var active := minf(float(count), flowers)
	for f in e["fams"]:
		var h: Dictionary = f.get("hives", {})
		if h.is_empty() or f.get("gone", false): continue
		var forage := float(h["count"]) / count * active
		var honey := forage * 0.04 * 7
		var wax := forage * 0.004 * 7
		h["honey_kg"] += honey; h["wax_kg"] += wax
		var honey_meals := honey * float(Herds.A()["honey_meals"]) + float(h["carry_honey"])
		var wax_units := wax + float(h["carry_wax"])
		var out := {"grain": int(floor(honey_meals)), "wax": int(floor(wax_units))}
		h["carry_honey"] = honey_meals - int(out["grain"])
		h["carry_wax"] = wax_units - int(out["wax"])
		# Use the same owner-payment and goods ledger as herd products; hives themselves are never herd animals.
		var owner := {"ow": "f", "oi": f["id"], "k": "hens"}
		Herds._sell(e, owner, out, float(TownEcon.data()["market"]["broker_share"]))
