class_name Renown
extends RefCounted
## Kill renown (economy spec 2, section 4): a lifetime score per unit. Each kill adds the victim's worth: a
## recruit/grunt 1, more per enemy rank (data army.kill_worth by rank index; a company officer counts as rank 2),
## plus renown_share of the victim's own renown; monsters by rarity tier (army.monster_worth: wolf 1, bear 5,
## troll lair 20, EPIC hydra 100, LEGENDARY dragon 300) [ours, tuned]. The best kills are kept as notable
## [[victim, worth, day]]. Called by the battle sim on every kill (player battles, succession fights, later AI
## clashes). Renown is one weighted term in every weighted rank rule (campaign/army.gd), except orcs.

static func A() -> Dictionary:
	return TownEcon.data()["army"]

static func worth(victim: Unit) -> float:
	var a := A()
	var rd: Dictionary = victim.race_def()
	var base := 1.0
	if rd.get("creature", false):
		base = float(a["monster_worth"].get(String(rd.get("rarity", "common")), 1))
	else:
		var r := victim.rank
		if victim.faction == "player" and victim.is_officer():
			r = maxi(r, 2)
		var kw: Array = a["kill_worth"]
		base = float(kw[clampi(r, 0, kw.size() - 1)])
	return base + float(a["renown_share"]) * victim.renown

static func on_kill(killer: Unit, victim: Unit) -> void:
	if killer == null or victim == null:
		return
	var v := worth(victim)
	killer.renown += v
	Legends.on_kill(killer, victim)   # v0.014: a legendary weapon counts its kills
	var day := int(Game.day)
	var nb: Array = killer.notable
	nb.append([victim.name, snappedf(v, 0.1), day])
	nb.sort_custom(func(x, y): return float(x[1]) > float(y[1]))
	while nb.size() > int(A()["notable"]):
		nb.pop_back()

## "Renown 23: Grukk Bonesaw (warboss, 9), Old Ragged (wolf, 1) ..." for the unit card.
static func lines(u: Unit) -> Array:
	var out := ["Renown %d" % int(round(u.renown))]
	for n in u.notable:
		out.append("%s (%s renown, %s)" % [String(n[0]), str(snappedf(float(n[1]), 0.1)), Calendar.text(float(n[2])).split(" - ")[0]])
	return out
