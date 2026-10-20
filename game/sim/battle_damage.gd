class_name BattleDamage
extends RefCounted
## Strike delivery, armour/shield/parry, gear wear, tissue wounds, body-part functions,
## lodged weapons, and unarmed grapple/disarm helpers split from BattleSim (game/sim/battle_sim.gd)
## to keep each file focused and under the size threshold.
## Structure only; all BattleSim.* entry points delegate here with identical behavior.

const PS_STANCE := BattleSim.PS_STANCE
const PS_LEG := BattleSim.PS_LEG
const PS_BAD := BattleSim.PS_BAD
const PS_SPINE := BattleSim.PS_SPINE
const PS_WHY := BattleSim.PS_WHY
const PS_EYE := BattleSim.PS_EYE
const PS_EYE_OK := BattleSim.PS_EYE_OK
const PS_GRASP := BattleSim.PS_GRASP
const PS_REL := BattleSim.PS_REL
const PS_DIGIT := BattleSim.PS_DIGIT
const PS_DIGIT_W := BattleSim.PS_DIGIT_W
const PS_DIGIT_OK := BattleSim.PS_DIGIT_OK
const PS_ARMS := BattleSim.PS_ARMS
const ARMOR_BROKEN_KINDS := BattleSim.ARMOR_BROKEN_KINDS

static func _deliver(sim, f: Fighter) -> void:
	var pa := f.pending_attack
	var rec: int = sim._ticks(f, float(pa.get("rec_raw", 4.5)))
	var ti := int(pa.get("target", -1))
	var t: Fighter = sim.fighters[ti] if ti >= 0 else null
	if t != null and t.alive() and t.state != "fled" and sim._in_reach(f, t) and f.lodged.is_empty():
		sim._event("attack", f.idx, t.idx, "", false)
		sim._strike(f, t, pa["atk"], pa["swing"], pa.get("pre", {}))
		if pa["atk"].get("creature", false):
			NaturalAttacks.after_strike(sim, f, t, pa["atk"])   # monsters wave 1: latch, charge run-up spent
	else:
		sim._log(f, "ev", {"key": "notarget", "al": f.label, "v": f.current_attack, "vk": f.voff, "vc": 0})
	if f.state == "preparing":
		sim._set_action(f, "recovering", rec)

## Inspection/test hook: fighter `ai` strikes fighter `di` right now with attack `attack_idx` of its weapon
## (-1 = rolled), on `part_id` ("" = rolled), skipping the defence contest when `land` is true.
## Uses sim.rng like any strike (coverage, strike quality ...). Returns last_strike.
static func debug_strike(sim, ai: int, di: int, part_id: String = "", attack_idx: int = -1, land: bool = true) -> Dictionary:
	var a: Fighter = sim.fighters[ai]
	var d: Fighter = sim.fighters[di]
	a.target = di
	var attacks: Array = sim._attacks_of(a, 1)
	var atk: Dictionary = attacks[attack_idx] if attack_idx >= 0 and attack_idx < attacks.size() else attacks[Formulas.roll_attack_choice(sim.rng, attacks)["i"]]
	sim._force_part = part_id
	sim._force_land = land
	sim._strike(a, d, atk, sim._swing_for(a, atk), {})
	sim._force_part = ""
	sim._force_land = false
	return sim.last_strike

