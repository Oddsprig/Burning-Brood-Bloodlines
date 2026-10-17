extends RefCounted
## v0.014: a roster row keeps its name in view when a man carries status tags ("badly wounded", "stays in
## camp"): the name has its own line and the tags shrink under it. Checked at 720 px wide (a phone held
## upright, laid out unscaled) and at the game's 1280 base.

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: ", what)

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.new_game(11)
	Game.location = ""
	var victim: Unit = Roster.troops_of(Game, Roster.leaders(Game)[0].uid)[0]
	victim.name = "Petra Coldwater"
	for p in ["arm_upper_l", "leg_upper_r", "arm_lower_r", "leg_lower_l"]:
		for l in victim.body.wound_part(p).get("layers", []):
			if l["tissue"] in ["skin", "muscle", "bone"]:
				l["dmg"] = 0.9; l["kind"] = "fractured" if l["tissue"] == "bone" else "cut"
	Game.invalidate_deploy()
	var st: String = HealthReport.describe(victim).get("status", "healthy")
	var why: String = Game.deploy_block_reason(victim)
	print("  status '%s', stays in: '%s'" % [st, why])
	check(st != "healthy" and why != "", "the test man is wounded and kept in camp")
	for w in [Vector2i(720, 1280), Vector2i(1280, 720)]:
		var sv := SubViewport.new()
		sv.size = w
		sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
		tree.root.add_child(sv)
		var s: Node = (load("res://ui/company.tscn") as PackedScene).instantiate()
		sv.add_child(s)
		for i in 3:
			await tree.process_frame
		var found := false
		for n in s.list_box.get_children():
			var l := n.find_child("RosterName", true, false) as Label
			if l == null or not l.text.begins_with("Petra Coldwater"):
				continue
			found = true
			var name_w := l.get_theme_font("font").get_string_size("Petra Coldwater", HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
			check(l.size.x >= name_w, "%s: the name gets %d px of the %d it needs" % [w, int(l.size.x), int(name_w)])
			var tags := n.find_child("RosterTags", true, false) as Control
			check(tags != null and tags.get_child_count() >= 1, "%s: the tags show" % [w])
			var row := n as Control
			if tags != null:
				var tr := tags.get_global_rect()
				var rr := row.get_global_rect()
				check(tr.end.x <= rr.end.x + 1.0 and tr.end.y <= rr.end.y + 1.0, "%s: the tags stay inside the row (%s in %s)" % [w, tr, rr])
				var lr := l.get_global_rect()
				check(lr.end.y <= tr.position.y + 1.0, "%s: the tags sit under the name" % [w])
		check(found, "%s: the man's row is listed" % [w])
		sv.queue_free()
		await tree.process_frame
	return fails
