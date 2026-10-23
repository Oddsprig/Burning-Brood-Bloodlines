class_name Food
extends RefCounted
## Food and drink (spec: docs/specs/food-drink.md; tuned values listed in docs/FOOD.md).
##
## Company stock: Game.provisions = {"meal"|"beer"|"wine": [[qty, age_days], ...]} (oldest lot first).
## Rations: Game.rations = {"food": "short"|"normal"|"feast", "drink": "dry"|"ration"|"free"}.
## Clock: Game.food_clock = {"next": day of the next tick, "last": day of the last drain, "march": marching days since}.
## Campaign ticks run only when Game.advance_time crosses a tick boundary (morning, midday, evening), so the
## per-frame cost on the map is one float compare and one add.
##
## Per unit (core/unit.gd): belly 0-100, buzz 0-100, hungover, drink_days, drank_today, fav_drink, fav_today,
## fav_bonus, mass_mult (body mass loss/regain, Unit.mass()), merry_day.
## Battle: apply_battle(unit) sets Unit.food_attr_mult (KIN/FOC/AGI/END) while a BattleSim runs; the sim reads
## fatigue_mult / focus_mult / pain_tol / walk_mult / stumble_p and morale_mod from here.
## Every constant tagged # tuned is a starting value from the spec.

# ------------------------------------------------------------------ belly
const MEAL_BELLY := 35.0              # tuned (spec 3): each meal +35, cap 100
const BELLY_MAX := 100.0
const DRAIN_MARCH := 50.0             # tuned: belly per campaign day while marching
const DRAIN_REST := 30.0              # tuned: belly per day resting / in town
const BATTLE_DRAIN := 10.0            # tuned: extra at battle end
const STUFFED := 85.0                 # tuned: state thresholds
const FED := 40.0
const HUNGRY := 15.0
const SKIP_MEAL_AT := 65.0            # ours [tuned]: a man eats a meal only when it fits (belly <= 100 - 35); else it stays in stock
const START_BELLY := 60.0             # ours: a new man arrives Fed
## Effects per belly state: fatigue gain mult, walk ticks/tile mult, END mult, focus, start morale, stress/day.
const BELLY_FX := {
	"stuffed": {"fatigue": 1.10, "walk": 1.05, "end": 1.0, "focus": 0.0, "morale": 3.0, "stress": 0.0},
	"fed": {"fatigue": 1.0, "walk": 1.0, "end": 1.0, "focus": 0.0, "morale": 5.0, "stress": 0.0},
	"hungry": {"fatigue": 1.15, "walk": 1.0, "end": 1.0, "focus": -0.05, "morale": -5.0, "stress": 0.0},
	"starving": {"fatigue": 1.35, "walk": 1.0, "end": 0.75, "focus": 0.0, "morale": -15.0, "stress": 5.0},
}  # tuned (spec 3)
const MASS_LOSS := 0.015              # tuned: per day ending Starving, of rolled mass
const MASS_FLOOR := 0.85              # tuned: never below 85% of rolled mass
const MASS_REGAIN := 0.01             # tuned: per day ending Fed or Stuffed, up to rolled mass

# ------------------------------------------------------------------ drink need
const DRINK_FOCUS := [0.0, -0.03, -0.06, -0.10]   # tuned: focus by days unmet in a row (3+ = last)
const DRINK_STRESS := 3.0             # tuned: stress per day unmet, from day 2
const DRINK_STRESS_FROM := 2
const LOW_APPETITE_MEDIAN := 35       # tuned: races with appetite median <= this take x0.5 drink-need penalties
const LOW_APPETITE_MULT := 0.5

# ------------------------------------------------------------------ buzz
const BUZZ_PER_MUG := 12.0            # tuned: x (70 / body kg)^0.5
const BUZZ_REF_KG := 70.0
const WINE_MUGS := 1.5                # tuned: a cup of wine counts 1.5 mugs (stock, want and buzz)
const BUZZ_DECAY_HOUR := 4.0          # tuned: per campaign hour
const BUZZ_DECAY_TICK := 0.1          # tuned: per battle tick
const BUZZ_MAX := 100.0
const TIPSY := 10.0                   # tuned: state thresholds
const DRUNK := 30.0
const HAMMERED := 60.0
const WANT_BASE := 1.0                # tuned: Free mugs/day = 1 + appetite/25, rounded
const WANT_PER_APPETITE := 25.0
## Effects per buzz state: start morale, pain tolerance mult, attribute mults, stumble chance per move.
const BUZZ_FX := {
	"sober": {"morale": 0.0, "pain": 1.0, "attr": {}, "stumble": 0.0},
	"tipsy": {"morale": 5.0, "pain": 1.10, "attr": {}, "stumble": 0.0},
	"drunk": {"morale": 10.0, "pain": 1.20, "attr": {"KIN": 0.90, "FOC": 0.90}, "stumble": 0.0},
	"hammered": {"morale": 15.0, "pain": 1.25, "attr": {"KIN": 0.75, "AGI": 0.75}, "stumble": 0.02},
}  # tuned (spec 5)
const HANGOVER_BUZZ := 30.0           # tuned: buzz 30+ at the evening tick -> hung over until the next evening
const HANGOVER_FOCUS := -0.10         # tuned
const HANGOVER_FATIGUE := 1.10        # tuned
const FOCUS_CAP := 0.15               # spec: total focus modifier stays inside +-15%

