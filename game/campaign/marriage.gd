class_name Marriage
extends RefCounted
## Arranged marriages between noble houses, betrothals, alliances and claims (CK3/AGOT-style dynasty play).
##
## People are the native register's real persons. A match brings the spouse INTO your household (they move town
## if needed, keeping their identity, birth house and kin links), so the native childbearing rules give the couple
## children of YOUR house, who become heirs under your succession law. The spouse's household pays a real dowry;
## you may add a real gift to sweeten the offer; dragon houses may send an egg with the bride or groom.
## Effects: an alliance with the spouse's house (their realm warms to yours; a vassal house's loyalty rises and
## defection becomes far less likely), and children of the match hold a CLAIM on the spouse's family seat when it
## is a ruling house: pressing it by siege makes the conquest welcome rather than resented.
## A refusal costs a little standing; nobody can be asked twice within a season.
## Other noble houses arrange their own matches across towns and realms. Those live in ai_links
## and use the same diplomacy bonus, not your alliance list. The bride joins the groom's house.
const GIFTS := [0.0, 0.02, 0.06]          # share of your house purse offered: none / modest / generous
const GIFT_NAMES := ["No gift", "Modest gift", "Generous gift"]
const DOWRY_SHARE := 0.03
const ASK_COOLDOWN := 30
const ACCEPT := 50.0

static func state(game) -> Dictionary:
	if not game.world.has("marriage"):
		game.world["marriage"] = {"alliances": {}, "claims": {}, "betrothals": [], "asked": {}, "history": []}
	return game.world["marriage"]

static func _house(game) -> String:
	return str(game.world.get("player_house", {}).get("house_uid", ""))

static func _household_uid(game) -> String:
	return str(game.world.get("player_house", {}).get("household_uid", ""))

## An alliance needs the same living couple, still married to one another and to your house.
static func alliance_holds(game, al: Dictionary) -> bool:
	var member := str(al.get("member_uid", ""))
	var spouse := str(al.get("spouse_uid", ""))
	var a := Dynasty._person(game, member)
	var b := Dynasty._person(game, spouse)
	if a.is_empty() or b.is_empty(): return false
	return str(Persons.g(a["person"], Persons.HOUSE_UID, "")) == _house(game) \
		and str(Persons.g(a["person"], Persons.SPOUSE_UID, "")) == spouse \
		and str(Persons.g(b["person"], Persons.SPOUSE_UID, "")) == member

## Even a non-ruling landed house can support a proposal to its realm.
static func ties_to(game, fid: String) -> bool:
	for al: Dictionary in game.world.get("marriage", {}).get("alliances", {}).values():
		var town: Dictionary = game.world.get("towns", {}).get(str(al.get("town_id", "")), {})
		if str(town.get("faction", "")) == fid and alliance_holds(game, al): return true
	return false

## Only the house currently holding the seat binds its realm to peace.
static func realm_allies(game) -> Dictionary:
	var out := {}
	var mine := Diplomacy.player_realm(game.world)
	for hh in game.world.get("marriage", {}).get("alliances", {}):
		var al: Dictionary = game.world["marriage"]["alliances"][hh]
		var town: Dictionary = game.world.get("towns", {}).get(str(al.get("town_id", "")), {})
		var fid := str(town.get("faction", ""))
		var head: Dictionary = town.get("econ", {}).get("head", {})
		var ruling := str(head.get("household_uid", "")) == str(hh) or (str(al.get("house_uid", "")) != "" and str(head.get("house_uid", "")) == str(al["house_uid"]))
		if fid != "" and fid != mine and ruling and alliance_holds(game, al): out[fid] = true
	return out

static func _ages(race: String) -> Dictionary:
	return People.ages(race)

static func _married(loc: Dictionary) -> bool:
	var p: Array = loc["person"]
	if str(Persons.g(p, Persons.SPOUSE_UID, "")) != "":
		var other := Dynasty._person(Game, str(p[Persons.SPOUSE_UID]))
		if not other.is_empty(): return true
	return not Persons.by_pid(loc["family"], int(Persons.g(p, Persons.SP, -1))).is_empty()

static func _betrothed(game, uid: String) -> bool:
	for b: Dictionary in state(game)["betrothals"]:
		if str(b["a"]) == uid or str(b["b"]) == uid: return true
	return false

