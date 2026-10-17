class_name ClashRounds
extends RefCounted
## Off-screen army-vs-army battles fought in literal rounds (written by Sol 6.1 through the bridge, reviewed here):
## up to ROUND fit men from each army meet until that clash is decided, then the next pair goes in. Wounded sit
## out; the round's loser leaves prisoners; morale and officer losses decide when an army breaks.

const ROUND: int = 100
const MAX_ROUNDS: int = 20
const BREAK_MORALE: float = 25.0


## Resolves a battle using only the supplied RNG for randomness.
static func resolve(a_n: int, b_n: int, a_pow: float, b_pow: float, a_officers: int, b_officers: int,
		rng: RandomNumberGenerator, a_morale: float = 70.0, b_morale: float = 70.0) -> Dictionary:
	var a: Dictionary = _army(a_n, a_officers, a_morale)
	var b: Dictionary = _army(b_n, b_officers, b_morale)
	var a_power: float = a_pow if a_pow > 0.0 else 1.0
	var b_power: float = b_pow if b_pow > 0.0 else 1.0
	var rounds: int = 0
	var battle_log: Array[Dictionary] = []
	while rounds < MAX_ROUNDS and not _broken(a) and not _broken(b):
		rounds += 1
		var a_in: int = mini(ROUND, int(a["fit"]))
		var b_in: int = mini(ROUND, int(b["fit"]))
		# Normalize powers before squaring to avoid overflowing combat strengths.
		var power_scale: float = maxf(a_power, b_power)
		var a_strength: float = float(a_in) * (a_power / power_scale)
		var b_strength: float = float(b_in) * (b_power / power_scale)
		var a_squared: float = a_strength * a_strength
		var b_squared: float = b_strength * b_strength
		var p: float = a_squared / maxf(0.0001, a_squared + b_squared)
		var a_won: bool = rng.randf() < p
		var a_losses: int = _roll_losses(a_in, a_power, b_power, a_won, rng)
		var b_losses: int = _roll_losses(b_in, b_power, a_power, not a_won, rng)
		var a_result: Dictionary = _apply_losses(a, a_in, a_losses, a_won, rng)
		var b_result: Dictionary = _apply_losses(b, b_in, b_losses, not a_won, rng)
		battle_log.append({"round": rounds, "a_in": a_in, "b_in": b_in, "winner": "a" if a_won else "b",
			"a_dead": a_result["dead"], "a_wounded": a_result["wounded"], "a_captured": a_result["captured"],
			"b_dead": b_result["dead"], "b_wounded": b_result["wounded"], "b_captured": b_result["captured"],
			"a_morale": a["morale"], "b_morale": b["morale"]})
	var a_broken: bool = _broken(a)
	var b_broken: bool = _broken(b)
	var winner: String
	if a_broken != b_broken:
		winner = "b" if a_broken else "a"
	elif float(a["morale"]) != float(b["morale"]):
		winner = "a" if float(a["morale"]) > float(b["morale"]) else "b"
	else:
		winner = "a" if rng.randf() < 0.5 else "b"
	# Both broken armies flee; at the round limit, the defeated army retreats.
	if a_broken or winner == "b":
		_flee(a)
	if b_broken or winner == "a":
		_flee(b)
	return {"winner": winner, "rounds": rounds, "a": _report(a), "b": _report(b), "log": battle_log}


## Creates an army with bounded counts and its original officer probability.
static func _army(men: int, officers: int, morale: float) -> Dictionary:
	var count: int = maxi(0, men)
	var officer_count: int = clampi(officers, 0, count)
	return {"starting": count, "fit": count, "dead": 0, "wounded": 0, "captured": 0, "fled": 0,
		"officers": officer_count, "officers_lost": 0,
		"officer_chance": float(officer_count) / float(count) if count > 0 else 0.0,
		"morale": clampf(morale, 0.0, 100.0)}


## Scales a random casualty share by opposing power divided by own power.
static func _roll_losses(sent: int, own_power: float, enemy_power: float, won: bool, rng: RandomNumberGenerator) -> int:
	var share: float = rng.randf_range(0.10, 0.30) if won else rng.randf_range(0.35, 0.60)
	var scaled: float = float(sent) * share * (enemy_power / own_power)
	return clampi(roundi(clampf(scaled, 0.0, float(sent))), 0, sent)


## Removes casualties from fit men, samples officer losses, and updates morale.
static func _apply_losses(army: Dictionary, sent: int, losses: int, won: bool, rng: RandomNumberGenerator) -> Dictionary:
	var casualties: int = clampi(losses, 0, mini(sent, int(army["fit"])))
	var dead: int = clampi(roundi(float(casualties) * 0.40), 0, casualties)
	var captured: int = 0
	if not won:
		captured = clampi(roundi(float(casualties) * 0.15), 0, casualties - dead)
	var wounded: int = casualties - dead - captured
	var officers_lost: int = 0
	var available_officers: int = int(army["officers"]) - int(army["officers_lost"])
	var officer_chance: float = float(army["officer_chance"])
	for _casualty in range(casualties):
		if officers_lost >= available_officers:
			break
		if rng.randf() < officer_chance:
			officers_lost += 1
	army["fit"] = int(army["fit"]) - casualties
	army["dead"] = int(army["dead"]) + dead
	army["wounded"] = int(army["wounded"]) + wounded
	army["captured"] = int(army["captured"]) + captured
	army["officers_lost"] = int(army["officers_lost"]) + officers_lost
	var loss_share: float = float(casualties) / float(sent) if sent > 0 else 0.0
	var morale_delta: float
	if won:
		morale_delta = 4.0 - 10.0 * loss_share - 5.0 * float(officers_lost)
	else:
		morale_delta = -12.0 - 30.0 * loss_share - 8.0 * float(officers_lost)
	army["morale"] = clampf(float(army["morale"]) + morale_delta, 0.0, 100.0)
	return {"dead": dead, "wounded": wounded, "captured": captured}


## Treats all casualties, including wounded, as losses toward the break threshold.
static func _broken(army: Dictionary) -> bool:
	var starting: int = int(army["starting"])
	var fit: int = int(army["fit"])
	return float(army["morale"]) < BREAK_MORALE or fit <= 0 or float(starting - fit) > float(starting) * 0.60


## Moves every remaining fit soldier into fled without adding casualties.
static func _flee(army: Dictionary) -> void:
	army["fled"] = int(army["fled"]) + int(army["fit"])
	army["fit"] = 0


## Returns public totals, with left including fit, wounded, and fled soldiers.
static func _report(army: Dictionary) -> Dictionary:
	return {"dead": int(army["dead"]), "wounded": int(army["wounded"]), "captured": int(army["captured"]),
		"fled": int(army["fled"]), "left": int(army["starting"]) - int(army["dead"]) - int(army["captured"]),
		"officers_lost": int(army["officers_lost"]), "morale": float(army["morale"])}
