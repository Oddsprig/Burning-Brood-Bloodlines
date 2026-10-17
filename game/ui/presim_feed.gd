extends RefCounted
## The chronicle on the world-start screen (ui/presim.gd, v0.014): notable things the sim has REALLY recorded
## during the years before, read from the records it already keeps. Nothing is made up here; each line is one
## record (or one change in a town's or realm's state) told in a sentence.
##
## Sources: the world log (sacks, marches on towns, militia fights, battles between forces, plundered caravans,
## sickness brought from beyond the map, bloody succession fights), the diplomacy news (wars, peaces, alliances),
## each town's history (new heads, granaries opened, herd sickness), each town's famine stage, each town's open
## sickness cases (an outbreak), each realm's war leader, each realm's research know-how, each town's Census (the
## deaths of war leaders and town heads; the season's births and deaths across the land).
##
## Cost: poll() is called a few times a second. Every source is read from where the last poll stopped: the world
## log and the deaths by their day, the diplomacy news by its day, a town's history from its last line read; the
## state sources (famine stage, outbreaks, leaders, know-how) compare one value per town or realm. No class_name.

const OUTBREAK_MIN := 8   # open cases of one disease in one town that make it an outbreak worth telling
const FAMINE_AT := 3      # Barge.STAGES: 3 famine, 4 starvation, 5 collapse
## World-log lines worth telling, by a phrase in them, and how much (higher = kept first when the chronicle is busy).
const LOG_PRI := [["was sacked by", 4], ["'s corpse", 3], ["marches on", 2], ["beat back", 2], ["cut down the militia", 2],
	["from beyond the edge of the map", 2], ["fought off", 1], ["destroyed a band of", 1], ["cut to pieces", 1],
	[" caught ", 1], ["was plundered by", 1], ["Soldiers have deserted", 1], ["went home unpaid", 1],
	["unpaid soldiers walked home", 1]]
const DEATH_WORDS := {"battle": "fell in battle", "wounds": "died of wounds", "starved": "starved to death",
	"frozen": "froze to death", "old age": "died of old age", "childbirth": "died in childbirth", "executed": "was executed",
	"accident": "died in an accident", "murdered": "was murdered"}

var from_day := 0.0       # the day the years before began (the chronicle's year 1)
var last_day := 0.0       # game day at the last poll
var log_day := 0          # newest world-log "Day N" already read
var dp_day := -1.0        # newest diplomacy news day already read
var hist_last := {}       # tid -> the last town-history line read
var famine := {}          # tid -> worst famine stage told (0 = none)
var sick := {}            # tid -> {disease: true} outbreaks told and still open
var leaders := {}         # fid -> war leader's name
var lead_names := {}      # war leader name -> "war leader of the X"
var head_names := {}      # "tid|name" -> "the reeve of Ashford"
var kh_tier := {}         # "fid|knowhow" -> tier told
var census_stamp := 0     # the newest census season told

func setup(game) -> void:
	var w: Dictionary = game.world
	from_day = float(w.get("presim", {}).get("from", game.day))
	last_day = float(game.day)
	for s in w.get("log", []):
		log_day = maxi(log_day, _log_day(String(s)))
	for n in w.get("diplo", {}).get("news", []):
		dp_day = maxf(dp_day, float(n["day"]))
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		var h: Array = e.get("hist", [])
		hist_last[tid] = String(h[-1]) if not h.is_empty() else ""
		var fs := int(e.get("fstage", 0))
		famine[tid] = fs if fs >= FAMINE_AT else 0
		var told := {}
		var act: Dictionary = e.get("sk", {}).get("act", {})
		for dis in act:
			if int(act[dis]) >= OUTBREAK_MIN:
				told[dis] = true
		sick[tid] = told
	for fid in w.get("factions", {}):
		leaders[fid] = String(w["factions"][fid].get("war_leader", {}).get("name", ""))
	var rs: Dictionary = w.get("research", {})
	for fid in rs:
		for k in rs[fid].get("kh", {}):
			kh_tier["%s|%s" % [fid, k]] = _tier(float(rs[fid]["kh"][k]))
	census_stamp = Census.stamp_of(float(game.day))

## The new notable records since the last poll: [{day, text, pri, pos (world px, only when it happened at a town)}].
func poll(game) -> Array:
	var w: Dictionary = game.world
	var out := []
	_leaders(game, w, out)
	_world_log(w, out)
	_diplo(w, out)
	_towns(game, w, out)
	_research(game, w, out)
	_census(game, w, out)
	last_day = float(game.day)
	return out

## "Year 2, summer" for a day of the years before.
func date_text(day: float) -> String:
	var y := int(maxf(0.0, day - from_day)) / (4 * Calendar.DAYS_PER_SEASON) + 1
	return "Year %d, %s" % [y, Calendar.season(day)]

