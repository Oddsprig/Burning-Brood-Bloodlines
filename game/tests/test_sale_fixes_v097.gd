extends RefCounted
## v0.097 sale-readiness fixes, one short headless run on the DevTools start world (no campaign days):
##   1. a betrothal weds only when BOTH of the pair are of age (no child weddings)
##   2. in a battle of rounds the winner strips only the field: men who fled or left alive with their army keep
##      their purse and kit; a man who fled early and died later is still stripped
##   3. a dragon too badly hurt to fight sits out later rounds; a rider too badly hurt to fight is not seated
##   4. a house improvement needs every material in the market; nothing is charged or taken when one is short
##   5. Court lists every prisoner and every marriage match (a page at a time, "Show more")
##   6. Records: the Research card names charcoal (not wood); the Carriers line no longer denies pack animals
##   godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_sale_fixes_v097.gd --watchdog=170
const CourtScreen = preload("res://ui/court.gd")
var fails := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL v097: " + message)
	print(("ok   " if ok else "FAIL ") + message)

func troops(faction: String, n: int, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	for i in n:
		out.append(Factory.make_troop(rng, faction, DB.factions[faction]["troops"][i % 2], 2))
	return out

func cripple(u: Unit) -> void:
	u.body.blood = u.body.blood_max * 0.05   # below the collapse line: "cannot fight", still alive

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "DevTools start world loads")
		return fails
	var tid := DevTools.choose_house(Game)
	check(tid != "", "a house is chosen")
	if tid == "": return fails
	DevTools.stand_at(Game, tid)
	weddings()
	rounds_loot()
	dragons(tid)
	improvements()
	court_lists()
	records_text()
	print("v097 checks %d, failures %d, %d ms" % [checks, fails, Time.get_ticks_msec() - started])
	return fails

# ------------------------------------------------------------------ 1. weddings
func _set_age(loc: Dictionary, years: float) -> void:
	loc["person"][3] = float(Game.day) - years * People.year_days()

