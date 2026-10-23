extends RefCounted
## v0.052 individual growth. One DevTools start world; the curve checks are records.
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL dragon growth v052: " + why)

func adult(id: String, points: float, potential: float) -> Dictionary:
	return {"id": id, "name": "Cinderwake", "gem_id": "ruby", "morph_id": "spirewing",
		"size_class": "small", "appearance_seed": 37, "stage": "adult", "alive": true,
		"growth_points": points, "growth_potential": potential, "care": {"health": 1.0}}

func curve_cases() -> void:
	check(DragonGrowth.maturity_id(0.2, 4.0) == "hatchling", "early fraction is hatchling")
	check(DragonGrowth.maturity_id(1.0, 4.0) == "juvenile", "a quarter of potential is juvenile")
	check(DragonGrowth.maturity_id(2.2, 4.0) == "adult", "just past half is the adult curve")
	check(DragonGrowth.maturity_id(3.4, 4.0) == "mature", "the last band is mature")
	var growing := adult("dragon:v052:stage", 0.9, 4.0)
	DragonGrowth.advance(growing, 20.0, 1.0, 1.0, 1.0)
	check(float(growing["growth_points"]) > 1.0 and DragonGrowth.maturity_id(float(growing["growth_points"]), 4.0) == "juvenile", "twenty well-fed days leave the hatchling curve")
	var older := adult("dragon:v052:mature", 3.3, 4.0)
	older["size_class"] = "huge"
	DragonGrowth.advance(older, 24.0, 1.0, 1.0, 1.0)
	check(float(older["growth_points"]) >= 3.4 and DragonGrowth.maturity_id(float(older["growth_points"]), 4.0) == "mature", "the adult curve reaches mature")
	var well := adult("dragon:v052:well", 0.9, 4.0)
	var under := well.duplicate(true)
	var starved := well.duplicate(true)
	var same := well.duplicate(true)
	var well_step := DragonGrowth.advance(well, 10.0, 1.0, 1.0, 1.0)
	var under_step := DragonGrowth.advance(under, 10.0, 0.85, 1.0, 1.0)
	var starve_step := DragonGrowth.advance(starved, 10.0, 0.2, 1.0, 1.0)
	var near_well := DragonGrowth.advance(same, 10.0, 0.96, 1.0, 1.0)
	check(is_equal_approx(float(well_step["delta"]), 10.0 / DragonGrowth.DAYS_PER_BAND), "well-fed hatchling uses the full daily rate")
	check(is_equal_approx(float(under_step["delta"]), 0.55 * 10.0 / DragonGrowth.DAYS_PER_BAND), "underfed uses the slower nutrition band")
	check(float(well_step["delta"]) > float(under_step["delta"]) and float(under_step["delta"]) > 0.0, "well-fed grows faster than underfed")
	check(is_equal_approx(float(near_well["delta"]), float(well_step["delta"])), "every well-fed ratio shares the full rate")
	check(float(starve_step["delta"]) == 0.0 and str(starve_step["reason"]) == "stalled_food" and starved["growth_points"] == 0.9, "starving stalls and changes nothing")
	var low_food := well.duplicate(true)
	var before_low := low_food.duplicate(true)
	var low_step := DragonGrowth.advance(low_food, 1.0, 0.799, 1.0, 1.0)
	check(str(low_step["reason"]) == "stalled_food" and low_food == before_low, "food under 0.8 stalls the curve")
	var shelter := adult("dragon:v052:care", 0.4, 3.0)
	var weak := shelter.duplicate(true)
	var shelter_before := shelter.duplicate(true)
	check(str(DragonGrowth.advance(shelter, 5.0, 1.0, 0.5, 1.0)["reason"]) == "stalled_care" and shelter == shelter_before, "short shelter stalls")
	check(str(DragonGrowth.advance(weak, 5.0, 1.0, 1.0, 0.2)["reason"]) == "stalled_health" and weak == shelter_before, "a weak dragon stalls")
	var capped := adult("dragon:v052:cap", 1.1, 1.25)
	capped["size_class"] = "medium"
	var hit := DragonGrowth.advance(capped, 1.0e20, 1.0, 1.0, 1.0)
	check(bool(hit["changed"]) and float(capped["growth_points"]) == 1.25 and str(capped["size_class"]) == "medium", "growth stops on the potential, inside medium")
	check(not (float(capped["growth_points"]) > 1.25), "points never pass the potential")
	var stopped := DragonGrowth.advance(capped, 10.0, 1.0, 1.0, 1.0)
	check(str(stopped["reason"]) == "at_limit" and float(capped["growth_points"]) == 1.25, "a second stretch stays on the cap")
	var legacy := {"id": "dragon:v052:legacy", "size_class": "huge", "stage": "adult", "alive": true, "gem_id": "ruby"}
	var legacy_before := legacy.duplicate(true)
	var giant := DragonGrowth.advance(legacy, 1.0e300, 50.0, 50.0, 50.0)
	check(float(legacy["growth_points"]) == 4.0 and str(legacy["size_class"]) == "colossal", "a record without potential still reaches colossal")
	check(is_equal_approx(float(giant["rate_per_day"]), 1.0 / DragonGrowth.DAYS_PER_BAND), "legacy overfeed rate is one band a year")
	check(not legacy.has("growth_potential"), "legacy growth does not invent a potential")
	legacy.erase("growth_points")
	legacy["size_class"] = legacy_before["size_class"]
	check(legacy == legacy_before, "legacy growth writes points and size only")

