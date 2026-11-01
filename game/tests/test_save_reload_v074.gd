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
##   value   both files parsed by the same JSON reader, every key, array slot and number equal (key order ignored).
##           This is the zero-drift assertion. r5: Godot's JSON number reader is not correctly rounded (a float
##           written in full can come back one unit in its last place off; the strict report prints examples), so a
##           float within ROUND_TRIP_TOL (two units in the last place) of the other is counted, not asserted, in the
##           round trips; the one-more-day parity allows PARITY_TOL for what those last bits move in a day; the
##           control (the same file loaded twice) is exact.
##   strict  in process: the live snapshot against the snapshot after load. Leaf types must match (an int key that
##           comes back as a string, a packed array that comes back as a plain array, a Color that comes back as text,
##           a fraction cut to an int). Floats may differ only by the JSON reader's last-unit error (ROUND_TRIP_TOL);
##           how many were is printed, not asserted. A whole number that comes back as the other number type
##           (JSON has one number type) is counted and its patterns listed, not asserted: the next-day parity check is what shows a type change that
##           changes the game.
##   shared  the number of Unit/Item references the save writer saw more than once (one person reachable from two
##           places) must be the same after load: a reload must not split one person into two.
## Each drift kind is printed once per path pattern (array slots as #, ids with digits as *) with its first example.
## A self-check first confirms the comparer reports a planted change (a harness that cannot fail proves nothing).
## r5 diagnostics (printed, never asserted): every `static var` of the loaded game scripts is fingerprinted before
## the live day (write) and before each reloaded day (check); process state outside the save shows up there.

