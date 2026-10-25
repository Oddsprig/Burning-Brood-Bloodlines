extends RefCounted
## v0.059: opening a unit's record page (a caravan guard's, a militiaman's) must not touch the household it reads.
## Persons.pp()/kp() used to create an empty "pp"/"kp" list on first touch, which turned an abstract household
## (a cohort, the estate, an older save) into a record household. Record pages read through pp_read/kp_read now.
var checks := 0
var fails := 0
var tree: SceneTree

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL guard record v059: " + why)

func keys_of(e: Dictionary) -> Array:
	var out := []
	for f: Dictionary in e.get("fams", []):
		out.append(f.keys().duplicate())
	return out

func read_everything(e: Dictionary, f: Dictionary, uid: int, full: bool = true) -> void:
	Persons.by_uid(f, uid)
	Persons.by_pid(f, 1)
	Persons.any(f, 1)
	Persons.head_of(f)
	RecPages.remembered(e, f)
	if not full: return
	Persons.household(e, f, 0.0)
	Persons.by_name(e, f, "nobody")
	Persons.by_name_any(e, f, "nobody")

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	await tree.process_frame
	# an abstract household and a record household side by side
	var plain := {"id": 0, "name": "Plain", "cohort": true, "gone": false}
	var rec := {"id": 1, "name": "Rec", "gone": false, "pp": [], "kp": []}
	var e := {"fams": [plain, rec]}
	var before := keys_of(e)
	read_everything(e, plain, 77, false)
	read_everything(e, rec, 77, false)
	check(keys_of(e) == before, "reads leave abstract and record households with the same keys")
	check(not plain.has("pp") and not plain.has("kp"), "a household without records stays without them")
	check(Persons.pp_read(plain).is_empty() and Persons.kp_read(plain).is_empty(), "read views of a bare household are empty")
	check(Persons.pp(plain).is_empty() and plain.has("pp"), "pp() still creates the list for the writers that need it")

	# a real world: every unit in a force, caravan guards included
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "DevTools world loads")
		tree = null
		return fails
	var opened := 0
	var caravan_units := 0
	for wid in Game.world.get("warbands", {}):
		var wb: Dictionary = Game.world["warbands"][wid]
		var kind := String(wb.get("kind", ""))
		for u in wb.get("units", []):
			if not (u is Unit): continue
			var t: Dictionary = RecData.town(u.home_town)
			if t.is_empty(): continue
			var w := RecData.econ(t)
			var fam: Dictionary = People.fam_of(t, u.family)
			if fam.is_empty(): continue
			var k0 := keys_of(w)
			read_everything(w, fam, u.uid)
			opened += 1
			if kind == "caravan": caravan_units += 1
			check(keys_of(w) == k0, "unit %s (%s): reading its household adds no field" % [u.name, kind])
	check(opened > 0, "the world has units with a home household to open")
	print("Guard record v059: %d units opened (%d in caravans), %d checks, %d failures." % [opened, caravan_units, checks, fails])
	tree = null
	return fails
