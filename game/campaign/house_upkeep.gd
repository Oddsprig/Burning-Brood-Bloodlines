class_name HouseUpkeep
extends RefCounted
## Economy pass (coin sinks, part A): ruling and noble house upkeep.
##
## Costs follow each house's trailing-year disposable receipts, including actual local taxes.
## This module adds two coin-conserving household sinks:
##   1) Household staff wages: staff tier (1..5) grows with house wealth and seat rank/prestige;
##      budgeted part-time wages are paid from f["purse"] to real common-folk cohorts / working
##      families in e["fams"]. A house cannot drop below MIN_TIER (1); if f["purse"] cannot cover
##      its tier's weekly wage, the tier steps down with a small prestige loss instead of going
##      negative.
##   2) House improvements: manor_hall, great_kitchen, stables, library, chapel, gardens (levels 1..3).
##      Building charges coin (paid to town folk builders/workers in e["fams"]) plus market materials
##      (wood, stone, iron_bars, tools, furniture) bought from e["stock"] via TownEcon.pay_market,
##      TownEcon.led(e, "used", g, n) and Barge.add_demand. Completed improvements charge weekly
##      upkeep (credited to town folk) and grant yearly prestige plus opinion, health and skill bonuses.
##   3) AI ruling houses: in weekly(game, town, e, f), an AI ruling house buys an improvement or
##      raises its staff tier only from surplus above a safe keep (>= 8 weeks of upkeep), at most
##      one purchase per 30-day month, and never into debt.

# Shares of disposable income AFTER native food, funding, tax, tribute and dragon care.
# Recurring 55% + capital 10% + optional treasury funding 10% leaves at least 25%.
const STAFF_SHARE: float = 0.15
const IMPROVEMENT_SHARE: float = 0.10
const TROOP_SHARE: float = 0.20
const COURT_SHARE: float = 0.10
const CAPITAL_SHARE: float = 0.10
const SERVICE_SCALE: float = 0.25

const MIN_TIER: int = 1
const MAX_TIER: int = 5
const SAFE_KEEP_WEEKS: float = 8.0
const AI_BUY_COOLDOWN_DAYS: int = 30
const PRESTIGE_STEP_DOWN_LOSS: float = 5.0
const BASE_PRESTIGE: float = 25.0

## Nominal staff schedules; multiply by service_scale(e), then cap at STAFF_SHARE.
## At 100/day, full schedules cost 350/1,050/2,450/4,725/7,000 per week.
## A house contracts fewer hours when even tier 1 exceeds its income budget.
const STAFF_TIERS: Array = [
	{
		"tier": 1,
		"id": "retainers",
		"name": "Retainer Household",
		"weekly_wage": 1400.0,
		"min_prestige": 0.0,
		"min_rank": 0,
		"effects": {"prestige_per_year": 2.0, "opinion": 1, "health": 0.01, "skill": 0}
	},
	{
		"tier": 2,
		"id": "manor_staff",
		"name": "Manor Staff",
		"weekly_wage": 4200.0,
		"min_prestige": 10.0,
		"min_rank": 0,
		"effects": {"prestige_per_year": 5.0, "opinion": 2, "health": 0.02, "skill": 1}
	},
	{
		"tier": 3,
		"id": "steward_guard",
		"name": "Steward & Household Guard",
		"weekly_wage": 9800.0,
		"min_prestige": 20.0,
		"min_rank": 1,
		"effects": {"prestige_per_year": 10.0, "opinion": 4, "health": 0.03, "skill": 1}
	},
	{
		"tier": 4,
		"id": "noble_court",
		"name": "Noble Court",
		"weekly_wage": 18900.0,
		"min_prestige": 35.0,
		"min_rank": 1,
		"effects": {"prestige_per_year": 18.0, "opinion": 6, "health": 0.04, "skill": 2}
	},
	{
		"tier": 5,
		"id": "sovereign_court",
		"name": "Grand Sovereign Court",
		"weekly_wage": 28000.0,
		"min_prestige": 55.0,
		"min_rank": 2,
		"effects": {"prestige_per_year": 30.0, "opinion": 10, "health": 0.05, "skill": 3}
	}
]

const IMPROVEMENT_ORDER: Array = [
	"manor_hall",
	"great_kitchen",
	"stables",
	"library",
	"chapel",
	"gardens"
]

