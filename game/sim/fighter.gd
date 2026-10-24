class_name Fighter
extends RefCounted
## INTERFACE CONTRACT: one combatant inside a BattleSim (wraps a persistent Unit).
## The sim workstream may add fields; these are what the battle screen reads.

var idx: int = 0
var unit: Unit
var side: int = 0                  # 0 player, 1 enemy
var cell: Vector2i = Vector2i.ZERO # tile position
var prev_cell: Vector2i = Vector2i.ZERO  # tile before the current move (presentation interpolates prev_cell -> cell over action_total ticks)
var facing: int = 1                # +1 faces right, -1 faces left
var target: int = -1               # fighter idx being engaged
## state: "ready" | "moving" | "preparing" | "recovering" | "prone" | "unconscious" | "dead" | "fled"
var state: String = "ready"
var action_ticks: int = 0          # ticks until the current action completes
var action_total: int = 1          # total ticks of the current action (for animation progress)
var action_delay: int = 0          # stagger/stun ticks already added to the current action (capped)
var delay_uncapped: int = 0        # diagnostic: stagger/stun ticks requested in total
var current_attack: String = ""    # verb of the attack being prepared/delivered
## Per-fighter combat log. Entries are stored lazily: {"tick": int, "k": kind, "d": data} and rendered on demand.
## Read an entry with BattleSim.render_entry(entry) -> {"tick", "text" (short story line), "detail" (Array of
## per-layer / consequence lines), "calc" (the numbers: rolls, momentum, layer tests, pain, timing)}.
## Rendering caches "text", "detail" and "calc" into the entry, so after the first read entry["text"] works too.
var log: Array = []