func _ev(day: float, text: String, pri: int, w: Dictionary = {}, tid: String = "") -> Dictionary:
	var d := {"day": day, "text": text, "pri": pri}
	if tid != "" and w.get("towns", {}).has(tid):
		d["pos"] = w["towns"][tid]["pos"]
	return d

func _log_day(s: String) -> int:
	if not s.begins_with("Day "):
		return 0
	return s.substr(4, s.find(":") - 4).to_int()

## The first town named in a line (for the flash on the map).
func _town_in(w: Dictionary, text: String) -> String:
	for tid in w.get("towns", {}):
		if text.contains(String(w["towns"][tid]["name"])):
			return tid
	return ""

# ---------------------------------------------------------------- the world log (newest at the end, capped)
func _world_log(w: Dictionary, out: Array) -> void:
	var lg: Array = w.get("log", [])
	var got := []
	var newest := log_day
	var i := lg.size() - 1
	while i >= 0:
		var s := String(lg[i])
		var n := _log_day(s)
		if n <= log_day:
			break
		newest = maxi(newest, n)
		got.append(s)
		i -= 1
	log_day = newest
	for k in range(got.size() - 1, -1, -1):
		var s: String = got[k]
		var text := s.substr(s.find(": ") + 2)
		if text.begins_with("The company") or text.begins_with("Contract") or text.begins_with("You "):
			continue
		var pri := 0
		for lp in LOG_PRI:
			if text.contains(String(lp[0])):
				pri = int(lp[1])
				break
		if pri > 0:
			out.append(_ev(float(_log_day(s) - 1), text, pri, w, _town_in(w, text)))

# ---------------------------------------------------------------- diplomacy news (wars, peaces, alliances)
func _diplo(w: Dictionary, out: Array) -> void:
	var news: Array = w.get("diplo", {}).get("news", [])
	var newest := dp_day
	for n in news:
		var d := float(n["day"])
		if d <= dp_day:
			continue
		newest = maxf(newest, d)
		var text := String(n["text"])
		var pri := 2
		if text.contains("declares war") or text.begins_with("Peace:"):
			pri = 4
		elif text.contains("alliance"):
			pri = 3
		elif text.contains("trade pact"):
			pri = 1
		out.append(_ev(d, text, pri))
	dp_day = newest

# ---------------------------------------------------------------- war leaders (and who counts as notable)
func _leaders(game, w: Dictionary, out: Array) -> void:
	lead_names.clear()
	for fid in w.get("factions", {}):
		var fac: Dictionary = w["factions"][fid]
		var wl: Dictionary = fac.get("war_leader", {})
		var nm := String(wl.get("name", ""))
		if nm == "":
			continue
		var title := String(wl.get("title", "war leader"))
		lead_names[nm] = "%s of %s" % [title, CampaignWorld.faction_the(fid)]
		var old := String(leaders.get(fid, ""))
		leaders[fid] = nm
		if old != nm and old != "":
			out.append(_ev(float(game.day), "%s is the new %s of %s, after %s." % [nm, title, CampaignWorld.faction_the(fid), old], 3,
				w, String(fac.get("capital", ""))))
	head_names.clear()
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var hd: Dictionary = t["econ"].get("head", {})
		if hd.has("name"):
			head_names["%s|%s" % [tid, hd["name"]]] = "the %s of %s" % [String(hd.get("title", "head")), t["name"]]

