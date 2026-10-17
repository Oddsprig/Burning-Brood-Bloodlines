extends RefCounted
## Short capacity/history/suspension checks. No complete 200-per-side battle benchmark.
const U = preload("res://tests/sim_util.gd")
var fails := 0
var checks := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL army scale / monster pause: " + why)

func run(_tree: SceneTree) -> int:
	for size in [100, 200]:
		var a := []; var b := []; var bodies := {}
		for i in size:
			var left := U.make("human", [["arming_sword", "copper"]])
			var right := U.make("orc" if size == 100 else "goblin", [["boar_spear", "copper"]])
			a.append(left); b.append(right)
			bodies[left.uid] = left.body; bodies[right.uid] = right.body
		var sim := BattleSim.new()
		sim.setup(a, b, size, {"max_ticks": 2, "tiles": ["....", ".##.", "...."]})
		check(sim.fighters.size() == 2 * size and sim.side_total == [size, size], "all original fighters retained")
		check(sim.grid_w >= 80 and sim.grid_h >= 44, "army battlefield expanded")
		var occupied := {}; var correct := true; var persistent := true
		for f in sim.fighters:
			if occupied.has(f.cell) or sim.tile_at(f.cell) == "blocked": correct = false
			if f.side == 0 and f.cell.x >= sim.grid_w / 2: correct = false
			if f.side == 1 and f.cell.x < sim.grid_w / 2: correct = false
			occupied[f.cell] = true
			if f.unit.body != bodies[f.unit.uid] or not (a if f.side == 0 else b).has(f.unit): persistent = false
		check(correct, "distinct passable formation cells on the correct side")
		check(persistent, "actual Unit/body/race identities retained")
		check(sim.tile_at(Vector2i(sim.grid_w / 2 - 1, sim.grid_h / 2 - 1)) == "blocked", "central terrain retained")
		sim.step(); sim.step()
		check(sim.is_over() and sim.tick == 2, "bounded native ticks advance all fighters")
		check(sim.history_event_limit == 8192 and sim.history_log_limit == 512, "army histories have bounds")
	# Trimming presentation history must preserve latest skill-level reports for aftermath.
	var tiny := BattleSim.new()
	tiny.setup([U.soldier("copper")], [U.soldier("copper")], 9, {"history_events": 8, "history_log": 8})
	tiny._ev_simple("learn", 0, -1, "learn", {"n": "Test", "skill": "sword", "lvl": 5})
	for i in 30:
		tiny._event("move", 0, -1, "", false)
		tiny._log(tiny.fighters[0], "move", {})
	tiny._trim_history()
	check(tiny.events.size() <= 8 and tiny.fighters[0].log.size() <= 8, "old history trimmed")
	check(tiny.events_dropped > 0 and int(tiny.log_dropped.get(0, 0)) > 0, "omitted history counted")
	var learning := tiny.result_events().filter(func(e): return e["type"] == "learn")
	check(learning.size() == 1 and learning[0]["entry"]["d"]["lvl"] == 5, "aftermath retains learning summary")
	check(CampaignWorld.field_target({}) == 100 and CampaignWorld.field_target({"size": "large"}) == 150 and
		CampaignWorld.field_target({"size": "huge"}) == 200, "100/150/200 initial field targets")
	check(CampaignWorld.field_target({}, 7) == 125 and CampaignWorld.field_target({}, 1000) == 200, "weekly request growth capped")
	var rng := RandomNumberGenerator.new(); rng.seed = 23
	var creature := {"id": "frozen", "kind": "beasts", "faction": "beasts", "pos": Vector2(2, 3), "units": []}
	var initial := creature.duplicate(true); var rs := rng.state
	check(not Monsters.campaign_creatures_enabled(), "creatures temporarily suspended")
	check(Monsters.suspended_band(creature), "creature band suspended")
	check(Monsters.step_band(Game, "frozen", creature, 1.0, 2.0, rng) and creature == initial and rng.state == rs,
		"no creature movement/state/random draws")
	for fid in ["middle_kingdom", "goblin_warren", "orc_horde"]:
		check(not Monsters.suspended_band({"kind": "patrol", "faction": fid, "units": []}), "conventional faction remains enabled " + fid)
	check(not Monsters.suspended_lair({"kind": "bandit_camp"}) and Monsters.suspended_lair({"kind": "den"}), "human camp remains active")
	check(Monsters.do_work(Game, ["lair"], rng) and Monsters.do_work(Game, ["lair_fill"], rng) and rng.state == rs,
		"queued creature jobs consumed without work")
	check(Monsters.available({}, 10000).is_empty(), "no creature unlock/spawn candidates")
	check(CampaignWorld.spawn_warband(Game, "beasts", Vector2.ZERO, 10, "beasts", rng) == "", "creature spawn refused")
	check(Monsters.suspended_contract({"kind": "hunt"}, {}), "hunt contract disabled")
	var world_before: Dictionary = Game.world
	var pending_before: Dictionary = Game.pending_battle
	Game.world = {"warbands": {"frozen": creature}, "party": {"pos": Vector2.ZERO}}
	Game.pending_battle = {}
	check(CampaignWorld.visible_warbands(Game).is_empty(), "creatures absent from map presentation")
	CampaignWorld.engage(Game, "frozen")
	check(Game.pending_battle.is_empty(), "creature encounter cannot enter battle")
	Game.world = world_before; Game.pending_battle = pending_before
	var captured := {"econ": {"culture": "orc", "stock": {}}}
	# A full native culture row is needed by Persons.race_of; use its culture identity.
	for key in TownEcon.data()["cultures"]:
		if TownEcon.data()["cultures"][key].get("race", "") == "orc": captured["econ"]["culture"] = key
	var resident := CampaignWorld.make_resident_troop(rng, "middle_kingdom", captured)
	check(resident.race == "orc" and resident.faction == "middle_kingdom", "resident body and political allegiance separate")
	print("army scale / creature pause: %d checks, %d failures" % [checks, fails])
	return fails