# ------------------------------------------------------------------ favourite drink, feast, stock
const FAV_MORALE := 3.0               # tuned: start morale the day after he got his favourite
const FAV_STRESS := -1.0              # tuned: per day he gets it
const FEAST_MEALS := 3                # tuned: feast cost = 3 meals + Free drink per man at town prices
const FEAST_STRESS := -15.0           # tuned
const STRESS_MAX := 100.0
const SPOIL_DAYS := {"meal": 21, "beer": 30, "wine": -1}  # tuned: -1 never spoils
const BASE_PRICE := {"meal": 3.6, "beer": 6.0, "wine": 20.0}  # coins (the economy's base prices: a grain meal, a mug, a cup)
const KINDS := ["meal", "beer", "wine"]
const MEAT_GOODS := ["fresh_meat", "meat"]
const START_STOCK := {"meal": 200, "beer": 100, "wine": 10}   # ours: about 6 days for the starting company

# ------------------------------------------------------------------ campaign clock and rations
const TICK_HOURS := [7.0, 13.0, 19.0] # tuned: morning, midday, evening ticks (map clock hours, Calendar.hour)
const FOOD_RATIONS := ["short", "normal", "feast"]
const DRINK_RATIONS := ["dry", "ration", "free"]
const MEALS_PER_DAY := {"short": 1, "normal": 2, "feast": 3}
## Which ticks (0 morning, 1 midday, 2 evening) serve a meal under each food ration.
const MEAL_TICKS := {"short": [2], "normal": [0, 2], "feast": [0, 1, 2]}
const RATION_LABELS := {"short": "Short", "normal": "Normal", "feast": "Feast", "dry": "Dry", "ration": "Ration", "free": "Free"}
const WARN_DAYS := 3.0                # spec: warn under 3 days of stock

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/food.json"))
		_data = d if d is Dictionary else {}
	return _data

static func _race_pair(table: String, race: String, dflt: Array) -> Array:
	var t: Dictionary = data().get(table, {})
	return t.get(race, t.get("_default", dflt))

# ================================================================== states
static func belly_state(b: float) -> String:
	if b >= STUFFED: return "stuffed"
	if b >= FED: return "fed"
	if b >= HUNGRY: return "hungry"
	return "starving"

static func buzz_state(z: float) -> String:
	if z >= HAMMERED: return "hammered"
	if z >= DRUNK: return "drunk"
	if z >= TIPSY: return "tipsy"
	return "sober"

const STATE_NAMES := {"stuffed": "Stuffed", "fed": "Fed", "hungry": "Hungry", "starving": "Starving",
	"sober": "Sober", "tipsy": "Tipsy", "drunk": "Drunk", "hammered": "Hammered"}

static func is_beast(u: Unit) -> bool:
	return bool(u.race_def().get("beast", false))

static func appetite(u: Unit) -> float:
	if u.personality.has("appetite"):
		return float(u.personality["appetite"])
	return race_appetite(u.race)

static func race_appetite(race: String) -> float:
	var rp = DB.races.get(race, {}).get("personality", {})
	if rp is Dictionary and rp.has("appetite") and not (rp["appetite"] is Array):
		return float(rp["appetite"])
	return 50.0

## Elves and other low-appetite races feel the drink need at half strength.
static func need_mult(u: Unit) -> float:
	return LOW_APPETITE_MULT if race_appetite(u.race) <= LOW_APPETITE_MEDIAN else 1.0

## Mugs (equivalents) a man wants per day under Free.
static func want(u: Unit) -> int:
	return maxi(1, int(round(WANT_BASE + appetite(u) / WANT_PER_APPETITE)))

static func fav(u: Unit) -> String:
	return u.fav_drink if u.fav_drink != "" else "beer"

static func buzz_per_drink(u: Unit, kind: String) -> float:
	var kg := maxf(10.0, u.rolled_mass() * u.mass_mult)
	return BUZZ_PER_MUG * sqrt(BUZZ_REF_KG / kg) * (WINE_MUGS if kind == "wine" else 1.0)

## Total focus modifier from food and drink (hunger, drink need, hangover), inside +-FOCUS_CAP.
static func focus(u: Unit) -> float:
	var f: float = BELLY_FX[belly_state(u.belly)]["focus"]
	f += float(DRINK_FOCUS[mini(u.drink_days, DRINK_FOCUS.size() - 1)]) * need_mult(u)
	if u.hungover:
		f += HANGOVER_FOCUS
	f += Sickness.unit_focus(u)   # sickness: a sick man's focus (inside the same cap)
	return clampf(f, -FOCUS_CAP, FOCUS_CAP)

static func fatigue_mult(u: Unit) -> float:
	return float(BELLY_FX[belly_state(u.belly)]["fatigue"]) * (HANGOVER_FATIGUE if u.hungover else 1.0) * Sickness.unit_fatigue(u)

