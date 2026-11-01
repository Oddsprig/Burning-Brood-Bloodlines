extends RefCounted
## Economy spec 2 (docs/specs/economy-2-army.md section 7 + Douglas's rules): every non-monster unit on the map has
## a family; no force has unpaid soldiers without the desertion timer running (and the timer ends in desertion
## home); rank counts never exceed caps and caps follow army size; the orc cascade (kill a warboss -> one big
## boss, one boss, one blooded promoted, all by fights, counts valid); wage gold leaves the treasury and lands in
## family purses (conserved, coin and kind); a succession fight < 10 ms; kill renown; force stores (player win
## gains them, player loss keeps its own, AI winner takes them, conserved); bandits paid from the camp; company
## desertion; save/load round trip and old-save migration.

var fails := 0
var _base := ""

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_save_army_%d.json" % OS.get_process_id()
	# One generated world, reloaded between sections. A fresh new_game per check was most of the 93 s.
	_base = "user://test_econ_army_base_%d.json" % OS.get_process_id()
	var keep := Game.SAVE_PATH
	Game.SAVE_PATH = _base
	Game.new_game(5150)
	Game.save_game()
	Game.SAVE_PATH = keep
	_test_families_on_map()
	_test_caps()
	_test_pay_conserved()
	_test_unpaid_and_desertion()
	_test_orc_cascade()
	_test_fight_speed()
	_test_rules()
	_test_renown()
	_test_supplies()
	_test_bandits_and_company()
	_test_days_run()
	_test_save_and_migration()
	_test_draft()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_base))
	return fails

func _fresh() -> void:
	var keep := Game.SAVE_PATH
	Game.SAVE_PATH = _base
	Game.world = {}
	var ok := Game.load_game()
	Game.SAVE_PATH = keep
	check(ok, "could not reload the army test world")
	Game.company.clear()

func _units_without_family(w: Dictionary) -> Array:
	var bad := []
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if Monsters.is_monster_band(wb) or Monsters.is_monster_faction(wb["faction"]):
			continue
		for u in wb["units"]:
			if u.dead or u.race_def().get("creature", false):
				continue
			var f := People.fam_of(w["towns"].get(u.home_town, {}), u.family)
			if f.is_empty():
				bad.append("%s %s (%s)" % [wb["kind"], u.name, wb["faction"]])
	return bad

## Explicit fixture transfers: coins and household food change owners, never appear.
func _move_cash(source: Dictionary, source_key: String, dest: Dictionary, dest_key: String, amount: float) -> float:
	var moved := minf(maxf(0.0, amount), maxf(0.0, float(source.get(source_key, 0.0))))
	source[source_key] = float(source.get(source_key, 0.0)) - moved
	dest[dest_key] = float(dest.get(dest_key, 0.0)) + moved
	return moved

func _fund_faction(fid: String, target: float) -> void:
	var w: Dictionary = Game.world
	var fac: Dictionary = w["factions"][fid]
	for town in w["towns"].values():
		if TownEcon.has_econ(town):
			_move_cash(town["econ"], "treasury", fac, "treasury", target - float(fac["treasury"]))
	check(float(fac["treasury"]) >= target, "%s: fixture could not transfer enough existing coin" % fid)

func _empty_faction(fid: String) -> void:
	var w: Dictionary = Game.world
	var fac: Dictionary = w["factions"][fid]
	var dest: Dictionary = w["towns"][fac["towns"][0]]["econ"]
	_move_cash(fac, "treasury", dest, "treasury", float(fac["treasury"]))
	_move_cash(fac, "loot", dest, "treasury", float(fac.get("loot", 0.0)))

## Garrison enlist draws the nearest town of the race spawn_warband just made.
## A roaming gang is factory-human, so it draws the nearest human town. Those are
## often not the same town. Outlaw draw also refuses a fed household and a zero food price.
func _nearest_econ_town(w: Dictionary, pos: Vector2, race: String = "") -> Dictionary:
	var nearest: Dictionary = {}
	var distance := INF
	for t in w["towns"].values():
		if not TownEcon.has_econ(t):
			continue
		if race != "" and String(TownEcon.culture_of(t["econ"]).get("race", "")) != race:
			continue
		var d: float = (t["pos"] as Vector2).distance_squared_to(pos)
		if d < distance:
			distance = d
			nearest = t
	return nearest

func _garrison_town(w: Dictionary, l: Dictionary) -> Dictionary:
	var tid := CampaignWorld.nearest_faction_town(w, "outlaws", l["pos"])
	var home: Dictionary = w["towns"].get(tid, {})
	var race := String(DB.factions.get("outlaws", {}).get("race", "human"))
	if TownEcon.has_econ(home):
		race = String(TownEcon.culture_of(home["econ"]).get("race", race))
	return _nearest_econ_town(w, l["pos"], race)

## How many people this household can send once its purse and stored meals are moved away.
## Mirrors People.outlaw_value: spare hands, a real food price, and a wage below the camp's pay.
func _outlaw_draws(e: Dictionary, f: Dictionary, pay: float) -> int:
	if f.get("gone", false) or f.get("estate", false) or Population.spare(f) <= 0:
		return 0
	var rate := float(Families.daily_rates(e, f)["food"])
	if rate <= 0.0 or float(e.get("price", {}).get("grain", 1)) <= 0.0:
		return 0
	var jobs := Persons.work(e, f)
	var n := 0
	for p in Persons.pp(f):
		if int(p[6]) != 0 or String(p[4]) != "" or int(p[5]) >= 0:
			continue
		var job: Dictionary = jobs.get(int(p[0]), {})
		if job.get("keeper", false) or pay - float(job.get("wage", 0.0)) <= 0.0:
			continue
		n += 1
	if Population.is_cohort(f) and int(f.get("idle", 0)) > 0:
		n += Population.eligible_slots(e, f, float(e.get("day", 0)))
	return mini(n, Population.spare(f))

## Draws left after one household is kept to hold the transferred purse and meals.
func _count_ready(town: Dictionary, pay: float) -> int:
	if town.is_empty():
		return 0
	var e: Dictionary = town["econ"]
	var donors: Array = []
	for f in e["fams"]:
		if _outlaw_draws(e, f, pay) > 0:
			donors.append(f)
	var receiver := false
	for f in e["fams"]:
		if donors.has(f) or f.get("gone", false) or f.has("estate") or Families.people(f) <= 0:
			continue
		if float(Families.daily_rates(e, f)["food"]) <= 0.0:
			continue
		receiver = true
		break
	if not receiver and donors.size() > 1:
		donors.sort_custom(func(a, b): return _outlaw_draws(e, a, pay) < _outlaw_draws(e, b, pay))
		donors.pop_front()
	elif not receiver:
		return 0
	var n := 0
	for f in donors:
		n += _outlaw_draws(e, f, pay)
	return n

## Moves volunteers' savings and meals to one household that is not itself a donor.
## Returns how many draws remain. Physical town stock, barns and the cash total stay put.
func _prepare_outlaws(town: Dictionary, pay: float) -> int:
	if town.is_empty():
		return 0
	var e: Dictionary = town["econ"]
	var donors: Array = []
	for f in e["fams"]:
		if _outlaw_draws(e, f, pay) > 0:
			donors.append(f)
	var receiver: Dictionary = {}
	for f in e["fams"]:
		if donors.has(f) or f.get("gone", false) or f.has("estate") or Families.people(f) <= 0:
			continue
		if float(Families.daily_rates(e, f)["food"]) <= 0.0:
			continue
		receiver = f
		break
	if receiver.is_empty() and donors.size() > 1:
		donors.sort_custom(func(a, b): return _outlaw_draws(e, a, pay) < _outlaw_draws(e, b, pay))
		receiver = donors.pop_front()
	if receiver.is_empty():
		return 0
	var cash0 := float(receiver.get("purse", 0.0))
	var recv_rate := float(Families.daily_rates(e, receiver)["food"])
	var food0 := float(receiver["store"]["food"]) * recv_rate
	for f in donors:
		cash0 += float(f.get("purse", 0.0))
		food0 += float(f["store"]["food"]) * float(Families.daily_rates(e, f)["food"])
		_move_cash(f, "purse", receiver, "purse", float(f.get("purse", 0.0)))
		var meals := float(f["store"]["food"]) * float(Families.daily_rates(e, f)["food"])
		if recv_rate > 0.0:
			receiver["store"]["food"] = float(receiver["store"]["food"]) + meals / recv_rate
		f["store"]["food"] = 0.0
	check(absf(float(receiver["purse"]) - cash0) < 0.01, "outlaw setup created or lost savings")
	check(absf(float(receiver["store"]["food"]) * recv_rate - food0) < 0.0001, "outlaw setup created or lost household meals")
	var left := 0
	for f in donors:
		left += _outlaw_draws(e, f, pay)
	return left

