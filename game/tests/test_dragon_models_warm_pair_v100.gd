extends "res://tests/test_dragon_models.gd"
## Adjacent warm-cache supplement to r6; the six cold rows remain mandatory.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.
const PAIR_BUDGET_MSEC: int = 160000
var pair_checks: int = 0

func run(_tree: SceneTree) -> int:
	var started: int = Time.get_ticks_msec()
	var before: String = _snapshot()
	var catalogs: Dictionary = Dragons.catalogs()
	var selected: Array = _selected_forms(catalogs["morphs"])
	if not _pair_check(selected.size() == 2, "select exactly two --forms=A,B"): return maxi(1, fails)
	var first_step: int = MORPH_PARTS.find(String(selected[0]["id"]))
	if not _pair_check(first_step >= 0 and first_step < MORPH_PARTS.size() - 1 and String(selected[1]["id"]) == MORPH_PARTS[first_step + 1], "only an original adjacent ordered pair is allowed"): return maxi(1, fails)
	var chain: String = _chain_argument()
	if fails > 0: return fails
	var receipt_path: String = _pair_receipt_path(chain, first_step)
	if not _part_check(_write_json(receipt_path, {"complete": false, "passed": false, "run": chain, "pair": first_step}), "initialize incomplete pair receipt"): return maxi(1, fails)
	var errors: Object = _tree.current_scene.get("script_errors") as Object
	if not _part_check(errors != null and errors.has_method("total"), "use the native runner with its script-error counter"): return maxi(1, fails)
	var errors_before: int = int(errors.call("total"))
	var identity: String = _source_identity()
	if not _part_check(not identity.is_empty(), "source, art, imports, engine and profile identity captured"): return maxi(1, fails)
	# Read observations only; all six cold rows must precede every pair.
	var prefix: Dictionary = _predecessors(chain, MORPH_PARTS.size(), identity)
	if prefix.is_empty(): return maxi(1, fails)
	if not _pair_check(_art_is_cold(), "pair starts with empty native in-memory art caches"): return maxi(1, fails)
	var warm_started: int = Time.get_ticks_msec()
	var warm: Dictionary = _warm_first(selected[0])
	if warm.is_empty() or fails > 0: return maxi(1, fails)
	var warm_ms: int = Time.get_ticks_msec() - warm_started
	var sources: Dictionary = {warm["source_rgba_sha256"]: true}
	var observed: Dictionary = {String(selected[0]["id"]): warm["source_rgba_sha256"]}
	var full_started: int = Time.get_ticks_msec()
	# B executes the complete original per-form assertion block, unchanged.
	var form_ids: Array[String] = []
	for form: Dictionary in selected: form_ids.append(String(form["id"]))
	print("Dragon source model forms: " + ",".join(form_ids))
	for form: Dictionary in selected.slice(1):
		var code_row: Dictionary = {"stage": "adult", "alive": true, "gem_id": "sapphire", "morph_id": form["id"], "size_class": "medium", "appearance_seed": 27}
		var code_img: Image = DragonArt.source_image(code_row)
		var code_rebuilt: Image = DragonArt.reconstruct_source(code_row)
		_assert(code_img != null and code_img.get_size() == Vector2i(128, 96) and code_img.get_data() == code_rebuilt.get_data(), "default v0.064 code-drawn source reconstructs cleanly: " + String(form["id"]))
		var row: Dictionary = {"stage": "adult", "alive": true, "gem_id": "sapphire", "morph_id": form["id"], "size_class": "medium", "appearance_seed": 27, "sprite_id": "classic"}
		var copied: Dictionary = row.duplicate(true)
		var original: Image = DragonArt.source_image(row)
		var reconstructed: Image = DragonArt.reconstruct_source(row)
		_assert(original != null and reconstructed != null, "observed coherent source loads: " + String(form["id"]))
		if original == null or reconstructed == null: continue
		_assert(original.get_size() == Vector2i(1536, 1024) and original.get_size() == reconstructed.get_size(), "rest proof retains original pixel dimensions")
		_assert(original.get_data() == reconstructed.get_data(), "all original RGBA bytes reconstruct exactly, including alpha-zero RGB")
		var entry: Dictionary = DragonSpriteCatalog.entry(String(form["id"]))
		_materials(row, original, entry)
		var path: String = String(entry["source_path"])
		if FileAccess.file_exists(path):
			var raw: Image = Image.new()
			var decoded: Error = raw.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
			if decoded != OK:
				_assert(false, "raw source PNG must decode: " + path)
				continue
			raw.convert(Image.FORMAT_RGBA8)
			_assert(raw.get_data() == reconstructed.get_data(), "imported source preserves untouched PNG RGBA, without border-RGB or compression changes")
		sources[original.get_data().hex_encode().sha256_text()] = true
		observed[String(form["id"])] = original.get_data().hex_encode().sha256_text()
		_source_layers(row, original)
		var source: Dictionary = DragonRigArt._source(row)
		var gem: Dictionary = DragonArt._entry("gems", "sapphire")
		var job: Dictionary = DragonArt._tint_job(source, row, Color(String(gem["base"])), Color(String(gem["accent"])))
		if not _pair_check(not DragonArt._load_tint(String(job["key"]), (job["original"] as PackedByteArray).size()).is_empty(), "B requires a native-loadable persistent tint produced by the cold chain"): return maxi(1, fails)
		var rest: Dictionary = DragonArt.model(row, "rest", 0.77)
		_assert(bool(rest.get("valid", false)), "rest model is valid")
		if not bool(rest.get("valid", false)): continue
		_assert(rest["parts"].size() == 3 and rest["all_parts"].size() == 3 and rest["regions"].size() == 15, "three drawable source cuts and fifteen damage masks")
		_assert(rest["hind_legs"] == 2 and rest["wing_forelimbs"] == 2 and rest["front_legs"] == 0, "source preserves wyvern anatomy")
		_assert(rest["seat"].is_equal_approx(Vector2.ZERO) and rest["rider_height"] == 24 and rest["rider_scale"] == 1, "observed seat origin and fixed native rider size")
		var idle: Dictionary = DragonArt.model(row, "idle", 0)
		for index: int in rest["all_parts"].size():
			_assert((rest["all_parts"][index]["xf"] as Transform2D).is_equal_approx(idle["all_parts"][index]["xf"]), "idle zero agrees with identity rest")
		var part_image: Image = rest["parts"][0]["image"]
		_assert(DragonRigArt._texture_for(part_image) == DragonRigArt._texture_for(part_image), "live CanvasItem reuses source-part texture")
		var frame: Dictionary = DragonArt.framing(row, "rest")
		var cv: PixelCanvas = PixelCanvas.new(720, 420)
		var prior_xf: Transform2D = cv.xf
		var prior_scale: float = cv.k
		var painted: Dictionary = DragonArt.draw(cv, row, "rest", frame["origin"], frame["pixels_per_unit"])
		_assert(cv.xf == prior_xf and cv.k == prior_scale, "software rendering preserves caller frame")
		_assert(Rect2(0, 0, 720, 420).encloses(painted["bounds"]), "whole coherent model fits declared frame")
		_assert(painted["rider_height"] == 24 * float(frame["pixels_per_unit"]) and painted["rider_scale"] == frame["pixels_per_unit"], "drawn rider scale excludes host size multiplier")
		_assert(cv.to_image().get_size() == Vector2i(720, 420) and cv.opaque_count() > 5000, "coherent source renders substantial native model")
		_assert(DragonArt.portrait_for(row, "rest").get_size() == Vector2i(384, 384), "head portrait uses source crop")
		_motion(row)
		_damage(row)
		_sizes(row, catalogs["sizes"])
		_assert(row == copied and original.get_data() == reconstructed.get_data(), "palette/motion/damage reads preserve source identity")
	_check_pair_history(warm)
	_assert(sources.size() == selected.size(), "every selected body form has a distinct coherent source")
	_assert(_snapshot() == before, "art reads preserve world, catalogs, native identity counters and RNG")
	_assert(DragonRigArt._textures.size() <= DragonRigArt.TEXTURE_CACHE_LIMIT and DragonRigArt._images.size() <= DragonRigArt.IMAGE_CACHE_LIMIT, "native texture/image caches remain bounded")
	DragonRigArt.clear_texture_cache()
	_assert(DragonRigArt._textures.is_empty() and DragonRigArt._texture_order.is_empty(), "explicit GPU cleanup releases texture references")
	if not _part_check(checks == _expected_checks(String(selected[1]["id"])), "all of B's original normal-path assertions and four terminal assertions ran"): return maxi(1, fails)
	if not _part_check(pair_checks == 30, "all additional warmup and cache-history checks ran"): return maxi(1, fails)
	for i: int in range(2):
		var prior: Dictionary = _read_json(_receipt_path(chain, first_step + i))
		if not _part_check(prior.get("source_rgba_sha256") == observed.get(String(selected[i]["id"])), "native pair source matches its fully checked cold observation"): return maxi(1, fails)
	if fails > 0: return fails
	var candidate: Dictionary = {
		"format": "dragon-models-r8-pair", "complete": true, "passed": true, "fails": 0,
		"run": chain, "nonce": prefix["nonce"], "pair": first_step,
		"forms": [String(selected[0]["id"]), String(selected[1]["id"])],
		"source": identity, "source_rgba_sha256": observed, "checks": checks, "pair_checks": pair_checks,
		"warmup_ms": warm_ms, "full_checks_ms": Time.get_ticks_msec() - full_started,
		"checks_ms": Time.get_ticks_msec() - started, "budget_ms": PAIR_BUDGET_MSEC,
	}
	var pending: String = receipt_path + ".pending"
	if not _part_check(_write_json(pending, candidate) and FileAccess.get_file_as_string(pending) == JSON.stringify(candidate), "candidate pair receipt roundtrips exactly"): return maxi(1, fails)
	if not _part_check(_source_identity() == identity, "source and native inputs stayed fixed"): return maxi(1, fails)
	if not _part_check(int(errors.call("total")) == errors_before, "no runtime script error skipped a pair check"): return maxi(1, fails)
	if not _part_check(Time.get_ticks_msec() - started < PAIR_BUDGET_MSEC, "pair checks and receipt verification finish below 160 s"): return maxi(1, fails)
	var published: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(pending), ProjectSettings.globalize_path(receipt_path))
	if not _part_check(published == OK, "publish the verified pair receipt"): return maxi(1, fails)
	print("Dragon warm pair %s -> %s: %d original assertions, %d pair checks, 0 failures; all eleven rows required." % [selected[0]["id"], selected[1]["id"], checks, pair_checks])
	return 0

