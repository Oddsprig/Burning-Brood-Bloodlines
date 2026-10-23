extends Node2D
## v0.047: read-only trade marks using the map's existing fonts, circles and track arrows.
## Only stock/cargo snapshots are cached. Motion reads the walkers' actual remaining waypoints.
const MODES := ["off", "grain", "meat", "metal"]
const GOODS := {
	"grain": ["grain"],
	"meat": ["meat", "fresh_meat"],
	"metal": ["copper_ore", "tin_ore", "iron_ore", "copper_bars", "tin_bars",
		"bronze_bars", "iron_bars", "steel_bars", "scrap_copper", "scrap_tin",
		"scrap_bronze", "scrap_iron", "scrap_steel"]}
const MARKS := {"shortage": "-", "surplus": "+", "balanced": "=", "unrecorded": "?"}
const TONES := {"shortage": UiTheme.BAD, "surplus": UiTheme.GOOD,
	"balanced": UiTheme.BRASS, "unrecorded": UiTheme.INK_SOFT}

var good := "off"
var day := -1
var data: Dictionary = {"towns": {}, "caravans": {}}
var draws := 0
var _world: Dictionary = {}
var _zoom := 1.0

## One rebuild per settled game day or changed toggle/world. No simulation helper, pathfinder
## or lazy ledger initializer is called. Leave yesterday's figures visible during midnight jobs.
func sync(w: Dictionary, game_day: float, selected_good: String, zoom: float) -> bool:
	var mode := selected_good if MODES.has(selected_good) else "off"
	var changed := mode != good or not is_same(_world, w)
	_zoom = maxf(0.01, zoom)
	modulate = MapTokens.night_comp(Calendar.tint(game_day))
	if changed:
		good = mode
		day = -1
		data = {"towns": {}, "caravans": {}}
		_world = w
	var today := int(floor(game_day))
	if day != today and (good == "off" or (w.get("work", []) as Array).is_empty()):
		data = build(w, good)
		day = today
		changed = true
	# Redraw cheap live geometry; never reread town economies or cargo here.
	if changed or good != "off":
		queue_redraw()
	return changed

## Detached scalar/Vector2 records. In particular, never use Goods._stock on towns
## without books (that accessor initializes a stock dictionary).
static func build(w: Dictionary, selected_good: String) -> Dictionary:
	var result := {"towns": {}, "caravans": {}}
	var goods: Array = GOODS.get(selected_good, [])
	if goods.is_empty(): return result
	var table := Goods.table()
	for tid in w.get("towns", {}):
		var town: Dictionary = w["towns"][tid]
		var row := {"pos": town.get("pos", Vector2.ZERO), "size": int(town.get("size", 0)),
			"stock": {}, "target": {}, "prices": {}, "status": "unrecorded", "price_index": null}
		result["towns"][tid] = row
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		var stock_value := 0.0; var target_value := 0.0
		var price_value := 0.0; var normal_value := 0.0
		for g in goods:
			var n := int(e["stock"].get(g, 0))
			var target := Goods.target(town, g)
			var base := float(table.get(g, {}).get("price", 1.0))
			row["stock"][g] = n
			row["target"][g] = target
			# Only metal mixes units: value weights keep baskets, bars and kg separate.
			var weight := base if selected_good == "metal" else 1.0
			stock_value += n * weight
			target_value += target * weight
			if e.get("price", {}).has(g):
				var price := float(e["price"][g])
				row["prices"][g] = price
				price_value += price * target
				normal_value += base * target
		row["status"] = "shortage" if stock_value < target_value * 0.9 else (
			"surplus" if stock_value > target_value * 1.1 else "balanced")
		if normal_value > 0.0: row["price_index"] = price_value / normal_value
	for wid in w.get("warbands", {}):
		var band: Dictionary = w["warbands"][wid]
		if String(band.get("kind", "")) != "caravan": continue
		var carried := {}; var quantity := 0
		var cargo: Dictionary = band.get("cargo", {}).get("goods", {})
		for g in goods:
			var n := int(cargo.get(g, 0))
			if n > 0:
				carried[g] = n
				quantity += n
		if quantity <= 0: continue
		result["caravans"][wid] = {"goods": carried, "quantity": quantity,
			"pos": band.get("pos", Vector2.ZERO), "path": (band.get("path", []) as Array).duplicate(),
			"dest": String(band.get("dest", "")), "leg": String(band.get("leg", "out"))}
	return result

