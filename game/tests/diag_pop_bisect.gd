extends RefCounted
## Version-tolerant copy of tests/diag_economy_fast.gd for bisecting population starvation
## across older checkouts (v0.032..v0.042).

var ROOT: String = "user://econ_fast_" + OS.get_environment("ECON_TAG") if OS.get_environment("ECON_TAG") != "" else "user://econ_fast"
const META: String = "_diag_pop_bisect"
const LEGACY_META: String = "_diag_economy_fast"
const YEAR_DAYS: int = 120
const WEEK: int = 7
const MONTH: int = 30
const STOP_MS: int = 52000
const WORLD_SEED: int = 4242

var _started: int = 0
var _origin: int = 0
var _year_i: int = 1
var _year_end: int = 0
var _completed_year: int = 0
var _flows: Dictionary = {}
var _metrics_base: Dictionary = {}
var _court = null
var _court_checked: bool = false
var _prof: Dictionary = {}
var _prof_printed: bool = false
var _classes_built: bool = false
var _class_paths: Dictionary = {}
var _class_cache: Dictionary = {}


func _cls(cname: String):
	if not _classes_built:
		_classes_built = true
		for item in ProjectSettings.get_global_class_list():
			if item is Dictionary:
				var row: Dictionary = item
				var k: String = str(row.get("class", ""))
				var p: String = str(row.get("path", ""))
				if k != "" and p != "":
					_class_paths[k] = p
	if _class_cache.has(cname):
		return _class_cache[cname]
	var path: String = str(_class_paths.get(cname, ""))
	var loaded = null
	if path != "" and ResourceLoader.exists(path):
		loaded = load(path)
	_class_cache[cname] = loaded
	return loaded


func _unique_save_file(base_prefix: String, ext: String) -> String:
	var base: String = base_prefix + ext
	if not FileAccess.file_exists(base):
		return base
	var letters: String = "bcdefghijklmnopqrstuvwxyz"
	for i in letters.length():
		var cand: String = "%s_%s%s" % [base_prefix, letters.substr(i, 1), ext]
		if not FileAccess.file_exists(cand):
			return cand
	var k: int = 2
	while true:
		var cand: String = "%s_%d%s" % [base_prefix, k, ext]
		if not FileAccess.file_exists(cand):
			return cand
		k += 1
	return base


func _base_path(n: int) -> String:
	return "%s/checkpoint_year_%d.save" % [ROOT, n]


func _save_path_for(n: int) -> String:
	return _unique_save_file("%s/checkpoint_year_%d" % [ROOT, n], ".save")


func _latest_for_year(n: int) -> String:
	var best: String = ""
	var base: String = _base_path(n)
	if FileAccess.file_exists(base):
		best = base
	var letters: String = "bcdefghijklmnopqrstuvwxyz"
	for i in letters.length():
		var cand: String = "%s/checkpoint_year_%d_%s.save" % [ROOT, n, letters.substr(i, 1)]
		if FileAccess.file_exists(cand):
			best = cand
		else:
			break
	var k: int = 2
	while true:
		var cand2: String = "%s/checkpoint_year_%d_%d.save" % [ROOT, n, k]
		if FileAccess.file_exists(cand2):
			best = cand2
			k += 1
		else:
			break
	return best


func _find_load_path(from_year: int) -> String:
	for n in range(from_year - 1, -1, -1):
		var found: String = _latest_for_year(n)
		if found != "":
			return found
	return ""


func _flow(uid: String, key: String, amount: float) -> void:
	if uid == "" or amount == 0.0:
		return
	if not _flows.has(uid):
		_flows[uid] = {}
	var row: Dictionary = _flows[uid]
	row[key] = float(row.get(key, 0.0)) + amount


func _income(uid: String) -> float:
	var row: Dictionary = _flows.get(uid, {})
	var total: float = 0.0
	for key in ["land", "business", "wages", "lord_tax", "tribute"]:
		total += float(row.get(key, 0.0))
	return total


func _mod_day(prev: int, now: int, modulus: int, residue: int) -> int:
	if now <= prev or modulus <= 0:
		return -1
	var start: int = prev + 1
	var dist: int = (residue - (start % modulus) + modulus) % modulus
	var at: int = start + dist
	return at if at <= now else -1


func _ids() -> Array:
	var towns_var = Game.world.get("towns", {})
	if not (towns_var is Dictionary):
		return []
	var ids: Array = (towns_var as Dictionary).keys()
	ids.sort()
	return ids


func _clear_work() -> void:
	Game.world["work"] = []
	Game.world["encounter"] = ""


func _court_script():
	if not _court_checked:
		_court_checked = true
		var loaded = _cls("CourtEvents")
		if loaded == null:
			var path: String = "res://campaign/court_events.gd"
			if ResourceLoader.exists(path):
				loaded = load(path)
		if loaded != null and loaded.has_method("hoard_view"):
			_court = loaded
	return _court


