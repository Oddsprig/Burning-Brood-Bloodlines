extends RefCounted
## Fast 12-year economy measurement, split across runs (--from_year=A --to_year=B, default 1..3).
## Each run stops and checkpoints before 55 s, using 120-day years and 7-day steps.
##
## Each step calls the economy entry points the midnight tick uses, and nothing else:
##   TownEcon.daily_pass + Barge.coin_day once per calendar day inside the step
##   Settlement.daily + Feudal.daily once per calendar day (tax, tribute, market bonus, projects)
##   Families.turn for every living household once per weekly step (Population.turn runs inside it);
##     Families.turn spans the days since that household's last turn (clamped 1..60)
##   TownEcon.town_turn, TownEcon.faction_turn once per weekly step
##   Barge.treasury_month / Barge.move_in / Migration.weekly / Persons.marriages
##     only when that calendar day falls inside the step
##
## Skipped on purpose: battles, army jobs, pathing, warbands, war AI, monster spawns,
## dragon combat and dragon care, rendering, autosave, company wages/healing/meals,
## census, caravans (town_turn may queue one; the queue is dropped), herds, the
## sickness work queue, diplomacy's daily pass, plots, and party movement.
## A 120-day year is sixteen 7-day steps plus one 8-day step (120 is not divisible by 7).
##
## Year 1 starts from DevTools.start_world; later runs load the checkpoint from the previous
## run under user://econ_fast/checkpoint_year_N.save (or _b, _c, ... if that file already exists).

var ROOT: String = "user://econ_fast_" + OS.get_environment("ECON_TAG") if OS.get_environment("ECON_TAG") != "" else "user://econ_fast"
const META: String = "_diag_economy_fast"
const YEAR_DAYS: int = 120
const WEEK: int = 7
const MONTH: int = 30
const STOP_MS: int = 52000

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


func _base_path(n: int) -> String:
	return "%s/checkpoint_year_%d.save" % [ROOT, n]


func _save_path_for(n: int) -> String:
	var base: String = _base_path(n)
	if not FileAccess.file_exists(base):
		return base
	var letters: String = "bcdefghijklmnopqrstuvwxyz"
	for i in letters.length():
		var cand: String = "%s/checkpoint_year_%d_%s.save" % [ROOT, n, letters.substr(i, 1)]
		if not FileAccess.file_exists(cand):
			return cand
	var k: int = 2
	while true:
		var cand: String = "%s/checkpoint_year_%d_%d.save" % [ROOT, n, k]
		if not FileAccess.file_exists(cand):
			return cand
		k += 1
	return base


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
	var ids: Array = Game.world.get("towns", {}).keys()
	ids.sort()
	return ids


func _clear_work() -> void:
	Game.world["work"] = []
	Game.world["encounter"] = ""


func _court_script():
	if not _court_checked:
		_court_checked = true
		var path: String = "res://campaign/court_events.gd"
		if ResourceLoader.exists(path):
			var loaded = load(path)
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


func _rulers() -> Dictionary:
	var out: Dictionary = {}
	for key in _ids():
		var f: Dictionary = Feudal.tax_recipient(Game, str(key))
		var uid: String = str(f.get("household_uid", ""))
		if uid != "":
			out[uid] = f
	var player: Dictionary = Feudal._payer(Game)
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
	var parts: Dictionary = f.get("income_parts", {})
	var scale: float = span / 7.0
	_flow(uid, "land", float(parts.get("land", 0.0)) * scale)
	_flow(uid, "business", (float(parts.get("business profit", 0.0)) + float(parts.get("business funding", 0.0))) * scale)
	_flow(uid, "wages", (float(parts.get("staff wages", 0.0)) + float(parts.get("casual work", 0.0))) * scale)


func _turn_households(town: Dictionary, end: int) -> void:
	var e: Dictionary = town["econ"]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([int(Game.world.get("seed", 0)), town.get("id", ""), end, "fam", -1])
	var copy: Array = (e.get("fams", []) as Array).duplicate()
	TownEcon.batch_open = true
	for item in copy:
		if not item is Dictionary:
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
	var towns: Dictionary = Game.world.get("towns", {})
	for key in towns.keys():
		var town: Dictionary = towns[key]
		if not TownEcon.has_econ(town):
			continue
		out[str(key)] = {
			"uid": str(Feudal.tax_recipient(Game, str(key)).get("household_uid", "")),
			"tax": float(town["econ"].get("stats", {}).get("lord_tax", 0.0)),
		}
	return out


