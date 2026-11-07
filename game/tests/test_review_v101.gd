extends RefCounted
## v0.101: tests for review findings F1–F5 (test-results/v0.101/findings.md).
const U = preload("res://tests/sim_util.gd")
const WorldMapScene = preload("res://campaign/world_map.gd")
const BattleScene = preload("res://battle/battle.gd")

var checks := 0
var fails := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	if ok: print("ok   ", what)
	else:
		fails += 1
		print("FAIL ", what)

func run(tree: SceneTree) -> int:
	if Game.world.is_empty() or not Game.world.has("towns"):
		Game.new_game()
	var saved_world: Dictionary = Game.world
	var saved_day: float = Game.day
	var saved_pb: Dictionary = Game.pending_battle.duplicate(true)
	var saved_loc: String = Game.location
	var saved_company: Array = Game.company.duplicate()
	_test_f1_ai_age_gap()
	_test_f2_betrothal_window()
	_test_f5_cross_race_spouse()
	_test_f3_mounted_pool_rider_accounting()
	Game.world = saved_world
	Game.day = saved_day
	Game.pending_battle = saved_pb
	Game.location = saved_loc
	Game.company = saved_company
	Dynasty.note_households_changed()
	await _test_f4_landscape_ui_layouts(tree)
	print("v101 checks %d, failures %d" % [checks, fails])
	return fails

func _make_person(e: Dictionary, f: Dictionary, pid: int, name_idx: int, sex: int, age_years: float, day: float, kind: int = 0) -> Array:
	var born := int(round(day - age_years * People.year_days()))
	var p := [pid, name_idx, sex, born, "", -1, kind, "", -1, -1, -1, "", []]
	Persons.identity(e, f, p)
	return p

func _make_town(tid: String, tname: String, faction: String, race: String, culture: String, day: float) -> Dictionary:
	var e := {
		"day": day, "race": race, "culture": culture, "faction": faction,
		"identity_scope": "1:%s" % tid, "next_pid": 100, "next_fid": 10,
		"pop": 3, "adults": 3, "idle_n": 0, "hands": 0, "homes": 3, "treasury": 1000.0,
		"fams": [], "biz": [], "open": [], "head": {}, "dead_log": [],
		"stats": {"deaths": 0, "births": 0, "sales": 0.0, "gold_left": 0.0},
		"census": {"births": [], "deaths": [], "marriages": [], "arrivals": [], "departures": []}
	}
	return {"id": tid, "name": tname, "faction": faction, "pos": Vector2(100, 100), "econ": e, "shop": [], "goods": {}}

func _make_noble_family(e: Dictionary, fid: int, hname: String, tid: String, race: String, day: float, child_sex: int, child_age: float, child_kind: int = 0) -> Dictionary:
	var f := {
		"id": fid, "name": hname, "race": race, "tier": "rich", "cls": 2, "job": "ruler",
		"named": true, "purse": 5000.0, "m": 2, "f": 0, "kids": 0, "old": 0,
		"homes": 2, "cond": 1.0, "hungry": 0, "unpaid": 0, "idle": 0, "debt": 0.0,
		"hands": 0, "worked": 0.0, "land": {}, "herd": {}, "jobs": {}, "owns": [], "keeps": [],
		"store": {"food": 14.0, "drink": 14.0, "wood": 14.0}, "wear": {}, "cum": {}, "serve": {},
		"hist": [], "pp": [], "kp": [], "dp": [], "seed": fid * 100 + 7
	}
	Families.identity(e, f)
	var head_age := 160.0 if race == "elf" else 42.0
	var heir_age := 120.0 if race == "elf" else 24.0
	var head := _make_person(e, f, fid * 10 + 1, 0, 0, head_age, day, 0)
	var heir := _make_person(e, f, fid * 10 + 2, 1, 0, heir_age, day, 0)
	var match_p := _make_person(e, f, fid * 10 + 3, 2, child_sex, child_age, day, child_kind)
	heir[Persons.FA] = int(head[0])
	match_p[Persons.FA] = int(head[0])
	f["pp"].append(head)
	f["pp"].append(heir)
	if child_kind == 2:
		f["kp"].append(match_p)
		f["kids"] = 1
	elif child_kind == 1:
		f["pp"].append(match_p)
		f["old"] = 1
	else:
		f["pp"].append(match_p)
		var sk := "f" if child_sex == 1 else "m"
		f[sk] = int(f[sk]) + 1
	for p in f["pp"] + f["kp"]:
		Persons.identity_kin(e, p)
	e["fams"].append(f)
	e["head"] = {
		"fam": fid, "pid": int(head[0]), "name": Persons.name_of(f, head, race),
		"person_uid": str(head[Persons.PERSON_UID]), "house_uid": str(head[Persons.HOUSE_UID]),
		"household_uid": str(f["household_uid"]), "home_town": tid, "title": "Lord"
	}
	return {"family": f, "head": head, "heir": heir, "member": match_p}

