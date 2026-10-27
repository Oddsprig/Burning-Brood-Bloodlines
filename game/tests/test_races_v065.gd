extends RefCounted
## v0.065 verification & image capture: all 7 non-human humanoid races
## (dwarf, high_elf, moon_elf, dark_elf, orc, goblin, troll) in the 2.5D normal-mapped
## ShadedLayer style across standing paperdolls, horse mounts, dragon mounts, portraits,
## and a 100v100 mixed-race battle frame.

const NON_HUMAN_RACES: Array[String] = [
	"dwarf", "high_elf", "moon_elf", "dark_elf", "orc", "goblin", "troll"
]
const ALL_RACES: Array[String] = [
	"human", "dwarf", "high_elf", "moon_elf", "dark_elf", "orc", "goblin", "troll"
]

const FONT_5X7 := {
	" ": [0, 0, 0, 0, 0, 0, 0],
	"0": [14, 17, 19, 21, 25, 17, 14],
	"1": [4, 12, 4, 4, 4, 4, 14],
	"2": [14, 17, 1, 6, 8, 16, 31],
	"3": [31, 2, 4, 6, 1, 17, 14],
	"4": [2, 6, 10, 18, 31, 2, 2],
	"5": [31, 16, 30, 1, 1, 17, 14],
	"6": [6, 8, 16, 30, 17, 17, 14],
	"7": [31, 1, 2, 4, 8, 8, 8],
	"8": [14, 17, 17, 14, 17, 17, 14],
	"9": [14, 17, 17, 15, 1, 2, 12],
	"A": [14, 17, 17, 31, 17, 17, 17],
	"B": [30, 17, 17, 30, 17, 17, 30],
	"C": [14, 17, 16, 16, 16, 17, 14],
	"D": [28, 18, 17, 17, 17, 18, 28],
	"E": [31, 16, 16, 30, 16, 16, 31],
	"F": [31, 16, 16, 30, 16, 16, 16],
	"G": [14, 17, 16, 23, 17, 17, 15],
	"H": [17, 17, 17, 31, 17, 17, 17],
	"I": [14, 4, 4, 4, 4, 4, 14],
	"J": [7, 2, 2, 2, 2, 18, 12],
	"K": [17, 18, 20, 24, 20, 18, 17],
	"L": [16, 16, 16, 16, 16, 16, 31],
	"M": [17, 27, 21, 21, 17, 17, 17],
	"N": [17, 25, 21, 19, 17, 17, 17],
	"O": [14, 17, 17, 17, 17, 17, 14],
	"P": [30, 17, 17, 30, 16, 16, 16],
	"Q": [14, 17, 17, 17, 21, 18, 13],
	"R": [30, 17, 17, 30, 20, 18, 17],
	"S": [15, 16, 16, 14, 1, 1, 30],
	"T": [31, 4, 4, 4, 4, 4, 4],
	"U": [17, 17, 17, 17, 17, 17, 14],
	"V": [17, 17, 17, 17, 17, 10, 4],
	"W": [17, 17, 17, 21, 21, 27, 17],
	"X": [17, 17, 10, 4, 10, 17, 17],
	"Y": [17, 17, 10, 4, 4, 4, 4],
	"Z": [31, 1, 2, 4, 8, 16, 31],
	"-": [0, 0, 0, 31, 0, 0, 0],
	"_": [0, 0, 0, 0, 0, 0, 31],
	":": [0, 12, 12, 0, 12, 12, 0],
	".": [0, 0, 0, 0, 0, 12, 12],
	"(": [2, 4, 8, 8, 8, 4, 2],
	")": [8, 4, 2, 2, 2, 4, 8],
	"|": [4, 4, 4, 4, 4, 4, 4],
	"/": [1, 2, 2, 4, 8, 8, 16],
}

var pass_count: int = 0
var fail_count: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		pass_count += 1
	else:
		fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)

func _draw_text(img: Image, x: int, y: int, text: String, col: Color, scale: int = 2) -> void:
	var cx: int = x
	var up: String = text.to_upper()
	for i in up.length():
		var ch: String = up.substr(i, 1)
		var rows: Array = FONT_5X7.get(ch, FONT_5X7[" "])
		for ry in 7:
			var bits: int = int(rows[ry])
			for rx in 5:
				if (bits & (1 << (4 - rx))) != 0:
					img.fill_rect(Rect2i(cx + rx * scale, y + ry * scale, scale, scale), col)
		cx += 6 * scale

