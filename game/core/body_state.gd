class_name BodyState
extends RefCounted
## Tissue-level body state for one unit. No HP anywhere.
##
## Sparse (v0.013, full DF anatomy, ~117 parts a humanoid): ONLY parts that carry a wound or a mark are stored.
## parts[part_id] = {
##   "severed": bool,
##   "layers": [ {"tissue": String, "name": String,
##                "dmg": float 0..1 (1 = destroyed), "kind": String ("" | "bruised" | "cut" | "torn" |
##                "pierced" | "fractured" | "broken" | "mangled" | "destroyed"),
##                "bleed": float (blood per tick while open), "heal_days": float, + healing's keys}, ... ],
##   optional marks: "impair" (healing), "stump_assessed", "nerve_m" / "nerve_s" (motor / sensory nerve severed,
##   DF HAS_NERVES), "punct" (lung punctured), "spilled" (guts spilled), "knocked" (tooth knocked out)
## }
## An unhurt part is not stored: part(pid) / layers_of(pid) give the plan's shared unhurt part (READ ONLY);
## wound_part(pid) stores a copy the first time the part is hurt (callers write only into that copy).
## A layer's thickness lives in the plan: layer def "t" (mm at 70 kg) x scale.
## Persists between battles; town healing reduces dmg/heal_days and compact() drops parts that healed clean.

var plan_id: String = "humanoid"
var scale: float = 1.0          # (mass/70)^(1/3); layer thickness multiplier
var parts: Dictionary = {}      # wounded / marked parts only
var blood_max: float = 100.0    # scaled by body mass
var blood: float = 100.0
var pain: float = 0.0           # summed pain, decays
var exertion: float = 0.0       # fatigue; slows swings (exertion/END)
var permanent: Array = []       # human-readable permanent injury strings

## Per plan, shared by every body: [the plan dictionary it was built from, {part id -> def}, {part id -> unhurt part}].
static var _plans: Dictionary = {}
const LAYER_STATE := ["tissue", "name", "dmg", "kind", "bleed", "heal_days"]

func init_from_plan(_plan: Dictionary, mass_kg: float) -> void:
	scale = pow(mass_kg / 70.0, 1.0 / 3.0)
	blood_max = 100.0 * mass_kg / 70.0
	blood = blood_max
	parts = {}

func plan() -> Dictionary:
	return DB.bodies[plan_id]

func _cache() -> Array:
	var pl := plan()
	var e: Array = _plans.get(plan_id, [])
	if e.is_empty() or not is_same(e[0], pl):
		var defs := {}
		var unhurt := {}
		for p in pl["parts"]:
			defs[p["id"]] = p
			var layers := []
			for l in p["layers"]:
				layers.append({"tissue": l["tissue"], "name": l.get("name", l["tissue"]), "dmg": 0.0, "kind": "",
					"bleed": 0.0, "heal_days": 0.0})
			unhurt[p["id"]] = {"severed": false, "layers": layers}
		e = [pl, defs, unhurt]
		_plans[plan_id] = e
	return e

## {part id -> part def} of this body's plan.
func defs() -> Dictionary:
	return _cache()[1]

func part_def(part_id: String) -> Dictionary:
	return _cache()[1].get(part_id, {})

## The plan has this part (stored or not).
func has_part(part_id: String) -> bool:
	return _cache()[1].has(part_id)

## The part's state: the stored one, else the plan's shared unhurt part (do not write into it).
func part(part_id: String) -> Dictionary:
	var p = parts.get(part_id)
	if p != null:
		return p
	return _cache()[2].get(part_id, {})

func layers_of(part_id: String) -> Array:
	return part(part_id).get("layers", [])

## The stored (writable) part, made from the unhurt one the first time it is hurt.
func wound_part(part_id: String) -> Dictionary:
	var p = parts.get(part_id)
	if p == null:
		p = (_cache()[2].get(part_id, {"severed": false, "layers": []}) as Dictionary).duplicate(true)
		parts[part_id] = p
	return p

## A part is lost if it, or any ancestor, is severed.
func is_lost(part_id: String) -> bool:
	if parts.is_empty():
		return false
	var d: Dictionary = _cache()[1]
	var id := part_id
	var guard := 0
	while id != "" and guard < 16:
		var p = parts.get(id)
		if p != null and p.get("severed", false):
			return true
		id = d.get(id, {}).get("parent", "")
		guard += 1
	return false