func founders() -> void:
	var spec := DragonGrowth.rules()
	var span_min := float(spec.get("founder_span_min", 0.85))
	var span_max := float(spec.get("founder_span_max", 3.15))
	var span_ok := true
	var colossal := 0
	for i in 400:
		var draw := DragonGrowth.founder_draw("founder:%d" % i)
		if draw >= 4.0:
			colossal += 1
			if DragonGrowth.band_index(draw) != 4:
				span_ok = false
		elif draw < span_min - 0.000001 or draw > span_max + 0.000001 or DragonGrowth.band_index(draw) >= 4:
			span_ok = false
	check(span_ok, "founder draws stay in the authored span unless they are colossal")
	check(colossal >= 5 and colossal <= 45, "about one founder in twenty is colossal (got %d of 400)" % colossal)
	var picked := ""
	var expect := 4.0
	for i in 80:
		var id := "founder:shrink:%d" % i
		expect = DragonGrowth.founder_draw(id)
		if expect < 3.9:
			picked = id
			break
	check(picked != "", "a non-colossal founder id exists")
	var created := {"id": picked, "stage": "adult", "alive": true, "size_class": "colossal", "growth_points": 4.0}
	DragonGrowth.assign_new(created)
	check(is_equal_approx(float(created["growth_points"]), expect) and is_equal_approx(float(created["growth_potential"]), expect), "creation stores the draw in place of the size roll")
	check(str(created["size_class"]) == DragonGrowth.SIZE_IDS[DragonGrowth.band_index(expect)] and float(created["growth_points"]) < 4.0, "a new founder is not left colossal by the discarded roll")
	var old := {"id": "dragon:old:9", "stage": "adult", "alive": true, "size_class": "large", "growth_points": 2.4}
	var old_draw := DragonGrowth.founder_draw(str(old["id"]))
	DragonGrowth.ensure(old)
	check(float(old["growth_points"]) == 2.4 and str(old["size_class"]) == "large", "an old save keeps its points and size")
	check(is_equal_approx(float(old["growth_potential"]), maxf(old_draw, 2.4)) and float(old["growth_potential"]) >= 2.4, "an old save's potential is at least its current points")
	var egg := {"id": "dragon:egg:1", "stage": "egg", "alive": true, "size_class": "huge", "growth_points": 3.2}
	DragonGrowth.ensure(egg)
	check(is_equal_approx(float(egg["growth_potential"]), DragonGrowth.founder_draw(str(egg["id"]))) and float(egg["growth_points"]) == 3.2, "an egg stores the draw and not its unused size roll")

