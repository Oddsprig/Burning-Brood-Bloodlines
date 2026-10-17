extends RefCounted
## Real tracked-person/dragon records; no world generation, combat, art or save IO.
const NativeFixture = preload("res://tests/test_dragon_identities.gd")
const CareFixture = preload("res://tests/test_dragon_care.gd")
var native: NativeFixture
var checks: int = 0
var fails: int = 0
var dragon_uid: String = ""
var other_dragon_uid: String = ""
var adult_uid: String = ""
var namesake_uid: String = ""
var child_uid: String = ""
var cohort_uid: String = ""

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon bond: ", why)

func snapshot() -> String:
	return JSON.stringify(Game._serialize({"world": Game.world, "company": Game.company, "squads": Game.squads,
		"day": Game.day, "gold": Game.gold, "location": Game.location, "rng": str(Game.rng.state),
		"unit_next": Unit._next_uid, "item_next": Item._next_uid}), "", true, true)

func native_snapshot() -> String:
	return JSON.stringify(native_tree(), "", true, true)

func native_tree() -> Dictionary:
	var world: Dictionary = Game.world.duplicate(true); world.erase("dragons")
	return Game._serialize({"world": world, "company": Game.company, "squads": Game.squads,
		"gold": Game.gold, "rng": str(Game.rng.state), "unit_next": Unit._next_uid, "item_next": Item._next_uid})