func weddings() -> void:
	var fam: Array = Marriage.family(Game)
	var member := {}
	var cand := {}
	for row: Dictionary in fam:
		if bool(row.get("married", false)) or bool(row.get("betrothed", false)) or not bool(row.get("adult", false)): continue
		var list: Array = Marriage.candidates(Game, str(row["person_uid"]))
		if list.is_empty(): continue
		member = row; cand = list[0]; break
	check(not member.is_empty(), "weddings: an unmarried adult of the house with a candidate")
	if member.is_empty(): return
	var a := Dynasty._person(Game, str(member["person_uid"]))
	var b := Dynasty._person(Game, str(cand["person_uid"]))
	var adult_b := int(People.ages(Persons.family_race(b["econ"], b["family"]))["adult"])
	var adult_a := int(People.ages(Persons.family_race(a["econ"], a["family"]))["adult"])
	var b_birth := float(b["person"][3])
	# Member just of age, the betrothed still a child (three years short).
	_set_age(a, float(adult_a) + 0.1)
	_set_age(b, float(adult_b) - 3.0)
	var st := Marriage.state(Game)
	st["betrothals"].append({"a": str(member["person_uid"]), "b": str(cand["person_uid"]), "day": int(Game.day), "dowry_owed": true})
	Marriage.daily(Game)
	var a2 := Dynasty._person(Game, str(member["person_uid"]))
	check(str(Persons.g(a2["person"], Persons.SPOUSE_UID, "")) == "", "weddings: no wedding while the betrothed is still a child")
	check(Marriage._betrothed(Game, str(cand["person_uid"])), "weddings: the betrothal is kept until both are of age")
	# Now the betrothed comes of age too: the wedding happens.
	_set_age(Dynasty._person(Game, str(cand["person_uid"])), float(adult_b) + 0.1)
	Marriage.daily(Game)
	var a3 := Dynasty._person(Game, str(member["person_uid"]))
	check(not a3.is_empty() and str(Persons.g(a3["person"], Persons.SPOUSE_UID, "")) == str(cand["person_uid"]), "weddings: once both are of age they wed")
	check(not Marriage._betrothed(Game, str(cand["person_uid"])), "weddings: the betrothal is closed by the wedding")
	var sp := Dynasty._person(Game, str(cand["person_uid"]))
	if not sp.is_empty(): sp["person"][3] = b_birth
	# An elf household living in a human town comes of age as elves do (40), not at the town's 16.
	var other := {}
	for o: Dictionary in Marriage.candidates(Game, str(member["person_uid"])):
		var loc := Dynasty._person(Game, str(o["person_uid"]))
		if loc.is_empty() or str(o["person_uid"]) == str(cand["person_uid"]): continue
		if Persons.race_of(loc["econ"]) == "human" and Persons.family_race(loc["econ"], loc["family"]) == "human":
			other = loc; break
	check(not other.is_empty(), "weddings: a match from a human household in a human town")
	if other.is_empty(): return
	var other_uid := str(Persons.g(other["person"], Persons.PERSON_UID, ""))
	var other_birth := float(other["person"][3])
	var had_race: bool = other["family"].has("race")
	var old_race := str(other["family"].get("race", ""))
	_set_age(other, 20.0)
	check(Marriage._of_age(Game, other), "weddings: a human of 20 is of age")
	other["family"]["race"] = "moon_elf"
	check(not Marriage._of_age(Game, other), "weddings: a moon elf of 20 in a human town is still a child")
	var listed := Marriage.candidates(Game, str(member["person_uid"])).any(func(o): return str(o["person_uid"]) == other_uid)
	check(not listed, "weddings: that elf child is not offered to an adult as a spouse")
	if had_race: other["family"]["race"] = old_race
	else: other["family"].erase("race")
	other["person"][3] = other_birth
	# One who came of age since their family's weekly turn is still listed with the children: the wedding takes
	# them from that list, and the next weekly turn does not bring a second copy into the family.
	var grown := {}
	for town in Game.world["towns"].values():
		for f in town["econ"].get("fams", []):
			if str(f.get("household_uid", "")) == "" or f == a["family"]: continue
			for k in Persons.kp_read(f):
				if int(k[2]) != int(a["person"][2]) and str(Persons.g(k, Persons.PERSON_UID, "")) != "":
					grown = {"town": town, "econ": town["econ"], "family": f, "person": k}; break
			if not grown.is_empty(): break
		if not grown.is_empty(): break
	check(not grown.is_empty(), "weddings: a household child of the other sex to grow up")
	if grown.is_empty(): return
	var gf: Dictionary = grown["family"]
	var gp: Array = grown["person"]
	var g_uid := str(Persons.g(gp, Persons.PERSON_UID, ""))
	_set_age(grown, float(People.ages(Persons.family_race(grown["econ"], gf))["adult"]) + 0.5)
	var kids0 := int(gf.get("kids", 0))
	var pp0 := Persons.pp_read(gf).size()
	var w := Marriage.wed(Game, str(member["person_uid"]), g_uid)
	var to_f: Dictionary = Dynasty._person(Game, str(member["person_uid"]))["family"]
	var copies := Persons.pp_read(to_f).filter(func(x): return str(Persons.g(x, Persons.PERSON_UID, "")) == g_uid).size()
	check(bool(w.get("ok", false)) and not Persons.kp_read(gf).has(gp) and copies == 1 and int(gf.get("kids", 0)) == kids0 - 1 and Persons.pp_read(gf).size() == pp0,
		"weddings: a just-grown spouse leaves the children's list (kids %d -> %d, %d copy)" % [kids0, int(gf.get("kids", 0)), copies])
	gf["nxa"] = -1.0
	Persons.age_up(grown["econ"], gf, float(Game.day))
	var back := Persons.pp_read(gf).filter(func(x): return str(Persons.g(x, Persons.PERSON_UID, "")) == g_uid).size()
	check(back == 0, "weddings: the next family turn does not bring a second copy back (%d)" % back)