func _race_preset(race: String, armed: bool = true, female: bool = false) -> Dictionary:
	var rd: Dictionary = DB.races.get(race, DB.races["human"])
	var skins: Array = rd.get("skin", ["#e8c4a0"])
	var hairs: Array = rd.get("hair", ["#3a2a1a"])
	var prim := Color("#2c5fa8")
	var sec := Color("#e2b448")
	var cloth_tid := "tunic"
	var body_spec := {}
	var helm_spec := {}
	var weapon_spec := {}
	var shield_spec := {}
	var hands_spec := {}
	var legs_spec := {}
	var feet_spec := {"tid": "leather_boots", "sprite": "boots", "mat": "leather", "q": 1}
	match race:
		"dwarf":
			prim = Color("#8f2c24"); sec = Color("#e0a838")
			if armed:
				cloth_tid = "gambeson"
				body_spec = {"tid": "dwarf_mail", "sprite": "mail", "mat": "steel", "q": 2, "maker_race": "dwarf"}
				helm_spec = {"tid": "nasal_helm", "sprite": "nasal", "mat": "steel", "q": 2, "maker_race": "dwarf"}
				weapon_spec = {"tid": "dwarf_war_axe", "sprite": "axe", "mat": "steel", "q": 2, "two": false, "reach": 95}
				shield_spec = {"tid": "heavy_shield", "sprite": "round", "mat": "iron", "q": 2}
				hands_spec = {"tid": "dwarf_gauntlets", "sprite": "gauntlet", "mat": "steel", "q": 2}
				legs_spec = {"tid": "greaves", "sprite": "greaves", "mat": "steel", "q": 2}
		"high_elf":
			prim = Color("#2468b8"); sec = Color("#f0c850")
			if armed:
				body_spec = {"tid": "scale_hauberk", "sprite": "scale", "mat": "bronze", "q": 2, "maker_race": "high_elf"}
				helm_spec = {"tid": "crown", "sprite": "crown", "mat": "gold", "q": 2, "maker_race": "high_elf"}
				weapon_spec = {"tid": "arming_sword", "sprite": "sword", "mat": "steel", "q": 2, "two": false, "reach": 100}
				shield_spec = {"tid": "kite_shield", "sprite": "kite", "mat": "bronze", "q": 2}
				hands_spec = {"tid": "bracers", "sprite": "bracer", "mat": "bronze", "q": 2}
				legs_spec = {"tid": "greaves", "sprite": "greaves", "mat": "bronze", "q": 2}
		"moon_elf":
			prim = Color("#245878"); sec = Color("#98d8f8")
			if armed:
				body_spec = {"tid": "lamellar", "sprite": "lamellar", "mat": "steel", "q": 2, "maker_race": "moon_elf"}
				helm_spec = {"tid": "crescent_helm", "sprite": "crescent_helm", "mat": "steel", "q": 2, "maker_race": "moon_elf"}
				weapon_spec = {"tid": "glaive", "sprite": "glaive", "mat": "steel", "q": 2, "two": true, "reach": 150}
				hands_spec = {"tid": "arm_rings", "sprite": "arm_rings", "mat": "silver", "q": 2}
				legs_spec = {"tid": "moon_greaves", "sprite": "greaves", "mat": "steel", "q": 2}
		"dark_elf":
			prim = Color("#482058"); sec = Color("#c84868")
			if armed:
				body_spec = {"tid": "lamellar", "sprite": "lamellar", "mat": "iron", "q": 2, "maker_race": "dark_elf"}
				helm_spec = {"tid": "spangenhelm", "sprite": "spangen", "mat": "iron", "q": 2, "maker_race": "dark_elf"}
				weapon_spec = {"tid": "arming_sword", "sprite": "sword", "mat": "steel", "q": 2, "two": false, "reach": 100}
				shield_spec = {"tid": "heater_shield", "sprite": "heater", "mat": "iron", "q": 2}
				hands_spec = {"tid": "bracers", "sprite": "bracer", "mat": "iron", "q": 2}
				legs_spec = {"tid": "greaves", "sprite": "greaves", "mat": "iron", "q": 2}
		"orc":
			prim = Color("#8c281c"); sec = Color("#d08828")
			if armed:
				body_spec = {"tid": "scrap_armor", "sprite": "scrap", "mat": "iron", "q": 1, "maker_race": "orc"}
				helm_spec = {"tid": "spangenhelm", "sprite": "spangen", "mat": "iron", "q": 1, "maker_race": "orc"}
				weapon_spec = {"tid": "bearded_axe", "sprite": "axe", "mat": "iron", "q": 1, "two": false, "reach": 100}
				shield_spec = {"tid": "round_shield", "sprite": "round", "mat": "iron", "q": 1}
				hands_spec = {"tid": "crude_bracers", "sprite": "bracer", "mat": "iron", "q": 1}
				legs_spec = {"tid": "splint_greaves", "sprite": "greaves", "mat": "iron", "q": 1}
		"goblin":
			prim = Color("#6c5820"); sec = Color("#c89830")
			if armed:
				body_spec = {"tid": "byrnie", "sprite": "byrnie", "mat": "copper", "q": 1, "maker_race": "goblin"}
				helm_spec = {"tid": "kettle_hat", "sprite": "kettle", "mat": "copper", "q": 1, "maker_race": "goblin"}
				weapon_spec = {"tid": "short_spear", "sprite": "spear", "mat": "iron", "q": 1, "two": false, "reach": 130}
				shield_spec = {"tid": "buckler", "sprite": "round", "mat": "copper", "q": 1}
		"troll":
			prim = Color("#584228"); sec = Color("#a87838")
			if armed:
				body_spec = {"tid": "scrap_armor", "sprite": "scrap", "mat": "iron", "q": 1, "maker_race": "troll"}
				weapon_spec = {"tid": "war_maul", "sprite": "mace", "mat": "iron", "q": 1, "two": true, "reach": 140}
				hands_spec = {"tid": "crude_bracers", "sprite": "bracer", "mat": "iron", "q": 1}
		"human":
			prim = Color("#2458a8"); sec = Color("#e8b840")
			if armed:
				body_spec = {"tid": "cuirass", "sprite": "cuirass", "mat": "steel", "q": 2, "maker_race": "human"}
				helm_spec = {"tid": "nasal_helm", "sprite": "nasal", "mat": "steel", "q": 2, "maker_race": "human"}
				weapon_spec = {"tid": "arming_sword", "sprite": "sword", "mat": "steel", "q": 2, "two": false, "reach": 100}
				shield_spec = {"tid": "heater_shield", "sprite": "heater", "mat": "steel", "q": 2}
				hands_spec = {"tid": "gauntlets", "sprite": "gauntlet", "mat": "steel", "q": 2}
				legs_spec = {"tid": "greaves", "sprite": "greaves", "mat": "steel", "q": 2}

	var seed_val: int = 1 if not female else 61
	var spec := {
		"race": race,
		"skin": Color(skins[0]),
		"hair": Color(hairs[0]),
		"beard": (race in ["dwarf", "orc", "human", "troll"]) and not female,
		"seed": seed_val,
		"prim": FigurePainter._vivid(prim),
		"sec": FigurePainter._vivid(sec),
		"team": FigurePainter._vivid(prim),
		"role": "officer" if armed else "troop",
		"dead": false,
		"sex": "female" if female else "male",
		"age": 30,
		"weapon": weapon_spec,
		"shield": shield_spec,
		"body": body_spec,
		"helm": helm_spec if armed else {},
		"clothing": {"tid": cloth_tid, "sprite": "gambeson" if cloth_tid == "gambeson" else "tunic", "mat": "linen", "q": 1},
		"legs": legs_spec,
		"hands": hands_spec,
		"feet": feet_spec,
		"legs_under": {"tid": "trousers", "sprite": "", "mat": "linen", "q": 1},
		"dmg": {}, "wk": {}, "bleed": {}, "lost": [], "blood": 1.0
	}
	if not female and bool(spec["beard"]):
		spec["beard_style"] = 0
	return spec

func _scale_nearest(src: Image, scale: int) -> Image:
	var out: Image = src.duplicate()
	out.resize(src.get_width() * scale, src.get_height() * scale, Image.INTERPOLATE_NEAREST)
	return out

func _blit_alpha(dst: Image, src: Image, dst_pos: Vector2i) -> void:
	dst.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), dst_pos)

