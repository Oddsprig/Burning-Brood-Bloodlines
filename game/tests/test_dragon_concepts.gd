extends RefCounted
## Exact metadata and compact imported portrait checks; no campaign setup.
const Registry = preload("res://art/dragon_concepts.gd")
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon concepts: " + message)

func run(_tree: SceneTree) -> int:
	var before: String = JSON.stringify(Game._serialize(Game.world))
	var rng_state: int = Game.rng.state
	var next_unit: int = Unit._next_uid
	var expected: Dictionary = {"ruby": "broadmantle", "sapphire": "spirewing", "black_diamond": "ironcrest",
		"emerald": "reedrunner", "amethyst": "duskfin", "opal": "stormkeel", "topaz": "broadmantle",
		"garnet": "ironcrest", "jade": "stormkeel", "aquamarine": "duskfin", "citrine": "reedrunner",
		"moonstone": "spirewing", "pearl": "duskfin", "onyx": "ironcrest", "diamond": "spirewing", "tourmaline": "reedrunner"}
	var rows: Array = Registry.entries()
	check(rows.size() == 16, "sixteen explicitly authored type/body-form entries")
	var seen: Dictionary = {}
	for example in rows:
		var gem: String = str(example["gem_id"])
		check(expected.has(gem) and expected.get(gem, "") == example["morph_id"] and not seen.has(gem), "exact authored pair: " + gem)
		seen[gem] = true
		check(example["asset_path"] == "res://art/concepts/dragon_%s_v006.webp" % gem
			and example["type_example"] and example["caption"] == "%s Dragon · %s portrait" % [example["gem_name"], example["morph_name"]],
			"exact WebP asset and plain type/body-form caption: " + gem)
		var description: String = str(example["description"])
		check(description.contains("curved horns match the gem type") and description.contains("only on horns, teeth and claws")
			and description.contains("Organic gem-hued skin and scales") and description.contains("never a jewel body"),
			"type description gives gem horns while preserving organic skin/scales: " + gem)
		var actual: Dictionary = {"gem_id": gem, "morph_id": example["morph_id"], "id": "native-personal-dragon",
			"name": "Personal name", "stage": "juvenile", "size_id": "small", "appearance_seed": 91}
		var copy: Dictionary = actual.duplicate(true)
		check(Registry.matches(actual) and Registry.for_record(actual) == example and actual == copy, "type match preserves individual record: " + gem)
		var texture: Texture2D = Registry.texture_for_record(actual)
		check(texture != null and texture.get_width() == 384 and texture.get_height() == 384,
			"exact portrait imports at compact 384 by 384 dimensions: " + gem)
		if texture != null:
			var image: Image = texture.get_image()
			check(image != null and not image.is_empty() and image.get_size() == Vector2i(384, 384), "imported portrait decodes correctly: " + gem)
			check(Registry.texture(gem) == texture, "successful exact texture reused: " + gem)
		var file: FileAccess = FileAccess.open(str(example["asset_path"]), FileAccess.READ)
		check(file != null and file.get_length() > 0 and file.get_length() <= 128 * 1024, "portrait source is compact (at most 128 KiB): " + gem)
	rows[0]["caption"] = "caller edit"
	check(Registry.entry("ruby")["caption"] != "caller edit", "registry metadata copies cannot change later entries")
	var mismatch: Dictionary = {"gem_id": "sapphire", "morph_id": "broadmantle", "asset_path": Registry.entry("ruby")["asset_path"]}
	check(not Registry.matches(mismatch) and Registry.for_record(mismatch).is_empty()
		and Registry.texture_for_record(mismatch) == null, "mismatched body form cannot substitute another portrait or supplied path")
	check(Registry.entry("missing").is_empty() and Registry.texture("missing") == null
		and not Registry.matches({}) and Registry.texture_for_record({}) == null, "unknown/empty identity never falls back to an unrelated example")
	check(JSON.stringify(Game._serialize(Game.world)) == before and Game.rng.state == rng_state and Unit._next_uid == next_unit,
		"registry reads preserve campaign state, people/accounts, RNG and native Unit counter")
	print("dragon concepts: %d checks, %d failures" % [checks, fails])
	return fails