## Your house's living members with their marriage standing.
static func family(game) -> Array:
	var out: Array = []
	for row: Dictionary in Dynasty.living_members(game):
		var loc := Dynasty._person(game, str(row["person_uid"]))
		if loc.is_empty(): continue
		var ab := _ages(str(row["race"]))
		row["married"] = _married(loc)
		row["betrothed"] = _betrothed(game, str(row["person_uid"]))
		row["adult"] = int(row["age"]) >= int(ab["adult"])
		row["can_betroth"] = not row["married"] and not row["betrothed"] and int(row["age"]) >= maxi(1, int(ab["adult"]) - 8) and int(row["age"]) < int(ab["elder"])
		row["spouse"] = Dynasty.person(game, str(row.get("spouse_uid", ""))) if str(row.get("spouse_uid", "")) != "" else {}
		out.append(row)
	out.sort_custom(func(a, b): return int(a["age"]) > int(b["age"]))
	return out

static func _rank(game, town_id: String) -> float:
	var town: Dictionary = game.world.get("towns", {}).get(town_id, {})
	var tier := str(game.world.get("feudal", {}).get("towns", {}).get(town_id, {}).get("tier", "village"))
	return float(int(town.get("size", 1))) + {"sovereign": 3.0, "county": 1.0}.get(tier, 0.0)

static func _player_rank(game) -> float:
	var sel := Dynasty.selected(game)
	var r := _rank(game, str(sel.get("town_id", "")))
	return r if bool(sel.get("holds_office", false)) else r - 2.0

static func _dragons_of(game, household_uid: String, house_uid: String = "") -> Array:
	var out: Array = []
	for row: Dictionary in game.world.get("dragons", {}).get("records", {}).values():
		if not bool(row.get("alive", false)): continue
		if str(row.get("owner_household_uid", "")) == household_uid or (house_uid != "" and str(row.get("owner_house_uid", "")) == house_uid): out.append(row)
	return out

## Unmarried people of other landed houses (ruling households and the tracked business-owning families of every
## settlement) who could marry this member and move into your household. Children can be betrothed to children.
static func candidates(game, member_uid: String) -> Array:
	var me := Dynasty._person(game, member_uid)
	if me.is_empty(): return []
	var my_sex := int(me["person"][2])
	var my_age := Persons.age_of(me["person"], float(game.day))
	var my_ab := _ages(Persons.race_of(me["econ"]))
	var child_match := my_age < int(my_ab["adult"])
	if child_match and my_age < int(my_ab["adult"]) - 6: return []
	var out: Array = []
	var house := _house(game)
	for town in game.world.get("towns", {}).values():
		var tid := str(town.get("id", ""))
		var e: Dictionary = town.get("econ", {})
		var head: Dictionary = e.get("head", {})
		var ruling_hh := str(head.get("household_uid", ""))
		var heir_uid := str(Dynasty.heir(game, tid).get("person_uid", ""))
		var race := Persons.race_of(e)
		var ab := _ages(race)
		for f in e.get("fams", []):
			if f.get("cohort", false) or f.get("estate", false) or f.get("gone", false): continue
			if str(f.get("household_uid", "")) == "" or str(f.get("household_uid", "")) == _household_uid(game): continue
			var ruling := str(f.get("household_uid", "")) == ruling_hh
			for p in Persons.pp(f) + Persons.kp(f):
				var uid := str(Persons.g(p, Persons.PERSON_UID, ""))
				if uid == "" or uid == str(head.get("person_uid", "")) or uid == heir_uid: continue
				if int(p[2]) == my_sex or String(p[4]) != "" or int(p[5]) >= 0: continue
				if str(Persons.g(p, Persons.HOUSE_UID, "")) == house: continue
				var age := Persons.age_of(p, float(game.day))
				if child_match:
					if age >= int(ab["adult"]) + 4 or age < int(ab["adult"]) - 6: continue
				elif age < int(ab["adult"]) or age >= int(ab["elder"]) or int(p[6]) != 0: continue
				if absi(age - my_age) > 16: continue
				var loc := {"town": town, "econ": e, "family": f, "person": p, "alive": true}
				if not Dynasty._living(game, tid, f, p) or _married(loc) or _betrothed(game, uid): continue
				out.append(_offer(game, member_uid, loc, tid, 0, ruling))
	out.sort_custom(func(a, b): return (1 if a["ruling_house"] else 0) * 15 + float(a["score"]) > (1 if b["ruling_house"] else 0) * 15 + float(b["score"]))
	return out.slice(0, 24)

