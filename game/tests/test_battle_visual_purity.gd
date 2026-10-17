extends RefCounted
## Bounded native fighters and rendering-state checks; no campaign generation.
const U := preload("res://tests/sim_util.gd")
const View := preload("res://battle/unit_view.gd")
const Screen := preload("res://battle/battle.gd")
var checks := 0
var fails := 0

class CountingDoll extends Paperdoll:
	var invalidations := 0
	func invalidate() -> void:
		invalidations += 1
		super.invalidate()

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL battle visuals: " + why)

func make_screen(sim: BattleSim) -> Node2D:
	# Do not enter the scene tree/_ready: the native sim is already initialized.
	var screen := Screen.new()
	screen.sim = sim
	screen.paused = true # Explicit ticks below; no slowmo viewport query in this detached fixture.
	screen.fx = load("res://battle/fx_layer.gd").new(); screen.add_child(screen.fx)
	screen.blood = load("res://battle/gore_layer.gd").new(); screen.add_child(screen.blood)
	screen.blood.setup(40.0, true, 19)
	screen.gore_layer = Node2D.new(); screen.add_child(screen.gore_layer)
	screen.feed_box = VBoxContainer.new(); screen.add_child(screen.feed_box)
	screen.status_label = Label.new(); screen.add_child(screen.status_label)
	for fighter: Fighter in sim.fighters:
		var view := View.new(); screen.add_child(view); view.setup(fighter, 40.0)
		var old: Node2D = view.doll
		var doll := CountingDoll.new(); doll.team_color = old.team_color
		view.remove_child(old); old.free(); view.doll = doll; view.add_child(doll)
		doll.set_unit(fighter.unit)
		screen.views.append(view)
	return screen

func plain(value: Variant) -> Variant:
	if value is Item: return plain(value.to_dict())
	if value is Array:
		var out: Array = []
		for element in value: out.append(plain(element))
		return out
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value: out[key] = plain(value[key])
		return out
	return value

