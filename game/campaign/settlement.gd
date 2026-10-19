class_name Settlement
extends RefCounted

const MAX_LEVEL: int = 3
const BASE_FOOD_CAP: int = 1000
const GRANARY_CAP_BONUS: int = 500
const HOUSING_BONUS_PER_LEVEL: float = 30.0
const MARKET_BONUS_PER_LEVEL: float = 0.10
const WALLS_BONUS_PER_LEVEL: float = 0.15
const TEMPLE_GRIEVANCE_DROP: float = 0.05
const AI_COOLDOWN_DAYS: int = 30
const AI_RICH_TREASURY: float = 500.0
const AI_RICH_PURSE: float = 2500.0
## Quarters of People.year_days(), in Calendar order: spring, summer, autumn, winter.
## Applied to the flat daily yield so a granary, not a daily surplus, carries a town through winter.
const HARVEST_SEASON_MULT: Array[float] = [0.8, 1.2, 1.6, 0.2]

const KEYS: Array[String] = ["granary", "housing", "market", "walls", "temple"]

const CATALOG: Dictionary = {
	"granary": {
		"key": "granary",
		"name": "Granary",
		"base_cost": 1200,
		"base_days": 6,
		"desc": "Raises town food storage capacity."
	},
	"housing": {
		"key": "housing",
		"name": "Housing",
		"base_cost": 1400,
		"base_days": 7,
		"desc": "Expands household room capacity and eases crowding."
	},
	"market": {
		"key": "market",
		"name": "Market",
		"base_cost": 1600,
		"base_days": 8,
		"desc": "Increases town trade and tax income."
	},
	"walls": {
		"key": "walls",
		"name": "Walls",
		"base_cost": 2000,
		"base_days": 10,
		"desc": "Provides a siege defence bonus."
	},
	"temple": {
		"key": "temple",
		"name": "Temple",
		"base_cost": 1500,
		"base_days": 7,
		"desc": "Lowers local sickness and feudal grievance."
	}
}

static func _econ_of(town_or_econ: Dictionary) -> Dictionary:
	if town_or_econ.has("econ") and town_or_econ["econ"] is Dictionary:
		return town_or_econ["econ"]
	return town_or_econ

static func _town_by_id(game, town_id: String) -> Dictionary:
	if game == null or not (game.world is Dictionary):
		return {}
	var towns: Dictionary = game.world.get("towns", {})
	var t = towns.get(town_id, {})
	return t if t is Dictionary else {}

static func _feudal_row(game, town_id: String) -> Dictionary:
	if game == null or not (game.world is Dictionary):
		return {}
	var feudal: Dictionary = game.world.get("feudal", {})
	var f_towns: Dictionary = feudal.get("towns", {})
	var row = f_towns.get(town_id, {})
	return row if row is Dictionary else {}

static func _day_of(game, day: int = -1) -> int:
	if day >= 0:
		return day
	if game != null and "day" in game:
		return int(floor(float(game.day)))
	if game != null and game.world is Dictionary:
		return int(floor(float(game.world.get("day", 0.0))))
	return 0

static func _num(v, default_val: float = 0.0) -> float:
	if v is int or v is float:
		return float(v)
	return default_val

static func _pop_of(town_or_econ: Dictionary) -> int:
	var e: Dictionary = _econ_of(town_or_econ)
	var p = e.get("pop", town_or_econ.get("pop", 0))
	if p is int or p is float:
		return maxi(0, int(p))
	return 0

static func _calc_food_capacity(town_or_econ: Dictionary) -> int:
	var e: Dictionary = _econ_of(town_or_econ)
	var lvl: int = building_level(e, "granary")
	var cons: int = daily_consumption(town_or_econ)
	if cons <= 0:
		return BASE_FOOD_CAP * (1 + lvl)
	return cons * 30 * (1 + lvl)