func _hoard(uid: String) -> float:
	var script = _court_script()
	if uid == "" or script == null:
		return -1.0
	var total: float = 0.0
	for item in script.hoard_view(Game, uid):
		if item is Dictionary:
			total += float((item as Dictionary).get("value", 0.0))
	return total


func _family_alive(f: Dictionary) -> bool:
	return not f.is_empty() and not bool(f.get("gone", false)) and not f.has("estate") and Families.people(f) > 0


func _tax_recipient(tid: String) -> Dictionary:
	var F = _cls("Feudal")
	if F != null and F.has_method("tax_recipient"):
		var res = F.tax_recipient(Game, tid)
		if res is Dictionary:
			return res
	return {}


func _payer_house() -> Dictionary:
	var F = _cls("Feudal")
	if F != null and F.has_method("_payer"):
		var res = F._payer(Game)
		if res is Dictionary:
			return res
	return {}


func _rulers() -> Dictionary:
	var out: Dictionary = {}
	for key in _ids():
		var f: Dictionary = _tax_recipient(str(key))
		var uid: String = str(f.get("household_uid", ""))
		if uid != "":
			out[uid] = f
	var player: Dictionary = _payer_house()
	var puid: String = str(player.get("household_uid", ""))
	if puid != "" and not out.has(puid):
		out[puid] = player
	return out


func _spread(values: Array) -> Dictionary:
	if values.is_empty():
		return {"med": 0.0, "min": 0.0, "max": 0.0}
	var copy: Array = values.duplicate()
	copy.sort()
	var n: int = copy.size()
	var med: float = float(copy[n / 2]) if n % 2 == 1 else (float(copy[n / 2 - 1]) + float(copy[n / 2])) * 0.5
	return {"med": med, "min": float(copy[0]), "max": float(copy[n - 1])}


func _book_family(f: Dictionary, end: int, before: float) -> void:
	var after: float = float(f.get("last", before))
	if after == before and before != float(end):
		return
	var uid: String = str(f.get("household_uid", ""))
	var span: float = clampf(float(end) - before, 1.0, 60.0)
	var parts_var = f.get("income_parts", {})
	var parts: Dictionary = parts_var if parts_var is Dictionary else {}
	var scale: float = span / 7.0
	_flow(uid, "land", float(parts.get("land", 0.0)) * scale)
	_flow(uid, "business", (float(parts.get("business profit", 0.0)) + float(parts.get("business funding", 0.0))) * scale)
	_flow(uid, "wages", (float(parts.get("staff wages", 0.0)) + float(parts.get("casual work", 0.0))) * scale)


func _turn_households(town: Dictionary, end: int) -> void:
	var e: Dictionary = town["econ"]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([int(Game.world.get("seed", 0)), town.get("id", ""), end, "fam", -1])
	var fams_var = e.get("fams", [])
	var copy: Array = (fams_var as Array).duplicate() if fams_var is Array else []
	if "batch_open" in TownEcon:
		TownEcon.batch_open = true
	for item in copy:
		if not (item is Dictionary):
			continue
		var f: Dictionary = item
		if bool(f.get("gone", false)) or f.has("estate"):
			continue
		var before: float = float(f.get("last", end))
		Families.turn(Game, town, e, f, float(end), rng)
		_book_family(f, end, before)
	TownEcon.batch_open = false
	TownEcon.clear_batch(e)
	Families.match_idle(e)


func _tax_snap() -> Dictionary:
	var out: Dictionary = {}
	var towns_var = Game.world.get("towns", {})
	if not (towns_var is Dictionary):
		return out
	var towns: Dictionary = towns_var
	for key in towns.keys():
		var town_var = towns[key]
		if not (town_var is Dictionary):
			continue
		var town: Dictionary = town_var
		if not TownEcon.has_econ(town):
			continue
		var stats_var = town["econ"].get("stats", {})
		var stats: Dictionary = stats_var if stats_var is Dictionary else {}
		out[str(key)] = {
			"uid": str(_tax_recipient(str(key)).get("household_uid", "")),
			"tax": float(stats.get("lord_tax", 0.0)),
		}
	return out


func _tax_delta(pre: Dictionary) -> void:
	var towns_var = Game.world.get("towns", {})
	if not (towns_var is Dictionary):
		return
	var towns: Dictionary = towns_var
	for tid in pre.keys():
		var town_var = towns.get(tid, {})
		if not (town_var is Dictionary):
			continue
		var town: Dictionary = town_var
		if town.is_empty() or not TownEcon.has_econ(town):
			continue
		var row: Dictionary = pre[tid]
		var stats_var = town["econ"].get("stats", {})
		var stats: Dictionary = stats_var if stats_var is Dictionary else {}
		var delta: float = float(stats.get("lord_tax", 0.0)) - float(row.get("tax", 0.0))
		if delta > 0.0:
			_flow(str(row.get("uid", "")), "lord_tax", delta)


