extends RefCounted
## Windowed screenshot capture for v0.105 ("Clear battles, without the fear-circle clutter").
## Not registered in blocks.json or the headless test_* suite.
## Run in windowed mode via:
##   godot --path game res://tests/runner.tscn -- --test=res://tests/capture_v105_screens.gd
## Saves before ("full") and after ("light") 100-on-100 dragon battle PNGs to test-results/v0.105/.
const U := preload("res://tests/sim_util.gd")
const Screen := preload("res://battle/battle.gd")

func _frames(tree: SceneTree, n: int = 4) -> void:
	for i in n:
		await tree.process_frame

func _make_dragon_unit() -> Unit:
	Game.world["dragons"] = {"schema": 1, "next_id": 1, "records": {}, "pairs": {}, "initialized": true}
	var owner := {"person_uid": "p:v105", "house_uid": "h:v105", "household_uid": "hh:v105", "town_id": "t:v105", "state": "hire"}
	var row := Dragons._make(Game, "adult", "t:v105", owner, "v105:dragon", 0, "female")
	DragonCombat.prepare_world(Game)
	return DragonCombat._unit(Game, str(row["id"]))

func _clone_army(template: Unit, count: int, base_uid: int) -> Array:
	var base := template.to_dict()
	var out: Array = []
	for i in count:
		var d := base.duplicate(true)
		d["uid"] = base_uid + i
		d["name"] = "%s %d" % [template.name, i + 1]
		out.append(Unit.from_dict(d))
	return out

func _capture_mode(tree: SceneTree, mode_name: String, out_path: String, dragon: Unit, left_tmpl: Unit, right_tmpl: Unit) -> bool:
	Game.set_setting("battle_markers", mode_name)
	var side0 := [Unit.from_dict(dragon.to_dict().duplicate(true))]
	side0.append_array(_clone_army(left_tmpl, 99, 20000))
	var side1 := _clone_army(right_tmpl, 100, 30000)
	Game.pending_battle = {
		"seed": 1050,
		"round_side0": side0,
		"enemy": side1,
		"terrain": "grassland",
		"max_ticks": 600,
	}
	var b := Screen.new()
	b.paused = true
	tree.root.add_child.call_deferred(b)
	await _frames(tree, 4)
	b.set_process(false)

	# Advance to the clash where the dragon and lines engage and front ranks take morale shock / rout.
	for step_i in 24:
		b.step_ticks(2)
		b._process(0.05)
	var batch: Array = []
	var df: Fighter = b.sim.fighters[0]
	batch.append({"type": "breath", "actor": 0, "origin": df.cell, "facing": df.facing, "range": 4, "element": "fire"})
	for j in range(100, 128):
		if j >= b.sim.fighters.size():
			break
		var f: Fighter = b.sim.fighters[j]
		if f.present():
			f.morale = maxf(0.0, f.morale - 16.0)
			if j % 3 == 0:
				f.routed = true
				batch.append({"type": "rout", "actor": j})
	b.readability.observe(b.sim, batch)
	b.readability.queue_redraw()
	for p in 12:
		b._process(0.016)
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var tex := tree.root.get_texture()
	var ok := false
	if tex != null and tex.get_image() != null:
		ok = tex.get_image().save_png(out_path) == OK
	b.queue_free()
	await _frames(tree, 3)
	return ok

func run(tree: SceneTree) -> int:
	tree.root.size = Vector2i(1600, 900)
	await _frames(tree, 4)
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../test-results/v0.105").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)

	var prev_world := Game.world.duplicate(true)
	var prev_mode := Game.battle_markers_mode()
	var dragon := _make_dragon_unit()
	var left_tmpl := U.soldier("copper")
	var right_tmpl := U.make("orc", [["hacking_cleaver", "copper"], ["tunic", "linen"]], {"axe": 3, "fighter": 2})
	Food.roll_fav_drink(left_tmpl, 501)
	Food.roll_fav_drink(right_tmpl, 602)

	var before_path := out_dir.path_join("v0105_battle_100v100_before_full.png")
	var after_path := out_dir.path_join("v0105_battle_100v100_after_light.png")
	var ok_before := await _capture_mode(tree, "full", before_path, dragon, left_tmpl, right_tmpl)
	var ok_after := await _capture_mode(tree, "light", after_path, dragon, left_tmpl, right_tmpl)

	Game.world = prev_world
	Game.set_setting("battle_markers", prev_mode)
	print("capture_v105_screens: before=%s (%s), after=%s (%s)" % [before_path, str(ok_before), after_path, str(ok_after)])
	return 0 if (ok_before and ok_after) else 1
