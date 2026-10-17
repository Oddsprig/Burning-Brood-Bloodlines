extends RefCounted
## Exact source/purity checks cannot certify animation or artwork quality.
var checks: int = 0
var fails: int = 0

func run(_tree: SceneTree) -> int:
	var before: String = _snapshot()
	var catalogs: Dictionary = Dragons.catalogs()
	var selected: Array = _selected_forms(catalogs["morphs"])
	if selected.is_empty():
		print("Dragon source models: %d assertions, %d failures; invalid form selection." % [checks, fails])
		return fails
	var form_ids: Array[String] = []
	for form: Dictionary in selected: form_ids.append(String(form["id"]))
	print("Dragon source model forms: " + ",".join(form_ids))
	var sources: Dictionary = {}
	for form: Dictionary in selected:
		var row: Dictionary = {"stage": "adult", "alive": true, "gem_id": "sapphire", "morph_id": form["id"], "size_class": "medium", "appearance_seed": 27}
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
		_source_layers(row, original)
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
	_assert(sources.size() == selected.size(), "every selected body form has a distinct coherent source")
	_assert(_snapshot() == before, "art reads preserve world, catalogs, native identity counters and RNG")
	_assert(DragonRigArt._textures.size() <= DragonRigArt.TEXTURE_CACHE_LIMIT and DragonRigArt._images.size() <= DragonRigArt.IMAGE_CACHE_LIMIT, "native texture/image caches remain bounded")
	DragonRigArt.clear_texture_cache()
	_assert(DragonRigArt._textures.is_empty() and DragonRigArt._texture_order.is_empty(), "explicit GPU cleanup releases texture references")
	print("Dragon source models: %d assertions, %d failures; artwork requires fresh visual review." % [checks, fails])
	return fails

func _selected_forms(forms: Array) -> Array:
	var argument: String = ""
	var provided: bool = false
	for value: String in OS.get_cmdline_user_args():
		if not value.begins_with("--forms="): continue
		if provided:
			_assert(false, "supply --forms only once")
			return []
		provided = true
		argument = value.trim_prefix("--forms=")
	if not provided: return forms.duplicate(true)
	var known: Dictionary = {}
	for form: Dictionary in forms: known[String(form["id"])] = form
	var selected: Array = []
	var seen: Dictionary = {}
	for value: String in argument.split(",", true):
		var id: String = value.strip_edges()
		if id == "" or not known.has(id) or seen.has(id):
			_assert(false, "--forms requires nonempty, known, unique morph IDs: " + id)
			return []
		selected.append(known[id].duplicate(true))
		seen[id] = true
	if selected.is_empty(): _assert(false, "--forms must select at least one known morph")
	return selected

