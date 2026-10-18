class_name HouseOnboarding
extends RefCounted
## Campaign entry references existing local tracked people/property only.
const EMBLEMS := ["crown", "tower", "wolf", "stag", "leaf", "hammer", "flame", "star"]
const DEFAULT_PRIMARY := "#2F6B4F"
const DEFAULT_SECONDARY := "#E4C47D"
const PALETTE := [{"name": "Forest", "color": "#2F6B4F"}, {"name": "Gold", "color": "#E4C47D"},
	{"name": "Crimson", "color": "#8B2E35"}, {"name": "Navy", "color": "#294A76"},
	{"name": "Ivory", "color": "#EDE5D0"}, {"name": "Charcoal", "color": "#2C3038"},
	{"name": "Violet", "color": "#6E4B85"}, {"name": "Copper", "color": "#B87943"}]

static func _valid(game, town: Dictionary, f: Dictionary, p: Array, minor_office: bool = false) -> bool:
	if p.size() <= Persons.HOUSE_UID or str(p[Persons.PERSON_UID]) == "" or str(p[Persons.HOUSE_UID]) == "": return false
	if not Dynasty._living(game, str(town["id"]), f, p): return false
	if not minor_office and Persons.age_of(p, float(game.day)) < int(People.ages(Persons.race_of(town["econ"]))["adult"]): return false
	if int(p[5]) >= 0:
		var row: Dictionary = Dynasty._row({"town": town, "econ": town["econ"], "family": f, "person": p, "alive": true}, float(game.day))
		var u: Unit = Dynasty.bound_unit(game, row)
		if u == null or u.dead or not ServiceIdentity.unit_person(town["econ"], f, p, u): return false
	return true

static func _leader(game, town: Dictionary, f: Dictionary) -> Array:
	var office_uid := str(town["econ"].get("head", {}).get("person_uid", ""))
	# A real reigning minor remains the legitimate office holder; ordinary local
	# houses start with their existing eligible adult household head.
	for key in ["pp", "kp"]:
		for p in f.get(key, []):
			if str(Persons.g(p, Persons.PERSON_UID, "")) == office_uid and _valid(game, town, f, p, true): return p
	var head: Array = Persons.head_of(f)
	if not head.is_empty() and _valid(game, town, f, head): return head
	for p in f.get("pp", []):
		if _valid(game, town, f, p): return p
	return []

static func houses(game, town_id: String) -> Array:
	var town: Dictionary = game.world.get("towns", {}).get(town_id, {})
	var e: Dictionary = town.get("econ", {})
	if e.is_empty() or not TownEcon.data()["cultures"].has(str(e.get("culture", ""))): return []
	var out: Array = []
	for f in e.get("fams", []):
		if Population.is_cohort(f) or f.get("estate", false) or f.get("gone", false) or not f.has("pp") or str(f.get("household_uid", "")) == "": continue
		var p: Array = _leader(game, town, f)
		if p.is_empty(): continue
		var leader_uid := str(p[Persons.PERSON_UID]); var office: bool = leader_uid == str(e.get("head", {}).get("person_uid", ""))
		var person: Dictionary = Dynasty._row({"town": town, "econ": e, "family": f, "person": p, "alive": true}, float(game.day), str(e["head"].get("title", "Ruler")) if office else "House leader")
		var members := 0
		for key in ["pp", "kp"]:
			for member in f.get(key, []):
				if Dynasty._living(game, town_id, f, member): members += 1
		out.append({"town_id": town_id, "town_name": str(town.get("name", town_id)), "household_uid": str(f["household_uid"]),
			"house_uid": str(p[Persons.HOUSE_UID]), "house_name": str(f.get("name", "House")), "native_house_name": str(f.get("name", "House")),
			"family_id": int(f["id"]), "leader_uid": leader_uid, "leader_name": person["name"], "leader_age": person["age"],
			"leader_sex": person["sex"], "leader_race": person["race"], "title": person["title"], "is_ruling": office, "holds_office": office,
			"selection_kind": "office" if office else "household", "leadership_mode": "office" if office else "household",
			"house_purse": float(f.get("purse", 0.0)), "member_count": members, "portrait_spec": Dynasty.portrait_for(game, person)})
	out.sort_custom(func(a, b):
		if a["is_ruling"] != b["is_ruling"]: return a["is_ruling"]
		return str(a["native_house_name"]) < str(b["native_house_name"]) if a["native_house_name"] != b["native_house_name"] else str(a["household_uid"]) < str(b["household_uid"]))
	return out

static func settlements(game) -> Array:
	var out: Array = []
	for tid in game.world.get("towns", {}):
		var local: Array = houses(game, str(tid))
		if local.is_empty(): continue
		var town: Dictionary = game.world["towns"][tid]; var e: Dictionary = town["econ"]
		var fid := str(town.get("faction", ""))
		out.append({"town_id": str(tid), "town_name": str(town.get("name", tid)), "pos": town.get("pos", Vector2.ZERO),
			"faction_id": fid, "faction_name": str(DB.factions.get(fid, {}).get("name", fid)), "race": Persons.race_of(e),
			"culture": str(e["culture"]), "size": int(town.get("size", 0)), "population": int(e.get("pop", 0)),
			"house_count": local.size(), "ruler_name": str(e.get("head", {}).get("name", ""))})
	out.sort_custom(func(a, b): return str(a["town_name"]) < str(b["town_name"]) if a["town_name"] != b["town_name"] else str(a["town_id"]) < str(b["town_id"]))
	return out

