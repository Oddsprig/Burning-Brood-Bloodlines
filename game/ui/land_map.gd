class_name LandMap
extends RefCounted
## The town's land map (docs/specs/barge/07-land-map.md part 2-3; addendum A): one square tile per plot record
## (campaign/plots.gd), bright flat sprites drawn in code, drag to pan, pinch / wheel to zoom, Centre. Overlay chips:
## USE, OWNER, STATE, VALUE, FOR SALE, WORKED; a summary strip that follows the overlay (tap a family to show only
## its plots); tap a tile -> the plot card. The town's own buildings are drawn on a slate-blue tile with a gold
## edge in every overlay.
##
## Entry: LandMap.mount(parent, town) builds the whole view inside `parent` (any Control; the town screen's Land &
## Homes tab mounts it there) and returns its root. LandMap.open(host, town) shows it full screen over `host`.
## The map is composed into one image (one blit per tile) when the overlay or the records change; panning and
## zooming only move that one texture.

const TILE := 32
const OVERLAYS := ["USE", "OWNER", "STATE", "VALUE", "FOR SALE", "WORKED"]
const SLATE := Color("46597d")
const GOLD := Color("f0c24f")
const BG := Color("2b1c12")
const OWNER_COLS := [Color("e6194b"), Color("3cb44b"), Color("4363d8"), Color("f58231"), Color("911eb4"), Color("42d4f4"),
	Color("f032e6"), Color("bfef45")]
const HEALTH := {"busy": Color("3ccf3c"), "idle": Color("f4f4f4"), "full": Color("f4f4f4"), "hands": Color("f0a020"),
	"inputs": Color("f0a020"), "nopay": Color("f0a020"), "wages": Color("e02a1e")}
const YARD_ICON := {"weaponsmith": "anvil", "armorsmith": "anvil", "smelter": "kiln", "jeweler": "kiln", "builder": "kiln",
	"tanner": "vat", "leatherworker": "vat", "brewer": "mill", "vintner": "barrel", "weaver": "loom", "tailor": "loom",
	"carpenter": "logs", "woodcutter": "logs", "bowyer": "logs", "fletcher": "logs", "hunter": "antlers", "fishery": "fish",
	"market": "stall", "farm": "barn", "quarry": "quarry", "mine": "mine"}

static var _sprites := {}
static var _solids := {}

