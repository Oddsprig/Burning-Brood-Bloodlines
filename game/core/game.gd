extends Node
## Autoload "Game": the campaign state and screen switching.
## Ownership: core fields live here. Workstreams extend behaviour from their own files
## (campaign/world.gd, ui/outfit.gd, sim/healing.gd ...) instead of growing this file.

signal changed
signal screen_changed(screen: String)
signal setting_changed(key: String, value: Variant)

## Tests redirect saves/settings (tests/runner.gd) so they never touch the player's real save.
var SAVE_PATH := "user://save.json"
const SCREENS := {
	"title": "res://ui/title.tscn",
	"map": "res://campaign/world_map.tscn",
	"town": "res://ui/town.tscn",
	"company": "res://ui/company.tscn",
	"muster": "res://ui/muster.tscn",
	"battle": "res://battle/battle.tscn",
	"aftermath": "res://battle/aftermath.tscn",
	"settings": "res://ui/settings.tscn",
	"gameover": "res://ui/gameover.tscn",
	"victory": "res://ui/victory.tscn",
	"court": "res://ui/court.tscn",
	"house_select": "res://ui/house_select.tscn",
	"house": "res://ui/house.tscn",
	"laws": "res://ui/house_laws.tscn",
	"dragons": "res://ui/dragons.tscn",
	"politics": "res://ui/politics.tscn",
	"population": "res://ui/population.tscn",
	"presim": "res://ui/presim.tscn",   # a new campaign: the years before (campaign/world.gd presim_step)
	"newgame": "res://ui/newgame.tscn",   # New Campaign options: world size and the years before (then presim)
}
const LOOT_FRACTION := 0.25   # loot gold = fraction of defeated enemy gear value (handoff decision)
const START_COMPANY_SIZE := 100

var seed_value: int = 0
var rng := RandomNumberGenerator.new()
var day: float = 0.0
var gold: int = 0
var company: Array = []          # Array[Unit], includes captain, officers, troops, and the dead are removed
var stash: Array = []            # Array[Item], company storage
## squads[officer_uid] = {"uniform": {slot: template_id}, "material": "any"|"copper"|"tin"}
var squads: Dictionary = {}
var rep: Dictionary = {}         # faction_id -> int (-100..100)
var world: Dictionary = {}       # owned by campaign/world.gd (towns, warbands, party position, contracts)
var location: String = ""        # town id when inside a town
var contract: Dictionary = {}    # active contract (see campaign/contracts.gd)
var pending_battle: Dictionary = {}  # {"enemy": Array[Unit], "allies": Array[Unit], "contract": {}, "map": "small"|"large", "seed": int, "terrain": String}
var last_result: Dictionary = {}     # filled by finish_battle, read by the aftermath screen
var screen_params: Dictionary = {}
## Food and drink (core/food.gd): stock lots {"meal"|"beer"|"wine": [[qty, age_days], ...]}, company-wide rations,
## and the meal clock (next tick time, last drain time, marching time since).
var provisions: Dictionary = {"meal": [], "beer": [], "wine": []}
var rations: Dictionary = {"food": "normal", "drink": "ration"}
var food_clock: Dictionary = {}
var main: Node = null            # set by main.gd; holds the active screen
var _active_screen := "title"    # runtime only; pending jobs also settle in paused campaign views

func _exit_tree() -> void:
	DragonArt.finish_warm()   # worker threads painting dragon pigment must finish before the engine exits

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # capture slices keep running while the campaign is held
	rng.randomize()
	load_settings()

# ---------------------------------------------------------------- screens
func goto(screen: String, params: Dictionary = {}) -> void:
	if _active_screen in ["aftermath", "gameover"] and screen not in ["aftermath", "gameover"]:
		_release_result_history()
		last_result = {}   # results have been consumed; release their combatants and event payload
	_active_screen = screen
	screen_params = params
	if main != null:
		main.show_screen(SCREENS.get(screen, screen))
	screen_changed.emit(screen)

## Complete combat histories are transient; only the current battle/results own them.
func _release_result_history() -> void:
	var journal = last_result.get("combat_journal")
	if journal is CombatJournal: journal.dispose()
	Perf.record_combat_history()

# ---------------------------------------------------------------- company helpers
## The company is officers and their troops; its leader is separate from the selected ruling person.
## lead_officer() is the first living officer (default company selection).
func lead_officer() -> Unit:
	for u in company:
		if u.is_officer() and not u.dead:
			return u
	return null

## A selected campaign ends only when its registered founding dynasty has no living members.
## An unselected generated world is still onboarding. Standalone combat retains its company fallback.
func is_game_over() -> bool:
	if not Dynasty.selected(self).is_empty():
		return Dynasty.is_extinct(self)
	if world.has("towns"):
		return false
	return company.filter(func(u): return not u.dead).is_empty()

func officers() -> Array:
	return company.filter(func(u): return u.is_officer())

