class_name Outfit
extends RefCounted
## Pure outfitting logic (DF-style uniforms). No nodes; every function takes the data it changes.
##
## Squad rule: squads[officer_uid] = {"uniform": {slot: template_id}, "material": "any"|"copper"|"tin"}.
## A troop's wanted gear = squad uniform, overlaid with unit.overrides[slot] (override "" = leave the slot empty).
## Officers (and the captain) are outfitted individually: only their own overrides count as a rule.
## Two-handed weapons preclude a shield.

## Equipment slot a template goes into.
static func slot_of(tid: String) -> String:
	if DB.is_weapon(tid):
		return "main_hand"
	if DB.is_bow(tid):   # bows
		return "ranged"
	var s: String = DB.armor.get(tid, {}).get("slot", "")
	return "off_hand" if s == "shield" else s

static func is_two_handed(tid: String) -> bool:
	return bool(DB.weapons.get(tid, {}).get("two_handed", false))

static func template_name(tid: String) -> String:
	if tid == "":
		return "(nothing)"
	return String(DB.template(tid).get("name", tid))

## All known templates for a slot, sorted by name.
static func templates_for_slot(slot: String) -> Array:
	var out := []
	for tid in DB.weapons.keys() + DB.armor.keys() + DB.bows.keys():   # bows: the ranged slot
		if slot_of(tid) == slot:
			out.append(tid)
	out.sort_custom(func(a, b): return template_name(a) < template_name(b))
	return out

## Does an item satisfy a material rule? Rules only bind templates that can be made of that material
## (a linen tunic satisfies a "copper" rule).
static func material_ok(item: Item, material: String) -> bool:
	if material == "" or material == "any" or item.material == material:
		return true
	var mats: Array = item.tmpl().get("materials", ["copper", "tin"])
	if DB.is_weapon(item.tid):
		mats = ["copper", "tin"]
	return not mats.has(material)

## Higher is better: quality first, then material value, then condition.
static func score(item: Item) -> float:
	return item.quality * 100.0 + float(item.mat().get("value", 1)) * 10.0 - item.wear * 3.0

static func best_in(items: Array, tid: String, material: String = "any") -> Item:
	var best: Item = null
	for it in items:
		if not it.broken and it.tid == tid and material_ok(it, material):
			if best == null or score(it) > score(best):
				best = it
	return best

## Squad rule for a troop's squad ({} when none).
static func rule_of(squads: Dictionary, unit: Unit) -> Dictionary:
	if unit.is_officer():
		return {"uniform": {}, "material": "any"}
	return squads.get(unit.squad, {"uniform": {}, "material": "any"})

## slot -> template id this unit should wear ("" = keep the slot empty).
static func wanted(squads: Dictionary, unit: Unit) -> Dictionary:
	var rule := rule_of(squads, unit)
	var w: Dictionary = (rule.get("uniform", {}) as Dictionary).duplicate()
	for s in unit.overrides:
		w[s] = unit.overrides[s]
	if is_two_handed(String(w.get("main_hand", ""))):
		w["off_hand"] = ""
	return w

## Plans which items from `avail` a unit takes. Removes taken items from `avail` (pass a copy for a dry run).
## Returns {"take": {slot: Item or null (null = strip the slot)}, "missing": [slot, ...]}.
static func plan_unit(unit: Unit, want: Dictionary, material: String, avail: Array) -> Dictionary:
	var take := {}
	var missing := []
	for slot in want:
		var tid: String = want[slot]
		var cur: Item = unit.equip.get(slot, null)
		if tid == "":
			if cur != null:
				take[slot] = null
			continue
		var best := best_in(avail, tid, material)
		var cur_ok := cur != null and not cur.broken and cur.tid == tid and material_ok(cur, material)
		if cur_ok:
			if best != null and score(best) > score(cur):
				take[slot] = best
				avail.erase(best)
			continue
		if best != null:
			take[slot] = best
			avail.erase(best)
		else:
			missing.append(slot)
	# Two-handed weapon in hand after the plan -> no shield.
	var w: Item = take.get("main_hand", unit.equip.get("main_hand", null))
	if w != null and is_two_handed(w.tid):
		if take.get("off_hand", null) != null:
			avail.append(take["off_hand"])
		if unit.equip.has("off_hand"):
			take["off_hand"] = null
		else:
			take.erase("off_hand")
		missing.erase("off_hand")
	return {"take": take, "missing": missing}

