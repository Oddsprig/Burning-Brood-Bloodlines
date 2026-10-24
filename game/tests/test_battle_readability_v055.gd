extends RefCounted
## DevTools Normal / one-day fixture, two small rendered fights and six simulated minutes.
## --test=res://tests/test_battle_readability_v055.gd --watchdog=60
const Screen := preload("res://battle/battle.gd")
const Ground := preload("res://battle/map_view.gd")
const Cues := preload("res://battle/readability_fx.gd")
const Purity := preload("res://tests/test_battle_visual_purity.gd")
var checks := 0
var fails := 0
var started := 0
var fixture: Array[Dictionary] = []
var state_reader := Purity.new()

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL battle readability v055: " + why)

func outcome_hash(s: BattleSim) -> String:
	var state: Dictionary = state_reader.mechanical(s)
	var morale: Array = []
	for f: Fighter in s.fighters: morale.append([f.morale, f.kills])
	state["morale"] = morale
	state["arrow_field"] = s.arrow_field
	state["projectiles"] = s.projectiles
	state["dragon_downs"] = s.dragon_downs
	return JSON.stringify(state, "", true, true).sha256_text()

func patterns_and_legend(tree: SceneTree, legend: Control) -> void:
	var modelled: Array = Formulas.TERRAIN_MOVE.keys() + BattleTactics.TERRAIN_MODS.keys() \
		+ Screen.TERRAIN_DRESS.keys() + Screen.SIM_TERRAIN.keys() + Ground.PALETTES.keys() + Ground.ALIASES.keys()
	for id: String in modelled:
		var canonical := Ground.pattern_id(id)
		check(Ground.PATTERNS.has(canonical) and Ground.PATTERNS.get(canonical, []).size() >= 2, "pattern covers modelled terrain " + id)
		var label: Label = legend.find_child("Terrain_" + canonical, true, false)
		check(label != null and label.text.to_lower().contains(id), "visible legend names " + id)
	var shapes := {}
	for id: String in Ground.PATTERNS:
		var signature := str(Ground.PATTERNS[id])
		check(not shapes.has(signature), "distinct pattern for " + id)
		shapes[signature] = true
	for id: String in ["rough", "blocked", "raid", "siege"]:
		check(legend.find_child("Terrain_" + id, true, false) is Label, "legend explains cell/backdrop " + id)
	for id: String in ["fire", "frost", "storm", "venom", "fear", "rout", "charge", "volley", "rider_fall"]:
		var label: Label = legend.find_child("Cue_" + id, true, false)
		check(label != null and not label.text.is_empty(), "legend explains cue " + id)
	check(not legend.is_open(), "legend starts closed")
	legend.button.set_pressed(true)
	check(legend.is_open(), "legend toggle opens")
	await tree.process_frame
	legend.close()
	check(not legend.is_open() and not legend.button.button_pressed, "legend closes without changing playback")

