extends RefCounted
## Bounded native-state differential. Rendering correctness is not a rendered FPS claim.
## No campaign generation, complete battles, native formula changes or save-file writes.
const SimUtil = preload("res://tests/sim_util.gd")
const TICKS := 24
var checks := 0
var fails := 0
var _marshal_cache: Dictionary = {}
var _property_names: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL battle presentation state: ", message)

## Object-aware values, never Object instance addresses. Native dictionaries have
## identical insertion order in these cloned fixtures. Memoization expires at each
## snapshot; native hash collisions are checked against the original value too.
## Only documented lazy text/detail/calc caches are excluded, not their log data.
func _plain(value: Variant) -> Variant:
	if value is Item: return _plain(value.to_dict())
	if value is Unit: return value.uid
	if value is Fighter: return value.idx
	if value is Dictionary or value is Array:
		var code: int = value.hash()
		for prior: Array in _marshal_cache.get(code, []):
			if typeof(prior[0]) == typeof(value) and prior[0] == value: return prior[1]
	if value is Dictionary:
		var out: Dictionary = {}
		var entry: bool = value.has("tick") and value.has("k") and value.has("d")
		var event: bool = value.has("tick") and value.has("type") and value.has("actor") and value.has("target")
		for k in value:
			if entry and k in ["text", "detail", "calc"]: continue
			if event and k == "text": continue
			out["item:%d" % k.uid if k is Item else k] = _plain(value[k])
		_memo(value, out)
		return out
	if value is Array:
		var out: Array = []
		for v in value: out.append(_plain(v))
		_memo(value, out)
		return out
	return value

func _memo(source: Variant, result: Variant) -> void:
	var code: int = source.hash()
	if not _marshal_cache.has(code): _marshal_cache[code] = []
	_marshal_cache[code].append([source, result])

func _hash(value: Variant, already_plain: bool = false) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(value if already_plain else _plain(value)))
	return ctx.finish().hex_encode()

func _fields(object: Object, skip: Array = []) -> Dictionary:
	var out: Dictionary = {}
	var script: Script = object.get_script()
	if not _property_names.has(script):
		var names: Array = []
		for property in object.get_property_list():
			if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0: names.append(str(property["name"]))
		_property_names[script] = names
	for name: String in _property_names[script]:
		if not name in skip: out[name] = object.get(name)
	return out

func _state(sim: BattleSim) -> Dictionary:
	_marshal_cache.clear()
	var units: Array = []
	var fighters: Array = []
	for f: Fighter in sim.fighters:
		units.append([f.unit.to_dict(), f.unit.food_attr_mult])
		fighters.append(_fields(f, ["unit"]))
	var result: Dictionary = {"rng": _hash([str(sim.rng.seed), str(sim.rng.state)], true),
		"units": _hash(units, true), "fighters": _hash(fighters),
		"field": _hash(_fields(sim, ["fighters", "rng"]))}
	_marshal_cache.clear() # Do not retain the native graph or marshaled snapshot.
	return result

func _same(expected: Dictionary, actual: Dictionary, label: String) -> void:
	for key in ["rng", "units", "fighters", "field"]:
		check(expected[key] == actual[key], label + " preserves " + key)

func _sides(n: int) -> Array:
	# Native fully initialized bodies/items, with a small appearance set to keep this
	# correctness fixture bounded. All people and equipment have distinct real UIDs.
	var prototype: Unit = SimUtil.soldier("copper")
	prototype.look = {"seed": 731, "beard": true}
	var saved: Dictionary = prototype.to_dict()
	var sides: Array = [[], []]
	for side in 2:
		for i in n:
			var row: Dictionary = saved.duplicate(true)
			row["uid"] = 10000 + side * n + i
			row["name"] = "Native fixture %d-%d" % [side, i]
			row["faction"] = "middle_kingdom" if side == 0 else "orc_horde"
			row["look"]["seed"] = 731 + i % 2
			var slots: Array = row["equip"].keys()
			for j in slots.size(): row["equip"][slots[j]]["uid"] = 100000 + (side * n + i) * 16 + j
			sides[side].append(Unit.from_dict(row))
	return sides

func _copy(sides: Array) -> Array:
	var out: Array = [[], []]
	for side in 2:
		for u: Unit in sides[side]: out[side].append(Unit.from_dict(u.to_dict().duplicate(true)))
	return out

