extends Node2D
## Art preview: every race x armor / helm / weapon / shield, every pose, wounds, a 1x battle
## lineup, portraits and party icons. Pages auto-advance (left/right arrows or click to flip).
## Capture: godot --path game --write-movie out.png --fixed-fps 10 --quit-after 96 res://art/preview.tscn

const PAGE_FRAMES := 12
const RACES := ["human", "orc", "goblin", "moon_elf", "high_elf", "dark_elf", "troll"]
const RACE_FACTION := {"human": "middle_kingdom", "orc": "orc_horde", "goblin": "goblin_warren", "moon_elf": "moon_court",
	"high_elf": "player", "dark_elf": "moon_court", "troll": "orc_horde"}
const BODIES := ["", "tunic", "mail_shirt", "mail_byrnie", "scrap_plates", "scale_vest", "lamellar_cuirass"]
const HELMS := ["nasal_helm", "mail_coif", "spangen_helm", "skull_cap", "pot_helm", "crescent_helm"]
const WEAPONS := ["arming_sword", "boar_spear", "flanged_mace", "bearded_axe", "dane_axe", "seax", "hacking_cleaver",
	"spiked_club", "war_maul", "hook_sickle", "glaive", "crescent_sabre"]
const SHIELDS := ["kite_shield", "round_shield", "slab_shield", "buckler"]

var pages: Array[Node2D] = []
var page := 0
var frame := 0
var anim_dolls: Array = []   # [doll, pose, speed]
var rng := RandomNumberGenerator.new()
var title: Label

func _ready() -> void:
	rng.seed = 1234
	RenderingServer.set_default_clear_color(Color("#6d7270"))
	title = Label.new()
	title.position = Vector2(8, 2)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 4)
	_page_closeup()
	_page_armor("copper", 0, "Races x body armor + helms (copper, q0)")
	_page_armor("tin", 3, "Races x body armor + helms (tin, q3 trim)")
	_page_weapons()
	_page_keyframes()
	_page_anim()
	_page_wounds_and_lineup()
	_page_portraits()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(title)
	var start := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--page="):
			start = int(a.substr(7))
	_show(start)

func _new_page(name: String) -> Node2D:
	var p := Node2D.new()
	p.name = name
	p.set_meta("title", name)
	add_child(p)
	pages.append(p)
	return p

func _show(i: int) -> void:
	page = posmod(i, pages.size())
	for k in pages.size():
		pages[k].visible = k == page
	title.text = "[%d/%d] %s" % [page + 1, pages.size(), pages[page].get_meta("title")]

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		if e.keycode == KEY_RIGHT:
			_show(page + 1)
		elif e.keycode == KEY_LEFT:
			_show(page - 1)
	elif e is InputEventMouseButton and e.pressed:
		_show(page + 1)

func _process(delta: float) -> void:
	frame += 1
	if frame % PAGE_FRAMES == 0:
		_show(page + 1)
	for a in anim_dolls:
		var d: Paperdoll = a[0]
		var spd: float = a[2]
		d.set_pose(a[1], fposmod(frame * 0.1 * spd, 1.0))

# --- unit building ---------------------------------------------------------------------------------

func make_unit(race: String, gear: Dictionary, seed_i: int = 0) -> Unit:
	var u := Unit.create(race, RACE_FACTION.get(race, "player"))
	var r := RandomNumberGenerator.new()
	r.seed = seed_i * 7919 + race.hash()
	Factory.roll_look(r, u)
	u.look["seed"] = seed_i
	u.equip["legs_under"] = Item.make("trousers", "linen")
	if race in ["human", "moon_elf", "high_elf", "dark_elf"]:
		u.equip["feet"] = Item.make("shoes", "leather")
	for slot in gear:
		var g: Array = gear[slot]
		if g[0] == "":
			continue
		u.equip[slot] = Item.make(g[0], g[1] if g.size() > 1 else "", g[2] if g.size() > 2 else 0)
	return u

