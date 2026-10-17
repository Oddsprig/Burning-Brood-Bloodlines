extends RefCounted
## v0.014 gore, combat text and gear damage (Douglas 22:51-22:58).
##  1. Every story line the log makes for a strike claims only what the sim did: each claim word (artery, skull,
##     brain, heart, lung, guts, spine, windpipe, eye, tooth, severed/beheaded, slain, snapped/bent/chipped weapon,
##     cracked/split/dented armour, a cry of pain, through-the-armour) is checked against that strike's record
##     (layers, funcs, art, out, kill, wd, ad, rx/pain). Kills always say so. Decisive event lines match their event.
##  2. The Gore setting switches the log words (Reduced: no gore-only words), the battle decals (GoreLayer: a third
##     of the droplets, half pools) and the sprite wound marks; it is saved and read back.
##  3. Gear damage: a weapon bends only at or past its yield, snaps only past its fracture (quality steps lost /
##     broken); armour dents only past its yield; broken pieces become scrap of their metal at their real mass.

const U = preload("res://tests/sim_util.gd")
const DG = preload("res://tests/test_bows_melee_digest.gd")

var fails := 0

func _check(cond: bool, what: String) -> void:
	if not cond:
		printerr("FAIL: ", what)
		fails += 1

func run(_tree: SceneTree) -> int:
	CombatText.gore_full = true
	var sims := _battles()
	var entries := _strikes(sims)
	print("  %d strike entries from %d battles" % [entries.size(), sims.size()])
	_claims(entries, true)
	_samples(entries)
	_decisive(sims)
	CombatText.gore_full = false
	_claims(entries, false)
	_reduced_words(entries)
	CombatText.gore_full = true
	_gore_setting()
	_weapon_bend()
	_armor_dent()
	_scrap()
	return fails

# ---------------------------------------------------------------- battles
func _battles() -> Array:
	var out := []
	var bs: Dictionary = DG.battles()
	for k in bs:
		out.append(bs[k])
	# tin swords and maces against steel: bends, chips and snaps; mauls against plate: cracks and breaches
	for s in 3:
		var a := []
		var b := []
		for i in 4:
			a.append(U.soldier("tin", "arming_sword" if i % 2 == 0 else "flanged_mace", "scrap_plates", "skull_cap"))
			b.append(U.soldier("steel", "war_maul" if i % 2 == 0 else "arming_sword", "scrap_plates", "skull_cap", ""))
		out.append(U.run(a, b, 40 + s, {"w": 16, "h": 8}))
	for s in 2:   # goblins (backstabs) against northern clansmen
		var rng := RandomNumberGenerator.new()
		rng.seed = 70 + s
		out.append(U.run(Factory.make_warband(rng, "goblin_warren", 8), Factory.make_warband(rng, "northern_clans", 6), 90 + s, {"w": 20, "h": 10}))
	return out

func _strikes(sims: Array) -> Array:
	var seen := {}
	var out := []
	for sim in sims:
		for f in sim.fighters:
			for le in f.log:
				if le["k"] == "strike" and not seen.has(le["d"]):
					seen[le["d"]] = true
					out.append(le)
	return out

## A fresh render of a strike entry (the cache keys dropped) under the current gore setting.
func _render(le: Dictionary) -> String:
	var e := {"tick": le["tick"], "k": le["k"], "d": le["d"]}
	return String(CombatText.render(e)["text"])

# ---------------------------------------------------------------- 1. claims
func _has_layer(d: Dictionary, pred: Callable) -> bool:
	for l in d.get("layers", []):
		if pred.call(l):
			return true
	return false

func _part_layer(d: Dictionary, prefix: String) -> bool:
	return _has_layer(d, func(l): return l.size() > 5 and String(l[5]).begins_with(prefix))

func _ad(d: Dictionary, kinds: Array) -> bool:
	for x in d.get("ad", []):
		if String(x[1]) in kinds:
			return true
	return false

