extends RefCounted
## v0.031: native campaign setup, visible army cards/badges, orders and size-scaled marching.
## Run through the existing test harness: -- --test=res://tests/claude_markers_v031.gd
var checks := 0
var fails := 0
var main: Node = null

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL markers031: ", what)

func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n:
		await tree.process_frame

func finish() -> int:
	var width := float(WorldGen.W * WorldGen.CELL)
	var before := CampaignWorld.WARBAND_SPEED / CampaignWorld.MAP_PACE
	var after := CampaignWorld.travel_speed(CampaignWorld.WARBAND_SPEED, 1000)
	print("markers031: 1000-man army, flat map width %.0f px: before %.2f days, after %.2f days (%.4f px/day)" % [
		width, width / before, width / after, after])
	print("markers031: %d checks, %d failures" % [checks, fails])
	return fails

func run(tree: SceneTree) -> int:
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
	tree.root.position = Vector2i(-20000, -20000)
	tree.root.size = Vector2i(1280, 720)
	Game.settings["guide_seen"] = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 8)
	WorldGen.gen_size = "normal"
	WorldGen.gen_stretch = WorldGen.STRETCH
	CampaignWorld.presim_span_days = 1
	var generation := Game.new_game_begin(4242)
	while not Game.new_game_slice(generation, 8000):
		await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 8000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	Game.new_game_finalize()
	var sample := ""
	var field_count := 0
	for wid in Game.world["warbands"]:
		var wb: Dictionary = Game.world["warbands"][wid]
		if not Army.is_field(wb): continue
		field_count += 1
		check(WarAI.OBJECTIVES.has(String(wb.get("objective", ""))), "field band %s has a valid objective" % wid)
		if sample == "" and not (wb["units"] as Array).is_empty(): sample = String(wid)
	check(field_count > 0 and sample != "", "generated field armies exist")
	if sample == "": return finish()
	for pair in [["home", "hold_capital"], ["avoid", "defend"], ["shadow", "defend"],
		["intercept", "march"], ["join", "march"], ["track", "march"], ["hunt", "march"]]:
		var probe := {"kind": "patrol", "mode": "wander", "path": [], "war": {"m": pair[0]}}
		WarAI.sync_objective(probe, float(Game.day))
		check(probe["objective"] == pair[1] and WarAI.mode_text(probe).begins_with(String(WarAI.OBJECTIVES[pair[1]])),
			"war order %s supplies the displayed objective" % pair[0])
	for pair in [["chase", "march"], ["flee", "defend"]]:
		var probe := {"kind": "raider", "mode": pair[0], "war": {"m": "shadow"}}
		WarAI.sync_objective(probe, float(Game.day))
		check(probe["objective"] == pair[1], "party response %s overrides older war orders" % pair[0])
	var chosen := false
	for c: Dictionary in Dynasty.choices(Game):
		var town: Dictionary = Game.world["towns"][c["town_id"]]
		if town["faction"] != "middle_kingdom": continue
		if str(town.get("econ", {}).get("head", {}).get("household_uid", "")) != str(c["household_uid"]): continue
		chosen = bool(HouseOnboarding.begin(Game, str(c["town_id"]), str(c["household_uid"])).get("ok", false))
		if chosen: break
	check(chosen, "selected an existing ruling house")
	if not chosen: return finish()
	Game.goto("map")
	await frames(tree, 5)
	var map: Node = main.current
	Game.world["warbands"][sample]["pos"] = Game.world["party"]["pos"] + Vector2(70, 0)
	map._sync_icons()
	map._select({"kind": "warband", "id": sample})
	var card := String(map.info_body.text)
	check(card.begins_with("Commander: ") and card.contains("\nTroops: ") and card.contains("\nObjective: "),
		"selected army card starts with Commander, Troops, Objective")
	var token: MapToken = map.icons[sample]
	check(token.count == MapTokens.alive_count(Game.world["warbands"][sample]), "badge has the living headcount")
	check(token.badge_color == MapTokens.fcol(String(Game.world["warbands"][sample]["faction"])), "badge uses realm colour")
	var texture: Texture2D = token.tex
	var paints := MapTokens.paint_count
	token.set_badge(1200, token.badge_color)
	check(token.badge_text == "1.2k", "badge abbreviates 1200 men")
	token.set_badge(1300, token.badge_color)
	check(token.badge_text == "1.3k" and is_same(texture, token.tex) and paints == MapTokens.paint_count,
		"headcount changes retain the cached token texture")
	token.refresh(Game, Game.world["warbands"][sample])
	map._select({"kind": "party"})
	card = String(map.info_body.text)
	check(card.begins_with("Commander: ") and card.contains("\nTroops: ") and card.contains("\nObjective: "),
		"player army card starts with Commander, Troops, Objective")
	var party: Dictionary = Game.world["party"]
	for objective in WarAI.OBJECTIVES:
		var button: Button = null
		for child in map.info_buttons.get_children():
			if child is Button and child.text == WarAI.OBJECTIVES[objective]:
				button = child
				break
		check(button != null, "player card offers " + String(WarAI.OBJECTIVES[objective]))
		if button == null: continue
		party["path"] = [party["pos"] + Vector2(120, 0)]
		party["dest_town"] = String(Game.world["start_town"])
		party["arrived"] = party["dest_town"]
		party["waiting"] = true
		map.pursue_wid = sample
		button.pressed.emit()
		check(party.get("objective", "") == objective, "player objective " + String(objective) + " stored")
		check(String(map.info_body.text).contains("Objective: " + String(WarAI.OBJECTIVES[objective])), "player card shows selected objective")
		if objective == "hold_capital":
			check(not CampaignWorld.is_travelling(Game) and party["dest_town"] == "" and party["arrived"] == ""
				and not party["waiting"] and map.pursue_wid == "", "hold cancels travel, pending arrival and pursuit")
		else:
			check(CampaignWorld.is_travelling(Game), "display objective preserves the chosen route")
	map._set_party_objective("hold_capital")
	# Older saves gain objectives without resetting a saved player order.
	party["objective"] = "raid"
	Game.world["warbands"][sample].erase("objective")
	WarAI.after_load(Game)
	check(WarAI.OBJECTIVES.has(Game.world["warbands"][sample].get("objective", "")) and party["objective"] == "raid",
		"load backfills band objectives and preserves the player's order")
	party.erase("objective")
	WarAI.after_load(Game)
	check(party["objective"] == "hold_capital", "old stationary party defaults to holding")
	_movement()
	return finish()

