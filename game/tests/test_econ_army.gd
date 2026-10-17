extends RefCounted
## Economy spec 2 (docs/specs/economy-2-army.md section 7 + Douglas's rules): every non-monster unit on the map has
## a family; no force has unpaid soldiers without the desertion timer running (and the timer ends in desertion
## home); rank counts never exceed caps and caps follow army size; the orc cascade (kill a warboss -> one big
## boss, one boss, one blooded promoted, all by fights, counts valid); wage gold leaves the treasury and lands in
## family purses (conserved, coin and kind); a succession fight < 10 ms; kill renown; force stores (player win
## gains them, player loss keeps its own, AI winner takes them, conserved); bandits paid from the camp; company
## desertion; save/load round trip and old-save migration.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_save_army_%d.json" % OS.get_process_id()
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
	return fails

func _run_jobs(n_days: int) -> void:
	for i in n_days:
		Game.advance_time(1.0, true)
		var w: Dictionary = Game.world
		var guard := 0
		while not (w.get("work", []) as Array).is_empty() and guard < 100000:
			CampaignWorld._do_work(Game, CampaignWorld._rng(w))
			guard += 1

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

## Choose by actual free registered adults, never by a town or household name.
## A staged loss transfers poor volunteers' savings to another household and their
## food entitlement to that household at the same meal value; physical hh goods stay.
func _funded_camp() -> String:
	var w: Dictionary = Game.world
	var lid := ""
	var town: Dictionary = {}
	var candidates := []
	for key in w["lairs"]:
		var l: Dictionary = w["lairs"][key]
		if l.get("kind", "") != "bandit_camp": continue
		var nearest: Dictionary = {}
		var distance := INF
		for t in w["towns"].values():
			if not TownEcon.has_econ(t) or String(TownEcon.culture_of(t["econ"])["race"]) != "human": continue
			var d: float = (t["pos"] as Vector2).distance_squared_to(l["pos"])
			if d < distance:
				distance = d
				nearest = t
		if nearest.is_empty(): continue
		var possible := []
		var e: Dictionary = nearest["econ"]
		for f in e["fams"]:
			if f.get("gone", false) or f.has("estate") or Families.adults(f) - Families.serving(f) < 2: continue
			var jobs := Persons.work(e, f)
			for p in Persons.pp(f):
				var job: Dictionary = jobs.get(int(p[0]), {})
				if int(p[6]) == 0 and String(p[4]) == "" and int(p[5]) < 0 and not job.get("keeper", false) and float(job.get("wage", 0)) < float(Army.A()["wage"]["bandit"]):
					possible.append(f)
					break
		if possible.size() > candidates.size():
			lid = key
			town = nearest
			candidates = possible
	check(lid != "" and candidates.size() >= 6, "no camp near enough genuine free outlaw volunteers")
	if lid == "" or candidates.size() < 6: return ""
	var e: Dictionary = town["econ"]
	var receiver: Dictionary = {}
	for f in e["fams"]:
		if not f.get("gone", false) and not f.has("estate") and not candidates.has(f) and Families.people(f) > 0 and float(Families.daily_rates(e, f)["food"]) > 0.0:
			receiver = f
			break
	check(not receiver.is_empty(), "no existing household to receive fixture transfers")
	if receiver.is_empty(): return ""
	var cash0 := float(receiver["purse"])
	var food0 := float(receiver["store"]["food"]) * float(Families.daily_rates(e, receiver)["food"])
	for f in candidates:
		cash0 += float(f["purse"])
		food0 += float(f["store"]["food"]) * float(Families.daily_rates(e, f)["food"])
		_move_cash(f, "purse", receiver, "purse", float(f["purse"]))
		var meals := float(f["store"]["food"]) * float(Families.daily_rates(e, f)["food"])
		receiver["store"]["food"] += meals / float(Families.daily_rates(e, receiver)["food"])
		f["store"]["food"] = 0.0
	check(absf(float(receiver["purse"]) - cash0) < 0.01, "outlaw setup created or lost savings")
	check(absf(float(receiver["store"]["food"]) * float(Families.daily_rates(e, receiver)["food"]) - food0) < 0.0001, "outlaw setup created or lost household meals")
	var l: Dictionary = w["lairs"][lid]
	var fac: Dictionary = w["factions"][town["faction"]]
	var target := float(Army.A()["wage"]["bandit"]) * 20.0 * 14.0
	_fund_faction(String(town["faction"]), target)
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
	Game.new_game(5150)
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
	_run_jobs(4)
	bad = _units_without_family(w)
	check(bad.is_empty(), "after 4 days, units without a family: %s" % str(bad.slice(0, 6)))
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
	# the world's trees after some days: counts never over caps, caps from the army's size
	Game.new_game(5151)
	_run_jobs(6)
	var w: Dictionary = Game.world
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
	Game.new_game(5152)
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
func _test_unpaid_and_desertion() -> void:
	Game.new_game(5153)
	var w: Dictionary = Game.world
	var fid := "northern_clans"
	var units := Army.members(Game, fid)
	check(not units.is_empty(), "no northern army to test")
	var fams := {}
	for u in units:
		var f := People.fam_of(w["towns"][u.home_town], u.family)
		fams[u.uid] = [f, int(f["serve"].get("army", 0))]
	_empty_faction(fid)
	var dd := int(Army.A()["desert_days"])
	for d in dd - 1:
		Army.faction_day(Game, fid, int(Game.day) + 1 + d)
		var r: Dictionary = Army.rec(w, fid)
		var timer_ok := true
		for u in Army.members(Game, fid):
			if u.unpaid_days != d + 1:
				timer_ok = false
		check(timer_ok and int(r["unpaid_n"]) == Army.members(Game, fid).size(), "day %d: unpaid soldiers without the desertion timer running" % (d + 1))
		for wid in w["warbands"]:
			var wb: Dictionary = w["warbands"][wid]
			if wb["faction"] == fid and Army.is_field(wb):
				check(int(wb.get("unpaid_n", 0)) == (wb["units"] as Array).size(), "a band's unpaid count is wrong")
	Army.faction_day(Game, fid, int(Game.day) + dd)
	check(Army.members(Game, fid).is_empty(), "unpaid soldiers did not desert after %d days" % dd)
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
	# paid again: the timer resets
	Game.new_game(5153)
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
	Game.new_game(5154)
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
	for u in units:
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
	Game.new_game(5155)
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
	Game.new_game(5156)
	var w: Dictionary = Game.world
	for fid in ["middle_kingdom", "northern_clans", "goblin_warren", "moon_court"]:
		var units := Army.members(Game, fid)
		var r: Dictionary = Army.rec(w, fid)
		if int(r["levels"]) <= 0 or units.is_empty():
			continue
		var by := {}
		for u in units:
			by[u.uid] = u
		var top: Unit = by.get(int(r["posts"][0]), null)
		if top == null:
			check(false, "%s: no war leader" % fid)
			continue
		top.dead = true
		Army._bury(Game, top)
		Army.faction_day(Game, fid, int(Game.day) + 1)
		var nt := int(r["posts"][0])
		check(nt >= 0 and nt != top.uid, "%s (%s): the top post stayed empty" % [fid, Army.cul_of_faction(fid)["rank_rule"]])
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
	Game.new_game(5157)
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
	# the company wins: the beaten band's food and drink join its provisions
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
	Game.new_game(5158)
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
	# company men unpaid company_desert_days walk home to their families
	var u: Unit = Game.company[-1]
	var f := People.fam_of(w["towns"].get(u.home_town, {}), u.family)
	var ad := Families.adults(f) if not f.is_empty() else 0
	u.unpaid_days = int(Army.A()["company_desert_days"])
	Army.company_desertion(Game)
	check(not Game.company.has(u), "an unpaid company man did not desert")
	check(f.is_empty() or Families.adults(f) == ad + 1, "the deserter is not back on his family row")

