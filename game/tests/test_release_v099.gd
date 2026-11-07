extends RefCounted
## v0.099 release candidate, one short headless run on the DevTools start world:
##   1. in a battle of rounds your fit dragons fight every round. Game.start_battle appends them after every man,
##      and rounds took the first 100 in pool order, so with 100+ men a bonded dragon never fought.
##   godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_release_v099.gd --watchdog=170
var fails := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL v099: " + message)
	print(("ok   " if ok else "FAIL ") + message)

func troops(faction: String, n: int, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	for i in n:
		out.append(Factory.make_troop(rng, faction, DB.factions[faction]["troops"][i % 2], 2))
	return out

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "DevTools start world loads")
		return fails
	var tid := DevTools.choose_house(Game)
	check(tid != "", "a house is chosen")
	if tid == "": return fails
	DevTools.stand_at(Game, tid)
	dragons_in_rounds(tid)
	print("v099 checks %d, failures %d, %d ms" % [checks, fails, Time.get_ticks_msec() - started])
	return fails

# ------------------------------------------------------------------ 1. dragons fight in a battle of rounds
func dragons_in_rounds(tid: String) -> void:
	var ruler_uid := str(Dynasty.selected(Game).get("ruler_uid", ""))
	var owner := Dragons._person(Game, ruler_uid)
	Game.world["dragons"] = {"schema": 1, "next_id": 1, "records": {}, "pairs": {}, "initialized": true}
	var r1 := Dragons._make(Game, "adult", tid, owner, "v099:a", 0, "female")
	var r2 := Dragons._make(Game, "adult", tid, owner, "v099:b", 0, "male")
	DragonCombat.prepare_world(Game)
	var d1: Unit = DragonCombat._unit(Game, str(r1["id"]))
	var d2: Unit = DragonCombat._unit(Game, str(r2["id"]))
	check(d1 != null and d2 != null and BattleRounds._can_fight(Game, d1) and BattleRounds._can_fight(Game, d2), "rounds: two whole adult dragons")
	if d1 == null or d2 == null: return
	var saved_round := BattleRounds.round_size
	BattleRounds.round_size = 4
	var mine := troops("middle_kingdom", 10, 9911)   # over twice a round: before v0.099 the dragons never got in
	for u in mine: u.faction = "player"
	var pool: Array = mine + [d1, d2]   # the order Game.start_battle builds: every man, then the dragons
	var foes := troops("northern_clans", 12, 9912)
	Game.pending_battle = {"seed": 99, "enemy": foes}
	BattleRounds.begin(Game, pool, foes)
	var r: Array = Game.pending_battle["round_side0"]
	check(r.has(d1) and r.has(d2), "rounds: both dragons fight round 1 though more men wait than a round holds (%d picked)" % r.size())
	check(r.size() == BattleRounds.round_size, "rounds: the round is still %d a side" % BattleRounds.round_size)
	BattleRounds.next_round(Game)
	r = Game.pending_battle["round_side0"]
	check(r.has(d1) and r.has(d2), "rounds: fit dragons fight the next round too (they do not sit out as tired)")
	var men_now := r.filter(func(u): return not DragonCombat.is_dragon_unit(Game, u))
	check(men_now.all(func(u): return not mine.slice(0, 2).has(u)), "rounds: the men still rotate: round 1's men rest while the others fight")
	d2.body.blood = d2.body.blood_max * 0.05   # badly hurt: "cannot fight"
	BattleRounds.next_round(Game)
	r = Game.pending_battle["round_side0"]
	check(r.has(d1) and not r.has(d2), "rounds: a dragon too hurt to fight still sits out (v0.097 rule kept)")
	BattleRounds.round_size = saved_round
	Game.pending_battle = {}