func screen_and_hardness() -> void:
	var row := adult("dragon:v052:screen", 0.4, 3.0)
	var starving := {"food_need_units": 10, "food_possible_units": 0, "upkeep_need_units": 2, "upkeep_possible_units": 2, "health": 1.0}
	var shown := DragonGrowth.summary(row, starving)
	check(shown.contains("Size: ") and shown.contains("Maturity: ") and shown.contains(" to "), "the screen line has size, maturity, and a range")
	check(shown.contains("stalled") and shown.to_lower().contains("starv"), "starving is named as the stall")
	check(not shown.contains("points"), "the screen does not print the potential")
	var fed := {"food_need_units": 10, "food_possible_units": 10, "upkeep_need_units": 2, "upkeep_possible_units": 2, "health": 1.0}
	check(not DragonGrowth.summary(row, fed).to_lower().contains("stalled"), "a well-fed dragon below its cap is not stalled")
	var topped := adult("dragon:v052:top", 1.25, 1.25)
	topped["size_class"] = "medium"
	var cap_text := DragonGrowth.summary(topped, fed)
	check(cap_text.contains("Maturity: Mature") and cap_text.contains("it has reached its growth potential."), "a dragon on its cap reads as mature and finished")
	check(DragonGrowth.summary({"stage": "egg", "id": "egg"}, fed) == "", "an egg has no growth line")
	var body := adult("dragon:v052:gem", 0.2, 3.5)
	var before := Dragons.physical_profile(Game, body)
	var saved := body.duplicate(true)
	DragonGrowth.advance(body, 40.0, 1.0, 1.0, 1.0)
	var after := Dragons.physical_profile(Game, body)
	check(float(after["body_mass_kg"]) > float(before["body_mass_kg"]) and float(after["tooth_length_cm"]) > float(before["tooth_length_cm"]), "growth increases mass and tooth length")
	check(float(after["hardness_index"]) == float(before["hardness_index"]), "gem hardness is unchanged")
	check(float(after["tooth_material"]["shear_yield"]) == float(before["tooth_material"]["shear_yield"]) and float(after["tooth_material"]["impact_yield"]) == float(before["tooth_material"]["impact_yield"]), "tooth yields stay on the gem")
	check(float(after["claw_material"]["shear_yield"]) == float(before["claw_material"]["shear_yield"]), "claw yield stays on the gem")
	saved.erase("growth_points")
	saved.erase("size_class")
	var moved := body.duplicate(true)
	moved.erase("growth_points")
	moved.erase("size_class")
	check(moved == saved, "a curve step writes points and size only")