func _funded_camp() -> String:
	var w: Dictionary = Game.world
	var pay := float(Army.A()["wage"]["bandit"])
	var lid := ""
	var garrison: Dictionary = {}
	var human: Dictionary = {}
	var best := -1
	var best_note := "no bandit camp"
	for key in w["lairs"]:
		var l: Dictionary = w["lairs"][key]
		if l.get("kind", "") != "bandit_camp":
			continue
		var gtown := _garrison_town(w, l)
		var htown := _nearest_econ_town(w, l["pos"], "human")
		if gtown.is_empty() or htown.is_empty():
			best_note = "a camp has no town of the race its recruiters draw"
			continue
		# Subscript is a Variant, so := cannot infer .has(). A typed Dictionary makes the call a bool.
		var bands: Dictionary = w["warbands"]
		var resident: bool = bands.has(String(l.get("resident", "")))
		var shared := String(gtown.get("id", "")) == String(htown.get("id", ""))
		# Count without moving coin yet: one household is kept to receive the transfers.
		var g_n := _count_ready(gtown, pay)
		var h_n := g_n if shared else _count_ready(htown, pay)
		# The garrison asks for 3 and the gang for up to 6. One spare past the garrison
		# is enough for the gang when both draw the same town; a resident garrison needs only the gang.
		var need_g := 0 if resident else (4 if shared else 1)
		var need_h := 1 if resident or not shared else 4
		var score := g_n + h_n
		if g_n >= need_g and h_n >= need_h and score > best:
			best = score
			lid = key
			garrison = gtown
			human = htown
		elif best < 0:
			best_note = "nearest camp can ready %d garrison draws and %d human draws" % [g_n, h_n]
	check(lid != "", "no camp near enough genuine free outlaw volunteers (%s)" % best_note)
	if lid == "":
		return ""
	var ready_g := _prepare_outlaws(garrison, pay)
	var ready_h := ready_g if String(garrison.get("id", "")) == String(human.get("id", "")) else _prepare_outlaws(human, pay)
	check(ready_g > 0 or w["warbands"].has(String(w["lairs"][lid].get("resident", ""))), "preparing the garrison town left nobody the camp will take")
	check(ready_h > 0, "preparing the human town left nobody the gang will take")
	var l: Dictionary = w["lairs"][lid]
	var fac: Dictionary = w["factions"][human["faction"]]
	var target := pay * 20.0 * 14.0
	_fund_faction(String(human["faction"]), target)
	_move_cash(fac, "treasury", l, "gold", maxf(0.0, target - float(l.get("gold", 0))))
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	if not w["warbands"].has(String(l.get("resident", ""))):
		l["resident"] = CampaignWorld.spawn_warband(Game, "outlaws", l["pos"], 3, "camp", rng, {"home": lid, "lair": lid, "anchor": l["pos"]})
	check(w["warbands"].has(String(l.get("resident", ""))), "funded camp did not recruit real resident volunteers")
	var gang := Bandits.spawn_band(Game, lid, rng)
	check(gang != "", "funded camp did not recruit a real roaming gang")
	check(_units_without_family(w).is_empty(), "funded outlaw fixture invented or lost a family link")
	return lid

# ---------------------------------------------------------------- families
func _test_families_on_map() -> void:
	var w: Dictionary = Game.world
	_funded_camp()
	var bad := _units_without_family(w)
	check(bad.is_empty(), "units on the map without a family: %s" % str(bad.slice(0, 6)))
	# outlaws come from towns of their race; deserters from their own town
	var outl := 0
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["kind"] in ["camp", "bandit"]:
			for u in wb["units"]:
				var t: Dictionary = w["towns"][u.home_town]
				check(String(TownEcon.culture_of(t["econ"])["race"]) == u.race, "an outlaw from a town of another race")
				outl += 1
	check(outl > 0, "no outlaws to test")
	# new bands spawned during the campaign: families too, and stores bought at home
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tr0 := float(w["factions"]["orc_horde"]["treasury"])
	var wid2 := CampaignWorld.spawn_faction_band(Game, "orc_horde", rng, true)
	check(_units_without_family(w).is_empty(), "a new band without families")
	check(wid2 != "", "a funded faction could not raise a new band")
	check(wid2 != "" and not Supplies.stores(w["warbands"][wid2]).is_empty() and float(w["factions"]["orc_horde"]["treasury"]) < tr0,
		"a new band set out without stores bought by its realm")
	var dw := Bandits.spawn_deserters(Game, rng)
	if dw != "":
		check(_units_without_family(w).is_empty(), "deserters without families")
	print("  every non-monster unit on the map has a family (%d outlaws checked)" % outl)

# ---------------------------------------------------------------- caps
func _test_caps() -> void:
	check(Army.levels_for(5000, 5, 4) == 4 and Army.caps(4, 5) == [1, 5, 25, 125], "5,000 orcs: 1/5/25/125")
	check(Army.levels_for(24, 5, 4) == 1 and Army.levels_for(25, 5, 4) == 2 and Army.levels_for(4, 5, 4) == 0, "caps follow size (small armies)")
	var prev := 0
	var mono := true
	for n in range(0, 4000, 37):
		var l := Army.levels_for(n, 5, 4)
		if l < prev:
			mono = false
		prev = l
	check(mono, "levels shrink as an army grows")
	# One tree update per realm: the same caps, without six campaign days.
	_fresh()
	var w: Dictionary = Game.world
	for fid in Army.state(w)["f"]:
		Army.update_tree(Game, fid, Army.members(Game, fid), false, int(Game.day))
	for fid in Army.state(w)["f"]:
		var r: Dictionary = Army.state(w)["f"][fid]
		var n := Army.members(Game, fid).size()
		var cul := Army.cul_of_faction(fid)
		var span := int(cul["span"])
		check(int(r["levels"]) == Army.levels_for(n, span, (cul["ranks"]["army"] as Array).size() - 2), "%s: levels %d for %d men" % [fid, int(r["levels"]), n])
		for row in Army.tree_rows(Game, fid):
			if int(row["cap"]) >= 0:
				check(int(row["count"]) <= int(row["cap"]), "%s: %d %s over the cap %d" % [fid, int(row["count"]), row["title"], int(row["cap"])])
		var holders := {}
		for uid in r["posts"]:
			if int(uid) >= 0:
				check(not holders.has(uid), "%s: a man holds two posts" % fid)
				holders[uid] = true
		print("  %s: %d men, %s" % [fid, n, ", ".join(PackedStringArray(Army.tree_rows(Game, fid).map(func(x): return "%s %d%s" % [x["title"], int(x["count"]), "/%d" % int(x["cap"]) if int(x["cap"]) >= 0 else ""])))])

# ---------------------------------------------------------------- pay
func _family_gold(w: Dictionary, units: Array) -> float:
	var seen := {}
	var g := 0.0
	for u in units:
		var k := "%s|%d" % [u.home_town, u.family]
		if seen.has(k):
			continue
		seen[k] = true
		g += float(People.fam_of(w["towns"][u.home_town], u.family)["purse"])
	return g

func _tills(w: Dictionary) -> float:
	var g := 0.0
	for tid in w["towns"]:
		var e: Dictionary = w["towns"][tid]["econ"]
		g += float(e["biz"][int(e["mkt"])]["till"])
	return g

func _test_pay_conserved() -> void:
	_fresh()
	var w: Dictionary = Game.world
	for fid in ["middle_kingdom", "orc_horde"]:
		var units := Army.members(Game, fid)
		var fac: Dictionary = w["factions"][fid]
		_fund_faction(fid, 100000.0)
		var t0 := float(fac["treasury"]) + float(fac.get("loot", 0.0))
		var p0 := _family_gold(w, units)
		var m0 := _tills(w)
		var gone0 := TownEcon.gold_gone
		var cul := Army.cul_of_faction(fid)
		var order := units.duplicate()
		var res := Army.pay_units(Game, order, {"kind": "faction", "fac": fac}, "army", cul)
		var t1 := float(fac["treasury"]) + float(fac.get("loot", 0.0))
		var p1 := _family_gold(w, units)
		var m1 := _tills(w)
		var out := t0 - t1
		var into := (p1 - p0) + (m1 - m0)
		check(out > 0.0 and absf(out - into) < 0.01, "%s: wage gold not conserved: %.2f left the treasury, %.2f reached purses and tills" % [fid, out, into])
		check(int(res["unpaid"]) == 0 and absf(float(res["paid"]) - float(res["bill"])) < 1.0, "%s: a full treasury did not pay the whole bill" % fid)
		print("  %s pays %d men %.1f gold a day: purses +%.1f, market tills +%.1f (kind)" % [fid, units.size(), float(res["bill"]), p1 - p0, m1 - m0])
	# coinage (docs/specs/barge/05-coinage.md section 4): every soldier of every race is paid in coins now; orcs too:
	# the pay reaches the family purse, no goods move
	var ou := Army.members(Game, "orc_horde")
	var u0: Unit = ou[0]
	var e: Dictionary = w["towns"][u0.home_town]["econ"]
	var g0 := int(e["stock"]["grain"]) + int(e["hh"].get("grain", 0))
	var of: Dictionary = People.fam_of(w["towns"][u0.home_town], u0.family)
	var pp0 := float(of["purse"])
	var r0 := Army.pay_units(Game, [u0], {"kind": "faction", "fac": w["factions"]["orc_horde"]}, "army", Army.cul_of_faction("orc_horde"))
	check(int(e["stock"]["grain"]) + int(e["hh"].get("grain", 0)) == g0, "coin pay: grain appeared or vanished")
	check(float(r0["paid"]) > 0.0 and absf(float(of["purse"]) - pp0 - float(r0["paid"])) < 0.01, "orc pay did not reach the family purse in coins")
	# the militia: the town treasury pays by rank (guard in cities)
	for tid in w["militia"]:
		var town: Dictionary = w["towns"][tid]
		var tr := float(town["econ"]["treasury"])
		var paid := Army.pay_town(Game, town)
		check(paid <= 0.0 or float(town["econ"]["treasury"]) < tr, "militia pay did not come from the treasury")
		break

