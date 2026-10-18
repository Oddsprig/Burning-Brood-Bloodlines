class_name BattleTactics
extends RefCounted
## v0.041: tactical battle systems for round-based battles (campaign/battle_rounds.gd)
## and off-screen army clashes (campaign/clash_rounds.gd).
## Each side picks a tactic per round; counter matchups, terrain, and the best tactician
## skill among that round's house officers/leaders yield small attack/defence/morale multipliers.
## Round 1 defaults side 0 (the player) to "hold" (shield wall); later rounds carry over st["last_tactics"][0].

const ORDER: Array[String] = ["charge", "hold", "flank", "skirmish", "feint"]

const TACTICS: Dictionary = {
	"charge": {
		"name": "Charge",
		"label": "charge",
		"desc": "Drive straight into the enemy line with full shock and momentum."
	},
	"hold": {
		"name": "Hold (Shield Wall)",
		"label": "shield wall",
		"desc": "Lock shields and hold ground, breaking enemy charges upon the line."
	},
	"flank": {
		"name": "Flank",
		"label": "flanking sweep",
		"desc": "Swing around the enemy's wings to strike their exposed sides."
	},
	"skirmish": {
		"name": "Skirmish (Missiles First)",
		"label": "skirmish screen",
		"desc": "Loose missiles first and harry the enemy before closing."
	},
	"feint": {
		"name": "Feint",
		"label": "feigned retreat",
		"desc": "Stage a false withdrawal to draw an eager charge into a trap."
	},
}

## Counter table: row tactic vs column tactic -> modifier in [-0.15, +0.15].
## Charge beats skirmish; hold beats charge; flank beats hold; skirmish beats flank;
## feint beats charge but loses to hold.
const COUNTER: Dictionary = {
	"charge": {"charge": 0.0, "hold": -0.15, "flank": 0.08, "skirmish": 0.15, "feint": -0.12},
	"hold": {"charge": 0.15, "hold": 0.0, "flank": -0.15, "skirmish": -0.08, "feint": 0.12},
	"flank": {"charge": -0.08, "hold": 0.15, "flank": 0.0, "skirmish": -0.15, "feint": 0.10},
	"skirmish": {"charge": -0.15, "hold": 0.08, "flank": 0.15, "skirmish": 0.0, "feint": -0.10},
	"feint": {"charge": 0.12, "hold": -0.12, "flank": -0.10, "skirmish": 0.10, "feint": 0.0},
}

## Base terrain modifiers by terrain and tactic; hills/mountains add HILLS_DEFENDER_HOLD for the defending side.
const TERRAIN_MODS: Dictionary = {
	"grassland": {"charge": 0.06, "hold": -0.02, "flank": 0.06, "skirmish": 0.0, "feint": 0.02},
	"plains": {"charge": 0.06, "hold": -0.02, "flank": 0.06, "skirmish": 0.0, "feint": 0.02},
	"badlands": {"charge": 0.04, "hold": 0.0, "flank": 0.05, "skirmish": 0.02, "feint": 0.02},
	"road": {"charge": 0.05, "hold": 0.0, "flank": 0.04, "skirmish": 0.0, "feint": 0.02},
	"forest": {"charge": -0.06, "hold": 0.06, "flank": -0.04, "skirmish": 0.06, "feint": 0.03},
	"silverwood": {"charge": -0.06, "hold": 0.06, "flank": -0.04, "skirmish": 0.06, "feint": 0.03},
	"marsh": {"charge": -0.08, "hold": 0.06, "flank": -0.06, "skirmish": 0.06, "feint": 0.02},
	"mud": {"charge": -0.07, "hold": 0.05, "flank": -0.05, "skirmish": 0.05, "feint": 0.01},
	"hills": {"charge": -0.05, "hold": 0.03, "flank": -0.02, "skirmish": 0.03, "feint": 0.02},
	"mountains": {"charge": -0.06, "hold": 0.04, "flank": -0.03, "skirmish": 0.03, "feint": 0.02},
}
const HILLS_DEFENDER_HOLD: float = 0.06

