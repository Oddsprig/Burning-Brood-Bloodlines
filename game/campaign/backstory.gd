class_name Backstory
extends RefCounted
## Backstories from what really happened (Douglas): a recruit's (or a family record's) story is built only from
## the sim: the family's real history events (Families.event: [day, code, args...]), its holdings, the recruit's own
## life history (Persons.life_spans), its debts and hardship, and the real reason he signs on now.
## v0.014 (Douglas: "needs to be more of a story, less of a list"): the recruit card is ONE short story in time
## order (story()): where he comes from (family, land or none, town), then up to four beats from his own life and
## the family's and town's events, joined by cause where the record supports it (no field -> hired work; a loss ->
## the next job or service), and it ends on why he stands before the captain, with his temper and his dream (and a
## like, where it fits his work) woven in. Nothing is invented: every clause comes from a recorded fact. Phrases are
## data (data/backstory.json "story"), several per kind and per culture, picked by a seed (same person, same text).
## The family record (family_text, recent_life) keeps the plain one-sentence-per-event form ("events").

static var _d: Dictionary = {}

static func data() -> Dictionary:
	if _d.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/backstory.json"))
		_d = d if d is Dictionary else {"events": {}, "how": {"": "in battle"}, "story": {}}
	return _d

const WORDS := ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

## "the Marshes", "the Kettles": a family name in the plural (-es after s, sh, ch, x, z; else -s).
static func plural(name: String) -> String:
	for end in ["s", "sh", "ch", "x", "z"]:
		if name.ends_with(end):
			return name + "es"
	return name + "s"

## The recruit card story (story()). role: Recruits.person_role (his trade), {} when nothing real fits; u: the
## recruit (his temper, dream and likes), null for none.
static func recruit_text(town: Dictionary, e: Dictionary, f: Dictionary, first: String, own_name: String = "", role: Dictionary = {}, u: Unit = null) -> String:
	return String(story(town, e, f, first, own_name, role, u)["text"])

## The places and services of his own history that his card tells (tests: every one is in the story).
static func own_lines(town: Dictionary, e: Dictionary, f: Dictionary, p: Array, first: String) -> Array:
	var st := story(town, e, f, first, Persons.name_of(f, p, Persons.race_of(e)))
	var out := []
	for part in st["parts"]:
		out.append_array(part["life"])
	return out

## The family record story (no reason line): up to four latest events, time order. "" when nothing happened yet.
static func family_text(town: Dictionary, e: Dictionary, f: Dictionary) -> String:
	if f.get("estate", false):
		return ""
	_k_e = e
	_k_me = []
	var evs := _pick(f, 4, "")
	var out := []
	var ctx := _ctx(town, e, f, "")
	for ev in evs:
		out.append(_sentence(ev, f, ctx, false, int(f.get("seed", 0))))
	return " ".join(PackedStringArray(out))

static func _ctx(town: Dictionary, e: Dictionary, f: Dictionary, first: String) -> Dictionary:
	var unpaid := int(f.get("unpaid", 0))
	return {"first": first, "fam": String(f.get("name", "")), "fams": plural(String(f.get("name", ""))), "town": String(town.get("name", "town")),
		"head": String(e.get("head", {}).get("title", "head")), "debt": str(maxi(1, int(ceil(float(f.get("debt", 0.0)))))) if float(f.get("debt", 0.0)) > 0.0 else "0",
		"weeks": WORDS[mini(unpaid, 10)] + (" week" if unpaid == 1 else " weeks"),
		"rate": Loans._pct(float(f.get("ln", {}).get("rate", Loans.rate(e)))) if TownEcon.has_econ(town) else "",
		"land": _holdings(e, f)}

