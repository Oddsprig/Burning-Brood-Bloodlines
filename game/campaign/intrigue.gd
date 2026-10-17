class_name Intrigue
extends RefCounted
## Saved plots contain stable person/house IDs and their own rolls, never copies
## of people or purses. Previewing and resolving plots do not consume game.rng.
const SCHEMES := {
	"assassinate": {"name": "Assassinate", "coins": 40, "days": 30, "chance": 0.50, "discovery": 0.35,
		"effect": "An assassin attempts to murder this person."},
	"sway": {"name": "Sway", "coins": 15, "days": 14, "chance": 0.70, "discovery": 0.20,
		"effect": "Their town loses 15 loyalty to its lord; your standing with its realm rises by 8."},
	"fabricate_claim": {"name": "Fabricate claim", "coins": 30, "days": 35, "chance": 0.60, "discovery": 0.30,
		"effect": "Your house gains a claim on this person's town."},
}
const DISCOVERY_LOSS := 15
const AI_INTERVAL := 60
const LOG_LIMIT := 60

static func state(game) -> Dictionary:
	if not game.world.has("intrigue"):
		game.world["intrigue"] = {"plots": [], "log": [], "next_id": 1, "day": -1}
	return game.world["intrigue"]

## Restore integer fields after JSON loading; costs and probabilities stay floats.
static func after_load(game) -> void:
	var st := state(game)
	st["next_id"] = int(st.get("next_id", 1))
	st["day"] = int(st.get("day", -1))
	for plot: Dictionary in st["plots"]:
		for key in ["id", "days", "started", "left", "seed"]:
			if plot.has(key): plot[key] = int(plot[key])
	for entry: Dictionary in st["log"]:
		entry["day"] = int(entry["day"])

static func _house(game) -> String:
	return str(game.world.get("player_house", {}).get("house_uid", ""))

static func _skill(game) -> int:
	if not game.has_method("best_skill"): return 0
	return maxi(int(game.best_skill("judge_of_intent")), int(game.best_skill("negotiator")))

## Landed seats and their rank measure the defending house's political strength.
static func _strength(game, house_uid: String) -> float:
	var strength := 1.0
	for tid in game.world.get("towns", {}):
		var town: Dictionary = game.world["towns"][tid]
		if str(town.get("econ", {}).get("head", {}).get("house_uid", "")) != house_uid: continue
		var tier := str(game.world.get("feudal", {}).get("towns", {}).get(tid, {}).get("tier", "village"))
		strength += maxf(1.0, float(town.get("size", 1))) + (2.0 if tier == "sovereign" else 0.0)
	return minf(12.0, strength)

static func _offer(game, kind: String, loc: Dictionary, source: Dictionary, skill: int) -> Dictionary:
	var def: Dictionary = SCHEMES[kind]
	var row := Dynasty._row(loc, float(game.day))
	var strength := _strength(game, str(row["house_uid"]))
	return {"kind": kind, "name": str(def["name"]), "cost": float(def["coins"]) * Item.COIN, "days": int(def["days"]),
		"chance": clampf(float(def["chance"]) + skill * 0.025 - strength * 0.025, 0.10, 0.95),
		"discovery": clampf(float(def["discovery"]) + strength * 0.02 - skill * 0.012, 0.05, 0.85),
		"target_uid": str(row["person_uid"]), "target_house_uid": str(row["house_uid"]), "target_name": str(row["name"]),
		"town_id": str(row["town_id"]), "town_name": str(row["town_name"]), "faction_id": str(loc["town"].get("faction", "")),
		"source_house_uid": str(source["house_uid"]), "source_house_name": str(source["house_name"]),
		"source_faction_id": str(source["faction_id"])}

