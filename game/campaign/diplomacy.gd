class_name Diplomacy
extends RefCounted
## Diplomacy (docs/specs/diplomacy.md, "both layers"). Stepped once per campaign day from CampaignWorld._daily,
## right after the economy/day tick; nothing here runs per frame or per battle tick.
##
## State lives in Game.world["diplo"] (saved with the world):
##   factions: [fid]                     the factions that take part (data/diplomacy.json "factions")
##   pairs["a|b"] = {a, b, rel: -100..100, base, state, past, held, losses, cap}
##       state: WAR | HOSTILE | NEUTRAL | TRADE_PACT | ALLIANCE
##       past: days running the relation has sat in another state's band (hysteresis, 7 days)
##       held: days in the current state; losses: men lost in the current war (decays 2%/day)
##       truce: the day the truce after their last peace runs out (0 = none; see in_truce)
##   pairs also save treaty_alliance, pact_until (campaign day), calls[enemy] (war serial).
##       dynasty is rebuilt from living marriages; its bonuses never enter earned standing or raw rel.
##   player[fid] = {earned: float, comp: int, log: [{day, delta, text}] (last 5)}
##       standing = clamp(round(earned) + comp + dynasty bonus, -100, 100); Game.rep[fid] mirrors it for older callers.
##   size[fid]: armies + town militia, measured weekly (war odds, war weariness)
##   news: [{day, text}] declarations; stats: {wars, peaces, pacts, alliances} counted since world gen
##
## Lore (baselines, attitudes, caps) is data/diplomacy.json; tuning numbers are the constants below [ours].
## Factions outside the table (e.g. future monster factions) keep the old behaviour: CampaignWorld.WARS for
## faction pairs and Game.rep for the company.

const WAR := "WAR"
const HOSTILE := "HOSTILE"
const NEUTRAL := "NEUTRAL"
const TRADE_PACT := "TRADE_PACT"
const ALLIANCE := "ALLIANCE"
const ORDER := {"WAR": 0, "HOSTILE": 1, "NEUTRAL": 2, "TRADE_PACT": 3, "ALLIANCE": 4}
const STATE_WORDS := {"WAR": "War", "HOSTILE": "Hostile", "NEUTRAL": "Neutral", "TRADE_PACT": "Trade pact", "ALLIANCE": "Alliance"}
const STATE_COLORS := {"WAR": "#b02a1e", "HOSTILE": "#d0782a", "NEUTRAL": "#9a8b74", "TRADE_PACT": "#2f7ab0", "ALLIANCE": "#2e8a3e"}

# ---------------------------------------------------------------- layer 1 tuning [ours]
const HOLD_DAYS := 7              # hysteresis: days past a threshold before the state changes
const DRIFT := 0.01               # rel += (baseline - rel) * DRIFT per day
const SHARED_ENEMY := 0.2         # per day, per common enemy both are at WAR with
const LOSS_DECAY := 0.98          # war_losses *= LOSS_DECAY per day
const WEARINESS := 5.0            # rel += min(1, losses / size * WEARINESS) per day at war
const WAR_P_BASE := 0.05
const WAR_P_STRENGTH := 0.15
const WAR_P_CAP := 0.4
const PEACE_P := 0.3
const ARMY_DESTROYED := -4.0
const CARAVAN_RAIDED := -3.0
const TOWN_ATTACKED := -10.0
const TOWN_SACKED := -25.0
const ASSAULT_P := 0.25           # weekly, per side of a war: send a war band against an enemy town
const TRUCE_MIN := 60             # war pick 2 (Douglas): a peace brings a truce of 60-120 days, rolled per treaty;
const TRUCE_MAX := 120            #   the pair does not fight at all (no clashes, raids, interceptions, war)
const MILITIA_PER_SIZE := 3       # town militia = (size + 1) * this when the town has no militia field

# ---------------------------------------------------------------- layer 2 tuning [ours]
const EARNED_DRIFT := 0.995
const CONTRACT_DONE_MIN := 3
const CONTRACT_DONE_MAX := 8
const CONTRACT_FAILED := -5
const CONTRACT_ABANDONED := -8
const FIGHT := -10
const FIGHT_DEFENDING := -5
const RAID_CARAVAN := -12
const TAKING_SIDES := 2
const RANSOM := 2
const RELEASE := 2
const EXECUTE_PER_HEAD := -1
const EXECUTE_CAP := -10
const SLAVERS_PER_HEAD := -3
const COMP_MAX := 20
const OWN_RACE := 0.5
const HOSTILE_STANDING := -50     # <= : towns refuse trade, armies attack on sight, no contracts
const NO_CONTRACTS := -30         # < : no contracts
const FRIENDLY_STANDING := 50     # >= : patrols join your fights; > : better contract tier
const RECRUITS_HALVED := -20      # < : the faction's own race recruits halved; < -50 none
const LOG_SIZE := 5
const NEWS_DAYS := 3.0            # the map ticker shows a declaration for this many days
const DYNASTY_STANDING := 15
const DYNASTY_RELATION := 25.0
const ALLIANCE_ACCEPT := 60
const PACT_ACCEPT := 25
const CALL_STANDING := 40         # strictly above this standing, allies answer a call to war
const BREAK_STANDING := 25
const PACT_DAYS := 2 * 4 * Calendar.DAYS_PER_SEASON

static var _data: Dictionary = {}
static var _keys: Dictionary = {}

# ================================================================== data
static func data() -> Dictionary:
	if _data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/diplomacy.json"))
		_data = d if d is Dictionary else {"factions": []}
	return _data

## "the Warrens of Skrag" -> "The Warrens of Skrag" (String.capitalize would capitalize every word).
static func cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)

static func pair_key(a: String, b: String) -> String:
	var row: Dictionary = _keys.get(a, {})
	var k = row.get(b)
	if k == null:
		k = (a + "|" + b) if a < b else (b + "|" + a)
		row[b] = k
		_keys[a] = row
	return k

static func baseline(a: String, b: String) -> float:
	var d := data()
	var k := pair_key(a, b)
	if d.get("baselines", {}).has(k):
		return float(d["baselines"][k])
	var bd: Dictionary = d.get("baseline_default", {})
	if bd.has(a):
		return float(bd[a])
	if bd.has(b):
		return float(bd[b])
	return 0.0

## Best state index this pair can reach (goblins never above HOSTILE).
static func _cap_of(a: String, b: String) -> int:
	var caps: Dictionary = data().get("state_cap", {})
	var c := 4
	for f in [a, b]:
		if caps.has(f):
			c = mini(c, int(ORDER.get(caps[f], 4)))
	return c

