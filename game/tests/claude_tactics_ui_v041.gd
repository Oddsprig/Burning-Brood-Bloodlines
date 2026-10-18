extends RefCounted
## v0.041: orders on the between-rounds card.
## The card is RoundSummary.round_panel, the panel battle.gd shows after a round.
## The round state matches that summary (tactics + tactic_note). No screenshots.
## Check/frames follow tests/claude_rounds.gd. The world load and the fight stay in
## claude_rounds.gd and claude_tactics_v041.gd; this run only builds the card.

var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func frames(tree: SceneTree, n: int = 3) -> void:
	for _i in n:
		await tree.process_frame


func run(tree: SceneTree) -> int:
	await frames(tree, 1)
	if BattleTactics._pending_picks.size() >= 2:
		BattleTactics._pending_picks[0] = ""
		BattleTactics._pending_picks[1] = ""
	var saved_terrain := str(Game.pending_battle.get("terrain", ""))
	var had_next := Game.pending_battle.has("next_tactic")
	var saved_next: Variant = Game.pending_battle.get("next_tactic", []).duplicate()
	Game.pending_battle["terrain"] = "forest"
	if had_next:
		Game.pending_battle.erase("next_tactic")

	var note := BattleTactics.outcome_note("hold", "charge", 0, true)
	var d := {
		"round": 1,
		"winner": 0,
		"names": ["Your army", "The enemy"],
		"fought": [10, 10],
		"dead": [1, 2],
		"wounded": [1, 1],
		"captured": [0, 1],
		"fled": [0, 0],
		"morale": [62, 48],
		"morale_change": [2, -6],
		"fresh_left": [8, 7],
		"household": [],
		"broke": -1,
		"tactics": ["hold", "charge"],
		"tactic_note": note,
	}
	var panel := RoundSummary.round_panel(d, func() -> void: pass, false)
	var host := CenterContainer.new()
	host.theme = UiTheme.get_theme()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(panel)
	tree.root.add_child(host)
	await frames(tree, 2)

	for key in BattleTactics.ORDER:
		var tactic := String(key)
		var named: Button = panel.find_child("TacticButton_" + tactic, true, false) as Button
		check(named != null, "TacticButton_%s exists" % tactic)
		if named != null:
			check(named.tooltip_text.contains(BattleTactics.description(tactic)), "TacticButton_%s tooltip is the one-line description" % tactic)
		var desc_l: Label = panel.find_child("TacticDesc_" + tactic, true, false) as Label
		check(desc_l != null and desc_l.text == BattleTactics.description(tactic), "description label for %s" % tactic)

	var last: Label = panel.find_child("TacticLast", true, false) as Label
	var last_text := ""
	if last != null:
		last_text = last.text
	check(last != null and last_text == "You: Shield wall  -  Them: Charge", "last round tactics line (got '%s')" % last_text)
	var orders: Label = panel.find_child("TacticOrders", true, false) as Label
	check(orders != null and orders.text == "Orders for the next round", "orders row heading")

	var note_l: Label = panel.find_child("TacticNote", true, false) as Label
	var note_text := ""
	if note_l != null:
		note_text = note_l.text
	check(note_l != null and note_text == note and note.length() > 5, "tactic_note shows (got '%s')" % note_text)

	var hold: Button = panel.find_child("TacticButton_hold", true, false) as Button
	var charge: Button = panel.find_child("TacticButton_charge", true, false) as Button
	var flank: Button = panel.find_child("TacticButton_flank", true, false) as Button
	var hold_text := ""
	var charge_text := ""
	if hold != null:
		hold_text = hold.text
	if charge != null:
		charge_text = charge.text
	check(hold != null and hold_text.contains("favoured here"), "hold is favoured here (got '%s')" % hold_text)
	check(charge != null and charge_text.contains("unfavoured here"), "charge is unfavoured here (got '%s')" % charge_text)
	check(hold != null and hold.theme_type_variation == "RowOn", "carried-over order (hold) is highlighted as RowOn")
	check(charge != null and charge.theme_type_variation == "Row", "non-carried order is not highlighted before a pick")

	if flank != null:
		flank.pressed.emit()
	await frames(tree, 1)
	check(flank != null and flank.theme_type_variation == "RowOn" and hold != null and hold.theme_type_variation == "Row",
		"pressing TacticButton_flank moves RowOn highlight from carried order to flank")

	if hold != null:
		hold.pressed.emit()
	await frames(tree, 1)

	var nxt: Variant = Game.pending_battle.get("next_tactic", [])
	var stored := ""
	if nxt is Array and (nxt as Array).size() > 0:
		stored = str((nxt as Array)[0])
	check(stored == "hold", "pressing TacticButton_hold stored the pick (got '%s')" % stored)
	check(hold != null and hold.theme_type_variation == "RowOn", "the current pick is highlighted")
	check(charge != null and charge.theme_type_variation == "Row", "the other tactics are not highlighted")

	var over_panel := RoundSummary.round_panel(d, func() -> void: pass, true)
	host.add_child(over_panel)
	await frames(tree, 1)
	check(over_panel.find_child("TacticLast", true, false) != null, "battle_over panel still shows last round tactics")
	check(over_panel.find_child("TacticOrders", true, false) == null and over_panel.find_child("TacticOrdersRow", true, false) == null,
		"battle_over panel hides 'Orders for the next round'")

	host.queue_free()
	if BattleTactics._pending_picks.size() >= 2:
		BattleTactics._pending_picks[0] = ""
		BattleTactics._pending_picks[1] = ""
	if had_next:
		Game.pending_battle["next_tactic"] = saved_next
	else:
		Game.pending_battle.erase("next_tactic")
	if saved_terrain == "":
		Game.pending_battle.erase("terrain")
	else:
		Game.pending_battle["terrain"] = saved_terrain
	print("tactics ui v041: %d checks, %d failures" % [checks, fails])
	return fails
