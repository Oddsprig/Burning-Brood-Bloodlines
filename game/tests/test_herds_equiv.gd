extends RefCounted
## Native frame warmup to days 10-11, with the frozen weekly/dog-buying oracle.
## Run through the existing runner; this test does not register itself.
const DAYS: int = 2
const WALL_USEC: int = 50000000
var _deadline: int = 0
var _failure: String = ""
var _weeks: int = 0
var _slices: int = 0
var _held: int = 0
var _committed_holds: int = 0
var _actions: Array = []
var _save_checked: bool = false
var _fixture_ready: bool = false
var _warmup_ready: bool = false
var _fixture_receipt: Dictionary = {}
var _native_counters: Dictionary = {"native_headers": 0, "herd_records": 0, "animal_heads": 0}
const ARMY_FIXTURE: GDScript = preload("res://tests/test_army_split_equiv.gd")
const CONTRACT_PROBE: GDScript = preload("res://tests/day_job_contract_probe.gd")

func run(tree: SceneTree) -> int:
	_deadline = Time.get_ticks_usec() + WALL_USEC
	Game.wait_save()
	var old_size: String = WorldGen.gen_size
	var old_span: int = CampaignWorld.presim_span_days
	var old_prof_on: bool = TownEcon.prof_on
	var old_processing: bool = Game.is_processing()
	var old_screen: String = String(Game._active_screen)
	var old_paused: bool = tree.paused
	var old_fps: int = Engine.max_fps
	var old_scale: float = Engine.time_scale
	Game.set_process(false)
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	tree.paused = false
	Game._active_screen = "map"
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	TownEcon.prof_on = false
	_phase("generation")
	var fixture: Variant = ARMY_FIXTURE.NativeFixture.new()
	fixture.hard_deadline = _deadline
	fixture._started_us = Time.get_ticks_usec()
	_fixture_ready = await fixture._setup_world(tree)
	WorldGen.gen_size = old_size
	CampaignWorld.presim_span_days = old_span
	_fixture_receipt = fixture._receipt.duplicate(true)
	if not _fixture_ready:
		_failure = fixture._reason if not fixture._reason.is_empty() else "Full frame fixture unavailable."
	Game._active_screen = "map"
	if _ok():
		_phase("warmup")
		_warmup_ready = await fixture._warmup(tree)
		if not _warmup_ready:
			_failure = fixture._reason
	_phase("preparation")
	for offset: int in DAYS:
		if not _ok():
			break
		if offset > 0 and not await fixture.settle(tree):
			_failure = fixture._reason
			break
		Game.advance_time(1.0, false, 0, 1)
		if int(Game.world.get("last_day", -1)) != 10 + offset or not is_equal_approx(Game.day, float(10 + offset)):
			_failure = "Native warmup did not reach the expected day-10/11 herd queue."
			break
		var weeks_before: int = _weeks
		while _ok() and not Game.world.get("work", []).is_empty():
			var head: Array = Game.world["work"][0]
			if head[0] == "herds":
				await _compare_week(tree)
			else:
				var rng: RandomNumberGenerator = CampaignWorld._rng(Game.world)
				CampaignWorld._run_job(Game, rng, false)
				Game.world["rng_state"] = str(rng.state)
		if _ok() and _weeks == weeks_before:
			_failure = "A native day scheduled no herd week."
	if _ok() and (_held == 0 or _weeks < DAYS):
		_failure = "No held continuation or insufficient native-day coverage."
	if _ok():
		_round_trip()
	_phase("cleanup")
	if CampaignWorld.day_job_pending(Game):
		var abandoned: CampaignDayJob = Game.world["work"][0][-1]
		abandoned.after.clear()
		abandoned.release(Game)
		Game.world["work"] = []
	Game._save_pending = false
	Game._autosave_day_pending = false
	Game._day_job_owner = null
	Game._day_job_dispatching = false
	Game._day_job_actions.clear()
	Game._day_job_observers.clear()
	Game._day_job_changed_pending = false
	Game._day_job_slice_frame = -1
	Game._day_job_quit_generation = -1
	Game._active_screen = old_screen
	Game.set_process(old_processing)
	tree.paused = old_paused
	Engine.max_fps = old_fps
	Engine.time_scale = old_scale
	TownEcon.prof_on = old_prof_on
	if not _ok():
		printerr("HERDS EQUIV FAIL: " + _failure)
		return 1
	print("HERDS EQUIV PASS: %d days; %d herd weeks; %d slices; %d held; full ordered state/RNG/save codec exact." % [DAYS, _weeks, _slices, _held])
	return 0