func _tribute(day: int) -> void:
	var feudal_var = Game.world.get("feudal", {})
	if not (feudal_var is Dictionary):
		return
	var rows_var = (feudal_var as Dictionary).get("towns", {})
	if not (rows_var is Dictionary):
		return
	var rows: Dictionary = rows_var
	for tid in rows.keys():
		var row_var = rows[tid]
		if not (row_var is Dictionary):
			continue
		var row: Dictionary = row_var
		if int(row.get("tribute_day", -2)) != day:
			continue
		var amount: float = float(row.get("tribute", 0.0))
		if amount == 0.0:
			continue
		var parent: String = str(row.get("liege_town_id", ""))
		var uid: String = str(_tax_recipient(parent).get("household_uid", ""))
		_flow(uid, "tribute", amount)


func _pt(k: String, t0: int) -> void:
	_prof[k] = int(_prof.get(k, 0)) + Time.get_ticks_usec() - t0


func _heavy(prev: int, end: int) -> void:
	_clear_work()
	var ids: Array = _ids()
	var towns: Dictionary = Game.world["towns"]
	var P = _cls("Persons")
	var M = _cls("Migration")
	for d in range(prev + 1, end + 1):
		Game.day = float(d)
		var td: int = Time.get_ticks_usec()
		for key in ids:
			var town: Dictionary = towns[key]
			if TownEcon.has_econ(town) and true:
				TownEcon.daily_pass(Game, town, d, true)
		_pt("daily_pass", td)
		td = Time.get_ticks_usec()
		if true:
			Barge.coin_day(Game, d)
		_pt("coin_day", td)
	var _t: int = Time.get_ticks_usec()
	Game.day = float(end)
	for key in ids:
		var town: Dictionary = towns[key]
		if TownEcon.has_econ(town):
			_turn_households(town, end)
	_pt("households", _t)
	_t = Time.get_ticks_usec()
	for i in ids.size():
		var town: Dictionary = towns[ids[i]]
		if not TownEcon.has_econ(town):
			continue
		if true:
			TownEcon.town_turn(Game, town, end)
		var tax_residue: int = (MONTH - ((i * 7) % MONTH)) % MONTH
		var tax_day: int = _mod_day(prev, end, MONTH, tax_residue)
		if tax_day >= 0 and true:
			Game.day = float(tax_day)
			Barge.treasury_month(Game, town, town["econ"], float(tax_day))
		var wed_residue: int = (3 - (i % 28) + 28) % 28
		var wed_day: int = _mod_day(prev, end, 28, wed_residue)
		if wed_day >= 0 and P != null and P.has_method("marriages"):
			Game.day = float(wed_day)
			P.marriages(town["econ"], float(wed_day))
	_pt("town_turn+tax+wed", _t)
	_t = Time.get_ticks_usec()
	Game.day = float(end)
	if true:
		TownEcon.faction_turn(Game, end)
	if _mod_day(prev, end, MONTH, 15) >= 0 and true:
		Barge.move_in(Game, float(end))
	if _mod_day(prev, end, WEEK, 5) >= 0 and M != null and M.has_method("weekly"):
		M.weekly(Game, float(end))
	_pt("faction+move+migr", _t)
	_clear_work()


func _coarse(prev: int, end: int) -> void:
	var pre: Dictionary = _tax_snap()
	_heavy(prev, end)
	var _t2: int = Time.get_ticks_usec()
	var S = _cls("Settlement")
	var F = _cls("Feudal")
	for d in range(prev + 1, end + 1):
		Game.day = float(d)
		if S != null and S.has_method("daily"):
			S.daily(Game, d)
		if F != null and F.has_method("daily"):
			F.daily(Game, d)
		_tribute(d)
	_pt("settle+feudal daily", _t2)
	_tax_delta(pre)
	_clear_work()
	Game.day = float(end)
	Game.world["last_day"] = end


func _town_starved(e: Dictionary, census: Dictionary, stats: Dictionary) -> int:
	var total: int = 0
	var has_census_causes: bool = false
	var rows_var = census.get("rows", [])
	if rows_var is Array:
		for r_item in rows_var:
			if r_item is Dictionary:
				var d_var = (r_item as Dictionary).get("deaths", null)
				if d_var is Dictionary:
					has_census_causes = true
					total += int((d_var as Dictionary).get("starved", 0))
	var cur_var = census.get("cur", null)
	if cur_var is Dictionary:
		var cd_var = (cur_var as Dictionary).get("deaths", null)
		if cd_var is Dictionary:
			has_census_causes = true
			total += int((cd_var as Dictionary).get("starved", 0))
	if not has_census_causes:
		var dc_var = stats.get("dc", null)
		if dc_var is Dictionary and (dc_var as Dictionary).has("starved"):
			total = int((dc_var as Dictionary).get("starved", 0))
		else:
			var sk_var = e.get("sk", null)
			if sk_var is Dictionary:
				total = int((sk_var as Dictionary).get("starved", 0))
	return total


