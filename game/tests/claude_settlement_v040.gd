extends RefCounted

var checks: int = 0
var fails: int = 0
var previous_save_path: String = ""

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL settlement040: ", what)

func _finish() -> int:
	Game.wait_save()
	if previous_save_path != "":
		Game.SAVE_PATH = previous_save_path
	print("settlement040: %d checks, %d failures" % [checks, fails])
	return fails

func _cohort(e: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var fams: Array = e.get("fams", [])
	for item in fams:
		if not (item is Dictionary):
			continue
		var f: Dictionary = item
		if Population.is_cohort(f) and not bool(f.get("gone", false)):
			if best.is_empty() or Families.people(f) > Families.people(best):
				best = f
	return best

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.wait_save()
	previous_save_path = Game.SAVE_PATH
	if not await DevTools.start_world(tree, "user://settlement040-test.json"):
		check(false, "the shared test world loads")
		return _finish()

	var choices: Array = Dynasty.choices(Game)
	var seat: String = ""
	for item in choices:
		var choice: Dictionary = item
		var c_tid: String = str(choice.get("town_id", ""))
		var c_huid: String = str(choice.get("household_uid", ""))
		var res: Dictionary = HouseOnboarding.begin(Game, c_tid, c_huid)
		if bool(res.get("ok", false)):
			seat = c_tid
			break
	check(seat != "", "selected a player ruling house")
	if seat == "":
		return _finish()

	var w: Dictionary = Game.world
	var towns: Dictionary = w["towns"]
	var town: Dictionary = towns[seat]
	var e: Dictionary = Settlement.ensure_town(town)

	# 1. Building catalog and initial levels = 0
	check(Settlement.CATALOG.size() == 5, "catalog has 5 building types")
	for k in ["granary", "housing", "market", "walls", "temple"]:
		check(Settlement.CATALOG.has(k), "catalog has " + k)
		check(Settlement.building_level(town, k) == 0, "initial level of %s is 0" % k)
	var projects0: Array = e.get("projects", [])
	check(projects0.is_empty(), "player town starts with no active project")

	# Find a non-player AI town
	var ai_tid: String = ""
	for tid_key in towns.keys():
		var cand_id: String = str(tid_key)
		if cand_id != seat and not Settlement.is_player_town(Game, cand_id):
			ai_tid = cand_id
			break
	check(ai_tid != "", "found a non-player AI town")

	# 2. Rejecting when not player's town
	var bad_town_prev: Dictionary = Settlement.start_preview(Game, ai_tid, "granary")
	check(not bool(bad_town_prev.get("ok", true)) and str(bad_town_prev.get("reason", "")) == "not_player_town", "rejects starting project in non-player town")

	# 3. Rejecting when purse < cost
	var payer: Dictionary = Feudal._payer(Game)
	var saved_purse: float = float(payer.get("purse", 0.0))
	payer["purse"] = 5.0
	var poor_prev: Dictionary = Settlement.start_preview(Game, seat, "granary")
	check(not bool(poor_prev.get("ok", true)) and str(poor_prev.get("reason", "")) == "no_funds", "rejects when payer purse < cost")

	# 4. start_preview and start for player-ruled town (granary Lv.1)
	payer["purse"] = 5000.0
	var cap_before: int = Settlement.food_capacity(town)
	var prev: Dictionary = Settlement.start_preview(Game, seat, "granary")
	var expected_cost: int = int(prev.get("cost", 0))
	var expected_days: int = int(prev.get("days", 0))
	check(bool(prev.get("ok", false)) and expected_cost > 0 and expected_days > 0 and int(prev.get("level", 0)) == 1, "start_preview succeeds for granary Lv.1")

	var started: Dictionary = Settlement.start(Game, seat, "granary", prev)
	check(bool(started.get("ok", false)), "start succeeds for granary Lv.1")
	check(is_equal_approx(float(payer.get("purse", 0.0)), 5000.0 - float(expected_cost)), "start deducts cost from player payer purse")
	var active_projects: Array = e.get("projects", [])
	check(active_projects.size() == 1, "project added to town econ.projects")

	# 5. Rejecting a second project while one is active
	var busy_prev: Dictionary = Settlement.start_preview(Game, seat, "housing")
	check(not bool(busy_prev.get("ok", true)) and str(busy_prev.get("reason", "")) == "busy", "rejects a second project while one is active")
	var busy_start: Dictionary = Settlement.start(Game, seat, "housing")
	check(not bool(busy_start.get("ok", true)) and str(busy_start.get("reason", "")) == "busy", "start rejects a second project while busy")

	# 6. Advancing days_left days via Settlement.daily completes the project and increments buildings[key]
	var cur_day: int = int(floor(float(Game.day)))
	for step in range(expected_days):
		cur_day += 1
		Settlement.daily(Game, cur_day)
	check(Settlement.building_level(town, "granary") == 1, "granary reaches level 1 after days_left daily ticks")
	var after_projects: Array = e.get("projects", [])
	check(after_projects.is_empty(), "projects queue is empty after completion")

	# 7. Granary upgrade increases food.capacity
	var cap_after: int = Settlement.food_capacity(town)
	check(cap_after > cap_before, "granary upgrade increases food.capacity (%d -> %d)" % [cap_before, cap_after])

	# 8. Housing upgrade increases the housing capacity Migration uses
	var cohort: Dictionary = _cohort(e)
	var mig_cap_before: float = Migration.housing_capacity(e, cohort)
	var h_prev: Dictionary = Settlement.start_preview(Game, seat, "housing")
	var h_days: int = int(h_prev.get("days", 1))
	var h_start: Dictionary = Settlement.start(Game, seat, "housing", h_prev)
	check(bool(h_start.get("ok", false)), "started housing Lv.1 upgrade")
	for step in range(h_days):
		cur_day += 1
		Settlement.daily(Game, cur_day)
	check(Settlement.building_level(town, "housing") == 1, "housing reaches level 1")
	var mig_cap_after: float = Migration.housing_capacity(e, cohort)
	check(mig_cap_after > mig_cap_before, "housing upgrade increases Migration.housing_capacity (%.1f -> %.1f)" % [mig_cap_before, mig_cap_after])

	# 9. Rejecting above level 3
	var b_dict: Dictionary = e["buildings"]
	b_dict["walls"] = 3
	check(Settlement.walls_level(town) == 3, "walls_level helper reads level 3")
	var max_prev: Dictionary = Settlement.start_preview(Game, seat, "walls")
	check(not bool(max_prev.get("ok", true)) and str(max_prev.get("reason", "")) == "max_level", "rejects upgrading building above level 3")

	# 10. Food store hitting 0 sets the famine flag Migration reads, and refilling clears it
	var food: Dictionary = e["food"]
	e["fstage"] = 0
	e["food_short"] = 0.0
	food["stock"] = 0
	cur_day += 1
	Settlement.daily(Game, cur_day)
	check(int(food.get("stock", -1)) == 0, "food stock is 0")
	check(bool(e.get("famine", false)) and Migration.push(Game, town, float(cur_day)) == "hunger", "empty food store sets famine flag read by Migration.push")

	food["stock"] = 400
	cur_day += 1
	Settlement.daily(Game, cur_day)
	check(int(food.get("stock", 0)) > 0, "food stock refilled > 0")
	check(not bool(e.get("famine", false)) and Migration.push(Game, town, float(cur_day)) != "hunger", "refilling food store clears famine flag")

	# 11. AI town starts a project when rich
	var ai_town: Dictionary = towns[ai_tid]
	var ai_e: Dictionary = Settlement.ensure_town(ai_town)
	var ai_projects: Array = ai_e["projects"]
	ai_projects.clear()
	ai_e["ai_project_day"] = -999
	ai_e["treasury"] = 2000.0
	cur_day += 35
	Settlement.daily(Game, cur_day)
	var ai_projects_after: Array = ai_e["projects"]
	check(ai_projects_after.size() == 1, "rich AI town starts an affordable upgrade project")

	# 12. after_load round-trip preserves state and integer types
	b_dict["granary"] = 2.0
	food["stock"] = 321.0
	food["capacity"] = 2000.0
	if not ai_projects_after.is_empty():
		var ap: Dictionary = ai_projects_after[0]
		ap["days_left"] = 4.0
		ap["target_level"] = 1.0
		ap["cost"] = 120.0
	Settlement.after_load(Game)
	check(typeof(b_dict["granary"]) == TYPE_INT and int(b_dict["granary"]) == 2, "after_load casts building level to int and preserves state")
	check(typeof(food["stock"]) == TYPE_INT and int(food["stock"]) == 321, "after_load casts food.stock to int and preserves state")
	check(typeof(food["capacity"]) == TYPE_INT and int(food["capacity"]) == Settlement.food_capacity(town), "after_load casts food.capacity to int")
	if not ai_projects_after.is_empty():
		var ap2: Dictionary = ai_projects_after[0]
		check(typeof(ap2["days_left"]) == TYPE_INT and typeof(ap2["target_level"]) == TYPE_INT, "after_load casts project fields to int")

	payer["purse"] = saved_purse
	return _finish()