func squad_of(officer_uid: int) -> Array:
	return company.filter(func(u): return u.squad == officer_uid and not u.is_officer())

func unit_by_uid(uid: int) -> Unit:
	for u in company:
		if u.uid == uid:
			return u
	return null

## Units that will take the field: living, not benched, and able to fight. A unit that "cannot fight"
## (unconscious, can't stand, can't hold a weapon, blind, collapsed from blood loss, critical wound)
## stays in camp. Units that "should rest" may still fight hurt.
## Cached: fitness needs a full health report per unit, far too slow to run every map frame. The cache
## refreshes when healing runs (hourly), after battles, on load, and when the company changes size.
var _deploy_rev := 0
var _deploy_key := []
var _deploy_cache: Array = []

func invalidate_deploy() -> void:
	_deploy_rev += 1
	_deploy_cache.clear()
	_deploy_key.clear()

func deployed_units() -> Array:
	var key := [_deploy_rev, company.size()]
	if key != _deploy_key:
		_deploy_cache = company.filter(func(u): return deploy_block_reason(u) == "")
		_deploy_key = key
	return _deploy_cache.filter(func(u): return not u.dead and not u.get_meta("benched", false))

## "" if the unit can deploy, else a short reason for the roster card. report: the unit's HealthReport.describe when
## the caller already has it (the roster card does: one report per man instead of two).
func deploy_block_reason(u: Unit, report: Dictionary = {}) -> String:
	if u.dead:
		return "dead"
	if u.get_meta("benched", false):
		return "benched"
	if Mobilization.is_medic(self, u):
		return "battle medic"
	if report.has("fitness"):
		return "too hurt to fight" if report["fitness"] == "cannot fight" else ""
	var H = load("res://sim/healing.gd") if ResourceLoader.exists("res://sim/healing.gd") else null
	if H != null and H.fitness_text(u) == "cannot fight":
		return "too hurt to fight"
	return ""

func daily_wages() -> int:
	var w := 0
	for u in company:
		w += u.wage
	return w

## Daily wages, man by man while the gold lasts (officers first, then in roster order); gold never goes below
## zero. A man not paid that day counts an unpaid day (unpaid_days; desertion and morale come with economy
## spec 2). The coins paid go to each man's family purse (campaign/people.gd, via world.gd wages_paid).
func pay_wages(days: int) -> void:
	if not company.is_empty() and not world.is_empty():   # house arms: drill every mustered day, conditioning on the road
		for i in days: ArmsPool.day(self, "player", CampaignWorld.is_travelling(self))
	var order: Array = company.filter(func(u): return u.is_officer()) + company.filter(func(u): return not u.is_officer())
	var W = load("res://campaign/world.gd") if ResourceLoader.exists("res://campaign/world.gd") else null
	for d in days:
		for u in order:
			if u.dead or u.wage <= 0:
				continue
			var received := 0.0
			if gold >= u.wage:
				if W != null and W.has_method("wages_paid") and world.has("towns"):
					received = float(W.wages_paid(self, [[u, u.wage]]))
				else:
					received = float(u.wage)   # standalone play without the campaign economy hook
			if received == float(u.wage):
				gold -= u.wage
				u.unpaid_days = 0
				u.last_pay = received
			else:
				u.unpaid_days += 1
				u.last_pay = 0.0
	if world.has("towns"):
		Warfare.daily(self, days)

func unpaid_count() -> int:
	return company.filter(func(u): return not u.dead and u.unpaid_days > 0).size()

# ---------------------------------------------------------------- new game
func new_game(game_seed: int = 0) -> void:
	var generation := new_game_begin(game_seed)
	while not new_game_slice(generation, 0):
		pass
	new_game_finalize()   # synchronous callers own their subsequent history work

## Shared initialization for synchronous callers and the visible startup screen.
## The returned state belongs to the caller and is never added to the saved world.
func new_game_begin(game_seed: int = 0) -> Dictionary:
	wait_save()   # no old snapshot may publish after the world is replaced
	_save_pending = false
	_save_epoch += 1
	_save_ready = false
	seed_value = game_seed if game_seed != 0 else randi()
	rng.seed = seed_value
	day = 0.0
	gold = 0 # The selected native household funds a field army explicitly.
	company.clear(); stash.clear(); squads.clear(); rep.clear(); world.clear()
	Unit._next_uid = 1   # a new world numbers its people and things from 1 (same seed = same world, same ids)
	_release_result_history()
	contract = {}; location = ""; pending_battle = {}; last_result = {}
	invalidate_deploy()
	for fid in DB.factions:
		rep[fid] = -40 if DB.factions[fid].get("player_hostile", false) else 0
	Food.init_company(self, 0.0)
	if ClassDB.class_exists("World") or ResourceLoader.exists("res://campaign/world.gd"):
		var W = load("res://campaign/world.gd")
		if W != null and W.has_method("generate_begin"):
			return W.generate_begin(self, rng)
	return {"generation_unavailable": true}

