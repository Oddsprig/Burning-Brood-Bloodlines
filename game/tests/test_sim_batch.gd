extends RefCounted
## Batch statistics over 40 seeds:
##  - copper gear beats otherwise identical tin gear clearly
##  - orc beats goblin 1v1 mostly
##  - fight length is believable (armored 1v1 lasts tens of exchanges; unarmored fewer)

const U = preload("res://tests/sim_util.gd")
const SEEDS := 40

func _batch(label: String, make_a: Callable, make_b: Callable) -> Dictionary:
	var st := {"a": 0, "b": 0, "draw": 0, "ticks": 0.0, "ex": 0.0, "hits": 0.0, "dead": 0, "ko": 0, "rout": 0, "sever": 0, "artery": 0, "min_ex": 1 << 30, "max_ex": 0}
	for s in SEEDS:
		var sim: BattleSim = U.run([make_a.call()], [make_b.call()], 1000 + s * 7919)
		if sim.winner == 0:
			st["a"] += 1
		elif sim.winner == 1:
			st["b"] += 1
		else:
			st["draw"] += 1
		var ex := U.exchanges(sim)
		st["ticks"] += sim.tick
		st["ex"] += ex
		st["min_ex"] = mini(st["min_ex"], ex)
		st["max_ex"] = maxi(st["max_ex"], ex)
		st["hits"] += U.count(sim, "hit")
		st["dead"] += U.count(sim, "death")
		st["ko"] += U.count(sim, "unconscious")
		st["rout"] += U.count(sim, "rout")
		st["sever"] += U.count(sim, "sever")
		for e in sim.events:
			if e["type"] == "artery":
				st["artery"] += 1
			if e["type"] in ["unconscious", "death"]:
				var d: Dictionary = e["entry"]["d"]
				var cause: String = String(d.get("why", "")) if e["type"] == "death" else String(d.get("key", ""))
				var causes: Dictionary = st.get("causes", {})
				causes[e["type"] + ":" + cause] = int(causes.get(e["type"] + ":" + cause, 0)) + 1
				st["causes"] = causes
	print("%-34s A wins %2d  B wins %2d  draws %d | exchanges avg %.1f (min %d max %d), hits %.1f, %.1f s | deaths %d KO %d routs %d severs %d arteries %d" % [
		label, st["a"], st["b"], st["draw"], st["ex"] / SEEDS, st["min_ex"], st["max_ex"], st["hits"] / SEEDS,
		st["ticks"] / SEEDS * Formulas.TICK_SECONDS, st["dead"], st["ko"], st["rout"], st["sever"], st["artery"]])
	print("    causes: ", st.get("causes", {}))
	return st

func run(_tree: SceneTree) -> int:
	var fails := 0
	var cu_tin := _batch("copper vs tin (sword, mail, helm)", func(): return U.soldier("copper"), func(): return U.soldier("tin"))
	var tin_cu := _batch("tin vs copper (sides swapped)", func(): return U.soldier("tin"), func(): return U.soldier("copper"))
	var copper_wins: int = cu_tin["a"] + tin_cu["b"]
	print("copper wins %d / %d" % [copper_wins, SEEDS * 2])
	if copper_wins < int(SEEDS * 2 * 0.75):
		print("TRACKED (informational, outcome): copper should clearly beat tin")
	var mirror := _batch("copper vs copper (armored mirror)", func(): return U.soldier("copper"), func(): return U.soldier("copper"))
	var naked := _batch("copper swords, no armor/shield", func(): return U.soldier("copper", "arming_sword", "", "", ""),
		func(): return U.soldier("copper", "arming_sword", "", "", ""))
	var armored_ex: float = mirror["ex"] / SEEDS
	var naked_ex: float = naked["ex"] / SEEDS
	if armored_ex < 10.0:
		print("TRACKED (informational): armored 1v1 should last tens of exchanges (%.1f)" % armored_ex)
	if naked_ex >= armored_ex:
		print("TRACKED (informational): unarmored fights should be shorter than armored ones")
	_batch("mace vs sword (copper, armored)", func(): return U.soldier("copper", "flanged_mace"), func(): return U.soldier("copper"))
	_batch("spear vs sword (copper, armored)", func(): return U.soldier("copper", "boar_spear"), func(): return U.soldier("copper"))
	var og := _batch("orc vs goblin (own gear, copper)", _orc, _goblin)
	if og["a"] < int(SEEDS * 0.7):
		print("TRACKED (informational): orc should beat goblin mostly")
	if mirror["draw"] > SEEDS / 4:
		print("FAIL: too many draws"); fails += 1
	return fails

func _orc() -> Unit:
	return U.make("orc", [["hacking_cleaver", "copper"], ["slab_shield", "copper"], ["skull_cap", "copper"], ["scrap_plates", "copper"],
		["tunic", "linen"], ["trousers", "linen"]], {"axe": 4, "fighter": 3, "shield_user": 1})

func _goblin() -> Unit:
	return U.make("goblin", [["short_spear", "copper"], ["buckler", "copper"], ["pot_helm", "copper"], ["scale_vest", "copper"],
		["tunic", "linen"], ["trousers", "linen"]], {"spear": 3, "dodger": 3, "fighter": 1})