static func preview(game, target_uid: String, kind: String) -> Dictionary:
	if not SCHEMES.has(kind): return {"ok": false, "text": "Unknown scheme."}
	var mine: Dictionary = game.world.get("player_house", {})
	if _house(game) == "" or not Dynasty.ruler(game).get("alive", false):
		return {"ok": false, "text": "Choose a living house leader before plotting."}
	var loc := Dynasty._person(game, target_uid)
	if loc.is_empty(): return {"ok": false, "text": "That person is no longer alive."}
	var house := str(Persons.g(loc["person"], Persons.HOUSE_UID, ""))
	if house == "" or house == _house(game): return {"ok": false, "text": "Choose someone of another house."}
	var unit: Unit = Dynasty.bound_unit(game, Dynasty._row(loc, float(game.day)))
	if unit != null and unit.dead: return {"ok": false, "text": "That person has already died."}
	var source := {"house_uid": _house(game), "house_name": str(mine.get("house_name", "Your house")),
		"faction_id": Diplomacy.player_realm(game.world)}
	var offer := _offer(game, kind, loc, source, _skill(game))
	offer["review"] = offer.duplicate(true)
	offer["review"]["payer_household_uid"] = str(mine.get("household_uid", ""))
	offer["ok"] = true; offer["text"] = ""
	var payer := Feudal._payer(game)
	if payer.is_empty() or float(payer.get("purse", 0.0)) < float(offer["cost"]):
		offer["ok"] = false; offer["text"] = "Your house purse cannot cover the cost."
	if kind == "sway" and not game.world.get("feudal", {}).get("towns", {}).has(offer["town_id"]):
		offer["ok"] = false; offer["text"] = "That town has no lord to sway it against."
	if kind == "fabricate_claim" and Marriage.has_claim(game, str(offer["town_id"])):
		offer["ok"] = false; offer["text"] = "Your house already holds a claim on that town."
	for plot: Dictionary in state(game)["plots"]:
		if not bool(plot.get("ai", false)) and str(plot["source_house_uid"]) == _house(game) \
				and str(plot["target_uid"]) == target_uid and str(plot["kind"]) == kind:
			offer["ok"] = false; offer["text"] = "You already have this scheme in motion against that person."
	return offer

## Confirmation rechecks availability and coin, and rejects a changed preview.
static func start(game, target_uid: String, kind: String, review: Dictionary = {}) -> Dictionary:
	var offer := preview(game, target_uid, kind)
	if not offer.get("ok", false): return offer
	if not review.is_empty() and review != offer["review"]:
		return {"ok": false, "text": "The circumstances changed. Review the scheme again."}
	var payer := Feudal._payer(game)
	payer["purse"] = float(payer["purse"]) - float(offer["cost"])
	var plot := _enqueue(game, offer, false, int(game.day))
	var text := "%s plot against %s begun (%d days)." % [offer["name"], offer["target_name"], int(offer["days"])]
	_log(game, text, int(game.day))
	game.changed.emit()
	return {"ok": true, "text": text, "plot": plot}

static func _enqueue(game, offer: Dictionary, ai: bool, day: int) -> Dictionary:
	var st := state(game)
	var serial := int(st.get("next_id", 1))
	st["next_id"] = serial + 1
	var plot := offer.duplicate(true)
	for key in ["review", "ok", "text"]: plot.erase(key)
	plot["id"] = serial; plot["ai"] = ai; plot["started"] = day
	plot["left"] = int(plot["days"]); plot["status"] = "active"; plot["discovered"] = false
	plot["seed"] = hash([int(game.world.get("seed", 0)), serial, day, plot["source_house_uid"], plot["target_uid"], plot["kind"]]) & 0x7fffffff
	st["plots"].append(plot)
	return plot

## Only the player's own operations are visible before a hostile plot is uncovered.
static func active(game) -> Array:
	var out: Array = []
	for plot: Dictionary in state(game)["plots"]:
		if not bool(plot.get("ai", false)) and str(plot["source_house_uid"]) == _house(game): out.append(plot)
	return out