## Nominal maintenance schedules; actual work scales with local wages and income.
## At 100/day, all level 1/2/3 cost 14,100/28,500/57,000 per 120-day year
## before the IMPROVEMENT_SHARE cap. Unfunded work grants no bonuses.
const IMPROVEMENTS: Dictionary = {
	"manor_hall": {
		"key": "manor_hall",
		"name": "Manor Hall",
		"summary": "The great hall where petitions are heard and feasts are held.",
		"levels": [
			{
				"level": 1,
				"coin_cost": 15000.0,
				"materials": {"wood": 10, "stone": 8, "tools": 1},
				"weekly_upkeep": 700.0,
				"build_weeks": 2,
				"effects": {"prestige_per_year": 8.0, "opinion": 2, "health": 0.01, "skill": 0}
			},
			{
				"level": 2,
				"coin_cost": 35000.0,
				"materials": {"wood": 18, "stone": 16, "furniture": 2, "iron_bars": 2},
				"weekly_upkeep": 1400.0,
				"build_weeks": 3,
				"effects": {"prestige_per_year": 18.0, "opinion": 4, "health": 0.02, "skill": 1}
			},
			{
				"level": 3,
				"coin_cost": 75000.0,
				"materials": {"wood": 30, "stone": 28, "furniture": 4, "iron_bars": 4, "tools": 2},
				"weekly_upkeep": 2800.0,
				"build_weeks": 4,
				"effects": {"prestige_per_year": 35.0, "opinion": 8, "health": 0.03, "skill": 2}
			}
		]
	},
	"great_kitchen": {
		"key": "great_kitchen",
		"name": "Great Kitchen",
		"summary": "Bakehouses, cellars and hearths keeping the household well-fed and healthy.",
		"levels": [
			{
				"level": 1,
				"coin_cost": 12000.0,
				"materials": {"wood": 8, "stone": 6, "tools": 1},
				"weekly_upkeep": 560.0,
				"build_weeks": 2,
				"effects": {"prestige_per_year": 5.0, "opinion": 2, "health": 0.03, "skill": 0}
			},
			{
				"level": 2,
				"coin_cost": 28000.0,
				"materials": {"wood": 14, "stone": 12, "tools": 2, "iron_bars": 2},
				"weekly_upkeep": 1120.0,
				"build_weeks": 3,
				"effects": {"prestige_per_year": 12.0, "opinion": 4, "health": 0.06, "skill": 0}
			},
			{
				"level": 3,
				"coin_cost": 60000.0,
				"materials": {"wood": 22, "stone": 20, "tools": 3, "iron_bars": 4, "furniture": 2},
				"weekly_upkeep": 2240.0,
				"build_weeks": 4,
				"effects": {"prestige_per_year": 22.0, "opinion": 6, "health": 0.10, "skill": 1}
			}
		]
	},
	"stables": {
		"key": "stables",
		"name": "Household Stables",
		"summary": "Coursers, tack rooms and farriers for riders, envoys and household patrols.",
		"levels": [
			{
				"level": 1,
				"coin_cost": 14000.0,
				"materials": {"wood": 10, "stone": 4, "tools": 1},
				"weekly_upkeep": 630.0,
				"build_weeks": 2,
				"effects": {"prestige_per_year": 6.0, "opinion": 1, "health": 0.01, "skill": 1}
			},
			{
				"level": 2,
				"coin_cost": 32000.0,
				"materials": {"wood": 18, "stone": 10, "tools": 2, "iron_bars": 3},
				"weekly_upkeep": 1260.0,
				"build_weeks": 3,
				"effects": {"prestige_per_year": 14.0, "opinion": 2, "health": 0.02, "skill": 2}
			},
			{
				"level": 3,
				"coin_cost": 68000.0,
				"materials": {"wood": 28, "stone": 18, "tools": 4, "iron_bars": 6},
				"weekly_upkeep": 2520.0,
				"build_weeks": 4,
				"effects": {"prestige_per_year": 26.0, "opinion": 4, "health": 0.03, "skill": 3}
			}
		]
	},
	"library": {
		"key": "library",
		"name": "Manor Library",
		"summary": "Charters, ledgers and chronicles training stewards and heirs in statecraft.",
		"levels": [
			{
				"level": 1,
				"coin_cost": 13000.0,
				"materials": {"wood": 8, "stone": 4, "tools": 1},
				"weekly_upkeep": 490.0,
				"build_weeks": 2,
				"effects": {"prestige_per_year": 6.0, "opinion": 1, "health": 0.0, "skill": 2}
			},
			{
				"level": 2,
				"coin_cost": 30000.0,
				"materials": {"wood": 14, "stone": 8, "furniture": 2, "tools": 1},
				"weekly_upkeep": 980.0,
				"build_weeks": 3,
				"effects": {"prestige_per_year": 14.0, "opinion": 2, "health": 0.01, "skill": 4}
			},
			{
				"level": 3,
				"coin_cost": 64000.0,
				"materials": {"wood": 22, "stone": 14, "furniture": 4, "tools": 2},
				"weekly_upkeep": 1960.0,
				"build_weeks": 4,
				"effects": {"prestige_per_year": 28.0, "opinion": 4, "health": 0.02, "skill": 6}
			}
		]
	},
	"chapel": {
		"key": "chapel",
		"name": "House Chapel",
		"summary": "Shrine and almonry elevating the dynasty's standing among town and realm.",
		"levels": [
			{
				"level": 1,
				"coin_cost": 12500.0,
				"materials": {"wood": 6, "stone": 8, "tools": 1},
				"weekly_upkeep": 490.0,
				"build_weeks": 2,
				"effects": {"prestige_per_year": 7.0, "opinion": 3, "health": 0.01, "skill": 0}
			},
			{
				"level": 2,
				"coin_cost": 29000.0,
				"materials": {"wood": 12, "stone": 16, "furniture": 2},
				"weekly_upkeep": 1050.0,
				"build_weeks": 3,
				"effects": {"prestige_per_year": 16.0, "opinion": 6, "health": 0.02, "skill": 1}
			},
			{
				"level": 3,
				"coin_cost": 62000.0,
				"materials": {"wood": 20, "stone": 26, "furniture": 3, "iron_bars": 2},
				"weekly_upkeep": 2100.0,
				"build_weeks": 4,
				"effects": {"prestige_per_year": 30.0, "opinion": 10, "health": 0.03, "skill": 2}
			}
		]
	},
	"gardens": {
		"key": "gardens",
		"name": "Walled Gardens",
		"summary": "Herb courts, orchards and quiet walks restoring health and courtly grace.",
		"levels": [
			{
				"level": 1,
				"coin_cost": 10000.0,
				"materials": {"wood": 6, "stone": 6, "tools": 1},
				"weekly_upkeep": 420.0,
				"build_weeks": 1,
				"effects": {"prestige_per_year": 5.0, "opinion": 2, "health": 0.02, "skill": 0}
			},
			{
				"level": 2,
				"coin_cost": 24000.0,
				"materials": {"wood": 12, "stone": 12, "tools": 2},
				"weekly_upkeep": 840.0,
				"build_weeks": 2,
				"effects": {"prestige_per_year": 11.0, "opinion": 4, "health": 0.04, "skill": 0}
			},
			{
				"level": 3,
				"coin_cost": 52000.0,
				"materials": {"wood": 18, "stone": 20, "tools": 3, "furniture": 2},
				"weekly_upkeep": 1680.0,
				"build_weeks": 3,
				"effects": {"prestige_per_year": 20.0, "opinion": 7, "health": 0.07, "skill": 1}
			}
		]
	}
}


static func weeks_per_year() -> float:
	return float(EconGen.YEAR_DAYS) / 7.0


## Sample real cash less debt, adding back only this pass's discretionary payments.
## Keep signed losses, prorate the boundary week, and use a full 120-day denominator
## even during startup: neither starting cash nor one good week is annual income.
static func observe_income(f: Dictionary, day: float) -> void:
	if Population.is_cohort(f) or f.get("estate", false) or f.get("gone", false): return
	var balance: float = float(f.get("purse", 0.0)) - float(f.get("debt", 0.0))
	if not f.has("house_budget"):
		f["house_budget"] = {"day": day, "balance": balance, "spent": 0.0, "yearly": 0.0, "history": [], "capital": []}
		return
	var b: Dictionary = f["house_budget"]
	var prior: float = float(b["day"])
	if day <= prior: return
	var rows: Array = b["history"]
	rows.append([prior, day, balance - float(b["balance"]) + float(b["spent"])])
	var cutoff: float = day - float(EconGen.YEAR_DAYS)
	var keep: Array = []
	var income: float = 0.0
	for row: Array in rows:
		if float(row[1]) <= cutoff: continue
		keep.append(row)
		income += float(row[2]) * (float(row[1]) - maxf(cutoff, float(row[0]))) / maxf(1.0, float(row[1]) - float(row[0]))
	b["history"] = keep
	b["yearly"] = maxf(0.0, income)
	b["day"] = day; b["balance"] = balance; b["spent"] = 0.0
	var capital: Array = []
	for row: Array in b["capital"]:
		if float(row[0]) > cutoff: capital.append(row)
	b["capital"] = capital


static func recent_income(f: Dictionary) -> float:
	return maxf(0.0, float(f.get("house_budget", {}).get("yearly", 0.0)))


static func book_spending(f: Dictionary, amount: float) -> void:
	if f.has("house_budget"):
		f["house_budget"]["spent"] = float(f["house_budget"].get("spent", 0.0)) + amount


static func capital_room(f: Dictionary) -> float:
	var spent: float = 0.0
	for row: Array in f.get("house_budget", {}).get("capital", []): spent += float(row[1])
	return maxf(0.0, recent_income(f) * CAPITAL_SHARE - spent)


static func book_capital(f: Dictionary, amount: float, day: float) -> void:
	book_spending(f, amount)
	if f.has("house_budget"): f["house_budget"]["capital"].append([day, amount])


