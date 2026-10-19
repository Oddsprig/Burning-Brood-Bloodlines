extends RefCounted
## Weekly famine trace for the first ~20 weeks of sim year 2.
## Economy-only, same entry points as tests/diag_economy_fast.gd.
## Loads that diag's year-1 checkpoint (ECON_TAG). With no checkpoint, starts
## the world and fast-forwards to the year-2 boundary, then prints each week.
##
##   godot --headless --path . res://tests/runner.tscn -- --test=res://tests/diag_famine_weekly.gd --weeks=20 --watchdog=60

const YEAR_DAYS: int = 120
const WEEK: int = 7

var _sim = null
var _prev: Dictionary = {}


func _arg_int(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return int(arg.substr(prefix.length()))
	return fallback


func _ids() -> Array:
	var ids: Array = Game.world.get("towns", {}).keys()
	ids.sort()
	return ids


func _snap() -> Dictionary:
	var s := {
		"day": int(floor(Game.day)), "year": Calendar.year(Game.day), "season": Calendar.season(Game.day),
		"pop": 0, "worked": 0.0, "land": 0, "need": 0.0, "own": 0, "helpers": 0.0,
		"workers": 0, "cap": 0, "till": 0.0, "owed": 0.0, "field": 0.0,
		"farms": 0, "closed": 0, "broke": 0, "unpaid": 0, "idle": 0, "hungry": 0, "hungry_n": 0,
		"stock_g": 0, "stock_f": 0, "stock_m": 0, "barn_g": 0, "barn_f": 0, "barn_m": 0,
		"granary": 0, "made_g": 0, "made_f": 0, "made_m": 0, "starved": 0, "deaths": 0,
		"food": 0.0, "larders": 0, "food_short": 0.0, "hh_food": 0,
		"fwage": 0.0, "fwn": 0, "twage": 0.0, "dwage": 0.0, "towns": 0, "vacant": 0,
	}
	for key in _ids():
		var town: Dictionary = Game.world["towns"][key]
		if not TownEcon.has_econ(town):
			continue
		var e: Dictionary = town["econ"]
		s["towns"] += 1
		s["dwage"] += float(e.get("dwage", 0.0))
		s["granary"] += int(e.get("granary", 0))
		s["food_short"] += float(e.get("food_short", 0.0))
		var stock: Dictionary = e.get("stock", {})
		var barn: Dictionary = e.get("barn", {})
		s["stock_g"] += int(stock.get("grain", 0))
		s["stock_f"] += int(stock.get("fruit", 0))
		s["stock_m"] += int(stock.get("meat", 0)) + int(stock.get("fresh_meat", 0))
		s["barn_g"] += int(barn.get("grain", 0))
		s["barn_f"] += int(barn.get("fruit", 0))
		s["barn_m"] += int(barn.get("meat", 0)) + int(barn.get("fresh_meat", 0))
		var made: Dictionary = e.get("led", {}).get("made", {})
		s["made_g"] += int(made.get("grain", 0))
		s["made_f"] += int(made.get("fruit", 0))
		s["made_m"] += int(made.get("meat", 0)) + int(made.get("fresh_meat", 0))
		s["starved"] += int(Sickness.book(e).get("starved", 0))
		s["deaths"] += int(e.get("stats", {}).get("deaths", 0))
		s["hh_food"] += int(e.get("hh", {}).get("grain", 0))
		for acres in e.get("wacres", {}).values():
			s["worked"] += float(acres)
		for acres in e.get("land", {}).values():
			s["land"] += int(acres)
		for f in e.get("fams", []):
			if f.get("gone", false) or f.get("estate", false):
				continue
			s["pop"] += Families.people(f)
			s["need"] += Families.need_hands(f, e)
			s["own"] += int(f.get("hands", 0))
			s["helpers"] += Barge.helper_hands(e, f, float(e.get("day", 0)))
			s["idle"] += int(f.get("idle", 0))
			if int(f.get("unpaid", 0)) > 0:
				s["unpaid"] += 1
			var stage := int(f.get("hungry", 0))
			if stage > 0:
				s["hungry"] += stage
				s["hungry_n"] += 1
			s["food"] += float(f.get("store", {}).get("food", 0.0))
			s["larders"] += 1
		for b in e.get("biz", []):
			var typ := String(b.get("type", ""))
			if typ != "farm" and typ != "estate":
				continue
			s["farms"] += 1
			if b.get("closed", false):
				s["closed"] += 1
				continue
			var bw := int(b.get("workers", 0))
			var bc := int(b.get("cap", 0))
			s["workers"] += bw
			s["cap"] += bc
			s["vacant"] += maxi(0, bc - bw)
			s["till"] += float(b.get("till", 0.0))
			s["owed"] += float(b.get("owed", 0.0))
			s["field"] += Families.field_hands(e, b)
			s["fwage"] += float(b.get("wage", 0.0))
			s["fwn"] += 1
			if float(b.get("till", 0.0)) < float(b.get("wage", 0.0)) * 3.0:
				s["broke"] += 1
		for b in e.get("biz", []):
			var typ2 := String(b.get("type", ""))
			if typ2 == "farm" or typ2 == "estate" or b.get("closed", false):
				continue
			s["twage"] = maxf(float(s["twage"]), float(b.get("wage", 0.0)))
	return s


func _line(tag: String, now: Dictionary) -> void:
	var dg := int(now["made_g"]) - int(_prev.get("made_g", now["made_g"]))
	var starved := int(now["starved"]) - int(_prev.get("starved", now["starved"]))
	var dw := float(now["worked"]) - float(_prev.get("worked", now["worked"]))
	var down := float(now["own"]) - float(_prev.get("own", now["own"]))
	var dh := float(now["workers"]) - float(_prev.get("workers", now["workers"]))
	var dneed := float(now["need"]) - float(_prev.get("need", now["need"]))
	var dfield := float(now["field"]) - float(_prev.get("field", now["field"]))
	var link := "steady"
	if _prev.is_empty():
		link = "baseline"
	elif dw < -500.0:
		if dneed > 500.0 and dfield > -50.0 and down > -50.0:
			link = "need_rose"
		elif dh < -20.0 or dfield < -50.0:
			link = "hands_left"
		elif down < -20.0:
			link = "owners_left_fields"
		elif int(now["closed"]) > int(_prev.get("closed", 0)):
			link = "farms_closed"
		elif int(now["broke"]) > int(_prev.get("broke", 0)) + 5 and float(now["owed"]) > float(_prev.get("owed", 0.0)):
			link = "wages_unpaid"
		elif int(now["hungry_n"]) > int(_prev.get("hungry_n", 0)) + 10:
			link = "hunger"
		else:
			link = "worked_fell"
	var food_avg := float(now["food"]) / maxf(1.0, float(now["larders"]))
	var fw := float(now["fwage"]) / maxf(1.0, float(now["fwn"]))
	var daywage := float(now["dwage"]) / maxf(1.0, float(now["towns"]))
	# stderr is unbuffered, so a watchdog kill still leaves the weeks already finished.
	printerr("FAMINE wk day=%d cal=%s y%d pop=%d starved_wk=%d worked=%.0f dworked=%.0f land=%d need=%.0f own=%d helpers=%.0f hired=%d cap=%d vacant=%d field=%.0f farms=%d closed=%d broke=%d till=%.0f owed=%.0f unpaid=%d idle=%d hungry_n=%d hungry_sum=%d food_avg=%.2f fwage=%.2f dwage=%.2f twage_max=%.2f mkt_g=%d barn_g=%d granary=%d hh_g=%d made_g_wk=%d stock_ffm=%d/%d/%d barn_ffm=%d/%d/%d short=%.2f link=%s down=%d dhired=%d dneed=%.0f dfield=%.0f" % [
		now["day"], now["season"], now["year"], now["pop"], starved, now["worked"], dw, now["land"],
		now["need"], now["own"], now["helpers"], now["workers"], now["cap"], now["vacant"], now["field"],
		now["farms"], now["closed"], now["broke"], now["till"], now["owed"], now["unpaid"], now["idle"],
		now["hungry_n"], now["hungry"], food_avg, fw, daywage, now["twage"], now["stock_g"], now["barn_g"], now["granary"], now["hh_food"], dg,
		now["stock_g"], now["stock_f"], now["stock_m"], now["barn_g"], now["barn_f"], now["barn_m"],
		now["food_short"], link, int(down), int(dh), dneed, dfield])
	if tag != "":
		printerr("FAMINE note " + tag)
	_prev = now


func _ck_path() -> String:
	return "%s/famine_week.save" % _sim.ROOT


func _save_ck(day: int) -> void:
	DirAccess.make_dir_recursive_absolute(_sim.ROOT)
	Game._save_ready = true
	Game._save_pending = false
	Game.SAVE_PATH = _ck_path()
	Game.save_game()
	Game.wait_save()
	printerr("FAMINE checkpoint day=%d ok=%s path=%s" % [day, str(bool(Game.save_stats().get("last_ok", false))), Game.SAVE_PATH])


func _forward_to(tree: SceneTree, target: int) -> int:
	var day := int(floor(Game.day))
	var started := Time.get_ticks_msec()
	while day < target:
		if Time.get_ticks_msec() - started > 50000:
			print("FAMINE note forward_stopped day=%d target=%d" % [day, target])
			break
		var span := mini(WEEK, target - day)
		_sim._coarse(day, day + span)
		day += span
		await tree.process_frame
	return day


func run(tree: SceneTree) -> int:
	var weeks := maxi(1, _arg_int("--weeks=", 20))
	var steps := maxi(1, _arg_int("--steps=", 1))
	var t0 := Time.get_ticks_msec()
	_sim = load("res://tests/diag_economy_fast.gd").new()
	await tree.process_frame
	Game.wait_save()
	var old_path: String = Game.SAVE_PATH
	Game.settings["guide_seen"] = true
	var load_path := _ck_path() if FileAccess.file_exists(_ck_path()) else ""
	if load_path != "":
		Game.SAVE_PATH = load_path
		if not Game.load_game():
			printerr("FAMINE note load_failed path=%s" % load_path)
			Game.SAVE_PATH = old_path
			return 0
		var saved: Dictionary = Game.world.get("_famine_wk", {})
		_prev = (saved.get("prev", {}) as Dictionary).duplicate(true)
		printerr("FAMINE loaded path=%s day=%d" % [load_path, int(floor(Game.day))])
	else:
		printerr("FAMINE note no_checkpoint root=%s starting_world" % _sim.ROOT)
		if not await DevTools.start_world(tree, "user://diag_famine_weekly.json"):
			printerr("FAMINE note start_failed")
			Game.SAVE_PATH = old_path
			return 0
	Game._save_ready = false
	Game._save_pending = false
	Game._active_screen = "presim"
	Game.world["work"] = []
	Game.world["encounter"] = ""
	var day := int(floor(Game.day))
	var saved_now: Dictionary = Game.world.get("_famine_wk", {})
	var year2 := int(saved_now.get("year2", day + YEAR_DAYS))
	var y2: int = int(saved_now.get("y2_weeks", 0))
	if _prev.is_empty():
		year2 = day + YEAR_DAYS
		_line("start", _snap())
	var did := 0
	while y2 < weeks and did < steps:
		if Time.get_ticks_msec() - t0 > 42000:
			printerr("FAMINE note time_stop day=%d y2_weeks=%d" % [day, y2])
			break
		var span := WEEK
		_sim._coarse(day, day + span)
		day += span
		Game.day = float(day)
		_line("", _snap())
		if day >= year2:
			y2 += 1
		did += 1
		await tree.process_frame
	Game.world["_famine_wk"] = {"day": day, "prev": _prev, "year2": year2, "y2_weeks": y2}
	_save_ck(day)
	Game.SAVE_PATH = old_path
	printerr("FAMINE done day=%d y2_weeks=%d/%d year2_at=%d secs=%.2f" % [day, y2, weeks, year2, float(Time.get_ticks_msec() - t0) / 1000.0])
	return 0
