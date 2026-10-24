extends Node2D
## v0.055. Read-only snapshots of finished ticks. No sim callbacks, RNG, particles or timers.
## Each slot is one code-drawn cue; even a breath is one slot. No child nodes per effect.
const MAX_CUES := 64
const LIFE := 0.75
const INFO := {
	"fire": ["Fire breath: orange cone and flame", Color("#ff9b48")],
	"frost": ["Frost breath: blue cone and snowflake", Color("#a6e7ff")],
	"storm": ["Storm breath: violet cone and bolt", Color("#cab2ff")],
	"venom": ["Venom breath: green cone and droplets", Color("#b3ed66")],
	"fear": ["Fear / morale shock: amber ripples", Color("#f5cb74")],
	"rout": ["Rout: red chevrons toward retreat", Color("#ff8979")],
	"charge": ["Charge impact: white radial burst", Color("#fff0ce")],
	"volley": ["Missile release / volley: pale arrow fan", Color("#e3edff")],
	"rider_fall": ["Rider danger: mounted dragon fell; outcome in results", Color("#ffbc77")],
}
var items: Array[Dictionary] = []
var peak_count := 0
var enabled := true
var tile := 40.0
var _next := 0
var _ended := false
var _morale := PackedFloat32Array()
var _fear_at := PackedInt32Array()
var _fall_at := PackedInt32Array()
var _contact := PackedByteArray()
var _charge_sides: Array = []

func setup(s: BattleSim, tile_px: float, on: bool = true, tactics: Array = []) -> void:
	end_battle()
	_ended = false
	enabled = on
	tile = tile_px
	peak_count = 0
	_charge_sides = tactics.duplicate()
	var n := s.fighters.size()
	_morale.resize(n); _fear_at.resize(n); _fall_at.resize(n); _contact.resize(n)
	_fear_at.fill(-1000); _fall_at.fill(-1000); _contact.fill(0)
	for f: Fighter in s.fighters: _morale[f.idx] = f.morale

func _at(f: Fighter) -> Vector2:
	return (Vector2(f.cell) + Vector2(0.5, 0.5)) * tile

func _push(kind: String, at: Vector2, facing: int = 1, cone: PackedVector2Array = PackedVector2Array()) -> void:
	if not enabled or _ended: return
	var edge := cone.duplicate()
	if not edge.is_empty(): edge.append(edge[0])
	var item := {"kind": kind, "pos": at, "dir": facing, "age": 0.0, "cone": cone, "edge": edge}
	if items.size() < MAX_CUES:
		items.append(item)
	else:
		items[_next] = item
		_next = (_next + 1) % MAX_CUES
	peak_count = maxi(peak_count, items.size())
	set_process(true)
	queue_redraw()

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
	var volleys := {} # Coalesce releases from one nearby group during this tick only.
	for e: Dictionary in (s.new_events if batch.is_empty() else batch):
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
			_push("rout", _at(a), -1 if a.side == 0 else 1)
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
	for f: Fighter in s.fighters:
		if f.present() and not f.routed and not f.nofear and _morale[f.idx] - f.morale >= 2.0 \
				and s.tick - _fear_at[f.idx] >= 20:
			_fear_at[f.idx] = s.tick
			_push("fear", _at(f))
		_morale[f.idx] = f.morale

func advance(delta: float) -> void:
	if items.is_empty():
		set_process(false)
		return
	for i in range(items.size() - 1, -1, -1):
		items[i]["age"] = float(items[i]["age"]) + delta
		if float(items[i]["age"]) >= LIFE: items.remove_at(i)
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
	set_process(false)
	queue_redraw()

func _exit_tree() -> void:
	end_battle()

static func symbol(ci: CanvasItem, kind: String, p: Vector2, ink: Color, facing: int = 1) -> void:
	match kind:
		"fire":
			ci.draw_colored_polygon(PackedVector2Array([p+Vector2(-8,8), p+Vector2(-10,0),
				p+Vector2(-3,-6), p+Vector2(0,-13), p+Vector2(5,-2), p+Vector2(10,3), p+Vector2(6,8)]), ink)
		"frost":
			for i in 3:
				var d := Vector2.from_angle(PI * i / 3.0)
				ci.draw_line(p-d*11, p+d*11, ink, 2.0)
				for side: int in [-1, 1]:
					var tip := p + d * 8 * side
					ci.draw_line(tip, tip - d.rotated(0.65) * 4 * side, ink, 1.5)
					ci.draw_line(tip, tip - d.rotated(-0.65) * 4 * side, ink, 1.5)
		"storm":
			ci.draw_polyline(PackedVector2Array([p+Vector2(6,-12), p+Vector2(-5,-1),
				p+Vector2(3,-1), p+Vector2(-6,12)]), ink, 3.0)
		"venom":
			for i in 3:
				var q := p + Vector2((i-1)*8, (i%2)*5)
				ci.draw_circle(q, 3.0, ink)
				ci.draw_line(q, q+Vector2(1,-8), ink, 2.0)
		"fear":
			ci.draw_arc(p, 10, PI, TAU, 9, ink, 2)
			ci.draw_arc(p, 15, PI, TAU, 9, ink, 2)
			ci.draw_line(p+Vector2(0,-7), p, ink, 2)
			ci.draw_circle(p+Vector2(0,4), 1.5, ink)
		"rout":
			for i in 2:
				var q := p + Vector2(i*10*facing, 0)
				ci.draw_polyline(PackedVector2Array([q+Vector2(-5*facing,-7), q+Vector2(3*facing,0),
					q+Vector2(-5*facing,7)]), ink, 2.5)
		"charge":
			ci.draw_arc(p, 6, 0, TAU, 12, ink, 2)
			for i in 8:
				var d := Vector2.from_angle(TAU*i/8.0)
				ci.draw_line(p+d*9, p+d*16, ink, 2)
		"volley":
			for i in 3:
				var d := Vector2(facing, (i-1)*0.25).normalized()
				var q := p + Vector2(0, (i-1)*5)
				ci.draw_line(q-d*12, q+d*8, ink, 1.6)
				ci.draw_line(q+d*8, q+d*3+d.orthogonal()*3, ink, 1.6)
		"rider_fall":
			ci.draw_circle(p+Vector2(-5,-10), 3.5, ink)
			ci.draw_line(p+Vector2(-4,-5), p+Vector2(5,1), ink, 3)
			ci.draw_line(p+Vector2(5,1), p+Vector2(-1,8), ink, 2)
			ci.draw_line(p+Vector2(-1,-3), p+Vector2(-9,2), ink, 2)
			ci.draw_line(p+Vector2(12,-5), p+Vector2(12,9), ink, 2)
			ci.draw_polyline(PackedVector2Array([p+Vector2(8,5), p+Vector2(12,10), p+Vector2(16,5)]), ink, 2)

func _draw() -> void:
	for item: Dictionary in items:
		var k := float(item["age"]) / LIFE
		var kind := str(item["kind"])
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
		var p := at + Vector2(0, -25 - k * 12)
		symbol(self, kind, p, ink, int(item["dir"]))
		if kind in ["fire", "frost", "storm", "venom", "fear", "rout", "rider_fall"]:
			var text := "RIDER DANGER" if kind == "rider_fall" else kind.to_upper()
			var font := ThemeDB.fallback_font
			var start := p + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x*0.5, -20)
			draw_string_outline(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0,0,0,ink.a))
			draw_string(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