static func _role_ctx(e: Dictionary, f: Dictionary, role: Dictionary) -> Dictionary:
	if role.is_empty():
		return {"title": "", "a_title": "", "where": "", "crop": "", "herd": ""}
	var t: String = role["title"]
	var c := {"title": t, "a_title": ("an " if t.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + t, "where": String(role.get("where", "")),
		"crop": "", "herd": ""}
	if role["kind"] == "land":
		c["crop"] = TownEcon.variety_word(e, role["key"])
	elif role["kind"] == "herd":
		c["herd"] = String(role["key"])
	return c

## "12 acres of barley and 6 pigs", "" when they hold nothing.
static func _holdings(e: Dictionary, f: Dictionary) -> String:
	var parts := []
	for c in f.get("land", {}):
		parts.append("%s of %s" % [TownEcon.n_of(int(f["land"][c]), "acres"), TownEcon.variety_word(e, c)])
	for a in f.get("herd", {}):
		parts.append(TownEcon.n_of(int(f["herd"][a]), a))
	if parts.size() > 1:
		return ", ".join(PackedStringArray(parts.slice(0, -1))) + " and " + String(parts[-1])
	return "" if parts.is_empty() else String(parts[0])

## What weighs most in a life: losses of house, land and kin first, then the rest (ties: the more recent).
const WEIGHT := {"home_head": 5, "sold_house": 5, "land": 5, "sold_land": 5, "died": 5, "sick_died": 5, "starved": 5, "childbed": 5,
	"destitute": 4, "home_ruin": 4, "evicted": 4, "maimed": 4, "loan": 3, "borrow": 3, "unpaid": 3, "shelter": 3, "deserted": 3,
	"hunger_winter": 3, "housed": 2, "owned": 2, "joined": 2, "company": 2, "officer": 2, "hunger": 2, "left": 2, "ruined": 1, "elder": 1, "born": 1}

const KIN_CODES := ["died", "maimed", "joined", "company", "deserted", "officer", "elder", "born", "left", "married", "wed_away"]

## Household events a recruit card leaves out (births, the old dying, weddings, someone leaving: the family's,
## not his); his kin's fates stay in when the register knows how they are related to him.
const NOT_HIS := ["elder", "born", "left", "married", "wed_away"]

static func _pick(f: Dictionary, n: int, own_name: String, skip: Array = [], kin_known: bool = false) -> Array:
	var evs: Array = f.get("ev", [])
	var seen := {}
	var cands := []
	for i in range(evs.size() - 1, -1, -1):
		var ev: Array = evs[i]
		var code := str(ev[1])
		if not data()["events"].has(code) or skip.has(code):
			continue
		if own_name != "" and ev.size() > 2 and str(ev[2]) == own_name:
			continue
		if kin_known and code in PERSON_CODES and ev.size() > 2 and _rel(f, ev, true) in ["", "-"]:
			continue
		if int(seen.get(code, 0)) >= (2 if code == "died" else 1):
			continue
		seen[code] = int(seen.get(code, 0)) + 1
		cands.append([int(WEIGHT.get(code, 1)), i, ev])
	cands.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] > b[1])
	var top := cands.slice(0, n)
	top.sort_custom(func(a, b): return a[1] < b[1])   # time order
	return top.map(func(x): return x[2])

static func _var(list: Array, seed: int) -> String:
	if list.is_empty():
		return ""
	return String(list[absi(seed) % list.size()])

## Events about one named person of the family (args: [name, ...]).
const PERSON_CODES := ["died", "maimed", "joined", "company", "deserted", "officer"]
## The kinship context for the sentences being built: the town economy and the person the text is about
## (the recruit; [] = the family record, read from the head of the household).
static var _k_e: Dictionary = {}
static var _k_me: Array = []

## The real kinship of the event's person to the recruit (or to the head): "Wil's brother", "Doran's mother".
## "-" when the event is the recruit's own; "" when the register does not know the person or the link.
static func _rel(f: Dictionary, ev: Array, as_recruit: bool) -> String:
	if _k_e.is_empty():
		return ""
	var who := Persons.by_name_any(_k_e, f, str(ev[2]))
	if who.is_empty():
		return ""
	var ref: Array = _k_me if as_recruit and not _k_me.is_empty() else Persons.head_of(f)
	if ref.is_empty():
		return ""
	if int(who[0]) == int(ref[0]):
		return "-"
	var k := Persons.kin_of(_k_e, f, who, ref)
	return "" if k == "kin" or k == "head of the family" else k