## Intrinsic tactic profile: small shifts to [attack, defence, morale] before counter/terrain edges.
const PROFILE: Dictionary = {
	"charge": {"attack": 0.06, "defence": -0.03, "morale": 0.04},
	"hold": {"attack": -0.03, "defence": 0.07, "morale": 0.03},
	"flank": {"attack": 0.05, "defence": -0.01, "morale": 0.02},
	"skirmish": {"attack": 0.03, "defence": 0.03, "morale": 0.01},
	"feint": {"attack": 0.04, "defence": 0.02, "morale": 0.02},
}

const MIN_MULT: float = 0.75
const MAX_MULT: float = 1.35
const MAX_TACTICIAN_BONUS: float = 0.50

static var _pending_picks: Array[String] = ["", ""]
static var _pending_epoch: int = -1
static var _bound_game: Object = null


static func valid(tactic: String) -> String:
	return tactic if TACTICS.has(tactic) else "hold"


static func description(tactic: String) -> String:
	var row: Dictionary = TACTICS.get(tactic, {})
	return str(row.get("desc", ""))


static func counter_mod(my_tactic: String, enemy_tactic: String) -> float:
	var row: Dictionary = COUNTER.get(my_tactic, {})
	return clampf(float(row.get(enemy_tactic, 0.0)), -0.15, 0.15)


static func terrain_mod(terrain: String, tactic: String, side: int = 0, def_side: int = 1) -> float:
	var key: String = terrain if TERRAIN_MODS.has(terrain) else "plains"
	var row: Dictionary = TERRAIN_MODS.get(key, TERRAIN_MODS["plains"])
	var val: float = float(row.get(tactic, 0.0))
	if key in ["hills", "mountains"] and side == def_side and tactic == "hold":
		val += HILLS_DEFENDER_HOLD
	return clampf(val, -0.15, 0.15)


## Returns which battle side (0 or 1) is the defender from pending_battle / round_state context.
## Defaults to side 1 when no explicit attacker/defender context is present (standard player-initiated engagement).
static func defender_side(game, round_state: Dictionary = {}) -> int:
	var pb: Dictionary = _pending_battle_of(game)
	for src in [round_state, pb]:
		if not (src is Dictionary) or (src as Dictionary).is_empty():
			continue
		var d: Dictionary = src
		if d.has("defender_side"):
			return clampi(int(d["defender_side"]), 0, 1)
		if d.has("attacker_side"):
			return 1 - clampi(int(d["attacker_side"]), 0, 1)
		if d.has("they_attacked"):
			return 0 if bool(d["they_attacked"]) else 1
		if d.has("enemy_attacked"):
			return 0 if bool(d["enemy_attacked"]) else 1
		if d.has("player_defending"):
			return 0 if bool(d["player_defending"]) else 1
		if d.has("player_attacked"):
			return 1 if bool(d["player_attacked"]) else 0
		if d.has("defender") and (d["defender"] is int or d["defender"] is String):
			var dv: String = str(d["defender"]).to_lower()
			if dv in ["0", "player", "side0"]:
				return 0
			if dv in ["1", "enemy", "side1"]:
				return 1
		if d.has("attacker") and (d["attacker"] is int or d["attacker"] is String):
			var av: String = str(d["attacker"]).to_lower()
			if av in ["0", "player", "side0"]:
				return 1
			if av in ["1", "enemy", "side1"]:
				return 0
	if not pb.is_empty():
		if pb.has("assault") or pb.has("lair_id") or pb.has("hold1"):
			return 1
		if pb.has("hold0") or pb.has("militia_town"):
			return 0
		if pb.has("contract") and pb["contract"] is Dictionary:
			var ck: String = str((pb["contract"] as Dictionary).get("kind", ""))
			if ck == "defend":
				return 0
		var wid: int = int(pb.get("warband_id", 0))
		if wid > 0 and game != null and not (game is Dictionary) and "world" in game and game.world is Dictionary:
			var wbs: Variant = (game.world as Dictionary).get("warbands", [])
			if wbs is Array:
				for item in wbs as Array:
					if item is Dictionary and int((item as Dictionary).get("id", 0)) == wid:
						var wb: Dictionary = item
						if bool(wb.get("escort_fight", false)):
							return 0
						var wkind: String = str(wb.get("kind", ""))
						if wkind == "assault":
							return 0
						if wkind == "caravan":
							return 1
						if str(wb.get("mode", "")) == "chase":
							return 0
						if wb.has("war") and wb["war"] is Dictionary:
							var wm: String = str((wb["war"] as Dictionary).get("m", ""))
							if wm in ["intercept", "join"]:
								return 0
	return 1


