extends Node2D
## v0.055 / v0.105. Read-only snapshots of finished ticks. No sim callbacks, RNG, particles or timers.
## Each slot is one code-drawn cue; even a breath is one slot. No child nodes per effect.
## v0.105 ("battle_markers" setting: "light" | "full" | "off", default "light"):
## - "light": no fear circles, no floating FEAR/ROUT words, at most one small marker per man, throttled on mass breaks.
## - "full": keeps fear circles and floating FEAR/ROUT words.
## - "off": hides fear and rout markers completely.
const MAX_CUES := 64
const LIFE := 0.75
const LIGHT_LIFE := 0.42
const LIGHT_MAX_BREAK_PER_TICK := 3
const LIGHT_MAX_MORALE_ACTIVE := 6
const LIGHT_FEAR_COOLDOWN := 40
const FULL_FEAR_COOLDOWN := 20
const INFO := {
	"fire": ["Fire breath: orange cone and flame", Color("#ff9b48")],
	"frost": ["Frost breath: blue cone and snowflake", Color("#a6e7ff")],
	"storm": ["Storm breath: violet cone and bolt", Color("#cab2ff")],
	"venom": ["Venom breath: green cone and droplets", Color("#b3ed66")],
	"fear": ["Fear / morale shock: amber marker", Color("#f5cb74")],
	"rout": ["Rout: red chevron toward retreat", Color("#ff8979")],
	"charge": ["Charge impact: white radial burst", Color("#fff0ce")],
	"volley": ["Missile release / volley: pale arrow fan", Color("#e3edff")],
	"rider_fall": ["Rider danger: mounted dragon fell; outcome in results", Color("#ffbc77")],
}
var items: Array[Dictionary] = []
var peak_count := 0
var enabled := true
var mode := "light"
var _explicit_mode := false
var tile := 40.0
var last_draw_fear_circles := 0
var last_draw_words := 0
var last_draw_markers := 0
var last_draw_calls := 0
var last_draw_usec := 0
var draw_pass_count := 0
var throttled_breaks := 0
var _next := 0
var _ended := false
var _morale := PackedFloat32Array()
var _fear_at := PackedInt32Array()
var _fall_at := PackedInt32Array()
var _contact := PackedByteArray()
var _charge_sides: Array = []

static func normalize_mode(m: Variant) -> String:
	var s := String(m).strip_edges().to_lower()
	if s == "full" or s == "off" or s == "light":
		return s
	return "light"

func current_mode() -> String:
	if _explicit_mode:
		return mode
	if Game != null and Game.has_method("battle_markers_mode"):
		return Game.battle_markers_mode()
	return mode

func set_mode(m: Variant) -> void:
	mode = normalize_mode(m)
	_explicit_mode = true
	if mode == "off":
		for i in range(items.size() - 1, -1, -1):
			if str(items[i].get("kind", "")) in ["fear", "rout"]:
				items.remove_at(i)
		_next = _next % maxi(1, items.size()) if not items.is_empty() else 0
	elif mode == "light":
		var seen_actors := {}
		var active_morale := 0
		for i in range(items.size() - 1, -1, -1):
			var k := str(items[i].get("kind", ""))
			if k not in ["fear", "rout"]:
				continue
			var ai := int(items[i].get("actor", -1))
			if (ai >= 0 and seen_actors.has(ai)) or active_morale >= LIGHT_MAX_MORALE_ACTIVE:
				items.remove_at(i)
				continue
			if ai >= 0:
				seen_actors[ai] = true
			active_morale += 1
			items[i]["life"] = minf(float(items[i].get("life", LIFE)), LIGHT_LIFE)
		_next = _next % maxi(1, items.size()) if not items.is_empty() else 0
	queue_redraw()

func setup(s: BattleSim, tile_px: float, on: bool = true, tactics: Array = [], marker_mode: String = "") -> void:
	end_battle()
	_ended = false
	enabled = on
	tile = tile_px
	peak_count = 0
	throttled_breaks = 0
	draw_pass_count = 0
	if marker_mode != "":
		mode = normalize_mode(marker_mode)
		_explicit_mode = true
	elif not _explicit_mode:
		mode = Game.battle_markers_mode() if (Game != null and Game.has_method("battle_markers_mode")) else "light"
	_charge_sides = tactics.duplicate()
	var n := s.fighters.size()
	_morale.resize(n); _fear_at.resize(n); _fall_at.resize(n); _contact.resize(n)
	_fear_at.fill(-1000); _fall_at.fill(-1000); _contact.fill(0)
	for f: Fighter in s.fighters: _morale[f.idx] = f.morale
	queue_redraw()