## Deterministic acceptance with the reasons shown to the player (CK3-style transparency).
static func _offer(game, member_uid: String, loc: Dictionary, tid: String, gift_tier: int, ruling: bool = true) -> Dictionary:
	var town: Dictionary = loc["town"]
	var f: Dictionary = loc["family"]
	var p: Array = loc["person"]
	var row := Dynasty._row(loc, float(game.day))
	var fid := str(town.get("faction", ""))
	var reasons: Array = []
	var score := 40.0
	var rank_diff := (_player_rank(game) - (_rank(game, tid) if ruling else _rank(game, tid) - 3.0)) * 6.0
	score += rank_diff; reasons.append(["Standing of your house vs theirs", rank_diff])
	var mine := Warfare.player_faction(game)
	if fid == mine:
		score += 10.0; reasons.append(["Same realm", 10.0])
	else:
		var st := float(Diplomacy.standing(game, fid)) / 3.0
		score += st; reasons.append(["Your standing with " + CampaignWorld.faction_name(fid), st])
		if CampaignWorld.is_hostile(game, fid):
			score -= 35.0; reasons.append(["Their realm is hostile to yours", -35.0])
	var dragons := 0
	for d: Dictionary in _dragons_of(game, _household_uid(game), _house(game)):
		if str(d.get("stage", "")) == "adult": dragons += 1
	if dragons > 0:
		var dv := minf(24.0, dragons * 8.0)
		score += dv; reasons.append(["Your house rides dragons", dv])
	var me := Dynasty._person(game, member_uid)
	var my_age := Persons.age_of(me["person"], float(game.day)) if not me.is_empty() else 30
	var gap := absf(float(my_age - int(row["age"])))
	if gap > 8.0:
		var gp := -(gap - 8.0) * 1.5
		score += gp; reasons.append(["Age difference", gp])
	if str(f.get("household_uid", "")) in state(game)["alliances"]:
		score += 10.0; reasons.append(["Already allied by marriage", 10.0])
	var purse := float(Feudal._payer(game).get("purse", 0.0))
	var gift := floorf(purse * float(GIFTS[clampi(gift_tier, 0, GIFTS.size() - 1)]))
	if gift_tier > 0:
		var gv := 12.0 if gift_tier == 1 else 28.0
		score += gv; reasons.append([GIFT_NAMES[gift_tier], gv])
	var dowry := floorf(maxf(0.0, float(f.get("purse", 0.0))) * DOWRY_SHARE)
	var egg := {}
	for d: Dictionary in _dragons_of(game, str(f.get("household_uid", ""))):
		if str(d.get("stage", "")) == "egg" and score >= ACCEPT + 10.0: egg = d; break
	return {"person_uid": str(row["person_uid"]), "name": str(row["name"]), "age": int(row["age"]), "sex": int(row["sex"]),
		"race": str(row["race"]), "house_name": str(f.get("name", "")), "household_uid": str(f.get("household_uid", "")),
		"town_id": tid, "town_name": str(town.get("name", "")), "faction_id": fid, "score": snappedf(score, 0.1),
		"accepts": score >= ACCEPT, "reasons": reasons, "gift": gift, "gift_tier": gift_tier, "dowry": dowry,
		"egg_uid": str(egg.get("id", "")), "egg_name": str(egg.get("name", "")), "member_uid": member_uid,
		"row": row, "ruling_house": ruling}

static func offer(game, member_uid: String, candidate_uid: String, gift_tier: int) -> Dictionary:
	var loc := Dynasty._person(game, candidate_uid)
	if loc.is_empty(): return {"accepts": false, "score": 0.0, "reasons": [], "error": "That person is no longer available."}
	var ruling := str(loc["family"].get("household_uid", "")) == str(loc["town"].get("econ", {}).get("head", {}).get("household_uid", ""))
	return _offer(game, member_uid, loc, str(loc["town"]["id"]), gift_tier, ruling)

## Propose; returns {ok, accepted, text}. Accepted proposals wed at once (adults) or become a betrothal (children).
static func propose(game, member_uid: String, candidate_uid: String, gift_tier: int) -> Dictionary:
	var st := state(game)
	var key := member_uid + "|" + candidate_uid
	if int(st["asked"].get(candidate_uid, -999)) + ASK_COOLDOWN > int(game.day):
		return {"ok": false, "text": "They were asked recently; try again next season."}
	var o := offer(game, member_uid, candidate_uid, gift_tier)
	if o.has("error"): return {"ok": false, "text": o["error"]}
	var me := Dynasty._person(game, member_uid)
	if me.is_empty(): return {"ok": false, "text": "Your family member is no longer available."}
	st["asked"][candidate_uid] = int(game.day)
	if not bool(o["accepts"]):
		if str(o["faction_id"]) != Warfare.player_faction(game):
			CampaignWorld.change_rep(game, str(o["faction_id"]), -3, "A marriage proposal was refused.")
		_log(game, "House %s refused the match between %s and %s." % [o["house_name"], me_name(game, member_uid), o["name"]])
		return {"ok": true, "accepted": false, "text": "House %s refuses. (acceptance %.0f of %.0f needed)" % [o["house_name"], float(o["score"]), ACCEPT]}
	# Gift: real coin from your house purse to theirs.
	var payer := Feudal._payer(game)
	var their: Dictionary = Dynasty._person(game, candidate_uid)["family"]
	var gift := minf(float(o["gift"]), float(payer.get("purse", 0.0)))
	if gift > 0.0:
		payer["purse"] = float(payer["purse"]) - gift
		their["purse"] = float(their.get("purse", 0.0)) + gift
	var my_age := Persons.age_of(me["person"], float(game.day))
	if my_age < int(_ages(Persons.race_of(me["econ"]))["adult"]):
		st["betrothals"].append({"a": member_uid, "b": candidate_uid, "day": int(game.day), "dowry_owed": true})
		_log(game, "%s is betrothed to %s of House %s. They will wed when %s comes of age." % [me_name(game, member_uid), o["name"], o["house_name"], me_name(game, member_uid)])
		return {"ok": true, "accepted": true, "text": "Betrothal agreed. The wedding will follow when %s comes of age." % me_name(game, member_uid)}
	var w := wed(game, member_uid, candidate_uid)
	return {"ok": bool(w.get("ok", false)), "accepted": bool(w.get("ok", false)), "text": str(w.get("text", ""))}