static func _strike(sim, a: Fighter, d: Fighter, atk: Dictionary, sw: Dictionary, pre: Dictionary) -> void:
	var V: bool = sim.verbose
	var steps := []
	var au := a.unit
	var du := d.unit
	# perf (same results): one weapon template lookup per strike (= _weapon_skill_name / w_item.tmpl())
	var shot: Dictionary = sim._shot   # bows: an arrow (sim/archery.gd) when not empty; every shot branch below is arrow-only
	var arrow := not shot.is_empty()
	var w_item: Item = a.wielded if sim._has_weapon(a) and not arrow else null
	var wt: Dictionary = sim._tmpl(w_item) if w_item != null else {}
	var wskill: String = String(wt.get("skill", "fighter")) if w_item != null else ("bow" if arrow else "brawler")
	var natural := w_item == null and not arrow
	var verb := String(atk.get("verb", "attack"))
	var edged0: bool = atk.get("type", "blunt") == "edge"
	var thrust: bool = sim._is_thrust(atk)
	var D := {"a": a.idx, "d": d.idx, "al": a.label, "dl": d.label, "w": sim._item_name(w_item) if w_item != null else "",
		"wn": String(wt.get("name", "")),
		"verb": verb, "edge": edged0, "thrust": thrust, "natural": natural, "steps": steps, "layers": [], "armor": [],
		"funcs": [], "out": "hit", "def": "", "part": "", "pname": "", "art": 0.0, "sever": false, "kill": "",
		"path": "", "wtype": _weapon_class(w_item, atk), "vk": a.voff, "lodged": false, "stop": "", "glance": false, "apr": a.pron, "dpr": d.pron}
	if arrow:
		D["w"] = shot["name"]
		D["shot"] = shot["kind"]
		D["wtype"] = "arrow"
		if shot.has("via"):
			D["via"] = shot["via"]
	a.swing_count += 1
	if a.swing_count == 1 and a.cul != "" and not arrow:   # v0.014: his battle cry, once, on his first blow (log only)
		sim._say(a, d, "cry")
	sim.last_strike = {"attacker": a.idx, "defender": d.idx, "verb": verb, "landed": false, "part": "", "armor": [], "tissue": [],
		"p": 0.0, "E": 0.0, "q": 0.0, "severed": false, "artery": false, "glanced": false, "defence": "", "lodged": false}
	if V and not pre.is_empty():
		steps.append(["pre", pre])
	var helpless := d.helpless()
	var rel: String = sim._rel(a, d) if not arrow else String(shot["rel"])
	d.last_hit_rel = rel
	var att: float = sim._eff(a, wskill, "hit") if not arrow else float(shot["att"])
	if w_item != null:
		att += (DB.quality_mult(w_item.quality) - 1.0) * Formulas.QUALITY_HIT_LEVELS
		if float(wt.get("reach", 80)) < 60.0 and sim._dist(a.cell, d.cell) <= 1:
			att += Formulas.SHORT_BLADE_CLOSE_BONUS
	if rel != "front":
		att += Formulas.REAR_ATT_BONUS - 0.25 * du.skill("observer")
	if not arrow:   # bows: the draw's exertion, XP and attribute use were paid when the arrow was loosed
		au.body.exertion += Formulas.exertion_swing(float(sw["E"]), au.attr("END"), a.breath_bad) * a.fatigue_mult
		if a.buzz_state == "drunk" or a.buzz_state == "hammered":
			if a.swing_count % 5 == 1:
				sim._food_line(a, "food_swing", {"dl": d.label})
		elif a.belly_state == "starving" or a.belly_state == "hungry":
			sim._food_gasp(a)
		sim._learn(a, wskill, Learning.XP_SWING)
		sim._learn(a, "fighter", Learning.XP_FIGHTER)
		sim._use(a, wskill)
		sim._use(a, "fighter", 0.5)
	d.last_attacked_tick = sim.tick
	if V:
		if arrow:
			steps.append(["shot", shot])
		steps.append(["att", wskill, au.skill(wskill), att, sim._alv(a, "hit" if not arrow else "aim"), au.skill("fighter"), sim._cond(a), rel, a.prone and not arrow])
	# ---- one defence per attack (survey item 1)
	if arrow:
		# bows: dodge, then shield (x2 vs projectiles), then armour; no parrying arrows (sim/archery.gd)
		if not helpless and not sim._force_land and Archery.defend(sim, a, d, D, steps, att, rel):
			return
	elif sim._force_land:
		if V: steps.append(["help", "forced"])
	elif helpless:
		if V: steps.append(["help", "unconscious" if d.state == "unconscious" else "prone"])
	else:
		var seen := true
		if rel != "front":
			var sr := Formulas.roll_spot(sim.rng, Formulas.spot_chance(rel == "rear", du.skill("observer"), sim._alv(d, "spot")))
			if V: steps.append(sr)
			seen = sr["ok"]
			if sim.tick - d.last_flank_tick >= Formulas.FLANK_SHOCK_COOLDOWN:
				d.last_flank_tick = sim.tick
				sim._shock(d, Formulas.SHOCK_FLANKED, "flanked", false)
		if seen:
			var kind := ""
			var def := 0.0
			var ds := ""
			var sh: Item = sim._shield(du)
			if sh != null and not d.shield_dropped and d.grabbed_by < 0 and not d.bow_hand and (rel == "front" or (rel == "side" and du.skill("observer") >= Formulas.OBSERVER_ARC_LEVEL)):
				kind = "block"
				def = sim._eff(d, "shield_user", "block") + Formulas.DEF_BASE["block"] * float(sim._tmpl(sh).get("block", 1.0))
			elif sim._has_weapon(d) and d.lodged.is_empty() and d.grabbed_by < 0 and not d.bow_hand:   # bows: a bow in the hands parries nothing
				kind = "parry"
				var dwt: Dictionary = sim._tmpl(d.wielded)
				ds = String(dwt.get("skill", "fighter"))   # = _weapon_skill_name(d): d holds a weapon here
				var dsw := float(dwt.get("reach", 80)) / 100.0
				def = sim._eff(d, ds, "parry") + Formulas.PARRY_LEN_LEVELS * (dsw - 0.8) - Formulas.PARRY_P_LEVELS * maxf(0.0, float(sw["p"]) - 20.0) / 20.0 \
					+ (float(dwt.get("parry", 0.5)) - 0.5) * 4.0
			elif d.grabbed_by < 0:
				kind = "dodge"
				var enc: float = sim._enc_ratio(d) * (1.0 - minf(0.75, du.skill("armor_user") * Formulas.ARMOR_USER_RELIEF))
				def = sim._eff(d, "dodger", "dodge") - Formulas.DODGE_ENC_LEVELS * enc
			if kind != "":
				var p_through := Formulas.contest_through(att, def)
				var recent := 0
				for t0 in d.defence_ticks:
					if sim.tick - int(t0) <= Formulas.SATURATION_WINDOW:
						recent += 1
				var sat := Formulas.saturation(recent)
				var p_def := maxf(0.0, 1.0 - p_through - sat)
				if d.rage_ticks > 0 and kind != "block":
					p_def *= Formulas.RAGE_DEF_MULT
				if kind == "dodge" and sim._held_in_place(d):
					p_def *= Formulas.HELD_VICTIM_DODGE
				if kind == "dodge" and not d.lodged.is_empty():
					p_def *= Formulas.HELD_WIELDER_DODGE
				var cr := Formulas.roll_contest(sim.rng, 1.0 - p_def, kind)
				if V:
					steps.append(["def", kind, def, p_through, sat, 1.0 - p_def, recent])
					steps.append(cr)
				d.defence_ticks.append(sim.tick)
				if d.defence_ticks.size() > 8:
					d.defence_ticks.pop_front()
				du.body.exertion += Formulas.exertion_defend(du.attr("END"), d.breath_bad) * d.fatigue_mult
				var sk: String = "shield_user" if kind == "block" else (ds if kind == "parry" else "dodger")
				if not cr["ok"]:
					sim._learn(d, sk, Learning.XP_DEFEND)
					sim._learn(d, "fighter", Learning.XP_FIGHTER)
					sim._use(d, sk)
					D["out"] = kind
					D["def"] = kind
					D["sh"] = sim._item_name(sh) if kind == "block" else ""
					D["dw"] = sim._item_name(d.wielded) if kind == "parry" else ""
					sim.last_strike["defence"] = kind
					_strike_end(sim, a, d, D, kind, "", false)
					return
				sim._learn(d, sk, Learning.XP_DEFEND_TRY)
		elif V:
			steps.append(["note", "attack from the %s unseen: no defence" % rel])
	sim._learn(a, wskill, Learning.XP_HIT)
	# ---- body part (DF: weighted by relsize; no armor/wound evaluation; skill-blind anatomy)
	var body := du.body
	if d.parts_cache.is_empty():
		var cids := []
		var cws := []
		var cnames := []
		for p in body.plan()["parts"]:
			if not d.lost.has(p["id"]) and not p.get("internal", false):   # DF: inner parts are reached through their parent
				cids.append(p["id"])
				cws.append(float(p.get("relsize", 100)))
				cnames.append(p.get("name", p["id"]))
		d.parts_cache = [cids, cws, cnames]
	var ids: Array = d.parts_cache[0]
	var ws: Array = d.parts_cache[1]
	var names: Array = d.parts_cache[2]
	if helpless and not arrow and ids.has("head"):   # (an arrow falls where it falls)
		ws = ws.duplicate()
		ws[ids.find("head")] *= Formulas.HELPLESS_HEAD_WEIGHT
	if ids.is_empty():
		D["out"] = "harmless"
		_strike_end(sim, a, d, D, "miss", "", false)
		return
	var part_id: String = sim._force_part
	var force_inner := ""
	if part_id == "":
		var prr := Formulas.roll_body_part(sim.rng, ws, names)
		if V: steps.append(prr)
		part_id = ids[prr["i"]]
	elif _pdef(body, part_id).get("internal", false):   # inspection strike aimed at an inner part: through its parent
		force_inner = part_id
		part_id = String(_pdef(body, part_id).get("parent", ""))
	var pdef: Dictionary = _pdef(body, part_id)
	var part_name: String = pdef.get("name", part_id)
	D["part"] = part_id
	D["pname"] = part_name
	# v0.013: no face roll; the face's parts (eyes, nose, cheeks, lips, mouth, teeth ...) are targets of their own (DF)
	# ---- the one strike-quality roll, then deterministic physics
	var q := 1.0
	var p: float
	var energy: float
	var wmat: Dictionary
	var qw := 1.0
	var w_size := 0.0
	if arrow:
		# bows: no strike-quality roll (skill never adds energy); the aim roll set how square it lands
		p = float(shot["p"]) * float(shot["sq"])
		energy = float(shot["E"]) * float(shot["sq"])
		wmat = shot["mat"]
		w_size = float(shot["w_size"])
		if V: steps.append(["note", "arrow: E %.1f J, p %.2f, squareness x%.2f (no strike-quality roll: skill never adds energy)" % [float(shot["E"]), float(shot["p"]), float(shot["sq"])]])
	else:
		var q_level: float = float(au.skill(wskill)) + sim._alv(a, "quality")
		var sq := Formulas.roll_strike_quality(sim.rng, q_level, au.attr("KIN"))
		q = sq["q"]
		if V:
			steps.append(sq)
			steps.append(["swing", sw])
		p = float(sw["p"]) * q
		energy = float(sw["E"]) * q
		wmat = atk["native_material"] if a.dragon and atk.get("native_material") is Dictionary else (w_item.mat() if w_item != null else DB.materials.get(String(atk.get("mat", "bone")), DB.materials.get("bone", {})))
		qw = DB.quality_mult(w_item.quality) if w_item != null else 1.0
		w_size = float(wt.get("head_cm3", 0)) if w_item != null else 0.0
		if a.prone:
			p *= Formulas.PRONE_ATTACKER_MOMENTUM
			energy *= Formulas.PRONE_ATTACKER_MOMENTUM
			if V: steps.append(["note", "attacker lying down: x%.1f" % Formulas.PRONE_ATTACKER_MOMENTUM])
		if helpless:
			p *= Formulas.PRONE_TARGET_MOMENTUM
			energy *= Formulas.PRONE_TARGET_MOMENTUM
			if V: steps.append(["note", "target lying down: x2 (df_wiki)"])
	var headed := w_item != null or arrow   # a made head (weapon or arrowhead) can glance off armour
	var edged := edged0
	var contact := float(atk.get("contact", 20))
	var pen_mm := float(atk.get("penetration", 0)) * Formulas.PENETRATION_MM_PER_UNIT
	if a.dragon:
		var provenance: Dictionary = {"dragon_uid": au.dragon_uid, "mass_kg": au.mass(), "strength": float(sw.get("str", au.combat_strength())), "base_strength": au.combat_strength(),
			"contact": contact, "penetration_mm": pen_mm, "momentum": p, "energy": energy, "material": wmat.duplicate(true)}
		D["dragon_attack"] = provenance
		sim.last_strike["dragon_attack"] = provenance.duplicate(true)
	var sharp := Formulas.sharpness(float(wmat.get("max_edge", 10000)))
	var budget := pen_mm * q * sharp if edged else 0.0  # a dull (tin) edge cuts shallower (tuned)
	# v0.014 gear damage: a chipped edge (Item.dull) cuts less and shallower; the head is tested for bends/snaps
	# only when the blow is struck with it (not a pommel or shaft bash)
	var gear_w: bool = sim.gear_wear and w_item != null and not arrow and not natural and _head_blow(verb, wt)
	if w_item != null and w_item.dull > 0.0 and edged:
		var dk := 1.0 - Formulas.DULL_EDGE_K * w_item.dull
		budget *= dk
		qw *= dk
	if V:
		steps.append(["q", q, p, energy, D["w"] if headed else verb, wmat.get("name", "?"), qw,
			sharp, atk.get("type", "blunt"), contact, budget, edged])
	var p_impact := p
	sim.last_strike["landed"] = true
	sim.last_strike["part"] = part_id
	sim.last_strike["p"] = p
	sim.last_strike["E"] = energy
	sim.last_strike["q"] = q
	# ---- armor coverage (one roll per worn piece over that part); helmets never cover the face and are off vs the helpless
	var covering := []
	var worn: Array = d.armor_for.get(part_id, d.armor_for.get(String(pdef.get("armor_as", "")), []))   # fingers under the gauntlet ...
	var cov_sk := 0.0
	var cov_kin := 0.0
	var cov_au := 0.0
	if not worn.is_empty():   # perf: the coverage inputs once per strike, not per worn piece
		cov_sk = float(au.skill(wskill))
		cov_kin = float(au.attr("KIN"))
		cov_au = float(du.skill("armor_user"))
	for item in worn:
		if item["slot"] == "helm" and helpless:
			continue
		var cv := Formulas.coverage(item["cov"], thrust, cov_sk, cov_kin, cov_au)
		var cr := Formulas.roll_coverage(sim.rng, item["name"], cv)
		if V: steps.append(cr)
		if cr["ok"]:
			covering.append(item)
	# ---- armor layers, outside-in (deterministic tests)
	var stop_item := ""
	var glanced := false
	for item in covering:
		var mat: Dictionary = item["mat"]
		var ait: Item = item.get("item")
		var qa := DB.quality_mult(ait.quality if ait != null else int(item["q"]))   # v0.014: dents cost quality at once
		var th: float = float(item["t"]) * (1.0 - Formulas.SPOT_WEAKEN * float(item.get("w", 0.0)))   # a damaged spot
		var nm: String = item["name"]
		if edged:
			var R := Formulas.edge_resistance(mat, wmat, contact, qa, qw, th, true)
			if energy >= R:
				var e0 := energy
				if arrow:   # bows: the arrow spends part of the layer's resistance cutting through it
					var keep := (energy - R * Formulas.ARROW_ARMOR_SPEND) / maxf(energy, 0.001)
					energy *= keep
					p *= sqrt(maxf(keep, 0.0))
				energy *= Formulas.PASS_KEEP
				p *= Formulas.PASS_KEEP
				budget -= th
				if V: steps.append(["ae", nm, th, e0, R, true, energy, p, budget])
				D["armor"].append([nm, "cut", String(mat.get("kind", ""))])
				sim.last_strike["armor"].append({"name": nm, "result": "cut"})
				# v0.014: the edge went through: a point punctures (a hole), a cutting edge splits the piece (broken)
				_armor_dmg(sim, item, "punctured" if contact <= Formulas.PIERCE_CONTACT else "split", D, steps)
				continue
			edged = false
			stop_item = nm
			if V: steps.append(["ae", nm, th, energy, R, false, energy, p, budget])
			if gear_w:
				_gear_chip(sim, w_item, mat, wmat, nm, true, D, steps)
		if headed and Formulas.blunt_deflects(w_size, wmat, contact, mat):
			if V: steps.append(["ad", nm, w_size, float(wmat.get("impact_yield", 0)), contact, float(mat.get("density", 0))])
			glanced = true
			D["armor"].append([nm, "glance"])
			sim.last_strike["armor"].append({"name": nm, "result": "glance"})
			p = 0.0
			break
		var Rb := Formulas.blunt_resistance(mat, contact, qa, th, "armor")
		var p1 := p
		if p >= Rb:
			p *= Formulas.PASS_KEEP
			if V: steps.append(["ab", nm, p1, Rb, true, "", 1.0, p])
			D["armor"].append([nm, "dented", String(mat.get("kind", ""))])
			sim.last_strike["armor"].append({"name": nm, "result": "dented"})
			# v0.014: forced through (the fracture form): plate cracks, scale/lamellar shatters (broken); mail rings burst,
			# cloth and leather tear (a hole). The weapon met a layer that gave way at Rb.
			_armor_dmg(sim, item, "cracked" if item["rigid"] else ("shattered" if item["semi"] else ("burst" if String(mat.get("kind", "")) == "metal" else "torn")), D, steps)
			if gear_w:
				_gear_bend(sim, a, w_item, wt, wmat, contact, Rb, nm, true, D, steps)
		else:
			var tr := Formulas.armor_transmit(item["rigid"], item["semi"], item["padded"])
			p *= tr
			if V: steps.append(["ab", nm, p1, Rb, false, "rigid" if item["rigid"] else ("semi-rigid" if item["semi"] else ("padded" if item["padded"] else "flexible")), tr, p])
			D["armor"].append([nm, "held"])
			sim.last_strike["armor"].append({"name": nm, "result": "held"})
			# v0.014: held, but past the metal's yield: a plate or lame is dented (a quality step; mail and cloth flex);
			# the weapon took the whole blow back
			if (item["rigid"] or item["semi"]) and String(mat.get("kind", "")) == "metal" and p1 >= Formulas.yield_resistance(mat, contact, qa, th):
				_armor_dmg(sim, item, "dented", D, steps)
			if gear_w:
				_gear_bend(sim, a, w_item, wt, wmat, contact, p1, nm, true, D, steps)
	if covering.size() > 0:
		sim._learn(d, "armor_user", Learning.XP_ARMOR_HIT)
		sim._use(d, "armor_user")
	D["stop"] = stop_item
	D["glance"] = glanced
	# ---- tissue layers: the struck part's own layers, then (DF) one inner part picked by relative size when the
	# blow gets through them (organs, ribs, spine, skull, brain); a part "around" the pick is passed first (skull).
	# Sparse body: an unhurt part is read from the plan's shared copy and stored (body.wound_part) on its first wound.
	var tou := Formulas.tou_mult(du.attr("TOU"))
	var str_musc := pow(maxf(200.0, du.combat_strength() if d.dragon else float(du.attr("STR"))) / 1000.0, Formulas.STR_MUSCLE_EXP)
	var cut_all := edged and not glanced
	var pain_raw := 0.0
	var bleed_add := 0.0
	var art_rate := 0.0
	var death_cause := ""
	var reached := false
	var skull_p := -1.0
	var stopped_in := ""
	var stopped_by_bone := false
	var depth_used := 0.0
	var layers_cut := 0
	var d_funcs: Array = D["funcs"]
	var d_layers: Array = D["layers"]
	var ls_tissue: Array = sim.last_strike["tissue"]
	var wf := -1.0                   # Formulas.width_factor(contact), computed on first use
	sim._bleed_defer = d             # one bleed recount for the defender after the layers and the sever (same totals)
	var inner_info: Array = _inner_of(sim, body, part_id, pdef)   # [ids, weights, names, connector id, under-pressure id]
	var seg_pid := part_id           # the part whose layers the blow is going through now
	var seg_def := pdef
	var seg_n := 0                   # 0 = the struck part, 1+ = inside it
	var pending := ""                # the inner pick, when a part around it is passed first
	var ext_cut_all := false         # an edge went through every layer of the struck part
	var conn_cut := false            # ... and through its connector (upper spine, skull): needed to sever
	var musc_through := false        # the struck part's muscle cut through (DF HAS_NERVES)
	var spent := false
	var inner_hit := ""
	var stopped_part := part_id
	while seg_pid != "" and not glanced:
		var layers: Array = body.layers_of(seg_pid)
		var stored: bool = body.parts.has(seg_pid)
		var ldm := _ldef_map(sim, seg_pid, seg_def)
		var numb := bool(body.part(seg_pid).get("nerve_s", false))   # sensory nerve severed: no pain from this part
		for i in layers.size():
			var L: Dictionary = layers[i]
			var tissue: String = L["tissue"]
			var lname: String = L.get("name", tissue)
			var ld: Dictionary = ldm.get(lname, {})
			if ld.has("hit"):
				var ir := Formulas.roll_inner_layer(sim.rng, lname, float(ld["hit"]))
				if V: steps.append(ir)
				if not ir["ok"]:
					continue
			if p < 0.2 and energy < 1.0:
				if V: steps.append(["note", "nothing left of the blow"])
				cut_all = false
				spent = true
				break
			reached = true
			var tmat: Dictionary = _tmat(sim, String(ld.get("mat", tissue)))
			var th := float(ld.get("t", L.get("t", 1.0))) * body.scale * (str_musc if tissue == "muscle" else 1.0)
			if d.dragon and ld.has("dragon_material"):
				tmat = d.dragon_profile[str(ld["dragon_material"]) + "_material"]
			if d.dragon and ld.has("dragon_geometry"):
				th = float(d.dragon_profile[str(ld["dragon_geometry"])]) * 10.0 * float(ld.get("geometry_share", 1.0))
			var dmg := 0.0
			var kind := ""
			var through := false
			var was_edge := false
			var frac := 0.0
			if edged and budget <= 0.0:
				edged = false
				cut_all = false
				stopped_in = lname
				stopped_part = seg_pid
				if V: steps.append(["spent"])
			if edged:
				var R := Formulas.edge_resistance(tmat, wmat, contact, 1.0, qw, th, false)
				if energy >= R:
					var depth := minf(th, budget)
					var e_spend := 0.0
					if arrow:   # bows: energy is spent layer by layer, front to back (pure physics pass-through)
						var cost := R * th / 10.0 * Formulas.ARROW_TISSUE_SPEND
						depth = minf(depth, th * minf(1.0, energy / maxf(cost, 0.001)))
						e_spend = cost * depth / th
					frac = depth / th
					budget -= depth
					depth_used += depth
					through = frac >= 0.999
					if through and seg_n == 0 and tissue == "muscle":
						musc_through = true
					if wf < 0.0:
						wf = Formulas.width_factor(contact)
					dmg = minf(1.0, frac * wf * (Formulas.ORGAN_FRAGILITY if Formulas.is_fragile(tissue) else 1.0) * tou)
					kind = Formulas.edge_kind(tissue, contact, minf(1.0, float(L["dmg"]) + dmg))
					was_edge = true
					layers_cut += 1
					var e0 := energy
					if arrow:
						var keep := maxf(0.0, energy - e_spend) / maxf(energy, 0.001)
						energy *= keep
						p *= sqrt(keep)
					else:
						energy *= Formulas.PASS_KEEP
						p *= Formulas.PASS_KEEP
					if V: steps.append(["te", lname, tissue, th, e0, R, true, frac, dmg, tou, energy, p])
					if ld.has("artery"):
						# DF TL_MAJOR_ARTERIES (heart, throat) roll x2.5 like the old throat artery layer
						var ar := Formulas.roll_artery(sim.rng, lname, clampf(Formulas.ARTERY_CHANCE * frac * (1.5 if thrust else 1.0) * (2.5 if ld.get("major", false) or tissue == "vessel" else 1.0), 0.0, 0.95))
						if V: steps.append(ar)
						if ar["ok"]:
							if not stored:
								layers = body.wound_part(seg_pid)["layers"]
								stored = true
								L = layers[i]
							var ab := float(ld["artery"]) * Formulas.BLEED_ARTERY_MULT * tou
							sim._add_bleed(d, seg_pid, L, ab, Formulas.CLOT_ARTERY)
							bleed_add += ab
							art_rate = maxf(art_rate, ab)
							D["artname"] = lname
					if not through:
						edged = false
						cut_all = false
						stopped_in = lname
						stopped_part = seg_pid
				else:
					if V: steps.append(["te", lname, tissue, th, energy, R, false, 0.0, 0.0, tou, energy, p])
					edged = false
					cut_all = false
					stopped_in = lname
					stopped_part = seg_pid
					stopped_by_bone = tissue == "bone"
					if gear_w and stopped_by_bone and seg_n == 0:   # v0.014: an edge turned by harder bone chips
						_gear_chip(sim, w_item, tmat, wmat, _bone_word(lname, seg_def, seg_pid), false, D, steps)
			if not was_edge:
				cut_all = false
				if tissue == "bone":
					if seg_pid == "skull":
						skull_p = p
					var Rb := Formulas.blunt_resistance(tmat, contact, 1.0, th, "bone")
					var p0 := p
					if gear_w and seg_n == 0:   # v0.014: the bone pushes back on the head with min(p, what it takes)
						_gear_bend(sim, a, w_item, wt, wmat, contact, minf(p0, Rb), _bone_word(lname, seg_def, seg_pid), false, D, steps)
					if p >= Rb:
						dmg = Formulas.bone_blunt_dmg(p, Rb) * tou
						kind = Formulas.blunt_kind("bone", minf(1.0, float(L["dmg"]) + dmg))
						p *= Formulas.PASS_KEEP
						if V: steps.append(["tb", lname, th, p0, Rb, true, dmg, p, 0])
					else:
						var tr := Formulas.tissue_transmit(tmat, false)
						p *= tr
						if V: steps.append(["tb", lname, th, p0, Rb, false, 0.0, p, int(tmat.get("impact_strain", 100))])
				else:
					var Rs := Formulas.blunt_resistance(tmat, contact, 1.0, th, "soft")
					dmg = Formulas.soft_blunt_dmg(tissue, p, Rs, th, float(L["dmg"])) * tou
					if dmg < 0.02:
						dmg = 0.0
					else:
						kind = Formulas.blunt_kind(tissue, minf(1.0, float(L["dmg"]) + dmg))
					var p0 := p
					p *= Formulas.PASS_KEEP
					if V: steps.append(["ts", lname, tissue, th, p0, dmg, p])
				energy = 0.0
			if dmg <= 0.0:
				continue
			if not stored:
				layers = body.wound_part(seg_pid)["layers"]
				stored = true
				L = layers[i]
			var pr := _wound_core(sim, d, seg_pid, seg_def, L, ld, dmg, kind, was_edge, through, tou, d_funcs)
			if not numb:
				pain_raw += pr
			bleed_add += sim._wl_bleed
			if sim._wl_death != "":
				death_cause = sim._wl_death
			if seg_n > 0:
				inner_hit = seg_pid
			var st := Formulas.state_word(tissue, was_edge, through, float(L["dmg"]), contact <= Formulas.PIERCE_CONTACT)
			d_layers.append([lname, tissue, st, dmg, frac, seg_pid])   # v0.014: + the part (organ clauses in the log)
			ls_tissue.append({"part": seg_pid, "layer": lname, "tissue": tissue, "kind": kind, "dmg": dmg, "state": st})
		# ---- the end of this part's layers: on into the body, or done
		var next := ""
		if seg_n == 0:
			ext_cut_all = cut_all and reached
			if ext_cut_all and String(inner_info[4]) != "":   # DF UNDER_PRESSURE: the wall is cut open, the guts spill
				var gp := body.wound_part(String(inner_info[4]))
				if not gp.get("spilled", false):
					gp["spilled"] = true
					# the wound is the spill itself (healing times it as a mangled organ; the report says "spilled")
					gp["layers"][0]["kind"] = Formulas.worse_kind(String(gp["layers"][0]["kind"]), "mangled")
					d_funcs.append("guts")
					if V: steps.append(["note", "the wall of the %s is cut open: the %s spill out (DF UNDER_PRESSURE)" % [part_name, _pdef(body, String(inner_info[4])).get("name", "guts")]])
			if not spent and (p >= 0.2 or energy >= 1.0) and (force_inner != "" or not (inner_info[0] as Array).is_empty()):
				var pick := force_inner
				if pick == "":
					var irr := Formulas.roll_inner_part(sim.rng, inner_info[1], inner_info[2])
					if V: steps.append(irr)
					pick = String(inner_info[0][irr["i"]])
				var around := String(_pdef(body, pick).get("around", ""))
				if around != "":
					next = around
					pending = pick
				else:
					next = pick
		else:
			if seg_def.get("connector", false):
				conn_cut = cut_all
			if pending != "" and not spent and (p >= 0.2 or energy >= 1.0):
				next = pending
			pending = ""
		seg_pid = next
		seg_def = _pdef(body, next) if next != "" else {}
		seg_n += 1
	D["art"] = art_rate
	if art_rate > 0.0:
		var aev: Dictionary = sim._event("artery", a.idx, d.idx, "", true, part_id)
		aev["rate"] = art_rate
		aev["text"] = CombatText.decisive("artery", {"D": BattleSim._cap(d.label), "d": d.label, "P": D["pname"], "RATE": "%.2f" % art_rate,
			"his": d.pron, "ART": D.get("artname", "artery")}, art_rate, a.voff + sim.tick)
	# ---- severing (edge through every tissue layer of a severable part, with momentum to spare)
	var severed := false
	var knocked := false
	# DF SOCKET: a tooth broken (or cut through) is knocked out; nothing more (no sever bleeding, no extra pain)
	if pdef.get("socket", false) and not d.lost.has(part_id) and body.parts.has(part_id):
		var tl: Array = body.parts[part_id]["layers"]
		if not tl.is_empty() and (String(tl[0]["kind"]) in ["broken", "mangled", "destroyed"] or ext_cut_all):
			knocked = true
			var tp := body.wound_part(part_id)
			tp["severed"] = true
			tp["knocked"] = true
			_mark_lost(d, part_id)
			body.permanent.append("lost %s" % part_name)
			d_funcs.append("tooth")
	# DF HAS_NERVES: the muscle of a limb, hand or foot cut through severs its motor and sensory nerves
	if pdef.get("nerves", false) and musc_through and not knocked:
		var np := body.wound_part(part_id)
		if not np.get("nerve_m", false):
			np["nerve_m"] = true
			np["nerve_s"] = true
			d_funcs.append("nerve")
			d_funcs.append("numb")
	var need_p := Formulas.SEVER_MIN_P * body.scale * float(pdef.get("relsize", 100)) / 100.0
	var conn_ok := conn_cut or String(inner_info[3]) == ""   # DF CONNECTOR (upper spine, skull) must be cut through too
	if not knocked and ext_cut_all and conn_ok and pdef.get("severable", false) and contact >= Formulas.SEVER_MIN_CONTACT and p >= need_p:
		severed = true
		var sp := body.wound_part(part_id)
		sp["severed"] = true
		_mark_lost(d, part_id)
		var sb := float(pdef.get("relsize", 100)) * Formulas.BLEED_SEVER_PER_RELSIZE
		sim._add_bleed(d, part_id, sp["layers"][0], sb, Formulas.CLOT_ARTERY)
		bleed_add += sb
		pain_raw += Formulas.PAIN_SEVER
		body.permanent.append("lost %s" % part_name)
		if V: steps.append(["sever", p, need_p, sb])
		D["sever"] = true
		if part_id == "neck" or part_id == "head" or _has_vital(pdef):
			death_cause = "decapitated" if part_id in ["head", "neck"] else "lost a vital part"
	sim._bleed_defer = null
	if sim._bleed_dirty:
		sim._bleed_dirty = false
		sim._recount_bleed(d)
	# cut path (from the swing actually made: hack = overhead, slash = forehand/backhand diagonal, thrust = straight)
	if edged0 and layers_cut > 0:
		D["path"] = _cut_path(a, verb, thrust)
	# ---- stuck weapon (survey lodge rules): edged attack reached muscle and stopped inside the body
	if edged0 and w_item != null and not w_item.broken and not severed and stopped_in != "" and layers_cut > 0 and death_cause == "" and _reached_muscle(D):
		var base := Formulas.lodge_base(verb, thrust)
		var ch := base * clampf(depth_used / maxf(1.0, pen_mm), 0.0, 1.0) * (Formulas.LODGE_BONE_MULT if stopped_by_bone else 1.0) \
			* float(wt.get("lodge", 1.0))
		var lr := Formulas.roll_lodge(sim.rng, ch)
		if V: steps.append(lr)
		if lr["ok"]:
			a.lodged = {"victim": d.idx, "part": stopped_part, "layer": stopped_in, "p0": p_impact, "layers": layers_cut, "item": w_item}
			d.stuck_in_me.append({"wielder": a.idx, "item": w_item, "part": stopped_part, "layers": layers_cut})
			D["lodged"] = true
			sim.last_strike["lodged"] = true
	if arrow:
		# bows: an arrow lodges on any penetration [DF] (no roll); with energy to spare after the last layer it
		# comes out the other side (exit wound) and flies on
		var exits := cut_all and reached and layers_cut > 0 and energy >= Formulas.ARROW_EXIT_MIN_J
		var lodge_layer := stopped_in
		var lodge_part := stopped_part
		if lodge_layer == "" and layers_cut > 0 and not exits and d_layers.size() > 0:
			lodge_layer = String(d_layers[-1][0])
			lodge_part = String(ls_tissue[-1]["part"])
		sim._shot_out = {"exit": exits, "E": energy, "end": "armor" if layers_cut == 0 else ("" if exits else "body")}
		if exits:
			D["exit"] = true
			if V: steps.append(["note", "the arrow passes clean through with %.1f J left and flies on" % energy])
		elif layers_cut > 0 and lodge_layer != "":
			d.arrows_in.append({"kind": shot["kind"], "part": lodge_part, "layer": lodge_layer})
			D["lodged"] = true
			sim.last_strike["lodged"] = true
	# ---- pain, stagger, consequences
	var pm := Formulas.pain_mult(du.attr("WIL"), du.attr("END"), du.skill("discipline")) / d.pain_tol   # drink raises pain tolerance (Food)
	var pain_eff := pain_raw * pm
	if d.pain_tol >= 1.2 and pain_eff >= 10.0 and sim.tick - d.food_pain_tick >= 100 and d.alive():
		d.food_pain_tick = sim.tick
		sim._food_line(d, "food_pain", {"pain": pain_eff, "tol": d.pain_tol})
	body.pain += pain_eff
	d.tempo_tick = -1000
	d.pain_floor_src += pain_eff
	if pain_eff > 0.0:
		Learning.note_use(d.attr_use, "pain", pain_eff / 50.0)
	if V: steps.append(["pain", pain_eff, pain_raw, pm, body.pain, bleed_add, sim._bleed_total.get(d.idx, 0.0), body.blood, body.blood_max])
	var stab := Formulas.stability(du.mass(), d.gear_mass, d.leg_impair, d.prone, sim._shield(du) != null and not d.shield_dropped, du.attr("AGI"))
	var stagger := 0.0 if glanced else p_impact / maxf(1.0, stab) * float(atk.get("stagger", 1.0))
	if V: steps.append(["stag", p_impact, stab, stagger])
	d.last_attacker = a.idx
	sim.last_strike["severed"] = severed
	sim.last_strike["artery"] = art_rate > 0.0
	sim.last_strike["glanced"] = glanced
	D["kill"] = death_cause
	if pain_eff > 0.0:
		D["pe"] = snappedf(pain_eff, 0.1)   # v0.014: the log's reaction words read the real pain
	if D["layers"].is_empty():
		D["out"] = "glance" if glanced else ("absorbed" if covering.size() > 0 else "harmless")
	elif severed:
		D["out"] = "decap" if part_id in ["neck", "head"] else "sever"
	_strike_end(sim, a, d, D, "hit", part_id, art_rate > 0.0 or severed)
	if gear_w and w_item.broken and sim._has_weapon(a) and a.wielded == w_item:
		# v0.014: the weapon snapped on this blow: what is left in his hand is useless (scrap at the battle's end)
		a.weapon_dropped = true
		a.reach_tiles = 1
		sim._event("snap", a.idx, d.idx, "", false, part_id)
	if death_cause != "" or severed:
		sim._say(a, d, "kill" if death_cause != "" else "maim", rel)
	if D["layers"].size() > 0:
		sim._event("wound", a.idx, d.idx, "", false, part_id)
	if D["lodged"]:
		sim._ev_simple("lodged", a.idx, d.idx, "lodged", {"w": D["w"], "part": D["pname"]}, false, part_id)
	if severed:
		var se: Dictionary = sim._event("sever", a.idx, d.idx, CombatText.decisive("sever_head" if part_id in ["head", "neck"] else "sever",
			{"D": BattleSim._cap(d.label), "d": d.label, "P": part_name, "his": d.pron}, 0.0, a.voff + sim.tick), true, part_id)
		se["momentum_left"] = p
		se["direction"] = Vector2(float(signi(d.cell.x - a.cell.x)), -0.5)
	if death_cause != "":
		sim._kill(d, a.idx, death_cause)
		return
	if not d.alive():
		return
	if "guts" in D["funcs"]:
		sim._event("guts", a.idx, d.idx, CombatText.decisive("guts", {"D": BattleSim._cap(d.label), "d": d.label, "P": D["pname"], "his": d.pron},
			0.0, a.voff + sim.tick), true, part_id)
	sim._update_functions(d, true, "" if severed else part_id, inner_hit)
	if "airway" in D["funcs"] or "drown" in D["funcs"]:
		sim._ev_simple("stun", d.idx, -1, "breath", {})
	if pain_eff > 0.0:
		sim._shock(d, pain_eff / Formulas.SHOCK_WOUND_DIV + (Formulas.SHOCK_SEVER if severed else 0.0), "wounded", pain_eff >= Formulas.PAIN_STUN)
	if d.state != "unconscious" and d.alive():
		if body.pain > Formulas.PAIN_KO:
			sim._knock_out(d, "pain")
		elif d.think_dmg >= Formulas.THINK_KO:
			sim._knock_out(d, "head")
		elif not d.prone and (pain_eff >= Formulas.PAIN_KNOCKDOWN or stagger >= Formulas.STAGGER_KNOCKDOWN):
			sim._fall(d, "knocked" if stagger >= Formulas.STAGGER_KNOCKDOWN else "pain", Formulas.KNOCKDOWN_TICKS)
		else:
			var add := int(round(stagger * Formulas.STAGGER_TICKS_PER))
			var why := ""
			if pain_eff >= Formulas.VOMIT_PAIN:
				add += Formulas.STUN_TICKS
				why = "vomit"
			elif pain_eff >= Formulas.PAIN_STUN:
				add += Formulas.STUN_TICKS
				why = "pain"
			elif pain_eff >= Formulas.PAIN_CRY:
				D["rx"] = "cry"   # v0.014: hurt, below a stun: he cries out (the stun/vomit/fall/out lines say the rest)
			if skull_p > 0.0:
				var hs := Formulas.roll_head_stun(sim.rng, clampf(skull_p / Formulas.HEAD_STUN_P, 0.0, 0.9))
				if V: steps.append(hs)
				if hs["ok"]:
					add += Formulas.STUN_TICKS
					why = "head"
			if add > 0 and d.active():
				d.delay_uncapped += add
				add = mini(add, maxi(0, int(Formulas.MAX_ACTION_DELAY * (d.action_total - d.action_delay)) - d.action_delay))
				d.action_delay += add
				d.action_ticks += add
				d.action_total += add
				if why != "":
					sim._ev_simple("stun", d.idx, -1, "stun_" + why, {"ticks": add, "stagger": stagger, "pain": pain_eff})

