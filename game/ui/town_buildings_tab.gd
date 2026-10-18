class_name TownBuildingsTab
extends RefCounted
## Town Buildings tab. Reads Settlement and, on a town the player rules, starts a project through it.

static func build(scr: Control, t: Dictionary) -> Control:
	var e := Settlement.ensure_town(t)
	var tid := str(t.get("id", ""))
	if tid == "":
		tid = str(Game.location)
	var player := Settlement.is_player_town(Game, tid)
	var sc := UiKit.scroll()
	sc.name = "BuildingsView"
	var box := UiKit.vbox(8)
	UiKit.expand(box)
	sc.add_child(box)
	box.add_child(UiKit.label("Food store", "H2"))
	var food: Dictionary = e.get("food", {})
	var stock := int(food.get("stock", 0))
	var cap := int(food.get("capacity", Settlement.food_capacity(t)))
	var store := UiKit.label("%d / %d" % [stock, cap], "H2")
	store.name = "FoodStore"
	box.add_child(store)
	var days := UiKit.wrap(UiKit.label(_days_text(e, stock), "", true))
	days.name = "FoodDays"
	box.add_child(days)
	if stock <= 0:
		var warn := UiKit.chip("Famine", UiTheme.BAD)
		warn.name = "FamineWarning"
		box.add_child(warn)
	box.add_child(UiKit.label("Buildings", "H2"))
	for key in Settlement.KEYS:
		_building(box, scr, e, tid, player, String(key))
	box.add_child(UiKit.label("Project", "H2"))
	var project := UiKit.wrap(UiKit.label(_project_text(e), "", true))
	project.name = "ProjectLine"
	box.add_child(project)
	if not player:
		box.add_child(UiKit.wrap(UiKit.label("You do not rule this town. Buildings are shown only.", "Muted", true)))
	return sc

static func _building(box: VBoxContainer, scr: Control, e: Dictionary, tid: String, player: bool, key: String) -> void:
	var spec: Dictionary = Settlement.CATALOG.get(key, {})
	var level := Settlement.building_level(e, key)
	var card := UiKit.panel("Card")
	card.name = "Building_" + key
	UiKit.expand(card)
	box.add_child(card)
	var body := UiKit.vbox(4)
	card.add_child(body)
	var head := UiKit.hbox(8)
	body.add_child(head)
	head.add_child(UiKit.label(str(spec.get("name", key)), "H2"))
	head.add_child(UiKit.spacer())
	var lv := UiKit.label("Level %d / %d" % [level, Settlement.MAX_LEVEL])
	lv.name = "Level_" + key
	head.add_child(lv)
	var effect := UiKit.wrap(UiKit.label(_effect_line(key, level), "", true))
	effect.name = "Effect_" + key
	body.add_child(effect)
	if not player:
		return
	var preview := Settlement.start_preview(Game, tid, key)
	var shown := _preview_text(preview)
	var row := UiKit.hbox(8)
	body.add_child(row)
	var info := UiKit.wrap(UiKit.label(shown, "Muted", true))
	info.name = "Preview_" + key
	row.add_child(info)
	var button := UiKit.button("Build", _ask_build.bind(scr, tid, key), "", 140)
	button.name = "BuildButton_" + key
	button.tooltip_text = shown
	row.add_child(button)

static func _ask_build(scr: Control, town_id: String, key: String) -> void:
	var preview := Settlement.start_preview(Game, town_id, key)
	var spec: Dictionary = Settlement.CATALOG.get(key, {})
	var name := str(spec.get("name", key))
	var cost := int(preview.get("cost", 0))
	var days := int(preview.get("days", 0))
	var reason := str(preview.get("reason", ""))
	var level := int(preview.get("level", 0))
	if not bool(preview.get("ok", false)):
		UiKit.message(scr, "Build %s" % name, [
			"Cost: %d coins." % cost,
			"Days: %d." % days,
			"Reason: %s." % reason,
		])
		return
	var text := "Build %s to level %d? Cost %d coins, %d days." % [name, level, cost, days]
	if reason != "":
		text += " Reason: %s." % reason
	UiKit.confirm(scr, text, "Confirm", func() -> void:
		var result := Settlement.start(Game, town_id, key, preview)
		if bool(result.get("ok", false)):
			UiKit.toast(scr, "Started %s (%d coins, %d days)" % [name, cost, days])
		else:
			UiKit.toast(scr, "Reason: %s" % str(result.get("reason", "")), false)
		if scr.has_method("refresh"):
			scr.refresh()
	)

static func _preview_text(preview: Dictionary) -> String:
	var reason := str(preview.get("reason", ""))
	var text := "%d coins · %d days" % [int(preview.get("cost", 0)), int(preview.get("days", 0))]
	if reason != "":
		text += " · %s" % reason
	return text

static func _days_text(e: Dictionary, stock: int) -> String:
	var use := Settlement.daily_consumption(e)
	if use <= 0:
		return "0 days of food left" if stock <= 0 else "days of food left: no one is eating"
	return "%d days of food left" % int(floor(float(stock) / float(use)))

static func _project_text(e: Dictionary) -> String:
	var projects: Array = e.get("projects", [])
	if projects.is_empty():
		return "No project under way."
	var proj: Dictionary = projects[0]
	var key := str(proj.get("key", ""))
	var spec: Dictionary = Settlement.CATALOG.get(key, {})
	return "%s to level %d · %d days left" % [str(spec.get("name", key)), int(proj.get("target_level", 0)), int(proj.get("days_left", 0))]

static func _effect_line(key: String, level: int) -> String:
	var spec: Dictionary = Settlement.CATALOG.get(key, {})
	var desc := String(spec.get("desc", ""))
	var lv := clampi(level, 0, Settlement.MAX_LEVEL)
	match key:
		"granary":
			return "%s Capacity %d." % [desc, Settlement.BASE_FOOD_CAP + lv * Settlement.GRANARY_CAP_BONUS]
		"housing":
			return "%s Room +%d." % [desc, int(round(float(lv) * Settlement.HOUSING_BONUS_PER_LEVEL))]
		"market":
			return "%s Trade +%d%%." % [desc, int(round(float(lv) * Settlement.MARKET_BONUS_PER_LEVEL * 100.0))]
		"walls":
			return "%s Siege defence +%d%%." % [desc, int(round(float(lv) * Settlement.WALLS_BONUS_PER_LEVEL * 100.0))]
		"temple":
			return "%s Grievance drop %.2f." % [desc, float(lv) * Settlement.TEMPLE_GRIEVANCE_DROP]
		_:
			return desc
