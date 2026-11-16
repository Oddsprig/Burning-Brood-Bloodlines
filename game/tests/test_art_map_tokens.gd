extends RefCounted
const NativeForces = preload("res://tests/class_d_registered_forces.gd")
## Map tokens (docs/specs/map-tokens.md): every type builds for every faction, cache hits, types are told apart
## in greyscale, a 16-man company is one token, syncing 40 tokens per frame is cheap, and PNG sheets for review
## land in %TEMP%/copper_tokens/.

var fails := 0
var _deadline_msec: int = 0
var _budget_failed: bool = false
const OUT := "user://copper_tokens/"   # v0.099: was a path on one Windows PC

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _opaque(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n

func _factions() -> Array:
	var out := []
	for fid in DB.factions:
		if not DB.factions[fid].get("wild", false):
			out.append(fid)
	return out

## Luminance-times-alpha mask over a white-free field, downsampled to 36x36.
func _mask(img: Image) -> PackedFloat32Array:
	var s := img.duplicate() as Image
	s.resize(36, 36, Image.INTERPOLATE_BILINEAR)
	var out := PackedFloat32Array()
	for y in 36:
		for x in 36:
			var c := s.get_pixel(x, y)
			# greyscale on a mid-grey map: what the eye reads
			var l := c.get_luminance() * c.a + 0.5 * (1.0 - c.a)
			out.append(l)
			out.append(c.a)
	return out

func _diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var d := 0.0
	for i in a.size():
		d += absf(a[i] - b[i])
	return d / a.size()

# map-tokens.md: the caravan token represents a whole paid native merchant force.
func _native_caravan(faction: String, rng: RandomNumberGenerator) -> Dictionary:
	var town_ids: Array = Game.world["towns"].keys()
	town_ids.sort()
	for tid: String in town_ids:
		var town: Dictionary = Game.world["towns"][tid]
		if String(town["faction"]) != faction: continue
		for _attempt: int in 16:
			if not _within_budget(): return {"ok": false, "reason": "native caravan setup exceeded the test budget"}
			var offer: Dictionary = Contracts.escort_offer(town, Game.day, rng)
			if offer.is_empty(): continue
			var before_people: int = NativeForces.population(Game)
			var before_coin: float = Barge.holdings(Game)
			town["contracts"].append(offer)
			if not Contracts.accept(Game, offer):
				return {"ok": false, "reason": "native Northern escort could not hire its actual paid crew"}
			var wid: String = String(Game.contract.get("target_id", ""))
			var band: Dictionary = Game.world["warbands"].get(wid, {})
			var valid: Dictionary = NativeForces.record(Game, band)
			if not bool(valid.get("ok", false)): return valid
			if String(band["kind"]) != "caravan" or String(band["faction"]) != faction:
				return {"ok": false, "reason": "native escort did not retain its actual faction and caravan kind"}
			if NativeForces.population(Game) != before_people or absf(Barge.holdings(Game) - before_coin) >= 0.01:
				return {"ok": false, "reason": "native caravan setup changed population or total coin"}
			return {"ok": true, "id": wid}
	return {"ok": false, "reason": "no native paid escort offer at an actual Northern town"}

# Compare real owned property and physical fields around the conserved fixture transfer.
func _camp_property(e: Dictionary) -> Dictionary:
	var land: Dictionary = {}
	var animals: Dictionary = {}
	var oxen: int = 0
	for family: Dictionary in e["fams"]:
		oxen += maxi(0, int(family.get("ox", 0)))
		for crop: String in family["land"]:
			land[crop] = int(land.get(crop, 0)) + int(family["land"][crop])
		for herd: Dictionary in Herds.of_family(e, int(family["id"])):
			var kind: String = String(herd["k"])
			animals[kind] = int(animals.get(kind, 0)) + Herds.head(herd)
	var fields: Dictionary = {}
	var plots: Dictionary = e.get("plots", {})
	for i: int in Plots.count(plots):
		if int(plots["use"][i]) not in Plots.LAND_USES: continue
		var crop: String = String(plots["crops"][int(plots["sub"][i])])
		fields[crop] = int(fields.get(crop, 0)) + int(plots["ac"][i])
	return {"land": land, "animals": animals, "oxen": oxen, "fields": fields}

# Retain the helper signature, but never endow land or manufacture employment.
# Reuse r1's conserved hardship fixture only for a town with genuine spare workers.
func _endow_camp_workers(setup: Variant, town: Dictionary, pay: float, rng: RandomNumberGenerator) -> Dictionary:
	var e: Dictionary = town["econ"]
	var before_property: Dictionary = _camp_property(e)
	var ready: int = int(setup._prepare_outlaws(town, pay))
	# No field transfers remain; keep the inherited physical-property assertion.
	check(_camp_property(e) == before_property, "native camp field transfers conserve owned acres, physical fields, oxen and herd heads")
	if fails > 0: return {"ok": false, "reason": "native camp preparation changed physical property totals"}
	if ready < 4: return {"ok": false, "reason": "conserved local camp preparation left fewer than four genuine prospective volunteers"}
	# Keep the production gang-size draw, without requiring a human body template.
	var band_range: Array = Creatures.tun("bandit_band", [3, 6])
	var count: int = rng.randi_range(int(band_range[0]), int(band_range[1])) + mini(int(Game.day / 20.0), 3)
	print("  art outlaw local workers %s: race=%s transfer_ready=%d requested_gang=%d land_transfers=0" %
		[town["id"], TownEcon.culture_of(e)["race"], ready, count])
	return {"ok": true, "count": count}

# The token contract is outlaws/bandit, with no human ancestry requirement.
# Select the source used by native residence-based spawning, not factory-human gangs.
func _register_camp_workers(setup: Variant) -> Dictionary:
	var w: Dictionary = Game.world
	var pay: float = float(Army.A()["wage"]["bandit"])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), "art-outlaw-workers"])
	var candidate: Dictionary = {}
	var candidate_town: Dictionary = {}
	var candidate_score: int = -1
	for lid: String in w["lairs"]:
		if not _within_budget(): return {"ok": false, "reason": "native outlaw registration exceeded the test budget"}
		var lair: Dictionary = w["lairs"][lid]
		if String(lair.get("kind", "")) != "bandit_camp": continue
		var town: Dictionary = setup._garrison_town(w, lair)
		if town.is_empty(): continue
		var ready: int = int(setup._count_ready(town, pay))
		print("  art outlaw local candidate %s: source=%s race=%s transfer_ready=%d" %
			[lid, town["id"], TownEcon.culture_of(town["econ"])["race"], ready])
		# Three resident places plus at least one roaming volunteer; no padded roster.
		if ready >= 4 and ready > candidate_score:
			candidate_score = ready
			candidate = lair
			candidate_town = town
	if candidate.is_empty():
		return {"ok": false, "reason": "no existing native camp source can spare four genuine prospective local volunteers"}
	var result: Dictionary = _endow_camp_workers(setup, candidate_town, pay, rng)
	if not bool(result.get("ok", false)): return result
	result["camp_id"] = String(candidate["id"])
	result["source_town"] = String(candidate_town["id"])
	return result

