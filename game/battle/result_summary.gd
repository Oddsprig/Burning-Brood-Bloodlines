class_name BattleResultSummary
extends RefCounted
## Pure read of actual participant records. Detail rows borrow Units only while
## the result screen owns them; health categories partition, retreat overlaps.

static func build(result: Dictionary) -> Dictionary:
	var states: Dictionary = _states(result)
	var claimed: Dictionary = {}
	var sides: Array = []
	var names: Array = _array(result.get("side_names", []))
	# Actual side rosters outrank an off-side alias in a supplemental fallen/fled list.
	for side in 2:
		for value in _array(result.get("player_units" if side == 0 else "enemy_units", [])):
			if value is Unit and not claimed.has(value.get_instance_id()): claimed[value.get_instance_id()] = side
	for side in 2:
		var prefix: String = "player" if side == 0 else "enemy"
		var name: String = str(names[side]) if side < names.size() else ""
		if name.is_empty(): name = "Our side" if side == 0 else "Opposing side"
		var units: Array = []
		var seen: Dictionary = {}
		for key in [prefix + "_units", prefix + "_fallen", prefix + "_fled"]:
			for value in _array(result.get(key, [])):
				if not value is Unit: continue
				var id: int = value.get_instance_id()
				if not claimed.has(id): claimed[id] = side
				if int(claimed[id]) != side or seen.has(id): continue
				seen[id] = true
				units.append(value)
		var retreats: Dictionary = {}
		var fled_key: String = prefix + "_fled"
		var fled_values: Array = _array(result.get(fled_key, []))
		# Native enemy_fallen historically contains dead and fled. Explicit fled
		# metadata takes precedence, including an explicitly empty native list.
		if side == 1 and not result.has(fled_key): fled_values = _array(result.get("enemy_fallen", []))
		for value in fled_values:
			if value is Unit: retreats[value.get_instance_id()] = true
		var row: Dictionary = {"name": name, "total": units.size(), "slain": 0,
			"seriously_wounded": 0, "wounded": 0, "other_wounded": 0, "unhurt": 0,
			"fled": 0, "wounded_fled": 0, "officers_slain": 0,
			"rows": {"fallen": [], "wounded": []}}
		for u: Unit in units:
			var state: String = str(states.get(u.get_instance_id(), ""))
			var dead: bool = u.dead or state == "dead"
			var fled: bool = not dead and (retreats.has(u.get_instance_id()) or state == "fled")
			var report: Dictionary = _health(u, state, dead)
			var serious: bool = not dead and _serious(u, report, state)
			var hurt: bool = not dead and (serious or _hurt(u, report))
			var category: String = "slain" if dead else "seriously_wounded" if serious else "wounded" if hurt else "unhurt"
			row[category] += 1
			if fled: row["fled"] += 1
			if fled and hurt: row["wounded_fled"] += 1
			if dead and u.is_officer(): row["officers_slain"] += 1
			if dead or hurt:
				var detail: Dictionary = {"unit": u, "uid": u.uid, "name": u.name, "title": u.title,
					"officer": u.is_officer(), "category": category, "serious": serious, "fled": fled,
					"status": report["status"], "fitness": report.get("fitness", ""),
					"heal_days": float(report.get("heal_days", 0.0)), "recovery": report["recovery"],
					"summary": report.get("summary", []), "health_available": report.get("health_available", false)}
				row["rows"]["fallen" if dead else "wounded"].append(detail)
		row["other_wounded"] = row["wounded"]
		sides.append(row)
	return {"sides": sides}

static func _array(value: Variant) -> Array:
	return value if value is Array else []

static func _states(result: Dictionary) -> Dictionary:
	var units: Array = _array(result.get("fighter_units", []))
	var values: Array = _array(result.get("fighter_states", []))
	var out: Dictionary = {}
	var priority: Dictionary = {"dead": 3, "unconscious": 2, "fled": 1}
	for i in mini(units.size(), values.size()):
		if not units[i] is Unit: continue
		var id: int = units[i].get_instance_id()
		var state: String = str(values[i])
		if not out.has(id) or int(priority.get(state, 0)) > int(priority.get(out[id], 0)): out[id] = state
	return out