## Clears any unconsumed tactic picks in static state and on the given game/pending_battle.
static func clear_pending(game = null) -> void:
	_pending_picks = ["", ""]
	if game != null and not (game is Dictionary) and "_save_epoch" in game:
		_pending_epoch = int(game._save_epoch)
	var pb: Dictionary = _pending_battle_of(game)
	if not pb.is_empty():
		if pb.has("next_tactic"):
			pb["next_tactic"] = ["", ""]
		if pb.has("rounds") and pb["rounds"] is Dictionary:
			var st: Dictionary = pb["rounds"]
			if st.has("next_tactic"):
				st["next_tactic"] = ["", ""]


static func after_load(game = null) -> void:
	clear_pending(game)


static func _bind_game(game) -> void:
	if game == null or game is Dictionary or not (game is Object):
		return
	if _bound_game == game:
		return
	_bound_game = game
	if game.has_signal("changed"):
		var cb := Callable(BattleTactics, "_on_game_changed")
		if not game.is_connected("changed", cb):
			game.connect("changed", cb)
	if game.has_signal("screen_changed"):
		var scb := Callable(BattleTactics, "_on_screen_changed")
		if not game.is_connected("screen_changed", scb):
			game.connect("screen_changed", scb)


static func _on_game_changed() -> void:
	if _bound_game == null or not is_instance_valid(_bound_game):
		return
	var ep: int = int(_bound_game._save_epoch) if "_save_epoch" in _bound_game else -1
	if ep != _pending_epoch:
		_pending_picks = ["", ""]
		_pending_epoch = ep
		return
	if "pending_battle" in _bound_game and (_bound_game.pending_battle is Dictionary) and (_bound_game.pending_battle as Dictionary).is_empty():
		_pending_picks = ["", ""]


static func _on_screen_changed(screen_name: String) -> void:
	if screen_name != "battle":
		return
	if _bound_game == null or not is_instance_valid(_bound_game):
		return
	if not ("pending_battle" in _bound_game) or not (_bound_game.pending_battle is Dictionary):
		return
	var pb: Dictionary = _bound_game.pending_battle
	if not pb.has("rounds") or not (pb["rounds"] is Dictionary):
		return
	var st: Dictionary = pb["rounds"]
	var mods: Dictionary = st.get("tactic_mods", {}) if st.get("tactic_mods", null) is Dictionary else {}
	if mods.is_empty():
		mods = modifiers(_bound_game, st)
		st["tactic_mods"] = mods
	if "main" in _bound_game and _bound_game.main != null and "current" in _bound_game.main and _bound_game.main.current != null:
		var cur: Variant = _bound_game.main.current
		if cur != null and "sim" in cur and cur.sim != null:
			apply_sim(cur.sim, mods)


## Commander tactician bonus in [0.0, 0.50] (0..+50% scaling of the tactic edge).
static func tactician_bonus(skill_level: int) -> float:
	return clampf(float(maxi(0, skill_level)) * 0.05, 0.0, MAX_TACTICIAN_BONUS)