func _test_f1_ai_age_gap() -> void:
	var day := 36000.0
	Game.day = day
	var tp := _make_town("t_player", "Playerkeep", "f_hum", "human", "middle", day)
	var hp := _make_noble_family(tp["econ"], 1, "Valen", "t_player", "human", day, 0, 22.0)
	var te1 := _make_town("t_elf1", "Sylvanor", "f_elf", "elf", "high", day)
	var he1 := _make_noble_family(te1["econ"], 2, "Aelintar", "t_elf1", "elf", day, 0, 80.0)
	var te2 := _make_town("t_elf2", "Lorien", "f_elf", "elf", day_culture("elf"), day)
	var he2 := _make_noble_family(te2["econ"], 3, "Caelond", "t_elf2", "elf", day, 1, 110.0)
	var th1 := _make_town("t_hum1", "Oakhaven", "f_hum", "human", "middle", day)
	var hh1 := _make_noble_family(th1["econ"], 4, "Bram", "t_hum1", "human", day, 0, 20.0)
	var th2 := _make_town("t_hum2", "Redford", "f_hum", "human", "middle", day)
	var hh2 := _make_noble_family(th2["econ"], 5, "Dorn", "t_hum2", "human", day, 1, 40.0)
	Game.world = {
		"seed": 1, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
		"towns": {"t_player": tp, "t_elf1": te1, "t_elf2": te2, "t_hum1": th1, "t_hum2": th2},
		"player_house": {
			"town_id": "t_player", "house_uid": str(hp["head"][Persons.HOUSE_UID]),
			"household_uid": str(hp["family"]["household_uid"]), "ruler_uid": str(hp["head"][Persons.PERSON_UID]),
			"ruler_race": "human"
		}
	}
	Dynasty.prepare_world(Game)
	var hum_groom_uid := str(hh1["member"][Persons.PERSON_UID])
	var hum_bride_uid := str(hh2["member"][Persons.PERSON_UID])
	var hum_res := Marriage.try_ai_match(Game, hum_groom_uid, hum_bride_uid)
	check(not bool(hum_res.get("ok", true)) and str(hum_res.get("reason", "")).contains("age gap"),
		"F1: two humans aged 20 and 40 fail the AI age gate (%s)" % str(hum_res.get("reason", "")))
	var elf_groom_uid := str(he1["member"][Persons.PERSON_UID])
	var elf_bride_uid := str(he2["member"][Persons.PERSON_UID])
	var elf_res := Marriage.try_ai_match(Game, elf_groom_uid, elf_bride_uid)
	check(bool(elf_res.get("ok", false)),
		"F1: two elves aged 80 and 110 pass try_ai_match (%s)" % str(elf_res))
	# Also verify arrange_ai matches an 80-year-old elf and a 110-year-old elf, while rejecting 20 vs 40 humans.
	var ph: Dictionary = Game.world["player_house"].duplicate(true)
	var te3 := _make_town("t_elf3", "Sylvanor", "f_elf", "elf", "high", day)
	_make_noble_family(te3["econ"], 2, "Aelintar", "t_elf3", "elf", day, 0, 80.0)
	var te4 := _make_town("t_elf4", "Lorien", "f_elf", "elf", "high", day)
	_make_noble_family(te4["econ"], 3, "Caelond", "t_elf4", "elf", day, 1, 110.0)
	Game.world = {
		"seed": 2, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
		"towns": {"t_player": tp, "t_elf3": te3, "t_elf4": te4},
		"player_house": ph
	}
	Dynasty.prepare_world(Game)
	var arr_elf := Marriage.arrange_ai(Game)
	check(bool(arr_elf.get("arranged", false)),
		"F1: arrange_ai weds two elves aged 80 and 110 (%s)" % str(arr_elf))