func _paused_reads(b: Node) -> void:
	b.select(0)
	b.inspector.show_tab("health")
	b.set_speed(4.0)
	b.set_speed(0.0) # native pause control; automatic processing is disabled too
	for i in 3:
		b.cam_zoom = 1.0 + i * 0.5
		b.cam_pos = b.views[i].body_center()
		b._process_battle(0.1)
		b.inspector.refresh(true)
		for f: Fighter in b.sim.fighters:
			for entry: Dictionary in f.log: BattleSim.render_entry(entry)
		for event: Dictionary in b.sim.events: BattleSim.event_text(event)
	b.inspector.show_tab("log")
	if b.inspector.entry_row_count() > 0:
		b.inspector.expand_entry(0)
		b.inspector.expand_entry(0)
		b.inspector.expand_entry(0)
	b.select(-1)

func _dirty_return(b: Node, tree: SceneTree) -> Dictionary:
	var f: Fighter = b.sim.fighters[0]
	var v: Node = b.views[0]
	var doll: Paperdoll = v.doll
	check(not bool(doll.current_spec()["dead"]), "refresh fixture starts with actual living sprite")
	b.cam_zoom = 2.5
	b.cam_pos = b.map_size() - Vector2(60, 60)
	b._process_battle(0.0)
	check(not doll.visible, "camera excludes the actor before its mutation")
	# Use the actual native death operation/event, not a fabricated dirty flag.
	b.sim.new_events.clear()
	b.sim._kill(f, -1, "bled to death")
	check(f.unit.dead and f.state == "dead", "native death changes persistent body owner and Fighter")
	var after_death: Dictionary = _state(b.sim)
	var event: Dictionary = b.sim.new_events[-1]
	check(event["type"] == "death" and int(event["target"]) == f.idx, "native death emitted its actual target")
	var builds: int = int(Paperdoll.cache_stats()["spec_builds"])
	b._present_event(event, {})
	b._present_event(event, {})
	check(b._dirty_actors.size() == 1 and b._dirty_actors.has(f.idx), "repeated actual events coalesce one actor invalidation")
	b._invalidate_actor_visuals()
	check(b._dirty_actors.is_empty() and doll._dirty, "coalesced event defers the changed spec")
	check(int(Paperdoll.cache_stats()["spec_builds"]) == builds, "event invalidation does not eagerly rebuild specs")
	b._process_battle(0.0)
	check(not doll.visible and doll._dirty, "offscreen death remains pending without raster work")
	check(v.position == v.cell_pos(f.cell) and v.z_index == -1, "offscreen actor coordinates/death layer remain current")
	check(int(Paperdoll.cache_stats()["spec_builds"]) == builds, "hidden dirty actor does not rebuild a spec")
	b.cam_pos = v.body_center()
	b._process_battle(0.0)
	check(doll.visible and not doll._dirty, "camera return resolves pending native change")
	check(doll.pose == "dead" and bool(doll.current_spec()["dead"]), "returned sprite has current native death pose/spec")
	# Battle sprites may retain their previous texture until the exact current
	# native frame completes. Pump this specific paused doll without sim ticks.
	var desired_key: String = doll._frame_key
	var tick_before_wait: int = b.sim.tick
	var deadline: int = Time.get_ticks_msec() + 4000
	var waited_frames: int = 0
	while (doll._frame_pending or doll._tex == null) and waited_frames < 180 and Time.get_ticks_msec() < deadline:
		Paperdoll.pump_background()
		v.update_visual(0.0, 0.0, b._raster_view_rect())
		if not doll._frame_pending and doll._tex != null: break
		await tree.process_frame
		waited_frames += 1
	Paperdoll.pump_background()
	v.update_visual(0.0, 0.0, b._raster_view_rect())
	check(b.paused and b.sim.tick == tick_before_wait, "bounded worker wait stays paused without native ticks")
	check(doll._frame_key == desired_key and not doll._urgent_frame and not doll._frame_pending, "specific current dead frame completes within bounded pump")
	check(doll._tex != null and not doll._frame_pending, "returned native frame is available without pending work")
	var expected_image: Image = FigurePainter.render(FigurePainter.spec_for_unit(f.unit, doll.team_color), "dead", 1.0)
	check(doll._tex != null and doll._tex.get_image().get_data() == expected_image.get_data(), "returned texture pixels match the current native dead figure")
	var key: String = doll._frame_key
	b._process_battle(0.0)
	check(doll._frame_key == key and not doll._dirty, "unchanged paused frame reuses resolved death frame")
	var after_reads: Dictionary = _state(b.sim)
	_same(after_death, after_reads, "death event/camera/render reads")
	return after_reads