# ---------------------------------------------------------------- sim-internal additions (read-only for UI)
var waiting: bool = false          # stream arrival: still off the map, queued to enter
var hold: bool = false             # holds its ground (opts "hold0"/"hold1"): strikes what comes into reach, never advances
var prone: bool = false            # lying down (from leg wounds or knockdown); can still fight weakly
var routed: bool = false           # broke and is running for its own map edge
var wielded: Item = null           # weapon in hand right now (may be a picked-up one); null = unarmed
var weapon_dropped: bool = false   # lost the main-hand weapon (grasp lost, let go, disarmed)
var shield_dropped: bool = false   # off-hand shield dropped
var speed: float = 675.0           # last computed DF-style speed: effective gait (higher = slower)
var speed_info: Dictionary = {}    # factors of the last speed calculation
var tempo_tick: int = -1000       # tick of the last tempo computation (cached ~10 ticks)
var tempo: float = 1.0             # action-time multiplier from AGI, encumbrance, wounds, fatigue (1 = unhindered)
var gait: float = 675.0            # DF gait value used for movement (ticks per 100 tiles)
var initiative: float = 2000.0     # AGI+KIN: who acts first when two are ready on the same tick
var tiebreak: float = 0.0          # rolled once at setup (Formulas.roll_initiative_tiebreak)
var attr_use: Dictionary = {}      # attribute use this battle (Learning.note_use), turned into growth at the end
var label: String = ""             # narrative name ("Bram Kettle", "the goblin spear Snik")
var morale: float = 50.0           # 0..100 (survey item 3); below 25 a shock may rout the unit
var morale_start: float = 50.0
var morale_base: float = 50.0       # intrinsic initial morale without command support
var commander_idx: int = -1        # unique same-side assigned officer, resolved once at setup
var commander_uid: int = -1        # validates the cached command identity; never a Fighter back-reference
var rage_ticks: int = 0            # > 0 while enraged (+15% torque, -30% dodge/parry)
var pain_floor_src: float = 0.0    # total effective pain of wounds taken (pain decays toward a fraction of this)
var gear_mass: float = 0.0         # total carried mass (stagger stability)
var leg_impair: float = 0.0        # worst stance-part muscle damage, slows movement
var blind: bool = false
var breath_bad: bool = false
var air: float = 600.0             # ticks of air left while the airway is cut (Formulas.AIR_MAX)
var suffocating: bool = false
var think_dmg: float = 0.0         # brain damage (concussion)
var grip_r: float = 1.0            # v0.013: share of the right hand's fingers (DF relative size) that still close
var grip_l: float = 1.0
var drowning: bool = false         # v0.013: both lungs punctured or ruined (the air clock runs, as for a cut airway)
var knockdown_left: int = 0        # ticks of pain knockdown left (stands afterwards if legs work)
var stance_lost: bool = false      # a leg chain is disabled -> stays prone
var kills: int = 0
var last_attacker: int = -1
var last_attacked_tick: int = -1000
var defence_ticks: Array = []      # ticks of recent defence attempts (saturation)
var last_flank_tick: int = -1000
var ko_cause: String = ""
var death_cause: String = ""
var death_ctx: String = ""         # "helpless" (down when killed), "flanked", "lucky" (lethal blow while standing), "bled"
var last_hit_rel: String = "front" # where the last strike on this fighter came from
var reach_tiles: int = 1
var armor_mass: float = 0.0
var other_mass: float = 0.0
var armor_for: Dictionary = {}     # part id -> Array of worn-item layer dicts, outside-in
var tick_carry: float = 0.0        # fractional tick carry so speed differences below 1 tick still count
var pending_attack: Dictionary = {}
var pending_action: Dictionary = {} # non-attack action in progress (pull out, twist, retrieve, grab ...)
var retarget_count: int = 0
var wait_count: int = 0
var lodged: Dictionary = {}        # our weapon stuck in someone: {"victim": idx, "part": id, "layer": name, "p0", "layers", "item"}
var lost: Dictionary = {}          # part ids severed or attached to a severed part (cache of BodyState.is_lost)
var pstat: Dictionary = {}         # per-part function status cache (stance, grasp, sight): BattleSim.PS_* slots
var parts_cache: Array = []        # [ids, relsize weights, names] of parts still attached (target roll)
var stuck_in_me: Array = []        # weapons stuck in this fighter: [{"wielder": idx or -1 (let go), "item": Item, "part", "layers"}]
var grabbing: int = -1             # fighter idx this one holds (wrestling)
var grabbed_by: int = -1
var bleeding: Dictionary = {}      # part id -> bleed rate per tick (optional, for visuals)
var swing_count: int = 0           # alternates forehand/backhand (cut path wording)
var vcount: Dictionary = {}        # text variant counters per template key (never the same variant back to back)
var voff: int = 0                  # per-fighter variant offset
var last_move_tick: int = -1000    # monsters wave 1: tick of the last step (a creature's charge needs a run-up)
var pron: String = "his"           # monsters wave 1: log pronoun ("its" for animals; v0.014 "her" by Unit.sex)
var cul: String = ""               # v0.014: battle-cry / taunt culture (orc, goblin, dwarf, elf, middle, northern, eastern; "" beasts)
# food and drink (core/food.gd), set at setup and when the buzz state changes
var fatigue_mult: float = 1.0      # exertion gain multiplier (belly state, hangover)
var focus_mult: float = 1.0        # 1 + focus (hunger, drink need, hangover; inside +-15%)
var pain_tol: float = 1.0          # pain tolerance multiplier (buzz)
var walk_mult: float = 1.0         # move ticks/tile multiplier (Stuffed)
var stumble_p: float = 0.0         # chance per move to stumble and lose the move (Hammered)
var belly_state: String = "fed"
var buzz_state: String = "sober"
var buzz_floor: float = -1.0       # buzz below this = the next state down (checked each tick, cheap)
var food_said: int = 0             # flags of one-off food/drink log lines already said
var food_pain_tick: int = -1000    # last "too drunk to feel it" line
# perf caches (sim-internal, set by BattleSim; values are exactly what the uncached calls return)
var rdef: Dictionary = {}          # unit.race_def() (the race never changes in a battle)
var creature: bool = false         # NaturalAttacks.is_creature
## Support horse bodies are native targets at their rider's cell, not extra soldiers.
var mount_idx := -1
var mount_rider_idx := -1
var mount_attached := false
var dragon: bool = false           # actual prepared native dragon actor
var dragon_profile: Dictionary = {} # frozen detached per-individual physics
var dragon_attacks: Array = []     # [attack, required part IDs], never the race-shared cache
var nofear: bool = false           # race "nofear"
var trait_cache: Dictionary = {}   # trait -> BattleSim._trait value (personality is fixed in a battle)
var alv: Dictionary = {}           # check -> Formulas.attr_levels(check, eff_attrs); cleared when food multipliers change
var lmult: Dictionary = {}         # skill -> Learning.learn_mult
var tr_nerve: float = 50.0         # BattleSim._trait values, set at setup
var tr_temper: float = 50.0
var tr_prot: float = 50.0
var tr_courage: float = 50.0
var tr_loyalty: float = 50.0
var tr_cohesion: float = 50.0
var pagg: Array = []               # BattleSim._fold_functions result for the current pstat
var tslot: int = -1              # index in BattleSim._targets[side] this tick (packed target cells)

# bows (docs/specs/bows.md, sim/archery.gd)
var bow: Item = null               # the bow (ranged slot); null = no bow (or it broke)
var bow_hand: bool = false         # the bow is in his hands (no parry, no shield block; the sidearm is sheathed)
var bow_state: String = ""         # "" none | "hand" | "slung" | "dropped" | "broken"
var bow_cell: Vector2i = Vector2i(-1, -1)   # where a dropped bow lies
var arrows_in: Array = []          # arrows lodged in him: [{"kind", "part", "layer"}]
var shield_arrows: int = 0         # arrows stuck in his shield (they weigh it down)
var shots: int = 0                 # arrows loosed this battle
var bsol: Dictionary = {}          # cached shot solution for bsol_kind (refreshed with the tempo cache)
var bsol_tick: int = -1000
var bsol_kind: String = ""

func alive() -> bool:
	return state != "dead"

func active() -> bool:
	return state != "dead" and state != "fled" and state != "unconscious"

## On the field and able to act (not queued off-map).
func present() -> bool:
	return active() and not waiting

## Lying down or out cold: auto-hit, head priority.
func helpless() -> bool:
	return state == "unconscious" or prone

func standing() -> bool:
	return active() and not prone and not waiting