static func troop_room(f: Dictionary, day: float) -> float:
	var spent: float = 0.0
	for row: Array in f.get("house_budget", {}).get("troops", []):
		if float(row[0]) > day - 7.0: spent += float(row[1])
	return maxf(0.0, recent_income(f) * TROOP_SHARE / weeks_per_year() - spent)


static func book_troops(f: Dictionary, amount: float, day: float) -> void:
	book_spending(f, amount)
	if not f.has("house_budget"): return
	var keep: Array = []
	for row: Array in f["house_budget"].get("troops", []):
		if float(row[0]) > day - 7.0: keep.append(row)
	keep.append([day, amount])
	f["house_budget"]["troops"] = keep


static func spend_room(e: Dictionary, f: Dictionary) -> float:
	var food: float = EconomyRules.essential_food_cost(e, float(Families.daily_rates(e, f)["food"]) * 30.0)
	return maxf(0.0, float(f.get("purse", 0.0)) - food - Barge.day_wage(e) * 28.0 - maxf(0.0, float(f.get("debt", 0.0))))


static func service_scale(e: Dictionary) -> float:
	# Barge already uses real ldem/lsup, idle workers, shortages and prosperity;
	# Migration uses that same wage to attract workers. Do not apply scarcity twice.
	return SERVICE_SCALE * Barge.day_wage(e) / 100.0


static func staff_cost(e: Dictionary, f: Dictionary, tier: int) -> float:
	return minf(tier_cost(tier) * service_scale(e), recent_income(f) * STAFF_SHARE / weeks_per_year())


static func improvement_cost(e: Dictionary, f: Dictionary) -> float:
	return minf(_improvements_weekly_upkeep(f) * service_scale(e), recent_income(f) * IMPROVEMENT_SHARE / weeks_per_year())


static func catalog() -> Dictionary:
	return IMPROVEMENTS


static func improvement_keys() -> Array:
	return IMPROVEMENT_ORDER.duplicate()


static func staff_tiers() -> Array:
	return STAFF_TIERS.duplicate(true)


static func tier_spec(tier: int) -> Dictionary:
	var clamped: int = clampi(tier, MIN_TIER, MAX_TIER)
	return STAFF_TIERS[clamped - 1]


static func tier_cost(tier: int) -> float:
	return float(tier_spec(tier)["weekly_wage"])


static func _seat_rank(game, town: Dictionary) -> int:
	if town.is_empty():
		return 0
	var tid: String = str(town.get("id", ""))
	var f_tier: String = ""
	if game != null and game.world is Dictionary:
		f_tier = str(game.world.get("feudal", {}).get("towns", {}).get(tid, {}).get("tier", ""))
	var sz: int = int(town.get("size", 0))
	if f_tier == "sovereign" or sz >= 3:
		return 2
	if f_tier == "county" or sz >= 1:
		return 1
	return 0


static func _is_player_house(game, f: Dictionary) -> bool:
	if game == null or not (game.world is Dictionary):
		return false
	var p_uid: String = str(game.world.get("player_house", {}).get("household_uid", ""))
	var f_uid: String = str(f.get("household_uid", ""))
	return p_uid != "" and p_uid == f_uid


static func _is_ruling(game, town: Dictionary, e: Dictionary, f: Dictionary) -> bool:
	if f.is_empty() or Population.is_cohort(f) or bool(f.get("estate", false)) or bool(f.get("gone", false)):
		return false
	var uid: String = str(f.get("household_uid", ""))
	var head: Dictionary = e.get("head", {})
	var head_uid: String = str(head.get("household_uid", ""))
	if uid != "" and uid == head_uid:
		return true
	var head_fam: int = int(head.get("fam", -1))
	if head_fam >= 0 and int(f.get("id", -2)) == head_fam:
		return true
	var office_puid: String = str(head.get("person_uid", ""))
	if office_puid != "":
		for list_key in ["pp", "kp"]:
			var arr: Array = f.get(list_key, [])
			for p in arr:
				if p is Array and str(Persons.g(p, Persons.PERSON_UID, "")) == office_puid:
					return true
	if game != null and game.world is Dictionary and not town.is_empty():
		var tid: String = str(town.get("id", ""))
		if tid != "":
			var lord: Dictionary = Feudal.tax_recipient(game, tid)
			if uid != "" and str(lord.get("household_uid", "")) == uid:
				return true
	return false


static func _is_eligible_house(game, town: Dictionary, e: Dictionary, f: Dictionary) -> bool:
	if f.is_empty() or Population.is_cohort(f) or bool(f.get("estate", false)) or bool(f.get("gone", false)):
		return false
	if f.has("upkeep") or f.has("improvements"):
		return true
	if _is_player_house(game, f) or _is_ruling(game, town, e, f):
		return true
	return false


static func _max_tier_for_house(game, town: Dictionary, e: Dictionary, f: Dictionary) -> int:
	var rank: int = _seat_rank(game, town)
	var up: Dictionary = f.get("upkeep", {})
	var prestige: float = float(up.get("prestige", BASE_PRESTIGE))
	var imp_levels: int = total_improvement_levels(f)
	if rank >= 2 or prestige >= 55.0 or imp_levels >= 6:
		return MAX_TIER
	if rank >= 1 or _is_ruling(game, town, e, f) or prestige >= 30.0 or imp_levels >= 2:
		return 4
	return 3


## Ensures f["upkeep"] and f["improvements"] exist on the household dictionary and returns f["upkeep"].
static func ensure(game, town: Dictionary, e: Dictionary, f: Dictionary) -> Dictionary:
	if not f.has("improvements") or not (f["improvements"] is Dictionary):
		f["improvements"] = {}
	if not f.has("upkeep") or not (f["upkeep"] is Dictionary):
		var rank: int = _seat_rank(game, town)
		var start_prestige: float = BASE_PRESTIGE + float(rank) * 10.0
		var start_tier: int = MIN_TIER
		var purse: float = float(f.get("purse", 0.0))
		if _is_ruling(game, town, e, f) and purse >= SAFE_KEEP_WEEKS * tier_cost(2):
			start_tier = 2
		f["upkeep"] = {
			"tier": start_tier,
			"min_tier": MIN_TIER,
			"max_tier": MAX_TIER,
			"prestige": start_prestige,
			"opinion_bonus": 0,
			"health_bonus": 0.0,
			"skill_bonus": 0,
			"last_week_day": -7,
			"last_ai_buy_day": -AI_BUY_COOLDOWN_DAYS,
			"step_downs": 0,
			"ai_purchases": 0,
			"last_wage_paid": 0.0,
			"last_imp_upkeep_paid": 0.0,
			"total_wages_paid": 0.0,
			"total_imp_upkeep_paid": 0.0,
			"effects": {"prestige_per_year": 0.0, "opinion": 0, "health": 0.0, "skill": 0}
		}
	var up: Dictionary = f["upkeep"]
	up["tier"] = clampi(int(up.get("tier", MIN_TIER)), MIN_TIER, MAX_TIER)
	up["min_tier"] = MIN_TIER
	up["max_tier"] = _max_tier_for_house(game, town, e, f)
	if not up.has("prestige"):
		up["prestige"] = BASE_PRESTIGE
	_refresh_effects(f)
	return up


