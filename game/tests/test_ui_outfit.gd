extends RefCounted
## Outfit logic: apply uniform from stash (best quality first), material rule, overrides,
## two-handed rule, missing-piece report, unequip back to stash.

var fails := 0

func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)

func run(_tree: SceneTree) -> int:
	Game.new_game(42)
	var off: Unit = Roster.leaders(Game)[1]
	var troops := Roster.troops_of(Game, off.uid)
	check(troops.size() == 3, "officer has 3 troops")
	for t in troops:
		Outfit.strip(t, Game.stash)
	Game.stash.clear()
	Game.squads[off.uid] = {"uniform": {"body": "mail_shirt"}, "material": "any"}
	var q0 := Item.make("mail_shirt", "copper", 0)
	var q3 := Item.make("mail_shirt", "copper", 3)
	Game.stash.append_array([q0, q3])
	var r := Outfit.apply_uniform(Game.squads, Game.company, off.uid, Game.stash)
	check(troops[0].equip.get("body") == q3, "best quality goes first")
	check(troops[1].equip.get("body") == q0, "second troop gets the lesser shirt")
	check(not troops[2].equip.has("body"), "third troop has none")
	check(r["missing"].size() == 1 and r["lines"][0] == "1 x mail shirt missing", "missing report: %s" % [r["lines"]])
	check(Game.stash.is_empty(), "stash emptied")
	# material rule
	Game.squads[off.uid]["material"] = "copper"
	Game.stash.append(Item.make("mail_shirt", "tin", 5))
	r = Outfit.apply_uniform(Game.squads, Game.company, off.uid, Game.stash)
	check(not troops[2].equip.has("body"), "tin shirt refused under copper rule")
	check(r["lines"][0] == "1 x copper mail shirt missing", "material in report: %s" % [r["lines"]])
	# linen tunic satisfies a copper rule
	Game.squads[off.uid]["uniform"]["clothing"] = "tunic"
	for i in 3:
		Game.stash.append(Item.make("tunic", "linen", 0))
	Outfit.apply_uniform(Game.squads, Game.company, off.uid, Game.stash)
	check(troops.all(func(t): return t.equip.has("clothing")), "linen tunics pass a copper rule")
	# upgrade: a better copper shirt replaces the q0 one; old goes to stash
	var q5 := Item.make("mail_shirt", "copper", 5)
	Game.stash.append(q5)
	Outfit.apply_uniform(Game.squads, Game.company, off.uid, Game.stash)
	check(q5 in [troops[0].equip.get("body"), troops[1].equip.get("body")], "better piece upgrades")
	check(Game.stash.has(q0) or troops[2].equip.get("body") == q0, "replaced piece returned to stash or reused")
	# override
	troops[0].overrides["helm"] = "mail_coif"
	var coif := Item.make("mail_coif", "copper", 1)
	Game.stash.append(coif)
	Game.stash.append(Item.make("nasal_helm", "copper", 4))
	Outfit.outfit_unit(Game.squads, troops[0], Game.stash)
	check(troops[0].equip.get("helm") == coif, "override picks the coif")
	troops[0].overrides["body"] = ""
	Outfit.outfit_unit(Game.squads, troops[0], Game.stash)
	check(not troops[0].equip.has("body"), "override '' strips the slot")
	# two-handed rule
	Game.squads[off.uid]["uniform"]["main_hand"] = "dane_axe"
	Game.squads[off.uid]["uniform"]["off_hand"] = "kite_shield"
	var w := Outfit.wanted(Game.squads, troops[1])
	check(w.get("off_hand", "x") == "", "two-handed uniform wants no shield")
	var shield := Item.make("kite_shield", "copper", 0)
	troops[1].equip["off_hand"] = shield
	Game.stash.append(Item.make("dane_axe", "copper", 2))
	Outfit.outfit_unit(Game.squads, troops[1], Game.stash)
	check(troops[1].weapon() != null and troops[1].weapon().tid == "dane_axe", "dane axe equipped")
	check(not troops[1].equip.has("off_hand") and Game.stash.has(shield), "shield returned to stash")
	var err := Outfit.equip_item(troops[1], shield, Game.stash)
	check(err != "" and not troops[1].equip.has("off_hand"), "cannot equip a shield with a two-hander: " + err)
	# officer individual equip: a two-hander bumps the shield
	var o_sh := Item.make("kite_shield", "copper", 0)
	Game.stash.append(o_sh)
	check(Outfit.equip_item(off, o_sh, Game.stash) == "" or off.weapon() != null, "officer equips from stash")
	var gaxe := Item.make("dane_axe", "tin", 0)
	Game.stash.append(gaxe)
	Outfit.equip_item(off, gaxe, Game.stash)
	check(off.weapon() == gaxe and not off.equip.has("off_hand"), "two-hander unequips officer's shield")
	# unequip
	var n := Game.stash.size()
	Outfit.unequip(off, "main_hand", Game.stash)
	check(Game.stash.size() == n + 1 and off.weapon() == null, "unequip returns to stash")
	# shortfall dry run doesn't mutate
	var before := Game.stash.size()
	var sf := Outfit.shortfall(Game.squads, Game.company, Game.stash)
	check(Game.stash.size() == before, "shortfall is a dry run")
	print("shortfall: ", sf)
	return fails
