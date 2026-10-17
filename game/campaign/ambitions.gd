class_name Ambitions
extends RefCounted
## The dynasty's long-term goals. Each is measured from the real campaign state (dragons, battles, conquests,
## coin, succession), never from a separate score. Completing SIX of the eight crowns the campaign as a
## victory ("Dynasty Triumphant"); the player may keep playing afterwards. The founding line dying out is defeat.
const TO_WIN := 6
const LIST := [
	{"id": "saddle", "name": "Take the Saddle", "text": "Bond a rider to an adult dragon of your house."},
	{"id": "blooded", "name": "Blooded", "text": "Win five battles."},
	{"id": "dragonfire", "name": "Dragonfire", "text": "Lead a dragon into battle and win."},
	{"id": "plunder", "name": "Raider's Fortune", "text": "Carry off 400 coins in raids."},
	{"id": "banner", "name": "Plant the Banner", "text": "Conquer a settlement by siege."},
	{"id": "realm", "name": "Realm Breaker", "text": "Conquer three settlements, or bring a rival realm's seat into yours."},
	{"id": "brood", "name": "Brood Keeper", "text": "Hatch a dragon egg of your house."},
	{"id": "treasury", "name": "Golden House", "text": "Grow your house purse to twice what it held when you took the throne."},
]

static func _state(game) -> Dictionary:
	var st: Dictionary = Warfare._state(game)
	if not st.has("ambitions_done"): st["ambitions_done"] = {}
	return st

static func _house_purse(game) -> float:
	return float(Feudal._payer(game).get("purse", 0.0))

## {id: {"name","text","done","progress"}} in LIST order.
static func status(game) -> Array:
	var st := _state(game)
	if not st.has("start_purse") and not Dynasty.selected(game).is_empty():
		st["start_purse"] = _house_purse(game)
	var household := str(game.world.get("player_house", {}).get("household_uid", ""))
	var house := str(game.world.get("player_house", {}).get("house_uid", ""))
	var mine: Array = []
	for row: Dictionary in game.world.get("dragons", {}).get("records", {}).values():
		if str(row.get("owner_household_uid", "")) == household or (house != "" and str(row.get("owner_house_uid", "")) == house):
			mine.append(row)
	var bonded := 0
	var hatched := 0
	for row: Dictionary in mine:
		if bool(row.get("alive", false)) and str(row.get("stage", "")) == "adult" and str(row.get("rider_person_uid", "")) != "": bonded += 1
		for e in row.get("history", []):
			if e is Dictionary and str(e.get("kind", "")) == "hatched": hatched += 1
	var conquests: Array = st.get("conquests", [])
	var seat_taken := false
	for c: Dictionary in conquests:
		for fid in game.world.get("factions", {}):
			if str(game.world["factions"][fid].get("capital", "")) == str(c.get("town_id", "")) and str(c.get("from", "")) != Warfare.player_faction(game): seat_taken = true
		if bool(game.world.get("towns", {}).get(str(c.get("town_id", "")), {}).get("capital", false)): seat_taken = true
	var won := int(st.get("battles_won", 0))
	var plunder := float(st.get("raided_coin", 0.0)) / Item.COIN
	var start := float(st.get("start_purse", 0.0))
	var purse := _house_purse(game)
	var values := {
		"saddle": [bonded >= 1, "%d bonded adult dragon%s" % [bonded, "" if bonded == 1 else "s"]],
		"blooded": [won >= 5, "%d / 5 battles won" % won],
		"dragonfire": [int(st.get("dragon_victories", 0)) >= 1, "%d dragon victories" % int(st.get("dragon_victories", 0))],
		"plunder": [plunder >= 400.0, "%d / 400 coins" % int(plunder)],
		"banner": [conquests.size() >= 1, "%d settlements conquered" % conquests.size()],
		"realm": [conquests.size() >= 3 or seat_taken, "%d / 3 conquests%s" % [conquests.size(), " · a realm seat taken" if seat_taken else ""]],
		"brood": [hatched >= 1, "%d hatched" % hatched],
		"treasury": [start > 0.0 and purse >= start * 2.0, "%d%% of the goal" % int(clampf(purse / maxf(1.0, start * 2.0), 0.0, 9.99) * 100.0)],
	}
	var out: Array = []
	for a: Dictionary in LIST:
		var v: Array = values[a["id"]]
		var done := bool(v[0]) or bool(st["ambitions_done"].has(a["id"]))
		out.append({"id": a["id"], "name": a["name"], "text": a["text"], "done": done, "progress": v[1]})
	return out

static func completed(game) -> int:
	var n := 0
	for a: Dictionary in status(game):
		if a["done"]: n += 1
	return n

## Records newly completed ambitions (they stay completed) and opens the victory screen once.
static func check(game) -> void:
	if Dynasty.selected(game).is_empty(): return
	var st := _state(game)
	for a: Dictionary in status(game):
		if a["done"] and not st["ambitions_done"].has(a["id"]):
			st["ambitions_done"][a["id"]] = int(game.day)
			var line := "Ambition achieved: %s. (%d of %d needed for triumph)" % [a["name"], st["ambitions_done"].size(), TO_WIN]
			CampaignWorld.log_event(game, line)
			notify(game, line)
	if st["ambitions_done"].size() >= TO_WIN and not bool(st.get("victory_seen", false)):
		st["victory_seen"] = true
		st["victory_day"] = int(game.day)
		st["pending_victory"] = true

## Short messages the map shows as toasts (kept in the world so they survive a screen change).
static func notify(game, text: String) -> void:
	var st := _state(game)
	if not st.has("toasts"): st["toasts"] = []
	st["toasts"].append(text)
	while st["toasts"].size() > 6: st["toasts"].pop_front()

static func take_toasts(game) -> Array:
	var st := _state(game)
	var out: Array = st.get("toasts", [])
	st["toasts"] = []
	return out
