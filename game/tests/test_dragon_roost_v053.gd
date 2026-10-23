extends RefCounted
## One DevTools world; three holdings, still UI, no campaign time or native window changes.
var checks := 0
var fails := 0
var tree: SceneTree

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL dragon roost v053: " + why)

func settle() -> void:
	for _i in 5: await tree.process_frame

func state_hash() -> String:
	return JSON.stringify([Game._serialize(Game.world), Game._serialize(Game.company), Game.gold,
		Game.day, Game.location, str(Game.rng.state), Unit._next_uid, Item._next_uid]).sha256_text()

func cache_sizes() -> Array:
	var people := Paperdoll.cache_stats()
	return [DragonCard._shared.size(), DragonRigArt._sources.size(), DragonRigArt._images.size(),
		DragonRigArt._textures.size(), DragonArt._tints.size(), people["entries"],
		people["payload_bytes"], people["signature_entries"], people["signature_bytes"]]

func words(node: Node) -> String:
	var text := str(node.text) + "\n" if node is Label else ""
	for child: Node in node.get_children(): text += words(child)
	return text

func entry(roost: DragonRoost, uid: String) -> Dictionary:
	for value: Dictionary in roost._entries:
		if str(value["row"]["id"]) == uid: return value
	return {}

func fixture_house(choice: Dictionary) -> bool:
	var tid := str(choice["town_id"])
	if Persons.race_of(Game.world["towns"][tid]["econ"]) != "human": return false
	var adults := 0
	for person: Dictionary in Dragons.people(Game):
		if str(person.get("household_uid", "")) == str(choice["household_uid"]) and DragonBond._adult(person) and Dragons._present(person, tid):
			adults += 1
	return adults >= 2