# ------------------------------------------------------------------ 2. loot in a battle of rounds
func _fought(r: Dictionary, units: Array, states: Array, winner: int) -> void:
	r["fighter_units"] = units; r["fighter_states"] = states; r["winner"] = winner

func rounds_loot() -> void:
	var saved_round := BattleRounds.round_size
	BattleRounds.round_size = 1
	var mine := troops("middle_kingdom", 4, 9701)
	for u in mine: u.faction = "player"
	var foes := troops("northern_clans", 4, 9702)
	var fled_once: Unit = foes[0]      # flees round 1, never fights again
	var stood: Unit = foes[1]          # fights round 2 unhurt, then his army breaks
	var killed: Unit = foes[2]         # dies in round 3
	var fled_then_killed: Unit = foes[3]   # flees round 1... and dies in round 4
	Game.pending_battle = {"seed": 97, "enemy": foes}
	BattleRounds.begin(Game, mine, foes)
	BattleRounds.after_round(Game, _round([mine[0], fled_once, fled_then_killed], ["fighting", "fled", "fled"], 0))
	BattleRounds.next_round(Game)
	BattleRounds.after_round(Game, _round([mine[1], stood], ["fighting", "fighting"], 0))
	BattleRounds.next_round(Game)
	killed.dead = true
	BattleRounds.after_round(Game, _round([mine[2], killed], ["fighting", "dead"], 0))
	BattleRounds.next_round(Game)
	fled_then_killed.dead = true
	BattleRounds.after_round(Game, _round([mine[3], fled_then_killed], ["fighting", "dead"], 0))
	var st: Dictionary = Game.pending_battle["rounds"]
	st["winner"] = 0; st["over"] = true
	var r := BattleRounds.final_result(Game, {})
	var left := Loot.left_the_field(r)
	check((r["enemy_fled"] as Array).has(fled_once) and not (r["enemy_fled"] as Array).has(stood), "loot: the man whose latest round ended in flight is reported fled")
	check(left.has(fled_once) and left.has(stood), "loot: the fled man and the man who left with his beaten army are off the field")
	check(not left.has(killed) and not left.has(fled_then_killed), "loot: the dead (also one who fled earlier and died later) stay on the field")
	var kit := {}
	for u in foes: kit[u] = u.equip.size()
	var enemies: Array = (r["enemy_units"] as Array).filter(func(x): return x is Unit)
	Loot.spoils(enemies, left, 77, 0.5, "test")
	check(fled_once.equip.size() == int(kit[fled_once]) and stood.equip.size() == int(kit[stood]), "loot: men who left the field keep their kit (%d, %d pieces)" % [fled_once.equip.size(), stood.equip.size()])
	check(int(kit[killed]) == 0 or killed.equip.size() < int(kit[killed]), "loot: the dead are stripped (%d -> %d pieces)" % [int(kit[killed]), killed.equip.size()])
	BattleRounds.round_size = saved_round
	Game.pending_battle = {}

func _round(units: Array, states: Array, winner: int) -> Dictionary:
	var r := {}
	_fought(r, units, states, winner)
	r["side_names"] = ["Your army", "Enemy"]
	return r

