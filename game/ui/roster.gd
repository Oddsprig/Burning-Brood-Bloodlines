class_name Roster
extends RefCounted
## Pure company-management operations (squads, promotion, dismissal, hiring). Each takes the Game
## (or any object with company/squads/stash/gold) and returns "" on success or a reason string.

const MAX_OFFICERS := 8   # one actual officer per 25 people at the 200-person cap
const MAX_TROOPS := 24    # per squad, plus its actual officer
const MAX_COMPANY := 200

## Captain first, then officers in company order.
static func leaders(game) -> Array:
	var out := []
	for u in game.company:
		if u.role == "captain":
			out.push_front(u)
		elif u.role == "officer":
			out.append(u)
	return out

static func troops_of(game, officer_uid: int) -> Array:
	return game.company.filter(func(u): return u.squad == officer_uid and not u.is_officer())

static func unassigned(game) -> Array:
	var lead := {}
	for l in leaders(game):
		lead[l.uid] = true
	return game.company.filter(func(u): return not u.is_officer() and not lead.has(u.squad))

static func officer_count(game) -> int:
	return game.company.filter(func(u): return u.role == "officer").size()

static func has_room(game, officer_uid: int) -> bool:
	return troops_of(game, officer_uid).size() < MAX_TROOPS

static func ensure_squad(game, officer_uid: int) -> void:
	if not game.squads.has(officer_uid):
		game.squads[officer_uid] = {"uniform": {}, "material": "any"}

static func move_troop(game, unit: Unit, officer_uid: int) -> String:
	if unit.is_officer():
		return "officers lead their own squads"
	if unit.squad == officer_uid:
		return ""
	if officer_uid != -1 and not has_room(game, officer_uid):
		return "that squad is full (%d troops)" % MAX_TROOPS
	unit.squad = officer_uid
	return ""

static func promote(game, unit: Unit) -> String:
	if unit.is_officer():
		return "already an officer"
	if officer_count(game) >= MAX_OFFICERS:
		return "the company already has %d officers" % MAX_OFFICERS
	unit.role = "officer"
	unit.squad = -1
	unit.overrides = {}
	unit.wage = maxi(unit.wage, 12)
	ensure_squad(game, unit.uid)
	if game.get("world") is Dictionary:
		Diplomacy.roster_changed(game)   # diplomacy: officers weigh double in the band make-up offset
	return ""

## Dismiss: gear goes to the stash; an officer's troops become unassigned.
static func dismiss(game, unit: Unit) -> String:
	if unit.role == "captain":
		return "the captain cannot be dismissed"
	if game.get("world") is Dictionary and game.world.has("towns"):
		if Mobilization.manages(game, unit):
			var returned: Dictionary = Mobilization.dismiss(game, unit)
			return "" if bool(returned.get("ok", false)) else String(returned.get("reason", "This soldier cannot return home here."))
		var town: Dictionary = game.world.get("towns", {}).get(unit.home_town, {})
		var family: Dictionary = People.fam_of(town, unit.family)
		if not Persons.by_uid(family, unit.uid).is_empty():
			return "This registered soldier needs an authorized return to their real home; dismissal cannot erase their person record."
	Outfit.strip(unit, game.stash)
	if unit.is_officer():
		for t in game.company:
			if t.squad == unit.uid:
				t.squad = -1
		game.squads.erase(unit.uid)
	game.company.erase(unit)
	if game.get("world") is Dictionary:
		Diplomacy.roster_changed(game)   # diplomacy: band make-up offset follows the roster
	return ""

## Hire fee and daily wage (recruit fields, with a fallback from skills if the generator left them 0).
static func hire_cost(u: Unit) -> int:
	if u.hire_cost > 0:
		return u.hire_cost
	var s := 0
	for k in u.skills:
		s += int(u.skills[k])
	return 40 + s * 12

static func wage_of(u: Unit) -> int:
	if u.wage > 0:
		return u.wage
	var s := 0
	for k in u.skills:
		s += int(u.skills[k])
	return 3 + s / 4

## Terms this company gets (Recruits.offer: best Negotiator applied) -> {hire_cost, wage}.
static func offer(game, recruit: Unit) -> Dictionary:
	return Recruits.offer(game, recruit)

## Hire a recruit from a town (Recruits.hire, at offer terms) into a squad (-1 = unassigned).
static func hire(game, town: Dictionary, recruit: Unit, officer_uid: int) -> String:
	if game.company.filter(func(u): return not u.dead).size() >= MAX_COMPANY:
		return "the company is full (%d people)" % MAX_COMPANY
	var cost := int(offer(game, recruit)["hire_cost"])
	if game.gold < cost:
		return "not enough coins (%d needed)" % cost
	if officer_uid != -1 and not has_room(game, officer_uid):
		return "that squad is full"
	if not Recruits.hire(game, town, recruit):
		return "could not hire"
	recruit.squad = officer_uid
	return ""