## Visible startup calls this only after generation, native history and dynasty initialization.
func new_game_finalize() -> void:
	_save_ready = true
	if world.has("dragons"): DragonArt.warm(Dragons.records(self))   # pigment dragon art on worker threads
	if _save_pending: save_game_async()

## Emits changed once, when the full world is safe for screens and saving to read.
func new_game_slice(generation: Dictionary, budget_usec: int) -> bool:
	if generation.is_empty():
		return true
	if generation.get("generation_unavailable", false):
		generation.clear()
		changed.emit()
		return true
	if CampaignWorld.generate_slice(self, generation, budget_usec):
		changed.emit()
		return true
	return false

func _make_starting_company() -> void:
	# The player is the captain (off the field); the company starts with four officers and their squads.
	var picks := [["middle_kingdom", 1], ["northern_clans", 1], ["northern_clans", 0], ["middle_kingdom", 0]]
	for p in picks:
		var off := Factory.make_troop(rng, p[0], DB.factions[p[0]]["troops"][p[1]], 2)
		off.role = "officer"; off.faction = "player"; off.wage = 12 * Item.COIN
		for s in off.skills:
			if off.skills[s] > 0:
				off.skills[s] += 1
		company.append(off)
		squads[off.uid] = {"uniform": {}, "material": "any"}
		for i in range(int(START_COMPANY_SIZE / picks.size()) - 1):
			var tr := Factory.make_troop(rng, p[0], DB.factions[p[0]]["troops"][p[1]], 1)
			tr.faction = "player"; tr.squad = off.uid; tr.wage = 4 * Item.COIN
			company.append(tr)
		# Uniform rule defaults to the officer's own troop template loadout (first choices).
		var lo: Dictionary = DB.factions[p[0]]["troops"][p[1]]["loadout"]
		for slot in lo:
			if lo[slot][0] != "":
				squads[off.uid]["uniform"][slot] = lo[slot][0]

# ---------------------------------------------------------------- battle hand-off
func start_battle(params: Dictionary) -> void:
	if not world.is_empty() and not Monsters.campaign_creatures_enabled():
		if Monsters.creature_units(params.get("enemy", [])) or Monsters.creature_units(params.get("allies", [])):
			return
	pending_battle = params
	if not pending_battle.has("seed"):
		pending_battle["seed"] = rng.randi()
	for u in company:   # v0.014: a legendary piece's carriers go in its history
		Legends.touch_unit(u)
	Food.sync(self)                       # digestion and buzz up to now (the morning mug lands before a battle)
	Food.spawn_battle(self, pending_battle)   # enemies: belly/buzz from their supply and race
	BowsEcon.fill_company_quivers(self)      # bows: quivers topped up from the company's arrows
	# Borrow actual prepared dragon bodies only after the suspended-monster guard.
	# Eligibility is rechecked at this real home encounter; no travel or people mint.
	var dragons: Array = DragonCombat.battle_units(self)
	pending_battle["dragon_units"] = dragons
	pending_battle["dragon_admission"] = DragonCombat.admission_receipt(self, dragons)
	# Large battles go in rounds of 100 v 100 (campaign/battle_rounds.gd); small ones stay one clash.
	var whole0: Array = deployed_units() + pending_battle.get("allies", [])
	for dragon in dragons:
		if not whole0.has(dragon): whole0.append(dragon)
	ArmsPool.apply(self, whole0); ArmsPool.apply(self, pending_battle.get("enemy", []))   # house arms experience
	if not pending_battle.has("rounds") and BattleRounds.wanted(whole0, pending_battle.get("enemy", [])):
		BattleRounds.begin(self, whole0, pending_battle.get("enemy", []))
	goto("battle")