static func walk_mult(u: Unit) -> float:
	return float(BELLY_FX[belly_state(u.belly)]["walk"])

static func pain_tolerance(u: Unit) -> float:
	return float(BUZZ_FX[buzz_state(u.buzz)]["pain"])

static func stumble_chance(u: Unit) -> float:
	return float(BUZZ_FX[buzz_state(u.buzz)]["stumble"])

## Start-of-battle morale modifier (belly + buzz + favourite drink).
static func morale_mod(u: Unit) -> float:
	var m: float = float(BELLY_FX[belly_state(u.belly)]["morale"]) + float(BUZZ_FX[buzz_state(u.buzz)]["morale"])
	if u.fav_bonus or u.fav_today:
		m += FAV_MORALE
	return m

## Attribute multipliers (Unit.food_attr_mult) for the current belly/buzz state. Empty when none apply.
static func attr_mults(u: Unit) -> Dictionary:
	var m := {}
	var e: float = BELLY_FX[belly_state(u.belly)]["end"]
	if e != 1.0:
		m["END"] = e
	var bz: Dictionary = BUZZ_FX[buzz_state(u.buzz)]["attr"]
	for a in bz:
		m[a] = float(m.get(a, 1.0)) * float(bz[a])
	Sickness.unit_attr(u, m)   # sickness: END x0.75, STR x0.85 while sick
	return m

## Sets the battle attribute multipliers on the unit (BattleSim.setup and on a buzz state change).
static func apply_battle(u: Unit) -> void:
	u.set_food_attr_mult(attr_mults(u))

static func clear_battle(u: Unit) -> void:
	u.set_food_attr_mult({})

## Effects text for the unit card (tap on a bar).
static func belly_effects(u: Unit) -> Array:
	var st := belly_state(u.belly)
	var fx: Dictionary = BELLY_FX[st]
	var out := ["%s (belly %d/100): carrying %.1f kg of food." % [STATE_NAMES[st], int(u.belly), u.belly * Unit.BELLY_KG_PER_POINT]]
	if fx["morale"] != 0.0: out.append("Morale at the start of a battle %+d." % int(fx["morale"]))
	if fx["fatigue"] != 1.0: out.append("Tires %d%% faster." % int(round((fx["fatigue"] - 1.0) * 100)))
	if fx["walk"] != 1.0: out.append("Walks %d%% slower." % int(round((fx["walk"] - 1.0) * 100)))
	if fx["focus"] != 0.0: out.append("Focus %d%%." % int(round(fx["focus"] * 100)))
	if fx["end"] != 1.0: out.append("Endurance counts x%.2f." % fx["end"])
	if fx["stress"] != 0.0: out.append("Stress +%d each day he ends starving; he loses body mass." % int(fx["stress"]))
	if u.mass_mult < 0.999: out.append("Body mass down to %d%% of normal." % int(round(u.mass_mult * 100)))
	if u.drink_days > 0:
		out.append("No drink for %d day%s: focus %d%%%s." % [u.drink_days, "" if u.drink_days == 1 else "s",
			int(round(float(DRINK_FOCUS[mini(u.drink_days, 3)]) * need_mult(u) * 100)), ", stress rising" if u.drink_days >= DRINK_STRESS_FROM else ""])
	out.append("Total focus from food and drink: %+d%% (limit +-%d%%)." % [int(round(focus(u) * 100)), int(FOCUS_CAP * 100)])
	return out

static func buzz_effects(u: Unit) -> Array:
	var st := buzz_state(u.buzz)
	var fx: Dictionary = BUZZ_FX[st]
	var out := ["%s (buzz %d/100). Favourite drink: %s." % [STATE_NAMES[st], int(u.buzz), fav(u)]]
	if fx["morale"] != 0.0: out.append("Morale at the start of a battle %+d." % int(fx["morale"]))
	if fx["pain"] != 1.0: out.append("Shrugs off pain: tolerance x%.2f." % fx["pain"])
	for a in fx["attr"]:
		out.append("%s x%.2f." % [String(DB.ATTR_NAMES.get(a, a)).capitalize(), fx["attr"][a]])
	if fx["stumble"] > 0.0: out.append("%d%% chance to stumble on each step." % int(fx["stumble"] * 100))
	if u.hungover: out.append("Hung over: focus %d%%, tires %d%% faster, until the evening." % [int(HANGOVER_FOCUS * 100), int(round((HANGOVER_FATIGUE - 1.0) * 100))])
	out.append("Drinks %d mug%s a day when it flows freely." % [want(u), "" if want(u) == 1 else "s"])
	return out

# ================================================================== recruitment and spawn
## Favourite drink, rolled by race odds (data/food.json fav_drink). The rng is seeded from a value of the
## recruitment rng without drawing from it, so adding this roll changes no other roll.
static func roll_fav_drink(u: Unit, seed_value: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "fav_drink"])
	var odds := _race_pair("fav_drink", u.race, [70, 30])
	var total := float(odds[0]) + float(odds[1])
	u.fav_drink = "beer" if r.randf() * total < float(odds[0]) else "wine"

