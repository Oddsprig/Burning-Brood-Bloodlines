extends RefCounted
## Small native-Variant history fixtures. No world/battle generation or long sim.
var checks: int = 0
var fails: int = 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL combat journal: ", why)

static func _participants() -> Array:
	return [{"idx": 0, "name": "Native officer", "side": 0, "unit_uid": 77},
		{"idx": 1, "name": "Different actual person", "side": 1, "unit_uid": 77},
		{"idx": 2, "name": "Actual allied troop", "side": 0, "unit_uid": 88}]

static func _entry(i: int) -> Dictionary:
	return {"tick": int(i / 4), "k": "move", "d": {"native_order": i,
		"cell": Vector2i(i % 7, i % 11), "roll": 0.123456789012345,
		"layers": [["skin", 0.25, {"kind": "cut", "bleed": 0.0125}]],
		"packed": PackedInt32Array([i, i + 1])}}

func _immutability() -> void:
	var metadata: Array = _participants()
	var journal := CombatJournal.new()
	journal.setup(metadata)
	metadata[0]["name"] = "Changed live name"
	check(journal.participant(0)["name"] == "Native officer", "participant name is frozen at Fighter.idx registration")
	check(journal.participant(0)["unit_uid"] == journal.participant(1)["unit_uid"] and journal.participant(0)["idx"] != journal.participant(1)["idx"], "same saved UID preserves distinct actual participant indices")
	var copy: Array = journal.participants()
	copy[1]["side"] = 0
	check(journal.participant(1)["side"] == 1, "participant browser receives detached metadata")
	var entry: Dictionary = _entry(0)
	var before: PackedByteArray = var_to_bytes(entry)
	check(journal.append(entry, 0, 1, "strike"), "native outcome accepted once")
	check(var_to_bytes(entry) == before, "append does not render or mutate incoming native entry")
	entry["d"]["layers"][0][2]["bleed"] = 9.0; entry["d"]["packed"][0] = 999
	var page: Array = journal.page(0)
	check(page.size() == 1 and page[0]["seq"] == 0 and page[0]["actor"] == 0 and page[0]["target"] == 1 and page[0]["event_type"] == "strike", "record retains exact native cross-links and emission ordinal")
	check(var_to_bytes(page[0]["entry"]) == before, "nested/packed changes after emission cannot rewrite frozen outcome")
	page[0]["entry"]["text"] = "UI cached text"
	page[0]["entry"]["d"]["packed"][0] = 55
	check(var_to_bytes(journal.page(0)[0]["entry"]) == before, "render/page edits cannot mutate journal active storage")
	check(journal.count() == 1 and journal.count(0) == 1 and journal.count(1) == 1 and journal.count(2) == 0, "one shared strike appears once globally and once per related participant")
	check(journal.append(_entry(1), 0, 0, "learn") and journal.count(0) == 2, "self-target outcome links participant only once")
	var ordered: Array = journal.page(0)
	check(ordered[0]["tick"] == ordered[1]["tick"] and ordered[0]["seq"] == 0 and ordered[1]["seq"] == 1, "same-tick outcomes keep native emission order")
	journal.append(_entry(2), -1, -1, "environment")
	check(journal.count() == 3 and journal.count(0) == 2 and journal.count(1) == 1, "unattributed native outcome remains global without inventing participant links")
	check(journal.page(-1).is_empty() and journal.page(100).is_empty() and journal.page(0, 999).is_empty(), "invalid and empty pages are bounded")
	journal.dispose(); journal.dispose()
	check(journal.count() == 0 and journal.page(0).is_empty() and journal.stats()["disposed"], "disposal is idempotent and releases active outcomes")
	print("Combat journal checkpoint: immutable native records complete")

