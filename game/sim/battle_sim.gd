class_name BattleSim
extends RefCounted
## INTERFACE CONTRACT (implemented by the sim workstream; the battle screen depends only on this).
##
## Discrete DF-style ticks for movement AND fighting on a tile grid. Speed decides how often a
## unit acts, so a fast unit can move or strike several times before a slow one acts once.
##
##   var sim := BattleSim.new()
##   sim.setup(player_units, enemy_units, seed, {"w": 32, "h": 18, "terrain": "plains"})
##   while not sim.is_over(): sim.step()       # one tick
##
## Read-only state for presentation:
##   sim.tick: int
##   sim.grid_w, sim.grid_h: int
##   sim.tile_at(cell) -> "open" | "rough" | "blocked"
##   sim.fighters: Array[Fighter]   (see sim/fighter.gd)
##   sim.events: Array[Dictionary]  all events so far, appended each tick:
##       {"tick": int, "type": String, "actor": int (fighter idx) , "target": int, "text": String,
##        "decisive": bool, "part": String}  (+ "entry": the log entry behind it, when there is one)
##     type is one of: "move", "prepare", "attack", "miss", "dodge", "block", "parry", "hit", "wound",
##       "sever", "fall", "stand", "unconscious", "wake", "drop", "death", "rout", "flee", "learn",
##       additive: "artery", "lodged", "freed", "rally", "rage", "stun", "enter"
##     decisive = kills, severed limbs, arteries opened, rout of a side (for the battle feed + slow-mo).
##     PERFORMANCE: only decisive events carry their text eagerly; the others carry text "" and an
##     "entry" (rendered on demand). Read any event's text with BattleSim.event_text(e).
##   sim.new_events: Array[Dictionary]  events produced by the most recent step() only.
##   sim.winner: int  0 = side 0 (player) won, 1 = side 1 won, -1 = undecided/draw.
##
## Fighter logs are lazy: Fighter.log entries {"tick", "k", "d"}; BattleSim.render_entry(entry) returns (and caches
## into the entry) {"tick", "text", "detail": Array[String], "calc"}.
##
## Units passed in are mutated in place: wounds, blood, pain, skill XP, kills/kill_list, dead flags persist.
## Attribute growth (Learning.apply_growth) is applied once, automatically, when the battle ends
## (apply_battle_growth() is idempotent and returns what grew, for the aftermath screen).
##
## 1 tick = 0.05 s (Formulas.TICK_SECONDS). Scheduler: every fighter has an action countdown; all whose action
## completes on a tick act in order of AGI+KIN (initiative), ties broken by a per-fighter roll made at setup.
## Options: "w", "h", "terrain", "max_ticks" (default 24000 = 20 min, then draw), "log_moves" (default true),
## "verbose" (default true: calc steps recorded; false = story only, fastest), "tiles" (Array of row strings:
## '.' open, ',' rough, '#'/'~' blocked) or "map": "open" | "corridor1" | "corridor2", "stream": true (side 1
## enters one at a time through its map edge, "stream_gap" ticks apart), "cells0"/"cells1": explicit deploy cells,
## "hold0"/"hold1": that side holds its ground (strikes what comes into reach, never advances).
## All formulas/constants live in sim/formulas.gd; randomness only in its named roll_* functions.

var tick: int = 0
var grid_w: int = 32
var grid_h: int = 18
var fighters: Array = []
var events: Array = []
var new_events: Array = []
var winner: int = -1
var kill_pairs: Array = []   # [killer Unit, victim Unit] per kill (campaign/ennoble.gd reads the deeds)
var rng := RandomNumberGenerator.new()

var terrain: String = "plains"
var max_ticks: int = 24000
var log_moves: bool = true
var verbose: bool = true
var gear_wear: bool = true   # v0.014 gear damage on (opts "gear_wear")
var over: bool = false
var growth: Dictionary = {}          # fighter idx -> {attr: points} after apply_battle_growth
var occ := PackedInt32Array()       # standing fighter idx per tile, -1 empty
var tiles := PackedByteArray()      # 0 open, 1 rough, 2 blocked
var ground: Array = []               # dropped weapons: [{"cell": Vector2i, "item": Item}]
var side_total := [0, 0]
var side_down := [0, 0]              # dead, unconscious, fled or routed
var last_strike: Dictionary = {}     # summary of the most recent strike (tests, inspector)
var stream: bool = false
var stream_gap: int = 6
var _growth_done := false
var _terrain_mult: float = 1.0
var _bleeders: Dictionary = {}       # fighter idx -> Array of [layer dict, clot rate, part id]
var _bleed_total: Dictionary = {}    # fighter idx -> float
var _force_part := ""
var _force_land := false
var _ldef_cache: Dictionary = {}     # part id -> {layer name -> layer def}
var _seed: int = 0
var _targets: Array = [[], []]       # per side: fighters on the field this tick (target candidates)
var _downs: Array = []              # [fighter, died] shocks waiting for the next tick
# perf caches (per battle; hold exactly what the uncached lookups return)
var _iname: Dictionary = {}          # Item -> display_name()
var _itmpl: Dictionary = {}          # Item -> tmpl()
var _isw: Dictionary = {}            # Item -> is_weapon()
var _proles: Dictionary = {}         # part cache key -> [grasp side, stance, eye] (_part_status)
var _tmats: Dictionary = {}          # tissue -> DB.materials entry (muscle when unknown)
var _bleed_defer: Fighter = null     # inside a strike: _add_bleed on this defender only marks one recount at the end
var _bleed_dirty := false
var _tx0 := PackedInt32Array()       # x / y of each _targets cell per side (see _build_tcells)
var _ty0 := PackedInt32Array()
var _tx1 := PackedInt32Array()
var _ty1 := PackedInt32Array()
var _tcells_ok := false
var _officers: Array = [[], []]      # per side: officer fighters in idx order (roles never change in a battle)
var _wgeo: Dictionary = {}           # Item -> [template, head kg, haft kg, Formulas.weapon_geometry] (fixed per item)
var _wl_bleed := 0.0                 # _wound_core results besides the pain
var _wl_death := ""
# bows (docs/specs/bows.md, sim/archery.gd). Nothing below is touched in a battle without bows.
## Arrows in flight (presentation reads "x", "y" (tile coords, float), "dx", "dy", "side"): one per arrow.
var projectiles: Array = []
var breath_debug: Dictionary = {}
var breath_state: Dictionary = {}    # dragon fighter idx -> {left, next, element} (sim/dragon_breath.gd)
## Where the battle's arrows ended up: {arrow id: {"ground", "body", "shield", "armor", "lost": n}} (recovery).
var arrow_field: Dictionary = {}
var _bows_on := false                # any fighter carries a bow
var _shot: Dictionary = {}           # inside _strike: the arrow being resolved (empty = a melee strike)
var _shot_out: Dictionary = {}       # what the arrow did: {"exit": bool, "E", "v", "end": ground|body|shield|armor}
var _bows_down := 0                  # dropped bows lying on the field (trample check only while > 0)
var _proj_next := 0
var shot_log: Array = []             # opts "shot_log": every finished arrow {"id", "a", "hit": [fighter idx struck]}
var keep_shot_log := false
## Army-scale presentation history is bounded; physiology, damage and learning remain unchanged.
var history_event_limit := 0
var history_log_limit := 0
var events_dropped := 0
var log_dropped: Dictionary = {}
## Complete transient history is separate from bounded presentation tails.
var combat_journal: CombatJournal
var _journal_pending: Array = [] # at most one native tick, flushed before tail trimming
var learning_summary: Dictionary = {}

static func formation_grid(n0: int, n1: int, requested: Vector2i = Vector2i(32, 18)) -> Vector2i:
	var n := maxi(n0, n1)
	var grid := requested
	if n > 20: grid = Vector2i(maxi(grid.x, 64), maxi(grid.y, 36))
	if n > 64: grid = Vector2i(maxi(grid.x, 80), maxi(grid.y, 44))
	# No Unit is dropped if allied forces take a side beyond the supported 200 target.
	grid.y = maxi(grid.y, ceili(float(n) / maxi(1, grid.x / 2 - 2)) + 2)
	return grid

static func padded_tiles(rows: Array, grid: Vector2i) -> Array:
	if rows.is_empty(): return rows
	var width := maxi(grid.x, String(rows[0]).length())
	var height := maxi(grid.y, rows.size())
	var xpad := (width - String(rows[0]).length()) / 2
	var ypad := (height - rows.size()) / 2
	var out := []
	for y in height:
		if y < ypad or y >= ypad + rows.size(): out.append(".".repeat(width))
		else:
			var line := ".".repeat(xpad) + String(rows[y - ypad])
			out.append(line + ".".repeat(maxi(0, width - line.length())))
	return out

const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const T_OPEN := 0
const T_ROUGH := 1
const T_BLOCKED := 2
# Fighter.pstat entry slots (BattleSim._part_status)
const PS_STANCE := 0
const PS_LEG := 1
const PS_BAD := 2
const PS_SPINE := 3
const PS_WHY := 4
const PS_EYE := 5
const PS_EYE_OK := 6
const PS_GRASP := 7
const PS_REL := 8
const PS_DIGIT := 9       # v0.013: "r" / "l" for a finger of that hand ("" otherwise)
const PS_DIGIT_W := 10    # its DF relative size
const PS_DIGIT_OK := 11   # it can still close
const PS_ARMS := 12       # the upper spinal cord is cut (both arms limp)

# =====================================================================================================
# Setup
# =====================================================================================================
func setup(side0: Array, side1: Array, seed: int, opts: Dictionary = {}) -> void:
	rng.seed = seed
	_seed = seed
	tick = 0
	grid_w = maxi(4, int(opts.get("w", 32)))
	grid_h = maxi(3, int(opts.get("h", 18)))
	var per_side := maxi(side0.size(), side1.size())
	var grid := formation_grid(side0.size(), side1.size(), Vector2i(grid_w, grid_h))
	grid_w = grid.x; grid_h = grid.y
	if per_side > 64 and opts.has("tiles"):
		opts = opts.duplicate()
		opts["tiles"] = padded_tiles(opts["tiles"], grid)
	terrain = str(opts.get("terrain", "plains"))
	max_ticks = int(opts.get("max_ticks", 24000))
	log_moves = bool(opts.get("log_moves", true))
	verbose = bool(opts.get("verbose", true))
	gear_wear = bool(opts.get("gear_wear", true))   # v0.014: false = gear takes no damage (fresh-gear physics probes)
	stream = bool(opts.get("stream", false))
	stream_gap = maxi(1, int(opts.get("stream_gap", 6)))
	_terrain_mult = float(Formulas.TERRAIN_MOVE.get(terrain, 1.0))
	fighters.clear(); events.clear(); new_events.clear(); growth.clear(); ground.clear()
	winner = -1; over = false; _growth_done = false
	kill_pairs.clear()
	side_total = [0, 0]; side_down = [0, 0]
	_bleeders.clear(); _bleed_total.clear(); _ldef_cache.clear(); _downs.clear(); _iname.clear(); _tmats.clear(); _wgeo.clear(); _itmpl.clear(); _isw.clear(); _proles.clear()
	projectiles.clear(); arrow_field.clear(); _bows_on = false; _shot = {}; _shot_out = {}; _bows_down = 0; _proj_next = 0   # bows
	shot_log.clear(); keep_shot_log = bool(opts.get("shot_log", false))
	history_event_limit = maxi(0, int(opts.get("history_events", 8192 if per_side > 64 else 0)))
	history_log_limit = maxi(0, int(opts.get("history_log", 512 if per_side > 64 else 0)))
	events_dropped = 0; log_dropped.clear(); learning_summary.clear()
	if combat_journal != null: combat_journal.dispose()
	combat_journal = null
	_journal_pending.clear()
	_build_tiles(opts)
	if per_side > 64:
		# Army formations have open deployment bands even on dressed/chokepoint maps.
		var columns := ceili(float(per_side) / maxi(1, grid_h - 2)) + 1
		for y in grid_h:
			for x in columns:
				tiles[y * grid_w + x] = T_OPEN
				tiles[y * grid_w + grid_w - 1 - x] = T_OPEN
	occ.resize(grid_w * grid_h)
	occ.fill(-1)
	var sides := [side0, side1]
	for s in 2:
		for u in _squad_order(sides[s]):
			var f := Fighter.new()
			f.idx = fighters.size()
			f.unit = u
			f.side = s
			f.facing = 1 if s == 0 else -1
			Food.apply_battle(u)   # food/drink attribute multipliers count from the first decision (initiative too)
			_init_fighter(f)
			_food_refresh(f)
			f.tiebreak = Formulas.roll_initiative_tiebreak(rng)
			f.action_ticks = f.idx % 10  # staggered first decisions (spreads the opening target search)
			fighters.append(f)
	for s in 2:
		var cells: Array = opts.get("cells%d" % s, [])
		if s == 1 and stream:
			for f in fighters:
				if f.side == 1:
					f.waiting = true
					f.cell = Vector2i(-100, -100)
					f.prev_cell = f.cell
			continue
		_deploy(s, cells)
		if bool(opts.get("hold%d" % s, false)):
			for f in fighters:
				if f.side == s:
					f.hold = true
	for f in fighters:
		side_total[f.side] += 1
		if f.state == "dead" or f.state == "unconscious":
			side_down[f.side] += 1
	if bool(opts.get("combat_journal", true)):
		combat_journal = CombatJournal.new()
		var people: Array = []
		for f: Fighter in fighters:
			var person: Dictionary = {"idx": f.idx, "name": f.unit.name, "label": f.label,
				"side": f.side, "unit_uid": f.unit.uid, "race": f.unit.race, "role": f.unit.role}
			if f.dragon:
				person["dragon_uid"] = f.unit.dragon_uid
				person["rider_person_uid"] = str(f.dragon_profile.get("rider_person_uid", ""))
			people.append(person)
		combat_journal.setup(people)
	_init_morale()
	for f in fighters:
		_food_start_line(f)
	_check_end()
	_trim_history()

func _build_tiles(opts: Dictionary) -> void:
	var rows: Array = opts.get("tiles", []).duplicate()
	var map: String = str(opts.get("map", "open"))
	if rows.is_empty() and map.begins_with("corridor"):
		var width := 2 if map == "corridor2" else 1
		var cx := grid_w / 2
		var half := int(opts.get("corridor_len", 6)) / 2
		var y0 := (grid_h - width) / 2
		for y in grid_h:
			var line := ""
			for x in grid_w:
				var wall := x >= cx - half and x <= cx + half and (y < y0 or y >= y0 + width)
				line += "#" if wall else "."
			rows.append(line)
	if not rows.is_empty():
		grid_h = rows.size()
		grid_w = String(rows[0]).length()
	tiles.resize(grid_w * grid_h)
	tiles.fill(T_OPEN)
	for y in rows.size():
		var line: String = rows[y]
		for x in mini(line.length(), grid_w):
			var ch := line[x]
			if ch == "#" or ch == "~":
				tiles[y * grid_w + x] = T_BLOCKED
			elif ch == ",":
				tiles[y * grid_w + x] = T_ROUGH

func tile_at(c: Vector2i) -> String:
	if not _inb(c):
		return "blocked"
	return ["open", "rough", "blocked"][tiles[_ci(c)]]

func _passable(c: Vector2i) -> bool:
	return _inb(c) and tiles[_ci(c)] != T_BLOCKED

