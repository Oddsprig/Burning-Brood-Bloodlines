extends RefCounted
## v0.100: private, two-person native raid; no generation or campaign-day simulation.
## 4 opening ticks, save/load, then 24 ticks against the never-loaded control.
## Test brief: headless only, 180 s maximum; intended to take seconds on dev setups.
## "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief."
## "A test failure stops all further tests. No other test runs until that one failing test is fixed and passes."
const SimUtil = preload("res://tests/sim_util.gd")
const TICKS := 24
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL raid save v100: ", why)

func _codec() -> void:
	var typed: Array[int] = [3, 7]
	var source := {"first": 11, "wide": 9223372036854775806,
		"keys": {7: {"count": 5}, "7": [9, 0.03125]}, "typed": typed,
		"packed": PackedInt32Array([1, 2]), "floats": PackedFloat32Array([0.03, 0.75]),
		# v0.100: real null and both infinity signs coexist in the same exact round-trip.
		"float64": PackedFloat64Array([0.037, 53.736691176034476]), "unbuilt": INF, "built": null, "negative": -INF}
	# v0.100: repeated references retain their metadata and leave the source untouched.
	var shared := {"column": PackedInt32Array([4, 8])}
	source["alias0"] = shared
	source["alias1"] = shared
	var source_before := var_to_bytes(source)
	var text := Game.save_text(source, true)
	var parsed = JSON.parse_string(text)
	check(parsed is Dictionary, "native type save is JSON")
	if not (parsed is Dictionary): return
	check(parsed["packed"] is Array and parsed["floats"] is Array
		and parsed["__types"] is String and parsed["__types"].begins_with("lz:"), "v0.100: compressed metadata keeps the ordinary JSON fields readable")
	check(typeof(parsed["unbuilt"]) == TYPE_NIL and typeof(parsed["built"]) == TYPE_NIL
		and typeof(parsed["negative"]) == TYPE_NIL, "v0.100: null and signed INF use JSON null seats without overflow exponents")
	Game.restore_exact(parsed)
	check(var_to_bytes(parsed) == source_before, "integer keys, wide ints, typed/packed arrays, aliased seats and float bits round-trip")
	check(var_to_bytes(source) == source_before and not source.has("__types") and not source.has("__fx"), "codec leaves every input value unchanged")
	# The lead's reported food test removes fields but leaves the old type sidecar.
	var legacy_shape := {"keep": 2, "removed": {"count": 8}, "number": 9, "row": [{"gone": 4, "tail": 6}]}
	var edited: Dictionary = JSON.parse_string(Game.save_text(legacy_shape, true))
	edited.erase("removed")
	edited["number"] = {"replacement": true}
	edited["row"][0].erase("gone")
	edited["keep"] = null
	Game.restore_exact(edited)
	check(edited["keep"] == null and edited["number"] == {"replacement": true}
		and not edited.has("removed") and edited["row"][0] == {"tail": 6}, "old erased fields and nonnumeric seats are safe")
	check(typeof(edited["row"][0]["tail"]) == TYPE_INT, "remaining old-save fields retain their own keyed metadata")
	var obsolete := {"value": null, "__types": Marshalls.raw_to_base64(var_to_bytes({"ints": PackedInt32Array([0])}))}
	Game.restore_exact(obsolete)
	check(obsolete == {"value": null}, "obsolete positional dictionary metadata never casts unrelated values")
	# v0.100: checkpoints made before sidecar compression remain readable.
	var old_info := {"dictionary": true, "ints": ["value"], "children": {"packed": {"native": var_to_bytes(PackedInt32Array([2, 5]))}}}
	var old_native := {"value": 7.0, "packed": [2.0, 5.0], "__types": Marshalls.raw_to_base64(var_to_bytes(old_info))}
	Game.restore_exact(old_native)
	check(typeof(old_native["value"]) == TYPE_INT and old_native["packed"] is PackedInt32Array
		and old_native["packed"] == PackedInt32Array([2, 5]), "uncompressed native sidecars still restore exact types")

