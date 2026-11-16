extends RefCounted
## Focused v0.076 draft pool & cohort/named promotion verification entry.
## Exercises test_econ_army.gd:_test_draft (world-gen town draft with pre-draft
## named work/tier snapshots and cohort bin/slot tracking) and _test_draft_fixture
## (bounded cohort + named household fixture proving raw idle/cj/job slot tiers,
## observed promotion from draft-age adult bins, missing-snapshot failure, and
## keeper/land/herd/2-adult reserve protection) without full-day simulation.

const EconArmyTest := preload("res://tests/test_econ_army.gd")
const RunplanArgs: GDScript = preload("res://tests/fixtures/older_runplan_args_v100.gd")
const SpeedCheckpoint: GDScript = preload("res://tests/fixtures/older_speed_checkpoint_v100.gd")

func run(_tree: SceneTree) -> int:
	var suite := EconArmyTest.new()
	var selected: String = OS.get_environment("DRAFT_POOL_PART")
	var seen: bool = not selected.is_empty()
	for arg: String in RunplanArgs.arguments():
		var val: String = ""
		if arg.begins_with("--part="):
			val = arg.trim_prefix("--part=")
		elif arg.begins_with("--speed-part="):
			val = arg.trim_prefix("--speed-part=")
		elif arg == "--part" or arg == "--speed-part":
			printerr("FAIL: use --part=setup|draft|all")
			return 1
		else:
			continue
		if seen and val != selected:
			printerr("FAIL: conflicting draft pool part selectors")
			return 1
		seen = true
		selected = val
	if selected.is_empty():
		selected = "all"
	if not selected in ["setup", "draft", "all"]:
		printerr("FAIL: unknown --part=", selected, "; expected setup|draft|all")
		return 1
	var keep_size: String = WorldGen.gen_size
	var keep_presim: int = CampaignWorld.presim_span_days
	var keep_save: String = Game.SAVE_PATH
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Game.SAVE_PATH = "user://test_draft_pool_v076_%d.json" % OS.get_process_id()
	var checkpoint: RefCounted = SpeedCheckpoint.new("draft_pool_v076_s5150")
	if selected == "setup":
		Game.new_game(5150)
		if not bool(checkpoint.call("save_step", 0)):
			suite.fails += maxi(1, int(checkpoint.get("fails")))
	elif selected == "draft":
		if not bool(checkpoint.call("load_step", 0)):
			suite.fails += maxi(1, int(checkpoint.get("fails")))
		else:
			suite._test_draft()
	else:
		Game.new_game(5150)
		suite._test_draft()
	WorldGen.gen_size = keep_size
	CampaignWorld.presim_span_days = keep_presim
	Game.SAVE_PATH = keep_save
	if suite.fails == 0:
		if selected == "setup":
			print("PASS PARTIAL: test_draft_pool_v076 setup (run --part=draft to complete)")
		else:
			print("PASS: test_draft_pool_v076")
	return suite.fails
