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
## Dragon UID -> whether any native collapse happened while flying. Survives history-tail trimming.
var dragon_downs: Dictionary = {}
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
	kill_pairs.clear(); dragon_downs.clear()
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
	MountedCombat.setup(self)
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

func _trait(f: Fighter, t: String) -> float: return BattleMorale._trait(self, f, t)
func _init_morale() -> void: BattleMorale._init_morale(self)
func _commander_near(f: Fighter) -> Fighter: return BattleMorale._commander_near(self, f)
func _leader_near(f: Fighter) -> float: return BattleMorale._leader_near(self, f)

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
	MountedCombat.sync(self)
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
	MountedCombat.sync(self)
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
		if f.waiting and f.state != "dead" and f.mount_rider_idx < 0:
			f.waiting = false
			f.cell = best
			f.prev_cell = best
			if f.standing():
				occ[_ci(best)] = f.idx
			MountedCombat.follow(self, f)
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
		if f.mount_rider_idx < 0 and st != "dead" and st != "fled" and st != "unconscious" and not f.routed:
			first = f.side
			break
	var last := -1
	if first >= 0:
		for i in range(fighters.size() - 1, -1, -1):
			var f: Fighter = fighters[i]
			var st: String = f.state
			if f.mount_rider_idx < 0 and st != "dead" and st != "fled" and st != "unconscious" and not f.routed:
				last = f.side
				break
	if first >= 0 and last >= 0 and first != last:
		s0 = 1
		s1 = 1
	else:
		for f in fighters:
			var st: String = f.state
			if f.mount_rider_idx < 0 and st != "dead" and st != "fled" and st != "unconscious" and not f.routed:
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
			if f.mount_rider_idx >= 0: Healing.after_battle(f.unit)
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
	if f.mount_rider_idx >= 0 and f.mount_attached:
		_set_action(f, _idle_state(f), 10)
		return
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
	if f.mount_rider_idx >= 0:
		_set_action(f, _idle_state(f), 10)
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
		if occ[from.y * grid_w + from.x] == f.idx:
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
	var mover := MountedCombat.mover(self, f)
	_compute_tempo(mover)
	var mt := Formulas.move_ticks(mover.speed, tm, f.prone) * mover.walk_mult
	var ticks := _ticks(f, mt)
	_set_action(f, "moving", ticks)
	mover.unit.body.exertion += Formulas.exertion_move(_eff_mass(mover), mover.unit.attr("END"), mover.breath_bad) * mover.fatigue_mult
	MountedCombat.follow(self, f)
	if f.armor_mass > 5.0:
		Learning.note_use(f.attr_use, "march", 0.1)
	if f.belly_state == "starving" or f.belly_state == "hungry":
		_food_gasp(f)
	_event("move", f.idx, -1, "", false)
	if log_moves:
		_log(f, "move", {"al": f.label, "x": p.x, "y": p.y, "mt": mt, "ticks": ticks, "sp": f.speed_info, "tm": tm, "prone": f.prone, "run": f.routed, "wk": f.walk_mult})

func _flee_step(f: Fighter) -> void: BattleMorale._flee_step(self, f)

# ---------------------------------------------------------------- tempo and condition
func _eff_mass(f: Fighter) -> float:
	return Formulas.effective_gear_mass(f.armor_mass, f.other_mass, f.unit.skill("armor_user"))

func _enc_ratio(f: Fighter) -> float:
	var burden := _eff_mass(f)
	if f.mount_attached and f.mount_rider_idx >= 0:
		var rider: Unit = fighters[f.mount_rider_idx].unit
		burden += rider.mass() + rider.gear_mass()
	return Formulas.encumbrance_ratio(burden, f.unit.attr("STR"), f.unit.mass())

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

