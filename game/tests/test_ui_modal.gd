extends RefCounted
## Regression (Douglas, v0.008): a message opened from a picker (Families list -> family record) did not
## close on OK, because the second modal got auto-renamed while the first was still being freed.
func run(tree: SceneTree) -> int:
	var fails := 0
	var host := Control.new()
	tree.root.add_child.call_deferred(host)
	await tree.process_frame
	UiKit.picker(host, "Pick", [{"text": "A", "value": 1}], func(_v): UiKit.message(host, "Record", ["line"]))
	var pick_btn: Button = _find_button(host, "A")
	pick_btn.pressed.emit()        # closes the picker (queued) and opens the message in the same frame
	var ok: Button = _find_button(host, "OK")
	if ok == null:
		print("message did not open"); return 1
	ok.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	var left := 0
	for c in host.get_children():
		if not c.is_queued_for_deletion(): left += 1   # any overlay still standing
	if left != 0:
		print("modals still open after OK: ", left); fails += 1
	host.queue_free()
	return fails

func _find_button(n: Node, text: String) -> Button:
	for c in n.get_children():
		if c is Button and c.text == text and not c.is_queued_for_deletion():
			return c
		var r := _find_button(c, text)
		if r != null: return r
	return null
