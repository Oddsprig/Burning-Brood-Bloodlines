extends RefCounted
## Native image fidelity/API checks plus cheap synthetic cache-policy fixtures.
## Synthetic capacity fixtures are not renderer FPS or allocated-memory evidence.
var checks: int = 0
var fails: int = 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL Paperdoll cache: ", why)

static func spec(race: String, seed_value: int) -> Dictionary:
	return FigurePainter.spec_generic(race, Color("#3467a7"), Color("#c5a65f"), seed_value)

static func count(key: String) -> int:
	return int(Paperdoll.cache_stats()[key])

func settle_background(tree: SceneTree) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		Paperdoll.pump_background()
		var stats: Dictionary = Paperdoll.background_stats()
		if int(stats["pending"]) == 0 and int(stats["inflight"]) == 0: return true
		await tree.process_frame
	return false

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var native_before: PackedByteArray = var_to_bytes(Game._serialize({"world": Game.world, "company": Game.company, "gold": Game.gold, "day": Game.day}))
	var rng_before: int = Game.rng.state
	var unit_before: int = Unit._next_uid
	var item_before: int = Item._next_uid
	var definitions_before: PackedByteArray = var_to_bytes({"races": DB.races, "materials": DB.materials, "armor": DB.armor})
	var orphan_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	Paperdoll.clear_cache()
	for race: String in FigurePainter.DETAILED_RACES:
		var doll := Paperdoll.new()
		doll.set_spec(spec(race, 23))
		var expected: Image = FigurePainter.render(doll.current_spec(), "idle", 0.0)
		check(doll._tex.get_image().get_data() == expected.get_data(), race + " cached idle RGBA equals unchanged native painter")
		check(doll._anchor == FigurePainter.dims(race)["anchor"], race + " original feet anchor retained")
		doll.free()
	var actor := Paperdoll.new(); actor.set_spec(spec("human", 101))
	actor.set_pose("walk", 0.01)
	var texture: Texture2D = actor._tex
	var uploads: int = count("uploads")
	var redraws: int = count("redraw_requests")
	actor.facing = 1; actor.set_pose("walk", 0.02)
	check(actor._tex == texture and count("uploads") == uploads and count("redraw_requests") == redraws, "unchanged facing and quantized frame cause no upload/redraw")
	actor.facing = -1
	check(count("redraw_requests") == redraws + 1 and count("uploads") == uploads, "facing change redraws existing frame without painting")
	actor.set_pose("hit", 0.49)
	redraws = count("redraw_requests"); uploads = count("uploads")
	actor.set_pose("hit", 0.51)
	check(count("redraw_requests") == redraws + 1 and count("uploads") == uploads, "same hit frame still redraws when red flash threshold changes")
	var duplicate := Paperdoll.new(); duplicate.set_spec(spec("human", 101))
	duplicate.set_pose("walk", 0.01)
	check(duplicate._tex == texture and count("hits") > 0, "identical specs/frames reuse exact shared texture")
	duplicate.free()
	var spec_builds: int = count("spec_builds")
	var raster_builds: int = count("raster_builds")
	uploads = count("uploads"); redraws = count("redraw_requests")
	actor.invalidate(); actor.invalidate()
	actor.set_pose("strike", 0.83, false)
	actor._draw() # A queued facing redraw must respect the offscreen raster guard.
	check(actor.pose == "strike" and is_equal_approx(actor.progress, 0.83) and actor._dirty, "offscreen state advances while dirty spec stays deferred")
	check(count("spec_builds") == spec_builds and count("raster_builds") == raster_builds and count("uploads") == uploads and count("redraw_requests") == redraws, "invalidate/offscreen draw do no eager painting or redraw")
	actor.set_pose("strike", 0.83, true)
	check(not actor._dirty and count("spec_builds") == spec_builds + 1 and count("uploads") == uploads + 1, "reentry resolves latest invalidation even at identical pose/progress")
	var expected_strike: Image = FigurePainter.render(actor.current_spec(), "strike", FigurePainter.frame_t("strike", FigurePainter.frame_index("strike", 0.83)))
	check(actor._tex.get_image().get_data() == expected_strike.get_data(), "deferred strike resolves exact native quantized frame")
	actor.set_pose("unknown pose", 0.0)
	check(actor.pose == "idle", "legacy invalid-pose fallback remains idle")
	actor.refresh()
	check(not actor._dirty and actor._tex != null, "legacy refresh remains eager")
	var retained: Texture2D = actor._tex
	Paperdoll._remove_cached(actor._frame_key, true)
	uploads = count("uploads")
	actor.set_pose("idle", 0.0)
	check(actor._tex == retained and count("uploads") == uploads, "an active doll retains an evicted current frame without unnecessary reupload")
	check(retained.get_image().get_data() == actor.build_image().get_data(), "eviction preserves the active native frame pixels")
	var signature_hits: int = count("signature_hits")
	var signature_misses: int = count("signature_misses")
	actor.set_pose("walk", 0.31); actor.set_pose("walk", 0.45)
	check(count("signature_hits") == signature_hits and count("signature_misses") == signature_misses, "pose frame changes never serialize or compare spec identities")
	actor.free(); texture = null

	# Force a hash collision without altering artwork or using a probabilistic seed hunt.
	var first := Paperdoll.new(); first.set_spec(spec("human", 401))
	first._sig = 444; first._signature_id = Paperdoll._signature_for(444, first._spec_bytes)
	first._frame_pending = true; first._update_tex()
	var second := Paperdoll.new(); second.set_spec(spec("human", 402))
	second._sig = 444; second._signature_id = Paperdoll._signature_for(444, second._spec_bytes)
	second._frame_pending = true; second._update_tex()
	check(first._frame_key != second._frame_key and first._tex != second._tex, "different exact spec bytes never share a colliding hash texture")
	check(count("collision_checks") > 0 and Paperdoll._signature_for(444, first._spec_bytes) == first._signature_id, "exact collision verification runs at spec resolution and reuses the matching identity")
	var second_expected: Image = FigurePainter.render(second.current_spec(), "idle", 0.0)
	check(second._tex.get_image().get_data() == second_expected.get_data(), "collision-disambiguated texture retains native identity")
	first.free(); second.free()
	Paperdoll.clear_cache()
	var tiny: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	tiny.fill(Color.WHITE)
	var tiny_texture: Texture2D = ImageTexture.create_from_image(tiny)
	var signature: int = Paperdoll._signature_for(1, PackedByteArray([1, 2, 3]))
	# One shared tiny texture keeps policy verification cheap. Payload costs below
	# deliberately simulate native frames; they are not actual texture allocations.
	var human_size: Vector2i = FigurePainter.dims("human")["size"]
	var human_cost: int = human_size.x * human_size.y * 4
	for i in 400:
		for frame in 9: Paperdoll._store_cached("working-%d-%d" % [i, frame], tiny_texture, signature, human_cost)
	check(count("entries") == 3600 and count("evictions") == 0, "budget admits 400 native-human eight-walk/one-idle payload estimates")
	check(count("payload_bytes") == 3600 * human_cost and count("payload_bytes") <= Paperdoll.CACHE_BYTE_LIMIT, "working-set accounting uses unchanged native dimensions")
	var isolated: Dictionary = Paperdoll.cache_stats(); isolated["hits"] = -999
	check(count("hits") == 0 and not String(isolated["payload_scope"]).is_empty(), "stats are copied and disclose retained-doll/overhead limits")
	Paperdoll.clear_cache()
	for i in Paperdoll.CACHE_LIMIT: Paperdoll._store_cached("entry-%d" % i, tiny_texture, signature, 4)
	Paperdoll._touch("entry-0")
	Paperdoll._store_cached("new-entry", tiny_texture, signature, 4)
	check(count("entries") == Paperdoll.CACHE_LIMIT and count("evictions") == 1, "entry ceiling evicts one frame rather than clearing peers")
	check(Paperdoll._cache.has("entry-0") and not Paperdoll._cache.has("entry-1") and Paperdoll._cache.has("entry-2"), "recently touched frame survives oldest-entry eviction")
	Paperdoll.clear_cache()
	var half: int = Paperdoll.CACHE_BYTE_LIMIT >> 1
	Paperdoll._store_cached("older", tiny_texture, signature, half)
	Paperdoll._store_cached("newer", tiny_texture, signature, half)
	Paperdoll._touch("older")
	Paperdoll._store_cached("third", tiny_texture, signature, 4)
	check(Paperdoll._cache.has("older") and Paperdoll._cache.has("third") and not Paperdoll._cache.has("newer"), "byte ceiling individually evicts least-recent frame")
	check(count("payload_bytes") == half + 4 and count("evictions") == 1, "byte counter and eviction statistics remain exact")
	Paperdoll._store_cached("too-large", tiny_texture, signature, Paperdoll.CACHE_BYTE_LIMIT + 1)
	check(count("entries") == 2 and count("oversize_frames") == 1 and not Paperdoll._cache.has("too-large"), "one oversized frame is uncached without purging useful frames")
	check(tiny_texture.get_image().get_data() == tiny.get_data(), "eviction never invalidates a borrowed/current texture reference")
	# Exercise the bounded exact-identity index without rasterizing any images.
	Paperdoll.clear_cache()
	var initial_token: int = Paperdoll._signature_for(10, PackedByteArray([10]))
	for i in Paperdoll.SIGNATURE_LIMIT: Paperdoll._signature_for(20 + i, PackedByteArray([20, i % 256]))
	check(count("signature_entries") == Paperdoll.SIGNATURE_LIMIT and count("signature_evictions") == 1, "exact signature index has a fixed ceiling, independent of frame accesses")
	check(Paperdoll._signature_for(10, PackedByteArray([10])) != initial_token, "retired signature tokens are never reused for potentially retained actor frames")
	Paperdoll._store_cached("legacy-restore", tiny_texture, signature, 4)
	Paperdoll._cache = {} # Match the inherited art regression's direct restore path.
	Paperdoll._reconcile_external_cache()
	check(count("entries") == 0 and count("payload_bytes") == 0 and Paperdoll._cache_meta.is_empty(), "external diagnostic cache restore leaves no ghost links or payload")
	Paperdoll.clear_cache(); tiny_texture = null; tiny = null
	check(count("entries") == 0 and count("payload_bytes") == 0 and Paperdoll._cache_meta.is_empty(), "explicit legacy cache clear releases links/payload and resets stats")
	# Background battle rendering is optional; default/eager assertions above stay.
	var async_a := Paperdoll.new(); async_a.set_spec(spec("human", 7101))
	var async_b := Paperdoll.new(); async_b.set_spec(spec("human", 7101))
	Paperdoll.begin_background()
	async_a.set_background_rendering(true); async_b.set_background_rendering(true)
	var old_texture: Texture2D = async_a._tex
	uploads = count("uploads"); raster_builds = count("raster_builds")
	async_a.set_pose("walk", 0.31); async_b.set_pose("walk", 0.31)
	check(async_a._tex == old_texture and count("uploads") == uploads and count("raster_builds") == raster_builds, "opt-in miss retains completed art without synchronous painting/upload")
	Paperdoll.pump_background()
	check(int(Paperdoll.background_stats()["inflight"]) == 1 and int(Paperdoll.background_stats()["pending"]) == 2, "identical requested keys share one detached worker snapshot")
	check(await settle_background(tree), "bounded worker request completes before test deadline")
	var async_expected: Image = FigurePainter.render(async_a.current_spec(), "walk", FigurePainter.frame_t("walk", FigurePainter.frame_index("walk", 0.31)))
	check(async_a._tex == async_b._tex and async_a._tex.get_image().get_data() == async_expected.get_data(), "worker output/upload equals exact native RGBA and is shared by both actors")
	check(count("uploads") == uploads + 1 and int(Paperdoll.background_stats()["dispatched"]) == 1, "coalesced requests upload only one texture on pump")
	# Dispatch a healthy pose, then sever the head in the actual copied spec before
	# its result can be consumed. The old signature must never overwrite new art.
	async_a.set_pose("strike", 0.5); Paperdoll.pump_background()
	var copied_spec: Dictionary = async_a.current_spec().duplicate(true)
	copied_spec["lost"] = ["head"]
	async_a._spec = copied_spec; async_a.invalidate(); async_a.set_pose("hit", 0.55)
	check(bool(Paperdoll._background_requests[async_a.get_instance_id()]["urgent"]), "head loss/gear invalidation receives urgent scheduling")
	check(await settle_background(tree), "changed native wound signature completes through prioritized latest request")
	var wounded_expected: Image = FigurePainter.render(async_a.current_spec(), "hit", FigurePainter.frame_t("hit", FigurePainter.frame_index("hit", 0.55)))
	check(async_a._tex.get_image().get_data() == wounded_expected.get_data() and int(Paperdoll.background_stats()["retired"]) >= 1, "stale healthy job retires and head-loss pixels remain exact")
	# An in-flight task has its own immutable spec, not the caller's later mutation.
	async_a.set_pose("recover", 0.5); Paperdoll.pump_background()
	async_a._spec["lost"] = []; async_a.invalidate(); async_a.set_pose("recover", 0.75)
	for i in 20: async_a.set_pose("recover", float(i) / 20.0)
	check(int(Paperdoll.background_stats()["pending"]) == 1, "rapid pose/identity updates retain only the latest per-doll slot")
	check(await settle_background(tree), "latest coalesced frame completes without queued snapshot chains")
	var latest_expected: Image = async_a.build_image()
	check(async_a._tex.get_image().get_data() == latest_expected.get_data(), "latest pose and actual current spec win over older detached work")
	var parallel: Array[Paperdoll] = []
	for i in FigurePainter.DETAILED_RACES.size():
		var doll := Paperdoll.new(); doll.set_spec(spec(String(FigurePainter.DETAILED_RACES[i]), 7200 + i))
		doll.set_background_rendering(true); doll.set_pose("walk", 0.62)
		parallel.append(doll)
	Paperdoll.pump_background()
	check(int(Paperdoll.background_stats()["inflight"]) == Paperdoll.BACKGROUND_JOB_LIMIT and int(Paperdoll.background_stats()["pending"]) == 8, "dispatch never exceeds four jobs while eight lightweight native-race slots wait")
	parallel[0].set_pose("walk", 0.7, false)
	check(not Paperdoll._background_requests.has(parallel[0].get_instance_id()), "offscreen culling cancels queued demand without touching immutable in-flight work")
	parallel[0].set_pose("walk", 0.62, true)
	check(await settle_background(tree), "all eight native-race worker paths complete")
	for doll: Paperdoll in parallel:
		check(doll._tex.get_image().get_data() == doll.build_image().get_data(), "worker/native image fidelity for " + String(doll.current_spec()["race"]))
		# Fresh uncached requests give scene exit actual work to drain.
		doll.set_pose("strike", 0.75)
	Paperdoll.pump_background()
	Paperdoll.end_background()
	check(not bool(Paperdoll.background_stats()["active"]) and int(Paperdoll.background_stats()["pending"]) == 0 and int(Paperdoll.background_stats()["inflight"]) == 0, "scene end drains detached tasks and clears all demand/results")
	check(int(Paperdoll.background_stats()["inflight_peak"]) <= 4 and int(Paperdoll.background_stats()["worker_elapsed_us"]) > 0, "bounded worker CPU evidence stays separate from main-thread upload timings")
	for doll: Paperdoll in parallel: doll.free()
	async_a.free(); async_b.free(); old_texture = null
	Paperdoll.clear_cache()
	# Deterministic queue fairness, not a rendered FPS claim. Only the just-served
	# participants move back; priority and changed identities remain untouched.
	Paperdoll._background_requests = {
		11: {"key": "newer-frame", "signature": 77, "queued_us": 10, "urgent": false, "revision": 5},
		22: {"key": "waiting-other", "signature": 88, "queued_us": 20, "urgent": false, "revision": 2},
		33: {"key": "new-wound", "signature": 99, "queued_us": 8, "urgent": true, "revision": 7},
		44: {"key": "urgent-newer-frame", "signature": 77, "queued_us": 5, "urgent": true, "revision": 9},
		55: {"key": "completed-frame", "signature": 77, "queued_us": 7, "urgent": false, "revision": 1}}
	Paperdoll._rotate_completed_requests({"signature": 77, "participants": {11: null, 33: null, 44: null, 55: null}}, "completed-frame", 100)
	check(int(Paperdoll._background_requests[11]["queued_us"]) > int(Paperdoll._background_requests[22]["queued_us"]), "completed actor's newer normal frame yields to another waiting actor")
	check(int(Paperdoll._background_requests[44]["queued_us"]) == 100 and bool(Paperdoll._background_requests[44]["urgent"]) and int(Paperdoll._background_requests[44]["revision"]) == 9, "queue rotation preserves urgent status and actual identity/revision")
	check(int(Paperdoll._background_requests[33]["queued_us"]) == 8 and int(Paperdoll._background_requests[33]["signature"]) == 99, "an older completed identity cannot delay a new wound request")
	check(int(Paperdoll._background_requests[55]["queued_us"]) == 7 and int(Paperdoll._background_requests[22]["queued_us"]) == 20, "exact completed key and nonparticipating actor timestamps stay untouched")
	Paperdoll._background_requests.clear()
	for _i in 5: await tree.process_frame
	check(var_to_bytes(Game._serialize({"world": Game.world, "company": Game.company, "gold": Game.gold, "day": Game.day})) == native_before and Game.rng.state == rng_before, "render/cache checks preserve campaign and RNG")
	check(Unit._next_uid == unit_before and Item._next_uid == item_before, "cache tests create no native people or items")
	check(definitions_before == var_to_bytes({"races": DB.races, "materials": DB.materials, "armor": DB.armor}), "workers only read immutable native drawing definitions")
	if OS.is_debug_build(): check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_before, "standalone dolls/cache fixtures leave no orphan nodes")
	print("Paperdoll cache/API: ", checks, " assertions; failures=", fails, "; capacity fixtures are synthetic, not FPS/memory measurements")
	return fails
