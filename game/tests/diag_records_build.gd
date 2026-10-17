extends RefCounted
## Records opening and navigation costs with production counters untouched. Run alone, headlessly.
## Fresh generated world (no presimulation): separate cold first use, immediate rebuild and Back.
## Existing test_ui_records supplies the unchanged <16ms gate on its evolved 40-day scenario.

var tree: SceneTree

func run(st: SceneTree) -> int:
	tree = st
	await tree.process_frame
	Game.new_game(11)
	var town: Dictionary = {}
	for candidate: Dictionary in Game.world["towns"].values():
		if TownEcon.has_econ(candidate) and (town.is_empty() or candidate["econ"]["fams"].size() > town["econ"]["fams"].size()):
			town = candidate
	if town.is_empty(): return 1
	var e: Dictionary = town["econ"]
	Game.location = String(town["id"])
	Game.screen_params = {"view": "town", "id": Game.location, "tab": "Overview", "back": "town"}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 1280)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var start := Time.get_ticks_usec()
	var screen: Node = (load("res://ui/records.tscn") as PackedScene).instantiate()
	viewport.add_child(screen)
	print("RECORDS COST scenario=fresh seed=11 towns=", Game.world["towns"].size(), " selected_families=", RecData.fams(e).size(), " selected_businesses=", RecData.biz(e).size())
	_print_time("initial screen including scripts/frame controls", start)
	await _settle()
	for tab in ["Businesses", "Register"]:
		_measure("town " + tab + " first", func(): screen.show_tab(tab))
		await _settle()
		_measure("town " + tab + " rebuild", func(): screen.show_tab(tab))
		await _settle()
		var table := _table(screen.list_box)
		if table == null or table.rows.is_empty(): continue
		_measure("town " + tab + " detail first", func(): (table._rows_box.get_child(0) as Button).pressed.emit())
		await _settle()
		_measure("town " + tab + " Back", func(): screen.go_back())
		await _settle()
		table = _table(screen.list_box)
		_measure("town " + tab + " detail return", func(): (table._rows_box.get_child(0) as Button).pressed.emit())
		await _settle()
		screen.go_back()
		await _settle()
	for tab in ["Towns", "Census"]:
		_measure("world " + tab + " first", func(): screen.set_view("world", "", tab))
		await _settle()
		_measure("world " + tab + " rebuild", func(): screen.show_tab(tab))
		await _settle()
	_profile_world(screen)
	await _profile_rows(screen, town, e)
	viewport.queue_free()
	await tree.process_frame
	Game.location = ""
	return 0

func _profile_world(screen: Node) -> void:
	var tids: Array = screen.tids()
	var start := Time.get_ticks_usec()
	for tid in tids: RecData.live_people(RecData.econ(RecData.town(tid)))
	_print_time("world typed current people", start)
	start = Time.get_ticks_usec()
	Census.balance_of(Game.world, tids)
	_print_time("world census balance", start)
	start = Time.get_ticks_usec()
	RecTown._season_rows(Game.world, tids)
	_print_time("world season rows", start)
	start = Time.get_ticks_usec()
	RecTown._daily(Game.world, tids)
	_print_time("world daily samples", start)
	start = Time.get_ticks_usec()
	for tid in tids: RecWorld._hard_pct(RecData.econ(RecData.town(tid)))
	_print_time("world hardship values", start)

func _profile_rows(screen: Node, town: Dictionary, e: Dictionary) -> void:
	var rows := []
	var start := Time.get_ticks_usec()
	for business: Dictionary in RecData.biz(e):
		if business.get("closed", false): continue
		if int(business.get("cap", 0)) <= 0 and int(business.get("workers", 0)) <= 0 and int(business.get("kw", 0)) <= 0: continue
		rows.append(RecTown.biz_row(screen, town, e, business))
	_print_time("business row data standalone lookups", start)
	start = Time.get_ticks_usec()
	var table := RecTable.make([{"k": "trade", "t": "Trade"}, {"k": "cash", "t": "Cash", "num": true}], rows, "trade")
	_print_time("business native controls and first 15 rows", start)
	start = Time.get_ticks_usec()
	table.shown()
	_print_time("business filtering/sorting only", start)
	if rows.size() > table.limit:
		var more: Button = table._rows_box.get_child(table._rows_box.get_child_count() - 1)
		_measure("business Show more first", func(): more.pressed.emit())
		await _settle()
		if rows.size() > table.limit:
			more = table._rows_box.get_child(table._rows_box.get_child_count() - 1)
			_measure("business Show more second", func(): more.pressed.emit())
	table.free()
	await _settle()
	var shaped := []
	start = Time.get_ticks_usec()
	for row: Dictionary in rows.slice(0, 15):
		shaped.append(RecKit.row(String(row["_l"]), String(row["_r"]), String(row["_d"]), row["_tap"], row["_col"]))
	_print_time("business 15 shaped native row buttons only", start)
	for button in shaped: button.free()

func _measure(title: String, fn: Callable) -> void:
	var start := Time.get_ticks_usec()
	fn.call()
	_print_time(title, start)

func _print_time(title: String, start: int) -> void:
	print("RECORDS COST ", title, " ms=", (Time.get_ticks_usec() - start) / 1000.0)

func _settle() -> void:
	for i in 2: await tree.process_frame

func _table(node: Node) -> RecTable:
	if node is RecTable: return node
	for child in node.get_children():
		var found := _table(child)
		if found != null: return found
	return null
