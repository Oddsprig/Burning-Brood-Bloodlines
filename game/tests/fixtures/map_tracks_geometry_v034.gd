extends RefCounted
const COL_MEN := Color(1.0, 0.94, 0.8)
const COL_BEAST := Color(0.85, 0.72, 0.55)
const COL_MARK := Color(1.0, 0.8, 0.15)
func geometry(st: Dictionary, day: float, tgt: String) -> Array:
	# all chevrons go out in two batched calls (plain, and the marked trail drawn thicker)
	var pts := PackedVector2Array(); var cols := PackedColorArray()
	var mpts := PackedVector2Array(); var mcols := PackedColorArray()
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
					# a chevron pointing the way they went, plus a short footprint tick behind it
					var tip := p + d * 4.0
					var seg := [tip, p - d * 2.0 + s * 4.0, tip, p - d * 2.0 - s * 4.0, p - d * 6.0, p - d * 8.0]
					if marked:   # (packed arrays copy on assignment, so no alias variable here)
						mpts.append_array(seg); mcols.append_array([col, col, col])
					else:
						pts.append_array(seg); cols.append_array([col, col, col])
			i += Tracks.STRIDE
	return [pts, cols, mpts, mcols]