func _fixture(valid: bool) -> void:
	Game.seed_value = 100731
	Game.rng.seed = Game.seed_value
	Unit._next_uid = 100
	Item._next_uid = 500
	Game.day = 3.0
	Game.gold = 120
	Game.location = ""
	Game.squads = {}
	Game.rep = {}
	Game.contract = {}
	Game.stash = []
	Game.provisions = Food.new_stock()
	Game.rations = {"food": "normal", "drink": "ration"}
	Game.food_clock = {"next": 3.25, "last": 3.0, "march": 0.0, "rot": 1}
	var defender: Unit = SimUtil.soldier("copper")
	var attacker: Unit = SimUtil.soldier("copper")
	defender.role = "captain" # A current save must not apply the legacy captain rename.
	defender.title = "town guard"
	defender.belly = 10.0 # The live Unit's battle-only food attribute cache must survive.
	defender.home_town = "save_town"
	var layer: Dictionary = defender.body.wound_part("head")["layers"][0]
	layer["dmg"] = 0.01
	layer["kind"] = "cut"
	layer["bleed"] = 0.003
	var plots := {"x": PackedInt32Array([0, 1]), "y": PackedInt32Array([0, 0]),
		"ac": PackedInt32Array([5, 5]), "use": PackedInt32Array([Plots.FIELD, Plots.FIELD]),
		"sub": PackedInt32Array([0, 0]), "own": PackedInt32Array([0, 0]),
		"st": PackedFloat32Array([0.0, 0.0]), "crops": ["grain"], "variety": ["wheat", "wheat"],
		"soil": ["loam", "light"], "rotation_phase": [0, 0], "crop_year": Calendar.year(Game.day), "crop_count": 2,
		"crop_work_acres": {"0": {"grain": {"active": 10.0 if valid else 5.0, "fallow": 0.0}}},
		"crop_work_plots": {"0": {"grain": [0, 1] if valid else [0]}},
		"crop_yields": {"0": [10.0, 1750.0, 10.0]}, "crop_names": {"0": {"wheat": 10.0}},
		"_crop_work_plots_valid": valid, "dirty": true, "heads": {0: 31}}
	var town := {"id": "save_town", "name": "Save fixture", "faction": "middle_kingdom", "pos": Vector2.ZERO,
		"econ": {"stock": {}, "day": Game.day, "plots": plots,
			"hd": {"h": {"1": {"id": 1, "k": "cattle", "y": 0, "g": 6, "o": 0, "ow": "0"}}}}}
	var raiders := {"id": "raid", "faction": "bandits", "kind": "bandit", "units": [attacker], "pos": Vector2.ZERO,
		"raid": {"town": "save_town", "herd": 1, "wolves": false, "phase": "fighting", "day": Game.day, "goal": Vector2.ZERO}}
	var guard := {"id": "guard", "faction": "middle_kingdom", "kind": "militia", "units": [defender], "pos": Vector2.ZERO}
	Game.company = [defender]
	Game.world = {"version": 1, "seed": Game.seed_value, "w": 150, "h": 96, "next_id": 3,
		"rng_state": str(Game.rng.state), "towns": {"save_town": town}, "warbands": {"raid": raiders, "guard": guard},
		"town_guards": {"save_town": "guard"}, "creatures_enabled": false}
	var sim := BattleSim.new()
	sim.setup([defender], [attacker], 731, {"w": 16, "h": 8, "cells0": [Vector2i(6, 4)], "cells1": [Vector2i(7, 4)],
		"verbose": false, "log_moves": false, "combat_journal": false})
	HerdRaids.fights = {"raid": {"sim": sim, "defenders": [defender]}}
	HerdRaids.fight_seed = Game.seed_value
	HerdRaids.benchmark_fixed_steps = true
	TownEcon.gold_gone = 53.736691176034476
	TownEcon.goods_lost = {"grain": 7, "arms": 2}
	WarAI._grid = {Vector2i(0, 0): [guard, raiders]}
	WarAI._grid_t = Game.day - 0.02
	WarAI._grid_n = 3
	WarAI._budget = 1
	WarAI._counts = 1000
	for i in 4: sim.step()
	check(sim.tick == 4 and not sim.over, "fixture saves during an active native raid")