## The family's "Recent life" log: its real events, newest first, each dated: ["Day 3 of spring, year 2: ...", ...].
static func recent_life(town: Dictionary, e: Dictionary, f: Dictionary, n: int = 10) -> Array:
	var ctx := _ctx(town, e, f, "")
	_k_e = e
	_k_me = []
	var out := []
	var ev: Array = f.get("ev", [])
	for i in range(ev.size() - 1, maxi(-1, ev.size() - 1 - n), -1):
		var x: Array = ev[i]
		out.append("%s: %s" % [Calendar.text(float(x[0])).split(" - ")[0], _sentence(x, f, ctx, false)])
	return out

static func _sentence(ev: Array, f: Dictionary, ctx: Dictionary, as_recruit: bool, seed0: int = 0) -> String:
	var D := data()
	var code := str(ev[1])
	var day := float(ev[0])
	if code == "hunger" and ev.size() > 2 and int(ev[2]) == 3:
		code = "hunger_winter"
	var seed := hash([int(f.get("seed", 0)), int(ev[0]), code, seed0])
	var s := _var(D["events"].get(code, []), seed)
	var rel := ""
	if code in PERSON_CODES and ev.size() > 2:
		rel = _rel(f, ev, as_recruit)
		if rel == "":
			rel = "the family's " + ("kinswoman" if ev.size() > 4 and str(ev[4]) == "f" else "kinsman")
		elif rel == "-":
			rel = ""   # the event is his own
	var how := ""
	if code == "died":
		how = str(D["how"].get(str(ev[3]) if ev.size() > 3 else "", D["how"][""]))
	s = s.replace("{rel}", rel).replace("{how}", how)
	for i in 3:
		s = s.replace("{a%d}" % i, str(ev[i + 2]) if ev.size() > i + 2 else "")
	s = _fill(s, ctx).replace("{season}", Calendar.season(day)).replace("{year}", str(Calendar.year(day)))
	return _cap(s)

static func _fill(s: String, ctx: Dictionary) -> String:
	for k in ctx:
		s = s.replace("{%s}" % k, str(ctx[k]))
	return s

static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)

## Why he signs on now: the family's hardest current trouble.
static func _reason_key(f: Dictionary) -> String:
	if Shelter.destitute(f) or f.get("destitute", false):
		return "destitute"
	if int(f["homes"]) <= 0 and f.get("shel", false):
		return "sheltered"
	if int(f["homes"]) <= 0:
		return "homeless"
	if int(f["hungry"]) > 0:
		return "hungry"
	if int(f["unpaid"]) > 0:
		return "unpaid"
	if float(f["debt"]) > 0.5:
		return "debt"
	if f.get("ruined", false):
		return "ruined"
	if int(f["idle"]) > 0:
		return "idle"
	return "none"

## "two winters" (winters touched since day d0), "a season" when no winter yet.
static func winters_word(d0: float, now: float) -> String:
	var s0 := Calendar.year(d0) * 4 + Calendar.season_index(d0)
	var s1 := Calendar.year(now) * 4 + Calendar.season_index(now)
	var w := 0
	for s in range(s0, s1 + 1):
		if s % 4 == 3:
			w += 1
	if w == 0:
		var n := s1 - s0 + 1
		return "a season" if n <= 1 else "%s seasons" % WORDS[mini(n, 10)]
	return "a winter" if w == 1 else "%s winters" % WORDS[mini(w, 10)]