static func _imp_level(f: Dictionary, key: String) -> int:
	var imps: Dictionary = f.get("improvements", {})
	if not imps.has(key):
		return 0
	var entry = imps[key]
	if entry is Dictionary:
		return clampi(int((entry as Dictionary).get("level", 0)), 0, 3)
	return clampi(int(entry), 0, 3)


static func total_improvement_levels(f: Dictionary) -> int:
	var total: int = 0
	for k in IMPROVEMENT_ORDER:
		total += _imp_level(f, String(k))
	return total


static func _improvement_weekly_upkeep_for(key: String, level: int) -> float:
	if not IMPROVEMENTS.has(key) or level <= 0:
		return 0.0
	var levels: Array = IMPROVEMENTS[key]["levels"]
	var idx: int = clampi(level, 1, levels.size()) - 1
	var spec: Dictionary = levels[idx]
	return float(spec.get("weekly_upkeep", 0.0))


static func _improvements_weekly_upkeep(f: Dictionary) -> float:
	var sum: float = 0.0
	for k in IMPROVEMENT_ORDER:
		var key: String = String(k)
		var lvl: int = _imp_level(f, key)
		if lvl > 0:
			sum += _improvement_weekly_upkeep_for(key, lvl)
	return sum


static func _refresh_effects(f: Dictionary) -> Dictionary:
	var up: Dictionary = f.get("upkeep", {})
	var tier: int = clampi(int(up.get("tier", MIN_TIER)), MIN_TIER, MAX_TIER)
	var t_eff: Dictionary = tier_spec(tier)["effects"]
	var staff: float = float(up.get("staff_share", 0.0))
	var maintenance: float = float(up.get("maintenance_share", 0.0))
	var prestige_yr: float = float(t_eff.get("prestige_per_year", 0.0)) * staff
	var opinion: float = float(t_eff.get("opinion", 0)) * staff
	var health: float = float(t_eff.get("health", 0.0)) * staff
	var skill: float = float(t_eff.get("skill", 0)) * staff
	for k in IMPROVEMENT_ORDER:
		var key: String = String(k)
		var lvl: int = _imp_level(f, key)
		if lvl <= 0:
			continue
		var levels: Array = IMPROVEMENTS[key]["levels"]
		var lspec: Dictionary = levels[clampi(lvl, 1, levels.size()) - 1]
		var ieff: Dictionary = lspec["effects"]
		prestige_yr += float(ieff.get("prestige_per_year", 0.0)) * maintenance
		opinion += float(ieff.get("opinion", 0.0)) * maintenance
		health += float(ieff.get("health", 0.0)) * maintenance
		skill += float(ieff.get("skill", 0.0)) * maintenance
	var eff: Dictionary = {
		"prestige_per_year": snappedf(prestige_yr, 0.01),
		"opinion": int(floor(opinion)),
		"health": snappedf(health, 0.001),
		"skill": int(floor(skill))
	}
	if not up.is_empty():
		up["opinion_bonus"] = eff["opinion"]
		up["health_bonus"] = eff["health"]
		up["skill_bonus"] = eff["skill"]
		up["effects"] = eff
	return eff


## Credits `amount` to real recipient households in e["fams"] (common folk cohorts first, else working families).
## Never creates or destroys a single coin; the last recipient absorbs any floating-point remainder.
static func _pay_town_folk(e: Dictionary, payer: Dictionary, amount: float) -> Array:
	if amount <= 0.0:
		return []
	var fams: Array = e.get("fams", [])
	var recipients: Array = []
	var weights: Array = []
	var total_w: float = 0.0
	for cand in fams:
		if not (cand is Dictionary):
			continue
		var cf: Dictionary = cand
		if is_same(cf, payer) or bool(cf.get("gone", false)) or bool(cf.get("estate", false)):
			continue
		if Population.is_cohort(cf):
			var w: float = maxf(1.0, float(Population.households(cf)))
			recipients.append(cf)
			weights.append(w)
			total_w += w
	if recipients.is_empty():
		for cand in fams:
			if not (cand is Dictionary):
				continue
			var cf: Dictionary = cand
			if is_same(cf, payer) or bool(cf.get("gone", false)) or bool(cf.get("estate", false)):
				continue
			var w: float = maxf(1.0, float(Families.adults(cf)))
			recipients.append(cf)
			weights.append(w)
			total_w += w
	if recipients.is_empty():
		e["treasury"] = float(e.get("treasury", 0.0)) + amount
		return [{"kind": "treasury", "amount": amount}]
	var paid_so_far: float = 0.0
	var out: Array = []
	for i in recipients.size():
		var rf: Dictionary = recipients[i]
		var share: float = amount - paid_so_far if i == recipients.size() - 1 else minf(amount - paid_so_far, snappedf(amount * float(weights[i]) / maxf(1.0, total_w), 0.01))
		if share < 0.0:
			share = 0.0
		if i == recipients.size() - 1:
			share = amount - paid_so_far
		rf["purse"] = float(rf.get("purse", 0.0)) + share
		rf["staff_wage_received"] = float(rf.get("staff_wage_received", 0.0)) + share
		paid_so_far += share
		out.append({"family_id": int(rf.get("id", -1)), "amount": share})
	return out


static func _good_unit_price(e: Dictionary, good: String) -> float:
	var prices: Dictionary = e.get("price", {})
	var base: float = 10.0
	var goods_tbl: Dictionary = TownEcon.data().get("goods", {})
	if goods_tbl.has(good):
		base = float(goods_tbl[good].get("price", 10.0))
	var p: float = float(prices.get(good, base))
	return snappedf(p * TownEcon.markup(), 0.01)


static func _resolve_household(game, household_uid: String) -> Dictionary:
	if game == null or not (game.world is Dictionary):
		return {}
	var target_uid: String = household_uid
	if target_uid == "":
		target_uid = str(game.world.get("player_house", {}).get("household_uid", ""))
	if target_uid == "":
		return {}
	var hit: Dictionary = Dynasty._household(game, target_uid)
	if not hit.is_empty():
		return hit
	var towns: Dictionary = game.world.get("towns", {})
	for tid in towns.keys():
		var t: Dictionary = towns[tid]
		var e: Dictionary = t.get("econ", {})
		for cand in e.get("fams", []):
			if cand is Dictionary and str((cand as Dictionary).get("household_uid", "")) == target_uid and not bool((cand as Dictionary).get("gone", false)):
				return {"town": t, "family": cand}
	return {}


