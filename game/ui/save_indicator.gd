class_name SaveIndicator
extends PanelContainer
## A fixed status control while a consistent world snapshot holds simulation.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel",UiTheme.sb(Color("#14251f"),Color("#70568b"),1,5,12,12))
	var label := UiKit.label("Saving world…")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false

func _layout() -> void:
	var screen := get_viewport_rect().size
	position = Vector2((screen.x-240.0)/2.0,(screen.y-44.0)/2.0)
	size = Vector2(240,44)

func _process(_delta: float) -> void:
	visible = Game._save_capture != null