## Enemies and monsters have no daily sim: belly and buzz are set at battle spawn from the army's supply level
## ("well" until the economy exposes supply). Beasts: belly only (hungry packs), no buzz.
static func spawn_state(u: Unit, supply: String, rng: RandomNumberGenerator) -> void:
	var br: Array = data().get("supply_belly", {}).get(supply, [50, 80])
	if is_beast(u):
		br = data().get("beast_belly", [20, 50])
	u.belly = rng.randf_range(float(br[0]), float(br[1]))
	if is_beast(u):
		u.buzz = 0.0
	else:
		var zr := _race_pair("enemy_buzz", u.race, [0, 25])
		u.buzz = rng.randf_range(float(zr[0]), float(zr[1]))
	u.hungover = false
	u.drink_days = 0

## Game.start_battle: enemy (and allied non-company) units get their spawn state.
static func spawn_battle(game, params: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(params.get("seed", 0)), "food_spawn"])
	var supply: String = params.get("enemy_supply", "well")
	for u in params.get("enemy", []):
		spawn_state(u, supply, r)
	var ally_supply: String = params.get("ally_supply", "well")
	for u in params.get("allies", []):
		if not game.company.has(u):
			spawn_state(u, ally_supply, r)

# ================================================================== stock
static func new_stock() -> Dictionary:
	return {"meal": [], "beer": [], "wine": []}

static func stock(game, kind: String) -> int:
	var n := 0
	for lot in game.provisions.get(kind, []):
		n += int(lot[0])
	return n

static func add_stock(game, kind: String, qty: int, age: int = 0, good: String = "", food_name: String = "") -> void:
	if qty <= 0:
		return
	if not game.provisions.has(kind):
		game.provisions[kind] = []
	var lots: Array = game.provisions[kind]
	# the newest lot is last; merge same-age purchases
	if not lots.is_empty() and int(lots[-1][1]) == age and String(lots[-1][2] if lots[-1].size() > 2 else "") == good and String(lots[-1][3] if lots[-1].size() > 3 else "") == food_name:
		lots[-1][0] = int(lots[-1][0]) + qty
	else:
		var at := 0
		while at < lots.size() and int(lots[at][1]) >= age:
			at += 1
		lots.insert(at, [qty, age, good, food_name] if good != "" else [qty, age])

## Named foods remain lots in the same feeding inventory; old unidentified lots stay mixed rations.
static func packed_food(game) -> Array:
	var rows := []
	var by_name := {}
	for lot in game.provisions.get("meal", []):
		var good := String(lot[2]) if lot.size() > 2 else ""
		var title := String(lot[3]) if lot.size() > 3 and String(lot[3]) != "" else (Goods.good_name(good).capitalize() if good != "" else "Mixed rations")
		var key := good + "|" + title
		if not by_name.has(key):
			by_name[key] = rows.size()
			rows.append({"good": good, "name": title, "qty": 0, "oldest": 0})
		var row: Dictionary = rows[int(by_name[key])]
		row["qty"] += int(lot[0])
		row["oldest"] = maxi(int(row["oldest"]), int(lot[1]))
	return rows

static func food_stock(game, good: String) -> int:
	var qty := 0
	for row in packed_food(game):
		if row["good"] == good:
			qty += int(row["qty"])
	return qty

## Physical provision mass; unnamed older rations retain their historical grain weight.
static func food_weight(game) -> float:
	var table := Goods.table()
	var kg := 0.0
	for row in packed_food(game):
		var good := String(row["good"])
		kg += int(row["qty"]) * float(table[good if good != "" else "grain"]["weight"])
	for drink_kind in ["beer", "wine"]:
		kg += stock(game, drink_kind) * float(table[drink_kind]["weight"])
	return kg

## Pure preview of the existing immediate feeding rule, including pending digestion.
static func immediate_food_need(game) -> int:
	if String(game.rations.get("food", "normal")) == "short":
		return 0
	var dt := maxf(0.0, game.day - float(game.food_clock.get("last", game.day)))
	var march := clampf(float(game.food_clock.get("march", 0.0)), 0.0, dt)
	var drain := DRAIN_MARCH * march + DRAIN_REST * (dt - march)
	var need := 0
	for u in eaters(game):
		var belly := clampf(u.belly - drain, 0.0, BELLY_MAX)
		need += int(ceil(maxf(0.0, FED - belly) / MEAL_BELLY))
	return need

static func food_name(town: Dictionary, good: String) -> String:
	return (TownEcon.label(town["econ"], good) if TownEcon.has_econ(town) else Goods.good_name(good)).capitalize()

static func food_cost(town: Dictionary, good: String, qty: int) -> int:
	return maxi(1, int(ceil(Goods.price_f(town, good) * qty - 0.0001))) if qty > 0 and Goods.FOODS.has(good) else 0

## Buy a specific real market food, retaining its local name through travel/save/load.
static func buy_food(game, town: Dictionary, good: String, qty: int) -> String:
	if not Goods.FOODS.has(good):
		return "not a road provision"
	qty = mini(qty, int(floor(Goods.supply(town, good))))
	if qty <= 0:
		return "none for sale here"
	var coins := food_cost(town, good, qty)
	if coins > game.gold:
		return "not enough coins (%d needed)" % coins
	var title := food_name(town, good)
	Goods.take(town, good, qty) # synchronous, exact withdrawal prevalidated against the same stock above
	game.gold -= coins
	Goods.pay_market(town, float(coins))
	add_stock(game, "meal", qty, 0, good, title)
	sync(game)
	feed_hungry(game)
	game.changed.emit()
	return ""