func _render_mounted_horse_card(spec: Dictionary, coat: String = "bay") -> Image:
	var card := Image.create(180, 180, false, Image.FORMAT_RGBA8)
	card.fill(Color(0, 0, 0, 0))
	var center := Vector2(90.0, 138.0)
	var horse_scale: float = HorseDoll.HORSE_SCALE
	var rider_ppu: float = HorseDoll.RIDER_PPU
	var seat: Vector2 = center + HorseArt.seat("trot", 0) * horse_scale

	var m_spec: Dictionary = spec.duplicate(true)
	m_spec["mount_kind"] = "horse"
	var layers: Dictionary = MountedRiderArt.render_layers(m_spec)
	var horse_tex: Texture2D = HorseArt.frame(coat, "trot", 0)
	var horse_img: Image = horse_tex.get_image()
	horse_img.convert(Image.FORMAT_RGBA8)
	var h_scaled: Image = horse_img.duplicate()
	h_scaled.resize(int(round(horse_img.get_width() * horse_scale)), int(round(horse_img.get_height() * horse_scale)), Image.INTERPOLATE_NEAREST)
	var h_pos := Vector2i(int(round(center.x - HorseArt.ANCHOR.x * horse_scale)), int(round(center.y - HorseArt.ANCHOR.y * horse_scale)))

	var xf: Transform2D = MountedRiderArt.placement(layers, seat, rider_ppu, 0.0)
	var r_origin: Vector2 = xf * Vector2.ZERO
	var r_scale: float = xf.x.length()

	for pass_name in ["far", "horse", "saddle", "near"]:
		if pass_name == "horse":
			_blit_alpha(card, h_scaled, h_pos)
		else:
			var l_img: Image = layers[pass_name].duplicate()
			l_img.resize(maxi(1, int(round(l_img.get_width() * r_scale))), maxi(1, int(round(l_img.get_height() * r_scale))), Image.INTERPOLATE_NEAREST)
			_blit_alpha(card, l_img, Vector2i(int(round(r_origin.x)), int(round(r_origin.y))))
	return card

func _render_portrait_card(spec: Dictionary) -> Image:
	var bust: Image = FigurePainter.render_bust(spec)
	var size: int = 128
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var prim: Color = spec.get("prim", Color(0.25, 0.25, 0.3))
	var bg: Color = prim.darkened(0.6).lerp(Color("#1a120d"), 0.45)
	out.fill(bg.darkened(0.22))
	var scaled: Image = bust.duplicate()
	scaled.resize(size - 8, size - 8, Image.INTERPOLATE_NEAREST)
	_blit_alpha(out, scaled, Vector2i(4, 4))
	# Gold/bronze portrait frame
	var border := Color("#d9a441")
	out.fill_rect(Rect2i(0, 0, size, 2), border)
	out.fill_rect(Rect2i(0, size - 2, size, 2), border)
	out.fill_rect(Rect2i(0, 0, 2, size), border)
	out.fill_rect(Rect2i(size - 2, 0, 2, size), border)
	return out

func _portrait_variant_spec(race: String, variant_idx: int) -> Dictionary:
	var rd: Dictionary = DB.races.get(race, DB.races["human"])
	var skins: Array = rd.get("skin", ["#e8c4a0"])
	var hairs: Array = rd.get("hair", ["#3a2a1a"])
	var female: bool = variant_idx >= 3
	var sp := _race_preset(race, variant_idx == 1 or variant_idx == 4, female)
	sp["helm"] = {}
	sp["skin"] = Color(skins[variant_idx % skins.size()])
	sp["hair"] = Color(hairs[variant_idx % hairs.size()])
	match variant_idx:
		0: # Young Male
			sp["sex"] = "male"
			sp["age"] = 20
			sp["beard"] = (race == "dwarf")
			sp["beard_style"] = 0
			sp["seed"] = 11
		1: # Adult Male (bearded / armed)
			sp["sex"] = "male"
			sp["age"] = 35
			sp["beard"] = (race in ["human", "dwarf", "orc", "troll"])
			sp["beard_style"] = 1
			sp["seed"] = 23
		2: # Elder Male
			sp["sex"] = "male"
			sp["age"] = 68
			sp["beard"] = (race in ["human", "dwarf", "orc", "troll", "high_elf", "moon_elf"])
			sp["beard_style"] = 2
			sp["hair"] = Color(hairs[variant_idx % hairs.size()]).lerp(Color("#d8d8dc"), 0.65)
			sp["seed"] = 37
		3: # Young Female
			sp["sex"] = "female"
			sp["age"] = 21
			sp["beard"] = false
			sp["seed"] = 61
		4: # Elder Female
			sp["sex"] = "female"
			sp["age"] = 66
			sp["beard"] = false
			sp["hair"] = Color(hairs[variant_idx % hairs.size()]).lerp(Color("#d8d8dc"), 0.6)
			sp["seed"] = 79
	return sp

func _draw_v0066_portrait_half(img: Image, race: String, y_off: int, header_prefix: String) -> void:
	FigurePainter.set_legacy_v064(false)
	img.fill_rect(Rect2i(0, y_off, 920, 240), Color("#12161e"))
	img.fill_rect(Rect2i(0, y_off, 920, 28), Color("#1e2432"))
	_draw_text(img, 12, y_off + 7, "%s - %s PORTRAITS (AGE / SEX VARIANTS)" % [header_prefix, race.replace("_", " ")], Color("#f2da94"), 2)
	var labels := ["YOUNG MALE", "ADULT MALE", "ELDER MALE", "YOUNG FEMALE", "ELDER FEMALE"]
	for i in 5:
		var sp := _portrait_variant_spec(race, i)
		var card := _render_portrait_card(sp)
		var big := _scale_nearest(card, 1)
		big.resize(156, 156, Image.INTERPOLATE_NEAREST)
		var cx: int = 16 + i * 180
		var cy: int = y_off + 36
		_blit_alpha(img, big, Vector2i(cx, cy))
		_draw_text(img, cx + 10, cy + 164, labels[i], Color("#9ab4d0"), 1)

func _save_v0066_portrait_before_after(out_dir: String, race: String) -> void:
	var path: String = out_dir.path_join("v0066_portrait_before_after_%s.png" % race)
	var sheet: Image
	if FileAccess.file_exists(path):
		sheet = Image.load_from_file(path)
		if sheet == null or sheet.get_width() != 920 or sheet.get_height() != 480:
			sheet = Image.create(920, 480, false, Image.FORMAT_RGBA8)
			_draw_v0066_portrait_half(sheet, race, 0, "BEFORE (B78F919)")
	else:
		sheet = Image.create(920, 480, false, Image.FORMAT_RGBA8)
		_draw_v0066_portrait_half(sheet, race, 0, "BEFORE (B78F919)")
	_draw_v0066_portrait_half(sheet, race, 240, "AFTER (V0.066 FIXED EYES)")
	sheet.fill_rect(Rect2i(0, 238, 920, 2), Color("#38465e"))
	check(sheet.save_png(path) == OK, "saved " + path)