func fit(roost: DragonRoost, viewport: SubViewport, context: String) -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(viewport.size))
	check(screen.grow(1).encloses(roost.get_global_rect()), context + ": complete roost fits viewport")
	check(screen.grow(1).encloses(roost._panel.get_global_rect()), context + ": selection panel fits viewport")
	var yard := Rect2(Vector2.ZERO, roost._yard.size)
	for value: Dictionary in roost._entries:
		check(yard.grow(1).encloses(value["screen_bounds"]), context + ": whole dragon and attendants fit")
		check(yard.grow(1).encloses(value["dragon_rect"]), context + ": complete egg/dragon fits")
		for person: Dictionary in value["people"]:
			var doll: Paperdoll = person["doll"]
			var race := str(doll.current_spec().get("race", "human"))
			var dimensions := FigurePainter.dims(race)
			var scale := doll.scale.x * FigurePainter.display_scale(race)
			var drawn := Rect2(doll.position - Vector2(dimensions["anchor"]) * scale, Vector2(dimensions["size"]) * scale)
			check(yard.grow(1).encloses(drawn), context + ": actual figure canvas fits")
			check(is_equal_approx(doll.scale.x * FigurePainter.PX, roost._scale), context + ": people retain human scale")
	if viewport.size.x < viewport.size.y:
		check(roost._panel.position.y >= roost._yard.size.y, context + ": portrait panel below yard")
	else:
		check(roost._panel.position.x >= roost._yard.size.x, context + ": landscape panel beside yard")

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	await tree.process_frame
	var started := Time.get_ticks_msec()
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "DevTools world loads")
		tree = null
		return fails
	var tid := DevTools.choose_house(Game, fixture_house)
	check(tid != "", "native household with two human adults exists")
	if tid == "":
		tree = null
		return fails
	var owner := Dragons._person(Game, str(Dynasty.selected(Game)["ruler_uid"]))
	var rider_uid := ""
	for person: Dictionary in Dragons.people(Game):
		if str(person.get("household_uid", "")) == str(owner["household_uid"]) and str(person["person_uid"]) != str(owner["person_uid"]) and DragonBond._adult(person) and Dragons._present(person, tid):
			rider_uid = str(person["person_uid"])
			break
	check(rider_uid != "", "distinct native rider exists")
	if rider_uid == "":
		tree = null
		return fails
	# Fixture mutations end before opening the view. No fake people, Units or art.
	Game.world["dragons"] = {"schema": 1, "next_id": 1, "records": {}, "pairs": {}, "initialized": true}
	var egg := Dragons._make(Game, "egg", tid, owner, "v053:egg", 0, "unknown")
	var small := Dragons._make(Game, "adult", tid, owner, "v053:small", 0, "female")
	var large := Dragons._make(Game, "adult", tid, owner, "v053:large", 0, "male")
	for row: Dictionary in [egg, small, large]:
		row["gem_id"] = "ruby"
		row["morph_id"] = "spirewing"
		row["appearance_seed"] = 37
		row["growth_potential"] = 4.0
	small["size_class"] = "small"
	small["growth_points"] = 0.25
	small["rider_person_uid"] = rider_uid
	large["size_class"] = "huge"
	large["growth_points"] = 3.5
	large["custodian_person_uid"] = ""
	large["approach"] = {"person_uid": str(owner["person_uid"]), "familiarity": 23.5, "cooldown_until": 0}
	var expected_ratio := float(DragonGrowth.metrics(small)["linear_scale"]) / float(DragonGrowth.metrics(large)["linear_scale"])
	var before := state_hash()
	var events := [0]
	var changed: Callable = func(): events[0] += 1
	Game.changed.connect(changed)
	var saves := int(Game.save_stats().get("started", 0))
	var warm: Array = []
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for opening: int in 5:
		Game.screen_params = {"roost": opening > 0, "roost_uid": str(small["id"])}
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 720)
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		tree.root.add_child(viewport)
		var page: DragonsView = (load("res://ui/dragons.tscn") as PackedScene).instantiate()
		viewport.add_child(page)
		await settle()
		if opening == 0:
			var toggle := page.find_child("DragonRoostToggle", true, false) as Button
			check(toggle != null and toggle.text == "Roost", "Roost toggle sits beside List")
			if toggle != null: toggle.pressed.emit()
			await settle()
		var roost: DragonRoost = page.roost
		check(roost != null, "household roost opens")
		if roost == null:
			viewport.queue_free()
			await settle()
			continue
		check(roost._entries.size() == 3, "egg and two household dragons are shown")
		var a := entry(roost, str(small["id"]))
		var b := entry(roost, str(large["id"]))
		var shell := entry(roost, str(egg["id"]))
		check(not a.is_empty() and not b.is_empty() and not shell.is_empty(), "all three holdings have render geometry")
		if not a.is_empty() and not b.is_empty() and not shell.is_empty():
			check((a["people"] as Array).size() == 2 and (shell["people"] as Array).size() == 1, "keeper and distinct rider stand beside their holding")
			check((b["people"] as Array).is_empty(), "missing roles create no substitute figures")
			for person: Dictionary in a["people"]:
				var doll: Paperdoll = person["doll"]
				var spec := Dynasty.portrait_for(Game, Dynasty.person(Game, str(person["uid"])))
				spec["team"] = doll.team_color
				check(doll.unit == null and doll.current_spec() == spec, "standing figure uses the actual person's appearance")
			for dimensions: Vector2i in [Vector2i(390, 844), Vector2i(1280, 720)]:
				viewport.size = dimensions
				await settle()
				fit(roost, viewport, str(dimensions))
				var drawn_ratio := (a["dragon_rect"] as Rect2).size.x / (b["dragon_rect"] as Rect2).size.x
				check(is_equal_approx(drawn_ratio, expected_ratio), "drawn width ratio matches fractional v052 profile size")
			roost.select(str(small["id"]))
			check("Bond:" in words(roost._facts) and "(active)" in words(roost._facts), "bond state appears in side panel")
			roost.select(str(large["id"]))
			var shown := words(roost._facts)
			check("Stage: Adult" in shown and "Size:" in shown and "Maturity:" in shown and "Growth is stalled:" in shown, "growth stage, band and stall are readable")
			check("Familiarity 23.5" in shown, "v051 approach progress is read from the actual record")
			check(roost._uid_at((shell["dragon_rect"] as Rect2).get_center()) == str(egg["id"]), "egg artwork is selectable")
			var tap := InputEventScreenTouch.new()
			tap.position = (shell["dragon_rect"] as Rect2).get_center()
			tap.pressed = true
			roost._yard.gui_input.emit(tap)
			check(roost.selected_uid == str(egg["id"]), "tapping egg artwork selects its side panel")
			check("Egg condition:" in words(roost._facts) and "Size band: Unhatched" in words(roost._facts), "egg side panel shows care and growth state")
			check(roost._facts.find_children("*", "BaseButton", true, false).is_empty(), "side panel contains no simulation orders")
			var held_cache := cache_sizes()
			var builds := int(Paperdoll.cache_stats()["spec_builds"])
			await settle()
			check(cache_sizes() == held_cache and int(Paperdoll.cache_stats()["spec_builds"]) == builds and not roost.is_processing(), "idle view does no polling, animation or art rebuilding")
		check(state_hash() == before, "opening, resizing and selecting preserve the world/Units/IDs/RNG hash")
		check(events[0] == 0 and int(Game.save_stats().get("started", 0)) == saves, "inspection emits no world changes or saves")
		var released: WeakRef = weakref(roost)
		viewport.queue_free()
		page = null
		roost = null
		viewport = null
		await settle()
		check(released.get_ref() == null, "closing releases the view and its child figures")
		if opening == 0:
			warm = cache_sizes()
		else:
			check(cache_sizes() == warm, "opening/closing five times does not grow shared caches")
	Game.changed.disconnect(changed)
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_before, "no orphan controls or figures after closing")
	check(Time.get_ticks_msec() - started < 60000, "test finishes in under 60 seconds")
	print("Dragon roost v053: %d checks, %d failures." % [checks, fails])
	tree = null
	return fails