## Preview building or upgrading improvement `key` (levels 1..3) for `household_uid`.
static func improvement_preview(game, household_uid: String, key: String) -> Dictionary:
	if not IMPROVEMENTS.has(key):
		return {"ok": false, "reason": "Unknown house improvement '%s'." % key, "key": key, "household_uid": household_uid}
	var hit: Dictionary = _resolve_household(game, household_uid)
	if hit.is_empty():
		return {"ok": false, "reason": "Household '%s' was not found." % household_uid, "key": key, "household_uid": household_uid}
	var town: Dictionary = hit["town"]
	var e: Dictionary = town.get("econ", {})
	var f: Dictionary = hit["family"]
	ensure(game, town, e, f)
	var cur_level: int = _imp_level(f, key)
	var spec: Dictionary = IMPROVEMENTS[key]
	var levels: Array = spec["levels"]
	var max_lvl: int = levels.size()
	if cur_level >= max_lvl:
		return {
			"ok": false,
			"can_afford": false,
			"stock_ok": true,
			"reason": "%s is already at maximum level (%d)." % [str(spec["name"]), max_lvl],
			"household_uid": str(f.get("household_uid", household_uid)),
			"town_id": str(town.get("id", "")),
			"key": key,
			"name": str(spec["name"]),
			"current_level": cur_level,
			"level": cur_level,
			"next_level": 0,
			"max_level": max_lvl,
			"coin_cost": 0.0,
			"material_cost": 0.0,
			"total_cost": 0.0,
			"cost": 0.0,
			"materials": {},
			"stock": {},
			"shortfalls": {},
			"weekly_upkeep": _improvement_weekly_upkeep_for(key, cur_level) * service_scale(e),
			"yearly_upkeep": _improvement_weekly_upkeep_for(key, cur_level) * service_scale(e) * weeks_per_year(),
			"build_weeks": 0,
			"effects": (levels[max_lvl - 1] as Dictionary)["effects"].duplicate(true),
			"review": {}
		}
	var next_lvl: int = cur_level + 1
	var lspec: Dictionary = levels[next_lvl - 1]
	var coin_cost: float = float(lspec["coin_cost"]) * service_scale(e)
	var mats_req: Dictionary = lspec["materials"]
	var st: Dictionary = e.get("stock", {})
	var mats_out: Dictionary = {}
	var stock_out: Dictionary = {}
	var shortfalls: Dictionary = {}
	var mat_cost: float = 0.0
	var any_stocked: bool = false
	for g in mats_req.keys():
		var good: String = String(g)
		var need: int = int(mats_req[good])
		var have: int = maxi(0, int(st.get(good, 0)))
		mats_out[good] = need
		stock_out[good] = have
		if have > 0:
			any_stocked = true
		if have < need:
			shortfalls[good] = need - have
		mat_cost += float(need) * _good_unit_price(e, good)
	mat_cost = snappedf(mat_cost, 0.01)
	var total_cost: float = snappedf(coin_cost + mat_cost, 0.01)
	var purse: float = float(f.get("purse", 0.0))
	var can_afford: bool = purse >= total_cost
	var stock_ok: bool = shortfalls.is_empty() or any_stocked
	var weekly_up: float = float(lspec["weekly_upkeep"]) * service_scale(e)
	var reason: String = "Ready to build %s (Level %d)." % [str(spec["name"]), next_lvl]
	if not can_afford:
		reason = "Insufficient household purse (need %.2f coins, have %.2f)." % [total_cost, purse]
	elif not stock_ok:
		reason = "Market has no construction materials in stock."
	var uid_str: String = str(f.get("household_uid", household_uid))
	var review_tok: Dictionary = {
		"household_uid": uid_str,
		"town_id": str(town.get("id", "")),
		"key": key,
		"level": next_lvl,
		"coin_cost": coin_cost,
		"material_cost": mat_cost,
		"total_cost": total_cost
	}
	return {
		"ok": can_afford and stock_ok,
		"can_afford": can_afford,
		"stock_ok": stock_ok,
		"reason": reason,
		"household_uid": uid_str,
		"town_id": str(town.get("id", "")),
		"key": key,
		"name": str(spec["name"]),
		"summary": str(spec.get("summary", "")),
		"current_level": cur_level,
		"level": next_lvl,
		"next_level": next_lvl,
		"max_level": max_lvl,
		"coin_cost": coin_cost,
		"material_cost": mat_cost,
		"total_cost": total_cost,
		"cost": total_cost,
		"purse": purse,
		"purse_after": purse - total_cost,
		"materials": mats_out,
		"stock": stock_out,
		"shortfalls": shortfalls,
		"weekly_upkeep": weekly_up,
		"yearly_upkeep": snappedf(weekly_up * weeks_per_year(), 0.01),
		"build_weeks": int(lspec.get("build_weeks", 2)),
		"effects": (lspec["effects"] as Dictionary).duplicate(true),
		"review": review_tok
	}


## Starts or upgrades improvement `key` for `household_uid`.
## Deducts `coin_cost` from f["purse"] (paid to town folk in e["fams"]) and `material_cost` via
## TownEcon.pay_market(e, f, material_cost), deducting materials from e["stock"] with TownEcon.led
## and Barge.add_demand so total town/world coin is strictly conserved.
static func start_improvement(game, household_uid: String, key: String, review: Dictionary = {}) -> Dictionary:
	var prev: Dictionary = improvement_preview(game, household_uid, key)
	if not bool(prev.get("ok", false)):
		return prev
	if not review.is_empty():
		if review.has("key") and str(review.get("key", "")) != key:
			return {"ok": false, "reason": "Improvement review key mismatch."}
		if review.has("level") and int(review.get("level", 0)) != int(prev["next_level"]):
			return {"ok": false, "reason": "Improvement level changed since review."}
	var hit: Dictionary = _resolve_household(game, household_uid)
	var town: Dictionary = hit["town"]
	var e: Dictionary = town["econ"]
	var f: Dictionary = hit["family"]
	var coin_cost: float = float(prev["coin_cost"])
	var mat_cost: float = float(prev["material_cost"])
	var total_cost: float = float(prev["total_cost"])
	if float(f.get("purse", 0.0)) < total_cost:
		return {"ok": false, "reason": "Insufficient household purse."}
	# 1. Buy materials from the town market stock and pay the market till
	var st: Dictionary = e["stock"]
	var mats: Dictionary = prev["materials"]
	var bought_mats: Dictionary = {}
	for g in mats.keys():
		var good: String = String(g)
		var need: int = int(mats[good])
		var have: int = maxi(0, int(st.get(good, 0)))
		var taken: int = mini(need, have)
		st[good] = have - taken
		if taken > 0:
			TownEcon.led(e, "used", good, taken)
		Barge.add_demand(e, good, float(taken), float(need - taken), 0.0)
		bought_mats[good] = taken
	if mat_cost > 0.0:
		TownEcon.pay_market(e, f, mat_cost)
	# 2. Pay builder/craftsmen labor coin cost to town common folk cohorts / families
	var labor_recipients: Array = []
	if coin_cost > 0.0:
		f["purse"] = float(f["purse"]) - coin_cost
		labor_recipients = _pay_town_folk(e, f, coin_cost)
	book_capital(f, total_cost, float(game.day))
	# 3. Record the improvement on f["improvements"] and refresh f["upkeep"] effects
	var next_lvl: int = int(prev["next_level"])
	var build_weeks: int = int(prev["build_weeks"])
	var day_now: int = int(game.day) if game != null else int(e.get("day", 0))
	var eff_copy: Dictionary = (prev["effects"] as Dictionary).duplicate(true)
	eff_copy["opinion"] = int(eff_copy.get("opinion", 0))
	eff_copy["skill"] = int(eff_copy.get("skill", 0))
	eff_copy["prestige_per_year"] = float(eff_copy.get("prestige_per_year", 0.0))
	eff_copy["health"] = float(eff_copy.get("health", 0.0))
	var imp_record: Dictionary = {
		"key": key,
		"name": str(prev["name"]),
		"level": next_lvl,
		"building_to": next_lvl,
		"weeks_left": build_weeks,
		"built_day": day_now,
		"coin_paid": coin_cost,
		"material_cost": mat_cost,
		"total_cost": total_cost,
		"materials_used": bought_mats,
		"weekly_upkeep": float(prev["weekly_upkeep"]),
		"effects": eff_copy
	}
	f["improvements"][key] = imp_record
	var active_effects: Dictionary = _refresh_effects(f)
	if bool(f.get("named", false)):
		Families.add_hist(f, "Built %s (Level %d) for %d coins." % [str(prev["name"]), next_lvl, int(round(total_cost))], float(day_now))
	return {
		"ok": true,
		"reason": "Built %s (Level %d)." % [str(prev["name"]), next_lvl],
		"household_uid": str(f.get("household_uid", household_uid)),
		"town_id": str(town.get("id", "")),
		"key": key,
		"name": str(prev["name"]),
		"level": next_lvl,
		"coin_cost": coin_cost,
		"material_cost": mat_cost,
		"total_cost": total_cost,
		"materials_used": bought_mats,
		"labor_recipients": labor_recipients,
		"purse_after": float(f["purse"]),
		"improvement": imp_record,
		"effects": active_effects
	}


