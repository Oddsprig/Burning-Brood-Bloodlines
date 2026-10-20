class_name BargeViews
extends RefCounted
## Read-only UI/text/report/ledger view queries split from Barge (game/campaign/barge.gd)
## to keep each file focused and under the size threshold.
## Structure only; all Barge.* entry points delegate here with identical behavior.

const FED := Barge.FED
const STAGES := Barge.STAGES

# ================================================================== staple & diet views
## Staple index of the town: the staple's price over base x PL.
static func staple_index(e: Dictionary) -> float:
	return float(e["price"].get("grain", 3.6)) / (float(TownEcon.data()["goods"]["grain"]["price"]) * Barge.pl(e))

## The town's diet at base prices, meals a person a day by food: the staples by the race's taste filling what meat and
## produce (the rest wants, a class mix of 70% poor, 25% middling, 5% rich [ours]) leave of the 2 meals. World gen sizes
## the fields and herds from it; the opening demand reads it.
static func diet(e: Dictionary) -> Dictionary:
	var H: Dictionary = Barge.B()["household"]
	var mix := [0.7, 0.25, 0.05]
	var out := {"grain": 0.0, "fruit": 0.0, "meat": 0.0}
	var rest := 0.0
	for g in ["meat", "fruit"]:
		var q := 0.0
		for c in 3:
			q += float(mix[c]) * float(H["rest_q"][g][c])
		out[g] = q
		rest += q
	var sh := Barge.staple_shares(e, true)
	var food := float(TownEcon.data()["needs"]["food"])
	for g in sh:
		out[g] = float(out.get(g, 0.0)) + float(sh[g]) * maxf(0.0, food - rest)
	return out

# ================================================================== coin & mint ledger views
## Every coin held anywhere: towns (treasuries, tills, purses, unclaimed barn sales), realm treasuries and loot chests,
## bandit hoards, caravans and every force's purse, the company.
static func holdings(game) -> float:
	var w: Dictionary = game.world
	var g := 0.0
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t):
			g += TownEcon.town_gold(t["econ"])
	for fid in w.get("factions", {}):
		g += float(w["factions"][fid].get("treasury", 0.0)) + float(w["factions"][fid].get("loot", 0.0))
	for lid in w.get("lairs", {}):
		g += float(w["lairs"][lid].get("gold", 0.0))
	for wid in w.get("warbands", {}):
		g += float(w["warbands"][wid].get("gold", 0.0))
	g += float(game.gold)
	return g

static func faction_coin(w: Dictionary, fid: String, fresh: bool = true) -> float:
	var c := float(w["factions"].get(fid, {}).get("treasury", 0.0))
	for tid in w["factions"].get(fid, {}).get("towns", []):
		var t: Dictionary = w["towns"].get(tid, {})
		if TownEcon.has_econ(t):
			c += TownEcon.town_gold(t["econ"]) if fresh or not t["econ"].has("coin_now") else float(t["econ"]["coin_now"])
	return c

## Metal in 1,000 coins at today's town prices (copper 4.6 + tin 0.4 bars + 0.45 wood for charcoal), less debasement.
static func metal_per_k(e: Dictionary) -> float:
	var R: Dictionary = Barge.B()["coin"]["mint_recipe"]
	var v := 0.0
	for g in R:
		v += float(R[g]) * float(e["price"].get(g, 1.0))
	return v * (1.0 - float(e.get("debase", 0.0)))

## The mint's recipes for 1,000 coins (data barge.coin): copper and tin bars (mint_recipe) or bronze bars
## (mint_recipe_bronze: the same metal as one alloy, what melting gives back), with the charcoal; the cheaper first.
static func _mint_recipes(e: Dictionary) -> Array:
	var C: Dictionary = Barge.B()["coin"]
	var out: Array = [C["mint_recipe"]]
	if C.has("mint_recipe_bronze"):
		out.append(C["mint_recipe_bronze"])
		if _recipe_cost(e, out[1]) < _recipe_cost(e, out[0]):
			out.reverse()
	return out

## A recipe's metal at today's town prices, less debasement (coins per 1,000 cast).
static func _recipe_cost(e: Dictionary, R: Dictionary) -> float:
	var v := 0.0
	for g in R:
		v += float(R[g]) * float(e["price"].get(g, 1.0))
	return v * (1.0 - float(e.get("debase", 0.0)))

