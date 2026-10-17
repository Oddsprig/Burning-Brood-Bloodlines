class_name ItemIcon
extends RefCounted
## Small coloured 2D icons for the company's things, drawn in code (art/pixel_canvas.gd) on a 32x32 logical grid at 64x64 native detail:
## one shape per item type (from the template's sprite, slot or weapon skill), tinted by the item's real
## material colour (data/materials.json "color"), with gold pips for quality (one per level, five =
## masterful). Metals keep their own look: steel and bronze carry a bright glint, tin is dull and matte,
## iron dark. Food, drink, goods, arrows and coin have their own icons in their own colours.
## Textures are cached by shape|colour key|quality, so a long list draws each distinct look once.

const SIZE := 64
const LOGICAL_SIZE := 32
const RASTER_SCALE := 2
const GOLD := Color("#f2c84b")
const WOOD := Color("#7a5230")
const GRIP := Color("#4a3020")
const CLEAR := Color(0, 0, 0, 0)

const WEAPON_SHAPES := ["sword", "sabre", "knife", "axe", "greataxe", "cleaver", "mace", "club", "maul", "spear", "glaive", "sickle"]
const SKILL_SHAPES := {"sword": "sword", "axe": "axe", "mace": "mace", "hammer": "maul", "spear": "spear", "polearm": "glaive", "dagger": "knife"}
const BOW_SHAPES := ["bow", "longbow", "recurve"]
const SHIELD_SHAPES := ["round", "kite", "slab", "buckler"]
const HELM_SHAPES := {"nasal": "helm_nasal", "coif": "helm_coif", "spangen": "helm_spangen", "skullcap": "helm_cap", "pot": "helm_pot",
	"crescent": "helm_crescent", "closed": "helm_closed"}
const BODY_SHAPES := {"mail": "mail", "byrnie": "mail", "scale": "scale", "lamellar": "lamellar", "scrap": "scrap"}
## Colours of things that are not gear (food, drink, goods by kind).
const THING_COLORS := {"meal": "#c8954a", "grain": "#d8b45a", "fruit": "#b8402c", "meat": "#a8463a", "fresh_meat": "#b84a3e",
	"beer": "#d89a2c", "wine": "#7a1f3a", "milk": "#eeeadc", "coin": "#b08d57", "wood": "#7a5230", "staves": "#8a6238",
	"staves_green": "#6f7a3a", "stone": "#8a8a84", "linen": "#d8ccb0", "wool": "#e4ddcc", "wool_cloth": "#8a7aa0", "flax": "#c8c08a",
	"hides": "#8a5a3a", "leather": "#6b4a2b", "clothing": "#5a7a9a", "blankets": "#9a5a4a", "tools": "#6e6e70", "furniture": "#8a5a30",
	"jewelry": "#e8c860", "salt": "#f2f0ea", "candles": "#efe2b0", "wax": "#e8cf7a", "tallow": "#e6dcc0", "bones": "#e8e0cc",
	"fodder": "#b0a050", "remedy": "#5a9a6a", "horn": "#c8b890", "sinew": "#b89a7a", "glue": "#c8a860", "feathers": "#e8e8e8",
	"flux": "#c8c8b8", "pig_iron": "#5a5a5c", "goods": "#9a7a50",
	"quartz": "#e8eef4", "amethyst": "#9a5ac8", "garnet": "#8a1830", "topaz": "#f0b030", "sapphire": "#2a50d8", "ruby": "#e01838",
	"emerald": "#18b060"}