func _state() -> String:
	return Game.save_text(Game._save_tree())

func _tick(i: int) -> void:
	var sim: BattleSim = HerdRaids.fights["raid"]["sim"]
	sim.step()
	if i == 0:
		var e: Dictionary = Game.world["towns"]["save_town"]["econ"]
		CropRotation.reindex_owners(e, e["plots"], [0]) # exercises the saved validity bit's branch.
	if i == 7:
		TownEcon.gold_out(0.125)
		TownEcon.goods_lost["grain"] = int(TownEcon.goods_lost["grain"]) + 1

func _round_trip(valid: bool) -> void:
	_fixture(valid)
	if fails > 0: return
	var initial := _state()
	var raid_before := HerdRaids.save_state()
	var unit_next: int = Unit._next_uid
	var item_next: int = Item._next_uid
	check(Game.save_game(), "v0.100: round-trip manual save explicitly reports success")
	check(initial != "" and FileAccess.get_file_as_string(Game.SAVE_PATH) == initial, "manual save captures the exact live raid/counters/cache")
	if fails > 0: return
	var expected: Array = []
	for i in TICKS:
		_tick(i)
		expected.append(_state())
	Game.world = {}
	Game.company = []
	HerdRaids.reset()
	TownEcon.gold_gone = 0.0
	TownEcon.goods_lost = {}
	Unit._next_uid += 200
	Item._next_uid += 200
	check(Game.load_game(), "load the mid-raid save")
	if fails > 0: return
	check(_state() == initial and HerdRaids.save_state() == raid_before, "immediate save text and every combat field match the never-loaded initial state")
	check(Unit._next_uid == unit_next and Item._next_uid == item_next, "UID process counters restore exactly")
	check(TownEcon.gold_gone == 53.736691176034476 and TownEcon.goods_lost == {"grain": 7, "arms": 2}, "economy process counters restore exactly")
	var sim: BattleSim = HerdRaids.fights["raid"]["sim"]
	var f: Fighter = sim.fighters[0]
	check(is_same(f.unit, Game.company[0]) and is_same(f.unit, HerdRaids.fights["raid"]["defenders"][0])
		and is_same(f.unit, Game.world["warbands"]["guard"]["units"][0]), "raid and campaign share one defender body")
	check(is_same(f.wielded, f.unit.equip["main_hand"]), "fighter and campaign share one equipped weapon")
	check(is_same(f.rdef, DB.races[f.unit.race]), "future cache misses share the original race/attack/material definitions")
	var bleeders: Array = sim._bleeders.get(0, [])
	check(not bleeders.is_empty() and is_same(bleeders[0][0], f.unit.body.parts["head"]["layers"][0]), "bleeding cache points to the restored live wound layer")
	check(not f.unit.food_attr_mult.is_empty() and f.unit.role == "captain", "battle food cache survives and current saves skip the legacy captain migration")
	var P: Dictionary = Game.world["towns"]["save_town"]["econ"]["plots"]
	check(P["_crop_work_plots_valid"] == valid and P["crop_count"] == 2 and P["x"] is PackedInt32Array,
		"plot validity and packed columns survive even with unchanged crop_count")
	check(is_same(WarAI._grid[Vector2i(0, 0)][0], Game.world["warbands"]["guard"]), "aged hunt grid points to restored campaign bands")
	if fails > 0: return
	for i in TICKS:
		_tick(i)
		check(_state() == expected[i], "next native tick %d is exactly the never-loaded control (cache valid=%s)" % [i + 1, valid])
		if fails > 0: return