static func tactician_scale(skill_level: int) -> float:
	return 1.0 + tactician_bonus(skill_level)


## Best tactician skill among the side's house officers/leaders in that round.
static func commander_tactician(game, units: Array, side: int = 0, round_state: Dictionary = {}) -> int:
	var cmd_uid: int = -1
	var commanders: Variant = round_state.get("commander", [])
	if commanders is Array and side >= 0 and side < (commanders as Array).size():
		cmd_uid = int((commanders as Array)[side])
	var best: int = 0
	var found_leader: bool = false
	var fallback_best: int = 0
	for item in units:
		if not (item is Unit):
			continue
		var u: Unit = item
		if u.dead:
			continue
		var sk: int = u.skill("tactician")
		if sk > fallback_best:
			fallback_best = sk
		var is_leader: bool = u.is_officer() or u.role in ["captain", "officer", "leader"] or u.uid == cmd_uid or u.has_meta("house_member")
		if not is_leader and game != null and not (game is Dictionary):
			if Army.house_born(u) or BattleRounds.is_household(game, u):
				is_leader = true
		if is_leader:
			found_leader = true
			if sk > best:
				best = sk
	if not found_leader:
		return fallback_best
	return best


## Stores the player's (or a side's) tactic pick for the next round in the rounds state.
## If a round is currently set up and has not yet resolved, also updates that round's active tactic.
static func choose(game, side: int, tactic: String) -> String:
	_bind_game(game)
	if game != null and not (game is Dictionary) and "_save_epoch" in game:
		var ep: int = int(game._save_epoch)
		if _pending_epoch != ep:
			_pending_picks = ["", ""]
			_pending_epoch = ep
	var s: int = clampi(side, 0, 1)
	var pick: String = valid(tactic)
	_pending_picks[s] = pick
	if game == null:
		return pick
	var pb: Dictionary = _pending_battle_of(game)
	if not pb.has("next_tactic") or not (pb["next_tactic"] is Array) or (pb["next_tactic"] as Array).size() < 2:
		pb["next_tactic"] = ["", ""]
	(pb["next_tactic"] as Array)[s] = pick
	if pb.has("rounds") and pb["rounds"] is Dictionary:
		var st: Dictionary = pb["rounds"]
		_ensure_state(st)
		(st["next_tactic"] as Array)[s] = pick
		var cur_round: int = int(st.get("round", 0))
		var log_len: int = (st.get("log", []) as Array).size() if st.get("log", []) is Array else 0
		if cur_round > log_len:
			(st["tactics"] as Array)[s] = pick
			setup_round(game, st)
	return pick


## Deterministic (seeded) AI tactic pick weighted by terrain and the enemy's last tactic.
static func ai_pick(game, side: int, round_index: int) -> String:
	var s: int = clampi(side, 0, 1)
	var r_idx: int = maxi(1, round_index)
	var pb: Dictionary = _pending_battle_of(game)
	var st: Dictionary = _rounds_of(game, pb)
	var terrain: String = str(st.get("terrain", pb.get("terrain", "plains")))
	if terrain == "":
		terrain = "plains"
	var def_side: int = defender_side(game, st)
	var bseed: int = int(st.get("seed", pb.get("seed", 1)))
	if bseed == 1 and game != null and not (game is Dictionary) and "seed_value" in game and int(game.seed_value) != 0:
		bseed = int(game.seed_value)
	var enemy_last: String = _enemy_last_tactic(st, s, r_idx)
	var weights: Array[float] = []
	var total: float = 0.0
	for t in ORDER:
		var w: float = 1.0 + terrain_mod(terrain, t, s, def_side) * 6.0
		if enemy_last != "" and TACTICS.has(enemy_last):
			w += counter_mod(t, enemy_last) * 4.5
		w = maxf(0.10, w)
		weights.append(w)
		total += w
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash([bseed, s, r_idx, terrain, enemy_last, "battle_tactics_v041"])) + 1
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for i in ORDER.size():
		acc += weights[i]
		if roll <= acc:
			return ORDER[i]
	return ORDER[-1]