## Called by the battle screen when the sim ends.
## result = {"winner": 0 (player) | 1 (enemy) | -1, "player_units": Array[Unit], "enemy_units": Array[Unit],
##           "enemy_fallen": Array[Unit] (dead or fled), "events": Array}
func finish_battle(result: Dictionary) -> void:
	if bool(result.get("_finish_applied", false)):
		return
	result["_finish_applied"] = true
	if not result.has("rounds"):   # one-clash battle: the house arms pools learn here (rounds do it per round)
		var fu: Array = result.get("fighter_units", []); var fs: Array = result.get("fighter_states", [])
		for side in 2:
			var mine: Array = fu.filter(func(u): return u is Unit and (company.has(u) == (side == 0)))
			var dead: Array = mine.filter(func(u): return u.dead and not Army.house_born(u) and not DragonCombat.is_dragon_unit(self, u))
			ArmsPool.after_fight(self, ArmsPool.key_for_units(self, mine), mine.size(), int(result.get("winner", -1)) == side, dead)
		var acc := {}
		Ennoble.tally(self, result, [], acc)
		result["raised"] = Ennoble.grant(self, int(result.get("winner", -1)), acc)   # a great deed: raised to the nobility
	var loot := 0
	var salvage_records: Array = []
	var dead_names := []
	var won := int(result.get("winner", -1)) == 0
	var kept_items := []
	var kept_from_dead := 0
	if won:
		var sp := Loot.spoils(result.get("enemy_units", []).filter(func(x): return x is Unit and not company.has(x) and not DragonCombat.is_dragon_unit(self, x)),
			result.get("enemy_fled", []), int(pending_battle.get("seed", 0)) + 77, loot_fraction(), "your company")
		loot = int(sp["coin"])
		result["loot_coin"] = int(sp["coin"])
		kept_items = sp["items"]
		stash.append_array(kept_items)
		result["scrap_kg"] = sp["scrap_kg"]   # Offered physical mass; only paid pieces enter market stock.
		salvage_records.append_array(sp.get("salvage", []))
		# The company holds the field: its dead men's gear comes back to the stash.
		for u in company:
			if u.dead:
				for s in u.equip.keys():
					stash.append(u.equip[s]); kept_from_dead += 1
				u.equip.clear()
		# bows: arrows recovered from the field (broken ones are scrap), the enemy's quivers, the dead men's quivers
		result["arrows_got"] = BowsEcon.after_battle(self, result, sp.get("arrows", {}))
	# Broken kit keeps its exact identity until a funded market accepts the whole piece.
	var own_broken := []
	for it in stash:
		if it.broken:
			own_broken.append(it)
	for it in own_broken:
		stash.erase(it)
	var own_scrap := Loot.strip_broken(company, salvage_records)
	for it in own_broken:
		own_scrap[it.material] = float(own_scrap.get(it.material, 0.0)) + it.mass()
		salvage_records.append(Salvage.record(it, "scrap", "own", 0))
	if not own_scrap.is_empty():
		var sc: Dictionary = result.get("scrap_kg", {})
		Loot.add_kg(sc, own_scrap)
		result["scrap_kg"] = sc
		result["own_scrap_kg"] = own_scrap
	gold += loot
	var H = load("res://sim/healing.gd") if ResourceLoader.exists("res://sim/healing.gd") else null
	Food.after_battle(company)   # -10 belly for the fight; battle-only food/drink multipliers off
	Food.after_battle(result.get("enemy_units", []).filter(func(x): return x is Unit and not company.has(x) and not DragonCombat.is_dragon_unit(self, x)))
	for u in company.duplicate():
		if H != null and not u.dead:
			H.after_battle(u)
		u.battles += 1
		if u.dead:
			dead_names.append(u.name)
			company.erase(u)
			squads.erase(u.uid)
			for t in company:
				if t.squad == u.uid:
					t.squad = -1
	result["loot_gold"] = loot
	result["loot_items"] = kept_items
	result["fallen_gear"] = kept_from_dead
	result["dead_names"] = dead_names
	var sale := Salvage.finalize(self, result, salvage_records, world.get("party", {}).get("pos", Vector2.ZERO))
	result["loot_gold"] = loot + int(sale.get("paid", 0))
	result["scrap_gold"] = int(sale.get("scrap_paid", 0))
	result["scrap_paid"] = result["scrap_gold"]
	result["dragon_combat_receipt"] = DragonCombat.on_battle_result(self, result, pending_battle.get("dragon_admission", {}))
	last_result = result
	var W = load("res://campaign/world.gd") if ResourceLoader.exists("res://campaign/world.gd") else null
	if W != null and W.has_method("on_battle_result"):
		W.on_battle_result(self, result)
	if world.has("feudal"):
		Feudal.finish(self)
	Warfare.after_battle(self, result, pending_battle)
	pending_battle = {}
	invalidate_deploy()
	changed.emit()
	if is_game_over():
		goto("gameover")
	else:
		goto("aftermath")

# ---------------------------------------------------------------- time
## Advances campaign time. Healing (sim/healing.gd) and wages hook in here.
## healer_skill (optional): skill of the town healer tending the company while resting.
const HEAL_STEP := 4.0 / 24.0   # heal in 4-hour batches on the map (each batch is ~3 ms for a full company)
var _heal_acc := 0.0

