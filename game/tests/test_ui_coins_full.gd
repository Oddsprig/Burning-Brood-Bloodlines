extends RefCounted
## Douglas 10-06: "we should be able to see at least a million coins". The purse line on the town, company and
## baggage screens shows the whole sum (1,234,567 with separators), never cut off with "...", at phone and PC widths.
func run(tree: SceneTree) -> int:
	var fails := 0
	await tree.process_frame
	if UiKit.thousands(1000000) != "1,000,000" or UiKit.thousands(999) != "999" or UiKit.thousands(-12345) != "-12,345":
		print("FAIL: thousands formatting"); fails += 1
	WorldGen.gen_size = "normal"
	Game.new_game(31)
	Game.location = String(Game.world["towns"].keys()[0])
	Game.gold = 1234567
	for size in [Vector2i(720, 1280), Vector2i(1280, 720)]:
		for path in ["res://ui/town.tscn", "res://ui/company.tscn", "res://ui/baggage.tscn"]:
			var sv := SubViewport.new()
			sv.size = size
			sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
			tree.root.add_child(sv)
			var s: Node = (load(path) as PackedScene).instantiate()
			sv.add_child(s)
			for i in 3:
				await tree.process_frame
			var lbl = s.get("purse")
			if not (lbl is Label):
				print("FAIL: %s has no purse label" % path); fails += 1
			else:
				var l: Label = lbl
				if not l.text.contains("1,234,567 coins"):
					print("FAIL: %s purse text '%s'" % [path, l.text]); fails += 1
				if l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
					print("FAIL: %s purse can be cut off" % path); fails += 1
				# the purse lies inside its screen, and its text fits its own width on one line or wraps (never trimmed)
				var r := l.get_global_rect()
				var sr: Rect2 = (s as Control).get_global_rect()
				# (720 wide: the town and company screens are still wider than a phone (other rows), checked by test_ui_fit)
				if size.x >= 1280 and (r.end.x > sr.end.x + 1 or r.position.x < sr.position.x - 1):
					print("FAIL: %s purse runs off its screen at %s: %s in %s" % [path, size, r, sr]); fails += 1
			sv.queue_free()
			await tree.process_frame
	print("coins shown in full: %s" % ("ok" if fails == 0 else "FAILED"))
	return fails
