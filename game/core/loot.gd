class_name Loot
extends RefCounted
## After-battle spoils (Douglas, 2026-10-04): loot is gold, "if it's actually happening", but you occasionally
## get an item. Each piece left on the field by the beaten enemy (the dead and the downed; men who fled ran off
## with their kit) rolls to survive, weighted by its condition after the fight and its quality. Survivors go
## to the stash in that condition; the rest is scrap metal sold by the quartermaster for gold.
## Condition: the sim does not track item damage yet (weapon/armour wear, O9 in docs/SIM.md, comes later),
## so armour condition is read from the wounds under it (pierced/cut through = holed, broken bone under it =
## dented or bent) and weapons from how hard the fight went for their owner. [ours, tuned]
## Dead company men's gear goes to the stash when the company holds the field; lost otherwise.
## Arms trade (Douglas): AI winners loot through this same spoils() (campaign/arms_trade.gd field()).

const KEEP_BASE := 0.05          # chance a pristine ordinary piece survives fit to use [ours]
const KEEP_PER_QUALITY := 0.02   # better-made pieces survive more often [ours]
const KEEP_WEAR_MULT := [1.0, 0.6, 0.3, 0.0]   # by wear 0..3; tattered pieces are always scrap [ours]

## Wear 0..3 for an enemy's item after the fight, from the wounds under it.
static func battle_wear(u: Unit, it: Item) -> int:
	var t := it.tmpl()
	var cov: Dictionary = t.get("coverage", {})
	var worst := 0
	if cov.is_empty():   # weapon or shield: the fight's toll on its owner
		var bad := 0
		for pid in u.body.parts:
			for l in u.body.parts[pid]["layers"]:
				if float(l.get("dmg", 0.0)) >= 0.5:
					bad += 1
		return clampi(bad / 4, 0, 2)
	for pid in cov:
		var p: Dictionary = u.body.parts.get(pid, {})
		if p.is_empty():
			continue
		if p.get("severed", false):
			worst = maxi(worst, 3)
			continue
		for l in p["layers"]:
			var k: String = l.get("kind", "")
			if k in ["cut", "pierced", "torn"] and l.get("tissue", "") in ["skin", "fat"]:
				worst = maxi(worst, 2)      # the blow went through the piece
			elif k in ["fractured", "broken", "mangled"]:
				worst = maxi(worst, 1 if it.mat().get("kind", "") == "metal" else 2)
	return worst

## Splits the beaten enemy's kit into kept items and scrap gold. Returns {"items": [Item], "gold": int,
## "scrap_kg": {material: kg}}. Deterministic for a seed.
## v0.014: a legendary piece is never scrap and never rolls: the winners always take it (taker: who, for its history).
static func spoils(enemies: Array, fled: Array, seed: int, fraction: float, taker: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var kept := []
	var gold := 0.0
	var scrap := {}
	var coin := 0
	var arrows := {}   # bows: the arrows in the beaten enemy's quivers (counted goods, all kept)
	var scrapped := 0   # arms trade: pieces sold as scrap or rags (they leave the men too: conservation)
	var scrap_gold := 0.0   # v0.014: the part of "gold" that is metal scrap (not rags)
	var salvage := []   # Exact disowned pieces; a real buyer must pay before conversion.
	for e in enemies:
		if not (e is Unit) or fled.has(e):
			continue
		coin += carried_coin(e)
		for k in e.quiver:
			arrows[k] = int(arrows.get(k, 0)) + int(e.quiver[k])
		e.quiver.clear()
		for slot in e.equip.keys():
			var it: Item = e.equip[slot]
			if it.is_legend():
				it.wear = maxi(it.wear, battle_wear(e, it))
				kept.append(it)
				e.equip.erase(slot)
				Legends.fell(it, e, taker)
				continue
			if it.mat().get("kind", "") in ["cloth", "leather"] and rng.randf() > 0.15:
				var rag_value := it.value()
				gold += rag_value * fraction * 0.5     # most cloth is rags; sold by the bundle
				salvage.append(Salvage.record(it, "rags", "enemy", int(round(rag_value * fraction * 0.5))))
				e.equip.erase(slot)
				scrapped += 1
				continue
			var wear := 3 if it.broken else maxi(it.wear, battle_wear(e, it))   # v0.014: snapped/split/cracked = scrap
			var p: float = (KEEP_BASE + KEEP_PER_QUALITY * it.quality) * KEEP_WEAR_MULT[clampi(wear, 0, 3)]
			if rng.randf() < p:
				it.wear = wear
				kept.append(it)
				e.equip.erase(slot)
			else:
				var scrap_value := it.value()
				gold += scrap_value * fraction
				scrap_gold += scrap_value * fraction   # v0.014: re-priced at the town's scrap price (world.gd)
				scrap[it.material] = float(scrap.get(it.material, 0.0)) + it.mass()
				salvage.append(Salvage.record(it, "scrap", "enemy", int(round(scrap_value * fraction))))
				e.equip.erase(slot)
				scrapped += 1
	return {"items": kept, "gold": int(round(gold)), "coin": coin, "scrap_kg": scrap, "arrows": arrows, "scrapped": scrapped,
		"scrap_gold": int(round(scrap_gold)), "salvage": salvage}

## v0.014 gear damage: pieces broken in battle (snapped, split, cracked, shattered: Item.broken) come off these men and
## become scrap of their own metal at their real mass. Returns {material: kg} (cloth and leather count too; the town
## stock takes only metals, TownEcon.add_scrap). Bent or dented pieces stay: they lost quality steps already.
static func strip_broken(units: Array, salvage: Array = []) -> Dictionary:
	var scrap := {}
	for u in units:
		if not (u is Unit):
			continue
		for slot in u.equip.keys():
			var it: Item = u.equip[slot]
			if it != null and it.broken:
				scrap[it.material] = float(scrap.get(it.material, 0.0)) + it.mass()
				salvage.append(Salvage.record(it, "scrap", "own"))
				u.equip.erase(slot)
	return scrap

static func add_kg(into: Dictionary, more: Dictionary) -> void:
	for m in more:
		into[m] = float(into.get(m, 0.0)) + float(more[m])

## Coin on the body (Douglas): 5% of his household's purse. If he was the last living member of his house,
## you get 10% of the household's cash and the rest goes to his faction's coffer. Leaves the family's real purse. Until enemy households exist (economy v0.006/v0.007), a stand-in
## household purse scaled by faction wealth and his kit is used. [ours, stand-in]
const COIN_SHARE := 0.05          # Douglas
const LAST_MEMBER_SHARE := 0.10    # Douglas: last of his house; the rest of the purse goes to his faction coffer
const MAX_CARRIED := 500          # Douglas: nobody carries more than 500 on them (coins since v0.010, his number kept)
static func carried_coin(u: Unit) -> int:
	var F = load("res://campaign/families.gd") if ResourceLoader.exists("res://campaign/families.gd") else null
	if F != null and F.has_method("take_carried_coin"):
		return mini(MAX_CARRIED, int(F.take_carried_coin(u, COIN_SHARE, LAST_MEMBER_SHARE, MAX_CARRIED)))   # families.gd moves the remainder to the faction coffer
	var wealth := int(DB.factions.get(u.faction, {}).get("wealth", 2))
	var stand_in_purse := 40.0 * Item.COIN * wealth + u.gear_value() * 0.5
	return mini(MAX_CARRIED, int(round(stand_in_purse * COIN_SHARE)))