func _warm_first(form: Dictionary) -> Dictionary:
	# Only native cache-producing operations from A's original body.
	# Reconstruction proofs and software captures produce no additional shared cache.
	var code_row: Dictionary = {"stage": "adult", "alive": true, "gem_id": "sapphire", "morph_id": form["id"], "size_class": "medium", "appearance_seed": 27}
	var code_image: Image = DragonArt.source_image(code_row)
	if not _pair_check(code_image != null and code_image.get_size() == Vector2i(128, 96), "A builds its native generated-source cache"): return {}
	var row: Dictionary = code_row.duplicate(true)
	row["sprite_id"] = "classic"
	var source: Dictionary = DragonRigArt._source(row)
	if not _pair_check(not source.is_empty() and (source["image"] as Image).get_size() == Vector2i(1536, 1024), "A builds its native classic source, ownership and source cuts"): return {}
	var material_mask: PackedByteArray = DragonSpriteCatalog.material_mask(String(row["morph_id"]), Vector2i(source["size"]))
	if not _pair_check(material_mask.size() == 1536 * 1024, "A builds its source-shaped material mask"): return {}
	var gem: Dictionary = DragonArt._entry("gems", "sapphire")
	var job: Dictionary = DragonArt._tint_job(source, row, Color(String(gem["base"])), Color(String(gem["accent"])))
	if not _pair_check(not DragonArt._load_tint(String(job["key"]), (job["original"] as PackedByteArray).size()).is_empty(), "A requires a native-loadable persistent tint produced by the cold chain"): return {}
	var rest: Dictionary = DragonArt.model(row, "rest", 0.77)
	if not _pair_check(bool(rest.get("valid", false)), "A builds native tinted part/region images and full-size source masks"): return {}
	var part_image: Image = rest["parts"][0]["image"]
	if not _pair_check(DragonRigArt._texture_for(part_image) == DragonRigArt._texture_for(part_image), "A builds and reuses the original body texture"): return {}
	var state: Dictionary = {"lost": ["wing_upper_r", "leg_upper_l", "torso", "jaw"], "dmg": {"wing_lower_r": 0.6}, "wk": {"wing_lower_r": "c"}, "bleed": {"wing_lower_r": true}, "blood": 0.8,
		"fragments": [{"region_id": "jaw", "kind": "tooth", "count": 3}]}
	var damaged: Dictionary = DragonArt.model(row, "hit", 0.4, state)
	if not _pair_check(bool(damaged.get("valid", false)), "A supplies the original damage model"): return {}
	var overlays: Array = DragonDamageArt.overlay_layers(damaged["all_parts"], damaged["state"], 27, damaged["regions"])
	if not _pair_check(not overlays.is_empty(), "A builds its original native damage decals"): return {}
	var warm: Dictionary = _cache_keys()
	var code_key: String = DragonSpriteCatalog.source_id(code_row) + "/frame%d" % SapphireSpirewingArt.frame_index("rest", 0.0)
	if not _pair_check(warm["sources"] == [code_key, String(form["id"])], "A leaves exactly its generated and classic source keys in insertion order"): return {}
	if not _pair_check(warm["images"].size() == 1 and warm["image_order"] == warm["images"] and warm["textures"] == [part_image.get_instance_id()] and warm["texture_order"] == warm["textures"], "A retains its native image/texture sharing and one-entry LRU orders"): return {}
	if not _pair_check(warm["materials"].size() == 1 and warm["tints"].size() == 1 and warm["tint_order"] == warm["tints"] and warm["decals"].size() == overlays.size() and warm["decal_order"] == warm["decals"], "A retains native material, tint and decal contents and order"): return {}
	if not _pair_check(warm["frames"].size() + warm["variants"].size() == 1 and warm["variant_order"] == warm["variants"] and DragonArt._assets.is_empty() and DragonArt._warm_tasks.is_empty(), "A created one generated frame and no unrelated cache or worker"): return {}
	# Keep only observations across the call, never extra Image/Texture owners.
	warm["source_rgba_sha256"] = (source["image"] as Image).get_data().hex_encode().sha256_text()
	return warm

