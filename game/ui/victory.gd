extends Control
## Campaign victory: the dynasty achieved its ambitions. The player can keep playing the same world.

func _ready() -> void:
	var f := UiKit.screen_frame(self, "Dynasty Triumphant")
	var root: VBoxContainer = f["root"]
	var st: Dictionary = Warfare._state(Game)
	var house := str(Game.world.get("player_house", {}).get("house_name", "Your house"))
	var ruler: Dictionary = Dynasty.ruler(Game)
	var heading := UiKit.label("%s stands above every rival." % house, "H2", true)
	heading.add_theme_font_size_override("font_size", 30)
	root.add_child(heading)
	root.add_child(UiKit.label("On day %d of year %d, under %s, your house achieved %d of its ambitions." % [
		Calendar.day_of_season(Game.day) + 1, Calendar.year(Game.day), str(ruler.get("name", "its ruler")), Ambitions.completed(Game)], "", true))
	var dragons := 0
	for row: Dictionary in Game.world.get("dragons", {}).get("records", {}).values():
		if bool(row.get("alive", false)) and str(row.get("owner_household_uid", "")) == str(Game.world.get("player_house", {}).get("household_uid", "")): dragons += 1
	for line in [
		"Battles won: %d · lost: %d" % [int(st.get("battles_won", 0)), int(st.get("battles_lost", 0))],
		"Settlements conquered: %d" % (st.get("conquests", []) as Array).size(),
		"Coin carried off in raids: %d" % int(float(st.get("raided_coin", 0.0)) / Item.COIN),
		"Living dragons and eggs of your household: %d" % dragons,
	]:
		root.add_child(UiKit.label(line, "", true))
	for a: Dictionary in Ambitions.status(Game):
		root.add_child(UiKit.label(("✔ " if a["done"] else "○ ") + str(a["name"]) + " · " + str(a["progress"]), "Muted" if not a["done"] else "", true))
	root.add_child(UiKit.spacer())
	var row := UiKit.hbox(12)
	root.add_child(row)
	row.add_child(UiKit.button("Keep playing", func(): Game.goto("map"), "", 220))
	row.add_child(UiKit.button("Title", func(): Game.save_game(); Game.goto("title"), "", 200))