# ---------------------------------------------------------------- unpaid -> desertion
func _watched_soldiers(fid: String) -> Array:
	var out: Array = []
	for u in Army.members(Game, fid):
		var home: Dictionary = Game.world["towns"].get(u.home_town, {})
		var f := People.fam_of(home, u.family)
		if f.is_empty() or f.get("gone", false):
			continue
		out.append(u)
	return out

func _still_serving(fid: String, u: Unit) -> bool:
	for m in Army.members(Game, fid):
		if m.uid == u.uid:
			return true
	return false

func _test_unpaid_and_desertion() -> void:
	_fresh()
	var w: Dictionary = Game.world
	var fid := "northern_clans"
	var watched := _watched_soldiers(fid)
	check(not watched.is_empty(), "no northern army to test")
	var fams := {}
	for u in watched:
		var f := People.fam_of(w["towns"][u.home_town], u.family)
		fams[u.uid] = [f, int(f["serve"].get("army", 0))]
	_empty_faction(fid)
	var dd := int(Army.A()["desert_days"])
	for d in dd - 1:
		Army.faction_day(Game, fid, int(Game.day) + 1 + d)
		# Pay runs before the tree calls nobles up. New men are not yet unpaid.
		# A man with nobody at home serves for his keep and stays at 0.
		var timer_ok := true
		var still := 0
		for u in watched:
			if not _still_serving(fid, u):
				continue
			still += 1
			if u.unpaid_days != d + 1:
				timer_ok = false
		check(timer_ok and still > 0, "day %d: unpaid soldiers without the desertion timer running" % (d + 1))
		for wid in w["warbands"]:
			var wb: Dictionary = w["warbands"][wid]
			if wb["faction"] != fid or not Army.is_field(wb):
				continue
			var unpaid := 0
			for u in wb["units"]:
				if not u.dead and u.unpaid_days > 0:
					unpaid += 1
			check(int(wb.get("unpaid_n", 0)) == unpaid, "a band's unpaid count is wrong")
	Army.faction_day(Game, fid, int(Game.day) + dd)
	var deserted := 0
	for u in watched:
		if not _still_serving(fid, u):
			deserted += 1
	check(deserted == watched.size(), "unpaid soldiers did not desert after %d days (%d of %d still out)" % [dd, watched.size() - deserted, watched.size()])
	var home := 0
	for uid in fams:
		var f: Dictionary = fams[uid][0]
		if int(f["serve"].get("army", 0)) < int(fams[uid][1]):
			home += 1
	check(home > 0, "deserters did not come home to their families")
	var evs := 0
	for uid in fams:
		for ev in fams[uid][0].get("ev", []):
			if ev[1] == "deserted":
				evs += 1
				break
	check(evs > 0, "no 'deserted' history event")
	# paid again: the timer resets. Call-ups added after the empty day are already at 0.
	_fresh()
	w = Game.world
	_empty_faction(fid)
	Army.faction_day(Game, fid, 1)
	# Restoring pay must cover unsigned men's real call-up payment first, then
	# today's wages. The failed zero-fund day left those sign-on claims pending.
	# Recompute from current rank/kit rather than the previous day's cached bill.
	var restored_units := Army.members(Game, fid)
	var signed: Dictionary = Army.state(w).get("signed", {})
	var sign_range: Array = Army.A().get("sign_on", [1.5, 2.5])
	var low := Army.low_officer(restored_units, "army")
	var daily_bill := 0.0
	var pending_sign_on := 0.0
	var unsigned := 0
	for man in restored_units:
		daily_bill += Army.wage("army", man.rank, low, man)
		var household := People.fam_of(w["towns"].get(man.home_town, {}), man.family)
		if signed.has(str(man.uid)) or household.is_empty() or household["gone"]: continue
		var share := float(absi(hash([man.uid, "signon"])) % 1000) / 1000.0
		pending_sign_on += Army.wage("army", man.rank, -1, man) * lerpf(float(sign_range[0]), float(sign_range[1]), share)
		unsigned += 1
	# The transfer uses existing coins. Whole-coin rounding avoids different
	# payment/summation order leaving a final fractional claim just unfunded.
	var restored_budget := ceilf(daily_bill + pending_sign_on)
	print("  restored army funding: daily %.3f, pending sign-on %.3f for %d real men, transfer target %.0f (old two-bill target %.3f)" %
		[daily_bill, pending_sign_on, unsigned, restored_budget, Army.bill(Game, fid) * 2.0])
	_fund_faction(fid, restored_budget)
	Army.faction_day(Game, fid, 2)
	check(Army.members(Game, fid).all(func(u): return u.unpaid_days == 0), "paid men still count unpaid days")

# ---------------------------------------------------------------- orc cascade
func _orc_army(n: int) -> Array:
	var w: Dictionary = Game.world
	for wid in w["warbands"].keys():
		if w["warbands"][wid]["faction"] == "orc_horde" and Army.is_field(w["warbands"][wid]):
			for u in w["warbands"][wid]["units"]:
				if not u.dead:
					Army.release(Game, u, "fled")
			CampaignWorld.remove_warband(Game, wid)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var units := []
	var per := 10
	for home in w["factions"]["orc_horde"]["towns"]:
		while units.size() < n:
			var k := mini(per, n - units.size())
			var wid := CampaignWorld.spawn_warband(Game, "orc_horde", w["towns"][home]["pos"], k, "raider", rng, {"home": home})
			if wid == "": break   # this town cannot spare any more real people
			for u in w["warbands"][wid]["units"]:
				u.battles = 1
				u.rank = 1
				units.append(u)
		if units.size() >= n: break
	return units

func _test_orc_cascade() -> void:
	_fresh()
	var cultures: Dictionary = TownEcon.data()["cultures"]
	var original: Dictionary = cultures["orc"]
	var cul: Dictionary = original.duplicate(true)
	cul["span"] = 2   # [test] a narrow tree so a 40-orc army has all four officer levels
	cultures["orc"] = cul   # replace for this scenario; never mutate the original culture dictionary
	_orc_cascade_scenario(cul)
	# Caller restoration also runs if the scenario itself aborts with a script error.
	cultures["orc"] = original

func _orc_cascade_scenario(cul: Dictionary) -> void:
	var w: Dictionary = Game.world
	var units := _orc_army(40)
	check(units.size() == 40, "cascade needs 40 real recruits, raised %d" % units.size())
	if units.size() != 40:
		return
	# Commoners cannot hold posts. Call the realm's own nobles into the field, then fill.
	for _call in 8:
		if Army.call_up_nobles(Game, "orc_horde", 10).is_empty():
			break
	var nobles := 0
	for u in Army.members(Game, "orc_horde"):
		if Army.house_born(u):
			nobles += 1
	if nobles < 15:
		check(false, "orc houses fielded %d nobles; a span-2 tree of 15 posts needs house-born officers" % nobles)
		return
	Army.rec(w, "orc_horde")["posts"] = []
	Army.rec(w, "orc_horde")["levels"] = 0
	Army.rec(w, "orc_horde")["fights"] = []
	Army.update_tree(Game, "orc_horde", Army.members(Game, "orc_horde"), true, 0)
	var r: Dictionary = Army.rec(w, "orc_horde")
	var posts: Array = r["posts"]
	var full := int(r["levels"]) == 4 and posts.size() == 15 and posts.all(func(x): return int(x) >= 0)
	check(full, "orc tree not full: levels %d, posts %s" % [int(r["levels"]), str(posts)])
	if not full:
		return
	var by := {}
	for u in Army.members(Game, "orc_horde"):
		by[u.uid] = u
	var before := posts.duplicate()
	var wb_uid := int(posts[1])   # a warboss
	check(by.has(wb_uid), "cascade warboss does not belong to the actual recruited army")
	if not by.has(wb_uid):
		return
	var warboss: Unit = by[wb_uid]
	warboss.dead = true
	Army._bury(Game, warboss)
	var hist0 := (r["hist"] as Array).size()
	var t0 := Time.get_ticks_usec()
	Army.faction_day(Game, "orc_horde", int(Game.day) + 1)
	var duels := 0
	while not (r["fights"] as Array).is_empty() and duels < 60:
		Army.fight_step(Game, "orc_horde")
		duels += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	posts = r["posts"]
	var span := 2
	# the warboss post went to one of the big bosses under him; that big boss post to a boss; that boss post to a blooded
	var nb: int = int(posts[1])
	var lv1_ok := nb >= 0 and [int(before[3]), int(before[4])].has(nb)
	check(lv1_ok, "the warboss post did not go to one of his big bosses (%d)" % nb)
	var bb_post: int = [3, 4][[int(before[3]), int(before[4])].find(nb)] if lv1_ok else -1
	var nbb: int = int(posts[bb_post]) if bb_post >= 0 else -1
	var kids: Array = Army.children_of(bb_post, span, 4) if bb_post >= 0 else []
	var bosses: Array = kids.map(func(c): return int(before[c]))
	check(nbb >= 0 and bosses.has(nbb), "the big boss post did not go to one of his bosses")
	var boss_post: int = kids[bosses.find(nbb)] if nbb >= 0 and bosses.has(nbb) else -1
	var nboss: int = int(posts[boss_post]) if boss_post >= 0 else -1
	check(nboss >= 0 and not before.has(nboss) and by.has(nboss) and (by[nboss] as Unit).rank == 2, "the boss post did not go to a blooded")
	var by_fight := 0
	for l in (r["hist"] as Array).slice(hist0):
		if String(l).contains(" post"):
			by_fight += 1
	check(by_fight >= 3, "the cascade was not decided by fights (%d fight lines)" % by_fight)
	var cp := Army.caps(int(r["levels"]), span)
	var ok := true
	for k in cp.size():
		var c := 0
		for i in range(Army.offset(k, span), Army.offset(k + 1, span)):
			if int(posts[i]) >= 0:
				c += 1
		ok = ok and c <= int(cp[k])
	var rank_ok := true
	for u in Army.members(Game, "orc_horde"):
		var p := posts.find(u.uid)
		if p >= 0 and u.rank != Army.rank_at(Army.level_of(p, span), cul["ranks"]["army"]):
			rank_ok = false
		if p < 0 and u.rank >= 2:
			rank_ok = false
	check(ok and rank_ok, "counts or ranks invalid after the cascade")
	print("  orc cascade: %d duels in the sim, %.1f ms; %s" % [duels, ms, " | ".join(PackedStringArray((r["hist"] as Array).slice(hist0)))])