# ---------------------------------------------------------------- a campaign month: invariants, families, perf
func _test_days_run() -> void:
	Game.new_game(5159)
	var w: Dictionary = Game.world
	w["party"]["safe_until"] = 1.0e9
	var worst := 0.0
	var by_kind := {}
	var tot := 0.0
	var n := 0
	var rng := CampaignWorld._rng(w)
	for d in 30:
		# one campaign day the way the map runs it: the day's jobs queued, then one job per frame
		Game.day = float(int(Game.day) + 1)
		w["last_day"] = int(Game.day)
		CampaignWorld._daily(Game, int(Game.day), rng)
		while not (w.get("work", []) as Array).is_empty():
			var job: Array = w["work"][0]
			var t0 := Time.get_ticks_usec()
			CampaignWorld._do_work(Game, CampaignWorld._rng(w))
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			if String(job[0]).begins_with("army"):
				worst = maxf(worst, ms)
				by_kind[job[0]] = "%.2f" % maxf(float(by_kind.get(job[0], "0")), ms)
				tot += ms
				n += 1
	var bad := _units_without_family(w)
	check(bad.is_empty(), "after a month, units without a family: %s" % str(bad.slice(0, 6)))
	for fid in Army.state(w)["f"]:
		for row in Army.tree_rows(Game, fid):
			if int(row["cap"]) >= 0 and int(row["count"]) > int(row["cap"]):
				check(false, "%s over cap after a month" % fid)
		for wid in w["warbands"]:
			var wb: Dictionary = w["warbands"][wid]
			if wb["faction"] == fid and Army.is_field(wb):
				for u in wb["units"]:
					check(u.unpaid_days < int(Army.A()["desert_days"]), "a man unpaid past the desertion day still serves")
	var lines := []
	for fid in ["middle_kingdom", "northern_clans", "orc_horde", "goblin_warren", "moon_court"]:
		lines.append("%s %d men, bill %.0f/day, treasury %d (%.0f days)" % [fid, Army.members(Game, fid).size(), Army.bill(Game, fid),
			int(w["factions"][fid]["treasury"]), minf(9999.0, Army.days_of_pay(Game, fid))])
	print("  after 30 days: " + " | ".join(PackedStringArray(lines)))
	# the force panel's rank tree and an officer's record build (headless, no window)
	var host := Control.new()
	ArmyPanel.open(host, "orc_horde")
	var offs: Array = Army.tree_rows(Game, "middle_kingdom")[0]["officers"]
	if not offs.is_empty():
		ArmyPanel.record(host, offs[0])
	check(host.get_child_count() >= 1, "the rank tree panel did not open")
	for wid in w["warbands"]:
		ArmyPanel.band_line(w["warbands"][wid])
	host.free()
	print("  PERF army jobs: %d jobs, mean %.3f ms, worst %.2f ms; worst by kind %s" % [n, tot / maxf(1.0, n), worst, str(by_kind)])
	check(worst < 15.0, "an army job took %.1f ms (one map frame)" % worst)