const GEM_KINDS := ["quartz", "amethyst", "garnet", "topaz", "sapphire", "ruby", "emerald"]
## v0.014: where a legendary piece's gem is drawn on each shape (the pommel of a sword, the socket of an axe or spear,
## the boss of a shield, the brow of a helm, the breast clasp of body armour ...; matches Item.gem_spot).
const GEM_SPOTS := {"hammer": Vector2i(22, 10), "dirk": Vector2i(5, 27), "mattock": Vector2i(22, 10), "scale": Vector2i(16, 8), "sword": Vector2i(5, 27), "sabre": Vector2i(5, 27), "knife": Vector2i(5, 27), "axe": Vector2i(20, 13), "dwarf_axe": Vector2i(20, 12),
	"greataxe": Vector2i(20, 12), "cleaver": Vector2i(19, 9), "sickle": Vector2i(22, 6), "mace": Vector2i(22, 10), "club": Vector2i(20, 12),
	"maul": Vector2i(22, 10), "spear": Vector2i(21, 12), "spear_boar": Vector2i(21, 12), "spear_winged": Vector2i(21, 12), "spear_short": Vector2i(20, 14), "lance": Vector2i(22, 11), "glaive": Vector2i(13, 18), "bow": Vector2i(21, 16), "longbow": Vector2i(21, 16),
	"recurve": Vector2i(21, 16), "shield_round": Vector2i(16, 16), "shield_buckler": Vector2i(16, 16), "shield_kite": Vector2i(16, 10),
	"shield_slab": Vector2i(16, 16), "helm_nasal": Vector2i(16, 18), "helm_cap": Vector2i(16, 18), "helm_spangen": Vector2i(16, 18),
	"helm_pot": Vector2i(16, 18), "helm_closed": Vector2i(16, 18), "helm_crescent": Vector2i(16, 18), "helm_coif": Vector2i(16, 8), "mail": Vector2i(16, 8),
	"lamellar": Vector2i(16, 8), "scrap": Vector2i(16, 8), "tunic": Vector2i(16, 8), "gambeson": Vector2i(16, 8),
	"greaves": Vector2i(9, 8), "bracers": Vector2i(9, 14), "shoes": Vector2i(11, 12), "trousers": Vector2i(16, 6)}

static var _cache: Dictionary = {}

# ------------------------------------------------------------------ public
## The icon of one item (its template's shape, its material, its quality). v0.014: a legendary piece shows its gem
## where it is set and a sixth pip in the gem's colour.
static func for_item(it: Item) -> Texture2D:
	if it.is_legend():
		var shape := shape_of(it.tid)
		var gem := String(it.legend.get("gem", "ruby"))
		var ck := "%s|%s|L|%s" % [shape, it.material, gem]
		if not _cache.has(ck):
			_cache[ck] = ImageTexture.create_from_image(legend_image(shape, it.material, gem))
		return _cache[ck]
	return for_template(it.tid, it.material, it.quality)

## The legendary look: the masterwork icon, the gem set at its spot, a sixth pip in the gem's colour.
static func legend_image(shape: String, key: String, gem: String) -> Image:
	var img := image(shape, key, 5)
	var gc := Color(String(THING_COLORS.get(gem, "#e01838")))
	draw_gem(img, GEM_SPOTS.get(shape, Vector2i(16, 16)) * RASTER_SCALE, gc, 2 * RASTER_SCALE)
	draw_gem(img, Vector2i(22, 1) * RASTER_SCALE, gc, RASTER_SCALE)
	return img

## A cut stone: a dark rim, the gem's colour, a white glint at the top left. r = 2 (on an item) or 1 (the pip).
static func draw_gem(img: Image, c: Vector2i, col: Color, r: int = 2) -> void:
	for dy in range(-r - 1, r + 2):
		for dx in range(-r - 1, r + 2):
			var p := c + Vector2i(dx, dy)
			if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
				continue
			var d := absi(dx) + absi(dy)
			if d <= r:
				img.set_pixelv(p, col)
			elif d == r + 1:
				img.set_pixelv(p, col.darkened(0.7))
	var g := c + Vector2i(-maxi(0, r - 1), -maxi(0, r - 1))
	if g.x >= 0 and g.y >= 0:
		img.set_pixelv(g, Color(1, 1, 1, 1))

static func for_template(tid: String, mat: String, q: int = 0) -> Texture2D:
	return _tex(shape_of(tid), mat, clampi(q, 0, 5))

