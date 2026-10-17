extends RefCounted
## Healing: timers, bandaging, town vs road, healers, lasting damage, permanence, determinism.

const H = preload("res://tests/health_util.gd")

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", msg)

func arm_wound(u: Unit) -> void:
	H.wound(u, "arm_upper_l", "skin", "cut", 0.6, 0.01)
	H.wound(u, "arm_upper_l", "muscle", "torn", 0.5, 0.02)
	H.wound(u, "arm_upper_l", "bone", "fractured", 0.6)

func run(_tree: SceneTree) -> int:
	# --- timers by tissue/kind
	var u := H.human()
	H.wound(u, "leg_upper_r", "skin", "bruised", 0.3)
	H.wound(u, "arm_upper_r", "muscle", "torn", 0.6)
	H.wound(u, "arm_upper_l", "bone", "fractured", 0.6)
	H.wound(u, "leg_lower_l", "bone", "broken", 0.8)
	H.wound(u, "hand_l", "skin", "cut", 0.5)
	Healing.update_heal_days(u)
	var bruise: float = H.layer(u, "leg_upper_r", "skin")["heal_days"]
	var cut: float = H.layer(u, "hand_l", "skin")["heal_days"]
	var torn: float = H.layer(u, "arm_upper_r", "muscle")["heal_days"]
	var frac: float = H.layer(u, "arm_upper_l", "bone")["heal_days"]
	var broke: float = H.layer(u, "leg_lower_l", "bone")["heal_days"]
	print("timers (REC 1000): bruise %.1f, cut %.1f, torn muscle %.1f, fractured bone %.1f, broken bone %.1f" % [bruise, cut, torn, frac, broke])
	check(bruise > 0.0 and bruise < 7.0, "bruise days")
	check(cut >= 4.0 and cut <= 10.0, "cut about a week")
	check(torn >= 14.0 and torn <= 42.0, "torn muscle weeks")
	check(frac >= 28.0 and frac <= 60.0, "fracture 1-2 months")
	check(broke >= 45.0, "broken bone 1.5+ months")
	check(bruise < cut and cut < torn and torn < frac and frac < broke, "ordering")

	# --- idempotent, never shortens
	var snap := JSON.stringify(u.to_dict())
	Healing.update_heal_days(u)
	check(JSON.stringify(u.to_dict()) == snap, "update_heal_days idempotent")
	H.layer(u, "arm_upper_l", "bone")["heal_days"] = 90.0
	Healing.update_heal_days(u)
	check(H.layer(u, "arm_upper_l", "bone")["heal_days"] == 90.0, "never shortens")
	Healing.heal(u, 10.0, true)
	var mid: float = H.layer(u, "leg_lower_l", "bone")["heal_days"]
	Healing.update_heal_days(u)
	check(H.layer(u, "leg_lower_l", "bone")["heal_days"] == mid, "partial heal not reset by update")
	# fresh damage on a healing wound re-assesses upward
	H.layer(u, "leg_lower_l", "bone")["dmg"] = 0.95
	Healing.update_heal_days(u)
	check(H.layer(u, "leg_lower_l", "bone")["heal_days"] > mid, "new damage lengthens timer")

	# --- REC scaling
	var slow := H.human(); slow.attrs["REC"] = 500
	var fast := H.human(); fast.attrs["REC"] = 2000
	for x in [slow, fast]:
		H.wound(x, "arm_upper_l", "bone", "fractured", 0.6)
		Healing.update_heal_days(x)
	check(H.layer(slow, "arm_upper_l", "bone")["heal_days"] > frac and H.layer(fast, "arm_upper_l", "bone")["heal_days"] < frac, "REC scales timers")

	# --- bandaging after battle
	u = H.human()
	arm_wound(u)
	H.wound(u, "lung_l", "left lung", "pierced", 0.5, 0.04)
	Healing.after_battle(u)
	check(H.layer(u, "arm_upper_l", "muscle")["bleed"] == 0.0, "bandaged limb stops bleeding")
	check(H.layer(u, "lung_l", "left lung")["bleed"] > 0.0 and H.layer(u, "lung_l", "left lung")["bleed"] < 0.04, "internal bleeding slowed, not stopped")
	check(H.layer(u, "arm_upper_l", "bone")["heal_days"] > 0.0, "after_battle assesses")
	Healing.heal(u, 1.0, false)
	check(u.body.total_bleed() < 0.01, "internal bleeding stops within a day or so")

	# --- heals over time, town faster than road, healer faster still
	var town := H.human(); var road := H.human(); var doc := H.human(); var camp := H.human()
	for x in [town, road, doc, camp]:
		arm_wound(x)
		x.body.blood = x.body.blood_max * 0.75
		x.body.pain = 40.0
		x.body.exertion = 30.0
		Healing.after_battle(x)
	Healing.treat(doc, 10)
	for i in 10:
		Healing.heal(town, 1.0, true)
		Healing.heal(road, 1.0, false)
		Healing.heal(doc, 1.0, true)
		Healing.heal(camp, 1.0, false, 12)
	var t_town: float = town.body.days_to_heal()
	print("after 10 days: town %.1f, road %.1f, treated in town %.1f, road with camp healer %.1f days left" % [t_town, road.body.days_to_heal(), doc.body.days_to_heal(), camp.body.days_to_heal()])
	check(t_town < road.body.days_to_heal(), "town faster than road")
	check(doc.body.days_to_heal() < t_town, "treated faster")
	check(camp.body.days_to_heal() < road.body.days_to_heal(), "camp healer helps")
	check(H.layer(town, "arm_upper_l", "skin")["dmg"] == 0.0, "skin cut healed in 10 days")
	check(H.layer(town, "arm_upper_l", "bone")["dmg"] > 0.0 and H.layer(town, "arm_upper_l", "bone")["dmg"] < 0.6, "bone partly healed")
	check(town.body.blood == town.body.blood_max, "blood restored")
	check(town.body.pain == 0.0 and town.body.exertion == 0.0, "pain and exertion reset")
	var mend: Dictionary = H.part_entry(HealthReport.describe(town), "arm_upper_l")
	print("  town arm after 10 days: ", mend.get("text", ""), " [", mend.get("recovery", ""), "]")
	for i in 60:
		Healing.heal(town, 1.0, true)
	check(not town.body.is_wounded(), "fully healed eventually")
	check(HealthReport.describe(town)["status"] == "healthy", "healthy after rest")

	# --- treatment cost
	u = H.human()
	arm_wound(u)
	var cost8 := Healing.treatment_cost(u, 8)
	var cost2 := Healing.treatment_cost(u, 2)
	check(cost8 > 0 and cost8 > cost2, "better healer costs more (%d vs %d)" % [cost8, cost2])
	Healing.treat(u, 8)
	check(Healing.treatment_cost(u, 8) == 0, "already treated")
	check(Healing.treatment_cost(u, 12) > 0, "a better healer can still treat")
	check(Healing.treatment_cost(H.human(), 8) == 0, "healthy costs nothing")
	check(u.body.total_bleed() == 0.0, "treat stops bleeding")

	# --- permanence: severed hand, destroyed eye stay
	u = H.human()
	u.body.wound_part("hand_r")["severed"] = true
	H.wound(u, "eye_l", "eye", "destroyed", 1.0)
	Healing.after_battle(u)
	check("right hand lost" in u.body.permanent and "left eye destroyed" in u.body.permanent, "permanent recorded: %s" % [u.body.permanent])
	Healing.after_battle(u)
	check(u.body.permanent.size() == 2, "no duplicates")
	for i in 200:
		Healing.heal(u, 1.0, true)
	check(u.body.parts["hand_r"]["severed"], "hand stays severed")
	check(H.layer(u, "eye_l", "eye")["kind"] == "destroyed" and H.layer(u, "eye_l", "eye")["dmg"] == 1.0, "eye stays destroyed")
	check(u.body.days_to_heal() == 0.0, "nothing left to heal")
	var r := HealthReport.describe(u)
	check(r["status"] == "healthy", "only old injuries -> healthy (%s)" % r["status"])
	check(r["fitness"] == "fights hurt", "maimed veteran fights hurt (%s)" % r["fitness"])
	check(H.part_entry(r, "eye_l")["recovery"] == "permanent", "eye recovery permanent")
	check(u.body.parts["hand_r"]["impair"] == 1.0 and u.body.parts["eye_l"]["impair"] == 1.0, "impair 1 on lost parts")

	# --- bad untreated wounds sometimes heal into lasting damage; treatment makes it rarer
	var limp_untreated := 0
	var limp_treated := 0
	for i in 40:
		for treated in [false, true]:
			var x := H.human()
			x.uid = 5000 + i
			H.wound(x, "leg_lower_l", "bone", "broken", 0.8)
			H.wound(x, "leg_lower_l", "muscle", "mangled", 0.7)
			Healing.after_battle(x)
			if treated:
				Healing.treat(x, 12)
			for d in 30:
				Healing.heal(x, 5.0, true)
			check(not x.body.is_wounded(), "broken leg heals eventually")
			var lamed := false
			for s in x.body.permanent:
				if "limps" in s:
					lamed = true
			if lamed:
				check(float(x.body.parts["leg_lower_l"].get("impair", 0.0)) > 0.0, "limp sets impair")
				if treated: limp_treated += 1
				else: limp_untreated += 1
	print("lasting damage from a broken+mangled lower leg over 40 units: untreated %d, treated (skill 12) %d" % [limp_untreated, limp_treated])
	check(limp_untreated > 10 and limp_untreated < 40, "untreated sometimes lame")
	check(limp_treated < limp_untreated, "treatment helps")
	var lame := H.human()
	lame.body.permanent.append("left lower leg bone badly mended - limps")
	lame.body.wound_part("leg_lower_l")["impair"] = 0.3
	r = HealthReport.describe(lame)
	check("left lower leg bone badly mended - limps - permanent" in r["summary"], "limp in summary")
	check("standing, limping" in r["summary"], "limping stance %s" % [r["summary"]])

	# --- determinism
	var a := H.human(); var b := H.human()
	b.uid = a.uid
	for x in [a, b]:
		arm_wound(x)
		H.wound(x, "leg_lower_r", "bone", "mangled", 0.9)
		x.body.blood = 40.0
		Healing.after_battle(x)
		for i in 25:
			Healing.heal(x, 3.0, i % 2 == 0, 3)
	check(JSON.stringify(a.to_dict()["body"]) == JSON.stringify(b.to_dict()["body"]), "deterministic")

	# --- fitness
	u = H.human()
	check(Healing.fitness_text(u) == "fit to fight" and Healing.is_fit(u), "fit")
	H.wound(u, "hand_l", "skin", "cut", 0.3)
	Healing.after_battle(u)
	check(Healing.fitness_text(u) == "fights hurt" and Healing.is_fit(u), "fights hurt")
	arm_wound(u)
	Healing.after_battle(u)
	check(Healing.fitness_text(u) == "should rest" and not Healing.is_fit(u), "should rest: " + Healing.fitness_text(u))
	H.wound(u, "heart", "heart", "pierced", 0.6)
	check(Healing.fitness_text(u) == "cannot fight", "cannot fight")
	var dead := H.human(); dead.dead = true
	check(Healing.fitness_text(dead) == "cannot fight", "dead cannot fight")

	# --- Game.advance_time hook (2-arg call) works
	u = H.human()
	arm_wound(u)
	Healing.after_battle(u)
	var d0 := u.body.days_to_heal()
	var Hs = load("res://sim/healing.gd")
	Hs.heal(u, 2.0, true)
	check(u.body.days_to_heal() < d0, "load()ed heal works with 3 args")
	return fails
