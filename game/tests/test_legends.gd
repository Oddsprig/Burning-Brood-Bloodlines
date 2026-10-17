extends RefCounted
## v0.014 legendary items and gems (docs/specs/next/03-legendary-items.md; Douglas 22:31-23:00): the refit quality
## curve (masterwork 1.4% at skill 10, 25% at 15), legendary = masterwork / 25 (1% at 15), the 5-a-life cap, the gem
## from real stock, the name, description and icon, never lost and always passed to the winner (player and AI),
## gem pockets in mines at the set rate, families buying stones and selling them when hungry.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	_test_curve()
	Game.SAVE_PATH = "user://test_save_legends_%d.json" % OS.get_process_id()
	Game.new_game(3131)
	_test_forge_cap_gem()
	_test_name_icon()
	_test_never_lost()
	_test_no_gear_damage()
	_test_mine_gems()
	_test_family_gems()
	return fails

func _rate(skill: float, n: int, legend: bool, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mw := 0
	var lg := 0
	for i in n:
		var q := Factory.roll_quality(rng, skill, legend)
		if q >= 5:
			mw += 1
		if q == DB.LEGEND:
			lg += 1
	return [float(mw) / n, float(lg) / n]

func _test_curve() -> void:
	var line := []
	for s in [5, 8, 9, 10, 11, 12, 13, 14, 15]:
		line.append("%d: %.2f%% (curve %.2f%%)" % [s, 100.0 * float(_rate(s, 40000, false, 77 + s)[0]), 100.0 * Factory.masterwork_chance(s)])
	print("masterwork chance by skill: ", ", ".join(PackedStringArray(line)))
	var r10 := _rate(10.0, 400000, false, 10)
	var r15 := _rate(15.0, 200000, false, 15)
	print("measured: masterwork at skill 10 %.3f%%, at skill 15 %.2f%%" % [100.0 * float(r10[0]), 100.0 * float(r15[0])])
	check(absf(float(r10[0]) - 0.014) < 0.0012, "masterwork at skill 10 ~1.4%% (%.3f%%)" % (100.0 * float(r10[0])))
	check(absf(float(r15[0]) - 0.25) < 0.006, "masterwork at skill 15 ~25%% (%.2f%%)" % (100.0 * float(r15[0])))
	var ratio := Factory.masterwork_chance(12.0) / Factory.masterwork_chance(11.0)
	check(absf(ratio - 1.78) < 0.02, "the same ratio a skill point (x%.3f)" % ratio)
	var l15 := _rate(15.0, 400000, true, 151)
	print("measured: legendary at skill 15 %.3f%% (masterwork or better %.2f%%)" % [100.0 * float(l15[1]), 100.0 * float(l15[0])])
	check(absf(float(l15[1]) - 0.01) < 0.0012, "legendary at skill 15 ~1%% (%.3f%%)" % (100.0 * float(l15[1])))
	var l10 := _rate(10.0, 400000, true, 101)
	print("measured: legendary at skill 10 %.4f%% (curve %.4f%%)" % [100.0 * float(l10[1]), 100.0 * Factory.legend_chance(10.0)])
	check(float(_rate(15.0, 50000, false, 9)[1]) == 0.0, "no legendary without a named smith (generic rolls)")
	# deterministic per RNG
	var a := RandomNumberGenerator.new(); a.seed = 5
	var b := RandomNumberGenerator.new(); b.seed = 5
	var same := true
	for i in 500:
		same = same and Factory.roll_quality(a, 12.0, true) == Factory.roll_quality(b, 12.0, true)
	check(same, "the roll is deterministic per RNG")
	# lower qualities shift: the median at skill 9 is superior-ish (3), at skill 3 poor (0)
	check(int(round(Factory.quality_center(9.0))) == 2 and int(round(Factory.quality_center(3.0))) == 0, "lower qualities follow the refit")

## A town with a weaponsmith forge that has register people at work.
func _forge_town() -> Array:
	var w: Dictionary = Game.world
	var ids: Array = w["towns"].keys()
	ids.sort()
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		for b in t["econ"]["biz"]:
			if String(b["type"]) == "weaponsmith" and not Legends.makers(t["econ"], b).is_empty():
				return [t, b]
	return []

func _test_forge_cap_gem() -> void:
	var tb := _forge_town()
	check(not tb.is_empty(), "a forge with real makers exists")
	if tb.is_empty():
		return
	var t: Dictionary = tb[0]
	var b: Dictionary = tb[1]
	var e: Dictionary = t["econ"]
	var rng := RandomNumberGenerator.new(); rng.seed = 42
	for g in Legends.GEMS:
		e["stock"][g] = 0
	for f in e["fams"]:
		f.erase("gems")
	e.erase("gh")
	# no stone anywhere: stays masterwork
	b["till"] = 1.0e7
	var it0 := Item.make("w_sword" if DB.weapons.has("w_sword") else DB.weapons.keys()[0], "copper", DB.LEGEND)
	check(not Legends.forge(Game, t, e, b, it0, rng, 10.0) and it0.quality == 5, "no gem in the town: the piece stays masterwork")
	var makers := Legends.makers(e, b)
	e["stock"]["ruby"] = 1000
	var made := 0
	for i in makers.size() * Legends.CAP + 6:
		var it := Item.make(it0.tid, "copper", DB.LEGEND)
		var r0 := int(e["stock"]["ruby"])
		if Legends.forge(Game, t, e, b, it, rng, 10.0 + i):
			made += 1
			check(int(e["stock"]["ruby"]) == r0 - 1 and String(it.legend["gem"]) == "ruby", "the gem comes from the market's real stock")
	var cap_ok := true
	for m in makers:
		cap_ok = cap_ok and Legends.made_by(m["p"]) <= Legends.CAP
	print("forge with %d makers: %d legendary pieces before every maker reached the cap of %d" % [makers.size(), made, Legends.CAP])
	check(cap_ok and made == makers.size() * Legends.CAP, "at most %d legendary pieces a smith's life (%d made by %d makers)" % [Legends.CAP, made, makers.size()])
	# a stone a family keeps is bought when the market has none
	for m in makers:
		m["p"][Persons.LEG] = 0
	e["stock"]["ruby"] = 0
	var fam: Dictionary = e["fams"][1]
	Legends.add_fam_gem(e, fam, "sapphire", 1)
	var p0 := float(fam["purse"])
	var it2 := Item.make(it0.tid, "copper", DB.LEGEND)
	check(Legends.forge(Game, t, e, b, it2, rng, 50.0) and String(it2.legend["gem"]) == "sapphire" and float(fam["purse"]) > p0
		and not fam.get("gems", {}).has("sapphire"), "a family's own stone, bought, when the market has none")

func _test_name_icon() -> void:
	var it := Item.make(DB.weapons.keys()[0], "copper", DB.LEGEND)
	it.legend = {"nm": "Oathbreaker", "gem": "ruby", "at": Item.gem_spot(it.tid), "by": "Aldric Smith", "bt": "Ashford", "d": 3, "k": 0, "kl": [], "cu": -1, "h": []}
	var nm := it.display_name()
	check(nm.begins_with("Oathbreaker, legendary copper "), "the name reads \"(name), legendary (material) (item)\" (%s)" % nm)
	var lines := it.legend_lines()
	print("sample: ", " | ".join(PackedStringArray(lines)))
	check(String(lines[0]).contains("ruby") and String(lines[0]).contains(Item.gem_spot(it.tid)), "the gem and its spot in the description")
	check(it.value() > 15 * Item.make(it.tid, "copper", 5).value(), "worth a fortune (%d coins vs masterwork %d)" % [it.value(), Item.make(it.tid, "copper", 5).value()])
	check(is_equal_approx(DB.quality_mult(DB.LEGEND), 3.0) and is_equal_approx(DB.quality_mult(5), 2.0), "quality value 3.0 vs masterwork 2.0")
	var shape := ItemIcon.shape_of(it.tid)
	var img := ItemIcon.legend_image(shape, "copper", "ruby")
	var spot: Vector2i = ItemIcon.GEM_SPOTS.get(shape, Vector2i(16, 16))
	var px := img.get_pixelv(spot)
	var ruby := Color(String(ItemIcon.THING_COLORS["ruby"]))
	check(px.is_equal_approx(ruby), "the icon shows the gem at its spot (%s)" % str(px))
	var mw := ItemIcon.image(shape, "copper", 5)
	check(mw.get_pixelv(spot) != px, "the legendary icon differs from the masterwork one")
	check(ItemIcon.for_item(it) != null and ItemIcon.for_thing("ruby") != null, "item and gem icons draw")
	var d := it.to_dict()
	var back := Item.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(back.display_name() == nm and back.is_legend(), "a legendary piece survives the save")

func _legend(tid: String) -> Item:
	var it := Item.make(tid, "copper", DB.LEGEND)
	it.legend = {"nm": "Gravefang", "gem": "garnet", "at": Item.gem_spot(tid), "by": "Test Smith", "bt": "Testford", "d": 0, "k": 0, "kl": [], "cu": -1, "h": []}
	return it

func _test_never_lost() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 8
	var tid: String = DB.weapons.keys()[0]
	# player: the company always takes it, whatever the roll
	var ok := true
	for s in 40:
		var foes: Array = Factory.make_warband(rng, "orc_horde", 3)
		var it := _legend(tid)
		foes[0].equip["main_hand"] = it
		foes[0].dead = true
		var sp := Loot.spoils(foes, [], 1000 + s, 0.25, "your company")
		ok = ok and (sp["items"] as Array).has(it)
	check(ok, "a fallen carrier's legendary piece always goes to the player (40 seeds)")
	# AI: a band wins and puts it on its best fitting fighter
	var w: Dictionary = Game.world
	var wid := ""
	for k in w["warbands"]:
		var wb: Dictionary = w["warbands"][k]
		if String(wb["kind"]) != "caravan" and not Monsters.is_monster_band(wb) and (wb["units"] as Array).size() >= 2:
			wid = k
			break
	check(wid != "", "an AI band to win the fight")
	if wid == "":
		return
	var win: Dictionary = w["warbands"][wid]
	var ok2 := true
	for s in 10:
		var dead: Array = Factory.make_warband(rng, "orc_horde", 2)
		var it := _legend(tid)
		dead[0].equip["main_hand"] = it
		dead[0].dead = true
		dead[0].name = "Grukk %d" % s
		ArmsTrade.field(Game, dead, {"band": win}, win["pos"])
		var holder: Unit = null
		for u in win["units"]:
			if u.equip.get("main_hand", null) == it:
				holder = u
		ok2 = ok2 and holder != null and dead[0].equip.is_empty()
		if s == 0 and holder != null:
			var best := Legends.best_fighter(win["units"].filter(func(x): return x != holder), _legend(tid))
			print("AI winner: %s took it up (skill %d); history: %s" % [holder.name, holder.skill(String(it.tmpl().get("skill", ""))), str(it.legend["h"])])
			check((it.legend["h"] as Array).size() >= 2, "every change of hands is in its history")
		if holder != null:
			holder.equip.erase("main_hand")   # (the next fight's piece: a fighter free to take it up)
	check(ok2, "an AI winner always takes it and puts it on a fighter (10 fights)")
	# beasts won: the nearest town picks it up
	var dead2: Array = Factory.make_warband(rng, "orc_horde", 1)
	var it3 := _legend(tid)
	dead2[0].equip["main_hand"] = it3
	dead2[0].dead = true
	ArmsTrade.field(Game, dead2, {}, win["pos"])
	var found := false
	for t in w["towns"]:
		if ArmsTrade.armory(w["towns"][t]).has(it3):
			found = true
	check(found, "beasts win: the nearest town's people find it (never left)")
	# the losing town remembers
	var t0: Dictionary = {}
	for t in w["towns"]:
		if TownEcon.has_econ(w["towns"][t]):
			t0 = w["towns"][t]
			break
	var man: Unit = Factory.make_warband(rng, "orc_horde", 1)[0]
	man.home_town = String(t0["id"])
	var it4 := _legend(tid)
	man.equip["main_hand"] = it4
	man.dead = true
	Loot.spoils([man], [], 5, 0.25, "your company")
	check(not (t0["econ"].get("legends_lost", []) as Array).is_empty(), "a town that loses one remembers it")
	check(Legends.all_held(Game).size() > 0, "the records list the world's legendary pieces")

## Gear damage (battle sim bends, snaps, chips, armour cracks) never breaks or wears down a legendary piece.
func _test_no_gear_damage() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 21
	var a: Array = Factory.make_warband(rng, "middle_kingdom", 1)
	var d: Array = Factory.make_warband(rng, "middle_kingdom", 1)
	var sim := BattleSim.new()
	sim.setup(a, d, 5, {"w": 8, "h": 4, "log_moves": false})
	var w := _legend("arming_sword" if DB.weapons.has("arming_sword") else DB.weapons.keys()[0])
	w.material = "tin"
	var wt := w.tmpl()
	var wmat := w.mat()
	var t := Formulas.head_section_mm(float(wt.get("head_cm3", 0)), false)
	var rs := Formulas.blunt_resistance(wmat, 50.0, DB.quality_mult(w.quality), t, "armor")
	for i in 5:
		sim._gear_bend(sim.fighters[0], w, wt, wmat, 50.0, rs * 3.0, "steel helm", true, {}, [])
		sim._gear_chip(w, DB.materials["steel"], wmat, "steel helm", true, {}, [])
	check(w.quality == DB.LEGEND and not w.broken and w.dull == 0.0, "a legendary weapon never bends, snaps or chips (q %d, broken %s)" % [w.quality, str(w.broken)])
	var arm := _legend(DB.armor.keys()[0])
	var entry := {"item": arm, "w": 0.0, "name": "helm", "mat": arm.mat()}
	for k in ["cracked", "dented", "shattered"]:
		sim._armor_dmg(entry, k, {}, [])
	check(arm.quality == DB.LEGEND and not arm.broken, "a legendary armour piece never cracks or loses quality")
	var u: Unit = a[0]
	u.equip["main_hand"] = w
	Loot.strip_broken([u])
	check(u.equip.get("main_hand") == w, "never stripped as broken after a battle")

func _test_mine_gems() -> void:
	var w: Dictionary = Game.world
	var e: Dictionary = {}
	var b: Dictionary = {}
	for t in w["towns"]:
		if not TownEcon.has_econ(w["towns"][t]):
			continue
		for bb in w["towns"][t]["econ"]["biz"]:
			if String(bb["type"]) == "mine":
				e = w["towns"][t]["econ"]; b = bb
				break
		if not b.is_empty():
			break
	check(not b.is_empty(), "a mine to dig")
	if b.is_empty():
		return
	var rng := RandomNumberGenerator.new(); rng.seed = 99
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	mkt["till"] = 1.0e9
	var days := 20000
	var n := 10
	var got := 0
	var kinds := {}
	for i in days:
		var g := Legends.mine_day(e, b, String(b.get("ore", "copper_ore")), n, mkt, 0.9, rng)
		if g != "":
			got += 1
			kinds[g] = int(kinds.get(g, 0)) + 1
	var c := float(TownEcon.data()["gem_pockets"]["chance"])
	var expect := days * (1.0 - pow(1.0 - c, n))
	print("gem pockets: %d stones from %d baskets (%.4f a basket; set %.4f); %s" % [got, days * n, float(got) / (days * n), c, str(kinds)])
	check(absf(float(got) - expect) < 4.0 * sqrt(expect), "mining yields gems at about the set rate (%d vs %.0f)" % [got, expect])
	check(int(kinds.get("quartz", 0)) > int(kinds.get("emerald", 0)), "common stones more often than rare ones")

func _test_family_gems() -> void:
	var w: Dictionary = Game.world
	var t: Dictionary = {}
	for k in w["towns"]:
		if TownEcon.has_econ(w["towns"][k]):
			t = w["towns"][k]
			break
	var e: Dictionary = t["econ"]
	var f: Dictionary = e["fams"][2]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	mkt["till"] = 1.0e7
	# a rich family buys a stone from its 'rest' (the batch fills it into its own holdings)
	e["stock"]["ruby"] = 3
	e["stock"]["quartz"] = 3
	f["purse"] = 1.0e6
	f["wear"]["gems"] = 1.5
	TownEcon.batch.clear()
	var cost := Legends.want_order(e, f, 2, 7.0, TownEcon.batch)
	TownEcon.clear_batch(e)
	check(cost > 0.0 and int(f.get("gems", {}).get("ruby", 0)) == 1 and int(e["gh"].get("ruby", 0)) >= 1, "a rich family buys the dearest stone as stored wealth")
	# hungry: it sells its stones for food before pawning
	Legends.add_fam_gem(e, f, "garnet", 2)
	f["purse"] = 0.0
	f["hungry"] = 2
	var s0 := int(e["stock"].get("garnet", 0))
	var got := Legends.sell_gems(e, f, 100.0)
	print("a hungry family sold stones for %d coins" % int(got))
	check(got > 0.0 and float(f["purse"]) > 0.0 and int(e["stock"]["garnet"]) > s0, "a hungry family with gems sells them for food")
	check(TownEcon.town_total(e, "ruby") >= 1, "families' stones count in the town's goods")