## The optional calendar day lets Warfare's multi-day advances tick each midnight
## exactly once without changing game.day. Repeated calls for a day are harmless.
static func daily(game, day: int = -1) -> void:
	if _house(game) == "": return
	if day < 0: day = int(game.day)
	var st := state(game)
	if day <= int(st.get("day", -1)): return
	st["day"] = day
	var keep: Array = []
	var killed := false
	for plot: Dictionary in st["plots"]:
		if day <= int(plot["started"]):
			keep.append(plot); continue
		plot["left"] = maxi(0, int(plot["left"]) - 1)
		if int(plot["left"]) > 0:
			keep.append(plot)
		elif _resolve(game, plot, day):
			killed = true
	st["plots"] = keep
	if killed:
		Feudal.finish(game)
		Diplomacy.sync_dynasty(game)
	_ai(game, day)

static func _roll(rng: RandomNumberGenerator, chance: float) -> bool:
	var value := rng.randf()
	return chance >= 1.0 or (chance > 0.0 and value < chance)

static func _resolve(game, plot: Dictionary, day: int) -> bool:
	var ai := bool(plot.get("ai", false))
	var loc := Dynasty._person(game, str(plot["target_uid"]))
	var kind := str(plot["kind"])
	var valid := not loc.is_empty()
	if valid:
		var bound: Unit = Dynasty.bound_unit(game, Dynasty._row(loc, float(game.day)))
		valid = (bound == null or not bound.dead) and str(Persons.g(loc["person"], Persons.HOUSE_UID, "")) == str(plot["target_house_uid"])
		if ai: valid = valid and str(plot["target_house_uid"]) == _house(game)
		else: valid = valid and str(plot["source_house_uid"]) == _house(game)
		if kind != "assassinate":
			valid = valid and str(loc["town"]["id"]) == str(plot["town_id"]) \
				and str(loc["town"].get("faction", "")) == str(plot["faction_id"])
		if kind == "sway":
			valid = valid and game.world.get("feudal", {}).get("towns", {}).has(plot["town_id"])
		if kind == "fabricate_claim": valid = valid and not Marriage.has_claim(game, str(plot["town_id"]))
	if not valid:
		plot["status"] = "cancelled"
		if not ai: _log(game, "%s plot against %s ended: the target or town is no longer available." % [plot["name"], plot["target_name"]], day)
		return false
	var rng := RandomNumberGenerator.new(); rng.seed = int(plot["seed"])
	var discovered := _roll(rng, float(plot["discovery"]))
	var success := _roll(rng, float(plot["chance"]))
	plot["discovered"] = discovered
	if ai and discovered:
		plot["status"] = "foiled"
		_log(game, "Your spymaster uncovered and foiled House %s's assassination plot against %s." % [plot["source_house_name"], plot["target_name"]], day)
		return false
	if not ai and discovered:
		var fid := str(loc["town"].get("faction", ""))
		Diplomacy.add_earned(game, fid, -DISCOVERY_LOSS, "Your intrigue was discovered.")
		_log(game, "Your %s plot against %s was discovered: -%d standing with %s." % [str(plot["name"]).to_lower(), plot["target_name"], DISCOVERY_LOSS, CampaignWorld.faction_name(fid)], day)
	if not success:
		plot["status"] = "failed"
		if ai: _log(game, "An attempt on %s's life failed; its sponsor is unknown." % plot["target_name"], day)
		else: _log(game, "%s plot against %s failed." % [plot["name"], plot["target_name"]], day)
		return false
	plot["status"] = "succeeded"
	match kind:
		"assassinate":
			_murder(game, loc)
			_log(game, ("%s was murdered by an unknown assassin." if ai else "Your assassins murdered %s.") % plot["target_name"], day)
			return true
		"sway":
			var row: Dictionary = game.world["feudal"]["towns"][plot["town_id"]]
			row["loyalty"] = maxf(0.0, float(row.get("loyalty", 65.0)) - 15.0)
			row["grievance"] = minf(100.0, float(row.get("grievance", 0.0)) + 5.0)
			Diplomacy.add_earned(game, str(plot["faction_id"]), 8, "Your sway scheme won influence.")
			_log(game, "%s was swayed: %s loses 15 loyalty to its lord; your standing with its realm rises by 8." % [plot["target_name"], plot["town_name"]], day)
		"fabricate_claim":
			Marriage.state(game)["claims"][str(plot["town_id"])] = {"through_uid": str(plot["target_uid"]), "day": day,
				"house_name": str(plot["source_house_name"]), "house_uid": str(plot["source_house_uid"]), "fabricated": true}
			_log(game, "Your house fabricated a claim on %s." % plot["town_name"], day)
	return false

