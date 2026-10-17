extends RefCounted
## v0.033 Court -> Prisoners through main.tscn: the panel lists each realm, Bargain opens its window, and the
## real buttons ransom one prisoner and pay for one captive. Needs a display (screenshots with --out=<dir>).
## -- --test=res://tests/claude_prisoners_ui_v033.gd [--out=<dir>] [--size=WxH]
var fails := 0
var checks := 0
var out := ""

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL prisoners_ui033: ", what)

func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n:
		await tree.process_frame
		await RenderingServer.frame_post_draw

func shot(tree: SceneTree, name: String) -> void:
	if out == "": return
	await frames(tree, 4)
	tree.root.get_texture().get_image().save_png(out.path_join(name + ".png"))

## The visible button with this text under root (the last match, so the newest modal wins).
func button(root: Node, text: String) -> Button:
	var found: Button = null
	for child in root.get_children():
		var b := button(child, text)
		if b != null: found = b
	if found == null and root is Button and (root as Button).text == text and (root as Button).is_visible_in_tree(): found = root
	return found

func has_text(root: Node, part: String) -> bool:
	if root is Label and (root as Label).text.contains(part): return true
	for child in root.get_children():
		if has_text(child, part): return true
	return false

func _person(u: Unit) -> Array:
	var town: Dictionary = Game.world["towns"].get(u.home_town, {})
	var f: Dictionary = People.fam_of(town, u.family) if not town.is_empty() else {}
	return Persons.by_uid(f, u.uid) if not f.is_empty() else []