## Returns {side0: {attack, defence, morale}, side1: {attack, defence, morale}} as small multipliers.
static func modifiers(game, round_state: Dictionary) -> Dictionary:
	var pb: Dictionary = _pending_battle_of(game)
	var st: Dictionary = round_state if not round_state.is_empty() else _rounds_of(game, pb)
	var r_idx: int = maxi(1, int(st.get("round", 1)))
	var terrain: String = str(st.get("terrain", pb.get("terrain", "plains")))
	if terrain == "":
		terrain = "plains"
	var def_side: int = defender_side(game, st)
	var picks: Array[String] = _resolve_pair(game, st, r_idx)
	var t0: String = picks[0]
	var t1: String = picks[1]
	var sk0: int = _side_tactician(game, st, pb, 0)
	var sk1: int = _side_tactician(game, st, pb, 1)
	return {
		"side0": _side_mods(t0, t1, terrain, 0, sk0, def_side),
		"side1": _side_mods(t1, t0, terrain, 1, sk1, def_side),
	}


static func _side_mods(my_tactic: String, enemy_tactic: String, terrain: String, side: int, tactician_skill: int, def_side: int = 1) -> Dictionary:
	var t: String = valid(my_tactic)
	var foe: String = valid(enemy_tactic)
	var prof: Dictionary = PROFILE.get(t, PROFILE["hold"])
	var c_edge: float = counter_mod(t, foe)
	var t_edge: float = terrain_mod(terrain, t, side, def_side)
	var raw_edge: float = c_edge + t_edge
	var scale: float = tactician_scale(tactician_skill)
	var skill_Bonus: float = tactician_bonus(tactician_skill) * 0.12
	var eff_edge: float = (raw_edge * scale if raw_edge >= 0.0 else raw_edge / scale) + skill_Bonus
	var prof_scale: float = 1.0 + 0.5 * (scale - 1.0)
	var att_bias: float = float(prof["attack"]) * (prof_scale if float(prof["attack"]) >= 0.0 else 1.0)
	var def_bias: float = float(prof["defence"]) * (prof_scale if float(prof["defence"]) >= 0.0 else 1.0)
	var mor_bias: float = float(prof["morale"]) * (prof_scale if float(prof["morale"]) >= 0.0 else 1.0)
	return {
		"attack": clampf(1.0 + att_bias + eff_edge, MIN_MULT, MAX_MULT),
		"defence": clampf(1.0 + def_bias + eff_edge, MIN_MULT, MAX_MULT),
		"morale": clampf(1.0 + mor_bias + eff_edge * 0.85, MIN_MULT, MAX_MULT),
	}


