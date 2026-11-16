extends RefCounted
## v0.104: real screens, viewport mouse/key input, all 17 small-house highlights and native loan/funding/muster/travel.
## Headless brief: --block=tutorial_chapter_v104 --watchdog=120 (aim <60 s, hard stop 120 s).
## v0.104: presses CreateWorld, runs native Normal / one-day presim, and reloads mid-chapter; no fixture/flag bypass.
## v0.104: the declined path stops after native initialization; only the selected path generates the full world.
## v0.104: the real presim Skip button skips the map reveal only, never generation or the one-day history.
## v0.104: requires the real v0.102 implementation. Default/--small-house is the poor non-ruling path.
## v0.104: --ruling-house is an explicit funded control, never a fallback or small-house acceptance.
## v0.104: after real generation, the sole hardship fixture reduces the chosen House purse to 0 before UI selection.
## v0.104: it grants no money, changes no debt/credit/treasury/stock/service or authority; all borrowing uses viewport input.
## Testing rules (verbatim): "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief."
## "A test failure stops all further tests. No other test runs until that one failing test is fixed and passes."

class ChapterMain:
	extends "res://main.gd"
	func _ready() -> void:
		Game.main = self # v0.104: retain production show_screen; skip title warm-up/diagnostics in the bounded fixture.

var fails := 0
var checks := 0
var capture_dir := "" # Only the separate windowed capture entry point sets this.
var captured: Dictionary = {}
var visited: Dictionary = {} # v0.104: required borrowing steps cannot disappear behind a completion flag.
var viewport: Viewport
var main: Node
var started := 0
var running := false
var old_main: Node
var old_screen := ""
var old_params: Dictionary = {}
var old_settings: Dictionary = {}

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL v0.104: ", message)
	return ok

func frames(tree: SceneTree, count: int = 4) -> void:
	for i in count:
		await tree.process_frame

func overlay_now() -> TutorialOverlay:
	if not is_instance_valid(main) or not is_instance_valid(main.current): return null
	return main.current.find_child("TutorialOverlay", true, false) as TutorialOverlay

func rect_of(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)