func day_culture(_race: String) -> String:
	return "high"

func _test_f2_betrothal_window() -> void:
	var day := 36000.0
	Game.day = day
	var te1 := _make_town("t_elf_home", "Sylvanor", "f_elf", "elf", "high", day)
	var he1 := _make_noble_family(te1["econ"], 1, "Aelintar", "t_elf_home", "elf", day, 0, 30.0, 2)
	var te2 := _make_town("t_elf_other", "Lorien", "f_elf", "elf", "high", day)
	var he2 := _make_noble_family(te2["econ"], 2, "Caelond", "t_elf_other", "elf", day, 1, 30.0, 2)
	Game.world = {
		"seed": 3, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
		"towns": {"t_elf_home": te1, "t_elf_other": te2},
		"player_house": {
			"town_id": "t_elf_home", "house_uid": str(he1["head"][Persons.HOUSE_UID]),
			"household_uid": str(he1["family"]["household_uid"]), "ruler_uid": str(he1["head"][Persons.PERSON_UID]),
			"ruler_race": "elf"
		}
	}
	Dynasty.prepare_world(Game)
	var child_uid := str(he1["member"][Persons.PERSON_UID])
	var win := Marriage.betrothal_window("elf")
	check(win.x <= 30 and 30 < 40 and win.y > 40,
		"F2: elf betrothal_window (%s) covers age 30" % str(win))
	check(win.x >= 20 and Marriage.betrothal_window("human") == Vector2i(10, 20),
		"F2: no infant betrothals for long-lived races (elf from %d); humans keep 10..20 (%s)" % [win.x, str(Marriage.betrothal_window("human"))])
	var fam_rows := Marriage.family(Game)
	var child_row := {}
	for r in fam_rows:
		if str(r.get("person_uid", "")) == child_uid:
			child_row = r
			break
	var cands := Marriage.candidates(Game, child_uid)
	check(bool(child_row.get("can_betroth", false)) and not cands.is_empty(),
		"F2: elf child of 30 is advertised can_betroth=%s and has %d candidate(s)" % [str(child_row.get("can_betroth", false)), cands.size()])
	# Check agreement between Marriage.family and Marriage.candidates at adult boundary (age 40):
	# UI uses can_betroth for adult spouse searches too, and adult=true at 40.
	he1["member"][3] = int(round(day - 40.0 * People.year_days()))
	he1["member"][6] = 0
	he1["family"]["kp"].erase(he1["member"])
	he1["family"]["pp"].append(he1["member"])
	he1["family"]["kids"] = 0
	he1["family"]["m"] = int(he1["family"]["m"]) + 1
	he2["member"][3] = int(round(day - 40.0 * People.year_days()))
	he2["member"][6] = 0
	he2["family"]["kp"].erase(he2["member"])
	he2["family"]["pp"].append(he2["member"])
	he2["family"]["kids"] = 0
	he2["family"]["f"] = int(he2["family"]["f"]) + 1
	var fam_adult := Marriage.family(Game)
	var adult_row := {}
	for r in fam_adult:
		if str(r.get("person_uid", "")) == child_uid:
			adult_row = r
			break
	var adult_cands := Marriage.candidates(Game, child_uid)
	check(bool(adult_row.get("adult", false)) and bool(adult_row.get("can_betroth", false)) and not adult_cands.is_empty(),
		"F2: at elf adulthood (40), adult is true, can_betroth stays true for spouse search, and candidates match (%d)" % adult_cands.size())

