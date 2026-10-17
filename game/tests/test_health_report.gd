extends RefCounted
## HealthReport: DF-style wording, severity, summary lines, status. Prints sample screens.

const H = preload("res://tests/health_util.gd")

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", msg)

func expect_text(r: Dictionary, pid: String, want: String) -> Dictionary:
	var e := H.part_entry(r, pid)
	check(not e.is_empty(), "no entry for " + pid)
	if not e.is_empty():
		check(e["text"] == want, "%s text: got '%s' want '%s'" % [pid, e["text"], want])
	return e

func has(r: Dictionary, line: String) -> bool:
	return line in r["summary"]

func run(_tree: SceneTree) -> int:
	# healthy
	var u := H.human("Healthy Hal")
	var r := HealthReport.describe(u)
	check(r["parts"].is_empty(), "healthy has no wounds")
	check(r["status"] == "healthy", "healthy status")
	check(has(r, "standing"), "healthy standing")
	check(r["fitness"] == "fit to fight", "healthy fit")
	check(r["heal_days"] == 0.0, "healthy heal_days 0")

	# arm: fractured bone, torn muscle, bleeding
	u = H.human("Arm")
	H.wound(u, "arm_upper_l", "bone", "fractured", 0.6)
	H.wound(u, "arm_upper_l", "muscle", "torn", 0.5, 0.02)
	H.wound(u, "arm_upper_l", "fat", "cut", 0.4)
	r = HealthReport.describe(u)
	var e := expect_text(r, "arm_upper_l", "Left upper arm: bone fractured, muscle torn - bleeding")
	check(e.get("severity", -1) == 2, "fractured arm is serious")
	check(e.get("heal_days", 0.0) > 20.0, "fracture estimate > 20 days before assessment")
	check(e["lines"] == ["bone fractured", "muscle torn", "bleeding"], "lines array %s" % [e["lines"]])
	check(r["status"] == "wounded", "arm status wounded, got " + r["status"])
	check(has(r, "bleeding"), "bleeding summary")
	check("weak grip (left hand)" in r["summary"], "fractured arm weakens grip: %s" % [r["summary"]])

	# head: scalp cut, skull bruised
	u = H.human("Head")
	H.wound(u, "head", "skin", "cut", 0.5)
	H.wound(u, "skull", "skull", "bruised", 0.2)
	r = HealthReport.describe(u)
	e = expect_text(r, "head", "Head: scalp cut")
	check(e.get("severity", -1) == 1, "scalp cut is minor")
	e = expect_text(r, "skull", "Skull: bruised")
	check(e.get("severity", -1) == 1 and e.get("heal_days", 0.0) > 0.0, "separate skull bruise retains minor severity and recovery estimate")
	check(r["parts"].size() == 2, "scalp and internal skull appear as distinct anatomical records")

	# heart pierced
	u = H.human("Heart")
	H.wound(u, "torso_upper", "skin", "pierced", 0.9)
	H.wound(u, "torso_upper", "muscle", "pierced", 0.6)
	H.wound(u, "heart", "heart", "pierced", 0.7, 0.15)
	r = HealthReport.describe(u)
	expect_text(r, "torso_upper", "Upper body: muscle pierced, skin punctured")
	e = expect_text(r, "heart", "Heart: pierced - heavy bleeding")
	check(e.get("severity", -1) == 3, "heart pierced critical")
	check(e.get("lines", []) == ["pierced", "heavy bleeding"] and e.get("heal_days", 0.0) > 0.0, "heart record retains precise internal injury, bleeding and recovery estimate")
	check(r["parts"].size() == 2 and r["parts"][0]["part"] == "heart", "critical heart is reported separately and before outer torso damage")
	check(r["status"] == "badly wounded", "heart status")
	check(has(r, "bleeding heavily"), "bleeding heavily")
	check(r["fitness"] == "cannot fight", "heart cannot fight")

	# severed hand, destroyed eye, blood loss
	u = H.human("Maimed")
	u.body.wound_part("hand_r")["severed"] = true
	H.wound(u, "hand_r", "bone", "broken", 1.0)   # wounds on a lost part don't show
	H.wound(u, "eye_l", "eye", "destroyed", 1.0)
	u.body.blood = u.body.blood_max * 0.72
	r = HealthReport.describe(u)
	e = expect_text(r, "hand_r", "Right hand: severed")
	check(e.get("severity", -1) == 3 and e.get("permanent", false), "severed is critical/permanent")
	e = expect_text(r, "eye_l", "Left eye: destroyed")
	check(e.get("permanent", false), "eye permanent")
	check(has(r, "has lost a lot of blood"), "lot of blood")
	check(has(r, "cannot use the right hand"), "right hand unusable %s" % [r["summary"]])
	check(has(r, "blind in the left eye"), "half blind")
	check(has(r, "right hand lost - permanent"), "hand lost permanent")
	check(has(r, "left eye destroyed - permanent"), "eye destroyed permanent")
	check(not has(r, "cannot hold a weapon"), "one hand still holds")

	# pale, both hands gone, broken leg
	u = H.human("Wreck")
	u.body.blood = u.body.blood_max * 0.8
	u.body.wound_part("arm_lower_l")["severed"] = true
	u.body.wound_part("hand_r")["severed"] = true
	H.wound(u, "leg_lower_l", "bone", "broken", 0.8)
	r = HealthReport.describe(u)
	check(has(r, "is pale"), "pale")
	check(has(r, "cannot hold a weapon"), "no grasp")
	check(has(r, "unable to stand"), "broken leg -> unable to stand %s" % [r["summary"]])
	check(H.part_entry(r, "hand_l").is_empty(), "hand below a severed forearm is not listed")
	expect_text(r, "arm_lower_l", "Left lower arm: severed")
	check(has(r, "left lower arm lost - permanent"), "forearm lost")
	expect_text(r, "leg_lower_l", "Left lower leg: bone broken")

	# guts, spine, pain and bled out
	u = H.human("Gut")
	H.wound(u, "guts", "guts", "torn", 0.6, 0.01)
	H.wound(u, "spine_lower", "lower spine", "broken", 0.7)
	# Current anatomy models the cord separately: the damaged cord prevents standing.
	H.wound(u, "spine_lower", "spinal cord", "torn", 0.7)
	u.body.pain = 110.0
	r = HealthReport.describe(u)
	e = expect_text(r, "guts", "Guts: torn open - bleeding")
	check(e.get("severity", -1) == 3 and e.get("heal_days", 0.0) > 0.0, "torn guts retain critical internal damage and healing estimate")
	e = expect_text(r, "spine_lower", "Lower spine: lower spine broken, spinal cord torn")
	check(e.get("severity", -1) == 2 and e.get("heal_days", 0.0) > 0.0, "broken spine and damaged cord have a separate serious injury record")
	check(r["parts"].size() == 2 and r["flags"]["no_stance"], "gut and spinal injuries remain distinct and cord damage disables stance")
	check(has(r, "unable to stand"), "broken spine with damaged cord -> unable to stand")
	check(has(r, "in agony"), "pain 110 -> agony %s" % [r["summary"]])
	u.body.pain = 160.0
	r = HealthReport.describe(u)
	check(has(r, "unconscious from pain") and r["status"] == "unconscious", "pain KO")
	check(has(r, "prone, unable to stand"), "KO prone")
	u.body.blood = 0.0
	u.dead = true
	r = HealthReport.describe(u)
	check(r["status"] == "dead" and has(r, "has bled out"), "bled out dead")

	# severity 0: skin bruise only
	u = H.human("Bruise")
	H.wound(u, "leg_upper_r", "skin", "bruised", 0.1)
	r = HealthReport.describe(u)
	e = expect_text(r, "leg_upper_r", "Right upper leg: skin bruised")
	check(e.get("severity", -1) == 0, "bruise is a scratch")
	check(r["fitness"] == "fights hurt", "bruise fights hurt: " + r["fitness"])

	# describe is read-only
	u = H.human("RO")
	H.wound(u, "arm_upper_r", "bone", "broken", 0.7, 0.03)
	var before := JSON.stringify(u.to_dict())
	HealthReport.describe(u)
	HealthReport.to_text(u)
	check(JSON.stringify(u.to_dict()) == before, "describe must not mutate")

	_samples()
	return fails