## "a tanner's hand at the Thorne tanner" from a job record ("title@where").
static func job_words(arg: String) -> String:
	var parts := arg.split("@")
	var t := String(parts[0])
	var a := ("an " if t.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + t
	return a + (" at " + String(parts[1]) if parts.size() > 1 and String(parts[1]) != "" else "")

## "two years", "a season", "three seasons", "a few weeks"
static func span_words(days: float) -> String:
	var yd := People.year_days()
	if days >= yd * 1.5:
		return "%s years" % WORDS[mini(10, int(round(days / yd)))]
	if days >= yd * 0.9:
		return "a year"
	var s := int(round(days / float(Calendar.DAYS_PER_SEASON)))
	if s >= 2:
		return "%s seasons" % WORDS[mini(10, s)]
	if s == 1:
		return "a season"
	return "a few weeks"

# ================================================================== the recruit's story (v0.014)
## Town events a recruit's story may tell (e.tev), the weightiest of his last two years.
const STORY_TOWN := {"sacked": 2, "famine": 1}
## Family events that are good news (never the cause of his next move).
const GAINS := ["housed", "owned", "joined"]
## Family events that undo a working life ("he worked as ..., but ..."): wages, debts, land, house, bread.
const HITS_WORK := ["unpaid", "loan", "land", "sold_land", "home_head", "sold_house", "evicted", "ruined", "hunger", "hunger_winter", "destitute"]
## Family events about one of his kin: told only when the register knows how they are related to him.
const KIN_EV := ["died", "maimed", "deserted", "joined", "sick_died", "starved", "childbed"]
## The beats behind each hardship: when the story's last beat is one, the ending says "still ...".
const THEMES := {"unpaid": ["unpaid"], "debt": ["loan", "borrow", "land", "sold_land"], "hungry": ["hunger", "hunger_winter", "famine"],
	"homeless": ["home_head", "sold_house", "evicted", "home_ruin", "idle_homeless"], "sheltered": ["shelter", "idle_poorhouse"],
	"destitute": ["destitute", "sold_house", "home_head"], "ruined": ["ruined", "land", "sold_land"],
	"idle": ["idle_idle", "idle_homeless", "idle_poorhouse"]}
## Event arguments the story must carry word for word (tests: the clause tells that fact).
const MUST_ARG := ["loan", "borrow", "land", "sold_land", "unpaid", "died", "maimed", "deserted", "joined", "sick_died", "starved", "childbed"]
const MAX_BEATS := 4
const MIN_SPAN := 7.0   # [ours] a job or idle spell shorter than a week is not worth a line

static func _sd() -> Dictionary:
	return data().get("story", {})

## A story phrase for the town's culture: story.cultures[cul] first, then story. "a.b" reaches into a dictionary.
static func _sl(cul: String, key: String) -> Variant:
	var roots: Array = [_sd().get("cultures", {}).get(cul, {}), _sd()]
	for r in roots:
		var v: Variant = r
		for k in key.split("."):
			v = (v as Dictionary).get(k) if v is Dictionary else null
			if v == null:
				break
		if v != null:
			return v
	return []

## One phrase of a list (by the seed), or the string itself; "" when there is none.
static func _pv(cul: String, key: String, seed: int) -> String:
	var v: Variant = _sl(cul, key)
	if v is Array:
		return _var(v, seed)
	return String(v) if v is String else ""

## The recruit's story: {text, parts: [{s (one sentence), facts (what it is built from), days (the dated beats in
## it), must (words it must carry), life (his own places and services in it)}]}. Deterministic per person.
static func story(town: Dictionary, e: Dictionary, f: Dictionary, first: String, own_name: String = "", role: Dictionary = {}, u: Unit = null) -> Dictionary:
	var cul := String(town.get("culture", "middle"))
	if not (_sd().get("cultures", {}) as Dictionary).has(cul):
		cul = "middle"
	var seed := absi(hash([int(f.get("seed", 0)), first]))
	var now := float(e.get("day", 0))
	var ctx := _ctx(town, e, f, first)
	ctx.merge(_role_ctx(e, f, role), true)
	_k_e = e
	_k_me = Persons.by_name(e, f, own_name) if own_name != "" else []
	var me: Array = _k_me
	var sex := int(me[2]) if not me.is_empty() else -1
	ctx["pro"] = ("he" if sex == 0 else "she") if sex >= 0 else first
	ctx["pos"] = ("his" if sex == 0 else "her") if sex >= 0 else first + "'s"
	ctx["full"] = own_name if own_name != "" else first
	ctx["famw"] = _pv(cul, "famw", 0)
	ctx["winters"] = winters_word(float(f.get("hl", {}).get("d", now)), now)
	ctx["debt_c"] = String(ctx["debt"]) + (" coin" if String(ctx["debt"]) == "1" else " coins")
	var tn := String(ctx["town"])
	ctx["a_town"] = ("an " if tn.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + tn
	var lk := "land" if String(ctx["land"]) != "" else ("homeless" if int(f.get("homes", 1)) <= 0 else "none")
	var lv: Variant = _sl(cul, "landverb." + lk)
	ctx["lv"] = _fill(String(lv[0]), ctx) if lv is Array and lv.size() >= 2 else ""
	ctx["lvs"] = _fill(String(lv[1]), ctx) if lv is Array and lv.size() >= 2 else ""
	var beats := _beats(e, f, me, ctx, cul, seed, own_name, now)
	var amb := String(u.ambition) if u != null else ""
	var amb_done := false
	var like_done := false
	# where he comes from (his full name first; a landless house and his first hired work are one sentence: cause)
	var parts := []
	var cur := {"s": _fill(_pv(cul, "origin", seed), ctx), "n": 1, "facts": ["origin:" + lk], "days": [], "must": [String(ctx["full"]), String(ctx["town"])], "life": []}
	var prev := {"kind": "origin", "landless": lk != "land"}
	var last_me := true
	var last_day := -1.0
	for i in beats.size():
		var b: Dictionary = beats[i]
		var h := absi(hash([seed, i, 7]))
		var link := _link(prev, b)
		var subj := String(ctx["pro"]) if last_me else first
		var c := String(b["c"]).replace("{subj}", subj)
		var tail := ""
		if not amb_done and amb == "see the world" and b["kind"] == "serve" and String(b["arg"]) in ["caravan", "army", "company", "bandit"]:
			tail = ", " + _fill(_pv(cul, "road_dream", h), ctx); amb_done = true
		elif not amb_done and amb == "avenge their home" and b["kind"] == "town" and b["code"] == "sacked":
			tail = ", " + _fill(_pv(cul, "avenge", h), ctx); amb_done = true
		elif not like_done and u != null and b["code"] == "job_now":
			tail = _like_tail(cul, ctx, role, u, h)
			like_done = tail != ""
		var date := _date_words(float(b["day"]), last_day)
		var d := ("since " + date) if b["since"] else (date if date.begins_with("that ") else "in " + date)
		var join: bool = int(cur["n"]) < 2 and (link in ["so", "but"] or h % 2 == 0)
		if join:
			cur["s"] = String(cur["s"]) + ", %s %s %s%s" % [_pv(cul, "joins." + link, h), c, d, tail]
		else:
			parts.append(_close(cur))
			var op := _pv(cul, "openers." + link, h)
			if b["since"] and not (op.begins_with("{D}") or op.begins_with("{C}")):
				op = "{D}, {c}"   # "since ..." reads only at the front or the end
			cur = {"s": op.replace("{D}", _cap(d)).replace("{d}", d).replace("{C}", _cap(c)).replace("{c}", c) + tail, "n": 0,
				"facts": [], "days": [], "must": [], "life": []}
		cur["n"] = int(cur["n"]) + 1
		cur["facts"].append("%s:%s" % [b["kind"], b["code"]])
		cur["days"].append(float(b["day"]))
		cur["must"].append_array(b["must"])
		cur["life"].append_array(b["life"])
		last_me = b["me"]
		last_day = float(b["day"])
		prev = b
	parts.append(_close(cur))
	parts.append(_ending(cul, ctx, f, beats, u, amb if not amb_done else "", last_me, seed))
	var txt := " ".join(PackedStringArray(parts.map(func(p): return String(p["s"]))))
	return {"text": txt, "parts": parts}

static func _close(cur: Dictionary) -> Dictionary:
	return {"s": _tidy(_cap(String(cur["s"])) + "."), "facts": cur["facts"], "days": cur["days"], "must": (cur["must"] as Array).map(func(x): return _tidy(String(x))),
		"life": (cur["life"] as Array).map(func(x): return _tidy(String(x)))}

## Names that already carry an article ("the Sly", "of the Grey Horse") after a "the": "the the Sly farm" -> "the Sly farm".
static func _tidy(s: String) -> String:
	return s.replace("the the ", "the ").replace("The the ", "The ").replace("the of the ", "the ").replace("The of the ", "The ")

## "the autumn of year 1"; "that winter" in the same year as the beat before.
static func _date_words(day: float, last: float) -> String:
	if last >= 0.0 and Calendar.year(last) == Calendar.year(day):
		return "that " + Calendar.season(day)
	return "the %s of year %d" % [Calendar.season(day), Calendar.year(day)]

## How a beat follows the one before: "so" (a cause the record supports: a house with no field and his first hired
## work; a loss and the job or service he took within the year), "but" (work, then a loss), else "then" / "and".
static func _link(prev: Dictionary, b: Dictionary) -> String:
	var work: bool = b["me"] and String(b["kind"]) in ["job", "serve"]
	if prev["kind"] == "origin":
		return "so" if prev["landless"] and work and not b["own"] else "and"
	var pk := String(prev["kind"])
	var hurt := pk in ["idle", "wound", "town"] or (pk == "ev" and not String(prev["code"]) in GAINS)
	if hurt and work and float(b["day"]) - float(prev["day"]) <= People.year_days():
		return "so"
	if pk == "job" and b["kind"] == "ev" and String(b["code"]) in HITS_WORK:
		return "but"
	return "and" if b["since"] else "then"   # ("and then he has worked ..." does not read)

## His beats in time order, at most MAX_BEATS (the latest): his own life (jobs, service, idle spells, wounds), the
## family's weightiest events, and what befell the town in his last two years.
static func _beats(e: Dictionary, f: Dictionary, me: Array, ctx: Dictionary, cul: String, seed: int, own_name: String, now: float) -> Array:
	var out := []
	var mine := []
	for s in (Persons.life_spans(me) if not me.is_empty() else []):   # newest first
		if mine.size() >= 3:
			break
		var code := String(s["code"])
		var open := float(s["to"]) < 0.0
		if code == "serve" and String(s["arg"]) in ["hire", "company"]:
			continue
		if code in ["job", "idle"] and not open and float(s["to"]) - float(s["from"]) < MIN_SPAN:
			continue
		mine.append(s)
	for s in mine:
		var b := _life_beat(s, ctx, cul, seed + out.size(), now)
		if not b.is_empty():
			out.append(b)
	var nf := 2 if out.size() >= 2 else 3
	for ev in _story_events(f, nf, own_name, cul):
		var b := _ev_beat(ev, f, ctx, cul, seed)
		if not b.is_empty():
			out.append(b)
	var born := float(me[3]) if not me.is_empty() else -1.0e9
	var best: Array = []
	for x in e.get("tev", []):
		var w := int(STORY_TOWN.get(String(x[1]), 0))
		if w > 0 and now - float(x[0]) <= 2.0 * People.year_days() and float(x[0]) >= born and (best.is_empty() or w >= int(STORY_TOWN[String(best[1])])):
			best = x
	if not best.is_empty():
		var c := ctx.duplicate()
		for i in 3:
			c["a%d" % i] = str(best[i + 2]) if best.size() > i + 2 else ""
		out.append({"day": float(best[0]), "kind": "town", "code": String(best[1]), "arg": "", "me": false, "since": false, "own": false,
			"c": _fill(_pv(cul, "town." + String(best[1]), seed), c), "must": [String(c["a0"])] if String(best[1]) == "sacked" else [],
			"life": [], "theme": String(best[1])})
	out.sort_custom(func(a, b): return float(a["day"]) < float(b["day"]))
	return out.slice(maxi(0, out.size() - MAX_BEATS))

## One span of his own history as a beat (clause without the date; {subj} filled by the teller).
static func _life_beat(s: Dictionary, ctx: Dictionary, cul: String, seed: int, now: float) -> Dictionary:
	var code := String(s["code"])
	var arg := String(s["arg"])
	var open := float(s["to"]) < 0.0
	var c := ctx.duplicate()
	c["span"] = span_words((now if open else float(s["to"])) - float(s["from"]))
	var key := code
	var must := []
	match code:
		"job":
			var title := arg.split("@")[0]
			if title.begins_with("farmhand on the family "):
				key = "land"
				c["crop"] = title.substr(23).strip_edges()
				must = [String(c["crop"])] if String(c["crop"]) != "" else []
				if String(c["crop"]) == "":
					c["crop"] = "fields"
			else:
				c["what"] = job_words(arg)
				must = [arg.split("@")[1] if arg.contains("@") else title]
			if open:
				key += "_now"
		"serve":
			var fw: Variant = _sl(cul, "force." + arg)
			c["force"] = String(fw) if fw is String else "in service"
			key = "serving" if open else "serve"
			must = [String(c["force"])]
		"idle":
			key = "idle_" + arg + ("_now" if open else "")
		"wound":
			key = "wound"
		"legend":   # v0.014: a legendary piece he made
			c["what"] = arg
			must = [arg]
	var t := _pv(cul, "me." + key, seed)
	if t == "":
		return {}
	return {"day": float(s["from"]), "kind": code, "code": key, "arg": arg, "me": true, "since": open and code != "wound",
		"own": key.begins_with("land") or arg.contains("on the family "), "c": _fill(t, c), "must": must, "life": must.duplicate(),
		"theme": ("idle_" + arg) if code == "idle" else key}

## The family's weightiest events for the story (codes with story phrases; his kin's only when the register knows
## the link; never his own), time order.
static func _story_events(f: Dictionary, n: int, own_name: String, cul: String) -> Array:
	var evs: Array = f.get("ev", [])
	var seen := {}
	var cands := []
	for i in range(evs.size() - 1, -1, -1):
		var ev: Array = evs[i]
		var code := _ev_code(ev)
		if code in NOT_HIS or (_sl(cul, "ev." + code) as Array).is_empty() or seen.has(code):
			continue
		if own_name != "" and ev.size() > 2 and str(ev[2]) == own_name:
			continue
		if code in KIN_EV and (ev.size() < 3 or _rel(f, ev, true) in ["", "-"]):
			continue
		seen[code] = true
		cands.append([int(WEIGHT.get(code, 1)), i, ev])
	cands.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] > b[1])
	var top := cands.slice(0, n)
	top.sort_custom(func(a, b): return a[1] < b[1])
	return top.map(func(x): return x[2])