const PATH_A := "user://save_reload_v074_a.json"
const PATH_L := "user://save_reload_v074_live_day.json"
const PATH_B := "user://save_reload_v074_b.json"
const PATH_R := "user://save_reload_v074_reload_day.json"
const PATH_R2 := "user://save_reload_v074_reload_day2.json"
const PATH_WORK := "user://test_save_reload_v074_start.json"
const PATH_STATICS_L := "user://save_reload_v074_statics_live.json"
const DAYS := 3
const ROUND_TRIP_TOL := 4.5e-16   # two units in the last place: the JSON reader's error on one float
const PARITY_TOL := 1e-9          # one day on from those last bits

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
	const FLOAT_REL_TOL := 4.5e-16   # strict mode: the JSON reader's last-unit error (r4 allowed 1e-9)
	const SHOW_MAX := 60
	var strict := false
	var tol_rel := 0.0   # value mode: floats this close (relative) are counted as noise, not drift
	var count := 0
	var rounded := 0
	var rounded_examples: Array = []   # [path, live, loaded] (the first few, for the codec probe in report)
	var noise := 0
	var numtype := 0   # whole numbers that came back as the other number type (JSON has one number type)
	var numtype_patterns := {}   # pattern -> [count, first example] (printed, not asserted)
	var numtype_order: Array = []
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
			TYPE_FLOAT: return "%s float" % JSON.stringify(v, "", false, true)   # the writer's full digits
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
			var fa := float(a)
			var fb := float(b)
			if typed and ta != tb:
				if fa == fb and fa == floorf(fa):
					# v0.074 r3: a whole number back as the other number type. JSON keeps one number type, and GDScript
					# reckons and compares 4 and 4.0 alike; the load code turns back the ones used as ids, keys or
					# indices. Counted and listed, not asserted: the next-day parity check is what shows a type that
					# changes the game.
					numtype += 1
					var pk := "%s->%s  %s" % [type_string(ta), type_string(tb), pattern(path)]
					if not numtype_patterns.has(pk):
						numtype_patterns[pk] = [0, "%s: %s -> %s" % [path, show(a), show(b)]]
						numtype_order.append(pk)
					numtype_patterns[pk][0] += 1
					return
				note("num %s->%s" % [type_string(ta), type_string(tb)], path, a, b)
			if fa == fb: return
			# (and 1e-18 absolute: the writer keeps a fixed number of decimals, so a float near zero keeps fewer digits)
			var near := absf(fa - fb)
			if typed and (near <= FLOAT_REL_TOL * maxf(absf(fa), absf(fb)) or near <= 1e-18):
				rounded += 1   # the JSON reader's last-unit error, not drift
				if rounded_examples.size() < 4: rounded_examples.append([path, fa, fb])
				return
			if not typed and tol_rel > 0.0 and (near <= tol_rel * maxf(absf(fa), absf(fb)) or near <= 1e-18):
				noise += 1
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
		print("%s: %d difference(s) in %d pattern(s)%s%s" % [title, count, order.size(),
			(", %d float(s) within the JSON reader's last-unit error, %d whole number(s) back as the other number type in %d pattern(s) (not asserted)" \
				% [rounded, numtype, numtype_order.size()]) if strict else "",
			(", %d float(s) within %s relative (not asserted)" % [noise, String.num_scientific(tol_rel)]) if tol_rel > 0.0 else ""])
		if strict:
			# Codec probe: the same float through Godot's own writer and reader, nothing of the game in between.
			for ex in rounded_examples:
				var text := JSON.stringify(ex[1], "", false, true)
				var back: Variant = JSON.parse_string(text)
				print("  codec probe %s: live %s -> loaded %s; the live float written alone reads back %s (%s)" % [ex[0],
					text, JSON.stringify(ex[2], "", false, true), JSON.stringify(back, "", false, true),
					"same" if typeof(back) == TYPE_FLOAT and float(back) == float(ex[1]) else "NOT the same: the reader"])
				if absf(float(ex[1])) < 0.1:   # v0.074 r6: the save writes floats below 0.1 through Game.float_text
					var own := Game.float_text(float(ex[1]))
					var own_back: Variant = JSON.parse_string(own)
					print("    save text %s reads back %s (%s)" % [own, JSON.stringify(own_back, "", false, true),
						"same" if typeof(own_back) == TYPE_FLOAT and float(own_back) == float(ex[1]) else "NOT the same"])
		var shown := 0
		for key in order:
			if shown >= SHOW_MAX:
				print("  ... %d more pattern(s)" % (order.size() - shown))
				break
			print("  %6d x %s\n           e.g. %s" % [patterns[key][0], key, patterns[key][1]])
			shown += 1
		if strict and not numtype_order.is_empty():
			print("  number type only (first %d of %d patterns):" % [mini(12, numtype_order.size()), numtype_order.size()])
			for i in mini(12, numtype_order.size()):
				var pk: String = numtype_order[i]
				print("  %6d x %s\n           e.g. %s" % [numtype_patterns[pk][0], pk, numtype_patterns[pk][1]])

static func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