func _deliver(f: Fighter) -> void: BattleDamage._deliver(self, f)
func debug_strike(ai: int, di: int, part_id: String = "", attack_idx: int = -1, land: bool = true) -> Dictionary: return BattleDamage.debug_strike(self, ai, di, part_id, attack_idx, land)
func _strike(a: Fighter, d: Fighter, atk: Dictionary, sw: Dictionary, pre: Dictionary) -> void: BattleDamage._strike(self, a, d, atk, sw, pre)
func _head_blow(verb: String, _wt: Dictionary) -> bool: return BattleDamage._head_blow(verb, _wt)
func _solid_head(wt: Dictionary) -> bool: return BattleDamage._solid_head(wt)
func _gear_bend(_a: Fighter, w: Item, wt: Dictionary, wmat: Dictionary, contact: float, reaction: float, piece: String, is_armor: bool, D: Dictionary, steps: Array) -> void: BattleDamage._gear_bend(self, _a, w, wt, wmat, contact, reaction, piece, is_armor, D, steps)
func _gear_chip(w: Item, layer_mat: Dictionary, wmat: Dictionary, piece: String, is_armor: bool, D: Dictionary, steps: Array) -> void: BattleDamage._gear_chip(self, w, layer_mat, wmat, piece, is_armor, D, steps)
func _bone_word(lname: String, pdef: Dictionary, pid: String) -> String: return BattleDamage._bone_word(lname, pdef, pid)
const ARMOR_BROKEN_KINDS := ["split", "cracked", "shattered"]
func _armor_dmg(entry: Dictionary, kind: String, D: Dictionary, steps: Array) -> void: BattleDamage._armor_dmg(self, entry, kind, D, steps)
func _say(a: Fighter, d: Fighter, kind: String, rel: String = "front") -> void: BattleMorale._say(self, a, d, kind, rel)
func _reached_muscle(D: Dictionary) -> bool: return BattleDamage._reached_muscle(D)
func _cut_path(a: Fighter, verb: String, thrust: bool) -> String: return BattleDamage._cut_path(a, verb, thrust)
func _weapon_class(w: Item, atk: Dictionary) -> String: return BattleDamage._weapon_class(w, atk)
func _ldef(pid: String, pdef: Dictionary, lname: String) -> Dictionary: return BattleDamage._ldef(self, pid, pdef, lname)
func _ldef_map(pid: String, pdef: Dictionary) -> Dictionary: return BattleDamage._ldef_map(self, pid, pdef)
func _tmat(tissue: String) -> Dictionary: return BattleDamage._tmat(self, tissue)
func _has_vital(pdef: Dictionary) -> bool: return BattleDamage._has_vital(pdef)
func _strike_end(a: Fighter, d: Fighter, D: Dictionary, ev_type: String, part: String, decisive: bool) -> void: BattleDamage._strike_end(self, a, d, D, ev_type, part, decisive)
func _wound_layer(f: Fighter, part_id: String, pdef: Dictionary, L: Dictionary, ld: Dictionary, dmg: float, kind: String, edge: bool, through: bool, tou: float = -1.0) -> Dictionary: return BattleDamage._wound_layer(self, f, part_id, pdef, L, ld, dmg, kind, edge, through, tou)
func _wound_core(f: Fighter, part_id: String, pdef: Dictionary, L: Dictionary, ld: Dictionary, dmg: float, kind: String, edge: bool, through: bool, tou: float, funcs_out: Array) -> float: return BattleDamage._wound_core(self, f, part_id, pdef, L, ld, dmg, kind, edge, through, tou, funcs_out)
func _update_functions(f: Fighter, announce: bool, only: String = "", only2: String = "") -> void: BattleDamage._update_functions(self, f, announce, only, only2)
func _fold_functions(f: Fighter) -> void: BattleDamage._fold_functions(self, f)
func _apply_functions(f: Fighter, announce: bool, stance_lost: bool, leg_imp: float, right_ok: bool, left_ok: bool, eyes: int, eyes_ok: int, right_why: String, left_why: String, stance_why: String) -> void: BattleDamage._apply_functions(self, f, announce, stance_lost, leg_imp, right_ok, left_ok, eyes, eyes_ok, right_why, left_why, stance_why)
func _part_status(f: Fighter, p: Dictionary) -> Array: return BattleDamage._part_status(self, f, p)
func _pdef(body: BodyState, pid: String) -> Dictionary: return BattleDamage._pdef(body, pid)
func _mark_lost(f: Fighter, pid: String) -> void: BattleDamage._mark_lost(f, pid)
var _inner_cache: Dictionary = {}
func _inner_of(body: BodyState, pid: String, pdef: Dictionary) -> Array: return BattleDamage._inner_of(self, body, pid, pdef)
func _lungs_failed(f: Fighter) -> bool: return BattleDamage._lungs_failed(f)
func _drop_weapon(f: Fighter, announce: bool, why: String) -> void: BattleDamage._drop_weapon(self, f, announce, why)
func _fall(f: Fighter, why: String, knock_ticks: int) -> void: BattleDamage._fall(self, f, why, knock_ticks)
func _knock_out(f: Fighter, why: String) -> void: BattleMorale._knock_out(self, f, why)
func _kill(f: Fighter, killer: int, why: String) -> void: BattleMorale._kill(self, f, killer, why)
func _ally_down(f: Fighter, died: bool) -> void: BattleMorale._ally_down(self, f, died)
func _process_downs() -> void: BattleMorale._process_downs(self)
func _ally_down_now(f: Fighter, died: bool) -> void: BattleMorale._ally_down_now(self, f, died)
func _shock(f: Fighter, base: float, why: String, rage_trigger: bool) -> void: BattleMorale._shock(self, f, base, why, rage_trigger)
func _rout(f: Fighter, why: String, roll: Dictionary, amount: float) -> void: BattleMorale._rout(self, f, why, roll, amount)
func _build_tcells() -> void: BattleMorale._build_tcells(self)
func _morale_tick(f: Fighter) -> void: BattleMorale._morale_tick(self, f)
func _command_rally(f: Fighter, officer: Fighter, leader: float) -> void: BattleMorale._command_rally(self, f, officer, leader)