static func ensure_town(town_or_econ: Dictionary) -> Dictionary:
	var e: Dictionary = _econ_of(town_or_econ)
	if not (e.get("buildings") is Dictionary):
		e["buildings"] = {}
	var b: Dictionary = e["buildings"]
	for k in KEYS:
		b[k] = clampi(int(_num(b.get(k, 0), 0.0)), 0, MAX_LEVEL)
	if not (e.get("projects") is Array):
		e["projects"] = []
	var clean_projects: Array = []
	var raw_projects: Array = e["projects"]
	for item in raw_projects:
		if item is Dictionary and CATALOG.has(str(item.get("key", ""))):
			var p: Dictionary = item
			p["key"] = str(p.get("key", ""))
			p["target_level"] = clampi(int(_num(p.get("target_level", 1), 1.0)), 1, MAX_LEVEL)
			p["days_left"] = maxi(0, int(_num(p.get("days_left", 1), 1.0)))
			p["started_day"] = int(_num(p.get("started_day", 0), 0.0))
			p["cost"] = maxi(0, int(_num(p.get("cost", 0), 0.0)))
			clean_projects.append(p)
			break
	e["projects"] = clean_projects
	var cap: int = _calc_food_capacity(town_or_econ)
	if not (e.get("food") is Dictionary):
		var init_stock: int = clampi(cap / 2, 0, cap)
		e["food"] = {
			"stock": init_stock,
			"capacity": cap,
			"last_stock": init_stock,
			"store_famine": false
		}
	else:
		var food: Dictionary = e["food"]
		food["capacity"] = cap
		food["stock"] = clampi(int(_num(food.get("stock", cap / 2), float(cap / 2))), 0, cap)
		if not food.has("last_stock"):
			food["last_stock"] = int(food["stock"])
		else:
			food["last_stock"] = int(_num(food.get("last_stock", food["stock"]), float(food["stock"])))
		food["store_famine"] = bool(food.get("store_famine", false))
	return e

static func building_level(town_or_econ: Dictionary, key: String) -> int:
	if town_or_econ.is_empty() or not CATALOG.has(key):
		return 0
	var e: Dictionary = _econ_of(town_or_econ)
	if not (e.get("buildings") is Dictionary):
		return 0
	var b: Dictionary = e["buildings"]
	return clampi(int(_num(b.get(key, 0), 0.0)), 0, MAX_LEVEL)

static func walls_level(town_or_econ: Dictionary) -> int:
	return building_level(town_or_econ, "walls")

static func siege_bonus(town_or_econ: Dictionary) -> float:
	return float(walls_level(town_or_econ)) * WALLS_BONUS_PER_LEVEL

static func housing_bonus(town_or_econ: Dictionary) -> float:
	return float(building_level(town_or_econ, "housing")) * HOUSING_BONUS_PER_LEVEL

static func food_capacity(town_or_econ: Dictionary) -> int:
	var e: Dictionary = ensure_town(town_or_econ)
	var food: Dictionary = e["food"]
	return int(food.get("capacity", BASE_FOOD_CAP))

static func cost_for_level(key: String, target_level: int) -> int:
	if not CATALOG.has(key):
		return 0
	var spec: Dictionary = CATALOG[key]
	return int(spec.get("base_cost", 100)) * clampi(target_level, 1, MAX_LEVEL)

static func days_for_level(key: String, target_level: int) -> int:
	if not CATALOG.has(key):
		return 0
	var spec: Dictionary = CATALOG[key]
	return int(spec.get("base_days", 5)) * clampi(target_level, 1, MAX_LEVEL)

static func is_player_town(game, town_id: String) -> bool:
	if game == null or not (game.world is Dictionary):
		return false
	var selected: Dictionary = Dynasty.selected(game)
	if selected.is_empty() or not Dynasty.holds_office(game) or not bool(Dynasty.ruler(game).get("alive", false)):
		return false
	var p_house_uid: String = str(selected.get("house_uid", ""))
	if p_house_uid == "":
		return false
	var office: Dictionary = Dynasty.town_office(game, town_id)
	if not office.is_empty() and not bool(office.get("vacant", true)):
		return str(office.get("house_uid", "")) == p_house_uid
	var town: Dictionary = _town_by_id(game, town_id)
	if town.is_empty():
		return false
	var e: Dictionary = _econ_of(town)
	var head: Dictionary = e.get("head", {})
	return str(head.get("house_uid", "")) == p_house_uid

