extends RefCounted
## Rendered Windows GPU gate. No headless substitute for native circle equality.
## --test=res://tests/test_gore_render_v016.gd; bounded full/reduced local fixtures.
const U := preload("res://tests/sim_util.gd")
var checks: int = 0
var fails: int = 0

class CountedGore extends "res://battle/gore_layer.gd":
	var pool_draws: int = 0
	var chunk_draws := PackedInt32Array()
	func _init() -> void:
		chunk_draws.resize(DECAL_CHUNK_COUNT)
	func reset_counts() -> void:
		pool_draws = 0
		chunk_draws.fill(0)
	func _draw_pools() -> void:
		pool_draws += 1
		super._draw_pools()
	func _draw_decal_chunk(chunk: int) -> void:
		chunk_draws[chunk] += 1
		super._draw_decal_chunk(chunk)
	func chunk_count() -> int:
		var total: int = 0
		for value: int in chunk_draws: total += value
		return total

class ReferenceGore extends "res://battle/gore_layer.gd":
	# Original single-CanvasItem circle order, copied locally for this GPU oracle.
	# Invalidation overrides only repaint the original root; native arrays/RNG stay shared code.
	func setup(tile_px: float, gore_full: bool, rseed: int) -> void:
		super.setup(tile_px, gore_full, rseed)
		_pool_canvas.visible = false
		for canvas: Node2D in _decal_chunks: canvas.visible = false
	func _decal(p: Vector2, r: float, c: Color) -> void:
		super._decal(p, r, c)
		decals.queue_redraw()
	func tick(sim, views: Array) -> void:
		super.tick(sim, views)
		decals.queue_redraw()
	func _process_drops(delta: float) -> void:
		super._process_drops(delta)
		decals.queue_redraw()
	func _draw_decals_body() -> void:
		for idx in _pools:
			var pl: Array = _pools[idx]
			var c: Vector2 = pl[0]
			var r: float = pl[1]
			decals.draw_set_transform(c, 0.0, Vector2(1.0, 0.45))
			decals.draw_circle(Vector2.ZERO, r, BLOOD_DARK.lerp(BLOOD, 0.3))
			decals.draw_circle(Vector2(-r * 0.2, -r * 0.15), r * 0.55, BLOOD.darkened(0.1))
		decals.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
		for i in _gn:
			var p := _gp[i]
			decals.draw_circle(Vector2(p.x, p.y / 0.6), _gr[i], _gc[i])
		decals.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

class Feet extends Node2D:
	func body_center() -> Vector2:
		return position + Vector2(0, -16)

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL gore render: ", why)

func settle(tree: SceneTree) -> void:
	# Root queue_redraw can enqueue child draw callbacks; settle both generations.
	for frame: int in 3: await tree.process_frame
	await RenderingServer.frame_post_draw

func state(gore: Node2D) -> PackedByteArray:
	return var_to_bytes([gore.full, gore.tile, gore._dp, gore._dv, gore._dl, gore._dground, gore._ds,
		gore._alive, gore._next, gore._gp, gore._gr, gore._gc, gore._gn, gore._gi,
		gore._pools, gore._trail_acc, str(gore._rng.state)])

func viewport(tree: SceneTree, gore: Node2D) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(512, 320)
	view.world_2d = World2D.new()
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(gore)
	tree.root.add_child(view)
	gore.set_process(false) # Physics is advanced by identical explicit deltas below.
	return view

func pixels(tree: SceneTree, actual: SubViewport, original: SubViewport, label: String, expect_blood: bool = true) -> void:
	await settle(tree)
	var a: Image = actual.get_texture().get_image()
	var b: Image = original.get_texture().get_image()
	check(a != null and b != null and not a.is_empty() and not b.is_empty(), label + " has actual GPU images")
	if a == null or b == null or a.is_empty() or b.is_empty(): return
	check(a.get_size() == b.get_size() and a.get_format() == b.get_format() and a.get_data() == b.get_data(),
		label + " exact original native-circle GPU bytes")
	check(not a.get_used_rect().has_area() if not expect_blood else a.get_used_rect().has_area(), label + " expected visible blood/clear frame")

func units(sim: BattleSim) -> PackedByteArray:
	var rows: Array = []
	for fighter: Fighter in sim.fighters:
		rows.append([fighter.unit.to_dict(), fighter.state, fighter.prone, fighter.bleeding, fighter.cell])
	return var_to_bytes([rows, str(sim.rng.state)])