# Native spawn_warband builds resident bodies and enlists them as bandits at creation.
# It calls the unchanged People.draw_outlaw; neither an army draft nor a relabel.
func _native_bandit(excluded: Array) -> Dictionary:
	if not _within_budget(): return {"ok": false, "reason": "native outlaw setup exceeded the test budget"}
	var before_people: int = NativeForces.population(Game)
	var before_coin: float = Barge.holdings(Game)
	var before_day: float = float(Game.day)
	var setup: Variant = load("res://tests/test_bandit_camp_funding.gd").new()
	var before_facts: Dictionary = setup._people_and_goods()
	var registration: Dictionary = _register_camp_workers(setup)
	if not bool(registration.get("ok", false)):
		setup._check_people_and_goods(before_facts, "native token camp setup/recruitment")
		if int(setup.fails) != 0:
			return {"ok": false, "reason": "refused native camp preparation failed people/goods/meals conservation"}
		if NativeForces.population(Game) != before_people or absf(Barge.holdings(Game) - before_coin) >= 0.01 or float(Game.day) != before_day:
			return {"ok": false, "reason": "refused native camp preparation changed population, total coin or the campaign clock"}
		return registration
	var camp_id: String = String(registration["camp_id"])
	var w: Dictionary = Game.world
	var lair: Dictionary = w["lairs"][camp_id]
	var town: Dictionary = w["towns"][String(registration["source_town"])]
	var faction: String = String(town["faction"])
	var pay: float = float(Army.A()["wage"]["bandit"])
	var target: float = pay * 20.0 * 14.0
	# Exactly r1's existing-coin funding, from this actual source town's realm.
	setup._fund_faction(faction, target)
	setup._move_cash(w["factions"][faction], "treasury", lair, "gold", maxf(0.0, target - float(lair.get("gold", 0))))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 73
	var gang_id: String = ""
	if int(setup.fails) == 0 and _within_budget():
		if not w["warbands"].has(String(lair.get("resident", ""))):
			lair["resident"] = CampaignWorld.spawn_warband(Game, "outlaws", lair["pos"], 3, "camp", rng,
				{"home": camp_id, "lair": camp_id, "anchor": lair["pos"]})
		check(w["warbands"].has(String(lair.get("resident", ""))), "funded camp did not recruit real resident volunteers")
		if w["warbands"].has(String(lair.get("resident", ""))):
			# No supplied Units: the native spawner selects the real local residence.
			gang_id = CampaignWorld.spawn_warband(Game, "outlaws", lair["pos"], int(registration["count"]), "bandit", rng,
				{"home": camp_id, "lair": camp_id, "anchor": lair["pos"]})
		check(gang_id != "", "funded camp did not recruit a real roaming gang")
		if gang_id != "": Bandits.reequip(lair, w["warbands"][gang_id]["units"])
		check((setup._units_without_family(w) as Array).is_empty(), "funded outlaw fixture invented or lost a family link")
	setup._check_people_and_goods(before_facts, "native token camp setup/recruitment")
	if int(setup.fails) != 0 or camp_id == "":
		return {"ok": false, "reason": "conserved native camp/volunteer prerequisites failed"}
	if not _within_budget(): return {"ok": false, "reason": "native outlaw setup exceeded the test budget"}
	if NativeForces.population(Game) != before_people or absf(Barge.holdings(Game) - before_coin) >= 0.01 or float(Game.day) != before_day:
		return {"ok": false, "reason": "native outlaw setup changed population, total coin or the campaign clock"}
	if fails > 0 or gang_id == "":
		return {"ok": false, "reason": "native local camp/gang recruitment failed"}
	var resident: Dictionary = w["warbands"].get(String(lair.get("resident", "")), {})
	var valid_resident: Dictionary = NativeForces.record(Game, resident)
	check(bool(valid_resident.get("ok", false)), "native camp resident: " + str(valid_resident.get("reason", "")))
	if not bool(valid_resident.get("ok", false)): return valid_resident
	check(String(resident.get("kind", "")) == "camp" and String(resident.get("home", "")) == camp_id and String(resident.get("lair", "")) == camp_id,
		"native resident retains its actual camp kind, home and funding reference")
	var fixture: Dictionary = NativeForces.existing(Game, "outlaws", "bandit", excluded)
	if not bool(fixture.get("ok", false)): return fixture
	var band: Dictionary = Game.world["warbands"][String(fixture["id"])]
	if String(band["home"]) != camp_id or String(band.get("lair", "")) != camp_id:
		return {"ok": false, "reason": "native outlaw gang did not retain its actual recruiting/funding camp"}
	for unit: Unit in band["units"]:
		var home: Dictionary = w["towns"].get(unit.home_town, {})
		var family: Dictionary = People.fam_of(home, unit.family)
		var person: Array = Persons.by_uid(family, unit.uid)
		check(unit.race == Persons.family_race(home["econ"], family), "native outlaw body matches its actual household race")
		check(not person.is_empty() and String(person[4]) == "bandit" and int(family["serve"].get("bandit", 0)) > 0,
			"native roaming outlaw passed actual bandit enlistment and service registration")
	if fails > 0: return {"ok": false, "reason": "native outlaw household race/service registration failed"}
	print("  art outlaw recruited %s: camp=%s people=%d" % [fixture["id"], camp_id, (band["units"] as Array).size()])
	return fixture