static func start_preview(game, town_id: String, key: String) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": "",
		"cost": 0,
		"days": 0,
		"level": 0,
		"key": key,
		"town_id": town_id
	}
	if game == null or not (game.world is Dictionary):
		out["reason"] = "no_world"
		return out
	var town: Dictionary = _town_by_id(game, town_id)
	if town.is_empty():
		out["reason"] = "no_town"
		return out
	if not CATALOG.has(key):
		out["reason"] = "bad_key"
		return out
	if not is_player_town(game, town_id):
		out["reason"] = "not_player_town"
		return out
	var e: Dictionary = ensure_town(town)
	var cur_level: int = building_level(e, key)
	if cur_level >= MAX_LEVEL:
		out["reason"] = "max_level"
		out["level"] = cur_level
		return out
	var next_level: int = cur_level + 1
	var cost: int = cost_for_level(key, next_level)
	var days: int = days_for_level(key, next_level)
	out["level"] = next_level
	out["cost"] = cost
	out["days"] = days
	var projects: Array = e.get("projects", [])
	if not projects.is_empty():
		out["reason"] = "busy"
		return out
	var payer: Dictionary = Feudal._payer(game)
	var purse: float = float(payer.get("purse", 0.0))
	if purse < float(cost):
		out["reason"] = "no_funds"
		return out
	out["ok"] = true
	return out

static func start(game, town_id: String, key: String, review: Dictionary = {}) -> Dictionary:
	var check: Dictionary = start_preview(game, town_id, key)
	if not bool(check.get("ok", false)):
		return check
	var cost: int = int(check.get("cost", 0))
	var days: int = int(check.get("days", 1))
	var next_level: int = int(check.get("level", 1))
	if not review.is_empty() and bool(review.get("ok", false)):
		if str(review.get("key", key)) == key and str(review.get("town_id", town_id)) == town_id:
			cost = int(review.get("cost", cost))
			days = int(review.get("days", days))
			next_level = int(review.get("level", next_level))
	var payer: Dictionary = Feudal._payer(game)
	if float(payer.get("purse", 0.0)) < float(cost):
		check["ok"] = false
		check["reason"] = "no_funds"
		return check
	payer["purse"] = float(payer.get("purse", 0.0)) - float(cost)
	var town: Dictionary = _town_by_id(game, town_id)
	var e: Dictionary = ensure_town(town)
	HouseUpkeep._pay_town_folk(e, payer, float(cost))
	var day_now: int = _day_of(game)
	var proj: Dictionary = {
		"key": key,
		"target_level": next_level,
		"days_left": days,
		"started_day": day_now,
		"cost": cost
	}
	var projects: Array = e["projects"]
	projects.append(proj)
	var spec: Dictionary = CATALOG[key]
	CampaignWorld.log_event(
		game,
		"%s began building %s Lv.%d (%d days)." % [str(town.get("name", town_id)), str(spec.get("name", key)), next_level, days]
	)
	check["project"] = proj
	return check

## Season index 0..3 from game.day (or an explicit day): each quarter of People.year_days().
static func harvest_season_index(day: float) -> int:
	var year_len: float = maxf(4.0, People.year_days())
	var quarter: float = year_len / 4.0
	var wrapped: float = fposmod(day, year_len)
	return clampi(int(floor(wrapped / quarter)), 0, 3)

static func harvest_season_mult(day: float) -> float:
	return HARVEST_SEASON_MULT[harvest_season_index(day)]

static func _harvest_day(day: float = -1.0) -> float:
	if day >= 0.0:
		return day
	return float(Game.day)

## Flat daily yield before the seasonal multiplier.
static func _base_daily_harvest(town_or_econ: Dictionary) -> int:
	var e: Dictionary = _econ_of(town_or_econ)
	var wacres: Dictionary = e["wacres"] if e.get("wacres") is Dictionary else {}
	var land: Dictionary = e["land"] if e.get("land") is Dictionary else {}
	var herd: Dictionary = e["herd"] if e.get("herd") is Dictionary else {}
	var grain_acres: float = _num(wacres.get("grain", land.get("grain", 0.0)), 0.0)
	var fruit_acres: float = _num(wacres.get("fruit", land.get("fruit", 0.0)), 0.0)
	var herd_total: float = 0.0
	for hk in herd.keys():
		var hv = herd.get(hk)
		if hv is int or hv is float:
			herd_total += float(hv)
	var pop: int = _pop_of(town_or_econ)
	var raw: float = (grain_acres * 0.35 + fruit_acres * 0.25 + herd_total * 0.15) * 0.22
	if raw <= 0.0:
		if pop <= 0:
			return 0
		raw = float(pop) * 0.12
	return maxi(1, int(round(raw)))

## Seasonal harvest. `day` defaults to Game.day. Winter is a fraction of the flat yield.
static func daily_harvest(town_or_econ: Dictionary, day: float = -1.0) -> int:
	var base: int = _base_daily_harvest(town_or_econ)
	if base <= 0:
		return 0
	return maxi(0, int(round(float(base) * harvest_season_mult(_harvest_day(day)))))