## Named meat and fresh meat still sitting in the meal lots. Unnamed rations are not meat.
static func meat_units(game) -> int:
	var n := 0
	if not (game.provisions is Dictionary): return 0
	for lot in game.provisions.get("meal", []):
		var good := String(lot[2]) if lot.size() > 2 else ""
		if MEAT_GOODS.has(good): n += int(lot[0])
	return n

## Meat the day's ration meals would take. Same skip, rotation and oldest-lot order as _serve_meals.
## Bellies and stock are not changed. A man who eats earlier in the day may be too full for a later tick.
static func ration_meat_reserve(game) -> int:
	var men := eaters(game)
	var n := men.size()
	if n == 0 or not (game.provisions is Dictionary): return 0
	var ration := "normal"
	if game.rations is Dictionary: ration = String(game.rations.get("food", "normal"))
	var ticks: Array = MEAL_TICKS.get(ration, [0, 2])
	var belly: Array = []
	belly.resize(n)
	for i in n:
		belly[i] = float((men[i] as Unit).belly)
	var lots: Array = []
	for lot in game.provisions.get("meal", []):
		var good := String(lot[2]) if lot.size() > 2 else ""
		lots.append([int(lot[0]), good])
	var rot := 0
	if game.food_clock is Dictionary: rot = int(game.food_clock.get("rot", 0))
	var meat := 0
	for which in [0, 1, 2]:
		if ticks.has(which):
			for i in n:
				var u := posmod(i + rot, n)
				if float(belly[u]) > SKIP_MEAL_AT: continue
				if lots.is_empty(): return meat
				var top: Array = lots[0]
				top[0] = int(top[0]) - 1
				if MEAT_GOODS.has(String(top[1])): meat += 1
				if int(top[0]) <= 0: lots.pop_front()
				belly[u] = minf(BELLY_MAX, float(belly[u]) + MEAL_BELLY)
		rot += 1
	return meat

## Draws qty from the oldest meal lots whose good is listed. Unnamed and other foods stay.
## Does not create provisions, age lots, or spoil anything. Partial lots keep age, good and name.
static func take_named(game, goods: Array, qty: int) -> Dictionary:
	var out := {"taken": 0, "by_good": {}, "lots": [], "spoiled": 0}
	if qty <= 0 or not (game.provisions is Dictionary) or not game.provisions.has("meal"): return out
	var lots: Array = game.provisions["meal"]
	var i := 0
	while i < lots.size() and int(out["taken"]) < qty:
		var lot: Array = lots[i]
		var good := String(lot[2]) if lot.size() > 2 else ""
		if not goods.has(good):
			i += 1
			continue
		var n := mini(int(lot[0]), qty - int(out["taken"]))
		var age := int(lot[1])
		var food_name := String(lot[3]) if lot.size() > 3 else ""
		lot[0] = int(lot[0]) - n
		out["taken"] = int(out["taken"]) + n
		out["by_good"][good] = int(out["by_good"].get(good, 0)) + n
		(out["lots"] as Array).append({"good": good, "name": food_name, "qty": n, "age": age})
		if int(lot[0]) <= 0: lots.remove_at(i)
		else: i += 1
	return out

## Takes up to qty from the oldest lots first. Returns how many were taken.
static func take(game, kind: String, qty: int) -> int:
	var lots: Array = game.provisions.get(kind, [])
	var got := 0
	while got < qty and not lots.is_empty():
		var n := mini(int(lots[0][0]), qty - got)
		lots[0][0] = int(lots[0][0]) - n
		got += n
		if int(lots[0][0]) <= 0:
			lots.pop_front()
	return got

## Ages every lot by a day and throws out what has spoiled. Returns {kind: qty spoiled}.
static func age_stock(game) -> Dictionary:
	var spoiled := {}
	for kind in KINDS:
		var lots: Array = game.provisions.get(kind, [])
		var keep := []
		for lot in lots:
			lot[1] = int(lot[1]) + 1
			var limit: int = SPOIL_DAYS[kind]
			if limit >= 0 and int(lot[1]) >= limit:
				spoiled[kind] = int(spoiled.get(kind, 0)) + int(lot[0])
			else:
				keep.append(lot)
		game.provisions[kind] = keep
	return spoiled

static func eaters(game) -> Array:
	return game.company.filter(func(u): return not u.dead)

static func drink_allowance(game, u: Unit) -> float:
	match String(game.rations.get("drink", "ration")):
		"dry": return 0.0
		"free": return float(want(u))
	return 1.0

## Days the stock lasts at the current rations (INF when nothing is consumed).
static func food_days(game) -> float:
	var per := float(MEALS_PER_DAY.get(String(game.rations.get("food", "normal")), 2)) * eaters(game).size()
	return INF if per <= 0.0 else float(stock(game, "meal")) / per

