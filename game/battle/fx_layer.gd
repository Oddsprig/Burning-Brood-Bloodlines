extends Node2D
## Small floating combat text over units ("dodge", "blocked", "arm!"). Drawn above all units.

const LIFE := 1.1
const MAX_ITEMS := 80

var items: Array = []   # {pos, text, color, t, size}

func add(pos: Vector2, text: String, color: Color, size := 15) -> void:
	# stack texts that spawn on the same spot
	var off := 0.0
	for it in items:
		if it["t"] < 0.25 and it["pos"].distance_to(pos) < 12.0:
			off -= 16.0
	items.append({"pos": pos + Vector2(0, off), "text": text, "color": color, "t": 0.0, "size": size})
	if items.size() > MAX_ITEMS:
		items.pop_front()

func clear_all() -> void:
	items.clear()
	queue_redraw()

func _process(delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	_process_fx(delta)
	Perf.record_us("Battle FX process", Time.get_ticks_usec() - started)

func _process_fx(delta: float) -> void:
	if items.is_empty():
		return
	# v0.072: age and drop in place (no new array and lambda call per frame)
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		it["t"] += delta
		if it["t"] >= LIFE: items.remove_at(i)
	queue_redraw()

func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	_draw_fx()
	Perf.record_us("Battle FX draw", Time.get_ticks_usec() - started)

func _draw_fx() -> void:
	var font := ThemeDB.fallback_font
	for it in items:
		var k: float = it["t"] / LIFE
		var p: Vector2 = it["pos"] + Vector2(0, -26.0 * k)
		var c: Color = it["color"]
		c.a = 1.0 - k * k
		var s: int = it["size"]
		var w := font.get_string_size(it["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
		var o := Color(0, 0, 0, c.a * 0.9)
		draw_string_outline(font, p - Vector2(w * 0.5, 0), it["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, s, 4, o)
		draw_string(font, p - Vector2(w * 0.5, 0), it["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, s, c)