## Raises or lowers staff tier for `household_uid` (clamped to MIN_TIER..MAX_TIER).
static func set_staff_tier(game, household_uid: String, target_tier: int) -> Dictionary:
	var hit: Dictionary = _resolve_household(game, household_uid)
	if hit.is_empty():
		return {"ok": false, "reason": "Household not found."}
	var town: Dictionary = hit["town"]
	var e: Dictionary = town["econ"]
	var f: Dictionary = hit["family"]
	var up: Dictionary = ensure(game, town, e, f)
	var max_t: int = _max_tier_for_house(game, town, e, f)
	var clamped: int = clampi(target_tier, MIN_TIER, max_t)
	var old_tier: int = int(up.get("tier", MIN_TIER))
	if clamped > old_tier and tier_cost(clamped) * service_scale(e) > recent_income(f) * STAFF_SHARE / weeks_per_year():
		return {"ok": false, "reason": "Insufficient household purse to support %s." % str(tier_spec(clamped)["name"])}
	up["tier"] = clamped
	var eff: Dictionary = _refresh_effects(f)
	return {
		"ok": true,
		"old_tier": old_tier,
		"tier": clamped,
		"tier_name": str(tier_spec(clamped)["name"]),
		"weekly_wage": staff_cost(e, f, clamped),
		"effects": eff
	}


## Weekly household upkeep pass:
##   1) Progresses any in-flight improvement construction (weeks_left) and applies active effects
##      (yearly prestige gain, opinion/health/skill bonuses).
##   2) Charges weekly staff wages (stepping down staff tier with a small prestige loss if f["purse"]
##      cannot cover the current tier's wage, never dropping below MIN_TIER and never going negative)
##      plus ongoing improvement upkeep; every coin is credited to real town folk in e["fams"].
##   3) For AI ruling houses, considers at most one purchase per 30 days (either an improvement or
##      raising staff tier) strictly out of surplus above SAFE_KEEP_WEEKS (8) weeks of upkeep, never into debt.
static func weekly(game, town: Dictionary, e: Dictionary, f: Dictionary) -> Dictionary:
	if not _is_eligible_house(game, town, e, f):
		return {"ok": false, "skipped": true}
	var up: Dictionary = ensure(game, town, e, f)
	var day_now: int = int(game.day) if game != null else int(e.get("day", 0))
	up["last_week_day"] = day_now
	# 1. Progress improvement build timers
	var imps: Dictionary = f["improvements"]
	for k in imps.keys():
		var entry = imps[k]
		if entry is Dictionary:
			var imp: Dictionary = entry
			var left: int = int(imp.get("weeks_left", 0))
			if left > 0:
				left -= 1
				imp["weeks_left"] = left
				if left <= 0:
					imp["building_to"] = 0
	# 2. Staff wages with automatic step-down when poor (never below MIN_TIER, purse never < 0)
	var tier_before: int = clampi(int(up.get("tier", MIN_TIER)), MIN_TIER, MAX_TIER)
	var tier_now: int = tier_before
	var staff_budget: float = recent_income(f) * STAFF_SHARE / weeks_per_year()
	var room: float = spend_room(e, f)
	while tier_now > MIN_TIER and tier_cost(tier_now) * service_scale(e) > minf(staff_budget, room):
		tier_now -= 1
	up["tier"] = tier_now
	var purse_now: float = maxf(0.0, float(f.get("purse", 0.0)))
	var stepped_down: bool = tier_now < tier_before
	var wage_due: float = staff_cost(e, f, tier_now)
	var wage_short: bool = room < wage_due
	if stepped_down or wage_short:
		up["step_downs"] = int(up.get("step_downs", 0)) + tier_before - tier_now
		up["prestige"] = maxf(0.0, snappedf(float(up.get("prestige", BASE_PRESTIGE)) - PRESTIGE_STEP_DOWN_LOSS, 0.01))
	var wage_paid: float = minf(spend_room(e, f), wage_due)
	book_spending(f, wage_paid)
	up["staff_share"] = wage_paid / maxf(0.01, tier_cost(tier_now) * service_scale(e))
	if wage_paid > 0.0:
		f["purse"] = purse_now - wage_paid
		_pay_town_folk(e, f, wage_paid)
	else:
		f["purse"] = purse_now
	up["last_wage_paid"] = wage_paid
	up["total_wages_paid"] = float(up.get("total_wages_paid", 0.0)) + wage_paid
	# 3. Ongoing weekly improvement upkeep (also paid to town folk, capped by remaining purse so purse >= 0)
	var imp_due: float = improvement_cost(e, f)
	var purse_after_wage: float = maxf(0.0, float(f.get("purse", 0.0)))
	var imp_paid: float = minf(spend_room(e, f), imp_due)
	book_spending(f, imp_paid)
	up["maintenance_share"] = imp_paid / maxf(0.01, _improvements_weekly_upkeep(f) * service_scale(e))
	if imp_paid > 0.0:
		f["purse"] = purse_after_wage - imp_paid
		_pay_town_folk(e, f, imp_paid)
	up["last_imp_upkeep_paid"] = imp_paid
	up["total_imp_upkeep_paid"] = float(up.get("total_imp_upkeep_paid", 0.0)) + imp_paid
	# 4. Refresh and apply active house effects (prestige, opinion, health, skill)
	var eff: Dictionary = _refresh_effects(f)
	if not wage_short:
		var weekly_prestige: float = float(eff.get("prestige_per_year", 0.0)) / weeks_per_year()
		up["prestige"] = snappedf(float(up.get("prestige", BASE_PRESTIGE)) + weekly_prestige, 0.01)
	if f.has("body"):
		f["body"] = minf(1.0, float(f.get("body", 1.0)) + float(eff.get("health", 0.0)) * 0.25)
	up["max_tier"] = _max_tier_for_house(game, town, e, f)
	# 5. AI ruling house spending from surplus above SAFE_KEEP_WEEKS (at most once per 30 days, never into debt)
	var ai_action: Dictionary = _maybe_ai_purchase(game, town, e, f, up, day_now)
	return {
		"ok": true,
		"tier_before": tier_before,
		"tier": int(up["tier"]),
		"stepped_down": stepped_down,
		"wage_due": wage_due,
		"wage_paid": wage_paid,
		"imp_upkeep_due": imp_due,
		"imp_upkeep_paid": imp_paid,
		"total_paid": wage_paid + imp_paid,
		"prestige": float(up["prestige"]),
		"purse": float(f["purse"]),
		"effects": eff,
		"ai_action": ai_action
	}