static func daily_consumption(town_or_econ: Dictionary) -> int:
	var pop: int = _pop_of(town_or_econ)
	if pop <= 0:
		return 0
	return maxi(1, int(ceil(float(pop) * 0.08)))

static func update_food(town_or_econ: Dictionary, day: float = -1.0) -> void:
	var e: Dictionary = ensure_town(town_or_econ)
	var food: Dictionary = e["food"]
	var cap: int = _calc_food_capacity(town_or_econ)
	food["capacity"] = cap
	var cur_stock: int = int(_num(food.get("stock", 0), 0.0))
	var last_stock: int = int(_num(food.get("last_stock", cur_stock), float(cur_stock)))
	var harvest: int = daily_harvest(town_or_econ, day)
	var cons: int = daily_consumption(town_or_econ)
	var net: int = harvest - cons
	var new_stock: int = cur_stock
	if cur_stock <= 0 and last_stock != 0:
		new_stock = 0
	elif last_stock <= 0 and cur_stock > 0:
		new_stock = clampi(cur_stock + maxi(0, net), 1, cap)
	else:
		new_stock = clampi(cur_stock + net, 0, cap)
	food["stock"] = new_stock
	food["last_stock"] = new_stock
	if new_stock <= 0:
		if not bool(e.get("famine", false)):
			food["store_famine"] = true
			e["famine"] = true
		elif bool(food.get("store_famine", false)):
			e["famine"] = true
	else:
		if bool(food.get("store_famine", false)):
			food["store_famine"] = false
			if _num(e.get("food_short", 0.0), 0.0) <= 0.05:
				e["famine"] = false

static func _apply_daily_effects(game, town: Dictionary) -> void:
	var e: Dictionary = ensure_town(town)
	var tid: String = str(town.get("id", ""))
	var market_lvl: int = building_level(e, "market")
	if market_lvl > 0:
		var stats: Dictionary = e.get("stats", {}) if e.get("stats") is Dictionary else {}
		var base_trade: float = _num(stats.get("mtax", stats.get("tax_month", 0.0)), 0.0) / 30.0
		if base_trade < 2.0:
			base_trade = 2.0
		var bonus: float = base_trade * float(market_lvl) * MARKET_BONUS_PER_LEVEL
		if game != null and game.world is Dictionary and tid != "":
			var rec: Dictionary = Feudal.tax_recipient(game, tid)
			if not rec.is_empty():
				# The market allowance is paid from actual municipal receipts.
				var paid: float = minf(bonus, maxf(0.0, _num(e.get("treasury", 0.0), 0.0)))
				e["treasury"] = _num(e.get("treasury", 0.0), 0.0) - paid
				rec["purse"] = _num(rec.get("purse", 0.0), 0.0) + paid
	var temple_lvl: int = building_level(e, "temple")
	if temple_lvl > 0:
		if game != null and game.world is Dictionary and tid != "":
			var f_row: Dictionary = _feudal_row(game, tid)
			if not f_row.is_empty():
				var g: float = _num(f_row.get("grievance", 0.0), 0.0)
				f_row["grievance"] = clampf(g - TEMPLE_GRIEVANCE_DROP * float(temple_lvl), 0.0, 100.0)
		if game != null and game.world is Dictionary:
			var sk: Dictionary = game.world.get("sickness", {}) if game.world.get("sickness") is Dictionary else {}
			var cases: Dictionary = sk.get("cases", {}) if sk.get("cases") is Dictionary else {}
			for uid in cases.keys():
				if not (cases[uid] is Dictionary):
					continue
				var c: Dictionary = cases[uid]
				if str(c.get("town_id", "")) == tid:
					c["severity"] = maxf(0.0, _num(c.get("severity", 1.0), 1.0) * (1.0 - 0.05 * float(temple_lvl)))

static func _advance_projects(game, town: Dictionary) -> void:
	var e: Dictionary = ensure_town(town)
	var projects: Array = e["projects"]
	if projects.is_empty():
		return
	var proj: Dictionary = projects[0]
	var left: int = int(_num(proj.get("days_left", 1), 1.0)) - 1
	proj["days_left"] = left
	if left <= 0:
		var key: String = str(proj.get("key", ""))
		var target_lvl: int = clampi(int(_num(proj.get("target_level", building_level(e, key) + 1), float(building_level(e, key) + 1))), 1, MAX_LEVEL)
		var b: Dictionary = e["buildings"]
		if CATALOG.has(key):
			b[key] = target_lvl
		projects.remove_at(0)
		var food: Dictionary = e["food"]
		var cap: int = _calc_food_capacity(town)
		food["capacity"] = cap
		food["stock"] = clampi(int(_num(food.get("stock", 0), 0.0)), 0, cap)
		food["last_stock"] = int(food["stock"])
		if game != null and game.world is Dictionary:
			var tid: String = str(town.get("id", ""))
			var spec: Dictionary = CATALOG.get(key, {})
			CampaignWorld.log_event(
				game,
				"%s completed %s Lv.%d." % [str(town.get("name", tid)), str(spec.get("name", key)), target_lvl]
			)

