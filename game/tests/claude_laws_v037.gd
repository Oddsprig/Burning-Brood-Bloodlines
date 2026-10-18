extends RefCounted
## Editable succession laws (v0.037). Uses the shared start world, then each of the four laws.
## -- --test=res://tests/claude_laws_v037.gd
var checks := 0
var fails := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL laws037: ", what)

func frames(tree: SceneTree, n: int = 3) -> void:
	for _i in n:
		await tree.process_frame

func finish() -> int:
	print("laws037: %d checks, %d failures" % [checks, fails])
	return fails

func grievance_of(tid: String) -> float:
	var feudal_v: Variant = Game.world.get("feudal", {})
	if not (feudal_v is Dictionary): return 0.0
	var towns_v: Variant = (feudal_v as Dictionary).get("towns", {})
	if not (towns_v is Dictionary): return 0.0
	var row_v: Variant = (towns_v as Dictionary).get(tid, {})
	if not (row_v is Dictionary): return 0.0
	return float((row_v as Dictionary).get("grievance", 0.0))

func other_adults(house_uid: String, ruler_uid: String) -> int:
	var n := 0
	var day: float = float(Game.day)
	var towns_v: Variant = Game.world.get("towns", {})
	if not (towns_v is Dictionary): return 0
	var towns: Dictionary = towns_v
	for tid_v in towns.keys():
		var town_v: Variant = towns[tid_v]
		if not (town_v is Dictionary): continue
		var town: Dictionary = town_v
		var econ_v: Variant = town.get("econ", {})
		if not (econ_v is Dictionary): continue
		var econ: Dictionary = econ_v
		if econ.is_empty(): continue
		var race: String = Persons.race_of(econ)
		var adult_age: int = int(People.ages(race)["adult"])
		var lists: Array = [econ.get("fams", [])]
		for fams_v in lists:
			if not (fams_v is Array): continue
			for f_v in fams_v:
				if not (f_v is Dictionary): continue
				var f: Dictionary = f_v
				if bool(f.get("estate", false)): continue
				var people: Array = []
				var pp_v: Variant = f.get("pp", [])
				var kp_v: Variant = f.get("kp", [])
				if pp_v is Array: people.append_array(pp_v)
				if kp_v is Array: people.append_array(kp_v)
				for p_v in people:
					if not (p_v is Array): continue
					var p: Array = p_v
					if p.size() <= Persons.HOUSE_UID: continue
					var uid: String = str(Persons.g(p, Persons.PERSON_UID, ""))
					if uid == "" or uid == ruler_uid: continue
					if str(Persons.g(p, Persons.HOUSE_UID, "")) != house_uid: continue
					var state: String = str(p[4]) if p.size() > 4 else ""
					if state == "gone" or state == "dead": continue
					if bool(f.get("gone", false)) and state != "company" and state != "captive": continue
					if Persons.age_of(p, day) < adult_age: continue
					var row := {"unit_uid": int(p[5]) if p.size() > 5 else -1, "town_id": str(town.get("id", tid_v)), "family_id": int(f.get("id", -1)), "race": race}
					var unit: Unit = Dynasty.bound_unit(Game, row)
					if unit != null and unit.dead: continue
					n += 1
	return n

func pick_house() -> String:
	var best_pop := -1
	var best: Dictionary = {}
	for choice_v in Dynasty.choices(Game):
		if not (choice_v is Dictionary): continue
		var choice: Dictionary = choice_v
		var id: String = str(choice.get("town_id", ""))
		if id == "" or Dynasty.default_law(Game, id) == "strength": continue
		if str(choice.get("culture", "")) == "orc": continue
		var house_uid: String = str(choice.get("house_uid", ""))
		var ruler_uid: String = str(choice.get("ruler_uid", ""))
		if other_adults(house_uid, ruler_uid) < 1: continue
		var town_v: Variant = Game.world.get("towns", {}).get(id, {})
		var pop := 0
		if town_v is Dictionary:
			var econ_v: Variant = (town_v as Dictionary).get("econ", {})
			if econ_v is Dictionary: pop = int((econ_v as Dictionary).get("pop", 0))
		if pop > best_pop:
			best_pop = pop
			best = choice
	if best.is_empty(): return ""
	var begun: Dictionary = HouseOnboarding.begin(Game, str(best.get("town_id", "")), str(best.get("household_uid", "")))
	if not bool(begun.get("ok", false)): return ""
	return str(best.get("town_id", ""))