func _test_f3_mounted_pool_rider_accounting() -> void:
	var day := 36000.0
	Game.day = day
	var saved_pb: Dictionary = Game.pending_battle.duplicate(true)
	var saved_company: Array = Game.company.duplicate()
	var t_f3 := _make_town("t_f3", "Valorhall", "f_hum", "human", "middle", day)
	var e_f3: Dictionary = t_f3["econ"]
	var h_f3 := _make_noble_family(e_f3, 1, "Valen", "t_f3", "human", day, 0, 26.0, 0)
	var f_f3: Dictionary = h_f3["family"]
	var p_rider: Array = h_f3["member"]
	var rider_uid := str(p_rider[Persons.PERSON_UID])
	Game.world = {
		"seed": 42, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
		"towns": {"t_f3": t_f3},
		"player_house": {
			"town_id": "t_f3", "house_uid": str(h_f3["head"][Persons.HOUSE_UID]),
			"household_uid": str(f_f3["household_uid"]), "ruler_uid": str(h_f3["head"][Persons.PERSON_UID]),
			"ruler_race": "human"
		}
	}
	Dynasty.prepare_world(Game)
	var u_foot := U.soldier("copper", "arming_sword", "", "", "")
	u_foot.name = "Footman Hal"
	var u_rider := U.soldier("copper", "arming_sword", "", "", "")
	u_rider.home_town = "t_f3"
	Persons.bind(e_f3, f_f3, p_rider, u_rider, "company", day)
	f_f3["m"] = maxi(0, int(f_f3["m"]) - 1)
	u_rider.name = "Lord Commander Valen"
	u_rider.role = "captain"
	u_rider.rank = 3
	u_rider.set_meta("house_member", true)
	Game.company = [u_foot, u_rider]
	var u_foe := U.soldier("copper", "arming_sword", "", "", "")
	u_foe.name = "Enemy Footman"
	var u_dragon := Unit.create("dragon", "f_hum", false)
	u_dragon.dragon_uid = "drg_test_1"
	u_dragon.name = "Vaelor"
	Game.pending_battle = {"seed": 42}
	BattleRounds.begin(Game, [u_foot, u_rider], [u_foe])
	var st: Dictionary = Game.pending_battle["rounds"]
	st["commander"][0] = u_rider.uid
	# Rider is in st["pool"][0], seated on a dragon off-round (not in fighter_units), and killed while mounted.
	var r := {
		"winner": 0,
		"side_names": ["Your army", "Enemy"],
		"fighter_units": [u_foot, u_foe],
		"fighter_states": ["alive", "dead"],
		"dragon_downs": {},
		"dragon_seats": {
			"drg_test_1": {
				"person_uid": rider_uid,
				"unit": u_rider,
				"joined": true,
				"detached": false,
				"dead": true,
				"state": "dead",
				"damage": 60.0
			}
		}
	}
	u_foe.dead = true
	var d := BattleRounds.after_round(Game, r)
	var hh_matches := (d["household"] as Array).filter(func(row): return str(row.get("name", "")) == u_rider.name)
	check(int(d["fought"][0]) == 2 and int(d["dead"][0]) == 1 and int(st["dead"][0]) == 1,
		"F3: seated pool rider is counted once in round fought (%d) and dead (%d)" % [int(d["fought"][0]), int(d["dead"][0])])
	check(int(d["morale_change"][0]) < 0,
		"F3: seated pool commander/officer loss applies nerve morale penalty (morale_change=%d)" % int(d["morale_change"][0]))
	check(hh_matches.size() == 1 and str(hh_matches[0].get("fate", "")) == "dead",
		"F3: seated pool rider appears once in round household list (%d)" % hh_matches.size())
	# Reversion check for dragon_combat._rider_result: a dead off-round seated rider now in final_result["player_units"]
	# must be settled once overall (by the finish_battle roster pass, not a second time in DragonCombat._rider_result).
	var final_r := BattleRounds.final_result(Game, r)
	var deaths_before := int(e_f3["stats"].get("deaths", 0))
	var rr := DragonCombat._rider_result(Game, final_r, {"rider_person_uid": rider_uid, "damage_before": 0.0, "flying": false}, u_dragon, 42)
	var roster_hits := 0
	for u in final_r.get("player_units", []):
		if u is Unit and u.dead:
			roster_hits += 1
			People.casualty(Game, u, "dead")
	var total_settled := (0 if rr.is_empty() else 1) + roster_hits
	var deaths_recorded := int(e_f3["stats"].get("deaths", 0)) - deaths_before
	check(rr.is_empty() and total_settled == 1 and deaths_recorded == 1,
		"F3: dead off-round seated rider is settled once overall (rr_empty=%s, settled=%d, deaths=%d)" % [str(rr.is_empty()), total_settled, deaths_recorded])
	Game.company = saved_company
	Game.pending_battle = saved_pb

