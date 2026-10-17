extends RefCounted
## Exact short-history selection, existing simulation paths, and save compatibility.

const Options := preload("res://ui/newgame.gd")
const Startup := preload("res://ui/presim.gd")
var fails := 0

class SpanFixture:
	extends RefCounted
	var world := {}

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", message)
	else:
		print("ok: ", message)

func run(tree: SceneTree) -> int:
	var previous_span := CampaignWorld.presim_span_days
	var previous_size := WorldGen.gen_size
	var previous_params := Game.screen_params
	check(previous_span == CampaignWorld.PRESIM_YEARS * CampaignWorld.PRESIM_YEAR_DAYS,
		"fresh default retains the existing five-year history")
	_test_span_config()
	await tree.process_frame
	_test_options(tree)
	_test_one_day()
	_test_saved_history()
	CampaignWorld.presim_span_days = previous_span
	WorldGen.gen_size = previous_size
	Game.screen_params = previous_params
	return fails

func _test_span_config() -> void:
	CampaignWorld.presim_span_days = 0
	check(CampaignWorld.presim_span_days == 1, "day span clamps to exactly one day")
	CampaignWorld.presim_span_days = 999999
	check(CampaignWorld.presim_span_days == 100 * CampaignWorld.PRESIM_YEAR_DAYS,
		"day span retains the existing 100-year maximum")
	CampaignWorld.presim_years = 5
	check(CampaignWorld.presim_span_days == 600 and CampaignWorld.presim_years == 5,
		"existing integer-year assignments still select exact whole years")
	check(CampaignWorld.presim_days(1) == 120 and CampaignWorld.presim_days(100) == 12000,
		"legacy years-to-days conversion retains its meaning")
	CampaignWorld.presim_span_days = 1
	var fixture := SpanFixture.new()
	check(CampaignWorld.presim_total(fixture) == 1 and CampaignWorld.presim_left(fixture) == 1,
		"a new history reads its exact selected one-day budget")
	check(is_equal_approx(CampaignWorld.presim_years_of(fixture), 1.0 / 120.0),
		"a one-day history is not rounded to one year")
	fixture.world["presim"] = {"total": 600, "done": 120}
	check(CampaignWorld.presim_total(fixture) == 600 and CampaignWorld.presim_left(fixture) == 480,
		"existing saved whole-year history overrides the next campaign's day selection")
	var previous := 0
	var monotone := true
	var reversible := true
	for index in range(Options.SLIDER_MAX + 1):
		var days := Options.span_days(index)
		monotone = monotone and days > previous
		reversible = reversible and Options.span_index(days) == index
		previous = days
	check(monotone and reversible, "each slider stop is increasing and round-trips without day truncation")
	check(Options.span_days(0) == 1 and Options.span_days(Options.SLIDER_MAX) == 12000,
		"slider spans one day through 100 years")
	for days in [1, 7, 30, 60, 90, 120, 600, 2400, 12000]:
		check(Options.span_days(Options.span_index(days)) == days, "exact short/long slider choice: %d days" % days)
	check(CampaignWorld.presim_span_text(1) == "1 day" and CampaignWorld.presim_span_text(7) == "7 days"
		and CampaignWorld.presim_span_text(120) == "1 year" and CampaignWorld.presim_span_text(121) == "1 year, 1 day",
		"duration labels use accurate day/year units")
	check(Startup.history_progress_text(0, 1, "Spring") == "Spring · 0 / 1 day"
		and Startup.history_progress_text(1, 1, "Spring") == "Spring · 1 / 1 day",
		"one-day progress counts completed days and never claims a year")
	check(Startup.history_progress_text(120, 600, "Spring").contains("120 / 600 days · 5 years"),
		"long-history progress retains exact total years and completed days")

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := _button(child, text)
		if found != null:
			return found
	return null