# ------------------------------------------------------------------ 3. hurt dragons and riders between rounds
func dragons(tid: String) -> void:
	var ruler_uid := str(Dynasty.selected(Game).get("ruler_uid", ""))
	var owner := Dragons._person(Game, ruler_uid)
	Game.world["dragons"] = {"schema": 1, "next_id": 1, "records": {}, "pairs": {}, "initialized": true}
	var rec := Dragons._make(Game, "adult", tid, owner, "v097:hurt", 0, "female")
	DragonCombat.prepare_world(Game)
	var d: Unit = DragonCombat._unit(Game, str(rec["id"]))
	check(d != null and BattleRounds._can_fight(Game, d), "dragons: a whole adult dragon can fight")
	if d == null: return
	var fresh: Dictionary = d.body.to_dict()
	cripple(d)
	check(str(HealthReport.describe(d).get("fitness", "")) == "cannot fight" and not d.dead, "dragons: the bled dragon is alive but cannot fight")
	check(not BattleRounds._can_fight(Game, d), "dragons: a dragon that cannot fight is not fit for a round")
	var saved_round := BattleRounds.round_size
	BattleRounds.round_size = 2
	var mine := troops("middle_kingdom", 3, 9711)
	for u in mine: u.faction = "player"
	var pool: Array = [d] + mine
	Game.pending_battle = {"seed": 98, "enemy": troops("northern_clans", 3, 9712)}
	BattleRounds.begin(Game, pool, Game.pending_battle["enemy"])
	check(not (Game.pending_battle["round_side0"] as Array).has(d), "dragons: the badly hurt dragon is not sent into the round")
	d.body = BodyState.from_dict(fresh.duplicate(true))
	BattleRounds.next_round(Game)
	var picked: Array = Game.pending_battle["round_side0"]
	check(BattleRounds.fit(Game, pool, []).has(d), "dragons: once whole it is fit again (%d picked)" % picked.size())
	BattleRounds.round_size = saved_round
	# The rider: a bound rider too badly hurt to fight is not seated; whole, he is.
	var rider: Unit = Dynasty.bound_unit(Game, Dynasty.person(Game, ruler_uid))
	if rider == null:
		var enlisted := Mobilization.enlist_household(Game, ruler_uid)
		if bool(enlisted.get("ok", false)): rider = enlisted["unit"]
	check(rider != null, "dragons: the ruler has a Unit to ride as")
	if rider == null:
		Game.pending_battle = {}
		return
	rec["rider_person_uid"] = ruler_uid
	DragonCombat.sync_profile(Game, str(rec["id"]))
	Game.pending_battle = {"seed": 99}
	var seats := DragonCombat.battle_riders(Game, [d])
	check(seats.has(str(d.uid)) and seats[str(d.uid)]["unit"] == rider, "dragons: a whole rider is seated on his dragon")
	var rider_fresh: Dictionary = rider.body.to_dict()
	cripple(rider)
	seats = DragonCombat.battle_riders(Game, [d])
	check(not seats.has(str(d.uid)), "dragons: a rider who cannot fight is not seated (the dragon fights riderless)")
	rider.body = BodyState.from_dict(rider_fresh.duplicate(true))
	# A whole rider deployed with the army stays out with his badly hurt dragon (not sent in on foot).
	var foot := troops("middle_kingdom", 2, 9713)
	var with_rider: Array = [d, rider] + foot
	check(BattleRounds.fit(Game, with_rider, []).has(rider), "dragons: with his dragon whole, the deployed rider is fit")
	cripple(d)
	var fit_now := BattleRounds.fit(Game, with_rider, [])
	check(not fit_now.has(rider) and not fit_now.has(d) and fit_now.size() == foot.size(), "dragons: the rider of a badly hurt dragon stays out with it")
	d.body = BodyState.from_dict(fresh.duplicate(true))
	Game.pending_battle = {}

# ------------------------------------------------------------------ 4. house improvements
func improvements() -> void:
	var uid := str(Game.world.get("player_house", {}).get("household_uid", ""))
	var home: Dictionary = HouseUpkeep._resolve_household(Game, uid)
	check(not home.is_empty(), "improvements: the player's household is found")
	if home.is_empty(): return
	var e: Dictionary = home["town"]["econ"]
	var f: Dictionary = home["family"]
	HouseUpkeep.ensure(Game, home["town"], e, f)
	f["improvements"] = {}
	f["purse"] = 10000000.0
	var st: Dictionary = e["stock"]
	var saved := {"wood": st.get("wood", 0), "stone": st.get("stone", 0), "tools": st.get("tools", 0)}
	st["wood"] = 50; st["stone"] = 50; st["tools"] = 0   # manor_hall level 1 needs wood, stone and one set of tools
	var prev := HouseUpkeep.improvement_preview(Game, uid, "manor_hall")
	check(not bool(prev.get("ok", true)) and not bool(prev.get("stock_ok", true)), "improvements: preview refuses when tools are missing (%s)" % str(prev.get("reason", "")))
	check(str(prev.get("reason", "")).contains("tools"), "improvements: the reason names the missing material")
	var purse0 := float(f["purse"])
	var built := HouseUpkeep.start_improvement(Game, uid, "manor_hall", prev.get("review", {}))
	check(not bool(built.get("ok", true)) and int(st["wood"]) == 50 and int(st["stone"]) == 50 and absf(float(f["purse"]) - purse0) < 0.001 and not f["improvements"].has("manor_hall"), "improvements: nothing is built, taken or charged when one material is short")
	st["tools"] = 5
	var prev2 := HouseUpkeep.improvement_preview(Game, uid, "manor_hall")
	check(bool(prev2.get("ok", false)), "improvements: with every material in stock the preview is ready")
	var built2 := HouseUpkeep.start_improvement(Game, uid, "manor_hall", prev2.get("review", {}))
	check(bool(built2.get("ok", false)) and int(st["tools"]) == 4, "improvements: it builds and takes the full set")
	for g in saved: st[g] = saved[g]

