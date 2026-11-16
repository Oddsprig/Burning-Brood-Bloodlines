class_name Bandits
extends RefCounted
## Monsters wave 1, section B: bandits and deserters (humanoids on the existing sim).
## Rule: every non-monster unit on the map belongs to a specific home and faction.
## - Bandits belong to a bandit camp: a small town-like map site (a lair of kind "bandit_camp", see lairs.gd) of
##   the outlaw faction ("outlaws", data/creatures.json). The camp keeps a stock of what its bands raid (caravan
##   cargo), re-equips its people from that stock (best piece per slot), and can be cleared as a lair: destroyed
##   when cleared (its hoard sells as loot gold); a new camp can appear elsewhere later.
##   Warbands: the garrison (kind "camp", stays at the camp, a named chief = bounty target) and its gangs (kind
##   "bandit", prowl roads and caravans near the camp). Their home is the camp id.
## - Deserters keep their original town and faction (home = that town), flagged deserter = true: hostile to the
##   company and to their own faction's bands. Gear is their old faction's.
## Loot from humanoids is the existing gear-value gold rule (Game.finish_battle).

const ROAM := 320.0            # [ours] px a gang prowls around its camp
const STOCK_MAX := 40          # [ours] items a camp hoards

static func camp(game, lid: String) -> Dictionary:
	var l: Dictionary = game.world.get("lairs", {}).get(lid, {})
	return l if l.get("kind", "") == "bandit_camp" else {}

static func outlaw_name(rng: RandomNumberGenerator) -> String:
	var ep: Array = DB.names.get("outlaw_epithets", ["the Knife"])
	var first: Array = DB.names["human"]["first"]
	return "%s %s" % [first[rng.randi() % first.size()], ep[rng.randi() % ep.size()]]

## A new camp in the wilds with its garrison (chief + outlaws) and a first stock. Returns the lair id.
static func new_camp(game, rng: RandomNumberGenerator) -> String:
	var lid := Lairs.place(game, "bandit_camp", rng)
	if lid == "":
		return ""
	var w: Dictionary = game.world
	var l: Dictionary = w["lairs"][lid]
	var g: Array = Creatures.tun("camp_garrison", [4, 7])
	var units := Factory.make_warband(rng, "outlaws", rng.randi_range(int(g[0]), int(g[1])))
	var chief_t: Dictionary = {}
	for tr in DB.factions["outlaws"]["troops"]:
		if tr.get("name", "") == "bandit chief":
			chief_t = tr
	var chief := Factory.make_troop(rng, "outlaws", chief_t if not chief_t.is_empty() else Factory.pick_troop(rng, "outlaws"))
	chief.name = outlaw_name(rng)
	chief.role = "officer"
	units.push_front(chief)
	for u in units:
		if u != chief:
			u.squad = chief.uid
	# the first hoard: a few pieces of whatever the roads carried
	var stock: Array = l["stock"]
	for i in rng.randi_range(2, 5):
		var pool: Array = DB.weapons.keys() if rng.randf() < 0.4 else DB.armor_by_culture.get(["middle", "northern", "common"][rng.randi() % 3], [])
		if pool.is_empty():
			continue
		var tid: String = pool[rng.randi() % pool.size()]
		stock.append(Factory.make_item(rng, tid, 2))
	var wid := CampaignWorld.spawn_warband(game, "outlaws", l["pos"], units.size(), "camp", rng,
		{"units": units, "home": lid, "lair": lid, "anchor": l["pos"], "named": chief.name, "since": float(game.day)})
	l["resident"] = wid
	reequip(l, units)
	for i in int(Creatures.tun("camp_bands", 1)):
		spawn_band(game, lid, rng)
	return lid

static func bands_of(game, lid: String) -> Array:
	var out := []
	for wid in game.world["warbands"]:
		var wb: Dictionary = game.world["warbands"][wid]
		if wb["kind"] == "bandit" and wb.get("home", "") == lid:
			out.append(wid)
	return out

static func wants_band(game, lid: String) -> bool:
	var l := camp(game, lid)
	if l.is_empty() or not game.world["warbands"].has(String(l.get("resident", ""))):
		return false
	return bands_of(game, lid).size() < int(Creatures.tun("camp_bands", 1))

## A gang leaves the camp, armed from the camp's stock.
static func spawn_band(game, lid: String, rng: RandomNumberGenerator) -> String:
	var l := camp(game, lid)
	if l.is_empty():
		return ""
	var r: Array = Creatures.tun("bandit_band", [3, 6])
	var n := rng.randi_range(int(r[0]), int(r[1])) + mini(int(game.day / 20.0), 3)
	var units := Factory.make_warband(rng, "outlaws", n)
	reequip(l, units)
	var pos: Vector2 = l["pos"] + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
	return CampaignWorld.spawn_warband(game, "outlaws", pos, units.size(), "bandit", rng,
		{"units": units, "home": lid, "lair": lid, "anchor": l["pos"]})

