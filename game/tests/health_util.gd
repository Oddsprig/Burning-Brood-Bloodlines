extends RefCounted
## Shared helpers for test_health_*.gd: hand-written wounds on a fresh human.

static func human(uname: String = "Test") -> Unit:
	var u := Unit.create("human", "player")
	u.name = uname
	return u

## Wound the first layer of `part_id` whose name or tissue matches `layer`.
static func wound(u: Unit, part_id: String, layer: String, kind: String, dmg: float, bleed: float = 0.0) -> void:
	for l in u.body.wound_part(part_id)["layers"]:
		if l["name"] == layer or l["tissue"] == layer:
			l["kind"] = kind
			l["dmg"] = dmg
			l["bleed"] = bleed
			return
	push_error("no layer %s on %s" % [layer, part_id])

static func layer(u: Unit, part_id: String, lname: String) -> Dictionary:
	# Tests also write through this helper, so return a stored writable layer.
	for l in u.body.wound_part(part_id)["layers"]:
		if l["name"] == lname or l["tissue"] == lname:
			return l
	return {}

static func part_entry(r: Dictionary, part_id: String) -> Dictionary:
	for p in r["parts"]:
		if p["part"] == part_id:
			return p
	return {}