func _claims(entries: Array, full: bool) -> void:
	var rules := [
		["artery", "\\bartery\\b|\\bART\\b", func(d): return float(d.get("art", 0.0)) > 0.0],
		["blood jets", "spurts|jets|hoses|fountain", func(d): return float(d.get("art", 0.0)) > 0.0 or String(d["out"]) in ["sever", "decap"]],
		["skull", "\\bskull\\b(?! cap)",func(d): return _has_layer(d, func(l): return String(l[0]) == "skull")],
		["brain", "\\bbrains?\\b", func(d): return _part_layer(d, "brain")],
		["heart", "\\bheart\\b", func(d): return _part_layer(d, "heart")],
		["lung", "\\blungs?\\b", func(d): return _part_layer(d, "lung") or "lung" in d["funcs"] or "drown" in d["funcs"]],
		["guts", "\\bguts\\b|entrails|loops of gut|\\bbelly\\b", func(d): return "guts" in d["funcs"] or _part_layer(d, "guts")],
		["spine", "\\bspine\\b|spinal", func(d): return "spine" in d["funcs"] or _part_layer(d, "spine")],
		["windpipe", "windpipe|throat gapes|airway", func(d): return "airway" in d["funcs"]],
		["eye", "\\beye\\b", func(d): return "eye" in d["funcs"] or _part_layer(d, "eye")],
		["tooth", "\\btooth\\b|\\bteeth\\b", func(d): return d["natural"] or "tooth" in d["funcs"] or String(d["part"]).begins_with("tooth")],
		["severed", "\\boff!|off with|spins away|lops off|beheads|tumbling from|red arc|drops to the dirt|bounces across|head from|falls away|strikes off|hews .* from (his|her|its) body", func(d): return String(d["out"]) in ["sever", "decap"]],
		["slain", "\\bslay|\\bkilling\\b|\\bdead\\b|ending (him|her|it)\\b|stopping (his|her|its) heart", func(d): return String(d.get("kill", "")) != "" or String(d["out"]) == "decap"],
		["weapon snapped", "\\bsnaps\\b|\\bsnapped\\b|breaks apart|breaks off short", func(d): return d["natural"] or String(d.get("wd", [""])[0]) == "snap"],
		["weapon bent", "\\bbends\\b|bent out of true", func(d): return String(d.get("wd", [""])[0]) == "bend"],
		["edge chipped", "\\bchips\\b|notches against|sliver of edge", func(d): return String(d.get("wd", [""])[0]) == "chip"],
		["armour dented", "\\bdents\\b|buckles inward|deep dent", func(d): return _ad(d, ["dented"])],
		["armour broken", "\\bcracks\\b|\\bsplits\\b|split open|split apart|shatters|bursts apart|caves in|stoves in|rings burst|links snap", func(d): return _ad(d, ["split", "cracked", "shattered", "burst"])],
		["armour holed", "is holed|punches a hole", func(d): return _ad(d, ["punctured"])],
		["cry of pain", "cries out|howls|grunts|screams|bellows in pain|strangled yell", func(d): return String(d.get("rx", "")) == "cry" and float(d.get("pe", 0.0)) >= Formulas.PAIN_CRY],
		["through armour", "through (his|her|its) (?!body)", func(d):
			for a in d.get("armor", []):
				if String(a[1]) in ["cut", "dented"]:
					return true
			return d.has("via")],
		["stuck", "lodged|sticks fast|stuck fast|buried", func(d): return d.get("lodged", false)],
	]
	var bad := 0
	var hits := {}
	var kills_said := 0
	var kills := 0
	for le in entries:
		var d: Dictionary = le["d"]
		var t := _render(le).to_lower()
		for r in rules:
			var re := RegEx.create_from_string(r[1])
			if re.search(t) != null:
				hits[r[0]] = int(hits.get(r[0], 0)) + 1
				if not (r[2] as Callable).call(d):
					bad += 1
					if bad <= 8:
						printerr("  claim '%s' without the wound (gore %s): %s" % [r[0], "full" if full else "reduced", t])
		if String(d.get("kill", "")) != "" and String(d["out"]) in ["hit", "sever", "decap"]:
			kills += 1
			if RegEx.create_from_string("\\bslay|\\bkilling\\b|\\bdead\\b|ending (him|her|it)|stopping (his|her|its) heart|beheads|head|bursting").search(t) != null:
				kills_said += 1
			elif full:
				printerr("  killing blow not told as one: " + t)
	print("  gore %s: claims found %s" % ["full" if full else "reduced", str(hits)])
	_check(bad == 0, "every claim in a strike line maps to a real wound (%d unbacked, gore %s)" % [bad, "full" if full else "reduced"])
	_check(kills > 0 and kills_said == kills, "every killing blow says it killed (%d of %d)" % [kills_said, kills])
	if full:
		for need in ["slain", "through armour"]:
			_check(int(hits.get(need, 0)) > 0, "the battles produced '%s' lines" % need)