## Readable outcome note for the round log entry (e.g. "Your shield wall broke their charge").
static func outcome_note(t0: String, t1: String, winner: int = -1, player_side0: bool = true) -> String:
	var a: String = valid(t0)
	var b: String = valid(t1)
	var my_poss: String = "Your" if player_side0 else "Side A's"
	var foe_poss: String = "their" if player_side0 else "Side B's"
	var foe_cap: String = "Their" if player_side0 else "Side B's"
	var my_low: String = "your" if player_side0 else "Side A's"
	var l0: String = str(TACTICS[a]["label"])
	var l1: String = str(TACTICS[b]["label"])
	if a == "hold" and b == "charge":
		return "%s shield wall broke %s charge" % [my_poss, foe_poss]
	if a == "charge" and b == "hold":
		return "%s shield wall broke %s charge" % [foe_cap, my_low]
	var edge: float = counter_mod(a, b)
	if edge > 0.0:
		match a:
			"charge":
				return "%s charge overran %s %s" % [my_poss, foe_poss, l1]
			"hold":
				return "%s shield wall stood firm against %s %s" % [my_poss, foe_poss, l1]
			"flank":
				return "%s flanking sweep rolled up %s %s" % [my_poss, foe_poss, l1]
			"skirmish":
				return "%s skirmishers harried %s %s" % [my_poss, foe_poss, l1]
			"feint":
				return "%s feigned retreat drew %s %s into a trap" % [my_poss, foe_poss, l1]
	elif edge < 0.0:
		match b:
			"charge":
				return "%s charge overran %s %s" % [foe_cap, my_low, l0]
			"hold":
				return "%s shield wall stood firm against %s %s" % [foe_cap, my_low, l0]
			"flank":
				return "%s flanking sweep rolled up %s %s" % [foe_cap, my_low, l0]
			"skirmish":
				return "%s skirmishers harried %s %s" % [foe_cap, my_low, l0]
			"feint":
				return "%s feigned retreat drew %s %s into a trap" % [foe_cap, my_low, l0]
	if winner == 0:
		return "%s %s prevailed over %s %s" % [my_poss, l0, foe_poss, l1]
	if winner == 1:
		return "%s %s prevailed over %s %s" % [foe_cap, l1, my_low, l0]
	return "%s %s met %s %s head-on" % [my_poss, l0, foe_poss, l1]


## Hook called from BattleRounds._pick_round (and choose when updating the active round):
## resolves both sides' tactics for the round and applies the attack/defence/morale multipliers to the round's fighters.
static func setup_round(game, st: Dictionary) -> void:
	_bind_game(game)
	if game != null and not (game is Dictionary) and "_save_epoch" in game:
		var ep: int = int(game._save_epoch)
		if _pending_epoch != -1 and _pending_epoch != ep:
			_pending_picks = ["", ""]
		_pending_epoch = ep
	_ensure_state(st)
	var pb: Dictionary = _pending_battle_of(game)
	if pb.has("next_tactic") and pb["next_tactic"] is Array:
		var pnext: Array = pb["next_tactic"]
		for s in mini(2, pnext.size()):
			if str(pnext[s]) != "" and str((st["next_tactic"] as Array)[s]) == "":
				(st["next_tactic"] as Array)[s] = str(pnext[s])
		pb["next_tactic"] = ["", ""]
	for s in 2:
		if _pending_picks[s] != "" and str((st["next_tactic"] as Array)[s]) == "":
			(st["next_tactic"] as Array)[s] = _pending_picks[s]
		_pending_picks[s] = ""
	var r_idx: int = maxi(1, int(st.get("round", 1)))
	var next_arr: Array = st["next_tactic"]
	var cur_arr: Array = st["tactics"]
	var t0: String = ""
	if str(next_arr[0]) != "":
		t0 = str(next_arr[0])
	elif int(st.get("_tactics_round", 0)) == r_idx and str(cur_arr[0]) != "":
		t0 = str(cur_arr[0])
	else:
		t0 = _player_carry_tactic(st)
	var t1: String = ""
	if str(next_arr[1]) != "":
		t1 = str(next_arr[1])
	elif int(st.get("_tactics_round", 0)) == r_idx and str(cur_arr[1]) != "":
		t1 = str(cur_arr[1])
	else:
		t1 = ai_pick(game, 1, r_idx)
	t0 = valid(t0)
	t1 = valid(t1)
	st["tactics"] = [t0, t1]
	st["next_tactic"] = ["", ""]
	st["_tactics_round"] = r_idx
	var mods: Dictionary = modifiers(game, st)
	st["tactic_mods"] = mods
	if game != null and not (game is Dictionary) and "main" in game and game.main != null and "current" in game.main and game.main.current != null:
		var cur: Variant = game.main.current
		if cur != null and "sim" in cur and cur.sim != null and not cur.sim.over:
			apply_sim(cur.sim, mods)