func birth_map() -> Dictionary:
	var out: Dictionary = {}
	var towns_v: Variant = Game.world.get("towns", {})
	if not (towns_v is Dictionary): return out
	for town_v in (towns_v as Dictionary).values():
		if not (town_v is Dictionary): continue
		var econ_v: Variant = (town_v as Dictionary).get("econ", {})
		if not (econ_v is Dictionary): continue
		var fams_v: Variant = (econ_v as Dictionary).get("fams", [])
		if not (fams_v is Array): continue
		for f_v in fams_v:
			if not (f_v is Dictionary): continue
			var f: Dictionary = f_v
			for key in ["pp", "kp"]:
				var rows_v: Variant = f.get(str(key), [])
				if not (rows_v is Array): continue
				for p_v in rows_v:
					if not (p_v is Array): continue
					var p: Array = p_v
					if p.size() <= 3: continue
					var uid: String = str(Persons.g(p, Persons.PERSON_UID, ""))
					if uid != "": out[uid] = float(p[3])
	return out

func exclude_uid(tid: String) -> String:
	var state_v: Variant = Game.world.get("player_house", {})
	var state: Dictionary = {}
	if state_v is Dictionary: state = state_v
	var head_uid := ""
	var town_v: Variant = Game.world.get("towns", {}).get(tid, {})
	if town_v is Dictionary:
		var econ_v: Variant = (town_v as Dictionary).get("econ", {})
		if econ_v is Dictionary:
			var head_v: Variant = (econ_v as Dictionary).get("head", {})
			if head_v is Dictionary: head_uid = str((head_v as Dictionary).get("person_uid", ""))
	var household: bool = str(state.get("town_id", "")) == tid and not Dynasty.holds_office(Game)
	if household or head_uid == "": return str(state.get("ruler_uid", ""))
	return head_uid

func best_adult(policy: String, tid: String) -> String:
	var skip: String = exclude_uid(tid)
	var births: Dictionary = birth_map()
	var best := ""
	var best_age := -1
	var best_ability := 0.0
	var best_born := 0.0
	for member_v in Dynasty.living_members(Game):
		if not (member_v is Dictionary): continue
		var member: Dictionary = member_v
		var uid: String = str(member.get("person_uid", ""))
		if uid == "" or uid == skip: continue
		if not bool(member.get("alive", false)): continue
		var race: String = str(member.get("race", "human"))
		var adult_age: int = int(People.ages(race)["adult"])
		var age: int = int(member.get("age", 0))
		if age < adult_age: continue
		var unit: Unit = Dynasty.bound_unit(Game, member)
		if unit != null and unit.dead: continue
		var born: float = float(births.get(uid, 0.0))
		var ability: float = Dynasty.ability_of(Game, uid)
		var better := best == ""
		if not better and policy == "seniority":
			if age != best_age: better = age > best_age
			elif born != best_born: better = born < best_born
			else: better = uid < best
		elif not better:
			if not is_equal_approx(ability, best_ability): better = ability > best_ability
			elif born != best_born: better = born < best_born
			else: better = uid < best
		if better:
			best = uid
			best_age = age
			best_ability = ability
			best_born = born
	return best

func law_order(tid: String) -> Array:
	var current: String = Dynasty.law(Game, tid)
	var order: Array = []
	for law_v in Dynasty.SUCCESSION_LAWS:
		var law_id: String = str(law_v)
		if law_id != current: order.append(law_id)
	if current in Dynasty.SUCCESSION_LAWS: order.append(current)
	return order

func release_lock(tid: String) -> void:
	var status: Dictionary = Dynasty.law_status(Game, tid)
	if not bool(status.get("locked", false)): return
	Game.day = float(int(status.get("unlock_day", 0)))
	var after: Dictionary = Dynasty.law_status(Game, tid)
	check(not bool(after.get("locked", false)), "moving Game.day forward ends the 5-year lock")

func snapshot_grievance() -> Dictionary:
	var out: Dictionary = {}
	var feudal_v: Variant = Game.world.get("feudal", {})
	if not (feudal_v is Dictionary): return out
	var towns_v: Variant = (feudal_v as Dictionary).get("towns", {})
	if not (towns_v is Dictionary): return out
	for id_v in (towns_v as Dictionary).keys():
		var id: String = str(id_v)
		out[id] = grievance_of(id)
	return out