func advance_time(days: float, in_town: bool = false, healer_skill: int = 0, work_budget_usec: int = 0) -> void:
	if _save_capture != null: return   # a multi-frame capture owns one complete campaign instant
	var started := Time.get_ticks_usec()
	# A loaded or just-entered town can retain a previous midnight. Finish that
	# exact ordered queue before wages/calendar or a later census are advanced.
	if not world.get("work", []).is_empty():
		var pending_started := Time.get_ticks_usec()
		if work_budget_usec > 0:
			CampaignWorld.work_slice(self, work_budget_usec)
			changed.emit()
			Perf.record_us("Pending campaign jobs", Time.get_ticks_usec() - pending_started)
			return
		while not world.get("work", []).is_empty():
			CampaignWorld.work_slice(self, 4000)
		Perf.record_us("Pending campaign jobs", Time.get_ticks_usec() - pending_started)
	var part := Time.get_ticks_usec()
	var before := int(floor(day))
	day += days
	var whole := int(floor(day)) - before
	if whole > 0:
		pay_wages(whole)
	Perf.record_us("Company wages", Time.get_ticks_usec() - part)
	part = Time.get_ticks_usec()
	# Healing runs in 4-hour batches, not every map frame (it was most of the per-frame cost).
	_heal_acc += days
	if _heal_acc >= HEAL_STEP or in_town:
		var H = load("res://sim/healing.gd") if ResourceLoader.exists("res://sim/healing.gd") else null
		if H != null and H.has_method("heal"):
			for u in company:
				H.heal(u, _heal_acc, in_town, healer_skill)
			# Home reserves keep their actual wounded bodies, without field payroll
			# or field meals. Native household food/sickness still owns their care.
			for u in Mobilization.reserves(self).duplicate():
				if u.dead: continue
				H.heal(u, _heal_acc, true, 0)
				if u.dead:
					Census.note_fate(world, u.uid, "wounds", "died of wounds at home")
					People.casualty(self, u, "dead", "reserve")
		_heal_acc = 0.0
	if whole > 0 or in_town:
		invalidate_deploy()   # fitness changes slowly; recheck once a day (it costs a health report per unit)
	Perf.record_us("Company healing", Time.get_ticks_usec() - part)
	part = Time.get_ticks_usec()
	# food and drink: meals/drinks at the morning, midday and evening ticks (a float compare per frame otherwise)
	Food.on_time(self, days, in_town)
	Perf.record_us("Company meals", Time.get_ticks_usec() - part)
	part = Time.get_ticks_usec()
	# strategy layer: party travel, warbands, daily spawns, town refresh, contract deadlines
	var Wt = load("res://campaign/world.gd") if ResourceLoader.exists("res://campaign/world.gd") else null
	if Wt != null and Wt.has_method("on_time"):
		Wt.on_time(self, days, in_town, work_budget_usec)
	Perf.record_us("Campaign update", Time.get_ticks_usec() - part)
	part = Time.get_ticks_usec()
	changed.emit()
	Perf.record_us("State notifications", Time.get_ticks_usec() - part)
	Perf.record_us("Time advance", Time.get_ticks_usec() - started)
	if work_budget_usec <= 0:
		Perf.record_us("Time advance", Time.get_ticks_usec() - started, true)

# ---------------------------------------------------------------- save / load
func save_game() -> void:
	wait_save()
	if not _save_ready:
		_save_pending = true
		return
	_accept_save_receipt(_write_save(SAVE_PATH, _save_tree()))

## A real-world snapshot uses bounded main-thread slices under a simulation hold.
## Only detached plain data reaches the JSON/file worker. One snapshot + dirty flag;
## replacement/loading/closing flush ownership, and incomplete startup never publishes.
var _save_task := -1
var _save_pending := false
var _save_ready := true
var _save_epoch := 0
var _save_receipt: Dictionary = {}
var _save_capture: SaveSnapshot
var _save_was_paused := false
var _save_started_us := 0
var _save_status := {"started":0,"completed":0,"failed":0,"last_snapshot_us":0,
	"last_encode_us":0,"last_write_us":0,"serialized_bytes":0,"last_ok":true,"last_stage":"idle","last_error":0,
	"last_release_us":0,
	"capture_slices":0,"capture_begin_us":0,"capture_worst_us":0,"capture_wall_us":0,"unit_records":0,"item_records":0,"reused_records":0}
const SAVE_SLICE_US := 6000

func _process(_delta: float) -> void:
	if _save_capture != null:
		var slice_start := Time.get_ticks_usec()
		if _save_capture.step(SAVE_SLICE_US): _finish_capture()
		Perf.record_us("Autosave capture slice", Time.get_ticks_usec()-slice_start, true)
		return
	if _save_task != -1 and WorkerThreadPool.is_task_completed(_save_task):
		_retire_save()
	if _save_pending and _save_task == -1 and _save_ready and _active_screen not in ["battle", "presim", "newgame"]:
		save_game_async(true)
		return
	if not get_tree().paused and _active_screen in ["town", "company", "muster", "house", "laws", "dragons", "politics", "population", "settings", "house_select"] and not world.get("work", []).is_empty():
		var started := Time.get_ticks_usec()
		if CampaignWorld.work_slice(self, 4000) > 0:
			changed.emit()
		Perf.record_us("Paused campaign jobs", Time.get_ticks_usec() - started, true)
		Perf.set_stage("Settling campaign jobs")