func _within_budget() -> bool:
	if Time.get_ticks_msec() < _deadline_msec: return true
	if not _budget_failed:
		check(false, "art token test exceeded 150 seconds; an incomplete scene is a failure")
		_budget_failed = true
	return false

func run(tree: SceneTree) -> int:
	_deadline_msec = Time.get_ticks_msec() + 150000
	_budget_failed = false
	var result: int = await _run(tree)
	if not _within_budget(): result += 1
	return result

func _run(tree: SceneTree) -> int:
	await tree.process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	MapTokens.clear_cache()
	var t0 := Time.get_ticks_usec()
	# --- every token type builds for every faction (and every pip count / stance)
	var facs := _factions()
	for fid in facs:
		if not _within_budget(): return fails
		for ty in ["army", "militia", "caravan", "deserter"]:
			for p in [1, 3, 5]:
				for st in ["hostile", "neutral", "allied"]:
					var tx := MapTokens.texture(ty, fid, p, st)
					check(tx != null and tx.get_width() == MapTokens.SIZE, "%s %s builds" % [ty, fid])
			check(_opaque(MapTokens.image(ty, fid, 2, "neutral")) > 2500, "%s %s has a body" % [ty, fid])
	for cid in MapTokens.MONSTERS:
		check(_opaque(MapTokens.image("monster", cid, 1, "hostile")) > 2500, "monster %s has a body" % cid)
	check(_opaque(MapTokens.image("bandit", "", 1, "hostile")) > 2500, "bandit has a body")
	check(_opaque(MapTokens.image("player")) > 2500, "player has a body")
	var t_build := (Time.get_ticks_usec() - t0) / 1000.0
	print("  built %d bases in %.0f ms (%.1f ms per base, pips composited)" % [MapTokens.paint_count, t_build, t_build / maxf(1, MapTokens.paint_count)])

	# --- cache: same key -> same texture object, no repaint
	var pc := MapTokens.paint_count
	var a := MapTokens.texture("army", "middle_kingdom", 3, "hostile")
	var b := MapTokens.texture("army", "middle_kingdom", 3, "hostile")
	check(is_same(a, b), "cache hit returns the same texture object")
	check(not is_same(a, MapTokens.texture("army", "middle_kingdom", 3, "allied")), "stance is part of the key")
	check(MapTokens.paint_count == pc, "cache hits paint nothing")

	# --- greyscale distinctness between types (shape alone)
	var samples := {"player": MapTokens.image("player"), "army": MapTokens.image("army", "middle_kingdom", 2, "neutral"),
		"militia": MapTokens.image("militia", "middle_kingdom", 2, "neutral"), "caravan": MapTokens.image("caravan", "middle_kingdom", 2, "neutral"),
		"bandit": MapTokens.image("bandit", "", 2, "hostile"), "monster": MapTokens.image("monster", "wolf", 2, "hostile")}
	var masks := {}
	for k in samples:
		masks[k] = _mask(samples[k])
	var ks := samples.keys()
	var worst := 1.0
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			var d := _diff(masks[ks[i]], masks[ks[j]])
			worst = minf(worst, d)
			check(d > 0.08, "greyscale %s vs %s differ (%.3f)" % [ks[i], ks[j], d])
	print("  smallest greyscale type difference %.3f" % worst)
	# monster heads differ from each other too
	var heads := {}
	for cid in MapTokens.MONSTERS:
		# the inner disc only (box 17..47): the spiked ring and pips are shared by design
		heads[cid] = _mask(MapTokens.image("monster", cid, 1, "hostile").get_region(Rect2i(42, 42, 60, 60)))
	for i in MapTokens.MONSTERS.size():
		for j in range(i + 1, MapTokens.MONSTERS.size()):
			var d := _diff(heads[MapTokens.MONSTERS[i]], heads[MapTokens.MONSTERS[j]])
			print("  head %s vs %s %.3f" % [MapTokens.MONSTERS[i], MapTokens.MONSTERS[j], d])
			check(d > 0.025, "monster heads %s vs %s differ (%.3f)" % [MapTokens.MONSTERS[i], MapTokens.MONSTERS[j], d])

	# --- size bands
	check(MapTokens.pips_for(1) == 1 and MapTokens.pips_for(5) == 1 and MapTokens.pips_for(6) == 2 and MapTokens.pips_for(15) == 2
		and MapTokens.pips_for(16) == 3 and MapTokens.pips_for(30) == 3 and MapTokens.pips_for(31) == 4 and MapTokens.pips_for(60) == 4
		and MapTokens.pips_for(61) == 5, "size bands 1-5 / 6-15 / 16-30 / 31-60 / 61+")

	# --- night cap: token layer modulate x map tint never darker than 70%
	for tint in [Color(0.45, 0.5, 0.72), Calendar.tint(0.0), Color(1, 0.82, 0.68), Color.WHITE]:
		var m := MapTokens.night_comp(tint)
		var f := Color(m.r * tint.r, m.g * tint.g, m.b * tint.b)
		check(minf(f.r, minf(f.g, f.b)) >= 0.699, "night tint capped at 30%% (%s -> %s)" % [tint, f])

	# --- a 16-man company is one token; sync + perf on a real world
	if not _within_budget(): return fails
	Game.new_game(4242)
	if not _within_budget(): return fails
	var w: Dictionary = Game.world
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var ppos: Vector2 = w["party"]["pos"]
	# Keep every generated donor untouched; ask the native draft for sixteen actual residents.
	var large: Dictionary = NativeForces.spawn_exact(Game, "middle_kingdom", 16, "patrol", ppos + Vector2(60, 0), rng)
	check(bool(large.get("ok", false)), "sixteen-person native token fixture: " + str(large.get("reason", "")))
	if not bool(large.get("ok", false)): return fails
	var big: String = str(large["id"])
	check((w["warbands"][big]["units"] as Array).size() == 16, "native big force contains exactly sixteen real people")
	if fails > 0: return fails
	var root := Node2D.new()
	tree.root.add_child(root)
	var tokens := {}
	var player := MapToken.new()
	player.set_texture("player", MapTokens.texture("player"))
	root.add_child(player)
	MapTokens.sync(root, tokens, Game, [big], 1.0, true, player)
	check(tokens.size() == 1 and root.get_child_count() == 2, "a 16-man company yields exactly one token")
	check(tokens.has(big), "the native sixteen-person force has its token ID")
	if not tokens.has(big): root.queue_free(); return fails
	check((tokens[big] as MapToken).key == MapTokens.key("army", "middle_kingdom", 3, "neutral"), "16 men -> army, 3 pips (%s)" % tokens[big].key)
	# tap hit circle r=30 screen px around the token centre
	for z in [0.5, 1.0, 2.0]:
		MapTokens.sync(root, tokens, Game, [big], z, false, player)
		var cpos := MapTokens.center(w["warbands"][big]["pos"], z)
		check(MapTokens.pick(tokens, w["warbands"], cpos + Vector2(29.0 / z, 0), z) == big, "tap inside r30 hits at zoom %s" % z)
		check(MapTokens.pick(tokens, w["warbands"], cpos + Vector2(31.0 / z, 0), z) == "", "tap outside r30 misses at zoom %s" % z)
		check(is_equal_approx(player.scale.x * MapTokens.BOX * z, maxf(52.0 * z, 40.0)), "token size on screen at zoom %s" % z)
	# 40 forces of mixed kinds
	var kinds := [["middle_kingdom", "patrol"], ["orc_horde", "raider"], ["goblin_warren", "raider"], ["moon_court", "patrol"],
		["northern_clans", "caravan"], ["outlaws", "bandit"], ["middle_kingdom", "militia"]]
	var vis: Array = [big]
	var represented: Dictionary = {}
	# Whole native caravans/militia retain all route, crew and town-registration state.
	for kd: Array in kinds:
		if not _within_budget(): root.queue_free(); return fails
		var fixture: Dictionary = NativeForces.existing(Game, str(kd[0]), str(kd[1]), vis)
		if not bool(fixture.get("ok", false)) and str(kd[1]) == "caravan":
			fixture = _native_caravan(str(kd[0]), rng)
		if not bool(fixture.get("ok", false)) and str(kd[0]) == "outlaws" and str(kd[1]) == "bandit":
			fixture = _native_bandit(vis)
		if not bool(fixture.get("ok", false)) and str(kd[1]) in ["patrol", "raider"]:
			fixture = NativeForces.spawn_exact(Game, str(kd[0]), 2, str(kd[1]), ppos, rng)
		check(bool(fixture.get("ok", false)), "native mixed-force prerequisite: " + str(fixture.get("reason", "")))
		if not bool(fixture.get("ok", false)): root.queue_free(); return fails
		var wid: String = str(fixture["id"])
		check(wid != "" and w["warbands"].has(wid) and not vis.has(wid), "every native token fixture has a unique live force ID")
		if wid == "" or not w["warbands"].has(wid) or vis.has(wid): root.queue_free(); return fails
		vis.append(wid)
		represented[str(kd[0]) + "/" + str(kd[1])] = true
	# Fill from the native world before drafting anyone else; band sizes/identities remain untouched.
	var native_ids: Array = w["warbands"].keys()
	native_ids.sort()
	for wid: String in native_ids:
		if not _within_budget(): root.queue_free(); return fails
		if vis.size() == 40: break
		if vis.has(wid): continue
		var band: Dictionary = w["warbands"][wid]
		if str(band["kind"]) not in ["patrol", "raider", "militia", "caravan", "bandit"]: continue
		var valid: Dictionary = NativeForces.record(Game, band)
		check(bool(valid["ok"]), "native mixed force " + wid + ": " + str(valid.get("reason", "")))
		if not bool(valid["ok"]): root.queue_free(); return fails
		vis.append(wid)
	for attempt: int in 40:
		if not _within_budget(): root.queue_free(); return fails
		if vis.size() == 40: break
		var faction: String = str(kinds[attempt % 4][0])
		var kind: String = str(kinds[attempt % 4][1])
		var fixture: Dictionary = NativeForces.spawn_exact(Game, faction, 2, kind, ppos, rng)
		check(bool(fixture.get("ok", false)), "forty-force native draft prerequisite: " + str(fixture.get("reason", "")))
		if not bool(fixture.get("ok", false)): root.queue_free(); return fails
		var wid: String = str(fixture["id"])
		check(not vis.has(wid), "native fill never reuses a selected force ID")
		if vis.has(wid): root.queue_free(); return fails
		vis.append(wid)
	check(vis.size() == 40 and represented.size() == kinds.size(), "exactly forty native forces include all seven original faction/kind cases")
	check((w["warbands"][big]["units"] as Array).size() == 16, "building the mixed scene preserves the exact sixteen-person force")
	var unique_units: Dictionary = {}
	for band: Dictionary in w["warbands"].values():
		for unit: Unit in band["units"]:
			check(not unique_units.has(unit.uid), "native token fixture never duplicates a Unit across forces")
			unique_units[unit.uid] = true
	if fails > 0: root.queue_free(); return fails
	MapTokens.sync(root, tokens, Game, vis, 1.0, true, player)
	check(tokens.size() == 40, "40 tokens (%d)" % tokens.size())
	for wid: String in vis: check(tokens.has(wid), "one token for native force " + wid)
	if fails > 0: root.queue_free(); return fails
	for i in 30:
		MapTokens.sync(root, tokens, Game, vis, 1.0, false, player)
	var n := 400
	var ts := Time.get_ticks_usec()
	for i in n:
		for wid in vis:
			w["warbands"][wid]["pos"] += Vector2(0.1, 0)
		MapTokens.sync(root, tokens, Game, vis, 1.0, false, player)
	var move_us := Time.get_ticks_usec() - ts
	ts = Time.get_ticks_usec()
	for i in n:
		for wid in vis:
			w["warbands"][wid]["pos"] += Vector2(0.1, 0)
	var base_us := Time.get_ticks_usec() - ts
	var mean_ms := (move_us - base_us) / 1000.0 / n
	print("  sync of 40 tokens: %.4f ms per frame" % mean_ms)
	check(mean_ms < 0.1, "sync of 40 tokens < 0.1 ms per frame (%.4f)" % mean_ms)
	var ts2 := Time.get_ticks_usec()
	for i in 20:
		MapTokens.sync(root, tokens, Game, vis, 1.0, true, player)
	print("  refresh sync of 40 tokens: %.3f ms" % ((Time.get_ticks_usec() - ts2) / 1000.0 / 20))
	# a force leaving sight frees its token
	MapTokens.sync(root, tokens, Game, vis.slice(0, 10), 1.0, false, player)
	check(tokens.size() == 10, "tokens of forces out of sight are removed")
	root.queue_free()

	_sheets()
	return fails

