extends Node
## v0.072 mobile: Android back navigation, lifecycle pause + autosave, and the screen wake lock
## (map/battle vs menus). Safe-area margins live in UiKit.safe_area_margins (ui/kit.gd); the phone
## performance profile in core/mobile_perf.gd. On desktop this node only answers the pause/quit menus
## it is asked for: closing the window, losing focus and the back button behave as before.

const BUTTON_MIN_H := UiKit.MOBILE_TAP
const PLAY_SCREENS := ["map", "battle"]

var force_mobile := false
var keep_screen_on := false

var _layer: CanvasLayer = null
var _layer_root: Control = null
var _pause_modal: Control = null
var _quit_modal: Control = null
var _paused_before_menu := false
var _battle_paused_before_menu := false
var _paused_by_lifecycle := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	if Game != null and not Game.screen_changed.is_connected(_on_screen_changed):
		Game.screen_changed.connect(_on_screen_changed)
	_update_keep_screen_on(String(Game._active_screen) if Game != null else "title")

func is_mobile() -> bool:
	return force_mobile or UiTheme.is_mobile()

# ------------------------------------------------------------------ screen wake lock
func should_keep_screen_on(screen: String = "") -> bool:
	var active := screen if screen != "" else (String(Game._active_screen) if Game != null else "title")
	if is_pause_menu_open() or is_quit_confirm_open():
		return false
	return active in PLAY_SCREENS

func _update_keep_screen_on(screen: String = "") -> void:
	keep_screen_on = should_keep_screen_on(screen)
	if is_mobile() and DisplayServer.get_name() != "headless":
		DisplayServer.screen_set_keep_on(keep_screen_on)

func _on_screen_changed(screen: String) -> void:
	if screen == "title" and is_pause_menu_open():
		close_pause_menu(false)
	_update_keep_screen_on(screen)

# ------------------------------------------------------------------ lifecycle & autosave
func can_autosave() -> bool:
	if Game == null or not Game._save_ready:
		return false
	var screen := String(Game._active_screen)
	# The game never saves mid-battle (Game.save_game_async defers it): the fight is not part of the save.
	if screen in ["title", "presim", "newgame", "gameover", "battle"]:
		return false
	return not Game.world.is_empty() or not Game.company.is_empty()

func autosave() -> bool:
	if not can_autosave():
		return false
	Game.save_game()
	return true

## stop_party = false (a brief focus loss: shade, dialog) keeps the map's travel order; the tree hold alone stops time.
func pause_gameplay(pause_tree: bool = true, stop_party: bool = true) -> void:
	if Game == null:
		return
	var screen := String(Game._active_screen)
	if screen in ["title", "presim", "newgame"]:
		return
	var cur: Node = Game.main.current if Game.main != null else null
	if screen == "battle" and is_instance_valid(cur):
		cur.set("paused", true)
		if cur.has_method("_refresh_speed_buttons"):
			cur._refresh_speed_buttons()
	elif screen == "map" and stop_party and Game.world.has("party"):
		Game.world["party"]["waiting"] = false
		CampaignWorld.stop_travel(Game)
	if pause_tree and is_inside_tree():
		get_tree().paused = true
		_paused_by_lifecycle = true
	_update_keep_screen_on(screen)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			handle_back_request()
		NOTIFICATION_APPLICATION_PAUSED:
			autosave()
			pause_gameplay(true)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Shade / dialogs: hold the game only. Leaving the app always sends PAUSED next, which saves.
			if is_mobile():
				pause_gameplay(true, false)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			if _paused_by_lifecycle and not is_pause_menu_open() and (Game == null or Game._save_capture == null):
				_paused_by_lifecycle = false
				if is_inside_tree():
					get_tree().paused = false
		NOTIFICATION_WM_CLOSE_REQUEST:
			if is_mobile():
				autosave()

## Test/runner reset: no menus open and no lifecycle pause held.
func reset() -> void:
	close_quit_confirm()
	close_pause_menu(false)
	_paused_by_lifecycle = false
	force_mobile = false

# ------------------------------------------------------------------ Android back button & menus
func is_pause_menu_open() -> bool:
	return is_instance_valid(_pause_modal) and not _pause_modal.is_queued_for_deletion()

func is_quit_confirm_open() -> bool:
	return is_instance_valid(_quit_modal) and not _quit_modal.is_queued_for_deletion()

func handle_back_request() -> String:
	if is_quit_confirm_open():
		close_quit_confirm()
		return "closed_quit_confirm"
	if _close_topmost_popup_or_panel():
		return "closed_panel"
	var screen := String(Game._active_screen) if Game != null else "title"
	if is_pause_menu_open() or screen == "title":
		ask_quit_confirm()
		return "asked_quit"
	open_pause_menu()
	return "opened_pause"