## Every lost part id of the plan (severed ones and everything attached below them).
func lost_ids() -> Array:
	var out := []
	var any := false
	for id in parts:
		if parts[id].get("severed", false):
			any = true
			break
	if not any:
		return out
	for id in _cache()[1]:
		if is_lost(id):
			out.append(id)
	return out

func total_bleed() -> float:
	var b := 0.0
	for id in parts:
		for l in parts[id]["layers"]:
			b += l["bleed"]
	return b

func is_wounded() -> bool:
	for id in parts:
		if parts[id]["severed"]:
			return true
		for l in parts[id]["layers"]:
			if l["dmg"] > 0.0:
				return true
	return blood < blood_max * 0.999

## Days until fully recovered (excluding permanent losses).
func days_to_heal() -> float:
	var d := 0.0
	for id in parts:
		for l in parts[id]["layers"]:
			d = maxf(d, l["heal_days"])
	return d

## A stored part with nothing left on it (healed clean, no marks).
static func _clean(p: Dictionary) -> bool:
	if p.get("severed", false):
		return false
	for k in p:
		if k == "severed" or k == "layers":
			continue
		var v = p[k]
		if v is bool and v or (v is float or v is int) and v != 0:
			return false
	for l in p.get("layers", []):
		if float(l.get("dmg", 0.0)) > 0.0 or String(l.get("kind", "")) != "" or float(l.get("bleed", 0.0)) > 0.0 \
				or float(l.get("heal_days", 0.0)) > 0.0 or l.get("permanent", false):
			return false
	return true

## Drops stored parts that healed clean (memory and save size: an unhurt body stores nothing).
## Not during a battle: the sim holds references to stored layers.
func compact() -> void:
	for id in parts.keys():
		if _clean(parts[id]):
			parts.erase(id)

func to_dict() -> Dictionary:
	var ps := {}
	for id in parts:
		if not _clean(parts[id]):
			ps[id] = parts[id].duplicate(true)
	return {"plan": plan_id, "scale": scale, "parts": ps, "blood_max": blood_max,
		"blood": blood, "pain": pain, "exertion": exertion, "permanent": permanent.duplicate()}

static func from_dict(d: Dictionary) -> BodyState:
	var b := BodyState.new()
	b.plan_id = d.get("plan", "humanoid")
	if not DB.bodies.has(b.plan_id):
		b.plan_id = "humanoid"
	b.scale = d.get("scale", 1.0)
	b.blood_max = d.get("blood_max", 100.0)
	b.blood = d.get("blood", b.blood_max)
	b.pain = d.get("pain", 0.0)
	b.exertion = d.get("exertion", 0.0)
	b.permanent = d.get("permanent", [])
	b._load_parts(d.get("parts", {}))
	return b

## Saved parts onto the current plan. Saves from before v0.013 stored every part with the old layer lists (organs
## as layers of the trunk, motor nerve layers): each layer is matched by name; wounds of layers the plan no longer
## has are dropped (the organs are parts of their own now), a severed old motor nerve becomes the part's nerve mark.
func _load_parts(raw: Dictionary) -> void:
	parts = {}
	var defs: Dictionary = _cache()[1]
	for pid in raw:
		if not defs.has(pid):
			continue
		var old: Dictionary = raw[pid]
		var olayers: Array = old.get("layers", [])
		var dl: Array = defs[pid]["layers"]
		var same := olayers.size() == dl.size()
		if same:
			for i in dl.size():
				if String(olayers[i].get("name", olayers[i].get("tissue", ""))) != String(dl[i].get("name", dl[i]["tissue"])):
					same = false
					break
		if same:
			for l in olayers:
				l.erase("t")
			parts[pid] = old
			continue
		var np: Dictionary = (_cache()[2][pid] as Dictionary).duplicate(true)
		for k in old:
			if k != "layers":
				np[k] = old[k]
		for ol in olayers:
			var nm := String(ol.get("name", ol.get("tissue", "")))
			if nm == "motor nerve" and float(ol.get("dmg", 0.0)) >= 0.6:
				np["nerve_m"] = true
			for nl in np["layers"]:
				if String(nl["name"]) == nm:
					for k in ol:
						if k != "t" and k != "tissue" and k != "name":
							nl[k] = ol[k]
					break
		parts[pid] = np
	compact()