# ---------------------------------------------------------------- v0.014 gear damage (Formulas: gear damage block)
## The blow is struck with the weapon's head (blade, point or head), not a pommel, haft or shaft.
static func _head_blow(verb: String, _wt: Dictionary) -> bool:
	return not (verb.contains("pommel") or verb.contains("shaft") or verb.contains("haft") or verb.contains("butt"))

## A solid head (no edged attack: maces, hammers, clubs) bends as a whole head, a blade by its section.
static func _solid_head(wt: Dictionary) -> bool:
	for at in wt.get("attacks", []):
		if String(at.get("type", "")) == "edge":
			return false
	return true

## The weapon's head took `reaction` back from the layer that stopped it (`piece`: an armour piece or a bone layer).
## Snap past the fracture form (broken: scrap), bend past the yield form (bent back after: -1 quality step, -2 when
## twice the yield). One bend/snap per strike; nothing below the yield.
static func _gear_bend(sim, _a: Fighter, w: Item, wt: Dictionary, wmat: Dictionary, contact: float, reaction: float, piece: String,
		is_armor: bool, D: Dictionary, steps: Array) -> void:
	if w.broken or w.is_legend() or (D.has("wd") and String(D["wd"][0]) != "chip"):   # v0.014: a legendary piece never bends or snaps
		return
	var t := Formulas.head_section_mm(float(wt.get("head_cm3", 0)), _solid_head(wt))
	var qw := DB.quality_mult(w.quality)
	var r_yield := Formulas.yield_resistance(wmat, contact, qw, t)
	if reaction < r_yield:
		return
	var r_snap := Formulas.blunt_resistance(wmat, contact, qw, t, "armor")
	if reaction >= r_snap:
		w.broken = true
		w.wear = 3
		D["wd"] = ["snap", piece, is_armor]
		if sim.verbose: steps.append(["note", "WEAPON SNAPS: reaction p %.1f >= fracture R %.1f (%s head %.1f mm)" % [reaction, r_snap, w.material, t]])
	else:
		var n := 2 if reaction >= Formulas.BEND_SEVERE * r_yield else 1
		var q0 := w.quality
		w.quality = maxi(0, w.quality - n)
		sim._iname.erase(w)
		D["wd"] = ["bend", piece, is_armor]
		if sim.verbose: steps.append(["note", "weapon bends: reaction p %.1f >= yield R %.1f (%s head %.1f mm); quality %d -> %d" % [reaction, r_yield, w.material, t, q0, w.quality]])