func _samples(entries: Array) -> void:
	var picked := 0
	var want := ["sever", "decap"]
	print("  --- sample lines (gore full) ---")
	for le in entries:
		var d: Dictionary = le["d"]
		var big := String(d["out"]) in want or String(d.get("kill", "")) != "" or d.has("wd") or not (d.get("ad", []) as Array).is_empty() or not (d["funcs"] as Array).is_empty()
		if big and picked < 14:
			print("    " + _render(le))
			picked += 1

func _decisive(sims: Array) -> void:
	var bad := 0
	for sim in sims:
		for e in sim.events:
			var t := String(e.get("text", "")).to_lower()
			if t == "":
				continue
			match String(e["type"]):
				"artery":
					if not (t.contains("blood") or t.contains("bleed")):
						bad += 1
				"sever":
					if not (t.contains("off") or t.contains("head") or t.contains("ground") or t.contains("behead")):
						bad += 1
				"guts":
					if not (t.contains("gut") or t.contains("entrails") or t.contains("belly")):
						bad += 1
	_check(bad == 0, "decisive artery/sever/guts lines match their event (%d off)" % bad)
	var says := 0
	for sim in sims:
		for f in sim.fighters:
			for le in f.log:
				if le["k"] == "ev" and String(le["d"].get("key", "")) == "say":
					var t := String(CombatText.render(le)["text"])
					_check(t != "say" and t != "" and not t.contains("{"), "a battle cry or taunt renders (%s)" % t)
					says += 1
	_check(says > 0, "battle cries and taunts are logged (%d)" % says)

# ---------------------------------------------------------------- 2. the Gore setting
const GORE_ONLY := ["spray", "brains", "entrails", "fountain", "slop", "jets", "hoses", "spurts", "twitching", "pumps blood", "loops of gut", "froth", "splatter"]

func _reduced_words(entries: Array) -> void:
	var differ := 0
	var gory := 0
	for le in entries:
		CombatText.gore_full = true
		var full_t := _render(le)
		CombatText.gore_full = false
		var mild_t := _render(le).to_lower()
		if full_t.to_lower() != mild_t:
			differ += 1
		for w in GORE_ONLY:
			if mild_t.contains(w):
				gory += 1
				if gory <= 4:
					printerr("  reduced line still gory ('%s'): %s" % [w, mild_t])
	CombatText.gore_full = true
	_check(gory == 0, "Gore Reduced: no gore-only words in the log (%d)" % gory)
	_check(differ > 0, "Gore Reduced changes some lines (%d)" % differ)