# ---------------------------------------------------------------- per town: history, famine, outbreaks, deaths
func _towns(game, w: Dictionary, out: Array) -> void:
	var today := float(game.day)
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		var tn := String(t["name"])
		# the town's history: lines after the last one read
		var h: Array = e.get("hist", [])
		if not h.is_empty() and String(h[-1]) != String(hist_last.get(tid, "")):
			var last := String(hist_last.get(tid, ""))
			var j := h.size() - 1
			while j >= 0 and String(h[j]) != last:
				j -= 1
			for k in range(j + 1, h.size()):
				var s := String(h[k])
				var body := s.substr(s.find(": ") + 2)
				if body.begins_with("The "):
					body = "t" + body.substr(1)
				var pri := 0
				if body.contains("is the new"):
					pri = 3 if t.get("capital", false) else 1
				elif body.contains("opened the granary"):
					pri = 2
				elif body.contains("broke out among"):
					pri = 1
				if pri > 0:
					out.append(_ev(today, "In %s, %s" % [tn, body], pri, w, tid))
			hist_last[tid] = String(h[-1])
		# famine: told when the town reaches famine (and each worse stage), and when it is fed again
		var fs := int(e.get("fstage", 0))
		var told := int(famine.get(tid, 0))
		if fs >= FAMINE_AT and fs > told:
			famine[tid] = fs
			var words := {3: "Famine in %s.", 4: "Starvation in %s: people are dying in the streets.", 5: "%s is collapsing from hunger."}
			out.append(_ev(today, String(words.get(fs, "Famine in %s.")) % tn, 4 if fs >= 5 else 3, w, tid))
		elif told >= FAMINE_AT and fs <= 1:
			famine[tid] = 0
			out.append(_ev(today, "The famine in %s is over." % tn, 2, w, tid))
		# sickness: an outbreak once one disease has OUTBREAK_MIN open cases; forgotten when it has gone
		var act: Dictionary = e.get("sk", {}).get("act", {})
		if not sick.has(tid):
			sick[tid] = {}
		var st: Dictionary = sick[tid]
		for dis in act:
			if int(act[dis]) >= OUTBREAK_MIN and not st.has(dis):
				st[dis] = true
				out.append(_ev(today, "An outbreak of %s in %s: %d sick." % [Sickness.dname(String(dis)), tn, int(act[dis])], 3, w, tid))
		for dis in st.keys():
			if not act.has(dis):
				st.erase(dis)
		# deaths of the notable (war leaders, town heads), from the town's Census since the last poll
		var deaths: Array = e.get("census", {}).get("deaths", [])
		var i := deaths.size() - 1
		while i >= 0 and float(deaths[i][0]) > last_day:
			var d: Array = deaths[i]
			i -= 1
			var nm := String(d[2])
			if nm == "":
				continue
			var role := String(head_names.get("%s|%s" % [tid, nm], lead_names.get(nm, "")))
			if role == "":
				continue
			var cause := String(d[5])
			var how := String(DEATH_WORDS.get(cause, "died"))
			if cause == "sickness":
				how = "died of %s" % String(d[6]) if String(d[6]) != "" else "died of sickness"
			var aged := ", aged %d" % int(d[3]) if int(d[3]) >= 0 else ""
			out.append(_ev(float(d[0]), "%s, %s, %s%s." % [nm, role, how, aged], 3, w, tid))

# ---------------------------------------------------------------- research know-how
func _tier(kh: float) -> int:
	return 0 if kh <= 0.0 else 1 + int(kh / (100.0 / 6.0))

func _research(game, w: Dictionary, out: Array) -> void:
	var rs: Dictionary = w.get("research", {})
	for fid in rs:
		var khs: Dictionary = rs[fid].get("kh", {})
		for k in khs:
			var key := "%s|%s" % [fid, k]
			var tr := _tier(float(khs[k]))
			var old := int(kh_tier.get(key, tr))
			kh_tier[key] = tr
			if tr <= old:
				continue
			var cap := String(w.get("factions", {}).get(fid, {}).get("capital", ""))
			var who := Diplomacy.cap(CampaignWorld.faction_the(fid))
			if old == 0:
				out.append(_ev(float(game.day), "%s: the research house makes its first headway in %s." % [who, k], 2, w, cap))
			else:
				out.append(_ev(float(game.day), "%s: the research house raises its %s know-how to %d of 100." % [who, k, int(float(khs[k]))], 2, w, cap))

# ---------------------------------------------------------------- the season's census across the land
func _census(game, w: Dictionary, out: Array) -> void:
	var day := float(game.day)
	var stamp := Census.stamp_of(day)
	if stamp <= census_stamp or Calendar.day_of_season(day) < 3:
		return   # a few days into the season, so every town has cut its row
	census_stamp = stamp
	var born := 0
	var died := 0
	var people := 0
	var before := 0
	var causes := {}
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var rows: Array = t["econ"].get("census", {}).get("rows", [])
		for k in range(rows.size() - 1, maxi(-1, rows.size() - 4), -1):
			var r: Dictionary = rows[k]
			if int(r.get("stamp", -1)) != stamp:
				continue
			born += int(r.get("births", 0))
			people += int(r.get("people", 0))
			var dd: Dictionary = r.get("deaths", {})
			for c in dd:
				died += int(dd[c])
				causes[c] = int(causes.get(c, 0)) + int(dd[c])
			if k > 0:
				before += int((rows[k - 1] as Dictionary).get("people", 0))
			break
	if people <= 0:
		return
	var top := ""
	for c in causes:
		if top == "" or int(causes[c]) > int(causes[top]):
			top = c
	var most := " (most of %s)" % top if top != "" and died > 0 else ""
	var ended := day - Calendar.day_of_season(day)   # a day of the season that just ended
	var yr := int(maxf(0.0, ended - from_day)) / (4 * Calendar.DAYS_PER_SEASON) + 1
	var change := " (%+d)" % (people - before) if before > 0 else ""
	out.append(_ev(day, "The census after the %s of year %d: %d born, %d died%s. %d people in the land%s." % [
		Calendar.season(ended), yr, born, died, most, people, change], 2))
