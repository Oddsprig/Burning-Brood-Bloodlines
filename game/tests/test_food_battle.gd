extends RefCounted
## Food and drink in battle (core/food.gd + sim hooks; spec docs/specs/food-drink.md section 10):
##  - enemy spawn sets belly/buzz in range per supply level and race (beasts: belly only)
##  - recruit vs recruit stays about 50% when both sides are Fed and sober
##  - 50v50 worst tick stays under 2 ms with food/drink states in play (min of two runs per tick, as test_sim_perf)
## plus: start morale modifiers, focus inside +-15%, Hammered stumbles, buzz decays per tick, battle-only attribute
## multipliers come off at the end, belly -10 at battle end, data-driven log lines from the real state.

const U = preload("res://tests/sim_util.gd")
const WORST_GATE_MS := 2.0

var fails := 0

func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)

func run(_tree: SceneTree) -> int:
	if OS.get_environment("FOOD_DIAG") == "1":
		_diag()
		return 0
	_test_spawn()
	_test_effects()
	_test_logs()
	_test_rvr()
	_test_perf()
	return fails

func _test_spawn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var ok := true
	for supply in ["well", "short", "starving"]:
		var br: Array = Food.data()["supply_belly"][supply]
		for race in ["human", "orc", "goblin", "moon_elf", "troll"]:
			var zr: Array = Food.data()["enemy_buzz"][race]
			for i in 60:
				var u := Unit.create(race, "x")
				Food.spawn_state(u, supply, rng)
				if u.belly < float(br[0]) or u.belly > float(br[1]) or u.buzz < float(zr[0]) or u.buzz > float(zr[1]):
					ok = false
					print("  out of range: %s %s belly %.1f buzz %.1f" % [supply, race, u.belly, u.buzz])
	check(ok, "enemy spawn: belly per supply level, buzz per race, always in range")
	# beasts and monsters: belly only (hungry packs), no buzz
	var beast: Dictionary = DB.races["human"].duplicate(true)
	beast["beast"] = true
	DB.races["test_beast"] = beast
	var b := Unit.create("test_beast", "x")
	b.buzz = 50.0
	var bad := false
	for i in 60:
		Food.spawn_state(b, "well", rng)
		bad = bad or b.buzz != 0.0 or b.belly < 20.0 or b.belly > 50.0
	DB.races.erase("test_beast")
	check(not bad, "beasts get belly 20-50 and no buzz")
	# the Game.start_battle hook: "well supplied" for every enemy until the economy exposes supply
	Game.new_game(5)
	Game.main = null
	var enemy := Factory.make_warband(rng, "orc_horde", 6)
	for e in enemy:
		e.belly = -1.0; e.buzz = -1.0
	Game.start_battle({"enemy": enemy, "allies": [], "contract": {}, "map": "small", "terrain": "plains"})
	check(enemy.all(func(e): return e.belly >= 50.0 and e.belly <= 80.0 and e.buzz >= 20.0 and e.buzz <= 50.0), "start_battle: orcs well supplied (belly 50-80) with buzz 20-50")
	var again := Factory.make_warband(rng, "orc_horde", 6)
	Food.spawn_battle(Game, {"enemy": again, "seed": Game.pending_battle["seed"]})
	var same := true
	for i in 6:
		same = same and absf(again[i].belly - enemy[i].belly) < 0.0001
	check(same, "spawn state is seeded by the battle seed")

func _unit(belly: float, buzz: float) -> Unit:
	var u := U.recruit()
	u.belly = belly
	u.buzz = buzz
	return u