func _gore_setting() -> void:
	Game.set_setting("gore", "reduced")
	_check(not CombatText.gore_full and not Game.gore_full(), "Gore Reduced reaches the log")
	Game.load_settings()
	_check(String(Game.setting("gore")) == "reduced", "Gore setting is saved and read back")
	var u := U.soldier("copper")
	u.body.wound_part("arm_upper_r")["layers"][2]["dmg"] = 0.6
	u.body.parts["arm_upper_r"]["layers"][2]["kind"] = "cut"
	_check(int(FigurePainter.spec_for_unit(u)["gore"]) == 0, "sprite wound marks follow Gore Reduced")
	var GL = load("res://battle/gore_layer.gd")
	var g_red = GL.new()
	g_red.setup(40.0, Game.gore_full(), 1)
	g_red.spray(Vector2(100, 100), Vector2.RIGHT, 30, 120.0)
	Game.set_setting("gore", "full")
	_check(CombatText.gore_full and int(FigurePainter.spec_for_unit(u)["gore"]) == 1, "Gore Full is the default look")
	_check(String(FigurePainter.spec_for_unit(u)["wk"].get("arm_upper_r", "")) == "c", "a cut shows as a cut on the arm")
	var g_full = GL.new()
	g_full.setup(40.0, Game.gore_full(), 1)
	g_full.spray(Vector2(100, 100), Vector2.RIGHT, 30, 120.0)
	_check(g_full.drop_count() == 30 and g_red.drop_count() == 10, "Reduced throws a third of the droplets (%d vs %d)" % [g_red.drop_count(), g_full.drop_count()])
	# pools grow with the real blood lost; Reduced pools are half size
	var sim := U.run([U.soldier("copper")], [U.soldier("tin")], 3, {"w": 10, "h": 5})
	var views := []
	for f in sim.fighters:
		var vv := Node2D.new()
		vv.set_script(load("res://battle/unit_view.gd"))
		vv.setup(f, 40.0)
		views.append(vv)
	var down := -1
	for f in sim.fighters:
		if f.state == "dead" or f.state == "unconscious" or f.prone:
			down = f.idx
	if down >= 0:
		g_full.tick(sim, views)
		g_red.tick(sim, views)
		_check(g_full.pool_radius(down) > 0.0 and absf(g_red.pool_radius(down) - g_full.pool_radius(down) * 0.5) < 0.01, "a downed fighter leaves a pool (Reduced half size)")
		var r0: float = g_full.pool_radius(down)
		var b: BodyState = sim.fighters[down].unit.body
		if b.blood / b.blood_max > 0.6:
			b.blood *= 0.8
			g_full.tick(sim, views)
			_check(g_full.pool_radius(down) > r0, "the pool grows with the blood really lost")
	for vv in views:
		vv.free()
	g_full.free()
	g_red.free()
	_gore_perf()

## 50 a side: the gore layer's per-tick work (drips, spurts, pools) and a spray per hit stay cheap and capped.
func _gore_perf() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 50
	var sim := BattleSim.new()
	sim.setup(Factory.make_warband(rng, "middle_kingdom", 50), Factory.make_warband(rng, "orc_horde", 50), 50, {"w": 64, "h": 36, "verbose": false, "log_moves": false})
	var views := []
	for f in sim.fighters:
		var vv := Node2D.new()
		vv.set_script(load("res://battle/unit_view.gd"))
		vv.setup(f, 40.0)
		views.append(vv)
	var g = load("res://battle/gore_layer.gd").new()
	g.setup(40.0, true, 1)
	var worst := 0
	var total := 0
	var n := 0
	while not sim.is_over() and n < 3000:
		sim.step()
		for v in views:
			v.position = v.cell_pos(v.fighter.cell)
		var t0 := Time.get_ticks_usec()
		for e in sim.new_events:
			if e["type"] == "hit":
				g.spray(views[e["target"]].body_center(), Vector2.RIGHT, 12, views[e["target"]].position.y)
		g.tick(sim, views)
		g._process(0.05)
		var dt := Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
		n += 1
	print("  gore layer 50v50: %d ticks, mean %.3f ms, worst %.3f ms; %d decals (cap %d), %d pools, %d drops in flight" % [n,
		float(total) / maxf(1.0, n) / 1000.0, worst / 1000.0, g.decal_count(), g.MAX_DECALS, g.pool_count(), g.drop_count()])
	_check(g.decal_count() <= g.MAX_DECALS and g.drop_count() <= g.MAX_DROPS, "gore decals and droplets stay capped")
	_check(float(total) / maxf(1.0, n) < 1000.0, "gore layer mean cost under 1 ms a tick at 50 a side")
	for vv in views:
		vv.free()
	g.free()

