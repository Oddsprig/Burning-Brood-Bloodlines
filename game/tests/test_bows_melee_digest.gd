extends RefCounted
## bows: melee-only battles must match their reviewed recording after deliberate data/text changes.
## Explicit troop templates freeze equipment and skill ranges; live race data still determines attributes/size.
## Every event, rendered log/detail/calc and final body is hashed. Original archive hashes stay pinned below.

const U = preload("res://tests/sim_util.gd")
const Observations = preload("res://tests/class_d_observations.gd")

## Recorded before bows (5f8d605); re-recorded at v0.014: the v0.013 anatomy had already changed every digest, and
## v0.014 gear damage (bends, chips, dents, snaps change later blows) and the new log wording change them by design.
## Re-recorded at v0.070 from the live headless run: sword thrust and spear recovery in the weapon tables
## changed these melee digests on purpose. A mismatch means melee results (or the log text) changed.
## v0.100: reviewed v0.080 goblin STR/TOU/mass tuning and v0.098 artery-text change.
## Apply only after independent original-trace comparison; receipt: test-results/v0.100/melee_reference/v100_refresh_receipt.md.
const EXPECT := {
	"soldiers": "d50e2137b900ed2a2f64bd69143a073b",
	"middle_vs_goblins": "25ce1f38be5aa4829e6924335f516186",
	"elves_vs_orcs": "c4cd645170afecd58a5955f4b920cdb7",
	"corridor_stream": "a4b9550c5a182935160cd0e4317830ac",
	"wolves": "6c84b428beb0e4a477d0665236a075a1",
}

## --melee-reference authenticates only the original v0.070a recording, never the replacement targets above.
const REFERENCE_EXPECT: Dictionary = {
	"soldiers": "43b8a3143e684a60899f436dd9c17e17",
	"middle_vs_goblins": "4c9c7903c5520585f1c70413f5ce4d44",
	"elves_vs_orcs": "8ad711a865626d0df1f519c3e902f2a7",
	"corridor_stream": "d5ca0b8be20e29ba561ecef3c2d2c28e",
	"wolves": "fdc3a834ed869c105c13e89671dba725",
}

const T_SPEAR := {"name": "spearman", "skills": {"spear": [2, 5], "shield_user": [1, 4], "dodger": [0, 2], "armor_user": [1, 3], "fighter": [1, 3]},
	"loadout": {"main_hand": ["boar_spear"], "off_hand": ["kite_shield"], "helm": ["nasal_helm", "mail_coif"], "body": ["mail_shirt", ""], "clothing": ["tunic"], "legs_under": ["trousers"], "feet": ["shoes"]}}
const T_MAA := {"name": "man-at-arms", "skills": {"sword": [3, 6], "shield_user": [2, 5], "armor_user": [2, 5], "fighter": [2, 4], "dodger": [1, 3]},
	"loadout": {"main_hand": ["arming_sword", "flanged_mace"], "off_hand": ["kite_shield"], "helm": ["nasal_helm"], "body": ["mail_shirt"], "legs": ["splint_greaves", ""], "clothing": ["tunic"], "legs_under": ["trousers"], "feet": ["shoes"]}}
const T_GSPEAR := {"name": "goblin spear", "skills": {"spear": [1, 4], "dodger": [1, 3], "fighter": [0, 2]},
	"loadout": {"main_hand": ["short_spear"], "off_hand": ["buckler", ""], "helm": ["pot_helm", ""], "body": ["scale_vest", ""], "clothing": ["tunic"], "legs_under": ["trousers"]}}
const T_GSKULK := {"name": "goblin skulker", "skills": {"dagger": [1, 4], "dodger": [2, 5], "fighter": [0, 2]},
	"loadout": {"main_hand": ["shiv", "hook_sickle"], "off_hand": ["buckler", ""], "helm": ["pot_helm", ""], "clothing": ["tunic"], "legs_under": ["trousers"]}}
const T_GLAIVE := {"name": "glaive dancer", "skills": {"polearm": [3, 6], "dodger": [3, 6], "fighter": [2, 4], "discipline": [2, 4]},
	"loadout": {"main_hand": ["glaive"], "helm": ["crescent_helm"], "body": ["lamellar_cuirass", ""], "legs": ["moon_greaves", ""], "clothing": ["tunic"], "legs_under": ["trousers"], "feet": ["shoes"]}}
const T_MBLADE := {"name": "moon blade", "skills": {"sword": [3, 6], "dagger": [2, 4], "dodger": [3, 6], "fighter": [2, 4]},
	"loadout": {"main_hand": ["crescent_sabre"], "helm": ["crescent_helm", ""], "body": ["lamellar_cuirass"], "hands": ["vambraces", ""], "clothing": ["tunic"], "legs_under": ["trousers"], "feet": ["shoes"]}}
const T_ORC := {"name": "orc warrior", "skills": {"axe": [2, 5], "mace": [2, 5], "fighter": [2, 4], "shield_user": [0, 2]},
	"loadout": {"main_hand": ["hacking_cleaver", "spiked_club"], "off_hand": ["slab_shield", ""], "helm": ["skull_cap", ""], "body": ["scrap_plates", ""], "hands": ["crude_bracers", ""], "clothing": ["tunic"], "legs_under": ["trousers"]}}