# v0.100: exercise refusal, disk preservation, visible feedback and recovery on a tiny fixture.
func _save_failures() -> void:
	var path := Game.SAVE_PATH
	var was_paused := Game.get_tree().paused
	check(not Game.get_tree().auto_accept_quit, "v0.100: window close is gated on the close-save")
	var disk_before := FileAccess.get_file_as_string(path)
	var data: Dictionary = Game._save_tree()
	data["raid_state"] = ""
	var input_before := var_to_bytes(data)
	var receipt: Dictionary = Game._write_save(path, data)
	check(not bool(receipt["ok"]) and int(receipt["error"]) == ERR_INVALID_DATA
		and String(receipt["stage"]) == "encode" and int(receipt["serialized_bytes"]) == 0, "empty capture returns an explicit encode failure")
	check(FileAccess.get_file_as_string(path) == disk_before and not FileAccess.file_exists(path + ".tmp")
		and var_to_bytes(data) == input_before, "refused empty output preserves the good save and input and removes only its temporary file")
	var failures_before := int(Game.save_stats()["failed"])
	Game._accept_save_receipt(receipt)
	check(not bool(Game.save_stats()["last_ok"]) and int(Game.save_stats()["failed"]) == failures_before + 1, "refused encode is accepted as a failed receipt")
	var notice_path := "MobileAppLayer/MobileAppRoot/SaveFailureModal"
	var notice: Node = MobileApp.get_node_or_null(notice_path)
	check(notice is Control and (notice as Control).is_visible_in_tree(), "refused save shows a visible in-game failure notice")
	check(Game.get_tree().paused, "v0.100: campaign and battle processing stop behind the blocking failure notice")
	# An existing file cannot be a parent directory: no blocker files or directories are needed.
	Game.SAVE_PATH = path + "/blocked.json"
	check(not Game.save_game(), "manual save reports a failed write instead of claiming success")
	check(not Game.save_on_quit(), "quit save reports failure so its caller can keep the game open")
	check(MobileApp.get_node_or_null(notice_path) == notice, "repeated failures reuse one persistent notice")
	# v0.100: never probe WM-close on a writable path - a successful close-save quits the runner.
	if Game.SAVE_PATH == path + "/blocked.json":
		Game._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		check(false, "WM-close probe requires the blocked save path")
	check(MobileApp.is_save_failure_open(), "v0.100: a failed window-close save keeps the failure choice visible")
	MobileApp.ask_quit_confirm()
	# v0.100: keep the same blocked-path pin on the save-and-quit probe.
	if Game.SAVE_PATH == path + "/blocked.json":
		MobileApp.confirm_quit()
	else:
		check(false, "save-and-quit probe requires the blocked save path")
	check(MobileApp.is_quit_confirm_open() and MobileApp.is_save_failure_open(), "v0.100: failed save-and-quit retains the quit confirmation and failure choice")
	MobileApp.close_quit_confirm()
	check(MobileApp.handle_back_request() == "closed_save_failure" and Game.get_tree().paused == was_paused,
		"v0.100: back dismisses the notice through its pause-restoring close path")
	var screen_before := String(Game._active_screen)
	Game._active_screen = "battle"
	var failed_before_battle := int(Game.save_stats()["failed"])
	check(not Game.save_on_quit() and int(Game.save_stats()["failed"]) == failed_before_battle,
		"v0.100: unresolved pre-battle failure blocks quit without attempting a mid-battle write")
	check(MobileApp.is_save_failure_open() and Game._save_capture == null and Game._save_task == -1,
		"v0.100: battle quit reopens the failure choice without creating a snapshot or writer")
	Game._active_screen = screen_before
	Game.SAVE_PATH = path
	check(FileAccess.get_file_as_string(path) == disk_before, "failed manual and quit saves preserve the previous good bytes")
	check(Game.save_game(), "a recovered manual save explicitly reports success")
	check(MobileApp.get_node_or_null(notice_path) == null, "successful recovery closes the stale failure notice")
	check(Game.get_tree().paused == was_paused, "v0.100: recovery restores the pause state from before the notice")
	# v0.100: an existing pause belongs to its original owner, not the failure notice.
	Game.get_tree().paused = true
	MobileApp._on_save_finished(false)
	MobileApp.handle_back_request()
	check(Game.get_tree().paused, "v0.100: dismissing a failure preserves a pre-existing pause")
	Game.get_tree().paused = false
	MobileApp.pause_gameplay(true, false)
	MobileApp._on_save_finished(false)
	MobileApp._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(Game.get_tree().paused and MobileApp.is_save_failure_open(), "v0.100: lifecycle resume keeps an open failure notice paused")
	MobileApp.handle_back_request()
	check(not Game.get_tree().paused, "v0.100: dismissal releases the hold transferred from lifecycle resume")
	Game.get_tree().paused = was_paused

