class_name HerdRaids
extends RefCounted
## Travel, confrontation and actual taking replace proximity-based weekly losses.
static var fights := {}
static var fight_seed := -1
## Diagnostics may request a fixed tick quota to compare identical simulation work.
## Ordinary play retains the existing 4 ms budget; new/load always switches this off.
static var benchmark_fixed_steps := false

static func reset() -> void:
	fights.clear()
	fight_seed = -1
	benchmark_fixed_steps = false

static func plot_pos(town: Dictionary, P: Dictionary, i: int) -> Vector2:
	return (town["pos"] as Vector2) + Vector2(float(P["x"][i]) - float(P["gw"]) / 2, float(P["y"][i]) - float(P["gh"]) / 2) * 5

static func plan(game, town: Dictionary, day: float) -> void:
	var e: Dictionary = town["econ"]
	var P: Dictionary = e.get("plots", {})
	for wb in game.world["warbands"].values():
		if Monsters.suspended_band(wb): continue
		if wb.has("raid") or wb.get("units", []).is_empty() or not String(wb["kind"]) in ["bandit", "beasts"]: continue
		var wolves: bool = String(wb["kind"]) == "beasts" and wb["units"].all(func(u): return u.race == "wolf")
		if String(wb["kind"]) == "beasts" and not wolves: continue
		if wolves:
			if day - float(wb.get("last_fed", 0)) < 7: continue
		elif Supplies.days(wb) >= 7: continue
		var best: Dictionary = {}
		var distance := 300.0 * 300
		var goal := Vector2.ZERO
		for h in Herds.herds(e).values():
			if not Herds.GRAZE.has(String(h["k"])) or Herds.head(h) <= 0 or String(h["ow"]) == "d": continue
			for i in h.get("pl", []):
				if int(i) >= Plots.count(P) or int(P["use"][int(i)]) != Plots.PASTURE: continue
				var pos := plot_pos(town, P, int(i))
				var d := (wb["pos"] as Vector2).distance_squared_to(pos)
				if d < distance: distance = d; best = h; goal = pos
		if best.is_empty(): continue
		var path := CampaignWorld.find_path(game.world, wb["pos"], goal)
		if path.is_empty(): continue
		wb["raid"] = {"town": town["id"], "herd": best["id"], "goal": goal, "wolves": wolves, "phase": "travelling", "day": day}
		wb["path"] = path
		TownDefence.set_muster(game, town, true)
		var mil := Militia.band_of(game, String(town["id"]))
		if not mil.is_empty(): mil["path"] = CampaignWorld.find_path(game.world, mil["pos"], goal)
		var guard := TownDefence.guard_band(game, String(town["id"]))
		if not guard.is_empty():
			guard["path"] = CampaignWorld.find_path(game.world, guard["pos"], goal)
			guard["marching"] = true
		CampaignWorld.log_event(game, "A %s set out to raid a pasture of %s." % ["wolf pack" if wolves else "hungry outlaw band", town["name"]])