func check_change(law_id: String, tid: String) -> void:
	var before: Dictionary = snapshot_grievance()
	var preview: Dictionary = Dynasty.change_law_preview(Game, law_id, tid)
	check(bool(preview.get("ok", false)), "preview allows " + law_id + " (" + str(preview.get("reason", "")) + ")")
	var result: Dictionary = Dynasty.change_law(Game, law_id, tid)
	check(bool(result.get("ok", false)) and Dynasty.law(Game, tid) == law_id, "law changes to " + law_id + " (" + str(result.get("reason", "")) + ")")
	var affected_v: Variant = result.get("towns", [])
	var affected: Array = affected_v if affected_v is Array else []
	check(not affected.is_empty(), law_id + " adds grievance in the player towns")
	for id_v in affected:
		var id: String = str(id_v)
		var was: float = float(before.get(id, 0.0))
		var now: float = grievance_of(id)
		check(is_equal_approx(now, minf(100.0, was + float(Dynasty.LAW_GRIEVANCE))), "%s grievance +10 in %s (%.1f -> %.1f)" % [law_id, id, was, now])
	var got: Dictionary = Dynasty.heir(Game, tid)
	var via: Dictionary = Dynasty.heir_for_law(Game, tid, law_id)
	check(str(got.get("person_uid", "")) == str(via.get("person_uid", "")), law_id + " heir() follows heir_for_law")
	if law_id == "elective" or law_id == "seniority":
		var want: String = best_adult(law_id, tid)
		check(want != "" and str(via.get("person_uid", "")) == want, law_id + " heir is the expected adult (" + str(via.get("name", "")) + " / " + want + ")")
	var other: String = "absolute" if law_id != "absolute" else "seniority"
	var held: float = grievance_of(tid)
	var refused: Dictionary = Dynasty.change_law(Game, other, tid)
	var locked: Dictionary = Dynasty.law_status(Game, tid)
	check(not bool(refused.get("ok", false)) and Dynasty.law(Game, tid) == law_id, "5-year lock refuses " + other + " (" + str(refused.get("reason", "")) + ")")
	check(bool(locked.get("locked", false)) and str(locked.get("lock_text", "")).begins_with("Next change possible in year "), "lock text names the next year")
	check(is_equal_approx(grievance_of(tid), held), "a refused change adds no grievance")

func labels(node: Node) -> String:
	var text := ""
	if node is Label: text = (node as Label).text + "\n"
	for child in node.get_children(): text += labels(child)
	return text

func press_text(root: Node, text: String) -> bool:
	var buttons: Array = root.find_children("*", "Button", true, false)
	for i in range(buttons.size() - 1, -1, -1):
		var b: Button = buttons[i] as Button
		if b != null and b.text == text:
			b.pressed.emit()
			return true
	return false

func open_laws(tree: SceneTree, tid: String) -> HouseLaws:
	Game.screen_params = {"town_id": tid, "back": "house", "back_params": {"back": "map"}, "return_location": tid}
	var viewport := SubViewport.new()
	viewport.name = "LawsProbe"
	viewport.size = Vector2i(1280, 720)
	# The first call can still be inside the runner's _ready, while the root is
	# blocked from add_child. Defer the viewport so the page actually enters the tree.
	tree.root.add_child.call_deferred(viewport)
	var page: HouseLaws = (load("res://ui/house_laws.tscn") as PackedScene).instantiate()
	viewport.add_child(page)
	await frames(tree, 4)
	return page

func close_laws(tree: SceneTree, page: HouseLaws) -> void:
	var viewport: Node = page.get_parent() if page != null else null
	if page != null: page.queue_free()
	if viewport != null: viewport.queue_free()
	await frames(tree, 2)

func ui_unlocked(tree: SceneTree, tid: String) -> void:
	var page: HouseLaws = await open_laws(tree, tid)
	var button: Button = page.find_child("LawsChangeButton", true, false)
	check(button != null and not button.disabled and button.text == "Change law", "Change law button is enabled for the house")
	var law_now: String = Dynasty.law(Game, tid)
	if button != null: button.pressed.emit()
	await frames(tree, 2)
	var shown: String = labels(page)
	for law_v in Dynasty.SUCCESSION_LAWS:
		var law_id: String = str(law_v)
		check(shown.contains(HouseLaws.law_name(law_id)), "law list shows " + HouseLaws.law_name(law_id))
		check(shown.contains(HouseLaws.choice_line(law_id)) and shown.contains("+10 grievance in your towns, 5-year lock."), law_id + " row has a one-line consequence")
	var pick: String = "absolute" if law_now != "absolute" else "elective"
	var choose: Button = page.find_child("LawsChoose_" + pick, true, false)
	check(choose != null and not choose.disabled, "an unused law can be chosen")
	if choose != null: choose.pressed.emit()
	await frames(tree, 2)
	var confirm: String = labels(page)
	check(confirm.contains("+10 grievance in your towns, 5-year lock"), "confirm step states the grievance and the 5-year lock")
	check(press_text(page, "Cancel"), "confirm can be cancelled")
	await frames(tree, 2)
	check(Dynasty.law(Game, tid) == law_now, "cancelling the confirm leaves the law in place")
	await close_laws(tree, page)