static func drink_days(game) -> float:
	var per := 0.0
	for u in eaters(game):
		per += drink_allowance(game, u)
	if per <= 0.0:
		return INF
	return (float(stock(game, "beer")) + WINE_MUGS * float(stock(game, "wine"))) / per

## One warning line for the company screen ("" = nothing to warn about).
static func warning(game) -> String:
	var parts := []
	if food_days(game) < WARN_DAYS:
		parts.append("food runs out in %s" % _days_word(food_days(game)))
	if String(game.rations.get("drink", "ration")) != "dry" and drink_days(game) < WARN_DAYS:
		parts.append("drink runs out in %s" % _days_word(drink_days(game)))
	var hungry := 0
	for u in eaters(game):
		if u.belly < FED:
			hungry += 1
	if hungry > 0:
		var why := ""
		if stock(game, "meal") > 0 and String(game.rations.get("food", "normal")) == "short":
			why = " on Short rations"   # v0.014: with meals in stock only Short rations leave men hungry (feed_hungry)
		parts.append("%d %s hungry%s" % [hungry, "man is" if hungry == 1 else "men are", why])
	if parts.is_empty():
		return ""
	var s: String = ", ".join(PackedStringArray(parts))
	return s.substr(0, 1).to_upper() + s.substr(1) + "."

static func _days_word(d: float) -> String:
	if d < 1.0:
		return "under a day"
	return "%d day%s" % [int(d), "" if int(d) == 1 else "s"]

static func days_text(d: float) -> String:
	if d == INF:
		return "-"
	return "%.1f days" % d if d < 10.0 else "%d days" % int(d)

# ================================================================== campaign time
static func init_company(game, scale: float = 1.0) -> void:
	game.provisions = new_stock()
	for k in START_STOCK:
		add_stock(game, k, int(round(float(START_STOCK[k]) * maxf(0.0, scale))))
	game.rations = {"food": "normal", "drink": "ration"}
	game.food_clock = {"next": next_tick_after(game.day), "last": game.day, "march": 0.0}

## First tick time (Game.day value) strictly after day t. Ticks sit at TICK_HOURS on the map clock
## (campaign/calendar.gd: Calendar.hour / day_index; Game.day 0 = 07:00 of calendar day 0).
static func next_tick_after(t: float) -> float:
	var d := Calendar.day_index(t)
	for k in 2:
		for h in TICK_HOURS:
			var x := day_at_hour(d + k, h)
			if x > t + 0.000001:
				return x
	return day_at_hour(d + 2, TICK_HOURS[0])

## Game.day value of hour h on calendar day d.
static func day_at_hour(d: int, h: float) -> float:
	return (float(d) * 24.0 + h - Calendar.START_HOUR) / 24.0

static func tick_index(t: float) -> int:
	var hr := Calendar.hour(t)
	var best := 0
	for i in TICK_HOURS.size():
		if absf(hr - TICK_HOURS[i]) < absf(hr - TICK_HOURS[best]):
			best = i
	return best

## Called from Game.advance_time every time step (map frames). Cheap unless a tick boundary is crossed.
## Marching dragons eat at each morning boundary, after every earlier tick (including that evening's spoilage).
static func on_time(game, days: float, in_town: bool) -> void:
	if game.food_clock.is_empty():
		game.food_clock = {"next": next_tick_after(game.day - days), "last": game.day - days, "march": 0.0}
	if not in_town and game.location == "" and not (game.world.get("party", {}).get("path", []) as Array).is_empty():
		game.food_clock["march"] = float(game.food_clock.get("march", 0.0)) + days
	var fed_until := int(floor(float(game.day) - days + 0.0000001))
	var guard := 0
	while game.day >= float(game.food_clock["next"]) and guard < 400:
		guard += 1
		var t := float(game.food_clock["next"])
		fed_until = _feed_march_until(game, fed_until, t)
		_drain_to(game, t)
		do_tick(game, tick_index(t))
		game.food_clock["next"] = next_tick_after(t)
	_feed_march_until(game, fed_until, float(game.day))

## Feeds each new morning strictly before the tick at that time, so a one-day jump spoils before it feeds.
static func _feed_march_until(game, fed_until: int, t: float) -> int:
	var boundary := int(floor(t + 0.0000001))
	while fed_until < boundary:
		fed_until += 1
		Warfare.feed_march_day(game, fed_until)
	return fed_until

## Applies digestion and buzz decay up to time t (no meals). Also used right before a battle.
static func _drain_to(game, t: float) -> void:
	var last := float(game.food_clock.get("last", t))
	var dt := maxf(0.0, t - last)
	if dt <= 0.0:
		return
	var march := clampf(float(game.food_clock.get("march", 0.0)), 0.0, dt)
	var drain := DRAIN_MARCH * march + DRAIN_REST * (dt - march)
	var decay := BUZZ_DECAY_HOUR * 24.0 * dt
	for u in eaters(game):
		u.belly = clampf(u.belly - drain, 0.0, BELLY_MAX)
		u.buzz = maxf(0.0, u.buzz - decay)
	game.food_clock["last"] = t
	game.food_clock["march"] = 0.0