func _test_options(tree: SceneTree) -> void:
	CampaignWorld.presim_span_days = 1
	var screen := Options.new()
	screen.visible = false
	tree.root.add_child(screen)
	check(screen.history_days == 1 and screen.span_lbl.text == "1 day" and int(screen.slider.value) == 0,
		"options reopen at the exact selected one-day value")
	for preset in [["1 day", 1], ["1 week", 7], ["1 month", 30], ["1 year", 120], ["100 years", 12000]]:
		var button := _button(screen, String(preset[0]))
		check(button != null, "history preset is accessible: " + String(preset[0]))
		if button != null:
			button.pressed.emit()
			check(screen.history_days == int(preset[1]), "preset callback selects exact days: " + String(preset[0]))
	screen.slider.value = 0
	check(screen.history_days == 1 and screen.est.text.contains("simulate 1 day."),
		"slider minimum and startup explanation select one day")
	screen.call("_step_span", -1)
	check(screen.history_days == 1, "minus cannot shorten history below one day")
	screen.call("_step_span", 1)
	check(screen.history_days == 2, "plus steps short history by one day")
	screen.call("_set_days", 1)
	screen.call("_begin")
	check(CampaignWorld.presim_span_days == 1 and bool(Game.screen_params.get("new_world", false)),
		"Begin passes the exact one-day span into the existing new-world route")
	screen.free()

func _test_one_day() -> void:
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Game.new_game(9371)
	var initial_gold := Game.gold
	var ages := {}
	var births := {}
	for unit in Game.company:
		ages[unit.uid] = unit.age
		births[unit.uid] = unit.born
	var pending := {}
	var start := Time.get_ticks_msec()
	var slices := 0
	while CampaignWorld.presim_left(Game) > 0 and Time.get_ticks_msec() - start < 60000:
		CampaignWorld.presim_slice(Game, pending, 12000)
		slices += 1
	check(slices > 0 and pending.is_empty() and Game.day == 1.0
		and CampaignWorld.presim_total(Game) == 1 and CampaignWorld.presim_left(Game) == 0
		and int(Game.world.get("presim", {}).get("done", 0)) == 1,
		"real resumable history completes exactly one original simulation day")
	var before := Game.day
	CampaignWorld.presim_slice(Game, pending, 12000)
	CampaignWorld.presim_step(Game, 50)
	check(Game.day == before and pending.is_empty(), "completed one-day history cannot run an extra day")
	CampaignWorld.presim_finish(Game)
	var protected_company := Game.gold == initial_gold
	for unit in Game.company:
		protected_company = protected_company and unit.age == int(ages[unit.uid])
		if float(births[unit.uid]) > -1.0e8:
			protected_company = protected_company and is_equal_approx(unit.born, float(births[unit.uid]) + 1.0)
	check(protected_company and is_equal_approx(float(Game.food_clock.get("last", -1)), 1.0),
		"one-day arrival preserves company ages and coins and starts its food clock today")
	Game.save_game()
	CampaignWorld.presim_years = 100
	check(Game.load_game(), "completed one-day history saves and loads through the existing save format")
	check(Game.day == 1.0 and CampaignWorld.presim_total(Game) == 1
		and CampaignWorld.presim_left(Game) == 0 and bool(Game.world.get("presim", {}).get("finished", false)),
		"saved one-day history retains its exact total despite a different next-campaign selection")
	CampaignWorld.presim_step(Game, 1)
	check(Game.day == 1.0, "loading a finished short history never reruns it")

func _test_saved_history() -> void:
	# Preserve the existing day-based record from an older whole-year selection.
	Game.world["presim"] = {"total": 600, "done": 120, "from": 0.0}
	Game.day = 120.0
	Game.save_game()
	CampaignWorld.presim_span_days = 1
	check(Game.load_game() and CampaignWorld.presim_total(Game) == 600 and CampaignWorld.presim_left(Game) == 480,
		"loading an older whole-year record keeps its original day budget")
	# Worlds saved before startup history existed still do not start it on load.
	Game.world.erase("presim")
	Game.save_game()
	check(Game.load_game() and not Game.world.has("presim") and Game.day == 120.0,
		"loading a pre-history save does not create a new one-day history")
	# The atomic compatibility path initializes the selected span itself too.
	CampaignWorld.presim_span_days = 1
	check(CampaignWorld.presim_step(Game, 50) == 0 and Game.day == 121.0
		and CampaignWorld.presim_total(Game) == 1 and int(Game.world["presim"]["done"]) == 1,
		"atomic compatibility path clamps its work to the selected one day")