func _test_fight_speed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var times := []
	var ticks := []
	for i in 20:
		var a := Factory.make_troop(rng, "orc_horde", Factory.pick_troop(rng, "orc_horde"))
		var b := Factory.make_troop(rng, "orc_horde", Factory.pick_troop(rng, "orc_horde"))
		var res := Army.duel(a, b, 1000 + i)
		times.append(float(res["ms"]))
		ticks.append(int(res["ticks"]))
	times.sort()
	var mean := 0.0
	for t in times:
		mean += t
	mean /= times.size()
	print("  succession fight (orc duel, tiny map, story off): mean %.2f ms, median %.2f, worst %.2f ms (gate 10 ms); ticks %s" % [mean, times[times.size() / 2], times[-1], str(ticks)])
	check(times[times.size() / 2] < 10.0, "a succession fight takes over 10 ms (median %.2f)" % times[times.size() / 2])

# ---------------------------------------------------------------- the other rules
func _test_rules() -> void:
	_fresh()
	var w: Dictionary = Game.world
	for fid in ["middle_kingdom", "northern_clans", "goblin_warren", "moon_court"]:
		var units := Army.members(Game, fid)
		if units.is_empty():
			continue
		# A fresh field army can have an empty top post until the tree seats a house-born officer.
		Army.update_tree(Game, fid, units, false, int(Game.day))
		units = Army.members(Game, fid)
		var r: Dictionary = Army.rec(w, fid)
		if int(r["levels"]) <= 0 or (r["posts"] as Array).is_empty():
			print("  %s: no officer posts for %d men" % [fid, units.size()])
			continue
		var by := {}
		for u in units:
			by[u.uid] = u
		var top: Unit = by.get(int(r["posts"][0]), null)
		if top == null:
			print("  %s: no house-born war leader seated" % fid)
			continue
		var cands: Array = ArmyRanks.candidates(Game, fid, 0, by, false)
		top.dead = true
		Army._bury(Game, top)
		by.erase(top.uid)
		Army.faction_day(Game, fid, int(Game.day) + 1)
		var nt := int(r["posts"][0]) if not (r["posts"] as Array).is_empty() else -1
		if nt < 0 or nt == top.uid:
			# Cunning can fill a lower post the same day the top has nobody left to take it.
			var still: Array = ArmyRanks.candidates(Game, fid, 0, by, false)
			check(cands.is_empty() or still.is_empty(), "%s (%s): the top post stayed empty" % [fid, Army.cul_of_faction(fid)["rank_rule"]])
		else:
			check(nt != top.uid, "%s (%s): the top post stayed with the dead leader" % [fid, Army.cul_of_faction(fid)["rank_rule"]])
		print("  %s (%s): %s" % [fid, Army.cul_of_faction(fid)["rank_rule"], String((r["hist"] as Array)[-1]) if not (r["hist"] as Array).is_empty() else "-"])
	# renown weighs in the weighted rules
	var a := Factory.make_troop(RandomNumberGenerator.new(), "middle_kingdom", Factory.pick_troop(RandomNumberGenerator.new(), "middle_kingdom"))
	var s0 := RankRules.score(Game, "politics", a, "middle_kingdom")
	a.renown = 40.0
	check(RankRules.score(Game, "politics", a, "middle_kingdom") > s0 + 10.0, "renown does not weigh in a rank rule")

# ---------------------------------------------------------------- renown
func _test_renown() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var k := Factory.make_troop(rng, "middle_kingdom", Factory.pick_troop(rng, "middle_kingdom"))
	var v := Factory.make_troop(rng, "orc_horde", Factory.pick_troop(rng, "orc_horde"))
	v.rank = 4   # a big boss
	v.renown = 20.0
	Renown.on_kill(k, v)
	var want := float(Army.A()["kill_worth"][4]) + 0.25 * 20.0
	check(absf(k.renown - want) < 0.01 and k.notable.size() == 1, "kill renown %.2f (want %.2f)" % [k.renown, want])
	var wolf := Creatures.make(rng, "wolf", "beasts")
	Renown.on_kill(k, wolf)
	check(absf(k.renown - want - 1.0) < 0.01, "a wolf is worth 1")
	check(String(k.notable[0][0]) == v.name, "notable kills best first")
	# the sim calls it: a real duel's killer gains renown
	var got := false
	for i in 30:
		var a := Factory.make_troop(rng, "orc_horde", Factory.pick_troop(rng, "orc_horde"))
		var b := Factory.make_troop(rng, "orc_horde", Factory.pick_troop(rng, "orc_horde"))
		Army.duel(a, b, 500 + i)
		if a.renown > 0.0 or b.renown > 0.0:
			got = true
			break
	check(got, "no kill renown from sim kills")
	check(Renown.lines(k).size() == 3, "unit card renown lines")

