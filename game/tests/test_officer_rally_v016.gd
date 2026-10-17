extends RefCounted
## Bounded native morale fixtures; no world generation, rendering or money.
const U := preload("res://tests/sim_util.gd")
var checks: int = 0
var fails: int = 0

class CountSim extends BattleSim:
	var command_reads: int = 0
	func _commander_near(f: Fighter) -> Fighter:
		command_reads += 1
		return super._commander_near(f)

class ArmyGame extends RefCounted:
	var world: Dictionary = {"warbands":{},"towns":{},"factions":{},"seed":1616}
	var company: Array = []
	var day: float = 0.0
	var gold: int = 77

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL officer rally: ", message)

func _actor(sim: BattleSim, unit: Unit) -> Fighter:
	for f: Fighter in sim.fighters:
		if f.unit == unit: return f
	return null

func _fixture() -> Dictionary:
	var armies: Array = [[],[]]
	var leaders: Array = []
	var men: Array = []
	var others: Array = []
	for side: int in 2:
		var race: String = "human" if side == 0 else "orc"
		var officer: Unit = U.make(race, [], {"leader":6}, "Officer %d" % side)
		officer.role = "officer"
		var soldier: Unit = U.make(race, [], {}, "Soldier %d" % side)
		soldier.squad = officer.uid
		var unrelated: Unit = U.make(race, [], {"leader":20}, "Other officer %d" % side)
		unrelated.role = "officer"
		armies[side] = [officer,soldier,unrelated]
		leaders.append(officer); men.append(soldier); others.append(unrelated)
	var sim := CountSim.new()
	sim.setup(armies[0], armies[1], 1616, {"w":24,"h":10,"log_moves":false,"hold0":true,"hold1":true,
		"cells0":[Vector2i(4,3),Vector2i(5,3),Vector2i(6,3)],
		"cells1":[Vector2i(19,3),Vector2i(18,3),Vector2i(17,3)]})
	return {"sim":sim,"leaders":[_actor(sim,leaders[0]),_actor(sim,leaders[1])],
		"men":[_actor(sim,men[0]),_actor(sim,men[1])],"others":[_actor(sim,others[0]),_actor(sim,others[1])]}

func _route(sim: BattleSim, f: Fighter) -> void:
	# Precisely one native routed-count contribution; no manufactured wound.
	f.routed = true
	f.morale = 10.0
	f.state = "moving"
	f.action_ticks = 9; f.action_total = 9; f.action_delay = 2
	f.target = 0 if f.side == 1 else sim.fighters.size() - 1
	f.pending_action = {"kind":"obsolete_flee_fixture"}
	f.pending_attack = {"verb":"obsolete_attack_fixture"}
	f.current_attack = "run"
	f.prev_cell = f.cell + Vector2i(1,0)
	sim.side_down[f.side] += 1

func _seed_for(chance: float, succeeds: bool) -> int:
	var local_rng := RandomNumberGenerator.new()
	for seed: int in range(1,1000):
		local_rng.seed = seed
		if (local_rng.randf() < chance) == succeeds: return seed
	check(false, "bounded seeded rally outcome is available")
	return 1

func _command_events(sim: BattleSim) -> Array:
	return sim.events.filter(func(e): return e.get("entry", {}).get("d", {}).get("key", "") == "officer_rally")

func _body(f: Fighter) -> String:
	return JSON.stringify(f.unit.to_dict(), "", true, true)