static func _ev_code(ev: Array) -> String:
	var code := str(ev[1])
	return "hunger_winter" if code == "hunger" and ev.size() > 2 and int(ev[2]) == 3 else code

static func _ev_beat(ev: Array, f: Dictionary, ctx: Dictionary, cul: String, seed: int) -> Dictionary:
	var code := _ev_code(ev)
	var c := ctx.duplicate()
	for i in 3:
		c["a%d" % i] = str(ev[i + 2]) if ev.size() > i + 2 else ""
	if code in KIN_EV:
		var rel := _rel(f, ev, true)
		var first := String(ctx["first"])
		var at := rel.find("'s ")
		if first != "" and at > 0 and (rel.begins_with(first + "'s ") or rel.begins_with(first + " and ")):
			rel = String(ctx["pos"]) + " " + rel.substr(at + 3)   # "Gerd's brother", "Orrin and Elsa's daughter" -> "his ..."
		c["rel"] = rel
	c["how"] = str(data()["how"].get(str(ev[3]) if ev.size() > 3 else "", data()["how"][""])) if code == "died" else ""
	var t := _pv(cul, "ev." + code, hash([seed, int(ev[0]), code]))
	if t == "":
		return {}
	return {"day": float(ev[0]), "kind": "ev", "code": code, "arg": "", "me": false, "since": false, "own": false,
		"c": _fill(t, c), "must": [String(c["a0"])] if code in MUST_ARG and String(c["a0"]) != "" else [], "life": [], "theme": code}

