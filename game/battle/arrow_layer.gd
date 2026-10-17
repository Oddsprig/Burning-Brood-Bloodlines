class_name ArrowLayer
extends Node2D
## bows: arrows in flight (BattleSim.projectiles) as simple shafts over the battle map. Reads only the projectile
## dictionaries ("x", "y", "dx", "dy", "s", "L", "flat", "v", "kind"); never changes the sim. Long shots are drawn
## arcing (a parabola over their flight); flat ones at chest height.

const SHAFT := Color("#8a5a30")
const FLETCH := Color("#f2f2e8")

var sim: BattleSim
var tile := 40.0
var frac := 0.0      # progress into the next tick (smooth flight between sim ticks)
var _had := false

func setup(s: BattleSim, tile_px: float) -> void:
	sim = s
	tile = tile_px

func _process(_delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	_process_arrows()
	Perf.record_us("Battle arrows process", Time.get_ticks_usec() - started)

func _process_arrows() -> void:
	if sim == null:
		return
	var has := not sim.projectiles.is_empty()
	if has or _had:
		queue_redraw()
	_had = has

## Screen position of a projectile (with its arc height) and the direction it points on screen.
func arrow_pos(p: Dictionary) -> Array:
	var ds := float(p["v"]) * Formulas.TICK_SECONDS / Formulas.TILE_M * frac
	var s := minf(float(p["s"]) + ds, float(p["L"]))
	var x := float(p["ox"]) + float(p["dx"]) * s
	var y := float(p["oy"]) + float(p["dy"]) * s
	var base := Vector2((x + 0.5) * tile, (y + 0.82) * tile - 26.0)
	var lift := 0.0
	var slope := 0.0
	if not p["flat"]:
		var L := maxf(0.01, float(p["L"]))
		var q := clampf(s / L, 0.0, 1.0)
		var peak := L * tile * 0.12
		lift = 4.0 * peak * q * (1.0 - q)
		slope = 4.0 * peak * (1.0 - 2.0 * q) / L   # d(lift)/ds in px per tile
	var dir := Vector2(float(p["dx"]) * tile, float(p["dy"]) * tile - slope).normalized()
	return [base - Vector2(0, lift), dir]

func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	_draw_arrows()
	Perf.record_us("Battle arrows draw", Time.get_ticks_usec() - started)

func _draw_arrows() -> void:
	if sim == null:
		return
	for p in sim.projectiles:
		var r := arrow_pos(p)
		var at: Vector2 = r[0]
		var d: Vector2 = r[1]
		var tip_mat := String(DB.arrows.get(String(p["kind"]), {}).get("tip", "wood"))
		var tip := Color(DB.materials.get(tip_mat, {}).get("color", "#7a5230"))
		draw_line(at - d * 14.0, at, SHAFT, 2.0)
		draw_line(at - d * 14.0, at - d * 10.0, FLETCH, 3.0)
		draw_line(at - d * 2.5, at + d * 1.5, tip, 3.0)