## Bars for a thousand coins by one of the mint's recipes in the town's market (the weekly staffing).
static func mint_bars(e: Dictionary) -> bool:
	for R in _mint_recipes(e):
		var ok := true
		for g in R:
			if float(e["stock"].get(g, 0)) < float(R[g]):
				ok = false
		if ok:
			return true
	return false

# ================================================================== treasury, tax quote & rent views
## Treasury lines for the town: barge Yellow Springs start 420,000, short under 250,000, full over 800,000, scaled by
## the town's people / 8,000 [ours].
static func treasury_lines(e: Dictionary) -> Dictionary:
	var T: Dictionary = Barge.B()["treasury"]
	var k := maxf(1.0, float(e.get("pop0", e.get("pop", 1)))) / float(T["per"])
	return {"start": float(T["start"]) * k, "short": float(T["short"]) * k, "full": float(T["full"]) * k}

## One year of ordinary public payroll plus due kit and wage claims. Surplus-funded
## works are discretionary, so exclude them from the target to avoid a ratchet.
static func treasury_target(game, town: Dictionary, e: Dictionary) -> float:
	var daily: float = Army.town_bill(game, town)
	var due: float = maxf(0.0, float(e.get("garrison_owed", 0.0))) + maxf(0.0, float(e.get("arms_due", 0.0)))
	for business: Dictionary in e.get("biz", []):
		if not TownEcon._town_funded(business) or business.get("closed", false): continue
		due += maxf(0.0, float(business.get("owed", 0.0)))
		if str(business.get("type", "")) != "works":
			daily += float(business.get("workers", 0)) * float(business.get("wage", 0.0))
	return maxf(float(treasury_lines(e)["short"]), daily * float(EconGen.YEAR_DAYS)) + due

## The ruler's temper from his traits (rolled at world gen): "greedy", "steady", "merciful".
static func temper(e: Dictionary) -> String:
	return String(e.get("ruler", {}).get("temper", "steady"))

static func common_tax_rate(e: Dictionary) -> float:
	return clampf(float(e.get("lord_tax_rate", e.get("ruler", {}).get("tribute", 0.05))), 0.02, 0.10)

static func _common_food_gap(e: Dictionary, f: Dictionary) -> float:
	return maxf(0.0, 7.0 - maxf(0.0, float(f.get("store", {}).get("food", 0.0)))) * float(Families.daily_rates(e, f)["food"])

## One shared native staple quote makes a pool split neutral even when the
## cheaper staple is scarce. Each owner retains its proportion of that cost.
static func _common_food_unit(e: Dictionary) -> float:
	var meals := 0.0
	for f in e.get("fams", []):
		if Population.is_cohort(f) and Population.households(f) > 0: meals += _common_food_gap(e, f)
	return EconomyRules.essential_food_cost(e, meals) / meals if meals > 0.0 else 0.0

static func _common_owner_budget(e: Dictionary, f: Dictionary, food_unit: float) -> Dictionary:
	var wealth := maxf(0.0, float(f.get("purse", 0.0)))
	var reserve := _common_food_gap(e, f) * food_unit
	var base := maxf(0.0, wealth - reserve)
	var rate := common_tax_rate(e)
	var leak := clampf(float(e.get("tax", {}).get("leak", 0.0)), 0.0, 1.0)
	return {"rate": rate, "wealth": wealth, "food_reserve": reserve, "taxable_wealth": base, "monthly_due": base * rate * (1.0 - leak)}

static func common_tax_budget(e: Dictionary) -> Dictionary:
	var out := {"rate": common_tax_rate(e), "wealth": 0.0, "food_reserve": 0.0, "taxable_wealth": 0.0, "monthly_due": 0.0}
	var unit := _common_food_unit(e)
	for f in e.get("fams", []):
		if not Population.is_cohort(f) or Population.households(f) <= 0: continue
		var row := _common_owner_budget(e, f, unit)
		for key in ["wealth", "food_reserve", "taxable_wealth", "monthly_due"]: out[key] = float(out[key]) + float(row[key])
	return out

## Rent a week for a house (value x 0.008 a month).
static func rent_week(e: Dictionary) -> float:
	return float(TownEcon.data()["goods"]["home"]["price"]) * Barge.pl(e) * float(Barge.B()["rent"]["month"]) * 7.0 / 30.0
