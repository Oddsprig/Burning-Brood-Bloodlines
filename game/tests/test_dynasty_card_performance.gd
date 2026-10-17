extends RefCounted
## Deterministic UI invalidation checks, without time advancement or Unit creation.
var checks := 0
var fails := 0

class CountingCard extends DynastyCard:
	var forced_reads := 0
	func refresh(force: bool = false) -> void:
		if force and portrait != null: forced_reads += 1
		super.refresh(force)

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL dynasty card: " + why)

func burst(count: int = 100) -> void:
	for i in count: Game.changed.emit()

func fixture() -> Array:
	var p: Array = [1, 0, 0, -5000, "", -1, 0, "Original Ruler", -1, -1, -1, "", [], 0, {},
		"person:card", "house:card", "", "", ""]
	var f: Dictionary = {"id": 1, "name": "Native", "household_uid": "household:card",
		"founding_house_uid": "house:card", "gone": false, "pp": [p], "kp": [], "purse": 77.0}
	Game.world = {"seed": 12, "towns": {"t": {"id": "t", "name": "Test City", "faction": "middle_kingdom",
		"econ": {"culture": "middle", "fams": [{"id": 0, "estate": true, "pp": [], "kp": []}, f],
		"head": {"person_uid": "person:card", "house_uid": "house:card", "household_uid": "household:card"}}}},
		"warbands": {}, "player_house": {"town_id": "t", "house_uid": "house:card",
			"household_uid": "household:card", "ruler_uid": "person:card", "title": "Lord"}}
	Game.company = []
	Game.day = 10.0
	return p

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var original_world: Dictionary = Game.world
	var original_company: Array = Game.company
	var original_day: float = Game.day
	var rng_state: int = Game.rng.state
	var next_unit: int = Unit._next_uid
	var next_item: int = Item._next_uid
	var connections: int = Game.changed.get_connections().size()
	var orphan_baseline: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var p: Array = fixture()
	var snapshot: PackedByteArray = var_to_bytes(Game._serialize(Game.world))
	var card := CountingCard.new()
	# Advance only this UI cooldown manually, so a fast/slow host has equal results.
	card.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(card)
	check(card.ruler_name.text == "Original Ruler", "initial actual native ruler read")
	check(not card.is_processing(), "idle card has no processing callback")
	check(Game.changed.get_connections().size() == connections + 1, "one bound change listener")
	var texture_id: int = card.portrait._tex.get_instance_id()
	burst()
	check(card.forced_reads == 0 and card.is_processing(), "100 signals queue one dirty read without synchronous work")
	card._process(0.10)
	check(card.forced_reads == 0, "cooldown groups moving frames")
	card._process(0.151)
	check(card.forced_reads == 1 and not card.is_processing(), "burst flushes once within 0.25 seconds")
	check(card.portrait._tex.get_instance_id() == texture_id, "unchanged burst reuses portrait texture")
	check(var_to_bytes(Game._serialize(Game.world)) == snapshot and Game.day == 10.0, "refresh does not advance frozen time or mutate register")
	card._process(1.0)
	check(card.forced_reads == 1, "idle manual frame performs no read")
	for interval in 4:
		burst()
		card._process(0.25)
	check(card.forced_reads == 5, "400 additional signals take four bounded forced reads")
	p[7] = "Renamed Ruler"
	burst()
	card.refresh() # Map HUD's cheap same-day read must not swallow the dirty update.
	check(card.ruler_name.text == "Original Ruler", "same-day normal refresh remains cheap")
	card._process(0.25)
	check(card.ruler_name.text == "Renamed Ruler" and card.forced_reads == 6, "same-day native name eventually refreshes")
	var town: Dictionary = Game.world["towns"]["t"]
	town["faction"] = "moon_court"
	burst()
	card._process(0.25)
	check(card.portrait._spec == Dynasty.portrait_spec(Game), "same-day faction renders current native portrait")
	check(card.portrait._tex.get_instance_id() != texture_id, "changed appearance replaces portrait texture")
	p[2] = 1
	burst()
	card.refresh(true)
	check(card.portrait._spec["sex"] == "female" and not card.is_processing(), "explicit same-day forced refresh is immediate and clears pending work")
	var reads: int = card.forced_reads
	card._process(0.25)
	check(card.forced_reads == reads, "explicit refresh prevents a redundant delayed read")
	_equipment_check(card, p, original_company)
	p[4] = "dead"
	burst(); card._process(0.25)
	check(card.office_state.text == "LAST RULER" and card.portrait._spec["dead"], "same-day actual death refreshes remembered ruler")
	card.free()
	check(Game.changed.get_connections().size() == connections, "freed card removes bound listener")
	burst() # Stale callbacks must not survive the destroyed control.
	# A card can leave and re-enter the tree without duplicate or missing listeners.
	var replacement := CountingCard.new()
	replacement.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(replacement)
	tree.root.remove_child(replacement)
	check(Game.changed.get_connections().size() == connections, "detached card disconnects before destruction")
	tree.root.add_child(replacement)
	check(Game.changed.get_connections().size() == connections + 1, "re-entered card reconnects once")
	replacement.free()
	Game.world = original_world; Game.company = original_company; Game.day = original_day
	await tree.process_frame
	check(Game.changed.get_connections().size() == connections, "replacement leaves no signal listeners")
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == orphan_baseline, "card and portrait children leave no orphan nodes")
	check(Game.rng.state == rng_state and Unit._next_uid == next_unit and Item._next_uid == next_item, "display never creates Units/Items or consumes campaign RNG")
	print("Dynasty card performance: %d checks, %d failures" % [checks, fails])
	return fails

func _equipment_check(card: CountingCard, p: Array, existing: Array) -> void:
	# Reuse a real supplied unit only; an empty isolated fixture cannot prove gear.
	var bound: Unit = null
	for u in existing:
		if u is Unit and u.race == "human" and not u.dead and u.equip.get("helm", null) != null:
			bound = u; break
	if bound == null:
		print("Dynasty card gear case unavailable: no existing equipped human Unit supplied")
		return
	var old_home: String = bound.home_town
	var old_family: int = bound.family
	var old_equip: Dictionary = bound.equip
	bound.home_town = "t"; bound.family = 1
	p[4] = "company"; p[5] = bound.uid
	Game.company = [bound]
	card.refresh(true)
	check(card.portrait._spec["helm"]["tid"] == bound.equip["helm"].tid, "actual existing ruler equipment renders")
	var equipped_key: int = card._visual_key
	bound.equip = old_equip.duplicate(); bound.equip.erase("helm")
	burst(); card._process(0.25)
	check(card._visual_key != equipped_key and card.portrait._spec["helm"].is_empty(), "same-day actual equipment removal eventually refreshes")
	bound.home_town = old_home; bound.family = old_family; bound.equip = old_equip
	p[4] = ""; p[5] = -1
	Game.company = []