# ---------------------------------------------------------------- force stores
func _test_supplies() -> void:
	_fresh()
	var w: Dictionary = Game.world
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	# AI winner takes the loser's stores up to what it can carry; the rest is lost; nothing appears
	# (staged: the start town has sent all the men it can spare by now, war pick 4; these two are a scene)
	var a := CampaignWorld.spawn_warband(Game, "orc_horde", w["party"]["pos"] + Vector2(400, 0), 6, "raider", rng, {"staged": true})
	var b := CampaignWorld.spawn_warband(Game, "middle_kingdom", w["party"]["pos"] + Vector2(400, 0), 3, "patrol", rng, {"staged": true})
	var wa: Dictionary = w["warbands"][a]
	var wbb: Dictionary = w["warbands"][b]
	wa["stores"] = {"grain": 10}
	wbb["stores"] = {"grain": 300, "beer": 100, "meat": 40}
	var before := {"grain": 310, "beer": 100, "meat": 40}
	var got := Supplies.take(wa, wbb)
	var kg := Supplies.weight(wa["stores"])
	check(kg <= Supplies.capacity(Supplies.men(wa)) + 0.01, "the winner carries more than it can")
	check(not got.is_empty() and (wbb["stores"] as Dictionary).is_empty(), "the AI winner took nothing / the loser kept its stores")
	var conserved := true
	for g in before:
		var have := int(wa["stores"].get(g, 0))
		if have > int(before[g]):
			conserved = false
	check(conserved, "stores appeared from nowhere in the take")
	print("  AI winner took %s (carry %.0f kg)" % [Supplies.text(got), Supplies.capacity(Supplies.men(wa))])
	# An unraised company has no carriers, so company_take moves nothing. Raise a real handful first.
	var seat := DevTools.choose_house(Game)
	var raised := DevTools.raise_army(Game, seat, 4) if seat != "" else 0
	check(raised > 0, "the company has nobody to carry taken stores")
	var meals0 := Food.stock(Game, "meal")
	var beer0 := Food.stock(Game, "beer")
	wbb["stores"] = {"grain": 30, "beer": 12}
	Game.pending_battle = {"warband_id": b}
	var res := {"winner": 0, "player_units": [], "enemy_units": wbb["units"]}
	CampaignWorld.on_battle_result(Game, res)
	check(Food.stock(Game, "meal") == meals0 + int(res.get("supplies_taken", {}).get("grain", 0)) and int(res.get("supplies_taken", {}).get("grain", 0)) > 0,
		"a company win did not add the beaten band's food to the provisions")
	check(Food.stock(Game, "beer") == beer0 + int(res["supplies_taken"].get("beer", 0)), "beer taken not in the provisions")
	# the company loses: its own stores stay whole
	var meals1 := Food.stock(Game, "meal")
	var beer1 := Food.stock(Game, "beer")
	Game.pending_battle = {"warband_id": a}
	CampaignWorld.on_battle_result(Game, {"winner": 1, "player_units": [], "enemy_units": wa["units"]})
	check(Food.stock(Game, "meal") == meals1 and Food.stock(Game, "beer") == beer1, "the company lost its stores to an AI winner")
	# bands eat and restock from home (the realm pays the market; the goods leave the town's books as used)
	var c := CampaignWorld.spawn_faction_band(Game, "middle_kingdom", rng, true)
	check(c != "", "provisioning fixture could not raise a real band")
	if c == "": return
	var wc: Dictionary = w["warbands"][c]
	# provisioning is a real purchase: the town's stock falls by what the stores gain, the realm pays the till
	var e: Dictionary = w["towns"][wc["home"]]["econ"]
	# Return the actual opening purchase before testing a fresh provisioning pass.
	# The mess was counted as used when bought; its return reverses that entry.
	for good in Supplies.stores(wc):
		var returned := int(wc["stores"][good])
		e["stock"][good] = int(e["stock"].get(good, 0)) + returned
		TownEcon.led(e, "used", good, -returned)
	wc["stores"] = {}
	var fac: Dictionary = w["factions"]["middle_kingdom"]
	_fund_faction("middle_kingdom", 5000.0 * TownEcon.COIN)
	var treasury0 := float(fac["treasury"])
	var st0 := int(e["stock"]["grain"]) + int(e["stock"]["meat"]) + int(e["stock"]["fruit"]) + int(e["stock"]["beer"]) + int(e["stock"]["wine"])
	var till0 := float(e["biz"][int(e["mkt"])]["till"])
	Supplies.provision(Game, wc, {"kind": "faction", "fac": fac})
	var st1 := int(e["stock"]["grain"]) + int(e["stock"]["meat"]) + int(e["stock"]["fruit"]) + int(e["stock"]["beer"]) + int(e["stock"]["wine"])
	var sum := 0
	for g in wc["stores"]:
		sum += int(wc["stores"][g])
	check(sum > 0 and st0 - st1 == sum, "provisioning not conserved: stock -%d, stores +%d" % [st0 - st1, sum])
	check(absf((treasury0 - float(fac["treasury"])) - (float(e["biz"][int(e["mkt"])]["till"]) - till0)) < 0.01, "provisioning coin not conserved")
	var d0 := Supplies.days(wc)
	Supplies.eat(wc)
	check(Supplies.days(wc) < d0 or d0 == 0.0, "a band did not eat its stores")

# ---------------------------------------------------------------- bandits, company
func _test_bandits_and_company() -> void:
	_fresh()
	var w: Dictionary = Game.world
	var lid := _funded_camp()
	check(lid != "", "no bandit camp")
	if lid != "":
		var l: Dictionary = w["lairs"][lid]
		var camp_gold0 := float(l["gold"])
		var men := []
		for wid in [String(l["resident"])] + Bandits.bands_of(Game, lid):
			if w["warbands"].has(wid): men.append_array(w["warbands"][wid]["units"])
		check(not men.is_empty(), "no real camp men to test pay")
		var p0 := _family_gold(w, men)
		Army.camps_day(Game)
		var purse_gain := _family_gold(w, men) - p0
		check(float(l["gold"]) < camp_gold0 and purse_gain > 0.0, "the camp did not pay its men into their family purses")
		check(absf(camp_gold0 - float(l["gold"]) - purse_gain) < 0.01, "camp wages did not conserve coin")
		# broke camp with nothing to fence: gangs scatter after scatter_days
		var dest: Dictionary = w["towns"][CampaignWorld.nearest_town(w, l["pos"])]
		_move_cash(l, "gold", dest["econ"], "treasury", float(l["gold"]))
		(dest["shop"] as Array).append_array(l["stock"])
		l["stock"] = []
		var gangs := Bandits.bands_of(Game, lid)
		check(not gangs.is_empty(), "no recruited roaming gang to test scattering")
		for i in int(Army.A()["scatter_days"]) + 1:
			Army.camps_day(Game)
		check(Bandits.bands_of(Game, lid).is_empty(), "unpaid bandit gangs did not scatter")
	# A new campaign does not start with a company. Raise one real soldier, then send him home.
	var seat := DevTools.choose_house(Game)
	var raised := DevTools.raise_army(Game, seat, 1) if seat != "" else 0
	check(raised == 1 and not Game.company.is_empty(), "no real company soldier to test desertion")
	if raised != 1 or Game.company.is_empty():
		return
	var u: Unit = Game.company[0]
	var f := People.fam_of(w["towns"].get(u.home_town, {}), u.family)
	var ad := Families.adults(f) if not f.is_empty() else 0
	u.unpaid_days = int(Army.A()["company_desert_days"])
	Army.company_desertion(Game)
	check(not Game.company.has(u), "an unpaid company man did not desert")
	check(f.is_empty() or Families.adults(f) == ad + 1, "the deserter is not back on his family row")

# ---------------------------------------------------------------- family links and the rank panel (no simulated month)
func _test_days_run() -> void:
	_fresh()
	var w: Dictionary = Game.world
	var bad := _units_without_family(w)
	check(bad.is_empty(), "units without a family: %s" % str(bad.slice(0, 6)))
	var host := Control.new()
	ArmyPanel.open(host, "orc_horde")
	var rows: Array = Army.tree_rows(Game, "middle_kingdom")
	if not rows.is_empty():
		var offs: Array = rows[0]["officers"]
		if not offs.is_empty():
			ArmyPanel.record(host, offs[0])
	check(host.get_child_count() >= 1, "the rank tree panel did not open")
	for wid in w["warbands"]:
		ArmyPanel.band_line(w["warbands"][wid])
	host.free()
	print("  month-long army frame gate retired; the 23 ms sample was one map frame of a full month and was not retested")

# ---------------------------------------------------------------- save / load
# ---------------------------------------------------------------- war pick 4: the draft
## An army takes only real free people of its home town aged 17-30 (race-scaled), labourers first, never a hand
## the family land or herd needs; when the town can spare too few the band is smaller, when none it is not raised;
## no family is ever made up for it. Cohort families also send unnamed draft-age slots, capped by Population.spare.
func _draft_bins(econ: Dictionary, f: Dictionary, day: float) -> int:
	var n := 0
	var window := People.draft_ages(String(f.get("race", Persons.race_of(econ))))
	for key in f.get("age_bins", {}):
		if Population.bin_category(econ, f, String(key), day) >= 2:
			continue
		var age := int(floor(day / People.year_days())) - int(String(key).split(":")[1])
		if age >= window.x and age <= window.y:
			n += int(f["age_bins"][key])
	return n

func _cohort_raw_tier(c: Dictionary, slot_idx: int) -> int:
	var idle_n := int(c.get("idle", 0))
	var cas_n := int(c.get("casual", 0))
	var job_n := int(c.get("jobs", 0))
	if slot_idx < 0:
		return -1
	if slot_idx < idle_n:
		return 0
	if slot_idx < idle_n + cas_n:
		return 1
	if slot_idx < idle_n + cas_n + job_n:
		return 2
	return -1

func _snapshot_draft_town(e: Dictionary, day: float) -> Dictionary:
	var spare_left := {}
	var bins_left := {}
	var pre_named_kind := {}
	var pre_named_tier := {}
	var pre_cohort := {}
	var next_pid0 := int(e.get("next_pid", 1))
	for f in e["fams"]:
		if f.get("gone", false) or f.has("estate"):
			continue
		var fid := int(f["id"])
		Persons.sync(e, f, day)
		spare_left[fid] = Population.spare(f)
		var wk := People._work_kinds(f)
		var pw := Persons.work(e, f)
		var fam_kinds := {}
		var fam_tiers := {}
		for p in Persons.pp_read(f):
			var pid := int(p[0])
			if wk.has(pid):
				var k := String(wk[pid])
				var wjob: Dictionary = pw.get(pid, {})
				if bool(wjob.get("keeper", false)):
					k = "keeper"
				elif k == "land" and String(wjob.get("kind", "")) == "herd":
					k = "herd"
				fam_kinds[pid] = k
				fam_tiers[pid] = int(People.DRAFT_TIER.get(k, -1))
		pre_named_kind[fid] = fam_kinds
		pre_named_tier[fid] = fam_tiers
		if Population.is_cohort(f):
			var d_bins := _draft_bins(e, f, day)
			bins_left[fid] = d_bins
			var cas := 0
			for ck in f.get("cj", {}):
				cas += int(f["cj"][ck])
			pre_cohort[fid] = {
				"idle": int(f.get("idle", 0)),
				"casual": cas,
				"jobs": Families.job_total(f),
				"hands": int(f.get("hands", 0)),
				"keeps": (f.get("keeps", []) as Array).size(),
				"reserve": maxi(2, int(f.get("hands", 0)) + (f.get("keeps", []) as Array).size()),
				"spare": Population.spare(f),
				"draft_bins": d_bins,
				"bins_remaining": (f.get("age_bins", {}) as Dictionary).duplicate(true),
				"pp_count": Persons.pp_read(f).size(),
				"pool_seen": 0,
				"promoted_taken": 0,
				"total_taken": 0,
			}
	return {
		"spare_left": spare_left,
		"bins_left": bins_left,
		"pre_named_kind": pre_named_kind,
		"pre_named_tier": pre_named_tier,
		"pre_cohort": pre_cohort,
		"next_pid0": next_pid0,
	}