func _tax_delta(pre: Dictionary) -> void:
	var towns: Dictionary = Game.world.get("towns", {})
	for tid in pre.keys():
		var town: Dictionary = towns.get(tid, {})
		if town.is_empty() or not TownEcon.has_econ(town):
			continue
		var row: Dictionary = pre[tid]
		var delta: float = float(town["econ"].get("stats", {}).get("lord_tax", 0.0)) - float(row.get("tax", 0.0))
		if delta > 0.0:
			_flow(str(row.get("uid", "")), "lord_tax", delta)


func _tribute(day: int) -> void:
	var rows: Dictionary = Game.world.get("feudal", {}).get("towns", {})
	for tid in rows.keys():
		var row: Dictionary = rows[tid]
		if int(row.get("tribute_day", -2)) != day:
			continue
		var amount: float = float(row.get("tribute", 0.0))
		if amount == 0.0:
			continue
		var parent: String = str(row.get("liege_town_id", ""))
		var uid: String = str(Feudal.tax_recipient(Game, parent).get("household_uid", ""))
		_flow(uid, "tribute", amount)


func _pt(k: String, t0: int) -> void:
	_prof[k] = int(_prof.get(k, 0)) + Time.get_ticks_usec() - t0


func _heavy(prev: int, end: int) -> void:
	_clear_work()
	var ids: Array = _ids()
	var towns: Dictionary = Game.world["towns"]
	for d in range(prev + 1, end + 1):
		Game.day = float(d)
		var td: int = Time.get_ticks_usec()
		for key in ids:
			var town: Dictionary = towns[key]
			if TownEcon.has_econ(town):
				TownEcon.daily_pass(Game, town, d, true)
		_pt("daily_pass", td)
		td = Time.get_ticks_usec()
		Barge.coin_day(Game, d)
		_pt("coin_day", td)
	var _t: int = Time.get_ticks_usec()
	Game.day = float(end)
	for key in ids:
		var town: Dictionary = towns[key]
		if TownEcon.has_econ(town):
			_turn_households(town, end)
	_pt("households", _t); _t = Time.get_ticks_usec()
	for i in ids.size():
		var town: Dictionary = towns[ids[i]]
		if not TownEcon.has_econ(town):
			continue
		TownEcon.town_turn(Game, town, end)
		var tax_residue: int = (MONTH - ((i * 7) % MONTH)) % MONTH
		var tax_day: int = _mod_day(prev, end, MONTH, tax_residue)
		if tax_day >= 0:
			Game.day = float(tax_day)
			Barge.treasury_month(Game, town, town["econ"], float(tax_day))
		var wed_residue: int = (3 - (i % 28) + 28) % 28
		var wed_day: int = _mod_day(prev, end, 28, wed_residue)
		if wed_day >= 0:
			Game.day = float(wed_day)
			Persons.marriages(town["econ"], float(wed_day))
	_pt("town_turn+tax+wed", _t); _t = Time.get_ticks_usec()
	Game.day = float(end)
	TownEcon.faction_turn(Game, end)
	if _mod_day(prev, end, MONTH, 15) >= 0:
		Barge.move_in(Game, float(end))
	if _mod_day(prev, end, WEEK, 5) >= 0:
		Migration.weekly(Game, float(end))
	_pt("faction+move+migr", _t)
	_clear_work()


func _coarse(prev: int, end: int) -> void:
	var pre: Dictionary = _tax_snap()
	_heavy(prev, end)
	var _t2: int = Time.get_ticks_usec()
	for d in range(prev + 1, end + 1):
		Game.day = float(d)
		Settlement.daily(Game, d)
		Feudal.daily(Game, d)
		_tribute(d)
	_pt("settle+feudal daily", _t2)
	_tax_delta(pre)
	_clear_work()
	Game.day = float(end)
	Game.world["last_day"] = end