func save_game_async(from_process: bool = false) -> void:
	# Retain one in-flight snapshot. Repeated requests are a single dirty flag;
	# the newest state is copied only after the current write has completed.
	if not _save_ready or _save_capture != null or _active_screen == "battle":
		_save_pending = true
		return
	if world.get("towns", []).size() > 8 and not from_process:
		_save_pending = true   # begin after the requesting input/scene callback has finished
		return
	if _save_task != -1:
		if not WorkerThreadPool.is_task_completed(_save_task):
			_save_pending = true
			return
		_retire_save()
	_save_pending = false
	_save_started_us = Time.get_ticks_usec()
	_save_status["started"] += 1
	# Real worlds are copied in small slices while simulation/input mutations are held.
	# Small standalone fixtures remain atomic without paying a frame scheduling delay.
	if world.get("towns", []).size() > 8:
		_save_was_paused = get_tree().paused
		get_tree().paused = true
		_save_capture = SaveSnapshot.new()
		_save_capture.begin(self)
		return
	var started := Time.get_ticks_usec()
	var d := _save_tree()
	_save_status["last_snapshot_us"] = Time.get_ticks_usec()-started
	Perf.record_us("Autosave snapshot", Time.get_ticks_usec() - started)
	_start_writer(d)

func _finish_capture() -> void:
	_save_status["last_snapshot_us"] = _save_capture.total_us
	_save_status["capture_slices"] = _save_capture.slices
	_save_status["capture_begin_us"] = _save_capture.begin_us
	_save_status["capture_worst_us"] = _save_capture.worst_us
	_save_status["capture_wall_us"] = Time.get_ticks_usec()-_save_started_us
	_save_status["unit_records"] = _save_capture.unit_records
	_save_status["item_records"] = _save_capture.item_records
	_save_status["reused_records"] = _save_capture.reused_records
	var d := _save_capture.take()
	_save_capture = null
	if is_inside_tree(): get_tree().paused = _save_was_paused
	_start_writer(d)

func _start_writer(d: Dictionary) -> void:
	_save_receipt = {}
	_save_task = WorkerThreadPool.add_task(_save_worker.bind(SAVE_PATH, d, _save_receipt), false, "autosave")

static func _save_worker(path: String, d: Dictionary, receipt: Dictionary) -> void:
	receipt.merge(_write_save(path,d),true)
	var started := Time.get_ticks_usec()
	d.clear()   # destroy the large plain snapshot here, before its bound callable retires on main
	receipt["release_us"] = Time.get_ticks_usec()-started

func _retire_save() -> void:
	WorkerThreadPool.wait_for_task_completion(_save_task)
	_save_task = -1
	if not _save_receipt.is_empty(): _accept_save_receipt(_save_receipt)
	_save_receipt = {}

func _accept_save_receipt(receipt: Dictionary) -> void:
	_save_status["last_ok"] = receipt["ok"]
	_save_status["last_stage"] = receipt["stage"]
	_save_status["last_error"] = receipt["error"]
	_save_status["serialized_bytes"] = receipt["serialized_bytes"]
	_save_status["last_encode_us"] = receipt["encode_us"]
	_save_status["last_write_us"] = receipt["write_us"]
	_save_status["last_release_us"] = receipt.get("release_us",0)
	_save_status["completed" if receipt["ok"] else "failed"] += 1
	Perf.record_us("Autosave worker encode",receipt["encode_us"])
	Perf.record_us("Autosave worker write",receipt["write_us"])

func save_stats() -> Dictionary:
	var stats := _save_status.duplicate()
	stats.merge({"active_snapshots":int(_save_task != -1 or _save_capture != null),"pending":_save_pending,
		"ready":_save_ready,"epoch":_save_epoch,"capturing":_save_capture != null,
		"age_s":float(Time.get_ticks_usec()-_save_started_us)/1000000.0 if _save_task != -1 or _save_capture != null else 0.0})
	return stats

func wait_save() -> void:
	if _save_capture != null:
		_save_capture.step(0)
		_finish_capture()
	if _save_task != -1:
		_retire_save()
	if _save_pending and _save_ready:
		_save_pending = false
		_accept_save_receipt(_write_save(SAVE_PATH, _save_tree()))

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE, NOTIFICATION_APPLICATION_PAUSED]:
		wait_save()   # never quit (or go to the phone's background) half way through writing the save
	if what == NOTIFICATION_PREDELETE and ResourceLoader.has_cached("res://campaign/map_terrain.gd"):
		load("res://campaign/map_terrain.gd").free_cache()   # the map layer's kept decor canvas items

