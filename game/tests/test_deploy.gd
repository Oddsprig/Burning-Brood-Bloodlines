extends RefCounted
## Units that cannot fight (can't stand, unconscious, critical wounds) never deploy (Douglas bug report).

func run(_tree: SceneTree) -> int:
	var fails := 0
	Game.new_game(77)
	var all: int = Game.deployed_units().size()
	var lame: Unit = Game.company[1]
	lame.body.wound_part("leg_lower_l")["severed"] = true          # can't stand
	var faint: Unit = Game.company[2]
	faint.body.blood = faint.body.blood_max * 0.5               # collapsed from blood loss
	var ok_hurt: Unit = Game.company[3]
	ok_hurt.body.wound_part("arm_upper_r")["layers"][0]["dmg"] = 0.2  # a scratch: still deploys
	ok_hurt.body.wound_part("arm_upper_r")["layers"][0]["kind"] = "cut"
	Game.invalidate_deploy()
	var dep: Array = Game.deployed_units()
	print("deployable %d of %d; lame: '%s', faint: '%s', scratched: '%s'" % [dep.size(), all,
		Game.deploy_block_reason(lame), Game.deploy_block_reason(faint), Game.deploy_block_reason(ok_hurt)])
	if dep.has(lame) or dep.has(faint): fails += 1
	if not dep.has(ok_hurt): fails += 1
	if dep.size() != all - 2: fails += 1
	# Nobody fit: engaging does nothing and no battle is queued.
	for u in Game.company:
		u.body.blood = u.body.blood_max * 0.4
	Game.invalidate_deploy()
	Game.pending_battle = {}
	var W = load("res://campaign/world.gd")
	var wid: String = Game.world["warbands"].keys()[0]
	W.engage(Game, wid)
	if not Game.pending_battle.is_empty():
		print("battle started with nobody fit"); fails += 1
	# The company has no synthetic captain. Before house selection, an empty army is safe.
	Game.new_game(78)
	for u in Game.company:
		if u.role == "captain":
			print("captain unit present"); fails += 1
	if Game.lead_officer() == null or Game.is_game_over():
		fails += 1
	for u in Game.company:
		u.dead = true
	if Game.is_game_over():
		print("onboarding ended from troop losses"); fails += 1
	# Standalone combat, without a campaign world, keeps the inherited company-loss fallback.
	var campaign: Dictionary = Game.world
	Game.world = {}
	if not Game.is_game_over():
		fails += 1
	var gs: Node = load("res://ui/gameover.tscn").instantiate()
	_tree.root.add_child.call_deferred(gs)
	await _tree.process_frame
	await _tree.process_frame
	gs.queue_free()
	Game.world = campaign
	return fails