## Read only: scan existing counters/accounts at year boundaries, never replay days or walk plots.
## Keep the baseline in checkpoints so partial runs do not lose births, output or coin flows.
func _metrics_snapshot() -> Dictionary:
	var w: Dictionary = Game.world
	var ledger: Dictionary = w.get("coin", {})
	var out: Dictionary = {
		"day": int(floor(Game.day)), "population": 0, "population_cached": 0, "births": 0, "deaths": 0,
		"businesses_open": 0, "businesses_total": 0, "businesses_staffed": 0,
		"land_acres": 0, "worked_acres": 0.0, "ruler_acres": 0, "harvest": {}, "harvest_area": {},
		"houses": 0.0, "cohorts": 0.0, "treasuries": 0.0, "tills": 0.0, "farm": 0.0,
		"other": float(Game.gold), "holdings": Barge.holdings(Game),
		"cast": float(ledger.get("cast", 0.0)), "melted": float(ledger.get("melted", 0.0)),
		"drained": float(ledger.get("drained", 0.0)),
		"ledger_ok": ledger.has("cast") and ledger.has("melted") and ledger.has("drained"),
		"grain_prices": [], "bread_prices": [], "price_levels": [], "grain_demand_ema": 0.0,
	}
	for town: Dictionary in w.get("towns", {}).values():
		if not TownEcon.has_econ(town):
			continue
		var e: Dictionary = town["econ"]
		var census: Dictionary = e.get("census", {})
		out["births"] += int(census.get("bt", e.get("stats", {}).get("births", 0)))
		out["deaths"] += int(census.get("dt", e.get("stats", {}).get("deaths", 0)))
		out["population_cached"] += int(e.get("pop", 0))
		out["treasuries"] += float(e.get("treasury", 0.0))
		out["farm"] += float(e.get("farm_till", 0.0))
		for f: Dictionary in e.get("fams", []):
			# town_gold counts ALL purses, including gone rows; do the same for coin only.
			var sector: String = "treasuries" if f.has("estate") else ("cohorts" if Population.is_cohort(f) else "houses")
			out[sector] += float(f.get("purse", 0.0))
			if not f.get("gone", false) and not f.has("estate"):
				out["population"] += Families.people(f)
		for b: Dictionary in e.get("biz", []):
			out["tills"] += float(b.get("till", 0.0))
			out["businesses_total"] += 1
			if not b.get("closed", false):
				out["businesses_open"] += 1
				if int(b.get("workers", 0)) + int(b.get("kw", 0)) > 0:
					out["businesses_staffed"] += 1
		var made: Dictionary = e.get("led", {}).get("made", {})
		var harvest: Dictionary = out["harvest"]
		for crop in e.get("land", {}):
			out["land_acres"] += int(e["land"][crop])
			harvest[crop] = int(harvest.get(crop, 0)) + int(made.get(crop, 0))
			out["harvest_area"][crop] = float(out["harvest_area"].get(crop, 0.0)) + float(e.get("stats", {}).get("harvest_area", {}).get(crop, 0.0))
		for acres in e.get("wacres", {}).values():
			out["worked_acres"] += float(acres)
		var prices: Dictionary = e.get("price", {})
		for good in ["grain", "bread"]:
			if prices.has(good):
				(out[good + "_prices"] as Array).append(float(prices[good]))
		(out["price_levels"] as Array).append(float(e.get("pl", 1.0)))
		out["grain_demand_ema"] += float(e.get("dem", {}).get("grain", 0.0))
	for f: Dictionary in _rulers().values():
		if _family_alive(f):
			out["ruler_acres"] += Families.acres(f)
	for fac: Dictionary in w.get("factions", {}).values():
		out["treasuries"] += float(fac.get("treasury", 0.0))
		out["other"] += float(fac.get("loot", 0.0))
	for lair: Dictionary in w.get("lairs", {}).values():
		out["other"] += float(lair.get("gold", 0.0))
	for band: Dictionary in w.get("warbands", {}).values():
		out["other"] += float(band.get("gold", 0.0))
	return out


func _metric_delta(now: Dictionary, key: String) -> float:
	return float(now.get(key, 0.0)) - float(_metrics_base.get(key, 0.0))


func _year_metrics() -> String:
	var now: Dictionary = _metrics_snapshot()
	var days: int = int(_metric_delta(now, "day"))
	var births: int = int(_metric_delta(now, "births"))
	var deaths: int = int(_metric_delta(now, "deaths"))
	var population_delta: int = int(_metric_delta(now, "population"))
	var harvest: Dictionary = {}
	var harvest_units: int = 0
	var yields: Dictionary = {}
	var prior_harvest: Dictionary = _metrics_base.get("harvest", {})
	for crop in now["harvest"]:
		harvest[crop] = int(now["harvest"][crop]) - int(prior_harvest.get(crop, 0))
		harvest_units += int(harvest[crop])
		var area: float = float(now["harvest_area"].get(crop, 0.0)) - float(_metrics_base.get("harvest_area", {}).get(crop, 0.0))
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
		# Positive unexplained = unledgered creation; negative = unledgered destruction.
		# The annual residual excludes inherited ledger offsets; also expose the absolute gap.
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
	var rulers: Dictionary = _rulers()
	var puid: String = str(Game.world.get("player_house", {}).get("household_uid", ""))
	var player: Dictionary = Feudal._payer(Game)
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
	print("FAST year=%d step=weekly player_purse=%.2f player_hoard=%s player_income=%.2f ai_alive=%d ai_purse_med=%.2f ai_purse_min=%.2f ai_purse_max=%.2f ai_income_med=%.2f treasury_med=%.2f holdings=%.2f houses_alive=%d%s" % [
		year_i, float(player.get("purse", 0.0)), hoard_text, _income(puid), ai,
		float(purse_s["med"]), float(purse_s["min"]), float(purse_s["max"]), float(income_s["med"]),
		float(tre["med"]), Barge.holdings(Game), alive, _year_metrics()])
	_flows = {}


