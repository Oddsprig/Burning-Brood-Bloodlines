class_name PixelCanvas
extends RefCounted
## Tiny software rasteriser for code-drawn pixel art. Shapes are given in a *local* frame
## (`xf`: rotation in 90-degree steps, uniform scale `k`, translation) and land on an integer
## pixel grid. Shapes drawn between begin() and end() form one "part": end() shades the part
## (light from the top-left) and gives it a 1-px dark outline, so overlapping parts stay readable.
## Everything is plain data (PackedColorArray), so it runs headless and is easy to test.

const CLEAR := Color(0, 0, 0, 0)
const N4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var w: int
var h: int
var buf := PackedColorArray()
var xf := Transform2D.IDENTITY
var k := 1.0
var _part: Dictionary = {}   # Vector2i -> Color
var _in_part := false

func _init(width: int = 32, height: int = 32) -> void:
	w = width
	h = height
	buf.resize(w * h)
	buf.fill(CLEAR)

## Local frame: `origin` is where local (0,0) lands in image pixels.
func set_frame(origin: Vector2, scale: float = 1.0, rot: float = 0.0) -> void:
	xf = Transform2D(rot, Vector2(scale, scale), 0.0, origin)
	k = scale

func get_px(x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= w or y >= h:
		return CLEAR
	return buf[y * w + x]

func set_px(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	if c.a < 0.999:
		c = buf[y * w + x].blend(c)
	buf[y * w + x] = c

func _put(x: int, y: int, c: Color, pat: Callable) -> void:
	if pat.is_valid():
		c = pat.call(x, y, c)
	if _in_part:
		_part[Vector2i(x, y)] = c
	else:
		set_px(x, y, c)

func map(p: Vector2) -> Vector2:
	return xf * p

func map_i(p: Vector2) -> Vector2i:
	var m := xf * p
	return Vector2i(floori(m.x), floori(m.y))

# --- primitives (local coordinates) -------------------------------------------------------

## Axis-aligned (in local frame) rectangle; covers pixels whose centres fall inside.
func rect(r: Rect2, c: Color, pat: Callable = Callable()) -> void:
	var a := xf * r.position
	var b := xf * (r.position + r.size)
	var x0 := ceili(minf(a.x, b.x) - 0.5)
	var x1 := ceili(maxf(a.x, b.x) - 0.5)
	var y0 := ceili(minf(a.y, b.y) - 0.5)
	var y1 := ceili(maxf(a.y, b.y) - 0.5)
	for y in range(maxi(y0, -1), mini(y1, h + 1)):
		for x in range(maxi(x0, -1), mini(x1, w + 1)):
			_put(x, y, c, pat)

## One logical pixel (k x k image pixels).
func dot(p: Vector2, c: Color) -> void:
	rect(Rect2(p, Vector2.ONE), c)

func poly(pts: PackedVector2Array, c: Color, pat: Callable = Callable()) -> void:
	var m := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		var q := xf * p
		m.append(q)
		lo = lo.min(q)
		hi = hi.max(q)
	for y in range(maxi(floori(lo.y), -1), mini(ceili(hi.y) + 1, h + 1)):
		for x in range(maxi(floori(lo.x), -1), mini(ceili(hi.x) + 1, w + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), m):
				_put(x, y, c, pat)

## Thick segment with round caps; r is a local radius.
func capsule(a: Vector2, b: Vector2, r: float, c: Color, pat: Callable = Callable()) -> void:
	var ma := xf * a
	var mb := xf * b
	var rr := r * k
	var lo := ma.min(mb) - Vector2(rr, rr)
	var hi := ma.max(mb) + Vector2(rr, rr)
	for y in range(maxi(floori(lo.y), -1), mini(ceili(hi.y) + 1, h + 1)):
		for x in range(maxi(floori(lo.x), -1), mini(ceili(hi.x) + 1, w + 1)):
			var pc := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.get_closest_point_to_segment(pc, ma, mb).distance_squared_to(pc) <= rr * rr:
				_put(x, y, c, pat)

## 1-px line (Bresenham) at k=1; a k-wide capsule when the frame is scaled up.
func line1(a: Vector2, b: Vector2, c: Color, pat: Callable = Callable()) -> void:
	if k > 1.5:
		capsule(a, b, 0.5, c, pat)
		return
	var p0 := map_i(a)
	var p1 := map_i(b)
	var dx := absi(p1.x - p0.x)
	var dy := -absi(p1.y - p0.y)
	var sx := 1 if p0.x < p1.x else -1
	var sy := 1 if p0.y < p1.y else -1
	var err := dx + dy
	var x := p0.x
	var y := p0.y
	var guard := 0
	while guard < 512:
		guard += 1
		_put(x, y, c, pat)
		if x == p1.x and y == p1.y:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy

## Ellipse with local radii (axes follow the local frame).
func ellipse(cn: Vector2, rx: float, ry: float, c: Color, pat: Callable = Callable()) -> void:
	var m := xf * cn
	var ex := (absf(xf.x.x) * rx + absf(xf.y.x) * ry)
	var ey := (absf(xf.x.y) * rx + absf(xf.y.y) * ry)
	if ex <= 0.01 or ey <= 0.01:
		return
	for y in range(maxi(floori(m.y - ey), -1), mini(ceili(m.y + ey) + 1, h + 1)):
		for x in range(maxi(floori(m.x - ex), -1), mini(ceili(m.x + ex) + 1, w + 1)):
			var dx := (x + 0.5 - m.x) / ex
			var dy := (y + 0.5 - m.y) / ey
			if dx * dx + dy * dy <= 1.0:
				_put(x, y, c, pat)

## Remove pixels of the current part inside a local rect (cut-outs such as a coif's face hole).
func erase_rect(r: Rect2) -> void:
	var a := xf * r.position
	var b := xf * (r.position + r.size)
	var x0 := ceili(minf(a.x, b.x) - 0.5)
	var x1 := ceili(maxf(a.x, b.x) - 0.5)
	var y0 := ceili(minf(a.y, b.y) - 0.5)
	var y1 := ceili(maxf(a.y, b.y) - 0.5)
	for y in range(y0, y1):
		for x in range(x0, x1):
			_part.erase(Vector2i(x, y))

## Paint over already-drawn opaque pixels only (blood, stains). Image coordinates.
func stain_px(x: int, y: int, c: Color) -> bool:
	if get_px(x, y).a < 0.5:
		return false
	set_px(x, y, c)
	return true

func px_img(x: int, y: int, c: Color) -> void:
	if _in_part:
		_part[Vector2i(x, y)] = c
	else:
		set_px(x, y, c)

# --- parts ------------------------------------------------------------------------------

func begin() -> void:
	_part.clear()
	_in_part = true

## Commit the current part: shade edges, outline with `outline` (alpha 0 = none).
## `shade` = edge light/dark strength; `shine` = colour for top-edge glints (metal, elf skin).
func end(outline: Color, shade: float = 0.14, shine: Color = CLEAR) -> void:
	_in_part = false
	if _part.is_empty():
		return
	var out := {}
	for p in _part:
		var c: Color = _part[p]
		if shade > 0.0:
			var up := _part.has(p + Vector2i(0, -1))
			var lf := _part.has(p + Vector2i(-1, 0))
			var dn := _part.has(p + Vector2i(0, 1))
			var rt := _part.has(p + Vector2i(1, 0))
			if not up:
				c = c.lerp(shine, 0.55) if shine.a > 0.0 else c.lightened(shade * 1.4)
			elif not lf:
				c = c.lightened(shade * 0.6)
			elif not dn or not rt:
				c = c.darkened(shade)
		out[p] = c
	if outline.a > 0.0:
		for p in _part:
			for d in N4:
				var q: Vector2i = p + d
				if not _part.has(q):
					set_px(q.x, q.y, outline)
	for p in out:
		set_px(p.x, p.y, out[p])
	_part.clear()

func opaque_count() -> int:
	var n := 0
	for c in buf:
		if c.a > 0.5:
			n += 1
	return n

func to_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(w * h * 4)
	for i in w * h:
		var c: Color = buf[i]
		bytes[i * 4] = c.r8
		bytes[i * 4 + 1] = c.g8
		bytes[i * 4 + 2] = c.b8
		bytes[i * 4 + 3] = c.a8
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