func _test_f4_landscape_ui_layouts(tree: SceneTree) -> void:
	if Game.world.is_empty() or not Game.world.has("towns"):
		Game.new_game()
	UiTheme.set_mobile_override(true)
	check(UiTheme.is_mobile(), "F4: UiTheme.set_mobile_override(true) forces phone/mobile layout path")
	for sz in [Vector2i(844, 390), Vector2i(1280, 720)]:
		var svp := SubViewport.new()
		svp.size = sz
		tree.root.add_child(svp)
		var wm: Node2D = WorldMapScene.new()
		svp.add_child(wm)
		wm._layout_hud()
		await tree.process_frame
		await tree.process_frame
		wm._layout_hud()
		var nav_scroll_ok: bool = wm.bottom_nav.get_child_count() > 0 and wm.bottom_nav.get_child(0) is ScrollContainer and (wm.bottom_nav.get_child(0) as ScrollContainer).horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
		var top_bottom: float = wm.top_panel.position.y + wm.top_panel.size.y
		var card_ok: bool = not wm.ruler_card.visible or (wm.ruler_card.position.y >= top_bottom and wm.ruler_card.position.y + wm.ruler_card.size.y <= wm.bottom_nav.position.y)
		if sz.y >= 720:
			card_ok = card_ok and wm.ruler_card.visible
		check(card_ok and nav_scroll_ok,
			"F4a (%dx%d): map ruler_card fits or hides without overlapping top_panel (vis=%s, y=%.1f, top_b=%.1f, nav_y=%.1f)" % [sz.x, sz.y, str(wm.ruler_card.visible), wm.ruler_card.position.y, top_bottom, wm.bottom_nav.position.y])
		if sz.x == 844:
			wm.lbl_contract.text = "Contract: Hunt the brigand warband near Oakhaven (5 days remaining)"
			wm.lbl_contract.visible = true
			wm._layout_hud()
			await tree.process_frame
			await tree.process_frame
			wm._layout_hud()
			var top_b_contract: float = wm.top_panel.position.y + wm.top_panel.size.y
			var contract_ok: bool = not wm.ruler_card.visible or (wm.ruler_card.position.y >= top_b_contract and wm.ruler_card.position.y + wm.ruler_card.size.y <= wm.bottom_nav.position.y)
			check(contract_ok,
				"F4a (844x390 contract): ruler_card hides instead of overlapping top_panel (vis=%s, y=%.1f, top_b=%.1f)" % [str(wm.ruler_card.visible), wm.ruler_card.position.y, top_b_contract])
		svp.remove_child(wm)
		wm.free()

		var saved_pb: Dictionary = Game.pending_battle.duplicate(true)
		var s0 := U.soldier("copper", "arming_sword", "", "", "")
		s0.name = "Captain Aldric of the Golden Vanguard"
		var s1 := U.soldier("copper", "arming_sword", "", "", "")
		s1.name = "Dread Warlord Gorgash of the Iron Crags"
		Game.pending_battle = {"round_side0": [s0], "enemy": [s1], "seed": 7}
		var b: Node2D = BattleScene.new()
		svp.add_child(b)
		for i in 6:
			b._add_feed({"type": "sever", "actor": 0, "target": 1, "part": "arm_l", "damage": 18.0})
		b._layout_diagnostics()
		await tree.process_frame
		await tree.process_frame
		b._layout_diagnostics()
		var feed_bottom: float = b.feed_box.position.y + b.feed_box.size.y
		var feed_right: float = b.feed_box.position.x + b.feed_box.size.x
		check(feed_bottom <= float(sz.y) and feed_right <= float(sz.x) and b.feed_box.get_child_count() >= 1,
			"F4b (%dx%d): wrapped mobile battle toasts fit inside viewport (right=%.1f <= %d, bottom=%.1f <= %d, count=%d)" % [sz.x, sz.y, feed_right, sz.x, feed_bottom, sz.y, b.feed_box.get_child_count()])
		svp.remove_child(b)
		b.free()
		Game.pending_battle = saved_pb

		tree.root.remove_child(svp)
		svp.free()

	var host := Control.new()
	var any_town: Dictionary = Game.world["towns"].values()[0] if not Game.world.get("towns", {}).is_empty() else {"shop": [], "goods": {}, "econ": {}}
	var market_root := TownMarketTab.build(host, any_town)
	var market_sc: ScrollContainer = null
	for c in market_root.get_children():
		if c is ScrollContainer:
			market_sc = c as ScrollContainer
			break
	check(market_sc != null and market_sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
		"F4c: TownMarketTab stock scroll enables horizontal scrolling")
	market_root.free()
	host.free()
	UiTheme.set_mobile_override(null)