## A like woven into his present work where it fits: the weapon his trade puts in his hands, the drink he makes.
static func _like_tail(cul: String, ctx: Dictionary, role: Dictionary, u: Unit, seed: int) -> String:
	if String(role.get("kind", "")) != "job":
		return ""
	var key := String(role.get("key", ""))
	var c := ctx.duplicate()
	var kit: Dictionary = Recruits.KITS.get(Recruits.JOB_KIT.get(key, ""), {})
	if u.pref_weapon != "" and (kit.get("skills", {}) as Dictionary).has(u.pref_weapon):
		c["weapons"] = String((_sl(cul, "weapons") as Dictionary).get(u.pref_weapon, u.pref_weapon))
		return ", " + _fill(_pv(cul, "likes_tool", seed), c)
	if (key == "brewer" and u.fav_drink == "beer") or (key == "vintner" and u.fav_drink == "wine"):
		c["drink"] = u.fav_drink
		return ", " + _fill(_pv(cul, "likes_drink", seed), c)
	return ""

## His temper in a word or two ("very steady-nerved", "a loner"); "" when nothing stands out or it is a squad phrase.
static func _trait_words(u: Unit) -> String:
	if u == null:
		return ""
	var best := ""
	var dev := 30
	for t in u.personality:
		var d := absi(int(u.personality[t]) - 50)
		if d > dev:
			dev = d; best = t
	if best == "":
		return ""
	var word := Factory.trait_word(best, int(u.personality[best]))
	var ws := word.split(" ")
	if ws.size() >= 3 and ws[0] != "a" and ws[0] != "very" and ws[0].ends_with("s"):
		return ""   # a verb phrase ("sticks with the squad"): only said of a man in the company
	return word