## Reuse native noncombat Unit/loan cleanup, then the one casualty/census path.
## Children use that same path; People.casualty_rec handles their child counter.
static func _murder(game, loc: Dictionary) -> void:
	var p: Array = loc["person"]
	var f: Dictionary = loc["family"]
	var tid := str(loc["town"]["id"])
	var name := Persons.name_of(f, p, Persons.race_of(loc["econ"]))
	var role := str(p[4])
	var unit_uid := int(p[5])
	var unit: Unit = Dynasty.bound_unit(game, Dynasty._row(loc, float(game.day)))
	if unit_uid >= 0:
		Sickness._remove_unit(game, loc["town"], f, p, role, unit_uid, "%s was murdered." % name)
	if unit != null: unit.dead = true
	var previous: Array = Census._ctx.duplicate()
	Census.ctx("murdered", "an assassin's knife")
	People.casualty_rec(game, tid, int(f["id"]), name, "dead", role, p, unit_uid)
	if previous.is_empty(): Census.ctx_end()
	else: Census.ctx(str(previous[0]), str(previous[1]))

## One world-wide attempt per sixty days on average, capped at one active hostile
## operation. Both the daily roll and choices depend only on seed/day and real IDs.
static func _ai(game, day: int) -> void:
	for plot: Dictionary in state(game)["plots"]:
		if bool(plot.get("ai", false)): return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(game.world.get("seed", 0)), day, "intrigue-ai"]) & 0x7fffffff
	if rng.randi_range(1, AI_INTERVAL) != 1: return
	var targets := Dynasty.living_members(game)
	if targets.is_empty(): return
	var sources: Array = []
	var seen := {}
	for choice: Dictionary in Dynasty.choices(game):
		var house_uid := str(choice["house_uid"])
		if house_uid == _house(game) or seen.has(house_uid): continue
		var candidate := Dynasty._person(game, str(choice["ruler_uid"]))
		if candidate.is_empty(): continue
		if str(candidate["family"].get("household_uid", "")) == str(game.world.get("player_house", {}).get("household_uid", "")): continue
		if float(candidate["family"].get("purse", 0.0)) < float(SCHEMES["assassinate"]["coins"]) * Item.COIN: continue
		seen[house_uid] = true
		sources.append(candidate)
	if sources.is_empty(): return
	var source: Dictionary = sources[rng.randi_range(0, sources.size() - 1)]
	var target: Dictionary = targets[rng.randi_range(0, targets.size() - 1)]
	var loc := Dynasty._person(game, str(target["person_uid"]))
	if loc.is_empty(): return
	var person := Dynasty._row(source, float(game.day))
	var unit: Unit = Dynasty.bound_unit(game, person)
	var skill := maxi(unit.skill("judge_of_intent"), unit.skill("negotiator")) if unit != null and not unit.dead else 0
	var house := {"house_uid": str(person["house_uid"]), "house_name": str(source["family"].get("name", "?")),
		"faction_id": str(source["town"].get("faction", ""))}
	var offer := _offer(game, "assassinate", loc, house, skill)
	offer["discovery"] = clampf(float(offer["discovery"]) + _skill(game) * 0.015, 0.05, 0.95)
	source["family"]["purse"] = float(source["family"]["purse"]) - float(offer["cost"])
	_enqueue(game, offer, true, day)

static func _log(game, text: String, day: int) -> void:
	var st := state(game)
	st["log"].append({"day": day, "text": text})
	while st["log"].size() > LOG_LIMIT: st["log"].pop_front()
	CampaignWorld.log_event(game, text)