## An edge stopped by a harder layer chips (Item.dull); each full 1.0 is ground away for a quality step.
static func _gear_chip(sim, w: Item, layer_mat: Dictionary, wmat: Dictionary, piece: String, is_armor: bool, D: Dictionary, steps: Array) -> void:
	if w.broken or w.is_legend():   # v0.014: a legendary edge never chips
		return
	var c := Formulas.chip_amount(layer_mat, wmat)
	if c <= 0.0:
		return
	w.dull += c
	if w.dull >= 1.0:
		w.dull -= 1.0
		w.quality = maxi(0, w.quality - 1)
		sim._iname.erase(w)
	if not D.has("wd"):
		D["wd"] = ["chip", piece, is_armor]
	if sim.verbose: steps.append(["note", "edge chips on the %s (shear yield %d vs the blade's %d): dull %.2f" % [piece,
		int(layer_mat.get("shear_yield", 0)), int(wmat.get("shear_yield", 0)), w.dull]])

## "skull", "cartilage" as they are; a plain "bone" layer is named by its part ("shin bone" reads better as
## "right lower leg bone" than "bone").
static func _bone_word(lname: String, pdef: Dictionary, pid: String) -> String:
	if lname != "bone":
		return lname
	return "%s bone" % String(pdef.get("name", pid))