## Re-equip from the camp stock: for every unit and slot, take the most valuable stocked piece that beats what it
## wears (the old piece goes back to the stock). Returns how many pieces changed hands.
static func reequip(l: Dictionary, units: Array) -> int:
	var stock: Array = l.get("stock", [])
	var moved := 0
	for u in units:
		if u.dead:
			continue
		for i in range(stock.size() - 1, -1, -1):
			if i >= stock.size():
				continue
			var it: Item = stock[i]
			var slot := it.slot()
			if slot == "":
				continue
			var cur: Item = u.equip.get(slot, null)
			if cur != null and cur.value() >= it.value():
				continue
			if slot == "off_hand":
				var w: Item = u.weapon()
				if w != null and w.tmpl().get("two_handed", false):
					continue
			if slot == "main_hand" and it.tmpl().get("two_handed", false) and u.equip.has("off_hand"):
				continue
			stock.remove_at(i)
			if cur != null:
				stock.append(cur)
			u.equip[slot] = it
			moved += 1
	return moved

## A gang that beat a caravan carries its cargo items home to the camp stock.
static func on_plunder(game, winner: Dictionary, caravan: Dictionary) -> void:
	if winner.get("kind", "") != "bandit":
		return
	var l := camp(game, String(winner.get("home", "")))
	if l.is_empty():
		return
	var stock: Array = l["stock"]
	var cargo_items: Array = caravan.get("cargo", {}).get("items", [])
	for it in cargo_items:
		if stock.size() < STOCK_MAX or (it as Item).is_legend():   # v0.014: a legendary piece is always carried off
			stock.append(it)
		else:
			WorldAudit.lose_item(it, "-broken up by outlaws (camp full)")   # v0.075 r5
	WorldAudit.book(game.world, "arms", "-carried off by outlaws", -cargo_items.size())   # v0.075: out of the wagons (camp or broken)
	caravan["cargo"]["items"] = []

## Daily: garrison and gangs near the camp re-arm from the stock.
static func daily(game) -> void:
	var w: Dictionary = game.world
	for lid in w.get("lairs", {}):
		var l: Dictionary = w["lairs"][lid]
		if l["kind"] != "bandit_camp" or (l["stock"] as Array).is_empty():
			continue
		var g: Dictionary = w["warbands"].get(String(l["resident"]), {})
		if not g.is_empty():
			reequip(l, g["units"])
		for wid in bands_of(game, lid):
			var b: Dictionary = w["warbands"][wid]
			if (b["pos"] as Vector2).distance_to(l["pos"]) < 90.0:
				reequip(l, b["units"])