func _draw_v0066_troll_half(img: Image, y_off: int, header_prefix: String) -> void:
	FigurePainter.set_legacy_v064(false)
	img.fill_rect(Rect2i(0, y_off, 860, 270), Color("#12161e"))
	img.fill_rect(Rect2i(0, y_off, 860, 28), Color("#1e2432"))
	_draw_text(img, 12, y_off + 7, "%s - TROLL MASSING, IDLE ARMS & PORTRAIT" % header_prefix, Color("#f2da94"), 2)

	var sp_bare := _race_preset("troll", false, false)
	sp_bare["clothing"] = {}
	sp_bare["feet"] = {}
	var sp_unarmed := _race_preset("troll", false, false)
	var sp_maul := _race_preset("troll", true, false)
	sp_maul["role"] = "troop"
	var sp_cleaver := _race_preset("troll", true, false)
	sp_cleaver["role"] = "troop"
	sp_cleaver["weapon"] = {"tid": "hacking_cleaver", "sprite": "axe", "mat": "iron", "q": 1, "two": false, "reach": 105}
	sp_cleaver["shield"] = {"tid": "slab_shield", "sprite": "heater", "mat": "iron", "q": 1}

	var specs := [sp_bare, sp_unarmed, sp_maul, sp_cleaver]
	var poses := ["idle", "idle", "idle", "prepare"]
	var titles := ["BARE BODY", "UNARMED IDLE", "WAR MAUL", "CLEAVER+SHIELD"]
	for i in 4:
		var fig: Image = _scale_nearest(FigurePainter.render(specs[i], poses[i], 0.0), 2)
		var dm: Dictionary = FigurePainter.frame_dims(specs[i], poses[i])
		var anc: Vector2 = dm["anchor"] * 2.0
		var cx: int = 85 + i * 165
		var base_y: int = y_off + 232
		_blit_alpha(img, fig, Vector2i(int(cx - anc.x), int(base_y - anc.y)))
		_draw_text(img, cx - 38, y_off + 244, titles[i], Color("#9ab4d0"), 1)

	var sp_port := _portrait_variant_spec("troll", 1)
	var port_card := _render_portrait_card(sp_port)
	port_card.resize(164, 164, Image.INTERPOLATE_NEAREST)
	_blit_alpha(img, port_card, Vector2i(674, y_off + 52))
	_draw_text(img, 706, y_off + 244, "PORTRAIT BUST", Color("#9ab4d0"), 1)

func _save_v0066_troll_before_after(out_dir: String) -> void:
	var path: String = out_dir.path_join("v0066_troll_before_after.png")
	var sheet: Image
	if FileAccess.file_exists(path):
		sheet = Image.load_from_file(path)
		if sheet == null or sheet.get_width() != 860 or sheet.get_height() != 540:
			sheet = Image.create(860, 540, false, Image.FORMAT_RGBA8)
			_draw_v0066_troll_half(sheet, 0, "BEFORE (B78F919)")
	else:
		sheet = Image.create(860, 540, false, Image.FORMAT_RGBA8)
		_draw_v0066_troll_half(sheet, 0, "BEFORE (B78F919)")
	sheet.fill_rect(Rect2i(0, 0, 860, 28), Color("#1e2432"))
	_draw_text(sheet, 12, 7, "BEFORE (B78F919) - TROLL MASSING, IDLE ARMS & PORTRAIT", Color("#f2da94"), 2)
	_draw_v0066_troll_half(sheet, 270, "AFTER (V0.066 ORGANIC)")
	sheet.fill_rect(Rect2i(0, 268, 860, 2), Color("#38465e"))
	check(sheet.save_png(path) == OK, "saved " + path)