static func _report_ready(u: Unit) -> bool:
	if u.body == null or not DB.bodies.has(u.body.plan_id): return false
	for value in u.body.parts.values():
		if not value is Dictionary or not value.get("layers") is Array: return false
		for layer in value["layers"]:
			if not layer is Dictionary or not layer.has("bleed"): return false
	return true

static func _health(u: Unit, state: String, dead: bool) -> Dictionary:
	if dead:
		return {"status": "dead", "recovery": "", "health_available": u.body != null}
	var available: bool = _report_ready(u)
	if available:
		# Clean native participants need no costly anatomical detail report.
		if u.body.parts.is_empty() and u.body.permanent.is_empty() and u.body.blood >= u.body.blood_max * 0.999 \
				and u.body.pain < Healing.PAIN_KO and not u.get_meta("unconscious", false) and state != "unconscious":
			return {"status": "healthy", "fitness": "fit to fight", "recovery": "healed", "health_available": true}
		var report: Dictionary = HealthReport.describe(u)
		report["health_available"] = true
		if state == "unconscious":
			report["status"] = "unconscious"
			report["fitness"] = "cannot fight"
		return report
	# Handcrafted/sparse records are read without normalizing or inventing a body.
	var unconscious: bool = state == "unconscious" or bool(u.get_meta("unconscious", false))
	var days: float = 0.0
	if u.body != null:
		unconscious = unconscious or u.body.pain >= Healing.PAIN_KO or u.body.blood < u.body.blood_max * Healing.BLOOD_COLLAPSE
		for value in u.body.parts.values():
			if not value is Dictionary: continue
			for layer in _array(value.get("layers", [])):
				if layer is Dictionary: days = maxf(days, float(layer.get("heal_days", 0.0)))
	return {"status": "unconscious" if unconscious else "health unavailable",
		"fitness": "cannot fight" if unconscious else "", "heal_days": days,
		"recovery": HealthReport.format_days(days) if days > 0.0 else "not assessed", "health_available": false}

static func _serious(u: Unit, report: Dictionary, state: String) -> bool:
	if state == "unconscious" or report["status"] in ["unconscious", "badly wounded"]: return true
	if report.get("fitness", "") == "cannot fight" or report.get("flags", {}).get("impaired", false): return true
	for part: Dictionary in report.get("parts", []):
		if int(part.get("severity", 0)) >= 2 or part.get("permanent", false): return true
	if not report.get("health_available", false) and u.body != null:
		if not u.body.permanent.is_empty(): return true
		for value in u.body.parts.values():
			if not value is Dictionary: continue
			if value.get("severed", false) or value.get("nerve_m", false) or value.get("nerve_s", false) \
					or float(value.get("impair", 0.0)) > 0.0: return true
			for layer in _array(value.get("layers", [])):
				if layer is Dictionary and layer.get("permanent", false): return true
	return false

static func _hurt(u: Unit, report: Dictionary) -> bool:
	if report["status"] == "wounded" or not report.get("parts", []).is_empty(): return true
	if u.body == null: return false
	if not u.body.permanent.is_empty() or u.body.blood < u.body.blood_max * 0.999: return true
	for value in u.body.parts.values():
		if not value is Dictionary: continue
		if value.get("severed", false) or value.get("nerve_m", false) or value.get("nerve_s", false) or value.get("punct", false) \
				or float(value.get("impair", 0.0)) > 0.0: return true
		for layer in _array(value.get("layers", [])):
			if layer is Dictionary and (float(layer.get("dmg", 0.0)) > 0.0 or float(layer.get("bleed", 0.0)) > 0.0 \
					or not str(layer.get("kind", "")).is_empty() or layer.get("permanent", false)): return true
	return false