func _resolve_drafted_soldier(e: Dictionary, f: Dictionary, p: Array, day: float, snap: Dictionary) -> Dictionary:
	var fid := int(f.get("id", -1))
	var pid := int(p[0]) if not p.is_empty() else -1
	var next_pid0 := int(snap.get("next_pid0", 1))
	var pre_named_kind: Dictionary = snap.get("pre_named_kind", {})
	var pre_named_tier: Dictionary = snap.get("pre_named_tier", {})
	var pre_cohort: Dictionary = snap.get("pre_cohort", {})
	var fam_kinds: Dictionary = pre_named_kind.get(fid, {})
	var fam_tiers: Dictionary = pre_named_tier.get(fid, {})
	if Population.is_cohort(f) and pid >= next_pid0 and not fam_kinds.has(pid):
		if not pre_cohort.has(fid):
			return {"ok": false, "tier": -1, "kind": "", "promoted": true, "has_snap": false}
		var c: Dictionary = pre_cohort[fid]
		var slot_idx := int(c.get("promoted_taken", 0))
		var total_taken := int(c.get("total_taken", 0))
		c["promoted_taken"] = slot_idx + 1
		c["total_taken"] = total_taken + 1
		var bkey := "%d:%d" % [int(p[2]), int(round(float(p[3]) / People.year_days()))]
		var rem: Dictionary = c.get("bins_remaining", {})
		var bin_ok: bool = int(rem.get(bkey, 0)) > 0 and Population.bin_category(e, f, bkey, day) < 2
		if bin_ok:
			if int(rem[bkey]) <= 1:
				rem.erase(bkey)
			else:
				rem[bkey] = int(rem[bkey]) - 1
		var spare_ok: bool = total_taken < int(c.get("spare", 0)) and slot_idx < int(c.get("draft_bins", 0))
		var raw_tier := _cohort_raw_tier(c, slot_idx)
		var slot_kind := "none" if raw_tier == 0 else ("casual" if raw_tier == 1 else ("job" if raw_tier == 2 else "invalid"))
		var ok_c: bool = bin_ok and spare_ok and raw_tier >= 0
		return {"ok": ok_c, "tier": raw_tier if ok_c else -1, "kind": slot_kind, "promoted": true, "has_snap": true, "slot": slot_idx, "bin_key": bkey}
	if Population.is_cohort(f) and pre_cohort.has(fid):
		var c0: Dictionary = pre_cohort[fid]
		c0["total_taken"] = int(c0.get("total_taken", 0)) + 1
	var has_snap: bool = fam_kinds.has(pid) and fam_tiers.has(pid)
	var kind := String(fam_kinds.get(pid, "")) if has_snap else ""
	var tier := int(fam_tiers.get(pid, -1)) if has_snap else -1
	var ok_n: bool = has_snap and kind != "" and not (kind in ["land", "herd", "keeper"]) and tier >= 0
	return {"ok": ok_n, "tier": tier if ok_n else -1, "kind": kind, "promoted": false, "has_snap": has_snap}

func _test_draft() -> void:
	if _base != "":
		_fresh()
	var w: Dictionary = Game.world
	var town: Dictionary = {}
	for tid in w["towns"]:
		if w["towns"][tid]["faction"] == "middle_kingdom" and TownEcon.has_econ(w["towns"][tid]):
			town = w["towns"][tid]
			break
	if town.is_empty():
		check(false, "no kingdom town to draft")
		return
	var e: Dictionary = town["econ"]
	var ar := People.draft_ages("human")
	check(ar == Vector2i(17, 30), "human draft ages %s, want 17-30" % str(ar))
	print("draft ages: human %s, orc %s, goblin %s, moon elf %s" % [str(ar), str(People.draft_ages("orc")), str(People.draft_ages("goblin")), str(People.draft_ages("moon_elf"))])
	var pool := People.draft_pool(town)
	var tiers := {}
	var day := float(e.get("day", 0))
	var prev := -1
	var snap := _snapshot_draft_town(e, day)
	var spare_left: Dictionary = snap["spare_left"]
	var bins_left: Dictionary = snap["bins_left"]
	var pre_named_kind: Dictionary = snap["pre_named_kind"]
	var pre_named_tier: Dictionary = snap["pre_named_tier"]
	var pre_cohort: Dictionary = snap["pre_cohort"]
	for r in pool:
		tiers[int(r[0])] = int(tiers.get(int(r[0]), 0)) + 1
		check(int(r[0]) >= prev, "draft pool not labourers first")
		prev = int(r[0])
		var fid0 := int(r[2])
		var fam := People.fam_of(town, fid0)
		var race := Persons.family_race(e, fam)
		var window := People.draft_ages(race)
		var pid := int(r[3])
		if pid < 0:
			check(Population.is_cohort(fam), "an unnamed draft slot from a family that is not a cohort")
			check(int(bins_left.get(fid0, 0)) > 0, "an unnamed draft slot the family cannot name")
			var c_pool: Dictionary = pre_cohort.get(fid0, {})
			var seen_idx := int(c_pool.get("pool_seen", 0))
			c_pool["pool_seen"] = seen_idx + 1
			check(_cohort_raw_tier(c_pool, seen_idx) == int(r[0]), "cohort draft pool row tier %d does not match raw pre-draft idle/cj/job slot %d" % [int(r[0]), seen_idx])
		else:
			var p := Persons.by_pid(fam, pid)
			var age := Persons.age_of(p, day)
			check(age >= window.x and age <= window.y, "a %d-year-old in the %s draft pool" % [age, race])
			var fk: Dictionary = pre_named_kind.get(fid0, {})
			var ft: Dictionary = pre_named_tier.get(fid0, {})
			check(fk.has(pid) and ft.has(pid), "named draft pool pid %d missing pre-draft work snapshot in family %d" % [pid, fid0])
			var kind := String(fk.get(pid, ""))
			check(kind != "" and not kind in ["land", "herd", "keeper"], "a needed land hand in the draft pool")
			check(int(ft.get(pid, -1)) == int(r[0]), "named draft pool row tier %d does not match pre-draft work kind %s" % [int(r[0]), kind])
	print("draft pool of %s: %d (by tier idle/casual/job: %s)" % [town["name"], pool.size(), str(tiers)])
	check(not pool.is_empty(), "a town at world generation can spare nobody")
	var fams0 := (e["fams"] as Array).size()
	var pop0 := int(e["pop"])
	# Who can go: walk the pool the way People.draft does. A family keeps two grown-ups
	# and every land hand and keeper (Population.spare). Cohort rows are unnamed slots.
	var can := 0
	var first_sim_tier := -1
	var sim_tiers: Array = []
	for r in pool:
		var fid := int(r[2])
		var pid := int(r[3])
		if int(spare_left.get(fid, 0)) <= 0:
			continue
		var fam := People.fam_of(town, fid)
		var take := false
		if pid < 0:
			take = int(bins_left.get(fid, 0)) > 0
			if take:
				bins_left[fid] = int(bins_left[fid]) - 1
		else:
			var p := Persons.by_pid(fam, pid)
			take = not p.is_empty() and String(p[4]) == "" and int(p[5]) < 0 and int(p[6]) == 0
		if not take:
			continue
		spare_left[fid] = int(spare_left[fid]) - 1
		if first_sim_tier < 0:
			first_sim_tier = int(r[0])
		sim_tiers.append(int(r[0]))
		can += 1
	# ask for more men than it can spare: the band is as big as the pool
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var ask := can + 6
	var wid := CampaignWorld.spawn_warband(Game, "middle_kingdom", town["pos"], ask, "patrol", rng, {"home": town["id"]})
	var got := (w["warbands"][wid]["units"] as Array).size() if wid != "" else 0
	print("asked for %d, raised %d (pool %d, families can send %d)" % [ask, got, pool.size(), can])
	check(got == can and got < ask, "raised %d, the town can spare %d" % [got, can])
	check(wid != "" and int(w["warbands"][wid].get("unraised", 0)) == ask - got, "the men not raised are not counted")
	var first_tier := -1
	var drafted_tiers: Array = []
	if wid != "":
		for u in w["warbands"][wid]["units"]:
			check(u.home_town == town["id"], "a soldier from another town")
			var f := People.fam_of(town, u.family)
			var p := Persons.by_uid(f, u.uid)
			check(not p.is_empty() and String(p[4]) == "army", "a soldier who is not a register person of his town")
			if not p.is_empty():
				var window := People.draft_ages(Persons.family_race(e, f))
				var age := Persons.age_of(p, day)
				check(age >= window.x and age <= window.y, "a soldier aged %d" % age)
				var res := _resolve_drafted_soldier(e, f, p, day, snap)
				check(bool(res.get("has_snap", false)), "missing pre-draft work snapshot for drafted soldier pid %d in family %d" % [int(p[0]), u.family])
				var kind := String(res.get("kind", ""))
				check(bool(res.get("ok", false)) and kind != "" and not kind in ["land", "herd", "keeper"], "a land/herd/keeper hand or unrecorded person was drafted (%s)" % kind)
				var unit_tier := int(res.get("tier", -1))
				check(unit_tier >= 0, "drafted soldier pid %d has invalid pre-draft tier %d" % [int(p[0]), unit_tier])
				if drafted_tiers.is_empty():
					first_tier = unit_tier
				drafted_tiers.append(unit_tier)
	if not pool.is_empty():
		check(first_tier >= 0 and first_tier == first_sim_tier, "the first man drafted is not from the first tier the town can spare (%d vs %d)" % [first_tier, first_sim_tier])
		check(drafted_tiers == sim_tiers, "drafted soldier tiers do not match pre-draft pool order (%s vs %s)" % [str(drafted_tiers), str(sim_tiers)])
	for cfid in pre_cohort:
		var c_after: Dictionary = pre_cohort[cfid]
		var cfam := People.fam_of(town, int(cfid))
		check(cfam.get("age_bins", {}) == c_after["bins_remaining"], "cohort %d age_bins after draft do not match observed promotions" % int(cfid))
		check(Persons.pp_read(cfam).size() == int(c_after["pp_count"]) + int(c_after["promoted_taken"]), "cohort %d pp size mismatch after promotion" % int(cfid))
		check(int(cfam.get("hands", 0)) == int(c_after["hands"]) and (cfam.get("keeps", []) as Array).size() == int(c_after["keeps"]), "cohort %d land/herd/keeper places changed during draft" % int(cfid))
		check(Families.adults(cfam) - Families.serving(cfam) >= int(c_after["reserve"]), "cohort %d drafted into protected reserve" % int(cfid))
	check((e["fams"] as Array).size() == fams0 and int(e["pop"]) == pop0, "the draft made up families or people (%d -> %d families)" % [fams0, (e["fams"] as Array).size()])
	# nobody left: the next band is not raised
	var wid2 := CampaignWorld.spawn_warband(Game, "middle_kingdom", town["pos"], 6, "patrol", rng, {"home": town["id"]})
	check(wid2 == "" and People.draft_pool(town).is_empty(), "a band raised from a town with nobody to spare")
	check((e["fams"] as Array).size() == fams0, "families made up for an unraised band")
	_test_draft_fixture(town)