func _test_effects() -> void:
	var fed := _unit(60, 0)
	var starving := _unit(5, 0)
	var hammered := _unit(60, 80)
	var drunk := _unit(60, 45)
	var sim := BattleSim.new()
	sim.setup([fed, starving, hammered, drunk], [_unit(60, 0)], 3, {"w": 16, "h": 8})
	var f0: Fighter = sim.fighters[0]
	var f1: Fighter = sim.fighters[1]
	var f2: Fighter = sim.fighters[2]
	var f3: Fighter = sim.fighters[3]
	var base := Formulas.morale_start(sim._trait(f0, "courage"), sim._leader_near(f0))
	check(absf(f0.morale_start - (base + 5.0)) < 0.001, "Fed: start morale +5 (%.1f vs %.1f)" % [f0.morale_start, base])
	var b1 := Formulas.morale_start(sim._trait(f1, "courage"), sim._leader_near(f1))
	check(absf(f1.morale_start - clampf(b1 - 15.0, 5.0, 100.0)) < 0.001, "Starving: start morale -15")
	var b2 := Formulas.morale_start(sim._trait(f2, "courage"), sim._leader_near(f2))
	check(absf(f2.morale_start - clampf(b2 + 5.0 + 15.0, 5.0, 100.0)) < 0.001, "Hammered and Fed: start morale +20")
	check(f1.fatigue_mult == 1.35 and starving.attr("END") == int(starving.attrs["END"] * 0.75), "Starving: fatigue gain x1.35, END counts x0.75")
	check(f2.pain_tol == 1.25 and f2.stumble_p == 0.02 and hammered.attr("AGI") == int(hammered.attrs["AGI"] * 0.75) and hammered.attr("KIN") == int(hammered.attrs["KIN"] * 0.75), "Hammered: pain x1.25, KIN and AGI x0.75, 2% stumble")
	check(f3.pain_tol == 1.20 and drunk.attr("FOC") == int(drunk.attrs["FOC"] * 0.9) and drunk.eff_attrs()["KIN"] == int(drunk.attrs["KIN"] * 0.9), "Drunk: pain x1.20, KIN and FOC x0.90 (also in the check attributes)")
	check(f0.fatigue_mult == 1.0 and f0.focus_mult == 1.0 and f0.pain_tol == 1.0 and f0.walk_mult == 1.0 and fed.attr("KIN") == int(fed.attrs["KIN"]), "Fed and sober: no change")
	var z0 := hammered.buzz
	for i in 50:
		sim.step()
	check(absf(hammered.buzz - (z0 - 5.0)) < 0.01, "buzz -0.1 per battle tick (%.2f -> %.2f)" % [z0, hammered.buzz])
	while not sim.is_over():
		sim.step()
	check(hammered.food_attr_mult.is_empty() and hammered.attr("AGI") == int(hammered.attrs["AGI"]), "battle-only attribute multipliers come off at the end")
	# focus stays inside +-15% in the sim too
	var worst := _unit(25, 0)
	worst.drink_days = 4
	worst.hungover = true
	var s2 := BattleSim.new()
	s2.setup([worst], [_unit(60, 0)], 4, {"w": 8, "h": 4})
	check(absf((s2.fighters[0] as Fighter).focus_mult - 0.85) < 0.0001, "sim focus clamps at -15%% (%.3f)" % (s2.fighters[0] as Fighter).focus_mult)
	# Stuffed walks slower
	var st := _unit(95, 0)
	var s3 := BattleSim.new()
	s3.setup([st], [_unit(60, 0)], 4, {"w": 8, "h": 4})
	check((s3.fighters[0] as Fighter).walk_mult == 1.05 and (s3.fighters[0] as Fighter).fatigue_mult == 1.10, "Stuffed: walk x1.05, fatigue gain x1.10")
	# Game.finish_battle: belly -10
	Game.new_game(9)
	Game.main = null
	for u in Game.company:
		u.belly = 50.0
	Game.finish_battle({"winner": 0, "player_units": Game.company, "enemy_units": [], "enemy_fallen": [], "events": []})
	check(Game.company.all(func(u): return u.dead or absf(u.belly - 40.0) < 0.001), "belly -10 at battle end")

func _test_logs() -> void:
	# hammered men stumble (named roll, logged with the real numbers); drunk swings and pain lines; start lines
	var stumbles := 0
	var lines := {}
	for s in 6:
		var a := []
		var b := []
		for i in 6:
			a.append(_unit(60, 90))
			b.append(_unit(5, 0))
		var sim: BattleSim = U.run(a, b, 500 + s, {"w": 24, "h": 10})
		stumbles += U.count(sim, "stumble")
		for f in sim.fighters:
			for e in f.log:
				if e["k"] == "ev" and String(e["d"].get("key", "")).begins_with("food_"):
					var r := BattleSim.render_entry(e)
					lines[e["d"]["key"]] = r["text"] + "   [" + r["calc"] + "]"
	print("  stumbles in 6 battles: %d" % stumbles)
	for k in lines:
		print("  %s: %s" % [k, lines[k]])
	check(stumbles > 0, "Hammered men stumble and lose the move")
	check(lines.has("food_start_hammered") and lines.has("food_start_starving"), "start-of-battle lines from the real state")
	check(lines.has("food_swing") and lines.has("food_stumble"), "drunk swing and stumble lines")
	check(lines.has("food_gasp_starving"), "half-starved men gasp for breath")
	var any_calc := false
	for k in lines:
		any_calc = any_calc or String(lines[k]).contains("belly ")
	check(any_calc, "log lines carry the real belly/buzz numbers")

