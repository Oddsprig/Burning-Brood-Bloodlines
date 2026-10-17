extends RefCounted
## bows: melee-only battles must stay bit-identical to the sim before bows landed (Douglas).
## Each battle below uses fixed rosters (explicit troop templates copied here, so faction data edits cannot change
## them) and is digested over every event, every rendered log line and its calc text, and the end state of every
## body. The expected digests were recorded on the commit before the bows work (5f8d605 "Bows spec").

const U = preload("res://tests/sim_util.gd")

## Recorded before bows (5f8d605); re-recorded at v0.014: the v0.013 anatomy had already changed every digest, and
## v0.014 gear damage (bends, chips, dents, snaps change later blows) and the new log wording change them by design.
## A mismatch means melee results (or the log text) changed.
const EXPECT := {
	"soldiers": "b21ac38f64a829dd097fc63552b1147d",
	"middle_vs_goblins": "92271bbf0d54afa8cdfe4d847823ec6f",
	"elves_vs_orcs": "da78cdc64447b3a6ccc6788328655cd1",
	"corridor_stream": "2c835105d788e9fd343d8b3e9ebcfa3e",
	"wolves": "34c7893b5eb78b811c5efca0d15be76e",
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

func run(_tree: SceneTree) -> int:
	var fails := 0
	var bs := battles()
	for k in bs:
		var sim: BattleSim = bs[k]
		var dg := digest(sim)
		var exp: String = EXPECT.get(k, "")
		var ok := exp == dg
		print("  %-20s winner %d tick %5d events %5d digest %s %s" % [k, sim.winner, sim.tick, sim.events.size(), dg,
			"PASS" if ok else ("(no recorded digest)" if exp == "" else "FAIL: expected " + exp)])
		if not ok:
			fails += 1
	return fails