func _at(f: Fighter) -> Vector2:
	return (Vector2(f.cell) + Vector2(0.5, 0.5)) * tile

func _push(kind: String, at: Vector2, facing: int = 1, cone: PackedVector2Array = PackedVector2Array(), actor: int = -1, life: float = LIFE) -> Dictionary:
	if not enabled or _ended: return {}
	var edge := cone.duplicate()
	if not edge.is_empty(): edge.append(edge[0])
	var item := {"kind": kind, "pos": at, "dir": facing, "age": 0.0, "life": life, "cone": cone, "edge": edge, "actor": actor, "count": 1}
	if items.size() < MAX_CUES:
		items.append(item)
	else:
		items[_next] = item
		_next = (_next + 1) % MAX_CUES
	peak_count = maxi(peak_count, items.size())
	set_process(true)
	queue_redraw()
	return item

func _push_morale(kind: String, f: Fighter, facing: int, m: String, break_groups: Dictionary, state: Dictionary, bind_actor: bool = true) -> void:
	if not enabled or _ended or m == "off":
		return
	var actor_idx := f.idx if bind_actor else -1
	if m == "full":
		_push(kind, _at(f), facing, PackedVector2Array(), actor_idx, LIFE)
		return
	# v0.105: Light mode allows at most one marker per man and throttles/aggregates when many men break at once.
	if actor_idx >= 0:
		for existing: Dictionary in items:
			if int(existing.get("actor", -1)) == actor_idx and str(existing.get("kind", "")) in ["fear", "rout"]:
				if kind == "rout":
					existing["kind"] = "rout"
				existing["pos"] = _at(f)
				existing["dir"] = facing
				existing["age"] = 0.0
				existing["life"] = LIGHT_LIFE
				existing["count"] = int(existing.get("count", 1)) + 1
				throttled_breaks += 1
				queue_redraw()
				return
	var group := Vector3i(f.side, f.cell.x / 4, f.cell.y / 4)
	if break_groups.has(group):
		var g_item: Dictionary = break_groups[group]
		if kind == "rout":
			g_item["kind"] = "rout"
		g_item["count"] = int(g_item.get("count", 1)) + 1
		throttled_breaks += 1
		queue_redraw()
		return
	var emitted := int(state.get("emitted", 0))
	if emitted >= LIGHT_MAX_BREAK_PER_TICK or morale_marker_count() >= LIGHT_MAX_MORALE_ACTIVE:
		throttled_breaks += 1
		var last_item: Variant = state.get("last_item", null)
		if last_item is Dictionary:
			if kind == "rout":
				last_item["kind"] = "rout"
			last_item["count"] = int(last_item.get("count", 1)) + 1
		queue_redraw()
		return
	var pushed := _push(kind, _at(f), facing, PackedVector2Array(), actor_idx, LIGHT_LIFE)
	if not pushed.is_empty():
		break_groups[group] = pushed
		state["emitted"] = emitted + 1
		state["last_item"] = pushed