## Damage to one worn piece at the struck spot (entry = its armor_for dict for this part).
static func _armor_dmg(sim, entry: Dictionary, kind: String, D: Dictionary, steps: Array) -> void:
	if not sim.gear_wear:
		return
	var it: Item = entry.get("item")
	var w := float(entry.get("w", 0.0))
	var add: float = Formulas.SPOT_BROKEN if kind in ARMOR_BROKEN_KINDS else (Formulas.SPOT_DENT if kind == "dented" else Formulas.SPOT_HOLE)
	entry["w"] = minf(1.0, w + add)
	if it != null and not it.is_legend():   # v0.014: a legendary piece is never broken or worn down (the spot still gives)
		if kind in ARMOR_BROKEN_KINDS:
			it.broken = true
			it.wear = 3
		elif not it.broken:
			it.quality = maxi(0, it.quality - 1)
	if not D.has("ad"):
		D["ad"] = []
	D["ad"].append([entry["name"], kind, String((entry["mat"] as Dictionary).get("kind", ""))])
	if sim.verbose: steps.append(["note", "  %s %s here (spot weakness %.2f)%s" % [entry["name"], kind, entry["w"],
		"; broken: scrap after the battle" if kind in ARMOR_BROKEN_KINDS else ("; quality %d" % it.quality if it != null else "")]])

static func _reached_muscle(D: Dictionary) -> bool:
	for l in D["layers"]:
		if l[1] in ["muscle", "organ", "bone", "tendon", "nerve", "vessel", "brain"]:
			return true
	return false

static func _cut_path(a: Fighter, verb: String, thrust: bool) -> String:
	if thrust:
		return "straight"
	var v := verb.split(" ")[0]
	if v == "hack" or v == "chop":
		return "top_bottom"
	# forehand from the attacker's right = the defender's left; every other swing comes back as a backhand
	return "tl_br" if a.swing_count % 2 == 1 else "br_tl"

static func _weapon_class(w: Item, atk: Dictionary) -> String:
	if w == null:
		return "natural"
	if atk.get("type", "") == "blunt":
		return "blunt"
	return "pierce" if float(atk.get("contact", 1000)) <= Formulas.PIERCE_CONTACT else "edge"

static func _ldef(sim, pid: String, pdef: Dictionary, lname: String) -> Dictionary:
	var ck: String = pdef.get("_ck", pid)   # monsters wave 1: non-humanoid plans carry "_ck" = "plan:part" (core/db.gd)
	if not sim._ldef_cache.has(ck):
		var m := {}
		for l in pdef.get("layers", []):
			m[l.get("name", l["tissue"])] = l
		sim._ldef_cache[ck] = m
	return sim._ldef_cache[ck].get(lname, {})

## The whole {layer name -> layer def} map of a part (same cache as _ldef; one lookup per strike).
static func _ldef_map(sim, pid: String, pdef: Dictionary) -> Dictionary:
	var ck: String = pdef.get("_ck", pid)
	if not sim._ldef_cache.has(ck):
		var m := {}
		for l in pdef.get("layers", []):
			m[l.get("name", l["tissue"])] = l
		sim._ldef_cache[ck] = m
	return sim._ldef_cache[ck]

## DB.materials[tissue] (muscle for an unknown tissue), cached per battle.
static func _tmat(sim, tissue: String) -> Dictionary:
	var m = sim._tmats.get(tissue)
	if m == null:
		m = DB.materials.get(tissue, DB.materials["muscle"])
		sim._tmats[tissue] = m
	return m

