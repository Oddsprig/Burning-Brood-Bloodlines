extends RefCounted
## Headless, no days simulated: DevTools start_world plus one native consignment if needed.
## godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_trade_overlay_v047.gd --watchdog=60
const Overlay := preload("res://campaign/trade_overlay.gd")
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL trade047: ", message)

## Reuse recorded cargo, or transfer seven real market units to a native caravan.
## All setup precedes the purity boundary; never simulate days to obtain a caravan.
func _grain_caravan(w: Dictionary) -> String:
	for wid in w["warbands"]:
		var band: Dictionary = w["warbands"][wid]
		if band.get("kind", "") == "caravan" and int(band.get("cargo", {}).get("goods", {}).get("grain", 0)) > 0:
			return String(wid)
	var attempts := 0
	for tid in w["towns"]:
		var town: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(town) or int(town["econ"]["stock"].get("grain", 0)) < 7: continue
		var partners := Caravans.trade_partners(w, town)
		if partners.is_empty(): continue
		var n := Goods.take(town, "grain", 7)
		var wid := Caravans.spawn(Game, String(tid), Game.rng, String(partners[0]["id"]), "",
			{"goods": {"grain": n}, "items": []})
		if wid != "": return wid
		attempts += 1
		if attempts >= 3: break
	return ""

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "start_world fixture loads")
		return fails
	var w: Dictionary = Game.world
	var carrier := _grain_caravan(w)
	check(carrier != "", "fixture has a real grain consignment (non-vacuous cargo checks)")
	if carrier == "": return fails
	var before := Game._save_tree()
	var rng_state: int = Game.rng.state
	var snapshot := Overlay.build(w, "grain")
	check(snapshot["towns"].size() == w["towns"].size(), "every town is marked")
	for tid in w["towns"]:
		var town: Dictionary = w["towns"][tid]
		var row: Dictionary = snapshot["towns"][tid]
		if not TownEcon.has_econ(town):
			check(row["status"] == "unrecorded", "missing books are not invented")
			continue
		var e: Dictionary = town["econ"]
		var n := int(e["stock"].get("grain", 0))
		var target := maxf(1.0, float(e.get("need", {}).get("grain", 0.0)))
		var status := "shortage" if n < target * 0.9 else ("surplus" if n > target * 1.1 else "balanced")
		check(row["stock"]["grain"] == n and row["target"]["grain"] == target, "stock and target match " + String(tid))
		check(row["status"] == status, "mark agrees with recorded market target " + String(tid))
		check(row["prices"].has("grain") == e.get("price", {}).has("grain"), "price availability matches records")
		if row["prices"].has("grain"):
			check(row["prices"]["grain"] == float(e["price"]["grain"]), "exact recorded grain price")
			check(is_equal_approx(float(row["price_index"]), float(e["price"]["grain"]) / RecData.base_price("grain")), "price index matches records")
	var expected := 0
	for wid in w["warbands"]:
		var band: Dictionary = w["warbands"][wid]
		var n := int(band.get("cargo", {}).get("goods", {}).get("grain", 0))
		var included: bool = String(band.get("kind", "")) == "caravan" and n > 0
		check(snapshot["caravans"].has(wid) == included, "only grain-carrying caravans are marked")
		if not included: continue
		expected += 1
		var row: Dictionary = snapshot["caravans"][wid]
		check(row["quantity"] == n and row["goods"] == {"grain": n}, "cargo matches the actual consignment")
		check(row["pos"] == band["pos"] and row["path"] == band["path"], "actual position and road waypoints")
		check(not is_same(row["path"], band["path"]), "cached path is detached")
	check(snapshot["caravans"].size() == expected, "no omitted or invented caravans")
	var layer := Overlay.new()
	var today := floorf(Game.day)
	check(layer.sync(w, today, "grain", 1.0), "first selection builds")
	var cached: Dictionary = layer.data
	check(not layer.sync(w, today + 0.5, "grain", 0.45) and is_same(cached, layer.data), "same-day zoom reuses cache")
	for zoom in [0.45, 1.0, 2.6]:
		layer.sync(w, today, "grain", zoom)
		var hit := layer.pick(MapTokens.center(w["warbands"][carrier]["pos"], zoom))
		check(hit.get("kind", "") == "caravan" and hit.get("id", "") == carrier, "caravan hit follows zoom")
	check(layer.sync(w, today + 1.0, "grain", 1.0) and not is_same(cached, layer.data), "next day rebuilds")
	check(layer.sync(w, today + 1.0, "metal", 1.0) and layer.good == "metal", "toggle change rebuilds")
	check(layer.sync(w, today + 1.0, "off", 1.0) and layer.data["towns"].is_empty() and layer.data["caravans"].is_empty(), "off clears marks")
	var pending := w.duplicate()
	pending["work"] = [["econ", "", int(today)]]
	check(layer.sync(pending, today, "grain", 1.0) and layer.day < 0 and layer.data["towns"].is_empty(), "toggle waits for settled daily records")
	check(layer.sync(w, today, "grain", 1.0) and layer.day == int(today), "settled world refreshes")
	var sparse := {"towns": {"no_books": {"pos": Vector2.ZERO}}, "warbands": {}}
	var sparse_before := sparse.duplicate(true)
	check(Overlay.build(sparse, "grain")["towns"]["no_books"]["status"] == "unrecorded" and sparse == sparse_before, "missing books remain untouched")
	# Deliberately edit detached output, never the campaign: detect nested aliasing too.
	snapshot["towns"].values()[0]["stock"]["grain"] = -1
	snapshot["caravans"][carrier]["goods"]["grain"] = -1
	snapshot["caravans"][carrier]["path"].clear()
	check(before == Game._save_tree() and rng_state == Game.rng.state, "building, caching, picking and editing snapshots leave save and RNG unchanged")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(180, 180)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The runner is still inside _ready here, so the root rejects a direct add.
	tree.root.add_child.call_deferred(viewport)
	await tree.process_frame
	var view_cam := Camera2D.new()
	view_cam.position = (w["towns"].values()[0]["pos"] as Vector2)
	viewport.add_child(view_cam)
	view_cam.make_current()
	viewport.add_child(layer)
	RenderingServer.canvas_item_set_custom_rect(layer.get_canvas_item(), true, Rect2(-200000, -200000, 400000, 400000))
	var before_draws := layer.draws
	layer.sync(w, today, "grain", 1.0)
	await tree.process_frame
	await tree.process_frame
	check(layer.draws > before_draws, "off-screen viewport called _draw without error")
	print("trade047 draw calls=%d" % layer.draws)
	viewport.remove_child(layer)
	viewport.free()
	layer.free()
	check(Time.get_ticks_msec() - started < 60000, "finishes under 60 seconds")
	print("trade047: %d checks, %d failures" % [checks, fails])
	return fails
