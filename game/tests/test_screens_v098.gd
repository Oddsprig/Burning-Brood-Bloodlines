extends RefCounted
## v0.098 battle screen, Records tables and phone layout (headless):
##  - battle feed lines: whole sentences only, no "/tick" sim numbers, side colours that match the banners;
##  - battle bar: Settings in the same plate as its neighbours, the strength bar captioned "Standing";
##  - phone battle bar: the status line no longer squeezes to one letter per line (a bar 500+ px tall);
##  - UiTheme.px: fixed desktop text sizes grow on a phone by the theme's own +10, desktop unchanged;
##  - Records rows pack their columns on a wide desktop; phones keep the full width;
##  - the market "Week record" column now says the biggest 7-day price change plainly (x16.5, not +1552%).
## -- --test=res://tests/test_screens_v098.gd
const BattleScreen := preload("res://battle/battle.gd")

var fails := 0

func check(cond: bool, what: String) -> void:
	if cond: print("  ok: ", what)
	else:
		fails += 1
		printerr("FAIL: ", what)

func run(tree: SceneTree) -> int:
	await tree.process_frame
	_toast_text()
	_combat_text()
	_px()
	_price_move()
	await _rec_cells(tree)
	await _battle(tree, false)
	await _battle(tree, true)
	UiTheme.set_mobile_override(null)
	print("test_screens_v098: %d failures" % fails)
	return fails

func _toast_text() -> void:
	var short := "Sibrek Anvilbrow turns and flees in panic!"
	check(BattleScreen.toast_text(short) == short, "a short line is shown whole")
	var two := "The copper bodkin arrow strikes Rakust Oakenshield in the left lower leg, running through the muscle! Blood trickles from a nicked vessel. The arrow sticks fast."
	var t := BattleScreen.toast_text(two)
	check(t == "The copper bodkin arrow strikes Rakust Oakenshield in the left lower leg, running through the muscle!", "a long line keeps its whole first sentence, not a cut second one (%s)" % t)
	var three := "Mistem throws down all courage and bolts! Logem turns and flees in panic! Sibrek Anvilbrow turns and flees in panic too, dropping his shield and his helm."
	check(BattleScreen.toast_text(three) == "Mistem throws down all courage and bolts! Logem turns and flees in panic!", "as many whole sentences as fit")
	check(t.length() <= BattleScreen.TOAST_CAP, "within the desktop cap")
	var phone := BattleScreen.toast_text(two, BattleScreen.TOAST_CAP_MOBILE)
	check(phone.length() <= BattleScreen.TOAST_CAP_MOBILE and (phone.ends_with("!") or phone.ends_with("...")) and two.begins_with(phone.trim_suffix("...")), "the phone cap keeps the start of the first sentence (%s)" % phone)
	var one := "The human March bowman Clara's copper bodkin arrow hits Litast Deepdelver in the right upper leg, ripping the muscle and tearing through the vessel beneath while he stumbles"
	var cut := BattleScreen.toast_text(one)
	check(cut.ends_with("...") and cut.length() <= BattleScreen.TOAST_CAP, "one long sentence is cut with ... (%s)" % cut)
	var stem := cut.trim_suffix("...")
	check(one.begins_with(stem) and (one.length() == stem.length() or one[stem.length()] in " ,;:"), "the cut falls between words, not inside one")
	check(BattleScreen.toast_text("  Mistem falls.  ") == "Mistem falls.", "edges trimmed")
	check(BattleScreen.toast_text("Wait... he lives! Then he falls.", 20) == "Wait... he lives!", "an ellipsis inside a sentence is not a sentence end")
	check(BattleScreen.toast_text("Wait... he lives and fights on! Then he falls.", 12) == "Wait...", "a first sentence with an ellipsis is cut like any other, not taken as a whole sentence (%s)" % BattleScreen.toast_text("Wait... he lives and fights on! Then he falls.", 12))

func _combat_text() -> void:
	var raw := FileAccess.get_file_as_string("res://data/combat_text.json")
	check(raw != "" and not raw.contains("/tick") and not raw.contains("{RATE}"), "no per-tick bleed rates in any combat line")