func ui_orc(tree: SceneTree) -> void:
	var orc_tid := ""
	var towns_v: Variant = Game.world.get("towns", {})
	if towns_v is Dictionary:
		for tid_v in (towns_v as Dictionary).keys():
			var id: String = str(tid_v)
			if Dynasty.default_law(Game, id) != "strength": continue
			if HouseLaws.read_data(Game, id).is_empty(): continue
			orc_tid = id
			break
	check(orc_tid != "", "an orc realm exists to view")
	if orc_tid == "": return
	var page: HouseLaws = await open_laws(tree, orc_tid)
	var shown: String = labels(page)
	check(page.find_child("LawsChangeButton", true, false) == null, "orc realms have no Change law button")
	check(shown.contains("The law is strength.") and shown.contains("strength contests decide"), "orc realm says the law is strength")
	var orc_change: Dictionary = Dynasty.change_law(Game, "elective", orc_tid)
	check(not bool(orc_change.get("ok", false)), "orc realm refuses a law change")
	await close_laws(tree, page)

func ui_locked(tree: SceneTree, tid: String) -> void:
	var page: HouseLaws = await open_laws(tree, tid)
	var button: Button = page.find_child("LawsChangeButton", true, false)
	var status: Dictionary = Dynasty.law_status(Game, tid)
	check(button != null and button.disabled, "locked Change law button is disabled")
	check(labels(page).contains(str(status.get("lock_text", "Next change possible in year "))), "page shows the next year a change is possible")
	await close_laws(tree, page)

func check_roundtrip(tid: String) -> void:
	var state_v: Variant = Game.world.get("player_house", {})
	var house_uid := ""
	if state_v is Dictionary: house_uid = str((state_v as Dictionary).get("house_uid", ""))
	var law_before: String = Dynasty.law(Game, tid)
	var changed_before: int = int(Dynasty.law_status(Game, tid).get("changed_day", -1))
	var grievance_before: float = grievance_of(tid)
	Game.save_game()
	Game.wait_save()
	check(Game.load_game(), "save reloads")
	var changed_v: Variant = null
	var succession := ""
	var laws_v: Variant = Game.world.get("laws", {})
	if laws_v is Dictionary:
		var rec_v: Variant = (laws_v as Dictionary).get(house_uid, {})
		if rec_v is Dictionary:
			succession = str((rec_v as Dictionary).get("succession", ""))
			changed_v = (rec_v as Dictionary).get("changed_day", null)
	check(succession == law_before and Dynasty.law(Game, tid) == law_before, "save/load keeps the law " + law_before)
	check(changed_v != null and int(changed_v) == changed_before, "changed_day survives JSON number reload (%s)" % str(changed_v))
	var status: Dictionary = Dynasty.law_status(Game, tid)
	check(bool(status.get("locked", false)), "5-year lock still holds when changed_day comes back as a JSON number")
	check(is_equal_approx(grievance_of(tid), grievance_before), "grievance survives reload")

func run(tree: SceneTree) -> int:
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
	tree.root.position = Vector2i(-20000, -20000)
	tree.root.size = Vector2i(1280, 720)
	if not await DevTools.start_world(tree, "user://claude_laws_v037.json"):
		check(false, "start world did not load")
		return finish()
	var tid: String = pick_house()
	check(tid != "", "ruling house with another adult chosen")
	if tid == "": return finish()
	check(Dynasty.holds_office(Game), "chosen house holds the town office")
	await ui_unlocked(tree, tid)
	await ui_orc(tree)
	var saw_lock_ui := false
	for law_v in law_order(tid):
		var law_id: String = str(law_v)
		release_lock(tid)
		check_change(law_id, tid)
		if not saw_lock_ui:
			saw_lock_ui = true
			await ui_locked(tree, tid)
	check_roundtrip(tid)
	return finish()
