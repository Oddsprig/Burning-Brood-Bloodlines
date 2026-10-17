extends RefCounted
## Capture/read lifecycle against native fights. Never reconcile artificial troops.
const U := preload("res://tests/sim_util.gd")
const Pure := preload("res://tests/test_battle_visual_purity.gd")
const Browser := preload("res://battle/combat_log.gd")
const Screen := preload("res://battle/battle.gd")
var checks := 0
var fails := 0
var purity := Pure.new()

class PausedBattle extends "res://battle/battle.gd":
	func _ready() -> void:
		super._ready()
		paused = true
		set_process(false)
	func battle_opts(_pb: Dictionary, _n0: int, _n1: int) -> Dictionary:
		return {"w": 12, "h": 8, "max_ticks": 48, "log_moves": false,
			"cells0": [Vector2i(4,4)], "cells1": [Vector2i(5,4)]}
	func finish() -> void:
		push_error("Artificial history fixture must not reach campaign accounting")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL combat history: ", message)

func state(sim: BattleSim) -> String:
	return JSON.stringify(purity.mechanical(sim), "", true, true).sha256_text()

func escape() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE; e.pressed = true
	return e

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var saved_company: Array = Game.company
	var saved_pending: Dictionary = Game.pending_battle
	var saved_result: Dictionary = Game.last_result
	var saved_screen: String = Game._active_screen
	var saved_settings: Dictionary = Game.settings.duplicate(true)
	var game_rng: int = Game.rng.state
	var unit_counter: int = Unit._next_uid
	var item_counter: int = Item._next_uid
	var world_sha := JSON.stringify(Game._save_tree(), "", true, true).sha256_text()
	var probe := Screen.new()
	var live_options: Dictionary = probe.battle_opts({},1,1)
	check(live_options.get("history_events") == 8192 and live_options.get("history_log") == 512, "small and large actual battle presentation tails stay bounded beside complete history")
	probe.free()
	var left := U.soldier("copper")
	var right := U.make("orc", [["hacking_cleaver","copper"],["tunic","linen"]], {"axe":4,"fighter":3})
	Food.roll_fav_drink(left, hash([left.uid,left.name]))
	Food.roll_fav_drink(right, hash([right.uid,right.name]))
	var left_plain := left.to_dict().duplicate(true)
	var right_plain := right.to_dict().duplicate(true)
	var options := {"w":12,"h":8,"max_ticks":48,"log_moves":false,
		"cells0":[Vector2i(4,4)],"cells1":[Vector2i(5,4)]}
	var sim := BattleSim.new()
	var control := BattleSim.new()
	sim.setup([left],[right],321,options)
	var no_journal := options.duplicate(true)
	no_journal["combat_journal"] = false
	control.setup([Unit.from_dict(left_plain.duplicate(true))],[Unit.from_dict(right_plain.duplicate(true))],321,no_journal)
	check(state(sim) == state(control), "native setup identical with capture on/off")
	check(sim.combat_journal != null and control.combat_journal == null, "normal capture enabled; explicit diagnostic control disables only capture")
	for tick in 48:
		if sim.is_over(): break
		sim.step(); control.step()
		check(state(sim) == state(control), "capture preserves complete native fight and RNG tick %d" % sim.tick)
	var before := state(sim)
	var journal := sim.combat_journal
	var initial_count: int = journal.count()
	var hits := 0
	for event: Dictionary in sim.events:
		if event.get("type") == "hit": hits += 1
	check(hits > 0 and initial_count >= sim.events.size(), "actual native attacks/hits and log-only outcomes recorded")
	var pages: int = ceili(float(initial_count) / 18.0)
	for page in pages:
		for record: Dictionary in journal.page(page, -1, 18):
			CombatText.render(record["entry"])
	check(state(sim) == before and Game.rng.state == game_rng, "reading every native outcome preserves bodies, rolls and tick")
	var alias: Array = journal.page(0, -1, 18)
	if not alias.is_empty():
		alias[0]["entry"]["tamper"] = true
		check(not journal.page(0,-1,18)[0]["entry"].has("tamper"), "returned entry is detached from complete history")
	# Exercise the actual emit/trim hooks past BOTH inherited tails, no long battle run.
	sim.history_event_limit = 8192
	sim.history_log_limit = 512
	for index in 8300:
		sim._ev_simple("rally",0,1,"officer_rally",{"marker":index,"morale_before":12.0,"morale_after":35.0,"commander_uid":left.uid,"leader_level":3,"radius":6,"distance":1})
	sim._trim_history()
	check(sim.events_dropped > 0 and sim.events.size() <= 8192, "native presentation event tail still bounded")
	check(int(sim.log_dropped.get(0,0)) > 0 and sim.fighters[0].log.size() <= 512, "native per-person tail still bounded")
	check(journal.count() == initial_count + 8300 and journal.stats().get("complete",false), "full capture predates both native truncations")
	for marker: int in [0,4150,8299]:
		var sequence := initial_count + marker
		var records: Array = journal.page(sequence / 18,-1,18)
		var record: Dictionary = records[sequence % 18]
		check(int(record["entry"]["d"]["marker"]) == marker, "whole first/middle/last emitted outcomes survive %d" % marker)
	check(journal.count(0) >= 8300 and journal.count(1) >= 8300, "commander and recipient individual views share actual rally records")
	var last: Dictionary = journal.page((journal.count()-1)/18,-1,18).back()
	var rendered := CombatText.render(last["entry"])
	check(String(rendered.get("text","")).contains("rejoins") and String(rendered.get("calc","")).contains("12.0 -> 35.0"), "officer event describes actual order/morale numbers")
	var original_path: String = String(journal.stats().get("directory", ""))
	Game.company = [Unit.from_dict(left_plain.duplicate(true))]
	Game.pending_battle = {"enemy":[Unit.from_dict(right_plain.duplicate(true))],"seed":321,"terrain":"plains"}
	var battle := PausedBattle.new()
	tree.root.add_child(battle)
	var battle_sha := state(battle.sim)
	var battle_journal := battle.sim.combat_journal
	var battle_path: String = String(battle_journal.stats().get("directory", ""))
	battle.paused = false
	battle.open_combat_log()
	check(battle.paused and is_instance_valid(battle._log_overlay), "open during running playback holds the actual battle")
	var browser: Control = battle._log_overlay.find_child("BattleLogBrowser",true,false)
	check(browser != null and int(browser.detail_stats().get("participant",-2)) == -1, "running log opens whole fight")
	browser.set_participant(0); browser.turn_page(1)
	battle._process_battle(0.2)
	check(state(battle.sim) == battle_sha, "paused log input/paging/presentation never advances simulation")
	battle._unhandled_input(escape())
	check(not battle.paused and not is_instance_valid(battle._log_overlay), "Esc closes log and restores prior running playback")
	battle.paused = true
	battle.select(0)
	var history_button: Button = battle.inspector.find_child("InspectorFullHistory",true,false)
	history_button.pressed.emit()
	check(battle.paused and int(battle._log_overlay.find_child("BattleLogBrowser",true,false).detail_stats()["participant"]) == 0, "inspector opens selected fighter full history")
	battle.close_combat_log()
	check(battle.paused, "closing selected history restores prior pause")
	battle.queue_free()
	await tree.process_frame
	check(bool(battle_journal.stats().get("disposed",false)), "leaving unfinished battle explicitly disposes its transient journal")
	if battle_path != "": check(not DirAccess.dir_exists_absolute(battle_path), "unfinished battle temporary files removed")
	var transferred := PausedBattle.new()
	tree.root.add_child(transferred)
	var retained := transferred.sim.combat_journal
	var retained_count: int = retained.count()
	Game.last_result = transferred.build_result() # Native one-time finalization, no campaign reward handback.
	transferred.queue_free()
	await tree.process_frame
	check(not bool(retained.stats().get("disposed",true)) and retained.count() >= retained_count, "actual result ownership survives battle scene removal")
	Game._release_result_history()
	check(bool(retained.stats().get("disposed",false)), "result owner releases the transferred native history")
	Game.last_result = {"combat_journal":journal}
	Game._active_screen = "aftermath"
	Game.goto("company")
	check(bool(journal.stats().get("disposed",false)) and Game.last_result.is_empty(), "Continue/result exit disposes history even if another reader held reference")
	if original_path != "": check(not DirAccess.dir_exists_absolute(original_path), "completed result temporary files removed")
	Game.company = saved_company; Game.pending_battle = saved_pending; Game.last_result = saved_result
	Game._active_screen = saved_screen; Game.settings = saved_settings
	Game.invalidate_deploy()
	Unit._next_uid = unit_counter; Item._next_uid = item_counter
	check(JSON.stringify(Game._save_tree(),"",true,true).sha256_text() == world_sha and Game.rng.state == game_rng, "fixture restores complete campaign state/RNG/UIDs without handback")
	print("Combat history integration v016: %d checks, %d failures" % [checks,fails])
	return fails