const T_BRUTE := {"name": "orc brute", "skills": {"hammer": [3, 6], "fighter": [3, 5], "armor_user": [1, 3]},
	"loadout": {"main_hand": ["war_maul"], "helm": ["skull_cap"], "body": ["scrap_plates"], "hands": ["crude_bracers"], "clothing": ["tunic"], "legs_under": ["trousers"]}}

static func _named(units: Array, prefix: String) -> Array:
	for i in units.size():
		units[i].name = "%s %d" % [prefix, i]
	return units

static func _troops(rng: RandomNumberGenerator, fid: String, ts: Array, n: int, prefix: String) -> Array:
	var out := []
	for i in n:
		out.append(Factory.make_troop(rng, fid, ts[i % ts.size()], 2))
	return _named(out, prefix)

static func digest(sim: BattleSim) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(("%d|%d" % [sim.winner, sim.tick]).to_utf8_buffer())
	for e in sim.events:
		ctx.update(("%d|%s|%d|%d|%s" % [e["tick"], e["type"], e["actor"], e["target"], BattleSim.event_text(e)]).to_utf8_buffer())
	for f in sim.fighters:
		for le in f.log:
			var r := BattleSim.render_entry(le)
			ctx.update(("%d:%s:%s:%s" % [le["tick"], r["text"], "|".join(PackedStringArray(r["detail"])), r["calc"]]).to_utf8_buffer())
		ctx.update(("%s %.6f %.6f %.6f %d %d" % [f.state, f.unit.body.blood, f.unit.body.pain, f.unit.body.exertion, f.cell.x, f.cell.y]).to_utf8_buffer())
		for pid in f.unit.body.parts:
			for L in f.unit.body.parts[pid]["layers"]:
				ctx.update(("%s %.6f %s" % [pid, float(L["dmg"]), String(L.get("kind", ""))]).to_utf8_buffer())
	return ctx.finish().hex_encode()

## Exact hash input fragments, for comparing an authenticated archived trace to a mismatch.
## Kept separate from digest() so all five complete golden gates use the original hash algorithm.
static func digest_chunks(sim: BattleSim) -> Array[String]:
	var chunks: Array[String] = ["%d|%d" % [sim.winner, sim.tick]]
	for event: Dictionary in sim.events:
		chunks.append("%d|%s|%d|%d|%s" % [event["tick"], event["type"], event["actor"], event["target"], BattleSim.event_text(event)])
	for fighter: Fighter in sim.fighters:
		for entry: Dictionary in fighter.log:
			var rendered: Dictionary = BattleSim.render_entry(entry)
			chunks.append("%d:%s:%s:%s" % [entry["tick"], rendered["text"], "|".join(PackedStringArray(rendered["detail"])), rendered["calc"]])
		chunks.append("%s %.6f %.6f %.6f %d %d" % [fighter.state, fighter.unit.body.blood, fighter.unit.body.pain, fighter.unit.body.exertion, fighter.cell.x, fighter.cell.y])
		for part: String in fighter.unit.body.parts:
			for layer: Dictionary in fighter.unit.body.parts[part]["layers"]:
				chunks.append("%s %.6f %s" % [part, float(layer["dmg"]), String(layer.get("kind", ""))])
	return chunks

func _reference() -> Dictionary:
	var path: String = ""
	var selected: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--melee-reference="): continue
		if selected:
			printerr("FAIL: supply --melee-reference exactly once")
			return {"ok": false}
		selected = true
		path = argument.trim_prefix("--melee-reference=")
	if not selected: return {"ok": true, "traces": {}}
	if path == "" or not FileAccess.file_exists(path):
		printerr("FAIL: melee reference archive is missing or unreadable: ", path)
		return {"ok": false}
	var traces: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not traces is Dictionary or traces.size() != REFERENCE_EXPECT.size():
		printerr("FAIL: melee reference must contain all five archived hash-input arrays")
		return {"ok": false}
	for key: String in REFERENCE_EXPECT:
		if not traces.has(key) or not traces[key] is Array or traces[key].is_empty():
			printerr("FAIL: melee reference has no archived chunks for ", key)
			return {"ok": false}
		var context: HashingContext = HashingContext.new()
		context.start(HashingContext.HASH_MD5)
		for chunk: Variant in traces[key]:
			if not chunk is String:
				printerr("FAIL: non-string archived melee hash input for ", key)
				return {"ok": false}
			context.update(str(chunk).to_utf8_buffer())
		if context.finish().hex_encode() != REFERENCE_EXPECT[key]:
			printerr("FAIL: archived melee chunks do not authenticate against original v0.070a EXPECT for ", key)
			return {"ok": false}
	return {"ok": true, "traces": traces}