func _beyond_native_caps() -> void:
	const N: int = 10000
	var journal := CombatJournal.new()
	journal.setup(_participants())
	var expected: Array = [[], [], []]
	for i in N:
		var actor: int = i % 3
		var target: int = actor if i % 5 == 0 else (actor + 1) % 3
		journal.append(_entry(i), actor, target, "strike" if i % 2 == 0 else "move")
		expected[actor].append(i)
		if target != actor: expected[target].append(i)
	var stats: Dictionary = journal.stats()
	check(stats["complete"] and stats["error"] == "" and stats["dropped"] == 0, "complete history explicitly retained beyond native8192/512 caps")
	check(journal.count() == N and stats["attempted"] == N and stats["spilled_records"] + stats["active_records"] == N, "all outcomes accounted exactly once")
	check(stats["active_records"] < CombatJournal.CHUNK_SIZE and stats["chunk_files"] == int(N / CombatJournal.CHUNK_SIZE), "active record memory is bounded by one chunk")
	check(journal.page(0, -1, 10000).size() == CombatJournal.MAX_PAGE_SIZE, "reader cannot allocate an entire fight through oversized page request")
	for seq: int in [0, N / 2, N - 1]:
		var page: Array = journal.page(int(seq / 18))
		var record: Dictionary = page[seq % 18]
		check(record["seq"] == seq and record["tick"] == int(seq / 4) and record["entry"]["d"]["native_order"] == seq, "first/middle/last native emission survives spill")
		check(record["entry"]["d"]["cell"] is Vector2i and typeof(record["entry"]["d"]["roll"]) == TYPE_FLOAT and record["entry"]["d"]["roll"] == 0.123456789012345 and record["entry"]["d"]["packed"] is PackedInt32Array, "store_var preserves native Variant types/precision")
	for participant in 3:
		check(journal.count(participant) == expected[participant].size(), "indexed exact participant count including self/target links")
		var middle: int = int(expected[participant].size() / 2)
		for ordinal: int in [0, middle, expected[participant].size() - 1]:
			var reads_before: int = int(journal.stats()["reads"])
			var page: Array = journal.page(int(ordinal / 18), participant)
			var record: Dictionary = page[ordinal % 18]
			check(record["seq"] == expected[participant][ordinal], "participant first/middle/last seeks exact chronological emission")
			check(record["actor"] == participant or record["target"] == participant, "filtered page contains only actual participant cross-links")
			check(int(journal.stats()["reads"]) - reads_before <= 2, "filtered page reads relevant chunks rather than scanning full fight")
	for chunk in [1, 4, 8, 12, 16]:
		var first: int = int(ceil(float(chunk * CombatJournal.CHUNK_SIZE) / 18.0))
		journal.page(first)
		check(journal.stats()["cached_chunks"] <= CombatJournal.CACHE_CHUNKS, "LRU remains bounded across distant pages")
	var fresh: Array = journal.page(1)
	var before: PackedByteArray = var_to_bytes(fresh)
	var reads_before: int = int(journal.stats()["reads"])
	fresh[0]["entry"]["d"]["layers"][0][2]["kind"] = "changed cached display"
	check(var_to_bytes(journal.page(1)) == before and int(journal.stats()["reads"]) == reads_before, "cached chunks still return detached immutable page views")
	stats = journal.stats()
	check(stats["cached_records"] <= CombatJournal.CACHE_CHUNKS * CombatJournal.CHUNK_SIZE and stats["open_index_files"] <= 3, "record cache and participant handle ownership stay bounded")
	check(stats["index_bytes"] > 0 and stats["disk_bytes"] == stats["index_bytes"] + stats["stored_bytes"], "byte receipts include history plus on-disk participant indexes")
	var prefix_links: int = 0
	for idx in 3:
		for seq in expected[idx]:
			if seq < int(stats["spilled_records"]): prefix_links += 1
	check(stats["index_bytes"] == prefix_links * 8, "indexes use exactly one64-bit link per actual related participant")
	var directory: String = str(stats["directory"])
	check(directory.begins_with(CombatJournal.PRIVATE_ROOT + "/") and not directory.contains(".."), "journal files are private transient battle ownership")
	journal.dispose()
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)) and journal.stats()["open_index_files"] == 0 and journal.stats()["cached_records"] == 0, "disposal closes indexes and deletes only owned temporary chunks")
	print("Combat journal checkpoint:10000 outcomes/indexed pages complete")