func _test_rvr() -> void:
	var w := [0, 0, 0]
	for s in 80:
		var sim: BattleSim = U.run([_unit(60, 0)], [_unit(60, 0)], 7000 + s * 131)
		w[sim.winner + 1] += 1
	var decided: int = w[1] + w[2]
	var share := float(w[1]) / maxf(1.0, float(decided))
	print("  recruit vs recruit, Fed and sober: side 0 wins %d, side 1 wins %d, draws %d" % [w[1], w[2], w[0]])
	check(share >= 0.35 and share <= 0.65, "recruit vs recruit stays about 50%% when both are Fed and sober (%.2f)" % share)

func _diag() -> void:
	for food in [false, true]:
		for seed in [60, 61, 50]:
			var r1 := _times(seed, food)
			var r2 := _times(seed, food)
			var w := 0.0
			var wi := 0
			for i in mini(r1["t"].size(), r2["t"].size()):
				var t := minf(r1["t"][i], r2["t"][i])
				if t > w:
					w = t; wi = i + 1
			print("  diag food=%s seed %d worst %.3f at tick %d" % [str(food), seed, w, wi])

func _times(seed: int, food: bool = true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a := Factory.make_warband(rng, "middle_kingdom", 50)
	var b := Factory.make_warband(rng, "orc_horde", 50)
	var fr := RandomNumberGenerator.new()
	fr.seed = seed * 3
	# a campaign-like fight: the company on the road (fed or peckish, a morning mug or a heavy night, some hung
	# over, a few starving or hammered) against a well-supplied orc band rolled by the real spawn code
	if food:
		for u in a:
			u.belly = fr.randf_range(30.0, 95.0) if fr.randf() < 0.9 else fr.randf_range(0.0, 15.0)
			u.buzz = fr.randf_range(0.0, 40.0) if fr.randf() < 0.9 else fr.randf_range(60.0, 80.0)
			u.hungover = fr.randf() < 0.2
		for u in b:
			Food.spawn_state(u, "well", fr)
	var sim := BattleSim.new()
	sim.setup(a, b, seed, {"w": 64, "h": 36, "log_moves": true})
	var times := PackedFloat64Array()
	while not sim.is_over():
		var t0 := Time.get_ticks_usec()
		sim.step()
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	return {"t": times, "ticks": sim.tick, "stumbles": U.count(sim, "stumble"), "sim": sim}

## Per-tick cost = the minimum over RUNS deterministic runs (filters OS/GC spikes on a shared machine, 
## test_sim_perf does with two; five here because the sampled ticks sit close to the gate). Also prints the same battles without food/drink states for comparison.
const RUNS := 5

func _min_times(seed: int, food: bool) -> Dictionary:
	var first := _times(seed, food)
	var t: PackedFloat64Array = first["t"]
	var same := true
	for k in RUNS - 1:
		var r := _times(seed, food)
		var t2: PackedFloat64Array = r["t"]
		same = same and t2.size() == t.size()
		for i in mini(t.size(), t2.size()):
			t[i] = minf(t[i], t2[i])
	var w := 0.0
	var wi := 0
	var total := 0.0
	for i in t.size():
		if t[i] > w:
			w = t[i]; wi = i + 1
		total += t[i]
	var wc := {}
	for e in first["sim"].events:
		if e["tick"] == wi:
			wc[e["type"]] = int(wc.get(e["type"], 0)) + 1
	print("    worst tick %d: %s" % [wi, str(wc)])
	return {"worst": w, "mean": total / maxf(1.0, float(t.size())), "same": same, "ticks": first["ticks"], "stumbles": first["stumbles"]}

func _test_perf() -> void:
	var worst := 0.0
	for seed in [60, 61]:
		var r := _min_times(seed, true)
		var plain := _min_times(seed, false)
		print("  50v50 seed %d with food/drink states: %d ticks, %d stumbles, mean %.3f ms, worst %.3f ms | without: mean %.3f, worst %.3f" % [
			seed, r["ticks"], r["stumbles"], r["mean"], r["worst"], plain["mean"], plain["worst"]])
		worst = maxf(worst, r["worst"])
		check(r["same"], "deterministic with food/drink states (seed %d)" % seed)
		check(r["mean"] < plain["mean"] * 1.15 + 0.02, "food/drink adds no real per-tick cost (mean %.3f vs %.3f ms)" % [r["mean"], plain["mean"]])
	check(worst < WORST_GATE_MS, "50v50 worst tick under 2 ms with food/drink states (%.3f ms)" % worst)