func _both_side_checks() -> void:
	for side: int in 2:
		var row: Dictionary = _fixture()
		var sim: CountSim = row["sim"]
		var officer: Fighter = row["leaders"][side]
		var soldier: Fighter = row["men"][side]
		check(soldier.commander_idx == officer.idx and soldier.commander_uid == officer.unit.uid, "side%d binds actual assigned officer identity" % side)
		check(sim._leader_near(soldier) == 6.0 and sim._leader_near(officer) == 0.0, "side%d unrelated stronger officer/self cannot supply command aura" % side)
		check(is_equal_approx(soldier.morale_start, clampf(soldier.morale_base + 6.0,5.0,100.0)), "side%d starts with one native assigned aura" % side)
		_route(sim,soldier)
		var old_cell: Vector2i = soldier.cell
		var body: String = _body(soldier)
		var officer_body: String = _body(officer)
		var rng_state: int = sim.rng.state
		var count_before: int = int(sim.side_down[side])
		sim._morale_tick(soldier)
		check(not soldier.routed and soldier.morale == Formulas.RALLY_MORALE, "side%d assigned standing officer rallies before permanent flight" % side)
		check(sim.rng.state == rng_state, "side%d commanded rally consumes no fabricated roll" % side)
		check(soldier.cell == old_cell and soldier.prev_cell == old_cell and soldier.state == "ready", "side%d rejoin clears fleeing interpolation without teleporting" % side)
		check(soldier.action_ticks == 0 and soldier.action_total == 1 and soldier.action_delay == 0 and soldier.target == -1 and
			soldier.pending_action.is_empty() and soldier.pending_attack.is_empty() and soldier.current_attack == "", "side%d rejoin clears obsolete fleeing orders/attack" % side)
		check(_body(soldier) == body and _body(officer) == officer_body, "side%d command changes no wound/blood/equipment/physical Unit fields" % side)
		check(sim.side_down[side] == count_before - 1, "side%d routed count decrements once" % side)
		var emitted: Array = _command_events(sim)
		check(emitted.size() == 1 and emitted[0]["actor"] == officer.idx and emitted[0]["target"] == soldier.idx, "side%d rally records actual officer actor and soldier target" % side)
		var params: Dictionary = emitted[0]["entry"]["d"]
		check(params["mode"] == "commanded" and params["commander_uid"] == officer.unit.uid and params["soldier_uid"] == soldier.unit.uid and
			params["morale_before"] == 10.0 and params["morale_after"] == soldier.morale and params["leader_level"] == 6.0 and
			params["distance"] == 1 and params["radius"] == Formulas.LEADER_RADIUS and not params.has("roll"), "side%d log parameters describe actual command, not a random roll" % side)
		sim._morale_tick(soldier)
		check(sim.side_down[side] == count_before - 1 and _command_events(sim).size() == 1, "side%d subsequent morale update cannot double rally/count" % side)
		sim._decide(soldier)
		check(not soldier.routed and soldier.state != "fled" and soldier.action_ticks > 0, "side%d rallied man rejoins native hold/target orders" % side)

func _officer_loss_checks() -> void:
	for side: int in 2:
		for loss: String in ["dead","unconscious","prone","routed","waiting","withdrawn","fled","stance_lost","wrong_role","range"]:
			var row: Dictionary = _fixture()
			var sim: CountSim = row["sim"]
			var officer: Fighter = row["leaders"][side]
			var soldier: Fighter = row["men"][side]
			match loss:
				"dead": sim._kill(officer,-1,"native fixture death")
				"unconscious": sim._knock_out(officer,"native fixture KO")
				"prone": officer.prone = true; officer.state = "prone"
				"routed": officer.routed = true
				"waiting": officer.waiting = true
				"withdrawn": officer.state = "withdrawn"
				"fled": officer.state = "fled"
				"stance_lost": officer.stance_lost = true
				"wrong_role": officer.unit.role = "troop"
				"range": officer.cell = soldier.cell + Vector2i(Formulas.LEADER_RADIUS+1,0)
			check(sim._commander_near(soldier) == null and sim._leader_near(soldier) == 0.0, "side%d %s officer immediately supplies no support" % [side,loss])
			soldier.morale = 1.0
			sim._morale_tick(soldier)
			check(soldier.morale_start == clampf(soldier.morale_base,5.0,100.0), "side%d %s officer leaves no stale supported cap" % [side,loss])
			_route(sim,soldier)
			var before: String = _body(soldier)
			var down_before: int = int(sim.side_down[side])
			var chance: float = Formulas.RALLY_BASE + Formulas.RALLY_LOYALTY * soldier.tr_loyalty
			sim.rng.seed = _seed_for(chance,false)
			var rng_before: int = sim.rng.state
			sim._morale_tick(soldier)
			check(soldier.routed and _command_events(sim).is_empty() and sim.side_down[side] == down_before and _body(soldier) == before and
				sim.rng.state != rng_before, "side%d %s loss keeps native autonomous failed roll, not commanded return/healing" % [side,loss])