## PNG sheets for review: colour on parchment, greyscale, and at true map size (52 px) on a dark map green.
func _sheets() -> void:
	var rows := []
	for fid in _factions():
		rows.append([["army", fid, 2, "neutral"], ["army", fid, 4, "allied"], ["militia", fid, 3, "neutral"],
			["caravan", fid, 2, "allied"], ["deserter", fid, 1, "hostile"]])
	rows.append([["player", "", 0, ""], ["bandit", "", 1, "hostile"], ["bandit", "", 3, "hostile"], ["army", "orc_horde", 5, "hostile"],
		["army", "goblin_warren", 2, "hostile"]])
	var mons := []
	for cid in MapTokens.MONSTERS:
		mons.append(["monster", cid, 1 + mons.size(), "hostile"])
	rows.append(mons)
	var S := MapTokens.SIZE
	var sheet := Image.create(S * 5, S * rows.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#cdbb8f"))
	var small := Image.create(70 * 5, 70 * rows.size(), false, Image.FORMAT_RGBA8)
	small.fill(Color("#4f6b3a"))
	for r in rows.size():
		for c in (rows[r] as Array).size():
			var e: Array = rows[r][c]
			var img := MapTokens.image(e[0], e[1], e[2], e[3])
			sheet.blend_rect(img, Rect2i(0, 0, S, S), Vector2i(c * S, r * S))
			var sm := img.duplicate() as Image
			var px := int(round(52.0 * 72.0 / 64.0))
			sm.resize(px, px, Image.INTERPOLATE_LANCZOS)
			small.blend_rect(sm, Rect2i(0, 0, px, px), Vector2i(c * 70 + 6, r * 70 + 4))
	sheet.save_png(OUT + "tokens_sheet.png")
	small.save_png(OUT + "tokens_52px.png")
	var grey := sheet.duplicate() as Image
	for y in grey.get_height():
		for x in grey.get_width():
			var l := grey.get_pixel(x, y).get_luminance()
			grey.set_pixel(x, y, Color(l, l, l))
	grey.save_png(OUT + "tokens_grey.png")
	print("  sheets saved to ", OUT)