func mode_checks(tree: SceneTree, full: bool) -> void:
	var label: String = "full" if full else "reduced"
	var gore := CountedGore.new()
	var original := ReferenceGore.new()
	gore.setup(40.0, full, 53); original.setup(40.0, full, 53)
	var a: SubViewport = viewport(tree, gore)
	var b: SubViewport = viewport(tree, original)
	check(gore.get_child_count() == 2 and gore.decals.get_child_count() == 31, label + " fixed two roots and 31 retained decal children")
	check(gore.decals.get_child(0) == gore._pool_canvas, label + " pools precede every ring-slot chunk")
	var ordered: bool = true
	var valid_rids: bool = true
	var weak_nodes: Array[WeakRef] = [weakref(gore), weakref(gore.decals), weakref(gore.drops)]
	var child_ids: Array[int] = []
	for i: int in 31:
		var child: Node2D = gore.decals.get_child(i)
		weak_nodes.append(weakref(child)); child_ids.append(child.get_instance_id())
		valid_rids = valid_rids and child.get_canvas_item().is_valid()
		if i > 0: ordered = ordered and child == gore._decal_chunks[i - 1]
	check(ordered and valid_rids, label + " ascending slot chunks have live scene-owned canvas RIDs")
	gore.setup(40.0, full, 53); original.setup(40.0, full, 53)
	var same_nodes: bool = gore.decals.get_child_count() == 31
	for i: int in 31: same_nodes = same_nodes and gore.decals.get_child(i).get_instance_id() == child_ids[i]
	check(same_nodes, label + " repeated empty setup reuses the fixed node set")
	await pixels(tree, a, b, label + " initial", false)
	for target: Node2D in [gore, original]:
		# Deliberate overlap and translucent circles exercise pool-first and slot alpha order.
		target._pools[37] = [Vector2(151.25, 131.5), 38.0]
		target._pools[3] = [Vector2(161.0, 133.0), 26.0]
		for i: int in 960:
			var p := Vector2(60.25 + (i % 67) * 4.3, 65.5 + (i % 31) * 4.7)
			var c := Color(0.65, 0.03, 0.08, 0.38) if i % 2 == 0 else Color(0.2, 0.01, 0.035, 0.7)
			target._decal(p, 2.4 + (i % 7) * 0.8, c)
		target.decals.queue_redraw()
	check(gore._gn == 900 and gore._gi == 60 and state(gore) == state(original), label + " 900-slot ring overwrite preserves native arrays and RNG")
	await pixels(tree, a, b, label + " overlapping wrapped ring")
	for camera: Transform2D in [Transform2D(0.0, Vector2(23.5, -11.25)),
		Transform2D(Vector2(1.65, 0.0), Vector2(0.0, 1.65), Vector2(-71.0, -39.0)),
		Transform2D(0.17, Vector2(34.0, -21.0))]:
		gore.transform = camera; original.transform = camera
		gore.modulate = Color(0.94, 0.83, 0.89, 0.77); original.modulate = gore.modulate
		await pixels(tree, a, b, label + " parent camera/colour transform")
	check(state(gore) == state(original), label + " redraw and camera transforms consume no native visual RNG")
	gore.reset_counts()
	gore._decal(Vector2(145, 122), 19.0, Color(0.7, 0.01, 0.03, 0.4))
	original._decal(Vector2(145, 122), 19.0, Color(0.7, 0.01, 0.03, 0.4))
	await pixels(tree, a, b, label + " one-slot overwrite")
	check(gore.chunk_count() == 1 and gore.chunk_draws[2] == 1 and gore.pool_draws == 0, label + " one slot rebuilds exactly its one 30-circle chunk")
	gore.reset_counts()
	gore._gi = 28; original._gi = 28
	for i: int in 5:
		gore._decal(Vector2(152 + i, 129), 8.0, Color(0.75, 0.01, 0.04, 0.45))
		original._decal(Vector2(152 + i, 129), 8.0, Color(0.75, 0.01, 0.04, 0.45))
	await pixels(tree, a, b, label + " adjacent chunk boundary")
	check(gore.chunk_count() == 2 and gore.chunk_draws[0] == 1 and gore.chunk_draws[1] == 1 and gore.pool_draws == 0,
		label + " five mutations coalesce into exactly two adjacent chunk redraws")
	var sim := BattleSim.new()
	sim.setup([U.soldier("copper")], [U.soldier("tin")], 71, {"w": 8, "h": 5, "combat_journal": false})
	var views: Array = [Feet.new(), Feet.new()]
	views[0].position = Vector2(144, 125); views[1].position = Vector2(174, 127)
	for fighter: Fighter in sim.fighters:
		fighter.prone = true
		fighter.unit.body.blood = fighter.unit.body.blood_max * 0.82
	var native_before: PackedByteArray = units(sim)
	gore.reset_counts()
	gore.tick(sim, views); original.tick(sim, views)
	await pixels(tree, a, b, label + " real fighter pools")
	check(gore.pool_draws == 1 and gore.chunk_count() == 0 and state(gore) == state(original), label + " pool creation redraws pools only with exact native state")
	gore.reset_counts()
	gore.tick(sim, views); original.tick(sim, views)
	await settle(tree)
	check(gore.pool_draws == 0 and gore.chunk_count() == 0 and units(sim) == native_before, label + " unchanged pool tick has zero retained rebuilds and no fighter mutation")
	gore.reset_counts()
	sim.fighters[0].unit.body.blood *= 0.75
	native_before = units(sim)
	gore.tick(sim, views); original.tick(sim, views)
	await pixels(tree, a, b, label + " native blood-loss pool growth")
	check(gore.pool_draws == 1 and gore.chunk_count() == 0 and state(gore) == state(original) and units(sim) == native_before,
		label + " native blood-loss growth redraws pools only and preserves fighters/RNG")
	sim.fighters[0].bleeding = {"arm_upper_r": 0.065, "leg_lower_r": 0.02}
	sim.fighters[1].state = "fled" # Native tick skips departed fighters.
	native_before = units(sim)
	var all_same: bool = true
	for frame: int in 16:
		sim.tick = frame
		views[0].position.x += 1.75
		gore.tick(sim, views); original.tick(sim, views)
		gore._process_drops(0.04); original._process_drops(0.04)
		gore.set_process(false); original.set_process(false)
		all_same = all_same and state(gore) == state(original)
		if frame == 3: await pixels(tree, a, b, label + " in-flight native spurt/trail")
	check(all_same and units(sim) == native_before, label + " sixteen native gore ticks/deltas preserve exact spray/trail/landing arrays, local RNG and fighter state")
	for target: Node2D in [gore, original]:
		target.spray(Vector2(162, 94), Vector2(0.5, -0.3), 441, 136.0)
		target._process_drops(0.025)
		target.set_process(false)
	check(gore.drop_count() <= 384 and state(gore) == state(original), label + " native capped spray overwrite state and RNG equal reference")
	await pixels(tree, a, b, label + " capped droplets above settled decals")
	var settled_before: PackedByteArray = var_to_bytes([gore._gp, gore._gr, gore._gc, gore._gn, gore._gi, gore._pools])
	gore.reset_counts()
	gore.clear_all(); original.clear_all()
	await pixels(tree, a, b, label + " native clear flying drops")
	check(gore.drop_count() == 0 and state(gore) == state(original) and settled_before == var_to_bytes([gore._gp, gore._gr, gore._gc, gore._gn, gore._gi, gore._pools]),
		label + " clear_all preserves original settled blood and clears only droplets")
	check(gore.pool_draws == 0 and gore.chunk_count() == 0, label + " clear_all rebuilds no retained ground circles")
	for target: Node2D in [gore, original]:
		target._gn = 2
		target._pools.clear()
		target._gp[0] = Vector2(210, 132); target._gr[0] = 13.0; target._gc[0] = Color(0.5, 0.01, 0.035, 0.6)
		target._pools[5] = [Vector2(205, 136), 12.0]
		target.decals.queue_redraw()
	await pixels(tree, a, b, label + " external arrays shrink and replace")
	gore.reset_counts()
	for target: Node2D in [gore, original]:
		target._pools[5][1] = 33.0 # Borrowed pool Array mutation, explicit public invalidation.
		target.decals.queue_redraw()
	await pixels(tree, a, b, label + " external pool Array mutation")
	check(gore.pool_draws == 1 and gore.chunk_count() == 30, label + " public root redraw invalidates all custom edited retained data")
	for target: Node2D in [gore, original]:
		target._gn = 0; target._gi = 0; target._pools.clear(); target._trail_acc.clear()
		target.decals.queue_redraw()
	await pixels(tree, a, b, label + " explicit ground reset", false)
	gore.reset_counts()
	await settle(tree)
	check(gore.pool_draws == 0 and gore.chunk_count() == 0 and gore.decals.get_child_count() == 31, label + " clean idle has no redraws or history-growing nodes")
	for view: Node2D in views: view.free()
	views.clear()
	a.queue_free(); b.queue_free()
	gore = null; original = null; sim = null
	await settle(tree)
	var released: bool = true
	for ref: WeakRef in weak_nodes: released = released and ref.get_ref() == null
	check(released, label + " deferred scene deletion releases root and every CanvasItem/RID owner")

func run(tree: SceneTree) -> int:
	await tree.process_frame
	check(DisplayServer.get_name() != "headless", "requires actual Windows GPU raster output")
	if DisplayServer.get_name() == "headless": return fails
	var native_before: String = JSON.stringify(Game._save_tree(), "", true, true).sha256_text()
	var rng_before: int = Game.rng.state
	var unit_before: int = Unit._next_uid
	var item_before: int = Item._next_uid
	var nodes_before: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	await mode_checks(tree, true)
	await mode_checks(tree, false)
	Unit._next_uid = unit_before; Item._next_uid = item_before
	check(Game.rng.state == rng_before and JSON.stringify(Game._save_tree(), "", true, true).sha256_text() == native_before,
		"rendered fixtures preserve exact campaign state, RNG and restored Unit/Item counters")
	check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == nodes_before
		and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == orphans_before,
		"all fixed scene nodes release without orphan growth")
	print("Gore render v016: ", checks, " checks, ", fails, " failures; native GPU RGBA, full/reduced, 30 chunks + pools")
	return fails
