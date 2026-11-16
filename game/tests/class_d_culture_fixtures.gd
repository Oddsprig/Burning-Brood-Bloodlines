extends RefCounted
## Complete culture coverage using the native economy generator, never relabelled economy/person rows.
static func towns(game: Node) -> Dictionary:
	var registry: Dictionary = TownEcon.data()["cultures"]
	if registry.is_empty():
		return {"ok": false, "reason": "native culture registry is empty"}
	var found: Dictionary = {}
	var source: Dictionary = {}
	var ids: Array = game.world["towns"].keys()
	ids.sort()
	for tid: String in ids:
		var town: Dictionary = game.world["towns"][tid]
		if not TownEcon.has_econ(town): continue
		var culture: String = str(town["econ"]["culture"])
		if not registry.has(culture):
			return {"ok": false, "reason": "unregistered generated culture: " + culture}
		if not found.has(culture): found[culture] = town
		if source.is_empty() or town["econ"]["fams"].size() > source["econ"]["fams"].size():
			source = town
	if source.is_empty():
		return {"ok": false, "reason": "native culture fixture needs a generated source town"}
	var cultures: Array = registry.keys()
	cultures.sort()
	for culture: String in cultures:
		if found.has(culture): continue
		# Culture/race are generator inputs; every household, person and plot is generated afresh.
		var town: Dictionary = source.duplicate(true)
		town.erase("econ")
		town["id"] = "class_d_" + culture
		town["culture"] = culture
		town["race"] = str(registry[culture]["race"])
		# Do not copy Item objects, recruit lists or economy caches from the source.
		for key: String in ["shop", "recruits", "contracts", "roads", "neighbours"]:
			town[key] = []
		for key: String in ["crafters", "healer", "prices", "material_prices"]:
			town[key] = {}
		if game.world["towns"].has(town["id"]):
			return {"ok": false, "reason": "native culture fixture town ID already exists: " + str(town["id"])}
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = hash([game.world["seed"], culture, "class-d-native-economy"])
		Economy.make_crafters(town, rng)
		Economy.roll_prices(town, rng)
		EconGen.generate(game.world, town, rng)
		if not TownEcon.has_econ(town) or str(town["econ"].get("culture", "")) != culture:
			return {"ok": false, "reason": "needs game fix: campaign/econ_gen.gd did not generate culture " + culture}
		# Campaign generation lays out physical fields after EconGen, not inside it.
		# Derive these plots from this culture's actual generated holdings too.
		Plots.layout(game.world, town)
		if Plots.needs_layout(town["econ"]):
			return {"ok": false, "reason": "native culture fixture needs complete physical plots for " + culture}
		found[culture] = town
	return {"ok": true, "towns": found}