func same_values(a: Variant, b: Variant) -> bool:
	# Native JSON represents integral numbers as floats. No value tolerance.
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]: return is_finite(float(a)) and is_finite(float(b)) and a == b
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same_values(a[key], b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for i: int in a.size():
			if not same_values(a[i], b[i]): return false
		return true
	return a == b

func row(uid: String = "") -> Dictionary:
	return Game.world["dragons"]["records"][dragon_uid if uid == "" else uid]

func person(uid: String) -> Array:
	return Dynasty._person(Game, uid)["person"]

func fixture(tid: String = "a") -> void:
	native = NativeFixture.new(); native.fixture()
	var town: Dictionary = Game.world["towns"]["a"]
	var e: Dictionary = town["econ"]; var f: Dictionary = e["fams"][0]
	var adult_age: int = int(People.ages(Persons.race_of(e))["adult"])
	var p: Array = native.person(e, f, 20, 0, adult_age + 3, "Shared name")
	adult_uid = str(p[Persons.PERSON_UID])
	p = native.person(e, f, 21, 0, adult_age + 4, "Shared name")
	namesake_uid = str(p[Persons.PERSON_UID])
	p = native.person(e, f, 22, 1, adult_age - 1, "Minor candidate")
	child_uid = str(p[Persons.PERSON_UID])
	var cohort: Dictionary = Families._blank(1)
	cohort["cohort"] = true; cohort["name"] = "Pool owner"; cohort["pp"] = []; cohort["kp"] = []
	e["fams"].append(cohort); Families.identity(e, cohort)
	p = native.person(e, cohort, 23, 0, adult_age + 5, "Pool candidate")
	cohort_uid = str(p[Persons.PERSON_UID])
	Dragons.init_world(Game)
	var candidates: Array = []
	for record: Dictionary in Dragons.records(Game):
		if str(record["stage"]) == "adult" and str(record["estate_town_id"]) == tid: candidates.append(str(record["id"]))
	dragon_uid = str(candidates[0]); other_dragon_uid = str(candidates[1])
	var selected_family: Dictionary = Game.world["towns"][tid]["econ"]["fams"][0]
	var result: Dictionary = HouseOnboarding.begin(Game, tid, str(selected_family["household_uid"]))
	check(bool(result["ok"]), "actual native household onboarding positions the existing party")

func reject(result: Dictionary, before: String, why: String) -> void:
	check(not bool(result.get("ok", false)) and str(result.get("reason", "")) != "", why)
	check(snapshot() == before, why + " is pure")

func bind_current(uid: String, rider_uid: String) -> Dictionary:
	return DragonBond.bind(Game, uid, rider_uid, DragonBond.bind_preview(Game, uid, rider_uid))

func readers_and_initial_gate() -> void:
	fixture()
	var before: String = snapshot()
	var status: Dictionary = DragonBond.status(Game, dragon_uid)
	var candidates: Array = DragonBond.candidates(Game, dragon_uid)
	var ids: Array = candidates.map(func(p: Dictionary): return str(p["person_uid"]))
	check(status["can_bind"] and not status["bonded"] and not status["can_release"] and status["at_location"], "unbonded native adult at actual owner home can be reviewed")
	check(ids.has(adult_uid) and ids.has(namesake_uid) and not ids.has(child_uid) and not ids.has(cohort_uid), "eligible-only candidates retain distinct same-name adults and exclude minors/cohorts")
	status["rider_person_uid"] = "copied"; candidates[0]["name"] = "copied"
	var review: Dictionary = DragonBond.bind_preview(Game, dragon_uid, adult_uid)
	check(review["ok"] and review["recipient"]["person_uid"] == adult_uid and review["authority_household_uid"] == row()["owner_household_uid"], "review names exact rider/leader/owning household")
	review["source"]["name"] = "copied"; review["recipient"]["name"] = "copied"
	check(snapshot() == before, "all status/candidates/review rows are detached and conserve native state/RNG/counters")
	reject(DragonBond.bind(Game, dragon_uid, adult_uid), before, "unreviewed bind is refused")
	reject(DragonBond.bind_preview(Game, "missing", adult_uid), before, "unknown dragon is refused")
	reject(DragonBond.bind_preview(Game, dragon_uid, "missing"), before, "unknown person is refused")
	reject(DragonBond.bind_preview(Game, dragon_uid, child_uid), before, "native pre-adult person is refused")
	reject(DragonBond.bind_preview(Game, dragon_uid, cohort_uid), before, "cohort row cannot impersonate tracked rider")
	var egg: String = native.holding("a")
	reject(DragonBond.bind_preview(Game, egg, adult_uid), before, "existing egg cannot form a rider bond")
	row()["alive"] = false; before = snapshot()
	reject(DragonBond.bind_preview(Game, dragon_uid, adult_uid), before, "dead dragon is refused")
	row()["alive"] = true
	person(adult_uid)[4] = "militia"; before = snapshot()
	reject(DragonBond.bind_preview(Game, dragon_uid, adult_uid), before, "home registration alone does not prove absent military person contact")
	person(adult_uid)[4] = ""
	Game.location = "b"; before = snapshot()
	reject(DragonBond.bind_preview(Game, dragon_uid, adult_uid), before, "remote records are not a town visit")
	Game.location = "a"; Game.world["party"]["pos"] = Vector2(1000, 1000); before = snapshot()
	reject(DragonBond.bind_preview(Game, dragon_uid, adult_uid), before, "location string cannot override native party proximity")
	Game.world["party"]["pos"] = Game.world["towns"]["a"]["pos"]

func commands_and_stale_reviews() -> void:
	fixture()
	var native_before: String = native_snapshot()
	var independent: Array = [row()["owner_person_uid"], row()["owner_household_uid"], row()["custodian_person_uid"], row()["location_town_id"], row()["gem_id"], row()["morph_id"], row()["size_class"], row()["appearance_seed"]]
	var review: Dictionary = DragonBond.bind_preview(Game, dragon_uid, adult_uid)
	person(adult_uid)[7] = "Actually renamed"; var before: String = snapshot()
	reject(DragonBond.bind(Game, dragon_uid, adult_uid, review), before, "changed native recipient invalidates a review")
	person(adult_uid)[7] = "Shared name"
	review = DragonBond.bind_preview(Game, dragon_uid, adult_uid)
	row()["custodian_person_uid"] = namesake_uid; before = snapshot()
	reject(DragonBond.bind(Game, dragon_uid, adult_uid, review), before, "changed custody invalidates a review without replacing rider")
	row()["custodian_person_uid"] = independent[2]
	review = DragonBond.bind_preview(Game, dragon_uid, adult_uid)
	Game.day += 0.25; before = snapshot()
	reject(DragonBond.bind(Game, dragon_uid, adult_uid, review), before, "expired day/context invalidates a review")
	Game.day -= 0.25
	check(bind_current(dragon_uid, adult_uid)["ok"], "reviewed command records the actual person bond")
	check(native_snapshot() == native_before and row()["rider_person_uid"] == adult_uid, "bind conserves all original population/coin/items/Units/RNG")
	check([row()["owner_person_uid"], row()["owner_household_uid"], row()["custodian_person_uid"], row()["location_town_id"], row()["gem_id"], row()["morph_id"], row()["size_class"], row()["appearance_seed"]] == independent,
		"owner/custody/location/type/appearance remain independent of rider bond")
	before = snapshot()
	reject(DragonBond.bind(Game, dragon_uid, adult_uid, review), before, "repeat confirmed bind cannot add history twice")
	reject(DragonBond.bind_preview(Game, dragon_uid, namesake_uid), before, "a dragon cannot accept a second active rider")
	reject(DragonBond.bind_preview(Game, other_dragon_uid, adult_uid), before, "a person cannot accept a second active dragon")
	check(DragonBond.bind_preview(Game, other_dragon_uid, namesake_uid)["ok"], "same name is not the same native person identity")
	var released: Dictionary = DragonBond.release_preview(Game, dragon_uid)
	row()["name"] = "Actual name change"; before = snapshot()
	reject(DragonBond.release(Game, dragon_uid, released), before, "changed dragon invalidates release review")
	before = snapshot(); reject(DragonBond.release(Game, dragon_uid), before, "unreviewed release is refused")
	Game.location = ""; Game.world["party"]["pos"] = Vector2(1000, 1000)
	person(adult_uid)[4] = "army"
	DragonBond.reconcile(Game); Dragons.reconcile(Game)
	check(row()["rider_person_uid"] == adult_uid and DragonBond.status(Game, dragon_uid)["active"], "travel/service absence preserves surviving bond despite custody changes")
	check(DragonBond.release(Game, dragon_uid, DragonBond.release_preview(Game, dragon_uid))["ok"], "owner household can explicitly release surviving bond while away")
	check(row()["rider_person_uid"] == "" and row()["last_rider_person_uid"] == adult_uid and row()["last_separation_reason"] == "released", "release retains actual last person and reason")
	before = snapshot(); reject(DragonBond.release(Game, dragon_uid, released), before, "repeat release is pure")

func household_authority() -> void:
	fixture()
	# A real member owns the dragon; the current actual household head manages it.
	Dragons._set_owner(row(), Dragons._person(Game, adult_uid))
	var before: String = native_snapshot()
	check(Dragons.authority(Game, row())["ok"] and bind_current(dragon_uid, namesake_uid)["ok"], "current leader may manage another actual member's holding in same economic household")
	check(row()["owner_person_uid"] == adult_uid and native_snapshot() == before, "household authority does not take personal ownership or native funds")
	check(DragonBond.release(Game, dragon_uid, DragonBond.release_preview(Game, dragon_uid))["ok"], "household leader can release another member's recorded bond")
	# Same birth dynasty, genuinely different economic household: no authority.
	var family: Dictionary = Game.world["towns"]["b"]["econ"]["fams"][1]
	var cadet: Array = Persons.by_pid(family, 10)
	cadet[Persons.HOUSE_UID] = row()["owner_house_uid"]
	Dragons._set_owner(row(), Dragons._person(Game, str(cadet[Persons.PERSON_UID])))
	before = snapshot()
	reject(DragonBond.bind_preview(Game, dragon_uid, namesake_uid), before, "cadet shared dynasty cannot grant another household's asset")
	reject(Dragons.transfer_preview(Game, dragon_uid, namesake_uid), before, "gift authority rejects shared-house foreign household")
	reject(Dragons.set_custodian_preview(Game, dragon_uid, namesake_uid), before, "custodian authority rejects shared-house foreign household")
	# Stale owning household cannot be trusted even with an otherwise live owner.
	Dragons._set_owner(row(), Dragons._person(Game, adult_uid)); row()["owner_household_uid"] = family["household_uid"]
	before = snapshot(); reject(DragonBond.bind_preview(Game, dragon_uid, namesake_uid), before, "malformed household refs require canonical reconciliation")
	Dragons.reconcile(Game)
	check(row()["owner_household_uid"] == Dragons._person(Game, adult_uid)["household_uid"] and Dragons.authority(Game, row())["ok"], "native owner alone repairs canonical household reference")
	# Ordinary household selection, no lordship or public force authority.
	Game.world.erase("player_house")
	var selected: Dictionary = HouseOnboarding.begin(Game, "b", str(family["household_uid"]))
	Dragons._set_owner(row(), Dragons._person(Game, str(cadet[Persons.PERSON_UID])))
	row()["location_town_id"] = "b"
	check(selected["ok"] and not Dynasty.holds_office(Game) and Dragons.authority(Game, row())["ok"], "ordinary actual local household leader has asset authority without office")
	check(bind_current(dragon_uid, str(cadet[Persons.PERSON_UID]))["ok"], "ordinary owner leader can form reviewed bond at actual home")
	fixture()
	var review: Dictionary = DragonBond.bind_preview(Game, dragon_uid, namesake_uid)
	check(Dynasty.appoint(Game, "a", adult_uid), "native office appointment changes the actual selected leader")
	before = snapshot()
	reject(DragonBond.bind(Game, dragon_uid, namesake_uid, review), before, "actual native leadership change invalidates previous authority review")
	check(DragonBond.bind_preview(Game, dragon_uid, namesake_uid)["ok"], "fresh actual leader still manages same-household asset without seizing ownership")

func company_contact_and_physical_death() -> void:
	fixture()
	var loc: Dictionary = Dynasty._person(Game, adult_uid)
	var unit: Unit = Unit.create(str(Persons.race_of(loc["econ"])), "player")
	unit.home_town = "a"
	Persons.bind(loc["econ"], loc["family"], loc["person"], unit, "company", Game.day)
	Game.company.append(unit)
	# A physical identity fixture, not a claimed funded recruitment/muster receipt.
	var before: String = snapshot()
	check(DragonBond.bind_preview(Game, dragon_uid, adult_uid)["ok"], "actual registered company Unit visiting the dragon is eligible")
	check(snapshot() == before, "company contact reader never changes actual Unit/body or service record")
	unit.home_town = "b"; before = snapshot()
	reject(DragonBond.bind_preview(Game, dragon_uid, adult_uid), before, "wrong actual Unit home binding cannot impersonate present registered person")
	unit.home_town = "a"
	Game.company.erase(unit); before = snapshot()
	reject(DragonBond.bind_preview(Game, dragon_uid, adult_uid), before, "missing actual company holder cannot be invented from person UID")
	Game.company.append(unit)
	check(bind_current(dragon_uid, adult_uid)["ok"], "actual company contact can form reviewed relationship")
	Game.location = "b"; Game.world["party"]["pos"] = Game.world["towns"]["b"]["pos"]
	DragonBond.reconcile(Game)
	check(row()["rider_person_uid"] == adult_uid, "actual company departure retains existing bond")
	unit.dead = true
	var native_before: String = native_snapshot()
	DragonBond.reconcile(Game)
	check(row()["rider_person_uid"] == "" and row()["last_rider_person_uid"] == adult_uid, "actual physical rider death clears bond before native person removal")
	check(native_snapshot() == native_before and unit.dead and Game.company.has(unit), "bond death hook never removes person/Unit/gear or double-applies casualty")
	before = snapshot(); DragonBond.reconcile(Game)
	check(snapshot() == before, "actual physical rider death reconciliation repeats once")

func native_age_and_death() -> void:
	fixture("c")
	var elf_uid: String = native.uid("c", 2)
	var elf: Array = person(elf_uid)
	var threshold: int = int(People.ages("moon_elf")["adult"])
	elf[3] = -float(threshold - 1) * People.year_days()
	var before: String = snapshot()
	reject(DragonBond.bind_preview(Game, dragon_uid, elf_uid), before, "elven eligibility uses native adult age rather than human cutoff")
	elf[3] = -float(threshold) * People.year_days()
	check(bind_current(dragon_uid, elf_uid)["ok"], "actual native elf adulthood threshold is eligible")
	native.kill(elf_uid); Dragons.reconcile(Game)
	check(row()["rider_person_uid"] == "" and row()["last_rider_person_uid"] == elf_uid and row()["last_separation_reason"] == "rider_died_or_unavailable", "native person death clears bond and remembers exact dead rider once")
	before = snapshot(); Dragons.reconcile(Game); DragonBond.reconcile(Game)
	check(snapshot() == before, "repeated native person death reconciliation is pure")
	var care_fixture: CareFixture = CareFixture.new(); care_fixture.fixture()
	native = care_fixture.native; dragon_uid = str(care_fixture.dragon_uid)
	adult_uid = str(native.uid("a", 0))
	Game.location = "a"; Game.world["party"]["pos"] = Game.world["towns"]["a"]["pos"]
	check(bind_current(dragon_uid, adult_uid)["ok"], "real native care fixture forms bond before shortage death")
	row()["care"]["health"] = 0.001; row()["custodian_person_uid"] = ""
	# Missing actual keeper means native care shortage, not synthetic death.
	DragonCare.daily(Game, 1)
	check(not row()["alive"] and row()["rider_person_uid"] == "" and row()["last_rider_person_uid"] == adult_uid and row()["last_separation_reason"] == "dragon_died", "native daily care death clears actual dragon bond on that same boundary")
	before = snapshot(); DragonCare.daily(Game, 1); Dragons.reconcile(Game)
	check(snapshot() == before, "same-day care death/reconcile repeats do not duplicate bond history")
	fixture()
	bind_current(dragon_uid, adult_uid)
	row(other_dragon_uid)["rider_person_uid"] = adult_uid # malformed current fixture, not a legal command
	DragonBond.reconcile(Game)
	check(row()["rider_person_uid"] == "" and row(other_dragon_uid)["rider_person_uid"] == "" and row()["last_separation_reason"] == "conflicting_bonds", "malformed duplicate relationships fail closed without appointing an arbitrary winner")
	before = snapshot(); DragonBond.reconcile(Game)
	check(snapshot() == before, "duplicate-link cleanup is idempotent")

func save_and_history() -> void:
	fixture()
	check(bind_current(dragon_uid, adult_uid)["ok"], "current-build native save fixture has real bond")
	var original: Dictionary = row().duplicate(true)
	var native_before: Dictionary = native_tree()
	var world: Dictionary = JSON.parse_string(JSON.stringify(Game._serialize(Game.world), "", true, true))
	Game.world = Game._deserialize(world.duplicate(true))
	Dragons.after_load(Game)
	check(row()["id"] == original["id"] and row()["rider_person_uid"] == adult_uid and row()["owner_person_uid"] == original["owner_person_uid"], "current native JSON keeps exact dragon/person/owner identities")
	check(DragonBond.status(Game, dragon_uid)["active"] and same_values(native_tree(), native_before), "load keeps valid bond and exact native people/funds/Unit values")
	var before: String = snapshot(); Dragons.after_load(Game)
	check(snapshot() == before, "current load reconciliation repeats are pure")
	check(DragonBond.release(Game, dragon_uid, DragonBond.release_preview(Game, dragon_uid))["ok"], "loaded actual bond can be explicitly released")
	for i: int in 20:
		bind_current(dragon_uid, adult_uid)
		DragonBond.release(Game, dragon_uid, DragonBond.release_preview(Game, dragon_uid))
	var history: Array = row()["history"]
	check(history.size() == Dragons.HISTORY_LIMIT and row()["last_rider_person_uid"] == adult_uid and row()["rider_person_uid"] == "", "repeated legitimate bind/release retains bounded history and exact last UID")
	check(str(history[-1]["kind"]) == "bond_released" and str(history[-1]["prior_rider_person_uid"]) == adult_uid, "bounded final history retains actual native separation event")

func run(_tree: SceneTree) -> int:
	var original: Dictionary = {"world": Game.world, "company": Game.company, "squads": Game.squads,
		"gold": Game.gold, "day": Game.day, "location": Game.location, "rng": Game.rng.state,
		"unit_next": Unit._next_uid, "item_next": Item._next_uid}
	readers_and_initial_gate(); commands_and_stale_reviews(); household_authority(); company_contact_and_physical_death(); native_age_and_death(); save_and_history()
	Game.world = original["world"]; Game.company = original["company"]; Game.squads = original["squads"]
	Game.gold = int(original["gold"]); Game.day = float(original["day"]); Game.location = str(original["location"])
	Game.rng.state = int(original["rng"]); Unit._next_uid = int(original["unit_next"]); Item._next_uid = int(original["item_next"])
	native = null
	print("Dragon bond v021: ", checks, " checks, ", fails, " failures")
	return fails