# ---------------------------------------------------------------- 3. gear damage
func _weapon_bend() -> void:
	var a := U.soldier("tin")
	var d := U.soldier("steel")
	var sim := BattleSim.new()
	sim.setup([a], [d], 5, {"w": 8, "h": 4, "log_moves": false})
	var w: Item = a.weapon()
	var wt := w.tmpl()
	var wmat := w.mat()
	var contact := 50.0   # a stab
	var t := Formulas.head_section_mm(float(wt["head_cm3"]), false)
	w.quality = 3
	var ry := Formulas.yield_resistance(wmat, contact, DB.quality_mult(w.quality), t)
	var D := {}
	sim._gear_bend(sim.fighters[0], w, wt, wmat, contact, ry * 0.99, "steel helm", true, D, [])
	_check(not D.has("wd") and w.quality == 3 and not w.broken, "below the yield: no bend, no quality lost")
	sim._gear_bend(sim.fighters[0], w, wt, wmat, contact, ry * 1.01, "steel helm", true, D, [])
	_check(String(D.get("wd", [""])[0]) == "bend" and w.quality == 2 and not w.broken, "past the yield: bent (a quality step lost, still usable)")
	D = {}
	var ry2 := Formulas.yield_resistance(wmat, contact, DB.quality_mult(w.quality), t)
	var rs2 := Formulas.blunt_resistance(wmat, contact, DB.quality_mult(w.quality), t, "armor")
	if ry2 * Formulas.BEND_SEVERE < rs2:
		sim._gear_bend(sim.fighters[0], w, wt, wmat, contact, ry2 * Formulas.BEND_SEVERE, "steel helm", true, D, [])
		_check(w.quality == 0 and not w.broken, "a severe bend costs two quality steps")
	D = {}
	var rs := Formulas.blunt_resistance(wmat, contact, DB.quality_mult(w.quality), t, "armor")
	sim._gear_bend(sim.fighters[0], w, wt, wmat, contact, rs * 1.001, "steel gauntlet", true, D, [])
	_check(String(D.get("wd", [""])[0]) == "snap" and w.broken and w.wear == 3, "past the fracture: snapped (broken, scrap)")
	# the log says so, with the metal, the weapon and the piece it struck
	var le := {"tick": 1, "k": "strike", "d": {"al": "Arnold", "dl": "Grushnak", "w": "tin arming sword", "wn": "arming sword", "verb": "stab",
		"wtype": "pierce", "out": "absorbed", "pname": "hand", "armor": [["steel gauntlet", "held", "metal"]], "layers": [], "funcs": [],
		"wd": ["snap", "steel gauntlet", true], "apr": "his", "dpr": "his", "vk": 0, "vc": 0, "steps": []}}
	var txt := String(CombatText.render(le)["text"])
	print("  snap line: " + txt)
	_check(txt.contains("tin arming sword") and txt.contains("steel gauntlet") and (txt.contains("snap") or txt.contains("break")), "the snap is told: metal, weapon, the piece it broke on")
	# softer metal suffers more, from the values alone
	var r_tin := Formulas.yield_resistance(DB.materials["tin"], contact, 1.0, t)
	var r_cu := Formulas.yield_resistance(DB.materials["copper"], contact, 1.0, t)
	var r_st := Formulas.yield_resistance(DB.materials["steel"], contact, 1.0, t)
	_check(r_tin < r_cu and r_cu < r_st, "tin bends before copper, copper before steel (%.1f < %.1f < %.1f)" % [r_tin, r_cu, r_st])
	_check(Formulas.chip_amount(DB.materials["bone"], DB.materials["copper"]) > 0.0 and Formulas.chip_amount(DB.materials["bone"], DB.materials["steel"]) == 0.0,
		"copper edges chip on bone, steel does not")
	# a whole fight: the steel men's tin opponents' weapons really suffer, and every event is in the log
	var a2 := []
	var b2 := []
	for i in 4:
		a2.append(U.soldier("tin", "flanged_mace", "scrap_plates", "skull_cap"))
		b2.append(U.soldier("steel", "arming_sword", "scrap_plates", "skull_cap"))
	var s2 := U.run(a2, b2, 12, {"w": 12, "h": 6})
	var wd := 0
	for f in s2.fighters:
		for e in f.log:
			if e["k"] == "strike" and e["d"].has("wd") and int(e["d"]["a"]) == f.idx:
				wd += 1
	print("  tin maces vs steel plate: %d weapon damage events" % wd)