func _test_f5_cross_race_spouse() -> void:
	var day := 36000.0
	Game.day = day
	var th := _make_town("t_hum_seat", "Oakhaven", "f_hum", "human", "middle", day)
	var hh := _make_noble_family(th["econ"], 1, "Valen", "t_hum_seat", "human", day, 0, 25.0)
	var te := _make_town("t_elf_seat", "Sylvanor", "f_elf", "elf", "high", day)
	# Elf bride aged 75: young adult for an elf (adult=40, elder=300, max=390), but past human elder (55) and near human max (82).
	var he := _make_noble_family(te["econ"], 2, "Aelintar", "t_elf_seat", "elf", day, 1, 75.0)
	Game.world = {
		"seed": 5, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
		"towns": {"t_hum_seat": th, "t_elf_seat": te},
		"player_house": {
			"town_id": "t_hum_seat", "house_uid": str(hh["head"][Persons.HOUSE_UID]),
			"household_uid": str(hh["family"]["household_uid"]), "ruler_uid": str(hh["head"][Persons.PERSON_UID]),
			"ruler_race": "human"
		}
	}
	Dynasty.prepare_world(Game)
	var groom_uid := str(hh["member"][Persons.PERSON_UID])
	var bride_uid := str(he["member"][Persons.PERSON_UID])
	var w := Marriage.wed(Game, groom_uid, bride_uid)
	check(bool(w.get("ok", false)), "F5: cross-race wedding between human groom and elf bride succeeds")
	var bride_row := Dynasty.person(Game, bride_uid)
	check(str(bride_row.get("race", "")) == "elf",
		"F5: married-in elf spouse in human household keeps her own 'elf' race (got '%s')" % str(bride_row.get("race", "")))
	# Advance 30 years (bride reaches age 105, well past human max age 82) and run Persons.age_up(e, f, day) each year.
	var f_hum: Dictionary = hh["family"]
	var e_hum: Dictionary = th["econ"]
	for yr in 30:
		Game.day += People.year_days()
		e_hum["day"] = Game.day
		Persons.age_up(e_hum, f_hum, Game.day)
	var after_row := Dynasty.person(Game, bride_uid)
	check(bool(after_row.get("alive", false)) and str(after_row.get("race", "")) == "elf" and int(after_row.get("age", 0)) >= 104,
		"F5: elf spouse in human household ages by elf rules and survives at age %d (alive=%s, race=%s)" % [int(after_row.get("age", 0)), str(after_row.get("alive", false)), str(after_row.get("race", ""))])
	# F5(a): weekly elder mortality in Families._people uses each elder's own race, not the town/household human race.
	var f_mort := _make_noble_family(e_hum, 6, "MortTest", "t_hum_seat", "human", Game.day, 1, 310.0, 1)["family"]
	var p_elf_elder: Array = (f_mort["pp"] as Array)[2]
	Persons.set_person_race(p_elf_elder, "elf")
	var yd := float(EconGen.YEAR_DAYS)
	var ab_hum := People.ages("human")
	var ab_elf := People.ages("elf")
	var po_hum := 7.0 / (Families.ELDER_MEAN * maxf(1.0, float(ab_hum["lifespan"]) - float(ab_hum["elder"])) * yd)
	var po_elf := 7.0 / (Families.ELDER_MEAN * maxf(1.0, float(ab_elf["lifespan"]) - float(ab_elf["elder"])) * yd)
	var rng_probe := RandomNumberGenerator.new()
	rng_probe.seed = 98765
	var r0 := rng_probe.randf()
	var rng_run := RandomNumberGenerator.new()
	rng_run.seed = 98765
	# Choose ev_mult so r = r0 / ev_mult lies strictly between po_elf and po_hum: dies under human rules, survives under elf rules.
	var ev_mult := r0 / ((po_elf + po_hum) * 0.5)
	var cul: Dictionary = TownEcon.culture_of(e_hum)
	Families._people(th, e_hum, f_mort, cul, Game.day, rng_run, ev_mult)
	check((f_mort["pp"] as Array).has(p_elf_elder) and int(f_mort["old"]) == 1,
		"F5a: per-elder weekly mortality in Families._people uses elf elder's own race (po_elf=%.6f < po_hum=%.6f)" % [po_elf, po_hum])
	# F5(b): set_person_race pads RESEARCH (index 20) with null so Academy._training still rolls seeded aptitude.
	var p_sch := _make_person(e_hum, f_hum, 901, 0, 0, 30.0, Game.day, 0)
	Persons.set_person_race(p_sch, "elf")
	var research_null_ok: bool = p_sch.size() > Persons.RACE and p_sch[Persons.RESEARCH] == null and absf(Academy._skill(p_sch, 2.5) - 2.5) < 1e-6
	var apt_rng := RandomNumberGenerator.new()
	apt_rng.seed = hash([Persons.g(p_sch, Persons.PERSON_UID, ""), int(p_sch[0]), float(p_sch[3]), "research aptitude"])
	var expected_apt := apt_rng.randf_range(0.9, 1.1)
	var tr := Academy._training(p_sch, 2.5)
	check(research_null_ok and absf(float(tr.get("aptitude", 0.0)) - expected_apt) < 1e-6,
		"F5b: set_person_race leaves RESEARCH null and Academy._training rolls seeded aptitude (%.4f == %.4f)" % [float(tr.get("aptitude", 0.0)), expected_apt])
	# F5(c): a person array of the old length (no index 21) still reads family_race.
	var p_old := _make_person(e_hum, f_hum, 902, 0, 0, 28.0, Game.day, 0)
	var f_dwarf := {"id": 99, "name": "Ironbeard", "race": "dwarf"}
	check(p_old.size() <= Persons.RACE and Persons.person_race(e_hum, f_dwarf, p_old) == "dwarf" and Persons.person_race(e_hum, {}, p_old) == "human",
		"F5c: legacy person array without index 21 (size=%d) falls back to family_race ('%s')" % [p_old.size(), Persons.person_race(e_hum, f_dwarf, p_old)])