func _materials(row: Dictionary, original: Image, entry: Dictionary) -> void:
	var mask: PackedByteArray = DragonSpriteCatalog.material_mask(String(row["morph_id"]), original.get_size())
	_assert(mask.size() == original.get_width() * original.get_height() and entry.get("preserve_regions", []).is_empty(), "material preservation uses source-shaped masks without rectangular fallback")
	var asset: Dictionary = {"size": Vector2(original.get_size()), "material_mask": mask, "gems": []}
	var gem: Dictionary = DragonArt._entry("gems", "sapphire")
	var probes: Dictionary = entry["material_probes_px"]
	for kind: String in ["horn", "eye", "skin"]:
		var point: Array = probes[kind]
		var at: Vector2i = Vector2i(int(point[0]), int(point[1]))
		var source: Color = original.get_pixelv(at)
		var material: int = mask[at.y * original.get_width() + at.x]
		var pigmented: Color = DragonArt._tint(source, Vector2(at) + Vector2(0.5, 0.5), asset, Color(String(gem["base"])), Color(String(gem["accent"])), "sapphire")
		_assert(source.a > 0.1 and material == (DragonSpriteCatalog.HORN_MASK if kind == "horn" else DragonSpriteCatalog.EYE_MASK if kind == "eye" else 0), "observed " + kind + " pixel has correct material ownership")
		_assert((pigmented == source) if kind == "eye" else (pigmented != source), "only eyeballs preserve original colour; horns and scales receive gem pigment")
		if kind == "horn": _assert(pigmented.b > pigmented.r and pigmented.b > pigmented.g, "Sapphire horn is blue gem material")
	for point: Array in entry["horn_edge_probes_px"]:
		var at: Vector2i = Vector2i(int(point[0]), int(point[1]))
		var source: Color = original.get_pixelv(at)
		var pigmented: Color = DragonArt._tint(source, Vector2(at) + Vector2(0.5, 0.5), asset, Color(String(gem["base"])), Color(String(gem["accent"])), "sapphire")
		_assert(source.a > 0.1 and (mask[at.y * original.get_width() + at.x] & DragonSpriteCatalog.HORN_MASK) != 0 and pigmented.b > pigmented.r and pigmented.b > pigmented.g, "complete observed horn edge receives blue gem pigment, without natural bands")
	var horn_at: Array = probes["horn"]
	var horn_source: Color = original.get_pixel(int(horn_at[0]), int(horn_at[1]))
	var eye_at: Array = probes["eye"]
	var eye_source: Color = original.get_pixel(int(eye_at[0]), int(eye_at[1]))
	var horn_colours: Dictionary = {}
	for type: Dictionary in Dragons.catalogs()["gems"]:
		var horn: Color = DragonArt._tint(horn_source, Vector2(horn_at[0] + 0.5, horn_at[1] + 0.5), asset, Color(String(type["base"])), Color(String(type["accent"])), String(type["id"]))
		var eye: Color = DragonArt._tint(eye_source, Vector2(eye_at[0] + 0.5, eye_at[1] + 0.5), asset, Color(String(type["base"])), Color(String(type["accent"])), String(type["id"]))
		_assert(horn != horn_source and horn.a == horn_source.a and eye == eye_source, "every gem type colours actual horns while retaining alpha and original eyeballs")
		horn_colours[str(horn)] = true
	_assert(horn_colours.size() >= 12, "gem horn colours vary with type across the actual catalog")
	_assert(DragonSpriteCatalog._material_masks.size() <= 6, "source material-mask cache remains bounded")

func _source_layers(row: Dictionary, original: Image) -> void:
	var layers: Array = DragonArt.labelled_source_layers(row)
	_assert(layers.size() == 3, "labelled source capture returns exactly body/head/jaw")
	var ownership: PackedByteArray = PackedByteArray()
	ownership.resize(original.get_width() * original.get_height())
	var overlaps: int = 0
	for layer: Dictionary in layers:
		var image: Image = layer["image"]
		var rect: Rect2i = layer["source_rect"]
		var mask: PackedByteArray = layer["mask"]
		var xf: Transform2D = layer["xf"]
		_assert(image.get_size() == rect.size and xf.x == Vector2.RIGHT and xf.y == Vector2.DOWN and xf.origin == Vector2(rect.position), "source cuts keep pixel sizing and exact global offsets")
		_assert(image.get_used_rect().size.length() > 0 and String(layer["label"]) != "", "labelled source piece contains actual original alpha")
		for y: int in rect.size.y:
			for x: int in rect.size.x:
				if mask[y * rect.size.x + x] == 0: continue
				var index: int = (y + rect.position.y) * original.get_width() + x + rect.position.x
				if ownership[index] != 0: overlaps += 1
				ownership[index] += 1
	_assert(overlaps == 0 and not ownership.has(0), "every source pixel has exactly one owner, with no omissions or overlapping discoloration")

func _motion(row: Dictionary) -> void:
	for joined_pose: String in ["hit", "strike"]:
		var joined: Dictionary = DragonArt.model(row, joined_pose, 0.55)
		var contact: Dictionary = joined["neck_join"]
		_assert(int(contact["contact_count"]) > 2 and float(contact["minimum_overlap_px"]) >= 0.5, "recoil/bite retains overlap at every original alpha-visible neck cut contact")
	var identity: Dictionary = DragonArt.model(row, "rest", 0.55)
	_assert((identity["neck_join"]["translation_px"] as Vector2).is_equal_approx(Vector2.ZERO), "neck seating leaves original rest positions exactly unchanged")
	for pose: String in FigurePainter.POSES:
		var first: Dictionary = DragonArt.model(row, pose, 0.12)
		var next: Dictionary = DragonArt.model(row, pose, 0.58)
		_assert(bool(first.get("valid", false)) and first["frames"] == FigurePainter.FRAMES[pose], "native pose/frame metadata: " + pose)
		var changed: bool = false
		for index: int in first["all_parts"].size():
			if first["all_parts"][index]["xf"] != next["all_parts"][index]["xf"]: changed = true
		_assert(changed if int(FigurePainter.FRAMES[pose]) > 1 else not changed, "progress poses head/jaw and gently moves intact body; corpse freezes: " + pose)
	var strike: Dictionary = DragonArt.model(row, "strike", 0.5)
	var rest: Dictionary = DragonArt.model(row, "rest")
	_assert(not (strike["all_parts"][2]["xf"] as Transform2D).is_equal_approx(rest["all_parts"][2]["xf"]), "bite animates the original lower jaw")
	for part: Dictionary in strike["all_parts"]:
		var xf: Transform2D = part["xf"]
		_assert(is_equal_approx(xf.x.length(), float(strike["source_scale"])) and is_equal_approx(xf.y.length(), float(strike["source_scale"])) and absf(xf.x.dot(xf.y)) < 0.0001, "animation applies rigid deltas with a single shared scale")