static func me_name(game, uid: String) -> String:
	return str(Dynasty.person(game, uid).get("name", "your kin"))

## The wedding: the spouse joins your member's household (moving town if needed), dowry and egg follow,
## the alliance and any claim are recorded.
static func wed(game, member_uid: String, spouse_uid: String) -> Dictionary:
	var me := Dynasty._person(game, member_uid)
	var sp := Dynasty._person(game, spouse_uid)
	if me.is_empty() or sp.is_empty(): return {"ok": false, "text": "The wedding could not take place: one of the pair is gone."}
	var from_town: Dictionary = sp["town"]
	var from_e: Dictionary = sp["econ"]; var from_f: Dictionary = sp["family"]; var p: Array = sp["person"]
	var to_e: Dictionary = me["econ"]; var to_f: Dictionary = me["family"]; var mp: Array = me["person"]
	var their_house_uid := str(Persons.g(p, Persons.HOUSE_UID, ""))
	var their_household := str(from_f.get("household_uid", ""))
	var their_house_name := str(from_f.get("name", ""))
	var spouse_name := Persons.name_of(from_f, p, Persons.race_of(from_e))
	var day := float(game.day)
	# Dowry: real coin from the spouse's household to yours.
	var dowry := floorf(maxf(0.0, float(from_f.get("purse", 0.0))) * DOWRY_SHARE)
	if dowry > 0.0:
		from_f["purse"] = float(from_f["purse"]) - dowry
		to_f["purse"] = float(to_f.get("purse", 0.0)) + dowry
	# Move the person record.
	var cat_key := "m" if int(p[2]) == 0 else "f"
	Persons.forget(from_e, from_f, p)
	Persons.pp(from_f).erase(p)
	from_f[cat_key] = maxi(0, int(from_f.get(cat_key, 0)) - 1)
	if not is_same(from_e, to_e):
		p[0] = int(to_e.get("next_pid", 1)); to_e["next_pid"] = int(p[0]) + 1
		p[Persons.MO] = -1; p[Persons.FA] = -1
		from_e["pop"] = maxi(0, int(from_e.get("pop", 0)) - 1); to_e["pop"] = int(to_e.get("pop", 0)) + 1
		from_e["adults"] = maxi(0, int(from_e.get("adults", 0)) - 1); to_e["adults"] = int(to_e.get("adults", 0)) + 1
	p[4] = ""
	to_f[cat_key] = int(to_f.get(cat_key, 0)) + 1
	Persons.pp(to_f).append(p)
	p[Persons.SP] = int(mp[0]); mp[Persons.SP] = int(p[0])
	Persons._identity_pad(p); Persons._identity_pad(mp)
	p[Persons.SPOUSE_UID] = member_uid; mp[Persons.SPOUSE_UID] = spouse_uid
	to_f.erase("nxa")
	Families.event(to_f, "married", [Persons.name_of(to_f, mp, Persons.race_of(to_e)), spouse_name], day)
	Families.event(from_f, "wed_away", [spouse_name, str(to_f.get("name", ""))], day)
	Families.reassign(from_e, from_f); Families.reassign(to_e, to_f)
	Dynasty.record_person(to_e, to_f, p, true)
	Dynasty.record_person(to_e, to_f, mp, true)
	# Egg dowry from a dragon house.
	var egg_text := ""
	var st := state(game)
	var ruler := Dragons._person(game, str(game.world.get("player_house", {}).get("ruler_uid", "")))
	if not ruler.is_empty():
		for d: Dictionary in game.world.get("dragons", {}).get("records", {}).values():
			if bool(d.get("alive", false)) and str(d.get("stage", "")) == "egg" and str(d.get("owner_household_uid", "")) == their_household:
				if their_household in st["alliances"]: break
				Dragons._set_owner(d, ruler)
				var home := str(Dynasty.selected(game).get("town_id", ""))
				d["estate_town_id"] = home; d["location_town_id"] = home
				d["custodian_person_uid"] = str(ruler["person_uid"]) if Dragons._present(ruler, home) else ""
				Dragons._history(game, d, "dowry", {"from_household_uid": their_household})
				egg_text = " The %s comes with the match as a dowry." % d.get("name", "dragon egg")
				break
	# Alliance and its political effects.
	st["alliances"][their_household] = {"house_uid": their_house_uid, "house_name": their_house_name, "town_id": str(from_town.get("id", "")),
		"day": int(day), "spouse_uid": spouse_uid, "member_uid": member_uid}
	var their_fid := str(from_town.get("faction", ""))
	var mine := Warfare.player_faction(game)
	var political := ""
	Diplomacy.sync_dynasty(game)
	if their_fid != "" and their_fid != mine and realm_allies(game).has(their_fid):
		political = " %s is allied to your realm while this marriage holds (+%d standing)." % [Diplomacy.cap(CampaignWorld.faction_the(their_fid)), Diplomacy.DYNASTY_STANDING]
	var row: Dictionary = game.world.get("feudal", {}).get("towns", {}).get(str(from_town.get("id", "")), {})
	if not row.is_empty() and their_fid == mine:
		row["loyalty"] = minf(100.0, float(row["loyalty"]) + 15.0)
		row["grievance"] = maxf(0.0, float(row["grievance"]) - 10.0)
		political = " The vassal house of %s is bound closer to you." % from_town.get("name", "")
	# A claim on the spouse's family seat (their children will hold it).
	if str(from_town.get("econ", {}).get("head", {}).get("household_uid", "")) == their_household:
		st["claims"][str(from_town.get("id", ""))] = {"through_uid": spouse_uid, "day": int(day), "house_name": their_house_name}
	var text := "%s weds %s of House %s, who joins your household at %s.%s%s%s" % [me_name(game, member_uid), spouse_name, their_house_name,
		str(me["town"].get("name", "")), (" Dowry: %d coins." % int(dowry / Item.COIN)) if dowry > 0.0 else "", egg_text, political]
	_log(game, text)
	game.changed.emit()
	return {"ok": true, "text": text}

