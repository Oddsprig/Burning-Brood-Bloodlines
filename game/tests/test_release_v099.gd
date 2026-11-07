extends RefCounted
## v0.099 release candidate, one short headless run on the DevTools start world:
##   1. in a battle of rounds your fit dragons fight every round. Game.start_battle appends them after every man,
##      and rounds took the first 100 in pool order, so with 100+ men a bonded dragon never fought.
##   2. the battle inspector speaks words: "(80% done)" and "Speed: steady", not "(12/15 ticks)" and "Speed 944 (lower is faster)".
##   3. the store build: shown name without "Claude Edition", saves folder unchanged, version and export presets.
##   4. Muster says why no family member can ride (they serve with the realm's army, the town guard or a caravan).
##   godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_release_v099.gd --watchdog=170
var fails := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL v099: " + message)
	print(("ok   " if ok else "FAIL ") + message)

func troops(faction: String, n: int, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	for i in n:
		out.append(Factory.make_troop(rng, faction, DB.factions[faction]["troops"][i % 2], 2))
	return out

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "DevTools start world loads")
		return fails
	var tid := DevTools.choose_house(Game)
	check(tid != "", "a house is chosen")
	if tid == "": return fails
	DevTools.stand_at(Game, tid)
	dragons_in_rounds(tid)
	inspector_words()
	muster_words()
	store_build()
	print("v099 checks %d, failures %d, %d ms" % [checks, fails, Time.get_ticks_msec() - started])
	return fails

# ------------------------------------------------------------------ 1. dragons fight in a battle of rounds
func dragons_in_rounds(tid: String) -> void:
	var ruler_uid := str(Dynasty.selected(Game).get("ruler_uid", ""))
	var owner := Dragons._person(Game, ruler_uid)
	Game.world["dragons"] = {"schema": 1, "next_id": 1, "records": {}, "pairs": {}, "initialized": true}
	var r1 := Dragons._make(Game, "adult", tid, owner, "v099:a", 0, "female")
	var r2 := Dragons._make(Game, "adult", tid, owner, "v099:b", 0, "male")
	DragonCombat.prepare_world(Game)
	var d1: Unit = DragonCombat._unit(Game, str(r1["id"]))
	var d2: Unit = DragonCombat._unit(Game, str(r2["id"]))
	check(d1 != null and d2 != null and BattleRounds._can_fight(Game, d1) and BattleRounds._can_fight(Game, d2), "rounds: two whole adult dragons")
	if d1 == null or d2 == null: return
	var saved_round := BattleRounds.round_size
	BattleRounds.round_size = 4
	var mine := troops("middle_kingdom", 10, 9911)   # over twice a round: before v0.099 the dragons never got in
	for u in mine: u.faction = "player"
	var pool: Array = mine + [d1, d2]   # the order Game.start_battle builds: every man, then the dragons
	var foes := troops("northern_clans", 12, 9912)
	Game.pending_battle = {"seed": 99, "enemy": foes}
	BattleRounds.begin(Game, pool, foes)
	var r: Array = Game.pending_battle["round_side0"]
	check(r.has(d1) and r.has(d2), "rounds: both dragons fight round 1 though more men wait than a round holds (%d picked)" % r.size())
	check(r.size() == BattleRounds.round_size, "rounds: the round is still %d a side" % BattleRounds.round_size)
	BattleRounds.next_round(Game)
	r = Game.pending_battle["round_side0"]
	check(r.has(d1) and r.has(d2), "rounds: fit dragons fight the next round too (they do not sit out as tired)")
	var men_now := r.filter(func(u): return not DragonCombat.is_dragon_unit(Game, u))
	check(men_now.all(func(u): return not mine.slice(0, 2).has(u)), "rounds: the men still rotate: round 1's men rest while the others fight")
	d2.body.blood = d2.body.blood_max * 0.05   # badly hurt: "cannot fight"
	BattleRounds.next_round(Game)
	r = Game.pending_battle["round_side0"]
	check(r.has(d1) and not r.has(d2), "rounds: a dragon too hurt to fight still sits out (v0.097 rule kept)")
	BattleRounds.round_size = saved_round
	Game.pending_battle = {}