func _damage(row: Dictionary) -> void:
	var state: Dictionary = {"lost": ["wing_upper_r", "leg_upper_l", "torso", "jaw"], "dmg": {"wing_lower_r": 0.6}, "wk": {"wing_lower_r": "c"}, "bleed": {"wing_lower_r": true}, "blood": 0.8,
		"fragments": [{"region_id": "jaw", "kind": "tooth", "count": 3}]}
	var copied: Dictionary = state.duplicate(true)
	var damaged: Dictionary = DragonArt.model(row, "hit", 0.4, state)
	_assert(damaged["parts"].size() == 3 and bool(damaged["mountable"]), "mangled wings/legs/body/jaw retain coherent source and saddle")
	_assert(not damaged["fragments"].is_empty() and damaged["original_state"].get("fragments", []) == copied["fragments"], "tiny explicit tooth tips survive native injury normalization")
	var overlays: Array = DragonDamageArt.overlay_layers(damaged["all_parts"], damaged["state"], 27, damaged["regions"])
	_assert(not overlays.is_empty(), "source-alpha masks produce actual bloody mangle decals")
	for loss: String in ["head", "neck"]:
		var missing: Dictionary = DragonArt.model(row, "rest", 0, {"lost": [loss], "blood": 0.8})
		_assert(missing["parts"].size() == 1 and missing["parts"][0]["id"] == "body" and missing["all_parts"].size() == 3, "only head/neck hides head and jaw, preserving removed source masks")
		var piece: Dictionary = DragonRigArt.detached(row, loss, "rest", 0, {"lost": [loss]})
		_assert(piece["parts"].size() == 2 and not bool(piece["mountable"]) and "head" not in piece["state"]["lost"] and "neck" not in piece["state"]["lost"], "detached head and jaw render with copied overlay state")
	_assert(not bool(DragonRigArt.detached(row, "wing_upper_r")["valid"]) and not bool(DragonRigArt.detached(row, "jaw")["valid"]), "no detached limb or standalone jaw art")
	_assert(not bool(DragonArt.model(row, "dead")["mountable"]), "corpse preview cannot float a rider")
	_assert(state == copied, "preview does not alter native wounds, fragments or loss state")

func _sizes(row: Dictionary, sizes: Array) -> void:
	var prior: float = 0
	for size: Dictionary in sizes:
		var sized: Dictionary = row.duplicate(true)
		sized["size_class"] = size["id"]
		var info: Dictionary = DragonArt.model(sized, "rest")
		var scale: float = 0.04 * float(size["physical"]["linear_scale"])
		_assert(is_equal_approx(float(info["source_scale"]), scale), "host size uses only shared original-pixel scale")
		_assert(info["bounds"].size.length() > prior and info["rider_height"] == 24 and info["rider_scale"] == 1, "all five sizes enlarge host while rider stays native24")
		prior = info["bounds"].size.length()
		for part: Dictionary in info["parts"]:
			var xf: Transform2D = part["xf"]
			var rect: Rect2i = part["source_rect"]
			var expected: Vector2 = (Vector2(rect.position) - (info["source_origin_px"] as Vector2)) * scale
			_assert(xf.origin.is_equal_approx(expected) and xf.x.is_equal_approx(Vector2(scale, 0)) and xf.y.is_equal_approx(Vector2(0, scale)), "rest transform preserves source coordinates without local fit/stretch")

func _snapshot() -> String:
	return JSON.stringify({"world": Game._serialize(Game.world), "catalogs": Dragons.catalogs(), "rng": str(Game.rng.state), "unit_uid": Unit._next_uid, "item_uid": Item._next_uid})

func _assert(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("dragon source model: ", label)