## The relation ceiling that keeps a capped pair inside its best state's band.
static func _cap_rel(cap: int) -> float:
	return [-50.5, -10.5, 30.0, 60.0, 100.0][clampi(cap, 0, 4)]

static func band(rel: float) -> String:
	if rel < -50.0: return WAR
	if rel < -10.0: return HOSTILE
	if rel <= 30.0: return NEUTRAL
	if rel <= 60.0: return TRADE_PACT
	return ALLIANCE

static func attitude(fid: String, race: String) -> float:
	var att: Dictionary = data().get("attitudes", {}).get(fid, {})
	if att.has(race):
		return float(att[race])
	if DB.factions.get(fid, {}).get("race", "") == race:
		return OWN_RACE
	return float(att.get("*", 0.0))

static func members(w: Dictionary) -> Array:
	var dp = w.get("diplo")
	return dp["factions"] if dp != null else []

static func takes_part(w: Dictionary, fid: String) -> bool:
	var dp = w.get("diplo")
	return dp != null and (dp["player"] as Dictionary).has(fid)

# ================================================================== setup / load
## World generation: every pair at baseline +-10, state straight from its band; standings from start_earned.
static func init_world(game) -> void:
	var w: Dictionary = game.world
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), "diplomacy"])
	var fl := []
	for f in data().get("factions", []):
		if DB.factions.has(f):
			fl.append(f)
	fl.sort()
	var dp := {"v": 1, "factions": fl, "pairs": {}, "player": {}, "size": {}, "news": [], "day": 0,
		"stats": {"wars": 0, "peaces": 0, "pacts": 0, "alliances": 0}, "comp_sig": -1}
	for i in fl.size():
		for j in range(i + 1, fl.size()):
			var a: String = fl[i]; var b: String = fl[j]
			var cap := _cap_of(a, b)
			var base := baseline(a, b)
			var rel := clampf(base + rng.randf_range(-10.0, 10.0), -100.0, minf(100.0, _cap_rel(cap)))
			dp["pairs"][pair_key(a, b)] = {"a": a, "b": b, "rel": rel, "base": base, "state": band(rel), "past": 0,
				"held": HOLD_DAYS, "losses": 0.0, "cap": cap, "truce": 0}
	var se: Dictionary = data().get("start_earned", {})
	for f in fl:
		dp["player"][f] = {"earned": float(se.get(f, 0.0)), "comp": 0, "log": []}
	w["diplo"] = dp
	_sync_wars(w)
	sync_comp(game, true)
	# Douglas: orcs and goblins start hostile to a human company, standing -60 (earned = that less the make-up);
	# keyed on the starting company's race (data start_standing), any other band keeps start_earned
	var ss: Dictionary = data().get("start_standing", {}).get(company_race(game), {})
	for f in ss:
		if dp["player"].has(f):
			dp["player"][f]["earned"] = float(ss[f]) - float(dp["player"][f]["comp"])
	_mirror_all(game)

## The race most of the company is (officers count double, as in the make-up offset); "" for an empty company.
static func company_race(game) -> String:
	var n := {}
	for u in game.company:
		if not u.dead:
			n[u.race] = float(n.get(u.race, 0.0)) + (2.0 if u.is_officer() else 1.0)
	var best := ""
	for r in n:
		if best == "" or float(n[r]) > float(n[best]) or (float(n[r]) == float(n[best]) and String(r) < best):
			best = r
	return best

## After load: older saves have no diplomacy state; build it from the baselines and keep the old
## Game.rep values as earned standing. Baselines and caps are re-read so data edits apply to saves.
static func after_load(game) -> void:
	var w: Dictionary = game.world
	if w.is_empty() or not w.has("towns"):
		return
	if not w.has("diplo"):
		var old: Dictionary = game.rep.duplicate()
		init_world(game)
		for f in w["diplo"]["player"]:
			if old.has(f):
				w["diplo"]["player"][f]["earned"] = clampf(float(old[f]), -100.0, 100.0)
				_log(game, f, 0, "Old reputation carried over: %+d." % int(old[f]))
	var dp: Dictionary = w["diplo"]
	dp["day"] = int(dp.get("day", 0))
	for s in dp["stats"]:
		dp["stats"][s] = int(dp["stats"][s])
	for k in dp["pairs"]:
		var p: Dictionary = dp["pairs"][k]
		p["cap"] = _cap_of(p["a"], p["b"])
		p["base"] = baseline(p["a"], p["b"])
		for n in ["past", "held", "pact_until", "war_serial"]:
			p[n] = int(p.get(n, 0))
		p["truce"] = int(p.get("truce", 0))   # saves from before truces: none
		for enemy in p.get("calls", {}):
			p["calls"][enemy] = int(p["calls"][enemy])
	for f in dp["player"]:
		dp["player"][f]["comp"] = int(dp["player"][f].get("comp", 0))
	sync_dynasty(game)
	_sync_wars(w)
	sync_comp(game, true)

# ================================================================== layer 1 queries
## State between two factions. Same faction counts as ALLIANCE. Pairs outside the table use the old
## fixed war list (CampaignWorld.WARS): WAR or NEUTRAL.
static func state(w: Dictionary, a: String, b: String) -> String:
	if a == b:
		return ALLIANCE
	var dp = w.get("diplo")
	if dp != null:
		var p = dp["pairs"].get(pair_key(a, b))
		if p != null:
			if _bound(p): return ALLIANCE
			if int(p.get("pact_until", 0)) > int(dp["day"]) and ORDER[p["state"]] < 2: return NEUTRAL
			return p["state"]
	var legacy: Array = w.get("wars", CampaignWorld.WARS) if dp == null else CampaignWorld.WARS
	for pair in legacy:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return WAR
	return NEUTRAL

static func relation(w: Dictionary, a: String, b: String) -> float:
	var dp = w.get("diplo")
	if dp == null or a == b:
		return 100.0 if a == b else 0.0
	var p = dp["pairs"].get(pair_key(a, b))
	return clampf(float(p["rel"]) + (DYNASTY_RELATION if p.get("dynasty", false) else 0.0), -100.0, 100.0) if p != null else 0.0

static func at_war(w: Dictionary, a: String, b: String) -> bool:
	return a != b and state(w, a, b) == WAR

## WAR or HOSTILE: their armies fight on contact. Never during the truce after a peace (war pick 2).
static func fights(w: Dictionary, a: String, b: String) -> bool:
	if a == b:
		return false
	var dp = w.get("diplo")
	if dp != null:
		var p = dp["pairs"].get(pair_key(a, b))
		if p != null:   # (one lookup: this runs for every contact on the map)
			if _bound(p) or int(p.get("pact_until", 0)) > int(dp["day"]): return false
			var st: String = p["state"]
			return st == WAR or (st == HOSTILE and int(p.get("truce", 0)) <= int(dp["day"]))
	return ORDER[state(w, a, b)] <= 1