static func first_difference(actual: Array[String], expected: Array) -> Dictionary:
	for index: int in mini(actual.size(), expected.size()):
		if actual[index] != expected[index]:
			return {"index": index, "expected": expected[index], "actual": actual[index]}
	if actual.size() != expected.size(): return {"index": mini(actual.size(), expected.size()), "expected_size": expected.size(), "actual_size": actual.size()}
	return {}

static func battles() -> Dictionary:
	var out := {}
	# 1. sim_util soldiers: copper swords and shields vs tin spears
	var a := []
	var b := []
	for i in 4:
		a.append(U.soldier("copper"))
		b.append(U.soldier("tin", "boar_spear"))
	_named(a, "Copper"); _named(b, "Tin")
	out["soldiers"] = U.run(a, b, 11, {"w": 16, "h": 8, "log_moves": true})
	# 2. March troops vs goblins on a 24x12 field
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var m := _troops(rng, "middle_kingdom", [T_SPEAR, T_MAA], 6, "March")
	var g := _troops(rng, "goblin_warren", [T_GSPEAR, T_GSKULK], 8, "Gob")
	out["middle_vs_goblins"] = U.run(m, g, 4242, {"w": 24, "h": 12, "log_moves": true})
	# 3. moon elves vs orcs
	rng.seed = 6
	var el := _troops(rng, "moon_court", [T_GLAIVE, T_MBLADE], 5, "Elf")
	var oc := _troops(rng, "orc_horde", [T_ORC, T_BRUTE], 5, "Orc")
	out["elves_vs_orcs"] = U.run(el, oc, 77, {"w": 24, "h": 12, "log_moves": true, "terrain": "forest"})
	# 4. a veteran holding a corridor against a stream of recruits
	var v := U.veteran(50)
	v.name = "Veteran"
	var rs := []
	for i in 8:
		rs.append(U.recruit())
	_named(rs, "Recruit")
	out["corridor_stream"] = U.run([v], rs, 3, {"w": 24, "h": 9, "map": "corridor1", "stream": true, "stream_gap": 30,
		"cells0": [Vector2i(11, 4)], "hold0": true, "log_moves": true})
	# 5. wolves against two spearmen (natural attacks, latching)
	rng.seed = 9
	var wolves := _named(Creatures.make_group(rng, "wolf", 4), "Wolf")
	var men := _troops(rng, "middle_kingdom", [T_SPEAR], 2, "Herder")
	out["wolves"] = U.run(men, wolves, 21, {"w": 16, "h": 8, "log_moves": true})
	return out

static func observation(sim: BattleSim) -> Dictionary:
	var events: Array = []
	for event: Dictionary in sim.events:
		events.append({"event": event.duplicate(true), "text": BattleSim.event_text(event)})
	var fighters: Array = []
	for fighter: Variant in sim.fighters:
		var logs: Array = []
		for entry: Dictionary in fighter.log:
			logs.append({"entry": entry.duplicate(true), "rendered": BattleSim.render_entry(entry)})
		fighters.append({"uid": fighter.unit.uid, "name": fighter.unit.name, "state": fighter.state,
			"cell": fighter.cell, "blood": fighter.unit.body.blood, "pain": fighter.unit.body.pain,
			"exertion": fighter.unit.body.exertion, "part_order": fighter.unit.body.parts.keys(),
			"parts": fighter.unit.body.parts.duplicate(true), "logs": logs})
	return {"digest_chunks": digest_chunks(sim), "winner": sim.winner, "tick": sim.tick, "events": events, "fighters": fighters}

func run(_tree: SceneTree) -> int:
	var fails: int = 0
	var archive: Dictionary = _reference()
	if not bool(archive["ok"]): return 1
	var bs: Dictionary = battles()
	var actual_keys: Array = bs.keys(); actual_keys.sort()
	var expected_keys: Array = EXPECT.keys(); expected_keys.sort()
	if actual_keys != expected_keys:
		printerr("FAIL: melee digest must execute every immutable battle: ", actual_keys)
		return 1
	for k in bs:
		var sim: BattleSim = bs[k]
		var dg := digest(sim)
		var exp: String = EXPECT.get(k, "")
		var ok := exp == dg
		print("  %-20s winner %d tick %5d events %5d digest %s %s" % [k, sim.winner, sim.tick, sim.events.size(), dg,
			"PASS" if ok else ("(no recorded digest)" if exp == "" else "FAIL: expected " + exp)])
		if not ok:
			fails += 1
			var chunks: Array[String] = digest_chunks(sim)
			var archived: Dictionary = archive["traces"]
			if archived.has(k):
				print("MELEE_FIRST_DIFFERENCE ", JSON.stringify({"case": k, "difference": first_difference(chunks, archived[k])}))
			else:
				printerr("FAIL: independent archived melee trace needed for ", k, "; current output cannot authenticate a replacement golden")
			printerr("FAIL: melee digest ", k, " actual ", dg, " expected ", exp)
			if not Observations.write("bows_melee_digest", {"case": k, "actual": dg, "expected": exp,
				"expected_trace_available": archived.has(k), "reference_difference": first_difference(chunks, archived[k]) if archived.has(k) else {}, "observed": observation(sim)}):
				fails += 1
	return fails
