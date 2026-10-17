class_name DragonConcepts
extends RefCounted
## Authored type/body-form examples, independent of individual native identities.
## Matching a pair never makes this image an age/size/seed-specific likeness.
const PAIRS := [
	["ruby", "Ruby", "broadmantle"], ["sapphire", "Sapphire", "spirewing"],
	["black_diamond", "Black Diamond", "ironcrest"], ["emerald", "Emerald", "reedrunner"],
	["amethyst", "Amethyst", "duskfin"], ["opal", "Opal", "stormkeel"],
	["topaz", "Topaz", "broadmantle"], ["garnet", "Garnet", "ironcrest"],
	["jade", "Jade", "stormkeel"], ["aquamarine", "Aquamarine", "duskfin"],
	["citrine", "Citrine", "reedrunner"], ["moonstone", "Moonstone", "spirewing"],
	["pearl", "Pearl", "duskfin"], ["onyx", "Onyx", "ironcrest"],
	["diamond", "Diamond", "spirewing"], ["tourmaline", "Tourmaline", "reedrunner"]]
const MORPHS := {
	"broadmantle": ["Broadmantle", "A wide-chested heavy wyvern with broad wings and a thick tail."],
	"spirewing": ["Spirewing", "A lean wyvern with a long neck and tall narrow wings."],
	"ironcrest": ["Ironcrest", "A compact wyvern with a short deep torso and a high crest."],
	"reedrunner": ["Reedrunner", "An elongated low-bodied wyvern with a long tail and slim hind legs."],
	"duskfin": ["Duskfin", "A smooth slender wyvern with swept wings and a finned tail."],
	"stormkeel": ["Stormkeel", "A barrel-bodied wyvern with a deep keeled chest, broad wing roots and sturdy hind legs."]}
const EXAMPLE_NOTE := "An example of this dragon type and body form."
const BIOLOGY_NOTE := "Two hind legs; wings are its only forelimbs, with no separate front legs. Organic gem-hued skin and scales; curved horns match the gem type. Gem faceting and glints only on horns, teeth and claws, never a jewel body."
static var _textures: Dictionary = {}

static func entries() -> Array:
	var out: Array = []
	for pair in PAIRS: out.append(entry(str(pair[0])))
	return out

static func entry(gem_id: String) -> Dictionary:
	for pair in PAIRS:
		if str(pair[0]) != gem_id: continue
		var morph_id: String = str(pair[2])
		var morph: Array = MORPHS[morph_id]
		var gem_name: String = str(pair[1])
		var morph_name: String = str(morph[0])
		return {"gem_id": gem_id, "gem_name": gem_name, "morph_id": morph_id, "morph_name": morph_name,
			"asset_path": "res://art/concepts/dragon_%s_v006.webp" % gem_id, "type_example": true,
			"caption": "%s Dragon · %s portrait" % [gem_name, morph_name],
			"description": "%s Dragon. %s %s %s" % [gem_name, str(morph[1]), BIOLOGY_NOTE, EXAMPLE_NOTE]}
	return {}

## Exact gem/body-form agreement only; age, size, seed and personal name remain
## the individual portrait's responsibility. Eggs can browse this type example.
static func matches(row: Dictionary) -> bool:
	var example: Dictionary = entry(str(row.get("gem_id", "")))
	return not example.is_empty() and str(row.get("morph_id", "")) == str(example["morph_id"])

static func for_record(row: Dictionary) -> Dictionary:
	return entry(str(row.get("gem_id", ""))) if matches(row) else {}

## Normal imported Godot textures; only these sixteen explicit assets can enter
## the successful-load cache. Missing assets can be retried after import.
static func texture(gem_id: String) -> Texture2D:
	var example: Dictionary = entry(gem_id)
	if example.is_empty(): return null
	if _textures.has(gem_id): return _textures[gem_id] as Texture2D
	var path: String = str(example["asset_path"])
	if not ResourceLoader.exists(path, "Texture2D"): return null
	var result: Texture2D = ResourceLoader.load(path, "Texture2D") as Texture2D
	if result == null: return null
	_textures[gem_id] = result
	return result

static func texture_for_record(row: Dictionary) -> Texture2D:
	return texture(str(row.get("gem_id", ""))) if matches(row) else null