func _px() -> void:
	UiTheme.set_mobile_override(false)
	check(UiTheme.px(15) == 15 and UiTheme.px(24) == 24 and UiTheme.px(56) == 56, "desktop sizes unchanged")
	UiTheme.set_mobile_override(true)
	check(UiTheme.px(15) == 25 and UiTheme.px(24) == 34 and UiTheme.px(28) == 38, "phone small sizes +10, like the theme's own")
	check(UiTheme.px(46) == 46 and UiTheme.px(56) == 56, "phone display sizes stay")
	check(UiTheme.px(16) >= UiTheme.MOBILE_FONT_SIZE - 4, "a 16 px desktop label is near the phone body size")
	UiTheme.set_mobile_override(false)

func _price_move() -> void:
	check(RecMarket.price_move_text("fresh meat", 15.52) == "fresh meat ×16.5", "a big rise reads as a multiple (%s)" % RecMarket.price_move_text("fresh meat", 15.52))
	check(RecMarket.price_move_text("beer", 0.26) == "beer +26%", "a small rise keeps the percent")
	check(RecMarket.price_move_text("ruby", -0.3) == "ruby -30%", "a fall keeps the percent")
	check(RecMarket.price_move_text("charcoal", 1.0) == "charcoal ×2", "doubled reads x2")
	var src := FileAccess.get_file_as_string("res://ui/rec_market.gd")
	check(not src.contains("\"Week record\""), "no unexplained Week record heading")

func _rec_cells(tree: SceneTree) -> void:
	var long_note := "Fresh meat, beer and grain all rose sharply after the caravans failed to arrive from the coast"
	for mobile in [false, true]:
		UiTheme.set_mobile_override(mobile)
		var host := VBoxContainer.new()
		host.size = Vector2(1560, 400)
		tree.root.add_child(host)
		var box := RecKit.grid(host, ["Kind", "Stock units", "Market days"], [{"values": ["Food", "1879819", "16.8"]}, {"values": ["Arms & armour", "3145", "16.3"]}])
		var rows: Array = box.get_children().filter(func(n): return n is RecCells)
		for r in rows: r.size = Vector2(1560, 56); r._fit()
		var head: RecCells = rows[0]
		var w: Array = head.cells.map(func(c): return c.width)
		if not mobile:
			check(w[0] + w[1] + w[2] < 800.0, "desktop: a 3-column table no longer spreads over 1560 px (%s)" % str(w))
			var whole := true
			for r: RecCells in rows:
				for i in r.cells.size():
					if r.cells[i].width + 0.5 < float(r.natural[i]): whole = false
			check(whole, "desktop: every cell is at least as wide as its text, so nothing new is cut")
			check(rows.all(func(r): return r.cells.map(func(c): return c.width) == w), "desktop: header and rows share the same column widths")
		else:
			check(w[1] > 400.0, "phone: columns keep the full width (%s)" % str(w))
		var box2 := RecKit.grid(host, ["Measure", "Now", "Context"], [{"values": ["Prices", "x1.00", long_note]}])
		var rows2: Array = box2.get_children().filter(func(n): return n is RecCells)
		for r in rows2: r.size = Vector2(1560, 56); r._fit()
		var share := (1560.0 - 20.0 - 20.0) / 3.0
		check(absf(rows2[1].cells[2].width - share) < 1.0, "%s: a long text column keeps its full share (%.0f of %.0f)" % ["phone" if mobile else "desktop", rows2[1].cells[2].width, share])
		host.queue_free()
		await tree.process_frame
	UiTheme.set_mobile_override(false)