## Written to a side file first, then moved over the save: a crash mid-write leaves the old save whole.
static func _write_save(path: String, d: Dictionary) -> Dictionary:
	var tmp := path + ".tmp"
	var result := {"ok":false,"error":OK,"stage":"open","serialized_bytes":0,"encode_us":0,"write_us":0}
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		result["error"] = FileAccess.get_open_error()
		return result
	var started := Time.get_ticks_usec()
	var text := JSON.stringify(d)
	result["encode_us"] = Time.get_ticks_usec()-started
	started = Time.get_ticks_usec()
	f.store_string(text)
	text = ""
	f.flush()
	result["error"] = f.get_error()
	result["serialized_bytes"] = f.get_position()
	f.close()
	result["write_us"] = Time.get_ticks_usec()-started
	result["stage"] = "write"
	if result["error"] == OK:
		result["stage"] = "rename"
		result["error"] = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if result["error"] == OK:
		result["ok"] = true
		result["stage"] = "complete"
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	return result

## The save as plain data. Everything outside world and contract is deep-copied (small); _serialize copies every
## container it walks and to_dict output is deep-copied, so nothing in it is shared with the live game.
func _save_tree() -> Dictionary:
	var snapshot := SaveSnapshot.new()
	snapshot.begin(self)
	snapshot.step(0)
	return snapshot.take()

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func load_game() -> bool:
	wait_save()
	if not has_save():
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if d == null:
		return false
	_save_epoch += 1
	_save_ready = true
	_save_pending = false
	_release_result_history()
	pending_battle = {}; last_result = {}
	Unit._next_uid = maxi(1, int(d.get("next_unit_uid", 1)))
	seed_value = int(d.get("seed", 0)); rng.seed = seed_value
	day = d.get("day", 0.0); gold = int(d.get("gold", 0))
	company = d.get("company", []).map(func(x): return Unit.from_dict(x))
	if gold < 0:
		# older saves let wages run the purse negative: clamp, and the owed days become unpaid days
		var dw := maxi(1, daily_wages())
		var owed_days := int(ceil(float(-gold) / float(dw)))
		for u in company:
			u.unpaid_days += owed_days
		gold = 0
	for u in company:
		if u.role == "captain":
			u.role = "officer"   # pre-v0.003 saves had a captain unit; the player is the captain now
	invalidate_deploy()
	stash = d.get("stash", []).map(func(x): return Item.from_dict(x))
	squads = {}
	for k in d.get("squads", {}):
		squads[int(k)] = d["squads"][k]
	rep = d.get("rep", {}); world = _deserialize(d.get("world", {})); location = d.get("location", "")
	contract = _deserialize(d.get("contract", {}))
	Unit._next_uid = maxi(Unit._next_uid, ServiceIdentity.uid_floor(self))
	Unit._next_uid = maxi(Unit._next_uid, DragonCombat.uid_floor(self))
	if d.has("provisions"):
		provisions = Food.stock_from_save(d["provisions"])
		var r: Dictionary = d.get("rations", {})
		rations = {"food": str(r.get("food", "normal")), "drink": str(r.get("drink", "ration"))}
		food_clock = {}
		var fc: Dictionary = d.get("food_clock", {})
		for k in fc:
			food_clock[k] = int(fc[k]) if k == "rot" else float(fc[k])
		if food_clock.is_empty():
			food_clock = {"next": Food.next_tick_after(day), "last": day, "march": 0.0}
	else:
		Food.init_company(self)   # saves from before food and drink: starting stock, default rations
	var Wl = load("res://campaign/world.gd") if ResourceLoader.exists("res://campaign/world.gd") else null
	if Wl != null and Wl.has_method("after_load"):
		Wl.after_load(self)   # JSON floats -> ints for world fields
	if world.has("militia"):
		var released := Militia.trim_all(self)   # older saves: oversized town reserves return to civilian life
		if released > 0: print("load: %d surplus reservists returned to their households" % released)
	if world.has("dragons"): DragonArt.warm(Dragons.records(self))
	changed.emit()
	return true

func _keys_to_str(dict: Dictionary) -> Dictionary:
	var o := {}
	for k in dict:
		o[str(k)] = dict[k]
	return o

## Units and Items inside world/contract dictionaries are stored with a type tag.
## Speed (v0.014, Douglas "long loading screen ... map screen to town screen"): a Large world's save walks ~25 MB
## of plain data, so each container is copied natively (shallow duplicate) and the walk only replaces what is not
## a plain value (nil, bool, int, float, string: typeof <= TYPE_STRING); no call or lambda per plain element.
## Typed containers take the old element-by-element copy (a tag dictionary cannot go into them). Same output.
func _serialize(v):
	match typeof(v):
		TYPE_DICTIONARY:
			if v.is_typed():
				var o0 := {}
				for k in v:
					o0[k] = _serialize(v[k])
				return o0
			var o: Dictionary = v.duplicate()
			for k in o:
				var x = o[k]
				if typeof(x) > TYPE_STRING:
					o[k] = _serialize(x)
			return o
		TYPE_ARRAY:
			if v.is_typed():
				var a0 := []
				if v.get_typed_builtin() <= TYPE_STRING:
					a0.assign(v)   # untyped, as before: plain values only
					return a0
				for x in v:
					a0.append(_serialize(x))
				return a0
			var a: Array = v.duplicate()
			var i := 0
			for x in a:
				if typeof(x) > TYPE_STRING:
					a[i] = _serialize(x)
				i += 1
			return a
		TYPE_OBJECT:
			if v is Unit:
				return {"__unit": v.to_dict().duplicate(true)}
			if v is Item:
				return {"__item": v.to_dict().duplicate(true)}
		TYPE_VECTOR2:
			return {"__v2": [v.x, v.y]}
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return v.duplicate()
	return v

