extends RefCounted
## Animated popup inventory (production .gd/.tscn scan, v0.070):
## - UiKit.toast: immediate appearance, 2.2 s hold, 0.6 s fade-out; replacement frees the old toast.
## - battle.gd::_banner: 0.5 s fade-in, hold, 0.8 s fade-out; battle/round/aftermath/result titles.
## UiKit.modal/picker/confirm/message and settings overlays open/close immediately. Their callers in
## ui/, campaign/world_map.gd and battle/ use no additional open/close animation or Timer.
## Sound's music crossfade and world/battle actors are not popup transitions.

class BannerHost extends "res://battle/battle.gd":
	func _ready() -> void:
		# Exercise the real banner builder without generating a world or simulating a battle.
		set_process(false)
		_handing_over = true
		ui = Control.new()
		add_child(ui)

var _fails := 0
var _checks := 0

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	# Let the autoload's initial, unrelated music crossfade finish before measuring popup tweens.
	while not tree.get_processed_tweens().is_empty() and Time.get_ticks_msec() - started < 3000:
		await tree.process_frame
	await _frames(tree)
	_check(tree.get_processed_tweens().is_empty(), "startup crossfade settled")
	var baseline := _snapshot(tree)
	for fading in [false, true]:
		await _toast(tree, fading, false)
		await _toast(tree, fading, true)
		await _banner(tree, fading, false)
		await _banner(tree, fading, true)
	await _toast_replacement(tree)
	for kind in ["modal", "picker", "confirm", "message", "settings"]:
		await _instant_popup(tree, kind)
	await _frames(tree)
	_assert_clean(tree, baseline, [], "whole test")
	print("popup_cleanup_v070: %d checks, %d failures, %.3f s" % [
		_checks, _fails, float(Time.get_ticks_msec() - started) / 1000.0])
	return _fails

func _toast(tree: SceneTree, fading: bool, close_host: bool) -> void:
	var total := _snapshot(tree)
	var host := Control.new()
	tree.root.add_child(host)
	await _frames(tree)
	var before := _snapshot(tree)
	UiKit.toast(host, "Cleanup", not fading)
	var popup := host.get_node("Toast") as Control
	var owned := _node_ids(popup)
	var tweens := tree.get_processed_tweens()
	_check(tweens.size() == 1, "toast owns one tween")
	if fading and not tweens.is_empty(): tweens[0].custom_step(2.35)
	await _frames(tree, 3)
	if fading: _check(popup.modulate.a > 0.0 and popup.modulate.a < 1.0, "toast interrupted during fade-out")
	if close_host:
		host.queue_free()
		host.queue_free()
	else:
		popup.queue_free()
		popup.queue_free()
	await _frames(tree)
	_assert_clean(tree, total if close_host else before, owned,
		"toast %s / %s" % ["fade-out" if fading else "hold (no fade-in)", "host exit" if close_host else "double close"])
	_kill_failed_tweens(tweens)
	if not close_host:
		host.resized.emit() # A surviving host must have no callback targeting the freed popup.
		host.queue_free()
		await _frames(tree)
	_assert_clean(tree, total, [], "toast host cleanup")

func _banner(tree: SceneTree, fading: bool, close_host: bool) -> void:
	var total := _snapshot(tree)
	var host := BannerHost.new()
	tree.root.add_child(host)
	await _frames(tree)
	var before := _snapshot(tree)
	host._banner("Cleanup", "Interrupted transition", 60.0)
	var popup := host.ui.get_child(0) as Control
	var owned := _node_ids(popup)
	var tweens := tree.get_processed_tweens()
	_check(tweens.size() == 1, "banner owns one tween")
	# custom_step crosses the hold deterministically without sleeping or leaving a SceneTreeTimer.
	if not tweens.is_empty(): tweens[0].custom_step(60.7 if fading else 0.15)
	await _frames(tree, 3)
	_check(popup.modulate.a > 0.0 and popup.modulate.a < 1.0,
		"banner interrupted during %s" % ("fade-out" if fading else "fade-in"))
	if close_host:
		host.queue_free()
		host.queue_free()
	else:
		popup.queue_free()
		popup.queue_free()
	await _frames(tree)
	_assert_clean(tree, total if close_host else before, owned,
		"banner %s / %s" % ["fade-out" if fading else "fade-in", "host exit" if close_host else "double close"])
	_kill_failed_tweens(tweens)
	if not close_host:
		host.queue_free()
		await _frames(tree)
	_assert_clean(tree, total, [], "banner host cleanup")