func _close_topmost_popup_or_panel() -> bool:
	if _layer_root != null and is_instance_valid(_layer_root):
		for i in range(_layer_root.get_child_count() - 1, -1, -1):
			var c := _layer_root.get_child(i)
			if c != _pause_modal and c != _quit_modal and not c.is_queued_for_deletion():
				c.queue_free()
				return true
	if is_inside_tree() and get_tree().root != null:
		var modals: Array[Node] = []
		_collect_modals(get_tree().root, modals)
		if not modals.is_empty():
			var top_modal: Node = modals[-1]
			if top_modal.get_parent() != null:
				top_modal.get_parent().remove_child(top_modal)
			top_modal.queue_free()
			return true
		var popups: Array[Popup] = []
		_collect_popups(get_tree().root, popups)
		if not popups.is_empty():
			popups[-1].hide()
			return true
	if is_pause_menu_open():
		return false
	var scr: Node = Game.main.current if (Game != null and Game.main != null) else null
	if not is_instance_valid(scr):
		return false
	var screen := String(Game._active_screen)
	if screen == "battle":
		if scr.get("settings_open") == true and is_instance_valid(scr.get("_settings_overlay")):
			scr._toggle_settings()
			return true
		if is_instance_valid(scr.get("_log_overlay")):
			scr.close_combat_log()
			return true
		var rl = scr.get("readability_legend")
		if rl != null and rl.has_method("is_open") and rl.is_open():
			rl.close()
			return true
		var insp: Control = scr.get("inspector")
		if insp != null and insp.visible:
			scr.select(-1)
			return true
	elif screen == "map":
		var info: Control = scr.get("info_panel")
		if info != null and info.visible:
			scr._close_info()
			return true
	for child in scr.get_children():
		# `== true`, not bool(): most children have no `overlay` property and bool(null) is a script error.
		if child.get("overlay") == true and not child.is_queued_for_deletion():
			child.queue_free()
			return true
	if scr.get("stack") is Array and not (scr.get("stack") as Array).is_empty() and scr.has_method("go_back"):
		scr.go_back()
		return true
	if scr.has_method("close"):
		scr.close()
		return true
	if scr.get("member") is Dictionary and not (scr.get("member") as Dictionary).is_empty() and scr.has_method("_refresh"):
		scr.set("member", {})
		scr._refresh()
		return true
	if scr.get("detail_uid") is String and String(scr.get("detail_uid")) != "" and scr.has_method("_refresh"):
		scr.set("detail_uid", "")
		scr._refresh()
		return true
	if scr.has_method("previous_stage") and int(scr.get("stage")) > 0:
		scr.previous_stage()
		return true
	if scr.has_method("_back"):
		scr._back()
		return true
	if screen == "court":
		Game.goto(String(Game.screen_params.get("back", "map")))
		return true
	return false

func _collect_modals(node: Node, out: Array[Node]) -> void:
	if node == _pause_modal or node == _quit_modal or node.is_queued_for_deletion():
		return
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node.has_meta("ui_modal"):
		out.append(node)
	for child in node.get_children():
		_collect_modals(child, out)

func _collect_popups(node: Node, out: Array[Popup]) -> void:
	if node.is_queued_for_deletion():
		return
	if node is Popup and (node as Popup).visible:
		out.append(node as Popup)
	for child in node.get_children():
		_collect_popups(child, out)

func _ensure_layer() -> Control:
	if _layer == null or not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.name = "MobileAppLayer"
		_layer.layer = 110
		_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_layer)
		_layer_root = Control.new()
		_layer_root.name = "MobileAppRoot"
		_layer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer_root.theme = UiTheme.get_theme()
		_layer.add_child(_layer_root)
	return _layer_root

func _cleanup_layer_if_empty() -> void:
	if _layer_root != null and is_instance_valid(_layer_root) and _layer_root.get_child_count() == 0:
		if _layer != null and is_instance_valid(_layer):
			remove_child(_layer)
			_layer.queue_free()
		_layer = null
		_layer_root = null

func _menu_button(text: String, cb: Callable, variation: String = "", min_w: int = 240) -> Button:
	var b := UiKit.button(text, cb, variation, min_w)
	b.custom_minimum_size = Vector2(maxf(float(min_w), b.custom_minimum_size.x), maxf(float(BUTTON_MIN_H), b.custom_minimum_size.y))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