# ------------------------------------------------------------------ 2. inspector words
func inspector_words() -> void:
	var Insp = load("res://battle/inspector.gd")
	check(Insp.action_done_pct(15, 3) == 80 and Insp.action_done_pct(15, 15) == 0 and Insp.action_done_pct(15, 0) == 100, "inspector: action progress in percent (12 of 15 ticks = 80%)")
	check(Insp.action_done_pct(0, 0) == 100 and Insp.action_done_pct(4, 9) == 0, "inspector: odd tick counts stay within 0..100")
	check(Insp.pace_word(0.8) == "quick" and Insp.pace_word(1.0) == "steady" and Insp.pace_word(1.3) == "slowed" and Insp.pace_word(2.0) == "badly slowed", "inspector: pace words from tempo")
	var src := FileAccess.get_file_as_string("res://battle/inspector.gd")
	check(not src.contains("lower is faster") and not src.contains("ticks)\""), "inspector: no raw ticks or DF speed number left in the state line")

# ------------------------------------------------------------------ 3. store build
func store_build() -> void:
	var name_ := str(ProjectSettings.get_setting("application/config/name", ""))
	check(name_ == "Burning Brood: Bloodlines", "store: shown name is Burning Brood: Bloodlines (got %s)" % name_)
	check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")) == "Burning Brood Bloodlines Claude Edition", "store: the save folder name is unchanged, so old saves still load")
	check(str(ProjectSettings.get_setting("application/config/version", "")) == "0.099", "store: version 0.099")
	check(not FileAccess.get_file_as_string("res://ui/title.gd").contains("Claude Edition") and not FileAccess.get_file_as_string("res://main.gd").contains("Claude Edition"), "store: title screen and window title drop Claude Edition")
	var splash := str(ProjectSettings.get_setting("application/boot_splash/image", ""))
	check(splash != "" and FileAccess.file_exists(splash), "store: the boot splash image exists (%s)" % splash)
	var cfg := ConfigFile.new()
	check(cfg.load("res://export_presets.cfg") == OK, "store: export presets load")
	var by_name := {}
	for sec in cfg.get_sections():
		if sec.begins_with("preset.") and not sec.ends_with(".options"): by_name[str(cfg.get_value(sec, "name", ""))] = sec
	check(by_name.has("Windows Desktop") and by_name.has("Android"), "store: Windows Desktop and Android presets")
	if not (by_name.has("Windows Desktop") and by_name.has("Android")): return
	var w: String = by_name["Windows Desktop"] + ".options"
	var a: String = by_name["Android"] + ".options"
	check(cfg.get_value(w, "binary_format/embed_pck", false) == true and str(cfg.get_value(w, "binary_format/architecture", "")) == "x86_64", "store: Windows is one 64-bit .exe with the game inside")
	check(FileAccess.file_exists(str(cfg.get_value(w, "application/icon", ""))), "store: the Windows icon file exists")
	check(str(cfg.get_value(a, "version/name", "")) == "0.099" and int(cfg.get_value(a, "version/code", 0)) == 99, "store: Android version 0.099 (code 99)")
	check(str(cfg.get_value(a, "keystore/release_password", "")) == "" and str(cfg.get_value(a, "keystore/release", "")) == "", "store: no release key or password in the committed presets")
	for k in ["launcher_icons/main_192x192", "launcher_icons/adaptive_foreground_432x432", "launcher_icons/adaptive_background_432x432", "launcher_icons/adaptive_monochrome_432x432"]:
		check(FileAccess.file_exists(str(cfg.get_value(a, k, ""))), "store: Android %s exists" % k.get_file())
	for sec in [by_name["Windows Desktop"], by_name["Android"]]:
		check(str(cfg.get_value(sec, "exclude_filter", "")).contains("tests/*"), "store: %s leaves the tests out" % cfg.get_value(sec, "name", ""))

# ------------------------------------------------------------------ 4. muster words
func muster_words() -> void:
	var M = load("res://ui/muster.gd")
	var adult := int(People.ages("human")["adult"])
	var rows := [{"state": "army", "age": adult + 4, "race": "human"}, {"state": "army", "age": adult + 10, "race": "human"},
		{"state": "militia", "age": adult + 1, "race": "human"}, {"state": "army", "age": 2, "race": "human"}, {"state": "", "age": 3, "race": "human"}]
	var t: String = M.no_riders_text(rows)
	check(t.begins_with("No adult family members are free to ride with the army.") and t.contains("2 with the realm's field army") and t.contains("1 in the town guard"), "muster: says who is away serving (%s)" % t)
	check(M.no_riders_text([{"state": "", "age": 3, "race": "human"}]) == "No adult family members are free to ride with the army.", "muster: plain line when nobody is away")