## Days left of the truce after this pair's last peace (0 = none). A pair at WAR has no truce.
static func truce_left(w: Dictionary, a: String, b: String) -> int:
	var dp = w.get("diplo")
	if dp == null or a == b:
		return 0
	var p = dp["pairs"].get(pair_key(a, b))
	if p == null or p["state"] == WAR:
		return 0
	return maxi(0, int(p.get("truce", 0)) - int(dp["day"]))

## In truce: no fighting at all between the pair (clashes, militia, caravan raids, the company's allies), and
## neither side may declare war, until it runs out.
static func in_truce(w: Dictionary, a: String, b: String) -> bool:
	return truce_left(w, a, b) > 0

## Truce length for a peace made on day d: TRUCE_MIN..TRUCE_MAX days, its own generator per treaty (world seed,
## pair, day), so the weekly rolls are not shifted.
static func roll_truce(w: Dictionary, key: String, d: int) -> int:
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(w.get("seed", 0)), key, d, "truce"])
	return r.randi_range(TRUCE_MIN, TRUCE_MAX)

## "truce, 47 days left" ("" when none): the relations screen.
static func truce_text(w: Dictionary, a: String, b: String) -> String:
	var n := truce_left(w, a, b)
	if n <= 0:
		return ""
	return "truce, %d day%s left" % [n, "" if n == 1 else "s"]

## Caravans may run between these factions (NEUTRAL or better; never HOSTILE or WAR).
static func trade_ok(w: Dictionary, a: String, b: String) -> bool:
	return a == b or ORDER[state(w, a, b)] >= 2

static func allied(w: Dictionary, a: String, b: String) -> bool:
	return a != b and state(w, a, b) == ALLIANCE

## Caravan destination weight: x1.5 toward trade-pact (and alliance) partners.
static func route_weight(w: Dictionary, a: String, b: String) -> float:
	return 1.5 if a != b and ORDER[state(w, a, b)] >= 3 else 1.0

static func enemies_at_war(w: Dictionary, fid: String) -> Array:
	var out := []
	var dp = w.get("diplo")
	if dp == null or not (dp["player"] as Dictionary).has(fid):
		var legacy: Array = w.get("wars", CampaignWorld.WARS) if dp == null else CampaignWorld.WARS
		for pair in legacy:
			if pair[0] == fid: out.append(pair[1])
			elif pair[1] == fid: out.append(pair[0])
		return out
	for f in dp["factions"]:
		if f != fid and state(w, fid, f) == WAR:
			out.append(f)
	return out

## w["wars"] mirrors the WAR pairs for any code that still reads the old list.
static func _sync_wars(w: Dictionary) -> void:
	var wars := []
	for k in w["diplo"]["pairs"]:
		var p: Dictionary = w["diplo"]["pairs"][k]
		if at_war(w, p["a"], p["b"]):
			wars.append([p["a"], p["b"]])
	w["wars"] = wars

# ================================================================== dynasty ties / player treaties
## Read the selected house's home realm without resolving its entire family on hot query paths.
static func player_realm(w: Dictionary) -> String:
	var tid := str(w.get("player_house", {}).get("town_id", ""))
	return str(w.get("towns", {}).get(tid, {}).get("faction", ""))

static func _bound(p: Dictionary) -> bool:
	return bool(p.get("treaty_alliance", false)) or bool(p.get("dynasty", false))

static func pact_left(w: Dictionary, a: String, b: String) -> int:
	var dp: Dictionary = w.get("diplo", {})
	var p: Dictionary = dp.get("pairs", {}).get(pair_key(a, b), {})
	return maxi(0, int(p.get("pact_until", 0)) - int(dp.get("day", 0)))

## A sworn alliance, living ruling-house marriage or non-aggression pact forbids hostilities.
static func peace_bound(w: Dictionary, a: String, b: String) -> bool:
	if a == "" or b == "" or a == b: return false
	var p: Dictionary = w.get("diplo", {}).get("pairs", {}).get(pair_key(a, b), {})
	return p.get("state", "") == ALLIANCE or _bound(p) or pact_left(w, a, b) > 0

static func dynasty_bonus(game, fid: String) -> int:
	var mine := player_realm(game.world)
	if mine == "": return 0
	var p: Dictionary = game.world.get("diplo", {}).get("pairs", {}).get(pair_key(mine, fid), {})
	return DYNASTY_STANDING if mine != "" and bool(p.get("dynasty", false)) else 0

## Rebuild, rather than accumulate, marriage benefits; called at weddings, daily and after load.
static func sync_dynasty(game) -> void:
	var w: Dictionary = game.world
	var dp: Dictionary = w.get("diplo", {})
	if dp.is_empty(): return
	if w.get("marriage", {}).get("alliances", {}).is_empty() and dp.get("dynasty_realms", {}).is_empty(): return
	var mine := player_realm(w)
	var realms := Marriage.realm_allies(game)
	dp["dynasty_realms"] = realms
	for p: Dictionary in dp["pairs"].values():
		var tied := (str(p["a"]) == mine and realms.has(p["b"])) or (str(p["b"]) == mine and realms.has(p["a"]))
		p["dynasty"] = tied
		if tied and p["state"] == WAR:
			_set_state(game, p, NEUTRAL)
	_sync_wars(w)
	_mirror_all(game)

static func treaty_text(game, fid: String) -> String:
	var mine := player_realm(game.world)
	if mine == "" or mine == fid: return ""
	if allied(game.world, mine, fid): return "Allied to your realm"
	if pact_left(game.world, mine, fid) > 0:
		var p: Dictionary = game.world["diplo"]["pairs"][pair_key(mine, fid)]
		return "Pact with your realm until year %d" % Calendar.year(float(p["pact_until"]))
	return ""