# ------------------------------------------------------------------ 5. Court lists
func court_lists() -> void:
	var court: Control = CourtScreen.new()
	var box := VBoxContainer.new()
	var items: Array = range(95)
	var added: Array = []
	court._paged_rows(box, items, 40, func(i):
		added.append(i)
		box.add_child(Label.new()))
	check(added.size() == 40 and box.get_child_count() == 41 and box.get_child(40).name == "ShowMoreButton", "court: the first page lists 40 and offers Show more")
	(box.get_child(40) as Button).pressed.emit()
	var more_buttons := box.get_children().filter(func(n): return n.name == "ShowMoreButton" and not n.is_queued_for_deletion())
	check(added.size() == 80 and more_buttons.size() == 1, "court: Show more lists the next 40 in place")
	(more_buttons[0] as Button).pressed.emit()
	var left_buttons := box.get_children().filter(func(n): return n.name == "ShowMoreButton" and not n.is_queued_for_deletion())
	check(added.size() == 95 and added == items and left_buttons.is_empty(), "court: every entry is reachable, in order, and the button goes")
	box.free(); court.free()
	# Marriage matches are no longer cut off at 24 before they reach the Court list.
	var most := 0
	for row: Dictionary in Marriage.family(Game):
		most = maxi(most, Marriage.candidates(Game, str(row["person_uid"])).size())
	print("  largest match list in this world: %d (no longer cut at 24; Court pages it 24 at a time)" % most)

# ------------------------------------------------------------------ 6. Records text
func records_text() -> void:
	var note := RecPages.research_note()
	check(Academy.materials().has("charcoal") and not Academy.materials().has("wood"), "records: research trials buy charcoal, not wood")
	check(note.contains("charcoal") and not note.contains("wood"), "records: the Research card says charcoal (%s)" % note)
	# A caravan counts as travelling with pack donkeys only while its pack herd has a living animal.
	var herd_town := ""
	for tid in Game.world["towns"]:
		if Game.world["towns"][tid].get("econ", {}).has("hd"): herd_town = str(tid); break
	check(herd_town != "", "records: a town keeps herds")
	if herd_town != "":
		var hh: Dictionary = Game.world["towns"][herd_town]["econ"]["hd"]["h"]
		var hid := "97097"
		hh[hid] = {"id": int(hid), "k": "donkeys", "ow": "s", "oi": 0, "work_band": "v097-caravan", "y": 0, "g": 3, "o": 0}
		var wb := {"id": "v097-caravan", "kind": "caravan", "origin": herd_town, "pack_herd": hid}
		check(RecWorld.has_pack_animals(wb), "records: a caravan with 3 pack donkeys counts")
		hh[hid]["g"] = 0
		check(not RecWorld.has_pack_animals(wb), "records: a caravan whose pack donkeys all died does not count")
		hh.erase(hid)
	var carriers := RecWorld.carriers_text(2)
	check(not carriers.contains("no pack animals") and carriers.contains("pack donkeys"), "records: the Carriers line names pack donkeys (%s)" % carriers)
