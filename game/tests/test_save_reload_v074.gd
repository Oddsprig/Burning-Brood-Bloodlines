extends RefCounted
## v0.074 save-and-reload check (build_strategy: whole-world round trip, zero drift).
## A multi-day DevTools world (troll and giant families, horses and a bought mount, a supply order, an earned bond
## and a bond approach in progress, prisoners both ways, dragons) is saved, loaded and saved again.
##
## Two phases, two processes (the second load is a real fresh instance):
##   godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_save_reload_v074.gd --phase=write --watchdog=180
##   godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_save_reload_v074.gd --phase=check --watchdog=180
## Without --phase both run in one process (the second load is then in-process only).
##
## write: builds the world, saves A, checks the in-process round trip three ways, runs one more day on the LIVE
##        world and saves L (what the game would be had it never been reloaded).
## check: loads A in a fresh process, saves B (B must equal A), runs the same day and saves R (R must equal L),
##        then loads A again in the same process, runs the day and saves R2 (control: R2 must equal R).
##
## Comparisons:
##   value   both files parsed by the same JSON reader, every key, array slot and number exactly equal (key order
##           ignored). This is the zero-drift assertion.
##   strict  in process: the live snapshot against the snapshot after load. Leaf types must match (an int that comes
##           back as a float, an int key that comes back as a string, a packed array that comes back as a plain array,
##           a Color that comes back as text). Floats may differ only by the JSON writer's rounding (relative 1e-9);
##           how many floats were rounded is printed, not asserted.
##   shared  the number of Unit/Item references the save writer saw more than once (one person reachable from two
##           places) must be the same after load: a reload must not split one person into two.
## Each drift kind is printed once per path pattern (array slots as #, ids with digits as *) with its first example.
## A self-check first confirms the comparer reports a planted change (a harness that cannot fail proves nothing).

const PATH_A := "user://save_reload_v074_a.json"
const PATH_L := "user://save_reload_v074_live_day.json"
const PATH_B := "user://save_reload_v074_b.json"
const PATH_R := "user://save_reload_v074_reload_day.json"
const PATH_R2 := "user://save_reload_v074_reload_day2.json"
const PATH_WORK := "user://test_save_reload_v074_start.json"
const DAYS := 3