# ================================================================== entry
## Builds the land map of `town` inside `parent` and returns its root Control. focus_fid (optional, a family id):
## open on the OWNER overlay with only that family's plots bright ("show my land" from a family page).
static func mount(parent: Control, town: Dictionary, focus_fid: int = -99) -> Control:
	var root := UiKit.vbox(6)
	root.name = "LandMap"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.expand(root, true, true)
	parent.add_child(root)
	if Plots.of(town).is_empty():
		root.add_child(UiKit.label("Nobody keeps a land book here.", "Muted"))
		return root
	var view := MapView.new()
	view.town = town
	view.host = parent
	# overlay chips and Centre
	var top := UiKit.flow(6)
	root.add_child(top)
	var chips := {}
	for o in OVERLAYS:
		var b := UiKit.button(o, func(): view.set_overlay(o), "TabOn" if o == "USE" else "Tab", 96)
		chips[o] = b
		top.add_child(b)
	top.add_child(UiKit.button("Centre", func(): view.centre(), "", 110))
	view.chips = chips
	# the map and the card side by side
	var mid := UiKit.hbox(8)
	UiKit.expand(mid, true, true)
	root.add_child(mid)
	view.custom_minimum_size = Vector2(320, 240)
	UiKit.expand(view, true, true)
	view.clip_contents = true
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	mid.add_child(view)
	var side := UiKit.panel()
	side.custom_minimum_size = Vector2(380, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(side)
	var sc := UiKit.scroll()
	UiKit.expand(sc, true, true)
	side.add_child(sc)
	var card := UiKit.vbox(6)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(card)
	view.card_box = card
	# the summary strip
	var strip := UiKit.flow(6)
	root.add_child(strip)
	view.strip = strip
	if focus_fid != -99:
		view.overlay = "OWNER"
		view.focus = focus_fid
		for k in chips:
			(chips[k] as Button).theme_type_variation = "TabOn" if k == "OWNER" else "Tab"
	view.rebuild()
	view.show_card(-1)
	view.resized.connect(func(): view.centre())
	return root

## Full screen over `host` with a title bar and Close (the Town tab's "Land map" button).
static func open(host: Control, town: Dictionary) -> Control:
	var layer := PanelContainer.new()
	layer.set_meta("ui_modal", true)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(layer)
	var v := UiKit.vbox(6)
	layer.add_child(v)
	var bar := UiKit.hbox(8)
	v.add_child(bar)
	var title := UiKit.label("The land of %s" % town.get("name", "the town"), "H2")
	UiKit.expand(title)
	bar.add_child(title)
	bar.add_child(UiKit.button("Close", func(): layer.queue_free(), "", 120))
	var body := Control.new()
	UiKit.expand(body, true, true)
	v.add_child(body)
	mount(body, town)
	return layer

# ================================================================== composing the map
## The whole map as one image: each plot's sprite, then the overlay's tint or outline. focus >= 0: only that
## owner's plots stay bright. Returns {img, owners {fid: colour}}.
static func compose(town: Dictionary, overlay: String, focus: int = -99) -> Dictionary:
	var e: Dictionary = town["econ"]
	var P := Plots.of(town)
	var day := float(Game.day)
	var n := Plots.count(P)
	var img := Image.create(int(P["gw"]) * TILE, int(P["gh"]) * TILE, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	var owners := owner_colours(e, P)
	var vmax := 1
	var worked := PackedByteArray()
	if overlay == "VALUE":
		for i in n:
			vmax = maxi(vmax, Plots.value(e, P, i))
	elif overlay == "WORKED":
		worked = Plots.worked_mask(e, P)
	var use: PackedInt32Array = P["use"]
	var full := Rect2i(0, 0, TILE, TILE)
	for i in n:
		var at := Vector2i(int(P["x"][i]) * TILE, int(P["y"][i]) * TILE)
		img.blit_rect(sprite(sprite_key(e, P, i, day)), full, at)
		var u := use[i]
		if u == Plots.STATE:
			continue   # the town's own buildings stay bright in every overlay
		var o := int(P["own"][i])
		match overlay:
			"USE":
				_health_edge(img, e, P, i, at)
			"OWNER":
				var c: Color = owners.get(o, Color(0.6, 0.6, 0.6)) if Plots.LAND_USES.has(u) or u == Plots.HOME or u == Plots.YARD or u == Plots.MINE \
					else (Color(1, 1, 1) if o == Plots.TOWN else Color(0.6, 0.6, 0.6))
				img.blend_rect(_solid(Color(c, 0.55)), full, at)
				_health_edge(img, e, P, i, at)
			"STATE":
				img.blend_rect(_solid(Color(0.05, 0.05, 0.08, 0.62)), full, at)
			"VALUE":
				var v := Plots.value(e, P, i)
				if v < 0:
					img.blend_rect(_solid(Color(0.45, 0.45, 0.45, 0.7)), full, at)
				else:
					var k := clampf(sqrt(float(v) / float(vmax)), 0.0, 1.0)
					img.blend_rect(_solid(Color(Color("fff2b0").lerp(Color("5a2a08"), snappedf(k, 0.1)), 0.68)), full, at)
			"FOR SALE":
				var seized := int(P["fl"][i]) & Plots.F_SEIZED != 0
				if Plots.for_sale(P, i) or seized:
					_edge(img, at, Color("e02a1e") if seized else Color("fff4dc"), 3)
				else:
					img.blend_rect(_solid(Color(0, 0, 0, 0.5)), full, at)
			"WORKED":
				if u in [Plots.HOME, Plots.ROAD, Plots.WALL, Plots.WATER, Plots.SQUARE, Plots.LOT]:
					pass   # town ground: neither worked nor idle
				elif worked[i] == 0:
					img.blend_rect(_solid(Color(0, 0, 0, 0.55)), full, at)
				elif u != Plots.ROAD and u != Plots.WALL and u != Plots.WATER:
					_edge(img, at, Color("9dff6a"), 2)
		if focus != -99 and o != focus and int(P["ten"][i]) != focus:
			img.blend_rect(_solid(Color(0, 0, 0, 0.6)), full, at)
	return {"img": img, "owners": owners}

## The eight biggest farm landholders (families) each get a colour; the town is white.
static func owner_colours(e: Dictionary, P: Dictionary) -> Dictionary:
	var oc: Dictionary = Plots.totals(e).get("own_crop", {})
	var rows := []
	for o in oc:
		if int(o) > 0:
			var a := 0
			for c in oc[o]:
				a += int(oc[o][c])
			rows.append([int(o), a])
	rows.sort_custom(func(a, b): return a[1] > b[1] if a[1] != b[1] else a[0] < b[0])
	var out := {Plots.TOWN: Color(1, 1, 1)}
	for k in mini(8, rows.size()):
		out[rows[k][0]] = OWNER_COLS[k]
	return out

static func _health_edge(img: Image, e: Dictionary, P: Dictionary, i: int, at: Vector2i) -> void:
	var u := int(P["use"][i])
	if u != Plots.YARD and u != Plots.MINE:
		return
	var b: Dictionary = (e["biz"] as Array)[int(P["sub"][i])]
	var c: Color = Color("e02a1e") if b.get("closed", false) else HEALTH.get(String(b.get("state", "idle")), Color(1, 1, 1))
	_edge(img, at, c, 2)

static func _edge(img: Image, at: Vector2i, c: Color, w: int) -> void:
	img.fill_rect(Rect2i(at.x, at.y, TILE, w), c)
	img.fill_rect(Rect2i(at.x, at.y + TILE - w, TILE, w), c)
	img.fill_rect(Rect2i(at.x, at.y, w, TILE), c)
	img.fill_rect(Rect2i(at.x + TILE - w, at.y, w, TILE), c)

static func _solid(c: Color) -> Image:
	var k := c.to_html(true)
	if not _solids.has(k):
		var im := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
		im.fill(c)
		_solids[k] = im
	return _solids[k]

# ================================================================== sprites (drawn in code)
static func sprite_key(e: Dictionary, P: Dictionary, i: int, day: float) -> String:
	var u := int(P["use"][i])
	match u:
		Plots.FIELD:
			var crop: String = P["crops"][int(P["sub"][i])]
			return "field:%s:%s" % ["flax" if crop == "flax" else "grain", Plots.season_word(day)]
		Plots.ORCHARD:
			return "orchard"
		Plots.VINEYARD:
			return "vineyard"
		Plots.PASTURE:
			if e.has("hd"):   # herds as records: the herd grazing this plot
				return "pasture:" + Herds.plot_kind(e, P, i)
			var ten := int(P["ten"][i])
			var animal := ""
			if ten >= 0 and ten < (e["fams"] as Array).size():
				var hd: Dictionary = e["fams"][ten]["herd"]
				var most := 0
				for a in hd:
					if int(hd[a]) > most:
						most = int(hd[a]); animal = String(a)
			return "pasture:" + animal
		Plots.WOOD:
			return "wood:" + Plots.wood_stage(P, i)
		Plots.HOME:
			var pen := Herds.plot_kind(e, P, i)   # herds: a home's pen (hens, rats, hives)
			return "home:" + String(e.get("culture", "middle")) + ((":" + pen) if pen != "" else "")
		Plots.YARD, Plots.MINE:
			var b: Dictionary = (e["biz"] as Array)[int(P["sub"][i])]
			return "yard:" + String(YARD_ICON.get(String(b["type"]), "crate"))
		Plots.WASTE:
			return "hills" if int(P["sub"][i]) == 1 else "waste"
		Plots.ROAD:
			return "gate" if int(P["sub"][i]) == 1 else "road"
		Plots.WATER:
			return "water"
		Plots.WALL:
			return "wall"
		Plots.STATE:
			return "state:" + String(P["bld"][int(P["sub"][i])]["k"])
		Plots.COMMON:
			return "common"
		Plots.SQUARE:
			return "square"
		Plots.LOT:
			return "lot"
	return "waste"

static func sprite(key: String) -> Image:
	if _sprites.has(key):
		return _sprites[key]
	var im := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	_paint(im, key)
	_sprites[key] = im
	return im

static func _r(im: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	im.fill_rect(Rect2i(x, y, w, h), c)

static func _disc(im: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for y in range(int(cy - r), int(cy + r) + 1):
		for x in range(int(cx - r), int(cx + r) + 1):
			if x >= 0 and y >= 0 and x < TILE and y < TILE and Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= r:
				im.set_pixel(x, y, c)

static func _line(im: Image, a: Vector2, b: Vector2, c: Color, w: float = 1.5) -> void:
	var n := int(a.distance_to(b) * 2.0) + 1
	for k in n + 1:
		var p := a.lerp(b, float(k) / float(n))
		_disc(im, p.x, p.y, w * 0.5, c)

static func _tri(im: Image, a: Vector2, b: Vector2, c2: Vector2, col: Color) -> void:
	for y in TILE:
		for x in TILE:
			var p := Vector2(x + 0.5, y + 0.5)
			var d1 := (p - b).cross(a - b); var d2 := (p - c2).cross(b - c2); var d3 := (p - a).cross(c2 - a)
			if not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0)):
				im.set_pixel(x, y, col)

static func _paint(im: Image, key: String) -> void:
	var parts := key.split(":")
	var k := parts[0]
	var a1 := parts[1] if parts.size() > 1 else ""
	var a2 := parts[2] if parts.size() > 2 else ""
	var grass := Color("7cc35a")
	match k:
		"field":
			var bg: Color = {"sown": Color("8a5a32"), "growing": Color("5fb84a"), "ripe": Color("e8c13a"), "stubble": Color("e6d79a"), "bare": Color("7a5030")}[a2]
			im.fill(bg)
			var dot: Color = {"sown": Color("7fd35a"), "growing": Color("3a8a2e"), "ripe": Color("b8901f"), "stubble": Color("a07040"), "bare": Color("5e3c22")}[a2]
			if a1 == "flax" and a2 in ["growing", "ripe"]:
				dot = Color("5a8ee0")
			for row in range(3, TILE, 6):
				for x in range(2 + (row / 6) % 2 * 2, TILE - 1, 4):
					_r(im, x, row, 2, 2, dot)
			_r(im, 0, 0, TILE, 1, bg.darkened(0.2))
			_r(im, 0, 0, 1, TILE, bg.darkened(0.2))
		"orchard":
			im.fill(grass)
			for p in [Vector2(9, 9), Vector2(23, 10), Vector2(10, 23), Vector2(23, 23)]:
				_r(im, int(p.x) - 1, int(p.y) + 3, 2, 4, Color("6b4426"))
				_disc(im, p.x, p.y, 5.5, Color("2e8b3a"))
				_disc(im, p.x + 2, p.y - 1, 1.3, Color("e0302a"))
				_disc(im, p.x - 2, p.y + 1, 1.3, Color("e0302a"))
		"vineyard":
			im.fill(Color("a8c86a"))
			for x in [6, 16, 26]:
				_r(im, x, 3, 1, 26, Color("6b4426"))
				for y in range(5, 28, 6):
					_disc(im, x + 1.5, y, 2.2, Color("7a2a8a"))
		"pasture":
			im.fill(Color("8fd16a"))
			for p in [Vector2(5, 6), Vector2(26, 25), Vector2(24, 7)]:
				_r(im, int(p.x), int(p.y), 1, 2, Color("5fa040"))
			match a1:
				"cattle":
					_r(im, 8, 13, 14, 8, Color("8a4a22")); _r(im, 12, 15, 4, 3, Color("f4f4f4")); _r(im, 21, 11, 5, 5, Color("6b3418"))
					for x in [9, 13, 17, 20]:
						_r(im, x, 21, 2, 4, Color("3a2010"))
				"pigs":
					_disc(im, 15, 17, 6, Color("f4a0b0")); _disc(im, 21, 15, 3.5, Color("f4a0b0")); _r(im, 23, 15, 2, 2, Color("c06070"))
					for x in [11, 17]:
						_r(im, x, 22, 2, 3, Color("c06070"))
				"goats":
					_r(im, 9, 14, 12, 7, Color("e8e0cc")); _r(im, 20, 10, 4, 6, Color("d8d0bc")); _line(im, Vector2(21, 10), Vector2(19, 6), Color("6b5a40"), 1.2)
					for x in [10, 18]:
						_r(im, x, 21, 2, 4, Color("6b5a40"))
				"horses":   # v0.012: a bay horse with a dark mane
					_r(im, 7, 13, 16, 7, Color("9a5a2a")); _r(im, 21, 7, 4, 8, Color("9a5a2a")); _r(im, 23, 5, 5, 4, Color("9a5a2a"))
					_r(im, 20, 7, 2, 7, Color("2a1a10")); _r(im, 5, 13, 2, 6, Color("2a1a10"))
					for x in [8, 11, 18, 21]:
						_r(im, x, 20, 2, 7, Color("6b3a1a"))
				"donkeys":   # a grey donkey, long ears
					_r(im, 9, 15, 13, 6, Color("8a8478")); _r(im, 20, 10, 4, 7, Color("8a8478")); _r(im, 22, 9, 5, 4, Color("8a8478"))
					_r(im, 22, 5, 1, 4, Color("6a6458")); _r(im, 24, 5, 1, 4, Color("6a6458")); _r(im, 26, 11, 2, 2, Color("e8e4dc"))
					for x in [10, 13, 17, 20]:
						_r(im, x, 21, 2, 5, Color("5a5448"))
				"":
					pass
				_:
					_disc(im, 14, 16, 6.5, Color("f8f8f0")); _disc(im, 10, 15, 3.5, Color("f8f8f0")); _r(im, 20, 13, 5, 5, Color("2a2a2a"))
					for x in [11, 16]:
						_r(im, x, 22, 2, 3, Color("2a2a2a"))
		"wood":
			match a1:
				"dense":
					im.fill(Color("2c7a32"))
					for p in [Vector2(8, 8), Vector2(22, 7), Vector2(15, 16), Vector2(7, 24), Vector2(24, 23)]:
						_disc(im, p.x, p.y, 6.5, Color("1f5e26")); _disc(im, p.x - 1, p.y - 1, 4.5, Color("2e8b3a"))
				"thin":
					im.fill(Color("6fb050"))
					for p in [Vector2(10, 10), Vector2(22, 21)]:
						_r(im, int(p.x) - 1, int(p.y) + 3, 2, 5, Color("6b4426"))
						_disc(im, p.x, p.y, 6, Color("1f5e26")); _disc(im, p.x - 1, p.y - 1, 4, Color("2e8b3a"))
				"felled":
					im.fill(Color("9a7444"))
					for p in [Vector2(7, 8), Vector2(20, 6), Vector2(13, 18), Vector2(25, 21), Vector2(6, 26)]:
						_disc(im, p.x, p.y, 2.6, Color("6b4426")); _disc(im, p.x, p.y, 1.2, Color("d8b880"))
				_:
					im.fill(Color("8aa858"))
					for p in [Vector2(7, 8), Vector2(22, 9), Vector2(14, 22)]:
						_disc(im, p.x, p.y, 2.2, Color("6b4426"))
					for p in [Vector2(12, 10), Vector2(24, 21), Vector2(7, 20)]:
						_r(im, int(p.x), int(p.y), 1, 4, Color("3a7a2a")); _disc(im, p.x + 0.5, p.y, 2.2, Color("4aa83a"))
		"home":
			im.fill(grass)
			match a1:
				"northern":
					_r(im, 3, 14, 26, 11, Color("8a5a32")); _tri(im, Vector2(1, 15), Vector2(16, 5), Vector2(31, 15), Color("b02a1e"))
					_r(im, 14, 18, 4, 7, Color("3a2010"))
				"orc":
					_tri(im, Vector2(3, 27), Vector2(16, 4), Vector2(29, 27), Color("c89a5a")); _tri(im, Vector2(12, 27), Vector2(16, 15), Vector2(20, 27), Color("3a2010"))
					_line(im, Vector2(16, 4), Vector2(13, 1), Color("6b4426")); _line(im, Vector2(16, 4), Vector2(19, 1), Color("6b4426"))
				"goblin":
					_disc(im, 16, 24, 12, Color("8a6a3a")); _r(im, 0, 26, TILE, 6, grass); _disc(im, 16, 22, 4.5, Color("1a1008"))
				"moon_elf":
					_r(im, 13, 14, 6, 14, Color("c8d8e0")); _disc(im, 16, 11, 10, Color("3aa86a")); _disc(im, 13, 9, 4, Color("8ae0b0"))
					_r(im, 15, 21, 3, 7, Color("4a3a6a"))
				"dwarf":   # v0.012: a stone hall with a slate roof and an iron-bound door
					_r(im, 5, 13, 22, 14, Color("a8a298")); _tri(im, Vector2(3, 14), Vector2(16, 5), Vector2(29, 14), Color("5a6068"))
					for y in [17, 21]:
						_r(im, 5, y, 22, 1, Color("8a847a"))
					_r(im, 13, 18, 6, 9, Color("4a3020")); _r(im, 13, 21, 6, 1, Color("2a2a2a"))
				"eastern":   # a felt yurt: white dome, ochre door, a smoke ring at the crown
					_disc(im, 16, 20, 11, Color("efe8d8")); _r(im, 0, 22, TILE, 10, grass); _r(im, 5, 18, 22, 6, Color("efe8d8"))
					_r(im, 5, 18, 22, 1, Color("c0682a")); _r(im, 14, 19, 4, 5, Color("c0682a")); _disc(im, 16, 10, 1.6, Color("8a7a60"))
				_:
					_r(im, 6, 15, 20, 12, Color("f1e4c3")); _tri(im, Vector2(3, 16), Vector2(16, 4), Vector2(29, 16), Color("d0402a"))
					_r(im, 14, 19, 4, 8, Color("6b4426")); _r(im, 8, 18, 4, 4, Color("6ab0e0"))
			match a2:   # the household's pen in the corner
				"hens":
					_disc(im, 26, 27, 3, Color("f8f4e8")); _r(im, 28, 24, 2, 2, Color("e0302a")); _r(im, 29, 27, 2, 1, Color("f0b030"))
				"rats":
					_disc(im, 26, 28, 2.5, Color("7a6a5a")); _line(im, Vector2(23, 28), Vector2(20, 30), Color("c09080"), 1.0)
				"bees":
					_r(im, 23, 23, 7, 7, Color("e0b040")); _r(im, 23, 25, 7, 1, Color("8a5a20")); _r(im, 23, 27, 7, 1, Color("8a5a20"))
		"yard":
			im.fill(Color("b89a70"))
			_r(im, 0, 0, TILE, 1, Color("8a7050"))
			_paint_icon(im, a1)
		"road", "gate":
			im.fill(grass)
			_r(im, 0, 9, TILE, 14, Color("c9a26b")); _r(im, 9, 0, 14, TILE, Color("c9a26b"))
			if k == "gate":
				_r(im, 0, 0, 7, TILE, Color("9a9a9a")); _r(im, 25, 0, 7, TILE, Color("9a9a9a"))
				_r(im, 2, 2, 3, 3, Color("6a6a6a")); _r(im, 27, 2, 3, 3, Color("6a6a6a"))
		"water":
			im.fill(Color("3a8ee8"))
			for y in [6, 16, 26]:
				for x in range(2, 30, 8):
					_r(im, x + (y / 10) % 2 * 3, y, 4, 1, Color("8cc8ff"))
		"wall":
			im.fill(Color("8a8a8a"))
			for y in range(0, TILE, 8):
				for x in range(0, TILE, 10):
					_r(im, x + (y / 8) % 2 * 5, y, 9, 7, Color("a8a8a8"))
		"square":
			im.fill(Color("c8b898"))
			for y in range(0, TILE, 8):
				for x in range(0, TILE, 8):
					_r(im, x + 1, y + 1, 6, 6, Color("d8caa8"))
			_disc(im, 16, 16, 5, Color("6a6a6a")); _disc(im, 16, 16, 3, Color("3a8ee8"))
		"waste":
			im.fill(Color("a89a6a"))
			for p in [Vector2(6, 7), Vector2(20, 12), Vector2(10, 22), Vector2(25, 26)]:
				_r(im, int(p.x), int(p.y), 3, 2, Color("7a6a4a"))
		"hills":
			im.fill(Color("9aa070"))
			_tri(im, Vector2(1, 27), Vector2(11, 10), Vector2(21, 27), Color("7a7a5a"))
			_tri(im, Vector2(12, 27), Vector2(22, 6), Vector2(31, 27), Color("8a8a6a"))
		"common":
			im.fill(Color("a8d878"))
			for p in [Vector2(6, 8), Vector2(18, 20), Vector2(25, 6)]:
				_r(im, int(p.x), int(p.y), 2, 2, Color("e8e86a"))
		"lot":
			im.fill(Color("a89070"))
			for p in [Vector2(7, 10), Vector2(15, 18), Vector2(22, 9), Vector2(10, 24)]:
				_r(im, int(p.x), int(p.y), 4, 3, Color("8a8a8a"))
		"state":
			im.fill(SLATE)
			_paint_state(im, a1)
			_r(im, 0, 0, TILE, 2, GOLD); _r(im, 0, TILE - 2, TILE, 2, GOLD); _r(im, 0, 0, 2, TILE, GOLD); _r(im, TILE - 2, 0, 2, TILE, GOLD)
		_:
			im.fill(Color("a89a6a"))

static func _paint_icon(im: Image, icon: String) -> void:
	var dk := Color("3a3a3a")
	match icon:
		"anvil":
			_r(im, 7, 11, 18, 5, dk); _r(im, 4, 11, 4, 3, dk); _r(im, 12, 16, 8, 6, dk); _r(im, 9, 22, 14, 3, dk)
		"kiln":
			_disc(im, 16, 18, 10, Color("b04a2a")); _r(im, 0, 24, TILE, 8, Color("b89a70")); _disc(im, 16, 20, 4, Color("ffb020"))
			_r(im, 14, 4, 4, 6, Color("8a3a20"))
		"vat":
			_r(im, 7, 10, 18, 16, Color("8a5a32")); _r(im, 7, 13, 18, 2, Color("4a3018")); _r(im, 7, 21, 18, 2, Color("4a3018"))
			_r(im, 9, 9, 14, 3, Color("5a7a3a"))
		"mill":
			_disc(im, 16, 16, 11, Color("6b4426")); _disc(im, 16, 16, 8, Color("b89a70"))
			for ang in [0.0, PI / 4.0, PI / 2.0, 3.0 * PI / 4.0]:
				var d := Vector2.from_angle(ang) * 10.0
				_line(im, Vector2(16, 16) - d, Vector2(16, 16) + d, Color("6b4426"), 2.0)
			_disc(im, 16, 16, 2.5, dk)
		"barrel":
			_r(im, 9, 7, 14, 19, Color("8a5a32")); _r(im, 9, 11, 14, 2, dk); _r(im, 9, 20, 14, 2, dk); _disc(im, 16, 16, 2.5, Color("7a2a8a"))
		"loom":
			_r(im, 6, 6, 3, 20, Color("6b4426")); _r(im, 23, 6, 3, 20, Color("6b4426")); _r(im, 6, 6, 20, 3, Color("6b4426"))
			for x in range(10, 23, 3):
				_r(im, x, 9, 1, 15, Color("f4f0e0"))
			_r(im, 9, 18, 14, 4, Color("4a7ad0"))
		"logs":
			for p in [Vector2(10, 22), Vector2(22, 22), Vector2(16, 13)]:
				_disc(im, p.x, p.y, 5.5, Color("8a5a32")); _disc(im, p.x, p.y, 3, Color("d8b880"))
		"antlers":
			_line(im, Vector2(16, 26), Vector2(16, 14), Color("8a5a32"), 2.0)
			_line(im, Vector2(16, 14), Vector2(8, 6), Color("e8d8b0"), 2.0); _line(im, Vector2(16, 14), Vector2(24, 6), Color("e8d8b0"), 2.0)
			_line(im, Vector2(11, 9), Vector2(8, 12), Color("e8d8b0"), 1.5); _line(im, Vector2(21, 9), Vector2(24, 12), Color("e8d8b0"), 1.5)
		"fish":
			_disc(im, 15, 16, 7, Color("4a8ac0")); _tri(im, Vector2(21, 16), Vector2(28, 10), Vector2(28, 22), Color("4a8ac0")); _disc(im, 11, 14, 1.3, dk)
		"stall":
			_r(im, 6, 14, 20, 12, Color("8a5a32"))
			for x in range(4, 28, 6):
				_r(im, x, 7, 6, 7, Color("e0302a") if (x / 6) % 2 == 0 else Color("f4f0e0"))
		"barn":
			_r(im, 7, 13, 18, 14, Color("b02a1e")); _tri(im, Vector2(5, 14), Vector2(16, 5), Vector2(27, 14), Color("8a1a10"))
			_r(im, 13, 18, 6, 9, Color("f4f0e0")); _line(im, Vector2(13, 18), Vector2(19, 27), Color("b02a1e"), 1.2)
		"mine":
			im.fill(Color("7a7066"))
			_disc(im, 16, 22, 7, Color("2a2420")); _r(im, 0, 26, TILE, 6, Color("7a7066"))
			_line(im, Vector2(9, 5), Vector2(23, 15), Color("c8c8c8"), 2.0); _line(im, Vector2(8, 10), Vector2(14, 4), Color("c8c8c8"), 2.0)
			_line(im, Vector2(18, 4), Vector2(24, 10), Color("c8c8c8"), 2.0)
		"quarry":
			im.fill(Color("8a8a7a"))
			for p in [Vector2(5, 6), Vector2(17, 6), Vector2(10, 17), Vector2(21, 18)]:
				_r(im, int(p.x), int(p.y), 10, 8, Color("c8c8c0")); _r(im, int(p.x), int(p.y) + 7, 10, 1, Color("5a5a52"))
		_:
			_r(im, 8, 9, 16, 14, Color("a07040")); _line(im, Vector2(8, 9), Vector2(24, 23), Color("6b4426"), 1.5)
			_line(im, Vector2(24, 9), Vector2(8, 23), Color("6b4426"), 1.5)

static func _paint_state(im: Image, kind: String) -> void:
	var w := Color("f4f4f4")
	match kind:
		"keep":
			_r(im, 10, 9, 12, 18, w)
			for x in [10, 14, 18]:
				_r(im, x, 5, 3, 4, w)
			_r(im, 14, 19, 4, 8, SLATE.darkened(0.4)); _r(im, 15, 12, 2, 3, SLATE.darkened(0.4))
		"hall":
			_r(im, 15, 6, 2, 20, GOLD); _r(im, 7, 9, 18, 2, GOLD); _r(im, 11, 25, 10, 2, GOLD)
			_line(im, Vector2(8, 10), Vector2(5, 18), GOLD, 1.0); _line(im, Vector2(8, 10), Vector2(11, 18), GOLD, 1.0); _r(im, 4, 18, 8, 2, GOLD)
			_line(im, Vector2(24, 10), Vector2(21, 18), GOLD, 1.0); _line(im, Vector2(24, 10), Vector2(27, 18), GOLD, 1.0); _r(im, 20, 18, 8, 2, GOLD)
		"barracks":
			_line(im, Vector2(7, 7), Vector2(24, 24), w, 2.2); _line(im, Vector2(25, 7), Vector2(8, 24), w, 2.2)
			_r(im, 5, 21, 6, 2, GOLD); _r(im, 21, 21, 6, 2, GOLD)
		"armory":
			_r(im, 8, 6, 16, 12, w); _tri(im, Vector2(8, 17), Vector2(24, 17), Vector2(16, 28), w); _r(im, 15, 8, 2, 16, GOLD); _r(im, 10, 11, 12, 2, GOLD)
		"granary":
			_r(im, 9, 12, 14, 15, Color("e8c13a")); _tri(im, Vector2(7, 13), Vector2(16, 4), Vector2(25, 13), w); _r(im, 14, 19, 4, 8, Color("8a5a32"))
		"shelter":
			_tri(im, Vector2(5, 15), Vector2(27, 15), Vector2(16, 25), w); _r(im, 5, 14, 22, 2, w)
			_line(im, Vector2(12, 11), Vector2(13, 6), Color("d8d8d8"), 1.0); _line(im, Vector2(19, 11), Vector2(20, 6), Color("d8d8d8"), 1.0)
		"jail":
			_r(im, 6, 7, 20, 2, w); _r(im, 6, 24, 20, 2, w)
			for x in [7, 12, 17, 22]:
				_r(im, x, 7, 2, 19, w)
		"mint":
			_disc(im, 16, 16, 9, GOLD); _disc(im, 16, 16, 6, Color("d8a030")); _r(im, 15, 11, 2, 10, GOLD)
		"academy":   # v0.012: the research house - a furnace flask
			_r(im, 13, 5, 6, 9, w); _tri(im, Vector2(6, 27), Vector2(26, 27), Vector2(16, 12), w); _r(im, 10, 21, 12, 4, Color("9aa4ad"))

# ================================================================== the strip
## Rows for the summary strip under the map: [{text, fid (-99 = not a family)}].
static func strip_items(town: Dictionary, overlay: String) -> Array:
	var e: Dictionary = town["econ"]
	var P := Plots.of(town)
	var t := Plots.totals(e)
	var ua: Array = t["use_ac"]; var un: Array = t["use_n"]
	var out := []
	match overlay:
		"USE":
			for c in t["crop"]:
				out.append({"text": "%s %d acres" % [TownEcon.variety_word(e, String(c)).capitalize(), int(t["crop"][c])], "fid": -99})
			out.append({"text": "Pasture %d acres" % int(ua[Plots.PASTURE]), "fid": -99})
			var wd: Dictionary = t["wood"]
			out.append({"text": "Woods %d acres (%d dense, %d thin, %d felled, %d regrowing plots)" % [int(ua[Plots.WOOD]), wd["dense"], wd["thin"], wd["felled"], wd["regrowing"]], "fid": -99})
			out.append({"text": "%d homes, %d yards, %d town buildings" % [int(un[Plots.HOME]), int(un[Plots.YARD]) + int(un[Plots.MINE]), int(un[Plots.STATE])], "fid": -99})
		"OWNER":
			var cols := owner_colours(e, P)
			var rows := []
			for o in t["own_crop"]:
				var a := 0
				for c in t["own_crop"][o]:
					a += int(t["own_crop"][o][c])
				rows.append([int(o), a])
			rows.sort_custom(func(a, b): return a[1] > b[1] if a[1] != b[1] else a[0] < b[0])
			var rest := 0
			for r in rows:
				if cols.has(r[0]):
					var nm := "The town" if int(r[0]) == Plots.TOWN else String(e["fams"][int(r[0])]["name"])
					out.append({"text": "%s %d acres" % [nm, int(r[1])], "fid": int(r[0]), "col": cols[r[0]]})
				else:
					rest += int(r[1])
			if rest > 0:
				out.append({"text": "Others %d acres" % rest, "fid": -99, "col": Color(0.6, 0.6, 0.6)})
		"STATE":
			for b in P["bld"]:
				out.append({"text": _cap(String(b["n"])), "fid": -99, "plot": int(b["p"])})
		"VALUE":
			var land := 0; var homes := 0; var yards := 0
			for i in Plots.count(P):
				var v := Plots.value(e, P, i)
				if v <= 0:
					continue
				var u := int(P["use"][i])
				if Plots.LAND_USES.has(u):
					land += v
				elif u == Plots.HOME:
					homes += v
				else:
					yards += v
			out.append({"text": "Land %d coins (%d an acre)" % [land, int(TownEcon.data()["land"]["acre_price"])], "fid": -99})
			out.append({"text": "Homes %d coins" % homes, "fid": -99})
			out.append({"text": "Yards %d coins" % yards, "fid": -99})
		"FOR SALE":
			var acres := 0; var yd := 0; var hs := 0; var sz := 0
			for i in Plots.count(P):
				var u2 := int(P["use"][i])
				if int(P["fl"][i]) & Plots.F_SEIZED and Plots.LAND_USES.has(u2):
					sz += int(P["ac"][i])
				if not Plots.for_sale(P, i):
					continue
				if Plots.LAND_USES.has(u2):
					acres += int(P["ac"][i])
				elif u2 == Plots.HOME:
					hs += 1
				else:
					yd += 1
			out.append({"text": "Town land for sale %d acres (seized %d)" % [acres, sz], "fid": -99})
			out.append({"text": "%d yards, %d houses for sale" % [yd, hs], "fid": -99})
		"WORKED":
			var m := Plots.worked_mask(e, P)
			var wa := 0; var ta := 0
			for i in Plots.count(P):
				if Plots.LAND_USES.has(int(P["use"][i])):
					ta += int(P["ac"][i])
					if m[i] == 1:
						wa += int(P["ac"][i])
			out.append({"text": "Worked today %d of %d acres; idle %d" % [wa, ta, ta - wa], "fid": -99})
	return out

static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s

# ================================================================== the view
class MapView extends Control:
	var town: Dictionary
	var host: Control
	var overlay := "USE"
	var focus := -99
	var sel := -1
	var zoom := 1.5
	var off := Vector2.ZERO
	var tex: ImageTexture
	var chips := {}
	var card_box: VBoxContainer
	var strip: HFlowContainer
	var compose_ms := 0.0
	var _down := false
	var _moved := 0.0
	var _touches := {}
	var _pinch := 0.0
	var _centred := false

	func rebuild() -> void:
		var t0 := Time.get_ticks_usec()
		var r := LandMap.compose(town, overlay, focus)
		if tex == null:
			tex = ImageTexture.create_from_image(r["img"])
		else:
			tex.set_image(r["img"])
		compose_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		_fill_strip()
		queue_redraw()

	func set_overlay(o: String) -> void:
		overlay = o
		focus = -99
		for k in chips:
			(chips[k] as Button).theme_type_variation = "TabOn" if k == o else "Tab"
		rebuild()

	func set_focus(fid: int) -> void:
		focus = -99 if focus == fid else fid
		rebuild()

	func map_px() -> Vector2:
		var P := Plots.of(town)
		return Vector2(int(P["gw"]) * LandMap.TILE, int(P["gh"]) * LandMap.TILE)

	func centre() -> void:
		var m := map_px()
		if size.x <= 1.0 or size.y <= 1.0:
			return
		zoom = clampf(minf(size.x / m.x, size.y / m.y), 0.35, 4.0)
		zoom = maxf(zoom, minf(1.5, 48.0 / LandMap.TILE))   # phone: 32 px art at 48 px, the map then pans
		off = (size - m * zoom) * 0.5
		_centred = true
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), LandMap.BG)
		if tex == null:
			return
		if not _centred:
			centre()
		draw_texture_rect(tex, Rect2(off, map_px() * zoom), false)
		var P := Plots.of(town)
		var ts := LandMap.TILE * zoom
		if overlay == "STATE":
			var f := get_theme_default_font()
			for b in P["bld"]:
				var p := int(b["p"])
				if p < 0:
					continue
				var at := off + Vector2(int(P["x"][p]), int(P["y"][p])) * ts
				draw_string(f, at + Vector2(0, ts + 16), LandMap._cap(String(b["n"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, LandMap.GOLD)
		if sel >= 0 and sel < Plots.count(P):
			var at2 := off + Vector2(int(P["x"][sel]), int(P["y"][sel])) * ts
			draw_rect(Rect2(at2, Vector2(ts, ts)), Color(1, 1, 1), false, 3.0)

	func plot_at(pos: Vector2) -> int:
		var P := Plots.of(town)
		var c := ((pos - off) / (LandMap.TILE * zoom)).floor()
		if c.x < 0 or c.y < 0 or c.x >= int(P["gw"]) or c.y >= int(P["gh"]):
			return -1
		return int(P["g"][int(c.y) * int(P["gw"]) + int(c.x)])

	func zoom_at(pos: Vector2, factor: float) -> void:
		var nz := clampf(zoom * factor, 0.3, 5.0)
		off = pos - (pos - off) * (nz / zoom)
		zoom = nz
		queue_redraw()

	func tap(pos: Vector2) -> void:
		sel = plot_at(pos)
		show_card(sel)
		queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				zoom_at(mb.position, 1.15)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				zoom_at(mb.position, 1.0 / 1.15)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_down = true
					_moved = 0.0
				else:
					if _down and _moved < 10.0 and _touches.size() < 2:
						tap(mb.position)
					_down = false
			accept_event()
		elif ev is InputEventMouseMotion and _down and _touches.size() < 2:
			var mm := ev as InputEventMouseMotion
			off += mm.relative
			_moved += mm.relative.length()
			queue_redraw()
			accept_event()
		elif ev is InputEventScreenTouch:
			var st := ev as InputEventScreenTouch
			if st.pressed:
				_touches[st.index] = st.position
			else:
				_touches.erase(st.index)
			_pinch = _pinch_dist()
		elif ev is InputEventScreenDrag:
			var sd := ev as InputEventScreenDrag
			_touches[sd.index] = sd.position
			if _touches.size() >= 2:
				var d := _pinch_dist()
				if _pinch > 1.0 and d > 1.0:
					zoom_at(_pinch_mid(), d / _pinch)
				_pinch = d
				_moved = 100.0
				accept_event()
		elif ev is InputEventMagnifyGesture:
			var mg := ev as InputEventMagnifyGesture
			zoom_at(mg.position, mg.factor)
			accept_event()
		elif ev is InputEventPanGesture:
			off -= (ev as InputEventPanGesture).delta * 8.0
			queue_redraw()
			accept_event()

	func _pinch_dist() -> float:
		if _touches.size() < 2:
			return 0.0
		var v: Array = _touches.values()
		return (v[0] as Vector2).distance_to(v[1])

	func _pinch_mid() -> Vector2:
		var v: Array = _touches.values()
		return ((v[0] as Vector2) + (v[1] as Vector2)) * 0.5

	func _fill_strip() -> void:
		if strip == null:
			return
		UiKit.clear(strip)
		for it in LandMap.strip_items(town, overlay):
			if int(it["fid"]) != -99:
				var fid := int(it["fid"])
				var b := UiKit.button(String(it["text"]), func(): set_focus(fid), "RowOn" if focus == fid else "Row")
				if it.has("col"):
					b.add_theme_color_override("font_color", (it["col"] as Color).darkened(0.35))
				strip.add_child(b)
			elif it.has("plot"):
				var p := int(it["plot"])
				strip.add_child(UiKit.button(String(it["text"]), func(): select(p), "Row"))
			else:
				strip.add_child(UiKit.chip(String(it["text"]), it.get("col", UiTheme.WOOD_3)))

	func select(p: int) -> void:
		sel = p
		show_card(p)
		queue_redraw()

	## The plot card (or, with nothing picked, the "Town buildings" card).
	func show_card(i: int) -> void:
		if card_box == null:
			return
		UiKit.clear(card_box)
		if i < 0:
			card_box.add_child(LandMap.buildings_card(host, town, func(p): select(p)))
			return
		var c := Plots.card(Game, town, i)
		card_box.add_child(UiKit.label(String(c["title"]), "H2", true))
		for l in c["lines"]:
			card_box.add_child(UiKit.label(String(l), "", true))
		for tp in c["taps"]:
			var fid := int(tp["fid"])
			card_box.add_child(UiKit.button(String(tp["text"]), func(): TownEconTab.family_modal(host, town, fid), "Row"))
		if not (c["hist"] as Array).is_empty():
			card_box.add_child(UiKit.label("History", "H2"))
			for h in c["hist"]:
				card_box.add_child(UiKit.label(String(h), "Small", true))

## "Town buildings" (addendum A): one row per building with what it is doing now and who runs it; tap a row to
## find it on the map (on_pick(plot)), tap the runner for his household.
static func buildings_card(host: Control, town: Dictionary, on_pick: Callable = Callable()) -> Control:
	var v := UiKit.vbox(6)
	v.add_child(UiKit.label("Town buildings", "H2"))
	for b in Plots.buildings(Game, town):
		var p := int(b["plot"])
		var row := UiKit.button("%s: %s" % [_cap(String(b["name"])), String(b["now"])], func(): _pick(on_pick, p), "Row")
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(row)
		var r: Dictionary = b["runner"]
		if not r.is_empty():
			var fid := int(r["fid"])
			v.add_child(UiKit.button("   Run by %s%s" % [r["name"], (" (%s)" % r["role"]) if String(r.get("role", "")) != "" else ""],
				func(): TownEconTab.family_modal(host, town, fid), "", 0))
	return v

static func _pick(on_pick: Callable, p: int) -> void:
	if on_pick.is_valid():
		on_pick.call(p)
