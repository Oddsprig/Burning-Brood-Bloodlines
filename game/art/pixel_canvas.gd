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

func shaded() -> ShadedLayer:
	return ShadedLayer.new(self)

## Build a 6-stop Spirewing-style 2.5D colour ramp (deep shadow -> shadow -> mid-dark -> mid -> lit -> specular highlight).
static func make_ramp(base: Color, shine_tint: Color = Color(1.0, 0.96, 0.88), contrast: float = 1.0) -> Array[Color]:
	var cool := Color(0.06, 0.05, 0.12, 1.0)
	var s0 := base.darkened(clampf(0.56 * contrast, 0.15, 0.82)).lerp(cool, 0.28)
	var s1 := base.darkened(clampf(0.36 * contrast, 0.10, 0.65)).lerp(cool, 0.16)
	var s2 := base.darkened(clampf(0.16 * contrast, 0.05, 0.42)).lerp(cool, 0.06)
	var s3 := base
	var s4 := base.lightened(clampf(0.18 * contrast, 0.05, 0.48)).lerp(shine_tint, 0.14)
	var s5 := base.lightened(clampf(0.38 * contrast, 0.10, 0.72)).lerp(shine_tint, 0.34)
	s0.a = 1.0; s1.a = 1.0; s2.a = 1.0; s3.a = 1.0; s4.a = 1.0; s5.a = 1.0
	return [s0, s1, s2, s3, s4, s5]


