extends RefCounted
## Native two-fighter control; no campaign generation, save or result handback.
const U := preload("res://tests/sim_util.gd")
const Purity := preload("res://tests/test_battle_visual_purity.gd")
var checks: int = 0
var fails: int = 0

class PaceBattle extends "res://battle/battle.gd":
	func _ready() -> void:
		super._ready()
		paused = true
		_refresh_speed_buttons()
		set_process(false) # Explicit fixed ticks and zero-time presentation below.
	func battle_opts(_pb: Dictionary, _n0: int, _n1: int) -> Dictionary:
		return {"w":12,"h":8,"max_ticks":48,"log_moves":false,
			"cells0":[Vector2i(4,4)],"cells1":[Vector2i(5,4)]}
	func finish() -> void:
		push_error("Pace fixture must not reconcile artificial troops into a campaign")

class CountGrowth extends BattleSim:
	var growth_calls: int = 0
	func apply_battle_growth() -> Dictionary:
		growth_calls += 1
		return super.apply_battle_growth()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL battle pace: ", message)

func _cancel_event(echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	event.echo = echo
	return event

func _toggle(root: Node) -> Button:
	return root.find_child("Toggle_battle_event_slowmo", true, false) as Button

func _named_label(root: Node, text: String) -> bool:
	if root is Label and root.text == text: return true
	for child: Node in root.get_children():
		if _named_label(child, text): return true
	return false

func _sha() -> String:
	return JSON.stringify(Game._save_tree(), "", true, true).sha256_text()

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var original_settings: Dictionary = Game.settings.duplicate(true)
	var original_path: String = Game.SETTINGS_PATH
	var original_company: Array = Game.company
	var original_pending: Dictionary = Game.pending_battle
	var original_screen: String = Game._active_screen
	var original_params: Dictionary = Game.screen_params
	var original_unit_counter: int = Unit._next_uid
	var original_item_counter: int = Item._next_uid
	var original_sha: String = _sha()
	var native_rng: int = Game.rng.state
	var world_ref: Dictionary = Game.world
	Game.SETTINGS_PATH = "user://test_pace_v014_%d.json" % OS.get_process_id()
	if FileAccess.file_exists(Game.SETTINGS_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_PATH))
	Game.load_settings()
	check(Game.DEFAULT_SETTINGS["battle_event_slowmo"] == false and Game.setting("battle_event_slowmo") == false, "fresh automatic slow motion is OFF")
	check(Game.setting("gore") == "full" and Game.setting("anim_lodged") == false, "existing native defaults retained")
	var changes: Array = []
	var setting_listener: Callable = func(key: String, value: Variant): changes.append([key,value])
	Game.setting_changed.connect(setting_listener)
	Game.set_setting("battle_event_slowmo", true)
	check(changes.size() == 1 and changes[0] == ["battle_event_slowmo",true], "one actual setting change emits one notification")
	Game.set_setting("battle_event_slowmo", true)
	check(changes.size() == 1, "unchanged setting does not notify again")
	Game.set_setting("gore", "reduced")
	Game.set_setting("anim_lodged", true)
	Game.settings = Game.DEFAULT_SETTINGS.duplicate()
	Game.load_settings()
	check(Game.setting("battle_event_slowmo") == true and Game.setting("gore") == "reduced" and Game.setting("anim_lodged") == true, "native settings roundtrip retains gameplay/gore/animation values")
	check(not CombatText.gore_full, "loaded native gore wording follows persisted value")
	Game.set_setting("battle_event_slowmo", false)
	Game.load_settings()
	check(Game.setting("battle_event_slowmo") == false, "explicit OFF persists")
	var ordinary: Control = (load("res://ui/settings.tscn") as PackedScene).instantiate()
	tree.root.add_child(ordinary)
	check(_named_label(ordinary, "Gameplay") and _toggle(ordinary) != null and _toggle(ordinary).text == "OFF", "ordinary Settings exposes Gameplay option and current OFF")
	_toggle(ordinary).pressed.emit()
	await tree.process_frame
	check(Game.setting("battle_event_slowmo") == true and _toggle(ordinary).text == "ON", "ordinary Settings toggles actual persisted option")
	ordinary.queue_free()
	await tree.process_frame
	ordinary = null
	Game.set_setting("battle_event_slowmo", false)
	var left: Unit = U.soldier("copper")
	var right: Unit = U.make("orc", [["hacking_cleaver","copper"],["tunic","linen"]], {"axe":4,"fighter":3})
	Food.roll_fav_drink(left, hash([left.uid,left.name]))
	Food.roll_fav_drink(right, hash([right.uid,right.name]))
	var left_template: Dictionary = left.to_dict().duplicate(true)
	var right_template: Dictionary = right.to_dict().duplicate(true)
	var control_left: Unit = Unit.from_dict(left.to_dict().duplicate(true))
	var control_right: Unit = Unit.from_dict(right.to_dict().duplicate(true))
	Game.company = [left]
	Game.pending_battle = {"enemy":[right],"seed":321}
	Game.invalidate_deploy()
	var bindings_before: int = Game.setting_changed.get_connections().size()
	var battle := PaceBattle.new()
	tree.root.add_child(battle)
	var control := BattleSim.new()
	control.setup([control_left], [control_right], 321, battle.battle_opts({},1,1))
	var purity: RefCounted = Purity.new()
	check(purity.mechanical(battle.sim) == purity.mechanical(control), "native independent control starts identical")
	check(Game.setting_changed.is_connected(battle._on_setting_changed), "battle receives live setting changes")
	check(not battle._wants_slowmo({"type":"sever"}) and not battle._wants_slowmo({"type":"artery"}), "OFF suppresses severe-event slowdown requests")
	battle.paused = false
	battle._trigger_slowmo(1)
	check(battle._slowmo == 0.0 and battle._slowmo_cd == 0.0 and battle._nudge_amount == 0.0, "OFF also guards direct slowdown trigger")
	Game.set_setting("battle_event_slowmo", true)
	check(battle._wants_slowmo({"type":"sever"}) and battle._wants_slowmo({"type":"artery"}) and not battle._wants_slowmo({"type":"miss"}), "ON preserves native severe-event selection")
	battle.set_speed(2.0)
	battle._trigger_slowmo(1)
	check(battle._slowmo == battle.SLOWMO_TIME and battle._slowmo_cd > battle._slowmo and battle.speed == 2.0, "ON retains native slowdown duration/cooldown and selected speed")
	battle.paused = true
	battle._nudge = 0.75
	battle._update_camera(0.0)
	var native_before: Dictionary = purity.mechanical(battle.sim)
	Game.set_setting("battle_event_slowmo", false)
	check(battle._slowmo == 0.0 and battle._slowmo_cd == 0.0 and battle._nudge_amount == 0.0 and battle._nudge == 0.0, "OFF cancels active slowdown/cooldown/nudge immediately")
	check(battle.camera.zoom == Vector2(battle.cam_zoom,battle.cam_zoom) and battle.camera.position == battle.cam_pos, "OFF immediately restores chosen camera framing")
	check(battle.speed == 2.0 and battle.paused and purity.mechanical(battle.sim) == native_before, "OFF changes neither chosen speed/pause nor native state")
	Game.set_setting("battle_event_slowmo", true)
	battle._trigger_slowmo(1)
	check(battle._slowmo == 0.0, "native pause still blocks ON slowdown")
	Game.set_setting("battle_event_slowmo", false)
	battle.set_speed(4.0)
	var escape: InputEventKey = _cancel_event()
	check(escape.is_action_pressed("ui_cancel"), "native Esc action is mapped")
	battle._unhandled_input(escape)
	check(battle.settings_open and battle.paused and battle.speed == 4.0 and battle._settings_overlay != null, "Esc opens existing Settings overlay and pauses without changing speed")
	var overlay_ref: WeakRef = weakref(battle._settings_overlay)
	battle._unhandled_input(_cancel_event(true))
	check(overlay_ref.get_ref() == battle._settings_overlay, "key repeat cannot duplicate or close Settings")
	native_before = purity.mechanical(battle.sim)
	_toggle(battle._settings_overlay).pressed.emit()
	await tree.process_frame
	check(Game.setting("battle_event_slowmo") == true and _toggle(battle._settings_overlay).text == "ON", "battle overlay edits the same Gameplay option")
	battle._settings_overlay._unhandled_input(_cancel_event())
	await tree.process_frame
	await tree.process_frame
	battle._process_battle(0.0)
	check(overlay_ref.get_ref() == null and not battle.settings_open and not battle.paused and battle.speed == 4.0, "Esc closes overlay and restores previously running pause/speed")
	check(purity.mechanical(battle.sim) == native_before, "Settings reading/toggling/closing advances no native tick")
	battle.paused = true
	battle._unhandled_input(_cancel_event())
	check(battle.settings_open and battle._paused_before_settings, "Esc remembers a previously paused battle")
	battle._unhandled_input(_cancel_event())
	await tree.process_frame
	await tree.process_frame
	battle._process_battle(0.0)
	check(not battle.settings_open and battle.paused and battle.speed == 4.0, "Esc restores previously paused battle")
	Game.set_setting("battle_event_slowmo", false)
	battle.set_speed(4.0)
	var tick_before: int = battle.sim.tick
	battle._process_battle(1.0 / (battle.TICKS_PER_SEC * battle.speed))
	control.step()
	check(battle.sim.tick == tick_before + 1 and battle.speed == 4.0 and battle._slowmo == 0.0,
		"OFF delivers one native tick at selected speed without automatic reduction")
	for i: int in 24:
		battle.step_ticks(1)
		control.step()
	check(purity.mechanical(battle.sim) == purity.mechanical(control), "OFF fixed native ticks preserve full control outcomes")
	Game.set_setting("battle_event_slowmo", true)
	battle.paused = false
	for i: int in 24:
		battle.step_ticks(1)
		control.step()
	check(purity.mechanical(battle.sim) == purity.mechanical(control), "ON presentation at fixed ticks preserves RNG/body/wound/event outcomes")
	check(U.count(battle.sim,"attack") > 0 and U.count(battle.sim,"hit") > 0 and U.count(battle.sim,"wound") > 0, "native fixture actually attacks, hits and wounds")
	# Metadata extraction has one native growth call; copies never retain Fighters.
	var summary_sim := CountGrowth.new()
	summary_sim.setup([left], [right], 323, battle.battle_opts({},1,1))
	summary_sim.fighters[0].state = "fled"
	summary_sim.fighters[1].state = "fled"
	var summary: Node2D = load("res://battle/battle.gd").new()
	summary.sim = summary_sim
	summary.side_names = ["Company fixture","Enemy fixture"]
	var calls_before: int = summary_sim.growth_calls
	var result: Dictionary = summary.build_result()
	check(summary_sim.growth_calls == calls_before + 1, "result preserves exactly one native growth invocation")
	check(result["player_fled"] == [left] and result["enemy_fled"] == [right], "native result supplies both actual fled Unit arrays")
	check(result["fighter_states"] == ["fled","fled"] and result["fighter_units"] == [left,right], "plain fighter state metadata aligns with native Unit order")
	summary.side_names[0] = "Changed"
	summary_sim.fighters[0].state = "ready"
	check(result["side_names"] == ["Company fixture","Enemy fixture"] and result["fighter_states"] == ["fled","fled"], "result labels/states are detached from live presentation")
	check(result.has_all(["winner","player_units","enemy_units","enemy_fallen","events","ticks","growth","history_events_omitted","arrow_field"]), "existing result fields retained")
	summary.free()
	summary = null
	battle.queue_free()
	await tree.process_frame
	await tree.process_frame
	check(not is_instance_valid(battle) and Game.setting_changed.get_connections().size() == bindings_before, "battle live setting binding releases with scene")
	battle = null
	# A fresh native scene gives Skip its real camera/viewport and actor children.
	Game.company = [Unit.from_dict(left_template.duplicate(true))]
	Game.pending_battle = {"enemy":[Unit.from_dict(right_template.duplicate(true))],"seed":322}
	Game.invalidate_deploy()
	var skip_screen := PaceBattle.new()
	tree.root.add_child(skip_screen)
	skip_screen.skip_to_end()
	check(skip_screen.sim.is_over() and not skip_screen._skipping and skip_screen._slowmo == 0.0, "native skip completes bounded fight and settles slowdown")
	skip_screen.queue_free()
	await tree.process_frame
	await tree.process_frame
	skip_screen = null
	Game.setting_changed.disconnect(setting_listener)
	Game.company = original_company
	Game.pending_battle = original_pending
	Game.invalidate_deploy()
	Game.settings = original_settings
	CombatText.gore_full = Game.gore_full()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_PATH))
	Game.SETTINGS_PATH = original_path
	Game._active_screen = original_screen
	Game.screen_params = original_params
	Unit._next_uid = original_unit_counter
	Item._next_uid = original_item_counter
	check(Game.rng.state == native_rng and is_same(Game.world,world_ref) and _sha() == original_sha,
		"settings and presentation preserve complete campaign state/RNG/world ownership")
	print("Battle pace v014: ", checks, " checks, ", fails, " failures")
	return fails
