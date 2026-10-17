extends RefCounted
## Fresh Normal/exactly one-day campaign. All troops, enemy roster, dragon,
## households, funds and gear are actual native holdings. A close-contact start
## and native240-tick limit stage a bounded battle, not a full war benchmark.
const PRIVATE_WORK := "C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"
const NativeBattle = preload("res://battle/battle.gd")
var checks := 0
var fails := 0
var captures: Array = []

class HomeBattle:
	extends "res://battle/battle.gd"
	func battle_opts(pb: Dictionary, n0: int, n1: int) -> Dictionary:
		var opts := super.battle_opts(pb, n0, n1)
		var rows := int(opts["h"]) - 2
		var middle := int(opts["w"]) / 2
		for side in 2:
			var cells := []
			for i in n0 if side == 0 else n1:
				cells.append(Vector2i(middle - 1 - i / rows if side == 0 else middle + i / rows, 1 + i % rows))
			opts["cells%d" % side] = cells
		return opts

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL fresh dragon combat: ", message)

func frames(tree: SceneTree, count: int = 3) -> void:
	for i in count:
		await tree.process_frame
		await RenderingServer.frame_post_draw

func capture(tree: SceneTree, name: String, directory: String) -> void:
	await frames(tree, 3)
	var path := directory.path_join("dragon_world_" + name + ".png")
	var pixels: Image = tree.root.get_texture().get_image()
	check(pixels.get_size() == Vector2i(2560, 1440) and pixels.save_png(path) == OK, "actual " + name + " capture")
	captures.append({"state": name, "path": path, "sha256": FileAccess.get_sha256(path), "width": 2560, "height": 1440})

func world_digest() -> String:
	return JSON.stringify(Game._serialize({"world": Game.world, "company": Game.company, "gold": Game.gold,
		"stash": Game.stash, "day": Game.day, "rng": str(Game.rng.state), "next_unit": Unit._next_uid, "next_item": Item._next_uid}), "", true, true).sha256_text()