## Deterministic proposals expose the same reasons and terms that confirmation will revalidate.
static func action_preview(game, fid: String, action: String) -> Dictionary:
	var w: Dictionary = game.world
	var mine := player_realm(w)
	if mine == "": return {"ok": false, "reason": "Choose your house first."}
	if fid == mine or not w.get("diplo", {}).get("pairs", {}).has(pair_key(mine, fid)):
		return {"ok": false, "reason": "Choose another realm taking part in diplomacy."}
	if action not in ["alliance", "pact", "break"]:
		return {"ok": false, "reason": "Unknown diplomatic action."}
	var p: Dictionary = w["diplo"]["pairs"][pair_key(mine, fid)]
	var bound := allied(w, mine, fid)
	if action == "break" and not bound: return {"ok": false, "reason": "There is no alliance to break."}
	if action == "alliance" and bound: return {"ok": false, "reason": "Your realms are already allied."}
	if action == "pact" and (bound or pact_left(w, mine, fid) > 0):
		return {"ok": false, "reason": "An alliance or non-aggression pact already protects your realms."}
	var enemies := enemies_at_war(w, mine)
	enemies.sort()
	var common := 0
	for enemy in enemies:
		if at_war(w, fid, str(enemy)): common += 1
	var standing_now := standing(game, fid)
	var ties := 20 if Marriage.ties_to(game, fid) else 0
	var score := standing_now + common * 15 + ties
	var needed := ALLIANCE_ACCEPT if action == "alliance" else PACT_ACCEPT
	var accepts := action == "break" or score >= needed
	var until := maxi(int(game.day), int(w["diplo"]["day"])) + PACT_DAYS
	var terms := "Nearby field armies help you fight; allies above %+d standing join your wars, respecting existing treaties and truces." % CALL_STANDING
	if action == "pact":
		terms = "Neither realm may fight or declare war for two years (%d days), until year %d." % [PACT_DAYS, Calendar.year(float(until))]
	elif action == "break":
		terms = "End the realm alliance and its marriage ties. Earned standing falls by %d and realm relations cool; marriage bonuses end. Any non-aggression pact remains in force." % BREAK_STANDING
	var reasons := "Standing %+d; shared enemies %+d; marriage ties %+d. Acceptance %d / %d: %s." % [
		standing_now, common * 15, ties, score, needed, "accepted" if accepts else "refused"]
	if action == "break": reasons = "Your alliance will end."
	return {"ok": true, "accepts": accepts, "score": score, "reason": reasons + "\n" + terms,
		"review": {"realm": mine, "house": str(w["player_house"].get("household_uid", "")), "fid": fid,
			"action": action, "score": score, "standing": standing_now, "common": common, "ties": ties,
			"allied": bound, "pact_until": int(p.get("pact_until", 0)),
			"day": int(game.day), "enemies": enemies, "dynasty": bool(p.get("dynasty", false))}}

## A confirmation consumes the reviewed terms only if they still describe the current situation.
static func act(game, fid: String, action: String, review: Dictionary) -> Dictionary:
	sync_dynasty(game)
	var offer := action_preview(game, fid, action)
	if not offer.get("ok", false): return offer
	if review != offer["review"]:
		return {"ok": false, "reason": "Diplomatic circumstances changed. Review the proposal again."}
	if not offer["accepts"]:
		return {"ok": true, "accepted": false, "reason": "%s refuses. %s" % [cap(CampaignWorld.faction_the(fid)), offer["reason"]]}
	var w: Dictionary = game.world
	var mine := player_realm(w)
	var p: Dictionary = w["diplo"]["pairs"][pair_key(mine, fid)]
	var text := ""
	if action == "break":
		p["treaty_alliance"] = false
		var links: Dictionary = w.get("marriage", {}).get("alliances", {})
		for hh in links.keys():
			var tid := str(links[hh].get("town_id", ""))
			if str(w.get("towns", {}).get(tid, {}).get("faction", "")) == fid: links.erase(hh)
		p["dynasty"] = false
		p["calls"] = {}
		p["state"] = NEUTRAL
		p["past"] = 0; p["held"] = 0
		_push(w, mine, fid, -30.0)
		p["rel"] = minf(30.0, float(p["rel"]))
		add_earned(game, fid, -BREAK_STANDING, "Broke the realm alliance.")
		text = "%s breaks its alliance with %s." % [cap(CampaignWorld.faction_the(mine)), CampaignWorld.faction_the(fid)]
		news(game, text)
	else:
		if action == "alliance":
			if p["state"] == WAR: _set_state(game, p, NEUTRAL)
			p["treaty_alliance"] = true
			p["calls"] = {}
			_set_state(game, p, ALLIANCE)
			text = "Alliance agreed with %s." % CampaignWorld.faction_the(fid)
		else:
			p["pact_until"] = maxi(int(game.day), int(w["diplo"]["day"])) + PACT_DAYS
			if ORDER[p["state"]] < 2: _set_state(game, p, NEUTRAL)
			w["diplo"]["stats"]["pacts"] = int(w["diplo"]["stats"]["pacts"]) + 1
			text = "%s and %s swear a non-aggression pact until year %d." % [
				cap(CampaignWorld.faction_the(mine)), CampaignWorld.faction_the(fid), Calendar.year(float(p["pact_until"]))]
			news(game, text)
	sync_dynasty(game)
	_sync_wars(w)
	call_allies(game)
	_mirror_all(game)
	game.changed.emit()
	return {"ok": true, "accepted": true, "reason": text}

## Once per player/enemy war, willing allies answer. Peace later in that war does not trigger another call.
static func call_allies(game) -> void:
	var w: Dictionary = game.world
	var mine := player_realm(w)
	if mine == "" or not w.has("diplo"): return
	var pairs: Dictionary = w["diplo"]["pairs"]
	for fid in members(w):
		if not allied(w, mine, str(fid)) or standing(game, str(fid)) <= CALL_STANDING: continue
		var treaty: Dictionary = pairs[pair_key(mine, str(fid))]
		if not treaty.has("calls"): treaty["calls"] = {}
		for enemy in enemies_at_war(w, mine):
			var war: Dictionary = pairs[pair_key(mine, str(enemy))]
			var serial := int(war.get("war_serial", 0))
			if int(treaty["calls"].get(enemy, -1)) == serial: continue
			if allied(w, str(fid), str(enemy)) or peace_bound(w, str(fid), str(enemy)) or in_truce(w, str(fid), str(enemy)): continue
			treaty["calls"][enemy] = serial
			if at_war(w, str(fid), str(enemy)): continue
			var p: Dictionary = pairs[pair_key(str(fid), str(enemy))]
			p["declarer"] = str(fid)
			p["called_by"] = mine
			_set_state(game, p, WAR)
	_sync_wars(w)

# ================================================================== layer 1 events
static func _push(w: Dictionary, a: String, b: String, delta: float) -> void:
	var dp = w.get("diplo")
	if dp == null or a == b:
		return
	var p = dp["pairs"].get(pair_key(a, b))
	if p == null:
		return
	p["rel"] = clampf(float(p["rel"]) + delta, -100.0, minf(100.0, _cap_rel(int(p["cap"]))))

## A band of `loser` was destroyed by `winner`'s band; `men` = men lost on both sides (war losses).
static func on_army_destroyed(w: Dictionary, loser: String, winner: String, men: int) -> void:
	_push(w, loser, winner, ARMY_DESTROYED)
	add_war_losses(w, loser, winner, men)