func _failure_tail() -> void:
	var journal := CombatJournal.new()
	journal.setup(_participants())
	var directory: String = str(journal.stats()["directory"])
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CombatJournal.PRIVATE_ROOT)) == OK, "private failure parent exists")
	var blocker: FileAccess = FileAccess.open(directory, FileAccess.WRITE)
	check(blocker != null, "create deterministic private path blocker")
	if blocker == null:
		journal.dispose()
		return
	blocker.store_string("separately owned test sentinel"); blocker.close()
	for i in 600: journal.append(_entry(i), 0, 1, "strike")
	var stats: Dictionary = journal.stats()
	check(not stats["complete"] and not str(stats["error"]).is_empty(), "storage failure is explicit and never claims full history")
	check(stats["attempted"] == 600 and journal.count() == CombatJournal.CHUNK_SIZE and stats["dropped"] == 600 - CombatJournal.CHUNK_SIZE, "failed storage retains bounded latest outcomes with exact loss count")
	check(journal.page(0)[0]["seq"] == 600 - CombatJournal.CHUNK_SIZE, "failure tail starts at actual surviving emission, exposing sequence gap")
	var last_page: Array = journal.page(int((journal.count() - 1) / 18))
	check(last_page[-1]["seq"] == 599 and journal.count(0) == CombatJournal.CHUNK_SIZE and journal.count(1) == CombatJournal.CHUNK_SIZE, "current failure outcomes and cross-links remain readable")
	journal.dispose()
	check(FileAccess.get_file_as_string(directory) == "separately owned test sentinel", "disposal cannot delete an unrelated blocking file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	print("Combat journal checkpoint: explicit write failure/recent tail complete")

func _read_failure_and_objects() -> void:
	var journal := CombatJournal.new()
	journal.setup(_participants())
	for i in 530: journal.append(_entry(i), 0, 1)
	var directory: String = str(journal.stats()["directory"])
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(directory + "/chunk_00000000.bin")) == OK, "remove one private chunk to exercise read failure")
	check(journal.page(0).is_empty() and not journal.stats()["complete"] and not str(journal.stats()["error"]).is_empty(), "missing file cannot yield fabricated complete history")
	check(journal.count() == 18 and journal.count(0) == 18 and journal.page(0)[0]["seq"] == 512 and journal.stats()["dropped"] == 512, "read failure conservatively exposes only known readable tail/count")
	journal.dispose()
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)), "read failure still releases surviving chunks/indexes")
	var invalid := CombatJournal.new()
	invalid.setup(_participants())
	var u := Unit.new()
	var reference: WeakRef = weakref(u)
	var entry: Dictionary = {"tick": 1, "k": "fixture", "d": {"forbidden_native_backref": u}}
	check(not invalid.append(entry, 0, 1) and not invalid.stats()["complete"] and invalid.stats()["dropped"] == 1, "Object payload is rejected visibly before store_var")
	entry.clear(); u = null
	check(reference.get_ref() == null, "journal retains no rejected Unit or simulation ownership")
	invalid.append(_entry(2), 2, -1)
	check(invalid.count() == 1 and invalid.count(2) == 1 and not invalid.stats()["complete"], "valid current outcomes stay available after an explicit capture failure")
	invalid.dispose()
	var automatic := CombatJournal.new()
	automatic.setup(_participants())
	for i in CombatJournal.CHUNK_SIZE: automatic.append(_entry(i), 0, 1)
	var automatic_directory: String = str(automatic.stats()["directory"])
	var weak: WeakRef = weakref(automatic)
	automatic = null
	check(weak.get_ref() == null and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(automatic_directory)), "last RefCounted owner releases private history without a persistent archive")
	print("Combat journal checkpoint: read/capture failure/ownership complete")