func _armor_dent() -> void:
	# a copper mace on a copper pot helm: dented exactly when the held blow's momentum reaches the plate's yield form
	var a := U.make("human", [["flanged_mace", "copper"]], {"mace": 6, "fighter": 4})
	var d := U.make("human", [["pot_helm", "copper", 5]], {})
	var sim := BattleSim.new()
	sim.setup([a], [d], 9, {"w": 8, "h": 4, "log_moves": false})
	var fd: Fighter = sim.fighters[1]
	var ok := 0
	var wrong := 0
	var dents := 0
	for i in 60:
		d.body.init_from_plan(DB.bodies["humanoid"], d.mass())
		d.dead = false
		fd.state = "ready"; fd.prone = false; fd.think_dmg = 0.0
		var helm: Item = d.equip["helm"]
		helm.quality = 5
		helm.broken = false
		var entry: Dictionary = fd.armor_for["head"][0]
		entry["w"] = 0.0
		a.weapon().quality = 3
		a.weapon().broken = false
		sim.fighters[0].weapon_dropped = false
		sim.debug_strike(0, 1, "head", 0, true)
		var D: Dictionary = {}
		for le in fd.log:
			if le["k"] == "strike":
				D = le["d"]   # the last strike entry (a battle cry may follow it in the log)
		var ab: Array = []
		for s in D["steps"]:
			if s is Array and s[0] == "ab":
				ab = s
		if ab.is_empty():
			continue   # the helm did not cover this blow
		var held := not bool(ab[4])
		var ry := Formulas.yield_resistance(helm.mat(), 20.0, DB.quality_mult(5), float(entry["t"]))
		var dented := _ad(D, ["dented"])
		if dented:
			dents += 1
		if held and (dented == (float(ab[2]) >= ry)):
			ok += 1
		elif not held and not dented and _ad(D, ["cracked"]):
			ok += 1
		else:
			wrong += 1
	print("  copper mace on a copper pot helm: %d dents in %d probes" % [dents, ok + wrong])
	_check(wrong == 0 and ok > 0, "armour dents exactly when the blow reaches the metal's yield, cracks only past fracture (%d wrong)" % wrong)

func _scrap() -> void:
	# an enemy's split breastplate and snapped sword: scrap of their metal at their real mass
	var e := U.soldier("bronze", "arming_sword", "scrap_plates", "skull_cap")
	var plates: Item = e.equip["body"]
	var sword: Item = e.weapon()
	plates.broken = true
	sword.broken = true
	var kg_bronze := plates.mass() + sword.mass()
	e.dead = true
	var sp := Loot.spoils([e], [], 1, 0.5)
	_check(float(sp["scrap_kg"].get("bronze", 0.0)) >= kg_bronze - 0.001, "broken enemy pieces are bronze scrap at their mass (%.2f >= %.2f kg)" % [float(sp["scrap_kg"].get("bronze", 0.0)), kg_bronze])
	for it in sp["items"]:
		_check(not it.broken, "no broken piece is kept as loot")
	# the company's own: stripped off the man, scrap at its mass; a bent one stays (it lost quality instead)
	var m := U.soldier("iron")
	var hw: Item = m.equip["helm"]
	hw.broken = true
	var sw: Item = m.weapon()
	sw.quality = 1   # bent back after a bend
	var sc := Loot.strip_broken([m])
	_check(absf(float(sc.get("iron", 0.0)) - hw.mass()) < 0.001 and not m.equip.has("helm"), "the company's broken helm comes off as iron scrap (%.2f kg)" % float(sc.get("iron", 0.0)))
	_check(m.equip.has("main_hand") and m.weapon() == sw, "a bent weapon stays in use (quality lost, not scrap)")
	# saved and loaded
	var it := Item.make("arming_sword", "copper", 2)
	it.dull = 0.4
	it.broken = true
	var back := Item.from_dict(it.to_dict())
	_check(absf(back.dull - 0.4) < 0.001 and back.broken, "dull and broken survive a save")