## Value comparison of two save files through the same reader. Returns the Diff (count 0 = no drift). Floats within
## tol_rel of each other (relative) are counted as noise, not drift (0: exact).
func compare_files(title: String, path_a: String, path_b: String, tol_rel: float = 0.0) -> Diff:
	var d := Diff.new()
	d.tol_rel = tol_rel
	var pa = JSON.parse_string(_text(path_a))
	var pb = JSON.parse_string(_text(path_b))
	if pa == null or pb == null:
		d.note("unreadable", path_a if pa == null else path_b, null, null)
		d.report(title)
		return d
	# Fast path: the same canonical text (every float in full) means the same tree.
	if JSON.stringify(pa, "", true, true) == JSON.stringify(pb, "", true, true):
		print("%s: identical (%d bytes / %d bytes)" % [title, _text(path_a).length(), _text(path_b).length()])
		return d
	d.walk(pa, pb, "", false)
	if d.count == 0 and d.noise == 0: d.note("text-only", "", null, null)   # canonical texts differed but no value did
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
	b["n"] = 4
	b["d"] = {7: 2}
	b.erase("s")
	b["new"] = 1
	var planted := Diff.new()
	planted.strict = true
	planted.walk(a, b, "", true)
	check(planted.count == 5, "self-check: the comparer finds 5 planted changes (found %d)" % planted.count)
	var typing := Diff.new()
	typing.strict = true
	typing.walk({"n": 3, "m": 2.0, "p": 1.5}, {"n": 3.0, "m": 2, "p": 1}, "", true)
	check(typing.count == 2 and typing.numtype == 2, "self-check: a whole number back as the other number type is counted, a changed one is drift (%d drift, %d typing)" % [typing.count, typing.numtype])
	var rounding := Diff.new()
	rounding.strict = true
	rounding.walk({"x": 0.1 + 0.2}, {"x": 0.3}, "", true)
	check(rounding.count == 0 and rounding.rounded == 1, "self-check: the reader's last-unit error is counted, not drift")
	var wider := Diff.new()
	wider.strict = true
	wider.walk({"x": 1.0}, {"x": 1.0 + 1e-12}, "", true)
	check(wider.count == 1 and wider.rounded == 0, "self-check: a float off by more than two units in the last place is drift in strict mode")
	var loose := Diff.new()
	loose.walk({"x": 0.1 + 0.2}, {"x": 0.3}, "", false)
	check(loose.count == 1, "self-check: value mode is exact (0.1+0.2 vs 0.3 is a difference)")
	var tolerant := Diff.new()
	tolerant.tol_rel = ROUND_TRIP_TOL
	tolerant.walk({"x": 0.1 + 0.2, "y": 1.0, "n": 2}, {"x": 0.3, "y": 1.000001, "n": 3}, "", false)
	check(tolerant.count == 2 and tolerant.noise == 1, "self-check: a tolerance counts last-unit noise and still finds real changes (%d drift, %d noise)" % [tolerant.count, tolerant.noise])
	check(Diff.pattern("/towns/t12/econ/fams[3]/purse") == "/towns/*/econ/fams[#]/purse", "self-check: path pattern")

# ------------------------------------------------------------------ the save text codec (r7)
## Game texts shaped like the save writer's small-float markers (values and keys; numbers 0, -1, out of range; the
## next prefixes too) next to small floats: every text comes back as the same text, every key as the same key, every
## float within one unit in the last place, and the live tree is unchanged by writing it.
func codec_check() -> void:
	var cases := {
		"QC example": {"x": 0.05, "name": "~#f~0"},
		"marker keys": {"~#f~0": 0.02, "~#f~-1": "~#f~-1", "~#f~99": "a", "~#f~-999": 1, "~#f~": "~#f~", "y": 0.004},
		"lists": {"l": ["~#f~1", 0.003, "~#f~0", -0.0071, "~#f~-1"], "n": {"~#f~1": [0.06, "~#f~0"]}},
		"prefix chain": {"a": "~#f~0", "b": "~#f1~0", "c": "~#f2~0", "~#f3~0": "~#f4~", "f": 1.0e-5, "g": 0.09},
		"quotes and odd numbers": {"s": "say \"~#f~0\"", "t": "~#f~00", "u": "~#f~+1", "v": "~#f~0x", "w": 0.0123},
		"float lists": {"p": PackedFloat64Array([0.01, 0.5, 3.0e-9]), "q": "~#f~2", "r": [0.07, "~#f~3"]},
		"no marker texts": {"a": 0.031, "b": [0.2, 0.0005], "c": "plain"},
	}
	for title in cases:
		var tree: Dictionary = cases[title]
		var before: Dictionary = tree.duplicate(true)
		var text := Game.save_text(tree)
		check(tree == before, "codec %s: writing leaves the live tree as it was" % title)
		var back: Variant = JSON.parse_string(text)
		check(back is Dictionary, "codec %s: the text is valid JSON (%s)" % [title, text.left(160)])
		if not (back is Dictionary): continue
		var bad: Array = []
		_codec_same(before, back, title, bad)
		check(bad.is_empty(), "codec %s: every text, key and float comes back (%s) from %s" % [title, "; ".join(PackedStringArray(bad)), text.left(200)])
	# A negative control: the comparer above notices a text turned into a number and a lost key.
	var planted: Array = []
	_codec_same({"name": "~#f~0", "k": 1}, {"name": 0.05, "j": 1}, "planted", planted)
	check(planted.size() == 2, "codec self-check: a text read back as a number and a renamed key are both caught (%d)" % planted.size())