func _identity_and_incapacity_checks() -> void:
	for side: int in 2:
		for invalid: String in ["missing","foreign","self_uid","ambiguous"]:
			var row: Dictionary = _fixture()
			var sim: CountSim = row["sim"]
			var soldier: Fighter = row["men"][side]
			var officer: Fighter = row["leaders"][side]
			match invalid:
				"missing": soldier.unit.squad = 99999999
				"foreign": soldier.unit.squad = row["leaders"][1-side].unit.uid
				"self_uid": soldier.unit.uid = officer.unit.uid
				"ambiguous": row["others"][side].unit.uid = officer.unit.uid
			sim._init_morale()
			check(soldier.commander_idx == -1 and sim._commander_near(soldier) == null, "side%d %s identity cannot invent a commander" % [side,invalid])
			_route(sim,soldier)
			var chance: float = Formulas.RALLY_BASE + Formulas.RALLY_LOYALTY * soldier.tr_loyalty
			sim.rng.seed = _seed_for(chance,false)
			sim._morale_tick(soldier)
			check(soldier.routed and _command_events(sim).is_empty(), "side%d %s identity never receives guaranteed command" % [side,invalid])
		for state: String in ["dead","unconscious","fled","waiting","prone","stance_lost"]:
			var row: Dictionary = _fixture()
			var sim: CountSim = row["sim"]
			var soldier: Fighter = row["men"][side]
			_route(sim,soldier)
			if state == "waiting": soldier.waiting = true
			elif state == "prone": soldier.prone = true; soldier.state = "prone"
			elif state == "stance_lost": soldier.stance_lost = true; soldier.prone = true; soldier.state = "prone"
			else: soldier.state = state
			if state == "dead": soldier.unit.dead = true
			var before: String = _body(soldier)
			var down_before: int = int(sim.side_down[side])
			var chance: float = Formulas.RALLY_BASE + Formulas.RALLY_LOYALTY * soldier.tr_loyalty + Formulas.RALLY_LEADER * 6.0
			sim.rng.seed = _seed_for(chance,false)
			sim._morale_tick(soldier)
			check(soldier.routed and soldier.state == ("prone" if state in ["prone","stance_lost"] else "moving" if state == "waiting" else state) and
				_body(soldier) == before and sim.side_down[side] == down_before and _command_events(sim).is_empty(), "side%d %s soldier is never revived/healed by command" % [side,state])
		# Officer with no commander keeps the native autonomous chance and event.
		var row: Dictionary = _fixture()
		var sim: CountSim = row["sim"]
		var officer: Fighter = row["leaders"][side]
		_route(sim,officer)
		var chance: float = Formulas.RALLY_BASE + Formulas.RALLY_LOYALTY * officer.tr_loyalty
		var seed: int = _seed_for(chance,true)
		var control_rng := RandomNumberGenerator.new()
		control_rng.seed = seed
		var expected: bool = Formulas.roll_rally_ok(control_rng,chance)
		sim.rng.seed = seed
		sim._morale_tick(officer)
		check(expected and not officer.routed and officer.morale == Formulas.RALLY_MORALE and sim.rng.state == control_rng.state and
			_command_events(sim).is_empty(), "side%d uncommanded officer preserves exact native self-rally RNG and behavior" % side)

func _schedule_and_cost_checks() -> void:
	for side: int in 2:
		var row: Dictionary = _fixture()
		var sim: CountSim = row["sim"]
		var soldier: Fighter = row["men"][side]
		_route(sim,soldier)
		sim.tick = Formulas.MORALE_TICK - soldier.idx - 1
		sim._physiology(soldier)
		check(soldier.routed and _command_events(sim).is_empty(), "side%d command never runs before scheduled morale tick" % side)
		sim.tick += 1
		sim._physiology(soldier)
		check(not soldier.routed and _command_events(sim).size() == 1, "side%d existing staggered physiology schedule performs command once" % side)
	var armies: Array = [[],[]]
	for side: int in 2:
		var officer: Unit = U.make("human", [], {"leader":6})
		officer.role = "officer"
		armies[side].append(officer)
		for i: int in 199:
			var soldier: Unit = U.make("human", [])
			soldier.squad = officer.uid
			armies[side].append(soldier)
	var dense := CountSim.new()
	dense.setup(armies[0],armies[1],1620,{"log_moves":false})
	dense.command_reads = 0
	for f: Fighter in dense.fighters: dense._leader_near(f)
	check(dense.fighters.size() == 400 and dense.command_reads == 400, "native200/200 support reads exactly one cached command per fighter, no pair search")
	dense.command_reads = 0
	for f: Fighter in dense.fighters: dense._morale_tick(f)
	check(dense.command_reads == 400, "scheduled native200/200 morale reads one command identity per present fighter")