func _phase(_label: String) -> void:
	pass

func _ok() -> bool:
	if _failure == "" and Time.get_ticks_usec() >= _deadline:
		_failure = "50-second internal deadline exceeded; incomplete, not passed."
	return _failure == ""

func _drain_atomic() -> void:
	var rng: RandomNumberGenerator = CampaignWorld._rng(Game.world)
	while _ok() and not Game.world.get("work", []).is_empty():
		CampaignWorld._run_job(Game, rng, false)
		Game.world["rng_state"] = str(rng.state)

func _compare_week(tree: SceneTree) -> void:
	var original: Dictionary = Game.world
	var day_v: float = Game.day
	var midnight: int = int(original["last_day"])
	var world_rng: String = str(original.get("rng_state", ""))
	var game_rng: int = Game.rng.state
	var next_uid: int = Unit._next_uid
	var next_item: int = Item._next_uid
	var gold: float = TownEcon.gold_gone
	var goods: Dictionary = TownEcon.goods_lost.duplicate(true)
	var raids: String = HerdRaids.save_state()
	var tail: PackedByteArray = var_to_bytes(Game._serialize((original["work"] as Array).slice(1)))
	var plain: Dictionary = Game._serialize(original)
	Game.world = Game._deserialize(plain)
	Unit._next_uid = next_uid
	Item._next_uid = next_item
	# Batch all adjacent native herd headers in one full-world fork. This
	# retains their exact order while avoiding a full clone/save per town.
	var native_headers: int = 0
	while not Game.world["work"].is_empty() and Game.world["work"][0][0] == "herds":
		var atomic_header: Array = (Game.world["work"] as Array).pop_front()
		var town: Dictionary = Game.world["towns"][atomic_header[1]]
		var records: Dictionary = town["econ"].get("hd", {}).get("h", {})
		_native_counters["herd_records"] = int(_native_counters["herd_records"]) + records.size()
		for herd: Dictionary in records.values():
			_native_counters["animal_heads"] = int(_native_counters["animal_heads"]) + Herds.head(herd)
		native_headers += 1
		_atomic_week(Game, town, float(atomic_header[2]))
		if not _ok(): return
	_native_counters["native_headers"] = int(_native_counters["native_headers"]) + native_headers
	if Game.world["work"].is_empty() and Game.world.has("feudal"):
		Game.world["work"].append(["ownership_finish"])
	var expected: PackedByteArray = var_to_bytes(Game._serialize(Game.world))
	var expected_native: PackedByteArray = var_to_bytes(Game._save_tree())
	var expected_gold: PackedByteArray = var_to_bytes(TownEcon.gold_gone)
	var expected_goods: PackedByteArray = var_to_bytes(TownEcon.goods_lost)
	var expected_rng: int = Game.rng.state
	var expected_uid: int = Unit._next_uid
	var expected_raids: String = HerdRaids.save_state()
	Game.world = original
	Game.rng.state = game_rng
	TownEcon.gold_gone = gold
	TownEcon.goods_lost = goods
	if not HerdRaids.load_state(Game, raids):
		_failure = "Could not restore reference raid state."
		return
	Unit._next_uid = next_uid
	Item._next_uid = next_item
	_actions.clear()
	var deferred: bool = false
	var probe: Variant = CONTRACT_PROBE.new()
	var held_header: Array = []
	while _ok() and not Game.world["work"].is_empty() and Game.world["work"][0][0] == "herds":
		if not CampaignWorld.day_job_pending(Game):
			_actions.clear()
			held_header = (Game.world["work"][0] as Array).slice(0, 3)
			tail = var_to_bytes(Game._serialize((Game.world["work"] as Array).slice(1)))
			var header: Array = Game.world["work"][0]
			if not header[-1] is CampaignDayJob:
				var worker: CampaignDayJob = CampaignWorld._new_day_job(Game, header)
				header.append(worker)
				worker.hold(Game)
			(header[-1] as CampaignDayJob).after.append(_queue_boundary)
		await tree.process_frame
		if CampaignWorld.day_job_pending(Game):
			Game._process(1.0 / 60.0)
		else:
			CampaignWorld.work_slice(Game, 4000)
		_slices += 1
		if Game.day != day_v or int(Game.world["last_day"]) != midnight or str(Game.world.get("rng_state", "")) != world_rng:
			_failure = "Clock, effect day or campaign RNG advanced during a herd week."
			break
		if CampaignWorld.day_job_pending(Game):
			_held += 1
			if not tree.paused or Game.world["work"][0][2] != held_header[2]:
				_failure = "Herd continuation lost its original day or tree hold."
				break
			if var_to_bytes(Game._serialize((Game.world["work"] as Array).slice(1))) != tail:
				_failure = "Later queued work interleaved with the herd week."
				break
			if not deferred:
				deferred = true
				CampaignWorld.defer_day_job_action(Game, _record.bind("first"))
				CampaignWorld.defer_day_job_action(Game, _record.bind("second"))
				if not _save_checked:
					_save_checked = true
					var saves_started: int = int(Game.save_stats()["started"])
					Game.save_game_async()
					if Game.save_game():
						_failure = "A partial herd-week save reported a completed write."
					Game.wait_save()
					if int(Game.save_stats()["started"]) != saves_started or Game._save_capture != null or not Game._save_pending:
						_failure = "Partial state was captured or the pending save was lost."
			var draw_problem: String = await probe.observe_hold(tree, _deadline)
			if draw_problem != "":
				_failure = draw_problem
				break
			if not _actions.is_empty():
				_failure = "A deferred action observed a partial herd week."
		elif deferred or not Game._day_job_actions.is_empty():
			var committed_problem: String = await probe.finish(tree, _deadline, "async")
			if committed_problem != "":
				_failure = committed_problem
				break
			if deferred and _actions != ["first", "second"]:
				_failure = "Tree release or deferred action order differs."
				break
			if deferred:
				_committed_holds += 1
			deferred = false
			probe = CONTRACT_PROBE.new()
	if not _ok():
		probe.dispose()
		return
	var problem: String = await probe.finish(tree, _deadline, "async")
	if problem != "":
		_failure = problem
		return
	if tree.paused or (deferred and _actions != ["first", "second"]):
		_failure = "Tree release or deferred action order differs."
		return
	if var_to_bytes(Game._serialize(Game.world)) != expected:
		_failure = "Full ordered world state differs from the independent weekly oracle."
		return
	if var_to_bytes(TownEcon.gold_gone) != expected_gold or var_to_bytes(TownEcon.goods_lost) != expected_goods or Game.rng.state != expected_rng or Unit._next_uid != expected_uid or HerdRaids.save_state() != expected_raids:
		_failure = "Global RNG, conservation counters or raid state differs."
		return
	if var_to_bytes(Game._save_tree()) != expected_native:
		_failure = "Complete native save state differs from the independent weekly oracle."
		return
	_weeks += 1