func open_pause_menu() -> Control:
	if is_pause_menu_open():
		return _pause_modal
	var host := _ensure_layer()
	# A running save capture holds the tree paused for a few frames and then restores it; finish it now so
	# it cannot unpause the game under the menu, and so its hold is not mistaken for the player's pause.
	if Game != null and Game._save_capture != null:
		Game._save_capture.step(0)
		Game._finish_capture()
	# A lifecycle hold (focus lost) is not a pause to restore on Resume.
	_paused_before_menu = (get_tree().paused and not _paused_by_lifecycle) if is_inside_tree() else false
	var cur: Node = Game.main.current if (Game != null and Game.main != null) else null
	_battle_paused_before_menu = bool(cur.get("paused")) if (Game != null and String(Game._active_screen) == "battle" and is_instance_valid(cur)) else false
	if Game != null and String(Game._active_screen) == "battle" and is_instance_valid(cur):
		cur.set("paused", true)
		if cur.has_method("_refresh_speed_buttons"):
			cur._refresh_speed_buttons()
	# A finger still down when the menu opens never sends its release to a paused screen: drop that touch.
	var ti: Variant = cur.get("touch_input") if is_instance_valid(cur) else null
	if ti is TouchInput:
		(ti as TouchInput).reset()
	if is_inside_tree():
		get_tree().paused = true
	var box := UiKit.modal(host, "Game Paused", 440)
	_pause_modal = box.get_parent().get_parent().get_parent() as Control
	_pause_modal.name = "MobilePauseModal"
	var resume_btn := _menu_button("Resume", func(): close_pause_menu(true))
	resume_btn.name = "PauseResume"
	box.add_child(resume_btn)
	if can_autosave() and (Game == null or String(Game._active_screen) != "battle"):
		var save_btn := _menu_button("Save Game", func():
			autosave()
			close_pause_menu(true), "Row")
		save_btn.name = "PauseSave"
		box.add_child(save_btn)
	var settings_btn := _menu_button("Settings", func():
		UiKit.open_settings(_ensure_layer(), "", true), "Row")
	settings_btn.name = "PauseSettings"
	box.add_child(settings_btn)
	# Not from a battle: the half-fought campaign would stay in memory, and a later autosave (title -> settings, app
	# sent to the background) would write it. Quit leaves a fight without saving it.
	if Game != null and String(Game._active_screen) not in ["title", "battle"]:
		var title_btn := _menu_button("Title Screen", func():
			autosave()
			close_pause_menu(false)
			if is_inside_tree():
				get_tree().paused = false
			Game.goto("title"), "Row")
		title_btn.name = "PauseTitle"
		box.add_child(title_btn)
	var quit_btn := _menu_button("Quit Game", func(): ask_quit_confirm(), "Danger")
	quit_btn.name = "PauseQuit"
	box.add_child(quit_btn)
	_update_keep_screen_on()
	return _pause_modal

func close_pause_menu(restore_pause: bool = true) -> void:
	if is_quit_confirm_open():
		close_quit_confirm()
	if is_pause_menu_open():
		if _pause_modal.get_parent() != null:
			_pause_modal.get_parent().remove_child(_pause_modal)
		_pause_modal.queue_free()
	_pause_modal = null
	if restore_pause:
		var cur: Node = Game.main.current if (Game != null and Game.main != null) else null
		if Game != null and String(Game._active_screen) == "battle" and is_instance_valid(cur):
			cur.set("paused", _battle_paused_before_menu)
			if cur.has_method("_refresh_speed_buttons"):
				cur._refresh_speed_buttons()
		if is_inside_tree() and (Game == null or Game._save_capture == null):
			get_tree().paused = _paused_before_menu
		_paused_by_lifecycle = false
	_cleanup_layer_if_empty()
	_update_keep_screen_on()

func ask_quit_confirm() -> Control:
	if is_quit_confirm_open():
		return _quit_modal
	var host := _ensure_layer()
	var box := UiKit.modal(host, "Quit game?", 440)
	_quit_modal = box.get_parent().get_parent().get_parent() as Control
	_quit_modal.name = "MobileQuitConfirmModal"
	var note := "Your campaign progress will be saved before exiting."
	if Game != null and String(Game._active_screen) == "battle":
		note = "The battle in progress is not saved: the campaign keeps its last save, from before the fight."
	elif not can_autosave():
		note = ""   # title / new campaign: there is no campaign in play to save
	if note != "":
		box.add_child(UiKit.label(note, "Muted", true))
	var row := UiKit.hbox(10)
	var cancel_btn := _menu_button("Cancel", func(): close_quit_confirm(), "Row", 150)
	cancel_btn.name = "QuitCancel"
	var confirm_btn := _menu_button("Quit", func(): confirm_quit(), "Danger", 150)
	confirm_btn.name = "QuitConfirm"
	row.add_child(cancel_btn)
	row.add_child(confirm_btn)
	box.add_child(row)
	_update_keep_screen_on()
	return _quit_modal

func close_quit_confirm() -> void:
	if is_quit_confirm_open():
		if _quit_modal.get_parent() != null:
			_quit_modal.get_parent().remove_child(_quit_modal)
		_quit_modal.queue_free()
	_quit_modal = null
	_cleanup_layer_if_empty()
	_update_keep_screen_on()

func confirm_quit() -> void:
	autosave()
	if Game != null:
		Game.wait_save(String(Game._active_screen) != "battle")   # quitting a fight never writes the half-fought state
	close_quit_confirm()
	close_pause_menu(false)
	if is_inside_tree():
		get_tree().paused = false
		get_tree().quit()
