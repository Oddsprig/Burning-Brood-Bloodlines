class_name DragonGrowth
extends RefCounted
## Bounded record-only growth. The caller owns elapsed-day accounting, feed,
## care, health, calendar age and life stage; this helper never catches up age.
## A finite growth_potential selects that dragon's maturity curve and cap.
## Records without one keep the legacy one-band-per-year rate, unchanged.
const SIZE_IDS := ["small", "medium", "large", "huge", "colossal"]
const MAX_POINTS := 4.0
const YEARS_PER_BAND := 1.0   # a well-fed dragon grows one size band per campaign year
const DAYS_PER_BAND := YEARS_PER_BAND * 4.0 * Calendar.DAYS_PER_SEASON
const MIN_FOOD := 0.8
const MIN_CARE := 0.8
const MIN_HEALTH := 0.5

static func initial_points(row: Dictionary) -> float:
	# Unknown classes fail closed instead of silently becoming a small dragon.
	return float(SIZE_IDS.find(str(row.get("size_class", ""))))

static func _points(row: Dictionary, fallback: float) -> float:
	var stored: Variant = row.get("growth_points", fallback)
	if typeof(stored) not in [TYPE_INT, TYPE_FLOAT]: return fallback
	var value := float(stored)
	return clampf(value, 0.0, MAX_POINTS) if is_finite(value) else fallback

static func current_points(row: Dictionary) -> float:
	var initial := initial_points(row)
	return _points(row, initial if initial >= 0.0 else 0.0)

static func _size(id: String, sizes: Array) -> Dictionary:
	for entry: Dictionary in sizes:
		if str(entry.get("id", "")) == id: return entry.get("physical", {})
	return {}

## Base size metrics only: Dragons applies morph/appearance once afterwards.
## Readers never normalize or initialize the supplied record in place.
static func metrics(row: Dictionary) -> Dictionary:
	var initial := initial_points(row)
	if initial < 0.0: return {"valid": false, "reason": "unknown_size"}
	var points := _points(row, initial)
	var lower := floori(points)
	var upper := mini(lower + 1, SIZE_IDS.size() - 1)
	var fraction := points - float(lower)
	var sizes: Array = Dragons.catalog_section("sizes")
	var a := _size(SIZE_IDS[lower], sizes); var b := _size(SIZE_IDS[upper], sizes)
	if a.is_empty() or b.is_empty(): return {"valid": false, "reason": "missing_size_metrics"}
	var out := {"valid": true, "growth_points": points, "size_class": SIZE_IDS[lower], "next_size_class": SIZE_IDS[upper], "fraction": fraction}
	for key: String in ["body_mass_kg", "strength", "linear_scale"]:
		if not a.has(key) or not b.has(key): return {"valid": false, "reason": "missing_size_metrics"}
		# Integral points use the original authored value exactly.
		out[key] = float(a[key]) if fraction == 0.0 else lerpf(float(a[key]), float(b[key]), fraction)
	return out

static func _info(row: Dictionary, before: float, after: float, reason: String, rate: float = 0.0) -> Dictionary:
	return {"valid": before >= 0.0, "changed": after != before, "reason": reason,
		"points_before": before, "growth_points": after, "delta": after - before,
		"rate_per_day": rate, "size_class": str(row.get("size_class", "")), "stage": str(row.get("stage", ""))}