static func sync(game) -> void:
	if not game.food_clock.is_empty():
		_drain_to(game, game.day)

## One campaign tick: 0 morning, 1 midday, 2 evening.
static func do_tick(game, which: int) -> void:
	var men := eaters(game)
	if men.is_empty():
		return
	var rot := int(game.food_clock.get("rot", 0))
	game.food_clock["rot"] = rot + 1
	if (MEAL_TICKS.get(String(game.rations.get("food", "normal")), [0, 2]) as Array).has(which):
		_serve_meals(game, men, rot)
	feed_hungry(game, rot)
	if which == 0:
		_serve_drinks(game, men, rot, true)
	elif which == 2:
		_serve_drinks(game, men, rot, false)
		end_of_day(game, men)

static func _rotated(men: Array, rot: int) -> Array:
	var n := men.size()
	var out := []
	for i in n:
		out.append(men[(i + rot) % n])
	return out

## Out of stock: what's left goes round the company in turn (the start rotates each tick); the rest go without.
static func _serve_meals(game, men: Array, rot: int) -> void:
	for u in _rotated(men, rot):
		if u.belly > SKIP_MEAL_AT:
			continue
		if take(game, "meal", 1) == 1:
			u.belly = minf(BELLY_MAX, u.belly + MEAL_BELLY)

## v0.014: a Hungry or Starving man does not wait for the cook when there are meals in the wagons. Under Normal
## and Feast rations he eats now, a meal at a time, until he is Fed again (belly 40+), oldest meals first and
## round the company in turn while the stock lasts. Short rations keep men short by choice: nobody eats extra.
## In steady marching or rest the fixed meals keep every man Fed, so this only acts after hungry days (the
## company ran out, then bought or took food), which used to leave the whole company "hungry" for up to a day
## while hundreds of meals sat in stock. Called at every meal-clock tick and right after buying meals.
static func feed_hungry(game, rot: int = 0) -> int:
	if String(game.rations.get("food", "normal")) == "short":
		return 0
	var men := eaters(game)
	if men.is_empty():
		return 0
	var eaten := 0
	var guard := 0
	var any := true
	while any and guard < 8:
		guard += 1
		any = false
		for u in _rotated(men, rot):
			if u.belly >= FED:
				continue
			if take(game, "meal", 1) != 1:
				return eaten
			u.belly = minf(BELLY_MAX, u.belly + MEAL_BELLY)
			eaten += 1
			any = true
	return eaten

## Morning: one drink each (Ration and Free). Evening: the rest of his want under Free. Each drink is his
## favourite if stocked, otherwise whatever there is. Round-robin so a short stock is spread evenly.
static func _serve_drinks(game, men: Array, rot: int, morning: bool) -> void:
	var left := {}
	for u in men:
		var allow := drink_allowance(game, u)
		var amt := minf(1.0, allow) if morning else maxf(0.0, allow - u.drank_eq)
		if amt > 0.25:
			left[u] = amt
	var order := _rotated(men, rot)
	var guard := 0
	while not left.is_empty() and guard < 50:
		guard += 1
		var any := false
		for u in order:
			if not left.has(u):
				continue
			var kind := fav(u)
			var other := "wine" if kind == "beer" else "beer"
			if stock(game, kind) <= 0:
				kind = other
			if take(game, kind, 1) != 1:
				left.erase(u)
				continue
			any = true
			var eq := WINE_MUGS if kind == "wine" else 1.0
			drink(u, kind)
			u.drank_eq += eq
			left[u] = float(left[u]) - eq
			if float(left[u]) <= 0.25:
				left.erase(u)
		if not any:
			break

static func drink(u: Unit, kind: String) -> void:
	u.buzz = minf(BUZZ_MAX, u.buzz + buzz_per_drink(u, kind))
	u.drank_today = true
	if kind == fav(u):
		u.fav_today = true

## Evening: hangover check, drink need, hunger stress and body mass, favourite drink, stock ageing.
static func end_of_day(game, men: Array) -> void:
	for u in men:
		end_of_day_unit(u)
	age_stock(game)

static func end_of_day_unit(u: Unit) -> void:
	u.hungover = u.buzz >= HANGOVER_BUZZ
	if u.drank_today:
		u.drink_days = 0
	else:
		u.drink_days += 1
		if u.drink_days >= DRINK_STRESS_FROM:
			add_stress(u, DRINK_STRESS * need_mult(u))
	var st := belly_state(u.belly)
	if st == "starving":
		add_stress(u, float(BELLY_FX["starving"]["stress"]))
		u.mass_mult = maxf(MASS_FLOOR, u.mass_mult - MASS_LOSS)
	elif st == "fed" or st == "stuffed":
		u.mass_mult = minf(1.0, u.mass_mult + MASS_REGAIN)
	u.fav_bonus = u.fav_today
	if u.fav_today:
		add_stress(u, FAV_STRESS)
	u.fav_today = false
	u.drank_today = false
	u.drank_eq = 0.0

static func add_stress(u: Unit, amount: float) -> void:
	u.stress = clampf(u.stress + amount, 0.0, STRESS_MAX)