## Rebuilds in place: the tree is the freshly parsed JSON, owned by load_game alone (no copy needed).
func _deserialize(v):
	match typeof(v):
		TYPE_DICTIONARY:
			if v.has("__unit"):
				return Unit.from_dict(v["__unit"])
			if v.has("__item"):
				return Item.from_dict(v["__item"])
			if v.has("__v2"):
				return Vector2(v["__v2"][0], v["__v2"][1])
			for k in v:
				var x = v[k]
				if typeof(x) > TYPE_STRING:
					v[k] = _deserialize(x)
			return v
		TYPE_ARRAY:
			var i := 0
			for x in v:
				if typeof(x) > TYPE_STRING:
					v[i] = _deserialize(x)
				i += 1
			return v
	return v

# ---------------------------------------------------------------- company-level skills
## Map and economy skills (appraiser, negotiator, tracker, organizer, judge) use the company's best member.
func best_skill(skill: String) -> int:
	var best := 0
	for u in company:
		if not u.dead:
			best = maxi(best, u.skill(skill))
	return best

## Loot fraction of defeated enemy gear value: base 25%, best Appraiser adds up to +10% (tuned).
func loot_fraction() -> float:
	return LOOT_FRACTION + 0.005 * best_skill("appraiser")

# ---------------------------------------------------------------- settings (persist outside the save)
var SETTINGS_PATH := "user://settings.json"
## Event animations are kept in code but OFF by default (Douglas: compare with and without later).
const DEFAULT_SETTINGS := {
	"anim_limb_flyoff": false, "anim_spurts": false, "anim_lodged": false, "anim_wrestle": false,
	"battle_speed": 1.0,
	"battle_event_slowmo": false,
	"show_performance": false,   # diagnostics overlay (F3)
	"guide_seen": false,         # the campaign guide opens once on the first map visit
	"music_volume": 0.5,
	"sfx_volume": 0.5,
	"gore": "full",   # v0.014 (Douglas 22:51): "full" | "reduced" (a later phone-store build): blood, decals and log words
}
## Settings with named choices (the screen cycles through them): key -> {label, options [value, shown name]}.
const SETTING_CHOICES := {
	"music_volume": {"label": "Music volume", "options": [[0.0, "Off"], [0.35, "Low"], [0.7, "Normal"], [1.0, "High"]],
		"hint": "Title, campaign and battle music."},
	"sfx_volume": {"label": "Sound effects", "options": [[0.0, "Off"], [0.4, "Low"], [0.8, "Normal"], [1.0, "High"]],
		"hint": "Battle sounds, dragons, interface clicks and event fanfares."},
	"gore": {"label": "Gore", "options": [["full", "Full"], ["reduced", "Reduced"]],
		"hint": "Full: blood sprays, pools, trails and wounds on the fighters, severed parts stay on the field, vivid log. Reduced: less blood, no severed-part decals, milder log words."},
}

func gore_full() -> bool:
	return String(setting("gore")) != "reduced"
const SETTING_LABELS := {
	"battle_event_slowmo": "Automatic battle slow motion",
	"show_performance": "Performance overlay (F3)",
	"anim_limb_flyoff": "Severed parts fly off",   # (v0.014: arterial spurts are part of Gore: Full, no toggle)
	"anim_lodged": "Stuck weapons shown", "anim_wrestle": "Wrestling animations",
}
var settings: Dictionary = DEFAULT_SETTINGS.duplicate()

func setting(key: String):
	return settings.get(key, DEFAULT_SETTINGS.get(key))

func set_setting(key: String, value) -> void:
	var previous: Variant = setting(key)
	settings[key] = value
	CombatText.gore_full = gore_full()   # v0.014: the log's word set follows the Gore setting
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(settings))
		f.close()
	if previous != value:
		setting_changed.emit(key, value)

func load_settings() -> void:
	var previous: Dictionary = settings.duplicate()
	settings = DEFAULT_SETTINGS.duplicate()
	if FileAccess.file_exists(SETTINGS_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if d is Dictionary:
			settings.merge(d, true)
	CombatText.gore_full = gore_full()
	for key: String in settings:
		if previous.get(key, DEFAULT_SETTINGS.get(key)) != settings[key]:
			setting_changed.emit(key, settings[key])