## A stepped envelope around exactly the rows used by DragonBreath.cone:
## dx=1..range, abs(dy)<=1+dx/2. Uses the release's origin/facing/range, not the moving sprite.
func _cone(reach: int, facing: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for dx in range(1, reach + 1):
		var half_rows := 1 + dx / 2
		points.append(Vector2((dx - 0.5) * facing, -half_rows - 0.5) * tile)
		points.append(Vector2((dx + 0.5) * facing, -half_rows - 0.5) * tile)
	for dx in range(reach, 0, -1):
		var half_rows := 1 + dx / 2
		points.append(Vector2((dx + 0.5) * facing, half_rows + 0.5) * tile)
		points.append(Vector2((dx - 0.5) * facing, half_rows + 0.5) * tile)
	# Remove repeated/collinear corners so the filled polygon triangulates reliably.
	var outline := PackedVector2Array()
	for p: Vector2 in points:
		if outline.is_empty() or outline[outline.size()-1] != p: outline.append(p)
	for i in range(outline.size()-1, -1, -1):
		var n := outline.size()
		if is_zero_approx((outline[i]-outline[(i+n-1)%n]).cross(outline[(i+1)%n]-outline[i])):
			outline.remove_at(i)
	return outline

## Optional batch supports DevTools replay/stress fixtures without editing sim.new_events.
func observe(s: BattleSim, batch: Array = []) -> void:
	if s.is_over():
		end_battle()
		return
	if not enabled or _ended: return
	# v0.105: clean up active morale markers for fighters who died or left the battle.
	for i in range(items.size() - 1, -1, -1):
		if str(items[i].get("kind", "")) in ["fear", "rout"]:
			var item_actor := int(items[i].get("actor", -1))
			if item_actor >= 0 and item_actor < s.fighters.size() and not s.fighters[item_actor].present():
				items.remove_at(i)
	_next = _next % maxi(1, items.size()) if not items.is_empty() else 0
	var m := current_mode()
	var volleys := {} # Coalesce releases from one nearby group during this tick only.
	var break_groups := {}
	var break_state := {"emitted": 0, "last_item": null}
	var custom_batch := not batch.is_empty()
	for e: Dictionary in (s.new_events if not custom_batch else batch):
		var kind := str(e.get("type", ""))
		var ai := int(e.get("actor", -1))
		var ti := int(e.get("target", -1))
		var a: Fighter = s.fighters[ai] if ai >= 0 and ai < s.fighters.size() else null
		var d: Fighter = s.fighters[ti] if ti >= 0 and ti < s.fighters.size() else null
		if kind == "breath" and a != null:
			var element := str(e.get("element", "fire"))
			if element not in ["fire", "frost", "storm", "venom"]: continue
			var face := int(e.get("facing", a.facing))
			var origin: Vector2i = e.get("origin", a.cell)
			_push(element, (Vector2(origin) + Vector2(0.5, 0.5)) * tile, face,
				_cone(clampi(int(e.get("range", DragonBreath.RANGE)), 1, DragonBreath.RANGE), face))
		elif kind == "rout" and a != null:
			# v0.105: custom-batch markers also need an actor for present() cleanup.
			_push_morale("rout", a, -1 if a.side == 0 else 1, m, break_groups, break_state, true)
		elif kind == "shoot" and a != null:
			var group := Vector3i(a.side, a.cell.x / 4, a.cell.y / 4)
			if not volleys.has(group):
				volleys[group] = true
				_push("volley", _at(a), a.facing)
		elif kind in ["hit", "block", "parry"] and a != null and d != null:
			var data: Dictionary = e.get("entry", {}).get("d", {})
			if data.has("shot") or str(data.get("verb", "")) == "shoot": continue
			var native_charge := str(data.get("verb", "")) == "charge"
			var opening_charge := _contact[ai] == 0 and a.side < _charge_sides.size() \
				and str(_charge_sides[a.side]) == "charge" and s.tick - a.last_move_tick <= NaturalAttacks.CHARGE_RUNUP_TICKS
			if native_charge or opening_charge: _push("charge", _at(d), a.facing)
			_contact[ai] = 1
		if kind in ["fall", "unconscious", "death"]:
			var fallen: Fighter = d if kind == "death" else a
			if fallen != null and fallen.dragon and str(fallen.dragon_profile.get("rider_person_uid", "")) != "" \
					and s.tick - _fall_at[fallen.idx] > 12:
				_fall_at[fallen.idx] = s.tick
				_push("rider_fall", _at(fallen))
	# Shock has no standalone event. Observe actual morale loss, with a per-actor cooldown.
	var fear_cd := LIGHT_FEAR_COOLDOWN if m == "light" else FULL_FEAR_COOLDOWN
	for f: Fighter in s.fighters:
		if f.present() and not f.routed and not f.nofear and _morale[f.idx] - f.morale >= 2.0 \
				and s.tick - _fear_at[f.idx] >= fear_cd:
			_fear_at[f.idx] = s.tick
			_push_morale("fear", f, f.facing, m, break_groups, break_state, true)
		_morale[f.idx] = f.morale
	queue_redraw()

func advance(delta: float) -> void:
	if items.is_empty():
		set_process(false)
		queue_redraw()
		return
	for i in range(items.size() - 1, -1, -1):
		items[i]["age"] = float(items[i]["age"]) + delta
		var item_life := float(items[i].get("life", LIFE))
		if float(items[i]["age"]) >= item_life:
			items.remove_at(i)
	_next = _next % maxi(1, items.size()) if not items.is_empty() else 0
	queue_redraw()
	if items.is_empty(): set_process(false)

func _process(delta: float) -> void:
	advance(delta)

func end_battle() -> void:
	items.clear()
	_morale.clear(); _fear_at.clear(); _fall_at.clear(); _contact.clear()
	_charge_sides.clear()
	_next = 0
	_ended = true
	last_draw_fear_circles = 0
	last_draw_words = 0
	last_draw_markers = 0
	last_draw_calls = 0
	last_draw_usec = 0
	set_process(false)
	queue_redraw()

func _exit_tree() -> void:
	end_battle()

func _note_fear_circle() -> void:
	last_draw_fear_circles += 1

func fear_circle_count() -> int:
	return last_draw_fear_circles

func fear_rout_word_count() -> int:
	return last_draw_words

func morale_marker_count() -> int:
	var n := 0
	for item: Dictionary in items:
		if str(item.get("kind", "")) in ["fear", "rout"]:
			n += 1
	return n

func drawn_morale_marker_count() -> int:
	return last_draw_markers

func draw_call_count() -> int:
	return last_draw_calls

func markers_for_actor(actor_idx: int) -> int:
	if actor_idx < 0:
		return 0
	var n := 0
	for item: Dictionary in items:
		if int(item.get("actor", -1)) == actor_idx and str(item.get("kind", "")) in ["fear", "rout"]:
			n += 1
	return n

func max_markers_per_actor() -> int:
	var counts := {}
	var best := 0
	for item: Dictionary in items:
		var ai := int(item.get("actor", -1))
		if ai >= 0 and str(item.get("kind", "")) in ["fear", "rout"]:
			var c := int(counts.get(ai, 0)) + 1
			counts[ai] = c
			if c > best:
				best = c
	return best

static func symbol(ci: CanvasItem, kind: String, p: Vector2, ink: Color, facing: int = 1, light_mode: bool = false) -> int:
	var calls := 0
	match kind:
		"fire":
			ci.draw_colored_polygon(PackedVector2Array([p+Vector2(-8,8), p+Vector2(-10,0),
				p+Vector2(-3,-6), p+Vector2(0,-13), p+Vector2(5,-2), p+Vector2(10,3), p+Vector2(6,8)]), ink)
			calls += 1
		"frost":
			for i in 3:
				var d := Vector2.from_angle(PI * i / 3.0)
				ci.draw_line(p-d*11, p+d*11, ink, 2.0)
				calls += 1
				for side: int in [-1, 1]:
					var tip := p + d * 8 * side
					ci.draw_line(tip, tip - d.rotated(0.65) * 4 * side, ink, 1.5)
					ci.draw_line(tip, tip - d.rotated(-0.65) * 4 * side, ink, 1.5)
					calls += 2
		"storm":
			ci.draw_polyline(PackedVector2Array([p+Vector2(6,-12), p+Vector2(-5,-1),
				p+Vector2(3,-1), p+Vector2(-6,12)]), ink, 3.0)
			calls += 1
		"venom":
			for i in 3:
				var q := p + Vector2((i-1)*8, (i%2)*5)
				ci.draw_circle(q, 3.0, ink)
				ci.draw_line(q, q+Vector2(1,-8), ink, 2.0)
				calls += 2
		"fear":
			if light_mode:
				# v0.105: Light mode draws a single compact exclamation mark with no fear-circle arcs.
				ci.draw_line(p+Vector2(0,-5), p+Vector2(0,1), ink, 2.0)
				ci.draw_circle(p+Vector2(0,4), 1.4, ink)
				calls += 2
			else:
				ci.draw_arc(p, 10, PI, TAU, 9, ink, 2)
				if ci.has_method("_note_fear_circle"): ci.call("_note_fear_circle")
				ci.draw_arc(p, 15, PI, TAU, 9, ink, 2)
				if ci.has_method("_note_fear_circle"): ci.call("_note_fear_circle")
				ci.draw_line(p+Vector2(0,-7), p, ink, 2)
				ci.draw_circle(p+Vector2(0,4), 1.5, ink)
				calls += 4
		"rout":
			if light_mode:
				# v0.105: Light mode draws a single compact retreat chevron.
				ci.draw_polyline(PackedVector2Array([p+Vector2(-4*facing,-5), p+Vector2(3*facing,0),
					p+Vector2(-4*facing,5)]), ink, 2.0)
				calls += 1
			else:
				for i in 2:
					var q := p + Vector2(i*10*facing, 0)
					ci.draw_polyline(PackedVector2Array([q+Vector2(-5*facing,-7), q+Vector2(3*facing,0),
						q+Vector2(-5*facing,7)]), ink, 2.5)
					calls += 1
		"charge":
			ci.draw_arc(p, 6, 0, TAU, 12, ink, 2)
			calls += 1
			for i in 8:
				var d := Vector2.from_angle(TAU*i/8.0)
				ci.draw_line(p+d*9, p+d*16, ink, 2)
				calls += 1
		"volley":
			for i in 3:
				var d := Vector2(facing, (i-1)*0.25).normalized()
				var q := p + Vector2(0, (i-1)*5)
				ci.draw_line(q-d*12, q+d*8, ink, 1.6)
				ci.draw_line(q+d*8, q+d*3+d.orthogonal()*3, ink, 1.6)
				calls += 2
		"rider_fall":
			ci.draw_circle(p+Vector2(-5,-10), 3.5, ink)
			ci.draw_line(p+Vector2(-4,-5), p+Vector2(5,1), ink, 3)
			ci.draw_line(p+Vector2(5,1), p+Vector2(-1,8), ink, 2)
			ci.draw_line(p+Vector2(-1,-3), p+Vector2(-9,2), ink, 2)
			ci.draw_line(p+Vector2(12,-5), p+Vector2(12,9), ink, 2)
			ci.draw_polyline(PackedVector2Array([p+Vector2(8,5), p+Vector2(12,10), p+Vector2(16,5)]), ink, 2)
			calls += 6
	return calls

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	var m := current_mode()
	var light_mode := m == "light"
	last_draw_fear_circles = 0
	last_draw_words = 0
	last_draw_markers = 0
	last_draw_calls = 0
	for item: Dictionary in items:
		var kind := str(item["kind"])
		var is_morale := kind in ["fear", "rout"]
		if is_morale and m == "off":
			continue
		var item_life := float(item.get("life", LIFE))
		var k := clampf(float(item["age"]) / maxf(0.001, item_life), 0.0, 1.0)
		var ink: Color = INFO[kind][1]
		ink.a = 1.0 - k * k
		var at: Vector2 = item["pos"]
		var cone: PackedVector2Array = item["cone"]
		if not cone.is_empty():
			var fill := ink
			fill.a *= 0.12
			draw_set_transform(at)
			draw_colored_polygon(cone, fill)
			draw_polyline(item["edge"], ink * Color(1,1,1,0.65), 2)
			at += Vector2(float(item["dir"]) * tile * 2.5, 0)
			draw_set_transform(Vector2.ZERO)
			last_draw_calls += 2
		var p := at + (Vector2(0, -18 - k * 6) if (light_mode and is_morale) else Vector2(0, -25 - k * 12))
		last_draw_calls += symbol(self, kind, p, ink, int(item["dir"]), light_mode)
		if is_morale:
			last_draw_markers += 1
		var draw_word := kind in ["fire", "frost", "storm", "venom", "rider_fall"] or (is_morale and m == "full")
		if draw_word:
			var text := "RIDER DANGER" if kind == "rider_fall" else kind.to_upper()
			var font := ThemeDB.fallback_font
			var start := p + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x*0.5, -20)
			draw_string_outline(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0,0,0,ink.a))
			draw_string(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
			last_draw_calls += 2
			if is_morale:
				last_draw_words += 1
	last_draw_usec = Time.get_ticks_usec() - t0
	draw_pass_count += 1