static func _maybe_ai_start(game, town: Dictionary, day: int) -> void:
	if game == null or not (game.world is Dictionary):
		return
	var selected: Dictionary = Dynasty.selected(game)
	if selected.is_empty():
		return
	var tid: String = str(town.get("id", ""))
	if tid == "" or is_player_town(game, tid):
		return
	var e: Dictionary = ensure_town(town)
	var projects: Array = e["projects"]
	if not projects.is_empty():
		return
	var last_day: int = int(_num(e.get("ai_project_day", -999), -999.0))
	if day >= 0 and (day - last_day) < AI_COOLDOWN_DAYS:
		return
	var best_key: String = ""
	var best_lvl: int = MAX_LEVEL
	for k in KEYS:
		var lvl: int = building_level(e, k)
		if lvl < best_lvl:
			best_lvl = lvl
			best_key = k
	if best_key == "":
		return
	var next_lvl: int = best_lvl + 1
	var cost: int = cost_for_level(best_key, next_lvl)
	var days: int = days_for_level(best_key, next_lvl)
	var treasury: float = _num(e.get("treasury", 0.0), 0.0)
	var rec: Dictionary = Feudal.tax_recipient(game, tid)
	var payer: Dictionary = Feudal._payer(game)
	var p_huid: String = str(payer.get("household_uid", selected.get("household_uid", "")))
	var r_huid: String = str(rec.get("household_uid", ""))
	var is_player_payer: bool = (not payer.is_empty() and is_same(rec, payer)) or (p_huid != "" and r_huid == p_huid)
	var purse: float = _num(rec.get("purse", 0.0), 0.0)
	var funded: bool = false
	if treasury >= AI_RICH_TREASURY and treasury >= float(cost):
		e["treasury"] = treasury - float(cost)
		funded = true
	elif not rec.is_empty() and not is_player_payer and purse >= AI_RICH_PURSE and purse >= float(cost):
		rec["purse"] = purse - float(cost)
		funded = true
	if not funded:
		return
	# Construction pays existing local households; it does not erase coin.
	HouseUpkeep._pay_town_folk(e, rec, float(cost))
	e["ai_project_day"] = day
	var proj: Dictionary = {
		"key": best_key,
		"target_level": next_lvl,
		"days_left": days,
		"started_day": day,
		"cost": cost
	}
	projects.append(proj)
	var spec: Dictionary = CATALOG[best_key]
	CampaignWorld.log_event(
		game,
		"%s began building %s Lv.%d (%d days)." % [str(town.get("name", tid)), str(spec.get("name", best_key)), next_lvl, days]
	)

static func _town_list(game) -> Array:
	var out: Array = []
	if game == null or not (game.world is Dictionary):
		return out
	var raw = game.world.get("towns", {})
	if raw is Dictionary:
		var d: Dictionary = raw
		var keys: Array = d.keys()
		keys.sort()
		for k in keys:
			if d[k] is Dictionary:
				out.append(d[k])
	elif raw is Array:
		var a: Array = raw
		for item in a:
			if item is Dictionary:
				out.append(item)
	return out

static func daily(game, day: int = -1) -> void:
	if game == null or not (game.world is Dictionary):
		return
	var d: int = _day_of(game, day)
	var towns: Array = _town_list(game)
	for t in towns:
		var town: Dictionary = t
		ensure_town(town)
		_advance_projects(game, town)
		update_food(town, float(d))
		_apply_daily_effects(game, town)
		_maybe_ai_start(game, town, d)

static func after_load(game) -> void:
	if game == null or not (game.world is Dictionary):
		return
	var towns: Array = _town_list(game)
	for t in towns:
		var town: Dictionary = t
		var e: Dictionary = ensure_town(town)
		if e.has("ai_project_day"):
			e["ai_project_day"] = int(_num(e.get("ai_project_day", -999), -999.0))
