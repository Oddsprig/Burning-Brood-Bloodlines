class_name DragonFear
extends RefCounted
## v0.028: fear of dragons. A settlement that has seen a dragon fight against it
## remembers, in its feudal row ("dragon_fear" 0-100, "fear_of" = the faction whose
## dragon it was). Fear decays slowly, breeds grievance, and can make a disloyal
## town swear to the feared faction (see Feudal.daily). No new records live here.
const RADIUS := 400.0
const HIT := 20.0
const NEIGHBOUR := 6.0
const DECAY := 0.3
const GRIEVANCE_AT := 40.0
const GRIEVANCE_STEP := 0.1

static func fear(game, tid) -> float:
	var row: Dictionary = game.world.get("feudal", {}).get("towns", {}).get(str(tid), {})
	return clampf(float(row.get("dragon_fear", 0.0)), 0.0, 100.0)

static func add(game, tid, amount, source_faction) -> void:
	var row: Dictionary = Feudal._state(game.world)["towns"].get(str(tid), {})
	if row.is_empty(): return
	row["dragon_fear"] = clampf(float(row.get("dragon_fear", 0.0)) + float(amount), 0.0, 100.0)
	if float(amount) > 0.0 and str(source_faction) != "": row["fear_of"] = str(source_faction)

## The realm that owns a dragon record: the faction of its estate town.
static func _dragon_faction(game, rec: Dictionary) -> String:
	var estate := str(rec.get("estate_town_id", ""))
	return str(game.world.get("towns", {}).get(estate, {}).get("faction", ""))

static func _player_dragon_fought(game, result: Dictionary, assault: Dictionary) -> bool:
	var mine := Warfare.player_faction(game)
	for u in assault.get("dragon_units", []):
		if DragonCombat.is_dragon_unit(game, u):
			var rec := DragonCombat.record_for_unit(game, u)
			if rec.is_empty() or _dragon_faction(game, rec) == mine: return true
	var receipt: Dictionary = result.get("dragon_combat_receipt", {})
	for entry in receipt.get("units", []):
		var rec: Dictionary = game.world.get("dragons", {}).get("records", {}).get(str(entry.get("dragon_uid", "")), {})
		if not rec.is_empty() and _dragon_faction(game, rec) == mine: return true
	for u in result.get("player_units", []):
		if DragonCombat.is_dragon_unit(game, u): return true
	return false

## Called once per assault from Warfare.after_battle, before the assault resolves
## (so the town still wears its old faction when its neighbours are found).
static func after_battle(game, result, assault) -> void:
	if game.world.is_empty(): return
	var pending: Dictionary = assault.get("assault", assault) if assault is Dictionary else {}
	var tid := str(pending.get("town_id", ""))
	if tid == "": return
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	if town.is_empty(): return
	if not _player_dragon_fought(game, result, assault): return
	var source := Warfare.player_faction(game)
	if source == "": return
	add(game, tid, HIT, source)
	var fid := str(town.get("faction", ""))
	var pos: Variant = town.get("pos", null)
	if not (pos is Vector2): return
	for other_id in game.world.get("towns", {}):
		if str(other_id) == tid: continue
		var other: Dictionary = game.world["towns"][other_id]
		if str(other.get("faction", "")) != fid: continue
		var opos: Variant = other.get("pos", null)
		if opos is Vector2 and (opos as Vector2).distance_to(pos) <= RADIUS:
			add(game, str(other_id), NEIGHBOUR, source)

## Once a day, on the same daily path as Feudal.daily.
static func daily(game) -> void:
	var rows: Dictionary = Feudal._state(game.world)["towns"]
	for tid in rows:
		var row: Dictionary = rows[tid]
		var f := clampf(float(row.get("dragon_fear", 0.0)) - DECAY, 0.0, 100.0)
		row["dragon_fear"] = f
		if f >= GRIEVANCE_AT:
			row["grievance"] = clampf(float(row.get("grievance", 0.0)) + GRIEVANCE_STEP, 0.0, 100.0)