func _plan_uid(plan: Array, u: Unit) -> int:
	for row: Dictionary in plan:
		if row["unit"] == u: return int(row["commander_uid"])
	return -999 # Not in this command authority's eligible roster.

func _native_units(count: int) -> Array:
	var out: Array = []
	for i: int in count:
		var u: Unit = U.make("human", [])
		u.faction = "middle_kingdom"
		out.append(u)
	return out

func _unit_physics(units: Array) -> String:
	var rows: Array = []
	for u: Unit in units:
		var row: Dictionary = u.to_dict().duplicate(true)
		for key: String in ["squad","rank","role"]: row.erase(key)
		rows.append(row)
	return JSON.stringify(rows,"",true,true)

func _army_plan_checks() -> void:
	var units: Array = _native_units(8)
	var posts: Array = []
	for i: int in 7:
		units[i].role = "officer"
		posts.append(units[i].uid)
	var soldier: Unit = units[7]
	soldier.squad = 55555
	var bottom: int = Army.report_post(soldier,3,2)
	var before: String = _unit_physics(units)
	var plan: Array = Army.command_plan(units,posts,3,2,"middle_kingdom")
	check(_plan_uid(plan,soldier) == int(posts[bottom]) and _plan_uid(plan,units[0]) == -1 and
		_plan_uid(plan,units[3]) == int(posts[Army.up_of(3,2)]), "native tree links stable bottom troop and officer parent, never root self")
	check(soldier.squad == 55555 and _unit_physics(units) == before, "command plan is pure and changes no gear/body/role/squad")
	var vacant: Array = posts.duplicate()
	vacant[bottom] = -1
	check(_plan_uid(Army.command_plan(units,vacant,3,2,"middle_kingdom"),soldier) == int(posts[Army.up_of(bottom,2)]), "native vacancy resolves to real parent holder")
	var absent: Array = units.duplicate()
	absent.erase(units[bottom])
	check(_plan_uid(Army.command_plan(absent,posts,3,2,"middle_kingdom"),soldier) == int(posts[Army.up_of(bottom,2)]), "absent postholder is not fabricated; nearest actual ancestor commands")
	units[bottom].dead = true
	check(_plan_uid(Army.command_plan(units,posts,3,2,"middle_kingdom"),soldier) == int(posts[Army.up_of(bottom,2)]), "dead postholder cannot command living roster")
	units[bottom].dead = false
	units[bottom].faction = "orc_horde"
	check(_plan_uid(Army.command_plan(units,posts,3,2,"middle_kingdom"),soldier) == int(posts[Army.up_of(bottom,2)]), "foreign faction post claim cannot command native roster")
	units[bottom].faction = "middle_kingdom"
	var repeated: Array = units.duplicate()
	repeated.append_array(units)
	check(Army.command_plan(repeated,posts,3,2,"middle_kingdom").size() == units.size(), "repeated actual Unit references are deduplicated once")
	var duplicate: Unit = _native_units(1)[0]
	duplicate.uid = units[bottom].uid
	var ambiguous: Array = units.duplicate()
	ambiguous.append(duplicate)
	plan = Army.command_plan(ambiguous,posts,3,2,"middle_kingdom")
	check(_plan_uid(plan,duplicate) == -1 and _plan_uid(plan,units[bottom]) == -1 and _plan_uid(plan,soldier) == int(posts[Army.up_of(bottom,2)]), "different Units sharing UID cannot claim command identity")
	var duplicate_posts: Array = posts.duplicate()
	duplicate_posts[bottom] = int(posts[Army.up_of(bottom,2)])
	check(_plan_uid(Army.command_plan(units,duplicate_posts,3,2,"middle_kingdom"),soldier) == int(posts[0]), "duplicate post claims skip ambiguous holder up to unique root")
	check(_plan_uid(Army.command_plan(units,[],0,2,"middle_kingdom"),soldier) == -1, "no actual posts produces no invented officer")
	var game := ArmyGame.new()
	game.company = [soldier]
	Army._apply_commands(game,units,posts,3,2,"middle_kingdom")
	check(soldier.squad == 55555 and units[0].squad == -1 and units[3].squad == int(posts[Army.up_of(3,2)]), "apply links real units but preserves protected native company command")
	check(game.gold == 77 and _unit_physics(units) == before, "command linking touches no money, body, people or gear")