func _test_draft_fixture(town: Dictionary) -> void:
	var e: Dictionary = town["econ"]
	var yd := People.year_days()
	var year := 20
	var day := float(year) * yd
	e["day"] = day
	Game.day = day
	e.erase("hd")
	e["cjcap"] = {}
	e["cjused"] = {}
	var biz: Array = e["biz"]
	check(biz.size() >= 3, "fixture town needs at least 3 business rows")
	if biz.size() < 3:
		return
	for b0 in biz:
		var bd: Dictionary = b0
		bd["closed"] = true
		bd["for_sale"] = false
		bd["owner"] = -1
		bd["cap"] = 0
		bd["workers"] = 0
		bd["kw"] = 0
	var b_cf_shop: Dictionary = biz[0]
	b_cf_shop["id"] = 0; b_cf_shop["type"] = "baker"; b_cf_shop["owner"] = 1; b_cf_shop["closed"] = false; b_cf_shop["till"] = 500.0; b_cf_shop["wage"] = 90.0
	var b_nf_shop: Dictionary = biz[1]
	b_nf_shop["id"] = 1; b_nf_shop["type"] = "carpenter"; b_nf_shop["owner"] = 2; b_nf_shop["closed"] = false; b_nf_shop["till"] = 500.0; b_nf_shop["wage"] = 90.0
	var b_job: Dictionary = biz[2]
	b_job["id"] = 2; b_job["type"] = "works"; b_job["owner"] = 0; b_job["closed"] = false; b_job["cap"] = 2; b_job["workers"] = 2; b_job["till"] = 5000.0; b_job["wage"] = 80.0
	var estate := Families.make_estate(town)
	var cf := Families._blank(1)
	cf["cohort"] = true; cf["name"] = "Brook"; cf["race"] = "human"; cf["cul"] = e.get("culture", "middle")
	cf["households"] = 4; cf["homes"] = 4; cf["purse"] = 40.0; cf["hungry"] = 2
	cf["owns"] = [0]; cf["land"] = {"grain": 16}; cf["ox"] = 2; cf["herd"] = {"sheep": 40}
	cf["m"] = 20; cf["f"] = 0; cf["kids"] = 2; cf["old"] = 1; cf["pp"] = []; cf["kp"] = []; cf["age_bins"] = {}
	var nf := Families._blank(2)
	nf["name"] = "Miller"; nf["race"] = "human"; nf["cul"] = e.get("culture", "middle")
	nf["homes"] = 2; nf["purse"] = 80.0; nf["hungry"] = 1
	nf["owns"] = [1]; nf["land"] = {"grain": 16}; nf["ox"] = 2; nf["herd"] = {"sheep": 40}
	nf["m"] = 20; nf["f"] = 0; nf["kids"] = 0; nf["old"] = 0; nf["pp"] = []; nf["kp"] = []
	var rf := Families._blank(3)
	rf["cohort"] = true; rf["name"] = "Lane"; rf["race"] = "human"; rf["cul"] = e.get("culture", "middle")
	rf["households"] = 1; rf["homes"] = 1; rf["purse"] = 200.0; rf["hungry"] = 0
	rf["m"] = 2; rf["f"] = 1; rf["kids"] = 0; rf["old"] = 0; rf["pp"] = []; rf["kp"] = []
	rf["age_bins"] = {"0:%d" % (year - 22): 2, "1:%d" % (year - 23): 1}
	e["fams"] = [estate, cf, nf, rf]
	Families._aggregate_land(e)
	Families.reassign(e, cf)
	Families.reassign(e, nf)
	Families.reassign(e, rf)
	var cf_hands := int(cf["hands"])
	var cf_keeps := (cf["keeps"] as Array).size()
	var nf_hands := int(nf["hands"])
	var nf_keeps := (nf["keeps"] as Array).size()
	check(cf_keeps == 1 and cf_hands >= 2 and Families.crop_hands(cf, e) > 0.0 and Families.herd_hands(cf, e) > 0.0, "fixture cohort must have keeper, land, and herd hands")
	check(nf_keeps == 1 and nf_hands >= 2 and Families.crop_hands(nf, e) > 0.0 and Families.herd_hands(nf, e) > 0.0, "fixture named family must have keeper, land, and herd hands")
	var cf_reserve := cf_keeps + cf_hands
	cf["m"] = cf_reserve + 1; cf["f"] = 2
	cf["jobs"] = {"2": 1}; b_job["workers"] = 2; b_job["cap"] = 2
	Families.reassign(e, cf)
	cf["cj"] = {"porter": 1}; cf["idle"] = 1
	cf["age_bins"] = {
		"0:%d" % (year - 20): 2,
		"1:%d" % (year - 24): 2,
		"0:%d" % (year - 28): 1,
		"0:%d" % (year - 36): int(cf["m"]) - 3,
		"0:%d" % (year - 8): 2,
		"1:%d" % (year - 65): 1,
	}
	var nf_reserve := nf_keeps + nf_hands
	nf["m"] = nf_reserve + 3; nf["f"] = 0
	nf["jobs"] = {"2": 1}; b_job["workers"] = 2; b_job["cap"] = 2
	Families.reassign(e, nf)
	nf["cj"] = {"porter": 1}; nf["idle"] = 1
	var rng := RandomNumberGenerator.new(); rng.seed = 77
	var nf_pids: Array = []
	for i in int(nf["m"]):
		var p_new := Persons._new(e, nf, "human", 0, day - float(27 - i) * yd, 0, rng)
		Persons.pp(nf).append(p_new)
		nf_pids.append(int(p_new[0]))
	e["pop"] = Families.people(cf) + Families.people(nf) + Families.people(rf)
	check(not Families.assignments_stale(cf) and Population.spare(cf) == 3 and Population.eligible_slots(e, cf, day, true) == 3, "fixture cohort spare/eligible_slots setup invalid")
	check(not Families.assignments_stale(nf) and Population.spare(nf) == 3, "fixture named spare setup invalid")
	check(not Families.assignments_stale(rf) and Population.spare(rf) == 1 and Population.eligible_slots(e, rf, day, true) == 1, "fixture 2-adult reserve cohort setup invalid")
	var snap := _snapshot_draft_town(e, day)
	var nf_kinds: Dictionary = snap["pre_named_kind"][2]
	var nf_tiers: Dictionary = snap["pre_named_tier"][2]
	var pid_keep := int(nf_pids[0])
	var pid_job := int(nf_pids[nf_reserve])
	var pid_cas := int(nf_pids[nf_reserve + 1])
	var pid_idle := int(nf_pids[nf_reserve + 2])
	var saw_herd := false
	var saw_land := false
	for hi in range(1, nf_reserve):
		var hpid := int(nf_pids[hi])
		var hk := String(nf_kinds.get(hpid, ""))
		if hk == "herd":
			saw_herd = true
		elif hk == "land":
			saw_land = true
		check(int(nf_tiers.get(hpid, -1)) == -1, "fixture herd/land hand pid %d must not have a draft tier" % hpid)
	check(String(nf_kinds.get(pid_keep, "")) == "keeper" and int(nf_tiers.get(pid_keep, -1)) == -1, "fixture keeper snapshot mismatch")
	check(saw_herd and saw_land, "fixture named family must have both herd and land hand kinds in pre-draft snapshot")
	check(String(nf_kinds.get(pid_job, "")) == "job" and int(nf_tiers.get(pid_job, -1)) == 2, "fixture job snapshot mismatch")
	check(String(nf_kinds.get(pid_cas, "")) == "casual" and int(nf_tiers.get(pid_cas, -1)) == 1, "fixture casual snapshot mismatch")
	check(String(nf_kinds.get(pid_idle, "")) == "none" and int(nf_tiers.get(pid_idle, -1)) == 0, "fixture idle snapshot mismatch")
	# Negative control: a missing pre-draft snapshot for a named soldier must fail (-1), never fallback to expected tier.
	var empty_snap := {"pre_named_kind": {}, "pre_named_tier": {}, "pre_cohort": {}, "next_pid0": int(snap["next_pid0"])}
	var neg := _resolve_drafted_soldier(e, nf, Persons.by_pid(nf, pid_idle), day, empty_snap)
	check(not bool(neg.get("ok", true)) and not bool(neg.get("has_snap", true)) and int(neg.get("tier", 0)) == -1, "missing pre-draft snapshot did not fail")
	var fpool := People.draft_pool(town)
	var want_pool := [
		[0, 1, -1],
		[0, 2, pid_idle],
		[0, 3, -1],
		[1, 1, -1],
		[1, 2, pid_cas],
		[2, 1, -1],
		[2, 2, pid_job],
	]
	check(fpool.size() == want_pool.size(), "fixture draft_pool size %d, want %d" % [fpool.size(), want_pool.size()])
	for i in mini(fpool.size(), want_pool.size()):
		var row: Array = fpool[i]
		var exp_row: Array = want_pool[i]
		check(int(row[0]) == int(exp_row[0]) and int(row[2]) == int(exp_row[1]) and int(row[3]) == int(exp_row[2]), "fixture pool[%d] = %s, want tier/fid/pid %s" % [i, str(row), str(exp_row)])
	var want_kinds := ["none", "none", "none", "casual", "casual", "job", "job"]
	for step in want_pool.size():
		var exp_entry: Array = want_pool[step]
		var dfid := People.draft(town, fpool, "army")
		check(dfid == int(exp_entry[1]), "fixture draft step %d picked family %d, want %d" % [step, dfid, int(exp_entry[1])])
		var u := Factory.make_troop(rng, "middle_kingdom", Factory.pick_troop(rng, "middle_kingdom"))
		People.bind(town, dfid, u, "army")
		var dfam := People.fam_of(town, dfid)
		var dp := Persons.by_uid(dfam, u.uid)
		check(not dp.is_empty() and String(dp[4]) == "army", "fixture step %d unit not bound to army person" % step)
		var dres := _resolve_drafted_soldier(e, dfam, dp, day, snap)
		check(bool(dres.get("ok", false)) and int(dres.get("tier", -1)) == int(exp_entry[0]) and String(dres.get("kind", "")) == want_kinds[step], "fixture step %d resolved %s, want tier %d kind %s" % [step, str(dres), int(exp_entry[0]), want_kinds[step]])
		if dfid == 2:
			check(not bool(dres.get("promoted", true)) and int(dp[0]) == int(exp_entry[2]), "fixture named draft step %d wrong pid %d" % [step, int(dp[0])])
			check(String(People._work_kinds(nf).get(int(dp[0]), "")) == "", "drafted named soldier still appears in post-draft _work_kinds")
		else:
			check(bool(dres.get("promoted", false)) and int(dp[0]) >= int(snap["next_pid0"]), "fixture cohort draft step %d did not promote a new pid" % step)
			if dfid == 1:
				var c_slot := int(dres.get("slot", -1))
				if c_slot == 0:
					check(Families.job_total(cf) == 1 and int(cf["hands"]) == cf_hands and (cf["keeps"] as Array).size() == 1, "cohort idle draft disturbed job/land/herd/keeper")
				elif c_slot == 1:
					check(int(cf["idle"]) == 0 and cf.get("cj", {}).is_empty() and Families.job_total(cf) == 1 and int(cf["hands"]) == cf_hands and (cf["keeps"] as Array).size() == 1, "cohort casual draft disturbed job/land/herd/keeper")
				elif c_slot == 2:
					check(Families.job_total(cf) == 0 and int(cf["idle"]) == 0 and int(cf["hands"]) == cf_hands and (cf["keeps"] as Array).size() == 1 and Population.spare(cf) == 0, "cohort job draft did not stop at protected land/herd/keeper reserve")
	check(cf["age_bins"] == snap["pre_cohort"][1]["bins_remaining"] and _draft_bins(e, cf, day) == 2, "cohort remaining draft-age bins or non-draft bins corrupted")
	check(int(cf["age_bins"].get("0:%d" % (year - 36), 0)) == int(cf["m"]) - 3 and int(cf["age_bins"].get("0:%d" % (year - 8), 0)) == 2 and int(cf["age_bins"].get("1:%d" % (year - 65), 0)) == 1, "cohort over-age, child, or elder bins touched by promotion")
	check(rf["age_bins"] == snap["pre_cohort"][3]["bins_remaining"] and _draft_bins(e, rf, day) == 2 and Population.spare(rf) == 0, "2-adult reserve cohort did not protect remaining 2 draft-age adults")
	for prot_i in nf_reserve:
		var prot_p := Persons.by_pid(nf, int(nf_pids[prot_i]))
		check(not prot_p.is_empty() and String(prot_p[4]) == "" and int(prot_p[5]) == -1, "protected named keeper/herd/land pid %d was drafted" % int(nf_pids[prot_i]))
	var forced_pool := [[0, 0.0, 1, -1], [0, 0.0, 2, pid_keep], [0, 0.0, 2, int(nf_pids[1])], [0, 0.0, 3, -1]]
	check(People.draft(town, forced_pool, "army") == -1 and Population.promote(e, cf, day, rng, true).is_empty(), "draft or promote took from protected keeper/land/herd/reserve")

