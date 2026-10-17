class_name BreathFx
extends Node2D
## One breath blast: puffs stream out of the jaws along the cone and fade. Purely visual; frees itself.
const LIFE := 1.25
const PALETTE := {
	"fire": [Color(1.0, 0.95, 0.6), Color(1.0, 0.55, 0.12), Color(0.75, 0.12, 0.05), Color(0.25, 0.2, 0.18)],
	"frost": [Color(1.0, 1.0, 1.0), Color(0.7, 0.9, 1.0), Color(0.35, 0.6, 0.95), Color(0.75, 0.85, 0.95)],
	"venom": [Color(0.85, 1.0, 0.5), Color(0.45, 0.85, 0.2), Color(0.2, 0.5, 0.15), Color(0.3, 0.38, 0.2)],
	"storm": [Color(1.0, 1.0, 1.0), Color(0.75, 0.7, 1.0), Color(0.55, 0.4, 1.0), Color(0.35, 0.3, 0.5)],
}
var element := "fire"
var dir := 1
var length := 240.0
var t := 0.0
var puffs: Array = []   # [start_time, angle, speed, size]
var bolts: Array = []

func setup(kind: String, facing: int, reach_px: float, seed_value: int) -> void:
	element = kind if PALETTE.has(kind) else "fire"
	dir = facing
	length = reach_px
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 140:
		puffs.append([rng.randf_range(0.0, 0.55), rng.randf_range(-0.38, 0.38), rng.randf_range(0.75, 1.15), rng.randf_range(0.6, 1.4)])
	if element == "storm":
		for b in 3:
			var pts := PackedVector2Array([Vector2.ZERO])
			var ang := rng.randf_range(-0.3, 0.3)
			for k in range(1, 9):
				var d := length * float(k) / 8.0
				pts.append(Vector2(d, tan(ang) * d + rng.randf_range(-14, 14)))
			bolts.append(pts)
	z_index = 8

func _process(delta: float) -> void:
	t += delta
	if t >= LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var pal: Array = PALETTE[element]
	for p: Array in puffs:
		var age := t - float(p[0])
		if age < 0.0 or age > 0.7: continue
		var k := age / 0.7
		var d := length * k * float(p[2])
		var pos := Vector2(d * dir, tan(float(p[1])) * d)
		var col: Color = (pal[0] as Color).lerp(pal[1], clampf(k * 2.0, 0, 1)).lerp(pal[2], clampf(k * 2.0 - 1.0, 0, 1))
		col.a = (1.0 - k * k) * 0.9
		draw_circle(pos, (10.0 + 44.0 * k) * float(p[3]), col)
		if k > 0.6:
			var smoke: Color = pal[3]
			smoke.a = (1.0 - k) * 0.4
			draw_circle(pos + Vector2(0, -10.0 * k), (10.0 + 30.0 * k) * float(p[3]), smoke)
	if element == "storm" and t < 0.45:
		for pts: PackedVector2Array in bolts:
			var flipped := PackedVector2Array()
			for q in pts: flipped.append(Vector2(q.x * dir, q.y))
			draw_polyline(flipped, Color(0.9, 0.9, 1.0, 1.0 - t / 0.45), 3.0)
			draw_polyline(flipped, Color(0.6, 0.5, 1.0, 0.5 * (1.0 - t / 0.45)), 7.0)
