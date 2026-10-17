extends RefCounted
## Runs unchanged on shipped21 and candidate22: native ordinary Factory forces.
## No dragon APIs/new properties, world generation, save loading, rewards or UI.
var checks: int = 0
var fails: int = 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL native dragon control: ", why)

static func state(sim: BattleSim) -> Dictionary:
	var fighters: Array = []
	for f: Fighter in sim.fighters:
		fighters.append({"idx": f.idx, "unit": f.unit.to_dict(), "side": f.side, "cell": [f.cell.x,f.cell.y],
			"prev_cell": [f.prev_cell.x,f.prev_cell.y], "facing": f.facing, "target": f.target, "state": f.state,
			"prone": f.prone, "waiting": f.waiting, "action_ticks": f.action_ticks, "action_total": f.action_total,
			"pending_attack": f.pending_attack, "current_attack": f.current_attack, "morale": f.morale,
			"routed": f.routed, "grabbing": f.grabbing, "grabbed_by": f.grabbed_by, "lost": f.lost,
			"log": f.log.duplicate(true), "kills": f.kills})
	return Game._serialize({"tick": sim.tick, "rng": str(sim.rng.state), "winner": sim.winner,
		"over": sim.is_over(), "fighters": fighters, "events": sim.events, "growth": sim.growth,
		"side_total": sim.side_total, "side_down": sim.side_down, "arrow_field": sim.arrow_field,
		"projectiles": sim.projectiles, "ground": sim.ground})

func run(_tree: SceneTree) -> int:
	var report_path: String = ""; var reference_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=").replace("\\", "/").simplify_path()
		elif arg.begins_with("--reference="): reference_path = arg.trim_prefix("--reference=").replace("\\", "/").simplify_path()
	for path: String in [report_path, reference_path]:
		if path != "": check(path.is_absolute_path() and path.to_lower().begins_with("c:/users/bligh/documents/codex/2026-10-10/you/work/"), "control reports stay in explicit private workspace")
	if fails > 0: return fails
	var campaign_rng: int = Game.rng.state; var unit_counter: int = Unit._next_uid; var item_counter: int = Item._next_uid
	Unit._next_uid = 1; Item._next_uid = 1
	var local: RandomNumberGenerator = RandomNumberGenerator.new(); local.seed = 22021
	var left: Array = Factory.make_warband(local, "middle_kingdom", 4)
	var right: Array = Factory.make_warband(local, "orc_horde", 4)
	var sim: BattleSim = BattleSim.new()
	sim.setup(left, right, 22221, {"w": 12, "h": 7, "max_ticks": 96, "log_moves": false,
		"cells0": [Vector2i(4,1),Vector2i(4,2),Vector2i(4,3),Vector2i(4,4)],
		"cells1": [Vector2i(5,1),Vector2i(5,2),Vector2i(5,3),Vector2i(5,4)], "combat_journal": true})
	var transitions: Array = []
	for tick: int in 96:
		sim.step()
		transitions.append({"tick": sim.tick, "rng": str(sim.rng.state), "actors": sim.fighters.map(func(f: Fighter):
			return [f.state,f.cell.x,f.cell.y,f.target,f.action_ticks,f.action_total,f.current_attack,f.prone,f.routed])})
	sim.flush_combat_journal()
	var strikes: int = 0; var wounds: bool = false
	for f: Fighter in sim.fighters:
		wounds = wounds or f.unit.body.is_wounded()
		strikes += f.swing_count
	check(left.size() == 4 and right.size() == 4 and sim.fighters.size() == 8, "ordinary native4/4 force fixture")
	check(sim.tick > 0 and sim.tick <= 96 and transitions.size() == 96, "exactly96 native step calls, with native early-ending rules intact")
	check(strikes > 0 and wounds, "control exercises actual attacks and native tissue wounds")
	var native: Dictionary = {"state": state(sim), "transitions": transitions, "force_rng": str(local.state),
		"unit_next": Unit._next_uid, "item_next": Item._next_uid}
	var hash_text: String = JSON.stringify(native, "", true, true).sha256_text()
	if reference_path != "":
		var reference: Variant = JSON.parse_string(FileAccess.get_file_as_string(reference_path))
		check(reference is Dictionary and reference.get("native_sha", "") == hash_text, "shipped21/candidate22 exact native RNG/body/events/transitions/counters parity")
	if sim.combat_journal != null:
		sim.combat_journal.dispose()
		check(bool(sim.combat_journal.stats()["disposed"]), "actual transient native journal disposed")
	check(Game.rng.state == campaign_rng, "probe never consumes campaign RNG")
	Unit._next_uid = unit_counter; Item._next_uid = item_counter
	check(Unit._next_uid == unit_counter and Item._next_uid == item_counter, "test fixture restores native allocation counters")
	if report_path != "":
		var report: Dictionary = {"native_sha": hash_text, "native": native, "checks": checks + 1, "fails": fails,
			"scheduled_calls": 96, "ticks": sim.tick, "strikes": strikes, "wounds": wounds, "force_sizes": [4,4], "campaign_rng_untouched": Game.rng.state == campaign_rng}
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		check(file != null, "explicit private control report writable")
		if file != null: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("Native dragon control: ", checks, " checks, ", fails, " failures; SHA=", hash_text)
	return fails
