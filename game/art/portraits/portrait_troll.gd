extends RefCounted
## v0.068 troll redo entry. Keep all troll changes and copied helpers in this file.

static func paint(spec: Dictionary) -> Image:
	# Call the frozen renderer directly, never paint(), which dispatches back here.
	return load("res://art/portrait_bust.gd").new()._render(spec)