func _battle(tree: SceneTree, mobile: bool) -> void:
	UiTheme.set_mobile_override(mobile)
	var tag := "phone" if mobile else "desktop"
	var loaded := await DevTools.start_world(tree, Game.SAVE_PATH)
	check(loaded, tag + ": world fixture loads")
	var town := DevTools.choose_house(Game, func(choice: Dictionary):
		return str(Dynasty.person(Game, str(choice["ruler_uid"])).get("race", "")) == "human")
	DevTools.raise_army(Game, town, 2)
	var rng := RandomNumberGenerator.new(); rng.seed = 98
	Game.pending_battle = {"enemy": Factory.make_warband(rng, "orc_horde", 6), "allies": [], "seed": 98, "terrain": "open"}
	var b: Node = (load("res://battle/battle.tscn") as PackedScene).instantiate()
	tree.root.size = Vector2i(2000, 900) if mobile else Vector2i(1600, 900)
	tree.root.add_child(b)
	b.set_speed(0.0)
	await tree.process_frame
	await tree.process_frame
	var gear: Button = b.find_child("BattleSettings", true, false)
	var logb: Button = b.find_child("BattleCombatLog", true, false)
	check(gear != null and logb != null, tag + ": Settings and Combat log buttons found")
	if gear != null and logb != null:
		var gs := gear.get_theme_stylebox("normal") as StyleBoxFlat
		var ls := logb.get_theme_stylebox("normal") as StyleBoxFlat
		check(gs != null and ls != null and gs.bg_color == ls.bg_color, tag + ": Settings has the same plate as Combat log")
		check(gear.get_theme_color("font_color") == logb.get_theme_color("font_color"), tag + ": and the same text colour")
	var cap: Label = b.find_child("StrengthCaption", true, false)
	var bar: Control = b.find_child("StrengthBar", true, false)
	check(cap != null and cap.text == "Standing" and cap.is_visible_in_tree(), tag + ": the strength bar has a caption")
	check(bar != null and bar.tooltip_text.contains("gold") and bar.tooltip_text.contains("blue"), tag + ": its tooltip says whose colour is whose")
	var pb: Control = b._playback_bar
	var pb_h := pb.size.y if pb != null else 9999.0
	check(pb_h > 0.0 and pb_h < 200.0, tag + ": playback bar is one row high (%.0f px)" % pb_h)
	if mobile:
		var st: Label = b.status_label
		check(st.autowrap_mode == TextServer.AUTOWRAP_OFF and st.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "phone: status line is one trimmed line")
		check(st.size.x >= 200.0, "phone: status line has room (%.0f px)" % st.size.x)
	var ours := -1
	var theirs := -1
	for i in b.sim.fighters.size():
		if b.sim.fighters[i].side == 0 and ours < 0: ours = i
		if b.sim.fighters[i].side == 1 and theirs < 0: theirs = i
	var long := "The copper bodkin arrow strikes Rakust Oakenshield in the left lower leg, running through the muscle! Blood trickles from a nicked vessel. The arrow sticks fast in the bone and he howls."
	b._add_feed({"text": long, "actor": ours})
	b._add_feed({"text": "Sibrek turns and flees in panic!", "actor": theirs})
	var lines: Array = b.feed_box.get_children().filter(func(n): return n is Button and not n.is_queued_for_deletion())
	check(lines.size() >= 2, tag + ": two feed lines")
	if lines.size() >= 2:
		var first: Button = lines[lines.size() - 2]
		var second: Button = lines[lines.size() - 1]
		var cap_n: int = BattleScreen.TOAST_CAP_MOBILE if mobile else BattleScreen.TOAST_CAP
		if mobile:
			check(first.text.length() <= cap_n and (first.text.ends_with("!") or first.text.ends_with("...")), tag + ": the feed shows the line's start, cut between words (%s)" % first.text)
		else:
			check(first.text.length() <= cap_n and first.text.ends_with("!") and not first.text.ends_with("..."), tag + ": the feed shows whole sentences (%s)" % first.text)
		check(first.tooltip_text == long, tag + ": the full line stays in the tooltip")
		check(first.get_theme_color("font_color") == BattleScreen.TOAST_OURS, tag + ": your side's line is gold like your banners")
		check(second.get_theme_color("font_color") == BattleScreen.TOAST_THEIRS, tag + ": the enemy's line is blue like theirs")
		if mobile:
			check(first.autowrap_mode != TextServer.AUTOWRAP_OFF, "phone: a feed line wraps instead of cutting at 30 letters")
	for i in 6: b._add_feed({"text": "Line %d." % i, "actor": ours})
	await tree.process_frame
	var kept: int = b.feed_box.get_children().filter(func(n): return not n.is_queued_for_deletion()).size()
	check(kept <= (BattleScreen.FEED_MAX_MOBILE if mobile else BattleScreen.FEED_MAX), tag + ": feed keeps at most its line count (%d)" % kept)
	b.queue_free()
	await tree.process_frame
	Game.pending_battle = {}
	UiTheme.set_mobile_override(false)
