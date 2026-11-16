extends RefCounted
## v0.100: a real v0.099 save, not a current save with its version field changed.
## Generate the required fixture with gen_v099_save.gd on the pinned v0.099 checkout.
## Test brief: headless, fixture-only (no generation or simulated days), 170 s watchdog.
## "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief."
## "A test failure stops all further tests. No other test runs until that one failing test is fixed and passes."

const FIXTURE := "res://tests/fixtures/legacy_v099_save.json"
const ROOT_PREFIX := '{"version":1,'
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL v099 save compat: ", why)

func _sequence(value: Variant) -> bool:
	return value is Array or (typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) <= TYPE_PACKED_VECTOR4_ARRAY)

# Compare every selected field, allowing only JSON's int/float and packed/Array type differences.
# Current format can add fields inside old unit/dragon records without dropping their old fields.
func _difference(before: Variant, after: Variant, path: String, include_added: bool = false) -> String:
	# v0.100: report every differing path, so the first repaired Academy cannot hide later damage.
	var differences: PackedStringArray = PackedStringArray()
	if before is Dictionary:
		if not (after is Dictionary): return path + " is no longer a dictionary"
		for key in before:
			var here: String = path + "/" + str(key)
			if not after.has(key):
				differences.append(here + " is missing")
				continue
			var diff: String = _difference(before[key], after[key], here, include_added)
			if diff != "": differences.append(diff)
		if include_added:
			for key in after:
				if not before.has(key): differences.append(path + "/" + str(key) + " was added")
		return "\n".join(differences)
	if _sequence(before):
		if not _sequence(after): return path + " is no longer a sequence"
		if before.size() != after.size(): differences.append(path + " count differs")
		var common: int = mini(before.size(), after.size())
		for i in common:
			var diff: String = _difference(before[i], after[i], path + "/" + str(i), include_added)
			if diff != "": differences.append(diff)
		if include_added:
			for i in range(common, before.size()): differences.append(path + "/" + str(i) + " is missing")
			for i in range(common, after.size()): differences.append(path + "/" + str(i) + " was added")
		return "\n".join(differences)
	var before_number := typeof(before) == TYPE_INT or typeof(before) == TYPE_FLOAT
	var after_number := typeof(after) == TYPE_INT or typeof(after) == TYPE_FLOAT
	if before_number and after_number:
		if before == after: return ""
	elif typeof(before) == typeof(after) and before == after:
		return ""
	return "%s changed (%s -> %s)" % [path, str(before).left(80), str(after).left(80)]

# v0.100: ignore dictionary order only; retain every key, native type, array position and float bit.
func _native_difference(before: Variant, after: Variant, path: String) -> String:
	if typeof(before) != typeof(after): return path + " native type differs"
	if before is Dictionary:
		if before.size() != after.size() or not before.is_same_typed(after): return path + " dictionary shape differs"
		var after_keys := {}
		for key in after: after_keys[var_to_bytes(key).hex_encode()] = key
		for key in before:
			var encoded_key := var_to_bytes(key).hex_encode()
			var here := path + "/" + str(key)
			if not after_keys.has(encoded_key): return here + " native key is missing"
			var diff := _native_difference(before[key], after[after_keys[encoded_key]], here)
			if diff != "": return diff
		return ""
	if before is Array:
		if before.size() != after.size() or not before.is_same_typed(after): return path + " array shape differs"
		for i in before.size():
			var diff := _native_difference(before[i], after[i], path + "/" + str(i))
			if diff != "": return diff
		return ""
	return "" if var_to_bytes(before) == var_to_bytes(after) else path + " native value differs"

func _key_state(data: Dictionary, legacy_academies: bool = false) -> Dictionary:
	var world: Dictionary = data.get("world", {})
	var towns := {}
	var families := 0
	var ids: Array = world.get("towns", {}).keys()
	ids.sort()
	for tid in ids:
		var town: Dictionary = world["towns"][tid]
		var econ: Dictionary = town.get("econ", {})
		var family_ids: Array = []
		# v0.100: preserve each household's purse, so transfers cannot hide behind a town total.
		var family_purses := {}
		for family: Dictionary in econ.get("fams", []):
			family_ids.append(int(family["id"]))
			family_purses[int(family["id"])] = family.get("purse")
		family_ids.sort()
		# v0.100: other business fields may be repaired; identities/types/owners must survive.
		var biz_ids: Array = []
		for biz: Dictionary in econ.get("biz", []):
			var owner: int = int(biz["owner"])
			# v0.100: translate only the designated Academy's documented public-ownership repair.
			# Academy._state_owner removes the v0.099 generation pass's private operator.
			if legacy_academies and String(biz["type"]) == "academy" and int(biz["id"]) == int(econ.get("academy", -1)):
				owner = -1
			biz_ids.append([int(biz["id"]), String(biz["type"]), owner])
		biz_ids.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
		families += family_ids.size()
		towns[tid] = {"name": town.get("name"), "faction": town.get("faction"), "pos": town.get("pos"),
			"size": town.get("size"), "wealth": town.get("wealth"), "population": econ.get("pop"),
			"stock": econ.get("stock", {}).duplicate(true), "family_ids": family_ids,
			"biz": biz_ids, "academy": int(econ.get("academy", -1)),
			"treasury": econ.get("treasury"), "family_purses": family_purses}
	var dragon_records: Dictionary = world.get("dragons", {}).get("records", {})
	var dragon_ids: Array = dragon_records.keys()
	dragon_ids.sort()
	return {"gold": data.get("gold"), "day": data.get("day"), "seed": data.get("seed"),
		"location": data.get("location"), "company": data.get("company", []).duplicate(true),
		"player_house": world.get("player_house", {}).duplicate(true), "town_ids": ids, "towns": towns,
		"families_count": families, "dragon_ids": dragon_ids, "dragons": dragon_records.duplicate(true)}