## Battle end: the fight burns an extra 10 belly; the battle-only attribute multipliers come off.
static func after_battle(units: Array) -> void:
	for u in units:
		if u == null:
			continue
		clear_battle(u)
		if not u.dead:
			u.belly = maxf(0.0, u.belly - BATTLE_DRAIN)

# ================================================================== market and feast
static func good_of(kind: String) -> Dictionary:
	return data().get("goods", {}).get(kind, {})

## The town carries this good in its market (campaign/goods.gd; the town economy's stock, or a stand-in
## town's plain goods)? "food" = grain, fruit and meat together.
static func town_has_good(town: Dictionary, kind: String) -> bool:
	var g: String = good_of(kind).get("good", "")
	if g == "":
		return false
	if TownEcon.has_econ(town):
		return true
	if not town.has("goods"):
		return false
	var gd: Dictionary = town["goods"]
	return gd.has("grain") if g == "food" else gd.has(g)

## Price multiplier from the town's market (1.0 where the town has no such good): the real price over base.
static func price_mult(town: Dictionary, kind: String) -> float:
	if not town_has_good(town, kind):
		return 1.0
	return Goods.price_mult(town, good_of(kind)["good"])

## Gold for qty of kind in this town (at least 1).
static func cost(town: Dictionary, kind: String, qty: int) -> int:
	if qty <= 0:
		return 0
	return maxi(1, int(ceil(float(BASE_PRICE[kind]) * price_mult(town, kind) * qty - 0.0001)))

## How many the town can sell (-1 = no limit: the town has no supply of that good).
static func available(town: Dictionary, kind: String) -> int:
	if not town_has_good(town, kind):
		return -1
	var gd := good_of(kind)
	return int(floor(Goods.supply(town, gd["good"]) * float(gd.get("per", 1)) + 0.0001))

static func _take_supply(town: Dictionary, kind: String, qty: int) -> void:
	if not town_has_good(town, kind):
		return
	var gd := good_of(kind)
	Goods.take(town, gd["good"], int(ceil(float(qty) / float(gd.get("per", 1)) - 0.0001)))

## Buys qty (clipped to the town's supply). Returns "" or a reason.
static func buy(game, town: Dictionary, kind: String, qty: int) -> String:
	var av := available(town, kind)
	if av >= 0:
		qty = mini(qty, av)
	if qty <= 0:
		return "none for sale here"
	var c := cost(town, kind, qty)
	if c > game.gold:
		return "not enough coins (%d needed)" % c
	game.gold -= c
	Goods.pay_market(town, float(c))   # economy: the gold goes to the town's market
	_take_supply(town, kind, qty)
	add_stock(game, kind, qty)
	if kind == "meal":
		sync(game)          # digestion up to now, then the hungry eat straight away
		feed_hungry(game)
	game.changed.emit()
	return ""

## Towns of size >= 1 have a tavern unless the town says otherwise.
static func has_tavern(town: Dictionary) -> bool:
	if town.has("tavern"):
		return bool(town["tavern"])
	return int(town.get("size", 0)) >= 1

static func feast_cost(game, town: Dictionary) -> int:
	var meals := 0
	var beer := 0
	var wine := 0
	for u in eaters(game):
		meals += FEAST_MEALS
		if fav(u) == "wine":
			wine += int(ceil(want(u) / WINE_MUGS))
		else:
			beer += want(u)
	return cost(town, "meal", meals) + cost(town, "beer", beer) + cost(town, "wine", wine)

## Feast the company: belly 100, make merry met, stress -15, the night's drink (Free want, favourite drink).
static func feast(game, town: Dictionary) -> String:
	if not has_tavern(town):
		return "there is no tavern here"
	var men := eaters(game)
	if men.is_empty():
		return "no one to feast"
	var c := feast_cost(game, town)
	if c > game.gold:
		return "not enough coins (%d needed)" % c
	game.gold -= c
	Goods.pay_market(town, float(c))   # economy: the tavern's custom goes to the town's market
	for u in men:
		_take_supply(town, "meal", FEAST_MEALS)
		u.belly = BELLY_MAX
		u.merry_day = game.day
		add_stress(u, FEAST_STRESS)
		var kind := fav(u)
		var n := int(ceil(want(u) / WINE_MUGS)) if kind == "wine" else want(u)
		_take_supply(town, kind, n)
		for i in n:
			drink(u, kind)
		u.hungover = u.hungover or u.buzz >= HANGOVER_BUZZ
	game.changed.emit()
	return ""

# ================================================================== save / load
static func stock_to_save(game) -> Dictionary:
	return game.provisions.duplicate(true)

static func stock_from_save(d) -> Dictionary:
	var out := new_stock()
	if d is Dictionary:
		for k in KINDS:
			for lot in d.get(k, []):
				var saved := [int(lot[0]), int(lot[1])]
				if k == "meal" and lot.size() > 2 and (Goods.FOODS.has(String(lot[2])) or String(lot[2]) == "fresh_meat"):
					saved.append(String(lot[2]))
					saved.append(String(lot[3]) if lot.size() > 3 else "")
				out[k].append(saved)
	return out
