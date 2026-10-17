extends RefCounted
## Frozen accepted v0.034 On the move slice; only optional phase clocks are added.
## Source SHA256 (original bytes): bad977532e6d6c4e11e17d2dc3e786ec2a2baade0b8d7586d8959b0958358fd1

static var _pc := {}
static var profiling := false
static var phases := {}

static func build(scr, tids: Array, fid: String, tab: String) -> Control:
	assert(tab == "On the move")
	phases.clear()
	_pc.clear()
	var start := Time.get_ticks_usec() if profiling else 0
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var census_balance := Census.balance_of(Game.world, tids) if tab == "Census" else {}
	_header(tids, fid, v, int(census_balance["people"]) if tab == "Census" else -1)
	if profiling: phases["header_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	on_the_move(scr, tids, fid, v)
	_pc.clear()
	return v

static func _m(v: float) -> String:
	return RecData.money(v)

static func _t(tid: String) -> Dictionary:
	return RecData.town(tid)

static func _e(tid: String) -> Dictionary:
	return RecData.econ(_t(tid))

static func _people(tids: Array) -> int:
	var n := 0
	for tid in tids:
		n += _town_people(tid)
	return n

static func _town_people(tid: String) -> int:
	if not _pc.has(tid):
		_pc[tid] = RecData.live_people(_e(tid))
	return int(_pc[tid])

## Forces on the map in view: every one (world) or the faction's.

static func _forces(fid: String) -> Array:
	var out := []
	for wid in Game.world.get("warbands", {}):
		var wb: Dictionary = Game.world["warbands"][wid]
		if fid == "" or String(wb.get("faction", "")) == fid:
			out.append(wb)
	return out

static func _header(tids: Array, fid: String, v: VBoxContainer, people: int = -1) -> void:
	var w: Dictionary = Game.world
	var wars: Array = w.get("wars", [])
	if fid != "":
		wars = wars.filter(func(p): return String(p[0]) == fid or String(p[1]) == fid)
	RecKit.line(v, "%s. %d towns, %d people; %d pairs of factions at war; %d forces on the map." % [Calendar.text(Game.day), tids.size(),
		_people(tids) if people < 0 else people, wars.size(), _forces(fid).size()], "Small")

## v0.012: the faction's research house (campaign/academy.gd): its name and lead's title, know-how, budget, staff,
## each research line; tap through to the house's business page.

static func on_the_move(scr, tids: Array, fid: String, v: VBoxContainer) -> void:
	var start := Time.get_ticks_usec() if profiling else 0
	var w: Dictionary = Game.world
	var forces := _forces(fid)
	if profiling:
		phases["forces_ms"] = (Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
	var kinds := ["all"]
	var facs := ["all"]
	var rows := []
	var gold := 0.0; var ncar := 0; var nfield := 0
	for wb in forces:
		var kind := String(wb.get("kind", ""))
		if not kinds.has(kind): kinds.append(kind)
		var fname := UiWords.faction_name(String(wb.get("faction", "")))
		if not facs.has(fname): facs.append(fname)
		var units: Array = (wb["units"] as Array).filter(func(u): return not u.dead)
		var wid := String(wb["id"])
		var from := RecData.tname(String(wb.get("origin", wb.get("home", ""))))
		var to := String(wb.get("dest", wb.get("target_town", "")))
		if kind == "caravan":
			ncar += 1; gold += float(wb.get("gold", 0.0))
		if Army.is_field(wb):
			nfield += 1
		# Near is a sortable value, but a world-wide nearest-town scan is needed only when that sort or row is used.
		var near := func(): return CampaignWorld.nearest_town_name(w, wb["pos"])
		var force_name := RecPages.force_name(wb)
		rows.append({"kind": kind, "faction": fname, "men": units.size(), "near": near,
			"_l": force_name, "_r": "%d men" % units.size(),
			"_d": func(): return "%s; %s -> %s; near %s; %s; supply %s; %s" % [fname, from, RecData.tname(to) if to != "" else "-", near.call(),
				Caravans.cargo_text(wb.get("cargo", {}), float(wb.get("gold", 0.0))) if kind == "caravan" else "strength %s" % RecKit.num(CampaignWorld.band_power(units)),
				TownEcon.supply_word(TownEcon.force_supply(w, wb)), WarAI.mode_text(wb) if wb.has("mode") else String(wb.get("state", ""))],
			"_s": force_name, "_tap": func(): scr.open_force(wid)})
	if profiling:
		phases["row_data_ms"] = (Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
	var c := RecKit.card(v, "On the move")
	RecKit.kv(c, "Caravans on the road", "%d, carrying %s in coin" % [ncar, _m(gold)])
	RecKit.kv(c, "Armies in the field", "%d" % nfield)
	var ws: Dictionary = WarAI.state(w).get("stats", {})
	RecKit.kv(c, "Interceptions (since the world began)", "%d" % int(ws.get("intercepts", 0)))
	RecKit.kv(c, "Carriers", "wagons (caravans) only: no pack animals, porters or boats in the sim")
	for k in ["Robbed this season", "Worth of consignments", "Carriers going home empty", "Relief grain on the way", "Fetched by the buyer vs sent by the seller", "Arriving soonest (ETA)"]:
		RecKit.nt(c, k)
	if profiling:
		phases["cards_ms"] = (Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
	v.add_child(RecTable.make([{"k": "kind", "t": "Kind"}, {"k": "faction", "t": "Owner"}, {"k": "men", "t": "Men", "num": true}, {"k": "near", "t": "Near"}],
		rows, "kind", true, [{"t": "Kind", "opts": kinds, "fn": func(r, o): return r["kind"] == o},
		{"t": "Owner", "opts": facs, "fn": func(r, o): return r["faction"] == o}], true, 6))

	if profiling: phases["table_controls_sort_six_details_ms"] = (Time.get_ticks_usec() - start) / 1000.0