## Constant work for any explicit duration; never loops days or mutates identity,
## gem/material, body/Unit, age, health, food, coin, ownership or stage fields.
static func advance(row: Dictionary, days: float, food_ratio: float, care_ratio: float, health: float) -> Dictionary:
	var initial := initial_points(row)
	var before := _points(row, initial) if initial >= 0.0 else initial
	if initial < 0.0: return _info(row, before, before, "unknown_size")
	if not is_finite(days) or days < 0.0 or not is_finite(food_ratio) or not is_finite(care_ratio) or not is_finite(health):
		var invalid := _info(row, before, before, "invalid_inputs"); invalid["valid"] = false
		return invalid
	if not bool(row.get("alive", false)) or str(row.get("stage", "")) not in ["juvenile", "adult"]:
		return _info(row, before, before, "inactive")
	if days == 0.0: return _info(row, before, before, "no_elapsed_days")
	if has_potential(row): return _advance_curve(row, before, days, food_ratio, care_ratio, health)
	if before >= MAX_POINTS: return _info(row, before, before, "at_limit")
	var food := clampf(food_ratio, 0.0, 1.0); var care := clampf(care_ratio, 0.0, 1.0); var condition := clampf(health, 0.0, 1.0)
	if food < MIN_FOOD: return _info(row, before, before, "stalled_food")
	if care < MIN_CARE: return _info(row, before, before, "stalled_care")
	if condition < MIN_HEALTH: return _info(row, before, before, "stalled_health")
	var current := metrics(row)
	if not bool(current.get("valid", false)):
		var invalid := _info(row, before, before, "missing_size_metrics"); invalid["valid"] = false
		return invalid
	var rate := food * care * condition / DAYS_PER_BAND
	# Bound before multiplication: even a very large finite duration cannot overflow.
	var days_to_limit := (MAX_POINTS - before) / rate
	var after := MAX_POINTS if days >= days_to_limit else clampf(before + days * rate, before, MAX_POINTS)
	if after == before: return _info(row, before, before, "no_change", rate)
	row["growth_points"] = after
	row["size_class"] = SIZE_IDS[floori(after)]
	return _info(row, before, after, "grown", rate)

static func rules() -> Dictionary:
	var section: Variant = Dragons.catalog_section("growth")
	if section is Dictionary:
		return section
	return {}

static func has_potential(row: Dictionary) -> bool:
	var stored: Variant = row.get("growth_potential", null)
	if typeof(stored) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return is_finite(float(stored))

static func founder_draw(id: String) -> float:
	var spec := rules()
	var modulus := maxi(1, int(spec.get("founder_colossal_modulus", 20)))
	var seed := int(hash(["v052-growth", id])) & 0x7fffffff
	if seed % modulus == 0:
		return clampf(float(spec.get("colossal_band_min", MAX_POINTS)), 0.0, MAX_POINTS)
	var span := float(seed % 10000) / 9999.0
	return clampf(lerpf(float(spec.get("founder_span_min", 0.85)), float(spec.get("founder_span_max", 3.15)), span), 0.0, MAX_POINTS)

static func _store_potential(row: Dictionary, value: float) -> void:
	var next := clampf(value, 0.0, MAX_POINTS)
	if has_potential(row) and is_equal_approx(float(row["growth_potential"]), next):
		return
	row["growth_potential"] = next

## Creation only. Replaces the uniform size roll. Load and care must not call this.
static func assign_new(row: Dictionary) -> void:
	var draw := founder_draw(str(row.get("id", "")))
	_store_potential(row, draw)
	if str(row.get("stage", "")) == "egg":
		row["growth_points"] = 0.0
		row["size_class"] = SIZE_IDS[0]
		return
	row["growth_points"] = draw
	row["size_class"] = SIZE_IDS[band_index(draw)]

## Pure. The number ensure() would store for a hatched dragon: at least today's points.
static func read_potential(row: Dictionary) -> float:
	var base := founder_draw(str(row.get("id", "")))
	if has_potential(row):
		base = clampf(float(row["growth_potential"]), 0.0, MAX_POINTS)
	return clampf(maxf(base, current_points(row)), 0.0, MAX_POINTS)

## Does not lower points or size. An egg keeps the founder draw and not its unused size roll.
static func ensure(row: Dictionary) -> void:
	if str(row.get("stage", "")) == "egg":
		if not has_potential(row):
			_store_potential(row, founder_draw(str(row.get("id", ""))))
		return
	_store_potential(row, read_potential(row))

static func ensure_all(game) -> void:
	var records: Dictionary = game.world.get("dragons", {}).get("records", {})
	for uid in records.keys():
		var row: Variant = records[uid]
		if row is Dictionary:
			ensure(row)

static func inherit(game, mother: Dictionary, father: Dictionary, key: String) -> float:
	var lo := read_potential(mother)
	var hi := read_potential(father)
	var low := minf(lo, hi)
	var high := maxf(lo, hi)
	var slack := float(rules().get("inherit_slack", 0.2))
	var seed := Dragons._seed(game, key + ":growth_potential")
	var noise := ((float(seed % 10001) / 10000.0) * 2.0 - 1.0) * slack
	return clampf(clampf((lo + hi) * 0.5 + noise, low - slack, high + slack), 0.0, MAX_POINTS)