func _metrics_snapshot() -> Dictionary:
	var w: Dictionary = Game.world
	var ledger_var = w.get("coin", {})
	var ledger: Dictionary = ledger_var if ledger_var is Dictionary else {}
	var holdings_val: float = float(Barge.holdings(Game)) if true else 0.0
	var out: Dictionary = {
		"day": int(floor(Game.day)), "population": 0, "population_cached": 0, "births": 0, "deaths": 0,
		"starved": 0, "grain_stock": 0, "staffed_farms": 0, "farm_vacant": 0,
		"farm_wages": [], "day_wages": [],
		"businesses_open": 0, "businesses_total": 0, "businesses_staffed": 0,
		"land_acres": 0, "worked_acres": 0.0, "ruler_acres": 0, "harvest": {}, "harvest_area": {},
		"houses": 0.0, "cohorts": 0.0, "treasuries": 0.0, "tills": 0.0, "farm": 0.0,
		"other": float(Game.gold), "holdings": holdings_val,
		"cast": float(ledger.get("cast", 0.0)), "melted": float(ledger.get("melted", 0.0)),
		"drained": float(ledger.get("drained", 0.0)),
		"ledger_ok": ledger.has("cast") and ledger.has("melted") and ledger.has("drained"),
		"grain_prices": [], "bread_prices": [], "price_levels": [], "grain_demand_ema": 0.0,
	}
	var towns_var = w.get("towns", {})
	var towns: Dictionary = towns_var if towns_var is Dictionary else {}
	for town_item in towns.values():
		if not (town_item is Dictionary):
			continue
		var town: Dictionary = town_item
		if not TownEcon.has_econ(town):
			continue
		var e: Dictionary = town["econ"]
		var census_var = e.get("census", {})
		var census: Dictionary = census_var if census_var is Dictionary else {}
		var stats_var = e.get("stats", {})
		var stats: Dictionary = stats_var if stats_var is Dictionary else {}
		out["births"] += int(census.get("bt", stats.get("births", 0)))
		out["deaths"] += int(census.get("dt", stats.get("deaths", 0)))
		out["starved"] += _town_starved(e, census, stats)
		out["population_cached"] += int(e.get("pop", 0))
		out["treasuries"] += float(e.get("treasury", 0.0))
		out["farm"] += float(e.get("farm_till", 0.0))
		var stock_var = e.get("stock", {})
		if stock_var is Dictionary:
			out["grain_stock"] += int((stock_var as Dictionary).get("grain", 0))
		var dw: float = float(Barge.day_wage(e)) if true else float(e.get("dwage", 0.0))
		(out["day_wages"] as Array).append(dw)
		var fams_var = e.get("fams", [])
		var fams: Array = fams_var if fams_var is Array else []
		for f_item in fams:
			if not (f_item is Dictionary):
				continue
			var f: Dictionary = f_item
			var is_coh: bool = bool(Population.is_cohort(f)) if true else false
			var sector: String = "treasuries" if f.has("estate") else ("cohorts" if is_coh else "houses")
			out[sector] += float(f.get("purse", 0.0))
			if not bool(f.get("gone", false)) and not f.has("estate"):
				out["population"] += Families.people(f)
		var biz_var = e.get("biz", [])
		var biz_list: Array = biz_var if biz_var is Array else []
		for b_item in biz_list:
			if not (b_item is Dictionary):
				continue
			var b: Dictionary = b_item
			out["tills"] += float(b.get("till", 0.0))
			out["businesses_total"] += 1
			var btype: String = str(b.get("type", ""))
			var is_farm: bool = btype == "farm" or btype == "estate"
			if not bool(b.get("closed", false)):
				out["businesses_open"] += 1
				var bw: int = int(b.get("workers", 0))
				var bkw: int = int(b.get("kw", 0))
				if bw + bkw > 0:
					out["businesses_staffed"] += 1
				if is_farm:
					if bw + bkw > 0:
						out["staffed_farms"] += 1
					var bc: int = int(b.get("cap", 0))
					out["farm_vacant"] += maxi(0, bc - bw)
					(out["farm_wages"] as Array).append(float(b.get("wage", 0.0)))
		var led_var = e.get("led", {})
		var led: Dictionary = led_var if led_var is Dictionary else {}
		var made_var = led.get("made", {})
		var made: Dictionary = made_var if made_var is Dictionary else {}
		var harvest: Dictionary = out["harvest"]
		var land_var = e.get("land", {})
		var land: Dictionary = land_var if land_var is Dictionary else {}
		var h_area_var = stats.get("harvest_area", {})
		var h_area: Dictionary = h_area_var if h_area_var is Dictionary else {}
		for crop in land:
			out["land_acres"] += int(land[crop])
			harvest[crop] = int(harvest.get(crop, 0)) + int(made.get(crop, 0))
			out["harvest_area"][crop] = float(out["harvest_area"].get(crop, 0.0)) + float(h_area.get(crop, 0.0))
		var wacres_var = e.get("wacres", {})
		if wacres_var is Dictionary:
			for acres in (wacres_var as Dictionary).values():
				out["worked_acres"] += float(acres)
		var prices_var = e.get("price", {})
		var prices: Dictionary = prices_var if prices_var is Dictionary else {}
		for good in ["grain", "bread"]:
			if prices.has(good):
				(out[good + "_prices"] as Array).append(float(prices[good]))
		(out["price_levels"] as Array).append(float(e.get("pl", 1.0)))
		var dem_var = e.get("dem", {})
		var dem: Dictionary = dem_var if dem_var is Dictionary else {}
		out["grain_demand_ema"] += float(dem.get("grain", 0.0))
	for f_item in _rulers().values():
		if f_item is Dictionary:
			var rf: Dictionary = f_item
			if _family_alive(rf):
				out["ruler_acres"] += Families.acres(rf)
	var factions_var = w.get("factions", {})
	if factions_var is Dictionary:
		for fac_item in (factions_var as Dictionary).values():
			if fac_item is Dictionary:
				var fac: Dictionary = fac_item
				out["treasuries"] += float(fac.get("treasury", 0.0))
				out["other"] += float(fac.get("loot", 0.0))
	var lairs_var = w.get("lairs", {})
	if lairs_var is Dictionary:
		for lair_item in (lairs_var as Dictionary).values():
			if lair_item is Dictionary:
				out["other"] += float((lair_item as Dictionary).get("gold", 0.0))
	var bands_var = w.get("warbands", {})
	if bands_var is Dictionary:
		for band_item in (bands_var as Dictionary).values():
			if band_item is Dictionary:
				out["other"] += float((band_item as Dictionary).get("gold", 0.0))
	return out