static func add_war_losses(w: Dictionary, a: String, b: String, men: int) -> void:
	var dp = w.get("diplo")
	if dp == null or a == b:
		return
	var p = dp["pairs"].get(pair_key(a, b))
	if p != null and p["state"] == WAR:
		p["losses"] = float(p["losses"]) + men

## A caravan of `owner` was raided by a band of `raider`: grievance against the raider.
static func on_caravan_raided(w: Dictionary, owner: String, raider: String) -> void:
	_push(w, owner, raider, CARAVAN_RAIDED)

static func on_town_attacked(w: Dictionary, defender: String, attacker: String, sacked: bool) -> void:
	_push(w, defender, attacker, TOWN_SACKED if sacked else TOWN_ATTACKED)

# ================================================================== daily step
static func daily(game, d: int) -> void:
	var w: Dictionary = game.world
	var dp = w.get("diplo")
	if dp == null or int(dp["day"]) >= d:
		return
	dp["day"] = d
	sync_dynasty(game)
	var weekly := d % 7 == 0
	if weekly or (dp["size"] as Dictionary).is_empty():
		_measure(w, dp)
	var pairs: Dictionary = dp["pairs"]
	var fl: Array = dp["factions"]
	var sizes: Dictionary = dp["size"]
	var changed := false
	var wr: RandomNumberGenerator = null   # weekly rolls: one generator per week, seeded from world seed + day
	if weekly:
		wr = RandomNumberGenerator.new()
		wr.seed = hash([int(w.get("seed", 0)), d, "diplomacy"])
	# who is at WAR with whom at the start of the day (shared-enemy bonus; order-independent)
	var war_with := {}
	for f in fl:
		war_with[f] = {}
	for k in pairs:
		var q: Dictionary = pairs[k]
		if q["state"] == WAR and not _bound(q) and int(q.get("pact_until", 0)) <= d:
			war_with[q["a"]][q["b"]] = true
			war_with[q["b"]][q["a"]] = true
	for k in pairs:
		var p: Dictionary = pairs[k]
		var a: String = p["a"]; var b: String = p["b"]
		var st: String = p["state"]
		var rel: float = p["rel"]
		rel += (float(p["base"]) - rel) * DRIFT
		var wa: Dictionary = war_with[a]
		if not wa.is_empty():
			var wb: Dictionary = war_with[b]
			for c in wa:
				if wb.has(c):
					rel += SHARED_ENEMY
		if st == WAR:
			var losses: float = float(p["losses"]) * LOSS_DECAY
			p["losses"] = losses
			var size := maxf(1.0, minf(float(sizes.get(a, 1.0)), float(sizes.get(b, 1.0))))
			rel += minf(1.0, losses / size * WEARINESS)
		rel = clampf(rel, -100.0, minf(100.0, _cap_rel(int(p["cap"]))))
		p["rel"] = rel
		p["held"] = int(p["held"]) + 1
		if _bound(p): continue   # sworn alliances last until broken; marriages last while their couple does
		var bd := band(rel)
		if st == WAR:
			p["past"] = int(p["past"]) + 1 if bd != WAR else 0
			if weekly and int(p["past"]) >= HOLD_DAYS and wr.randf() < PEACE_P:
				_set_state(game, p, HOSTILE)
				changed = true
		else:
			var target := HOSTILE if bd == WAR else bd
			if int(p.get("pact_until", 0)) > d and ORDER[target] < 2: target = NEUTRAL
			if target == st:
				p["past"] = 0
			else:
				p["past"] = int(p["past"]) + 1
				if int(p["past"]) >= HOLD_DAYS:
					_set_state(game, p, target)
					changed = true
			if weekly and p["state"] == HOSTILE and int(p["held"]) >= HOLD_DAYS and int(p.get("truce", 0)) <= d and int(p.get("pact_until", 0)) <= d:
				var sa := float(sizes.get(a, 1.0)); var sb := float(sizes.get(b, 1.0))
				var pa := minf(WAR_P_CAP, WAR_P_BASE + WAR_P_STRENGTH * maxf(0.0, sa / maxf(1.0, sb) - 1.0))
				var pb := minf(WAR_P_CAP, WAR_P_BASE + WAR_P_STRENGTH * maxf(0.0, sb / maxf(1.0, sa) - 1.0))
				var who := ""
				if wr.randf() < pa:
					who = a
				elif wr.randf() < pb:
					who = b
				if who != "":
					p["declarer"] = who
					_set_state(game, p, WAR)
					changed = true
		if weekly and p["state"] == WAR:
			for side in [a, b]:
				if wr.randf() < ASSAULT_P:
					_queue_assault(w, side, b if side == a else a)
	if changed:
		_sync_wars(w)
	call_allies(game)
	# layer 2: earned standing drifts toward zero; make-up offset follows roster changes
	for f in dp["player"]:
		var pl: Dictionary = dp["player"][f]
		pl["earned"] = float(pl["earned"]) * EARNED_DRIFT
	sync_comp(game)
	_mirror_all(game)

static func _set_state(game, p: Dictionary, to: String) -> void:
	if to == WAR and peace_bound(game.world, str(p["a"]), str(p["b"])): return
	var from: String = p["state"]
	p["state"] = to
	p["past"] = 0
	p["held"] = 0
	var w: Dictionary = game.world
	var dp: Dictionary = w["diplo"]
	var an := CampaignWorld.faction_the(p["a"]); var bn := CampaignWorld.faction_the(p["b"])
	var text := ""
	if to == WAR:
		p["war_serial"] = int(p.get("war_serial", 0)) + 1
		p["losses"] = 0.0
		p["truce"] = 0
		var dec: String = p.get("declarer", p["a"])
		p.erase("declarer")
		var oth: String = p["b"] if dec == p["a"] else p["a"]
		text = "%s declares war on %s." % [Diplomacy.cap(CampaignWorld.faction_the(dec)), CampaignWorld.faction_the(oth)]
		if p.has("called_by"):
			text = "%s answers %s's call to war against %s." % [cap(CampaignWorld.faction_the(dec)),
				CampaignWorld.faction_the(str(p["called_by"])), CampaignWorld.faction_the(oth)]
			p.erase("called_by")
		dp["stats"]["wars"] = int(dp["stats"]["wars"]) + 1
		for fid in [dec, oth]:   # the towns of both remember (their people's stories)
			TownEcon.faction_event(w, fid, "war", [CampaignWorld.faction_the(dec), CampaignWorld.faction_the(oth)], float(game.day))
	elif from == WAR:
		var day := int(dp["day"])
		var days := roll_truce(w, pair_key(p["a"], p["b"]), day)
		p["truce"] = day + days   # war pick 2: no fighting between them until then
		text = "Peace: %s and %s end their war and swear a truce of %d days." % [cap(an), bn, days]
		dp["stats"]["peaces"] = int(dp["stats"]["peaces"]) + 1
		for fid in [p["a"], p["b"]]:
			TownEcon.faction_event(w, String(fid), "peace", [an, bn], float(game.day))
	elif to == TRADE_PACT and ORDER[from] < 3:
		text = "%s and %s sign a trade pact." % [cap(an), bn]
		dp["stats"]["pacts"] = int(dp["stats"]["pacts"]) + 1
	elif to == ALLIANCE:
		text = "%s and %s swear an alliance." % [cap(an), bn]
		dp["stats"]["alliances"] = int(dp["stats"]["alliances"]) + 1
	elif from == ALLIANCE:
		text = "The alliance of %s and %s lapses." % [an, bn]
	elif from == TRADE_PACT and ORDER[to] < 3:
		text = "The trade pact between %s and %s lapses." % [an, bn]
	if text != "":
		news(game, text)