## Shared 2.5D heightfield & surface-normal rasteriser (light from top-left, 6-stop shade ramp, clean outline).
class ShadedLayer extends RefCounted:
	const LIGHT := Vector3(-0.56, -0.74, 0.37)
	const HALF_VEC := Vector3(-0.32, -0.45, 0.83)
	const BAYER4: Array[float] = [-0.375, 0.125, -0.125, 0.375]

	var cv: PixelCanvas
	var w: int
	var h: int
	var fill := PackedByteArray()
	var z_buf := PackedFloat32Array()
	var nx_buf := PackedFloat32Array()
	var ny_buf := PackedFloat32Array()
	var nz_buf := PackedFloat32Array()
	var ramps: Array = []
	var specs := PackedFloat32Array()
	var dithers := PackedFloat32Array()
	var min_x: int = 999999
	var min_y: int = 999999
	var max_x: int = -1
	var max_y: int = -1

	func _init(canvas: PixelCanvas) -> void:
		cv = canvas
		w = canvas.w
		h = canvas.h
		var n := w * h
		fill.resize(n)
		fill.fill(0)
		z_buf.resize(n)
		z_buf.fill(-1e9)
		nx_buf.resize(n)
		ny_buf.resize(n)
		nz_buf.resize(n)

	func add_ramp(ramp: Array[Color], specular: float = 0.12, dither: float = 0.06) -> int:
		ramps.append(ramp)
		specs.append(specular)
		dithers.append(dither)
		return ramps.size()

	func add_color(base: Color, specular: float = 0.12, contrast: float = 1.0, shine_tint: Color = Color(1.0, 0.96, 0.88), dither: float = 0.06) -> int:
		return add_ramp(PixelCanvas.make_ramp(base, shine_tint, contrast), specular, dither)

	func _write(x: int, y: int, z: float, n: Vector3, mat_id: int) -> void:
		if x < 0 or y < 0 or x >= w or y >= h:
			return
		var idx := y * w + x
		if z >= z_buf[idx]:
			fill[idx] = mat_id
			z_buf[idx] = z
			var nn := n.normalized()
			nx_buf[idx] = nn.x
			ny_buf[idx] = nn.y
			nz_buf[idx] = nn.z
			if x < min_x: min_x = x
			if x > max_x: max_x = x
			if y < min_y: min_y = y
			if y > max_y: max_y = y

	func capsule(a: Vector2, b: Vector2, ra: float, rb: float, mat_id: int, z_bias: float = 0.0, z_scale: float = 1.0) -> void:
		var ma := cv.xf * a
		var mb := cv.xf * b
		var pra := maxf(0.45, ra * cv.k)
		var prb := maxf(0.45, rb * cv.k)
		var rmax := maxf(pra, prb)
		var x0 := maxi(0, floori(minf(ma.x, mb.x) - rmax - 1.0))
		var x1 := mini(w - 1, ceili(maxf(ma.x, mb.x) + rmax + 1.0))
		var y0 := maxi(0, floori(minf(ma.y, mb.y) - rmax - 1.0))
		var y1 := mini(h - 1, ceili(maxf(ma.y, mb.y) + rmax + 1.0))
		var ab := mb - ma
		var ab_len2 := ab.length_squared()
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var p := Vector2(float(x) + 0.5, float(y) + 0.5)
				var t := 0.0
				if ab_len2 > 0.0001:
					t = clampf((p - ma).dot(ab) / ab_len2, 0.0, 1.0)
				var closest := ma + ab * t
				var r := lerpf(pra, prb, t)
				if r <= 0.05:
					continue
				var d := p - closest
				var dist := d.length()
				if dist <= r:
					var u := clampf(dist / r, 0.0, 1.0)
					var hz := sqrt(maxf(0.0, 1.0 - u * u))
					var lr := maxf(0.2, lerpf(ra, rb, t))
					var z := z_bias + hz * lr * 0.5 * z_scale
					var n := Vector3(d.x / r, d.y / r, maxf(0.18, hz))
					_write(x, y, z, n, mat_id)

	func chain(pts: Array, radii: Array, mat_id: int, z_bias: float = 0.0, z_scale: float = 1.0) -> void:
		for i in range(pts.size() - 1):
			capsule(pts[i], pts[i + 1], float(radii[i]), float(radii[i + 1]), mat_id, z_bias, z_scale)

	func ellipsoid(center: Vector2, rx: float, ry: float, mat_id: int, z_bias: float = 0.0, z_scale: float = 1.0, local_angle: float = 0.0) -> void:
		var mc := cv.xf * center
		var prx := maxf(0.45, rx * cv.k)
		var pry := maxf(0.45, ry * cv.k)
		var rmax := maxf(prx, pry)
		var ang := local_angle + cv.xf.get_rotation()
		var ca := cos(ang)
		var sa := sin(ang)
		var x0 := maxi(0, floori(mc.x - rmax - 1.0))
		var x1 := mini(w - 1, ceili(mc.x + rmax + 1.0))
		var y0 := maxi(0, floori(mc.y - rmax - 1.0))
		var y1 := mini(h - 1, ceili(mc.y + rmax + 1.0))
		var lrz := maxf(0.2, minf(rx, ry))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var dp := Vector2(float(x) + 0.5, float(y) + 0.5) - mc
				var lx := dp.x * ca + dp.y * sa
				var ly := -dp.x * sa + dp.y * ca
				var ux := lx / prx
				var uy := ly / pry
				var u2 := ux * ux + uy * uy
				if u2 <= 1.0:
					var hz := sqrt(maxf(0.0, 1.0 - u2))
					var wx := ux * ca - uy * sa
					var wy := ux * sa + uy * ca
					var z := z_bias + hz * lrz * 0.5 * z_scale
					_write(x, y, z, Vector3(wx, wy, maxf(0.18, hz)), mat_id)

	func poly(pts: PackedVector2Array, mat_id: int, z_bias: float = 0.0, dome: float = 2.5, flat_n: Vector3 = Vector3(0.0, 0.0, 1.0)) -> void:
		if pts.size() < 3:
			return
		var m := PackedVector2Array()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var center := Vector2.ZERO
		for p in pts:
			var q := cv.xf * p
			m.append(q)
			lo = lo.min(q)
			hi = hi.max(q)
			center += q
		center /= float(m.size())
		var pdome := maxf(0.6, dome * cv.k)
		var x0 := maxi(0, floori(lo.x - 1.0))
		var x1 := mini(w - 1, ceili(hi.x + 1.0))
		var y0 := maxi(0, floori(lo.y - 1.0))
		var y1 := mini(h - 1, ceili(hi.y + 1.0))
		var fn := flat_n.normalized()
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var p := Vector2(float(x) + 0.5, float(y) + 0.5)
				if not Geometry2D.is_point_in_polygon(p, m):
					continue
				var min_d := 999.0
				for i in m.size():
					var a := m[i]
					var b := m[(i + 1) % m.size()]
					var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
					var dist := p.distance_to(closest)
					if dist < min_d:
						min_d = dist
				var u := clampf(1.0 - min_d / pdome, 0.0, 1.0)
				var hz := sqrt(maxf(0.05, 1.0 - u * u))
				var dir := (p - center)
				var dlen := maxf(1.0, dir.length())
				var n := (Vector3(dir.x / dlen * u * 0.65, dir.y / dlen * u * 0.65, hz) + fn * 0.55).normalized()
				_write(x, y, z_bias + hz * dome * 0.5, n, mat_id)

	func composite(outline: Color = Color(0.05, 0.04, 0.07, 1.0), exterior_outline: bool = true) -> void:
		if max_x < min_x or max_y < min_y:
			return
		var l_dir := LIGHT.normalized()
		var h_dir := HALF_VEC.normalized()
		if exterior_outline and outline.a > 0.0:
			for y in range(min_y, max_y + 1):
				for x in range(min_x, max_x + 1):
					var idx := y * w + x
					var m := fill[idx]
					if m == 0:
						continue
					var rmp: Array = ramps[m - 1]
					var edge_col := outline.lerp(rmp[0] as Color, 0.25)
					edge_col.a = outline.a
					for d in PixelCanvas.N4:
						var nx := x + d.x
						var ny := y + d.y
						if nx >= 0 and ny >= 0 and nx < w and ny < h and fill[ny * w + nx] == 0:
							cv._put(nx, ny, edge_col, Callable())
		for y in range(min_y, max_y + 1):
			for x in range(min_x, max_x + 1):
				var idx := y * w + x
				var m := fill[idx]
				if m == 0:
					continue
				var rmp: Array = ramps[m - 1]
				if not exterior_outline and outline.a > 0.0:
					var is_edge := false
					for d in PixelCanvas.N4:
						var nx := x + d.x
						var ny := y + d.y
						if nx < 0 or ny < 0 or nx >= w or ny >= h or fill[ny * w + nx] == 0:
							is_edge = true
							break
					if is_edge:
						cv._put(x, y, outline.lerp(rmp[0] as Color, 0.22), Callable())
						continue
				var seam_darken := 0.0
				for d in PixelCanvas.N4:
					var nx := x + d.x
					var ny := y + d.y
					if nx >= 0 and ny >= 0 and nx < w and ny < h:
						var nm := fill[ny * w + nx]
						if nm != 0 and nm != m and z_buf[ny * w + nx] > z_buf[idx] + 0.35:
							seam_darken = 0.16
							break
				var n := Vector3(nx_buf[idx], ny_buf[idx], nz_buf[idx])
				var ndotl := n.dot(l_dir)
				var spec := pow(maxf(0.0, n.dot(h_dir)), 10.0) * specs[m - 1]
				var bayer := BAYER4[(x & 1) + ((y & 1) << 1)] * dithers[m - 1]
				var t := clampf((ndotl + 0.68) / 1.52 + spec + bayer - seam_darken, 0.0, 0.999)
				var ci := clampi(int(t * float(rmp.size())), 0, rmp.size() - 1)
				cv._put(x, y, rmp[ci] as Color, Callable())