func _cache_keys() -> Dictionary:
	return {
		"sources": DragonRigArt._sources.keys(), "materials": DragonSpriteCatalog._material_masks.keys(),
		"images": DragonRigArt._images.keys(), "image_order": DragonRigArt._image_order.duplicate(),
		"textures": DragonRigArt._textures.keys(), "texture_order": DragonRigArt._texture_order.duplicate(),
		"tints": DragonArt._tints.keys(), "tint_order": DragonArt._tint_order.duplicate(),
		"decals": DragonDamageArt._decals.keys(), "decal_order": DragonDamageArt._decal_order.duplicate(),
		"frames": SapphireSpirewingArt._frames.keys(), "variants": SapphireSpirewingArt._variant_frames.keys(),
		"variant_order": SapphireSpirewingArt._variant_order.duplicate(),
	}

func _check_pair_history(warm: Dictionary) -> void:
	var after: Dictionary = _cache_keys()
	for name: String in ["sources", "materials", "images", "image_order", "textures", "texture_order", "tints", "tint_order", "decals", "decal_order", "frames", "variants", "variant_order"]:
		var prior: Array = warm[name]
		var current: Array = after[name]
		_pair_check(current.size() >= prior.size() and current.slice(0, prior.size()) == prior, "A's native cache keys/order survive B's entire assertion block: " + name)
	_pair_check(after["sources"].size() == 4 and after["materials"].size() == 2 and after["images"].size() == 2 and after["textures"].size() == 2 and after["tints"].size() == 2 and after["frames"].size() + after["variants"].size() == 2, "only the two selected forms populated the native caches")

func _pair_check(ok: bool, label: String) -> bool:
	pair_checks += 1
	return _part_check(ok, label)

func _pair_receipt_path(chain: String, pair_index: int) -> String:
	return "user://dragon_models_r8_pair_%s_%s_%d.json" % [ProjectSettings.globalize_path("res://").sha256_text().substr(0, 12), chain, pair_index]