# v0.100: retain every original business field for diagnostics, beyond the preservation triples.
func _business_state(data: Dictionary) -> Dictionary:
	var businesses: Dictionary = {}
	for tid in data.get("world", {}).get("towns", {}):
		var town: Dictionary = data["world"]["towns"][tid]
		businesses[tid] = {"econ": {"biz": town.get("econ", {}).get("biz", []).duplicate(true)}}
	return businesses

func _write_source(text: String) -> bool:
	Game.wait_save()
	var file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	check(file != null, "open the private working save, never the fixture: " + str(FileAccess.get_open_error()))
	if file == null: return false
	file.store_string(text)
	var error := file.get_error()
	file.close()
	check(error == OK, "write the private working save: " + str(error))
	return error == OK

func _load_clean(counter, label: String) -> bool:
	var errors_before: int = counter.total()
	var loaded: bool = Game.load_game()
	check(loaded, label + " loads successfully")
	check(int(counter.total()) == errors_before, label + " loads without script errors")
	return loaded and fails == 0

func _legacy_state(expected: Dictionary, legacy_businesses: Dictionary, label: String) -> void:
	# These fields are JSON floats/Arrays in the REAL old file. _deserialize does not
	# repair them; CampaignWorld.after_load -> TownEcon.after_load does. Do not call
	# Plots._p here: that would repair a broken load and hide a skipped migration.
	check(typeof(Game.world.get("next_id")) == TYPE_INT, label + " ran the legacy world integer migration")
	var bad_economy := ""
	var bad_types := ""
	for tid in Game.world.get("towns", {}):
		var town: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(town):
			bad_economy = str(tid) + " has no economy"
			break
		var econ: Dictionary = town["econ"]
		if (econ.get("fams", []) as Array).is_empty() or not (econ.get("stock") is Dictionary):
			bad_economy = str(tid) + " lacks families or market stock"
			break
		if typeof(town.get("size")) != TYPE_INT or typeof(econ.get("pop")) != TYPE_INT \
				or not (econ.get("plots", {}).get("x") is PackedInt32Array):
			bad_types = str(tid) + " has unconverted native economy fields"
			break
	check(bad_economy == "", label + " preserves every town economy: " + bad_economy)
	check(bad_types == "", label + " ran the town/plot migrations: " + bad_types)
	if fails > 0: return
	var saved: Dictionary = Game._save_tree()
	var actual: Dictionary = _key_state(saved) # v0.100: never normalize the actual loaded owner.
	var diff: String = _difference(expected, actual, label)
	check(diff == "", "gold/day/company/towns/families/dragons preserved: " + diff)
	# v0.100: prove the translated value and cleanup, rather than merely ignoring Academy owners.
	for tid in expected["towns"]:
		var academy_id: int = int(expected["towns"][tid]["academy"])
		if academy_id < 0: continue
		var econ: Dictionary = saved.get("world", {}).get("towns", {}).get(tid, {}).get("econ", {})
		var businesses: Array = econ.get("biz", [])
		var here: String = label + "/towns/" + str(tid) + "/biz/" + str(academy_id)
		check(academy_id < businesses.size(), here + " retains its designated Academy row")
		if academy_id >= businesses.size(): continue
		var academy: Dictionary = businesses[academy_id]
		check(int(academy.get("id", -1)) == academy_id and String(academy.get("type", "")) == "academy"
			and int(academy.get("owner", -2)) == -1 and int(academy.get("kw", -1)) == 0
			and String(academy.get("public_funding", "")) == "realm" and academy.get("for_sale") == false,
			here + " migrates to public ownership, realm funding and no private keeper or sale")
		var private_refs: int = 0
		for family: Dictionary in econ.get("fams", []):
			for key: String in ["owns", "keeps"]:
				for bid: Variant in family.get(key, []):
					if int(bid) == academy_id: private_refs += 1
		check(private_refs == 0, here + " is absent from every household's ownership and keeper lists")
	if label == "original schema 1" or fails > 0:
		var business_diff: String = _difference(legacy_businesses, _business_state(saved), label + "/world/towns", true)
		if business_diff != "": print("v0.100: ALL legacy business-field differences (including documented repairs):\n", business_diff)