static func customization(custom: Dictionary, native_name: String) -> Dictionary:
	for key in custom:
		if not key in ["display_name", "emblem", "primary_color", "secondary_color", "design"]: return {"ok": false, "reason": "Only display name, emblem and banner colours can be customized."}
	var display := str(custom.get("display_name", native_name))
	var normalized := ""
	for i in display.length():
		var code := display.unicode_at(i)
		if code < 32 or code == 127 or display[i] in ["[", "]", "<", ">"]: return {"ok": false, "reason": "Use a plain display name without control characters or markup."}
		if display[i] == " ":
			if normalized != "" and not normalized.ends_with(" "): normalized += " "
		else: normalized += display[i]
	display = normalized.strip_edges()
	if display.length() < 1 or display.length() > 40: return {"ok": false, "reason": "Choose a display name between one and forty characters."}
	var emblem := str(custom.get("emblem", "crown"))
	if not EMBLEMS.has(emblem): return {"ok": false, "reason": "Choose an available house emblem."}
	var primary := str(custom.get("primary_color", DEFAULT_PRIMARY)); var secondary := str(custom.get("secondary_color", DEFAULT_SECONDARY))
	for color in [primary, secondary]:
		if color.length() != 7 or not color.begins_with("#"): return {"ok": false, "reason": "Banner colours must use a six-digit hexadecimal colour."}
		for i in range(1, 7):
			if "0123456789abcdef".find(color.substr(i, 1).to_lower()) < 0: return {"ok": false, "reason": "Choose a valid banner colour."}
	return {"ok": true, "reason": "", "customization": {"display_name": display, "emblem": emblem,
		"primary_color": primary.to_upper(), "secondary_color": secondary.to_upper()}}

static func preview(game, town_id: String, household_uid: String, custom: Dictionary = {}) -> Dictionary:
	var row: Dictionary = {}
	for candidate in houses(game, town_id):
		if candidate["household_uid"] == household_uid: row = candidate; break
	if row.is_empty(): return {"ok": false, "reason": "This local house no longer has an eligible registered leader."}
	var normalized: Dictionary = customization(custom, str(row["native_house_name"]))
	if not normalized["ok"]: return normalized
	if custom.has("design"):
		if not (custom["design"] is Dictionary): return {"ok": false, "reason": "Character design must be a dictionary."}
		var dp: Dictionary = CharacterDesign.preview(game, str(row["leader_uid"]), custom["design"])
		if not bool(dp.get("ok", false)): return dp
	var person: Dictionary = Dynasty.person(game, str(row["leader_uid"]))
	var display: Dictionary = normalized["customization"]
	var rights := "This household rules the settlement. Its title and current authority remain in force." if row["holds_office"] else "Your household keeps its property and wealth. Selection grants no town lordship, levy, public armory or treasury authority."
	return {"ok": true, "reason": "Review this existing house before beginning.", "house": row, "customization": display,
		"town_id": town_id, "household_uid": household_uid, "house_uid": row["house_uid"], "leader_uid": row["leader_uid"],
		"selection_kind": row["selection_kind"], "leadership_mode": row["leadership_mode"], "holds_office": row["holds_office"],
		"rights_text": rights, "portrait_spec": Dynasty.portrait_for(game, person, display)}

static func begin(game, town_id: String, household_uid: String, custom: Dictionary = {}, expected_person_uid: String = "") -> Dictionary:
	if not game.world.get("player_house", {}).is_empty(): return {"ok": false, "reason": "A campaign house has already been chosen."}
	if game.get("_save_capture") != null or not game.world.get("work", []).is_empty(): return {"ok": false, "reason": "Let the current world and save work finish before beginning."}
	var out: Dictionary = preview(game, town_id, household_uid, custom)
	if not out["ok"]: return out
	if expected_person_uid != "" and expected_person_uid != str(out["leader_uid"]): return {"ok": false, "reason": "This house's eligible leader changed. Review the house again."}
	var party: Dictionary = game.world.get("party", {})
	if party.is_empty(): return {"ok": false, "reason": "The existing campaign party is unavailable."}
	var row: Dictionary = out["house"]; var town: Dictionary = game.world["towns"][town_id]
	var estate_uid := str(town["econ"].get("head", {}).get("household_uid", household_uid)) if row["holds_office"] else household_uid
	game.world["player_house"] = {"town_id": town_id, "house_uid": row["house_uid"], "household_uid": household_uid,
		"ruler_uid": row["leader_uid"], "leader_uid": row["leader_uid"], "estate_household_uid": estate_uid,
		"native_house_name": row["native_house_name"], "house_name": out["customization"]["display_name"],
		"ruler_name": row["leader_name"], "ruler_sex": row["leader_sex"], "ruler_race": row["leader_race"], "title": row["title"],
		"selection_kind": row["selection_kind"], "leadership_mode": row["leadership_mode"], "holds_office": row["holds_office"],
		"customization": out["customization"].duplicate(true)}
	if custom.has("design") and custom["design"] is Dictionary:
		var applied: Dictionary = CharacterDesign.apply(game, str(row["leader_uid"]), custom["design"])
		if not bool(applied.get("ok", false)): game.world.erase("player_house"); return applied
		out["portrait_spec"] = Dynasty.portrait_for(game, Dynasty.person(game, str(row["leader_uid"])), out["customization"])
	var pos: Vector2 = town["pos"]
	party["pos"] = CampaignWorld.nearest_passable(game.world, pos) if str(game.world.get("terrain", "")) != "" else pos
	party["target"] = party["pos"]; party["path"] = []; party["dest_town"] = ""; party["arrived"] = ""; party["waiting"] = false
	game.world["start_town"] = town_id; game.location = town_id
	out["selected"] = Dynasty.selected(game); out["reason"] = "Campaign begun with the existing house and its actual rights."
	game.changed.emit()
	return out