## Hook called from BattleRounds.after_round: writes d["tactics"], d["tactic_note"], and st["last_tactics"].
static func finish_round(game, st: Dictionary, d: Dictionary) -> void:
	_ensure_state(st)
	var r_idx: int = maxi(1, int(st.get("round", 1)))
	var cur: Array = st.get("tactics", ["", ""])
	var t0: String = valid(str(cur[0])) if cur.size() > 0 and str(cur[0]) != "" else _player_carry_tactic(st)
	var t1: String = valid(str(cur[1])) if cur.size() > 1 and str(cur[1]) != "" else ai_pick(game, 1, r_idx)
	var w: int = int(d.get("winner", -1))
	d["tactics"] = [t0, t1]
	d["tactic_note"] = outcome_note(t0, t1, w, true)
	st["last_tactics"] = [t0, t1]


## Applies tactic multipliers directly to the round's Fighter objects in BattleSim (never mutating Unit in place).
## Idempotent on a given BattleSim: unscaled fighter baselines are saved in fighter meta so repeated calls do not compound.
static func apply_sim(sim: BattleSim, mods: Dictionary) -> void:
	if sim == null:
		return
	for item in sim.fighters:
		var f: Fighter = item
		if f.unit == null:
			continue
		var side_key: String = "side0" if f.side == 0 else "side1"
		var m: Dictionary = mods.get(side_key, {})
		var att: float = float(m.get("attack", 1.0))
		var def_m: float = float(m.get("defence", 1.0))
		var mor: float = float(m.get("morale", 1.0))
		var base: Dictionary = {}
		if f.has_meta("_tactic_base") and f.get_meta("_tactic_base") is Dictionary:
			base = f.get_meta("_tactic_base")
		else:
			base = {
				"morale_base": float(f.morale_base),
				"morale_start": float(f.morale_start),
				"morale": float(f.morale),
			}
			f.set_meta("_tactic_base", base)
		var scaled_attrs: Dictionary = f.unit.eff_attrs().duplicate()
		for a in ["STR", "FOC", "SPA"]:
			if scaled_attrs.has(a):
				scaled_attrs[a] = maxi(1, int(round(float(scaled_attrs[a]) * att)))
		for a in ["TOU", "AGI"]:
			if scaled_attrs.has(a):
				scaled_attrs[a] = maxi(1, int(round(float(scaled_attrs[a]) * def_m)))
		f.alv.clear()
		for check in Formulas.CHECK_ATTRS:
			f.alv[check] = Formulas.attr_levels(String(check), scaled_attrs)
		# The v0.041 check reads scaled toughness (maxi(1, ...), never the 200 floor) at this key.
		f.alv["endurance"] = [int(scaled_attrs.get("TOU", f.unit.attr("TOU")))]
		var u := f.unit
		var body := u.body
		var agi_v := float(scaled_attrs.get("AGI", u.attr("AGI")))
		var str_v := float(scaled_attrs.get("STR", u.attr("STR")))
		var eff_mass := Formulas.effective_gear_mass(f.armor_mass, f.other_mass, u.skill("armor_user"))
		var enc := Formulas.encumbrance_ratio(eff_mass, str_v, u.mass())
		var pain_eff := 0.0
		var blood_frac := 1.0
		var ex_ratio := 0.0
		if body != null:
			pain_eff = float(body.pain)
			blood_frac = float(body.blood) / maxf(1.0, float(body.blood_max))
			ex_ratio = float(body.exertion) / maxf(100.0, float(u.attr("END")))
		f.speed_info = Formulas.tempo_breakdown(f.gait, agi_v, enc, f.leg_impair, pain_eff, blood_frac, ex_ratio)
		f.speed = float(f.speed_info["speed"])
		f.tempo = float(f.speed_info["tempo"])
		f.tempo_tick = sim.tick
		f.morale_base = float(base["morale_base"]) * mor
		f.morale_start = clampf(float(base["morale_start"]) * mor, 5.0, 100.0)
		f.morale = clampf(float(base["morale"]) * mor, 0.0, 100.0)