func _army_hook_checks() -> void:
	var fid: String = "middle_kingdom"
	var units: Array = _native_units(25)
	var game := ArmyGame.new()
	var cul: Dictionary = Army.cul_of_faction(fid)
	var span: int = maxi(2,int(cul.get("span",5)))
	var levels: int = Army.levels_for(units.size(),span,Army.ranks(cul,"army").size()-Army.first_officer("army"))
	var posts: Array = []
	for i: int in Army.offset(levels,span):
		units[i].role = "officer"
		posts.append(units[i].uid)
	game.world["warbands"] = {"field":{"faction":fid,"kind":"patrol","units":units}}
	var r: Dictionary = Army.rec(game.world,fid)
	r["posts"] = posts
	r["levels"] = levels
	var company_unit: Unit = units[-1]
	company_unit.squad = 424242
	game.company = [company_unit]
	var bandit: Unit = _native_units(1)[0]
	bandit.squad = 313131
	game.world["warbands"]["named_bandits"] = {"faction":fid,"kind":"bandit","units":[bandit]}
	var before: String = _unit_physics(units)
	var next_unit: int = Unit._next_uid
	var next_item: int = Item._next_uid
	Army.update_tree(game,fid,units,true,0)
	var correct: bool = true
	for row: Dictionary in Army.command_plan(units,posts,levels,span,fid,game.company):
		if row["unit"].squad != row["commander_uid"]: correct = false
	check(correct and company_unit.squad == 424242 and bandit.squad == 313131, "native field-tree update applies genuine links and leaves company/named-bandit links intact")
	check(before == _unit_physics(units) and game.gold == 77 and Unit._next_uid == next_unit and Item._next_uid == next_item, "field-tree hook creates no Unit/Item/coin or physical changes")
	# Current-tree assignment can happen later during one actual succession job.
	posts[1] = -1
	var by: Dictionary = {}
	for u: Unit in units: by[u.uid] = u
	Army.assign(game,fid,1,units[-2],by,true,0,[])
	correct = true
	for row: Dictionary in Army.command_plan(units,posts,levels,span,fid,game.company):
		if row["unit"].squad != row["commander_uid"]: correct = false
	check(correct and company_unit.squad == 424242 and bandit.squad == 313131, "native assignment/cascade completion refreshes links without touching company/bandits")
	for tier: String in ["militia","guard"]:
		var residents: Array = _native_units(25)
		var local_levels: int = Army.levels_for(residents.size(),span,Army.ranks(cul,tier).size()-1)
		var local_posts: Array = []
		for i: int in Army.offset(local_levels,span):
			residents[i].role = "officer"
			local_posts.append(residents[i].uid)
		var wb: Dictionary = {"kind":tier,"faction":fid,"units":residents,"posts":local_posts}
		var town: Dictionary = {"faction":fid,"econ":{"culture":"middle"}}
		before = _unit_physics(residents)
		Army.update_band_tree(game,town,wb,tier)
		correct = true
		for row: Dictionary in Army.command_plan(residents,local_posts,local_levels,span,fid,game.company):
			if row["unit"].squad != row["commander_uid"]: correct = false
		check(correct and local_levels > 0 and before == _unit_physics(residents), "native %s tree applies real post links without physical changes" % tier)

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var rng_state: int = Game.rng.state
	var unit_counter: int = Unit._next_uid
	var item_counter: int = Item._next_uid
	var state_sha: String = JSON.stringify(Game._save_tree(),"",true,true).sha256_text()
	_both_side_checks()
	_officer_loss_checks()
	_identity_and_incapacity_checks()
	_schedule_and_cost_checks()
	_army_plan_checks()
	_army_hook_checks()
	Unit._next_uid = unit_counter
	Item._next_uid = item_counter
	check(Game.rng.state == rng_state and JSON.stringify(Game._save_tree(),"",true,true).sha256_text() == state_sha,
		"native morale fixtures change no campaign population/coin/equipment/state/RNG")
	print("Officer rally v016: ",checks," checks, ",fails," failures")
	return fails