# v0.100: exercise the real Title button with no save eligible, without loading campaign scenes.
func _title_without_save() -> void:
	var screen_before := String(Game._active_screen)
	var ready_before: bool = Game._save_ready
	var main_before: Node = Game.main
	var was_paused := Game.get_tree().paused
	var counts := [Game.save_stats()["completed"], Game.save_stats()["failed"]]
	Game.main = null
	for screen in ["presim", "newgame", "gameover", "map"]:
		Game._active_screen = screen
		Game._save_ready = screen == "gameover" # map also covers incomplete startup outside the excluded screens.
		var menu: Control = MobileApp.open_pause_menu()
		var title := menu.find_child("PauseTitle", true, false) as Button
		check(title != null, "v0.100: Title button is available from " + screen)
		if title != null: title.pressed.emit()
		check(String(Game._active_screen) == "title" and not MobileApp.is_pause_menu_open(),
			"v0.100: nothing-to-save Title transition proceeds from " + screen)
		MobileApp.close_pause_menu(false)
	check([Game.save_stats()["completed"], Game.save_stats()["failed"]] == counts,
		"v0.100: ineligible Title transitions produce neither writes nor failure receipts")
	Game.main = main_before
	Game._active_screen = screen_before
	Game._save_ready = ready_before
	Game.get_tree().paused = was_paused