func _record(label: String) -> void:
	_actions.append(label)

func _queue_boundary() -> void:
	pass

func _round_trip() -> void:
	var before: PackedByteArray = var_to_bytes(Game._serialize(Game.world))
	var snapshot: Dictionary = Game._save_tree()
	var encoded: String = Game.save_text(snapshot)
	var parsed: Variant = JSON.parse_string(encoded)
	if not (parsed is Dictionary):
		_failure = "Completed-day save did not encode."
		return
	Game.restore_exact(parsed)
	var loaded: Dictionary = Game._deserialize(parsed["world"])
	if var_to_bytes(Game._serialize(loaded)) != before:
		_failure = "Production save codec changed full ordered world state."

# Independent pre-change policy; production continues to use its native helpers.
func _atomic_week(game: Variant, town: Dictionary, day_v: float) -> void:
	var e: Dictionary = town["econ"]
	if not e.has("hd"):
		Herds.migrate(game.world, town, e)
	var hd: Variant = Herds.H(e)
	var rng: Variant = RandomNumberGenerator.new()
	rng.seed = hash([int(game.world.get("seed", 0)), String(town["id"]), int(day_v), "herds"])
	var si: Variant = Calendar.season_index(day_v)
	var yr: Variant = Calendar.year(day_v)
	if yr != int(hd["y"]):
		hd["ly"] = hd["yr"]
		hd["yr"] = {}
		hd["y"] = yr
	hd.erase("_pg"); hd.erase("_pa")
	LivestockCare.feed_hens(e, day_v)
	DomesticAnimals.feed_dogs(e, day_v)
	Herds._disease(e, rng, day_v)
	Herds._males(e)
	Herds._land_choice(e, Plots.of(town), day_v)
	var P: Variant = Plots.of(town)
	Herds.assign_tiles(e, P) # Returned/bought stock uses its current native pasture allocation.
	var ids: Array = (hd["h"] as Dictionary).keys()
	for hid: Variant in ids:
		var h: Dictionary = hd["h"][hid]
		if h.has("work_band"): continue
		Herds._life(e, h, si, day_v, rng)
	Herds._orphans(e, day_v)
	Herds._feed_all(e, P, si, day_v, rng)
	HerdRaids.plan(game, town, day_v)
	Herds._stockpile(e, si, day_v)
	Herds._repay_loans(e)
	Herds._unsold(e, si, day_v)
	Herds._offers(e, si, day_v)
	_atomic_wants(game, town, e, si, day_v)
	Herds._drovers(game, town, e, day_v)
	Herds._prices(e)
	Herds._products(e, si, day_v)
	LivestockCare.hive_week(e, day_v)
	Herds._manure(e)
	Herds._herder_caps(e)
	# empty records leave the list (their ledgers join the town's gone ledger; the log keeps what happened)
	for hid: Variant in (hd["h"] as Dictionary).keys():
		var h2: Dictionary = hd["h"][hid]
		if Herds.head(h2) <= 0:
			Herds._retire(e, h2)