func _codec_same(a: Variant, b: Variant, path: String, bad: Array) -> void:
	if a is Dictionary:
		if not (b is Dictionary):
			bad.append("%s: not a dictionary" % path)
			return
		for k in a:
			if not (b as Dictionary).has(str(k)):
				bad.append("%s: key %s missing" % [path, str(k)])
				continue
			_codec_same(a[k], b[str(k)], path + "/" + str(k), bad)
		if (b as Dictionary).size() != (a as Dictionary).size():
			bad.append("%s: %d keys back for %d" % [path, (b as Dictionary).size(), (a as Dictionary).size()])
	elif a is Array or a is PackedFloat64Array:
		if not (b is Array) or (b as Array).size() != a.size():
			bad.append("%s: list not the same length" % path)
			return
		for i in a.size():
			_codec_same(a[i], b[i], "%s[%d]" % [path, i], bad)
	elif a is String:
		if not (b is String) or b != a:
			bad.append("%s: text %s came back as %s" % [path, a, var_to_str(b)])
	elif a is float or a is int:
		if not (b is float or b is int):
			bad.append("%s: number %s came back as %s" % [path, str(a), var_to_str(b)])
		elif absf(float(a) - float(b)) > absf(float(a)) * 2.3e-16:
			bad.append("%s: %s came back as %s" % [path, var_to_str(a), var_to_str(b)])
	elif a != b:
		bad.append("%s: %s came back as %s" % [path, var_to_str(a), var_to_str(b)])

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

## Grown, healthy horses in the town's herds (DevTools.offer_horses offers only those; it makes no animals).
func _grown_horses(town_id: String) -> int:
	var town: Dictionary = Game.world["towns"].get(town_id, {})
	if not TownEcon.has_econ(town): return 0
	var n := 0
	for h: Dictionary in Herds.herds(town["econ"]).values():
		if str(h["k"]) == "horses" and Herds.sick(h) <= float(Herds.A()["disease_no_sale"]):
			n += maxi(0, int(h["g"]))
	return n

## A ruling house with two adult dragons and two adults at home (earned bonds need both). r3: a house whose town has
## grown horses to sell comes first (the mount check needs one; r2's house town had none: "offered 0").
func _choose_house() -> Dictionary:
	var records: Dictionary = Game.world.get("dragons", {}).get("records", {})
	var tried := {}
	var first := {}
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
		var pick := {"tid": town_id, "house": house, "dragons": dragons, "adults": adults}
		if _grown_horses(town_id) > 0: return pick
		if first.is_empty(): first = pick
	if not first.is_empty(): cover["house_horses"] = "no candidate house town has grown horses"
	return first

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

static func _pos(town: Dictionary) -> Vector2:
	var p: Variant = town.get("pos", Vector2.ZERO)
	return p if p is Vector2 else Vector2.ZERO