func _movement() -> void:
	# Exercise the shared walker, with roster lengths only; no costly soldier/body construction.
	var small_roster: Array = []
	var large_roster: Array = []
	small_roster.resize(100)
	large_roster.resize(1000)
	var width := float(WorldGen.W * WorldGen.CELL)
	var small := {"pos": Vector2.ZERO, "path": [Vector2(width, 0)], "units": small_roster, "kind": "assault"}
	var large := {"pos": Vector2.ZERO, "path": [Vector2(width, 0)], "units": large_roster, "kind": "assault"}
	CampaignWorld._step_along(Game.world, small, CampaignWorld.WARBAND_SPEED)
	CampaignWorld._step_along(Game.world, large, CampaignWorld.WARBAND_SPEED)
	var small_distance: float = small["pos"].x
	var large_distance: float = large["pos"].x
	check(large_distance < small_distance, "1000-man band moves slower than 100-man band in one day")
	check(is_equal_approx(small_distance, 113.75) and is_equal_approx(large_distance, 73.9375),
		"walker applies the 35% base reduction and logarithmic size penalty exactly once")
	check(is_equal_approx(WarAI.speed_of(large, float(Game.day)), large_distance),
		"interception estimates agree with the size-adjusted walker")
	check(is_equal_approx(CampaignWorld.travel_speed(CampaignWorld.PARTY_SPEED, 1000), 84.5),
		"player army uses its reduced base and the same size penalty")
	check(is_equal_approx(CampaignWorld.travel_speed(1.0, 100000), 0.45)
		and is_equal_approx(CampaignWorld.travel_speed(1.0, 0), 1.0), "size penalty clamps safely at both ends")
