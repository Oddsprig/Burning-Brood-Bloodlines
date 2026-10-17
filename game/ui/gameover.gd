extends Control
## Dynasty extinction ends a selected campaign. A living family never loses its save here.

func _ready() -> void:
	var selected := not Dynasty.selected(Game).is_empty()
	var ended := Game.is_game_over()
	var heading := "The House Has Ended" if selected and ended else (
		"Your House Endures" if selected else ("The Company Is No More" if ended else "Continue Your Campaign"))
	var f := UiKit.screen_frame(self, heading)
	var root: VBoxContainer = f["root"]
	var r: Dictionary = Game.last_result
	var lines := []
	if selected:
		lines.append("Day %d. No living members of your founding dynasty remain." % int(Game.day) if ended else
			"Your ruling family lives on. The loss of troops does not end your house.")
	else:
		lines.append("Day %d. The last of your company has fallen." % int(Game.day) if ended else
			"Choose your ruling family to begin the campaign." if Game.world.has("towns") else "Your company can continue.")
	var names: Array = r.get("dead_names", [])
	if not names.is_empty():
		lines.append("Fallen in the last battle: " + ", ".join(names) + ".")
	lines.append("Coins left in the chest: %d." % Game.gold)
	for l in lines:
		root.add_child(UiKit.label(l, "", true))
	root.add_child(UiKit.spacer())
	var row := UiKit.hbox(12)
	root.add_child(row)
	if not ended:
		row.add_child(UiKit.button("Continue", func():
			Game.goto("house_select" if not selected and Game.world.has("towns") else "map"), "", 200))
	row.add_child(UiKit.button("New Campaign", func():
		Game.goto("newgame", {"back": "title"}), "", 260))   # options, then the years before; presim saves when the map opens
	row.add_child(UiKit.button("Title", func(): Game.goto("title"), "", 200))
	# Only a confirmed ending clears the save; a stale route must not erase a living dynasty.
	if ended:
		Game.wait_save()   # an autosave still writing would bring the ended save back
		if Game.is_game_over() and FileAccess.file_exists(Game.SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