func _round_trip(counter) -> void:
	# After the one legacy migration, compare the ENTIRE native snapshot, including
	# typed/packed data, float bits, RNG, UID counters, raid state and economy totals.
	var native_before := var_to_bytes(Game._save_tree())
	check(Game.save_game(), "write the migrated campaign through the real v0.100 writer")
	if fails > 0: return
	var disk_before := FileAccess.get_file_as_string(Game.SAVE_PATH)
	var written = JSON.parse_string(disk_before)
	check(written is Dictionary, "migrated save is JSON")
	if not (written is Dictionary): return
	check(int(written.get("version", -1)) == 2 and written.has("__types"), "v0.100 writer upgrades the actual old save to schema 2")
	if fails > 0: return
	Game.restore_exact(written) # v0.100: compare decoded values rather than JSON key order or float markers.
	Game.world = {}
	Game.company = []
	Game.stash = []
	Game.contract = {}
	if not _load_clean(counter, "schema-2 round-trip"): return
	check(var_to_bytes(Game._save_tree()) == native_before, "second save/load is lossless for the entire native state")
	if fails > 0: return
	check(Game.save_game(), "save the round-tripped campaign again")
	if fails > 0: return
	var written_again = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	check(written_again is Dictionary, "second schema-2 write is JSON")
	if not (written_again is Dictionary): return
	check(int(written_again.get("version", -1)) == 2 and written_again.has("__types"), "second schema-2 write retains its schema and native types")
	Game.restore_exact(written_again)
	var diff := _native_difference(written, written_again, "second schema-2 write")
	check(diff == "", "second schema-2 write is losslessly equivalent: " + diff)

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	if not FileAccess.file_exists(FIXTURE):
		check(false, "MISSING REAL v0.099 FIXTURE: " + FIXTURE + "; run gen_v099_save.gd on source 1fcb3fe758ad3a566cbb6b4466b25706fc3cd1d0 and copy its native save here")
		return fails
	var text := FileAccess.get_file_as_string(FIXTURE)
	var source = JSON.parse_string(text)
	check(source is Dictionary, "real v0.099 fixture parses as a JSON object")
	if not (source is Dictionary): return fails
	check(text.begins_with(ROOT_PREFIX) and int(source.get("version", -1)) == 1,
		"fixture is the unchanged v0.099 writer output with its original root version 1")
	check(not source.has("__types") and not source.has("raid_state"), "fixture predates the v0.100 native-type/raid sidecars")
	Game.restore_exact(source) # v0.099 __fx corrections, before constructing expected values.
	check(typeof(source.get("world", {}).get("next_id")) == TYPE_FLOAT,
		"old world integer fields genuinely require migration")
	var expected: Dictionary = _key_state(source, true)
	var legacy_businesses: Dictionary = _business_state(source)
	check(float(expected.get("day", 0.0)) >= 2.0 and int(expected.get("gold", 0)) > 0,
		"fixture is a played day-2+ campaign with a positive purse")
	check(not (expected["company"] as Array).is_empty() and not (expected["player_house"] as Dictionary).is_empty(),
		"fixture has a selected household and an actually mustered company")
	check(not (expected["towns"] as Dictionary).is_empty() and int(expected["families_count"]) > 0
		and not (expected["dragons"] as Dictionary).is_empty(), "fixture has real towns, families and dragons")
	source = null
	if fails > 0: return fails
	var runner := tree.root.get_node_or_null("Runner")
	var counter = runner.get("script_errors") if runner != null else null
	check(counter != null and counter.has_method("total"), "run through the existing script-error-counting test runner")
	if fails > 0: return fails
	Game.wait_save()
	Game.SAVE_PATH = "user://test_v099_compat_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	# First load the golden bytes unedited. Additional cases change ONLY the root
	# stamp's prefix, retaining the real v0.099 payload and every __fx correction.
	for stamp in [1, null, 0, -1]:
		await tree.process_frame # Let the existing watchdog run between bounded load phases.
		check(Time.get_ticks_msec() - started < 160000, "compatibility check remains within its 160 s budget")
		if fails > 0: return fails
		var label := "original schema 1" if stamp == 1 else ("missing schema" if stamp == null else "old schema " + str(stamp))
		var candidate := text
		if stamp == null: candidate = "{" + text.substr(ROOT_PREFIX.length())
		elif stamp != 1: candidate = ('{"version":%d,' % int(stamp)) + text.substr(ROOT_PREFIX.length())
		if not _write_source(candidate) or not _load_clean(counter, label): return fails
		_legacy_state(expected, legacy_businesses, label)
		if fails > 0: return fails
		if stamp == 1:
			_round_trip(counter)
			if fails > 0: return fails
	print("v0.100: real v0.099 compatibility: %d checks, %d failures" % [checks, fails])
	return fails