static func news(game, text: String) -> void:
	var dp: Dictionary = game.world["diplo"]
	var n: Array = dp["news"]
	n.append({"day": float(game.day), "text": text})
	while n.size() > 12:
		n.pop_front()
	CampaignWorld.log_event(game, text)

## Latest declaration for the map ticker, "" when nothing happened in the last few days.
static func ticker(game) -> String:
	var dp = game.world.get("diplo")
	if dp == null or (dp["news"] as Array).is_empty():
		return ""
	var last: Dictionary = dp["news"][-1]
	return last["text"] if float(game.day) - float(last["day"]) <= NEWS_DAYS else ""

## Weekly: each faction's strength = men in its armies + its towns' militia.
static func _measure(w: Dictionary, dp: Dictionary) -> void:
	var s := {}
	for f in dp["factions"]:
		s[f] = 0.0
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		if wb["kind"] != "caravan" and s.has(wb["faction"]):
			s[wb["faction"]] += (wb["units"] as Array).size()
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if s.has(t["faction"]):
			s[t["faction"]] += militia(t)
	dp["size"] = s

static func militia(town: Dictionary) -> int:
	var m = town.get("militia")
	if typeof(m) == TYPE_INT or typeof(m) == TYPE_FLOAT:
		return int(m)
	return (int(town.get("size", 0)) + 1) * MILITIA_PER_SIZE

static func strength(w: Dictionary, fid: String) -> float:
	var dp = w.get("diplo")
	return float(dp["size"].get(fid, 0.0)) if dp != null else 0.0

# ================================================================== war assaults
## At WAR the stronger factions march on enemy towns (one war band per attacker at a time). Queued as a
## daily work job so the spawn never lands in one frame.
static func _queue_assault(w: Dictionary, att: String, def: String) -> void:
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb.get("war_assault", false) and wb["faction"] == att:
			return
	if not w.has("work"):
		w["work"] = []
	for job in w["work"]:
		if job[0] == "war_assault" and job[1] == att:
			return
	# the enemy town nearest to any of the attacker's towns
	var best := ""; var bd := INF
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if t["faction"] != def:
			continue
		for oid in w["factions"].get(att, {}).get("towns", []):
			var d: float = (w["towns"][oid]["pos"] as Vector2).distance_to(t["pos"])
			if d < bd:
				bd = d; best = tid
	if best != "":
		(w["work"] as Array).append(["war_assault", att, best])

static func launch_assault(game, att: String, tid: String, rng: RandomNumberGenerator) -> String:
	var w: Dictionary = game.world
	var town: Dictionary = w["towns"].get(tid, {})
	if town.is_empty() or not at_war(w, att, town["faction"]):
		return ""
	var home := CampaignWorld.nearest_faction_town(w, att, town["pos"])
	if home == "" or w["towns"][home]["faction"] != att:
		return ""
	var n := rng.randi_range(6, 10) + mini(int(game.day / 20.0), 6)
	if not Army.can_raise(game, att, n):
		return ""   # economy spec 2: an empty war chest raises no war band
	var pos: Vector2 = w["towns"][home]["pos"] + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
	var wid := CampaignWorld.spawn_warband(game, att, pos, n, "assault", rng,
		{"home": home, "target_town": tid, "war_assault": true, "march_day": float(game.day)})
	if wid == "":
		return ""   # war pick 4: the town could spare nobody to march
	CampaignWorld.log_event(game, "A war band of %s marches on %s." % [CampaignWorld.faction_the(att), town["name"]])
	return wid

## The existing offscreen resolver counts actual living defenders. A stood-down
## reserve contributes no fictional town-size strength; guards keep their duty.
static func assault_defence(game, town: Dictionary) -> int:
	var tid := String(town.get("id", ""))
	var guards := TownDefence.guards(game, tid).filter(func(u): return not u.dead).size()
	var base: int = guards + (0 if TownDefence.defence_policy(game, town) == "stand_down" else Militia.units_of(game, tid).size())
	return int(ceil(float(base) * (1.0 + Settlement.siege_bonus(town))))

## A war band reaches its target town: the defenders hold or the town is sacked (no player battle).
static func war_assault_arrives(game, wid: String) -> void:
	var w: Dictionary = game.world
	var wb: Dictionary = w["warbands"][wid]
	var town: Dictionary = w["towns"].get(wb["target_town"], {})
	wb["war_assault"] = false
	wb["kind"] = "raider" if DB.factions[wb["faction"]].get("player_hostile", false) else "patrol"
	wb["path"] = []
	wb["rest_until"] = game.day + 1.0
	if town.is_empty() or not at_war(w, wb["faction"], town["faction"]):
		return
	var units: Array = wb["units"]
	var n := units.size()
	TownDefence.set_muster(game, town, true)
	var mil := assault_defence(game, town)
	if n == 0: return
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(w.get("seed", 0)), wid, int(game.day)])
	var sacked := r.randf() < float(n) / float(n + mil * 2)
	on_town_attacked(w, town["faction"], wb["faction"], sacked)
	Army.survived(wb)   # economy spec 2: a battle survived
	if sacked:
		Army.on_sack(w, town, wb["faction"])   # economy spec 2: the raiders carry a share of the treasury home
		Migration.note_attack(w, String(town["id"]), float(game.day))   # v0.034: its people fear for their lives
		town["wealth"] = maxi(1, int(town["wealth"]) - 1)
		add_war_losses(w, town["faction"], wb["faction"], mil / 2 + n / 4)
		CampaignWorld.log_event(game, "%s was sacked by %s." % [town["name"], CampaignWorld.faction_the(wb["faction"])])
		var fallen := []   # arms trade: the raiders hold the field
		for k in n / 4:
			if units.size() > 1:
				fallen.append(units.pop_at(r.randi() % units.size()))
		ArmsTrade.field(game, fallen, {"band": wb}, town["pos"])
	else:
		add_war_losses(w, town["faction"], wb["faction"], mil / 4 + n / 2)
		CampaignWorld.log_event(game, "The defenders of %s beat back %s." % [town["name"], CampaignWorld.faction_the(wb["faction"])])
		var fallen2 := []   # arms trade: the town holds the field
		for k in n / 2:
			if units.size() > 1:
				fallen2.append(units.pop_at(r.randi() % units.size()))
		ArmsTrade.field(game, fallen2, {"town": town}, town["pos"])
		CampaignWorld.weaken_faction(w, wb["faction"], n / 2)