func _atomic_wants(_game: Variant, _town: Dictionary, e: Dictionary, _si: int, day: float) -> void:
	var hd: Variant = Herds.H(e)
	var wak: Dictionary = hd["wak"]
	var aph: Variant = float(TownEcon.data()["land"]["acres_per_hand"])
	var reserve: Variant = float(Herds.A()["buy_reserve"])
	# These indices live only for this sales pass. References retain herd/offer order
	# and see head counts and offers change immediately as each purchase is made.
	var cattle: Variant = {}
	var oxen: Variant = {}
	for h: Variant in (hd["h"] as Dictionary).values():
		var fid: Variant = int(h["oi"])
		if String(h["ow"]) != ("s" if fid == 0 else "f"):
			continue
		if String(h["k"]) == "cattle":
			if not cattle.has(fid): cattle[fid] = []
			cattle[fid].append(h)
		elif String(h["k"]) == "oxen" and not oxen.has(fid):
			oxen[fid] = h
	var offers: Variant = {}
	for o: Variant in hd["of"]:
		var h: Dictionary = hd["h"].get(str(int(o[0])), {})
		if h.is_empty(): continue
		var k: Variant = String(h["k"])
		var age: Variant = String(o[1])
		if not offers.has(k): offers[k] = {}
		if not offers[k].has(age): offers[k][age] = []
		offers[k][age].append(o)
	for f: Variant in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		var ac: Variant = Families.acres(f)
		if ac <= 0:
			continue
		var short: Variant = int(ceil(float(ac) / aph - DomesticAnimals.draught(e, int(f["id"])))) - maxi(0, int(f.get("ox", 0)))
		if short <= 0:
			continue
		short = mini(short, 2)
		wak["oxen"] = int(wak.get("oxen", 0)) + short
		wak["cattle"] = int(wak.get("cattle", 0)) + short   # grown cattle are trained to the plough too
		# the family's own grown cattle first (trained to the plough: from its herd to its oxen, no coin)
		for own: Variant in cattle.get(int(f["id"]), []):
			while short > 0 and int(own["g"]) >= 2:
				var oxh0: Variant = HerdsMarket._indexed_oxen(e, oxen, int(f["id"]), day)
				if Herds._transfer(e, own, oxh0, "g", 1, "sold", "bought", "to the family's plough", "from the family's own herd", day) <= 0:
					break
				short -= 1
		for src: Variant in ["oxen", "cattle"]:
			if short <= 0:
				break
			var p: Variant = Herds.price(e, src)
			while short > 0 and float(f["purse"]) - p > reserve:
				var o: Variant = HerdsMarket._take_offer(e, src, ["g"], int(f["id"]), -1, offers)
				if o.is_empty():
					break
				var seller: Dictionary = hd["h"][str(int(o[0]))]
				var oxh: Variant = HerdsMarket._indexed_oxen(e, oxen, int(f["id"]), day)
				if Herds._transfer(e, seller, oxh, "g", 1, "sold", "bought", "to the %s for the plough" % Backstory.plural(String(f["name"])),
						"from %s" % Herds.owner_text(e, seller), day) > 0:
					f["purse"] = float(f["purse"]) - p
					Herds._add_coin(e, seller, p)
					hd["sok"][src] = int(hd["sok"].get(src, 0)) + 1
					short -= 1
	# restocking: a herd below half its keep buys grown stock of its kind
	for hid: Variant in (hd["h"] as Dictionary).keys():
		var h: Dictionary = hd["h"][hid]
		var k: Variant = String(h["k"])
		if not Herds.GRAZE.has(k) or String(h["ow"]) == "d" or h.has("work_band"):
			continue
		var need: Variant = int(float(h["t"]) * 0.5) - Herds.head(h)
		if need <= 0:
			continue
		need = mini(need, int(Herds.A()["restock_week"]))
		wak[k] = int(wak.get(k, 0)) + need
		var p2: Variant = Herds.price(e, k)
		while need > 0 and Herds._coin(e, h) - p2 > reserve:
			var o2: Variant = HerdsMarket._take_offer(e, k, ["g"], -1, int(h["id"]), offers)
			if o2.is_empty():
				break
			var s2: Dictionary = hd["h"][str(int(o2[0]))]
			if Herds._transfer(e, s2, h, "g", 1, "sold", "bought", "to %s" % Herds.owner_text(e, h), "from %s" % Herds.owner_text(e, s2), day) > 0:
				Herds._add_coin(e, h, -p2)
				Herds._add_coin(e, s2, p2)
				hd["sok"][k] = int(hd["sok"].get(k, 0)) + 1
				need -= 1
	HerdsMarket._pot_buys(e, day)
	_atomic_buy_dogs(e, day)