static func _player_carry_tactic(st: Dictionary) -> String:
	var last_v: Variant = st.get("last_tactics", [])
	if last_v is Array and (last_v as Array).size() > 0 and str((last_v as Array)[0]) != "":
		return valid(str((last_v as Array)[0]))
	return "hold"


static func _ensure_state(st: Dictionary) -> void:
	if not st.has("next_tactic") or not (st["next_tactic"] is Array) or (st["next_tactic"] as Array).size() < 2:
		st["next_tactic"] = ["", ""]
	if not st.has("tactics") or not (st["tactics"] is Array) or (st["tactics"] as Array).size() < 2:
		st["tactics"] = ["", ""]


static func _pending_battle_of(game) -> Dictionary:
	if game == null:
		return {}
	if game is Dictionary:
		if (game as Dictionary).has("pending_battle") and (game as Dictionary)["pending_battle"] is Dictionary:
			return (game as Dictionary)["pending_battle"]
		return game as Dictionary
	if "pending_battle" in game and game.pending_battle is Dictionary:
		return game.pending_battle
	return {}


static func _rounds_of(game, pb: Dictionary) -> Dictionary:
	if pb.has("rounds") and pb["rounds"] is Dictionary:
		return pb["rounds"]
	if game is Dictionary:
		return game as Dictionary
	return {}


static func _enemy_last_tactic(st: Dictionary, side: int, round_index: int) -> String:
	var foe: int = 1 - clampi(side, 0, 1)
	if round_index <= 1:
		return ""
	var log_v: Variant = st.get("log", [])
	if log_v is Array and not (log_v as Array).is_empty():
		var prev: Variant = (log_v as Array)[-1]
		if prev is Dictionary and (prev as Dictionary).has("tactics"):
			var t_arr: Variant = (prev as Dictionary)["tactics"]
			if t_arr is Array and foe < (t_arr as Array).size():
				return str((t_arr as Array)[foe])
	var last_v: Variant = st.get("last_tactics", [])
	if last_v is Array and foe < (last_v as Array).size():
		return str((last_v as Array)[foe])
	return ""


static func _resolve_pair(game, st: Dictionary, r_idx: int) -> Array[String]:
	var out: Array[String] = ["", ""]
	var next_v: Variant = st.get("next_tactic", [])
	var cur_v: Variant = st.get("tactics", [])
	for s in 2:
		var pick: String = ""
		if next_v is Array and s < (next_v as Array).size() and str((next_v as Array)[s]) != "":
			pick = str((next_v as Array)[s])
		elif cur_v is Array and s < (cur_v as Array).size() and str((cur_v as Array)[s]) != "":
			pick = str((cur_v as Array)[s])
		elif s == 0:
			pick = _player_carry_tactic(st)
		else:
			pick = ai_pick(game if game != null else st, s, r_idx)
		out[s] = valid(pick)
	return out


static func _side_tactician(game, st: Dictionary, pb: Dictionary, side: int) -> int:
	var tac_v: Variant = st.get("tactician", null)
	if tac_v is Array and side < (tac_v as Array).size() and int((tac_v as Array)[side]) >= 0:
		return int((tac_v as Array)[side])
	var units: Array = []
	var lf_v: Variant = st.get("last_fought", [])
	if lf_v is Array and side < (lf_v as Array).size() and (lf_v as Array)[side] is Array:
		units = (lf_v as Array)[side]
	if units.is_empty():
		var key: String = "round_side0" if side == 0 else "enemy"
		if pb.has(key) and pb[key] is Array:
			units = pb[key]
	if units.is_empty():
		var pool_v: Variant = st.get("pool", [])
		if pool_v is Array and side < (pool_v as Array).size() and (pool_v as Array)[side] is Array:
			units = (pool_v as Array)[side]
	return commander_tactician(game, units, side, st)