## Bands allied with `fid` close to pos that would join its fight against `enemy`: total power.
static func ally_power(w: Dictionary, fid: String, enemy: String, pos: Vector2, exclude: Array, radius: float = 120.0) -> float:
	var dp = w.get("diplo")
	if dp == null:
		return 0.0
	var p := 0.0
	for wid in w["warbands"]:
		var o: Dictionary = w["warbands"][wid]
		if o["kind"] == "caravan" or exclude.has(wid) or o["faction"] == fid or o["faction"] == enemy:
			continue
		if (o["pos"] as Vector2).distance_squared_to(pos) > radius * radius:
			continue
		if allied(w, o["faction"], fid) and fights(w, o["faction"], enemy):
			p += CampaignWorld.band_power(o["units"])
	return p

# ================================================================== layer 2: the company
static func standing(game, fid: String) -> int:
	var dp = game.world.get("diplo")
	if dp != null:
		var p = dp["player"].get(fid)
		if p != null:
			return clampi(int(round(float(p["earned"]))) + int(p["comp"]) + dynasty_bonus(game, fid), -100, 100)
	return int(game.rep.get(fid, -40 if DB.factions.get(fid, {}).get("player_hostile", false) else 0))

static func earned(game, fid: String) -> int:
	var dp = game.world.get("diplo")
	if dp != null and dp["player"].has(fid):
		return int(round(float(dp["player"][fid]["earned"])))
	return int(game.rep.get(fid, 0))

static func comp_offset(game, fid: String) -> int:
	var dp = game.world.get("diplo")
	if dp != null and dp["player"].has(fid):
		return int(dp["player"][fid]["comp"])
	return 0

## Change earned standing with a faction, with a reason for the relations screen.
static func add_earned(game, fid: String, delta: float, why: String = "") -> void:
	var dp = game.world.get("diplo")
	if dp == null or not dp["player"].has(fid):
		if DB.factions.has(fid):   # factions outside diplomacy: the old reputation number
			game.rep[fid] = clampi(int(game.rep.get(fid, 0)) + int(delta), -100, 100)
		return
	var p: Dictionary = dp["player"][fid]
	p["earned"] = clampf(float(p["earned"]) + delta, -100.0, 100.0)
	_log(game, fid, int(round(delta)), why)
	_mirror(game, fid)

static func _log(game, fid: String, delta: int, why: String) -> void:
	var lg: Array = game.world["diplo"]["player"][fid]["log"]
	lg.append({"day": int(game.day) + 1, "delta": delta, "text": why if why != "" else "Reputation"})
	while lg.size() > LOG_SIZE:
		lg.pop_front()

static func _mirror(game, fid: String) -> void:
	game.rep[fid] = standing(game, fid)

static func _mirror_all(game) -> void:
	var dp = game.world.get("diplo")
	if dp == null:
		return
	for f in dp["player"]:
		game.rep[f] = standing(game, f)

# ---------------------------------------------------------------- standing moves
static func contract_gain(c: Dictionary) -> int:
	var size := int(c.get("size", 0))
	var t := 0.0
	if size > 0:
		t = clampf((size - 3) / 12.0, 0.0, 1.0)
	else:
		t = clampf((float(c.get("pay", 0)) / TownEcon.COIN - 150.0) / 850.0, 0.0, 1.0)   # coinage: pay in coins
	return int(round(lerpf(CONTRACT_DONE_MIN, CONTRACT_DONE_MAX, t)))

static func on_contract_done(game, c: Dictionary) -> void:
	var emp: String = c.get("employer", "")
	add_earned(game, emp, contract_gain(c), "Contract fulfilled: %s" % c.get("title", ""))
	_taking_sides(game, c)

static func on_contract_failed(game, c: Dictionary) -> void:
	add_earned(game, c.get("employer", ""), CONTRACT_FAILED, "Contract failed: %s" % c.get("title", ""))

static func on_contract_abandoned(game, c: Dictionary) -> void:
	add_earned(game, c.get("employer", ""), CONTRACT_ABANDONED, "Contract abandoned: %s" % c.get("title", ""))

## Contract against Y while the employer X is at WAR with Y: X +2 extra, Y -2 extra.
static func _taking_sides(game, c: Dictionary) -> void:
	var x: String = c.get("employer", ""); var y: String = c.get("target_faction", "")
	if x == "" or y == "" or not at_war(game.world, x, y):
		return
	add_earned(game, x, TAKING_SIDES, "Fought for them in their war with %s" % CampaignWorld.faction_the(y))
	add_earned(game, y, -TAKING_SIDES, "Took %s's side in the war" % CampaignWorld.faction_name(x))

## The company fights a band of fid (-10; -5 when they attacked first).
static func on_fight(game, fid: String, they_attacked: bool) -> void:
	if they_attacked:
		add_earned(game, fid, FIGHT_DEFENDING, "Fought off a band of theirs that attacked us")
	else:
		add_earned(game, fid, FIGHT, "Attacked a band of theirs")

static func on_raid(game, fid: String) -> void:
	add_earned(game, fid, RAID_CARAVAN, "Raided one of their caravans")

# Prisoner moves (spec point 7): built as functions, nothing calls them until prisoners exist.
static func on_ransom(game, fid: String) -> void:
	add_earned(game, fid, RANSOM, "Ransomed captives back to them")

static func on_release(game, fid: String) -> void:
	add_earned(game, fid, RELEASE, "Released captives of theirs")

static func on_execute(game, fid: String, heads: int) -> void:
	add_earned(game, fid, maxi(EXECUTE_CAP, EXECUTE_PER_HEAD * heads), "Executed %d captives" % heads)

static func on_sell_to_slavers(game, heads: int) -> void:
	for f in data().get("opposes_slavery", []):
		add_earned(game, f, SLAVERS_PER_HEAD * heads, "Sold %d captives to slavers" % heads)