func _atomic_buy_dogs(e: Dictionary, day: float) -> void:
	var hd: Variant = Herds.H(e)
	for f: Variant in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		var fid: Variant = int(f["id"])
		var own: Variant = Herds.of_family(e, fid).filter(func(h: Variant) -> bool: return String(h["k"]) == "dogs")
		var have: Variant = 0
		for h: Variant in own: have += Herds.head(h)
		var short: Variant = maxi(0, _atomic_dog_target(e, fid) - have)
		hd["wak"]["dogs"] = int(hd["wak"].get("dogs", 0)) + short
		var price: Variant = Herds.price(e, "dogs")
		while short > 0 and float(f["purse"]) - price > float(Herds.A()["buy_reserve"]):
			var offer: Variant = Herds._take_offer(e, "dogs", ["g", "y"], fid)
			if offer.is_empty(): break
			var seller: Dictionary = hd["h"][str(int(offer[0]))]
			var age: Variant = String(offer[1])
			var paid: Variant = Herds.price(e, "dogs", age)
			var buyer: Variant = Herds.herd_for(e, fid, "dogs", day)
			if Herds._transfer(e, seller, buyer, age, 1, "sold", "bought", "guard dog sold", "guard dog bought", day) <= 0: break
			f["purse"] = float(f["purse"]) - paid
			Herds._add_coin(e, seller, paid)
			hd["sok"]["dogs"] = int(hd["sok"].get("dogs", 0)) + 1
			short -= 1

func _atomic_dog_target(e: Dictionary, fid: int) -> int:
	var stock: Variant = 0
	for h: Variant in Herds.herds(e).values():
		if Herds.GRAZE.has(String(h["k"])) and Herds.grazer(e, h) == fid:
			stock += Herds.head(h)
	return clampi(int(ceil(float(stock) / float(Herds.kind("dogs")["guard_head"]))), 0, 4)