func _toast_replacement(tree: SceneTree) -> void:
	var total := _snapshot(tree)
	var host := Control.new()
	tree.root.add_child(host)
	await _frames(tree)
	var before := _snapshot(tree)
	var owned: Array[int] = []
	for i in 6:
		UiKit.toast(host, "Replacement %d" % i)
		owned.append_array(_node_ids(host.get_node("Toast")))
		var tweens := tree.get_processed_tweens()
		# Replace in both hold and fade-out; always leave exactly the newest toast running.
		if i % 2 == 1 and not tweens.is_empty(): tweens.back().custom_step(2.35)
		await _frames(tree, 3)
		_check(host.get_child_count() == 1, "replacement frees previous toast subtree")
		_check(tree.get_processed_tweens().size() == 1, "replacement retires previous tween")
	host.get_node("Toast").queue_free()
	await _frames(tree)
	_assert_clean(tree, before, owned, "toast replacement chain")
	host.queue_free()
	await _frames(tree)
	_assert_clean(tree, total, [], "toast replacement host cleanup")

func _instant_popup(tree: SceneTree, kind: String) -> void:
	var total := _snapshot(tree)
	var host := Control.new()
	tree.root.add_child(host)
	await _frames(tree)
	var before := _snapshot(tree)
	match kind:
		"modal": UiKit.modal(host, "Cleanup")
		"picker": UiKit.picker(host, "Cleanup", [{"text": "Pick", "value": 1}], func(_v): _check(false, "cancel must not pick"))
		"confirm": UiKit.confirm(host, "Cleanup", "Confirm", func(): _check(false, "cancel must not confirm"))
		"message": UiKit.message(host, "Cleanup", ["Report"])
		"settings": UiKit.open_settings(host, "", true)
	var popup := host.get_child(0)
	var owned := _node_ids(popup)
	await _frames(tree, 3)
	if kind == "modal":
		UiKit.close_modal(popup)
		UiKit.close_modal(popup)
	else:
		var button := _button(popup, "Back" if kind == "settings" else ("OK" if kind == "message" else "Cancel"))
		_check(button != null, kind + " close button exists")
		if button != null:
			button.pressed.emit()
			button.pressed.emit()
	await _frames(tree)
	_assert_clean(tree, before, owned, kind + " double close")
	host.resized.emit()
	host.queue_free()
	await _frames(tree)
	_assert_clean(tree, total, [], kind + " host cleanup")

func _snapshot(tree: SceneTree) -> Dictionary:
	var nodes := _node_ids(tree.root)
	var timers: Array[int] = []
	var processing: Array[int] = []
	var signals := {}
	for id in nodes:
		var node := instance_from_id(id) as Node
		if node is Timer: timers.append(id)
		if node.is_processing() or node.is_physics_processing(): processing.append(id)
		for signal_info in node.get_signal_list():
			var connections := node.get_signal_connection_list(signal_info["name"])
			if not connections.is_empty(): signals["%d:%s" % [id, signal_info["name"]]] = connections.size()
	return {"count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"nodes": nodes, "timers": timers, "processing": processing, "signals": signals}

func _assert_clean(tree: SceneTree, before: Dictionary, owned: Array, context: String) -> void:
	var after := _snapshot(tree)
	for key in ["count", "orphans", "nodes", "timers", "processing", "signals"]:
		_check(after[key] == before[key], "%s: %s returns to baseline" % [context, key])
	_check(tree.get_processed_tweens().is_empty(), context + ": no processed tweens (including paused tweens)")
	for id in owned:
		_check(not is_instance_id_valid(id), "%s: owned node %d freed" % [context, id])
	for id in after["nodes"]:
		var node := instance_from_id(id) as Node
		for signal_info in node.get_signal_list():
			for connection in node.get_signal_connection_list(signal_info["name"]):
				if not (connection["callable"] as Callable).is_valid():
					_check(false, "%s: invalid signal target on %s" % [context, node.name])

func _node_ids(node: Node) -> Array[int]:
	var ids: Array[int] = [node.get_instance_id()]
	for child in node.get_children(): ids.append_array(_node_ids(child))
	ids.sort()
	return ids

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _button(child, text)
		if found != null: return found
	return null

func _frames(tree: SceneTree, count: int = 4) -> void:
	for _i in count: await tree.process_frame
	# No RenderingServer.frame_post_draw wait: these lifecycle checks also run headlessly.

func _kill_failed_tweens(tweens: Array[Tween]) -> void:
	# Failure-only fixture teardown, after recording the leak, so later cases remain independent.
	for tween in tweens:
		if tween.is_valid(): tween.kill()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("popup_cleanup_v070 FAIL: ", message)