## Where a gang prowls: a caravan in reach, else around its camp.
static func wander_target(game, wb: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var w: Dictionary = game.world
	for cid in w["warbands"]:
		var car: Dictionary = w["warbands"][cid]
		if car["kind"] == "caravan" and (car["pos"] as Vector2).distance_to(wb["pos"]) < 400.0 and Caravans.is_prey(w, wb, car):
			var ahead: Array = car["path"]
			return ahead[mini(2, ahead.size() - 1)] if not ahead.is_empty() else car["pos"]
	return wb["anchor"] + Vector2(rng.randf_range(-ROAM, ROAM), rng.randf_range(-ROAM, ROAM))

## Camp cleared by the company: the hoard sells as loot gold (gear-value rule), the gangs scatter, the camp is gone.
static func clear_camp(game, lid: String, result: Dictionary) -> int:
	var w: Dictionary = game.world
	var l := camp(game, lid)
	if l.is_empty():
		return 0
	if result.is_empty() and Salvage.nearest(w, l["pos"]).is_empty(): return 0
	var records := []
	for it: Item in l.get("stock", []):
		if (it as Item).is_legend():   # v0.014: a legendary piece is taken whole, never sold off with the hoard
			if not result.is_empty():
				game.stash.append(it)
				Legends.note(it, float(game.day), "Taken from an outlaw hoard by your company.")
			else:
				ArmsTrade._legend_found(game, it, null, l["pos"])
			continue
		records.append(Salvage.record(it, "hoard", "camp", int(round(it.value() * game.loot_fraction()))))
	var sold := 0
	if not result.is_empty():
		var receipt: Dictionary = Salvage.finalize(game, result, records, l["pos"], "camp_salvage_receipt", "camp_hoard")
		sold = int(receipt["paid"])
	else:
		# Offscreen destruction supplies no victorious payer/recipient identity.
		# Found real gear goes to a real local armory without a fabricated sale.
		var town: Dictionary = Salvage.nearest(w, l["pos"])
		if not town.is_empty():
			for entry in records:
				ArmsTrade.armory(town).append(entry["item"])
				if TownEcon.has_econ(town): TownEcon.led(town["econ"], "made", "arms", 1)   # v0.075: into the town's holdings
	var coin := int(l.get("gold", 0)); var loot := sold + coin
	if not result.is_empty():
		game.gold += coin # The actual sale was already credited once by Salvage.
		l["gold"] = float(l.get("gold", 0)) - coin
		result["camp_loot"] = loot
		result["camp_coin"] = coin; result["camp_sale_paid"] = sold
	for wid in bands_of(game, lid):
		Army.band_beaten(game, w["warbands"][wid], null, 1.0)   # economy spec 2: the gangs scatter home
		CampaignWorld.remove_warband(game, wid)
	Barge.drained(w, float(l.get("gold", 0.0)))   # any coin the company did not carry off is scattered
	w["lairs"].erase(lid)
	return loot

# ---------------------------------------------------------------- deserters
static func count_deserters(game) -> int:
	var n := 0
	for wid in game.world["warbands"]:
		if game.world["warbands"][wid].get("deserter", false):
			n += 1
	return n

static func wants_deserters(game, rng: RandomNumberGenerator) -> bool:
	return count_deserters(game) < int(Creatures.tun("max_deserters", 2)) and rng.randf() < float(Creatures.tun("deserter_chance", 0.12))

## Hungry or unpaid serving soldiers break away; timed-out soldiers still go home through Army.desertion().
static func spawn_deserters(game, rng: RandomNumberGenerator) -> String:
	var w: Dictionary = game.world
	var towns := []
	var ids: Array = w["warbands"].keys()
	ids.sort()
	var roll: Dictionary = Army.state(w)["roll"]
	var timeout: int = int(Army.A()["desert_days"])
	for source_id: String in ids:
		var source: Dictionary = w["warbands"][source_id]
		var faction: String = str(source["faction"])
		if not Army.is_field(source) or DB.factions[faction]["race"] != "human" or DB.factions[faction].get("player_hostile", false) or CampaignWorld.is_hostile(game, faction):
			continue
		var by_town: Dictionary = {}
		for soldier: Unit in source["units"]:
			if soldier.dead or soldier.unpaid_days >= timeout or (soldier.unpaid_days <= 0 and int(source.get("hungry", 0)) <= 0):
				continue
			var town: Dictionary = w["towns"].get(soldier.home_town, {})
			var family: Dictionary = People.fam_of(town, soldier.family)
			var person: Array = Persons.by_uid(family, soldier.uid)
			var entry: Array = roll.get(str(soldier.uid), [])
			if town.get("faction", "") != faction or soldier.faction != faction or family.is_empty() or family.get("gone", false):
				continue
			if person.is_empty() or str(person[4]) != "army" or entry.size() < 4 or str(entry[2]) != "army" or int(family.get("serve", {}).get("army", 0)) <= 0:
				continue
			if str(entry[0]) != soldier.home_town or int(entry[1]) != soldier.family:
				continue
			if not by_town.has(soldier.home_town):
				by_town[soldier.home_town] = []
			(by_town[soldier.home_town] as Array).append(soldier)
		for town_id: String in by_town:
			towns.append({"source": source, "home": town_id, "units": by_town[town_id]})
	if towns.is_empty():
		return ""
	var choice: Dictionary = towns[rng.randi() % towns.size()]
	var source: Dictionary = choice["source"]
	var t: Dictionary = w["towns"][choice["home"]]
	var eligible: Array = choice["units"]
	var leaving: Array = eligible.slice(0, mini(eligible.size(), rng.randi_range(3, 5)))
	var original_men: int = Supplies.men(source)
	var original_shares: float = Supplies.meal_shares(source)
	if leaving.size() == original_men and Supplies.weight(Supplies.stores(source)) > Supplies.capacity(leaving.size()):
		return ""   # a complete breakaway must be able to carry its actual load
	var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
	var pos: Vector2 = source["pos"]
	var wid := CampaignWorld.spawn_warband(game, t["faction"], pos, rng.randi_range(3, 5), "deserter", rng,
		{"units": leaving, "home": choice["home"], "deserter": true, "anchor": pos + dir * rng.randf_range(200.0, 340.0), "deserted_from": source["id"], "hungry": int(source.get("hungry", 0))})
	if wid == "":
		return ""
	var band: Dictionary = w["warbands"][wid]
	var old_stores: Dictionary = Supplies.stores(source)
	var new_stores: Dictionary = Supplies.stores(band)
	if leaving.size() == original_men:
		new_stores.merge(old_stores)
		source["stores"] = {}
	else:
		var room: float = Supplies.capacity(leaving.size())
		var goods: Dictionary = Goods.table()
		for good: String in old_stores.keys():
			var share: float = Supplies.meal_shares(band) / maxf(0.01, original_shares) if good in Supplies.FOOD else float(leaving.size()) / original_men
			var kg: float = float(goods.get(good, {}).get("weight", 0.5))
			var quantity: int = mini(int(floor(float(old_stores[good]) * share)), int(room / maxf(0.01, kg)))
			if quantity <= 0:
				continue
			new_stores[good] = quantity
			old_stores[good] = float(old_stores[good]) - quantity
			if float(old_stores[good]) <= 0.0: old_stores.erase(good)
			room -= quantity * kg
	var moved: Dictionary = {}
	for soldier: Unit in leaving:
		moved[soldier.uid] = true
		(source["units"] as Array).erase(soldier)
		var family: Dictionary = People.fam_of(w["towns"][soldier.home_town], soldier.family)
		var person: Array = Persons.by_uid(family, soldier.uid)
		if soldier.unpaid_days > 0:
			Persons.remember_unpaid(person, "army", soldier.unpaid_days, float(game.day), float(game.day) - Persons.served_since(person, "army"))
		var service: Dictionary = family["serve"]
		service["army"] = int(service["army"]) - 1
		if int(service["army"]) <= 0: service.erase("army")
		service["deserter"] = int(service.get("deserter", 0)) + 1
		person[4] = "deserter"
		Persons.log_life(person, float(game.day), "serve", "deserter")
		(roll[str(soldier.uid)] as Array)[2] = "deserter"
		soldier.title = "deserter " + soldier.title
		Families.add_hist(family, "%s broke away from the army with a deserter band." % soldier.name, float(game.day))
	for soldier: Unit in leaving:
		if not moved.has(soldier.squad): soldier.squad = -1
	if leaving.size() == original_men:
		var faction: Dictionary = w["factions"][source["faction"]]
		faction["treasury"] = float(faction["treasury"]) + float(source.get("gold", 0.0))
		source["gold"] = 0.0
	if (source["units"] as Array).is_empty():
		CampaignWorld.remove_warband(game, str(source["id"]))
	_detach_deserter_commands(game, str(band["faction"]), moved)
	Army._band_unpaid(w, str(band["faction"]))
	CampaignWorld.log_event(game, "Soldiers have deserted from %s." % t["name"])
	return wid

## Vacate old posts and shrink the existing command tree without raising or promoting replacement soldiers.
static func _detach_deserter_commands(game: Variant, faction: String, moved: Dictionary) -> void:
	var record: Dictionary = Army.rec(game.world, faction)
	var remaining: Array = Army.members(game, faction)
	var culture: Dictionary = Army.cul_of_faction(faction)
	var span: int = maxi(2, int(culture.get("span", 5)))
	var levels: int = mini(int(record["levels"]), Army.levels_for(remaining.size(), span, maxi(0, Army.ranks(culture, "army").size() - Army.first_officer("army"))))
	var posts: Array = record["posts"]
	var count: int = Army.offset(levels, span)
	while posts.size() > count:
		var old_uid: int = int(posts.pop_back())
		for soldier: Unit in remaining:
			if soldier.uid == old_uid: Army._demote(soldier)
	for index: int in posts.size():
		if moved.has(int(posts[index])): posts[index] = -1
	record["levels"] = levels
	var faction_record: Dictionary = game.world["factions"][faction]
	if posts.is_empty() or moved.has(int(faction_record.get("war_leader", {}).get("uid", -1))): faction_record.erase("war_leader")
	var fights: Array = []
	for fight: Dictionary in record["fights"]:
		if int(fight["p"]) >= posts.size(): continue
		var candidates: Array = []
		for uid: Variant in fight["c"]:
			if not moved.has(int(uid)): candidates.append(uid)
		fight["c"] = candidates
		fights.append(fight)
	record["fights"] = fights
	Army._link_field_commands(game, faction)

## Independent deserters have no sponsor; their meals still come out of their actual carried stores.
static func deserters_day(game: Variant, day: int) -> void:
	for band: Dictionary in game.world["warbands"].values():
		if not band.get("deserter", false): continue
		Supplies.eat(band)
		# Only the band's actual purse can pay; its former faction is not a sponsor.
		Horses.band_day(game, band, {"kind": "camp", "l": band}, day)

static func deserter_target(game, wb: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	# keep away from home: wander the roads around where they fled to
	return wb["anchor"] + Vector2(rng.randf_range(-260.0, 260.0), rng.randf_range(-260.0, 260.0))
