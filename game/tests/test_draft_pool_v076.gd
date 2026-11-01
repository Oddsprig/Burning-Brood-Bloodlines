extends RefCounted
## Focused v0.076 draft pool & cohort/named promotion verification entry.
## Exercises test_econ_army.gd:_test_draft (world-gen town draft with pre-draft
## named work/tier snapshots and cohort bin/slot tracking) and _test_draft_fixture
## (bounded cohort + named household fixture proving raw idle/cj/job slot tiers,
## observed promotion from draft-age adult bins, missing-snapshot failure, and
## keeper/land/herd/2-adult reserve protection) without full-day simulation.

const EconArmyTest := preload("res://tests/test_econ_army.gd")

func run(_tree: SceneTree) -> int:
	var suite := EconArmyTest.new()
	Game.new_game(5150)
	suite._test_draft()
	if suite.fails == 0:
		print("PASS: test_draft_pool_v076")
	return suite.fails