func _metric_delta(now: Dictionary, key: String) -> float:
	return float(now.get(key, 0.0)) - float(_metrics_base.get(key, 0.0))


func _harvest_delta(now: Dictionary) -> int:
	var harvest_units: int = 0
	var prior_var = _metrics_base.get("harvest", {})
	var prior_harvest: Dictionary = prior_var if prior_var is Dictionary else {}
	var now_harvest: Dictionary = now["harvest"]
	for crop in now_harvest:
		harvest_units += int(now_harvest[crop]) - int(prior_harvest.get(crop, 0))
	return harvest_units


func _print_bisect(now: Dictionary, year_i: int) -> void:
	var births: int = int(_metric_delta(now, "births"))
	var deaths: int = int(_metric_delta(now, "deaths"))
	var starved: int = int(_metric_delta(now, "starved"))
	var harvest_units: int = _harvest_delta(now)
	var fw_med: float = float(_spread(now["farm_wages"])["med"])
	var dw_med: float = float(_spread(now["day_wages"])["med"])
	print("BISECT year=%d day=%d population=%d births=%d deaths=%d starved=%d worked_acres=%.2f harvest=%d grain_stock=%d staffed_farms=%d farm_vacant=%d farm_wage_med=%.2f day_wage_med=%.2f" % [
		year_i, int(now["day"]), int(now["population"]), births, deaths, starved,
		float(now["worked_acres"]), harvest_units, int(now["grain_stock"]),
		int(now["staffed_farms"]), int(now["farm_vacant"]), fw_med, dw_med])