func _test_save_and_migration() -> void:
	_fresh()
	var w: Dictionary = Game.world
	var fid := "middle_kingdom"
	var members := Army.members(Game, fid)
	if members.is_empty():
		check(false, "no kingdom army to save")
		return
	var posts0: Array = (Army.rec(w, fid)["posts"] as Array).duplicate()
	var u0: Unit = members[0]
	u0.renown = 12.5
	u0.notable = [["Krug", 7.0, 3]]
	var uid := u0.uid
	var rank0 := u0.rank
	var tr0 := float(w["factions"][fid]["treasury"])
	Game.save_game()
	Game.world = {}
	Game.load_game()
	w = Game.world
	var posts1: Array = Army.rec(w, fid)["posts"]
	check(posts0 == posts1 and typeof(posts1[0]) == TYPE_INT if not posts1.is_empty() else true, "rank posts changed in save/load")
	var u1: Unit = null
	for u in Army.members(Game, fid):
		if u.uid == uid:
			u1 = u
	check(u1 != null and u1.rank == rank0 and absf(u1.renown - 12.5) < 0.01 and u1.notable.size() == 1, "unit rank/renown lost in save/load")
	check(absf(float(w["factions"][fid]["treasury"]) - tr0) < 0.01, "treasury changed in save/load")
	# an old save from before spec 2: no army state, soldiers without families or ranks
	w.erase("army")
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		wb.erase("stores")
		if Army.is_field(wb):
			for u in wb["units"]:
				u.family = -1
				u.rank = 0
	Game.save_game()
	Game.world = {}
	Game.load_game()
	w = Game.world
	check(w.has("army") and _units_without_family(w).is_empty(), "old save not migrated: soldiers without families")
	var any_tree := false
	for f2 in Army.state(w)["f"]:
		if int(Army.state(w)["f"][f2]["levels"]) > 0:
			any_tree = true
	check(any_tree, "old save not migrated: no rank trees")