# ---------------------------------------------------------------- band composition
## comp_offset = 20 * weighted mean attitude over the band's races (1 per unit, 2 per officer), capped +-20.
static func comp_offset_for(units: Array, fid: String) -> int:
	var num := 0.0; var den := 0.0
	for u in units:
		if u.dead:
			continue
		var wgt := 2.0 if u.is_officer() else 1.0
		num += wgt * attitude(fid, u.race)
		den += wgt
	if den <= 0.0:
		return 0
	return clampi(int(round(COMP_MAX * num / den)), -COMP_MAX, COMP_MAX)

## Cheap fingerprint of who is in the company (size, officers, races); checked once a day.
static func _roster_sig(game) -> int:
	var h: int = game.company.size()
	for u in game.company:
		if not u.dead:
			h = h * 31 + u.uid * (2 if u.is_officer() else 1)
	return h

## Recalculate comp offsets when the roster changed (daily, after hires/dismissals/deaths, on the screen).
static func sync_comp(game, force: bool = false) -> void:
	var dp = game.world.get("diplo")
	if dp == null:
		return
	var sig := _roster_sig(game)
	if not force and sig == int(dp.get("comp_sig", -1)):
		return
	dp["comp_sig"] = sig
	for f in dp["player"]:
		dp["player"][f]["comp"] = comp_offset_for(game.company, f)
	_mirror_all(game)

static func roster_changed(game) -> void:
	sync_dynasty(game)
	sync_comp(game)

## "Two orcs among your officers: -8 with the Silvered Court." (the race that moves the offset most).
static func comp_line(game, fid: String) -> String:
	var per := {}   # race -> [officers, troops]
	var den := 0.0
	for u in game.company:
		if u.dead:
			continue
		if not per.has(u.race):
			per[u.race] = [0, 0]
		if u.is_officer():
			per[u.race][0] += 1; den += 2.0
		else:
			per[u.race][1] += 1; den += 1.0
	if den <= 0.0:
		return "No one in the company."
	var best := ""; var bc := 0.0
	for r in per:
		var c: float = COMP_MAX * attitude(fid, r) * (2.0 * per[r][0] + per[r][1]) / den
		if absf(c) > absf(bc) or best == "":
			best = r; bc = c
	var pl: String = DB.races.get(best, {}).get("plural", best + "s")
	var sg: String = DB.races.get(best, {}).get("name", best)
	var o: int = per[best][0]; var t: int = per[best][1]
	var who := ""
	if o > 0 and t > 0:
		who = "%s %s among your officers and %s among the troops" % [_count_word(o).capitalize(), sg if o == 1 else pl, _count_word(t)]
	elif o > 0:
		who = "%s %s among your officers" % [_count_word(o).capitalize(), sg if o == 1 else pl]
	else:
		who = "%s %s in your ranks" % [_count_word(t).capitalize(), sg if t == 1 else pl]
	var total := comp_offset(game, fid)
	return "%s: %+d with %s (company make-up %+d in all)." % [who, int(round(bc)), CampaignWorld.faction_the(fid), total]

static func _count_word(n: int) -> String:
	var w := ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
	return w[n] if n < w.size() else str(n)

# ---------------------------------------------------------------- effects
static func player_hostile(game, fid: String) -> bool:
	if peace_bound(game.world, player_realm(game.world), fid): return false
	if not takes_part(game.world, fid):
		return int(game.rep.get(fid, 0)) <= CampaignWorld.HOSTILE_REP_LEGACY
	return standing(game, fid) <= HOSTILE_STANDING

static func friendly(game, fid: String) -> bool:
	return allied(game.world, player_realm(game.world), fid) or (takes_part(game.world, fid) and standing(game, fid) >= FRIENDLY_STANDING)

static func can_trade(game, fid: String) -> bool:
	return not player_hostile(game, fid)

static func contracts_allowed(game, fid: String) -> bool:
	return standing(game, fid) >= NO_CONTRACTS and not player_hostile(game, fid)

static func better_tier(game, fid: String) -> bool:
	return standing(game, fid) > FRIENDLY_STANDING

static func pay_mult(game, fid: String) -> float:
	return 1.0 + standing(game, fid) / 200.0

## Buying price multiplier in this faction's towns; selling uses the inverse direction (1 + standing/500).
static func price_mult(game, fid: String) -> float:
	return 1.0 - standing(game, fid) / 500.0

static func sell_mult(game, fid: String) -> float:
	return 1.0 + standing(game, fid) / 500.0

## How many of a town's recruits will talk to the company (own race of the faction: halved below -20,
## none below -50). Recruits of other races are unaffected.
static func recruit_ok(game, town: Dictionary, u: Unit, index_of_race: int, count_of_race: int) -> bool:
	var fid: String = town.get("faction", "")
	if u.race != DB.factions.get(fid, {}).get("race", ""):
		return true
	var s := standing(game, fid)
	if s <= HOSTILE_STANDING:
		return false
	if s < RECRUITS_HALVED:
		return index_of_race < int(ceil(count_of_race / 2.0))
	return true

static func visible_recruits(game, town: Dictionary) -> Array:
	var recs: Array = town.get("recruits", [])
	var race: String = DB.factions.get(town.get("faction", ""), {}).get("race", "")
	var total := 0
	for r in recs:
		if r.race == race:
			total += 1
	var out := []
	var i := 0
	for r in recs:
		if recruit_ok(game, town, r, i, total):
			out.append(r)
		if r.race == race:
			i += 1
	return out

## "Friendly", "Hostile" ... the company's standing in words.
static func standing_word(s: int) -> String:
	if s <= HOSTILE_STANDING: return "Hostile"
	if s < RECRUITS_HALVED: return "Unfriendly"
	if s < 20: return "Neutral"
	if s < FRIENDLY_STANDING: return "Well regarded"
	return "Friendly"

static func disposition(game, fid: String) -> String:
	if player_hostile(game, fid): return "hostile"
	if friendly(game, fid): return "friendly"
	return "neutral"

## One line of what the standing does right now (relations screen).
static func effects_text(game, fid: String) -> String:
	var s := standing(game, fid)
	var parts := []
	if player_hostile(game, fid):
		return "Their gates are barred, their armies attack on sight and nobody will hire you."
	if not contracts_allowed(game, fid):
		parts.append("no contracts")
	else:
		parts.append("contract pay x%.2f%s" % [pay_mult(game, fid), ", veteran contracts" if better_tier(game, fid) else ""])
	parts.append("prices x%.2f" % price_mult(game, fid))
	if s < RECRUITS_HALVED:
		parts.append("half the usual recruits")
	if friendly(game, fid):
		parts.append("their patrols join your fights")
	var txt := ", ".join(parts)
	return txt.substr(0, 1).to_upper() + txt.substr(1) + "."

static func log_of(game, fid: String) -> Array:
	var dp = game.world.get("diplo")
	if dp == null or not dp["player"].has(fid):
		return []
	return dp["player"][fid]["log"]