func _year_metrics(now: Dictionary) -> String:
	var days: int = int(_metric_delta(now, "day"))
	var births: int = int(_metric_delta(now, "births"))
	var deaths: int = int(_metric_delta(now, "deaths"))
	var population_delta: int = int(_metric_delta(now, "population"))
	var harvest: Dictionary = {}
	var harvest_units: int = 0
	var yields: Dictionary = {}
	var prior_var = _metrics_base.get("harvest", {})
	var prior_harvest: Dictionary = prior_var if prior_var is Dictionary else {}
	var base_area_var = _metrics_base.get("harvest_area", {})
	var base_area: Dictionary = base_area_var if base_area_var is Dictionary else {}
	for crop in now["harvest"]:
		harvest[crop] = int(now["harvest"][crop]) - int(prior_harvest.get(crop, 0))
		harvest_units += int(harvest[crop])
		var area: float = float(now["harvest_area"].get(crop, 0.0)) - float(base_area.get(crop, 0.0))
		yields[crop] = float(harvest[crop]) / area if area > 0.0 else -1.0
	var split: float = 0.0
	for key in ["houses", "cohorts", "treasuries", "tills", "farm", "other"]:
		split += float(now[key])
	var grain: Array = now["grain_prices"]
	var bread: Array = now["bread_prices"]
	var grain_text: String = "na" if grain.is_empty() else "%.4f" % float(_spread(grain)["med"])
	var bread_text: String = "na" if bread.is_empty() else "%.4f" % float(_spread(bread)["med"])
	var coin_text: String = " coin_created_ledger=na coin_destroyed_ledger=na coin_melted=na coin_drained=na coin_unexplained=na coin_ledger_gap=na"
	if bool(now["ledger_ok"]) and bool(_metrics_base.get("ledger_ok", false)):
		var created: float = _metric_delta(now, "cast")
		var melted: float = _metric_delta(now, "melted")
		var drained: float = _metric_delta(now, "drained")
		coin_text = " coin_created_ledger=%.2f coin_destroyed_ledger=%.2f coin_melted=%.2f coin_drained=%.2f coin_unexplained=%.2f coin_ledger_gap=%.2f" % [
			created, melted + drained, melted, drained,
			_metric_delta(now, "holdings") - created + melted + drained,
			float(now["holdings"]) - float(now["cast"]) + float(now["melted"]) + float(now["drained"])]
	var text: String = " diag_days=%d diag_full_year=%s population=%d population_delta=%d births=%d deaths=%d population_other_delta=%d pop_count_gap=%d businesses_open=%d businesses_total=%d businesses_staffed=%d land_acres=%d worked_acres=%.2f ruler_acres=%d harvest_units=%d harvest_by_crop=%s grain_price_med=%s bread_price_med=%s bread_markets=%d price_level_med=%.4f grain_demand_ema=%.2f coin_houses=%.2f coin_cohorts=%.2f coin_treasuries=%.2f coin_tills=%.2f coin_farm=%.2f coin_other=%.2f coin_split_gap=%.4f coin_delta=%.2f" % [
		days, str(days == YEAR_DAYS), int(now["population"]), population_delta, births, deaths,
		population_delta - births + deaths, int(now["population_cached"]) - int(now["population"]),
		int(now["businesses_open"]), int(now["businesses_total"]), int(now["businesses_staffed"]),
		int(now["land_acres"]), float(now["worked_acres"]), int(now["ruler_acres"]), harvest_units, JSON.stringify(harvest),
		grain_text, bread_text, bread.size(), float(_spread(now["price_levels"])["med"]), float(now["grain_demand_ema"]),
		float(now["houses"]), float(now["cohorts"]), float(now["treasuries"]), float(now["tills"]), float(now["farm"]), float(now["other"]),
		float(now["holdings"]) - split, _metric_delta(now, "holdings")]
	_metrics_base = now
	return text + coin_text + " harvest_yield_per_worked_acre=" + JSON.stringify(yields)


func _print_year(year_i: int) -> void:
	var now: Dictionary = _metrics_snapshot()
	_print_bisect(now, year_i)
	var rulers: Dictionary = _rulers()
	var ph_var = Game.world.get("player_house", {})
	var ph: Dictionary = ph_var if ph_var is Dictionary else {}
	var puid: String = str(ph.get("household_uid", ""))
	var player: Dictionary = _payer_house()
	if puid == "":
		puid = str(player.get("household_uid", ""))
	var purses: Array = []
	var incomes: Array = []
	var alive: int = 0
	var ai: int = 0
	for uid in rulers.keys():
		var f: Dictionary = rulers[uid]
		if not _family_alive(f):
			continue
		alive += 1
		if str(uid) == puid:
			continue
		ai += 1
		purses.append(float(f.get("purse", 0.0)))
		incomes.append(_income(str(uid)))
	var purse_s: Dictionary = _spread(purses)
	var income_s: Dictionary = _spread(incomes)
	var treasuries: Array = []
	for key in _ids():
		var town: Dictionary = Game.world["towns"][key]
		if TownEcon.has_econ(town):
			treasuries.append(float(town["econ"].get("treasury", 0.0)))
	var tre: Dictionary = _spread(treasuries)
	var hoard: float = _hoard(puid)
	var hoard_text: String = "na" if hoard < 0.0 else "%.2f" % hoard
	var holdings_val: float = float(Barge.holdings(Game)) if true else 0.0
	print("FAST year=%d step=weekly player_purse=%.2f player_hoard=%s player_income=%.2f ai_alive=%d ai_purse_med=%.2f ai_purse_min=%.2f ai_purse_max=%.2f ai_income_med=%.2f treasury_med=%.2f holdings=%.2f houses_alive=%d%s" % [
		year_i, float(player.get("purse", 0.0)), hoard_text, _income(puid), ai,
		float(purse_s["med"]), float(purse_s["min"]), float(purse_s["max"]), float(income_s["med"]),
		float(tre["med"]), holdings_val, alive, _year_metrics(now)])
	_flows = {}


