extends Node
## v0.072 mobile: Android back navigation, lifecycle pause + autosave, and the screen wake lock
## (map/battle vs menus). Safe-area margins live in UiKit.safe_area_margins (ui/kit.gd); the phone
## performance profile in core/mobile_perf.gd. On desktop this node only answers the pause/quit menus
## it is asked for: closing the window, losing focus and the back button behave as before.
## v0.083: drag-anywhere list scrolling on phones is the TouchScroll child (ui/touch_scroll.gd).

const BUTTON_MIN_H := UiKit.MOBILE_TAP
const PLAY_SCREENS := ["map", "battle"]

var force_mobile := false
var keep_screen_on := false
var touch_scroll: TouchScroll = null

var _layer: CanvasLayer = null
var _layer_root: Control = null
var _pause_modal: Control = null
var _quit_modal: Control = null
var _save_failure_modal: Control = null # v0.100: one persistent notice, including while paused.
var _save_failure_paused_tree := false # v0.100: release only the failure notice's own tree hold.
var _paused_before_menu := false
var _battle_paused_before_menu := false
var _paused_by_lifecycle := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	touch_scroll = TouchScroll.new()
	touch_scroll.name = "TouchScroll"
	add_child(touch_scroll)
	if Game != null and not Game.screen_changed.is_connected(_on_screen_changed):
		Game.screen_changed.connect(_on_screen_changed)
	# v0.100: use the global overlay so failed saves remain visible across screen changes.
	if Game != null and not Game.save_finished.is_connected(_on_save_finished):
		Game.save_finished.connect(_on_save_finished)
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

## v0.100: true means written; can_autosave() distinguishes an ineligible screen from a failed write.
func autosave() -> bool:
	if not can_autosave():
		return false
	return Game.save_game() # v0.100: admission alone does not mean the save succeeded.

## stop_party = false (a brief focus loss: shade, dialog) keeps the map's travel order; the tree hold alone stops time.
func pause_gameplay(pause_tree: bool = true, stop_party: bool = true) -> void:
	if Game != null and CampaignWorld.defer_day_job_action(Game, pause_gameplay.bind(pause_tree, stop_party)):
		return
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
	if Game != null and what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN] and CampaignWorld.defer_day_job_action(Game, _notification.bind(what)):
		return
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			handle_back_request()
		NOTIFICATION_APPLICATION_PAUSED:
			# v0.100: lifecycle must pause even on failure; save_finished supplies the visible result.
			autosave()
			pause_gameplay(true)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Shade / dialogs: hold the game only. Leaving the app always sends PAUSED next, which saves.
			if is_mobile():
				pause_gameplay(true, false)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			if _paused_by_lifecycle and not is_pause_menu_open():
				_paused_by_lifecycle = false
				if is_save_failure_open():
					_save_failure_paused_tree = true # v0.100: transfer the ended lifecycle hold to the notice.
				elif Game != null and Game._save_capture != null:
					Game._save_was_paused = false # v0.100: let the active capture release the ended lifecycle hold.
				elif is_inside_tree():
					get_tree().paused = false
		# v0.100: Game owns the close-save and quit decision on every platform.

## Test/runner reset: no menus open and no lifecycle pause held.
func reset() -> void:
	_close_save_failure() # v0.100: failure overlays must not survive a runner reset.
	close_quit_confirm()
	close_pause_menu(false)
	_paused_by_lifecycle = false
	force_mobile = false
	if touch_scroll != null:
		touch_scroll.reset()

# ------------------------------------------------------------------ Android back button & menus
func is_pause_menu_open() -> bool:
	return is_instance_valid(_pause_modal) and not _pause_modal.is_queued_for_deletion()

func is_quit_confirm_open() -> bool:
	return is_instance_valid(_quit_modal) and not _quit_modal.is_queued_for_deletion()

# v0.100: back navigation and pause restoration must respect this blocking notice.
func is_save_failure_open() -> bool:
	return is_instance_valid(_save_failure_modal) and not _save_failure_modal.is_queued_for_deletion()