func inherit_and_wounds() -> void:
	var records: Dictionary = Game.world["dragons"]["records"]
	var missing := 0
	var before := {}
	for uid in records.keys():
		var row: Dictionary = records[uid]
		if not DragonGrowth.has_potential(row):
			missing += 1
		if str(row.get("stage", "")) == "egg":
			continue
		before[str(uid)] = [DragonGrowth.current_points(row), str(row.get("size_class", ""))]
	check(missing == 0, "loading stores a potential on every dragon")
	DragonGrowth.ensure_all(Game)
	DragonGrowth.ensure_all(Game)
	var shrunk := false
	for uid in before.keys():
		var row: Dictionary = records[uid]
		if not is_equal_approx(DragonGrowth.current_points(row), float(before[uid][0])) or str(row.get("size_class", "")) != str(before[uid][1]):
			shrunk = true
	check(not shrunk, "a second load pass does not shrink points or change size")
	var sample: Dictionary = records[records.keys()[0]]
	var packed: Variant = JSON.parse_string(JSON.stringify(sample))
	check(packed is Dictionary and is_equal_approx(float((packed as Dictionary)["growth_potential"]), float(sample["growth_potential"])), "potential survives a JSON roundtrip")
	var mother := {"id": "dragon:v052:mother", "stage": "adult", "alive": true, "size_class": "small", "growth_points": 0.4, "growth_potential": 1.2}
	var father := {"id": "dragon:v052:father", "stage": "adult", "alive": true, "size_class": "small", "growth_points": 1.0, "growth_potential": 2.8}
	var seen_min := 99.0
	var seen_max := -1.0
	var bounded := true
	for i in 40:
		var child := DragonGrowth.inherit(Game, mother, father, "pair:%d" % i)
		if child < 1.0 - 0.000001 or child > 3.0 + 0.000001:
			bounded = false
		seen_min = minf(seen_min, child)
		seen_max = maxf(seen_max, child)
	check(bounded, "a child stays within the parents plus the inherit slack")
	check(seen_max - seen_min > 0.05 and seen_max - seen_min <= 0.4 + 0.000001, "children land near the middle of the parents")
	var adults: Array = []
	for uid in records.keys():
		var row: Dictionary = records[uid]
		if bool(row.get("alive", false)) and str(row.get("stage", "")) == "adult" and not Dragons._person(Game, str(row.get("owner_person_uid", ""))).is_empty():
			adults.append(row)
	check(adults.size() >= 2, "two owned adults are available to lay")
	if adults.size() >= 2:
		var dam: Dictionary = adults[0]
		var sire: Dictionary = adults[1]
		dam["growth_points"] = 0.4
		dam["growth_potential"] = 1.3
		dam["size_class"] = "small"
		sire["growth_points"] = 0.4
		sire["growth_potential"] = 2.7
		sire["size_class"] = "small"
		var day := 3
		var clutch := "%s:%s:clutch:%d:%d" % [str(dam["id"]), str(sire["id"]), day, 0]
		var expected := DragonGrowth.inherit(Game, dam, sire, clutch)
		var egg: Dictionary = DragonBreeding.spawn_egg(Game, dam, sire, day, 0)
		check(not egg.is_empty(), "the clutch egg is created")
		if not egg.is_empty():
			check(is_equal_approx(float(egg["growth_potential"]), expected) and float(egg["growth_points"]) == 0.0, "the egg stores the inherited potential and starts ungrown")
			check(float(egg["growth_potential"]) >= 1.1 - 0.000001 and float(egg["growth_potential"]) <= 2.9 + 0.000001, "the laid egg stays near its parents")
	if adults.is_empty():
		check(false, "no adult to wound")
		return
	var wounded: Dictionary = adults[0]
	wounded["growth_potential"] = 3.5
	wounded["growth_points"] = 0.2
	wounded["size_class"] = "small"
	if wounded.get("care", {}) is Dictionary:
		wounded["care"]["health"] = 1.0
	DragonCombat.prepare_world(Game)
	var unit: Unit = DragonCombat._unit(Game, str(wounded["id"]))
	var body_ready := unit != null and unit.body != null
	check(body_ready, "the adult has a native wyvern body")
	if not body_ready:
		return
	var leg: Dictionary = unit.body.wound_part("leg_upper_l")
	var muscle := false
	for layer in leg.get("layers", []):
		if str(layer.get("tissue", "")) == "muscle":
			layer["dmg"] = 0.3
			layer["kind"] = "cut"
			muscle = true
	check(muscle, "the hind leg has a muscle layer to injure")
	unit.body.wound_part("wing_lower_r")["severed"] = true
	var fraction := 0.62
	unit.body.blood = unit.body.blood_max * fraction
	var wounds: Dictionary = unit.body.parts.duplicate(true)
	var profile_before := Dragons.physical_profile(Game, wounded)
	DragonGrowth.advance(wounded, 40.0, 1.0, 1.0, 1.0)
	check(DragonCombat.sync_profile(Game, str(wounded["id"])), "growth refreshes the native profile")
	var profile_after := Dragons.physical_profile(Game, wounded)
	check(unit.body.parts == wounds and unit.body.is_lost("wing_lower_r"), "the wound and the lost wing survive growth")
	check(absf(unit.body.blood / unit.body.blood_max - fraction) < 0.000001, "blood fraction is kept while the body scales")
	check(float(profile_after["hardness_index"]) == float(profile_before["hardness_index"]), "the wounded dragon's gem hardness is unchanged")
	check(float(profile_after["tooth_material"]["shear_yield"]) == float(profile_before["tooth_material"]["shear_yield"]) and float(profile_after["tooth_material"]["impact_yield"]) == float(profile_before["tooth_material"]["impact_yield"]), "the wounded dragon's yields stay on the gem")
	check(float(profile_after["body_mass_kg"]) > float(profile_before["body_mass_kg"]) and float(profile_after["tooth_length_cm"]) > float(profile_before["tooth_length_cm"]), "the wounded dragon's mass and teeth still grow")

func run(tree: SceneTree) -> int:
	curve_cases()
	founders()
	screen_and_hardness()
	if not await DevTools.start_world(tree, "user://test_dragon_growth_v052.json"):
		check(false, "the start world failed to load")
	else:
		inherit_and_wounds()
	print("dragon growth v052: %d checks, %d failures" % [checks, fails])
	return fails
