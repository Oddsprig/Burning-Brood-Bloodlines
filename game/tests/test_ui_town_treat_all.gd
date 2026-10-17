extends RefCounted
## Healer tab "Treat all": treats everyone who needs it, most critical first, with the same per-man treatment as
## the single Treat (same cost, same Healing.treat); the total equals treating each singly; when coin runs short it
## stops and names who was treated and who was left.

const H = preload("res://tests/health_util.gd")

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)
	else:
		print("ok: ", msg)

## Sparse bodies only store hit parts: materialise the part first, then wound it.
func _w(u: Unit, pid: String, layer: String, kind: String, dmg: float, bleed: float = 0.0) -> void:
	u.body.wound_part(pid)
	H.wound(u, pid, layer, kind, dmg, bleed)

## Three men with wounds of rising seriousness, deliberately in the wrong company order.
func _men(tag: String) -> Array:
	var mild := H.human(tag + "-mild")
	_w(mild, "leg_upper_r", "skin", "bruised", 0.3)
	var mid := H.human(tag + "-mid")
	_w(mid, "arm_upper_r", "muscle", "torn", 0.6, 0.02)
	var bad := H.human(tag + "-bad")
	_w(bad, "leg_lower_l", "bone", "broken", 0.8, 0.02)
	_w(bad, "arm_upper_l", "bone", "fractured", 0.6)
	for u in [mild, mid, bad]:
		Healing.update_heal_days(u)
	return [mild, mid, bad]

func run(tree: SceneTree) -> int:
	Game.new_game(4411)
	var t: Dictionary = {}
	for id in Game.world["towns"].keys():
		if TownEcon.has_econ(Game.world["towns"][id]):
			t = Game.world["towns"][id]
			break
	check(not t.is_empty(), "a town with an economy")
	if t.is_empty():
		return fails
	t["healer"] = {"skill": 8, "name": "Healer"}
	Game.location = String(t["id"])
	var s: Node = load("res://ui/town.tscn").instantiate()
	tree.root.add_child.call_deferred(s)
	await tree.process_frame
	await tree.process_frame

	# nobody needs treatment: the button is there but disabled
	Game.company.clear()
	s.show_tab("Healer")
	await tree.process_frame
	var b := s.find_child("TreatAll", true, false) as Button
	check(b != null and b.disabled, "no wounded: Treat all is disabled")

	# the batch
	var batch := _men("A")
	for u in batch:
		Game.company.append(u)
	var singles := _men("S")
	var total := 0
	for u in singles:
		total += Healing.treatment_cost(u, 8)
	check(total > 0, "the wounded need treatment (%d coins)" % total)
	Game.gold = total + 1000
	s.refresh()
	await tree.process_frame
	b = s.find_child("TreatAll", true, false) as Button
	check(b != null and not b.disabled and b.text.contains("3"), "wounded: Treat all enabled, shows the count (%s)" % (b.text if b != null else "-"))

	var g0 := Game.gold
	var r: Dictionary = s.treat_all(t)
	var names := []
	for u in r["treated"]:
		names.append(u.name)
	check(names == ["A-bad", "A-mid", "A-mild"], "critical first: %s" % str(names))
	check(r["left"].is_empty(), "nobody left")
	check(Game.gold == g0 - total and int(r["spent"]) == total, "charged %d, the same as the three singles (%d)" % [g0 - Game.gold, total])
	Game.gold = total + 1000
	var g1 := Game.gold
	for u in singles:
		var c := Healing.treatment_cost(u, 8)
		s._treat_one(t, u, c)
	check(g1 - Game.gold == total, "treating each singly charged the same total")
	var same := true
	for i in 3:
		same = same and is_equal_approx(batch[i].body.days_to_heal(), singles[i].body.days_to_heal())
		same = same and Healing.treatment_cost(batch[i], 8) == 0
	check(same, "the batch left each man exactly as a single treatment does (nothing left to treat)")

	# coin runs short: the dearest-critical first, then stop and report
	Game.company.clear()
	var again := _men("B")
	for u in again:
		Game.company.append(u)
	var costs := {}
	for u in again:
		costs[u.name] = Healing.treatment_cost(u, 8)
	Game.gold = int(costs["B-bad"]) + int(costs["B-mid"]) + 0   # enough for the two worst only
	var short: Dictionary = s.treat_all(t)
	var tn := []
	for u in short["treated"]:
		tn.append(u.name)
	var ln := []
	for u in short["left"]:
		ln.append(u.name)
	check(tn == ["B-bad", "B-mid"] and ln == ["B-mild"], "short of coin: treated %s, left %s" % [str(tn), str(ln)])
	check(Game.gold == 0 and Healing.treatment_cost(again[0], 8) > 0, "the one left is still untreated and the purse is spent")
	check(not (s.find_child("TreatAll", true, false) as Button).disabled, "Treat all stays enabled for the man left")

	s.queue_free()
	await tree.process_frame
	Game.location = ""
	return fails
