extends RefCounted
## Baseline-compatible records transcript: run unchanged and candidate source separately and compare hashes.
## Hashes include every table row and resolved lazy value, visible label/button text and accessibility text.
## Keep output compact: no large generated fixture dumps. test_ui_records retains fit and timing gates.

var checks := 0
var fails := 0
var transcript := []

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", text)

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.new_game(11)
	var t: Dictionary = {}
	for candidate: Dictionary in Game.world["towns"].values():
		if TownEcon.has_econ(candidate):
			t = candidate
			break
	check(not t.is_empty(), "generated world has records")
	if t.is_empty(): return fails
	var tid := String(t["id"])
	Game.location = tid
	Game.screen_params = {"view": "town", "id": tid, "back": "town"}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 1280)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var screen: Node = (load("res://ui/records.tscn") as PackedScene).instantiate()
	viewport.add_child(screen)
	for view in ["town", "world", "faction"]:
		screen.set_view(view, tid if view == "town" else (String(t["faction"]) if view == "faction" else ""))
		for tab in screen.tabs():
			screen.show_tab(tab)
			await _capture(view + " " + tab, screen)
			var table := _table(screen.list_box)
			if table != null:
				for column in table.cols:
					var key := String(column["k"])
					table.sort_by(key)
					await _capture(view + " " + tab + " sort " + key, table)
					table.sort_by(key)
					await _capture(view + " " + tab + " reverse " + key, table)
				for filter in table.filters:
					var title := String(filter["t"])
					for option in filter["opts"]:
						table.set_filter(title, String(option))
						await _capture(view + " " + tab + " filter " + title + " " + String(option), table)
					table.set_filter(title, String(filter["opts"][0]))
				if not table.rows.is_empty():
					table.search = String(table.rows[0].get("_s", table.rows[0].get("_l", ""))).substr(0, 3).to_lower()
					table._refresh()
					await _capture(view + " " + tab + " search", table)
					table.search = ""
					table._refresh()
				if table.shown().size() > table.limit:
					var more: Button = table._rows_box.get_child(table._rows_box.get_child_count() - 1)
					more.pressed.emit()
					await _capture(view + " " + tab + " show more", table)
	# Use actual list-row signals for family and business navigation, then compare full detail content.
	screen.set_view("town", tid, "Register")
	var families := _table(screen.list_box)
	check(families != null and not families.rows.is_empty(), "Register keeps family rows")
	if families != null and not families.rows.is_empty():
		(families._rows_box.get_child(0) as Button).pressed.emit()
		check(screen.stack.size() == 1, "family row opens detail")
		await _capture("family detail", screen.page_box)
		screen.go_back()
		check(screen.stack.is_empty() and screen.tab == "Register", "family Back returns to Register")
		await _capture("family Back", screen.list_box)
	screen.show_tab("Businesses")
	var businesses := _table(screen.list_box)
	check(businesses != null and not businesses.rows.is_empty(), "Businesses keeps business rows")
	if businesses != null and not businesses.rows.is_empty():
		(businesses._rows_box.get_child(0) as Button).pressed.emit()
		check(screen.stack.size() == 1, "business row opens detail")
		await _capture("business detail", screen.page_box)
		screen.go_back()
		check(screen.stack.is_empty() and screen.tab == "Businesses", "business Back returns to Businesses")
		await _capture("business Back", screen.list_box)
	print("RECORDS SNAPSHOT sections=", transcript.size(), " sha256=", JSON.stringify(transcript).sha256_text())
	print("RECORDS SNAPSHOT checks=", checks, " failures=", fails)
	viewport.queue_free()
	await tree.process_frame
	Game.location = ""
	return fails

func _capture(title: String, node: Node) -> void:
	var content := []
	_walk(node, content)
	var digest := JSON.stringify(content).sha256_text()
	transcript.append([title, content.size(), digest])
	# Per-section hashes locate a difference without saving full-world text fixtures.
	print("RECORDS SECTION ", title, " entries=", content.size(), " sha256=", digest)
	# Let queued old controls release before the next refresh; retain only compact section hashes.
	await node.get_tree().process_frame

func _walk(node: Node, content: Array) -> void:
	if node is Label:
		content.append(["label", node.text])
	elif node is Button:
		if node.has_meta("rec_row"):
			content.append(["row", node.get_meta("rec_row"), node.tooltip_text, node.accessibility_name, node.accessibility_description])
		else:
			content.append(["button", node.text])
	if node is RecTable:
		var values := []
		for row in node.rows:
			var record := {}
			for key in row:
				if String(key) == "_tap": continue
				var value: Variant = row[key]
				if value is Callable: value = value.call()
				record[key] = _value(value)
			values.append(record)
		content.append(["all rows", values, node.limit, node.shown().map(func(r): return r.get("_l", ""))])
	for child in node.get_children():
		_walk(child, content)

func _value(value: Variant) -> Variant:
	if value is Color: return value.to_html(true)
	if value is Dictionary:
		var out := {}
		for key in value: out[str(key)] = _value(value[key])
		return out
	if value is Array: return value.map(_value)
	return value

func _table(node: Node) -> RecTable:
	if node is RecTable: return node
	for child in node.get_children():
		var found := _table(child)
		if found != null: return found
	return null