static func _maybe_ai_purchase(game, town: Dictionary, e: Dictionary, f: Dictionary, up: Dictionary, day_now: int) -> Dictionary:
	if _is_player_house(game, f) or not _is_ruling(game, town, e, f):
		return {"acted": false, "reason": "not_ai_ruler"}
	if float(f.get("debt", 0.0)) > 0.0:
		return {"acted": false, "reason": "in_debt"}
	var last_buy: int = int(up.get("last_ai_buy_day", -AI_BUY_COOLDOWN_DAYS))
	if day_now - last_buy < AI_BUY_COOLDOWN_DAYS:
		return {"acted": false, "reason": "cooldown"}
	var cur_tier: int = int(up.get("tier", MIN_TIER))
	var max_tier: int = _max_tier_for_house(game, town, e, f)
	var cur_imp_upkeep: float = _improvements_weekly_upkeep(f)
	var cur_weekly: float = staff_cost(e, f, cur_tier) + improvement_cost(e, f)
	var purse: float = float(f.get("purse", 0.0))
	if purse <= SAFE_KEEP_WEEKS * cur_weekly:
		return {"acted": false, "reason": "below_safe_keep"}
	var uid: String = str(f.get("household_uid", ""))
	var imp_levels: int = total_improvement_levels(f)
	var try_tier_first: bool = cur_tier < max_tier and imp_levels >= cur_tier
	if try_tier_first:
		var tier_res: Dictionary = _ai_try_raise_tier(e, f, up, cur_tier, max_tier, cur_imp_upkeep, day_now)
		if bool(tier_res.get("acted", false)):
			return tier_res
	var imp_res: Dictionary = _ai_try_buy_improvement(game, uid, f, up, cur_tier, cur_imp_upkeep, day_now)
	if bool(imp_res.get("acted", false)):
		return imp_res
	if not try_tier_first and cur_tier < max_tier:
		var tier_res2: Dictionary = _ai_try_raise_tier(e, f, up, cur_tier, max_tier, cur_imp_upkeep, day_now)
		if bool(tier_res2.get("acted", false)):
			return tier_res2
	return {"acted": false, "reason": "insufficient_surplus"}


static func _ai_try_buy_improvement(game, uid: String, f: Dictionary, up: Dictionary, cur_tier: int, cur_imp_upkeep: float, day_now: int) -> Dictionary:
	var purse: float = float(f.get("purse", 0.0))
	var best_key: String = ""
	var best_prev: Dictionary = {}
	var best_score: float = INF
	for k in IMPROVEMENT_ORDER:
		var key: String = String(k)
		var prev: Dictionary = improvement_preview(game, uid, key)
		if not bool(prev.get("ok", false)):
			continue
		var cost: float = float(prev["total_cost"])
		if cost > capital_room(f): continue
		var old_key_up: float = _improvement_weekly_upkeep_for(key, int(prev["current_level"]))
		var home: Dictionary = _resolve_household(game, uid)
		var econ: Dictionary = home["town"]["econ"]
		var new_imp: float = (cur_imp_upkeep - old_key_up) * service_scale(econ) + float(prev["weekly_upkeep"])
		if new_imp > recent_income(f) * IMPROVEMENT_SHARE / weeks_per_year(): continue
		var new_weekly: float = staff_cost(econ, f, cur_tier) + new_imp
		var keep_needed: float = SAFE_KEEP_WEEKS * new_weekly
		if purse - cost < keep_needed:
			continue
		var score: float = float(prev["next_level"]) * 100000.0 + cost
		if score < best_score:
			best_score = score
			best_key = key
			best_prev = prev
	if best_key == "":
		return {"acted": false}
	var built: Dictionary = start_improvement(game, uid, best_key, best_prev.get("review", {}))
	if not bool(built.get("ok", false)):
		return {"acted": false}
	up["last_ai_buy_day"] = day_now
	up["ai_purchases"] = int(up.get("ai_purchases", 0)) + 1
	up["last_ai_action"] = "improvement:%s:%d" % [best_key, int(built["level"])]
	return {
		"acted": true,
		"kind": "improvement",
		"key": best_key,
		"level": int(built["level"]),
		"cost": float(built["total_cost"]),
		"purse_after": float(f["purse"])
	}


static func _ai_try_raise_tier(e: Dictionary, f: Dictionary, up: Dictionary, cur_tier: int, max_tier: int, cur_imp_upkeep: float, day_now: int) -> Dictionary:
	if cur_tier >= max_tier:
		return {"acted": false}
	var next_tier: int = cur_tier + 1
	var new_weekly: float = (tier_cost(next_tier) + cur_imp_upkeep) * service_scale(e)
	if tier_cost(next_tier) * service_scale(e) > recent_income(f) * STAFF_SHARE / weeks_per_year(): return {"acted": false}
	var signing_fee: float = maxf(0.0, tier_cost(next_tier) - tier_cost(cur_tier)) * service_scale(e)
	if signing_fee > capital_room(f): return {"acted": false}
	var keep_needed: float = SAFE_KEEP_WEEKS * new_weekly
	var purse: float = float(f.get("purse", 0.0))
	if purse - signing_fee < keep_needed:
		return {"acted": false}
	if signing_fee > 0.0:
		f["purse"] = purse - signing_fee
		_pay_town_folk(e, f, signing_fee)
		book_capital(f, signing_fee, float(day_now))
	up["tier"] = next_tier
	up["last_ai_buy_day"] = day_now
	up["ai_purchases"] = int(up.get("ai_purchases", 0)) + 1
	up["last_ai_action"] = "tier:%d" % next_tier
	_refresh_effects(f)
	if bool(f.get("named", false)):
		Families.add_hist(f, "Expanded household staff to %s (Tier %d)." % [str(tier_spec(next_tier)["name"]), next_tier], float(day_now))
	return {
		"acted": true,
		"kind": "tier",
		"tier": next_tier,
		"cost": signing_fee,
		"purse_after": float(f["purse"])
	}


