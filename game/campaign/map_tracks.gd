extends Node2D
## Tracks layer of the campaign map (campaign/tracks.gd holds the data). Draws the tracks the company has noticed as
## small faint chevrons (one per breadcrumb, pointing the way the force went; the hunted target's trail in gold once
## identified) and the hunted target's last-seen circle. Static: drawn in world space, so camera moves cost nothing;
## it redraws only when Tracks.version() or the contract changes (a drop every few in-game hours, new tracks
## noticed, a new sighting). Per frame: one int and one string compare.
##
## Also wires the HUD: tapping the contract line centres the map on the target or its last-seen spot, and the
## info panel shows what a tapped track says (world_map.gd calls tap() and fill_info()).

const COL_MEN := Color(1.0, 0.94, 0.8)
const COL_BEAST := Color(0.85, 0.72, 0.55)
const COL_MARK := Color(1.0, 0.8, 0.15)
const COL_CIRCLE := Color(1.0, 0.75, 0.3)

static var usec := 0       # profiling: microseconds in _process + _draw (tests read it)
static var draws := 0

var map: Node = null
var _ver := -1
var _cid := ""
var track_sel := []        # [wid, drop time] of the tapped crumb (indices shift as the ring buffer turns)

func setup(m: Node) -> void:
	map = m
	if m != null and m.get("lbl_contract") != null:
		var l: Label = m.lbl_contract
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.gui_input.connect(_on_contract_input)
	queue_redraw()

func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var v := Tracks.version(Game.world)
	var cid: String = Game.contract.get("id", "")
	if v != _ver or cid != _cid:
		_ver = v
		_cid = cid
		queue_redraw()
	usec += Time.get_ticks_usec() - t0

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	draws += 1
	var w: Dictionary = Game.world
	var st: Dictionary = w.get("tracks", {})
	if st.is_empty():
		return
	var day := float(Game.day)
	var tgt := Tracks.hunted_target(Game)
	var ls := Tracks.last_seen(Game)
	if not ls.is_empty() and Tracks.hides_target(Game, tgt):
		var c: Vector2 = ls["pos"]
		var r: float = ls["radius"]
		draw_circle(c, r, Color(COL_CIRCLE, 0.08))
		draw_arc(c, r, 0, TAU, 72, Color(COL_CIRCLE, 0.7), 2.5)
		draw_line(c + Vector2(-7, 0), c + Vector2(7, 0), Color(COL_CIRCLE, 0.9), 2.0)
		draw_line(c + Vector2(0, -7), c + Vector2(0, 7), Color(COL_CIRCLE, 0.9), 2.0)
	var buffers := geometry(st, day, tgt)
	var pts: PackedVector2Array = buffers[0]; var cols: PackedColorArray = buffers[1]
	var mpts: PackedVector2Array = buffers[2]; var mcols: PackedColorArray = buffers[3]
	if not pts.is_empty():
		draw_multiline_colors(pts, cols, 1.5)
	if not mpts.is_empty():
		draw_multiline_colors(mpts, mcols, 2.5)
	if not track_sel.is_empty():
		var info := _sel_info()
		if not info.is_empty():
			draw_arc(info["pos"], 11.0, 0, TAU, 20, Color(1, 1, 1, 0.9), 1.5)
	usec += Time.get_ticks_usec() - t0