func _samples() -> void:
	print("\n---- sample health screens (fresh from battle, then after bandaging) ----")
	var a := H.human("Aldric Copperhand")
	H.wound(a, "arm_upper_l", "skin", "cut", 0.6)
	H.wound(a, "arm_upper_l", "muscle", "torn", 0.5, 0.02)
	H.wound(a, "arm_upper_l", "bone", "fractured", 0.6)
	H.wound(a, "head", "skin", "cut", 0.4, 0.004)
	H.wound(a, "skull", "skull", "bruised", 0.3)
	a.body.blood = a.body.blood_max * 0.78
	a.body.pain = 30.0
	var b := H.human("Brannoc the Spear")
	H.wound(b, "torso_upper", "skin", "pierced", 0.9)
	H.wound(b, "torso_upper", "muscle", "pierced", 0.7)
	H.wound(b, "rib_true1_l", "first left true rib", "fractured", 0.5)
	H.wound(b, "lung_l", "left lung", "pierced", 0.6, 0.02)
	H.wound(b, "leg_lower_r", "bone", "broken", 0.8)
	H.wound(b, "leg_lower_r", "muscle", "mangled", 0.8, 0.01)
	b.body.blood = b.body.blood_max * 0.72
	b.body.pain = 110.0
	var thorax := HealthReport.describe(b)
	var rib := expect_text(thorax, "rib_true1_l", "First left true rib: fractured")
	check(rib.get("severity", -1) == 2, "real fractured rib reports serious bone damage")
	var lung := expect_text(thorax, "lung_l", "Left lung: pierced - bleeding")
	check(lung.get("severity", -1) == 3 and has(thorax, "short of breath"), "real lung penetration reports critical damage and impaired breathing")
	var c := H.human("Cuthwin One-Eye")
	c.body.wound_part("hand_r")["severed"] = true
	c.body.parts["hand_r"]["layers"][0]["bleed"] = 0.06
	H.wound(c, "eye_l", "eye", "destroyed", 1.0)
	H.wound(c, "head", "skin", "torn", 0.7)
	c.body.blood = c.body.blood_max * 0.8
	var d := H.human("Dunstan Lucky")
	H.wound(d, "leg_upper_r", "skin", "bruised", 0.2)
	H.wound(d, "hand_l", "skin", "cut", 0.3)
	for u in [a, b, c, d]:
		print(HealthReport.to_text(u))
		Healing.after_battle(u)
		print("  after bandaging: ", HealthReport.describe(u)["fitness"], ", heal %.1f days, treatment %d gold (healer skill 8)" % [u.body.days_to_heal(), Healing.treatment_cost(u, 8)])
		print("")
