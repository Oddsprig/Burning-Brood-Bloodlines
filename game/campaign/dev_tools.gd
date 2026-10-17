class_name DevTools
extends RefCounted
## Developer tools: put the game straight into the state a check needs instead of simulating its way there
## (TEST TIME RULE in AGENTS.md: a test runs in under a minute, three at most). Every tool goes through the game's own
## code (muster, pregnancies, incubation, attacks, famine stages, sickness cases), so the state it makes is a real
## game state; a tool only skips the waiting. Tests use these; an in-game developer panel can call the same functions.

## ------------------------------------------------------------------ the saved start world
## The small world every test uses (Normal, seed 4242, one-day history, no house chosen) is generated once and kept
## as a save in user://fixtures; later starts load it in a few seconds. The file name carries the game version and
## WORLD_VERSION: bump WORLD_VERSION when a change to world generation or the save format makes an older one wrong.
const WORLD_VERSION := 1
const WORLD_DIR := "user://fixtures"
const WORLD_SEED := 4242

static func world_path(creatures: bool = false) -> String:
	return "%s/world%s_%s_v%d.json" % [WORLD_DIR, "_creatures" if creatures else "", str(ProjectSettings.get_setting("application/config/version", "dev")), WORLD_VERSION]

## Loads the start world (making and saving it the first time). Later saves go to save_path. False if it failed.
## creatures: the world with creatures on the map (lairs, packs, dens); the default world has none.
static func start_world(tree: SceneTree, save_path: String, creatures: bool = false) -> bool:
	Game.wait_save()
	var file := world_path(creatures)
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	Monsters.new_world_creatures = creatures
	if not FileAccess.file_exists(file):
		var t0 := Time.get_ticks_msec()
		var generation := Game.new_game_begin(WORLD_SEED)
		while not Game.new_game_slice(generation, 8000): await tree.process_frame
		var history := {}
		while CampaignWorld.presim_left(Game) > 0:
			CampaignWorld.presim_slice(Game, history, 8000)
			await tree.process_frame
		CampaignWorld.presim_finish(Game, 0)
		Dynasty.prepare_world(Game); Game.new_game_finalize()
		DirAccess.make_dir_recursive_absolute(WORLD_DIR)
		Game.SAVE_PATH = file
		Game.save_game(); Game.wait_save()
		print("dev: made the start world %s in %d ms" % [file, Time.get_ticks_msec() - t0])
	var t1 := Time.get_ticks_msec()
	Game.SAVE_PATH = file
	Game.world = {}; Game.rep = {}
	var ok := Game.load_game()
	Game.SAVE_PATH = save_path
	print("dev: loaded the start world in %d ms" % (Time.get_ticks_msec() - t1))
	return ok

## ------------------------------------------------------------------ houses and armies
## Chooses the ruling house of the most populous seat that can be chosen (filter: optional func(choice) -> bool).
## Returns its town id, or "".
static func choose_house(game, filter: Callable = Callable()) -> String:
	var by_pop: Array = Dynasty.choices(game)
	by_pop.sort_custom(func(a, b): return int(game.world["towns"][a["town_id"]]["econ"]["pop"]) > int(game.world["towns"][b["town_id"]]["econ"]["pop"]))
	for choice: Dictionary in by_pop:
		if filter.is_valid() and not bool(filter.call(choice)): continue
		if bool(HouseOnboarding.begin(game, str(choice["town_id"]), str(choice["household_uid"])).get("ok", false)):
			return str(choice["town_id"])
	return ""

## Stands the party at a town of the house (in person, as muster requires).
static func stand_at(game, tid: String) -> void:
	game.location = tid
	game.world["party"]["pos"] = game.world["towns"][tid]["pos"]
	game.world["party"]["path"] = []
	game.world["encounter"] = ""

## Raises n real residents of a house town through the native muster (funded from the house purse). Returns how many.
static func raise_army(game, tid: String, n: int) -> int:
	stand_at(game, tid)
	var purse := float(Feudal._payer(game).get("purse", 0.0))
	Mobilization.fund(game, int(floor(purse * 0.6)))
	var quote: Dictionary = Mobilization.quote(game, tid, n)
	if not quote.get("ok", false): return 0
	var before: int = game.company.size()
	Mobilization.muster(game, tid, n, quote["review"])
	return game.company.size() - before

## ------------------------------------------------------------------ time-skips through the game's own state
## A woman of a family carries a child due in `days` (the native Persons.childbearing pregnancy record); it is born
## at the family's next weekly turn on or after that day.
static func due_birth(game, mother_uid: String, father_uid: String, days: float = 1.0) -> bool:
	var mo := Dynasty._person(game, mother_uid)
	if mo.is_empty(): return false
	var fa := Dynasty._person(game, father_uid)
	var f: Dictionary = mo["family"]
	if not f.has("preg"): f["preg"] = []
	var father_pid := int(fa["person"][0]) if not fa.is_empty() and is_same(fa["family"], f) else -1
	f["preg"].append([int(mo["person"][0]), float(game.day) + days, father_pid])
	return true

## An egg a hair short of hatching (DragonLife's incubation count): it hatches on the next day DragonCare settles,
## whatever its care (each settled day adds at least 0.25), unless its health is below DragonLife's floor.
static func egg_almost_hatched(game, egg_id: String) -> bool:
	var row: Dictionary = game.world.get("dragons", {}).get("records", {}).get(egg_id, {})   # the live record (Dragons.get_record copies)
	if row.is_empty() or str(row.get("stage", "")) != "egg": return false
	row["incubation"] = float(DragonLife.HATCH_DAYS) - 0.01
	return true

## Runs n whole campaign days with every queued job finished (keep n small: a day is a full world update).
static func run_days(game, n: int) -> void:
	for d in n:
		game.advance_time(1.0, false, 0, 0)
		while not game.world.get("work", []).is_empty(): CampaignWorld.work_slice(game, 50000)

## ------------------------------------------------------------------ population states (v0.034)
## A town is sacked, raided or taken today (its people flee for Migration.WAR_DAYS).
static func sack(game, tid: String) -> void:
	Migration.note_attack(game.world, tid, float(game.day))

## A town's famine stage (Barge: 2+ drives hunger flight).
static func famine(game, tid: String, stage: int) -> void:
	game.world["towns"][tid]["econ"]["fstage"] = stage

## n of a town's common folk fall sick with a disease today, through the native common-folk case path.
static func outbreak(game, tid: String, dis: String, n: int) -> int:
	var e: Dictionary = game.world["towns"][tid]["econ"]
	var b := Sickness.book(e)
	var rng := RandomNumberGenerator.new(); rng.seed = hash([tid, dis, n, int(game.day)])
	var left := n
	for f in e["fams"]:
		if left <= 0: break
		if not Population.is_cohort(f) or f.get("gone", false): continue
		var k := mini(left, Population.anonymous(f, 0) + Population.anonymous(f, 1))
		if k <= 0: continue
		Sickness._pool_infect(e, b, f, dis, "adult", "workers", k, int(game.day), rng, "cond:set by a developer tool")
		left -= k
	return n - left
