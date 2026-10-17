extends RefCounted
## v0.014 (Douglas 23:02: "town armories are not desiring enough armor and arms. their militias are not even equiped
## really... and some caravans get naked people garding them"). In a normal town (seed 2026, the first human town):
## the armory's target covers the whole militia's missing kit and one caravan's guards; the head buys it off his
## stalls out of the treasury above the garrison's reserve and issues it; a caravan's guards are kitted from the
## armory before they leave and their kit comes back to it; a town that cannot pay sends its men out short and its
## armory log says why. Thresholds (chosen, not tuned): with the pieces on the stalls and the money in the chest,
## militia and guards each have a weapon (100%) and at least 90% of the armory slots of their troop loadouts filled
## (the optional ones counted); with an empty chest, none of the stripped kit comes back and the log names the money.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _town(w: Dictionary) -> Dictionary:
	var ids: Array = w["towns"].keys()
	ids.sort()
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if t["faction"] == "middle_kingdom" and TownEcon.has_econ(t) and not Militia.units_of(Game, tid).is_empty():
			return t
	return {}

## Share of the armory slots of the men's loadouts (optional ones too) that are filled, and of men with a weapon.
func _cover(units: Array) -> Array:
	var slots := 0; var filled := 0; var weap := 0; var men := 0
	for u in units:
		men += 1
		if u.equip.has("main_hand") or u.equip.has("ranged"):
			weap += 1
		var lo := ArmsTrade.loadout_of(u)
		for s in lo:
			if s == "off_hand" and u.weapon() != null and u.weapon().tmpl().get("two_handed", false):
				continue
			slots += 1
			if u.equip.has(s):
				filled += 1
	return [float(filled) / maxf(1.0, float(slots)), float(weap) / maxf(1.0, float(men))]

## Takes the armory pieces off the men (lost in a fight, say) and returns them.
func _strip(units: Array) -> Array:
	var out := []
	for u in units:
		for s in u.equip.keys():
			if ArmsTrade.cls(u.equip[s].tid) != "":
				out.append(u.equip[s])
				u.equip.erase(s)
	return out

## Stall pieces for every class the town's target wants (copper, made by its own smiths' pool).
func _stock_stalls(t: Dictionary) -> void:
	var tgt := ArmsTrade.targets(Game, t)
	var cul := String(t.get("culture", "middle"))
	for c in tgt:
		var pool := []
		for kind in ["weapon", "armor", "bow"]:
			for tid in Businesses.gear_pool(cul, kind):
				if ArmsTrade.cls(String(tid)) == c:
					pool.append(String(tid))
		for i in int(tgt[c]) + 2:
			if not pool.is_empty():
				var tid: String = pool[i % pool.size()]
				var mats: Array = DB.template(tid).get("materials", ["copper"])
				var mat := "wood" if DB.is_bow(tid) else ("copper" if DB.is_weapon(tid) or mats.has("copper") or mats.is_empty() else String(mats[0]))
				(t["shop"] as Array).append(Item.make(tid, mat, 2))

func _looks(t: Dictionary, n: int) -> void:
	var e: Dictionary = t["econ"]
	for i in n:
		ArmsTrade.econ_daily(Game, t, e, int(e.get("day", 0)), false)

func run(_tree: SceneTree) -> int:
	Game.new_game(2026)
	var w: Dictionary = Game.world
	var t := _town(w)
	check(not t.is_empty(), "a human town with a militia")
	if t.is_empty():
		return fails
	var e: Dictionary = t["econ"]
	var mil := Militia.units_of(Game, String(t["id"]))
	var arm := ArmsTrade.armory(t)

	# 1. stored reserve is 2.5x living actual supported troops, rounded per role.
	arm.clear()
	_strip(mil)
	var tgt := ArmsTrade.role_counts(ArmsTrade.targets(Game, t))
	var need := ArmsTrade.role_counts(ArmsTrade.requirements(Game, t))
	for role in need:
		check(int(tgt.get(role, 0)) == int(ceil(float(need[role]) * 2.5)), "actual supported troops define rounded reserve")
	# 2. with money and stall stock the head buys and kits the militia out
	(t["shop"] as Array).clear()
	_stock_stalls(t)
	var reserve := ArmsTrade.arms_reserve(Game, t, e)
	e["treasury"] = reserve + 500000.0 * TownEcon.COIN
	_looks(t, 2)
	var mc := _cover(mil)
	print("-- militia after the head's looks: %.0f%% of loadout slots, %.0f%% with a weapon; armory %d pieces, treasury %d (reserve %d)" % [
		100.0 * mc[0], 100.0 * mc[1], arm.size(), int(e["treasury"]), int(reserve)])
	check(mc[1] >= 1.0, "every militiaman has a weapon")
	check(mc[0] >= 0.9, "the militia's loadout slots are at least 90% filled")
	check(float(e["treasury"]) >= reserve, "the arms bill never dips into the garrison's reserve")

	# 3. a caravan's guards are kitted from the armory before they leave; their kit comes home to it
	_stock_stalls(t)
	_looks(t, 1)   # the armory refills to its target (which holds a caravan's guards)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var gu := Factory.make_warband(rng, String(t["faction"]), ArmsTrade.max_guards(t), int(t["wealth"]))
	var wb := {"id": "kit_test", "kind": "caravan", "origin": t["id"], "home": t["id"], "units": gu, "faction": t["faction"]}
	var tre0 := float(e["treasury"])
	var arm0 := arm.size()
	ArmsTrade.kit_guards(Game, t, wb)
	var gc := _cover(gu)
	print("-- guards (%d): %.0f%% of loadout slots, %.0f%% with a weapon; armory %d -> %d, treasury %d -> %d" % [gu.size(), 100.0 * gc[0],
		100.0 * gc[1], arm0, arm.size(), int(tre0), int(e["treasury"])])
	check(bool(wb.get("outfitted", false)), "the guards' kit is real (outfitted)")
	check(gc[1] >= 1.0, "every caravan guard has a weapon")
	check(gc[0] >= 0.9, "the guards' loadout slots are at least 90% filled")
	check(arm.size() < arm0, "the guards drew their kit from the armory")
	var carried := 0
	for u in gu:
		for s in u.equip:
			if ArmsTrade.cls(u.equip[s].tid) != "":
				carried += 1
	var arm1 := arm.size()
	ArmsTrade.guards_home(Game, wb)
	check(arm.size() == arm1 + carried, "the guards' armory kit goes back into the armory (%d -> %d, %d carried)" % [arm1, arm.size(), carried])

	# 4. a town that cannot pay: its men stay short and the armory log says why
	arm.clear()
	_strip(mil)
	_stock_stalls(t)
	e["treasury"] = 0.0
	_looks(t, 1)
	var mc2 := _cover(mil)
	var lg := ArmsTrade.armory_log(t)
	print("-- broke town: militia %.0f%% of loadout slots; log: %s" % [100.0 * mc2[0], String(lg[-1]) if not lg.is_empty() else "(none)"])
	check(mc2[0] < 0.5, "a town with an empty chest cannot kit its stripped militia")
	check(not lg.is_empty() and String(lg[-1]).contains("cannot pay"), "the armory log says the treasury cannot pay")
	check(float(e.get("arms_due", 0.0)) > 0.0, "the shortfall goes on the month's budget (arms_due)")
	return fails