## A returned/lost caravan must not display its old consignment until the next daily snapshot.
func _caravan(wid: String) -> Dictionary:
	var band: Dictionary = _world.get("warbands", {}).get(wid, {})
	var record: Dictionary = data["caravans"].get(wid, {})
	if record.is_empty() or String(band.get("kind", "")) != "caravan": return {}
	if String(band.get("dest", "")) != record["dest"] or String(band.get("leg", "out")) != record["leg"]: return {}
	return band

func _town_label(row: Dictionary) -> Vector2:
	return (row["pos"] as Vector2) - Vector2(0, 12.0 + int(row["size"]) * 5.0 + 10.0 / _zoom)

func _label_hit(p: Vector2, at: Vector2) -> bool:
	return Rect2(at + Vector2(-48, -18) / _zoom, Vector2(96, 24) / _zoom).has_point(p)

## Match visible marks before the map's travel handlers. No selection changes a walker.
func pick(p: Vector2) -> Dictionary:
	if good == "off": return {}
	var best := ""; var distance := MapTokens.HIT_R / _zoom
	for wid in data["caravans"]:
		var band := _caravan(String(wid))
		if band.is_empty(): continue
		var center := MapTokens.center(band["pos"], _zoom)
		var d := center.distance_to(p)
		if _label_hit(p, center + Vector2(0, 44) / _zoom): d = 0.0
		if d < distance:
			best = String(wid); distance = d
	if best != "": return {"kind": "caravan", "id": best}
	var town_id := ""; var nearest := maxf(34.0, 40.0 / _zoom)
	for tid in data["towns"]:
		var row: Dictionary = data["towns"][tid]
		var d := (row["pos"] as Vector2).distance_to(p)
		if _label_hit(p, _town_label(row)): d = 0.0
		if d < nearest:
			town_id = String(tid); nearest = d
	return {"kind": "town", "id": town_id} if town_id != "" else {}

func _text(at: Vector2, text: String, color: Color) -> void:
	# Fixed screen-size labels at every camera zoom and in either orientation.
	draw_set_transform(at, 0.0, Vector2.ONE / _zoom)
	var font := UiTheme.regular_font()
	draw_string_outline(font, Vector2(-48, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 96, 16, 4, UiTheme.WOOD)
	draw_string(font, Vector2(-48, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 96, 16, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw() -> void:
	draws += 1
	if good == "off": return
	for tid in data["towns"]:
		var row: Dictionary = data["towns"][tid]
		var status := String(row["status"])
		var color: Color = TONES[status]
		var radius := 12.0 + int(row["size"]) * 5.0 + 6.0 / _zoom
		draw_arc(row["pos"], radius, 0.0, TAU, 32, color, 2.0 / _zoom, true)
		var text := String(MARKS[status])
		if row["price_index"] != null: text += " x%.2f" % float(row["price_index"])
		_text(_town_label(row), text, color)
	for wid in data["caravans"]:
		var band := _caravan(String(wid))
		if band.is_empty(): continue
		var pos: Vector2 = band["pos"]
		var points := PackedVector2Array([pos])
		var direction := Vector2.ZERO
		# The native walker consumes this path from the front. Do not connect town
		# centres or run road_path: bends and the current leg come from the actual path.
		for point: Vector2 in band.get("path", []):
			points.append(point)
			if direction == Vector2.ZERO and pos.distance_squared_to(point) > 0.01:
				direction = pos.direction_to(point)
		if points.size() > 1:
			draw_polyline(points, Color(UiTheme.BLUE, 0.75), 2.0 / _zoom, true)
		if direction != Vector2.ZERO:
			var tip := pos + direction * 18.0 / _zoom
			var back := tip - direction * 10.0 / _zoom
			var side := direction.orthogonal() * 6.0 / _zoom
			draw_line(tip, back + side, UiTheme.BLUE, 2.0 / _zoom, true)
			draw_line(tip, back - side, UiTheme.BLUE, 2.0 / _zoom, true)
		var center := MapTokens.center(pos, _zoom)
		draw_arc(center, MapTokens.HIT_R / _zoom, 0.0, TAU, 32, UiTheme.BLUE, 2.0 / _zoom, true)
		_text(center + Vector2(0, 44) / _zoom, "%d cargo" % int(data["caravans"][wid]["quantity"]), UiTheme.BLUE)