# ---------------------------------------------------------------- save / load
# ---------------------------------------------------------------- war pick 4: the draft
## An army takes only real free people of its home town aged 17-30 (race-scaled), labourers first, never a hand
## the family land or herd needs; when the town can spare too few the band is smaller, when none it is not raised;
## no family is ever made up for it.
func _test_draft() -> void:
	Game.new_game(5155)
	var w: Dictionary = Game.world
	var town: Dictionary = {}
	for tid in w["towns"]:
		if w["towns"][tid]["faction"] == "middle_kingdom" and TownEcon.has_econ(w["towns"][tid]):
			town = w["towns"][tid]
			break
	var e: Dictionary = town["econ"]
	var ar := People.draft_ages("human")
	check(ar == Vector2i(17, 30), "human draft ages %s, want 17-30" % str(ar))
	print("draft ages: human %s, orc %s, goblin %s, moon elf %s" % [str(ar), str(People.draft_ages("orc")), str(People.draft_ages("goblin")), str(People.draft_ages("moon_elf"))])
	var pool := People.draft_pool(town)
	var tiers := {}
	var day := float(e.get("day", 0))
	var prev := -1
	var places := {}   # pid -> work place kind before the draft
	for f in e["fams"]:
		if f["gone"] or f.has("estate"):
			continue
		var wk := Persons.work(e, f)
		for pid in wk:
			places[int(pid)] = String(wk[pid]["kind"])
	for r in pool:
		tiers[int(r[0])] = int(tiers.get(int(r[0]), 0)) + 1
		check(int(r[0]) >= prev, "draft pool not labourers first")
		prev = int(r[0])
		var p := Persons.by_pid(People.fam_of(town, int(r[2])), int(r[3]))
		var age := Persons.age_of(p, day)
		check(age >= 17 and age <= 30, "a %d-year-old in the draft pool" % age)
		check(not places.get(int(r[3]), "") in ["land", "herd"], "a needed land hand in the draft pool")
	print("draft pool of %s: %d (by tier idle/casual/job: %s)" % [town["name"], pool.size(), str(tiers)])
	check(not pool.is_empty(), "a town at world generation can spare nobody")
	var fams0 := (e["fams"] as Array).size()
	var pop0 := int(e["pop"])
	# who can go: each family keeps two grown-ups at home, so it sends at most adults - serving - 1 of its pool
	var per := {}
	for r in pool:
		per[int(r[2])] = int(per.get(int(r[2]), 0)) + 1
	var can := 0
	for fid in per:
		var f := People.fam_of(town, fid)
		can += mini(int(per[fid]), Families.adults(f) - Families.serving(f) - 1)
	# ask for more men than it can spare: the band is as big as the pool
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var ask := can + 6
	var wid := CampaignWorld.spawn_warband(Game, "middle_kingdom", town["pos"], ask, "patrol", rng, {"home": town["id"]})
	var got := (w["warbands"][wid]["units"] as Array).size() if wid != "" else 0
	print("asked for %d, raised %d (pool %d, families can send %d)" % [ask, got, pool.size(), can])
	check(got == can and got < ask, "raised %d, the town can spare %d" % [got, can])
	check(wid != "" and int(w["warbands"][wid].get("unraised", 0)) == ask - got, "the men not raised are not counted")
	var first_tier := -1
	if wid != "":
		for u in w["warbands"][wid]["units"]:
			check(u.home_town == town["id"], "a soldier from another town")
			var f := People.fam_of(town, u.family)
			var p := Persons.by_uid(f, u.uid)
			check(not p.is_empty() and String(p[4]) == "army", "a soldier who is not a register person of his town")
			if not p.is_empty():
				var age := Persons.age_of(p, day)
				check(age >= 17 and age <= 30, "a soldier aged %d" % age)
				check(not places.get(int(p[0]), "") in ["land", "herd"], "a land hand was drafted")
				if first_tier < 0:
					first_tier = ["none", "casual", "job"].find(places.get(int(p[0]), ""))
	if not pool.is_empty():
		check(first_tier == int(pool[0][0]), "the first man drafted is not from the first tier (%d vs %d)" % [first_tier, int(pool[0][0])])
	check((e["fams"] as Array).size() == fams0 and int(e["pop"]) == pop0, "the draft made up families or people (%d -> %d families)" % [fams0, (e["fams"] as Array).size()])
	# nobody left: the next band is not raised
	var wid2 := CampaignWorld.spawn_warband(Game, "middle_kingdom", town["pos"], 6, "patrol", rng, {"home": town["id"]})
	check(wid2 == "" and People.draft_pool(town).is_empty(), "a band raised from a town with nobody to spare")
	check((e["fams"] as Array).size() == fams0, "families made up for an unraised band")

func _test_save_and_migration() -> void:
	Game.new_game(5160)
	_run_jobs(3)
	var w: Dictionary = Game.world
	var fid := "middle_kingdom"
	var posts0: Array = (Army.rec(w, fid)["posts"] as Array).duplicate()
	var u0: Unit = Army.members(Game, fid)[0]
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
	_run_jobs(2)
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
	_run_jobs(2)