static func _log(game, text: String) -> void:
	var st := state(game)
	st["history"].append({"day": int(game.day), "text": text})
	while st["history"].size() > 40: st["history"].pop_front()
	CampaignWorld.log_event(game, text)
	Ambitions.notify(game, text)

## Daily: betrothed children wed when they come of age; allied vassals keep faith; broken pairs are dissolved.
static func daily(game) -> void:
	if not game.world.has("marriage") or Dynasty.selected(game).is_empty(): return
	var st := state(game)
	var keep: Array = []
	for b: Dictionary in st["betrothals"]:
		var a := Dynasty._person(game, str(b["a"]))
		var c := Dynasty._person(game, str(b["b"]))
		if a.is_empty() or c.is_empty():
			_log(game, "A betrothal ended: one of the pair has died.")
			continue
		if Persons.age_of(a["person"], float(game.day)) >= int(_ages(Persons.race_of(a["econ"]))["adult"]):
			wed(game, str(b["a"]), str(b["b"]))
			continue
		keep.append(b)
	st["betrothals"] = keep
	for hh in st["alliances"].keys():
		var al: Dictionary = st["alliances"][hh]
		if not alliance_holds(game, al):
			st["alliances"].erase(hh)
			_log(game, "The marriage alliance with House %s ends: the couple is no longer living and married." % al.get("house_name", "?"))
			continue
		var row: Dictionary = game.world.get("feudal", {}).get("towns", {}).get(str(al.get("town_id", "")), {})
		if not row.is_empty() and str(game.world["towns"].get(str(al["town_id"]), {}).get("faction", "")) == Warfare.player_faction(game):
			row["loyalty"] = minf(100.0, float(row["loyalty"]) + 0.15)
	if st.has("ai_links"):
		for key in st["ai_links"].keys():
			var link: Dictionary = st["ai_links"][key]
			if not _ai_couple_holds(game, link):
				st["ai_links"].erase(key)
				_log(game, "The marriage between House %s and House %s ends: the couple is no longer living and married." % [link.get("groom_house_name", "?"), link.get("bride_house_name", "?")])
	if not st.has("ai_next"):
		st["ai_next"] = int(game.day) + 7
	elif int(game.day) >= int(st["ai_next"]):
		arrange_ai(game)
	Diplomacy.sync_dynasty(game)