# v0.100: rejecting foreign/wrong-type raid records leaves the running game intact.
func _rejected_raid_loads() -> void:
	var disk_before := FileAccess.get_file_as_string(Game.SAVE_PATH)
	var before := _state()
	var world_before: Dictionary = Game.world
	var company_before: Array = Game.company
	var fights_before: Dictionary = HerdRaids.fights
	var flags_before := [Game._save_epoch, Game._save_ready, Game._save_pending, Game._autosave_day_pending]
	var data: Dictionary = Game._save_tree()
	var foreign := Marshalls.raw_to_base64(var_to_bytes({"root": [0, 42], "nodes": []}))
	var bad_blobs: Array = [foreign, null, {}, 7, [], true, 7.0]
	data["raid_state"] = ""
	var empty_before := var_to_bytes(data)
	check(Game.save_text(data).is_empty() and var_to_bytes(data) == empty_before, "v0.100: failed empty raid capture refuses save without changing its input")
	check(HerdRaids.RaidSave.new().capture({"fights": 7}).is_empty(), "v0.100: wrong-type fights refuse capture without a failed dictionary cast")
	# v0.100: valid Variant bytes exercise malformed-graph rejection and live-state safety.
	# Some roots also fail state validation; these cases do not isolate each shape guard.
	for graph in [
		{"root": [{}, 0], "nodes": []},
		{"root": [1, null], "nodes": []},
		{"root": [1, {}], "nodes": []},
		{"root": [1, 0.5], "nodes": []},
		{"root": [1, -1], "nodes": []},
		{"root": [2, [null]], "nodes": []},
		{"root": [1, 0], "nodes": [{"kind": {}, "rows": []}]},
		{"root": [1, 0], "nodes": [{"kind": "dict", "rows": [null]}]},
		{"root": [1, 0], "nodes": [{"kind": "dict", "rows": [[[0, "x"]]]}]},
		{"root": [1, 0], "nodes": [{"kind": "array", "rows": [null]}]},
		{"root": [1, 0], "nodes": [{"kind": "rng", "rows": [], "seed": null, "state": 1}]},
		{"root": [1, 0], "nodes": [{"kind": "rng", "rows": [], "seed": 1, "state": {}}]},
		{"root": [1, 0], "nodes": [{"kind": "unit", "rows": [null]}]},
		{"root": [1, 0], "nodes": [{"kind": "unit", "rows": [["uid", [0, null]]]}]},
		{"root": [1, 0], "nodes": [{"kind": "unit", "rows": [["_next_uid", [0, 999]]]}]}
	]:
		bad_blobs.append(Marshalls.raw_to_base64(var_to_bytes(graph)))
	bad_blobs.append(HerdRaids.RaidSave.new().capture({"fights": {}, "fight_seed": null}))
	bad_blobs.append(HerdRaids.RaidSave.new().capture({"fights": {}, "fixed_steps": {}}))
	for bad in bad_blobs:
		data["raid_state"] = bad
		if typeof(bad) != TYPE_STRING:
			var data_before := var_to_bytes(data)
			check(Game.save_text(data).is_empty(), "v0.100: wrong-type raid record explicitly refuses save")
			check(var_to_bytes(data) == data_before, "v0.100: refused raid save preserves its input tree")
		var file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		check(file != null, "private corrupt save opens")
		if file == null: break
		# v0.100: deliberately bypass save validation to retain EVERY corrupt-load check.
		# These are valid JSON fixtures, not empty files left by a refused save.
		file.store_string(JSON.stringify(data))
		file.close()
		check(not Game.load_game(), "foreign/wrong-type raid record rejects the load")
		check(is_same(Game.world, world_before) and is_same(Game.company, company_before)
			and is_same(HerdRaids.fights, fights_before) and _state() == before, "rejected raid load preserves all live values and campaign/fight identities")
		check([Game._save_epoch, Game._save_ready, Game._save_pending, Game._autosave_day_pending] == flags_before,
			"rejected raid load preserves save epoch and readiness/pending flags")
		if fails > 0: break
	var restore_file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	check(restore_file != null, "private save reopens for restoration")
	if restore_file != null:
		restore_file.store_string(disk_before)
		restore_file.close()

func _legacy() -> void:
	# v0.100: the full after_load chain requires a genuine old campaign schema.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/harvest_legacy_v030_save.json"))
	check(parsed is Dictionary, "real v0.030 legacy fixture parses")
	if not (parsed is Dictionary): return
	var legacy: Dictionary = parsed
	check(legacy.get("version") == 1 and not legacy.get("company", []).is_empty()
		and not legacy.get("world", {}).get("towns", {}).is_empty(), "legacy fixture has schema 1, company and complete towns")
	if fails > 0: return
	legacy["company"][0]["role"] = "captain"
	# v0.100: a zero flow entry proves the final after_load hook was reached.
	legacy["world"]["flow"] = {"goods": {"grain": {"+v100 legacy probe": 0}}}
	var town_ids: Array = legacy["world"]["towns"].keys()
	for with_version in [true, false]:
		if not with_version: legacy.erase("version")
		var file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		check(file != null, "private legacy save opens")
		if file == null: return
		file.store_string(JSON.stringify(legacy)) # genuine old JSON, with no native-type sidecar.
		file.close()
		check(Game.load_game(), "older/missing-version save without new optional fields loads")
		if fails > 0: return
		check(Game.company[0].role == "officer", "older/missing-version save still runs legacy migration")
		check(Game.world["towns"].keys() == town_ids and Game.company.size() == legacy["company"].size()
			and is_equal_approx(Game.day, float(legacy["day"])), "real legacy towns, company and campaign day survive")
		check(typeof(Game.world["flow"]["goods"]["grain"]["+v100 legacy probe"]) == TYPE_INT, "legacy migration reaches the final WorldAudit.after_load hook")
		for tid in town_ids:
			var town: Dictionary = Game.world["towns"][tid]
			check(typeof(town["size"]) == TYPE_INT and typeof(town["wealth"]) == TYPE_INT
				and town["econ"]["plots"]["x"] is PackedInt32Array, "legacy town schema and packed plots migrate: " + str(tid))
		check(HerdRaids.fights.is_empty() and TownEcon.gold_gone == 0.0 and TownEcon.goods_lost.is_empty(), "missing runtime fields use compatible empty defaults")
		if fails > 0: return