## Executes a plan: replaced or stripped items go back to the stash.
static func execute(unit: Unit, take: Dictionary, stash: Array) -> int:
	var n := 0
	for slot in take:
		var cur: Item = unit.equip.get(slot, null)
		if cur != null:
			unit.equip.erase(slot)
			stash.append(cur)
		var it: Item = take[slot]
		if it != null:
			stash.erase(it)
			unit.equip[slot] = it
			n += 1
	return n

## Outfit one unit from the stash by its wanted gear. Returns {"equipped": int, "missing": [{...}]}.
static func outfit_unit(squads: Dictionary, unit: Unit, stash: Array) -> Dictionary:
	var rule := rule_of(squads, unit)
	var avail := stash.duplicate()
	var p := plan_unit(unit, wanted(squads, unit), String(rule.get("material", "any")), avail)
	var n := execute(unit, p["take"], stash)
	var want := wanted(squads, unit)
	var miss := []
	for slot in p["missing"]:
		miss.append({"uid": unit.uid, "name": unit.name, "slot": slot, "tid": want[slot],
			"material": String(rule.get("material", "any"))})
	return {"equipped": n, "missing": miss}

## "Apply uniform": every troop of the squad equips from the stash, best quality first.
## Returns {"equipped": int, "missing": [{uid, name, slot, tid, material}], "lines": [String]}.
static func apply_uniform(squads: Dictionary, company: Array, officer_uid: int, stash: Array) -> Dictionary:
	var equipped := 0
	var missing := []
	for u in company:
		if u.is_officer() or u.squad != officer_uid or u.dead:
			continue
		var r := outfit_unit(squads, u, stash)
		equipped += int(r["equipped"])
		missing.append_array(r["missing"])
	return {"equipped": equipped, "missing": missing, "lines": missing_lines(missing)}

## Human-readable missing-piece report, grouped by template: "3 x copper mail shirt missing".
static func missing_lines(missing: Array) -> Array:
	var counts := {}
	var order := []
	for m in missing:
		var mat: String = m.get("material", "any")
		var key := "%s|%s" % [m["tid"], mat]
		if not counts.has(key):
			counts[key] = 0
			order.append(key)
		counts[key] += 1
	var out := []
	for key in order:
		var parts: PackedStringArray = key.split("|")
		var mat_word := "" if parts[1] == "any" else parts[1] + " "
		out.append("%d x %s%s missing" % [counts[key], mat_word, template_name(parts[0])])
	return out

## Dry run over the whole company: what the stash cannot cover. Returns [{tid, material, count}].
static func shortfall(squads: Dictionary, company: Array, stash: Array) -> Array:
	var avail := stash.duplicate()
	var counts := {}
	for u in company:
		if u.is_officer() or u.dead:
			continue
		var rule := rule_of(squads, u)
		var mat := String(rule.get("material", "any"))
		var want := wanted(squads, u)
		var p := plan_unit(u, want, mat, avail)
		for slot in p["missing"]:
			var key := "%s|%s" % [want[slot], mat]
			counts[key] = int(counts.get(key, 0)) + 1
	var out := []
	for key in counts:
		var parts: PackedStringArray = key.split("|")
		out.append({"tid": parts[0], "material": parts[1], "count": counts[key]})
	return out

## Individual equip from the stash (officers, or a manual pick). Returns "" or a reason it failed.
static func equip_item(unit: Unit, item: Item, stash: Array) -> String:
	var slot := item.slot()
	if slot == "":
		return "cannot be worn"
	if slot == "off_hand":
		var w := unit.weapon()
		if w != null and is_two_handed(w.tid):
			return "a two-handed %s leaves no hand for a shield" % template_name(w.tid)
	stash.erase(item)
	if unit.equip.has(slot):
		stash.append(unit.equip[slot])
	unit.equip[slot] = item
	if slot == "main_hand" and is_two_handed(item.tid) and unit.equip.has("off_hand"):
		stash.append(unit.equip["off_hand"])
		unit.equip.erase("off_hand")
	return ""

static func unequip(unit: Unit, slot: String, stash: Array) -> void:
	if unit.equip.has(slot):
		stash.append(unit.equip[slot])
		unit.equip.erase(slot)

static func strip(unit: Unit, stash: Array) -> void:
	for slot in unit.equip.keys():
		unequip(unit, slot, stash)

## Stash items that fit a slot (and the unit's hands), best first.
static func stash_for_slot(stash: Array, slot: String, unit: Unit = null) -> Array:
	var out := stash.filter(func(it): return it.slot() == slot)
	if slot == "off_hand" and unit != null and unit.weapon() != null and is_two_handed(unit.weapon().tid):
		return []
	out.sort_custom(func(a, b): return score(a) > score(b))
	return out