static func has_claim(game, town_id: String) -> bool:
	return state(game)["claims"].has(town_id)

static func children_of(game, uid: String) -> Array:
	var out: Array = []
	for row: Dictionary in Dynasty.living_members(game):
		if str(row.get("mother_uid", "")) == uid or str(row.get("father_uid", "")) == uid: out.append(row)
	return out

## Living ruling-house AI marriages whose realms differ. Pair key -> true. Does not create save state.
static func ai_realm_pairs(game) -> Dictionary:
	var out := {}
	var links: Dictionary = game.world.get("marriage", {}).get("ai_links", {})
	for key in links.keys():
		var link: Dictionary = links[key]
		if not bool(link.get("ruling", false)) or not _ai_couple_holds(game, link): continue
		var a := str(link.get("faction_a", ""))
		var b := str(link.get("faction_b", ""))
		if a == "" or b == "" or a == b: continue
		out[Diplomacy.pair_key(a, b)] = true
	return out

static func _ai_couple_holds(game, link: Dictionary) -> bool:
	var groom := str(link.get("groom_uid", ""))
	var bride := str(link.get("bride_uid", ""))
	var a := Dynasty._person(game, groom)
	var b := Dynasty._person(game, bride)
	if a.is_empty() or b.is_empty(): return false
	return str(Persons.g(a["person"], Persons.SPOUSE_UID, "")) == bride \
		and str(Persons.g(b["person"], Persons.SPOUSE_UID, "")) == groom

static func _is_player_side(game, f: Dictionary, p: Array) -> bool:
	var hh := _household_uid(game)
	var house := _house(game)
	if hh != "" and str(f.get("household_uid", "")) == hh: return true
	if house != "" and str(Persons.g(p, Persons.HOUSE_UID, "")) == house: return true
	return false

## Empty when this noble adult can be matched. Heads and heirs stay on the seat.
static func _ai_blocked(game, town: Dictionary, f: Dictionary, p: Array, heir_uid: String = "") -> String:
	if f.get("cohort", false) or f.get("estate", false) or f.get("gone", false): return "is not of a noble house"
	if str(f.get("household_uid", "")) == "": return "is not of a noble house"
	if _is_player_side(game, f, p): return "is of your own house"
	var e: Dictionary = town.get("econ", {})
	var uid := str(Persons.g(p, Persons.PERSON_UID, ""))
	if uid == "" or uid == str(e.get("head", {}).get("person_uid", "")): return "holds the seat"
	var tid := str(town.get("id", ""))
	if heir_uid == "": heir_uid = str(Dynasty.heir(game, tid).get("person_uid", ""))
	if heir_uid != "" and uid == heir_uid: return "is the heir"
	if String(p[4]) != "" or int(p[5]) >= 0: return "is away from home"
	if int(p[6]) != 0: return "is not a free adult"
	var race := Persons.family_race(e, f)
	var ab := _ages(race)
	var age := Persons.age_of(p, float(game.day))
	if age < int(ab["adult"]) or age >= int(ab["elder"]): return "is outside marrying age"
	var loc := {"town": town, "econ": e, "family": f, "person": p, "alive": true}
	if not Dynasty._living(game, tid, f, p) or _married(loc) or _betrothed(game, uid): return "is not free to marry"
	return ""

## Acceptance from the groom's house, not the player's. Peace between realms can clear the line; war cannot.
static func _ai_score(game, groom_loc: Dictionary, bride_loc: Dictionary) -> Dictionary:
	var gt: Dictionary = groom_loc["town"]
	var bt: Dictionary = bride_loc["town"]
	var gf: Dictionary = groom_loc["family"]
	var bf: Dictionary = bride_loc["family"]
	var gtid := str(gt.get("id", ""))
	var btid := str(bt.get("id", ""))
	var fa := str(gt.get("faction", ""))
	var fb := str(bt.get("faction", ""))
	var groom_ruling := str(gf.get("household_uid", "")) == str(gt.get("econ", {}).get("head", {}).get("household_uid", ""))
	var bride_ruling := str(bf.get("household_uid", "")) == str(bt.get("econ", {}).get("head", {}).get("household_uid", ""))
	var score := 40.0
	var gr := _rank(game, gtid) - (0.0 if groom_ruling else 3.0)
	var br := _rank(game, btid) - (0.0 if bride_ruling else 3.0)
	score += (gr - br) * 6.0
	if fa == fb:
		score += 10.0
	else:
		score += Diplomacy.relation(game.world, fa, fb) / 3.0
		var rel_state := Diplomacy.state(game.world, fa, fb)
		if rel_state == Diplomacy.WAR or rel_state == Diplomacy.HOSTILE:
			score -= 35.0
		else:
			score += 12.0
	if groom_ruling or bride_ruling:
		score += 8.0
	var gap := absf(float(Persons.age_of(groom_loc["person"], float(game.day)) - Persons.age_of(bride_loc["person"], float(game.day))))
	if gap > 8.0:
		score -= (gap - 8.0) * 1.5
	return {"score": score, "accepts": score >= ACCEPT, "ruling": groom_ruling or bride_ruling,
		"faction_a": fa, "faction_b": fb}