static func _has_vital(pdef: Dictionary) -> bool:
	for l in pdef.get("layers", []):
		if "vital" in l.get("functions", []):
			return true
	return false

static func _strike_end(sim, a: Fighter, d: Fighter, D: Dictionary, ev_type: String, part: String, decisive: bool) -> void:
	var entry := {"tick": sim.tick, "k": "strike", "d": D}
	var key: String = "strike:" + String(D["out"])
	D["vc"] = int(a.vcount.get(key, 0))
	a.vcount[key] = int(D["vc"]) + 1
	a.log.append(entry)
	d.log.append(entry)
	var e: Dictionary = sim._event(ev_type, a.idx, d.idx, "", decisive, part)
	e["entry"] = entry

## Applies damage to one tissue layer; returns {"pain", "bleed", "death", "funcs"} (pain raw, before tolerance).
static func _wound_layer(sim, f: Fighter, part_id: String, pdef: Dictionary, L: Dictionary, ld: Dictionary, dmg: float,
		kind: String, edge: bool, through: bool, tou: float = -1.0) -> Dictionary:
	var funcs := []
	var pain := _wound_core(sim, f, part_id, pdef, L, ld, dmg, kind, edge, through, tou, funcs)
	return {"pain": pain, "bleed": sim._wl_bleed, "death": sim._wl_death, "funcs": funcs}

## _wound_layer without the result dictionary (the strike path, perf): returns the raw pain, leaves the bleed added
## in _wl_bleed and a death cause (or "") in _wl_death, and appends lost functions to `funcs_out`.
static func _wound_core(sim, f: Fighter, part_id: String, pdef: Dictionary, L: Dictionary, ld: Dictionary, dmg: float,
		kind: String, edge: bool, through: bool, tou: float, funcs_out: Array) -> float:
	sim._wl_bleed = 0.0
	sim._wl_death = ""
	var dm0 := float(L["dmg"])
	L["dmg"] = minf(1.0, dm0 + dmg)
	L["kind"] = Formulas.worse_kind(String(L.get("kind", "")), kind)
	var tissue: String = L["tissue"]
	# DF tissue PAIN_RECEPTORS / VASCULAR from the layer def where the plan gives them (organs, cartilage, teeth, nerve)
	var pain := float(ld.get("pain", Formulas.PAIN_RECEPTORS.get(tissue, 5.0))) * Formulas.pain_kind_mult(kind, through)
	if edge or kind == "mangled":
		if tou < 0.0:   # callers that already have Formulas.tou_mult(f.unit.attr("TOU")) pass it in
			tou = Formulas.tou_mult(f.unit.attr("TOU"))
		var b := float(ld.get("vasc", Formulas.BLEED_VASCULAR.get(tissue, 1.0))) * Formulas.BLEED_MINOR_SCALE * dmg * tou
		sim._add_bleed(f, part_id, L, b, Formulas.CLOT_MINOR)
		sim._wl_bleed = b
	if not ld.has("functions"):
		return pain
	var funcs: Array = ld["functions"]
	var lim := Formulas.BRAIN_DEATH if "think" in funcs else Formulas.VITAL_DESTROY
	var dm := float(L["dmg"])
	if "vital" in funcs and dm >= lim:
		L["kind"] = "destroyed"
		sim._wl_death = "%s destroyed" % L.get("name", tissue)
	if "think" in funcs:
		f.think_dmg = dm
	if "breathe" in funcs and dm >= 0.5 and not f.breath_bad:
		f.breath_bad = true
		funcs_out.append("breath")
	if "breathe" in funcs and pdef.get("internal", false):
		# a lung: cut through by an edge = punctured (winded: breath_bad, exertion x2); both lungs punctured or ruined =
		# drowning in blood, the same air clock as a cut airway (DF: a creature with both lungs gone cannot breathe)
		var lp: Dictionary = f.unit.body.wound_part(part_id)
		if edge and through and not lp.get("punct", false):
			lp["punct"] = true
			if not f.breath_bad:
				f.breath_bad = true
			funcs_out.append("lung")
		if (lp.get("punct", false) or dm >= Formulas.VITAL_DESTROY) and not f.suffocating and _lungs_failed(f):
			f.suffocating = true
			f.drowning = true
			f.air = Formulas.AIR_MAX
			funcs_out.append("drown")
	if "cord" in funcs and dm0 < Formulas.NERVE_DISABLE and dm >= Formulas.NERVE_DISABLE:
		# the spinal cord cut: everything below goes limp (stance; arms too from the upper spine, and the breath)
		funcs_out.append("spine")
		if String(pdef.get("spine", "")) == "upper" and not f.suffocating:
			f.suffocating = true
			f.air = Formulas.AIR_MAX
	if "airway" in funcs and dm >= Formulas.AIRWAY_CUT and not f.suffocating:
		f.suffocating = true
		f.air = Formulas.AIR_MAX
		funcs_out.append("airway")
	if "grip" in funcs and dm >= Formulas.TENDON_DISABLE:
		funcs_out.append("tendon_grip")
	if "stance" in funcs and tissue == "tendon" and dm >= Formulas.TENDON_DISABLE:
		funcs_out.append("tendon_leg")
	if "motor" in funcs and dm >= Formulas.NERVE_DISABLE:
		funcs_out.append("nerve")
	if "sight" in funcs and dm >= Formulas.VITAL_DESTROY:
		L["kind"] = "destroyed"
		var s := "%s destroyed" % pdef.get("name", part_id)
		if not f.unit.body.permanent.has(s):
			f.unit.body.permanent.append(s)
		funcs_out.append("eye")
	return pain

## Recomputes stance (legs) and grasp (hands) from wounds; drops items and falls as needed.
## Reads healing's permanent body.parts[id]["impair"] (0..1) too. Per-part results are cached in f.pstat;
## `only` recomputes just the struck part (the common case) before aggregating.
static func _update_functions(sim, f: Fighter, announce: bool, only: String = "", only2: String = "") -> void:
	var body := f.unit.body
	# perf: the totals below are a fold over the parts with rel = true; when the struck part was and stays rel = false
	# (or its status did not change) they are the stored ones (f.pagg) from the last fold over the same pstat.
	# only2: the inner part the blow reached as well (a spinal cord); both must be unchanged to reuse the totals.
	var reuse := false
	if only == "" or f.pstat.is_empty():
		for p in body.plan()["parts"]:
			f.pstat[p["id"]] = _part_status(sim, f, p)
	else:
		reuse = not f.pagg.is_empty()
		for o in [only, only2]:
			if o == "" or not body.has_part(o):
				continue
			var ns := _part_status(sim, f, _pdef(body, o))
			var old = f.pstat.get(o)
			f.pstat[o] = ns
			if not (old != null and ((not old[PS_REL] and not ns[PS_REL]) or old == ns)):
				reuse = false
	if not reuse:
		_fold_functions(sim, f)
	var g: Array = f.pagg
	_apply_functions(sim, f, announce, g[0], g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8])

## The fold of _update_functions over f.pstat, stored in f.pagg:
## [stance_lost, leg_imp, right_ok, left_ok, eyes, eyes_ok, right_why, left_why, stance_why].
static func _fold_functions(_sim, f: Fighter) -> void:
	var stance_lost := false
	var leg_imp := 0.0
	var right_ok := true
	var left_ok := true
	var eyes := 0
	var eyes_ok := 0
	var right_why := ""
	var left_why := ""
	var stance_why := ""
	var dw := {"r": 0.0, "l": 0.0}    # fingers: DF relative size of each hand's fingers, and of those that still close
	var dok := {"r": 0.0, "l": 0.0}
	# pstat entry: [stance, leg, bad, spine, why, eye, eye_ok, grasp, rel, digit, digit w, digit ok, arms] (_part_status)
	for s: Array in f.pstat.values():
		if not s[PS_REL]:   # perf: a part that changes none of the totals below
			continue
		if s[PS_DIGIT] != "":
			dw[s[PS_DIGIT]] += float(s[PS_DIGIT_W])
			if s[PS_DIGIT_OK]:
				dok[s[PS_DIGIT]] += float(s[PS_DIGIT_W])
			continue
		if s[PS_SPINE]:
			stance_lost = true
			stance_why = "spine"
			if s[PS_ARMS]:   # the upper spinal cord: both arms go limp too
				right_ok = false
				left_ok = false
				right_why = "spine"
				left_why = "spine"
		if s[PS_STANCE]:
			leg_imp = maxf(leg_imp, s[PS_LEG])
			if s[PS_BAD]:
				stance_lost = true
				stance_why = s[PS_WHY] if s[PS_WHY] != "arm" else "leg"
		if s[PS_EYE]:
			eyes += 1
			if s[PS_EYE_OK]:
				eyes_ok += 1
		if s[PS_GRASP] != "" and s[PS_BAD]:
			if s[PS_GRASP] == "r":
				right_ok = false
				right_why = s[PS_WHY]
			else:
				left_ok = false
				left_why = s[PS_WHY]
	# grip (v0.013): the share of a hand's fingers, by DF relative size, that can still close; none = it cannot hold
	f.grip_r = dok["r"] / dw["r"] if dw["r"] > 0.0 else 1.0
	f.grip_l = dok["l"] / dw["l"] if dw["l"] > 0.0 else 1.0
	if dw["r"] > 0.0 and dok["r"] <= 0.0 and right_ok:
		right_ok = false
		right_why = "fingers"
	if dw["l"] > 0.0 and dok["l"] <= 0.0 and left_ok:
		left_ok = false
		left_why = "fingers"
	f.pagg = [stance_lost, leg_imp, right_ok, left_ok, eyes, eyes_ok, right_why, left_why, stance_why]

## The consequences of the function totals (unchanged from the inline version).
static func _apply_functions(sim, f: Fighter, announce: bool, stance_lost: bool, leg_imp: float, right_ok: bool, left_ok: bool,
		eyes: int, eyes_ok: int, right_why: String, left_why: String, stance_why: String) -> void:
	f.leg_impair = leg_imp
	f.tempo_tick = -1000
	f.blind = eyes > 0 and eyes_ok == 0
	if not right_ok and not f.weapon_dropped and f.wielded != null:
		_drop_weapon(sim, f, announce, right_why)
	if not left_ok and not f.shield_dropped and f.unit.equip.get("off_hand", null) != null:
		f.shield_dropped = true
		if announce:
			sim._ev_simple("drop", f.idx, -1, "drop", {"w": f.unit.equip["off_hand"].display_name(), "why": left_why})
	var newly := stance_lost and not f.stance_lost
	f.stance_lost = stance_lost
	if newly and not f.prone:
		if announce:
			_fall(sim, f, "legs_" + stance_why, 0)
		else:
			f.prone = true