## Diagonal steps and strikes may not squeeze between wall corners.
func _diag_ok(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	if d.x == 0 or d.y == 0 or absi(d.x) > 1 or absi(d.y) > 1:
		return true
	return _passable(Vector2i(b.x, a.y)) and _passable(Vector2i(a.x, b.y))

## Groups units by squad (officer uid) keeping first-appearance order; officers lead their squad.
func _squad_order(units: Array) -> Array:
	var keys := []
	var groups := {}
	for u in units:
		var k: int = u.uid if u.is_officer() else u.squad
		if not groups.has(k):
			groups[k] = []
			keys.append(k)
		if u.is_officer():
			groups[k].push_front(u)
		else:
			groups[k].append(u)
	var out := []
	for k in keys:
		out.append_array(groups[k])
	return out

## Side 0 deploys on the left, side 1 on the right, in columns facing the enemy; squads stay contiguous.
func _deploy(s: int, cells: Array) -> void:
	var mine := fighters.filter(func(f): return f.side == s)
	var n := mine.size()
	if n == 0:
		return
	var per_col := maxi(1, grid_h - 2)
	var cols := mini(int(ceil(float(n) / per_col)), maxi(1, grid_w / 2 - 1))
	per_col = int(ceil(float(n) / cols))
	for i in n:
		var f: Fighter = mine[i]
		var cell: Vector2i
		if i < cells.size():
			cell = cells[i]
		else:
			var c := i / per_col
			var r := i % per_col
			var in_col := mini(per_col, n - c * per_col)
			var y0 := maxi(0, (grid_h - in_col) / 2)
			var x := (cols - c) if s == 0 else (grid_w - 1 - cols + c)
			cell = Vector2i(clampi(x, 0, grid_w - 1), clampi(y0 + r, 0, grid_h - 1))
		cell = _nearest_free(cell)
		f.cell = cell
		f.prev_cell = cell
		if f.standing():
			occ[_ci(cell)] = f.idx

func _nearest_free(c: Vector2i) -> Vector2i:
	if _passable(c) and occ[_ci(c)] == -1:
		return c
	for rad in range(1, maxi(grid_w, grid_h)):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var p := c + Vector2i(dx, dy)
				if _passable(p) and occ[_ci(p)] == -1:
					return p
	return c

func _init_fighter(f: Fighter) -> void:
	var u := f.unit
	var r := u.race_def()
	f.label = _make_label(f)
	f.rdef = r
	f.creature = bool(r.get("creature", false))
	f.dragon = u.is_native_dragon()
	if f.dragon:
		f.dragon_profile = u.native_dragon_profile.duplicate(true)
		f.dragon_attacks = DragonCombat.attack_rows(u, f.dragon_profile)
		f.rdef = r.duplicate(true) # per-actor silhouette, never mutate the shared race
		f.rdef["height"] = float(f.dragon_profile["height_m"])
		f.rdef["width"] = float(f.dragon_profile["width_m"])
		f.rdef["mass"] = u.mass()
	f.nofear = bool(r.get("nofear", false))
	f.pron = "its" if f.creature else ("her" if u.sex == 1 else "his")   # monsters wave 1; v0.014 the register's sex
	f.cul = "" if f.creature else _culture_of(u)
	f.voff = absi(hash(f.idx * 7919 + _seed * 31 + 13)) % 997
	f.wielded = u.weapon()
	if f.wielded != null and f.wielded.broken:   # v0.014: a snapped weapon not yet scrapped is useless
		f.weapon_dropped = true
	f.reach_tiles = _reach_of(f)
	f.initiative = float(u.attr("AGI") + u.attr("KIN"))
	var gaits: Array = r.get("gait", Formulas.GAIT_DEFAULT)
	var g := float(gaits[mini(Formulas.GAIT_INDEX_ADVANCE, gaits.size() - 1)])
	f.gait = g * (1.0 + Formulas.LEG_LEN_GAIT_K * (100.0 / maxf(50.0, float(u.leg_len)) - 1.0))
	f.armor_mass = 0.0
	f.other_mass = 0.0
	f.armor_for = {}
	for slot in u.equip:
		var it: Item = u.equip[slot]
		var t := it.tmpl()
		if it.is_weapon() or t.get("slot", "") == "shield" or t.get("slot", "") == "ranged":   # bows: the bow is carried, not worn
			f.other_mass += it.mass()
			continue
		f.armor_mass += it.mass()
		var order: int = {"cover": 0, "armor": 1, "over": 2, "under": 3}.get(t.get("layer", "armor"), 1)
		var cov: Dictionary = t.get("coverage", {})
		for pid in cov:
			if not f.armor_for.has(pid):
				f.armor_for[pid] = []
			f.armor_for[pid].append({"name": "%s %s" % [it.material, t.get("name", it.tid)], "mat": it.mat(),
				"cov": float(cov[pid]), "rigid": bool(t.get("rigid", false)), "semi": bool(t.get("semi_rigid", false)),
				"padded": bool(t.get("padded", false)), "t": float(t.get("thickness", 2)), "q": it.quality, "order": order,
				"slot": String(t.get("slot", slot)), "item": it, "w": 1.0 if it.broken else 0.0})   # v0.014: the Item (gear damage), spot weakness
	for pid in f.armor_for:
		f.armor_for[pid].sort_custom(func(a, b): return a["order"] < b["order"])
	if u.equip.has("ranged") or not u.quiver.is_empty():   # bows: the bow, the quiver and the arrows in it
		Archery.init_fighter(self, f)
	f.gear_mass = f.armor_mass + f.other_mass
	var b := u.body
	var list := []
	for pid in b.parts:
		for L in b.parts[pid]["layers"]:
			if float(L.get("bleed", 0.0)) > 0.0:
				list.append([L, Formulas.CLOT_MINOR, pid])
			if L["tissue"] == "brain":
				f.think_dmg = maxf(f.think_dmg, float(L["dmg"]))
	_bleeders[f.idx] = list
	_recount_bleed(f)
	for pid in b.lost_ids():   # sparse body: severed parts are stored, the parts below them are not
		f.lost[pid] = true
	_update_functions(f, false)
	if u.dead:
		f.state = "dead"
	elif b.blood < b.blood_max * Formulas.BLOOD_FAINT or b.pain > Formulas.PAIN_KO:
		f.state = "unconscious"
		f.prone = true
	elif f.stance_lost:
		f.prone = true
		f.state = "prone"
	_compute_tempo(f)

func _reach_of(f: Fighter) -> int:
	if f.dragon: return clampi(ceili(float(f.dragon_profile.get("reach_m", 1.0))), 1, 3)
	if f.wielded != null and not f.weapon_dropped and float(f.wielded.tmpl().get("reach", 80)) * f.unit.arm_len / 100.0 >= 150.0:
		return 2
	return 1

## v0.014: the culture whose battle cries and taunts a fighter uses (his faction's culture, else his race's).
const RACE_CULTURE := {"orc": "orc", "troll": "orc", "goblin": "goblin", "dwarf": "dwarf", "moon_elf": "elf", "high_elf": "elf", "dark_elf": "elf"}
func _culture_of(u: Unit) -> String:
	var c := String(DB.factions.get(u.faction, {}).get("culture", ""))
	if c in ["moon_elf", "high_elf", "dark_elf"]:
		c = "elf"
	if c == "":
		c = String(RACE_CULTURE.get(u.race, "middle"))
	return c

func _make_label(f: Fighter) -> String:
	var u := f.unit
	if f.side == 0:
		return u.name
	var race_name: String = u.race_def().get("name", u.race)
	var t := u.title if u.title != "" else race_name
	if not t.contains(race_name):
		t = race_name + " " + t
	var first := u.name.split(" ")[0] if u.name != "" else ""
	return ("the %s %s" % [t, first]).strip_edges()

func _trait(f: Fighter, t: String) -> float:
	var c = f.trait_cache.get(t)   # perf: personality and race are fixed during a battle
	if c != null:
		return c
	var rp = f.unit.race_def().get("personality", {})
	var dflt := 50.0
	if rp is Dictionary and rp.has(t) and not (rp[t] is Array):
		dflt = float(rp[t])
	var v := float(f.unit.personality.get(t, dflt))
	f.trait_cache[t] = v
	return v

func _init_morale() -> void:
	_officers = [[], []]
	var commands: Array = [{}, {}]
	for f in fighters:
		if f.unit.is_officer():
			_officers[f.side].append(f)
			var uid: int = f.unit.uid
			if uid > 0:
				# Duplicate native UID claims are ambiguous, never first-match leaders.
				commands[f.side][uid] = -2 if commands[f.side].has(uid) else f.idx
	for f: Fighter in fighters:
		f.commander_idx = -1
		f.commander_uid = -1
		var uid: int = f.unit.squad
		var idx: int = int(commands[f.side].get(uid, -1))
		if uid > 0 and idx >= 0 and idx != f.idx and f.unit.uid != uid:
			f.commander_idx = idx
			f.commander_uid = uid
	for f in fighters:
		# perf: the battle traits as fields (personality is fixed during a battle; same values as _trait)
		f.tr_nerve = _trait(f, "nerve")
		f.tr_temper = _trait(f, "temper")
		f.tr_prot = _trait(f, "protectiveness")
		f.tr_courage = _trait(f, "courage")
		f.tr_loyalty = _trait(f, "loyalty")
		f.tr_cohesion = _trait(f, "cohesion")
	for f in fighters:
		# Unclamped intrinsic component; clamp only after adding the native aura.
		f.morale_base = Formulas.MORALE_START + (f.tr_courage - 50.0) / 2.0 + Food.morale_mod(f.unit)
		f.morale_start = Formulas.morale_start(_trait(f, "courage"), _leader_near(f), Food.morale_mod(f.unit))
		f.morale = f.morale_start

## Actual assigned same-side officer within the existing native command radius.
## Cached indices make support/rally O(1), with live incapacity/identity checks.
func _commander_near(f: Fighter) -> Fighter:
	if f.commander_idx < 0 or f.commander_idx >= fighters.size(): return null
	var o: Fighter = fighters[f.commander_idx]
	if o == f or o.unit == f.unit or o.side != f.side or o.unit.uid != f.commander_uid or \
			f.unit.squad != f.commander_uid or f.unit.uid == f.commander_uid or not o.unit.is_officer():
		return null
	if o.unit.dead or not o.standing() or o.state not in ["ready", "moving", "preparing", "recovering"] or o.routed or o.stance_lost:
		return null
	if _dist(o.cell, f.cell) > Formulas.LEADER_RADIUS: return null
	return o

func _leader_near(f: Fighter) -> float:
	var o: Fighter = _commander_near(f)
	return float(o.unit.skill("leader")) if o != null else 0.0

# =====================================================================================================
# Tick loop
# =====================================================================================================
func is_over() -> bool:
	return over

func step() -> void:
	new_events = []
	if over:
		return
	tick += 1
	if not _downs.is_empty():
		_process_downs()
	if stream and tick % stream_gap == 0:
		_stream_enter()
	var ready := []
	var tg0 := []
	var tg1 := []
	_targets = [tg0, tg1]
	# perf (same results): state checks inlined (Fighter.active() = not dead, fled or unconscious)
	for f in fighters:
		var st: String = f.state
		if not (f.waiting or st == "dead" or st == "fled"):
			if f.side == 0:
				tg0.append(f)
			else:
				tg1.append(f)
	_tcells_ok = false
	if not projectiles.is_empty():   # bows: arrows in flight move before anyone acts
		Archery.step_projectiles(self)
	for f in fighters:
		var st: String = f.state
		if f.waiting or st == "dead" or st == "fled":
			continue
		_physiology(f)
		st = f.state
		if st == "dead" or st == "fled" or st == "unconscious":
			continue
		if f.action_ticks > 0:
			f.action_ticks -= 1
		if f.action_ticks <= 0:
			ready.append(f)
	if ready.size() > 1:
		ready.sort_custom(_initiative_first)
	for f in ready:
		if not f.active() or f.action_ticks > 0:
			continue
		_complete_action(f)
		if not f.active() or f.action_ticks > 0:
			continue
		_decide(f)
	_check_end()
	_trim_history()

func _initiative_first(a: Fighter, b: Fighter) -> bool:
	if a.initiative != b.initiative:
		return a.initiative > b.initiative
	return a.tiebreak > b.tiebreak

func _stream_enter() -> void:
	var edge_x := grid_w - 1
	var best := Vector2i(-1, -1)
	for y in grid_h:
		var c := Vector2i(edge_x, y)
		if _passable(c) and occ[_ci(c)] == -1 and (best.x < 0 or absi(y - grid_h / 2) < absi(best.y - grid_h / 2)):
			best = c
	if best.x < 0:
		return
	for f in fighters:
		if f.waiting and f.state != "dead":
			f.waiting = false
			f.cell = best
			f.prev_cell = best
			if f.standing():
				occ[_ci(best)] = f.idx
			_event("enter", f.idx, -1, "", false)
			return

func _check_end() -> void:
	var standing := [0, 0]
	# perf (same results): Fighter.active() inlined; only "is a side at zero" is used below, so the first fighter still
	# standing from the front and from the back are checked first: different sides = both sides stand, not over.
	var s0 := 0
	var s1 := 0
	var first := -1
	for f in fighters:
		var st: String = f.state
		if st != "dead" and st != "fled" and st != "unconscious" and not f.routed:
			first = f.side
			break
	var last := -1
	if first >= 0:
		for i in range(fighters.size() - 1, -1, -1):
			var f: Fighter = fighters[i]
			var st: String = f.state
			if st != "dead" and st != "fled" and st != "unconscious" and not f.routed:
				last = f.side
				break
	if first >= 0 and last >= 0 and first != last:
		s0 = 1
		s1 = 1
	else:
		for f in fighters:
			var st: String = f.state
			if st != "dead" and st != "fled" and st != "unconscious" and not f.routed:
				if f.side == 0:
					s0 += 1
				else:
					s1 += 1
				if s0 > 0 and s1 > 0:
					break
	standing[0] = s0
	standing[1] = s1
	if standing[0] == 0 or standing[1] == 0:
		over = true
		if standing[0] == 0 and standing[1] == 0:
			winner = -1
		else:
			winner = 0 if standing[0] > 0 else 1
			var loser := 1 - winner
			for f in fighters:
				if f.side == loser and f.active() and f.routed:
					_ev_simple("rout", -1, -1, "side_routed", {"side": "player" if loser == 0 else "enemy"}, true)
					break
	elif tick >= max_ticks:
		over = true
		winner = -1
	if over:
		if _bows_on:   # bows: arrows still in the air come down; lodged arrows are pulled on the field
			Archery.end_battle(self)
		apply_battle_growth()
		for f in fighters:
			# battle-only attribute multipliers come off when the fight ends (already empty = nothing to clear;
			# Unit.set_food_attr_mult empties both dictionaries together)
			if not f.unit.food_attr_mult.is_empty():
				Food.clear_battle(f.unit)
			f.alv.clear()

## End-of-battle attribute growth (once). Returns fighter idx -> {attr: points gained}.
func apply_battle_growth() -> Dictionary:
	if _growth_done:
		return growth
	_growth_done = true
	for f in fighters:
		var g := Learning.apply_growth(f.unit, f.attr_use, f.rdef)
		if not g.is_empty():
			growth[f.idx] = g
			# perf: the "STR +2, ..." text is built from "gd" when the line is read (CombatText.growth_text)
			_log(f, "ev", {"key": "growth", "n": f.unit.name, "gd": g, "use": f.attr_use.duplicate()})
	return growth

# ---------------------------------------------------------------- physiology (every tick, deterministic)
func _physiology(f: Fighter) -> void:
	var u := f.unit   # perf: locals for the unit, body and index (same reads and writes)
	var b := u.body
	var idx := f.idx
	var bt: float = _bleed_total.get(idx, 0.0)
	if bt > 0.0:
		b.blood = maxf(0.0, b.blood - bt)
		if (tick + idx) % 10 == 0:
			_clot(f, 10)
		var frac := b.blood / b.blood_max
		if frac < Formulas.BLOOD_DEATH:
			_kill(f, f.last_attacker, "bled to death")
			return
		if frac < Formulas.BLOOD_FAINT and f.state != "unconscious":
			_knock_out(f, "blood")
	if f.suffocating:
		f.air -= 1.0
		if f.air <= 0.0:
			_kill(f, f.last_attacker, "suffocated")
			return
		if f.air < Formulas.AIR_MAX * Formulas.AIR_KO and f.state != "unconscious":
			_knock_out(f, "air")
	var floor_p := f.pain_floor_src * Formulas.PAIN_PERSIST
	var pn := b.pain
	if pn > floor_p:
		b.pain = maxf(floor_p, pn - (pn - floor_p) * Formulas.PAIN_DECAY_PER_TICK)
	var ex := b.exertion
	if ex > 0.0 and tick - f.last_attacked_tick >= Formulas.EX_RECOVER_QUIET_TICKS:
		b.exertion = maxf(0.0, ex - Formulas.EX_RECOVER_PER_TICK)
	if f.knockdown_left > 0:
		f.knockdown_left -= 1
	if f.rage_ticks > 0:
		f.rage_ticks -= 1
	if u.buzz > 0.0:
		u.buzz = maxf(0.0, u.buzz - Food.BUZZ_DECAY_TICK)
		if u.buzz < f.buzz_floor:   # sobering up into the next state down
			Food.apply_battle(u)
			f.alv.clear()
			_food_refresh(f)
			f.tempo_tick = -1000
	if (tick + idx) % Formulas.MORALE_TICK == 0:
		_morale_tick(f)
	if f.state == "unconscious" and (tick + idx) % 10 == 0:
		var fr := b.blood / b.blood_max
		if b.pain < Formulas.PAIN_KO * Formulas.PAIN_WAKE and fr > Formulas.BLOOD_FAINT + 0.03 \
				and f.think_dmg < Formulas.THINK_KO and (not f.suffocating or f.air > Formulas.AIR_MAX * Formulas.AIR_KO):
			f.state = "prone"
			f.prone = true
			f.knockdown_left = Formulas.KNOCKDOWN_TICKS
			f.action_ticks = 0
			if not f.routed:
				side_down[f.side] -= 1
			_ev_simple("wake", f.idx, -1, "wake", {"pain": b.pain, "blood": fr})

func _clot(f: Fighter, dt: int) -> void:
	var keep := []
	for e in _bleeders.get(f.idx, []):
		var L: Dictionary = e[0]
		L["bleed"] = float(L["bleed"]) * pow(1.0 - float(e[1]), dt)
		if L["bleed"] < 0.0005:
			L["bleed"] = 0.0
		else:
			keep.append(e)
	_bleeders[f.idx] = keep
	_recount_bleed(f)

func _recount_bleed(f: Fighter) -> void:
	var t := 0.0
	f.bleeding.clear()
	for e in _bleeders.get(f.idx, []):
		var bl := float(e[0]["bleed"])
		t += bl
		f.bleeding[e[2]] = float(f.bleeding.get(e[2], 0.0)) + bl
	_bleed_total[f.idx] = t

func _add_bleed(f: Fighter, pid: String, L: Dictionary, amount: float, clot: float) -> void:
	if amount <= 0.0:
		return
	L["bleed"] = float(L.get("bleed", 0.0)) + amount
	var list: Array = _bleeders.get(f.idx, [])
	var found := false
	for e in list:
		if is_same(e[0], L):
			e[1] = minf(float(e[1]), clot)
			found = true
	if not found:
		list.append([L, clot, pid])
	_bleeders[f.idx] = list
	if f == _bleed_defer:
		_bleed_dirty = true   # recounted once at the end of the strike (nothing reads the totals before that)
	else:
		_recount_bleed(f)

# ---------------------------------------------------------------- actions
func _ticks(f: Fighter, x: float) -> int:
	var t := x + f.tick_carry
	var n := maxi(1, int(t))
	f.tick_carry = clampf(t - n, -1.0, 1.0)
	return n

func _set_action(f: Fighter, state: String, ticks: int) -> void:
	f.state = state
	f.action_ticks = ticks
	f.action_total = maxi(1, ticks)
	f.action_delay = 0

func _idle_state(f: Fighter) -> String:
	return "prone" if f.prone else "ready"

func _complete_action(f: Fighter) -> void:
	if f.state == "preparing":
		if not f.pending_action.is_empty():
			_finish_special(f)
		else:
			_deliver(f)
	else:
		f.state = _idle_state(f)

func _decide(f: Fighter) -> void:
	if f.routed:
		_flee_step(f)
		return
	if not f.lodged.is_empty():
		_decide_lodged(f)
		return
	if f.prone:
		if f.knockdown_left > 0:
			_set_action(f, "prone", f.knockdown_left)
			return
		if not f.stance_lost and occ[_ci(f.cell)] == -1:
			f.prone = false
			occ[_ci(f.cell)] = f.idx
			_ev_simple("stand", f.idx, -1, "stand", {})
			_set_action(f, "ready", _ticks(f, 6.0))
			return
	# A weapon stuck in me, still held by its wielder: fight on only if my weapon reaches him, else pull it out.
	for s in f.stuck_in_me:
		if int(s["wielder"]) >= 0:
			var w: Fighter = fighters[int(s["wielder"])]
			if not (_has_weapon(f) and _in_reach(f, w)):
				_begin_special(f, "victim_pull", Formulas.VICTIM_PULL_BASE + int(s["layers"]), {"wielder": int(s["wielder"])})
				return
			f.target = w.idx
	if f.dragon and DragonBreath.try(self, f):   # dragon breath: a cone attack a few times per battle
		return
	if f.bow != null and Archery.decide(self, f):   # bows: shoot, kite, switch to the sidearm and back
		return
	if f.grabbing >= 0 and f.creature and NaturalAttacks.decide(self, f):   # monsters wave 1: latched drag
		return
	if not _has_weapon(f) and _decide_unarmed_extra(f):
		return
	var t: Fighter = fighters[f.target] if f.target >= 0 else null
	f.retarget_count += 1
	var need := t == null or not t.alive() or t.state == "fled" or t.waiting
	if not need and t.state == "unconscious" and f.retarget_count % 3 == 0:
		need = true
	if not need and f.retarget_count % 6 == 0 and _dist(f.cell, t.cell) > f.reach_tiles:
		need = true
	if need:
		_pick_target(f)
		t = fighters[f.target] if f.target >= 0 else null
	if t == null:
		_set_action(f, _idle_state(f), _ticks(f, 5.0))
		return
	if f.hold and not _in_reach(f, t):
		# holding ground: strike whoever is in reach, else wait facing the enemy
		var near := _enemy_in_reach(f)
		if near != null:
			t = near
			f.target = near.idx
	if t.cell.x != f.cell.x:
		f.facing = 1 if t.cell.x > f.cell.x else -1
	if _in_reach(f, t):
		_start_attack(f, t)
	elif f.hold and f.grabbed_by < 0 and not _held_in_place(f) and _enemy_reaching_me(f) != null:
		# a longer weapon is poking from beyond my reach: step in to engage it (holding never means standing idle)
		_move_toward(f, _enemy_reaching_me(f).cell)
	elif f.grabbed_by >= 0 or _held_in_place(f) or f.hold:
		_set_action(f, _idle_state(f), _ticks(f, 3.0))
	else:
		_move_toward(f, t.cell)

func _enemy_in_reach(f: Fighter) -> Fighter:
	var best: Fighter = null
	for e in _targets[1 - f.side]:
		if e.alive() and e.state != "fled" and not e.routed and _in_reach(f, e):
			if best == null or (best.helpless() and not e.helpless()):
				best = e
	return best

func _enemy_reaching_me(f: Fighter) -> Fighter:
	for e in _targets[1 - f.side]:
		if e.standing() and not e.routed and _in_reach(e, f):
			return e
	return null

func _in_reach(f: Fighter, t: Fighter) -> bool:
	var d := _dist(f.cell, t.cell)
	if d < 1 or d > f.reach_tiles:
		return false
	if d == 1:
		return _diag_ok(f.cell, t.cell)
	if f.dragon and d > 2:
		# Three bounded native grid steps; do not strike through intervening walls.
		var previous: Vector2i = f.cell
		for step: int in range(1, d + 1):
			var at: Vector2i = Vector2i(roundi(lerpf(f.cell.x, t.cell.x, float(step) / d)), roundi(lerpf(f.cell.y, t.cell.y, float(step) / d)))
			if not _passable(at) or not _diag_ok(previous, at): return false
			previous = at
		return true
	return _reach_clear(f.cell, t.cell)

## A 2-tile strike needs an open tile between the two (no stabbing through or around wall corners).
func _reach_clear(a: Vector2i, b: Vector2i) -> bool:
	var dv := b - a
	var c1 := a + Vector2i(signi(dv.x), signi(dv.y))
	var c2 := a + Vector2i(dv.x / 2, dv.y / 2)
	for c in [c1, c2]:
		if _passable(c) and _diag_ok(a, c) and _diag_ok(c, b):
			return true
	return false

func _held_in_place(f: Fighter) -> bool:
	for s in f.stuck_in_me:
		if int(s["wielder"]) >= 0:
			return true
	return false

## DF-dumb targeting: nearest-ish enemy with a random preference; routers and the helpless are less attractive.
func _pick_target(f: Fighter) -> void:
	var best := -1
	var best_score := INF
	# first pass (no dice): the nearest plain distance; only candidates within reach of the noise get a roll
	var cands: Array = _targets[1 - f.side]
	var dists := PackedInt32Array()
	dists.resize(cands.size())
	var dmin := 1 << 30
	var fx := f.cell.x
	var fy := f.cell.y
	if not _tcells_ok:
		_build_tcells()
	var xs: PackedInt32Array = _tx1 if f.side == 0 else _tx0   # the candidates' cells (packed copy)
	var ys: PackedInt32Array = _ty1 if f.side == 0 else _ty0
	for i in cands.size():
		var dd := maxi(absi(xs[i] - fx), absi(ys[i] - fy))
		dists[i] = dd
		dmin = mini(dmin, dd)
	var cutoff := float(dmin) + Formulas.TARGET_NOISE
	for i in cands.size():
		var dd := float(dists[i])
		if dd > cutoff:
			continue
		var e: Fighter = cands[i]
		if not e.alive() or e.state == "fled":
			continue
		var s := dd + Formulas.roll_target_noise(rng)
		if e.routed:
			s += Formulas.TARGET_ROUTED_PENALTY
		if e.state == "unconscious":
			s += Formulas.TARGET_HELPLESS_PENALTY
		if s < best_score:
			best_score = s
			best = e.idx
	f.target = best

func _move_toward(f: Fighter, goal: Vector2i) -> void:
	var fc := f.cell
	var cur_d := _dist(fc, goal)
	var cur_e := _d2(fc, goal)
	var best := Vector2i(-1, -1)
	var best_score := INF
	for n in NEIGHBORS:
		var p: Vector2i = fc + n
		# perf (same result): the cheap distance filter first, inline bounds/tile/occupancy, then the corner check
		var gx := absi(p.x - goal.x)
		var gy := absi(p.y - goal.y)
		var dd := maxi(gx, gy)
		var de := gx * gx + gy * gy
		if dd > cur_d or (dd == cur_d and de >= cur_e):
			continue
		if p.x < 0 or p.y < 0 or p.x >= grid_w or p.y >= grid_h:
			continue
		var ci := p.y * grid_w + p.x
		if tiles[ci] == T_BLOCKED or occ[ci] != -1 or not _diag_ok(fc, p):
			continue
		var sc := dd * 1000.0 + de + (500.0 if tiles[ci] == T_ROUGH else 0.0)
		if sc < best_score:
			best_score = sc
			best = p
	if best.x < 0:
		f.wait_count += 1
		if f.wait_count % 4 == 0:
			f.target = -1  # blocked: look for someone else next time
		_set_action(f, _idle_state(f), _ticks(f, 3.0))
		return
	f.wait_count = 0
	_do_move(f, best)

func _do_move(f: Fighter, p: Vector2i) -> void:
	if f.stumble_p > 0.0:
		var sr := Formulas.roll_stumble(rng, f.stumble_p)
		if sr["ok"]:
			# too drunk: stumbles over his own feet and loses this move
			_compute_tempo(f)
			var lost_mt := Formulas.move_ticks(f.speed, _terrain_mult, f.prone) * f.walk_mult
			_set_action(f, _idle_state(f), _ticks(f, lost_mt))
			f.unit.body.exertion += Formulas.exertion_move(_eff_mass(f), f.unit.attr("END"), f.breath_bad) * f.fatigue_mult
			_ev_simple("stumble", f.idx, -1, "food_stumble", _food_params(f, {"roll": sr}))
			return
	if f.grabbing >= 0:
		_release_grab(f)
	var pci := p.y * grid_w + p.x   # = _ci(p)
	var from := f.cell
	if f.standing():
		occ[from.y * grid_w + from.x] = -1
		occ[pci] = f.idx
	f.prev_cell = from
	f.cell = p
	if _tcells_ok:   # keep the packed target cells current (or drop them if this fighter is not where tslot says)
		var tg: Array = _targets[f.side]
		var ts := f.tslot
		if ts >= 0 and ts < tg.size() and is_same(tg[ts], f):
			if f.side == 0:
				_tx0[ts] = p.x
				_ty0[ts] = p.y
			else:
				_tx1[ts] = p.x
				_ty1[ts] = p.y
		else:
			_tcells_ok = false
	f.last_move_tick = tick
	if _bows_down > 0:   # bows: a dropped bow under foot may be trampled
		Archery.trample(self, f, p)
	if p.x != from.x:
		f.facing = 1 if p.x > from.x else -1
	_compute_tempo(f)
	var tm := _terrain_mult * (Formulas.ROUGH_MOVE_MULT if tiles[pci] == T_ROUGH else 1.0)
	var mt := Formulas.move_ticks(f.speed, tm, f.prone) * f.walk_mult
	var ticks := _ticks(f, mt)
	_set_action(f, "moving", ticks)
	f.unit.body.exertion += Formulas.exertion_move(_eff_mass(f), f.unit.attr("END"), f.breath_bad) * f.fatigue_mult
	if f.armor_mass > 5.0:
		Learning.note_use(f.attr_use, "march", 0.1)
	if f.belly_state == "starving" or f.belly_state == "hungry":
		_food_gasp(f)
	_event("move", f.idx, -1, "", false)
	if log_moves:
		_log(f, "move", {"al": f.label, "x": p.x, "y": p.y, "mt": mt, "ticks": ticks, "sp": f.speed_info, "tm": tm, "prone": f.prone, "run": f.routed, "wk": f.walk_mult})

func _flee_step(f: Fighter) -> void:
	var edge_x := 0 if f.side == 0 else grid_w - 1
	if f.cell.x == edge_x:
		f.state = "fled"
		if occ[_ci(f.cell)] == f.idx:
			occ[_ci(f.cell)] = -1
		_ev_simple("flee", f.idx, -1, "flee", {})
		return
	var fc := f.cell
	var cur := absi(fc.x - edge_x)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	# perf (same result): the cheap edge-distance filter first, then the inlined passable/occupancy tests, corners last
	for n in NEIGHBORS:
		var p: Vector2i = fc + n
		var ax := absi(p.x - edge_x)
		if ax >= cur:
			continue
		var dd := ax * 10 + absi(n.y)
		if dd >= best_d:
			continue
		if p.x < 0 or p.y < 0 or p.x >= grid_w or p.y >= grid_h:
			continue
		var ci := p.y * grid_w + p.x
		if tiles[ci] == T_BLOCKED or occ[ci] != -1 or not _diag_ok(fc, p):
			continue
		best = p
		best_d = dd
	if best.x < 0:
		for n in NEIGHBORS:  # sidestep
			var p: Vector2i = fc + n
			if absi(p.x - edge_x) == cur and _passable(p) and occ[_ci(p)] == -1 and _diag_ok(fc, p):
				best = p
				break
	if best.x < 0:
		_set_action(f, _idle_state(f), _ticks(f, 3.0))
		return
	_do_move(f, best)

# ---------------------------------------------------------------- tempo and condition
func _eff_mass(f: Fighter) -> float:
	return Formulas.effective_gear_mass(f.armor_mass, f.other_mass, f.unit.skill("armor_user"))

func _enc_ratio(f: Fighter) -> float:
	return Formulas.encumbrance_ratio(_eff_mass(f), f.unit.attr("STR"), f.unit.mass())

func _ex_ratio(f: Fighter) -> float:
	var u := f.unit
	return u.body.exertion / maxf(100.0, float(u.attr("END")))

func _blood_frac(f: Fighter) -> float:
	var b := f.unit.body
	return b.blood / maxf(1.0, b.blood_max)

## Tempo is cached for TEMPO_CACHE_TICKS (exertion/pain/blood drift slowly); wounds and routs invalidate it.
func _compute_tempo(f: Fighter) -> void:
	if tick - f.tempo_tick < Formulas.TEMPO_CACHE_TICKS:
		return
	f.tempo_tick = tick
	var u := f.unit
	var gait := f.gait
	if f.routed:
		var gaits: Array = f.rdef.get("gait", Formulas.GAIT_DEFAULT)
		gait = float(gaits[mini(Formulas.GAIT_INDEX_FLEE, gaits.size() - 1)])
	var b := u.body   # perf: _blood_frac / _ex_ratio inlined (same expressions)
	f.speed_info = Formulas.tempo_breakdown(gait, u.attr("AGI"), _enc_ratio(f), f.leg_impair, b.pain,
		b.blood / maxf(1.0, b.blood_max), b.exertion / maxf(100.0, float(u.attr("END"))))
	f.speed = f.speed_info["speed"]
	f.tempo = f.speed_info["tempo"]

# ---------------------------------------------------------------- food and drink (core/food.gd)
## Caches the unit's belly/buzz effects on the fighter (setup, and when the buzz drops into another state).
func _food_refresh(f: Fighter) -> void:
	var u := f.unit
	f.belly_state = Food.belly_state(u.belly)
	f.buzz_state = Food.buzz_state(u.buzz)
	f.fatigue_mult = Food.fatigue_mult(u)
	f.focus_mult = 1.0 + Food.focus(u)
	f.pain_tol = Food.pain_tolerance(u)
	f.walk_mult = Food.walk_mult(u)
	f.stumble_p = Food.stumble_chance(u)
	f.buzz_floor = {"hammered": Food.HAMMERED, "drunk": Food.DRUNK, "tipsy": Food.TIPSY}.get(f.buzz_state, -1.0)

func _food_params(f: Fighter, extra: Dictionary = {}) -> Dictionary:
	var d := {"belly": f.unit.belly, "buzz": f.unit.buzz, "bs": f.belly_state, "zs": f.buzz_state, "hung": f.unit.hungover,
		"fat": f.fatigue_mult, "foc": f.focus_mult, "tol": f.pain_tol}
	d.merge(extra, true)
	return d

## A log-only line (no event) about the fighter's food/drink state, built from the real numbers.
func _food_line(f: Fighter, key: String, extra: Dictionary = {}) -> void:
	var params := _food_params(f, extra)
	params["key"] = key
	params["al"] = f.label
	params["vk"] = f.voff
	var ck := "ev:" + key
	params["vc"] = int(f.vcount.get(ck, 0))
	f.vcount[ck] = int(params["vc"]) + 1
	_log(f, "ev", params)

## Hungry or starving men run out of wind: said once, when exertion first passes a third of END.
func _food_gasp(f: Fighter) -> void:
	if f.food_said & 1 == 0 and _ex_ratio(f) >= 0.35:
		f.food_said |= 1
		_food_line(f, "food_gasp_" + f.belly_state)

## First line of the battle for anyone whose belly or buzz shows (most notable state only).
func _food_start_line(f: Fighter) -> void:
	if not f.alive():
		return
	var key := ""
	if f.buzz_state == "hammered": key = "hammered"
	elif f.belly_state == "starving": key = "starving"
	elif f.buzz_state == "drunk": key = "drunk"
	elif f.unit.hungover: key = "hungover"
	elif f.belly_state == "hungry": key = "hungry"
	elif f.buzz_state == "tipsy": key = "tipsy"
	elif f.belly_state == "stuffed": key = "stuffed"
	if key != "":
		_food_line(f, "food_start_" + key)

func _cond(f: Fighter) -> float:
	var u := f.unit   # perf: _ex_ratio / _blood_frac inlined (same expressions)
	var b := u.body
	return Formulas.condition_mult(b.pain, b.exertion / maxf(100.0, float(u.attr("END"))), b.blood / maxf(1.0, b.blood_max))

## Effective level for a check (survey item 2).
func _eff(f: Fighter, skill: String, check: String) -> float:
	var u := f.unit
	var e := Formulas.effective_level(u.skill(skill), _alv(f, check), u.skill("fighter"), _cond(f))
	if f.blind:
		e -= Formulas.BLIND_SKILL_PEN
	return maxf(0.0, e * f.focus_mult * (Formulas.PRONE_SKILL_MULT if f.prone else 1.0))

## Formulas.attr_levels(check, unit.eff_attrs()), cached per fighter (cleared whenever the food multipliers change).
func _alv(f: Fighter, check: String) -> float:
	var v = f.alv.get(check)
	if v == null:
		v = Formulas.attr_levels(check, f.unit.eff_attrs())
		f.alv[check] = v
	return v

## Item.tmpl() (the DB template dictionary itself), cached per item for this battle (an item's template id is fixed).
func _tmpl(it: Item) -> Dictionary:
	var t = _itmpl.get(it)
	if t == null:
		t = it.tmpl()
		_itmpl[it] = t
	return t

## Unit.shield() with the weapon test cached per item (same result: the off-hand item unless it is a weapon).
func _shield(u: Unit) -> Item:
	var it: Item = u.equip.get("off_hand", null)
	if it == null:
		return null
	var w = _isw.get(it)
	if w == null:
		w = it.is_weapon()
		_isw[it] = w
	return null if w else it

## Item.display_name(), cached per item for this battle (material, template and quality never change mid-battle).
func _item_name(it: Item) -> String:
	var n = _iname.get(it)
	if n == null:
		n = it.display_name()
		_iname[it] = n
	return n

func _has_weapon(f: Fighter) -> bool:
	return f.wielded != null and not f.weapon_dropped

func _weapon_skill_name(f: Fighter) -> String:
	if _has_weapon(f):
		return String(_tmpl(f.wielded).get("skill", "fighter"))
	return "brawler"

func _use(f: Fighter, skill: String, mult: float = 1.0) -> void:
	Learning.note_use(f.attr_use, skill if Learning.ATTR_LINKS.has(skill) else "weapon", mult)

## Relative position of attacker a seen from defender d: "front" | "side" | "rear".
func _rel(a: Fighter, d: Fighter) -> String:
	var dx := a.cell.x - d.cell.x
	if dx == 0:
		return "side"
	return "front" if signi(dx) == d.facing else "rear"

# =====================================================================================================
# Attacks
# =====================================================================================================
func _attacks_of(f: Fighter, dist: int) -> Array:
	if not _has_weapon(f):
		if f.creature:   # monsters wave 1: bite / claw / gore / charge from data
			return NaturalAttacks.attacks_for(self, f, fighters[f.target] if f.target >= 0 else null)
		return [_natural_attack(f, fighters[f.target] if f.target >= 0 else null)]
	var t := _tmpl(f.wielded)
	var all: Array = t.get("attacks", [])
	if all.is_empty():
		return [Formulas.NATURAL["punch"]]
	# O5: inside its minimum reach a long polearm hits with the haft.
	if dist <= 1 and float(t.get("reach", 80)) >= Formulas.POLEARM_MIN_REACH:
		var haft := all.filter(func(a): return a.get("type", "") == "blunt")
		if not haft.is_empty():
			return haft
	return all

## Unarmed pick rule (survey addendum): bite if the race has it and the target is grabbed; helpless target -> kick;
## kick if STR >= 1200; otherwise punch.
func _natural_attack(f: Fighter, t: Fighter) -> Dictionary:
	var nat: Dictionary = f.rdef.get("natural_attacks", {})
	if t != null and nat.has("bite") and f.grabbing == t.idx and _part_ok(f, "head"):
		return Formulas.NATURAL["bite"]
	var legs_ok := (_part_ok(f, "foot_r") or _part_ok(f, "foot_l")) and not f.prone
	if t != null and t.helpless() and legs_ok:
		return Formulas.NATURAL["kick"]
	var hands_ok := (_part_ok(f, "hand_r") or _part_ok(f, "hand_l")) and f.grabbing < 0
	if f.unit.attr("STR") >= Formulas.KICK_STR_MIN and legs_ok:
		return Formulas.NATURAL["kick"]
	if hands_ok or not legs_ok:
		return Formulas.NATURAL["punch"]
	return Formulas.NATURAL["kick"]

func _part_ok(f: Fighter, pid: String) -> bool:
	return f.unit.body.has_part(pid) and not f.lost.has(pid)

func _is_thrust(atk: Dictionary) -> bool:
	return atk.get("type", "") == "edge" and float(atk.get("contact", 1000)) <= Formulas.PIERCE_CONTACT

## Deterministic swing/thrust solution for an attack (before the strike-quality roll).
func _swing_for(f: Fighter, atk: Dictionary) -> Dictionary:
	var u := f.unit
	var strength := (u.combat_strength() if f.dragon else float(u.attr("STR"))) * clampf(_blood_frac(f) / Formulas.BLOOD_WEAK, 0.5, 1.0)
	if f.rage_ticks > 0:
		strength *= Formulas.RAGE_TORQUE
	if atk.get("creature", false):   # monsters wave 1
		var cs := NaturalAttacks.swing(f, atk, strength, _ex_ratio(f))
		cs["str"] = strength
		cs["grip"] = 1.0
		return cs
	if atk.has("p") and not _has_weapon(f):
		var slot: String = atk.get("gear_slot", "")
		var gear := 0.0
		if slot != "" and u.equip.has(slot):
			gear = (u.equip[slot] as Item).mass() * 0.5
		var rm := 1.0
		if atk["verb"] == "bite":
			rm = float(f.rdef.get("natural_attacks", {}).get("bite", 1.0))
		var ns := Formulas.natural_swing(String(atk["verb"]), strength, u.mass(), float(u.skill("brawler")), gear, rm, _ex_ratio(f), u.body.pain)
		ns["str"] = strength
		ns["grip"] = 1.0
		return ns
	var w: Item = f.wielded
	# perf (same values): template, head/haft mass and geometry depend only on the item; cached per battle
	var wg = _wgeo.get(w)
	if wg == null:
		var t0 := _tmpl(w)
		var dens := float(w.mat().get("density", 8930))
		var head0 := float(t0.get("head_cm3", 0)) * dens / 1.0e6
		var haft0 := float(t0.get("haft_kg", 0.0))
		wg = [t0, head0, haft0, Formulas.weapon_geometry(t0, head0, haft0)]
		_wgeo[w] = wg
	var t: Dictionary = wg[0]
	var head: float = wg[1]
	var haft: float = wg[2]
	var geo: Dictionary = wg[3]
	var skill := float(u.skill(String(t.get("skill", "fighter")) if _has_weapon(f) else "brawler"))   # = _weapon_skill_name(f)
	var grip := Formulas.GRIP_1H
	var hold := f.grip_r   # v0.013 fingers: share of the hand's fingers (by DF relative size) still able to close
	if t.get("two_handed", false):
		grip = Formulas.GRIP_2H_ONE_HAND if f.shield_dropped else Formulas.GRIP_2H
		if not f.shield_dropped:
			hold = (f.grip_r + f.grip_l) * 0.5
	grip *= hold
	var umass := u.mass()
	var tau := Formulas.torque(strength, umass, grip, skill, _ex_ratio(f), u.body.pain)
	var thrust := _is_thrust(atk)
	var theta := Formulas.THETA_THRUST if thrust else Formulas.THETA_NORMAL
	var sw := Formulas.swing(umass, float(u.arm_len), tau, theta, head + haft, geo, thrust, float(atk.get("vel", 1.0)),
		float(t.get("drag", 1.0)), u.attr("AGI"), skill)
	sw["grip"] = grip
	sw["str"] = strength
	return sw

func _start_attack(f: Fighter, t: Fighter) -> void:
	var attacks := _attacks_of(f, _dist(f.cell, t.cell))
	if f.dragon and attacks.is_empty():
		_set_action(f, _idle_state(f), _ticks(f, 3.0))
		return
	var ch := Formulas.roll_attack_choice(rng, attacks) if attacks.size() > 1 else {}
	var atk: Dictionary = attacks[ch["i"]] if not ch.is_empty() else attacks[0]
	_compute_tempo(f)
	var sw := _swing_for(f, atk)
	var prep_raw: float = sw["prep_ticks"]
	var prep := _ticks(f, prep_raw)
	var rec_raw := Formulas.recover_ticks(float(atk.get("rec", 3)), f.tempo)
	f.pending_attack = {"atk": atk, "target": t.idx, "rec_raw": rec_raw, "swing": sw,
		"pre": {"ch": ch, "prep": prep, "prep_raw": prep_raw, "rec_raw": rec_raw, "rec": int(atk.get("rec", 3)), "tempo": f.tempo, "sp": f.speed_info}}
	f.pending_action = {}
	f.current_attack = String(atk.get("verb", "attack"))
	f.target = t.idx
	_set_action(f, "preparing", prep)
	_event("prepare", f.idx, t.idx, "", false)

func _deliver(f: Fighter) -> void:
	var pa := f.pending_attack
	var rec := _ticks(f, float(pa.get("rec_raw", 4.5)))
	var ti := int(pa.get("target", -1))
	var t: Fighter = fighters[ti] if ti >= 0 else null
	if t != null and t.alive() and t.state != "fled" and _in_reach(f, t) and f.lodged.is_empty():
		_event("attack", f.idx, t.idx, "", false)
		_strike(f, t, pa["atk"], pa["swing"], pa.get("pre", {}))
		if pa["atk"].get("creature", false):
			NaturalAttacks.after_strike(self, f, t, pa["atk"])   # monsters wave 1: latch, charge run-up spent
	else:
		_log(f, "ev", {"key": "notarget", "al": f.label, "v": f.current_attack, "vk": f.voff, "vc": 0})
	if f.state == "preparing":
		_set_action(f, "recovering", rec)

## Inspection/test hook: fighter `ai` strikes fighter `di` right now with attack `attack_idx` of its weapon
## (-1 = rolled), on `part_id` ("" = rolled), skipping the defence contest when `land` is true.
## Uses sim.rng like any strike (coverage, strike quality ...). Returns last_strike.
func debug_strike(ai: int, di: int, part_id: String = "", attack_idx: int = -1, land: bool = true) -> Dictionary:
	var a: Fighter = fighters[ai]
	var d: Fighter = fighters[di]
	a.target = di
	var attacks := _attacks_of(a, 1)
	var atk: Dictionary = attacks[attack_idx] if attack_idx >= 0 and attack_idx < attacks.size() else attacks[Formulas.roll_attack_choice(rng, attacks)["i"]]
	_force_part = part_id
	_force_land = land
	_strike(a, d, atk, _swing_for(a, atk), {})
	_force_part = ""
	_force_land = false
	return last_strike

func _strike(a: Fighter, d: Fighter, atk: Dictionary, sw: Dictionary, pre: Dictionary) -> void:
	var V := verbose
	var steps := []
	var au := a.unit
	var du := d.unit
	# perf (same results): one weapon template lookup per strike (= _weapon_skill_name / w_item.tmpl())
	var shot := _shot   # bows: an arrow (sim/archery.gd) when not empty; every shot branch below is arrow-only
	var arrow := not shot.is_empty()
	var w_item: Item = a.wielded if _has_weapon(a) and not arrow else null
	var wt: Dictionary = _tmpl(w_item) if w_item != null else {}
	var wskill: String = String(wt.get("skill", "fighter")) if w_item != null else ("bow" if arrow else "brawler")
	var natural := w_item == null and not arrow
	var verb := String(atk.get("verb", "attack"))
	var edged0: bool = atk.get("type", "blunt") == "edge"
	var thrust := _is_thrust(atk)
	var D := {"a": a.idx, "d": d.idx, "al": a.label, "dl": d.label, "w": _item_name(w_item) if w_item != null else "",
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
		_say(a, d, "cry")
	last_strike = {"attacker": a.idx, "defender": d.idx, "verb": verb, "landed": false, "part": "", "armor": [], "tissue": [],
		"p": 0.0, "E": 0.0, "q": 0.0, "severed": false, "artery": false, "glanced": false, "defence": "", "lodged": false}
	if V and not pre.is_empty():
		steps.append(["pre", pre])
	var helpless := d.helpless()
	var rel := _rel(a, d) if not arrow else String(shot["rel"])
	d.last_hit_rel = rel
	var att := _eff(a, wskill, "hit") if not arrow else float(shot["att"])
	if w_item != null:
		att += (DB.quality_mult(w_item.quality) - 1.0) * Formulas.QUALITY_HIT_LEVELS
		if float(wt.get("reach", 80)) < 60.0 and _dist(a.cell, d.cell) <= 1:
			att += Formulas.SHORT_BLADE_CLOSE_BONUS
	if rel != "front":
		att += Formulas.REAR_ATT_BONUS - 0.25 * du.skill("observer")
	if not arrow:   # bows: the draw's exertion, XP and attribute use were paid when the arrow was loosed
		au.body.exertion += Formulas.exertion_swing(float(sw["E"]), au.attr("END"), a.breath_bad) * a.fatigue_mult
		if a.buzz_state == "drunk" or a.buzz_state == "hammered":
			if a.swing_count % 5 == 1:
				_food_line(a, "food_swing", {"dl": d.label})
		elif a.belly_state == "starving" or a.belly_state == "hungry":
			_food_gasp(a)
		_learn(a, wskill, Learning.XP_SWING)
		_learn(a, "fighter", Learning.XP_FIGHTER)
		_use(a, wskill)
		_use(a, "fighter", 0.5)
	d.last_attacked_tick = tick
	if V:
		if arrow:
			steps.append(["shot", shot])
		steps.append(["att", wskill, au.skill(wskill), att, _alv(a, "hit" if not arrow else "aim"), au.skill("fighter"), _cond(a), rel, a.prone and not arrow])
	# ---- one defence per attack (survey item 1)
	if arrow:
		# bows: dodge, then shield (x2 vs projectiles), then armour; no parrying arrows (sim/archery.gd)
		if not helpless and not _force_land and Archery.defend(self, a, d, D, steps, att, rel):
			return
	elif _force_land:
		if V: steps.append(["help", "forced"])
	elif helpless:
		if V: steps.append(["help", "unconscious" if d.state == "unconscious" else "prone"])
	else:
		var seen := true
		if rel != "front":
			var sr := Formulas.roll_spot(rng, Formulas.spot_chance(rel == "rear", du.skill("observer"), _alv(d, "spot")))
			if V: steps.append(sr)
			seen = sr["ok"]
			if tick - d.last_flank_tick >= Formulas.FLANK_SHOCK_COOLDOWN:
				d.last_flank_tick = tick
				_shock(d, Formulas.SHOCK_FLANKED, "flanked", false)
		if seen:
			var kind := ""
			var def := 0.0
			var ds := ""
			var sh := _shield(du)
			if sh != null and not d.shield_dropped and d.grabbed_by < 0 and not d.bow_hand and (rel == "front" or (rel == "side" and du.skill("observer") >= Formulas.OBSERVER_ARC_LEVEL)):
				kind = "block"
				def = _eff(d, "shield_user", "block") + Formulas.DEF_BASE["block"] * float(_tmpl(sh).get("block", 1.0))
			elif _has_weapon(d) and d.lodged.is_empty() and d.grabbed_by < 0 and not d.bow_hand:   # bows: a bow in the hands parries nothing
				kind = "parry"
				var dwt: Dictionary = _tmpl(d.wielded)
				ds = String(dwt.get("skill", "fighter"))   # = _weapon_skill_name(d): d holds a weapon here
				var dsw := float(dwt.get("reach", 80)) / 100.0
				def = _eff(d, ds, "parry") + Formulas.PARRY_LEN_LEVELS * (dsw - 0.8) - Formulas.PARRY_P_LEVELS * maxf(0.0, float(sw["p"]) - 20.0) / 20.0 \
					+ (float(dwt.get("parry", 0.5)) - 0.5) * 4.0
			elif d.grabbed_by < 0:
				kind = "dodge"
				var enc := _enc_ratio(d) * (1.0 - minf(0.75, du.skill("armor_user") * Formulas.ARMOR_USER_RELIEF))
				def = _eff(d, "dodger", "dodge") - Formulas.DODGE_ENC_LEVELS * enc
			if kind != "":
				var p_through := Formulas.contest_through(att, def)
				var recent := 0
				for t0 in d.defence_ticks:
					if tick - int(t0) <= Formulas.SATURATION_WINDOW:
						recent += 1
				var sat := Formulas.saturation(recent)
				var p_def := maxf(0.0, 1.0 - p_through - sat)
				if d.rage_ticks > 0 and kind != "block":
					p_def *= Formulas.RAGE_DEF_MULT
				if kind == "dodge" and _held_in_place(d):
					p_def *= Formulas.HELD_VICTIM_DODGE
				if kind == "dodge" and not d.lodged.is_empty():
					p_def *= Formulas.HELD_WIELDER_DODGE
				var cr := Formulas.roll_contest(rng, 1.0 - p_def, kind)
				if V:
					steps.append(["def", kind, def, p_through, sat, 1.0 - p_def, recent])
					steps.append(cr)
				d.defence_ticks.append(tick)
				if d.defence_ticks.size() > 8:
					d.defence_ticks.pop_front()
				du.body.exertion += Formulas.exertion_defend(du.attr("END"), d.breath_bad) * d.fatigue_mult
				var sk: String = "shield_user" if kind == "block" else (ds if kind == "parry" else "dodger")
				if not cr["ok"]:
					_learn(d, sk, Learning.XP_DEFEND)
					_learn(d, "fighter", Learning.XP_FIGHTER)
					_use(d, sk)
					D["out"] = kind
					D["def"] = kind
					D["sh"] = _item_name(sh) if kind == "block" else ""
					D["dw"] = _item_name(d.wielded) if kind == "parry" else ""
					last_strike["defence"] = kind
					_strike_end(a, d, D, kind, "", false)
					return
				_learn(d, sk, Learning.XP_DEFEND_TRY)
		elif V:
			steps.append(["note", "attack from the %s unseen: no defence" % rel])
	_learn(a, wskill, Learning.XP_HIT)
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
		_strike_end(a, d, D, "miss", "", false)
		return
	var part_id: String = _force_part
	var force_inner := ""
	if part_id == "":
		var prr := Formulas.roll_body_part(rng, ws, names)
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
		var q_level := float(au.skill(wskill)) + _alv(a, "quality")
		var sq := Formulas.roll_strike_quality(rng, q_level, au.attr("KIN"))
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
		last_strike["dragon_attack"] = provenance.duplicate(true)
	var sharp := Formulas.sharpness(float(wmat.get("max_edge", 10000)))
	var budget := pen_mm * q * sharp if edged else 0.0  # a dull (tin) edge cuts shallower (tuned)
	# v0.014 gear damage: a chipped edge (Item.dull) cuts less and shallower; the head is tested for bends/snaps
	# only when the blow is struck with it (not a pommel or shaft bash)
	var gear_w := gear_wear and w_item != null and not arrow and not natural and _head_blow(verb, wt)
	if w_item != null and w_item.dull > 0.0 and edged:
		var dk := 1.0 - Formulas.DULL_EDGE_K * w_item.dull
		budget *= dk
		qw *= dk
	if V:
		steps.append(["q", q, p, energy, D["w"] if headed else verb, wmat.get("name", "?"), qw,
			sharp, atk.get("type", "blunt"), contact, budget, edged])
	var p_impact := p
	last_strike["landed"] = true
	last_strike["part"] = part_id
	last_strike["p"] = p
	last_strike["E"] = energy
	last_strike["q"] = q
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
		var cr := Formulas.roll_coverage(rng, item["name"], cv)
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
				last_strike["armor"].append({"name": nm, "result": "cut"})
				# v0.014: the edge went through: a point punctures (a hole), a cutting edge splits the piece (broken)
				_armor_dmg(item, "punctured" if contact <= Formulas.PIERCE_CONTACT else "split", D, steps)
				continue
			edged = false
			stop_item = nm
			if V: steps.append(["ae", nm, th, energy, R, false, energy, p, budget])
			if gear_w:
				_gear_chip(w_item, mat, wmat, nm, true, D, steps)
		if headed and Formulas.blunt_deflects(w_size, wmat, contact, mat):
			if V: steps.append(["ad", nm, w_size, float(wmat.get("impact_yield", 0)), contact, float(mat.get("density", 0))])
			glanced = true
			D["armor"].append([nm, "glance"])
			last_strike["armor"].append({"name": nm, "result": "glance"})
			p = 0.0
			break
		var Rb := Formulas.blunt_resistance(mat, contact, qa, th, "armor")
		var p1 := p
		if p >= Rb:
			p *= Formulas.PASS_KEEP
			if V: steps.append(["ab", nm, p1, Rb, true, "", 1.0, p])
			D["armor"].append([nm, "dented", String(mat.get("kind", ""))])
			last_strike["armor"].append({"name": nm, "result": "dented"})
			# v0.014: forced through (the fracture form): plate cracks, scale/lamellar shatters (broken); mail rings burst,
			# cloth and leather tear (a hole). The weapon met a layer that gave way at Rb.
			_armor_dmg(item, "cracked" if item["rigid"] else ("shattered" if item["semi"] else ("burst" if String(mat.get("kind", "")) == "metal" else "torn")), D, steps)
			if gear_w:
				_gear_bend(a, w_item, wt, wmat, contact, Rb, nm, true, D, steps)
		else:
			var tr := Formulas.armor_transmit(item["rigid"], item["semi"], item["padded"])
			p *= tr
			if V: steps.append(["ab", nm, p1, Rb, false, "rigid" if item["rigid"] else ("semi-rigid" if item["semi"] else ("padded" if item["padded"] else "flexible")), tr, p])
			D["armor"].append([nm, "held"])
			last_strike["armor"].append({"name": nm, "result": "held"})
			# v0.014: held, but past the metal's yield: a plate or lame is dented (a quality step; mail and cloth flex);
			# the weapon took the whole blow back
			if (item["rigid"] or item["semi"]) and String(mat.get("kind", "")) == "metal" and p1 >=Formulas.yield_resistance(mat, contact, qa, th):
				_armor_dmg(item, "dented", D, steps)
			if gear_w:
				_gear_bend(a, w_item, wt, wmat, contact, p1, nm, true, D, steps)
	if covering.size() > 0:
		_learn(d, "armor_user", Learning.XP_ARMOR_HIT)
		_use(d, "armor_user")
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
	var ls_tissue: Array = last_strike["tissue"]
	var wf := -1.0                   # Formulas.width_factor(contact), computed on first use
	_bleed_defer = d                 # one bleed recount for the defender after the layers and the sever (same totals)
	var inner_info: Array = _inner_of(body, part_id, pdef)   # [ids, weights, names, connector id, under-pressure id]
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
		var ldm := _ldef_map(seg_pid, seg_def)
		var numb := bool(body.part(seg_pid).get("nerve_s", false))   # sensory nerve severed: no pain from this part
		for i in layers.size():
			var L: Dictionary = layers[i]
			var tissue: String = L["tissue"]
			var lname: String = L.get("name", tissue)
			var ld: Dictionary = ldm.get(lname, {})
			if ld.has("hit"):
				var ir := Formulas.roll_inner_layer(rng, lname, float(ld["hit"]))
				if V: steps.append(ir)
				if not ir["ok"]:
					continue
			if p < 0.2 and energy < 1.0:
				if V: steps.append(["note", "nothing left of the blow"])
				cut_all = false
				spent = true
				break
			reached = true
			var tmat: Dictionary = _tmat(String(ld.get("mat", tissue)))
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
						var ar := Formulas.roll_artery(rng, lname, clampf(Formulas.ARTERY_CHANCE * frac * (1.5 if thrust else 1.0) * (2.5 if ld.get("major", false) or tissue == "vessel" else 1.0), 0.0, 0.95))
						if V: steps.append(ar)
						if ar["ok"]:
							if not stored:
								layers = body.wound_part(seg_pid)["layers"]
								stored = true
								L = layers[i]
							var ab := float(ld["artery"]) * Formulas.BLEED_ARTERY_MULT * tou
							_add_bleed(d, seg_pid, L, ab, Formulas.CLOT_ARTERY)
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
						_gear_chip(w_item, tmat, wmat, _bone_word(lname, seg_def, seg_pid), false, D, steps)
			if not was_edge:
				cut_all = false
				if tissue == "bone":
					if seg_pid == "skull":
						skull_p = p
					var Rb := Formulas.blunt_resistance(tmat, contact, 1.0, th, "bone")
					var p0 := p
					if gear_w and seg_n == 0:   # v0.014: the bone pushes back on the head with min(p, what it takes)
						_gear_bend(a, w_item, wt, wmat, contact, minf(p0, Rb), _bone_word(lname, seg_def, seg_pid), false, D, steps)
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
			var pr := _wound_core(d, seg_pid, seg_def, L, ld, dmg, kind, was_edge, through, tou, d_funcs)
			if not numb:
				pain_raw += pr
			bleed_add += _wl_bleed
			if _wl_death != "":
				death_cause = _wl_death
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
					var irr := Formulas.roll_inner_part(rng, inner_info[1], inner_info[2])
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
		var aev := _event("artery", a.idx, d.idx, "", true, part_id)
		aev["rate"] = art_rate
		aev["text"] = CombatText.decisive("artery", {"D": _cap(d.label), "d": d.label, "P": D["pname"], "RATE": "%.2f" % art_rate,
			"his": d.pron, "ART": D.get("artname", "artery")}, art_rate, a.voff + tick)
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
		_add_bleed(d, part_id, sp["layers"][0], sb, Formulas.CLOT_ARTERY)
		bleed_add += sb
		pain_raw += Formulas.PAIN_SEVER
		body.permanent.append("lost %s" % part_name)
		if V: steps.append(["sever", p, need_p, sb])
		D["sever"] = true
		if part_id == "neck" or part_id == "head" or _has_vital(pdef):
			death_cause = "decapitated" if part_id in ["head", "neck"] else "lost a vital part"
	_bleed_defer = null
	if _bleed_dirty:
		_bleed_dirty = false
		_recount_bleed(d)
	# cut path (from the swing actually made: hack = overhead, slash = forehand/backhand diagonal, thrust = straight)
	if edged0 and layers_cut > 0:
		D["path"] = _cut_path(a, verb, thrust)
	# ---- stuck weapon (survey lodge rules): edged attack reached muscle and stopped inside the body
	if edged0 and w_item != null and not w_item.broken and not severed and stopped_in != "" and layers_cut > 0 and death_cause == "" and _reached_muscle(D):
		var base := Formulas.lodge_base(verb, thrust)
		var ch := base * clampf(depth_used / maxf(1.0, pen_mm), 0.0, 1.0) * (Formulas.LODGE_BONE_MULT if stopped_by_bone else 1.0) \
			* float(wt.get("lodge", 1.0))
		var lr := Formulas.roll_lodge(rng, ch)
		if V: steps.append(lr)
		if lr["ok"]:
			a.lodged = {"victim": d.idx, "part": stopped_part, "layer": stopped_in, "p0": p_impact, "layers": layers_cut, "item": w_item}
			d.stuck_in_me.append({"wielder": a.idx, "item": w_item, "part": stopped_part, "layers": layers_cut})
			D["lodged"] = true
			last_strike["lodged"] = true
	if arrow:
		# bows: an arrow lodges on any penetration [DF] (no roll); with energy to spare after the last layer it
		# comes out the other side (exit wound) and flies on
		var exits := cut_all and reached and layers_cut > 0 and energy >= Formulas.ARROW_EXIT_MIN_J
		var lodge_layer := stopped_in
		var lodge_part := stopped_part
		if lodge_layer == "" and layers_cut > 0 and not exits and d_layers.size() > 0:
			lodge_layer = String(d_layers[-1][0])
			lodge_part = String(ls_tissue[-1]["part"])
		_shot_out = {"exit": exits, "E": energy, "end": "armor" if layers_cut == 0 else ("" if exits else "body")}
		if exits:
			D["exit"] = true
			if V: steps.append(["note", "the arrow passes clean through with %.1f J left and flies on" % energy])
		elif layers_cut > 0 and lodge_layer != "":
			d.arrows_in.append({"kind": shot["kind"], "part": lodge_part, "layer": lodge_layer})
			D["lodged"] = true
			last_strike["lodged"] = true
	# ---- pain, stagger, consequences
	var pm := Formulas.pain_mult(du.attr("WIL"), du.attr("END"), du.skill("discipline")) / d.pain_tol   # drink raises pain tolerance (Food)
	var pain_eff := pain_raw * pm
	if d.pain_tol >= 1.2 and pain_eff >= 10.0 and tick - d.food_pain_tick >= 100 and d.alive():
		d.food_pain_tick = tick
		_food_line(d, "food_pain", {"pain": pain_eff, "tol": d.pain_tol})
	body.pain += pain_eff
	d.tempo_tick = -1000
	d.pain_floor_src += pain_eff
	if pain_eff > 0.0:
		Learning.note_use(d.attr_use, "pain", pain_eff / 50.0)
	if V: steps.append(["pain", pain_eff, pain_raw, pm, body.pain, bleed_add, _bleed_total.get(d.idx, 0.0), body.blood, body.blood_max])
	var stab := Formulas.stability(du.mass(), d.gear_mass, d.leg_impair, d.prone, _shield(du) != null and not d.shield_dropped, du.attr("AGI"))
	var stagger := 0.0 if glanced else p_impact / maxf(1.0, stab) * float(atk.get("stagger", 1.0))
	if V: steps.append(["stag", p_impact, stab, stagger])
	d.last_attacker = a.idx
	last_strike["severed"] = severed
	last_strike["artery"] = art_rate > 0.0
	last_strike["glanced"] = glanced
	D["kill"] = death_cause
	if pain_eff > 0.0:
		D["pe"] = snappedf(pain_eff, 0.1)   # v0.014: the log's reaction words read the real pain
	if D["layers"].is_empty():
		D["out"] = "glance" if glanced else ("absorbed" if covering.size() > 0 else "harmless")
	elif severed:
		D["out"] = "decap" if part_id in ["neck", "head"] else "sever"
	_strike_end(a, d, D, "hit", part_id, art_rate > 0.0 or severed)
	if gear_w and w_item.broken and _has_weapon(a) and a.wielded == w_item:
		# v0.014: the weapon snapped on this blow: what is left in his hand is useless (scrap at the battle's end)
		a.weapon_dropped = true
		a.reach_tiles = 1
		_event("snap", a.idx, d.idx, "", false, part_id)
	if death_cause != "" or severed:
		_say(a, d, "kill" if death_cause != "" else "maim", rel)
	if D["layers"].size() > 0:
		_event("wound", a.idx, d.idx, "", false, part_id)
	if D["lodged"]:
		_ev_simple("lodged", a.idx, d.idx, "lodged", {"w": D["w"], "part": D["pname"]}, false, part_id)
	if severed:
		var se := _event("sever", a.idx, d.idx, CombatText.decisive("sever_head" if part_id in ["head", "neck"] else "sever",
			{"D": _cap(d.label), "d": d.label, "P": part_name, "his": d.pron}, 0.0, a.voff + tick), true, part_id)
		se["momentum_left"] = p
		se["direction"] = Vector2(float(signi(d.cell.x - a.cell.x)), -0.5)
	if death_cause != "":
		_kill(d, a.idx, death_cause)
		return
	if not d.alive():
		return
	if "guts" in D["funcs"]:
		_event("guts", a.idx, d.idx, CombatText.decisive("guts", {"D": _cap(d.label), "d": d.label, "P": D["pname"], "his": d.pron},
			0.0, a.voff + tick), true, part_id)
	_update_functions(d, true, "" if severed else part_id, inner_hit)
	if "airway" in D["funcs"] or "drown" in D["funcs"]:
		_ev_simple("stun", d.idx, -1, "breath", {})
	if pain_eff > 0.0:
		_shock(d, pain_eff / Formulas.SHOCK_WOUND_DIV + (Formulas.SHOCK_SEVER if severed else 0.0), "wounded", pain_eff >= Formulas.PAIN_STUN)
	if d.state != "unconscious" and d.alive():
		if body.pain > Formulas.PAIN_KO:
			_knock_out(d, "pain")
		elif d.think_dmg >= Formulas.THINK_KO:
			_knock_out(d, "head")
		elif not d.prone and (pain_eff >= Formulas.PAIN_KNOCKDOWN or stagger >= Formulas.STAGGER_KNOCKDOWN):
			_fall(d, "knocked" if stagger >= Formulas.STAGGER_KNOCKDOWN else "pain", Formulas.KNOCKDOWN_TICKS)
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
				var hs := Formulas.roll_head_stun(rng, clampf(skull_p / Formulas.HEAD_STUN_P, 0.0, 0.9))
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
					_ev_simple("stun", d.idx, -1, "stun_" + why, {"ticks": add, "stagger": stagger, "pain": pain_eff})

# ---------------------------------------------------------------- v0.014 gear damage (Formulas: gear damage block)
## The blow is struck with the weapon's head (blade, point or head), not a pommel, haft or shaft.
func _head_blow(verb: String, _wt: Dictionary) -> bool:
	return not (verb.contains("pommel") or verb.contains("shaft") or verb.contains("haft") or verb.contains("butt"))

## A solid head (no edged attack: maces, hammers, clubs) bends as a whole head, a blade by its section.
func _solid_head(wt: Dictionary) -> bool:
	for at in wt.get("attacks", []):
		if String(at.get("type", "")) == "edge":
			return false
	return true

## The weapon's head took `reaction` back from the layer that stopped it (`piece`: an armour piece or a bone layer).
## Snap past the fracture form (broken: scrap), bend past the yield form (bent back after: -1 quality step, -2 when
## twice the yield). One bend/snap per strike; nothing below the yield.
func _gear_bend(_a: Fighter, w: Item, wt: Dictionary, wmat: Dictionary, contact: float, reaction: float, piece: String,
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
		if verbose: steps.append(["note", "WEAPON SNAPS: reaction p %.1f >= fracture R %.1f (%s head %.1f mm)" % [reaction, r_snap, w.material, t]])
	else:
		var n := 2 if reaction >= Formulas.BEND_SEVERE * r_yield else 1
		var q0 := w.quality
		w.quality = maxi(0, w.quality - n)
		_iname.erase(w)
		D["wd"] = ["bend", piece, is_armor]
		if verbose: steps.append(["note", "weapon bends: reaction p %.1f >= yield R %.1f (%s head %.1f mm); quality %d -> %d" % [reaction, r_yield, w.material, t, q0, w.quality]])

## An edge stopped by a harder layer chips (Item.dull); each full 1.0 is ground away for a quality step.
func _gear_chip(w: Item, layer_mat: Dictionary, wmat: Dictionary, piece: String, is_armor: bool, D: Dictionary, steps: Array) -> void:
	if w.broken or w.is_legend():   # v0.014: a legendary edge never chips
		return
	var c := Formulas.chip_amount(layer_mat, wmat)
	if c <= 0.0:
		return
	w.dull += c
	if w.dull >= 1.0:
		w.dull -= 1.0
		w.quality = maxi(0, w.quality - 1)
		_iname.erase(w)
	if not D.has("wd"):
		D["wd"] = ["chip", piece, is_armor]
	if verbose: steps.append(["note", "edge chips on the %s (shear yield %d vs the blade's %d): dull %.2f" % [piece,
		int(layer_mat.get("shear_yield", 0)), int(wmat.get("shear_yield", 0)), w.dull]])

## "skull", "cartilage" as they are; a plain "bone" layer is named by its part ("shin bone" reads better as
## "right lower leg bone" than "bone").
func _bone_word(lname: String, pdef: Dictionary, pid: String) -> String:
	if lname != "bone":
		return lname
	return "%s bone" % String(pdef.get("name", pid))

const ARMOR_BROKEN_KINDS := ["split", "cracked", "shattered"]
## Damage to one worn piece at the struck spot (entry = its armor_for dict for this part).
func _armor_dmg(entry: Dictionary, kind: String, D: Dictionary, steps: Array) -> void:
	if not gear_wear:
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
	if verbose: steps.append(["note", "  %s %s here (spot weakness %.2f)%s" % [entry["name"], kind, entry["w"],
		"; broken: scrap after the battle" if kind in ARMOR_BROKEN_KINDS else ("; quality %d" % it.quality if it != null else "")]])

## v0.014: a battle cry or taunt in the speaker's log (lazy text, CombatText "say"): cry (first blow), kill, maim;
## goblins striking from behind have their own backstab gloats.
func _say(a: Fighter, d: Fighter, kind: String, rel: String = "front") -> void:
	if a.cul == "":
		return
	if kind != "cry" and a.cul == "goblin" and rel != "front":
		kind = "back"
	var ck := "say:" + kind
	var vc := int(a.vcount.get(ck, 0))
	a.vcount[ck] = vc + 1
	_log(a, "ev", {"key": "say", "say": kind, "cul": a.cul, "al": a.label, "dl": d.label, "apr": a.pron, "dpr": d.pron,
		"w": _item_name(a.wielded) if _has_weapon(a) else "fists", "vk": a.voff, "vc": vc})

func _reached_muscle(D: Dictionary) -> bool:
	for l in D["layers"]:
		if l[1] in ["muscle", "organ", "bone", "tendon", "nerve", "vessel", "brain"]:
			return true
	return false

func _cut_path(a: Fighter, verb: String, thrust: bool) -> String:
	if thrust:
		return "straight"
	var v := verb.split(" ")[0]
	if v == "hack" or v == "chop":
		return "top_bottom"
	# forehand from the attacker's right = the defender's left; every other swing comes back as a backhand
	return "tl_br" if a.swing_count % 2 == 1 else "br_tl"

func _weapon_class(w: Item, atk: Dictionary) -> String:
	if w == null:
		return "natural"
	if atk.get("type", "") == "blunt":
		return "blunt"
	return "pierce" if float(atk.get("contact", 1000)) <= Formulas.PIERCE_CONTACT else "edge"

func _ldef(pid: String, pdef: Dictionary, lname: String) -> Dictionary:
	var ck: String = pdef.get("_ck", pid)   # monsters wave 1: non-humanoid plans carry "_ck" = "plan:part" (core/db.gd)
	if not _ldef_cache.has(ck):
		var m := {}
		for l in pdef.get("layers", []):
			m[l.get("name", l["tissue"])] = l
		_ldef_cache[ck] = m
	return _ldef_cache[ck].get(lname, {})

## The whole {layer name -> layer def} map of a part (same cache as _ldef; one lookup per strike).
func _ldef_map(pid: String, pdef: Dictionary) -> Dictionary:
	var ck: String = pdef.get("_ck", pid)
	if not _ldef_cache.has(ck):
		var m := {}
		for l in pdef.get("layers", []):
			m[l.get("name", l["tissue"])] = l
		_ldef_cache[ck] = m
	return _ldef_cache[ck]

## DB.materials[tissue] (muscle for an unknown tissue), cached per battle.
func _tmat(tissue: String) -> Dictionary:
	var m = _tmats.get(tissue)
	if m == null:
		m = DB.materials.get(tissue, DB.materials["muscle"])
		_tmats[tissue] = m
	return m

func _has_vital(pdef: Dictionary) -> bool:
	for l in pdef.get("layers", []):
		if "vital" in l.get("functions", []):
			return true
	return false

func _strike_end(a: Fighter, d: Fighter, D: Dictionary, ev_type: String, part: String, decisive: bool) -> void:
	var entry := {"tick": tick, "k": "strike", "d": D}
	var key: String = "strike:" + String(D["out"])
	D["vc"] = int(a.vcount.get(key, 0))
	a.vcount[key] = int(D["vc"]) + 1
	a.log.append(entry)
	d.log.append(entry)
	var e := _event(ev_type, a.idx, d.idx, "", decisive, part)
	e["entry"] = entry

## Applies damage to one tissue layer; returns {"pain", "bleed", "death", "funcs"} (pain raw, before tolerance).
func _wound_layer(f: Fighter, part_id: String, pdef: Dictionary, L: Dictionary, ld: Dictionary, dmg: float,
		kind: String, edge: bool, through: bool, tou: float = -1.0) -> Dictionary:
	var funcs := []
	var pain := _wound_core(f, part_id, pdef, L, ld, dmg, kind, edge, through, tou, funcs)
	return {"pain": pain, "bleed": _wl_bleed, "death": _wl_death, "funcs": funcs}

## _wound_layer without the result dictionary (the strike path, perf): returns the raw pain, leaves the bleed added
## in _wl_bleed and a death cause (or "") in _wl_death, and appends lost functions to `funcs_out`.
func _wound_core(f: Fighter, part_id: String, pdef: Dictionary, L: Dictionary, ld: Dictionary, dmg: float,
		kind: String, edge: bool, through: bool, tou: float, funcs_out: Array) -> float:
	_wl_bleed = 0.0
	_wl_death = ""
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
		_add_bleed(f, part_id, L, b, Formulas.CLOT_MINOR)
		_wl_bleed = b
	if not ld.has("functions"):
		return pain
	var funcs: Array = ld["functions"]
	var lim := Formulas.BRAIN_DEATH if "think" in funcs else Formulas.VITAL_DESTROY
	var dm := float(L["dmg"])
	if "vital" in funcs and dm >= lim:
		L["kind"] = "destroyed"
		_wl_death = "%s destroyed" % L.get("name", tissue)
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
func _update_functions(f: Fighter, announce: bool, only: String = "", only2: String = "") -> void:
	var body := f.unit.body
	# perf: the totals below are a fold over the parts with rel = true; when the struck part was and stays rel = false
	# (or its status did not change) they are the stored ones (f.pagg) from the last fold over the same pstat.
	# only2: the inner part the blow reached as well (a spinal cord); both must be unchanged to reuse the totals.
	var reuse := false
	if only == "" or f.pstat.is_empty():
		for p in body.plan()["parts"]:
			f.pstat[p["id"]] = _part_status(f, p)
	else:
		reuse = not f.pagg.is_empty()
		for o in [only, only2]:
			if o == "" or not body.has_part(o):
				continue
			var ns := _part_status(f, _pdef(body, o))
			var old = f.pstat.get(o)
			f.pstat[o] = ns
			if not (old != null and ((not old[PS_REL] and not ns[PS_REL]) or old == ns)):
				reuse = false
	if not reuse:
		_fold_functions(f)
	var g: Array = f.pagg
	_apply_functions(f, announce, g[0], g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8])

## The fold of _update_functions over f.pstat, stored in f.pagg:
## [stance_lost, leg_imp, right_ok, left_ok, eyes, eyes_ok, right_why, left_why, stance_why].
func _fold_functions(f: Fighter) -> void:
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
func _apply_functions(f: Fighter, announce: bool, stance_lost: bool, leg_imp: float, right_ok: bool, left_ok: bool,
		eyes: int, eyes_ok: int, right_why: String, left_why: String, stance_why: String) -> void:
	f.leg_impair = leg_imp
	f.tempo_tick = -1000
	f.blind = eyes > 0 and eyes_ok == 0
	if not right_ok and not f.weapon_dropped and f.wielded != null:
		_drop_weapon(f, announce, right_why)
	if not left_ok and not f.shield_dropped and f.unit.equip.get("off_hand", null) != null:
		f.shield_dropped = true
		if announce:
			_ev_simple("drop", f.idx, -1, "drop", {"w": f.unit.equip["off_hand"].display_name(), "why": left_why})
	var newly := stance_lost and not f.stance_lost
	f.stance_lost = stance_lost
	if newly and not f.prone:
		if announce:
			_fall(f, "legs_" + stance_why, 0)
		else:
			f.prone = true

func _part_status(f: Fighter, p: Dictionary) -> Array:
	var body := f.unit.body
	var pid: String = p["id"]
	var lost := f.lost.has(pid)
	# the part's fixed roles (grasp side, stance, eye, finger of which hand, its relsize, spine level) depend only on
	# its plan definition: cached like _ldef_map
	var ck: String = p.get("_ck", pid)
	var roles = _proles.get(ck)
	if roles == null:
		var gr := ""
		if pid.begins_with("hand") or pid.begins_with("arm"):
			gr = "r" if pid.ends_with("_r") else ("l" if pid.ends_with("_l") else "")
		roles = [gr, "stance" in p.get("functions", []), pid.begins_with("eye"), String(p.get("digit", "")),
			float(p.get("relsize", 0)), String(p.get("spine", ""))]
		_proles[ck] = roles
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
		var ldm := _ldef_map(pid, p)
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
func _pdef(body: BodyState, pid: String) -> Dictionary:
	return body.part_def(pid)   # BodyState caches {id -> def} per plan

## Marks a severed part and everything attached below it as lost (cache of BodyState.is_lost).
func _mark_lost(f: Fighter, pid: String) -> void:
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
var _inner_cache: Dictionary = {}

func _inner_of(body: BodyState, pid: String, pdef: Dictionary) -> Array:
	var ck: String = pdef.get("_ck", pid)
	var e = _inner_cache.get(ck)
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
		_inner_cache[ck] = e
	return e

## Every lung of the plan is punctured or ruined (v0.013 drowning in blood).
func _lungs_failed(f: Fighter) -> bool:
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

func _drop_weapon(f: Fighter, announce: bool, why: String) -> void:
	if f.wielded == null or f.weapon_dropped:
		return
	var it := f.wielded
	if not f.lodged.is_empty():
		_let_go(f, false)
	else:
		ground.append({"cell": f.cell, "item": it})
	f.weapon_dropped = true
	f.reach_tiles = 1
	if announce:
		_ev_simple("drop", f.idx, -1, "drop", {"w": it.display_name(), "why": why})

func _fall(f: Fighter, why: String, knock_ticks: int) -> void:
	if occ[_ci(f.cell)] == f.idx:
		occ[_ci(f.cell)] = -1
	f.prone = true
	f.knockdown_left = maxi(f.knockdown_left, knock_ticks)
	if f.state in ["preparing", "moving", "ready", "recovering"]:
		f.pending_action = {}
		_set_action(f, "prone", maxi(1, knock_ticks))
	_rip_free(f)
	_ev_simple("fall", f.idx, -1, "fall_" + why, {"ticks": knock_ticks})

func _knock_out(f: Fighter, why: String) -> void:
	if f.state == "unconscious" or f.state == "dead":
		return
	if occ[_ci(f.cell)] == f.idx:
		occ[_ci(f.cell)] = -1
	f.state = "unconscious"
	f.prone = true
	f.action_ticks = 0
	f.pending_action = {}
	f.ko_cause = why
	_rip_free(f)
	if f.grabbing >= 0:
		_release_grab(f)
	if not f.routed:
		side_down[f.side] += 1
	_ev_simple("unconscious", f.idx, -1, "ko_" + why, {"pain": f.unit.body.pain, "blood": _blood_frac(f), "brain": f.think_dmg})
	if not f.routed:
		_ally_down(f, false)

func _kill(f: Fighter, killer: int, why: String) -> void:
	if f.state == "dead":
		return
	if occ[_ci(f.cell)] == f.idx:
		occ[_ci(f.cell)] = -1
	var was_down := f.state == "unconscious" or f.routed
	# harness classification of how the end came (survey item 5)
	if why in ["bled to death", "suffocated"]:
		f.death_ctx = "bled"
	elif f.state == "unconscious" or f.prone:
		f.death_ctx = "helpless"
	elif f.last_hit_rel != "front":
		f.death_ctx = "flanked"
	else:
		f.death_ctx = "lucky"
	f.state = "dead"
	f.action_ticks = 0
	f.pending_action = {}
	f.death_cause = why
	f.unit.dead = true
	if f.grabbing >= 0:
		_release_grab(f)
	if f.grabbed_by >= 0:
		_release_grab(fighters[f.grabbed_by])
	if not f.lodged.is_empty():
		_let_go(f, false)
	if not was_down:
		side_down[f.side] += 1
	var kl := ""
	var kidx := -1
	if killer >= 0 and killer < fighters.size():
		var k: Fighter = fighters[killer]
		if k.side != f.side:
			kidx = killer
			k.kills += 1
			k.unit.kills += 1
			kill_pairs.append([k.unit, f.unit])
			k.unit.kill_list.append(f.unit.name)
			while k.unit.kill_list.size() > Unit.KILL_LIST_MAX:   # long lives: the newest names (u.kills keeps the count)
				k.unit.kill_list.pop_front()
			Renown.on_kill(k.unit, f.unit)   # economy spec 2: kill renown (campaign/renown.gd)
			kl = k.label
			k.morale = minf(100.0, k.morale + Formulas.MORALE_KILL)
			if k.unit.skill("intimidator") > 0:
				for o in fighters:
					if o.side == f.side and o != f and o.present() and _dist(o.cell, k.cell) <= Formulas.LEADER_RADIUS:
						_shock(o, Formulas.SHOCK_INTIMIDATE_PER * k.unit.skill("intimidator"), "intimidated", false)
	_ev_simple("death", kidx, f.idx, "death", {"why": why, "killer": kl}, true)
	if not was_down:
		_ally_down(f, true)

## Allies near a fallen or routed unit take a morale shock; an officer falling shakes his squad (the captain, everyone).
## Panic spreads one step per tick: the shock of a fall/rout reaches nearby allies on the next tick.
func _ally_down(f: Fighter, died: bool) -> void:
	_downs.append([f, died])

func _process_downs() -> void:
	# at most DOWNS_PER_TICK shocks spread per tick (panic travels; also keeps rout cascades off a single tick)
	var n := mini(_downs.size(), Formulas.DOWNS_PER_TICK)
	var batch := _downs.slice(0, n)
	_downs = _downs.slice(n)
	for x in batch:
		_ally_down_now(x[0], x[1])

func _ally_down_now(f: Fighter, died: bool) -> void:
	var officer := f.unit.is_officer()
	var fx := f.cell.x
	var fy := f.cell.y
	for o in _targets[f.side]:
		# perf (same set): a plain ally out of STRESS_RADIUS is skipped before the state checks
		if not officer:
			var oc: Vector2i = o.cell
			if absi(oc.x - fx) > Formulas.STRESS_RADIUS or absi(oc.y - fy) > Formulas.STRESS_RADIUS:
				continue
		if o.side != f.side or o == f or not o.present() or o.routed:
			continue
		if officer and (o.unit.squad == f.unit.uid or f.unit.role == "captain"):
			_shock(o, Formulas.SHOCK_OFFICER_FALLS * (0.5 + o.tr_loyalty / 100.0), "officer_falls", died)
		elif absi(o.cell.x - f.cell.x) <= Formulas.STRESS_RADIUS and absi(o.cell.y - f.cell.y) <= Formulas.STRESS_RADIUS:   # = _dist, inlined (perf)
			if died:
				o.unit.hardness = mini(100, o.unit.hardness + 1)
			_shock(o, Formulas.SHOCK_ALLY_DIES if died else (Formulas.SHOCK_ALLY_ROUTS if f.routed else Formulas.SHOCK_ALLY_KO), "ally_down", died)

## Morale shock (survey item 3). Rage may trigger; below 25 the unit rolls to hold or rout.
func _shock(f: Fighter, base: float, why: String, rage_trigger: bool) -> void:
	if not f.present() or f.routed or base <= 0.0:
		return
	if f.nofear:
		return
	var amount := Formulas.shock(base, f.tr_nerve, float(f.unit.hardness))
	f.morale = maxf(0.0, f.morale - amount)
	if rage_trigger and f.rage_ticks <= 0:
		var ch := f.tr_temper / 100.0 * Formulas.RAGE_CHANCE_K
		if why == "ally_down":
			ch *= f.tr_prot / 100.0
		if Formulas.roll_rage_ok(rng, ch):   # (roll_rage; the record is not kept)
			f.rage_ticks = Formulas.RAGE_TICKS
			_ev_simple("rage", f.idx, -1, "rage", {"why": why})
	if f.morale < Formulas.MORALE_ROUT_BELOW:
		var ch2 := Formulas.rout_chance(f.morale, f.tr_courage, f.unit.skill("discipline"))
		var mr_r := Formulas.roll_morale_draw(rng)   # roll_morale; its record is built only when the unit breaks
		if mr_r < ch2:
			_rout(f, why, Formulas.roll_record("morale", mr_r, ch2), amount)
		else:
			_learn(f, "discipline", Learning.XP_DISCIPLINE)
			_use(f, "discipline")

func _rout(f: Fighter, why: String, roll: Dictionary, amount: float) -> void:
	f.routed = true
	f.tempo_tick = -1000
	f.target = -1
	f.pending_action = {}
	if f.grabbing >= 0:
		_release_grab(f)
	if not f.lodged.is_empty():
		_let_go(f, false)
	side_down[f.side] += 1
	_ev_simple("rout", f.idx, -1, "rout", {"why": why, "morale": f.morale, "shock": amount, "roll": roll}, true)
	_ally_down(f, false)

## Packed x/y copies of the _targets cells, built on first use in a tick and kept current by _do_move
## (Fighter.tslot = the fighter's index in its side's _targets).
func _build_tcells() -> void:
	_tx0 = PackedInt32Array()
	_ty0 = PackedInt32Array()
	_tx1 = PackedInt32Array()
	_ty1 = PackedInt32Array()
	for s in 2:
		var arr: Array = _targets[s]
		var n := arr.size()
		var xs := PackedInt32Array()
		var ys := PackedInt32Array()
		xs.resize(n)
		ys.resize(n)
		for i in n:
			var o: Fighter = arr[i]
			var c: Vector2i = o.cell
			xs[i] = c.x
			ys[i] = c.y
			o.tslot = i
		if s == 0:
			_tx0 = xs
			_ty0 = ys
		else:
			_tx1 = xs
			_ty1 = ys
	_tcells_ok = true

## Periodic morale: cohesion gains, outnumbered shock, rally.
func _morale_tick(f: Fighter) -> void:
	if not f.present() or f.unit.dead:
		return
	var commander: Fighter = _commander_near(f)
	var leader: float = float(commander.unit.skill("leader")) if commander != null else 0.0
	# A departed/incapacitated officer cannot leave a permanently inflated cap.
	f.morale_start = clampf(f.morale_base + Formulas.LEADER_AURA_PER_LEVEL * leader, 5.0, 100.0)
	if f.routed:
		if commander != null and f.standing() and not f.stance_lost:
			_command_rally(f, commander, leader)
			return
		var ch := Formulas.RALLY_BASE + Formulas.RALLY_LOYALTY * f.tr_loyalty + Formulas.RALLY_LEADER * leader
		if Formulas.roll_rally_ok(rng, ch):   # (roll_rally; the record is not kept)
			f.routed = false
			f.morale = Formulas.RALLY_MORALE
			side_down[f.side] -= 1
			_ev_simple("rally", f.idx, -1, "rally", {})
		return
	var allies := 0
	var enemies := 0
	# allies within 3 tiles (cohesion); enemies actually engaging this unit (adjacent or reaching it)
	# perf (same results): cheap integer distance prefilters before the function calls
	# (cells read from the packed copies of the target cells, see _build_tcells).
	# The outnumbered test runs on every 5th morale tick only: the enemies are counted then, and the allies are counted
	# in full then; otherwise only up to the cohesion cap (more allies cannot change min(allies, cap)).
	var check_out := (tick / Formulas.MORALE_TICK) % 5 == 0
	var cap := f.tr_cohesion / 20.0
	if not _tcells_ok:
		_build_tcells()
	var fx := f.cell.x
	var fy := f.cell.y
	var mine: Array = _targets[f.side]
	var xs: PackedInt32Array = _tx0 if f.side == 0 else _tx1
	var ys: PackedInt32Array = _ty0 if f.side == 0 else _ty1
	# |x - fx| <= R as a range test (same integers)
	var x0 := fx - Formulas.COHESION_GAIN_RADIUS
	var x1 := fx + Formulas.COHESION_GAIN_RADIUS
	var y0 := fy - Formulas.COHESION_GAIN_RADIUS
	var y1 := fy + Formulas.COHESION_GAIN_RADIUS
	for i in mine.size():
		var x: int = xs[i]
		if x < x0 or x > x1:
			continue
		var y: int = ys[i]
		if y < y0 or y > y1:
			continue
		var o: Fighter = mine[i]
		if o != f and o.present() and not o.routed:
			allies += 1
			if not check_out and float(allies) >= cap:
				break
	if check_out:
		var theirs: Array = _targets[1 - f.side]
		xs = _tx1 if f.side == 0 else _tx0
		ys = _ty1 if f.side == 0 else _ty0
		x0 = fx - 2
		x1 = fx + 2
		y0 = fy - 2
		y1 = fy + 2
		for i in theirs.size():
			var x: int = xs[i]
			if x < x0 or x > x1:
				continue
			var y: int = ys[i]
			if y < y0 or y > y1:
				continue
			var o: Fighter = theirs[i]
			if o.standing() and not o.routed and _in_reach(o, f):
				enemies += 1
	var gain := Formulas.MORALE_GAIN_PER_ALLY * minf(float(allies), cap)
	f.morale = minf(f.morale_start, f.morale + gain)
	if check_out and enemies >= 2 * (allies + 1):
		var mult := Formulas.MORALE_OUTNUMBER_RACE if f.rdef.get("outnumber_morale", false) else 1.0
		_shock(f, Formulas.SHOCK_OUTNUMBERED * mult, "outnumbered", false)

## Scheduled command changes morale/orders only, never wounds, blood or body function.
func _command_rally(f: Fighter, officer: Fighter, leader: float) -> void:
	if not f.routed or not f.present() or f.unit.dead: return
	var before: float = f.morale
	f.routed = false
	f.morale = maxf(f.morale, Formulas.RALLY_MORALE)
	f.target = -1
	f.pending_attack = {}
	f.pending_action = {}
	f.current_attack = ""
	f.prev_cell = f.cell
	f.tempo_tick = -1000
	_set_action(f, _idle_state(f), 0)
	side_down[f.side] -= 1
	_ev_simple("rally", officer.idx, f.idx, "officer_rally", {
		"mode":"commanded", "commander_uid":officer.unit.uid, "soldier_uid":f.unit.uid,
		"morale_before":before, "morale_after":f.morale, "leader_level":leader,
		"radius":Formulas.LEADER_RADIUS, "distance":_dist(officer.cell, f.cell)})

func _learn(f: Fighter, skill: String, xp: float) -> void:
	var m = f.lmult.get(skill)   # perf: the race learn rate is fixed during a battle
	if m == null:
		m = Learning.learn_mult(f.unit, skill)
		f.lmult[skill] = m
	var lvl := Learning.add_skill_xp_mult(f.unit, skill, xp, m)
	if lvl >= 0:
		_ev_simple("learn", f.idx, -1, "learn", {"n": f.unit.name, "skill": skill.replace("_", " "), "lvl": lvl})

# =====================================================================================================
# Stuck weapons and the unarmed fallback (survey lodge rules + unarmed addendum)
# =====================================================================================================
## Wielder AI with a stuck weapon: victim helpless -> twist; pinned at reach and the victim can't hit back -> twist;
## threatened (another enemy within 2 tiles or the victim reaches me) -> pull out if <= 6 ticks else let go; else pull.
func _decide_lodged(f: Fighter) -> void:
	var v: Fighter = fighters[int(f.lodged["victim"])]
	var pull := Formulas.pull_ticks(int(f.lodged["layers"]), float(f.unit.attr("STR")))
	if not v.alive() or v.state == "fled":
		_begin_special(f, "pull", pull, {})
		return
	var victim_reaches := v.active() and _in_reach(v, f)
	var threatened := victim_reaches
	for o in fighters:
		if o.side != f.side and o != v and o.present() and _dist(o.cell, f.cell) <= 2:
			threatened = true
			break
	if v.helpless() or not threatened:
		if v.helpless() or not victim_reaches:
			_begin_special(f, "twist", 3, {})
		else:
			_begin_special(f, "pull", pull, {})
	elif pull <= Formulas.LET_GO_LIMIT:
		_begin_special(f, "pull", pull, {})
	else:
		_let_go(f, true)
		_set_action(f, _idle_state(f), 1)

func _begin_special(f: Fighter, kind: String, ticks: int, data: Dictionary) -> void:
	data["kind"] = kind
	f.pending_action = data
	f.current_attack = kind
	_set_action(f, "preparing", _ticks(f, float(ticks) * f.tempo))

func _finish_special(f: Fighter) -> void:
	var pa := f.pending_action
	f.pending_action = {}
	var kind: String = pa.get("kind", "")
	var rec := 2
	match kind:
		"twist":
			_twist(f)
			rec = 3
		"pull":
			_pull_out(f)
		"victim_pull":
			_victim_pull(f, int(pa.get("wielder", -1)))
		"retrieve":
			_retrieve(f, pa)
		"dragon_breath":
			DragonBreath.release(self, f, pa)
			rec = 6
		"grab":
			_grab(f, int(pa.get("t", -1)))
		"takedown":
			_takedown(f, int(pa.get("t", -1)))
			rec = 3
		"disarm":
			_disarm(f, int(pa.get("t", -1)))
			rec = 3
		"drag":   # monsters wave 1: a latched creature drags its victim down
			NaturalAttacks.drag(self, f, int(pa.get("t", -1)))
			rec = 3
		"shoot", "sling", "unsling", "pickup_bow":   # bows
			rec = Archery.finish(self, f, kind, pa)
	if f.state == "preparing":
		_set_action(f, "recovering", _ticks(f, float(rec) * f.tempo))

func _lodge_layer(v: Fighter, part: String, lname: String) -> Dictionary:
	if not v.unit.body.has_part(part):
		return {}
	for L in v.unit.body.wound_part(part)["layers"]:   # the stored part (a lodged blade cut it, so it is stored already)
		if L.get("name", L["tissue"]) == lname:
			return L
	return {}

func _twist(f: Fighter) -> void:
	if f.lodged.is_empty():
		return
	var v: Fighter = fighters[int(f.lodged["victim"])]
	var part: String = f.lodged["part"]
	var lname := String(f.lodged["layer"])
	var L := _lodge_layer(v, part, lname)
	if L.is_empty() or not v.alive():
		return
	var p := float(f.lodged["p0"]) * Formulas.TWIST_MOMENTUM
	var tissue: String = L["tissue"]
	var dmg := clampf(p / 40.0, 0.05, 0.5) * Formulas.tou_mult(v.unit.attr("TOU"))
	var pdef := _pdef(v.unit.body, part)
	var ld := _ldef(part, pdef, lname)
	var res := _wound_layer(v, part, pdef, L, ld, dmg, Formulas.edge_kind(tissue, 20.0, float(L["dmg"]) + dmg), true, false)
	var pain := float(res["pain"]) * Formulas.TWIST_PAIN_MULT * Formulas.pain_mult(v.unit.attr("WIL"), v.unit.attr("END"), v.unit.skill("discipline")) / v.pain_tol
	v.unit.body.pain += pain
	v.pain_floor_src += pain
	L["bleed"] = float(L.get("bleed", 0.0)) * Formulas.TWIST_BLEED_MULT
	_recount_bleed(v)
	v.last_attacker = f.idx
	v.last_attacked_tick = tick
	_ev_simple("hit", f.idx, v.idx, "twist", {"w": f.lodged["item"].display_name(), "part": pdef.get("name", part),
		"layer": lname, "dmg": dmg, "pain": pain, "p": p})
	if res["death"] != "":
		_kill(v, f.idx, res["death"])
	elif v.unit.body.pain > Formulas.PAIN_KO and v.state != "unconscious":
		_knock_out(v, "pain")

## Exit tear on the deepest layer reached when a stuck weapon comes out.
func _exit_tear(v: Fighter, lod: Dictionary, mult: float) -> void:
	var part: String = lod["part"]
	var lname := String(lod["layer"])
	var L := _lodge_layer(v, part, lname)
	if L.is_empty() or not v.alive():
		return
	var dmg := clampf(float(lod["p0"]) * Formulas.EXIT_TEAR * mult / 40.0, 0.02, 0.3)
	var pdef := _pdef(v.unit.body, part)
	_wound_layer(v, part, pdef, L, _ldef(part, pdef, lname), dmg, "torn", true, false)
	var pain := float(Formulas.PAIN_RECEPTORS.get(L["tissue"], 5.0)) * 2.0 * Formulas.pain_mult(v.unit.attr("WIL"), v.unit.attr("END"), v.unit.skill("discipline")) / v.pain_tol
	v.unit.body.pain += pain
	v.pain_floor_src += pain

func _unstick(f: Fighter) -> Dictionary:
	var lod := f.lodged
	f.lodged = {}
	if lod.is_empty():
		return lod
	var v: Fighter = fighters[int(lod["victim"])]
	for i in range(v.stuck_in_me.size() - 1, -1, -1):
		if is_same(v.stuck_in_me[i]["item"], lod["item"]):
			v.stuck_in_me.remove_at(i)
	return lod

func _pull_out(f: Fighter) -> void:
	var lod := _unstick(f)
	if lod.is_empty():
		return
	var v: Fighter = fighters[int(lod["victim"])]
	_exit_tear(v, lod, 1.0)
	_ev_simple("freed", f.idx, v.idx, "pull_out", {"w": lod["item"].display_name(), "part": _pdef(v.unit.body, lod["part"]).get("name", lod["part"])})

## Let go: the weapon stays in the victim (bleed x0.5, pain on every action); the wielder fights on unarmed.
func _let_go(f: Fighter, announce: bool) -> void:
	var lod := f.lodged
	if lod.is_empty():
		return
	f.lodged = {}
	var v: Fighter = fighters[int(lod["victim"])]
	for s in v.stuck_in_me:
		if is_same(s["item"], lod["item"]):
			s["wielder"] = -1
	f.weapon_dropped = true
	f.reach_tiles = 1
	if announce:
		_ev_simple("drop", f.idx, v.idx, "let_go", {"w": lod["item"].display_name()})

func _victim_pull(v: Fighter, wielder: int) -> void:
	var w: Fighter = fighters[wielder] if wielder >= 0 else null
	if w == null or w.lodged.is_empty() or int(w.lodged["victim"]) != v.idx:
		return
	var lod := _unstick(w)
	w.weapon_dropped = true
	w.reach_tiles = 1
	ground.append({"cell": v.cell, "item": lod["item"]})
	_exit_tear(v, lod, 1.0)
	_ev_simple("freed", v.idx, w.idx, "victim_pull", {"w": lod["item"].display_name()})

## Stagger/knockdown on either side rips a stuck weapon free (tear).
func _rip_free(f: Fighter) -> void:
	if not f.lodged.is_empty():
		var lod := _unstick(f)
		_exit_tear(fighters[int(lod["victim"])], lod, 1.0)
		_ev_simple("freed", f.idx, int(lod["victim"]), "rip_free", {"w": lod["item"].display_name()})
	for s in f.stuck_in_me.duplicate():
		if int(s["wielder"]) >= 0:
			var w: Fighter = fighters[int(s["wielder"])]
			var lod2 := _unstick(w)
			if not lod2.is_empty():
				_exit_tear(f, lod2, 1.0)
				_ev_simple("freed", w.idx, f.idx, "rip_free", {"w": lod2["item"].display_name()})

## Unarmed choices before a plain punch: retrieve a weapon within 2 tiles; grab an armed enemy and disarm;
## grab and take down. Returns true if an action was started.
func _decide_unarmed_extra(f: Fighter) -> bool:
	if f.prone or not (_part_ok(f, "hand_r") or _part_ok(f, "hand_l")):
		return false
	var best := -1
	var best_d := 99
	for i in ground.size():
		var dd := _dist(f.cell, ground[i]["cell"])
		if dd <= Formulas.RETRIEVE_RADIUS and dd < best_d:
			best = i
			best_d = dd
	if best >= 0:
		var g: Dictionary = ground[best]
		if best_d <= 1:
			_begin_special(f, "retrieve", Formulas.RETRIEVE_TICKS, {"g": g})
			return true
		var before := f.cell
		_move_toward(f, g["cell"])
		return f.cell != before
	for o in fighters:
		if o.stuck_in_me.is_empty() or not (o.state == "dead" or o.helpless()) or _dist(f.cell, o.cell) > Formulas.RETRIEVE_RADIUS:
			continue
		for s in o.stuck_in_me:
			if int(s["wielder"]) < 0:
				if _dist(f.cell, o.cell) <= 1:
					_begin_special(f, "retrieve", Formulas.RETRIEVE_TICKS + int(s["layers"]), {"body": o.idx, "s": s})
					return true
				var before2 := f.cell
				_move_toward(f, o.cell)
				return f.cell != before2
	var t: Fighter = fighters[f.target] if f.target >= 0 else null
	if t == null or not t.present() or _dist(f.cell, t.cell) > 1 or not _diag_ok(f.cell, t.cell):
		return false
	var gc := _grab_chance(f, t)
	if f.grabbing == t.idx:
		if _has_weapon(t) and gc >= 0.5:
			_begin_special(f, "disarm", 4, {"t": t.idx})
			return true
		if not t.prone and gc >= 0.6:
			_begin_special(f, "takedown", 4, {"t": t.idx})
			return true
		return false
	if t.helpless():
		return false
	if (_has_weapon(t) and gc >= 0.5) or gc >= 0.6:
		_begin_special(f, "grab", 3, {"t": t.idx})
		return true
	return false

func _contest_mass(f: Fighter) -> float:
	return (f.unit.mass() + f.gear_mass) * (1.0 - maxf(0.0, 1.0 - _blood_frac(f)))

func _grab_chance(f: Fighter, t: Fighter) -> float:
	return Formulas.grab_chance(_eff(f, "wrestler", "grab"), _eff(t, "wrestler", "grab"), _contest_mass(f), _contest_mass(t))

func _grab(f: Fighter, ti: int) -> void:
	var t: Fighter = fighters[ti] if ti >= 0 else null
	if t == null or not t.present() or _dist(f.cell, t.cell) > 1:
		return
	var rr := Formulas.roll_grab(rng, _grab_chance(f, t))
	_learn(f, "wrestler", Learning.XP_SWING)
	if rr["ok"]:
		if f.grabbing >= 0:
			_release_grab(f)
		f.grabbing = t.idx
		t.grabbed_by = f.idx
		t.last_attacked_tick = tick
	_ev_simple("hit" if rr["ok"] else "miss", f.idx, t.idx, "grab_ok" if rr["ok"] else "grab_fail", {"roll": rr})

func _takedown(f: Fighter, ti: int) -> void:
	var t: Fighter = fighters[ti] if ti >= 0 else null
	if t == null or not t.present() or f.grabbing != ti:
		return
	var rr := Formulas.roll_grab(rng, _grab_chance(f, t))
	_learn(f, "wrestler", Learning.XP_SWING)
	_ev_simple("hit" if rr["ok"] else "miss", f.idx, t.idx, "takedown_ok" if rr["ok"] else "takedown_fail", {"roll": rr})
	if rr["ok"]:
		_release_grab(f)
		_fall(t, "thrown", Formulas.KNOCKDOWN_TICKS)

func _disarm(f: Fighter, ti: int) -> void:
	var t: Fighter = fighters[ti] if ti >= 0 else null
	if t == null or not t.present() or f.grabbing != ti or not _has_weapon(t):
		return
	var rr := Formulas.roll_grab(rng, _grab_chance(f, t))
	_learn(f, "wrestler", Learning.XP_SWING)
	if rr["ok"]:
		var it := t.wielded
		if not t.lodged.is_empty():
			_unstick(t)
		t.weapon_dropped = true
		t.reach_tiles = 1
		f.wielded = it
		f.weapon_dropped = false
		f.reach_tiles = _reach_of(f)
		_release_grab(f)
		_ev_simple("drop", f.idx, t.idx, "disarm_ok", {"w": it.display_name()})
	else:
		_ev_simple("miss", f.idx, t.idx, "disarm_fail", {"roll": rr})

func _release_grab(f: Fighter) -> void:
	if f.grabbing >= 0:
		fighters[f.grabbing].grabbed_by = -1
	f.grabbing = -1

func _retrieve(f: Fighter, pa: Dictionary) -> void:
	var it: Item = null
	if pa.has("g"):
		var g: Dictionary = pa["g"]
		var i := ground.find(g)
		if i < 0 or _dist(f.cell, g["cell"]) > 1:
			return
		ground.remove_at(i)
		it = g["item"]
	elif pa.has("body"):
		var o: Fighter = fighters[int(pa["body"])]
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
	f.reach_tiles = _reach_of(f)
	_ev_simple("freed", f.idx, -1, "retrieve", {"w": it.display_name()})

# ---------------------------------------------------------------- events and lazy logs
func _trim_history() -> void:
	flush_combat_journal()
	if history_event_limit > 0 and events.size() > history_event_limit:
		var cut := maxi(events.size() - history_event_limit, maxi(1, history_event_limit / 8))
		events = events.slice(cut)
		events_dropped += cut
	if history_log_limit > 0:
		for f in fighters:
			if f.log.size() <= history_log_limit: continue
			var cut := maxi(f.log.size() - history_log_limit, maxi(1, history_log_limit / 4))
			f.log = f.log.slice(cut)
			log_dropped[f.idx] = int(log_dropped.get(f.idx, 0)) + cut

func result_events() -> Array:
	if history_event_limit == 0: return events
	var out := events.filter(func(e): return e.get("type", "") != "learn")
	out.append_array(learning_summary.values())
	out.sort_custom(func(a, b): return int(a["tick"]) < int(b["tick"]))
	return out

func _event(type: String, actor: int, target: int, text: String, decisive: bool, part: String = "") -> Dictionary:
	if _journal_pending.size() >= 256: flush_combat_journal()
	var e := {"tick": tick, "type": type, "actor": actor, "target": target, "text": text, "decisive": decisive, "part": part}
	events.append(e)
	new_events.append(e)
	if combat_journal != null and not (type == "move" and log_moves):
		var context: Dictionary = {}
		if actor >= 0 and actor < fighters.size():
			var a: Fighter = fighters[actor]
			context = {"al": a.label, "cell": a.cell, "verb": a.current_attack}
			if type in ["prepare", "attack", "snap"]:
				context["weapon"] = _item_name(a.wielded) if a.wielded != null else "bare hands"
		if target >= 0 and target < fighters.size():
			var d: Fighter = fighters[target]
			context["dl"] = d.label
			if part != "": context["pname"] = _pdef(d.unit.body, part).get("name", part)
		_journal_pending.append({"event": e, "context": context})
	return e

func _log(f: Fighter, k: String, d: Dictionary) -> Dictionary:
	if _journal_pending.size() >= 256: flush_combat_journal()
	var entry := {"tick": tick, "k": k, "d": d}
	f.log.append(entry)
	if combat_journal != null:
		_journal_pending.append({"entry": entry, "actor": f.idx, "target": -1, "type": k})
	return entry

## Entries are finalized by their emitters before this runs. No Unit/Item is stored.
func flush_combat_journal() -> void:
	if combat_journal == null or _journal_pending.is_empty(): return
	var started: int = Time.get_ticks_usec()
	for record: Dictionary in _journal_pending:
		if record.has("event"):
			var event: Dictionary = record["event"]
			var entry: Dictionary = event.get("entry", {})
			if entry.is_empty():
				entry = {"tick": int(event["tick"]), "k": "event", "d": {
					"event": event.duplicate(true), "context": record["context"]}}
			combat_journal.append(entry, int(event["actor"]), int(event["target"]), String(event["type"]))
		else:
			combat_journal.append(record["entry"], int(record["actor"]), int(record["target"]), String(record["type"]))
	_journal_pending.clear()
	Perf.record_us("Combat log capture", Time.get_ticks_usec() - started)

## A non-strike event with a lazily rendered entry in the actor's log (and the target's when given).
## Decisive ones (death, rout, sever) get their text rendered right away; the rest render lazily via event_text().
func _ev_simple(type: String, actor: int, target: int, key: String, params: Dictionary, decisive: bool = false, part: String = "") -> Dictionary:
	params["key"] = key
	var fa: Fighter = fighters[actor] if actor >= 0 else null   # perf: one lookup each
	var ft: Fighter = fighters[target] if target >= 0 else null
	if fa != null:
		params["al"] = fa.label
		params["vk"] = fa.voff
		if fa.pron != "his":
			params["apr"] = fa.pron
		var ck := "ev:" + key
		var vc := int(fa.vcount.get(ck, 0))
		params["vc"] = vc
		fa.vcount[ck] = vc + 1
	if ft != null:
		params["dl"] = ft.label
		if ft.pron != "his":
			params["dpr"] = ft.pron   # monsters wave 1: "its" for animals
	var entry := {"tick": tick, "k": "ev", "d": params}
	if fa != null:
		fa.log.append(entry)
	if ft != null and target != actor:
		ft.log.append(entry)
	var e := _event(type, actor if actor >= 0 else target, target, "", decisive, part)
	e["entry"] = entry
	if type == "learn" and history_event_limit > 0:
		learning_summary[str(actor) + ":" + String(params.get("skill", ""))] = e
	if decisive:
		e["text"] = CombatText.render(entry)["text"]
	return e

## Rendered view of a log entry: {"tick", "text", "detail": Array[String], "calc"}. Cached into the entry.
static func render_entry(entry: Dictionary) -> Dictionary:
	return CombatText.render(entry)

## Text of any event (strike events render their entry lazily).
static func event_text(e: Dictionary) -> String:
	if String(e.get("text", "")) != "":
		return e["text"]
	if e.has("entry"):
		return CombatText.render(e["entry"])["text"]
	return ""

# ---------------------------------------------------------------- helpers
func _ci(c: Vector2i) -> int:
	return c.y * grid_w + c.x

func _inb(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < grid_w and c.y < grid_h

func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func _d2(a: Vector2i, b: Vector2i) -> int:
	return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)

static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s

# ---------------------------------------------------------------- aftermath (after the clash is decided)
## One aftermath step (about AFTER_TICKS ticks of time): the downed keep bleeding and may bleed out; the medics
## of the side holding the field bandage the downed, their own first (worst bleeding first), then the enemy's,
## whom they take prisoner. Returns {"tended_own", "tended_enemy", "bled_out": [n0, n1]} for this step.
const AFTER_TICKS := 10.0
var medic_skill := 0   # the field holder's medics (0-15): skilled hands also slow internal bleeding
func aftermath_step(holder: int, medics: int) -> Dictionary:
	var out := {"tended_own": 0, "tended_enemy": 0, "bled_out": [0, 0]}
	new_events = []
	var own: Array = []; var foe: Array = []
	for f in fighters:
		if f.state == "dead" or f.unit.dead or DragonCombat.is_dragon_unit(Game, f.unit): continue
		var down: bool = f.state == "unconscious" or f.state == "prone"
		var b: BodyState = f.unit.body
		var bleed: float = b.total_bleed()
		if bleed > 0.0 and not f.unit.has_meta("tended"):
			b.blood -= bleed * AFTER_TICKS
			if b.blood < b.blood_max * Formulas.BLOOD_DEATH:
				_kill(f, -1, "bled to death"); out["bled_out"][f.side] += 1
				continue
		if (down or bleed > 0.0) and not f.unit.has_meta("tended") and holder >= 0:
			(own if f.side == holder else foe).append(f)
	var by_bleed := func(a, c): return a.unit.body.total_bleed() > c.unit.body.total_bleed()
	own.sort_custom(by_bleed); foe.sort_custom(by_bleed)
	var hands := maxi(1, medics / 2)   # two medics a man
	for f in own + foe:
		if hands <= 0: break
		Healing._bandage(f.unit, clampf(0.4 - 0.025 * float(medic_skill), 0.05, 0.4))
		f.unit.set_meta("tended", true)
		hands -= 1
		if f.side == holder: out["tended_own"] += 1
		else: out["tended_enemy"] += 1
	return out

## Downed men still lying on the field (not dead), per side.
func downed_counts() -> Array:
	var n := [0, 0]
	for f in fighters:
		if f.state in ["unconscious", "prone"] and not f.unit.dead: n[f.side] += 1
	return n
