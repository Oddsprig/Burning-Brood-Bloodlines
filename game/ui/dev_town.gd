class_name DevTown
extends RefCounted
## Local stand-in for a campaign town (world contract shape) so the town screen can be developed and
## tested before campaign/ lands. The town screen only uses it when Game.world.towns lacks Game.location.

const BACKSTORIES := [
	"A miller's son who ran from debts and a jealous husband. Knows which end of a spear goes forward.",
	"Served two winters on the border palisade until the lord stopped paying. Bitter about it.",
	"A tanner's apprentice with strong hands and a quick temper. Has never seen a real battle.",
	"Former caravan guard; the caravan was not so lucky. Says little and sleeps lightly.",
	"Third daughter of a smallholder; the farm went to her brothers and she went to the road.",
	"Poacher, by the look of the scars. Swears it was all a misunderstanding with the forester.",
	"Deserted a lord's levy after a rout. Fights well when cornered and badly when not.",
	"A wandering wrestler from the fairs, tired of breaking noses for copper bits.",
]

static func make(id: String = "dev_town", seed_value: int = 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var fid := "middle_kingdom"
	var shop := []
	var tids := ["arming_sword", "boar_spear", "flanged_mace", "dane_axe", "kite_shield", "mail_shirt",
		"mail_shirt", "nasal_helm", "nasal_helm", "mail_coif", "splint_greaves", "tunic", "tunic", "shoes",
		"trousers", "bearded_axe", "round_shield", "mail_byrnie", "glaive"]
	for tid in tids:
		shop.append(Factory.make_item(rng, tid, 3))
	var recruits := []
	for i in 5:
		var f: String = ["middle_kingdom", "middle_kingdom", "northern_clans", "middle_kingdom", "northern_clans"][i]
		var r := Factory.make_troop(rng, f, Factory.pick_troop(rng, f), 1)
		r.backstory = BACKSTORIES[rng.randi() % BACKSTORIES.size()]
		r.hire_cost = Roster.hire_cost(r)
		r.wage = Roster.wage_of(r)
		r.equip.clear()
		recruits.append(r)
	var contracts := [
		{"id": "c1", "kind": "battle", "employer": "Reeve Osric Thorne", "target_faction": "goblin_warren",
			"target_id": "", "pay": 420, "desc": "Goblins from the Warrens have burned two farmsteads east of the mill. Break the raiding band.",
			"deadline_day": 12, "town_id": id},
		{"id": "c2", "kind": "escort", "employer": "Petra Kettle, wool merchant", "target_faction": "",
			"target_id": "", "pay": 260, "desc": "Escort three wool wagons to the next market town without losing a bale.",
			"deadline_day": 9, "town_id": id},
	]
	return {"id": id, "name": "Brannoc's Ford", "pos": Vector2(400, 300), "faction": fid, "size": 2, "wealth": 3,
		"specialty": "copper smelting",
		"crafters": {"weaponsmith": {"name": "Gerd Ironside", "skill": 7}, "armorsmith": {"name": "Hild Greaves", "skill": 3}},
		"shop": shop, "prices": {}, "recruits": recruits, "healer": {"name": "Mother Liesel", "skill": 6},
		"contracts": contracts}

## Ensures Game.world.towns has `id` (installing a dev town if needed) and returns it.
static func ensure(game, id: String = "dev_town") -> Dictionary:
	if not game.world.has("towns"):
		game.world["towns"] = {}
	if not game.world["towns"].has(id):
		game.world["towns"][id] = make(id)
	return game.world["towns"][id]
