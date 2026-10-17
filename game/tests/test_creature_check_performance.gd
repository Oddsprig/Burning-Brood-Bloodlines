extends RefCounted
## Frozen native scan oracle and bounded lookup counts; no generation or bodies.
var checks := 0
var fails := 0

class CountedUnit extends Unit:
	var race_reads := 0
	func race_def() -> Dictionary:
		race_reads += 1
		return super.race_def()

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL creature check: " + why)

func old_scan(units: Array) -> bool:
	# Frozen pre-optimization implementation, including unknown-race fallback.
	for u in units:
		if u is Unit and u.race_def().get("creature", false): return true
	return false

func compare(units: Array, expected: bool, why: String) -> void:
	var before: bool = old_scan(units)
	var after: bool = Monsters.creature_units(units)
	check(before == expected and after == before, why)

func run(_tree: SceneTree) -> int:
	var next_unit: int = Unit._next_uid
	var next_item: int = Item._next_uid
	var rng_state: int = Game.rng.state
	var world: Dictionary = Game.world
	var human := CountedUnit.new(); human.race = "human"; human.uid = 101
	var orc := CountedUnit.new(); orc.race = "orc"; orc.uid = 102
	var goblin := CountedUnit.new(); goblin.race = "goblin"; goblin.uid = 103
	var wolf := CountedUnit.new(); wolf.race = "wolf"; wolf.uid = 104
	check(not bool(human.race_def().get("creature", false)) and bool(wolf.race_def().get("creature", false)), "actual loaded human and wolf definitions classify differently")
	compare([], false, "empty roster")
	compare([null, false, 42, "wolf", {"race": "wolf"}, []], false, "non-Unit slots are ignored")
	compare([human, orc, goblin], false, "ordinary human/orc/goblin soldiers remain enabled")
	compare([wolf], true, "native creature Unit is classified")
	compare([null, human, {"race": "wolf"}, orc, wolf, goblin], true, "mixed roster finds a real creature")
	compare([wolf, human, wolf], true, "early creature and repeated references")
	var rows: Array = [human, human]
	compare(rows, false, "initial reused-object roster")
	human.race = "wolf"
	compare(rows, true, "same Unit's race transformation is visible immediately")
	human.race = "human"
	compare(rows, false, "same Unit's restoration is visible immediately")
	rows[1] = wolf
	compare(rows, true, "array slot replacement is not persistently cached")
	rows[1] = orc
	compare(rows, false, "replacement back to ordinary unit")
	rows.append(wolf)
	compare(rows, true, "array growth finds appended creature")
	rows.pop_back()
	compare(rows, false, "array shrink removes creature classification")
	human.race = "unknown-test-race"
	check(human.race_def() == DB.races["human"], "unknown native race falls back to human")
	compare([human, human, null, orc], false, "unknown race retains inherited human fallback")
	human.race = "human"
	var band: Dictionary = {"kind": "patrol", "faction": "middle_kingdom", "units": rows}
	check(not Monsters.campaign_creatures_enabled(), "temporary campaign creature suspension remains in force")
	check(not Monsters.suspended_band(band), "ordinary patrol is still active")
	rows.append(wolf)
	check(Monsters.suspended_band(band), "same band's live roster growth suspends its creature")
	rows.pop_back()
	check(not Monsters.suspended_band(band), "same band's restored native roster is active")
	check(Monsters.suspended_band({"kind": "beasts", "faction": "middle_kingdom", "units": []}), "monster kind suspension remains independent of roster")
	check(Monsters.suspended_lair({"kind": "den"}) and not Monsters.suspended_lair({"kind": "bandit_camp"}), "creature lairs remain suspended and ordinary camps remain active")
	var repeated: Array = []
	repeated.resize(2000); repeated.fill(human)
	human.race_reads = 0
	check(not old_scan(repeated) and human.race_reads == 2000, "frozen scan resolves each of 2000 native references")
	human.race_reads = 0
	check(not Monsters.creature_units(repeated) and human.race_reads == 1, "optimized call resolves one repeated race once")
	repeated.append(wolf)
	human.race_reads = 0; wolf.race_reads = 0
	check(Monsters.creature_units(repeated) and human.race_reads == 1 and wolf.race_reads == 1, "tail creature still resolves both unique races")
	repeated.pop_back()
	# Small reproducible timing observation only: no speed threshold or benchmark loop.
	human.race_reads = 0
	var started: int = Time.get_ticks_usec()
	var old_hits := 0
	for i in 100:
		if old_scan(repeated): old_hits += 1
	var old_us: int = Time.get_ticks_usec() - started
	var old_reads: int = human.race_reads
	human.race_reads = 0
	started = Time.get_ticks_usec()
	var new_hits := 0
	for i in 100:
		if Monsters.creature_units(repeated): new_hits += 1
	var new_us: int = Time.get_ticks_usec() - started
	check(old_hits == 0 and new_hits == old_hits and old_reads == 200000 and human.race_reads == 100, "100 bounded scans preserve results with 200000 versus 100 definition reads")
	print("Creature scan observation (100 x 2000 references): old=%dus/%d reads, current=%dus/%d reads; timing is not an assertion" % [old_us, old_reads, new_us, human.race_reads])
	check(human.uid == 101 and orc.uid == 102 and goblin.uid == 103 and wolf.uid == 104 and human.body == null and wolf.body == null, "classification preserves existing unit UID and never requires or creates a body")
	check(Unit._next_uid == next_unit and Item._next_uid == next_item and Game.rng.state == rng_state and is_same(Game.world, world), "scans conserve allocation counters, campaign RNG and world reference")
	print("Creature check performance: %d checks, %d failures" % [checks, fails])
	return fails
