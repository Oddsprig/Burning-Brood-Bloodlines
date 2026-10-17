extends RefCounted
## A fresh native Normal world with exactly one history day; actual existing
## dragon, local owner house and adult person. No combat or population fixture.
const PRIVATE_WORK := "C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"
var checks := 0
var fails := 0
var captures: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL fresh dragon bond: ", message)

func frames(tree: SceneTree, count: int = 3) -> void:
	for i in count:
		await tree.process_frame
		await RenderingServer.frame_post_draw

func snapshot() -> String:
	return JSON.stringify(Game._serialize({"world": Game.world, "company": Game.company, "gold": Game.gold,
		"stash": Game.stash, "day": Game.day, "rng": str(Game.rng.state), "next_unit": Unit._next_uid, "next_item": Item._next_uid}), "", true, true)

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var directory := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): directory = arg.trim_prefix("--report-dir=").replace("\\", "/").simplify_path()
	check(DisplayServer.get_name() != "headless", "actual rendered native engine")
	check(directory.to_lower().begins_with(PRIVATE_WORK.to_lower()) and not DirAccess.dir_exists_absolute(directory), "fresh private report path")
	if fails > 0: return fails
	DirAccess.make_dir_recursive_absolute(directory)
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000); tree.root.size = Vector2i(2560, 1440)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 60
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var start := Time.get_ticks_usec()
	var generation := Game.new_game_begin(777)
	while not Game.new_game_slice(generation, 4000):
		if Time.get_ticks_usec() - start > 90000000: check(false, "bounded generation"); return fails
		await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		if Time.get_ticks_usec() - start > 120000000: check(false, "bounded one-day history"); return fails
		CampaignWorld.presim_slice(Game, history, 4000); await tree.process_frame
	CampaignWorld.presim_finish(Game, 0); Dynasty.prepare_world(Game); Game.new_game_finalize()
	Game._save_pending = false; Game.wait_save(); Game.set_process(false)
	var world_ms := float(Time.get_ticks_usec() - start) / 1000.0
	check(Game.day == 1.0 and Game.world.get("work", []).is_empty(), "exactly one fresh settled history day")
	check(Game.company.is_empty() and Game.gold == 0, "no automatically raised army or army coin")
	var uid := ""
	var tid := ""
	for dragon: Dictionary in Dragons.records(Game):
		if dragon.get("stage", "") != "adult" or not dragon.get("alive", false): continue
		var owner := Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty(): continue
		var result := HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"]))
		if result.get("ok", false) and not DragonBond.candidates(Game, str(dragon["id"])).is_empty():
			uid = str(dragon["id"]); tid = str(owner["town_id"]); break
	check(uid != "", "actual generated adult dragon and its native owning house have real local candidates")
	if uid == "": return fails
	var native_owner: Dictionary = Dragons.get_record(Game, uid)
	var person: Dictionary = DragonBond.candidates(Game, uid)[0]
	var before := snapshot()
	var review := DragonBond.bind_preview(Game, uid, str(person["person_uid"]))
	check(review.get("ok", false) and snapshot() == before, "actual reviewed candidate reads are pure")
	var coins := Barge.holdings(Game)
	var rng := Game.rng.state
	var next_unit := Unit._next_uid
	var next_item := Item._next_uid
	check(DragonBond.bind(Game, uid, str(person["person_uid"]), review).get("ok", false), "review confirms one actual native person bond")
	var status := DragonBond.status(Game, uid)
	check(status.get("active", false) and status.get("rider_person_uid", "") == person["person_uid"], "registry exposes the exact active real rider")
	var after: Dictionary = Dragons.get_record(Game, uid)
	for field in ["owner_person_uid", "owner_house_uid", "owner_household_uid", "custodian_person_uid", "location_town_id", "estate_town_id"]:
		check(after[field] == native_owner[field], "binding preserves " + field)
	check(Game.company.is_empty() and Unit._next_uid == next_unit and Item._next_uid == next_item, "binding creates no people, units, gear or army")
	check(Game.rng.state == rng and absf(Barge.holdings(Game) - coins) < 0.001, "no RNG draw or account transfer")
	Game.screen_params = {"dragon_uid": uid, "back": "house"}
	var view: Control = (load("res://ui/dragons.tscn") as PackedScene).instantiate(); tree.root.add_child(view)
	await frames(tree, 5)
	var pure := snapshot()
	view.call("_refresh"); await frames(tree, 5)
	check(snapshot() == pure, "actual dragon detail refresh leaves native world untouched")
	var path := directory.path_join("bonded_actual_world.png")
	var image: Image = tree.root.get_texture().get_image()
	check(image.get_size() == Vector2i(2560, 1440) and image.save_png(path) == OK, "actual bonded rider detail capture")
	captures.append({"state": "bonded_actual_world", "path": path, "sha256": FileAccess.get_sha256(path), "width": 2560, "height": 1440})
	view.queue_free(); view = null; await frames(tree)
	Game.save_game(); Game.wait_save()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	check(saved.get("world", {}).get("dragons", {}).get("records", {}).get(uid, {}).get("rider_person_uid", "") == person["person_uid"], "current native disk save keeps exact dragon and rider IDs")
	check(Game.load_game(), "current private native save reload succeeds")
	check(DragonBond.status(Game, uid).get("active", false), "same actual living rider bond survives current load")
	var loaded := snapshot()
	Dragons.after_load(Game)
	check(snapshot() == loaded, "repeat current registry normalization is idempotent")
	var release := DragonBond.release_preview(Game, uid)
	check(release.get("ok", false) and snapshot() == loaded, "release review is read-only")
	check(DragonBond.release(Game, uid, release).get("ok", false), "explicit reviewed release succeeds")
	check(Dragons.get_record(Game, uid).get("last_rider_person_uid", "") == person["person_uid"], "release preserves actual prior rider identity")
	var released := snapshot()
	check(not DragonBond.release(Game, uid, release).get("ok", false) and snapshot() == released, "repeat release cannot mutate native state")
	var report := {"version": ProjectSettings.get_setting("application/config/version"), "world_size": "normal", "history_days": 1, "seed": 777, "town_id": tid,
		"dragon_uid": uid, "rider_person_uid": person["person_uid"], "world_ready_ms": world_ms, "captures": captures, "checks": checks, "failures": fails,
		"scope": "Actual generated dragon/local household/adult bond, pure rendered detail, native private disk save/reload and explicit release; no combat or performance benchmark."}
	var file := FileAccess.open(directory.path_join("fresh-dragon-bond-world.json"), FileAccess.WRITE)
	check(file != null, "private report opens"); report["checks"] = checks; report["failures"] = fails
	if file != null: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("Fresh dragon bond world v021: ", checks, " checks, ", fails, " failures")
	return fails