var checks := 0
var fails := 0
var cover := {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL save_reload_v074: ", message)

# ------------------------------------------------------------------ comparison
class Diff extends RefCounted:
	const FLOAT_REL_TOL := 1e-9   # the JSON writer keeps 14-15 significant digits
	const SHOW_MAX := 60
	var strict := false
	var count := 0
	var rounded := 0
	var patterns := {}   # "kind pattern" -> [count, first example]
	var order: Array = []

	func note(kind: String, path: String, a, b) -> void:
		count += 1
		var key := kind + "  " + pattern(path)
		if not patterns.has(key):
			patterns[key] = [0, "%s: %s -> %s" % [path, show(a), show(b)]]
			order.append(key)
		patterns[key][0] += 1

	static func pattern(path: String) -> String:
		var parts := path.split("/")
		var out := PackedStringArray()
		for p in parts:
			var head := p
			var tail := ""
			var at := p.find("[")
			if at >= 0:
				head = p.substr(0, at)
				tail = "[#]"
			var digit := false
			for c in head:
				if c >= "0" and c <= "9":
					digit = true
					break
			out.append(("*" if digit else head) + tail)
		return "/".join(out)

	static func show(v) -> String:
		match typeof(v):
			TYPE_NIL: return "(missing)"
			TYPE_FLOAT: return "%s float" % String.num(v, 17)
			TYPE_INT: return "%d int" % v
			TYPE_STRING: return "\"%s\"" % (v as String).left(40)
			TYPE_DICTIONARY: return "{%d keys}" % (v as Dictionary).size()
			TYPE_ARRAY: return "[%d]" % (v as Array).size()
		return "%s %s" % [type_string(typeof(v)), str(v).left(40)]

	static func is_list(t: int) -> bool:
		return t == TYPE_ARRAY or (t >= TYPE_PACKED_BYTE_ARRAY and t <= TYPE_PACKED_VECTOR4_ARRAY)

	static func is_text(t: int) -> bool:
		return t == TYPE_STRING or t == TYPE_STRING_NAME

	func walk(a, b, path: String, typed: bool) -> void:
		var ta := typeof(a)
		var tb := typeof(b)
		if ta == TYPE_DICTIONARY and tb == TYPE_DICTIONARY:
			var da: Dictionary = a
			var db: Dictionary = b
			var left := {}
			for k in db:
				left[str(k)] = k
			for k in da:
				var sk := str(k)
				if not left.has(sk):
					note("lost-key", path + "/" + sk, da[k], null)
					continue
				var kb = left[sk]
				left.erase(sk)
				if typed and typeof(k) != typeof(kb) and not (is_text(typeof(k)) and is_text(typeof(kb))):
					note("key-type %s->%s" % [type_string(typeof(k)), type_string(typeof(kb))], path + "/" + sk, k, kb)
				walk(da[k], db[kb], path + "/" + sk, typed)
			for sk in left:
				note("added-key", path + "/" + sk, null, db[left[sk]])
			return
		if is_list(ta) and is_list(tb):
			var sub := typed
			if typed and ta != tb:
				note("container %s->%s" % [type_string(ta), type_string(tb)], path, a, b)
				sub = false   # the container changed kind; compare its values only
			if a.size() != b.size():
				note("size", path, a.size(), b.size())
			for i in mini(a.size(), b.size()):
				walk(a[i], b[i], "%s[%d]" % [path, i], sub)
			return
		var na := ta == TYPE_INT or ta == TYPE_FLOAT
		var nb := tb == TYPE_INT or tb == TYPE_FLOAT
		if na and nb:
			if typed and ta != tb:
				note("num %s->%s" % [type_string(ta), type_string(tb)], path, a, b)
			var fa := float(a)
			var fb := float(b)
			if fa == fb: return
			if typed and absf(fa - fb) <= FLOAT_REL_TOL * maxf(1.0, absf(fa)):
				rounded += 1   # the JSON writer's 14-15 significant digits, not drift
				return
			note("value", path, a, b)
			return
		if is_text(ta) and is_text(tb):
			if str(a) != str(b): note("value", path, a, b)
			return
		if ta != tb:
			note("type %s->%s" % [type_string(ta), type_string(tb)], path, a, b)
			return
		if a != b:
			note("value", path, a, b)

	func report(title: String) -> void:
		print("%s: %d difference(s) in %d pattern(s)%s" % [title, count, order.size(),
			(", %d float(s) rounded by the writer" % rounded) if strict else ""])
		var shown := 0
		for key in order:
			if shown >= SHOW_MAX:
				print("  ... %d more pattern(s)" % (order.size() - shown))
				break
			print("  %6d x %s\n           e.g. %s" % [patterns[key][0], key, patterns[key][1]])
			shown += 1

static func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

## Value comparison of two save files through the same reader. Returns the Diff (count 0 = no drift).
func compare_files(title: String, path_a: String, path_b: String) -> Diff:
	var d := Diff.new()
	var pa = JSON.parse_string(_text(path_a))
	var pb = JSON.parse_string(_text(path_b))
	if pa == null or pb == null:
		d.note("unreadable", path_a if pa == null else path_b, null, null)
		d.report(title)
		return d
	# Fast path: the same canonical text means the same tree.
	if JSON.stringify(pa, "", true) == JSON.stringify(pb, "", true):
		print("%s: identical (%d bytes / %d bytes)" % [title, _text(path_a).length(), _text(path_b).length()])
		return d
	d.walk(pa, pb, "", false)
	if d.count == 0: d.note("text-only", "", null, null)   # canonical texts differed but no value did
	d.report(title)
	return d

## A detached plain snapshot of the live game and the shared-reference count its writer saw.
func snapshot() -> Dictionary:
	var s := SaveSnapshot.new()
	s.begin(Game)
	s.step(0)
	var shared := s.reused_records
	var units := s.unit_records
	var items := s.item_records
	return {"tree": s.take(), "shared": shared, "units": units, "items": items}

func save_to(path: String) -> void:
	Game.wait_save()
	Game.SAVE_PATH = path
	Game.save_game()
	Game.wait_save()

## A reload as the game does it from the menu: nothing of the old world is kept in Game.
func load_from(path: String) -> bool:
	Game.wait_save()
	Game.world = {}
	Game.contract = {}
	Game.company = []
	Game.stash = []
	Game.rep = {}
	Game.pending_battle = {}
	Game.SAVE_PATH = path
	return Game.load_game()

func one_day() -> void:
	DevTools.run_days(Game, 1)

# ------------------------------------------------------------------ the self-check
func self_check() -> void:
	var a := {"n": 3, "f": 1.5, "s": "x", "l": [1, 2, {"k": true}], "d": {"7": 2}}
	var b: Dictionary = a.duplicate(true)
	var same := Diff.new()
	same.strict = true
	same.walk(a, b, "", true)
	check(same.count == 0, "self-check: identical trees report no difference (%d)" % same.count)
	b["l"][2]["k"] = false
	b["n"] = 3.0
	b["d"] = {7: 2}
	b.erase("s")
	b["new"] = 1
	var planted := Diff.new()
	planted.strict = true
	planted.walk(a, b, "", true)
	check(planted.count == 5, "self-check: the comparer finds 5 planted changes (found %d)" % planted.count)
	var rounding := Diff.new()
	rounding.strict = true
	rounding.walk({"x": 0.1 + 0.2}, {"x": 0.3}, "", true)
	check(rounding.count == 0 and rounding.rounded == 1, "self-check: writer rounding is counted, not drift")
	var loose := Diff.new()
	loose.walk({"x": 0.1 + 0.2}, {"x": 0.3}, "", false)
	check(loose.count == 1, "self-check: value mode is exact (0.1+0.2 vs 0.3 is a difference)")
	check(Diff.pattern("/towns/t12/econ/fams[3]/purse") == "/towns/*/econ/fams[#]/purse", "self-check: path pattern")

# ------------------------------------------------------------------ the world
func _adults_of(town_id: String, house: String) -> Array:
	var out: Array = []
	var town: Dictionary = Game.world["towns"].get(town_id, {})
	for family in town.get("econ", {}).get("fams", []):
		if str(family.get("household_uid", "")) != house: continue
		for person in family.get("pp", []):
			var uid := str(Persons.g(person, Persons.PERSON_UID, ""))
			var who: Dictionary = Dragons._person(Game, uid)
			if who.is_empty(): continue
			if str(who.get("town_id", "")) != town_id: continue
			if str(who.get("state", "")) not in ["", "hire", "reserve"]: continue
			if int(who.get("age", -1)) < int(People.ages(str(who.get("race", "human")))["adult"]): continue
			out.append(uid)
	out.sort()
	return out

func _dragons_of(town_id: String, house: String) -> Array:
	var out: Array = []
	var records: Dictionary = Game.world.get("dragons", {}).get("records", {})
	for uid in records:
		var row: Dictionary = records[uid]
		if str(row.get("owner_household_uid", "")) != house: continue
		if str(row.get("location_town_id", "")) != town_id: continue
		if str(row.get("stage", "")) != "adult" or not bool(row.get("alive", false)): continue
		if str(row.get("rider_person_uid", "")) != "": continue
		out.append(str(uid))
	out.sort()
	return out

## A ruling house with two adult dragons and two adults at home (earned bonds need both).
func _choose_house() -> Dictionary:
	var records: Dictionary = Game.world.get("dragons", {}).get("records", {})
	var tried := {}
	for uid in records:
		var row: Dictionary = records[uid]
		if str(row.get("stage", "")) != "adult" or not bool(row.get("alive", false)): continue
		var town_id := str(row.get("location_town_id", ""))
		var house := str(row.get("owner_household_uid", ""))
		if house == "" or tried.has(house + "|" + town_id): continue
		tried[house + "|" + town_id] = true
		if not bool(HouseOnboarding.preview(Game, town_id, house).get("ok", false)): continue
		var dragons := _dragons_of(town_id, house)
		var adults := _adults_of(town_id, house)
		if dragons.size() < 2 or adults.size() < 2: continue
		return {"tid": town_id, "house": house, "dragons": dragons, "adults": adults}
	return {}

func _bond(chosen: Dictionary) -> void:
	var dragons: Array = chosen["dragons"]
	var adults: Array = chosen["adults"]
	# An earned bond: a pair the dragon accepts, bound through the native bind.
	var bonded := false
	for dragon_uid in dragons:
		if bonded: break
		var row: Dictionary = Game.world["dragons"]["records"][dragon_uid]
		for person_uid in adults:
			if not DragonBond.will_accept(row, str(person_uid)): continue
			var preview: Dictionary = DragonBond.bind_preview(Game, str(dragon_uid), str(person_uid), true)
			if not bool(preview.get("ok", false)): continue
			var done: Dictionary = DragonBond.bind(Game, str(dragon_uid), str(person_uid), preview, true)
			if bool(done.get("ok", false)):
				bonded = true
				cover["bond_rider"] = str(person_uid)
				break
	# A bond in progress: another adult approaching another dragon.
	for dragon_uid in dragons:
		var row: Dictionary = Game.world["dragons"]["records"][dragon_uid]
		if str(row.get("rider_person_uid", "")) != "": continue
		for person_uid in adults:
			if str(person_uid) == str(cover.get("bond_rider", "")): continue
			if bool(DragonBond.approach(Game, str(dragon_uid), str(person_uid)).get("ok", false)):
				cover["approach_dragon"] = str(dragon_uid)
				return

func _supply_order(tid: String) -> void:
	if not SupplyOrders.can_manage(Game, tid):
		cover["supply_reason"] = "player house cannot manage its seat"
		return
	var town: Dictionary = Game.world["towns"][tid]
	var treasury := float(town["econ"]["treasury"])
	var cap := floorf(minf(treasury * 0.25, 4000.0))
	var sources: Array = ["best"]
	for link in town.get("road_links", []):
		sources.push_front(str(link.get("id", "")))
	for source in sources:
		if cap < 1.0: break
		var placed: Dictionary = SupplyOrders.place(Game, tid, "grain", 10, 1000.0, cap, str(source))
		if bool(placed.get("ok", false)):
			cover["supply_order"] = str(placed.get("id", ""))
			return
		cover["supply_reason"] = str(placed.get("reason", ""))

func _mount(tid: String) -> void:
	var town: Dictionary = Game.world["towns"][tid]
	DevTools.offer_horses(town)
	for u in Game.company:
		if u.dead or u.horse != null: continue
		if not bool(Horses.quote(Game, town, u).get("ok", false)): continue
		if bool(Horses.buy(Game, town, u).get("ok", false)):
			cover["mount_rider"] = u.uid
			return
	cover["mount_reason"] = "no soldier could buy a mount (offered %d, purse %d)" % [Horses.offered(town["econ"]), Game.gold]

## Prisoners both ways through the battle's own capture step.
func _prisoners(tid: String) -> void:
	var player_faction := str(Game.world["towns"][tid].get("faction", ""))
	var band_id := ""
	var enemy: Unit = null
	for wid in Game.world.get("warbands", {}):
		var wb: Dictionary = Game.world["warbands"][wid]
		if str(wb.get("faction", "")) == player_faction or not Army.is_people_band(wb): continue
		if str(wb.get("kind", "")) in ["militia", "guard", "town", "caravan"]: continue
		for u in wb.get("units", []):
			if u is Unit and not u.dead and not DragonCombat.is_dragon_unit(Game, u):
				band_id = str(wid)
				enemy = u
				break
		if enemy != null: break
	var ours: Unit = null
	for u in Game.company:
		if not u.dead and u.uid != int(cover.get("mount_rider", -1)):
			ours = u
			break
	if enemy == null or ours == null:
		cover["prisoner_reason"] = "no field band (%s) or no soldier (%s)" % [str(enemy != null), str(ours != null)]
		return
	Game.pending_battle = {"warband_id": band_id}
	BattleRounds._take_prisoners(Game, {"captives": [[ours], [enemy]]})
	Game.pending_battle = {}

func _count(tree: Dictionary) -> Dictionary:
	var w: Dictionary = tree.get("world", {})
	var c := {"troll_fams": 0, "giant_fams": 0, "horse_herds": 0, "mounts": 0, "supply_orders": 0, "bonded": 0,
		"approaches": 0, "dragons": 0, "eggs": 0, "prisoners": (w.get("prisoners", []) as Array).size(),
		"captives": (w.get("captives", []) as Array).size(), "company": (tree.get("company", []) as Array).size()}
	for town: Dictionary in w.get("towns", {}).values():
		var e: Dictionary = town.get("econ", {})
		for f in e.get("fams", []):
			if f.get("gone", false): continue
			if str(f.get("race", "")) == "troll": c["troll_fams"] += 1
			if str(f.get("race", "")) == "giant": c["giant_fams"] += 1
		for h in e.get("hd", {}).get("h", {}).values():
			if str(h.get("k", "")) == "horses": c["horse_herds"] += 1
		c["supply_orders"] += (e.get("supply_orders", []) as Array).size()
	for u in tree.get("company", []):
		if u.has("horse"): c["mounts"] += 1
	for row: Dictionary in w.get("dragons", {}).get("records", {}).values():
		if not bool(row.get("alive", false)): continue
		c["dragons"] += 1
		if str(row.get("stage", "")) == "egg": c["eggs"] += 1
		if str(row.get("rider_person_uid", "")) != "": c["bonded"] += 1
		if row.get("approach", null) is Dictionary and str(row["approach"].get("person_uid", "")) != "": c["approaches"] += 1
	return c

func build(tree: SceneTree) -> bool:
	if not await DevTools.start_world(tree, PATH_WORK):
		check(false, "the DevTools start world loads")
		return false
	var chosen := _choose_house()
	check(not chosen.is_empty(), "a ruling house has two adult dragons and two adults at home")
	if chosen.is_empty(): return false
	var began: Dictionary = HouseOnboarding.begin(Game, str(chosen["tid"]), str(chosen["house"]))
	check(bool(began.get("ok", false)), "the house can be chosen: " + str(began.get("reason", "")))
	if not bool(began.get("ok", false)): return false
	var tid := str(chosen["tid"])
	_bond(chosen)
	check(DevTools.raise_army(Game, tid, 8) > 0, "the house raises an army of its own residents")
	_mount(tid)
	_supply_order(tid)
	_prisoners(tid)
	# An egg about to hatch, so the days change a dragon's stage as well.
	for uid in Game.world.get("dragons", {}).get("records", {}):
		if DevTools.egg_almost_hatched(Game, str(uid)):
			cover["hatching_egg"] = str(uid)
			break
	DevTools.run_days(Game, DAYS)
	return true

# ------------------------------------------------------------------ phases
func phase_write(tree: SceneTree) -> bool:
	if not await build(tree): return false
	var live := snapshot()
	var c := _count(live["tree"])
	print("save_reload_v074 world on day %.2f: %s" % [Game.day, JSON.stringify(c)])
	print("  set up: %s" % JSON.stringify(cover))
	check(int(c["troll_fams"]) > 0 and int(c["giant_fams"]) > 0, "the world has troll and giant families (a start-world fixture made before v0.071 lacks them)")
	check(int(c["horse_herds"]) > 0, "the world has town horse herds")
	check(int(c["mounts"]) > 0, "a soldier rides a bought horse: " + str(cover.get("mount_reason", "")))
	check(int(c["supply_orders"]) > 0, "a supply order is open: " + str(cover.get("supply_reason", "")))
	check(int(c["bonded"]) > 0, "an earned rider bond exists")
	check(int(c["approaches"]) > 0, "a bond approach is in progress")
	check(int(c["prisoners"]) > 0 and int(c["captives"]) > 0, "prisoners are held both ways: " + str(cover.get("prisoner_reason", "")))
	check(int(c["dragons"]) > 0 and int(c["company"]) > 0, "dragons and an army exist")
	save_to(PATH_A)
	check(_text(PATH_A).length() > 0, "save A was written")
	# The game as it goes on when never reloaded: one more day on the live world, saved as L.
	one_day()
	save_to(PATH_L)
	# The in-process round trip of A, compared three ways.
	if not load_from(PATH_A):
		check(false, "save A loads")
		return false
	var loaded := snapshot()
	var strict := Diff.new()
	strict.strict = true
	strict.walk(live["tree"], loaded["tree"], "", true)
	strict.report("strict: live snapshot vs snapshot after load (types; values beyond writer rounding)")
	for key in strict.order:
		check(false, "strict drift %d x %s  e.g. %s" % [strict.patterns[key][0], key, strict.patterns[key][1]])
	print("shared references: live %d, after load %d (units %d/%d, items %d/%d)" % [live["shared"], loaded["shared"],
		live["units"], loaded["units"], live["items"], loaded["items"]])
	check(int(live["shared"]) == int(loaded["shared"]), "one Unit/Item referenced from two places stays one after load (live %d, loaded %d)" % [live["shared"], loaded["shared"]])
	check(int(live["units"]) == int(loaded["units"]) and int(live["items"]) == int(loaded["items"]), "the same number of distinct units and items after load")
	live = {}
	loaded = {}
	save_to(PATH_B)
	var same := compare_files("in-process: save A vs save after load (B)", PATH_A, PATH_B)
	for key in same.order:
		check(false, "in-process round trip drift %d x %s  e.g. %s" % [same.patterns[key][0], key, same.patterns[key][1]])
	return true

func phase_check() -> void:
	check(FileAccess.file_exists(PATH_A) and FileAccess.file_exists(PATH_L), "the write phase left saves A and L")
	if not FileAccess.file_exists(PATH_A): return
	if not load_from(PATH_A):
		check(false, "save A loads in a fresh instance")
		return
	save_to(PATH_B)
	var round := compare_files("fresh instance: save A vs save after load", PATH_A, PATH_B)
	for key in round.order:
		check(false, "fresh-instance round trip drift %d x %s  e.g. %s" % [round.patterns[key][0], key, round.patterns[key][1]])
	one_day()
	save_to(PATH_R)
	var parity := compare_files("one more day: never reloaded (L) vs reloaded (R)", PATH_L, PATH_R)
	for key in parity.order:
		check(false, "reload changes the next day %d x %s  e.g. %s" % [parity.patterns[key][0], key, parity.patterns[key][1]])
	# Control: the same reloaded day twice must agree (otherwise the day itself is not repeatable).
	if not load_from(PATH_A):
		check(false, "save A loads a second time")
		return
	one_day()
	save_to(PATH_R2)
	var control := compare_files("control: reloaded day twice (R vs R2)", PATH_R, PATH_R2)
	check(control.count == 0, "control: the same reloaded day is repeatable (if this fails, the parity check above is not about saving)")

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	var phase := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="): phase = a.substr(8)
	self_check()
	if phase == "" or phase == "write":
		await phase_write(tree)
	if phase == "" or phase == "check":
		phase_check()
	print("save_reload_v074%s: %d checks, %d fails, %.1f s" % [(" " + phase) if phase != "" else "", checks, fails,
		float(Time.get_ticks_msec() - started) / 1000.0])
	return fails