func _save_v0066_race_standing_lineup(out_dir: String) -> void:
	FigurePainter.set_legacy_v064(false)
	var sheet := Image.create(1240, 540, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#10141c"))
	sheet.fill_rect(Rect2i(0, 0, 1240, 34), Color("#1c2230"))
	_draw_text(sheet, 16, 10, "V0.066 STANDING IDLE LINEUP - ALL 8 RACES (ARMS AT SIDES / WEAPON READY, NO FOLDED ARMS)", Color("#f4dc96"), 2)

	for i in ALL_RACES.size():
		var race: String = ALL_RACES[i]
		var col: int = i % 4
		var row: int = i / 4
		var ox: int = 12 + col * 306
		var oy: int = 44 + row * 242
		sheet.fill_rect(Rect2i(ox, oy, 298, 232), Color("#161b26"))
		sheet.fill_rect(Rect2i(ox, oy, 298, 24), Color("#202838"))
		_draw_text(sheet, ox + 10, oy + 5, race.replace("_", " "), Color("#f0d890"), 2)

		var sp_m := _race_preset(race, false, false)
		var sp_f := _race_preset(race, false, true)
		var sp_w := _race_preset(race, true, false)
		if race == "troll":
			sp_w["role"] = "troop"
		var fig_m: Image = _scale_nearest(FigurePainter.render(sp_m, "idle", 0.0), 2)
		var fig_f: Image = _scale_nearest(FigurePainter.render(sp_f, "idle", 0.0), 2)
		var fig_w: Image = _scale_nearest(FigurePainter.render(sp_w, "idle", 0.0), 2)
		var dm: Dictionary = FigurePainter.frame_dims(sp_w, "idle")
		var anc: Vector2 = dm["anchor"] * 2.0
		var base_y: int = oy + (204 if race == "troll" else 196)
		_blit_alpha(sheet, fig_m, Vector2i(int(ox + 56 - anc.x), int(base_y - anc.y)))
		_blit_alpha(sheet, fig_f, Vector2i(int(ox + 136 - anc.x), int(base_y - anc.y)))
		_blit_alpha(sheet, fig_w, Vector2i(int(ox + 224 - anc.x), int(base_y - anc.y)))
		_draw_text(sheet, ox + 28, oy + 214, "MALE IDLE", Color("#9ab0c8"), 1)
		_draw_text(sheet, ox + 108, oy + 214, "FEM IDLE", Color("#9ab0c8"), 1)
		_draw_text(sheet, ox + 196, oy + 214, "ARMED IDLE", Color("#9ab0c8"), 1)

	var path: String = out_dir.path_join("v0066_race_standing_lineup.png")
	check(sheet.save_png(path) == OK, "saved " + path)

func _save_v0066_troll_on_foot_only(out_dir: String) -> void:
	FigurePainter.set_legacy_v064(false)
	var sheet := Image.create(980, 340, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#12161e"))
	sheet.fill_rect(Rect2i(0, 0, 980, 34), Color("#1e2432"))
	_draw_text(sheet, 14, 10, "V0.066 TROLLS FIGHT ON FOOT ONLY - NO HORSE MOUNTS ALLOWED", Color("#f4dc96"), 2)

	var sp_bare := _race_preset("troll", false, false)
	sp_bare["clothing"] = {}
	sp_bare["feet"] = {}
	var sp_unarmed := _race_preset("troll", false, false)
	var sp_maul := _race_preset("troll", true, false)
	sp_maul["role"] = "troop"
	var sp_club := _race_preset("troll", true, false)
	sp_club["role"] = "troop"
	sp_club["weapon"] = {"tid": "great_club", "sprite": "mace", "mat": "wood", "q": 1, "two": true, "reach": 140}
	var sp_cleaver := _race_preset("troll", true, false)
	sp_cleaver["role"] = "troop"
	sp_cleaver["weapon"] = {"tid": "hacking_cleaver", "sprite": "axe", "mat": "iron", "q": 1, "two": false, "reach": 105}
	sp_cleaver["shield"] = {"tid": "slab_shield", "sprite": "heater", "mat": "iron", "q": 1}

	var specs := [sp_bare, sp_unarmed, sp_maul, sp_club, sp_cleaver]
	var poses := ["idle", "walk", "idle", "strike", "prepare"]
	var t_vals := [0.0, 0.25, 0.0, 0.35, 0.5]
	var labels := ["BARE ON FOOT", "MARCH ON FOOT", "MAUL ON FOOT", "STRIKE ON FOOT", "CLEAVER+SHIELD"]

	for i in 5:
		var cx: int = 86 + i * 142
		var base_y: int = 268
		var fig: Image = _scale_nearest(FigurePainter.render(specs[i], poses[i], t_vals[i]), 2)
		var dm: Dictionary = FigurePainter.frame_dims(specs[i], poses[i])
		var anc: Vector2 = dm["anchor"] * 2.0
		_blit_alpha(sheet, fig, Vector2i(int(cx - anc.x), int(base_y - anc.y)))
		_draw_text(sheet, cx - 42, 286, labels[i], Color("#9ab4d0"), 1)

	# Verification badge box on the right confirming mount rejection in code
	sheet.fill_rect(Rect2i(748, 56, 216, 236), Color("#1b212e"))
	sheet.fill_rect(Rect2i(748, 56, 216, 24), Color("#582626"))
	_draw_text(sheet, 760, 65, "MOUNT CODE GATE: REFUSED", Color("#ffd0c8"), 1)
	_draw_text(sheet, 758, 98, "HORSES.CAN_MOUNT_RACE:", Color("#c8d6e8"), 1)
	_draw_text(sheet, 768, 114, "TROLL -> FALSE", Color("#88f0a8"), 1)
	_draw_text(sheet, 768, 130, "GIANT -> FALSE", Color("#88f0a8"), 1)
	_draw_text(sheet, 758, 158, "MOUNTEDRIDERART:", Color("#c8d6e8"), 1)
	_draw_text(sheet, 768, 174, "OK -> FALSE (ON FOOT)", Color("#88f0a8"), 1)
	_draw_text(sheet, 758, 202, "UNITVIEW / BATTLE:", Color("#c8d6e8"), 1)
	_draw_text(sheet, 768, 218, "PAPERDOLL ONLY", Color("#88f0a8"), 1)
	_draw_text(sheet, 768, 234, "NO HORSEDOLL", Color("#88f0a8"), 1)

	var path: String = out_dir.path_join("v0066_troll_on_foot_only.png")
	check(sheet.save_png(path) == OK, "saved " + path)

func _verify_v0066_contracts() -> void:
	FigurePainter.set_legacy_v064(false)
	# 1. Portrait eye, nose, and mouth landmarks across all 8 races and 5 age/sex variants
	for race in ALL_RACES:
		for v_idx in 5:
			var sp := _portrait_variant_spec(race, v_idx)
			var lm: Dictionary = FigurePainter.head_landmarks(sp)
			var h_top: float = float(lm["head_top"])
			var h_bot: float = float(lm["head_bottom"])
			var head_span: float = h_bot - h_top
			var eye_r: Vector2 = lm["eye_r"]
			var eye_l: Vector2 = lm["eye_l"]
			var nose_b: Vector2 = lm["nose_bridge"]
			var nose_t: Vector2 = lm["nose_tip"]
			var mouth: Vector2 = lm["mouth"]
			var rel_r: float = (eye_r.y - h_top) / maxf(0.01, head_span)
			var rel_l: float = (eye_l.y - h_top) / maxf(0.01, head_span)
			check(rel_r >= 0.40 and rel_r <= 0.56 and rel_l >= 0.40 and rel_l <= 0.56,
				"%s v%d eyes at mid-head height (rel_y=%.2f, %.2f)" % [race, v_idx, rel_r, rel_l])
			check(is_equal_approx(eye_r.y, eye_l.y),
				"%s v%d eyes symmetric in y (%.2f vs %.2f)" % [race, v_idx, eye_r.y, eye_l.y])
			check(eye_r.x < nose_b.x and nose_b.x < eye_l.x and (eye_l.x - eye_r.x) >= 1.2,
				"%s v%d both eyes on front plane straddling nose bridge" % [race, v_idx])
			check(nose_t.y > eye_r.y and mouth.y > nose_t.y and mouth.y < h_bot,
				"%s v%d visible nose and mouth ordered below eyes" % [race, v_idx])

	# 2. Trolls and giants refused by mounted-unit code
	check(not Horses.can_mount_race("troll") and not Horses.can_mount_race("giant"),
		"Horses.can_mount_race refuses troll and giant")
	check(not MountedRiderArt.can_mount_race("troll") and not MountedRiderArt.can_mount_race("giant"),
		"MountedRiderArt.can_mount_race refuses troll and giant")
	check(not bool(MountedRiderArt.render_layers({"race": "troll"}).get("ok", true)),
		"MountedRiderArt.render_layers refuses troll")
	check(not bool(MountedRiderArt.render_layers({"race": "giant"}).get("ok", true)),
		"MountedRiderArt.render_layers refuses giant")
	var troll_u: Unit = Unit.create("troll", "troll_den")
	var dummy_horse: Unit = Unit.create("horse", "troll_den", false)
	troll_u.horse = dummy_horse
	troll_u.horse_care = {"fed": true, "paid": true}
	check(not Horses.can_field(troll_u), "Horses.can_field refuses troll even if horse attached")
	check(not MountedRiderArt.spec_for_unit(troll_u).has("mount_kind"), "MountedRiderArt.spec_for_unit omits mount_kind for troll")
	var sim_troll := BattleSim.new()
	var orc_u: Unit = Unit.create("orc", "red_skull")
	sim_troll.setup([troll_u], [orc_u], 101, {"w": 16, "h": 10, "max_ticks": 10, "log_moves": false})
	check(sim_troll.fighters.size() == 2 and sim_troll.fighters[0].mount_idx == -1,
		"MountedCombat.setup refuses to spawn horse fighter for troll")
	var UnitViewScript := preload("res://battle/unit_view.gd")
	var uv: Node2D = UnitViewScript.new()
	uv.setup(sim_troll.fighters[0], 40.0)
	check(uv.doll is Paperdoll and not (uv.doll is HorseDoll),
		"UnitView uses on-foot Paperdoll for troll even if horse ref present")
	uv.free()

	# 3. No folded-arm idle pose across any race (unarmed male, unarmed female, armed)
	for race in ALL_RACES:
		for mode in 3:
			var sp := _race_preset(race, mode == 2, mode == 1)
			if race == "troll":
				sp["role"] = "troop"
			var fp := FigurePainter.new(sp)
			fp.pose = "idle"
			fp.t = 0.0
			fp._rig()
			var sr: Vector2 = fp.j["sr"]
			var er: Vector2 = fp.j["er"]
			var hr: Vector2 = fp.j["hr"]
			var sl: Vector2 = fp.j["sl"]
			var el: Vector2 = fp.j["el"]
			var hl: Vector2 = fp.j["hl"]
			if mode < 2:
				check(hr.x < sr.x and hr.x < 0.0 and hl.x > sl.x and hl.x > 0.0,
					"%s mode %d unarmed idle hands stay outside shoulders (no folded arms across stomach)" % [race, mode])
				check(hr.y > er.y and er.y > sr.y and hl.y > el.y and el.y > sl.y,
					"%s mode %d unarmed idle arms hang naturally downward at sides" % [race, mode])
			else:
				check(fp._wkind() != "none" and fp.j["grip"] == hr and hl.x > 0.0,
					"%s mode %d armed idle holds weapon in grip with off-hand at shield/shaft/side" % [race, mode])

func _build_race_panel(race: String, is_legacy: bool) -> Image:
	FigurePainter.set_legacy_v064(is_legacy)
	var panel := Image.create(520, 230, false, Image.FORMAT_RGBA8)
	panel.fill(Color("#141820"))

	var sp_civic := _race_preset(race, false, false)
	var sp_armed := _race_preset(race, true, false)
	if race == "troll":
		sp_armed["role"] = "troop"
	var sp_fem := _race_preset(race, false, true)

	# 1. Standing figures (unarmoured male, female, and armed warrior)
	var stand_m: Image = _scale_nearest(FigurePainter.render(sp_civic, "idle", 0.0), 2)
	var stand_f: Image = _scale_nearest(FigurePainter.render(sp_fem, "idle", 0.0), 2)
	var stand_w: Image = _scale_nearest(FigurePainter.render(sp_armed, "idle", 0.0), 2)
	var dm: Dictionary = FigurePainter.frame_dims(sp_armed, "idle")
	var anc: Vector2 = dm["anchor"] * 2.0
	var base_y: int = 200 if race == "troll" else 194
	_blit_alpha(panel, stand_m, Vector2i(int(48 - anc.x), int(base_y - anc.y)))
	_blit_alpha(panel, stand_f, Vector2i(int(112 - anc.x), int(base_y - anc.y)))
	_blit_alpha(panel, stand_w, Vector2i(int(180 - anc.x), int(base_y - anc.y)))
	_draw_text(panel, 28, 208, "STANDING", Color("#9ab0c8"), 1)

	# 2. Mounted on a horse (or on-foot heavy shock poses for troll, which never rides horses)
	if race == "troll":
		var sp_strike := sp_armed.duplicate(true)
		var stand_strike: Image = _scale_nearest(FigurePainter.render(sp_strike, "strike", 0.35), 2)
		var dm_s: Dictionary = FigurePainter.frame_dims(sp_strike, "strike")
		var anc_s: Vector2 = dm_s["anchor"] * 2.0
		_blit_alpha(panel, stand_strike, Vector2i(int(295 - anc_s.x), int(base_y - anc_s.y)))
		_draw_text(panel, 240, 208, "ON FOOT ONLY (NO MOUNT)", Color("#9ab0c8"), 1)
	else:
		var horse_card: Image = _render_mounted_horse_card(sp_armed, "bay" if race in ["dwarf", "human", "orc"] else ("palomino" if race in ["high_elf", "moon_elf"] else "black"))
		_blit_alpha(panel, horse_card, Vector2i(205, 32))
		_draw_text(panel, 250, 208, "MOUNTED (HORSE)", Color("#9ab0c8"), 1)

	# 3. Portrait (unhelm'd so full head/face/hair/beard shading is clear)
	var sp_port := sp_armed.duplicate(true)
	sp_port["helm"] = {}
	var port_card: Image = _render_portrait_card(sp_port)
	_blit_alpha(panel, port_card, Vector2i(378, 56))
	_draw_text(panel, 412, 208, "PORTRAIT", Color("#9ab0c8"), 1)

	# Header bar drawn on top so tall figures/standards never obscure the title
	panel.fill_rect(Rect2i(0, 0, 520, 28), Color("#1e2430"))
	var tag: String = "BEFORE (V0.064 FLAT)" if is_legacy else "AFTER (V0.065 2.5D SHADED)"
	_draw_text(panel, 10, 7, "%s - %s" % [race.replace("_", " "), tag], Color("#f0d890"), 2)

	FigurePainter.set_legacy_v064(false)
	return panel

func _make_battle_unit(race: String, faction_id: String, idx: int) -> Unit:
	var u: Unit = Unit.create(race, faction_id)
	u.sex = 1 if (idx % 4 == 1 and race != "troll") else 0
	var gear: Array = [["tunic", "linen"], ["trousers", "linen"], ["leather_boots", "leather"]]
	match race:
		"human":
			gear.append_array([
				["arming_sword" if idx % 2 == 0 else "spear", "steel", 1],
				["heater_shield", "steel", 1],
				["cuirass" if idx % 3 == 0 else "mail_shirt", "steel", 1],
				["nasal_helm", "steel", 1]
			])
		"dwarf":
			gear = [["gambeson", "linen"], ["trousers", "linen"], ["leather_boots", "leather"],
				["dwarf_war_axe" if idx % 2 == 0 else "war_hammer", "steel", 2],
				["heavy_shield", "iron", 2],
				["dwarf_mail", "steel", 2],
				["nasal_helm" if idx % 2 == 0 else "spangenhelm", "steel", 2],
				["dwarf_gauntlets", "steel", 1]]
		"high_elf":
			gear.append_array([
				["arming_sword" if idx % 2 == 0 else "spear", "bronze", 2],
				["kite_shield", "bronze", 2],
				["scale_hauberk", "bronze", 2],
				["crown" if idx % 4 == 0 else "nasal_helm", "gold" if idx % 4 == 0 else "bronze", 2]
			])
		"moon_elf":
			gear.append_array([
				["glaive" if idx % 2 == 0 else "arming_sword", "steel", 2],
				["lamellar", "steel", 2],
				["crescent_helm", "steel", 2],
				["moon_greaves", "steel", 2]
			])
		"dark_elf":
			gear.append_array([
				["arming_sword" if idx % 2 == 0 else "spear", "iron", 2],
				["heater_shield", "iron", 2],
				["lamellar", "iron", 2],
				["spangenhelm", "iron", 2]
			])
		"orc":
			gear.append_array([
				["bearded_axe" if idx % 2 == 0 else "hacking_cleaver", "iron", 1],
				["round_shield", "iron", 1],
				["scrap_armor" if idx % 2 == 0 else "lamellar", "iron", 1],
				["spangenhelm", "iron", 1]
			])
		"goblin":
			gear.append_array([
				["short_spear" if idx % 2 == 0 else "dagger", "copper", 1],
				["buckler", "copper", 1],
				["byrnie", "copper", 1],
				["kettle_hat", "copper", 1]
			])
		"troll":
			gear = [["tunic", "linen"], ["trousers", "linen"],
				["war_maul" if idx % 2 == 0 else "great_club", "iron", 1],
				["scrap_armor", "iron", 1],
				["crude_bracers", "iron", 1]]
	for g in gear:
		if DB.template(String(g[0])).is_empty():
			continue
		var it: Item = Item.make(String(g[0]), String(g[1]) if g.size() > 1 else "", int(g[2]) if g.size() > 2 else 0)
		if it != null:
			u.equip[it.slot()] = it
	u.skills["fighter"] = 3
	u.skills["sword"] = 3
	u.skills["axe"] = 3
	u.skills["spear"] = 3
	u.skills["mace"] = 3
	return u

func _flip_h_copy(src: Image) -> Image:
	var out: Image = src.duplicate()
	out.flip_x()
	return out

func _build_100v100_battle(tree: SceneTree, out_path: String) -> float:
	FigurePainter.set_legacy_v064(false)
	Paperdoll.clear_cache()
	Paperdoll.begin_background()
	var side0: Array = []
	var side1: Array = []
	var left_races := ["human", "dwarf", "high_elf", "moon_elf"]
	var right_races := ["orc", "goblin", "dark_elf", "troll"]
	var coats := ["bay", "chestnut", "black", "palomino", "grey"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 65065

	for i in 100:
		var r0: String = left_races[i % left_races.size()]
		var u0: Unit = _make_battle_unit(r0, "middle_kingdom", i)
		Factory.roll_look(rng, u0)
		if i < 12 and r0 != "troll":
			var h0: Unit = Unit.create("horse", "middle_kingdom")
			h0.look = {"coat": coats[i % coats.size()]}
			u0.horse = h0
		side0.append(u0)

		var r1: String = right_races[i % right_races.size()]
		var u1: Unit = _make_battle_unit(r1, "red_skull", i)
		Factory.roll_look(rng, u1)
		if i < 12 and r1 != "troll":
			var h1: Unit = Unit.create("horse", "red_skull")
			h1.look = {"coat": coats[(i + 2) % coats.size()]}
			u1.horse = h1
		side1.append(u1)

	var sim := BattleSim.new()
	sim.setup(side0, side1, 65065, {"w": 36, "h": 18, "max_ticks": 600, "log_moves": false})

	var UnitViewScript := preload("res://battle/unit_view.gd")
	var views: Array = []
	for f: Fighter in sim.fighters:
		var v: Node2D = UnitViewScript.new()
		v.setup(f, 40.0)
		if v.doll.has_method("set_background_rendering"):
			v.doll.set_background_rendering(true)
		views.append(v)

	# Warm up a few ticks and settle background worker jobs so initial frames are cached
	for _w in 8:
		if not sim.is_over():
			sim.step()
	var view_rect := Rect2(Vector2(-200, -200), Vector2(2000, 1300))
	for _w in 20:
		for v in views:
			v.update_visual(0.5, 0.016, view_rect)
		Paperdoll.pump_background()
		await tree.process_frame

	# Measure 30 battle + visual frames across all 200 units
	var frame_times_ms: Array[float] = []
	for step in 30:
		var t0: int = Time.get_ticks_usec()
		if step % 3 == 0 and not sim.is_over():
			sim.step()
		var frac: float = float(step % 3) / 3.0
		for v in views:
			v.update_visual(frac, 0.016, view_rect)
		Paperdoll.pump_background()
		var dt_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		frame_times_ms.append(dt_ms)

	var sum_ms: float = 0.0
	for v_ms in frame_times_ms:
		sum_ms += v_ms
	var mean_ms: float = sum_ms / float(frame_times_ms.size())
	var sorted_ms := frame_times_ms.duplicate()
	sorted_ms.sort()
	var p95_ms: float = sorted_ms[mini(sorted_ms.size() - 1, int(ceil(sorted_ms.size() * 0.95)) - 1)]
	var fps: float = 1000.0 / maxf(0.01, mean_ms)

	# Render the 1600x900 battlefield frame
	var frame_img := Image.create(1600, 900, false, Image.FORMAT_RGBA8)
	frame_img.fill(Color("#1b2419"))
	for ly in range(56, 900, 40):
		frame_img.fill_rect(Rect2i(0, ly, 1600, 1), Color("#2e3b2b"))

	# Build draw entries for all 200 units (both active front-line and reserve ranks)
	var draw_list: Array = []
	var s0_idx: int = 0
	var s1_idx: int = 0
	for v in views:
		var f: Fighter = v.fighter
		if f.mount_attached:
			continue
		var rank_idx: int = s0_idx if f.side == 0 else s1_idx
		if f.side == 0:
			s0_idx += 1
		else:
			s1_idx += 1
		var col_in_side: int = rank_idx / 10
		var row_in_side: int = rank_idx % 10
		var jitter_x: int = ((rank_idx * 17) % 15) - 7
		var jitter_y: int = ((rank_idx * 23) % 13) - 6
		var px: int
		if f.side == 0:
			px = 520 - col_in_side * 44 + jitter_x
		else:
			px = 1080 + col_in_side * 44 + jitter_x
		var py: int = 128 + row_in_side * 74 + jitter_y
		draw_list.append({"v": v, "f": f, "px": px, "py": py, "rank_idx": rank_idx})

	draw_list.sort_custom(func(a, b): return int(a["py"]) < int(b["py"]))

	var pose_Choices := ["idle", "walk", "prepare", "strike", "recover"]
	for idx in draw_list.size():
		var entry: Dictionary = draw_list[idx]
		var f: Fighter = entry["f"]
		var u: Unit = f.unit
		var px: int = int(entry["px"])
		var py: int = int(entry["py"])
		var facing: int = 1 if f.side == 0 else -1
		var team_col: Color = Color(0.25, 0.6, 1.0) if f.side == 0 else Color(1.0, 0.27, 0.2)
		var spec: Dictionary = FigurePainter.spec_for_unit(u, team_col)
		var r_pal := _race_preset(u.race, true, false)
		spec["prim"] = r_pal["prim"]
		spec["sec"] = r_pal["sec"]
		# Draw selection/team base ring
		frame_img.fill_rect(Rect2i(px - 12, py - 2, 24, 3), team_col.darkened(0.25))
		frame_img.fill_rect(Rect2i(px - 8, py - 3, 16, 1), team_col)

		if u.horse != null:
			var coat: String = String(u.horse.look.get("coat", "bay"))
			var h_card: Image = _render_mounted_horse_card(spec, coat)
			if facing < 0:
				h_card = _flip_h_copy(h_card)
			_blit_alpha(frame_img, h_card, Vector2i(px - 90, py - 142))
		else:
			var pose: String = pose_Choices[idx % pose_Choices.size()]
			var fig: Image = FigurePainter.render(spec, pose, float(idx % 5) * 0.2)
			var d_scale: float = FigurePainter.display_scale(u.race)
			var dm: Dictionary = FigurePainter.frame_dims(spec, pose)
			var w_sc: int = maxi(1, int(round(fig.get_width() * d_scale)))
			var h_sc: int = maxi(1, int(round(fig.get_height() * d_scale)))
			var scaled: Image = fig.duplicate()
			scaled.resize(w_sc, h_sc, Image.INTERPOLATE_NEAREST)
			var anc_x: int = int(round(dm["anchor"].x * d_scale))
			var anc_y: int = int(round(dm["anchor"].y * d_scale))
			if facing < 0:
				scaled.flip_x()
				anc_x = w_sc - anc_x
			_blit_alpha(frame_img, scaled, Vector2i(px - anc_x, py - anc_y))

	# Also composite a Sapphire Spirewing dragon + shaded non-human rider on each flank
	var d_left_spec := _race_preset("high_elf", true, false)
	var d_right_spec := _race_preset("orc", true, false)
	var d_row_l := {"id": "dragon:battle:0", "name": "Aurewing", "gem_id": "sapphire", "morph_id": "spirewing", "size_class": "medium", "appearance_seed": 651, "stage": "adult", "alive": true}
	var d_row_r := {"id": "dragon:battle:1", "name": "Gloomfang", "gem_id": "ruby", "morph_id": "spirewing", "size_class": "medium", "appearance_seed": 652, "stage": "adult", "alive": true}
	var d_img_l: Image = DragonMountPreviewArt.image_for(d_row_l, d_left_spec, "walk", false, 0.35)
	var d_img_r: Image = _flip_h_copy(DragonMountPreviewArt.image_for(d_row_r, d_right_spec, "strike", false, 0.45))
	var d_l_small: Image = d_img_l.duplicate()
	d_l_small.resize(360, 210, Image.INTERPOLATE_NEAREST)
	var d_r_small: Image = d_img_r.duplicate()
	d_r_small.resize(360, 210, Image.INTERPOLATE_NEAREST)
	_blit_alpha(frame_img, d_l_small, Vector2i(80, 470))
	_blit_alpha(frame_img, d_r_small, Vector2i(1160, 490))

	frame_img.fill_rect(Rect2i(0, 0, frame_img.get_width(), 42), Color("#10141c"))
	frame_img.fill_rect(Rect2i(0, 42, frame_img.get_width(), 2), Color("#2a3244"))
	var banner := "100V100 BATTLE (200 UNITS) - FRAME TIME: %.2f MS (P95: %.2f MS | %.1f FPS)" % [mean_ms, p95_ms, fps]
	_draw_text(frame_img, 20, 14, banner, Color("#98f0b8"), 2)
	frame_img.save_png(out_path)
	print("100v100 mixed-race battle frame time: %.2f ms (p95: %.2f ms, %.1f FPS)" % [mean_ms, p95_ms, fps])

	Paperdoll.end_background()
	for v in views:
		v.free()
	Paperdoll.clear_cache()
	return mean_ms

func run(tree: SceneTree) -> int:
	var out_dir: String = ProjectSettings.globalize_path("res://").path_join("../test-results").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)

	for race in ALL_RACES:
		_save_v0066_portrait_before_after(out_dir, race)
	_save_v0066_troll_before_after(out_dir)
	_save_v0066_race_standing_lineup(out_dir)
	_save_v0066_troll_on_foot_only(out_dir)
	_verify_v0066_contracts()

	var after_panels: Array[Image] = []
	# Also include human panel at top of combined lineup
	var human_panel: Image = _build_race_panel("human", false)
	after_panels.append(human_panel)

	for race in NON_HUMAN_RACES:
		var sp_test := _race_preset(race, true, false)
		sp_test["helm"] = {}
		FigurePainter.set_legacy_v064(true)
		var img_before_fig: Image = FigurePainter.render(sp_test, "idle", 0.0)
		var img_before_bust: Image = FigurePainter.render_bust(sp_test)
		FigurePainter.set_legacy_v064(false)
		var img_after_fig: Image = FigurePainter.render(sp_test, "idle", 0.0)
		var img_after_bust: Image = FigurePainter.render_bust(sp_test)

		check(img_before_fig.get_data() != img_after_fig.get_data(), "%s standing figure updated to v0.065 2.5D shaded style" % race)
		check(img_before_bust.get_data() != img_after_bust.get_data(), "%s portrait bust updated to v0.065 2.5D shaded style" % race)

		var layers: Dictionary = MountedRiderArt.render_layers(sp_test)
		if race == "troll":
			check(not bool(layers.get("ok", true)), "troll rejected by MountedRiderArt.render_layers")
		else:
			check(bool(layers.get("ok", false)), "%s MountedRiderArt layers build cleanly" % race)

		var before_panel: Image = _build_race_panel(race, true)
		var after_panel: Image = _build_race_panel(race, false)
		after_panels.append(after_panel)

		var before_path: String = out_dir.path_join("v0065_%s_before.png" % race)
		var after_path: String = out_dir.path_join("v0065_%s_after.png" % race)
		check(before_panel.save_png(before_path) == OK, "saved " + before_path)
		check(after_panel.save_png(after_path) == OK, "saved " + after_path)

	# Build combined 8-race lineup sheet (2 columns x 4 rows)
	var lineup := Image.create(1060, 960, false, Image.FORMAT_RGBA8)
	lineup.fill(Color("#0d1016"))
	_draw_text(lineup, 18, 10, "V0.065 ALL 8 HUMANOID RACES IN 2.5D SHADED STYLE (STANDING / HORSE MOUNT / PORTRAIT)", Color("#f4dc96"), 2)
	for idx in after_panels.size():
		var col: int = idx % 2
		var row: int = idx / 2
		_blit_alpha(lineup, after_panels[idx], Vector2i(10 + col * 525, 34 + row * 230))
	var lineup_path: String = out_dir.path_join("v0065_races_lineup.png")
	check(lineup.save_png(lineup_path) == OK, "saved " + lineup_path)

	# Build 100v100 mixed-race battle frame and measure frame time
	var battle_path: String = out_dir.path_join("v0065_battle_100v100.png")
	var mean_ms: float = await _build_100v100_battle(tree, battle_path)
	check(FileAccess.file_exists(battle_path) and mean_ms > 0.0, "saved 100v100 battle frame: " + battle_path)

	print("test_races_v065: %d passed, %d failed" % [pass_count, fail_count])
	return fail_count