## Icons for things that are not gear: "meal", "beer", "wine", "coin", a goods id (data/economy.json) or an
## arrow id (data/bows.json arrows).
static func for_thing(kind: String) -> Texture2D:
	if DB.arrows.has(kind):
		return _tex("arrow", String(DB.arrows[kind].get("tip", "wood")), 0)
	return _tex(thing_shape(kind), "#" + kind, 0)

## Every distinct look drawn so far (tests, memory).
static func cache_size() -> int:
	return _cache.size()

## The shape of a weapon, bow or armour template.
static func shape_of(tid: String) -> String:
	match tid:
		"war_hammer": return "hammer"
		"leaf_dirk": return "dirk"
		"dwarf_mattock": return "mattock"
		"dwarf_war_axe": return "dwarf_axe"
		"short_spear": return "spear_short"
		"boar_spear": return "spear_boar"
		"winged_spear": return "spear_winged"
		"steppe_lance": return "lance"
	if DB.is_bow(tid):
		var bs := String(DB.bows[tid].get("sprite", "bow"))
		return bs if bs in BOW_SHAPES else "bow"
	var t := DB.template(tid)
	var sp := String(t.get("sprite", ""))
	if DB.is_weapon(tid):
		if sp in WEAPON_SHAPES:
			return sp
		return String(SKILL_SHAPES.get(String(t.get("skill", "")), "sword"))
	match String(t.get("slot", "")):
		"shield": return "shield_" + (sp if sp in SHIELD_SHAPES else "round")
		"helm": return String(HELM_SHAPES.get(sp, "helm_cap"))
		"body": return String(BODY_SHAPES.get(sp, "mail"))
		"legs": return "greaves"
		"hands": return "bracers"
		"feet": return "shoes"
		"clothing": return "gambeson" if bool(t.get("padded", false)) else "tunic"
		"legs_under": return "trousers"
	return "bundle"

static func thing_shape(kind: String) -> String:
	if kind in ["meal", "grain"]: return "loaf"
	if kind == "beer": return "mug"
	if kind in ["wine", "milk"]: return "jug"
	if kind == "coin": return "coins"
	if kind in ["meat", "fresh_meat"]: return "ham"
	if kind == "fruit": return "apple"
	if kind.ends_with("_bars") or kind == "pig_iron": return "ingot"
	if kind.ends_with("_ore") or kind in ["stone", "flux", "salt"]: return "ore"
	if kind.begins_with("scrap_"): return "scrap_pile"
	if kind.begins_with("heads_"): return "heads"
	if kind.begins_with("arrow_"): return "arrow"
	if kind in ["wood", "staves", "staves_green", "furniture"]: return "logs"
	if kind in ["linen", "wool_cloth", "clothing", "blankets", "flax", "wool"]: return "bolt"
	if kind in ["hides", "leather"]: return "hide"
	if kind == "remedy": return "jug"
	if GEM_KINDS.has(kind): return "gem"   # v0.014: cut stones
	return "sack"

## The colour for a material id or a "#thing" key.
static func color_of(key: String) -> Color:
	if key.begins_with("#"):
		var k := key.substr(1)
		if k.ends_with("_bars") or k.ends_with("_ore") or k.begins_with("scrap_") or k.begins_with("heads_") or k.begins_with("arrow_"):
			for m in ["copper", "tin", "bronze", "iron", "steel", "wood"]:
				if k.contains(m):
					return Color(String(DB.materials[m].get("color", "#888888")))
		return Color(String(THING_COLORS.get(k, THING_COLORS["goods"])))
	var md: Dictionary = DB.materials.get(key, {})
	return Color(String(md.get("color", "#9a8a70")))

# ------------------------------------------------------------------ drawing
static func _tex(shape: String, key: String, q: int) -> Texture2D:
	var ck := "%s|%s|%d" % [shape, key, q]
	if _cache.has(ck):
		return _cache[ck]
	var tex := ImageTexture.create_from_image(image(shape, key, q))
	_cache[ck] = tex
	return tex

static func _ol(c: Color) -> Color:
	return c.darkened(0.72).lerp(Color("#140a10"), 0.45)