func _pick_player() -> String:
	for dragon: Dictionary in Dragons.records(Game):
		if str(dragon.get("stage", "")) != "adult" or not bool(dragon.get("alive", false)):
			continue
		var owner: Dictionary = Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner.get("town_id", "")):
			continue
		if bool(HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"])).get("ok", false)):
			return str(owner["town_id"])
	return DevTools.choose_house(Game)


func _save_checkpoint(day: int, target: int) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var ck_year: int = _completed_year if _completed_year > 0 else maxi(0, _year_i - 1)
	var save_path: String = _save_path_for(ck_year)
	Game.world[META] = {
		"origin": _origin,
		"year_i": _year_i,
		"year_end": _year_end,
		"completed_year": _completed_year,
		"flows": _flows,
		"metrics_base": _metrics_base,
	}
	Game._save_ready = true
	Game._save_pending = false
	Game.SAVE_PATH = save_path
	Game.save_game()
	Game.wait_save()
	var complete: bool = day >= target
	if not complete:
		var day_in_year: int = day - (_year_end - YEAR_DAYS)
		print("FAST stopped year=%d day_in_year=%d/%d day=%d target_day=%d completed_year=%d elapsed_s=%.2f checkpoint=%s" % [
			_year_i, day_in_year, YEAR_DAYS, day, target, _completed_year,
			float(Time.get_ticks_msec() - _started) / 1000.0, save_path])
	print("FAST checkpoint year=%d complete=%s day=%d/%d checkpoint_written=%s elapsed_ms=%d path=%s" % [
		ck_year, str(complete), day, target, str(bool(Game.save_stats().get("last_ok", false))),
		Time.get_ticks_msec() - _started, save_path])


func _simulate(tree: SceneTree, from_year: int, to_year: int) -> void:
	var target: int = _origin + to_year * YEAR_DAYS
	var day: int = int(floor(Game.day))
	if _metrics_base.is_empty():
		# An older midyear checkpoint can only supply a partial diagnostic interval.
		_metrics_base = _metrics_snapshot()
	print("FAST metrics population=resident_rows prices=year_end_town_medians harvest=made_crop_units coin_sectors=houses+cohorts+treasuries+tills+farm+other; estate_purses=treasuries; other=company+faction_loot+lairs+warbands; population_other_delta=migration_or_count_drift")
	var families: int = 0
	for key in _ids():
		var town: Dictionary = Game.world["towns"][key]
		if TownEcon.has_econ(town):
			families += (town["econ"].get("fams", []) as Array).size()
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
	Game.wait_save()
	var old_path: String = Game.SAVE_PATH
	var bounds: Vector2i = _parse_args()
	var from_year: int = bounds.x
	var to_year: int = bounds.y
	Game.settings["guide_seen"] = true
	if from_year == 1:
		if not await DevTools.start_world(tree, "user://diag_economy_fast.json"):
			print("FAST note start_failed")
			Game.SAVE_PATH = old_path
			_done()
			return 0
		var tid: String = _pick_player()
		if tid != "":
			DevTools.stand_at(Game, tid)
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
		var state: Dictionary = Game.world.get(META, {})
		_origin = int(state.get("origin", int(floor(Game.day)) - (from_year - 1) * YEAR_DAYS))
		_year_i = int(state.get("year_i", from_year))
		_year_end = int(state.get("year_end", _origin + _year_i * YEAR_DAYS))
		_completed_year = int(state.get("completed_year", _year_i - 1))
		_flows = (state.get("flows", {}) as Dictionary).duplicate(true)
		_metrics_base = (state.get("metrics_base", {}) as Dictionary).duplicate(true)
		print("FAST loaded path=%s day=%d year=%d" % [load_path, int(floor(Game.day)), _year_i])
	Game._save_ready = false
	Game._save_pending = false
	Game._active_screen = "presim"
	_clear_work()
	await _simulate(tree, from_year, to_year)
	Game.wait_save()
	Game.SAVE_PATH = old_path
	_done()
	return 0