func _pick_player() -> String:
	var Dr = _cls("Dragons")
	var HO = _cls("HouseOnboarding")
	if Dr != null and Dr.has_method("records") and Dr.has_method("_person") and HO != null and HO.has_method("begin"):
		for item in Dr.records(Game):
			if not (item is Dictionary):
				continue
			var dragon: Dictionary = item
			if str(dragon.get("stage", "")) != "adult" or not bool(dragon.get("alive", false)):
				continue
			var owner_var = Dr._person(Game, str(dragon.get("owner_person_uid", "")))
			if not (owner_var is Dictionary):
				continue
			var owner: Dictionary = owner_var
			if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner.get("town_id", "")):
				continue
			var res_var = HO.begin(Game, str(owner["town_id"]), str(owner["household_uid"]))
			if res_var is Dictionary and bool((res_var as Dictionary).get("ok", false)):
				return str(owner["town_id"])
	var dt = _cls("DevTools")
	if dt != null and dt.has_method("choose_house"):
		return str(dt.choose_house(Game))
	var Dy = _cls("Dynasty")
	if Dy != null and Dy.has_method("choices") and HO != null and HO.has_method("begin"):
		var by_pop: Array = Dy.choices(Game)
		by_pop.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa: int = int(Game.world.get("towns", {}).get(a.get("town_id", ""), {}).get("econ", {}).get("pop", 0))
			var pb: int = int(Game.world.get("towns", {}).get(b.get("town_id", ""), {}).get("econ", {}).get("pop", 0))
			return pa > pb
		)
		for item2 in by_pop:
			if not (item2 is Dictionary):
				continue
			var choice: Dictionary = item2
			var res2_var = HO.begin(Game, str(choice.get("town_id", "")), str(choice.get("household_uid", "")))
			if res2_var is Dictionary and bool((res2_var as Dictionary).get("ok", false)):
				return str(choice.get("town_id", ""))
	return ""


func _stand_at(tid: String) -> void:
	if tid == "":
		return
	var dt = _cls("DevTools")
	if dt != null and dt.has_method("stand_at"):
		dt.stand_at(Game, tid)
		return
	Game.location = tid
	var party_var = Game.world.get("party", null)
	var towns_var = Game.world.get("towns", null)
	if party_var is Dictionary and towns_var is Dictionary:
		var town_var = (towns_var as Dictionary).get(tid, null)
		if town_var is Dictionary and (town_var as Dictionary).has("pos"):
			(party_var as Dictionary)["pos"] = (town_var as Dictionary)["pos"]
		(party_var as Dictionary)["path"] = []
	Game.world["encounter"] = ""


func _start_world(tree: SceneTree) -> bool:
	var dt = _cls("DevTools")
	if dt != null and dt.has_method("start_world"):
		var temp_save: String = _unique_save_file("user://diag_pop_bisect", ".json")
		var ok: bool = await dt.start_world(tree, temp_save)
		return ok
	if "gen_size" in WorldGen:
		WorldGen.gen_size = "normal"
	if "presim_span_days" in CampaignWorld:
		CampaignWorld.presim_span_days = 1
	var M = _cls("Monsters")
	if M != null and "new_world_creatures" in M:
		M.new_world_creatures = false
	if Game.has_method("new_game_begin") and Game.has_method("new_game_slice"):
		var generation: Dictionary = Game.new_game_begin(WORLD_SEED)
		while not bool(Game.new_game_slice(generation, 8000)):
			await tree.process_frame
		var history: Dictionary = {}
		if true and true:
			while int(CampaignWorld.presim_left(Game)) > 0:
				CampaignWorld.presim_slice(Game, history, 8000)
				await tree.process_frame
		if true:
			CampaignWorld.presim_finish(Game, 0)
		var Dy = _cls("Dynasty")
		if Dy != null and Dy.has_method("prepare_world"):
			Dy.prepare_world(Game)
		if Game.has_method("new_game_finalize"):
			Game.new_game_finalize()
		return not _ids().is_empty()
	elif Game.has_method("new_game"):
		Game.new_game(WORLD_SEED)
		return not _ids().is_empty()
	return false


func _save_checkpoint(day: int, target: int) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var ck_year: int = _completed_year if _completed_year > 0 else maxi(0, _year_i - 1)
	var save_path: String = _save_path_for(ck_year)
	var meta_payload: Dictionary = {
		"origin": _origin,
		"year_i": _year_i,
		"year_end": _year_end,
		"completed_year": _completed_year,
		"flows": _flows,
		"metrics_base": _metrics_base,
	}
	Game.world[META] = meta_payload
	Game.world[LEGACY_META] = meta_payload
	Game._save_ready = true
	Game._save_pending = false
	Game.SAVE_PATH = save_path
	Game.save_game()
	if Game.has_method("wait_save"):
		Game.wait_save()
	var complete: bool = day >= target
	if not complete:
		var now: Dictionary = _metrics_snapshot()
		_print_bisect(now, _year_i)
		var day_in_year: int = day - (_year_end - YEAR_DAYS)
		print("FAST stopped year=%d day_in_year=%d/%d day=%d target_day=%d completed_year=%d elapsed_s=%.2f checkpoint=%s" % [
			_year_i, day_in_year, YEAR_DAYS, day, target, _completed_year,
			float(Time.get_ticks_msec() - _started) / 1000.0, save_path])
	var last_ok: bool = true
	if Game.has_method("save_stats"):
		var st_var = Game.save_stats()
		if st_var is Dictionary:
			last_ok = bool((st_var as Dictionary).get("last_ok", false))
	print("FAST checkpoint year=%d complete=%s day=%d/%d checkpoint_written=%s elapsed_ms=%d path=%s" % [
		ck_year, str(complete), day, target, str(last_ok),
		Time.get_ticks_msec() - _started, save_path])


