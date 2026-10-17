class_name AmbitionsView
extends RefCounted
## Modal list of the dynasty's ambitions with live progress (campaign/ambitions.gd).

static func open(host: Control) -> void:
	var list: Array = Ambitions.status(Game)
	var done := 0
	for a: Dictionary in list:
		if a["done"]: done += 1
	var v := UiKit.modal(host, "Ambitions of your house", 720)
	v.add_child(UiKit.label("Achieve %d of these %d to bring your dynasty to triumph. %d done." % [Ambitions.TO_WIN, list.size(), done], "", true))
	var bar := ProgressBar.new()
	bar.max_value = Ambitions.TO_WIN; bar.value = mini(done, Ambitions.TO_WIN); bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	v.add_child(bar)
	for a: Dictionary in list:
		var row := UiKit.panel("Card")
		var h := UiKit.hbox(12); row.add_child(h)
		var mark := UiKit.label("✔" if a["done"] else "○", "H2")
		mark.add_theme_color_override("font_color", UiTheme.GOOD if a["done"] else UiTheme.INK_SOFT)
		mark.custom_minimum_size.x = 28
		h.add_child(mark)
		var col := UiKit.vbox(2); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(col)
		var title := UiKit.label(str(a["name"]), "H2", true)
		title.add_theme_font_size_override("font_size", 20)
		col.add_child(title)
		col.add_child(UiKit.label(str(a["text"]), "", true))
		col.add_child(UiKit.label(str(a["progress"]), "Muted", true))
		v.add_child(row)
	var footer := UiKit.hbox(8); v.add_child(footer)
	footer.add_child(UiKit.spacer())
	footer.add_child(UiKit.button("Close", func(): UiKit.close_modal(v), "", 120))