func native_saved_values(a: Variant, b: Variant) -> bool:
	# The existing native disk writer rounds floats. Keep integral identities,
	# flags, wound kinds/losses and structure exact; allow only finite rounding.
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return is_finite(float(a)) and is_finite(float(b)) and absf(float(a) - float(b)) <= 0.000001 * maxf(1.0, absf(float(b)))
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not native_saved_values(a[key], b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not native_saved_values(a[i], b[i]): return false
		return true
	return a == b

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var directory := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): directory = arg.trim_prefix("--report-dir=").replace("\\", "/").simplify_path()
	check(DisplayServer.get_name() != "headless", "actual rendered native engine")
	check(directory.to_lower().begins_with(PRIVATE_WORK.to_lower()) and not DirAccess.dir_exists_absolute(directory), "fresh private report path")
	if fails > 0: return fails
	DirAccess.make_dir_recursive_absolute(directory)
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000); tree.root.size = Vector2i(2560, 1440)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 60
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var start := Time.get_ticks_usec()
	var generation := Game.new_game_begin(777)
	while not Game.new_game_slice(generation, 4000):
		if Time.get_ticks_usec() - start > 90000000: check(false, "bounded generation"); return fails
		await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		if Time.get_ticks_usec() - start > 120000000: check(false, "bounded one-day history"); return fails
		CampaignWorld.presim_slice(Game, history, 4000); await tree.process_frame
	CampaignWorld.presim_finish(Game, 0); Dynasty.prepare_world(Game); Game.new_game_finalize()
	Game._save_pending = false; Game.wait_save(); Game.set_process(false)
	var world_ms := float(Time.get_ticks_usec() - start) / 1000.0
	check(Game.day == 1.0 and Game.world.get("work", []).is_empty(), "exactly one fresh settled history day")
	check(Game.company.is_empty() and Game.gold == 0, "no automatically raised army or invented army coin")
	var uid := ""
	var tid := ""
	for dragon: Dictionary in Dragons.records(Game):
		if dragon.get("stage", "") != "adult" or not dragon.get("alive", false): continue
		var owner := Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty(): continue
		if str(dragon.get("location_town_id", "")) != str(owner["town_id"]): continue
		var available := false
		for local: Dictionary in Dragons.people(Game):
			if DragonBond._adult(local) and Dragons._present(local, str(owner["town_id"])):
				available = true; break
		if not available: continue
		var result := HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"]))
		if result.get("ok", false) and not DragonBond.candidates(Game, str(dragon["id"])).is_empty():
			uid = str(dragon["id"]); tid = str(owner["town_id"]); break
	check(uid != "", "generated adult dragon at its actual owning household home")
	if uid == "": return fails
	var dragon: Unit = Game.world["dragons"]["combat_units"].get(uid)
	check(dragon != null and DragonCombat.is_dragon_unit(Game, dragon) and not Game.company.has(dragon), "one actual independent persistent dragon body exists")
	if dragon == null: return fails
	var body := dragon.body
	var original_uid := dragon.uid
	var person: Dictionary = DragonBond.candidates(Game, uid)[0]
	var review := DragonBond.bind_preview(Game, uid, str(person["person_uid"]))
	check(DragonBond.bind(Game, uid, str(person["person_uid"]), review).get("ok", false), "actual local tracked person binds through native reviewed command")
	check(DragonCombat.battle_units(Game).is_empty(), "home defence starts OFF even with a valid bond")
	var coins := Barge.holdings(Game)
	var funding := Mobilization.fund(Game, int(floor(float(Feudal._payer(Game).get("purse", 0.0)) * 0.8)))
	var quote := Mobilization.quote(Game, tid, 8)
	check(funding.get("ok", false) and quote.get("ok", false) and quote.get("planned", 0) > 0, "actual private funds, population, food and gear permit native muster")
	if not quote.get("ok", false): return fails
	var muster := Mobilization.muster(Game, tid, 8, quote["review"])
	check(muster.get("ok", false) and Game.company.size() > 0 and not Game.company.has(dragon), "real residents enlist; dragon stays outside human roster")
	check(absf(Barge.holdings(Game) - coins) < 0.001, "native funding/muster conserve actual whole-world coin")
	var native_people := Game.company.duplicate()
	var wage := Game.daily_wages()
	var pure := world_digest()
	var defend := DragonCombat.participation_preview(Game, uid, true)
	check(defend.get("ok", false) and world_digest() == pure, "real home-defence review is pure and eligible")
	if not defend.get("ok", false): return fails
	check(DragonCombat.participation_order(Game, uid, true, defend).get("ok", false), "explicit unchanged defence review applies")
	check(DragonCombat.battle_units(Game).has(dragon) and Game.daily_wages() == wage, "same actual dragon admitted without human payroll")
	var enemy_id := ""
	for key in Game.world["warbands"]:
		var band: Dictionary = Game.world["warbands"][key]
		if band.get("faction", "") != Game.world["towns"][tid].get("faction", "") and Army.is_people_band(band) and not band.get("units", []).is_empty() and not Monsters.suspended_band(band):
			enemy_id = str(key); break
	check(enemy_id != "", "actual generated enemy people band exists")
	if enemy_id == "": return fails
	var enemy: Array = Game.world["warbands"][enemy_id]["units"].duplicate()
	Game.start_battle({"enemy": enemy, "allies": [], "warband_id": enemy_id, "seed": 9022, "terrain": "grassland", "map": "large", "max_ticks": 240})
	check(Game.pending_battle.get("dragon_units", []).has(dragon) and Game.company == native_people, "native entry borrows dragon and retains human service roster")
	var battle := HomeBattle.new(); tree.root.add_child(battle); battle.set_speed(0.0)
	var fighter_idx := -1
	for fighter: Fighter in battle.sim.fighters:
		if is_same(fighter.unit, dragon): fighter_idx = fighter.idx
	check(fighter_idx >= 0 and battle.views[fighter_idx].doll is DragonView, "actual native fighter renders through coherent dragon view")
	check(battle.sim.combat_journal.participant(fighter_idx).get("dragon_uid", "") == uid, "full journal participant carries real dragon identity")
	await capture(tree, "entry", directory)
	start = Time.get_ticks_usec()
	while not battle.sim.is_over():
		battle.step_ticks(4)
		await tree.process_frame
		if Time.get_ticks_usec() - start > 35000000: check(false, "bounded native battle finishes"); return fails
	var battle_ms := float(Time.get_ticks_usec() - start) / 1000.0
	var attacks := 0
	for event: Dictionary in battle.sim.events:
		if int(event.get("actor", -1)) == fighter_idx and event.get("type", "") == "attack": attacks += 1
	check(attacks > 0, "actual dragon automatically attacks through native sim")
	var result: Dictionary = battle.build_result()
	var physical_end := JSON.stringify(dragon.body.to_dict(), "", true, true)
	battle._journal_transferred = true
	Game.finish_battle(result)
	check(Game.world["dragons"]["combat_units"][uid] == dragon and is_same(dragon.body, body) and dragon.uid == original_uid, "finish keeps exact original dragon Unit/body/UID")
	check(not Game.company.has(dragon) and dragon.family == -1 and dragon.wage == 0, "dragon never gains human family/payroll claims")
	check(not result.get("dragon_combat_receipt", {}).is_empty(), "native finish records admitted dragon outcome")
	var settled := world_digest()
	Game.finish_battle(result)
	check(world_digest() == settled, "repeat finish cannot repeat native outcomes or accounting")
	battle.queue_free(); battle = null; await frames(tree, 3)
	var aftermath: Control = (load("res://battle/aftermath.tscn") as PackedScene).instantiate(); tree.root.add_child(aftermath)
	aftermath.call("toggle_section", "log"); await capture(tree, "log", directory)
	check(world_digest() == settled, "actual expandable end log is read-only")
	aftermath.queue_free(); aftermath = null; await frames(tree, 3)
	Game.goto("map")
	var map: Node2D = (load("res://campaign/world_map.tscn") as PackedScene).instantiate(); tree.root.add_child(map); map.set_process(false)
	await capture(tree, "map_return", directory)
	check(Game.pending_battle.is_empty() and Game.last_result.is_empty() and is_same(Game.world["dragons"]["combat_units"][uid], dragon), "real Continue releases result history while world owns original dragon")
	map.queue_free(); map = null; await frames(tree, 3)
	var ended := dragon.to_dict().duplicate(true)
	Game.save_game(); Game.wait_save()
	check(Game.load_game(), "current private native disk save reloads")
	var loaded: Unit = Game.world["dragons"]["combat_units"].get(uid)
	check(loaded != null and loaded.uid == original_uid and loaded.body.plan_id == "wyvern" and native_saved_values(loaded.body.to_dict(), ended["body"]), "loaded actual dragon retains original physical damage/UID with only native writer float rounding")
	check(Unit._next_uid > original_uid and not Game.company.has(loaded), "loaded native UID floor and independent ownership remain valid")
	var report := {"version": ProjectSettings.get_setting("application/config/version"), "world_size": "normal", "history_days": 1, "seed": 777, "town_id": tid,
		"dragon_uid": uid, "native_unit_uid": original_uid, "rider_person_uid": person["person_uid"], "actual_humanoids_raised": native_people.size(), "actual_enemy_band": enemy_id, "enemy_count": enemy.size(),
		"world_ready_ms": world_ms, "battle_ms": battle_ms, "ticks": result["ticks"], "dragon_native_attacks": attacks, "body_before_native_finish": physical_end.sha256_text(), "receipt": result.get("dragon_combat_receipt", {}),
		"captures": captures, "checks": checks, "failures": fails, "scope": "Actual fresh Normal/one-day real funded residents, whole genuine enemy band and one original dragon holder; explicit close-contact/native240tick bounded encounter, native finish/log/map/current private save; not a long battle/performance benchmark."}
	var file := FileAccess.open(directory.path_join("fresh-dragon-combat-world.json"), FileAccess.WRITE)
	check(file != null, "private actual report opens"); report["checks"] = checks; report["failures"] = fails
	if file != null: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("Fresh dragon combat world v022: ", checks, " checks, ", fails, " failures")
	return fails