func rendered_battle(tree: SceneTree, on: bool) -> String:
	var left := Unit.from_dict(fixture[0].duplicate(true))
	var right := Unit.from_dict(fixture[1].duplicate(true))
	Game.pending_battle = {"seed": 55, "round_side0": [left], "enemy": [right],
		"terrain": "hills", "max_ticks": 1200, "tiles": ["........", "........", "...,....", "........", "........"]}
	var b := Screen.new()
	b.readability_enabled = on
	b.paused = true
	tree.root.add_child(b)
	b.set_process(false) # Explicit native ticks; no wall-clock aftermath/medic simulation.
	await tree.process_frame
	await tree.process_frame
	var texture: Texture2D = b.map_view.ground_texture()
	var paints: int = b.map_view.terrain_paint_count
	check(texture != null and b.map_view.terrain_build_count == 1, "one terrain texture built for this battle")
	if on: await patterns_and_legend(tree, b.readability_legend)
	b.map_view.configure(b.sim, b.TILE, b.terrain, 55)
	var guard := 0
	while not b.sim.is_over() and guard < 1200:
		b.step_ticks(48)
		b._process(0.0) # Pump the normal background sprite completions while paused.
		guard += 48
		await tree.process_frame
		if Time.get_ticks_msec() - started > 55000:
			check(false, "bounded fight exceeded 55 second test budget")
			break
	check(b.sim.is_over(), "small native battle reaches its outcome")
	check(b.sim.events.any(func(e: Dictionary): return e["type"] == "hit"), "outcome comparison includes resolved native hits")
	check(b.map_view.terrain_build_count == 1 and is_same(texture, b.map_view.ground_texture()), "ticks/camera/legend reuse the same terrain texture")
	check(b.map_view.terrain_paint_count == paints and paints <= 1, "ground is never repainted during playback")
	check(b.readability.items.is_empty(), "live battle-end hook empties effects")
	check(b.readability.peak_count <= Cues.MAX_CUES, "rendered fight respects cue cap")
	var result := outcome_hash(b.sim)
	b.show_result()
	check(b.readability.items.is_empty(), "results retain no live cues")
	b.queue_free()
	await tree.process_frame
	return result

func cue_batch() -> Array:
	var events: Array = []
	for element: String in ["fire", "frost", "storm", "venom"]:
		events.append({"type": "breath", "actor": 0, "origin": Vector2i(4,3), "facing": -1, "range": 3, "element": element})
	events.append_array([{"type": "rout", "actor": 1}, {"type": "shoot", "actor": 1},
		{"type": "hit", "actor": 0, "target": 1, "entry": {"d": {"verb": "charge"}}},
		{"type": "fall", "actor": 0}])
	return events

func effects_and_long_battle(tree: SceneTree, dragon: Unit) -> void:
	var enemy := Unit.from_dict(fixture[1].duplicate(true))
	enemy.equip.clear(); enemy.quiver.clear()
	var s := BattleSim.new()
	s.setup([dragon], [enemy], 550, {"w": 12, "h": 7, "max_ticks": 7200,
		"hold0": true, "hold1": true, "cells0": [Vector2i(1,3)], "cells1": [Vector2i(10,3)],
		"verbose": false, "log_moves": false, "combat_journal": false, "history_events": 32, "history_log": 16})
	var fx := Cues.new()
	fx.setup(s, 40)
	fx.set_process(false) # This fixture advances effect ages explicitly.
	var events := cue_batch() # Event fixtures; inject only into the observer, never the sim.
	var before := outcome_hash(s)
	fx.observe(s, events)
	check(outcome_hash(s) == before, "all event cues leave native state and RNG unchanged")
	var seen := {}
	for item: Dictionary in fx.items:
		seen[item["kind"]] = true
		if str(item["kind"]) in ["fire", "frost", "storm", "venom"]:
			check(item["pos"] == Vector2(180,140) and int(item["dir"]) == -1, "breath uses release origin/facing")
			var points: PackedVector2Array = item["cone"]
			check(points.size() == 8 and is_equal_approx(points[points.size()/2-1].x, -140), "breath uses the released three-tile cone")
	for id: String in ["fire", "frost", "storm", "venom", "rout", "volley", "charge", "rider_fall"]:
		check(seen.has(id), "actual observer maps cue " + id)
	fx.end_battle()
	s.fighters[1].morale = 80.0 # Instant native shock fixture; no waiting for a campaign.
	fx.setup(s, 40)
	s._shock(s.fighters[1], 12, "dragonfear", false)
	before = outcome_hash(s)
	fx.observe(s)
	check(fx.items.any(func(item: Dictionary): return item["kind"] == "fear"), "native morale loss produces fear cue")
	check(outcome_hash(s) == before, "fear observation is read-only")
	# Native collapse emits several down events; only one rider warning should appear.
	s._fall(s.fighters[0], "pain", 1)
	s._knock_out(s.fighters[0], "pain")
	fx.observe(s)
	check(fx.items.filter(func(item: Dictionary): return item["kind"] == "rider_fall").size() == 1, "v054 native collapse warns once, without predicting rider fate")
	# Rebuild the held fixture from its pristine native body for a six-minute stream.
	var fresh := Unit.from_dict(fixture[2].duplicate(true))
	s.setup([fresh], [Unit.from_dict(fixture[1].duplicate(true))], 551,
		{"w": 12, "h": 7, "max_ticks": 7200, "hold0": true, "hold1": true,
		"cells0": [Vector2i(1,3)], "cells1": [Vector2i(10,3)], "verbose": false,
		"log_moves": false, "combat_journal": false, "history_events": 32, "history_log": 16})
	# Both sides remain beyond breath/melee range; the held enemy has no ranged kit.
	fx.setup(s, 40)
	for burst in Cues.MAX_CUES * 3: fx.observe(s, events)
	check(fx.items.size() == Cues.MAX_CUES, "event flood actually saturates the cap")
	var bounded := true
	while not s.is_over() and s.tick < 7200:
		s.step()
		fx.observe(s, events)
		fx.advance(Formulas.TICK_SECONDS)
		bounded = bounded and fx.items.size() <= Cues.MAX_CUES
		if s.tick % 240 == 0:
			await tree.process_frame
			if Time.get_ticks_msec() - started > 55000: break
	check(s.is_over() and s.tick == 7200, "six simulated minutes finish within the bounded fixture")
	check(bounded and fx.peak_count == Cues.MAX_CUES, "long stream stays at/below cap after saturation")
	check(fx.items.is_empty() and fx._morale.is_empty() and fx._fall_at.is_empty(), "battle end frees active cues and per-fighter tracking")
	fx.free()