static func _part_status(sim, f: Fighter, p: Dictionary) -> Array:
	var body := f.unit.body
	var pid: String = p["id"]
	var lost := f.lost.has(pid)
	# the part's fixed roles (grasp side, stance, eye, finger of which hand, its relsize, spine level) depend only on
	# its plan definition: cached like _ldef_map
	var ck: String = p.get("_ck", pid)
	var roles = sim._proles.get(ck)
	if roles == null:
		var gr := ""
		if pid.begins_with("hand") or pid.begins_with("arm"):
			gr = "r" if pid.ends_with("_r") else ("l" if pid.ends_with("_l") else "")
		roles = [gr, "stance" in p.get("functions", []), pid.begins_with("eye"), String(p.get("digit", "")),
			float(p.get("relsize", 0)), String(p.get("spine", ""))]
		sim._proles[ck] = roles
	var impair := 0.0
	var bone_d := 0.0
	var musc_d := 0.0
	var tendon_bad := false
	var nerve_bad := false
	var sight_bad := false
	var spine := false
	var part = body.parts.get(pid)   # null = unhurt (sparse body): nothing below to read
	if part != null:
		impair = float(part.get("impair", 0.0))
		nerve_bad = bool(part.get("nerve_m", false))   # DF HAS_NERVES: motor nerve severed -> the part goes limp
		var ldm := _ldef_map(sim, pid, p)
		for L in part["layers"]:
			var dm := float(L["dmg"])
			if dm <= 0.0:
				continue
			var t: String = L["tissue"]
			var lf: Array = ldm.get(L.get("name", t), {}).get("functions", [])
			if t == "bone":
				bone_d = maxf(bone_d, dm)
			elif t == "muscle":
				musc_d = maxf(musc_d, dm)
			elif t == "tendon" and dm >= Formulas.TENDON_DISABLE:
				tendon_bad = true
			elif t == "nerve" and dm >= Formulas.NERVE_DISABLE:
				if "cord" in lf:
					spine = true   # the spinal cord cut: everything below it
				else:
					nerve_bad = true
			if "stance" in lf and t == "bone" and dm >= Formulas.STANCE_BONE_DISABLE:
				spine = true
			if "sight" in lf and dm >= Formulas.VITAL_DESTROY:
				sight_bad = true
		musc_d = maxf(musc_d, impair)
	var bad := lost or bone_d >= Formulas.STANCE_BONE_DISABLE or musc_d >= Formulas.STANCE_MUSCLE_DISABLE or tendon_bad or nerve_bad or impair >= 0.8
	var grasp: String = roles[0]
	var stance: bool = roles[1]
	var leg := 1.0 if lost else musc_d
	var eye: bool = roles[2]
	var digit: String = roles[3]
	# rel: the part counts in _update_functions' totals (an intact stance part adds max(.., 0) = nothing)
	var rel := spine or eye or digit != "" or (stance and (leg > 0.0 or bad)) or (grasp != "" and bad)
	return [stance, leg, bad, spine, "lost" if lost else ("tendon" if tendon_bad else ("nerve" if nerve_bad else "arm")),
		eye, not lost and not sight_bad and impair < 0.8, grasp, rel, digit, roles[4], not bad, spine and roles[5] == "upper"]

## Part definition by id.
static func _pdef(body: BodyState, pid: String) -> Dictionary:
	return body.part_def(pid)   # BodyState caches {id -> def} per plan

## Marks a severed part and everything attached below it as lost (cache of BodyState.is_lost).
static func _mark_lost(f: Fighter, pid: String) -> void:
	f.parts_cache = []
	f.lost[pid] = true
	var changed := true
	while changed:
		changed = false
		for p in f.unit.body.plan()["parts"]:
			var id: String = p["id"]
			if not f.lost.has(id) and f.lost.has(String(p.get("parent", ""))):
				f.lost[id] = true
				changed = true

## The struck part's inner parts (cached per plan part): [ids, relsize weights, names, connector id, under-pressure id].
static func _inner_of(sim, body: BodyState, pid: String, pdef: Dictionary) -> Array:
	var ck: String = pdef.get("_ck", pid)
	var e = sim._inner_cache.get(ck)
	if e == null:
		var ids := []
		var ws := []
		var nm := []
		var conn := ""
		var press := ""
		for p in body.plan()["parts"]:
			if p.get("internal", false) and String(p.get("parent", "")) == pid:
				if p.get("connector", false):
					conn = p["id"]
				if p.get("under_pressure", false):
					press = p["id"]
				ids.append(p["id"])   # DF: every inner part is a pick by its relsize (the skull alone, or the brain through it)
				ws.append(float(p.get("relsize", 100)))
				nm.append(p.get("name", p["id"]))
		e = [ids, ws, nm, conn, press]
		sim._inner_cache[ck] = e
	return e

## Every lung of the plan is punctured or ruined (v0.013 drowning in blood).
static func _lungs_failed(f: Fighter) -> bool:
	var body := f.unit.body
	var n := 0
	for p in body.plan()["parts"]:
		if not p.get("internal", false) or p["layers"].is_empty() or not ("breathe" in p["layers"][0].get("functions", [])):
			continue
		n += 1
		var lp = body.parts.get(p["id"])
		if lp == null:
			return false
		if not lp.get("punct", false) and float(lp["layers"][0]["dmg"]) < Formulas.VITAL_DESTROY:
			return false
	return n > 0

static func _drop_weapon(sim, f: Fighter, announce: bool, why: String) -> void:
	if f.wielded == null or f.weapon_dropped:
		return
	var it := f.wielded
	if not f.lodged.is_empty():
		_let_go(sim, f, false)
	else:
		sim.ground.append({"cell": f.cell, "item": it})
	f.weapon_dropped = true
	f.reach_tiles = 1
	if announce:
		sim._ev_simple("drop", f.idx, -1, "drop", {"w": it.display_name(), "why": why})

static func _fall(sim, f: Fighter, why: String, knock_ticks: int) -> void:
	if sim.occ[sim._ci(f.cell)] == f.idx:
		sim.occ[sim._ci(f.cell)] = -1
	f.prone = true
	f.knockdown_left = maxi(f.knockdown_left, knock_ticks)
	if f.state in ["preparing", "moving", "ready", "recovering"]:
		f.pending_action = {}
		sim._set_action(f, "prone", maxi(1, knock_ticks))
	_rip_free(sim, f)
	sim._ev_simple("fall", f.idx, -1, "fall_" + why, {"ticks": knock_ticks})

# =====================================================================================================
# Stuck weapons and the unarmed fallback (survey lodge rules + unarmed addendum)
# =====================================================================================================
## Wielder AI with a stuck weapon: victim helpless -> twist; pinned at reach and the victim can't hit back -> twist;
## threatened (another enemy within 2 tiles or the victim reaches me) -> pull out if <= 6 ticks else let go; else pull.
static func _decide_lodged(sim, f: Fighter) -> void:
	var v: Fighter = sim.fighters[int(f.lodged["victim"])]
	var pull := Formulas.pull_ticks(int(f.lodged["layers"]), float(f.unit.attr("STR")))
	if not v.alive() or v.state == "fled":
		sim._begin_special(f, "pull", pull, {})
		return
	var victim_reaches: bool = v.active() and sim._in_reach(v, f)
	var threatened := victim_reaches
	for o in sim.fighters:
		if o.side != f.side and o != v and o.present() and sim._dist(o.cell, f.cell) <= 2:
			threatened = true
			break
	if v.helpless() or not threatened:
		if v.helpless() or not victim_reaches:
			sim._begin_special(f, "twist", 3, {})
		else:
			sim._begin_special(f, "pull", pull, {})
	elif pull <= Formulas.LET_GO_LIMIT:
		sim._begin_special(f, "pull", pull, {})
	else:
		_let_go(sim, f, true)
		sim._set_action(f, sim._idle_state(f), 1)

static func _lodge_layer(v: Fighter, part: String, lname: String) -> Dictionary:
	if not v.unit.body.has_part(part):
		return {}
	for L in v.unit.body.wound_part(part)["layers"]:   # the stored part (a lodged blade cut it, so it is stored already)
		if L.get("name", L["tissue"]) == lname:
			return L
	return {}

static func _twist(sim, f: Fighter) -> void:
	if f.lodged.is_empty():
		return
	var v: Fighter = sim.fighters[int(f.lodged["victim"])]
	var part: String = f.lodged["part"]
	var lname := String(f.lodged["layer"])
	var L := _lodge_layer(v, part, lname)
	if L.is_empty() or not v.alive():
		return
	var p := float(f.lodged["p0"]) * Formulas.TWIST_MOMENTUM
	var tissue: String = L["tissue"]
	var dmg := clampf(p / 40.0, 0.05, 0.5) * Formulas.tou_mult(v.unit.attr("TOU"))
	var pdef := _pdef(v.unit.body, part)
	var ld := _ldef(sim, part, pdef, lname)
	var res := _wound_layer(sim, v, part, pdef, L, ld, dmg, Formulas.edge_kind(tissue, 20.0, float(L["dmg"]) + dmg), true, false)
	var pain := float(res["pain"]) * Formulas.TWIST_PAIN_MULT * Formulas.pain_mult(v.unit.attr("WIL"), v.unit.attr("END"), v.unit.skill("discipline")) / v.pain_tol
	v.unit.body.pain += pain
	v.pain_floor_src += pain
	L["bleed"] = float(L.get("bleed", 0.0)) * Formulas.TWIST_BLEED_MULT
	sim._recount_bleed(v)
	v.last_attacker = f.idx
	v.last_attacked_tick = sim.tick
	sim._ev_simple("hit", f.idx, v.idx, "twist", {"w": f.lodged["item"].display_name(), "part": pdef.get("name", part),
		"layer": lname, "dmg": dmg, "pain": pain, "p": p})
	if res["death"] != "":
		sim._kill(v, f.idx, res["death"])
	elif v.unit.body.pain > Formulas.PAIN_KO and v.state != "unconscious":
		sim._knock_out(v, "pain")