func doll(parent: Node, u: Unit, pos: Vector2, scale_: float, pose: String = "idle", t: float = 0.0, team := Color(0, 0, 0, 0)) -> Paperdoll:
	var d := Paperdoll.new()
	d.team_color = team
	d.set_unit(u)
	d.set_pose(pose, t)
	d.position = pos
	d.scale = Vector2.ONE * scale_ / maxf(1.0, FigurePainter.race_scale(u.race) * 0.85)
	parent.add_child(d)
	return d

func label(parent: Node, text: String, pos: Vector2, size: int = 11) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("#f0f0e8"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	parent.add_child(l)

# --- pages -----------------------------------------------------------------------------------------

func _page_armor(mat: String, q: int, name: String) -> void:
	var p := _new_page(name)
	var cols := BODIES.size() + HELMS.size()
	var cw := 1280.0 / cols
	for c in cols:
		var lbl: String = BODIES[c] if c < BODIES.size() else HELMS[c - BODIES.size()]
		label(p, lbl if lbl != "" else "bare", Vector2(c * cw + 4, 22), 10)
	for r in RACES.size():
		var race: String = RACES[r]
		for c in cols:
			var gear := {"clothing": ["tunic", "linen"]}
			if c == 0:
				gear = {}
			elif c >= 2 and c < BODIES.size():
				gear["body"] = [BODIES[c], mat, q]
			elif c >= BODIES.size():
				gear["helm"] = [HELMS[c - BODIES.size()], mat, q]
			var u := make_unit(race, gear, r * 3 + c)
			doll(p, u, Vector2(c * cw + cw * 0.5, 130 + r * 96), 1.5)

func _page_weapons() -> void:
	var p := _new_page("Weapons (copper q1 / tin q4 alternating) + shields")
	var cols := WEAPONS.size() + SHIELDS.size()
	var cw := 1280.0 / cols
	for c in cols:
		label(p, (WEAPONS[c] if c < WEAPONS.size() else SHIELDS[c - WEAPONS.size()]).replace("_", " "), Vector2(c * cw + 2, 22), 9)
	for r in RACES.size():
		var race: String = RACES[r]
		for c in cols:
			var gear := {"clothing": ["tunic", "linen"]}
			var mat := "copper" if (c + r) % 2 == 0 else "tin"
			if c < WEAPONS.size():
				gear["main_hand"] = [WEAPONS[c], mat, 1 if mat == "copper" else 4]
			else:
				gear["main_hand"] = ["arming_sword", mat, 0]
				gear["off_hand"] = [SHIELDS[c - WEAPONS.size()], mat, 0]
			var u := make_unit(race, gear, r * 5 + c)
			doll(p, u, Vector2(c * cw + cw * 0.5, 130 + r * 96), 1.25)

func _loadouts() -> Array:
	return [
		["human", {"clothing": ["tunic", "linen"], "body": ["mail_shirt", "copper"], "helm": ["nasal_helm", "copper"], "main_hand": ["arming_sword", "copper"], "off_hand": ["kite_shield", "copper"]}],
		["human", {"clothing": ["tunic", "linen"], "helm": ["mail_coif", "tin"], "main_hand": ["boar_spear", "tin"], "off_hand": ["kite_shield", "tin"]}],
		["human", {"clothing": ["tunic", "linen"], "body": ["mail_byrnie", "copper"], "helm": ["spangen_helm", "copper"], "main_hand": ["dane_axe", "copper"]}],
		["orc", {"clothing": ["tunic", "linen"], "body": ["scrap_plates", "tin"], "helm": ["skull_cap", "tin"], "main_hand": ["war_maul", "tin"]}],
		["goblin", {"clothing": ["tunic", "linen"], "helm": ["pot_helm", "copper"], "main_hand": ["shiv", "copper"], "off_hand": ["buckler", "copper"]}],
		["moon_elf", {"clothing": ["tunic", "linen"], "body": ["lamellar_cuirass", "copper", 3], "helm": ["crescent_helm", "copper", 3], "main_hand": ["glaive", "copper", 3]}],
		["troll", {"main_hand": ["spiked_club", "copper"]}],
	]

func _page_closeup() -> void:
	var p := _new_page("Close-up 4x")
	var lo := _loadouts()
	for r in lo.size():
		var u := make_unit(lo[r][0], lo[r][1], r)
		var pos := Vector2(90 + r * 175, 330)
		var d := doll(p, u, pos, 4.0, "idle", 0.0, Color("#3ad0ff"))
		var d2 := doll(p, u, pos + Vector2(0, 330), 4.0, "strike", 0.33, Color("#ff4a3a"))
		d2.facing = 1

func _page_keyframes() -> void:
	var p := _new_page("Key frames: prepare 0/.5/1, strike 0/.33/.66/1, recover .5, hit 0, block 1, dodge .5, prone, dead")
	var frames := [["idle", 0.0], ["prepare", 0.0], ["prepare", 0.5], ["prepare", 1.0], ["strike", 0.0], ["strike", 0.33],
		["strike", 0.66], ["strike", 1.0], ["recover", 0.5], ["hit", 0.0], ["block", 1.0], ["dodge", 0.5], ["prone", 1.0], ["dead", 1.0]]
	var lo := _loadouts()
	var cw := 1280.0 / frames.size()
	for c in frames.size():
		label(p, "%s %.2f" % frames[c], Vector2(c * cw + 2, 22), 9)
	for r in lo.size():
		var u := make_unit(lo[r][0], lo[r][1], r)
		for c in frames.size():
			doll(p, u, Vector2(c * cw + cw * 0.5, 130 + r * 94), 1.25, frames[c][0], frames[c][1], Color("#3ad0ff") if r % 2 == 0 else Color("#ff4a3a"))

func _page_anim() -> void:
	var p := _new_page("All poses animated (progress cycles)")
	var lo := _loadouts()
	var cw := 1280.0 / FigurePainter.POSES.size()
	for c in FigurePainter.POSES.size():
		label(p, FigurePainter.POSES[c], Vector2(c * cw + 4, 22), 11)
	for r in lo.size():
		var u := make_unit(lo[r][0], lo[r][1], r + 20)
		for c in FigurePainter.POSES.size():
			var d := doll(p, u, Vector2(c * cw + cw * 0.5, 130 + r * 94), 1.25, FigurePainter.POSES[c], 0.0, Color.WHITE)
			anim_dolls.append([d, FigurePainter.POSES[c], 1.0 if c < 2 else 0.8])

func _page_wounds_and_lineup() -> void:
	var p := _new_page("Wounds (2x) / battle lineup at 1x (48 px)")
	var lo := _loadouts()
	var cases := [
		["fresh", {}, [], 1.0],
		["cuts", {"torso_upper": 0.4, "arm_lower_r": 0.3}, [], 0.9],
		["mauled", {"head": 0.8, "torso_upper": 0.9, "torso_lower": 0.7, "leg_upper_l": 0.6}, [], 0.6],
		["no hand", {"arm_lower_r": 0.5}, ["hand_r"], 0.8],
		["no forearm", {"torso_upper": 0.3}, ["arm_lower_l"], 0.7],
		["no shin", {"leg_upper_r": 0.4}, ["leg_lower_r"], 0.6],
		["bled white", {"torso_lower": 0.6}, [], 0.35],
		["headless", {}, ["head"], 0.3],
		["dead", {"torso_upper": 1.0}, [], 0.2],
	]
	var cw := 1280.0 / cases.size()
	for c in cases.size():
		var u := make_unit("human", lo[0][1], 40 + c)
		var cs: Array = cases[c]
		for pid in cs[1]:
			for l in u.body.wound_part(pid)["layers"]:
				l["dmg"] = cs[1][pid]
			u.body.wound_part(pid)["layers"][0]["bleed"] = 0.5
		for pid in cs[2]:
			u.body.wound_part(pid)["severed"] = true
		u.body.blood = u.body.blood_max * float(cs[3])
		label(p, cs[0], Vector2(c * cw + 4, 22), 11)
		var pose := "dead" if cs[0] in ["dead", "headless"] else "idle"
		doll(p, u, Vector2(c * cw + cw * 0.5, 160), 2.0, pose, 0.0, Color("#3ad0ff"))
	# 1x lineup: player-ish humans vs each enemy faction
	var x := 30.0
	var row := 0
	for fid in DB.factions:
		var band: Array = Factory.make_warband(rng, fid, 8)
		label(p, fid, Vector2(10, 230 + row * 95), 10)
		for i in band.size():
			var u: Unit = band[i]
			if i == 0:
				u.role = "officer"
			var d := doll(p, u, Vector2(x + 110 + i * 40, 300 + row * 95), 1.0, "idle", 0.0, Color("#ff4a3a") if row % 2 else Color("#3ad0ff"))
			d.scale = Vector2.ONE
			d.facing = 1 if row % 2 == 0 else -1
		row += 1
	# severed pieces (ground decals)
	label(p, "severed pieces", Vector2(480, 230), 11)
	var parts := ["head", "arm_upper_r", "arm_lower_l", "hand_r", "leg_upper_l", "leg_lower_r", "foot_l", "eye_l"]
	var who := [make_unit("human", lo[0][1], 7), make_unit("orc", lo[3][1], 8), make_unit("moon_elf", lo[5][1], 9)]
	for r in who.size():
		for c in parts.size():
			var piece := Paperdoll.make_severed_piece(who[r], parts[c])
			piece.position = Vector2(500 + (c % 4) * 70, 290 + r * 140 + (c / 4) * 60)
			p.add_child(piece)
	# same, poses mixed, at 1x on the right
	var lo2 := _loadouts()
	for r in lo2.size():
		for c in 6:
			var u := make_unit(lo2[r][0], lo2[r][1], 60 + r)
			var pp: String = ["idle", "walk", "prepare", "strike", "block", "hit"][c]
			var d := doll(p, u, Vector2(820 + c * 70, 270 + r * 64), 1.0, pp, 0.6, Color("#3ad0ff"))
			d.scale = Vector2.ONE

func _page_portraits() -> void:
	var p := _new_page("Portraits (96 px) + party icons (1 / 2 / 3 figures)")
	var y := 40.0
	var fids := DB.factions.keys()
	for r in fids.size():
		var band: Array = Factory.make_warband(rng, fids[r], 6)
		for i in band.size():
			var pt := Portrait.new()
			pt.position = Vector2(10 + i * 100, y + r * 104)
			pt.size = Vector2(96, 96)
			pt.set_unit(band[i])
			p.add_child(pt)
		var col: Color = Color(DB.factions[fids[r]]["colors"]["primary"])
		var counts := [2, 6, 12]
		for i in counts.size():
			var pi := PartyIcon.new()
			pi.setup(DB.factions[fids[r]]["race"], col, counts[i], band[0] if i == 2 else null)
			pi.position = Vector2(700 + i * 110, y + r * 104 + 88)
			pi.walking = i != 0
			p.add_child(pi)
	# a big portrait for detail
	var big := Portrait.new()
	big.position = Vector2(1040, 40)
	big.size = Vector2(200, 200)
	big.set_unit(make_unit("human", _loadouts()[0][1], 3))
	p.add_child(big)
	var big2 := Portrait.new()
	big2.position = Vector2(1040, 260)
	big2.size = Vector2(200, 200)
	big2.set_unit(make_unit("orc", {"clothing": ["tunic", "linen"], "helm": ["skull_cap", "tin"]}, 4))
	p.add_child(big2)
	var big3 := Portrait.new()
	big3.position = Vector2(1040, 480)
	big3.size = Vector2(200, 200)
	big3.set_unit(make_unit("moon_elf", {"clothing": ["tunic", "linen"], "body": ["lamellar_cuirass", "copper", 4]}, 2))
	p.add_child(big3)