func _army_case(tree: SceneTree, n: int) -> void:
	var started: int = Time.get_ticks_msec()
	var label: String = "%d/%d" % [n, n]
	print("Battle presentation state ", label, ": fixture start")
	var sides: Array = _sides(n)
	var reference_sides: Array = _copy(sides)
	print("Battle presentation state ", label, ": native records ready")
	await tree.process_frame
	var seed: int = 9010 + n
	var rows: Array = []
	for y in 36: rows.append(".".repeat(64))
	Game.company = sides[0]
	Game.invalidate_deploy()
	Game.pending_battle = {"enemy": sides[1], "allies": [], "seed": seed,
		"terrain": "plains", "map": "large", "tiles": rows}
	var b: Node = (load("res://battle/battle.tscn") as PackedScene).instantiate()
	b.set_process(false)
	b.paused = true
	tree.root.add_child(b)
	b.set_process(false)
	var reference := BattleSim.new()
	var opts: Dictionary = b.battle_opts(Game.pending_battle, n, n)
	reference.setup(reference_sides[0], reference_sides[1], seed, opts)
	print("Battle presentation state ", label, ": scenes/sims ready")
	await tree.process_frame
	check(b.sim.fighters.size() == n * 2 and b.views.size() == n * 2, label + " has every native person/view")
	check(b.sim.side_total == [n, n] and reference.side_total == [n, n], label + " has identical native formations")
	_same(_state(reference), _state(b.sim), label + " setup")
	print("Battle presentation state ", label, ": initial native hashes checked")
	await tree.process_frame
	var unit_counter: int = Unit._next_uid
	var item_counter: int = Item._next_uid
	for block in 3:
		for tick in 8:
			reference.step()
			b._do_tick() # Native event presentation on every fixed tick.
		b._process_battle(0.0) # Three actual paused control/render loops, not 24 raster sweeps.
		print("Battle presentation state ", label, ": tick ", b.sim.tick)
		await tree.process_frame
	var at_end: Dictionary = _state(b.sim)
	_same(_state(reference), at_end, label + " fixed tick 24")
	check(reference.tick == TICKS and b.sim.tick == TICKS and not b.sim.is_over(), label + " advances only the bounded 24 ticks")
	check(b.sim.events.any(func(e: Dictionary) -> bool: return e["type"] == "move"), label + " exercised actual native movement")
	_paused_reads(b)
	var after_reads: Dictionary = _state(b.sim)
	_same(at_end, after_reads, label + " paused controls/inspector/render")
	check(Unit._next_uid == unit_counter and Item._next_uid == item_counter, label + " presentation creates no native people/items")
	if n == 100: after_reads = await _dirty_return(b, tree)
	print("Battle presentation state ", label, ": purity/refresh checked")
	# Let inspector's deferred scroll finish while its nodes still exist.
	await tree.process_frame
	await tree.process_frame
	_same(after_reads, _state(b.sim), label + " queued draw/paused scene frames")
	b.queue_free()
	await tree.process_frame
	var background: Dictionary = Paperdoll.background_stats()
	check(not bool(background["active"]) and int(background["inflight"]) == 0 and int(background["pending"]) == 0,
		label + " scene teardown drains all raster tasks/latest requests")
	print("Battle presentation state ", label, ": complete in ", Time.get_ticks_msec() - started, "ms")

func run(tree: SceneTree) -> int:
	print("Battle presentation state: bounded fixture starting")
	await tree.process_frame
	checks = 0; fails = 0
	var company: Array = Game.company
	var pending: Dictionary = Game.pending_battle
	var world: Dictionary = Game.world
	var deploy_rev: int = Game._deploy_rev
	var deploy_key: Array = Game._deploy_key
	var deploy_cache: Array = Game._deploy_cache
	var unit_counter: int = Unit._next_uid
	var item_counter: int = Item._next_uid
	var gold: int = Game.gold
	var day: float = Game.day
	var camera: Camera2D = tree.root.get_camera_2d()
	Game.world = {} # isolate campaign callbacks; never generate a world
	await _army_case(tree, 100)
	await _army_case(tree, 200)
	check(Game.world.is_empty() and Game.gold == gold and Game.day == day, "presentation changes no campaign population/calendar/coins")
	Game.company = company; Game.pending_battle = pending; Game.world = world
	Game._deploy_rev = deploy_rev; Game._deploy_key = deploy_key; Game._deploy_cache = deploy_cache
	Unit._next_uid = unit_counter; Item._next_uid = item_counter
	if is_instance_valid(camera): camera.make_current()
	print("Battle presentation state: %d checks, %d failures (fixed native ticks, no FPS gate)" % [checks, fails])
	return fails