static func _old_freeze(value: Variant) -> Variant:
	# Frozen original recursive copy for an independent exact native-Variant check.
	if value is Dictionary:
		var out: Dictionary = value.duplicate()
		for key in value: out[_old_freeze(key)] = _old_freeze(value[key])
		return out
	if value is Array:
		var out: Array = value.duplicate()
		for i in value.size(): out[i] = _old_freeze(value[i])
		return out
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY: return value.duplicate()
	return value

func _copy_and_buffered_indexes() -> void:
	var journal := CombatJournal.new()
	journal.setup(_participants())
	var typed: Dictionary[String, int] = {"first": 7, "second": 9}
	var entry: Dictionary = _entry(0)
	entry["d"]["typed"] = typed
	entry["d"]["packed_nested"] = [PackedByteArray([1, 2, 3]), {"names": PackedStringArray(["original", "frozen"]),
		"vectors": PackedVector2Array([Vector2(1.25, 2.5)])}]
	for i in 48: entry["d"]["scalar_%d" % i] = i if i % 2 == 0 else float(i) / 7.0
	var expected: PackedByteArray = var_to_bytes(_old_freeze(entry))
	journal.append(entry, 0, 1)
	entry["d"]["typed"]["first"] = 99
	entry["d"]["packed_nested"][0][0] = 99
	entry["d"]["packed_nested"][1]["names"][0] = "changed"
	entry["d"]["packed_nested"][1]["vectors"][0] = Vector2(9, 9)
	check(var_to_bytes(journal.page(0)[0]["entry"]) == expected, "native deep-copy optimization matches frozen linear copy including typed/packed Variant values")
	for i in range(1, 1024): journal.append(_entry(i), 0, 1)
	var stats: Dictionary = journal.stats()
	check(stats["writes"] == 4 and stats["index_flushes"] == 0 and stats["buffered_indexes"] == 2, "four spills buffer touched participant indexes without per-chunk flushes")
	journal.page(0)
	check(journal.stats()["index_flushes"] == 0, "global chronology reads do not flush unrelated participant indexes")
	var filtered: Array = journal.page(0, 0)
	check(filtered.size() == 18 and filtered[0]["seq"] == 0 and filtered[-1]["seq"] == 17, "selected buffered index flushes before exact direct sequence read")
	check(journal.stats()["index_flushes"] == 1 and journal.stats()["buffered_indexes"] == 1, "only the selected participant writer flushes")
	check(var_to_bytes(filtered[0]["entry"]) == expected, "disk spill keeps original frozen typed/packed data")
	filtered[0]["entry"]["d"]["packed_nested"][0][0] = 55
	check(var_to_bytes(journal.page(0, 0)[0]["entry"]) == expected and journal.stats()["index_flushes"] == 1, "cached detached pages and clean index reads do not mutate or reflush storage")
	for i in range(1024, 1280): journal.append(_entry(i), 0, 1)
	journal.page(1, 0)
	check(journal.stats()["index_flushes"] == 2 and journal.stats()["buffered_indexes"] == 1 and journal.count(0) == 1280, "later spill dirties selected index once while preserving prefix sequences/count")
	var directory: String = str(journal.stats()["directory"])
	journal.dispose()
	check(journal.stats()["index_flushes"] == 3 and journal.stats()["buffered_indexes"] == 0 and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)), "explicit disposal flushes/checks remaining owned writers then deletes private files")
	print("Combat journal checkpoint: exact native copy/buffered indexes complete")

func run(_tree: SceneTree) -> int:
	var rng_before: int = Game.rng.state
	var unit_before: int = Unit._next_uid
	var item_before: int = Item._next_uid
	var gold_before: int = Game.gold
	var save_before: String = Game.SAVE_PATH
	_immutability()
	_beyond_native_caps()
	_failure_tail()
	_read_failure_and_objects()
	_copy_and_buffered_indexes()
	check(Game.rng.state == rng_before and Unit._next_uid == unit_before and Item._next_uid == item_before and Game.gold == gold_before and Game.SAVE_PATH == save_before, "journal draws no RNG, creates no identities/coins and never touches player saves")
	print("Combat journal v016: ", checks, " assertions; failures=", fails)
	return fails