## Why he stands before the captain: his temper and the family's hardship (said "still ..." when the last beat was
## that hardship), what he asks for, and his dream when no beat carried it.
static func _ending(cul: String, ctx: Dictionary, f: Dictionary, beats: Array, u: Unit, amb: String, last_me: bool, seed: int) -> Dictionary:
	var reason := _reason_key(f)
	var still: bool = not beats.is_empty() and String(beats[-1]["theme"]) in THEMES.get(reason, [])
	var st := _pv(cul, "still." + reason, seed + 3) if still else ""
	if st == "":
		st = _pv(cul, "state." + reason, seed + 3)
	st = _fill(st, ctx)
	var tr := _trait_words(u)
	var lead := tr + (", " if tr.begins_with("a ") else " and ") + st if tr != "" and st != "" else tr + st
	var t := _pv(cul, "come", seed + 5)
	if lead == "":
		t = t.replace("{lead}, ", "")
	var s := t.replace("{lead}", lead).replace("{subj}", String(ctx["pro"]) if last_me else String(ctx["first"])).replace("{pay}", _pv(cul, "pay", seed + 9))
	s = _fill(s, ctx)
	var facts := ["reason:" + reason]
	if tr != "":
		facts.append("trait")
	if amb != "":
		var c := ctx.duplicate()
		c["amb"] = amb.replace("their", String(ctx["pos"]))
		c["amb_ing"] = _fill(String((_sl(cul, "amb_ing") as Dictionary).get(amb, amb)), ctx)
		s += ", " + _fill(_pv(cul, "dream", seed + 11), c)
		facts.append("ambition")
	return {"s": _tidy(_cap(s) + "."), "facts": facts, "days": [], "must": [], "life": []}