func _simulate(tree: SceneTree, from_year: int, to_year: int) -> void:
	var target: int = _origin + to_year * YEAR_DAYS
	var day: int = int(floor(Game.day))
	if _metrics_base.is_empty():
		_metrics_base = _metrics_snapshot()
	print("FAST metrics population=resident_rows prices=year_end_town_medians harvest=made_crop_units coin_sectors=houses+cohorts+treasuries+tills+farm+other; estate_purses=treasuries; other=company+faction_loot+lairs+warbands; population_other_delta=migration_or_count_drift")
	var families: int = 0
	for key in _ids():
		var town: Dictionary = Game.world["towns"][key]
		if TownEcon.has_econ(town):
			var fams_var = town["econ"].get("fams", [])
			if fams_var is Array:
				families += (fams_var as Array).size()
	print("FAST note step=weekly year_days=%d from_year=%d to_year=%d origin=%d day=%d towns=%d families=%d" % [
		YEAR_DAYS, from_year, to_year, _origin, day, _ids().size(), families])
	var last_step_ms: int = 0
	var first_year_done: int = _year_i
	while day < target:
		if Time.get_ticks_msec() - _started + last_step_ms >= STOP_MS:
			break
		var left: int = mini(_year_end, target) - day
		var span: int = mini(WEEK, left)
		if left - span > 0 and left - span < WEEK:
			span = left
		var t0: int = Time.get_ticks_msec()
		_coarse(day, day + span)
		last_step_ms = Time.get_ticks_msec() - t0
		day += span
		if day >= _year_end and _year_i <= to_year:
			_print_year(_year_i)
			_completed_year = _year_i
			_year_i += 1
			_year_end += YEAR_DAYS
			if not _prof_printed and _year_i > first_year_done:
				_prof_printed = true
				print("FAST profile ms ", JSON.stringify(_prof))
		await tree.process_frame
	if not _prof_printed:
		_prof_printed = true
		print("FAST profile ms ", JSON.stringify(_prof))
	_save_checkpoint(day, target)


func _done() -> void:
	print("FAST done secs=%.2f" % (float(Time.get_ticks_msec() - _started) / 1000.0))


func _parse_args() -> Vector2i:
	var from_year: int = 1
	var to_year: int = 3
	var to_set: bool = false
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--from_year="):
			from_year = maxi(1, int(arg.substr(12)))
		elif arg.begins_with("--to_year="):
			to_year = maxi(1, int(arg.substr(10)))
			to_set = true
	if not to_set and to_year < from_year:
		to_year = from_year + 2
	elif to_year < from_year:
		to_year = from_year
	return Vector2i(from_year, to_year)


func run(tree: SceneTree) -> int:
	_started = Time.get_ticks_msec()
	await tree.process_frame
	if Game.has_method("wait_save"):
		Game.wait_save()
	var old_path: String = Game.SAVE_PATH
	var bounds: Vector2i = _parse_args()
	var from_year: int = bounds.x
	var to_year: int = bounds.y
	Game.settings["guide_seen"] = true
	if from_year == 1:
		if not await _start_world(tree):
			print("FAST note start_failed")
			Game.SAVE_PATH = old_path
			_done()
			return 0
		var tid: String = _pick_player()
		if tid != "":
			_stand_at(tid)
		_origin = int(floor(Game.day))
		_year_i = 1
		_year_end = _origin + YEAR_DAYS
		_completed_year = 0
		_flows = {}
		_metrics_base = {}
	else:
		var load_path: String = _find_load_path(from_year)
		if load_path == "":
			print("FAST note missing_checkpoint from_year=%d expected=%s" % [from_year, _base_path(from_year - 1)])
			Game.SAVE_PATH = old_path
			_done()
			return 0
		Game.SAVE_PATH = load_path
		if not Game.load_game():
			print("FAST note load_failed path=%s" % load_path)
			Game.SAVE_PATH = old_path
			_done()
			return 0
		var state_var = Game.world.get(META, Game.world.get(LEGACY_META, {}))
		var state: Dictionary = state_var if state_var is Dictionary else {}
		_origin = int(state.get("origin", int(floor(Game.day)) - (from_year - 1) * YEAR_DAYS))
		_year_i = int(state.get("year_i", from_year))
		_year_end = int(state.get("year_end", _origin + _year_i * YEAR_DAYS))
		_completed_year = int(state.get("completed_year", _year_i - 1))
		var flows_var = state.get("flows", {})
		_flows = (flows_var as Dictionary).duplicate(true) if flows_var is Dictionary else {}
		var base_var = state.get("metrics_base", {})
		_metrics_base = (base_var as Dictionary).duplicate(true) if base_var is Dictionary else {}
		print("FAST loaded path=%s day=%d year=%d" % [load_path, int(floor(Game.day)), _year_i])
	Game._save_ready = false
	Game._save_pending = false
	Game._active_screen = "presim"
	_clear_work()
	await _simulate(tree, from_year, to_year)
	if Game.has_method("wait_save"):
		Game.wait_save()
	Game.SAVE_PATH = old_path
	_done()
	return 0