## Metal looks: shine (top-edge glint) and edge shading per material.
static func _look(key: String) -> Array:
	match key:
		"steel": return [Color("#f4f8ff"), 0.18]
		"bronze": return [Color("#ffe2a0"), 0.16]
		"copper": return [Color("#ffc08a"), 0.16]
		"iron": return [Color("#b8b8bc"), 0.14]
		"tin": return [CLEAR, 0.05]   # soft and dull: no glint
	return [CLEAR, 0.12]

static func image(shape: String, key: String, q: int) -> Image:
	var cv := PixelCanvas.new(SIZE, SIZE)
	cv.set_frame(Vector2.ZERO, float(RASTER_SCALE), 0.0)
	if ItemIconArt.draw(cv, shape, key, q):
		_quality_pips(cv, q)
		return cv.to_image()
	var c := color_of(key)
	var look := _look(key)
	var sh: Color = look[0]
	var sd: float = look[1]
	var o := _ol(c)
	match shape:
		"sword", "sabre", "knife":
			var tip := Vector2(27, 5) if shape != "knife" else Vector2(23, 9)
			_part(cv, o, 0.1, CLEAR, func(): cv.capsule(Vector2(6, 26), Vector2(9, 23), 1.3, GRIP))
			if shape == "sabre":
				_part(cv, o, sd, sh, func():
					cv.capsule(Vector2(10, 22), Vector2(17, 13), 1.8, c)
					cv.capsule(Vector2(17, 13), Vector2(23, 8), 1.6, c)
					cv.capsule(Vector2(23, 8), Vector2(28, 6), 1.2, c))
			else:
				_part(cv, o, sd, sh, func():
					cv.capsule(Vector2(10, 22), tip, 1.7 if shape == "sword" else 2.0, c)
					cv.capsule(tip - (tip - Vector2(10, 22)).normalized() * 2.0, tip, 0.9, c))
			_part(cv, o, 0.12, CLEAR, func():
				cv.capsule(Vector2(6, 19), Vector2(13, 26), 1.3, c.darkened(0.15))
				cv.ellipse(Vector2(5, 27.5), 1.8, 1.8, c.darkened(0.1)))
		"axe", "greataxe", "cleaver", "sickle":
			var top := Vector2(22, 5) if shape != "greataxe" else Vector2(23, 4)
			_part(cv, o.darkened(0.2), 0.1, CLEAR, func(): cv.capsule(Vector2(7, 29), top, 1.2, WOOD))
			var heads := {"axe": [Vector2(18, 6), Vector2(26, 2), Vector2(29, 9), Vector2(26, 15), Vector2(20, 11)],
				"greataxe": [Vector2(18, 7), Vector2(25, 0), Vector2(31, 6), Vector2(30, 15), Vector2(26, 18), Vector2(20, 12)],
				"cleaver": [Vector2(17, 4), Vector2(27, 3), Vector2(29, 14), Vector2(19, 15)]}
			if heads.has(shape):
				var hp := PackedVector2Array(heads[shape])
				_part(cv, o, sd, sh, func(): cv.poly(hp, c))
			else:   # sickle: a hooked blade
				_part(cv, o, sd, sh, func():
					cv.capsule(Vector2(22, 5), Vector2(27, 4), 1.4, c)
					cv.capsule(Vector2(27, 4), Vector2(29, 9), 1.3, c)
					cv.capsule(Vector2(29, 9), Vector2(26, 14), 1.1, c))
		"mace", "club", "maul":
			if shape == "club":
				_part(cv, o, 0.14, CLEAR, func():
					cv.capsule(Vector2(7, 27), Vector2(20, 12), 1.6, WOOD)
					cv.capsule(Vector2(17, 15), Vector2(23, 9), 4.2, WOOD.lightened(0.05)))
				_part(cv, o, sd, sh, func():
					for p in [Vector2(19, 9), Vector2(24, 13), Vector2(22, 6), Vector2(27, 9), Vector2(17, 13)]:
						cv.ellipse(p, 1.4, 1.4, c))
			else:
				_part(cv, o.darkened(0.2), 0.1, CLEAR, func(): cv.capsule(Vector2(6, 28), Vector2(20, 12), 1.3, WOOD))
				if shape == "maul":
					_part(cv, o, sd, sh, func(): cv.poly(PackedVector2Array([Vector2(14, 8), Vector2(22, 2), Vector2(30, 10), Vector2(22, 18)]), c))
				else:
					_part(cv, o, sd, sh, func():
						cv.ellipse(Vector2(22, 10), 5.5, 5.5, c)
						for p in [Vector2(22, 3), Vector2(29, 10), Vector2(16, 6), Vector2(27, 4)]:
							cv.ellipse(p, 1.6, 1.6, c))
		"spear", "glaive":
			_part(cv, o.darkened(0.2), 0.1, CLEAR, func(): cv.capsule(Vector2(4, 30), Vector2(22, 10), 1.1, WOOD))
			_part(cv, o, sd, sh, func():
				if shape == "spear":
					cv.poly(PackedVector2Array([Vector2(20, 10), Vector2(25, 4), Vector2(30, 1), Vector2(28, 7), Vector2(23, 13)]), c)
				else:
					cv.poly(PackedVector2Array([Vector2(19, 12), Vector2(20, 5), Vector2(25, 1), Vector2(30, 1), Vector2(28, 8), Vector2(23, 14)]), c))
		"bow", "longbow", "recurve":
			var tall := 13.5 if shape == "longbow" else 11.0
			_part(cv, o, 0.12, CLEAR, func():
				var pts := []
				for i in 13:
					var a := lerpf(-1.25, 1.25, i / 12.0)
					pts.append(Vector2(12 + cos(a) * 9.0, 16 + sin(a) * tall))
				for i in 12:
					cv.capsule(pts[i], pts[i + 1], 1.4 if absi(i - 6) < 3 else 1.0, c)
				if shape == "recurve":
					cv.capsule(pts[0], pts[0] + Vector2(4, -1), 0.9, c)
					cv.capsule(pts[12], pts[12] + Vector2(4, 1), 0.9, c))
			cv.line1(Vector2(15, 16 - tall * 0.95), Vector2(15, 16 + tall * 0.95), Color("#ece4cc"))
		"shield_round", "shield_buckler":
			var r := 13.0 if shape == "shield_round" else 9.0
			_part(cv, o, sd, sh, func(): cv.ellipse(Vector2(16, 16), r, r, c))
			_part(cv, CLEAR, 0.0, CLEAR, func(): cv.ellipse(Vector2(16, 16), r - 2.5, r - 2.5, c.darkened(0.12)))
			_part(cv, o, sd, sh, func(): cv.ellipse(Vector2(16, 16), 3.2, 3.2, c.lightened(0.15)))
		"shield_kite":
			_part(cv, o, sd, sh, func(): cv.poly(PackedVector2Array([Vector2(5, 4), Vector2(16, 1), Vector2(27, 4), Vector2(25, 16), Vector2(16, 31), Vector2(7, 16)]), c))
			_part(cv, CLEAR, 0.0, CLEAR, func():
				cv.rect(Rect2(15, 4, 2, 22), c.darkened(0.2))
				cv.rect(Rect2(8, 9, 16, 2), c.darkened(0.2)))
		"shield_slab":
			_part(cv, o, sd, sh, func(): cv.rect(Rect2(6, 2, 20, 28), c))
			_part(cv, CLEAR, 0.0, CLEAR, func():
				for y in [8, 16, 24]:
					cv.rect(Rect2(7, y, 18, 1), c.darkened(0.25)))
		"helm_nasal", "helm_cap", "helm_spangen", "helm_pot", "helm_crescent", "helm_coif":
			if shape == "helm_coif":
				_part(cv, o, sd, sh, func():
					cv.ellipse(Vector2(16, 15), 11, 12, c)
					cv.rect(Rect2(5, 15, 22, 14), c)
					cv.erase_rect(Rect2(11, 12, 10, 11)))
				_part(cv, CLEAR, 0.0, CLEAR, func():
					for y in range(4, 28, 3):
						for x in range(6 + (y % 2), 26, 3):
							if not (x >= 11 and x < 21 and y >= 12 and y < 23):
								cv.dot(Vector2(x, y), c.darkened(0.22)))
			else:
				_part(cv, o, sd, sh, func():
					cv.ellipse(Vector2(16, 17), 11, 11, c)
					cv.erase_rect(Rect2(0, 18, 32, 14))
					cv.rect(Rect2(5, 17, 22, 4), c))
				match shape:
					"helm_nasal":
						_part(cv, o, sd, sh, func(): cv.rect(Rect2(15, 19, 3, 9), c))
					"helm_spangen":
						_part(cv, CLEAR, 0.0, CLEAR, func():
							for x in [10, 16, 22]:
								cv.rect(Rect2(x, 7, 1, 11), c.darkened(0.25)))
						_part(cv, o, sd, sh, func(): cv.ellipse(Vector2(16, 5), 1.6, 1.6, c))
					"helm_pot":
						_part(cv, o, sd, sh, func(): cv.rect(Rect2(2, 19, 28, 3), c))
					"helm_crescent":
						_part(cv, o, sd, sh, func():
							cv.capsule(Vector2(10, 4), Vector2(16, 7), 1.3, c)
							cv.capsule(Vector2(22, 4), Vector2(16, 7), 1.3, c))
		"mail", "lamellar", "scrap", "tunic", "gambeson":
			var body := PackedVector2Array([Vector2(9, 3), Vector2(13, 5), Vector2(19, 5), Vector2(23, 3), Vector2(30, 9), Vector2(27, 14),
				Vector2(24, 12), Vector2(24, 29), Vector2(8, 29), Vector2(8, 12), Vector2(5, 14), Vector2(2, 9)])
			var cc := c
			_part(cv, o, sd, sh, func(): cv.poly(body, cc))
			cv.begin()
			match shape:
				"mail":
					for y in range(6, 29, 2):
						for x in range(4 + (1 if y % 4 == 2 else 0), 29, 2):
							if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), body):
								cv.dot(Vector2(x, y), cc.darkened(0.25))
				"lamellar", "scrap":
					for y in range(9, 29, 4 if shape == "lamellar" else 5):
						cv.rect(Rect2(8, y, 16, 1), cc.darkened(0.3))
					if shape == "scrap":
						cv.rect(Rect2(15, 12, 1, 16), cc.darkened(0.3))
				"gambeson":
					for x in range(11, 23, 4):
						cv.rect(Rect2(x, 8, 1, 20), cc.darkened(0.18))
				_:
					cv.rect(Rect2(8, 22, 16, 2), cc.darkened(0.2))
			cv.end(CLEAR, 0.0)
		"greaves":
			_part(cv, o, sd, sh, func():
				cv.poly(PackedVector2Array([Vector2(5, 3), Vector2(13, 3), Vector2(13, 26), Vector2(9, 30), Vector2(6, 26)]), c)
				cv.poly(PackedVector2Array([Vector2(19, 3), Vector2(27, 3), Vector2(26, 26), Vector2(23, 30), Vector2(19, 26)]), c))
		"bracers":
			_part(cv, o, sd, sh, func():
				cv.capsule(Vector2(5, 26), Vector2(13, 6), 3.8, c)
				cv.capsule(Vector2(19, 26), Vector2(27, 6), 3.8, c))
			_part(cv, CLEAR, 0.0, CLEAR, func():
				cv.capsule(Vector2(5, 20), Vector2(10, 21), 0.5, c.darkened(0.3))
				cv.capsule(Vector2(19, 20), Vector2(24, 21), 0.5, c.darkened(0.3)))
		"shoes":
			_part(cv, o, sd, sh, func():
				cv.poly(PackedVector2Array([Vector2(8, 6), Vector2(16, 6), Vector2(16, 20), Vector2(28, 23), Vector2(28, 28), Vector2(6, 28), Vector2(7, 18)]), c))
		"trousers":
			_part(cv, o, sd, sh, func():
				cv.poly(PackedVector2Array([Vector2(7, 3), Vector2(25, 3), Vector2(27, 29), Vector2(19, 29), Vector2(16, 13), Vector2(13, 29), Vector2(5, 29)]), c))
		"loaf":
			_part(cv, o, 0.14, Color("#f0d090"), func(): cv.ellipse(Vector2(16, 18), 13, 8, c))
			_part(cv, CLEAR, 0.0, CLEAR, func():
				for x in [10, 16, 22]:
					cv.capsule(Vector2(x - 2, 14), Vector2(x + 2, 19), 0.5, c.darkened(0.25)))
		"mug":
			_part(cv, o, 0.12, CLEAR, func():
				cv.capsule(Vector2(23, 12), Vector2(27, 16), 1.0, Color("#8a6038"))
				cv.capsule(Vector2(27, 16), Vector2(23, 22), 1.0, Color("#8a6038")))
			_part(cv, o, 0.12, CLEAR, func(): cv.rect(Rect2(8, 9, 15, 20), Color("#8a6038")))
			_part(cv, o, 0.08, CLEAR, func():
				cv.rect(Rect2(9, 12, 13, 16), c)
				cv.ellipse(Vector2(15.5, 9), 8, 3.2, Color("#f4ecd8")))
		"jug":
			_part(cv, o, 0.12, Color(1, 1, 1, 0.5), func():
				cv.ellipse(Vector2(16, 20), 9, 9, c)
				cv.rect(Rect2(13, 3, 6, 10), c))
			_part(cv, o, 0.1, CLEAR, func(): cv.rect(Rect2(12, 2, 8, 3), Color("#8a6038")))
		"coins":
			for i in 3:
				var yy := 24 - i * 5
				_part(cv, _ol(c), 0.14, Color("#ffe2a0"), func(): cv.ellipse(Vector2(15 + i, yy), 10, 4, c))
		"ham":
			_part(cv, o, 0.12, CLEAR, func():
				cv.ellipse(Vector2(14, 17), 10, 9, c)
				cv.capsule(Vector2(20, 12), Vector2(28, 5), 1.6, Color("#f0e8d8")))
		"apple":
			_part(cv, o, 0.14, Color(1, 1, 1, 0.6), func(): cv.ellipse(Vector2(16, 18), 10, 10, c))
			_part(cv, _ol(Color("#4a8a3a")), 0.1, CLEAR, func():
				cv.capsule(Vector2(16, 9), Vector2(17, 5), 0.8, Color("#5a3a20"))
				cv.ellipse(Vector2(21, 6), 3, 1.8, Color("#4a8a3a")))
		"ingot":
			_part(cv, o, sd + 0.05, Color(1, 1, 1, 0.6), func():
				cv.poly(PackedVector2Array([Vector2(4, 24), Vector2(8, 13), Vector2(26, 13), Vector2(29, 24)]), c))
			_part(cv, o, sd, CLEAR, func():
				cv.poly(PackedVector2Array([Vector2(7, 14), Vector2(10, 7), Vector2(24, 7), Vector2(26, 14)]), c.lightened(0.08)))
		"ore", "scrap_pile":
			for p in [[Vector2(11, 20), 7.0], [Vector2(21, 21), 6.0], [Vector2(16, 12), 5.5]]:
				_part(cv, o, 0.16, CLEAR, func(): cv.ellipse(p[0], p[1], p[1] * 0.8, c if shape == "scrap_pile" else Color("#7a746a")))
			if shape == "ore":
				_part(cv, CLEAR, 0.0, CLEAR, func():
					for p in [Vector2(9, 19), Vector2(13, 22), Vector2(20, 20), Vector2(23, 23), Vector2(16, 11)]:
						cv.rect(Rect2(p, Vector2(2, 2)), c))
		"heads":
			for i in 3:
				_part(cv, o, sd, sh, func(): cv.poly(PackedVector2Array([Vector2(5 + i * 8, 26), Vector2(9 + i * 8, 8), Vector2(13 + i * 8, 26)]), c))
		"arrow":
			_part(cv, _ol(WOOD), 0.1, CLEAR, func(): cv.capsule(Vector2(5, 27), Vector2(23, 9), 0.9, Color("#a07848")))
			_part(cv, _ol(Color("#e8e8e8")), 0.1, CLEAR, func():
				cv.poly(PackedVector2Array([Vector2(3, 24), Vector2(8, 22), Vector2(6, 29)]), Color("#e8e8e8")))
			_part(cv, o, sd, sh, func(): cv.poly(PackedVector2Array([Vector2(21, 7), Vector2(29, 3), Vector2(25, 11)]), c))
		"logs":
			for i in 3:
				var yy := 22 - i * 7
				_part(cv, _ol(c), 0.14, CLEAR, func(): cv.capsule(Vector2(6 + i * 2, yy), Vector2(26 - i * 2, yy), 3.4, c))
		"bolt":
			_part(cv, o, 0.12, CLEAR, func(): cv.rect(Rect2(5, 8, 22, 16), c))
			_part(cv, CLEAR, 0.0, CLEAR, func():
				for x in range(8, 26, 4):
					cv.rect(Rect2(x, 8, 1, 16), c.darkened(0.18)))
		"hide":
			_part(cv, o, 0.12, CLEAR, func():
				cv.poly(PackedVector2Array([Vector2(4, 6), Vector2(11, 9), Vector2(21, 9), Vector2(28, 5), Vector2(26, 16), Vector2(29, 27),
					Vector2(20, 24), Vector2(12, 24), Vector2(3, 27), Vector2(6, 16)]), c))
		"gem":   # v0.014: a cut stone (its facets in lighter and darker tints)
			_part(cv, o, 0.1, Color(1, 1, 1, 0.8), func():
				cv.poly(PackedVector2Array([Vector2(9, 10), Vector2(23, 10), Vector2(28, 15), Vector2(16, 28), Vector2(4, 15)]), c))
			_part(cv, CLEAR, 0.0, CLEAR, func():
				cv.poly(PackedVector2Array([Vector2(11, 11), Vector2(21, 11), Vector2(19, 15), Vector2(13, 15)]), c.lightened(0.35))
				cv.poly(PackedVector2Array([Vector2(16, 26), Vector2(13, 16), Vector2(19, 16)]), c.darkened(0.25)))
		_:   # "sack" and anything unknown: a tied sack
			_part(cv, o, 0.12, CLEAR, func():
				cv.ellipse(Vector2(16, 20), 11, 10, c)
				cv.poly(PackedVector2Array([Vector2(11, 11), Vector2(16, 4), Vector2(21, 11)]), c))
			_part(cv, CLEAR, 0.0, CLEAR, func(): cv.rect(Rect2(12, 10, 8, 2), c.darkened(0.4)))
	_quality_pips(cv, q)
	return cv.to_image()

## One shaded, outlined part.
static func _part(cv: PixelCanvas, outline: Color, shade: float, shine: Color, draw: Callable) -> void:
	cv.begin()
	draw.call()
	cv.end(outline, shade, shine)

## Quality: a gold pip per level along the top-left corner (5 = masterful).
static func _quality_pips(cv: PixelCanvas, q: int) -> void:
	for i in q:
		var x := 1 + i * 4
		for d in [Vector2i(-1, 0), Vector2i(2, 0), Vector2i(0, -1), Vector2i(0, 2), Vector2i(-1, 1), Vector2i(2, 1), Vector2i(1, -1), Vector2i(1, 2)]:
			cv.rect(Rect2(Vector2(x + d.x, 1 + d.y), Vector2.ONE), Color("#3a2410"))
		for dy in 2:
			for dx in 2:
				cv.rect(Rect2(Vector2(x + dx, 1 + dy), Vector2.ONE), GOLD)
