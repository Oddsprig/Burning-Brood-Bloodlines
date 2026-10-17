extends RefCounted
## Small real native objects; no world generation, saves, assets or rendering.
var checks: int = 0
var fails: int = 0

class Fixture extends RefCounted:
	var company: Array = []
	var world: Dictionary = {}
	var pending_battle: Dictionary = {}
	var last_result: Dictionary = {}
	var _deploy_cache: Array = []

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL memory owners: ", why)

static func _fixture() -> Fixture:
	var fixture := Fixture.new()
	# new(), not factory/create(): no registered IDs, people, stock or RNG consumed.
	var unit := Unit.new()
	var body := BodyState.new()
	var item := Item.new()
	unit.body = body
	unit.equip = {"main_hand": item}
	body.parts = {"arm_r": {"severed": false, "layers": [
		{"tissue": "skin", "dmg": 0.2, "kind": "cut"}, {"tissue": "muscle", "dmg": 0.1, "kind": "bruised"}]}}
	fixture.company = [unit, unit]
	fixture.world = {"unit": unit, "item": item, "body": body}
	fixture.pending_battle = {"unit": unit}
	fixture.last_result = {"item": item, "body": body}
	fixture._deploy_cache = [unit]
	return fixture

static func _plain(value: Variant) -> bool:
	if typeof(value) <= TYPE_STRING: return true
	if value is Dictionary:
		for key: Variant in value:
			if not _plain(key) or not _plain(value[key]): return false
		return true
	if value is Array:
		for child: Variant in value:
			if not _plain(child): return false
		return true
	return false