static func _ai_pool(game, sex: int) -> Array:
	var out: Array = []
	var ids: Array = game.world.get("towns", {}).keys()
	ids.sort()
	for tid in ids:
		var town: Dictionary = game.world["towns"][tid]
		var e: Dictionary = town.get("econ", {})
		var heir_uid := str(Dynasty.heir(game, str(tid)).get("person_uid", ""))
		for f in e.get("fams", []):
			if not f is Dictionary: continue
			for p in Persons.pp(f):
				if int(p[2]) != sex: continue
				if _ai_blocked(game, town, f, p, heir_uid) != "": continue
				out.append({"town": town, "econ": e, "family": f, "person": p, "alive": true})
	return out

## One accepted AI match, if any. The next scan waits seven days either way.
static func arrange_ai(game) -> Dictionary:
	var st := state(game)
	st["ai_next"] = int(game.day) + 7
	if not game.world.has("towns"): return {"ok": true, "arranged": false, "reason": "No settlements."}
	var men := _ai_pool(game, 0)
	var women := _ai_pool(game, 1)
	for man: Dictionary in men:
		for woman: Dictionary in women:
			if str(man["town"].get("id", "")) == str(woman["town"].get("id", "")): continue
			if str(man["family"].get("household_uid", "")) == str(woman["family"].get("household_uid", "")): continue
			if Persons.family_race(man["econ"], man["family"]) != Persons.family_race(woman["econ"], woman["family"]): continue
			if absi(Persons.age_of(man["person"], float(game.day)) - Persons.age_of(woman["person"], float(game.day))) > 16: continue
			var offer := _ai_score(game, man, woman)
			if not bool(offer["accepts"]): continue
			var wed_row := _ai_wed(game, man, woman, offer)
			wed_row["arranged"] = true
			return wed_row
	return {"ok": true, "arranged": false, "reason": "No house accepted a match."}

## Direct match for a prepared pair. No cooldown. The bride must be the woman.
static func try_ai_match(game, groom_uid: String, bride_uid: String) -> Dictionary:
	var groom := Dynasty._person(game, groom_uid)
	var bride := Dynasty._person(game, bride_uid)
	if groom.is_empty() or bride.is_empty(): return {"ok": false, "reason": "One of the pair is gone."}
	if int(groom["person"][2]) != 0 or int(bride["person"][2]) != 1:
		return {"ok": false, "reason": "The bride joins the groom's house."}
	var gblock := _ai_blocked(game, groom["town"], groom["family"], groom["person"])
	if gblock != "": return {"ok": false, "reason": "The groom " + gblock + "."}
	var bblock := _ai_blocked(game, bride["town"], bride["family"], bride["person"])
	if bblock != "": return {"ok": false, "reason": "The bride " + bblock + "."}
	if str(groom["town"].get("id", "")) == str(bride["town"].get("id", "")):
		return {"ok": false, "reason": "They already share a town."}
	if str(groom["family"].get("household_uid", "")) == str(bride["family"].get("household_uid", "")):
		return {"ok": false, "reason": "They already share a house."}
	if Persons.family_race(groom["econ"], groom["family"]) != Persons.family_race(bride["econ"], bride["family"]):
		return {"ok": false, "reason": "The houses are not the same race."}
	if absi(Persons.age_of(groom["person"], float(game.day)) - Persons.age_of(bride["person"], float(game.day))) > 16:
		return {"ok": false, "reason": "The age gap is too wide."}
	var offer := _ai_score(game, groom, bride)
	if not bool(offer["accepts"]):
		return {"ok": false, "reason": "The houses decline (%.0f of %.0f)." % [float(offer["score"]), ACCEPT], "score": float(offer["score"])}
	return _ai_wed(game, groom, bride, offer)