func _learn(f: Fighter, skill: String, xp: float) -> void:
	var m = f.lmult.get(skill)   # perf: the race learn rate is fixed during a battle
	if m == null:
		m = Learning.learn_mult(f.unit, skill)
		f.lmult[skill] = m
	var lvl := Learning.add_skill_xp_mult(f.unit, skill, xp, m)
	if lvl >= 0:
		_ev_simple("learn", f.idx, -1, "learn", {"n": f.unit.name, "skill": skill.replace("_", " "), "lvl": lvl})

func _decide_lodged(f: Fighter) -> void: BattleDamage._decide_lodged(self, f)

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
		"twist": _twist(f); rec = 3
		"pull": _pull_out(f)
		"victim_pull": _victim_pull(f, int(pa.get("wielder", -1)))
		"retrieve": _retrieve(f, pa)
		"dragon_breath": DragonBreath.release(self, f, pa); rec = 6
		"grab": _grab(f, int(pa.get("t", -1)))
		"takedown": _takedown(f, int(pa.get("t", -1))); rec = 3
		"disarm": _disarm(f, int(pa.get("t", -1))); rec = 3
		"drag": NaturalAttacks.drag(self, f, int(pa.get("t", -1))); rec = 3   # monsters wave 1: a latched creature drags its victim down
		"shoot", "sling", "unsling", "pickup_bow": rec = Archery.finish(self, f, kind, pa)   # bows
	if f.state == "preparing":
		_set_action(f, "recovering", _ticks(f, float(rec) * f.tempo))

func _lodge_layer(v: Fighter, part: String, lname: String) -> Dictionary: return BattleDamage._lodge_layer(v, part, lname)
func _twist(f: Fighter) -> void: BattleDamage._twist(self, f)
func _exit_tear(v: Fighter, lod: Dictionary, mult: float) -> void: BattleDamage._exit_tear(self, v, lod, mult)
func _unstick(f: Fighter) -> Dictionary: return BattleDamage._unstick(self, f)
func _pull_out(f: Fighter) -> void: BattleDamage._pull_out(self, f)
func _let_go(f: Fighter, announce: bool) -> void: BattleDamage._let_go(self, f, announce)
func _victim_pull(v: Fighter, wielder: int) -> void: BattleDamage._victim_pull(self, v, wielder)
func _rip_free(f: Fighter) -> void: BattleDamage._rip_free(self, f)
func _decide_unarmed_extra(f: Fighter) -> bool: return BattleDamage._decide_unarmed_extra(self, f)
func _contest_mass(f: Fighter) -> float: return BattleDamage._contest_mass(self, f)
func _grab_chance(f: Fighter, t: Fighter) -> float: return BattleDamage._grab_chance(self, f, t)
func _grab(f: Fighter, ti: int) -> void: BattleDamage._grab(self, f, ti)
func _takedown(f: Fighter, ti: int) -> void: BattleDamage._takedown(self, f, ti)
func _disarm(f: Fighter, ti: int) -> void: BattleDamage._disarm(self, f, ti)
func _release_grab(f: Fighter) -> void: BattleDamage._release_grab(self, f)
func _retrieve(f: Fighter, pa: Dictionary) -> void: BattleDamage._retrieve(self, f, pa)

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
	if type in ["fall", "unconscious", "death"]:
		var down_idx := target if type == "death" else actor
		if down_idx >= 0 and down_idx < fighters.size():
			var down: Fighter = fighters[down_idx]
			if down.dragon:
				dragon_downs[down.unit.dragon_uid] = bool(dragon_downs.get(down.unit.dragon_uid, false)) or bool(down.dragon_profile.get("flying", false))
	if type == "death" and target >= 0 and target < fighters.size():
		var horse: Fighter = fighters[target]
		if horse.mount_rider_idx >= 0:
			Horses.casualty(fighters[horse.mount_rider_idx].unit, horse.unit)
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
