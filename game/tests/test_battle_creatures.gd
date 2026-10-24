extends RefCounted
## Monsters wave 1 through the real battle screen (headless): a fight at a wolf den (lair terrain with choke points)
## against a wolf pack and a bear, played out with full presentation (quadruped dolls, severed-part decals, inspector
## health tab on a creature), then the campaign hand-off: trophies auto-sold in the aftermath.

func _check(cond: bool, what: String) -> int:
	if not cond:
		printerr("FAIL: ", what)
		return 1
	return 0

func run(tree: SceneTree) -> int:
	var fails := 0
	await tree.process_frame
	Game.new_game(808)
	var town := DevTools.choose_house(Game)
	fails += _check(DevTools.raise_army(Game, town, 8) == 8, "eight native residents mustered for a real battle")
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var enemy: Array = Creatures.make_group(rng, "wolf", 5) + [Creatures.make(rng, "bear")]
	Game.pending_battle = {"enemy": enemy, "allies": [], "seed": 8, "terrain": "forest",
		"tiles": Lairs.battle_tiles("wolf_den", Vector2i(32, 18), 8)}
	var b: Node = (load("res://battle/battle.tscn") as PackedScene).instantiate()
	tree.root.add_child(b)
	b.set_speed(0.0)
	await tree.process_frame
	var blocked := 0
	for y in b.sim.grid_h:
		for x in b.sim.grid_w:
			if b.sim.tile_at(Vector2i(x, y)) == "blocked":
				blocked += 1
	fails += _check(blocked > 10, "lair map has walls (%d)" % blocked)
	var beast := -1
	for f in b.sim.fighters:
		if f.side == 1:
			beast = f.idx
	b.step_ticks(150)
	b.select(beast)
	b.inspector.show_tab("health")
	await tree.process_frame
	fails += _check(b.inspector.health_text.text != "", "creature health tab renders")
	var guard := 0
	while not b.sim.is_over() and guard < 30000:
		b.step_ticks(50)
		guard += 50
	fails += _check(b.sim.is_over() and b.sim.tick > 0, "nonempty creature battle ends")
	for v in b.views:
		v.update_visual(0.0, 0.0)
	b._drop_piece(beast, "leg_front_upper_l")
	fails += _check(b.gore_pieces.size() > 0 and b.gore_pieces[-1]["node"] is Node2D, "severed creature leg decal")
	var lines := []
	for e in b.sim.events:
		if e.has("entry") and e["actor"] >= 0 and b.sim.fighters[e["actor"]].side == 1 and e["type"] == "hit" and lines.size() < 5:
			lines.append(BattleSim.event_text(e))
	print("den battle: %d ticks, winner %d; %s" % [b.sim.tick, b.sim.winner, " | ".join(lines)])
	b.show_result()
	var main_before = Game.main
	Game.main = null
	b.finish()
	Game.main = main_before
	fails += _check(Game.last_result.has("winner"), "result handed to the campaign")
	b.queue_free()
	await tree.process_frame
	# trophies: a won fight against a pack on the map sells pelts and fangs in the aftermath
	var w: Dictionary = Game.world
	var units := Creatures.make_group(rng, "wolf", 4)
	var wid := CampaignWorld.spawn_warband(Game, "beasts", w["party"]["pos"] + Vector2(10, 0), 4, "beasts", rng,
		{"units": units, "creature": "wolf", "anchor": w["party"]["pos"], "roam": 50.0})
	Game.pending_battle = {"warband_id": wid}
	for u in units:
		u.dead = true
	var g0: int = Game.gold
	Game.main = null
	Game.finish_battle({"winner": 0, "player_units": [], "enemy_units": units, "enemy_fallen": units, "events": []})
	Game.main = main_before
	var r: Dictionary = Game.last_result
	print("trophies: %d gold %s" % [int(r.get("trophy_gold", 0)), str(r.get("trophies", []).map(func(x): return x["name"]))])
	fails += _check(int(r.get("trophy_gold", 0)) > 0 and Game.gold >= g0 + int(r["trophy_gold"]), "trophies sold")
	fails += _check(not w["warbands"].has(wid), "slain pack removed")
	var a: Node = (load("res://battle/aftermath.tscn") as PackedScene).instantiate()
	tree.root.add_child(a)
	await tree.process_frame
	fails += _check(a.get_child_count() > 0, "aftermath builds with trophies")
	a.queue_free()
	await tree.process_frame
	return fails
