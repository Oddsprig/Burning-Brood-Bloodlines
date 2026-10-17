extends RefCounted
## Fresh-process native scene ownership gate. Never saves the artificial force.
## --report=<absolute work/...json> is optional; --ticks=160 (64..240).
## Run through tests/runner.tscn. Rendered and headless samples are labelled.
const PRIVATE_WORK := "C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"
const CYCLES := 3
const FORCE := 100
const SLICE_LIMIT := 20000
const PHASE_LIMIT_US := 60000000
var checks: int = 0
var fails: int = 0

class ContactBattle extends "res://battle/battle.gd":
	var blocked_finish_calls: int = 0
	func _ready() -> void:
		super._ready()
		paused = true
		_refresh_speed_buttons()
	func finish() -> void:
		# Native show_result only builds UI after its timer; its Continue button
		# is the sole finish caller. Guard that route against fixture accounting.
		blocked_finish_calls += 1
	func battle_opts(pb: Dictionary, n0: int, n1: int) -> Dictionary:
		var opts: Dictionary = super.battle_opts(pb, n0, n1)
		var rows: int = int(opts["h"]) - 2
		var middle: int = int(opts["w"]) / 2
		for side: int in 2:
			var cells: Array = []
			for i: int in (n0 if side == 0 else n1):
				cells.append(Vector2i(middle - 1 - i / rows if side == 0 else middle + i / rows, 1 + i % rows))
			opts["cells%d" % side] = cells
		return opts

class SceneHost extends "res://main.gd":
	## Fixture deployment/pause/finish guard; native screen ownership/removal.
	func show_screen(path: String) -> void:
		if path != "res://battle/battle.tscn":
			super.show_screen(path)
			return
		if current != null: current.queue_free()
		current = ContactBattle.new()
		add_child(current)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL memory lifecycle: ", message)

func _state() -> String:
	return JSON.stringify(Game._save_tree(), "", true, true).sha256_text()

func _combat(sim: BattleSim) -> String:
	var units: Array = []
	var actors: Array = []
	var events: Array = []
	for f: Fighter in sim.fighters:
		units.append(f.unit.to_dict())
		actors.append([f.idx, f.side, f.cell, f.prev_cell, f.state, f.target,
			f.action_ticks, f.action_total, f.facing, f.prone, f.routed, f.waiting])
	for e: Dictionary in sim.events:
		var entry: Dictionary = e.get("entry", {})
		events.append([e.get("tick"), e.get("type"), e.get("actor"), e.get("target"),
			e.get("part"), entry.get("k"), entry.get("d", {})])
	return JSON.stringify(_plain({"units":units,"actors":actors,"events":events,
		"tick":sim.tick,"winner":sim.winner,"rng":str(sim.rng.state)}), "", true, true).sha256_text()

func _plain(value: Variant) -> Variant:
	if value is Item: return _plain(value.to_dict())
	if value is Array:
		var out: Array = []
		for element: Variant in value: out.append(_plain(element))
		return out
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in value: out[key] = _plain(value[key])
		return out
	return value

func _clone(rows: Array) -> Array:
	var out: Array = []
	for u: Unit in rows: out.append(Unit.from_dict(u.to_dict().duplicate(true)))
	return out

func _finish_drinks(rows: Array) -> void:
	for u: Unit in rows: Food.roll_fav_drink(u, hash([u.uid, u.name]))

func _dead_count(rows: Array) -> int:
	var count: int = 0
	for u: Unit in rows:
		if u.dead: count += 1
	return count

func _sample(label: String) -> Dictionary:
	var owners: Dictionary = {}
	if Perf.has_method("refresh_owners"): owners = Perf.call("refresh_owners", Game, label, 250000, 20000)
	return {"label":label,"engine_static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"engine_static_peak_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"cache":Paperdoll.cache_stats(),"workers":Paperdoll.background_stats(),"owners":owners,
		"os_rss_bytes":null,"os_rss_source":"External root process sampler; engine static memory is not RSS."}