static func _released_probe() -> Dictionary:
	var fixture: Fixture = _fixture()
	var unit: Unit = fixture.company[0]
	return {"fixture": weakref(fixture), "unit": weakref(unit), "body": weakref(unit.body),
		"item": weakref(unit.equip["main_hand"]), "result": MemoryOwners.capture(fixture, "Release proof", 250000, 200000)}

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var rng_before: int = Game.rng.state
	var unit_ids_before: int = Unit._next_uid
	var item_ids_before: int = Item._next_uid
	var gold_before: int = Game.gold
	var day_before: float = Game.day
	var company_before: Array = Game.company
	var world_before: Dictionary = Game.world
	var fixture: Fixture = _fixture()
	var unit: Unit = fixture.company[0]
	var body: BodyState = unit.body
	var item: Item = unit.equip["main_hand"]
	var wounds_before: Dictionary = body.parts.duplicate(true)
	var scan: Dictionary = MemoryOwners.capture(fixture, "Shared native owners", 250000, 200000)
	check(bool(scan["available"]) and not bool(scan["truncated"]) and not bool(scan["depth_limited"]), "small native ownership checkpoint is complete")
	var totals: Dictionary = scan["totals"]
	for kind: String in ["unit", "body", "item"]:
		check(int(totals[kind + "_unique"]) == 1, "one unique global " + kind + " despite shared owners")
	check(int(totals["unit_refs"]) == 5, "five encountered Unit references across five roots")
	check(int(totals["body_refs"]) == 6 and int(totals["item_refs"]) == 6, "native children expand once per root; direct shared body/item edges remain counted")
	var roots: Dictionary = scan["by_root"]
	check(int(roots["company"]["unit_refs"]) == 2 and int(roots["company"]["unit_unique"]) == 1, "company distinguishes duplicate occurrences and one native object")
	check(int(roots["world"]["body_refs"]) == 2 and int(roots["world"]["item_refs"]) == 2, "world counts direct and Unit-held native references")
	check(int(roots["last_result"]["unit_unique"]) == 0 and int(roots["last_result"]["item_unique"]) == 1, "aftermath ownership is measured independently")
	check(int(roots["deploy_cache"]["unit_unique"]) == 1 and int(roots["pending_battle"]["unit_unique"]) == 1, "deployment and pending battle are explicit owner roots")
	check(int(totals["wound_parts"]) == 1 and int(totals["wound_layers"]) == 2, "sparse wounds counted once globally, not five full anatomies")
	check(body.parts == wounds_before and unit.body == body and unit.equip["main_hand"] == item, "scan leaves native wounds and equipment references unchanged")
	check(_plain(scan), "checkpoint result recursively contains only plain values")
	check(String(scan["scope"]).contains("occurrences") and String(scan["caches"]["scope"]).contains("not unique buffers"), "shared storage semantics are explicit occurrence estimates")

	var packed_fixture := Fixture.new()
	var shared := PackedByteArray([1, 2, 3, 4, 5, 6, 7])
	packed_fixture.world = {"first": shared, "alias": shared, "ints": PackedInt32Array([1, 2, 3]), "nested": {"list": [1, 2]}}
	var packed_scan: Dictionary = MemoryOwners.capture(packed_fixture, "Packed occurrences", 250000, 200000)
	var packed: Dictionary = packed_scan["totals"]
	check(not bool(packed_scan["truncated"]), "packed/container fixture completes")
	check(int(packed["dictionaries"]) == 4 and int(packed["arrays"]) == 3, "root and nested containers counted as traversal occurrences")
	check(int(packed["container_entries"]) == 7, "seven entries across declared containers")
	check(int(packed["packed_arrays"]) == 3 and int(packed["packed_elements"]) == 17, "aliased packed buffer counts as two references")
	check(int(packed["packed_numeric_bytes"]) == 26, "packed estimate is 7+7+3*4, not unique storage")
	check(int(packed["unit_unique"]) == 0 and int(packed["body_unique"]) == 0 and int(packed["item_unique"]) == 0, "plain packed fixture creates no native people/items")
	check(packed_fixture.world["first"] == shared and packed_fixture.world["alias"] == shared, "packed contents stay unchanged")

	var limited: Dictionary = MemoryOwners.capture(fixture, "Value cap", 1, 200000)
	check(bool(limited["truncated"]) and int(limited["visited"]) <= 2, "value cap terminates and flags a partial scan")
	check(int(limited["limits"]["values"]) == 1, "reported cap matches actual bound")
	var clamped: Dictionary = MemoryOwners.capture(null, "No owner", -1, -1)
	check(not bool(clamped["available"]) and int(clamped["visited"]) == 0, "absent owner yields explicit unavailable sample")
	check(int(clamped["limits"]["values"]) == 1 and int(clamped["limits"]["us"]) == 100, "invalid scan budgets clamp to declared minima")
	# Force an already expired deadline; no timing-speed assertion or FPS claim.
	var expired_counts: Dictionary = MemoryOwners._counts()
	var expired: Dictionary = {"start": Time.get_ticks_usec() - 1000, "max_values": 1000, "max_us": 100,
		"visited": 0, "truncated": false, "depth_limited": false, "global_ids": {}, "root_ids": {}, "total": MemoryOwners._counts()}
	MemoryOwners._walk(unit, expired_counts, expired, 0)
	check(bool(expired["truncated"]) and int(expired["visited"]) == 1, "expired time deadline stops before native traversal")
	check(int(expired_counts["unit_refs"]) == 0, "time cap does not inspect native object after expiry")
	var deep_fixture := Fixture.new()
	var nested: Array = [1]
	for _i in MemoryOwners.MAX_DEPTH + 4: nested = [nested]
	deep_fixture.world = {"deep": nested}
	var deep: Dictionary = MemoryOwners.capture(deep_fixture, "Depth bound", 250000, 200000)
	check(bool(deep["depth_limited"]) and not bool(deep["truncated"]), "depth guard is separate from time/value truncation")
	check(int(deep["visited"]) < 100, "deep container traversal has a hard depth bound")

	var tracker := PerformanceTracker.new()
	tree.root.add_child(tracker)
	tracker.set_process(false)
	var checkpoint: Dictionary = tracker.refresh_owners(fixture, "Cached purity", 250000, 200000)
	var first: Dictionary = tracker.snapshot()
	var before_stamp: int = int(first["ownership"]["captured_us"])
	var before_visits: int = int(first["ownership"]["visited"])
	var extra := Unit.new()
	fixture.company.append(extra)
	for _i in 5:
		var cached: Dictionary = tracker.snapshot()
		check(int(cached["ownership"]["captured_us"]) == before_stamp and int(cached["ownership"]["visited"]) == before_visits, "snapshot reads cached scan, not changed native world")
		check(int(cached["ownership"]["totals"]["unit_unique"]) == 1, "cached owner totals remain unchanged until explicit refresh")
	first["ownership"]["totals"]["unit_unique"] = 999
	check(int(tracker.snapshot()["ownership"]["totals"]["unit_unique"]) == 1, "snapshot copy cannot corrupt cached diagnostic counts")
	checkpoint["totals"]["item_unique"] = 999
	check(int(tracker.snapshot()["ownership"]["totals"]["item_unique"]) == 1, "refresh return copy cannot mutate retained checkpoint")
	var refreshed: Dictionary = tracker.refresh_owners(fixture, "Explicit refresh", 250000, 200000)
	check(int(refreshed["totals"]["unit_unique"]) == 2, "explicit refresh observes actual changed owner graph")
	tracker.record_process_memory(-1, -1)
	var unavailable: Dictionary = tracker.snapshot()["process_memory"]
	check(unavailable["private_bytes"] == null and unavailable["working_bytes"] == null, "unmeasured OS memory stays unavailable, not zero/inferred")
	tracker.record_process_memory(1000, 2000)
	check(int(tracker.snapshot()["process_memory"]["private_bytes"]) == 1000 and int(tracker.snapshot()["process_memory"]["working_bytes"]) == 2000, "OS private and working samples stay separate")
	tracker.record_terrain_owners({"chunks": 2, "packed_bytes": 1234, "vertices": 99, "unexpected": unit, "mounted": true})
	var terrain: Dictionary = tracker.snapshot()["ownership"]["terrain"]
	check(int(terrain["chunks"]) == 2 and int(terrain["packed_bytes"]) == 1234 and not terrain.has("unexpected"), "terrain telemetry stores whitelisted counters only")
	tracker.record_terrain_owners({"chunks": unit})
	check(tracker.snapshot()["ownership"]["terrain"].is_empty(), "terrain whitelist cannot retain an Object even under a valid key")
	tracker.free()

	var released: Dictionary = _released_probe()
	for kind: String in ["fixture", "unit", "body", "item"]:
		check((released[kind] as WeakRef).get_ref() == null, "capture retains no strong " + kind + " reference")
	check(_plain(released["result"]), "released source still has a readable plain result")
	check(Game.rng.state == rng_before and Unit._next_uid == unit_ids_before and Item._next_uid == item_ids_before, "no RNG or registered Unit/Item identity mutation")
	check(Game.gold == gold_before and Game.day == day_before and is_same(Game.company, company_before) and is_same(Game.world, world_before), "live campaign accounts/time/root references untouched")
	print("Memory ownership v012: ", checks, " assertions; failures=", fails)
	return fails
