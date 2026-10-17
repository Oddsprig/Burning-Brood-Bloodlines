class_name DragonGrowth
extends RefCounted
## Bounded record-only growth. The caller owns elapsed-day accounting, feed,
## care, health, calendar age and stage/maturity; this helper never catches up age.
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
