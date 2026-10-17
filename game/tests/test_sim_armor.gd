extends RefCounted
## Armor physics, using forced inspection strikes on the upper body (BattleSim.debug_strike):
##  - a mace breaks ribs under an intact copper mail shirt (mail transmits blunt force)
##  - rigid armor (lamellar) absorbs far more of the same blows
##  - spear thrusts get through copper mail more often than sword slashes
##  - tin mail is cut far more often than copper mail

const U = preload("res://tests/sim_util.gd")
const N := 200

func _strikes(attacker: Unit, armor: Array, part: String, attack_idx: int, seed: int) -> Dictionary:
	var gear := [["tunic", "linen"], ["trousers", "linen"]] + armor
	var def := U.make("human", gear, {"armor_user": 3})
	var sim := BattleSim.new()
	# gear_wear off: 200 probes of FRESH armour and weapon (v0.014 gear damage would wear them down between probes)
	sim.setup([attacker], [def], seed, {"w": 8, "h": 4, "log_moves": false, "gear_wear": false})
	var st := {"n": 0, "covered": 0, "cut": 0, "bone": 0, "bone_under_intact": 0, "intact": 0, "wound": 0}
	for i in N:
		def.body.init_from_plan(DB.bodies["humanoid"], def.mass())
		def.dead = false
		attacker.body.exertion = 0.0
		var fd: Fighter = sim.fighters[1]
		fd.state = "ready"; fd.prone = false; fd.think_dmg = 0.0; fd.pain_floor_src = 0.0
		var r := sim.debug_strike(0, 1, part, attack_idx, true)
		st["n"] += 1
		var covered := false
		var cut := false
		for ar in r["armor"]:
			if String(ar["name"]).contains("linen"):
				continue
			covered = true
			if ar["result"] == "cut":
				cut = true
		var bone := false
		for t in r["tissue"]:
			if t["tissue"] == "bone" and t["kind"] in ["fractured", "broken", "mangled"]:
				bone = true
		if r["tissue"].size() > 0:
			st["wound"] += 1
		if covered:
			st["covered"] += 1
			if cut:
				st["cut"] += 1
			else:
				st["intact"] += 1
				if bone:
					st["bone_under_intact"] += 1
		if bone:
			st["bone"] += 1
	return st

func _rate(a: int, b: int) -> float:
	return float(a) / maxf(1.0, float(b))

func run(_tree: SceneTree) -> int:
	var fails := 0
	var mace := func(): return U.make("human", [["flanged_mace", "copper"]], {"mace": 4, "fighter": 3})
	var mail := _strikes(mace.call(), [["mail_shirt", "copper"]], "torso_upper", 0, 11)
	var lam := _strikes(mace.call(), [["lamellar_cuirass", "copper"]], "torso_upper", 0, 11)
	var bare := _strikes(mace.call(), [], "torso_upper", 0, 11)
	var mail_rate := _rate(mail["bone_under_intact"], mail["intact"])
	var lam_rate := _rate(lam["bone_under_intact"], lam["intact"])
	print("mace -> upper body, %d strikes each:" % N)
	print("  copper mail shirt: covered %d, intact %d, ribs broken under intact mail %d (%.0f%%)" % [mail["covered"], mail["intact"], mail["bone_under_intact"], mail_rate * 100.0])
	print("  copper lamellar:   covered %d, intact %d, ribs broken under intact lamellar %d (%.0f%%)" % [lam["covered"], lam["intact"], lam["bone_under_intact"], lam_rate * 100.0])
	print("  no armor:          ribs broken %d (%.0f%%)" % [bare["bone"], _rate(bare["bone"], N) * 100.0])
	if mail_rate < 0.4:
		print("FAIL: blunt force should break bones through intact mail"); fails += 1
	if lam_rate > mail_rate * 0.6:
		print("FAIL: rigid armor should absorb clearly more blunt force than mail"); fails += 1
	var spear := func(): return U.make("human", [["boar_spear", "copper"]], {"spear": 4, "fighter": 3})
	var sword := func(): return U.make("human", [["arming_sword", "copper"]], {"sword": 4, "fighter": 3})
	var sp := _strikes(spear.call(), [["mail_shirt", "copper"]], "torso_upper", 0, 21)
	var sl := _strikes(sword.call(), [["mail_shirt", "copper"]], "torso_upper", 0, 21)
	var stb := _strikes(sword.call(), [["mail_shirt", "copper"]], "torso_upper", 1, 21)
	var sl_tin := _strikes(sword.call(), [["mail_shirt", "tin"]], "torso_upper", 0, 21)
	var sp_tin := _strikes(spear.call(), [["mail_shirt", "tin"]], "torso_upper", 0, 21)
	var tin_sw := U.make("human", [["arming_sword", "tin"]], {"sword": 4, "fighter": 3})
	var tsl := _strikes(tin_sw, [["mail_shirt", "copper"]], "torso_upper", 0, 21)
	print("copper mail shirt penetration (upper body):")
	print("  copper spear stab   %3d / %d (%.0f%%)" % [sp["cut"], sp["covered"], _rate(sp["cut"], sp["covered"]) * 100.0])
	print("  copper sword stab   %3d / %d (%.0f%%)" % [stb["cut"], stb["covered"], _rate(stb["cut"], stb["covered"]) * 100.0])
	print("  copper sword slash  %3d / %d (%.0f%%)" % [sl["cut"], sl["covered"], _rate(sl["cut"], sl["covered"]) * 100.0])
	print("  tin sword slash     %3d / %d (%.0f%%)" % [tsl["cut"], tsl["covered"], _rate(tsl["cut"], tsl["covered"]) * 100.0])
	print("tin mail shirt penetration:")
	print("  copper spear stab   %3d / %d (%.0f%%)" % [sp_tin["cut"], sp_tin["covered"], _rate(sp_tin["cut"], sp_tin["covered"]) * 100.0])
	print("  copper sword slash  %3d / %d (%.0f%%)" % [sl_tin["cut"], sl_tin["covered"], _rate(sl_tin["cut"], sl_tin["covered"]) * 100.0])
	if _rate(sp["cut"], sp["covered"]) <= _rate(sl["cut"], sl["covered"]) + 0.15:
		print("FAIL: spear thrusts should get through mail clearly more often than slashes"); fails += 1
	if _rate(sl_tin["cut"], sl_tin["covered"]) <= _rate(sl["cut"], sl["covered"]) + 0.2:
		print("FAIL: tin mail should be cut far more often than copper mail"); fails += 1
	if tsl["cut"] > 0:
		print("FAIL: a tin blade should not cut copper mail at average strength"); fails += 1
	return fails