## r5: the house town of the start world has no grown horse to sell (r4: "offered 0"), so the army walks to the
## nearest town that has one (DevTools.stand_at, as muster stands it at home), buys there and comes home.
func _mount(tid: String) -> void:
	var home: Dictionary = Game.world["towns"][tid]
	var market := tid
	if _grown_horses(tid) <= 0:
		market = ""
		var best := INF
		var ids: Array = Game.world["towns"].keys()
		ids.sort()
		for other in ids:
			if _grown_horses(str(other)) <= 0: continue
			var d: float = _pos(Game.world["towns"][other]).distance_to(_pos(home))
			if d < best:
				best = d
				market = str(other)
	if market == "":
		cover["mount_reason"] = "no town of the world has a grown healthy horse to sell"
		return
	cover["mount_town"] = market
	DevTools.stand_at(Game, market)
	var town: Dictionary = Game.world["towns"][market]
	DevTools.offer_horses(town)
	var last := ""
	for u in Game.company:
		if u.dead or u.horse != null: continue
		var q: Dictionary = Horses.quote(Game, town, u)
		if not bool(q.get("ok", false)):
			last = str(q.get("reason", ""))
			continue
		if bool(Horses.buy(Game, town, u).get("ok", false)):
			cover["mount_rider"] = u.uid
			break
	if not cover.has("mount_rider"):
		cover["mount_reason"] = "no soldier could buy a mount at %s (offered %d, purse %d, last refusal: %s)" % [market, Horses.offered(town["econ"]), Game.gold, last]
	DevTools.stand_at(Game, tid)

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

# ------------------------------------------------------------------ diagnostics (printed, never asserted)
const STATIC_DIRS := ["res://campaign", "res://core", "res://sim", "res://battle"]

## Every `static var` of the game scripts already loaded in this process (none is loaded here, so taking the print
## does not warm anything), as name -> "fingerprint brief". Objects count by script/class, containers by size and a
## sample of their first entries, packed arrays by size and hash.
func statics_print() -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile("(?m)^static var ([A-Za-z_][A-Za-z0-9_]*)")
	for dir: String in STATIC_DIRS:
		for file: String in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"): continue
			var path := dir + "/" + file
			if not ResourceLoader.has_cached(path): continue
			var script: Script = load(path)
			if script == null: continue
			for m: RegExMatch in re.search_all(FileAccess.get_file_as_string(path)):
				var vname := m.get_string(1)
				var v: Variant = script.get(vname)
				out[file.get_basename() + "." + vname] = _fp(v, 0).md5_text() + " " + _brief(v)
	return out

static func _fp(v: Variant, depth: int) -> String:
	var t := typeof(v)
	if t == TYPE_OBJECT:
		if not is_instance_valid(v): return "null"
		var sc: Variant = (v as Object).get_script()
		return "obj:" + ((sc as Script).resource_path.get_file() if sc is Script else (v as Object).get_class())
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		if depth >= 2: return "{%d}" % d.size()
		var parts := PackedStringArray()
		for k in d:
			if parts.size() >= 48: break
			parts.append(str(k) + "=" + _fp(d[k], depth + 1))
		parts.sort()
		return "{%d:%s}" % [d.size(), ",".join(parts)]
	if t == TYPE_ARRAY:
		var a: Array = v
		if depth >= 2: return "[%d]" % a.size()
		var items := PackedStringArray()
		for i in mini(a.size(), 48):
			items.append(_fp(a[i], depth + 1))
		return "[%d:%s]" % [a.size(), ",".join(items)]
	if t >= TYPE_PACKED_BYTE_ARRAY and t <= TYPE_PACKED_VECTOR4_ARRAY:
		return "packed%d:%d" % [v.size(), hash(v)]
	return var_to_str(v)

static func _brief(v: Variant) -> String:
	var t := typeof(v)
	if t == TYPE_DICTIONARY or t == TYPE_ARRAY or (t >= TYPE_PACKED_BYTE_ARRAY and t <= TYPE_PACKED_VECTOR4_ARRAY):
		return "%s(%d)" % [type_string(t), v.size()]
	if t == TYPE_OBJECT: return "Object"
	return var_to_str(v).left(40)