## The woman joins the man's house. Dowry is real coin. No egg, no claim, no player alliance row.
static func _ai_wed(game, groom: Dictionary, bride: Dictionary, offer: Dictionary) -> Dictionary:
	var from_town: Dictionary = bride["town"]
	var from_e: Dictionary = bride["econ"]
	var from_f: Dictionary = bride["family"]
	var p: Array = bride["person"]
	var to_e: Dictionary = groom["econ"]
	var to_f: Dictionary = groom["family"]
	var mp: Array = groom["person"]
	var groom_uid := str(Persons.g(mp, Persons.PERSON_UID, ""))
	var bride_uid := str(Persons.g(p, Persons.PERSON_UID, ""))
	var groom_hh := str(to_f.get("household_uid", ""))
	var bride_hh := str(from_f.get("household_uid", ""))
	var groom_house := str(Persons.g(mp, Persons.HOUSE_UID, ""))
	var bride_house := str(Persons.g(p, Persons.HOUSE_UID, ""))
	var groom_name := str(to_f.get("name", ""))
	var bride_name := str(from_f.get("name", ""))
	var bride_town := str(from_town.get("id", ""))
	var groom_town := str(groom["town"].get("id", ""))
	var fa := str(offer.get("faction_a", ""))
	var fb := str(offer.get("faction_b", ""))
	var day := float(game.day)
	var dowry := floorf(maxf(0.0, float(from_f.get("purse", 0.0))) * DOWRY_SHARE)
	if dowry > 0.0:
		from_f["purse"] = float(from_f.get("purse", 0.0)) - dowry
		to_f["purse"] = float(to_f.get("purse", 0.0)) + dowry
	var bride_person_name := Persons.name_of(from_f, p, Persons.family_race(from_e, from_f))
	Persons.forget(from_e, from_f, p)
	Persons.pp(from_f).erase(p)
	from_f["f"] = maxi(0, int(from_f.get("f", 0)) - 1)
	if not is_same(from_e, to_e):
		p[0] = int(to_e.get("next_pid", 1)); to_e["next_pid"] = int(p[0]) + 1
		p[Persons.MO] = -1; p[Persons.FA] = -1
		from_e["pop"] = maxi(0, int(from_e.get("pop", 0)) - 1); to_e["pop"] = int(to_e.get("pop", 0)) + 1
		from_e["adults"] = maxi(0, int(from_e.get("adults", 0)) - 1); to_e["adults"] = int(to_e.get("adults", 0)) + 1
	p[4] = ""
	to_f["f"] = int(to_f.get("f", 0)) + 1
	Persons.pp(to_f).append(p)
	p[Persons.SP] = int(mp[0]); mp[Persons.SP] = int(p[0])
	Persons._identity_pad(p); Persons._identity_pad(mp)
	p[Persons.SPOUSE_UID] = groom_uid; mp[Persons.SPOUSE_UID] = bride_uid
	to_f.erase("nxa")
	Families.event(to_f, "married", [Persons.name_of(to_f, mp, Persons.family_race(to_e, to_f)), bride_person_name], day)
	Families.event(from_f, "wed_away", [bride_person_name, groom_name], day)
	Families.reassign(from_e, from_f); Families.reassign(to_e, to_f)
	Dynasty.record_person(to_e, to_f, p, true)
	Dynasty.record_person(to_e, to_f, mp, true)
	var st := state(game)
	if not st.has("ai_links"): st["ai_links"] = {}
	var key := groom_hh + "|" + bride_hh
	st["ai_links"][key] = {"groom_uid": groom_uid, "bride_uid": bride_uid, "groom_household": groom_hh, "bride_household": bride_hh,
		"groom_house_uid": groom_house, "bride_house_uid": bride_house, "groom_house_name": groom_name, "bride_house_name": bride_name,
		"groom_town": groom_town, "bride_town": bride_town, "faction_a": fa, "faction_b": fb,
		"ruling": bool(offer.get("ruling", false)), "day": int(day)}
	if fa != "" and fa == fb:
		var loyalty_row: Dictionary = game.world.get("feudal", {}).get("towns", {}).get(bride_town, {})
		if not loyalty_row.is_empty():
			loyalty_row["loyalty"] = minf(100.0, float(loyalty_row.get("loyalty", 0.0)) + 15.0)
			loyalty_row["grievance"] = maxf(0.0, float(loyalty_row.get("grievance", 0.0)) - 10.0)
	Diplomacy.sync_dynasty(game)
	var text := "%s of House %s weds %s of House %s. She joins his house at %s." % [Persons.name_of(to_f, mp, Persons.family_race(to_e, to_f)), groom_name, bride_person_name, bride_name, str(groom["town"].get("name", ""))]
	if dowry > 0.0: text += " Dowry: %d coins." % int(dowry / Item.COIN)
	_log(game, text)
	game.changed.emit()
	return {"ok": true, "reason": text, "text": text, "dowry": dowry, "key": key, "ruling": bool(offer.get("ruling", false)),
		"groom_uid": groom_uid, "bride_uid": bride_uid, "score": float(offer.get("score", 0.0))}