func run(tree: SceneTree) -> int:
	await tree.process_frame
	check(Game.SAVE_PATH.begins_with("user://test_"), "runner supplies a private save path")
	if fails > 0: return fails
	Game.wait_save()
	var fields := ["seed_value", "day", "gold", "company", "stash", "squads", "rep", "world", "location", "contract", "provisions", "rations", "food_clock", "_save_ready", "_save_pending", "_active_screen", "pending_battle", "last_result"]
	var original := {}
	for field in fields: original[field] = Game.get(field)
	var was_processing := Game.is_processing()
	var rng_before := [Game.rng.seed, Game.rng.state]
	var counters := [Unit._next_uid, Item._next_uid, TownEcon.gold_gone, TownEcon.goods_lost]
	var raids := [HerdRaids.fights, HerdRaids.fight_seed, HerdRaids.benchmark_fixed_steps]
	var war := [WarAI._grid, WarAI._grid_t, WarAI._grid_n, WarAI._budget, WarAI._counts, WarAI._unit_avg]
	var settings := [WorldGen.W, WorldGen.H, WorldGen.K, WorldGen.KD, WorldGen.TF, Sickness.deadliness, Monsters.creatures_on]
	var started := Time.get_ticks_msec()
	Game.set_process(false)
	Game._save_ready = true
	Game._save_pending = false
	Game._active_screen = "map"
	_codec()
	if fails == 0: _round_trip(false)
	if fails == 0: _round_trip(true)
	if fails == 0: _save_failures() # v0.100: no world generation or timed-save changes.
	if fails == 0: _title_without_save()
	if fails == 0: _rejected_raid_loads()
	if fails == 0: _legacy()
	Game.wait_save()
	for field in fields: Game.set(field, original[field])
	Game.rng.seed = rng_before[0]
	Game.rng.state = rng_before[1]
	Unit._next_uid = counters[0]
	Item._next_uid = counters[1]
	TownEcon.gold_gone = counters[2]
	TownEcon.goods_lost = counters[3]
	HerdRaids.fights = raids[0]
	HerdRaids.fight_seed = raids[1]
	HerdRaids.benchmark_fixed_steps = raids[2]
	WarAI._grid = war[0]
	WarAI._grid_t = war[1]
	WarAI._grid_n = war[2]
	WarAI._budget = war[3]
	WarAI._counts = war[4]
	WarAI._unit_avg = war[5]
	WorldGen.W = settings[0]
	WorldGen.H = settings[1]
	WorldGen.K = settings[2]
	WorldGen.KD = settings[3]
	WorldGen.TF = settings[4]
	Sickness.deadliness = settings[5]
	Monsters.creatures_on = settings[6]
	Game.set_process(was_processing)
	check(Time.get_ticks_msec() - started < 120000, "bounded tiny fixture finishes below two minutes")
	print("Raid save v100: %d checks, %d failures" % [checks, fails])
	return fails