static func band_index(points: float) -> int:
	if points >= MAX_POINTS:
		return SIZE_IDS.size() - 1
	return clampi(floori(points), 0, SIZE_IDS.size() - 1)

static func maturity_id(points: float, potential: float) -> String:
	var stages: Array = rules().get("stages", [])
	if potential <= 0.0 or stages.is_empty():
		return "mature"
	var frac := points / potential
	var last := "mature"
	var i := 0
	while i < stages.size():
		var stage: Variant = stages[i]
		i += 1
		if not stage is Dictionary:
			continue
		last = str((stage as Dictionary).get("id", last))
		if frac < float((stage as Dictionary).get("until", 1.01)):
			return last
	return last

static func _stage_rate(points: float, potential: float) -> float:
	var wanted := maturity_id(points, potential)
	var stages: Array = rules().get("stages", [])
	var i := 0
	while i < stages.size():
		var stage: Variant = stages[i]
		i += 1
		if stage is Dictionary and str((stage as Dictionary).get("id", "")) == wanted:
			return maxf(0.0, float((stage as Dictionary).get("rate", 1.0)))
	return 1.0

static func _nutrition(food: float) -> Dictionary:
	var spec: Variant = rules().get("nutrition", {})
	var starving := MIN_FOOD
	var well := 0.95
	var under := 0.55
	var full := 1.0
	if spec is Dictionary:
		starving = float((spec as Dictionary).get("starving_below", MIN_FOOD))
		well = float((spec as Dictionary).get("well_fed_min", 0.95))
		under = float((spec as Dictionary).get("underfed_rate", 0.55))
		full = float((spec as Dictionary).get("well_fed_rate", 1.0))
	if food < starving:
		return {"id": "starving", "rate": 0.0}
	if food < well:
		return {"id": "underfed", "rate": under}
	return {"id": "well_fed", "rate": full}

## A point this close to a stage edge is already inside the next stage. Comparing
## points/cap < until repeats the same edge when the product rounds a hair low,
## and the old loop then treated that repeat as "no next mark" and jumped to the cap.
const MARK_EPS := 0.000000001

## The stage that still has room, and the next boundary strictly ahead of points.
static func _span(points: float, cap: float) -> Dictionary:
	var stages: Array = rules().get("stages", [])
	var rate := 1.0
	var i := 0
	while i < stages.size():
		var stage: Variant = stages[i]
		i += 1
		if not stage is Dictionary:
			continue
		rate = maxf(0.0, float((stage as Dictionary).get("rate", rate)))
		var until := float((stage as Dictionary).get("until", 1.01))
		var edge := minf(cap, until * cap)
		if edge > points + MARK_EPS:
			return {"rate": rate, "mark": edge}
	return {"rate": rate, "mark": cap}

static func _next_mark(points: float, cap: float) -> float:
	return float(_span(points, cap)["mark"])

static func size_name(class_id: String) -> String:
	var sizes: Variant = Dragons.catalog_section("sizes")
	if sizes is Array:
		for entry in sizes:
			if entry is Dictionary and str((entry as Dictionary).get("id", "")) == class_id:
				return str((entry as Dictionary).get("name", class_id.capitalize()))
	return class_id.capitalize()

static func feed_ratios(row: Dictionary, quote: Dictionary) -> Dictionary:
	var food := 1.0
	var care := 1.0
	var health := 1.0
	var care_row: Variant = row.get("care", {})
	var last: Dictionary = {}
	if care_row is Dictionary:
		var stored_last: Variant = (care_row as Dictionary).get("last", {})
		if stored_last is Dictionary:
			last = stored_last
	if quote.has("food_need_units"):
		var need := float(quote.get("food_need_units", 0.0))
		food = 1.0 if need <= 0.0 else clampf(float(quote.get("food_possible_units", 0.0)) / need, 0.0, 1.0)
		var upkeep_need := float(quote.get("upkeep_need_units", 0.0))
		care = 1.0 if upkeep_need <= 0.0 else clampf(float(quote.get("upkeep_possible_units", 0.0)) / upkeep_need, 0.0, 1.0)
	else:
		if last.has("food_ratio"):
			food = clampf(float(last["food_ratio"]), 0.0, 1.0)
		if last.has("care_ratio"):
			care = clampf(float(last["care_ratio"]), 0.0, 1.0)
	if quote.has("health"):
		health = clampf(float(quote.get("health", 1.0)), 0.0, 1.0)
	elif care_row is Dictionary and (care_row as Dictionary).has("health"):
		health = clampf(float((care_row as Dictionary)["health"]), 0.0, 1.0)
	return {"food": food, "care": care, "health": health}

