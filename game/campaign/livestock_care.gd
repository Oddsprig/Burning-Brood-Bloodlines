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


# Horse cohorts extend Herds' counts and ledgers. Dates use the native 120-day year.
# A pasture's peak carrying capacity is a hard head limit, including foals.
static func horse_capacity(e: Dictionary, h: Dictionary, P: Dictionary) -> int:
	if P.is_empty(): return 0
	var grass := 0.0
	for part: Array in Herds._graze_parts(e, P, h, Herds.peak_season(e)):
		grass += float(part[1])
	return maxi(0, floori(grass / float(Herds.kind("horses")["feed"])))

## One opening cohort for the native aggregate young; new births have exact dates.
static func ensure_foals(h: Dictionary, incoming: int = 0) -> void:
	if h.has("foals"): return
	h["foals"] = []
	var young := maxi(0, int(h["y"]) - incoming)
	if young > 0:
		h["foals"].append([float(h["d0"]) - float(Herds.year_days()) * 1.5, young])

## Removal/transfer takes the oldest first. No change to the authoritative head count.
static func take_foals(h: Dictionary, count: int) -> Array:
	ensure_foals(h)
	var moved: Array = []
	var cohorts: Array = h["foals"]
	cohorts.sort_custom(func(a: Array, b: Array): return float(a[0]) < float(b[0]))
	for row: Array in cohorts:
		var take := mini(count, int(row[1]))
		if take <= 0: continue
		moved.append([float(row[0]), take])
		row[1] = int(row[1]) - take
		count -= take
	h["foals"] = cohorts.filter(func(row: Array): return int(row[1]) > 0)
	return moved

static func trim_foals(h: Dictionary) -> void:
	if not h.has("foals"): return
	var recorded := 0
	for row: Array in h["foals"]: recorded += int(row[1])
	if recorded > int(h["y"]): take_foals(h, recorded - int(h["y"]))

static func horse_life(e: Dictionary, h: Dictionary, P: Dictionary, day: float, rng: RandomNumberGenerator) -> void:
	if String(h["ow"]) == "d": return # Walking sale stock uses the native drover's feed.
	if float(h.get("horse_life_day", -1.0)) >= day: return
	h["horse_life_day"] = day
	ensure_foals(h)
	var K := Herds.kind("horses")
	var cap := horse_capacity(e, h, P)
	var excess := maxi(0, Herds.head(h) - cap)
	for age: String in ["y", "o", "g"]:
		var lost := mini(excess, int(h[age]))
		Herds.change(e, h, age, -lost, "died", "pasture capacity", day)
		excess -= lost
	# Native maturation moves the same heads, without booking a birth or a sale.
	var remaining: Array = []
	for row: Array in h["foals"]:
		if day >= float(row[0]) + float(K["grow"]) * Herds.year_days():
			var grown := mini(int(row[1]), int(h["y"]))
			h["y"] = int(h["y"]) - grown
			h["g"] = int(h["g"]) + grown
			if grown > 0: Herds.H(e)["ver"] = int(Herds.H(e).get("ver", 0)) + 1
		else: remaining.append(row)
	h["foals"] = remaining
	# Pregnancies reserve room but are not counted as live horses until delivery.
	var pregnancies: Array = []
	for row: Array in h.get("horse_due", []):
		var mothers := mini(int(row[1]), floori(float(h["g"]) * float(K["fem"])))
		if day < float(row[0]):
			if mothers > 0: pregnancies.append([float(row[0]), mothers])
			continue
		var born := mini(mothers, maxi(0, cap - Herds.head(h)))
		if born > 0:
			Herds.change(e, h, "y", born, "born", "after gestation", day)
			h["foals"].append([day, born])
	h["horse_due"] = pregnancies
	var season := Calendar.season_index(day)
	var stamp := Calendar.year(day)
	if season != 0 or int(h.get("horse_bred_year", -1)) == stamp: return
	h["horse_bred_year"] = stamp
	if int(h["hun"]) > 0: return
	var pending := 0
	for row: Array in pregnancies: pending += int(row[1])
	var room := maxi(0, cap - Herds.head(h) - pending)
	var females := maxf(0.0, float(h["g"]) * float(K["fem"]) - pending)
	var males := float(Herds.H(e).get("_male", {}).get("horses", 0.0))
	var conceived := mini(room, Herds._whole(females * float(K["bear"]) * males * (1.0 - Herds.sick(h)), rng))
	if conceived > 0:
		h["horse_due"].append([day + ceili(float(K["gestation"]) * Herds.year_days()), conceived])

## Mounted horse snapshots accompany existing counted grown heads, including sales.
static func take_mount_bodies(h: Dictionary, n: int) -> Array:
	var out: Array = []
	var bodies: Array = h.get("mount_bodies", [])
	for _i in mini(n, bodies.size()): out.append(bodies.pop_back())
	return out

static func trim_mount_bodies(h: Dictionary) -> void:
	if h.has("mount_bodies"):
		while h["mount_bodies"].size() > int(h["g"]): h["mount_bodies"].pop_back()
