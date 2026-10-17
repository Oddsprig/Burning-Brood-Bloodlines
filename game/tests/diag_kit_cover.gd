extends RefCounted
## DIAGNOSTIC (not a regression test): militia and caravan-guard kit coverage per town on a Normal world (seed 2026),
## after world generation and after the years before. Coverage = share of men with body armour, a helm, a weapon
## (main hand or bow), and the share of their troop loadout's armory slots that are filled. Armory stock vs target,
## stalls' arms, treasury. Caravan guards are sampled every 10 days through the years before.
## DIAG_DAYS (default the full years before) limits the run.

var car_acc := {"men": 0, "body": 0, "helm": 0, "weap": 0, "slots": 0, "filled": 0, "bands": 0}

func run(_tree: SceneTree) -> int:
	Game.new_game(2026)
	var w: Dictionary = Game.world
	print("== after world gen (day %d) ==" % int(Game.day))
	_report(w)
	var days := int(OS.get_environment("DIAG_DAYS")) if OS.get_environment("DIAG_DAYS") != "" else CampaignWorld.presim_total(Game)
	w["presim"] = {"total": days, "done": 0, "from": Game.day}
	var d := 0
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_step(Game, 1)
		d += 1
		if d % 10 == 0:
			_sample_caravans(w)
	CampaignWorld.presim_finish(Game, 0)
	print("== after the years before (day %d) ==" % int(Game.day))
	_report(w)
	print("caravan guards sampled every 10 days: %s" % _cov_line(car_acc))
	return 0

func _cov(units: Array) -> Dictionary:
	var a := {"men": 0, "body": 0, "helm": 0, "weap": 0, "slots": 0, "filled": 0}
	for u in units:
		if not u is Unit or u.dead or u.race_def().get("creature", false):
			continue
		a["men"] += 1
		if u.equip.has("body"): a["body"] += 1
		if u.equip.has("helm"): a["helm"] += 1
		if u.equip.has("main_hand") or u.equip.has("ranged"): a["weap"] += 1
		var lo := ArmsTrade.loadout_of(u)
		for s in lo:
			if lo[s]["opt"]:
				continue
			a["slots"] += 1
			if u.equip.has(s): a["filled"] += 1
	return a

func _add(acc: Dictionary, a: Dictionary) -> void:
	for k in a:
		acc[k] = int(acc.get(k, 0)) + int(a[k])

func _cov_line(a: Dictionary) -> String:
	var m := maxi(1, int(a["men"]))
	return "%d men: body %d%% helm %d%% weapon %d%% loadout slots %d%%" % [int(a["men"]), 100 * int(a["body"]) / m,
		100 * int(a["helm"]) / m, 100 * int(a["weap"]) / m, 100 * int(a["filled"]) / maxi(1, int(a["slots"]))]

func _sample_caravans(w: Dictionary) -> void:
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if String(wb.get("kind", "")) == "caravan" and wb.get("outfitted", false):
			_add(car_acc, _cov(wb["units"]))
			car_acc["bands"] += 1

func _report(w: Dictionary) -> void:
	var ids: Array = w["towns"].keys()
	ids.sort()
	var mil_all := {}
	var car_all := {}
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		var mil := _cov(Militia.units_of(Game, tid))
		_add(mil_all, mil)
		var car := {}
		for wid in w["warbands"]:
			var wb: Dictionary = w["warbands"][wid]
			if String(wb.get("kind", "")) == "caravan" and String(wb.get("origin", "")) == tid:
				_add(car, _cov(wb["units"]))
		_add(car_all, car)
		var tgt := ArmsTrade.targets(Game, t)
		var have := ArmsTrade.class_counts(ArmsTrade.armory(t))
		var tg := 0
		var hv := 0
		for c in tgt:
			tg += int(tgt[c])
		for c in have:
			hv += int(have[c])
		var smiths := []
		for b in e["biz"]:
			if String(b["type"]) in ["weaponsmith", "armorsmith"]:
				smiths.append("%s %d/%d%s %s %s till %d" % [b["type"], int(b["workers"]), int(b["cap"]), " closed" if b.get("closed", false) else "",
					String(b.get("state", "")), String(b.get("why", "")), int(b.get("till", 0))])
		smiths.append("bars cu %d sn %d br %d fe %d st %d" % [int(e["stock"].get("copper_bars", 0)), int(e["stock"].get("tin_bars", 0)),
			int(e["stock"].get("bronze_bars", 0)), int(e["stock"].get("iron_bars", 0)), int(e["stock"].get("steel_bars", 0))])
		if not ArmsTrade.armory_log(t).is_empty():
			smiths.append("log: " + String(ArmsTrade.armory_log(t)[-1]))
		print("%s (%s, size %d wealth %d) treasury %d | militia %s | caravans %s | armory %d / target %d (short %s) | stalls arms %d | %s" % [
			tid, t["name"], int(t["size"]), int(t["wealth"]), int(e["treasury"]),
			_cov_line(mil), _cov_line(car) if car.has("men") else "none", hv, tg, str(e.get("arms_short", {})),
			TownEcon.arms_count(t), ", ".join(PackedStringArray(smiths))])
	print("ALL militia: %s" % _cov_line(mil_all))
	if car_all.has("men"):
		print("ALL caravans on the map: %s" % _cov_line(car_all))
