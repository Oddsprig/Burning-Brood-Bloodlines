extends RefCounted
## v0.100: fixes found by running the older tests.
## 1. The autosave copies a large world over many frames. Changing the world meanwhile used to throw index errors
##    and leave keys out; the copy now walks what it started with and counts the change.
## 2. The siege preview created the marriage record (a read that wrote); an attack now waits for the save.
## 3. An archer with a knocked-down enemy beside him stood idle with his bow while the fallen man stabbed him.
const B = preload("res://tests/test_bows_sim.gd")
const U = preload("res://tests/sim_util.gd")

var checks := 0
var fails := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	if ok: print("ok   ", what)
	else:
		fails += 1
		print("FAIL ", what)

func run(_tree: SceneTree) -> int:
	_snapshot_changes()
	_reads_do_not_write()
	_attack_waits_for_save()
	_archer_and_fallen_foe()
	print("v100 checks %d, failures %d" % [checks, fails])
	return fails

func _snapshot_changes() -> void:
	# A dictionary gains a key and loses another after its copy began.
	var snap := SaveSnapshot.new()
	var src := {"a": 1, "b": [1, 2, 3], "c": {"x": 1}}
	var out: Dictionary = snap._container(src)
	src["d"] = {"late": true}
	src.erase("c")
	var done := snap.step(0)
	check(done, "snapshot: the copy finishes after the dictionary changed")
	check(out.has("a") and out.has("b") and not out.has("c") and not out.has("d"),
		"snapshot: the copy keeps the keys it started with that still exist (%s)" % str(out.keys()))
	check(snap.changed_during_capture >= 1, "snapshot: the change is counted (%d)" % snap.changed_during_capture)
	# A list grows after its copy began.
	var snap2 := SaveSnapshot.new()
	var arr := [1, {"k": 1}, 3]
	var out2: Array = snap2._container(arr)
	arr.append({"late": 2})
	check(snap2.step(0), "snapshot: the copy finishes after the list grew")
	check(out2.size() == 3 and (out2[1] as Dictionary).get("k", 0) == 1, "snapshot: the list copy keeps its first 3 entries")
	check(snap2.changed_during_capture >= 1, "snapshot: the list change is counted")
	# No change: nothing counted.
	var snap3 := SaveSnapshot.new()
	var same := {"a": [1, 2], "b": {"c": 3}}
	var out3: Dictionary = snap3._container(same)
	check(snap3.step(0) and snap3.changed_during_capture == 0 and JSON.stringify(out3) == JSON.stringify(same),
		"snapshot: an unchanged tree copies exactly with nothing counted")

func _reads_do_not_write() -> void:
	var fake := {"world": {"towns": {}}}
	check(not Marriage.has_claim(fake, "t0"), "marriage: no claim in a world without a marriage record")
	check(not (fake["world"] as Dictionary).has("marriage"), "marriage: asking about a claim does not create the record")
	fake["world"]["marriage"] = {"claims": {"t3": {}}}
	check(Marriage.has_claim(fake, "t3"), "marriage: a stored claim is still found")

func _attack_waits_for_save() -> void:
	var held = Game._save_capture
	Game._save_capture = SaveSnapshot.new()
	var r := Warfare.start(Game, "t0", "siege")
	Game._save_capture = held
	check(not bool(r.get("ok", true)) and str(r.get("reason", "")).contains("save"),
		"attack: refused while the save copies the world (%s)" % str(r.get("reason", "")))

func _archer_and_fallen_foe() -> void:
	# The old bows test's cornered archer: the swordsman falls beside him (a nerve hit to the legs) and keeps striking.
	var a := B.archer("self_bow", 0, 4, {"arrow_copper_bodkin": 50})
	var foe := U.soldier("copper", "arming_sword", "", "", "")
	var sim := B.sim_of([a], [foe], 5, {"w": 16, "h": 5, "cells0": [Vector2i(0, 2)], "cells1": [Vector2i(9, 2)]})
	var switched := ""
	var sidearm := 0
	var fallen_beside := false
	while not sim.is_over() and sim.tick < 3000:
		sim.step()
		var f = sim.fighters[1]
		if f.prone and f.active() and maxi(absi(f.cell.x - sim.fighters[0].cell.x), absi(f.cell.y - sim.fighters[0].cell.y)) <= 1:
			fallen_beside = true
		for e in sim.new_events:
			var en: Dictionary = e.get("entry", {})
			if en.is_empty(): continue
			var key := str(en["d"].get("key", ""))
			if key in ["drop_bow", "sling_bow"] and switched == "": switched = key
			if en["k"] == "strike" and int(en["d"].get("a", -1)) == 0 and not en["d"].has("shot"): sidearm += 1
	print("   cornered archer: fallen foe beside him %s, switched by %s, %d sidearm strikes, winner %d at tick %d" % [fallen_beside, switched if switched != "" else "-", sidearm, sim.winner, sim.tick])
	check(fallen_beside, "archer: the fixture still puts a fallen, fighting foe beside him")
	check(switched != "", "archer: he puts the bow away for his sword")
	check(sidearm > 0, "archer: he fights back with the sword (%d strikes)" % sidearm)
	# The check itself: a foe on the ground beside him counts; one two tiles away does not.
	check(Archery.foe_beside(sim, sim.fighters[0]) == (sim.fighters[1].active() and not sim.fighters[1].routed and maxi(absi(sim.fighters[1].cell.x - sim.fighters[0].cell.x), absi(sim.fighters[1].cell.y - sim.fighters[0].cell.y)) <= 1),
		"archer: foe_beside matches the field at the end")
