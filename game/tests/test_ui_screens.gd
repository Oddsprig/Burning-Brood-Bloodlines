extends RefCounted
## Every menu screen and tab instances headless without script errors
## (tools/test.sh fails the run on any SCRIPT ERROR line). Uses a real generated town when there is one.

var errors := 0

## A real generated town that hires mercenaries and has recruits and contracts ("" if none).
func _friendly_town() -> String:
	for id in Game.world.get("towns", {}):
		var t: Dictionary = Game.world["towns"][id]
		if not DB.factions.get(t["faction"], {}).get("player_hostile", false) and not t.get("recruits", []).is_empty() \
				and not t.get("contracts", []).is_empty():
			return id
	return ""

func run(tree: SceneTree) -> int:
	Game.new_game(11)
	Game.location = _friendly_town()
	if Game.location == "":
		Game.location = "dev_town"
		DevTown.ensure(Game, "dev_town")
	var town: Dictionary = Game.world["towns"][Game.location]
	print("town: ", town["name"])
	# a wounded officer so the Health tab and the healer have something to show
	var p: Dictionary = Game.company[1].body.wound_part("arm_upper_l")   # sparse bodies (v0.013): the writable part
	for l in p["layers"]:
		if l["tissue"] in ["skin", "muscle", "bone"]:
			l["dmg"] = 0.7; l["kind"] = "fractured" if l["tissue"] == "bone" else "cut"
	var root := tree.root
	await tree.process_frame
	for path in ["res://ui/title.tscn", "res://ui/settings.tscn", "res://ui/company.tscn", "res://ui/town.tscn"]:
		var s: Node = (load(path) as PackedScene).instantiate()
		root.add_child(s)
		await tree.process_frame
		if path.ends_with("company.tscn"):
			for u in [Game.lead_officer(), Roster.leaders(Game)[1], Roster.troops_of(Game, Roster.leaders(Game)[1].uid)[0]]:
				s.select(u.uid)
				for t in ["Overview", "Mind", "Skills", "Gear", "Health", "Squad"]:
					s.show_tab(t)
					await tree.process_frame
			s._pick_squad(Roster.troops_of(Game, Roster.leaders(Game)[1].uid)[0])
			await tree.process_frame
			while s.has_node("Modal"):
				s.get_node("Modal").free()
			# food and drink: ration toggles, the warning banner, the belly/buzz bars (tap = effects)
			s.set_ration("food", "feast")
			s.set_ration("drink", "free")
			if Game.rations != {"food": "feast", "drink": "free"}:
				errors += 1
				printerr("FAIL: ration toggles")
			Game.provisions = Food.new_stock()
			s.refresh()
			await tree.process_frame
			if s.find_child("FoodWarning", true, false) == null:
				errors += 1
				printerr("FAIL: no warning banner with an empty stock")
			Food.add_stock(Game, "meal", 300); Food.add_stock(Game, "beer", 300)
			s.set_ration("food", "normal")
			s.set_ration("drink", "ration")
			var bars := UnitSheet.food_bars(Game.lead_officer())
			s.add_child(bars)
			(bars.get_child(0) as Button).pressed.emit()
			await tree.process_frame
			if not s.has_node("Modal"):
				errors += 1
				printerr("FAIL: tapping the belly bar shows its effects")
		if path.ends_with("town.tscn"):
			for t in ["Market", "Provisions", "Recruits", "Healer", "Contracts"]:
				s.show_tab(t)
				await tree.process_frame
			# food and drink: buy at the market stalls and feast the company
			s.show_tab("Provisions")
			var meals0 := Food.stock(Game, "meal")
			s._buy_food(town, "meal", 10)
			s._feast(town)
			await tree.process_frame
			if Food.stock(Game, "meal") <= meals0 or (Food.has_tavern(town) and Game.lead_officer().belly < 99.0):
				errors += 1
				printerr("FAIL: provisions tab did not buy meals or feast")
			s._recruit_details(town["recruits"][0])
			await tree.process_frame
			s._rest(1)
			await tree.process_frame
			if not town.get("contracts", []).is_empty():
				s._accept(town, town["contracts"][0])
				await tree.process_frame
				print("contract: ", Contracts.status_text(Game))
				if Game.contract.is_empty():
					errors += 1
					printerr("FAIL: contract not accepted from the town screen")
		if path.ends_with("title.tscn"):
			UiKit.open_settings(s, "", true)
			await tree.process_frame
		s.queue_free()
		await tree.process_frame
		print("instanced ", path)
	return errors
