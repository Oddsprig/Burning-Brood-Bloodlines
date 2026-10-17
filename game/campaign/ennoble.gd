class_name Ennoble
extends RefCounted
## A commoner raised to the nobility for a great deed in battle. He founds his own independent house (his family
## row becomes a house family: rank, house marriages, a line of his own) with a long loyalty tie to the house that
## raised him: the tie starts at 100 and fades 4 a year, about a generation of goodwill.
## Deeds that weigh in the contribution score:
##   - killed a dragon, the enemy commander or an enemy house member;
## One man per battle won: the greatest contribution (score below). A world cap on living houses keeps it bounded.
const TIE_START := 100.0
const TIE_FADE_PER_YEAR := 4.0

static func _state(game) -> Dictionary:
	if not game.world.has("ennoble"): game.world["ennoble"] = {"last": {}, "ties": {}, "raised": []}
	return game.world["ennoble"]

## The raising house's key: "player" for your house, else the army's faction.
static func _raiser(u: Unit) -> String:
	return "player" if u.faction == "player" else u.faction

## Per clash: counts each man's kills and deeds into acc ({"kills": {uid: n}, "deeds": {uid: text}, "by": {uid: Unit}}).
static func tally(game, r: Dictionary, leaders: Array, acc: Dictionary) -> void:
	for key in ["kills", "deeds", "by"]:
		if not acc.has(key): acc[key] = {}
	for pair in r.get("kill_pairs", []):
		var killer: Unit = pair[0]; var victim: Unit = pair[1]
		acc["by"][killer.uid] = killer
		acc["kills"][killer.uid] = int(acc["kills"].get(killer.uid, 0)) + 1
		if DragonCombat.is_dragon_unit(game, victim):
			acc["deeds"][killer.uid] = "slaying the dragon %s" % victim.name
		elif leaders.has(victim.uid) or BattleRounds.is_household(game, victim):
			acc["deeds"][killer.uid] = "slaying %s" % victim.name

## Contribution in one battle: a kill is 1, slaying a dragon 15, the enemy commander or an enemy house member 10.
static func score(acc: Dictionary, uid: int) -> float:
	var deed := str(acc.get("deeds", {}).get(uid, ""))
	return float(acc.get("kills", {}).get(uid, 0)) + (15.0 if deed.contains("dragon") else (10.0 if deed != "" else 0.0))

## After every battle won: the commoner of the winning side with the greatest contribution is raised, unless the
## world already has its full number of houses (then the summary still names him). Returns his summary row, or {}.
static func grant(game, side: int, acc: Dictionary) -> Dictionary:
	if side < 0 or acc.is_empty(): return {}
	var pick: Unit = null; var best := 0.0
	for u in (acc.get("by", {}) as Dictionary).values():
		if not _eligible(game, u, side): continue
		var sc := score(acc, u.uid)
		if sc > best: best = sc; pick = u
	if pick == null: return {}
	var deed := str(acc["deeds"].get(pick.uid, ""))
	var why := ("%s and %d kills" % [deed, int(acc["kills"].get(pick.uid, 0))]) if deed != "" else ("%d kills, the greatest contribution in the battle" % int(acc["kills"].get(pick.uid, 0)))
	if house_count(game) >= house_cap(game):
		return {"name": pick.name, "side": side, "fate": "honoured", "relation": "greatest contribution (%s); no house granted: the world has its full %d houses" % [why, house_cap(game)]}
	return _raise(game, pick, side, why)

## Living houses in the world (named, landed and ruling families; not common folk).
static func house_count(game) -> int:
	var n := 0
	for town in game.world.get("towns", {}).values():
		for f in town.get("econ", {}).get("fams", []):
			if not f.get("cohort", false) and not f.get("estate", false) and not f.get("gone", false) and str(f.get("household_uid", "")) != "": n += 1
	return n

## The most houses the world allows (new-game setting "house_cap"; default: the houses it began with plus 60).
static func house_cap(game) -> int:
	if not game.world.has("house_cap"):
		var setting := int(game.settings.get("house_cap", 0))
		game.world["house_cap"] = setting if setting > 0 else house_count(game) + 60
	return int(game.world["house_cap"])

static func _eligible(game, u: Unit, side: int) -> bool:
	return u != null and not u.dead and not Army.house_born(u) and not DragonCombat.is_dragon_unit(game, u) and _on_side(game, u, side)

static func _raise(game, u: Unit, side: int, why: String) -> Dictionary:
	var st := _state(game)
	var raiser := _raiser(u)
	var hh: Dictionary = Population.promote_ruler(game, u)
	if hh.is_empty() or not Army.house_born(u): return {}
	hh["prestige"] = float(hh.get("prestige", 0.0)) + 10.0
	hh["ennobled"] = {"by": raiser, "day": float(game.day), "deed": why}
	Families.add_hist(hh, "%s was raised to the nobility for %s." % [u.name, why], float(game.day))
	st["last"][raiser] = float(game.day)
	st["ties"][str(hh.get("founding_house_uid", ""))] = {"to": raiser, "since": float(game.day), "name": str(hh.get("name", ""))}
	(st["raised"] as Array).append({"name": u.name, "house": str(hh.get("name", "")), "by": raiser, "day": float(game.day), "deed": why})
	CampaignWorld.log_event(game, "%s was raised to the nobility for %s and founded House %s." % [u.name, why, str(hh.get("name", ""))])
	return {"name": u.name, "side": side, "fate": "raised", "relation": "raised to the nobility for " + why}

static func _on_side(game, u: Unit, side: int) -> bool:
	var st: Dictionary = game.pending_battle.get("rounds", {})
	if not st.is_empty(): return (st["pool"][side] as Array).has(u)
	return game.company.has(u) == (side == 0)

## Loyalty tie between a raised house and the house that raised it (0 when there is none or it has faded).
static func tie(game, founding_house_uid: String, raiser: String) -> float:
	var t: Dictionary = _state(game)["ties"].get(founding_house_uid, {})
	if t.is_empty() or str(t.get("to", "")) != raiser: return 0.0
	var years := (float(game.day) - float(t["since"])) / 120.0
	return maxf(0.0, TIE_START - TIE_FADE_PER_YEAR * years)