func click(point: Vector2, wheel: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point; motion.global_position = point
	viewport.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.global_position = point
		event.button_index = wheel; event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and wheel == MOUSE_BUTTON_LEFT else 0
		viewport.push_input(event, true)

func press(control: Control) -> bool:
	if not check(is_instance_valid(control) and control.is_visible_in_tree(), "pressed control is visible"): return false
	if control is BaseButton and not check(not control.disabled, "%s is enabled" % control.name): return false
	var point := rect_of(control).get_center()
	if not check(viewport.get_visible_rect().has_point(point), "%s is inside the viewport" % control.name): return false
	var view := overlay_now()
	if is_instance_valid(view) and not view.is_ancestor_of(control):
		var hole: Rect2 = view.get_global_transform_with_canvas() * view.highlight_rect()
		if not check(hole.has_point(point), "%s is reachable through its highlight" % control.name): return false
	click(point)
	return true

func reveal(tree: SceneTree, control: Control) -> bool:
	# v0.104: New Campaign can be taller than the window; scroll the offer into view through UI input.
	if not check(is_instance_valid(control) and control.is_visible_in_tree(), "scroll target exists and is visible"): return false
	for i in 24:
		var area := viewport.get_visible_rect()
		if area.encloses(rect_of(control)): return true
		click(area.get_center(), MOUSE_BUTTON_WHEEL_UP if rect_of(control).get_center().y < area.get_center().y else MOUSE_BUTTON_WHEEL_DOWN)
		await frames(tree, 2)
	return check(false, "scroll reaches " + String(control.name))

func key(code: int, unicode: int = 0, control: bool = false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.unicode = unicode; event.ctrl_pressed = control; event.pressed = down
		viewport.push_input(event, true)

func amount(input: SpinBox, value: int) -> bool:
	if not check(is_instance_valid(input), "amount SpinBox exists"): return false # v0.104: missing controls fail explicitly.
	if not press(input.get_line_edit()): return false
	# Clear the field with real End + Backspace presses (Ctrl+A alone did not select the text headless).
	key(KEY_END)
	for i in input.get_line_edit().text.length() + 2:
		key(KEY_BACKSPACE)
	var digits := str(value)
	for i in digits.length():
		key(KEY_0 + int(digits[i]), digits.unicode_at(i))
	key(KEY_ENTER)
	await input.get_tree().process_frame # SpinBox applies submitted text after the event; let it settle.
	if not is_equal_approx(input.value, float(value)):
		print("v0.104 note: ", input.name, " did not apply on Enter; trying Tab")
		key(KEY_TAB) # leaving the field also applies its text
		await input.get_tree().process_frame
	if not is_equal_approx(input.value, float(value)):
		print("v0.104 amount diagnostics: ", input.name, " value=", input.value, " text='", input.get_line_edit().text, "' focus=", input.get_line_edit().has_focus(), " editable=", input.editable, " max=", input.max_value)
	return check(is_equal_approx(input.value, float(value)), "%s accepts real keyboard input" % input.name)

func shot(tree: SceneTree, id: String, index: int) -> void:
	if capture_dir == "" or captured.has(id): return
	await frames(tree, 2)
	await RenderingServer.frame_post_draw
	var picture: Image = viewport.get_texture().get_image()
	var file := capture_dir.path_join("%02d_%s.png" % [index + 1, id])
	if check(picture != null and not picture.is_empty(), "capture has rendered pixels for " + id):
		check(picture.save_png(file) == OK, "capture saved " + id)
	captured[id] = true

func step(tree: SceneTree, id: String) -> TutorialOverlay:
	var limit := Time.get_ticks_msec() + 3000
	var view: TutorialOverlay = null
	while Time.get_ticks_msec() < limit:
		view = overlay_now()
		if is_instance_valid(view) and view.is_node_ready() and String(view.tutorial.current().get("id", "")) == id and view.highlight_rect().has_area() and not tree.paused and Game.get("_save_capture") == null:
			break
		await tree.process_frame
	if not check(is_instance_valid(view) and view.is_node_ready(), "overlay exists for " + id): return null
	if not check(String(view.tutorial.current().get("id", "")) == id, "chapter reaches " + id): return null
	await frames(tree)
	var target: Control = view.current_target()
	if not check(is_instance_valid(target) and target.is_visible_in_tree(), "target exists for " + id): return null
	var hole := view.highlight_rect()
	var local: Rect2 = view.get_global_transform_with_canvas().affine_inverse() * rect_of(target)
	if not check(hole.has_area() and hole.intersects(local) and Rect2(Vector2.ZERO, view.size).encloses(hole), "highlight is on screen and matches " + id): return null
	var box := view.get("_box") as Control
	if not check(box != null and not Rect2(box.position, box.size).intersects(hole), "text leaves the target reachable for " + id): return null
	for blocker in view.blocker_rects():
		var dim_rect: Rect2 = blocker
		if not check(not dim_rect.intersects(hole), "dim leaves the target open for " + id): return null
	if target is BaseButton and not check(not target.disabled, "target is enabled for " + id): return null
	var next := view.find_child("TutorialNext", true, false) as Button
	if not check(next != null and next.disabled == (view.tutorial.done_kind() != "next"), "action gate matches data for " + id): return null
	await shot(tree, id, view.tutorial.index)
	visited[id] = true # v0.104: include every conditional step actually exercised.
	return view

func row(tree: SceneTree, uid: String) -> Button:
	var list := main.current.find_child("OnboardingRows", true, false) as Control
	if not check(is_instance_valid(list), "native onboarding list exists"): return null # v0.104: no missing-node skips.
	var button: Button = null
	for child in list.get_children():
		if child is Button and String(child.get_meta("onboarding_uid", "")) == uid:
			button = child
	if not check(button != null, "requested native row is on the first page: " + uid): return null
	# v0.104: scroll with real UI events, rather than altering scroll offsets through the test.
	for i in 16:
		var view := overlay_now()
		if not check(is_instance_valid(view), "chapter overlay exists while scrolling rows"): return null
		var hole: Rect2 = view.get_global_transform_with_canvas() * view.highlight_rect()
		if hole.encloses(rect_of(button)): return button
		click(hole.get_center(), MOUSE_BUTTON_WHEEL_UP if rect_of(button).get_center().y < hole.get_center().y else MOUSE_BUTTON_WHEEL_DOWN)
		await frames(tree, 2)
	check(false, "native row can be reached by scrolling: " + uid)
	return null

# v0.104: follow the checkbox -> CreateWorld -> presim -> new_game_begin path with actual viewport input.
func create_world(tree: SceneTree, guided: bool, finish_history: bool) -> bool:
	var offer := main.current.find_child("ChapterOneGuide", true, false) as CheckButton
	if not check(offer != null and offer.button_pressed == guided, "CreateWorld uses the visible guide choice"): return false
	if not check(String(main.current.get("size_key")) == "normal" and int(main.current.get("history_days")) == 1, "CreateWorld uses Normal / one-day options"): return false
	var create := main.current.find_child("CreateWorld", true, false) as Button
	if not await reveal(tree, create): return false
	if not press(create): return false
	if not check(Game._active_screen == "presim" and bool(Game.screen_params.get("new_world", false)), "CreateWorld opens native world generation"): return false
	var presim := main.current as Control
	if not check(presim != null and not bool(presim.get("generation_started")), "presim exists before generation starts"): return false
	if not check(bool(Game.setting("tutorial_chapter_requested")) == guided, "CreateWorld forwards the checkbox into the pending request"): return false
	presim.set("generation_seed", 4242) # v0.104: fix only the seed; native generation/history/flag handling remain untouched.
	var limit := Time.get_ticks_msec() + 40000
	while is_instance_valid(presim) and not bool(presim.get("generation_started")) and Time.get_ticks_msec() < limit:
		await tree.process_frame
	if not check(is_instance_valid(presim) and bool(presim.get("generation_started")), "presim calls native new_game_begin"): return false
	if not check(Game.seed_value == 4242 and Game.tutorial_chapter == guided and Game.tutorial_step == 0 and not Game.tutorial_done, "native world initialization applies the chosen chapter flag"): return false
	if not check(not bool(Game.setting("tutorial_chapter_requested")), "native initialization consumes the one-shot guide request"): return false
	if not finish_history:
		presim.set_process(false) # v0.104: cancel the declined startup before generating a second complete world.
		return check(not Game.tutorial_chapter and overlay_now() == null, "declining the guide leaves initialization unmounted")
	var skipped_reveal := false
	while Game._active_screen == "presim" and Time.get_ticks_msec() < limit:
		if not is_instance_valid(presim): return check(false, "presim remains present until its native handoff")
		if String(presim.get("phase")) == "build" and not skipped_reveal:
			if not press(presim.get("skip_btn") as Button): return false
			skipped_reveal = true
		await tree.process_frame
	if not check(Game._active_screen == "house_select", "presim finishes and opens the real household chooser within 40 seconds"): return false
	if not check(CampaignWorld.presim_total(Game) == 1 and CampaignWorld.presim_left(Game) == 0 and bool(Game.world.get("presim", {}).get("finished", false)) and Game.day == 1.0, "the real one-day history completed"): return false
	return check(Game.tutorial_chapter and not Game.tutorial_done, "the selected chapter flag survives presim's handoff")

# v0.104: select an actual first-page household; do not clear debt or release serving adults.
var _pick_diag: Array = [] # diagnostics only: why candidate houses were not picked

func eligible_house(house: Dictionary, small_house: bool) -> bool:
	if bool(house["holds_office"]) == small_house or int(house["leader_age"]) < int(People.ages(String(house["leader_race"]))["adult"]):
		return false
	var account: Dictionary = Dynasty._household(Game, String(house["household_uid"]))
	var family: Dictionary = account.get("family", {})
	if small_house and (family.is_empty() or bool(family.get("destitute", false)) or family.has("estate") or int(family.get("ln", {}).get("miss", 0)) != 0 or float(family.get("debt", 0.0)) >= 60.0 * TownEcon.COIN):
		_pick_diag.append({"uid": house["household_uid"], "why": "family", "empty": family.is_empty(), "destitute": family.get("destitute", false), "estate": family.has("estate"), "debt": family.get("debt", 0.0)})
		return false
	return feasible_house(house, small_house)

func feasible_house(house: Dictionary, small_house: bool) -> bool:
	# v0.104: prospective native quotes only; Begin and every committed order still use viewport input.
	# A shallow world/party shell supplies the candidate's REAL identity and location for the pure quote gates.
	# No purse/debt/treasury/stock/service or office record is changed, even during this synchronous preview.
	var live_world: Dictionary = Game.world
	var live_location: String = Game.location
	var preview: Dictionary = live_world.duplicate()
	var party: Dictionary = live_world["party"].duplicate()
	var home: String = String(house["town_id"])
	party["pos"] = live_world["towns"][home]["pos"]
	preview["party"] = party
	preview["player_house"] = {"town_id": home, "household_uid": house["household_uid"],
		"house_uid": house["house_uid"], "ruler_uid": house["leader_uid"]}
	Game.world = preview
	Game.location = home
	var quote: Dictionary = Mobilization.quote(Game, home, 1)
	var terms: Dictionary = Mobilization.borrow_quote(Game)
	Game.world = live_world
	Game.location = live_location
	Dynasty.note_households_changed() # v0.104: never retain an index owned by the prospective world shell.
	var shortfall: int = int(quote.get("required_funding", 0))
	var supplied: bool = not bool(quote.get("ok", true)) and shortfall > 0 \
		and int(quote.get("eligible", 0)) >= 2 and int(quote.get("kit_available", 0)) > 0 \
		and int(quote.get("food_available", 0)) >= Mobilization.MEALS
	_pick_diag.append({"uid": house["household_uid"], "ok": quote.get("ok"), "short": shortfall, "eligible": quote.get("eligible"), "kit": quote.get("kit_available"), "food": quote.get("food_available"), "reason": str(quote.get("reason", quote.get("text", ""))).left(80), "loan_ok": terms.get("ok"), "max_borrow": terms.get("max_borrow"), "purse": house.get("house_purse")})
	if not supplied: return false
	if small_house:
		return bool(terms.get("ok", false)) and int(floor(float(terms.get("max_borrow", 0.0)))) >= shortfall
	return int(floor(float(house.get("house_purse", 0.0)))) >= shortfall

func loan_state() -> Dictionary:
	return _same_numbers(_loan_state_raw())

func _loan_state_raw() -> Dictionary:
	# v0.104: deep copies of the real receipt, debt and event; no call to a loan command.
	var uid := String(Dynasty.selected(Game).get("household_uid", ""))
	var account := Dynasty._household(Game, uid)
	var family: Dictionary = account.get("family", {})
	var town: Dictionary = account.get("town", {})
	return {"household_uid": uid, "purse": float(family.get("purse", 0.0)),
		"debt": float(family.get("debt", 0.0)), "loan_day": float(family.get("loan_day", -1.0)),
		"ln": family.get("ln", {}).duplicate(true), "events": family.get("ev", []).duplicate(true),
		"town_lent": float(town.get("econ", {}).get("stats", {}).get("lent", 0.0)),
		"accounts": Dynasty.accounts(Game)}

# v0.104: compare chapter-relevant native state, including identities, all four purses, food and the route.
# Whole-number floats become ints, recursively, so a JSON round trip compares equal by value.
func _same_numbers(v: Variant) -> Variant:
	if v is float and is_finite(v) and v == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	if v is Dictionary:
		var out: Dictionary = {}
		for k: Variant in v:
			out[_same_numbers(k)] = _same_numbers(v[k])
		return out
	if v is Array:
		var arr: Array = []
		for e: Variant in v:
			arr.append(_same_numbers(e))
		return arr
	return v

func chapter_state() -> Dictionary:
	return _same_numbers(_chapter_state_raw())

func _chapter_state_raw() -> Dictionary:
	return {"seed": Game.seed_value, "rng": str(Game.rng.state), "day": Game.day, "location": Game.location,
		"house": Dynasty.selected(Game), "accounts": Dynasty.accounts(Game), "loan": loan_state(), "rep": Game.rep.duplicate(true),
		"company": Game.company.map(func(unit): return unit.to_dict()), "stash": Game.stash.map(func(item): return item.to_dict()),
		"provisions": Food.stock_to_save(Game), "rations": Game.rations.duplicate(true), "food_clock": Game.food_clock.duplicate(true),
		"party": Game.world.get("party", {}).duplicate(true)}

func reload_chapter(tree: SceneTree, expected_id: String, sliced: bool = false) -> TutorialOverlay:
	var view := overlay_now()
	if not check(is_instance_valid(view) and view.tutorial != null, "mid-chapter overlay exists before saving"): return null
	var saved_id := String(view.tutorial.current().get("id", ""))
	var saved_index := Game.tutorial_step
	var before: Dictionary = chapter_state()
	Game.wait_save()
	# v0.104: save_game() returns nothing on main; one fresh successful receipt plus the on-disk tutorial object prove this checkpoint.
	var completed_before: int = int(Game.save_stats()["completed"])
	var started_before: int = int(Game.save_stats()["started"])
	if sliced:
		if not check(Game.world["towns"].size() > 8, "native campaign reaches the real sliced writer"): return null
		Game.save_game_async(true)
		if not check(Game.get("_save_capture") != null, "async save actually starts a bounded capture"): return null
		var capture_limit: int = Time.get_ticks_msec() + 10000
		while Game.get("_save_capture") != null and Time.get_ticks_msec() < capture_limit:
			await tree.process_frame # v0.104: exercise process slices; wait_save() must not drain the capture atomically.
		if not check(Game.get("_save_capture") == null, "process slices finish the native capture"): return null
		Game.wait_save(false)
		if not check(int(Game.save_stats()["started"]) == started_before + 1 and int(Game.save_stats()["capture_slices"]) > 1, "one multi-slice capture supplies this checkpoint"): return null
	else:
		Game.save_game()
	Game.wait_save(false)
	var stats: Dictionary = Game.save_stats()
	if not check(bool(stats.get("last_ok", false)) and int(stats["completed"]) == completed_before + 1, "mid-chapter save receives one new successful receipt"): return null
	var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	if not check(payload is Dictionary, "chapter checkpoint contains a readable root object"): return null
	var progress: Variant = payload.get("tutorial")
	if not check(progress is Dictionary, "chapter checkpoint retains the tutorial object"): return null
	if not check(bool(progress.get("chapter_one", false)) and int(progress.get("step", -1)) == saved_index and not bool(progress.get("done", true)), "both payload paths keep the exact opted-in chapter and step"): return null
	# v0.104: retire the old overlay so a live engine cannot mask broken save/resume state.
	main.current.queue_free()
	main.set("current", null)
	await frames(tree, 2)
	Game.tutorial_chapter = false; Game.tutorial_step = 0; Game.tutorial_done = true
	Game.world = {}; Game.company = []; Game.stash = []; Game.rep = {}; Game.gold = -1; Game.day = -1.0; Game.location = ""
	Game.provisions = {}; Game.rations = {}; Game.food_clock = {}
	if not check(Game.load_game(), "mid-chapter save reloads through the native loader"): return null
	if not check(Game.tutorial_chapter and not Game.tutorial_done and Game.tutorial_step == saved_index, "chapter opt-in and the exact saved step survive load"): return null
	# JSON saves turn whole numbers into floats (-40 -> -40.0); compare values, not int/float type.
	var after_load: Dictionary = _same_numbers(chapter_state())
	before = _same_numbers(before)
	if after_load != before:
		for k: String in before:
			if str(before[k]) != str(after_load.get(k)):
				print("v0.104 reload diff [", k, "]: before=", str(before[k]).left(500), " after=", str(after_load.get(k)).left(500))
	if not check(after_load == before, "reload restores the same house, money, people, food, clock, RNG and route"): return null
	Game.goto("house", {"back": "map"}) # v0.104: deferred chapter resume must restore its own muster host.
	view = await step(tree, expected_id)
	if view == null: return null
	var resumed: Dictionary = chapter_state()
	for k: String in before:
		if str(before[k]) != str(resumed.get(k)):
			print("v0.104 resume diff [", k, "]: before=", str(before[k]).left(400), " after=", str(resumed.get(k)).left(400))
	if not check(resumed == before, "resuming the chapter neither replays an order nor changes native state"): return null
	if saved_id == expected_id and not check(view.tutorial.index == saved_index and Game.tutorial_step == saved_index, "a stable mid-chapter step resumes at the exact same index"): return null
	return view

func finish(tree: SceneTree) -> int:
	running = false
	Game.wait_save()
	Game.reset_tutorial_progress() # v0.104: stop deferred chapter resumes before retiring the test screen.
	if is_instance_valid(main): main.queue_free()
	await frames(tree, 2)
	Game.reset_tutorial_progress() # v0.104: teardown callbacks cannot leave progress for the next same-process test.
	Game.main = old_main; Game._active_screen = old_screen; Game.screen_params = old_params
	Game.settings = old_settings
	Game.settings["tutorial_chapter_requested"] = false # v0.104: never restore a stale one-shot guide request.
	UiTheme.set_mobile_override(null)
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	check(seconds < 60.0, "whole chapter meets the under-60-second block target")
	print("test_tutorial_chapter_v104: %d checks, %d failures, %.2f s; %d screenshots" % [checks, fails, seconds, captured.size()])
	return fails

func run(tree: SceneTree) -> int:
	started = Time.get_ticks_msec(); running = true
	old_main = Game.main; old_screen = Game._active_screen; old_params = Game.screen_params.duplicate(true); old_settings = Game.settings.duplicate(true)
	Game.reset_tutorial_progress() # v0.104: begin independently of the previous test's chapter/step/done.
	Game.settings["tutorial_chapter_requested"] = false
	var watchdog := tree.create_timer(120.0, true, false, true)
	watchdog.timeout.connect(func():
		if running:
			printerr("FAIL v0.104: internal 120-second watchdog")
			Game.reset_tutorial_progress() # v0.104: the timeout failure also clears tutorial state before exit.
			Game.settings["tutorial_chapter_requested"] = false
			tree.quit(124))
	viewport = tree.root
	UiTheme.set_mobile_override(false)
	Game.settings["tutorial_offered"] = false
	Game.settings["tutorial_chapter_requested"] = true # v0.104: an unchecked CreateWorld must replace a stale pending choice.
	Game.settings["music_volume"] = 0.0; Game.settings["sfx_volume"] = 0.0
	Game.settings["creatures_enabled"] = false; Game.settings["steppe_enabled"] = false; Game.settings["sickness_deadliness"] = 1.0
	WorldGen.gen_size = WorldGen.WORLD_SIZE; CampaignWorld.presim_span_days = CampaignWorld.PRESIM_DEFAULT_DAYS
	if capture_dir != "":
		if not check(DisplayServer.get_name() != "headless", "screenshot capture requires the separate windowed run"): return await finish(tree)
		if not check(DirAccess.make_dir_recursive_absolute(capture_dir) == OK, "capture output directory exists"): return await finish(tree)
	main = ChapterMain.new()
	tree.root.add_child.call_deferred(main)
	await frames(tree)
	Game.goto("newgame")
	await frames(tree)
	var offer := main.current.find_child("ChapterOneGuide", true, false) as CheckButton
	if not check(offer != null and offer.button_pressed, "first New Campaign offers the chapter selected"): return await finish(tree)
	if not await reveal(tree, offer): return await finish(tree)
	if not press(offer): return await finish(tree)
	if not check(not offer.button_pressed, "the guide can be declined using real UI input"): return await finish(tree)
	if not press(offer): return await finish(tree)
	if not check(offer.button_pressed, "the guide can be selected again"): return await finish(tree)
	if not press(offer): return await finish(tree)
	if not await create_world(tree, false, false): return await finish(tree)
	if not check(bool(Game.setting("tutorial_offered")), "CreateWorld records the first-campaign offer"): return await finish(tree)
	Game.goto("newgame")
	await frames(tree)
	offer = main.current.find_child("ChapterOneGuide", true, false) as CheckButton
	if not check(offer != null and not offer.button_pressed, "later new campaigns do not select the guide automatically"): return await finish(tree)
	Game.goto("settings", {"back": "title"})
	await frames(tree)
	if not press(main.current.find_child("ReplayTutorial", true, false) as Button): return await finish(tree)
	await frames(tree)
	offer = main.current.find_child("ChapterOneGuide", true, false) as CheckButton
	if not check(Game._active_screen == "newgame" and offer != null and offer.button_pressed, "Replay opens New Campaign with its guide selected"): return await finish(tree)
	if not await create_world(tree, true, true): return await finish(tree)
	if not check(Game.world.get("player_house", {}).is_empty() and Game.company.is_empty() and Game.gold == 0, "fresh generated campaign is before house selection, funding and muster"): return await finish(tree)
	var args := OS.get_cmdline_user_args()
	if not check(not (args.has("--small-house") and args.has("--ruling-house")), "choose exactly one chapter route"): return await finish(tree)
	var small_house := not args.has("--ruling-house") # v0.104: the default block now exercises borrowing.
	print("v0.104 UI route: ", "zero-purse non-ruling household via native borrowing" if small_house else "explicit ruling-house control")
	var view := await step(tree, "choose_settlement")
	if view == null: return await finish(tree)
	var towns: Array = main.current.get("settlement_rows")
	if not check(not towns.is_empty(), "fresh world has selectable settlements"): return await finish(tree)
	var home := ""
	var household := ""
	var most_people := -1
	# The fresh world's first save may still be capturing; quotes refuse until it finishes.
	Game.wait_save()
	# v0.104: use the same visible house page for suitability and the real row click.
	for town: Dictionary in towns.slice(0, HouseSelectView.PAGE_SIZE):
		var local_houses := HouseOnboarding.houses(Game, String(town["town_id"]))
		for candidate: Dictionary in local_houses.slice(0, HouseSelectView.PAGE_SIZE):
			if eligible_house(candidate, small_house) and int(town["population"]) > most_people:
				home = String(town["town_id"]); household = String(candidate["household_uid"])
				most_people = int(town["population"])
				break
	if home == "":
		print("v0.104 house pick diagnostics (first 12): ", _pick_diag.slice(0, 12))
	if not check(home != "" and household != "", "visible native rows contain the requested adult-led household"): return await finish(tree)
	if small_house:
		# v0.104: disclosed hardship fixture only. No grant, treasury top-up, debt clearing or stock/service edits.
		var account := Dynasty._household(Game, household)
		if not check(not account.is_empty(), "chosen hardship household has a real private account"): return await finish(tree)
		var family: Dictionary = account["family"]
		print("v0.104 hardship fixture: reduce native House purse from ", float(family["purse"]), " to 0 before selection")
		family["purse"] = 0.0
	var town_button := await row(tree, home)
	if town_button == null or not press(town_button): return await finish(tree)
	view = await step(tree, "settlement_continue")
	if view == null or not press(view.current_target()): return await finish(tree)
	view = await step(tree, "choose_house")
	if view == null: return await finish(tree)
	var houses: Array = main.current.get("house_rows")
	if not check(houses.slice(0, HouseSelectView.PAGE_SIZE).any(func(candidate): return String(candidate["household_uid"]) == household and eligible_house(candidate, small_house)), "the requested real household remains on the visible page"): return await finish(tree)
	var house_button := await row(tree, household)
	if house_button == null or not press(house_button): return await finish(tree)
	view = await step(tree, "customize_ruler")
	if view == null: return await finish(tree)
	for stage_index in [HouseSelectView.STAGE_CUSTOM, HouseSelectView.STAGE_DESIGN, HouseSelectView.STAGE_REVIEW]:
		if not press(main.current.get("next_button") as Button): return await finish(tree)
		await frames(tree)
		if not check(int(main.current.get("stage")) == stage_index, "real Continue/Review reaches native stage %d" % stage_index): return await finish(tree)
		if stage_index != HouseSelectView.STAGE_REVIEW: await shot(tree, "draft_stage_%d" % stage_index, 3)
	view = await step(tree, "begin_house")
	if view == null or not press(view.current_target()): return await finish(tree)
	view = await step(tree, "read_purse")
	if view == null: return await finish(tree)
	if not check(Game.company.is_empty() and Game.gold == 0 and String(Dynasty.selected(Game).get("household_uid", "")) == household, "Begin selects the real household without funding or raising"): return await finish(tree)
	if not check(Dynasty.holds_office(Game) != small_house, "selection keeps the household's actual authority"): return await finish(tree)
	if not check(Game.location == home and String(Game.world.get("start_town", "")) == home and Mobilization._here(Game, home), "Begin places the real party at the selected home"): return await finish(tree)
	if small_house:
		if not check(float(Dynasty.accounts(Game)["house_purse"]) == 0.0 and Feudal.can_act_household(Game, home) and not Feudal.can_act(Game, home), "zero-purse household has private Army authority and no settlement office"): return await finish(tree)
	if not press(view.find_child("TutorialNext", true, false) as Button): return await finish(tree)
	view = await step(tree, "find_men")
	if view == null or not press(view.current_target()): return await finish(tree)
	view = await step(tree, "choose_men")
	if view == null: return await finish(tree)
	if not check(bool(Mobilization.status(Game).get("can_act", false)), "v0.102 private household can muster at home"): return await finish(tree)
	# v0.104: editing away from the default and back makes ignored keyboard events fail.
	var count := main.current.get("count_input") as SpinBox
	if not check(count != null and count.max_value >= 2.0, "muster count can be keyboard-edited away from the default"): return await finish(tree) # v0.104: fail on a bad fixture.
	if not await amount(count, 2): return await finish(tree)
	if not await amount(count, 1): return await finish(tree)
	if not press(view.find_child("TutorialNext", true, false) as Button): return await finish(tree)
	var loan_after: Dictionary = {}
	if small_house:
		var unfunded := Mobilization.quote(Game, home, 1)
		var shortfall := int(unfunded.get("required_funding", 0))
		if not check(not bool(unfunded.get("ok", true)) and shortfall > 0 and int(unfunded.get("eligible", 0)) > 0 and int(unfunded.get("kit_available", 0)) > 0 and int(unfunded.get("food_available", 0)) >= Mobilization.MEALS, "real zero-purse route is blocked by Army coin, with native people, kit and deployment food"): return await finish(tree)
		var loan_before := loan_state()
		var terms := Mobilization.borrow_quote(Game)
		var requested := mini(int(floor(float(terms.get("max_borrow", 0.0)))), maxi(shortfall * 2, 100))
		if not check(bool(terms.get("ok", false)) and requested >= shortfall, "existing credit and treasury cover a real one-soldier loan"): return await finish(tree)
		view = await step(tree, "borrow_coin")
		if view == null or not press(view.current_target()): return await finish(tree)
		view = await step(tree, "confirm_borrow")
		if view == null: return await finish(tree)
		if not check(not bool(view.state_of.call("funding_review")) and main.current.find_child("MusterReview", true, false) == null, "native borrowing form cannot satisfy an Army-transfer review"): return await finish(tree)
		if not await amount(main.current.find_child("MusterBorrowAmount", true, false) as SpinBox, requested): return await finish(tree)
		if not check(loan_state() == loan_before and Game.gold == 0, "opening and editing the loan records no debt and moves no coin"): return await finish(tree)
		if not press(main.current.find_child("MusterBorrowCancel", true, false) as Button): return await finish(tree)
		view = await step(tree, "borrow_coin")
		if view == null: return await finish(tree)
		if not check(loan_state() == loan_before and main.current.find_child("MusterBorrowReview", true, false) == null, "native Cancel closes the loan without side effects"): return await finish(tree)
		if not press(view.current_target()): return await finish(tree)
		view = await step(tree, "confirm_borrow")
		if view == null or not press(view.find_child("TutorialBack", true, false) as Button): return await finish(tree)
		view = await step(tree, "borrow_coin")
		if view == null: return await finish(tree)
		if not check(loan_state() == loan_before and main.current.find_child("MusterBorrowReview", true, false) == null, "chapter Back cancels the loan draft without borrowing"): return await finish(tree)
		if not press(view.current_target()): return await finish(tree)
		view = await step(tree, "confirm_borrow")
		if view == null: return await finish(tree)
		view = await reload_chapter(tree, "borrow_coin", true) # v0.104: unsaved loan drafts restart before the Borrow button.
		if view == null: return await finish(tree)
		if not check(loan_state() == loan_before and main.current.find_child("MusterBorrowReview", true, false) == null, "reload neither borrows nor recreates an unconfirmed loan modal"): return await finish(tree)
		if not press(view.current_target()): return await finish(tree)
		view = await step(tree, "confirm_borrow")
		if view == null: return await finish(tree)
		if not await amount(main.current.find_child("MusterBorrowAmount", true, false) as SpinBox, requested): return await finish(tree)
		if not press(main.current.find_child("MusterBorrowConfirm", true, false) as Button): return await finish(tree)
		view = await step(tree, "fund_army")
		if view == null: return await finish(tree)
		loan_after = loan_state()
		if not check(loan_after["household_uid"] == household and is_equal_approx(float(loan_after["purse"]), float(loan_before["purse"]) + requested) and is_equal_approx(float(loan_after["debt"]), float(loan_before["debt"]) + requested), "Borrow credits the selected House purse and records its exact new debt"): return await finish(tree)
		if not check(is_equal_approx(float(loan_after["ln"].get("lent", 0.0)), float(loan_before["ln"].get("lent", 0.0)) + requested) and is_equal_approx(float(loan_after["town_lent"]), float(loan_before["town_lent"]) + requested) and float(loan_after["ln"].get("pay", 0.0)) > 0.0 and is_equal_approx(float(loan_after["ln"].get("rate", -1.0)), float(terms["rate"])), "native family/town loan receipts, instalment and weekly rate are recorded"): return await finish(tree)
		var events: Array = loan_after["events"]
		if not check(not events.is_empty() and events.back().size() >= 3 and events.back()[1] == "borrow" and int(events.back()[2]) == requested, "the native household history records the actual loan"): return await finish(tree)
		if not check(is_equal_approx(float(loan_after["accounts"]["city_treasury"]), float(loan_before["accounts"]["city_treasury"]) - requested) and loan_after["accounts"]["faction_treasury"] == loan_before["accounts"]["faction_treasury"] and Game.gold == 0 and Game.company.is_empty(), "loan debits only the lending treasury and leaves Army funds and troops empty"): return await finish(tree)
		if not check(not bool(Mobilization.quote(Game, home, 1).get("ok", true)) and not bool(view.state_of.call("army_funded")), "borrowed House coin still cannot muster or complete an unreviewed Army transfer"): return await finish(tree)
		var back_button := view.find_child("TutorialBack", true, false) as Button
		if not check(back_button != null and not back_button.disabled, "Back remains available after the committed loan"): return await finish(tree)
		if not press(back_button): return await finish(tree)
		view = await step(tree, "fund_army")
		if view == null: return await finish(tree)
		if not check(loan_state() == loan_after, "Back cannot undo or replay the committed loan"): return await finish(tree)
	else:
		if not check(not TutorialChapter.borrowing_needed(), "explicit ruling-house control covers the shortfall without a loan"): return await finish(tree)
	view = await step(tree, "fund_army")
	if view == null: return await finish(tree)
	var source := Mobilization.status(Game)
	if not check(String(source["payer_household_uid"]) == household, "the selected native household owns the funding purse"): return await finish(tree)
	var accounts_before := Dynasty.accounts(Game)
	var purse_before := float(source["payer_purse"])
	var quote := Mobilization.quote(Game, home, 1)
	var needed := maxi(1, int(quote.get("required_funding", 0)))
	var transfer := mini(int(floor(purse_before)), maxi(needed * 2, 100))
	if not check(transfer >= needed, "the actual house purse can fund one soldier"): return await finish(tree)
	if not await amount(main.current.get("fund_input") as SpinBox, transfer): return await finish(tree)
	if not press(main.current.get("fund_button") as Button): return await finish(tree)
	view = await step(tree, "confirm_funding")
	if view == null: return await finish(tree)
	if not check(Game.gold == 0, "reviewing the transfer moves no money"): return await finish(tree)
	if not press(view.find_child("TutorialBack", true, false) as Button): return await finish(tree)
	view = await step(tree, "fund_army")
	if view == null: return await finish(tree)
	if not check(main.current.find_child("MusterReview", true, false) == null and Game.gold == 0, "Back closes the review without transferring coin"): return await finish(tree)
	if not press(main.current.get("fund_button") as Button): return await finish(tree)
	view = await step(tree, "confirm_funding")
	if view == null: return await finish(tree)
	view = await reload_chapter(tree, "fund_army", true) # v0.104: an uncommitted modal resumes at its editable boundary.
	if view == null: return await finish(tree)
	if not check(Game.gold == 0 and main.current.find_child("MusterReview", true, false) == null, "reloading a funding review neither transfers coin nor restores a dead modal"): return await finish(tree)
	if not await amount(main.current.get("fund_input") as SpinBox, transfer): return await finish(tree)
	if not press(main.current.get("fund_button") as Button): return await finish(tree)
	view = await step(tree, "confirm_funding")
	if view == null or not press(view.current_target()): return await finish(tree)
	view = await step(tree, "raise_army")
	if view == null: return await finish(tree)
	if not check(Game.gold == transfer and is_equal_approx(float(Mobilization.status(Game)["payer_purse"]), purse_before - transfer), "real transfer debits the owner and credits the army exactly once"): return await finish(tree)
	var accounts_after := Dynasty.accounts(Game)
	if not check(accounts_after["city_treasury"] == accounts_before["city_treasury"] and accounts_after["faction_treasury"] == accounts_before["faction_treasury"], "funding leaves city and faction treasuries with their owners"): return await finish(tree)
	view = await reload_chapter(tree, "raise_army") # v0.104: save/load/resume at the SAME funded step and native state.
	if view == null: return await finish(tree)
	if not check(view.state_of.is_valid() and not bool(view.state_of.call("army_funded")), "existing saved coin cannot complete an unreviewed transfer"): return await finish(tree)
	quote = Mobilization.quote(Game, home, 1)
	var meals_before := Food.stock(Game, "meal") # v0.104: assert the actual ration increment.
	if not check(bool(quote.get("ok", false)) and int(quote.get("planned", 0)) == 1, "one real equipped and supplied person can be raised"): return await finish(tree)
	if not press(view.current_target()): return await finish(tree)
	view = await step(tree, "confirm_muster")
	if view == null: return await finish(tree)
	if not check(Game.company.is_empty(), "reviewing raising creates no field soldiers"): return await finish(tree)
	if not press(view.current_target()): return await finish(tree)
	view = await step(tree, "return_house")
	if view == null: return await finish(tree)
	if not check(Game.company.size() == 1 and not Game.company[0].dead and Mobilization.manages(Game, Game.company[0]), "confirmation raises one living native registered person"): return await finish(tree)
	if not check(Game.gold == transfer - int(quote["raise_cost"]) and Food.stock(Game, "meal") == meals_before + int(quote["food_units"]) and Game.gold >= Game.daily_wages() * 3, "muster charges its exact quote, packs deployment meals and retains three days of pay"): return await finish(tree)
	var address := Mobilization._address(Game, Game.company[0])
	if not check(not address.is_empty() and String(address["person"][4]) == "company" and Game.company[0].home_town == home and Game.company[0].weapon() != null, "raised soldier retains a real home, person/service identity and serviceable weapon"): return await finish(tree)
	if small_house:
		var debt_now := loan_state()
		for k: String in ["debt", "ln", "town_lent"]:
			if str(debt_now[k]) != str(loan_after[k]):
				print("v0.104 loan diff [", k, "]: committed=", str(loan_after[k]).left(400), " now=", str(debt_now[k]).left(400))
		if not check(debt_now["debt"] == loan_after["debt"] and debt_now["ln"] == loan_after["ln"] and debt_now["town_lent"] == loan_after["town_lent"], "funding, both save/reloads and muster preserve the single committed loan"): return await finish(tree)
	if not press(view.current_target()): return await finish(tree)
	view = await step(tree, "open_map")
	if view == null or not press(view.current_target()): return await finish(tree)
	view = await step(tree, "march_nearby")
	if view == null: return await finish(tree)
	if not check(view.get_parent() == main.current.get("hud_root"), "map highlight uses its HUD canvas"): return await finish(tree)
	var destination := String(main.current.get("tutorial_town"))
	var tutorial: Tutorial = view.tutorial # v0.104: the overlay frees itself when the final action completes.
	if not check(destination != "" and destination != home, "march names a different reachable friendly town"): return await finish(tree)
	if not press(view.current_target()): return await finish(tree)
	var end_limit := Time.get_ticks_msec() + 3000
	while not Game.tutorial_done and Time.get_ticks_msec() < end_limit: await tree.process_frame
	if not check(Game.tutorial_done and tutorial.is_finished and not tutorial.was_skipped, "chapter completes through real UI input"): return await finish(tree)
	var expected := Tutorial.load_steps().map(func(item): return String(item["id"])) # v0.104: all 17 small-house states must be visited.
	if not small_house:
		expected.erase("borrow_coin"); expected.erase("confirm_borrow")
	if not check(expected.all(func(id): return visited.has(id)) and visited.size() == expected.size(), "walkthrough visits every required chapter highlight, including conditional borrowing"): return await finish(tree)
	if not check(Game.company.size() == 1 and CampaignWorld.is_travelling(Game) and String(Game.world["party"]["dest_town"]) == destination, "chapter ends with a raised army marching on a native route"): return await finish(tree)
	await frames(tree)
	check(overlay_now() == null, "completed overlay releases the campaign")
	return await finish(tree)