func geometry(st: Dictionary, day: float, tgt: String) -> Array:
	# Reserve each buffer once; the final resize removes the unused slots.
	var capacity := 0
	for rec in st["forces"].values():
		capacity += (rec["c"] as Array).size()
	var pts := PackedVector2Array(); var cols := PackedColorArray()
	var mpts := PackedVector2Array(); var mcols := PackedColorArray()
	pts.resize(capacity); mpts.resize(capacity)
	cols.resize(capacity / 2); mcols.resize(capacity / 2)
	var pn := 0; var mn := 0
	for wid in st["forces"]:
		var rec: Dictionary = st["forces"][wid]
		var c: Array = rec["c"]
		var marked: bool = rec["mark"] and wid == tgt
		var base := COL_MARK if marked else (COL_BEAST if DB.is_creature(String(rec["r"])) else COL_MEN)
		var i := 0
		while i < c.size():
			if float(c[i + 5]) != 0.0:
				var fade := clampf(1.0 - (day - float(c[i + 2])) / Tracks.LIFE, 0.0, 1.0)
				if fade > 0.0:
					var p := Vector2(c[i], c[i + 1])
					var d := Vector2.from_angle(float(c[i + 4]))
					var s := d.orthogonal()
					var col := Color(base, (0.85 if marked else 0.5) * (0.25 + 0.75 * fade))
					var tip := p + d * 4.0
					if marked:
						mpts[mn] = tip; mpts[mn + 1] = p - d * 2.0 + s * 4.0
						mpts[mn + 2] = tip; mpts[mn + 3] = p - d * 2.0 - s * 4.0
						mpts[mn + 4] = p - d * 6.0; mpts[mn + 5] = p - d * 8.0
						mcols[mn / 2] = col; mcols[mn / 2 + 1] = col; mcols[mn / 2 + 2] = col
						mn += 6
					else:
						pts[pn] = tip; pts[pn + 1] = p - d * 2.0 + s * 4.0
						pts[pn + 2] = tip; pts[pn + 3] = p - d * 2.0 - s * 4.0
						pts[pn + 4] = p - d * 6.0; pts[pn + 5] = p - d * 8.0
						cols[pn / 2] = col; cols[pn / 2 + 1] = col; cols[pn / 2 + 2] = col
						pn += 6
			i += Tracks.STRIDE
	pts.resize(pn); cols.resize(pn / 2)
	mpts.resize(mn); mcols.resize(mn / 2)
	return [pts, cols, mpts, mcols]

# ---------------------------------------------------------------- HUD hooks
func _on_contract_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (ev as InputEventMouseButton).pressed:
		center_on_contract()

## Centres the map camera on the hunted target (when seen) or its last-seen spot; returns the point (INF if none).
func center_on_contract() -> Vector2:
	var p := Tracks.focus_point(Game)
	if p == Vector2.INF or map == null:
		return p
	map.follow = false
	map.cam.position = p
	var ls := Tracks.last_seen(Game)
	if not ls.is_empty() and not Tracks.target_in_sight(Game) and Tracks.hides_target(Game, ls["wid"]):
		map.toast("%s: last seen near %s, %s." % [Tracks.target_name(Game).capitalize(), ls["place"], Tracks.age_words(float(ls["age"]))])
	return p

## Map tap: selects a noticed track under p (radius r). Returns true when one was hit.
func tap(p: Vector2, r: float) -> bool:
	var hit := Tracks.track_at(Game, p, r)
	if hit.is_empty():
		return false
	track_sel = [hit[0], Tracks.crumb_time(Game, hit[0], hit[1])]
	queue_redraw()
	return true

func _sel_info() -> Dictionary:
	if track_sel.is_empty():
		return {}
	var idx := Tracks.index_of(Game, track_sel[0], float(track_sel[1]))
	return {} if idx < 0 else Tracks.describe(Game, track_sel[0], idx)

func clear_selection() -> void:
	if not track_sel.is_empty():
		track_sel = []
		queue_redraw()

## Fills the map's info panel for the selected track (called from world_map._fill_info).
func fill_info(m: Node, rebuild: bool) -> void:
	var info := _sel_info()
	if info.is_empty():
		m._close_info()
		return
	m.info_title.text = info["title"]
	m.info_body.text = info["text"]
	if not rebuild:
		return
	var wid: String = track_sel[0]
	m.info_buttons.add_child(m._button("Follow", func():
		var fp := Tracks.follow_point(Game, wid)
		if fp != Vector2.INF and CampaignWorld.set_travel(Game, fp):
			m.follow = true
		else:
			m.toast("The trail is lost here.")))
	m.info_buttons.add_child(m._button("Close", m._close_info))