func run(tree: SceneTree) -> int:
	started = Time.get_ticks_msec()
	await tree.process_frame
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "DevTools start fixture loads")
		return fails
	var town := DevTools.choose_house(Game, func(choice: Dictionary):
		return str(Dynasty.person(Game, str(choice["ruler_uid"])).get("race", "")) == "human")
	check(town != "", "native human household exists")
	if town == "": return fails
	check(DevTools.raise_army(Game, town, 2) == 2, "two actual residents form the native fixture")
	if Game.company.size() < 2: return fails
	for u: Unit in Game.company.slice(0,2):
		Food.roll_fav_drink(u, u.uid)
		fixture.append(u.to_dict().duplicate(true))
	# One native mount keeps fixture setup bounded; no campaign days are simulated.
	Game.world["dragons"] = {"schema": 1, "next_id": 1, "records": {}, "pairs": {}, "initialized": true}
	var person_uid := str(Dynasty.selected(Game)["ruler_uid"])
	var row := Dragons._make(Game, "adult", town, Dragons._person(Game, person_uid), "v055:readability", 0, "female")
	row["rider_person_uid"] = person_uid
	DragonCombat.prepare_world(Game)
	var dragon: Unit = DragonCombat._unit(Game, str(row["id"]))
	fixture.append(dragon.to_dict().duplicate(true))
	var campaign_rng := Game.rng.state
	var with_visuals := await rendered_battle(tree, true)
	var without_visuals := await rendered_battle(tree, false)
	check(with_visuals == without_visuals, "identical seed has identical full outcome hash with visuals on/off")
	# Strip only this detached held enemy's kit before BattleSim builds its caches.
	var held := Unit.from_dict(fixture[1].duplicate(true))
	held.equip.clear(); held.quiver.clear()
	var fight_enemy: Dictionary = fixture[1]
	fixture[1] = held.to_dict().duplicate(true)
	await effects_and_long_battle(tree, dragon)
	fixture[1] = fight_enemy
	check(Game.rng.state == campaign_rng, "new visuals never consume campaign RNG")
	check(Time.get_ticks_msec() - started < 60000, "whole DevTools check completes under 60 seconds")
	print("Battle readability v055: %d checks, %d failures." % [checks, fails])
	return fails