static func step(game, wb: Dictionary, dt: float, _t: float, rng: RandomNumberGenerator) -> bool:
	if Monsters.suspended_band(wb): return true
	if fight_seed != int(game.world.get("seed", 0)):
		fights.clear(); fight_seed = int(game.world.get("seed", 0))
	var raid: Dictionary = wb["raid"]
	var town: Dictionary = game.world["towns"].get(String(raid["town"]), {})
	if town.is_empty(): wb.erase("raid"); return false
	var e: Dictionary = town["econ"]
	var herd: Dictionary = Herds.herds(e).get(str(int(raid["herd"])), {})
	if herd.is_empty() or Herds.head(herd) == 0: wb.erase("raid"); return false
	if raid["phase"] == "travelling":
		if not CampaignWorld._step_along(game.world, wb, CampaignWorld.WARBAND_SPEED * dt): return true
		# The pasture is reached before anything can be stolen or killed.
		if (wb["pos"] as Vector2).distance_to(raid["goal"]) > CampaignWorld.CONTACT: wb.erase("raid"); return true
		var defenders := []
		var mil := Militia.band_of(game, String(town["id"]))
		var guard := TownDefence.guard_band(game, String(town["id"]))
		for force in [mil, guard]:
			if not force.is_empty() and (force["pos"] as Vector2).distance_to(wb["pos"]) <= Militia.RADIUS:
				defenders.append_array(force["units"].filter(func(u): return not u.dead))
		var herders := []
		var saved_force: Dictionary = game.world["warbands"].get(String(raid.get("herders", "")), {})
		if not saved_force.is_empty(): defenders.append_array(saved_force["units"].filter(func(u): return not u.dead))
		var fid := Herds.grazer(e, herd)
		if fid >= 0 and fid < e["fams"].size():
			var f: Dictionary = e["fams"][fid]
			var jobs := Persons.work(e, f)
			for p in Persons.pp(f):
				if int(p[5]) >= 0 or String(p[4]) != "" or String(jobs.get(int(p[0]), {}).get("kind", "")) != "herd": continue
				var u := Unit.create(Persons.race_of(e), String(town["faction"]))
				Persons.bind(e, f, p, u, "pasture", float(game.day)); u.home_town = String(town["id"])
				f["serve"]["pasture"] = int(f["serve"].get("pasture", 0)) + 1
				TownEcon.outfit_units(town, [u], 1)
				defenders.append(u); herders.append(u)
			if not herders.is_empty():
				# Muster all original herders before updating the civilian work they left.
				Families.reassign(e, f)
		if not herders.is_empty():
			raid["herders"] = CampaignWorld.spawn_warband(game, String(town["faction"]), wb["pos"], herders.size(), "militia", rng, {"units": herders, "home": town["id"], "anchor": wb["pos"], "pasture_defence": true})
		if defenders.is_empty(): take(game, wb, town, herd); wb.erase("raid"); return true
		var sim := BattleSim.new()
		sim.setup(defenders, wb["units"], hash([game.world.get("seed", 0), wb["id"], int(raid["day"])]), {"w": 24, "h": 12, "verbose": false, "log_moves": false})
		fights[String(wb["id"])] = {"sim": sim, "defenders": defenders}
		raid["phase"] = "fighting"
	if not fights.has(String(wb["id"])):
		raid["phase"] = "travelling"; wb["path"] = [raid["goal"]]; return true
	var fight: Dictionary = fights[String(wb["id"])]
	var sim: BattleSim = fight["sim"]
	var start := Time.get_ticks_usec()
	for i in 200:
		if sim.over or (not benchmark_fixed_steps and Time.get_ticks_usec() - start > 4000): break
		sim.step()
	if not sim.over: return true
	var dead := []
	for u in fight["defenders"]:
		if u.dead: dead.append(u)
		if u.dead:
			var role := "pasture" if u.title != "town guard" and not u.title.begins_with("militia") else ("guard" if u.title == "town guard" else "militia")
			if role == "pasture":
				# A queued illness may already have removed this exact registered defender.
				# Keep his first death and never substitute another household member.
				var home := People.fam_of(town, u.family)
				var person := Persons.by_uid(home, u.uid) if not home.is_empty() else []
				if not person.is_empty():
					People.casualty_rec(game, u.home_town, u.family, u.name, "dead", role, person)
			else:
				People.casualty(game, u, "dead", role)
		elif u.family >= 0:
			var f := People.fam_of(town, u.family)
			var p := Persons.by_uid(f, u.uid)
			if not p.is_empty() and String(p[4]) == "pasture": People.release(town, u.family, "pasture", u.uid)
	for u in wb["units"]:
		if u.dead:
			dead.append(u)
			if not u.race_def().get("creature", false): People.casualty(game, u, "dead", "bandit")
	ArmsTrade.field(game, dead, {"band": wb} if sim.winner == 1 and not raid["wolves"] else ({"town": town} if sim.winner == 0 else {}), wb["pos"])
	game.world["warbands"].erase(String(raid.get("herders", "")))
	wb["units"] = wb["units"].filter(func(u): return not u.dead)
	var militia := Militia.band_of(game, String(town["id"]))
	if not militia.is_empty(): militia["units"] = militia["units"].filter(func(u): return not u.dead)
	var guard := TownDefence.guard_band(game, String(town["id"]))
	if not guard.is_empty(): guard["units"] = guard["units"].filter(func(u): return not u.dead)
	if sim.winner == 1 and not wb["units"].is_empty(): take(game, wb, town, herd)
	CampaignWorld.log_event(game, "The pasture raid at %s ended: %s." % [town["name"], "raiders driven off" if sim.winner == 0 else ("raiders took livestock" if sim.winner == 1 else "both sides withdrew")])
	fights.erase(String(wb["id"])); wb.erase("raid")
	wb["rest_until"] = float(game.day) + 1
	return true

static func take(game, wb: Dictionary, town: Dictionary, h: Dictionary) -> void:
	if Monsters.suspended_band(wb): return
	var e: Dictionary = town["econ"]
	var n: int = wb["units"].size()
	var wolves := bool(wb["raid"]["wolves"])
	var food := maxi(0, n * 2 * 7 - int(Supplies.days(wb) * n * 2))
	var room := maxf(0, Supplies.capacity(n) - Supplies.weight(Supplies.stores(wb)))
	var meal_weight := float(Goods.table()["meat"]["weight"])
	if not wolves: food = mini(food, int(room / meal_weight))
	for age in ["y", "o", "g"]:
		var meat := int(floor(float(Herds.yields(String(h["k"]), age).get("fresh_meat", 0))))
		if meat <= 0: continue
		var take_n := mini(int(h[age]), int(ceil(float(food) / meat)))
		if take_n <= 0: continue
		Herds.change(e, h, age, -take_n, "stolen", "wolf pasture raid" if wb["raid"]["wolves"] else "outlaw pasture raid", float(game.day))
		var meals := take_n * meat
		var carried := mini(meals, food)
		if not wolves: Supplies.stores(wb)["meat"] = int(Supplies.stores(wb).get("meat", 0)) + carried
		# Animals leave the herd ledger; carcasses are produced here before eaten, carried or left.
		TownEcon.led(e, "made", "fresh_meat", meals)
		TownEcon.led(e, "used" if wolves else "out", "fresh_meat", carried)
		TownEcon.led(e, "spoil", "fresh_meat", meals - carried)
		food -= meals
		if food <= 0: break
	wb["last_fed"] = float(game.day)