func handle_back_request() -> String:
	if Game != null and CampaignWorld.defer_day_job_action(Game, handle_back_request):
		return "queued_day_job"
	if is_save_failure_open():
		_close_save_failure()
		return "closed_save_failure"
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
			if c != _pause_modal and c != _quit_modal and c != _save_failure_modal and not c.is_queued_for_deletion():
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
	if node == _pause_modal or node == _quit_modal or node == _save_failure_modal or node.is_queued_for_deletion():
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
	if Game != null and CampaignWorld.defer_day_job_action(Game, open_pause_menu):
		return null
	if is_pause_menu_open():
		return _pause_modal
	var host := _ensure_layer()
	# A running save capture holds the tree paused for a few frames and then restores it; finish it now so
	# it cannot unpause the game under the menu, and so its hold is not mistaken for the player's pause.
	if Game != null and Game._save_capture != null:
		Game._save_capture.step(0)
		Game._finish_capture()
	# A lifecycle hold (focus lost) is not a pause to restore on Resume.
	# v0.100: a notice's temporary hold is not a player pause to restore after Resume.
	_paused_before_menu = (get_tree().paused and not _paused_by_lifecycle and not _save_failure_paused_tree) if is_inside_tree() else false
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
			if not autosave(): return # v0.100: keep the menu on failure.
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
			# v0.100: nothing to save may leave normally; a real failed write keeps this menu open.
			if can_autosave() and not autosave(): return
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
	if Game != null and CampaignWorld.defer_day_job_action(Game, close_pause_menu.bind(restore_pause)):
		return
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
		if is_inside_tree() and Game != null and Game._save_capture != null:
			# v0.100: the capture restores the tree when it finishes; give it the post-menu state.
			if is_save_failure_open():
				_save_failure_paused_tree = _save_failure_paused_tree or not _paused_before_menu
			Game._save_was_paused = _paused_before_menu or is_save_failure_open()
		elif is_inside_tree():
			if is_save_failure_open():
				_save_failure_paused_tree = _save_failure_paused_tree or not _paused_before_menu
			else:
				get_tree().paused = _paused_before_menu
		_paused_by_lifecycle = false
	_cleanup_layer_if_empty()
	_update_keep_screen_on()

func ask_quit_confirm() -> Control:
	if Game != null and CampaignWorld.defer_day_job_action(Game, ask_quit_confirm):
		return null
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
	# v0.100: the receipt opens a failure notice; keep playing unless an unsaved exit is chosen.
	if Game != null and not Game.save_on_quit():
		return
	_quit_without_saving()

func _quit_without_saving() -> void:
	if Game != null and CampaignWorld.defer_day_job_action(Game, _quit_without_saving):
		return
	_close_save_failure()
	close_quit_confirm()
	close_pause_menu(false)
	if is_inside_tree():
		get_tree().paused = false
		get_tree().quit()

# v0.100: a refused save must be readable in-game, including after a failed quit.
func _on_save_finished(ok: bool) -> void:
	if Game != null and CampaignWorld.defer_day_job_action(Game, _on_save_finished.bind(ok)):
		return
	if ok:
		_close_save_failure()
		return
	if not is_inside_tree(): return
	if is_save_failure_open(): return
	# v0.100: freeze campaign and battle processing while the blocking notice is read.
	if not get_tree().paused:
		get_tree().paused = true
		_save_failure_paused_tree = true
	var box := UiKit.modal(_ensure_layer(), "Save failed", 560)
	_save_failure_modal = box.get_parent().get_parent().get_parent() as Control
	_save_failure_modal.name = "SaveFailureModal"
	box.add_child(UiKit.label("Your latest progress was not saved. Any previous save is unchanged.", "", true))
	box.add_child(UiKit.label("Keep playing to try Save Game again, or quit without saving this progress.", "Muted", true))
	var row := UiKit.flow()
	row.add_child(_menu_button("Keep playing", _close_save_failure, "Row", 150))
	row.add_child(_menu_button("Quit without saving", _quit_without_saving, "Danger", 240))
	box.add_child(row)

func _close_save_failure() -> void:
	if Game != null and CampaignWorld.defer_day_job_action(Game, _close_save_failure):
		return
	if is_instance_valid(_save_failure_modal):
		if _save_failure_modal.get_parent() != null:
			_save_failure_modal.get_parent().remove_child(_save_failure_modal)
		_save_failure_modal.queue_free()
	_save_failure_modal = null
	if _save_failure_paused_tree:
		_save_failure_paused_tree = false
		if is_inside_tree() and not is_pause_menu_open() and not _paused_by_lifecycle:
			if Game != null and Game._save_capture != null:
				# v0.100: the capture still owns the tree; release the notice's hold when it finishes.
				Game._save_was_paused = false
			else:
				get_tree().paused = false
	_cleanup_layer_if_empty()
