extends RefCounted
## Item icons (art/item_icon.gd): an icon for every weapon, bow and armour template in every material it can
## be made of (and every working metal for metal pieces), with and without quality pips; metals read
## differently; textures are cached; food, drink, coin, every goods id and every arrow have an icon too.
## ICON_SHEET=<png path> also writes a contact sheet of every template in five metals (art review aid).

const METALS := ["copper", "tin", "bronze", "iron", "steel"]

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: ", what)

func mats_of(tid: String) -> Array:
	if DB.is_bow(tid):
		return ["wood"]
	var m: Array = [] if DB.is_weapon(tid) else (DB.template(tid).get("materials", []) as Array).duplicate()
	if m.is_empty() or m.has("copper"):
		return METALS   # smiths make metal pieces in any working metal (campaign/businesses.gd _pick_metal)
	return m

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var tids: Array = DB.weapons.keys() + DB.armor.keys() + DB.bows.keys()
	var n := 0
	for tid in tids:
		var shape := ItemIcon.shape_of(tid)
		check(shape != "bundle", "%s has a real shape (got %s)" % [tid, shape])
		for m in mats_of(tid):
			check(DB.materials.has(m) and DB.materials[m].has("color"), "material %s has a colour" % m)
			for q in [0, 5]:
				var tex := ItemIcon.for_template(tid, m, q)
				n += 1
				check(tex != null and tex.get_width() == ItemIcon.SIZE, "%s %s q%d has an icon" % [m, tid, q])
				var img := ItemIcon.image(shape, m, q)
				var solid := 0
				for y in img.get_height():
					for x in img.get_width():
						if img.get_pixel(x, y).a > 0.5:
							solid += 1
				check(solid >= 60, "%s %s q%d icon is drawn (%d px)" % [m, tid, q, solid])
	print("  %d template x material x quality icons" % n)
	# an item's icon is its template's, cached
	var it := Item.make("arming_sword", "copper", 2)
	check(ItemIcon.for_item(it) == ItemIcon.for_template("arming_sword", "copper", 2), "for_item uses the cache")
	var before := ItemIcon.cache_size()
	ItemIcon.for_template("arming_sword", "copper", 2)
	check(ItemIcon.cache_size() == before, "a second request draws nothing new")
	# metals read differently; quality shows
	var imgs := {}
	for m in METALS:
		imgs[m] = ItemIcon.image("sword", m, 0)
	for a in METALS:
		for b in METALS:
			if a < b:
				check(_diff(imgs[a], imgs[b]) > 20, "%s and %s swords differ" % [a, b])
	check(_diff(ItemIcon.image("helm_nasal", "tin", 0), ItemIcon.image("helm_nasal", "tin", 3)) >= 9, "quality pips show")
	# shapes per type differ
	check(_diff(ItemIcon.image("sword", "iron", 0), ItemIcon.image("spear", "iron", 0)) > 40, "sword and spear shapes differ")
	check(_diff(ItemIcon.image("shield_kite", "iron", 0), ItemIcon.image("mail", "iron", 0)) > 40, "shield and mail shapes differ")
	# food, drink, coin, goods, arrows
	var things: Array = ["meal", "beer", "wine", "coin"] + Goods.table().keys() + DB.arrows.keys()
	for k in things:
		if String(k).begins_with("_"):
			continue
		var tex := ItemIcon.for_thing(String(k))
		check(tex != null and tex.get_width() == ItemIcon.SIZE, "%s has an icon" % k)
	check(_diff(ItemIcon.image("mug", "#beer", 0), ItemIcon.image("loaf", "#meal", 0)) > 40, "beer and meals look different")
	var sheet := OS.get_environment("ICON_SHEET")
	if sheet != "":
		_sheet(tids, sheet)
	return fails

func _diff(a: Image, b: Image) -> int:
	var d := 0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) + absf(p.a - q.a) > 0.08:
				d += 1
	return d

func _sheet(tids: Array, path: String) -> void:
	var cols := 6
	var rows := tids.size() + 3
	var img := Image.create(cols * 34 * 2, rows * 34 * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color("#3a2a1c"))
	for r in tids.size():
		var mats: Array = mats_of(tids[r]) if not DB.is_bow(tids[r]) else ["wood"]
		for c in mats.size():
			var ic := ItemIcon.image(ItemIcon.shape_of(tids[r]), mats[c], c)
			ic.resize(64, 64, Image.INTERPOLATE_NEAREST)
			img.blend_rect(ic, Rect2i(0, 0, 64, 64), Vector2i(c * 68, r * 68))
	var things := ["meal", "beer", "wine", "coin", "meat", "fruit", "copper_bars", "tin_ore", "wood", "linen", "hides", "arrow_copper_bodkin", "salt", "scrap_tin", "heads_copper", "remedy", "tools", "wool"]
	for i in things.size():
		var ic2 := ItemIcon.for_thing(things[i]).get_image()
		ic2.resize(64, 64, Image.INTERPOLATE_NEAREST)
		img.blend_rect(ic2, Rect2i(0, 0, 64, 64), Vector2i((i % 6) * 68, (tids.size() + i / 6) * 68))
	img.save_png(path)
	print("  icon sheet: ", path)