## Names whose print differs between a and b (printed, at most 40).
func statics_diff(title: String, a: Dictionary, b: Dictionary) -> Array:
	var names: Array = []
	for k in a:
		if str(a[k]) != str(b.get(k, "")):
			names.append(k)
	names.sort()
	print("%s: %d of %d static var(s) differ" % [title, names.size(), a.size()])
	for n in names.slice(0, 40):
		print("    %s: %s -> %s" % [n, str(a[n]).substr(33), str(b.get(n, " (not loaded)")).substr(33)])
	return names

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
	# Process state outside the save as the live day begins (the check phase compares its reloaded days with it).
	var sf := FileAccess.open(PATH_STATICS_L, FileAccess.WRITE)
	if sf != null:
		sf.store_string(JSON.stringify(statics_print()))
		sf.close()
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
	strict.report("strict: live snapshot vs snapshot after load (types; values beyond the reader's last-unit error)")
	for key in strict.order:
		check(false, "strict drift %d x %s  e.g. %s" % [strict.patterns[key][0], key, strict.patterns[key][1]])
	print("shared references: live %d, after load %d (units %d/%d, items %d/%d)" % [live["shared"], loaded["shared"],
		live["units"], loaded["units"], live["items"], loaded["items"]])
	check(int(live["shared"]) == int(loaded["shared"]), "one Unit/Item referenced from two places stays one after load (live %d, loaded %d)" % [live["shared"], loaded["shared"]])
	check(int(live["units"]) == int(loaded["units"]) and int(live["items"]) == int(loaded["items"]), "the same number of distinct units and items after load")
	live = {}
	loaded = {}
	save_to(PATH_B)
	var same := compare_files("in-process: save A vs save after load (B)", PATH_A, PATH_B, ROUND_TRIP_TOL)
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
	var round := compare_files("fresh instance: save A vs save after load", PATH_A, PATH_B, ROUND_TRIP_TOL)
	for key in round.order:
		check(false, "fresh-instance round trip drift %d x %s  e.g. %s" % [round.patterns[key][0], key, round.patterns[key][1]])
	var st_r := statics_print()
	one_day()
	save_to(PATH_R)
	var parity := compare_files("one more day: never reloaded (L) vs reloaded (R)", PATH_L, PATH_R, PARITY_TOL)
	for key in parity.order:
		check(false, "reload changes the next day %d x %s  e.g. %s" % [parity.patterns[key][0], key, parity.patterns[key][1]])
	# Control: the same reloaded day twice must agree (otherwise the day itself is not repeatable).
	if not load_from(PATH_A):
		check(false, "save A loads a second time")
		return
	var st_r2 := statics_print()
	one_day()
	save_to(PATH_R2)
	var control := compare_files("control: reloaded day twice (R vs R2)", PATH_R, PATH_R2)
	check(control.count == 0, "control: the same reloaded day is repeatable (if this fails, the parity check above is not about saving)")
	# Diagnostics: process state outside the save before each day. A static that differs before the first reloaded
	# day (R) from both the live day (L) and the second reloaded day (R2), while L and R2 agree, is a suspect for
	# a day that depends on what this process ran before.
	var st_l: Variant = JSON.parse_string(_text(PATH_STATICS_L))
	var r_r2 := statics_diff("statics before R vs before R2", st_r, st_r2)
	if st_l is Dictionary:
		var r_l := statics_diff("statics before R vs before L (write phase)", st_r, st_l)
		var r2_l := statics_diff("statics before R2 vs before L (write phase)", st_r2, st_l)
		var suspects: Array = []
		for n in r_r2:
			if n in r_l and not (n in r2_l): suspects.append(n)
		print("statics suspects (R differs from L and R2, L = R2): %s" % (", ".join(PackedStringArray(suspects)) if not suspects.is_empty() else "none"))

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	var phase := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="): phase = a.substr(8)
	self_check()
	codec_check()
	if phase == "" or phase == "write":
		await phase_write(tree)
	if phase == "" or phase == "check":
		phase_check()
	print("save_reload_v074%s: %d checks, %d fails, %.1f s" % [(" " + phase) if phase != "" else "", checks, fails,
		float(Time.get_ticks_msec() - started) / 1000.0])
	return fails