static func stall_sentence(reason: String) -> String:
	match reason:
		"at_limit":
			return "it has reached its growth potential."
		"stalled_food":
			return "it is starving."
		"stalled_care":
			return "shelter is short."
		"stalled_health":
			return "it is too weak."
		_:
			return ""

## Screen copy for one dragon. Eggs stay blank. Never names the stored potential.
static func summary(row: Dictionary, quote: Dictionary) -> String:
	if str(row.get("stage", "")) == "egg":
		return ""
	var points := current_points(row)
	var pot := read_potential(row)
	var class_id := str(row.get("size_class", ""))
	if SIZE_IDS.find(class_id) < 0:
		class_id = SIZE_IDS[band_index(points)]
	var slack := float(rules().get("display_slack", 0.5))
	var likely := "%s to %s" % [size_name(SIZE_IDS[band_index(pot - slack)]), size_name(SIZE_IDS[band_index(pot + slack)])]
	var ratios := feed_ratios(row, quote)
	var reason := ""
	if points >= pot - 0.000001:
		reason = "at_limit"
	elif float(_nutrition(float(ratios["food"]))["rate"]) <= 0.0:
		reason = "stalled_food"
	elif float(ratios["care"]) < MIN_CARE:
		reason = "stalled_care"
	elif float(ratios["health"]) < MIN_HEALTH:
		reason = "stalled_health"
	var text := "Size: %s\nMaturity: %s\nLikely adult size: %s" % [size_name(class_id), maturity_id(points, pot).capitalize(), likely]
	if reason != "":
		text += "\nGrowth is stalled: " + stall_sentence(reason)
	return text

static func _advance_curve(row: Dictionary, before: float, days: float, food_ratio: float, care_ratio: float, health: float) -> Dictionary:
	var cap := clampf(float(row["growth_potential"]), 0.0, MAX_POINTS)
	if before >= cap:
		return _info(row, before, before, "at_limit")
	var food := clampf(food_ratio, 0.0, 1.0)
	var care := clampf(care_ratio, 0.0, 1.0)
	var condition := clampf(health, 0.0, 1.0)
	var nutrition := _nutrition(food)
	if float(nutrition["rate"]) <= 0.0:
		return _info(row, before, before, "stalled_food")
	if care < MIN_CARE:
		return _info(row, before, before, "stalled_care")
	if condition < MIN_HEALTH:
		return _info(row, before, before, "stalled_health")
	var current := metrics(row)
	if not bool(current.get("valid", false)):
		var invalid := _info(row, before, before, "missing_size_metrics")
		invalid["valid"] = false
		return invalid
	var pace := care * condition * float(nutrition["rate"])
	var rate := pace * _stage_rate(before, cap) / DAYS_PER_BAND
	var after := before
	var left := days
	var guard := 0
	# One pass per stage. Each pass spends only the days still left, and stops
	# on the next boundary. It never snaps to the cap when a boundary repeats.
	while left > MARK_EPS and after + MARK_EPS < cap and guard < 8:
		guard += 1
		var span := _span(after, cap)
		var seg_rate := pace * float(span["rate"]) / DAYS_PER_BAND
		if seg_rate <= 0.0:
			break
		var mark := minf(float(span["mark"]), cap)
		var day_step := left * seg_rate
		if mark <= after + MARK_EPS:
			after += minf(day_step, maxf(0.0, cap - after))
			left = 0.0
			break
		var room := mark - after
		if day_step + MARK_EPS >= room:
			after = mark
			left -= room / seg_rate
			if left < 0.0:
				left = 0.0
			if after >= cap:
				after = cap
				break
		else:
			after += day_step
			left = 0.0
	if after > cap:
		after = cap
	if after < before:
		after = before
	if after == before:
		return _info(row, before, before, "no_change", rate)
	row["growth_points"] = after
	row["size_class"] = SIZE_IDS[band_index(after)]
	var info := _info(row, before, after, "grown", rate)
	info["maturity"] = maturity_id(after, cap)
	info["nutrition"] = str(nutrition["id"])
	return info