## Sizing helper: returns current and expected yearly upkeep for `household_uid`, plus reference
## benchmarks at 100/day; actual charges also obey each house's income caps.
static func expected_yearly_cost(game, household_uid: String = "") -> Dictionary:
	var yr_weeks: float = weeks_per_year()
	var hit: Dictionary = _resolve_household(game, household_uid)
	var cur_tier: int = 2
	var cur_weekly_wage: float = 0.0
	var cur_weekly_imp: float = 0.0
	var tid: String = ""
	var rank: int = 1
	var income: float = 0.0
	var wage_scale: float = SERVICE_SCALE
	if not hit.is_empty():
		var town: Dictionary = hit["town"]
		var e: Dictionary = town.get("econ", {})
		var f: Dictionary = hit["family"]
		var up: Dictionary = ensure(game, town, e, f)
		tid = str(town.get("id", ""))
		rank = _seat_rank(game, town)
		income = recent_income(f)
		wage_scale = service_scale(e)
		cur_tier = int(up.get("tier", MIN_TIER))
		cur_weekly_wage = staff_cost(e, f, cur_tier)
		cur_weekly_imp = improvement_cost(e, f)
	var cur_weekly_total: float = cur_weekly_wage + cur_weekly_imp
	var cur_yearly_wages: float = snappedf(cur_weekly_wage * yr_weeks, 0.01)
	var cur_yearly_imp: float = snappedf(cur_weekly_imp * yr_weeks, 0.01)
	var cur_yearly_total: float = snappedf(cur_weekly_total * yr_weeks, 0.01)
	# Targets are constrained by this house's observed disposable income.
	var target_tier: int = 5 if rank >= 2 else 4
	var target_yearly_wages: float = minf(tier_cost(target_tier) * wage_scale * yr_weeks, income * STAFF_SHARE)
	var target_yearly_imp: float = minf((228000.0 if target_tier >= 5 else 114000.0) * wage_scale, income * IMPROVEMENT_SHARE)
	var target_yearly_build: float = income * CAPITAL_SHARE
	var target_yearly_total: float = target_yearly_wages + target_yearly_imp
	return {
		"ok": not hit.is_empty(),
		"household_uid": household_uid,
		"town_id": tid,
		"tier": cur_tier,
		"weekly_wages": cur_weekly_wage,
		"weekly_improvements": cur_weekly_imp,
		"weekly_upkeep": cur_weekly_total,
		"yearly_wages": cur_yearly_wages,
		"yearly_improvements": cur_yearly_imp,
		"yearly_upkeep": cur_yearly_total,
		"total": cur_yearly_total,
		"expected_yearly_cost": cur_yearly_total,
		"disposable_income_year": income,
		"target_tier": target_tier,
		"target_yearly_wages": target_yearly_wages,
		"target_yearly_improvements": target_yearly_imp,
		"target_yearly_upkeep": target_yearly_total,
		"target_yearly_with_builds": target_yearly_total + target_yearly_build,
		"ruling_1m_yearly_upkeep": 109500.0,
		"ruling_1m_max_yearly_upkeep": 177000.0,
		"ruling_1m_with_upgrades": 209500.0
	}


static func summary(game, household_uid: String = "") -> Dictionary:
	var hit: Dictionary = _resolve_household(game, household_uid)
	if hit.is_empty():
		return {"ok": false, "reason": "Household not found."}
	var town: Dictionary = hit["town"]
	var e: Dictionary = town.get("econ", {})
	var f: Dictionary = hit["family"]
	var up: Dictionary = ensure(game, town, e, f)
	var uid: String = str(f.get("household_uid", household_uid))
	var cur_tier: int = int(up["tier"])
	var tspec: Dictionary = tier_spec(cur_tier)
	var rows: Array = []
	for k in IMPROVEMENT_ORDER:
		var key: String = String(k)
		rows.append(improvement_preview(game, uid, key))
	var sizing: Dictionary = expected_yearly_cost(game, uid)
	return {
		"ok": true,
		"household_uid": uid,
		"town_id": str(town.get("id", "")),
		"tier": cur_tier,
		"min_tier": MIN_TIER,
		"max_tier": int(up.get("max_tier", MAX_TIER)),
		"tier_name": str(tspec["name"]),
		"weekly_wage": staff_cost(e, f, cur_tier),
		"weekly_improvements": improvement_cost(e, f),
		"weekly_upkeep": staff_cost(e, f, cur_tier) + improvement_cost(e, f),
		"yearly_upkeep": float(sizing["yearly_upkeep"]),
		"prestige": float(up.get("prestige", BASE_PRESTIGE)),
		"effects": (up.get("effects", {}) as Dictionary).duplicate(true),
		"improvements": (f.get("improvements", {}) as Dictionary).duplicate(true),
		"improvement_previews": rows,
		"sizing": sizing
	}


## Casts integer and float fields in f["upkeep"] and f["improvements"] across all towns after JSON load.
static func after_load(game) -> void:
	if game == null or not (game.world is Dictionary):
		return
	var towns: Dictionary = game.world.get("towns", {})
	for tid in towns.keys():
		var t: Dictionary = towns[tid]
		var e: Dictionary = t.get("econ", {})
		if e.is_empty():
			continue
		for cand in e.get("fams", []):
			if not (cand is Dictionary):
				continue
			var f: Dictionary = cand
			if f.has("upkeep") and f["upkeep"] is Dictionary:
				var up: Dictionary = f["upkeep"]
				for ik in ["tier", "min_tier", "max_tier", "last_week_day", "last_ai_buy_day", "step_downs", "ai_purchases", "opinion_bonus", "skill_bonus"]:
					if up.has(ik):
						up[ik] = int(up[ik])
				for fk in ["prestige", "health_bonus", "last_wage_paid", "last_imp_upkeep_paid", "total_wages_paid", "total_imp_upkeep_paid"]:
					if up.has(fk):
						up[fk] = float(up[fk])
				if up.has("effects") and up["effects"] is Dictionary:
					var eff: Dictionary = up["effects"]
					eff["opinion"] = int(eff.get("opinion", 0))
					eff["skill"] = int(eff.get("skill", 0))
					eff["prestige_per_year"] = float(eff.get("prestige_per_year", 0.0))
					eff["health"] = float(eff.get("health", 0.0))
			if f.has("improvements") and f["improvements"] is Dictionary:
				var imps: Dictionary = f["improvements"]
				for k in imps.keys():
					var entry = imps[k]
					if entry is Dictionary:
						var imp: Dictionary = entry
						for ik2 in ["level", "building_to", "weeks_left", "built_day"]:
							if imp.has(ik2):
								imp[ik2] = int(imp[ik2])
						for fk2 in ["coin_paid", "material_cost", "total_cost", "weekly_upkeep"]:
							if imp.has(fk2):
								imp[fk2] = float(imp[fk2])
						if imp.has("materials_used") and imp["materials_used"] is Dictionary:
							var mu: Dictionary = imp["materials_used"]
							for mg in mu.keys():
								mu[mg] = int(mu[mg])
						if imp.has("effects") and imp["effects"] is Dictionary:
							var ieff: Dictionary = imp["effects"]
							ieff["opinion"] = int(ieff.get("opinion", 0))
							ieff["skill"] = int(ieff.get("skill", 0))
							ieff["prestige_per_year"] = float(ieff.get("prestige_per_year", 0.0))
							ieff["health"] = float(ieff.get("health", 0.0))
					else:
						imps[k] = int(entry)
			if f.has("upkeep") or f.has("improvements"):
				_refresh_effects(f)