func run(tree: SceneTree) -> int:
	var size := Vector2i(1600, 900)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=").replace("\\", "/")
		if a.begins_with("--size="):
			var p := a.trim_prefix("--size=").split("x"); size = Vector2i(int(p[0]), int(p[1]))
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000)
	tree.root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 6)
	if not await DevTools.start_world(tree, "user://claude_prisoners_ui_v033-test.json"):
		printerr("FAIL: the start world did not load")
		return 1
	var by_pop: Array = Dynasty.choices(Game)
	by_pop.sort_custom(func(a, b): return int(Game.world["towns"][a["town_id"]]["econ"]["pop"]) > int(Game.world["towns"][b["town_id"]]["econ"]["pop"]))
	var seat := ""
	for choice: Dictionary in by_pop:
		if bool(HouseOnboarding.begin(Game, str(choice["town_id"]), str(choice["household_uid"])).get("ok", false)):
			seat = str(choice["town_id"]); break
	check(seat != "", "a ruling house was chosen")
	if seat == "": return fails
	Game.settings["guide_seen"] = true
	Game.location = seat
	Feudal._payer(Game)["purse"] = 1000.0 * Item.COIN
	Mobilization.fund(Game, 400 * Item.COIN)
	var noble: Unit = null
	for row in Mobilization.household_candidates(Game).slice(0, 1):
		var er: Dictionary = Mobilization.enlist_household(Game, str(row["person_uid"]))
		if er.get("ok", false): noble = er["unit"]
	var quote := Mobilization.quote(Game, seat, 6)
	if quote.get("ok", false): Mobilization.muster(Game, seat, 6, quote["review"])
	var men: Array = Game.company.filter(func(u): return u != noble and u.family >= 0 and not _person(u).is_empty())
	check(noble != null and men.size() >= 1, "a house member and a man ride with the army")
	if noble == null or men.is_empty(): return fails
	var band_id := ""
	for key in Game.world["warbands"]:
		var band: Dictionary = Game.world["warbands"][key]
		if str(band.get("faction", "")) == Diplomacy.player_realm(Game.world) or not Army.is_people_band(band) or Monsters.suspended_band(band): continue
		if str(band.get("kind", "")) in ["caravan", "militia"] or (band["units"] as Array).size() < 6 or (band["units"] as Array).size() > BattleRounds.ROUND: continue
		band_id = str(key); break
	check(band_id != "", "an enemy field band exists")
	if band_id == "": return fails
	var wb: Dictionary = Game.world["warbands"][band_id]
	var enemy := str(wb["faction"])
	Game.world["factions"][enemy]["treasury"] = 500.0 * Item.COIN
	var foes: Array = (wb["units"] as Array).slice(0, 3)
	for side in [0, 1]:   # you beat their band, then they beat yours: prisoners on both sides
		var units: Array = foes if side == 0 else [noble, men[0]]
		Game.pending_battle = {"warband_id": band_id}
		BattleRounds.take_one_clash(Game, {"winner": side, "fighter_units": units, "fighter_states": units.map(func(_u): return "unconscious"), "enemy_units": foes.duplicate()})
		Game.pending_battle = {}
	check(Prisoners.held(Game).size() == 3 and Prisoners.captives(Game).size() == 2, "prisoners taken on both sides")
	Game.goto("court")
	await frames(tree, 8)
	var court: Node = main.current
	check(has_text(court, "Prisoners") and has_text(court, "you hold 3 of theirs; they hold 2 of yours"), "Court lists the realm's prisoners")
	await shot(tree, "court_prisoners")
	var bargain := button(court, "Bargain")
	check(bargain != null, "a Bargain button")
	if bargain == null: return fails
	bargain.pressed.emit()
	await frames(tree, 6)
	check(has_text(court, "Your people they hold (2)") and has_text(court, "Their people you hold (3)"), "the realm window lists both sides")
	await shot(tree, "prisoners_window")
	var purse := float(Feudal._payer(Game)["purse"])
	var ransom := button(court, "Ransom")
	check(ransom != null, "a Ransom button")
	if ransom == null: return fails
	ransom.pressed.emit()
	await frames(tree, 6)
	await shot(tree, "ransom_review")
	var ok := button(court, "Confirm")
	check(ok != null, "the ransom can be confirmed")
	if ok == null: return fails
	ok.pressed.emit()
	await frames(tree, 8)
	check(Prisoners.held(Game).size() == 2 and float(Feudal._payer(Game)["purse"]) > purse, "the button ransomed one prisoner for coin")
	check(has_text(main.current, "ransomed"), "the Court notice reports the ransom")
	Game.wait_save()   # the confirm started an autosave; bargaining waits for it (Prisoners._gate)
	# Pay for one of your own through the buttons.
	bargain = button(main.current, "Bargain")
	if bargain != null: bargain.pressed.emit()
	await frames(tree, 6)
	var pay := button(main.current, "Pay ransom")
	check(pay != null, "a Pay ransom button")
	if pay == null: return fails
	pay.pressed.emit()
	await frames(tree, 6)
	ok = button(main.current, "Confirm")
	if ok != null: ok.pressed.emit()
	await frames(tree, 8)
	check(Prisoners.captives(Game).size() == 1, "the button paid a ransom for one of yours")
	await shot(tree, "court_after")
	Game.wait_save()
	# A real one-clash battle (100 or fewer a side) through the battle scene: whoever lies downed on the
	# loser's side at the end is taken, and nobody else.
	wb = Game.world["warbands"].get(band_id, {})
	check(not wb.is_empty() and not Game.deployed_units().is_empty(), "a band and an army remain for a real small battle")
	if not wb.is_empty() and not Game.deployed_units().is_empty() and (wb["units"] as Array).size() <= BattleRounds.ROUND:
		var before := [Prisoners.captives(Game).size(), Prisoners.held(Game).size()]
		Game.start_battle({"enemy": (wb["units"] as Array).slice(0, 10), "allies": [], "warband_id": band_id, "seed": 31, "terrain": "grassland", "map": "small"})   # 10 of the band: fast
		await frames(tree, 8)
		var b: Node = main.current
		check(b != null and "sim" in b and not BattleRounds.active(Game), "a small battle is one clash")
		if b != null and "sim" in b:
			b.skip_to_end()
			var waited := 0
			while is_instance_valid(b) and main.current == b and waited < 6000:
				await tree.process_frame; waited += 1
				if b.result_shown and not b.finished: b.finish()
			await frames(tree, 6)
			var res: Dictionary = Game.last_result
			var w := int(res.get("winner", -1))
			var want := 0
			var states: Array = res.get("fighter_states", [])
			var fu: Array = res.get("fighter_units", [])
			for i in fu.size():
				var u = fu[i]
				if w < 0 or not u is Unit or u.dead or DragonCombat.is_dragon_unit(Game, u): continue
				if not str(states[i]) in ["unconscious", "prone"]: continue
				var mine_side: bool = Prisoners.captive_unit(Game, u.uid) != null or Game.company.has(u)
				if (0 if mine_side else 1) != w: want += 1
			var got: int = (Prisoners.captives(Game).size() - before[0]) + (Prisoners.held(Game).size() - before[1])
			print("prisoners_ui033: battle winner ", w, " downed losers ", want, " taken ", got, " captured ", res.get("captured", []))
			check(got == want, "a real small battle takes exactly the loser's downed men (%d of %d)" % [got, want])
			if got > 0: check(has_text(main.current, "Taken prisoner:"), "the aftermath reports who was taken")
			await shot(tree, "battle_aftermath")
	print("prisoners_ui033: %d checks, %d failures" % [checks, fails])
	return fails