func mechanical(sim: BattleSim) -> Dictionary:
	var units := []; var actors := []; var entries := []
	for f: Fighter in sim.fighters:
		units.append(f.unit.to_dict())
		actors.append([f.cell, f.prev_cell, f.state, f.target, f.action_ticks, f.action_total,
			f.prone, f.routed, f.bow_hand, f.bleeding.duplicate(true), f.log.size(), f.vcount.duplicate(true)])
	for e: Dictionary in sim.events:
		var entry: Dictionary = e.get("entry", {})
		entries.append([e.get("tick"), e.get("type"), e.get("actor"), e.get("target"), e.get("part"),
			entry.get("k", ""), entry.get("d", {}).duplicate(true)])
	return plain({"tick": sim.tick, "winner": sim.winner, "rng": str(sim.rng.state), "units": units,
		"actors": actors, "events": entries})

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var game_rng: int = Game.rng.state
	var world: Dictionary = Game.world
	var left: Unit = U.soldier("copper")
	var right: Unit = U.make("orc", [["hacking_cleaver", "copper"], ["tunic", "linen"]], {"axe": 4, "fighter": 3})
	# Bare Unit.create fixtures have no recruitment drink identity. Native load
	# seeds that missing field, so finish it on BOTH originals before copying.
	# This helper uses a local seeded RNG, never the campaign or combat RNG.
	Food.roll_fav_drink(left, hash([left.uid, left.name]))
	Food.roll_fav_drink(right, hash([right.uid, right.name]))
	var left_copy: Unit = Unit.from_dict(left.to_dict().duplicate(true))
	var right_copy: Unit = Unit.from_dict(right.to_dict().duplicate(true))
	check(left.to_dict() == left_copy.to_dict() and right.to_dict() == right_copy.to_dict(), "source and independent native clones match before presentation")
	var options: Dictionary = {"w": 12, "h": 8, "max_ticks": 48, "log_moves": false,
		"cells0": [Vector2i(4, 4)], "cells1": [Vector2i(5, 4)]}
	var sim := BattleSim.new(); sim.setup([left], [right], 321, options)
	var control := BattleSim.new(); control.setup([left_copy], [right_copy], 321, options)
	check(mechanical(sim) == mechanical(control), "both adjacent native simulations start from identical complete fixture state")
	check((sim.fighters[0].cell - sim.fighters[1].cell).length_squared() == 1, "actual deployment places opposing native fighters adjacent")
	var screen: Node2D = make_screen(sim)
	var view: Node2D = screen.views[0]
	var doll: CountingDoll = view.doll
	var fighter: Fighter = view.fighter
	var offscreen := Rect2(Vector2(10000, 10000), Vector2(200, 200))
	var before: Dictionary = mechanical(sim)
	view.flash("hit"); view.flash("strike")
	check(view._flash_pose == "hit", "native hit flash retains priority")
	view.highlight = 0.4; view.selected = true
	var stats: Dictionary = Paperdoll.cache_stats()
	check(not view.update_visual(0.5, 0.1, offscreen), "offscreen actor is not offered a raster frame")
	check(view.visible and not doll.visible and not doll._render_frame_enabled, "only sprite is hidden, while logical actor stays present")
	check(is_equal_approx(view._flash_t, 0.18) and is_equal_approx(view.highlight, 0.3) and doll.pose == "hit", "offscreen flash/highlight/pose stay current")
	var after: Dictionary = Paperdoll.cache_stats()
	check(after["spec_builds"] == stats["spec_builds"] and after["raster_builds"] == stats["raster_builds"] and after["uploads"] == stats["uploads"], "offscreen update has zero spec/raster/upload work")
	check(mechanical(sim) == before, "visual selection/interpolation/flash does not alter native state")
	var nearby := Rect2(view.position - Vector2(200, 200), Vector2(400, 400))
	check(view.update_visual(0.5, 0.0, nearby) and doll.visible and doll.pose == "hit", "camera reentry resolves latest flash frame")
	view.update_visual(0.5, 0.19, offscreen)
	var removed: Item = left.equip["helm"]
	left.equip.erase("helm"); doll.invalidate()
	stats = Paperdoll.cache_stats()
	view.update_visual(0.5, 0.0, offscreen)
	check(Paperdoll.cache_stats()["spec_builds"] == stats["spec_builds"], "offscreen actual gear change remains deferred")
	view.update_visual(0.5, 0.0, nearby)
	check(doll.current_spec()["helm"].is_empty(), "pan back reads current actual gear, not stale cached gear")
	left.equip["helm"] = removed; doll.invalidate()
	view.update_visual(0.5, 0.0, nearby)
	stats = Paperdoll.cache_stats()
	view.update_visual(0.5, 0.0, nearby)
	after = Paperdoll.cache_stats()
	check(after["raster_builds"] == stats["raster_builds"] and after["redraw_requests"] == stats["redraw_requests"], "unchanged visible frame reuses texture without doll redraw")
	# Multiple presentation notifications must invalidate each actor only once.
	var other: CountingDoll = screen.views[1].doll
	var first_count: int = doll.invalidations; var second_count: int = other.invalidations
	screen._skipping = true
	var touched: Dictionary = {}
	for kind: String in ["hit", "wound", "artery", "drop", "freed", "lodged", "death", "snap"]:
		screen._present_event({"type": kind, "actor": 0, "target": 1}, touched)
	check(doll.invalidations == first_count and other.invalidations == second_count, "events schedule dirtiness without eager sprite work")
	screen._invalidate_actor_visuals()
	check(doll.invalidations == first_count + 1 and other.invalidations == second_count + 1 and screen._dirty_actors.is_empty(), "event burst coalesces one invalidation per actor, including skip")
	screen._invalidate_actor_visuals()
	check(doll.invalidations == first_count + 1, "empty invalidation retry is pure")
	screen._skipping = false
	view._flash_t = 0.0; view.highlight = 0.0; view.selected = false
	check(mechanical(sim) == mechanical(control), "fixture presentation and restored gear retain exact initial native control")
	var same := true
	for tick in 48:
		if sim.is_over(): break
		screen._do_tick(); control.step()
		for actor: Node2D in screen.views: actor.update_visual(0.5, 0.01, offscreen)
		same = same and mechanical(sim) == mechanical(control)
	check(same and sim.tick == control.tick and sim.is_over() == control.is_over(), "48 native ticks with full event presentation preserve RNG/body/wound/gear/log payloads against control")
	var attacks: int = U.count(sim, "attack")
	var hits: int = U.count(sim, "hit")
	var wounds: int = U.count(sim, "wound")
	check(attacks > 0, "native adjacent fixture resolves actual attacks")
	check(hits > 0, "native adjacent fixture emits actual resolved hit events")
	check(wounds > 0, "native adjacent fixture reaches actual tissue layers and emits wounds")
	print("  Native adjacent combat: %d attacks, %d hits, %d wounds in %d ticks" % [attacks, hits, wounds, sim.tick])
	var ticks_before: int = sim.tick
	var ended: Dictionary = mechanical(sim)
	for actor: Node2D in screen.views:
		actor.settle(offscreen)
		actor.update_visual(1.0, 0.1, Rect2(actor.position - Vector2(200, 200), Vector2(400, 400)))
	check(sim.tick == ticks_before and mechanical(sim) == ended, "skip settle/result viewing and camera refresh do not advance combat")
	# Flee animation is independent of viewport; a headless visual fixture changes
	# fighter display state explicitly, then verifies only the view's timers move.
	fighter.state = "fled"
	view.gone = false; view._flee_t = -1.0
	before = mechanical(sim)
	view.update_visual(0.0, 0.8, offscreen)
	check(is_equal_approx(view._flee_t, 0.8) and view.position != view.cell_pos(fighter.cell), "offscreen flee position/timer progresses")
	view.update_visual(0.0, 0.8, offscreen)
	check(view.gone and not view.visible and mechanical(sim) == before, "offscreen flee completes without native mutation")
	screen.free()
	await tree.process_frame # Flush native feed buttons queued for deletion.
	check(Game.rng.state == game_rng and is_same(Game.world, world), "presentation never consumes campaign RNG or replaces world")
	print("Battle visual purity: %d checks, %d failures" % [checks, fails])
	return fails
