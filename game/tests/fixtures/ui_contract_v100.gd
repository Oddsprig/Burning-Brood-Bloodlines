extends RefCounted
## v0.100: exercise the category navigation and measure overflow, not scroll policy (6210641).

const TOWN_GROUPS := {"Overview": ["Overview"], "People": ["Register", "Census", "Hardship", "Sickness"],
	"Economy": ["Market", "Businesses", "Treasury", "Books"], "Land & defence": ["Land & Homes", "Garrison", "Roads"]}
const REALM_GROUPS := {"Places": ["Towns", "Factions", "Mines & land"], "People": ["Rulers", "Census"],
	"Economy": ["Goods", "Food flows", "Merchants"], "Military": ["Army", "On the move", "Fights"]}

static func navigate(screen: Control, section: String) -> bool:
	var groups: Dictionary = TOWN_GROUPS if screen.view == "town" else REALM_GROUPS
	for title in groups:
		if not (groups[title] as Array).has(section): continue
		var category := _button(screen.groups_box, String(title))
		if category == null: return false
		category.pressed.emit()
		var action := _button(screen.tabs_box, section)
		if screen.tabs_box.visible:
			if action == null: return false
			action.pressed.emit()
		return String(screen.tab) == section
	return false

static func _button(node: Node, title: String) -> Button:
	if node is Button and node.text == title: return node
	for child in node.get_children():
		var found := _button(child, title)
		if found != null: return found
	return null

static func horizontal_fits(sc: ScrollContainer, tolerance: float = 1.5) -> bool:
	var bar := sc.get_h_scroll_bar()
	if sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and bar.max_value - bar.page > tolerance:
		return false
	if absf(float(sc.scroll_horizontal)) > tolerance:
		return false
	var available := sc.size.x - sc.get_theme_stylebox("panel").get_minimum_size().x
	if sc.get_v_scroll_bar().visible: available -= sc.get_v_scroll_bar().size.x
	for child in sc.get_children():
		if child is Control and not (child is ScrollBar) and child.visible:
			if maxf(child.size.x, child.get_combined_minimum_size().x) > available + tolerance:
				return false
	return true

static func row_height() -> float:
	# v0.100: 56 px desktop rows (6210641); phones retain 96 px targets (4e2530a).
	return 96.0 if UiTheme.is_mobile() else 56.0