func _frames(tree: SceneTree, count: int = 3) -> void:
	for i: int in count:
		await tree.process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _workers_drained() -> void:
	var workers: Dictionary = Paperdoll.background_stats()
	check(not workers["active"] and int(workers["pending"]) == 0 and int(workers["inflight"]) == 0,
		"battle exit drains all jobs and weak requests")
	var cache: Dictionary = Paperdoll.cache_stats()
	check(int(cache["entries"]) <= int(cache["entry_limit"]) and int(cache["payload_bytes"]) <= int(cache["byte_limit"]),
		"warm texture cache remains within both caps")
	check(int(cache["signature_entries"]) <= int(cache["signature_limit"]), "spec identity cache remains bounded")

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node as Button
	for child: Node in node.get_children():
		var found: Button = _button(child, text)
		if found != null: return found
	return null

func _refs(battle: Node) -> Dictionary:
	var casualty: Unit = null
	for u: Unit in Game.last_result.get("enemy_units", []):
		if u.dead:
			casualty = u
			break
	check(casualty != null, "native close-contact fight contains an actual enemy casualty")
	if casualty == null: casualty = battle.sim.fighters[FORCE].unit
	return {"battle":weakref(battle),"sim":weakref(battle.sim),
		"fighter":weakref(battle.sim.fighters[FORCE]),"casualty":weakref(casualty)}