## Exit tear on the deepest layer reached when a stuck weapon comes out.
static func _exit_tear(sim, v: Fighter, lod: Dictionary, mult: float) -> void:
	var part: String = lod["part"]
	var lname := String(lod["layer"])
	var L := _lodge_layer(v, part, lname)
	if L.is_empty() or not v.alive():
		return
	var dmg := clampf(float(lod["p0"]) * Formulas.EXIT_TEAR * mult / 40.0, 0.02, 0.3)
	var pdef := _pdef(v.unit.body, part)
	_wound_layer(sim, v, part, pdef, L, _ldef(sim, part, pdef, lname), dmg, "torn", true, false)
	var pain := float(Formulas.PAIN_RECEPTORS.get(L["tissue"], 5.0)) * 2.0 * Formulas.pain_mult(v.unit.attr("WIL"), v.unit.attr("END"), v.unit.skill("discipline")) / v.pain_tol
	v.unit.body.pain += pain
	v.pain_floor_src += pain

static func _unstick(sim, f: Fighter) -> Dictionary:
	var lod := f.lodged
	f.lodged = {}
	if lod.is_empty():
		return lod
	var v: Fighter = sim.fighters[int(lod["victim"])]
	for i in range(v.stuck_in_me.size() - 1, -1, -1):
		if is_same(v.stuck_in_me[i]["item"], lod["item"]):
			v.stuck_in_me.remove_at(i)
	return lod

static func _pull_out(sim, f: Fighter) -> void:
	var lod := _unstick(sim, f)
	if lod.is_empty():
		return
	var v: Fighter = sim.fighters[int(lod["victim"])]
	_exit_tear(sim, v, lod, 1.0)
	sim._ev_simple("freed", f.idx, v.idx, "pull_out", {"w": lod["item"].display_name(), "part": _pdef(v.unit.body, lod["part"]).get("name", lod["part"])})

## Let go: the weapon stays in the victim (bleed x0.5, pain on every action); the wielder fights on unarmed.
static func _let_go(sim, f: Fighter, announce: bool) -> void:
	var lod := f.lodged
	if lod.is_empty():
		return
	f.lodged = {}
	var v: Fighter = sim.fighters[int(lod["victim"])]
	for s in v.stuck_in_me:
		if is_same(s["item"], lod["item"]):
			s["wielder"] = -1
	f.weapon_dropped = true
	f.reach_tiles = 1
	if announce:
		sim._ev_simple("drop", f.idx, v.idx, "let_go", {"w": lod["item"].display_name()})

static func _victim_pull(sim, v: Fighter, wielder: int) -> void:
	var w: Fighter = sim.fighters[wielder] if wielder >= 0 else null
	if w == null or w.lodged.is_empty() or int(w.lodged["victim"]) != v.idx:
		return
	var lod := _unstick(sim, w)
	w.weapon_dropped = true
	w.reach_tiles = 1
	sim.ground.append({"cell": v.cell, "item": lod["item"]})
	_exit_tear(sim, v, lod, 1.0)
	sim._ev_simple("freed", v.idx, w.idx, "victim_pull", {"w": lod["item"].display_name()})

## Stagger/knockdown on either side rips a stuck weapon free (tear).
static func _rip_free(sim, f: Fighter) -> void:
	if not f.lodged.is_empty():
		var lod := _unstick(sim, f)
		_exit_tear(sim, sim.fighters[int(lod["victim"])], lod, 1.0)
		sim._ev_simple("freed", f.idx, int(lod["victim"]), "rip_free", {"w": lod["item"].display_name()})
	for s in f.stuck_in_me.duplicate():
		if int(s["wielder"]) >= 0:
			var w: Fighter = sim.fighters[int(s["wielder"])]
			var lod2 := _unstick(sim, w)
			if not lod2.is_empty():
				_exit_tear(sim, f, lod2, 1.0)
				sim._ev_simple("freed", w.idx, f.idx, "rip_free", {"w": lod2["item"].display_name()})

## Unarmed choices before a plain punch: retrieve a weapon within 2 tiles; grab an armed enemy and disarm;
## grab and take down. Returns true if an action was started.
static func _decide_unarmed_extra(sim, f: Fighter) -> bool:
	if f.prone or not (sim._part_ok(f, "hand_r") or sim._part_ok(f, "hand_l")):
		return false
	var best := -1
	var best_d := 99
	for i in sim.ground.size():
		var dd: int = sim._dist(f.cell, sim.ground[i]["cell"])
		if dd <= Formulas.RETRIEVE_RADIUS and dd < best_d:
			best = i
			best_d = dd
	if best >= 0:
		var g: Dictionary = sim.ground[best]
		if best_d <= 1:
			sim._begin_special(f, "retrieve", Formulas.RETRIEVE_TICKS, {"g": g})
			return true
		var before := f.cell
		sim._move_toward(f, g["cell"])
		return f.cell != before
	for o in sim.fighters:
		if o.stuck_in_me.is_empty() or not (o.state == "dead" or o.helpless()) or sim._dist(f.cell, o.cell) > Formulas.RETRIEVE_RADIUS:
			continue
		for s in o.stuck_in_me:
			if int(s["wielder"]) < 0:
				if sim._dist(f.cell, o.cell) <= 1:
					sim._begin_special(f, "retrieve", Formulas.RETRIEVE_TICKS + int(s["layers"]), {"body": o.idx, "s": s})
					return true
				var before2 := f.cell
				sim._move_toward(f, o.cell)
				return f.cell != before2
	var t: Fighter = sim.fighters[f.target] if f.target >= 0 else null
	if t == null or not t.present() or sim._dist(f.cell, t.cell) > 1 or not sim._diag_ok(f.cell, t.cell):
		return false
	var gc := _grab_chance(sim, f, t)
	if f.grabbing == t.idx:
		if sim._has_weapon(t) and gc >= 0.5:
			sim._begin_special(f, "disarm", 4, {"t": t.idx})
			return true
		if not t.prone and gc >= 0.6:
			sim._begin_special(f, "takedown", 4, {"t": t.idx})
			return true
		return false
	if t.helpless():
		return false
	if (sim._has_weapon(t) and gc >= 0.5) or gc >= 0.6:
		sim._begin_special(f, "grab", 3, {"t": t.idx})
		return true
	return false

static func _contest_mass(sim, f: Fighter) -> float:
	return (f.unit.mass() + f.gear_mass) * (1.0 - maxf(0.0, 1.0 - sim._blood_frac(f)))

static func _grab_chance(sim, f: Fighter, t: Fighter) -> float:
	return Formulas.grab_chance(sim._eff(f, "wrestler", "grab"), sim._eff(t, "wrestler", "grab"), _contest_mass(sim, f), _contest_mass(sim, t))

static func _grab(sim, f: Fighter, ti: int) -> void:
	var t: Fighter = sim.fighters[ti] if ti >= 0 else null
	if t == null or not t.present() or sim._dist(f.cell, t.cell) > 1:
		return
	var rr := Formulas.roll_grab(sim.rng, _grab_chance(sim, f, t))
	sim._learn(f, "wrestler", Learning.XP_SWING)
	if rr["ok"]:
		if f.grabbing >= 0:
			_release_grab(sim, f)
		f.grabbing = t.idx
		t.grabbed_by = f.idx
		t.last_attacked_tick = sim.tick
	sim._ev_simple("hit" if rr["ok"] else "miss", f.idx, t.idx, "grab_ok" if rr["ok"] else "grab_fail", {"roll": rr})

static func _takedown(sim, f: Fighter, ti: int) -> void:
	var t: Fighter = sim.fighters[ti] if ti >= 0 else null
	if t == null or not t.present() or f.grabbing != ti:
		return
	var rr := Formulas.roll_grab(sim.rng, _grab_chance(sim, f, t))
	sim._learn(f, "wrestler", Learning.XP_SWING)
	sim._ev_simple("hit" if rr["ok"] else "miss", f.idx, t.idx, "takedown_ok" if rr["ok"] else "takedown_fail", {"roll": rr})
	if rr["ok"]:
		_release_grab(sim, f)
		_fall(sim, t, "thrown", Formulas.KNOCKDOWN_TICKS)

static func _disarm(sim, f: Fighter, ti: int) -> void:
	var t: Fighter = sim.fighters[ti] if ti >= 0 else null
	if t == null or not t.present() or f.grabbing != ti or not sim._has_weapon(t):
		return
	var rr := Formulas.roll_grab(sim.rng, _grab_chance(sim, f, t))
	sim._learn(f, "wrestler", Learning.XP_SWING)
	if rr["ok"]:
		var it := t.wielded
		if not t.lodged.is_empty():
			_unstick(sim, t)
		t.weapon_dropped = true
		t.reach_tiles = 1
		f.wielded = it
		f.weapon_dropped = false
		f.reach_tiles = sim._reach_of(f)
		_release_grab(sim, f)
		sim._ev_simple("drop", f.idx, t.idx, "disarm_ok", {"w": it.display_name()})
	else:
		sim._ev_simple("miss", f.idx, t.idx, "disarm_fail", {"roll": rr})

static func _release_grab(sim, f: Fighter) -> void:
	if f.grabbing >= 0:
		sim.fighters[f.grabbing].grabbed_by = -1
	f.grabbing = -1

static func _retrieve(sim, f: Fighter, pa: Dictionary) -> void:
	var it: Item = null
	if pa.has("g"):
		var g: Dictionary = pa["g"]
		var i: int = sim.ground.find(g)
		if i < 0 or sim._dist(f.cell, g["cell"]) > 1:
			return
		sim.ground.remove_at(i)
		it = g["item"]
	elif pa.has("body"):
		var o: Fighter = sim.fighters[int(pa["body"])]
		var s: Dictionary = pa["s"]
		var i2 := o.stuck_in_me.find(s)
		if i2 < 0:
			return
		o.stuck_in_me.remove_at(i2)
		it = s["item"]
	if it == null:
		return
	f.wielded = it
	f.weapon_dropped = false
	f.reach_tiles = sim._reach_of(f)
	sim._ev_simple("freed", f.idx, -1, "retrieve", {"w": it.display_name()})