func _released(refs: Dictionary, name: String) -> bool:
	return (refs[name] as WeakRef).get_ref() == null

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var ticks: int = 160
	var report_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--ticks="): ticks = int(argument.trim_prefix("--ticks="))
		elif argument.begins_with("--report="): report_path = argument.trim_prefix("--report=").replace("\\", "/").simplify_path()
	check(ticks >= 64 and ticks <= 240, "bounded native fixture tick limit")
	check(report_path == "" or (report_path.is_absolute_path() and report_path.to_lower().begins_with(PRIVATE_WORK.to_lower())), "optional report is private")
	if fails > 0: return fails
	if DisplayServer.get_name() != "headless":
		tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
		tree.root.position = Vector2i(-20000, -20000)
		tree.root.size = Vector2i(1280, 720)
		Engine.max_fps = 60
	# This object is deliberately owned ONLY by stale Game transients/cache.
	var old: Unit = Unit.create("human", "test")
	var old_ref: WeakRef = weakref(old)
	Game.company = [old]
	Game.deployed_units()
	Game.last_result = {"fighter_units":[old]}
	Game.pending_battle = {"enemy":[old]}
	old = null
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	var generation: Dictionary = Game.new_game_begin(777)
	check(old_ref.get_ref() == null, "new campaign releases old result, pending and deployment ownership")
	var slices: int = 0
	var generated: bool = false
	var phase_start: int = Time.get_ticks_usec()
	while not generated and slices < SLICE_LIMIT and Time.get_ticks_usec() - phase_start < PHASE_LIMIT_US:
		generated = Game.new_game_slice(generation, 4000)
		slices += 1
		await tree.process_frame
	generation = {}
	check(generated, "fresh Normal generation completes within bounded slices")
	if not generated: return fails
	var history: Dictionary = {}
	slices = 0
	phase_start = Time.get_ticks_usec()
	while CampaignWorld.presim_left(Game) > 0 and slices < SLICE_LIMIT and Time.get_ticks_usec() - phase_start < PHASE_LIMIT_US:
		CampaignWorld.presim_slice(Game, history, 4000)
		slices += 1
		await tree.process_frame
	check(CampaignWorld.presim_left(Game) == 0, "one native history day completes")
	if CampaignWorld.presim_left(Game) > 0: return fails
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	check(Game.has_method("new_game_finalize"), "native generation finalization boundary is available")
	if Game.has_method("new_game_finalize"): Game.call("new_game_finalize")
	history = {}
	check(Game.day == 1.0 and Game.world.get("work", []).is_empty(), "fresh campaign is settled at exactly day one")
	var host := SceneHost.new()
	tree.root.add_child(host)
	Game.goto("map")
	await _frames(tree)
	var campaign: Array = Game.company
	var campaign_sha: String = _state()
	var campaign_rng: int = Game.rng.state
	var campaign_unit_counter: int = Unit._next_uid
	var campaign_item_counter: int = Item._next_uid
	var samples: Array = [_sample("fresh_map")]
	var plain_result: Dictionary = {}
	var plain_forces: Dictionary = {}
	var combat_ticks: int = 0
	var native_deaths: int = 0
	for cycle: int in CYCLES:
		var previous: WeakRef = weakref(host.current)
		if cycle == 0:
			var local_rng := RandomNumberGenerator.new()
			local_rng.seed = 1212
			Game.company = Factory.make_warband(local_rng, "middle_kingdom", FORCE)
			Game.pending_battle = {"enemy":Factory.make_warband(local_rng, "orc_horde", FORCE),
				"seed":1212,"terrain":"grassland","map":"large","max_ticks":ticks}
			_finish_drinks(Game.company)
			_finish_drinks(Game.pending_battle["enemy"])
			plain_forces = Game._serialize({"left":Game.company,"right":Game.pending_battle["enemy"]})
		else:
			# Native deserialization rewrites containers in place. Borrowed plain
			# templates must never become hidden owners of reconstructed Units.
			var reconstructed: Dictionary = Game._deserialize(plain_forces.duplicate(true))
			Game.company = reconstructed["left"]
			Game.pending_battle = {"enemy":reconstructed["right"],"seed":1212,"map":"large","max_ticks":ticks}
			reconstructed = {}
		Game.invalidate_deploy()
		Game.goto("battle")
		var battle: Node = host.current
		check(battle.sim.fighters.size() == FORCE * 2, "actual 100/100 scene fixture retains every fighter")
		var refs: Dictionary = {}
		if cycle == 0:
			var control := BattleSim.new()
			control.setup(_clone(Game.company), _clone(Game.pending_battle["enemy"]), 1212,
				battle.battle_opts(Game.pending_battle, FORCE, FORCE))
			check(_combat(battle.sim) == _combat(control), "independent native control starts identical")
			phase_start = Time.get_ticks_usec()
			while not battle.sim.is_over() and combat_ticks < ticks and Time.get_ticks_usec() - phase_start < PHASE_LIMIT_US:
				battle.step_ticks(1)
				control.step()
				combat_ticks += 1
				await tree.process_frame
			check(battle.sim.is_over() and _combat(battle.sim) == _combat(control), "rendered native fight matches control bodies, events and RNG")
			control = null
			var result: Dictionary = battle.build_result() # Native growth/arrow finalization ONCE.
			native_deaths = _dead_count(result["enemy_units"])
			plain_result = Game._serialize(result)
			Game.last_result = result
			result = {}
			refs = _refs(battle)
		else:
			# No artificial repeat fighting/rewards: reopen the recorded result.
			Game.last_result = Game._deserialize(plain_result.duplicate(true))
			refs = _refs(battle)
		check(plain_forces["left"][0] is Dictionary and plain_forces["right"][0] is Dictionary and
			plain_result["enemy_units"][0] is Dictionary and plain_result["fighter_units"][0] is Dictionary,
			"serialized templates stay plain and do not retain reconstructed combatants")
		var paused_sha: String = _combat(battle.sim)
		var unit_counter: int = Unit._next_uid
		var item_counter: int = Item._next_uid
		battle.select(0)
		battle.cam_pos.x += 160.0
		await _frames(tree, 5)
		check(previous.get_ref() == null, "actual prior map is deleted after deferred screen swap")
		check(_combat(battle.sim) == paused_sha and Unit._next_uid == unit_counter and Item._next_uid == item_counter,
			"paused camera/inspector/workers preserve native state and identities")
		check(battle.paused and int(battle.blocked_finish_calls) == 0,
			"native end timer neither unpauses fixture nor invokes campaign result handback")
		if cycle == 0:
			check(int(Paperdoll.background_stats()["dispatched"]) > 0, "actual animated fight exercised worker dispatch before exit drain")
		samples.append(_sample("battle_%d" % cycle))
		Game.company = campaign
		Game.invalidate_deploy()
		Game.pending_battle = {}
		# Artificial identities are local test scaffolding, not campaign births.
		# No new Units/Items are allocated from here until the next fixture setup.
		Unit._next_uid = campaign_unit_counter
		Item._next_uid = campaign_item_counter
		Game.goto("aftermath")
		battle = null
		await _frames(tree)
		check(_released(refs, "battle") and _released(refs, "sim") and _released(refs, "fighter"), "battle tree/sim/fighter are released after results consumed")
		check(not _released(refs, "casualty"), "native result intentionally owns casualty while aftermath is visible")
		_workers_drained()
		var after_ref: WeakRef = weakref(host.current)
		var complete_sha: String = _state()
		var continue_button: Button = _button(host.current, "Continue")
		check(continue_button != null, "actual aftermath Continue exists")
		if continue_button != null: continue_button.pressed.emit()
		else: Game.goto("map")
		continue_button = null
		await _frames(tree)
		check(after_ref.get_ref() == null and Game.last_result.is_empty(), "Continue deletes aftermath and releases transient result")
		check(_released(refs, "casualty"), "unowned native casualty releases without test retaining a strong reference")
		check(_state() == complete_sha and _state() == campaign_sha and Game.rng.state == campaign_rng and
			Unit._next_uid == campaign_unit_counter and Item._next_uid == campaign_item_counter,
			"result disposal/map reentry preserves complete native campaign state and RNG")
		_workers_drained()
		Game.goto("company")
		await _frames(tree)
		var menu_ref: WeakRef = weakref(host.current)
		Game.goto("map")
		await _frames(tree)
		check(menu_ref.get_ref() == null and _state() == campaign_sha and Game.rng.state == campaign_rng and
			Unit._next_uid == campaign_unit_counter and Item._next_uid == campaign_item_counter,
			"actual company menu/map cycle releases scene and preserves exact campaign/counters")
		samples.append(_sample("settled_map_%d" % cycle))
	plain_result = {}
	plain_forces = {}
	Game.goto("title")
	await _frames(tree)
	var final_scene: WeakRef = weakref(host.current)
	var host_ref: WeakRef = weakref(host)
	Game.main = null
	host.queue_free()
	host = null
	await _frames(tree)
	check(host_ref.get_ref() == null and final_scene.get_ref() == null, "root and current screen delete with native resource loads drained")
	_workers_drained()
	samples.append(_sample("root_released"))
	var report: Dictionary = {"checks":checks,"failures":fails,"cycles":CYCLES,"force_per_side":FORCE,
		"native_fights":1,"native_ticks":combat_ticks,"native_enemy_deaths":native_deaths,
		"display":DisplayServer.get_name(),"rendered":DisplayServer.get_name() != "headless",
		"samples":samples,"campaign_sha":_state(),"rng":str(Game.rng.state),
		"next_unit_uid":Unit._next_uid,"next_item_uid":Item._next_uid,
		"memory_scope":"Engine static memory and objects only; no OS RSS or GPU total. Warm cache remains bounded, not forced empty.",
		"fixture":"Fresh Normal/one-day, one native close-contact 100/100 fight; two paused reopen cycles. No fixture save or campaign result reconciliation."}
	if report_path != "":
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		check(file != null, "private report opens")
		report["checks"] = checks
		report["failures"] = fails
		if file != null: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("memory lifecycle: ", checks, " checks, ", fails, " failures; ", combat_ticks, " native ticks; ", native_deaths, " native enemy deaths")
	return fails
