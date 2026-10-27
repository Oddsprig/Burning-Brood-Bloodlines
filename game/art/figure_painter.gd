class_name FigurePainter
extends RefCounted
## Draws a whole figure (race body + clothing + body armor + helm + shield + weapon + wounds) for one
## pose frame into a PixelCanvas. Paperdoll, Portrait and PartyIcon all use it, so every layer
## (and every item "sprite" key in data/) has exactly one drawing.
##
## Input is a plain "spec" Dictionary (spec_for_unit / spec_generic), so drawing never touches
## live game objects and the result can be cached by spec.hash().
## Local frame: 1 unit = 1 logical pixel, origin at the feet, +x = facing direction, y down.
## A human is 24 logical px tall; Paperdoll shows logical pixels at 2x (48 screen px).

const PX := 2.0
const BUST := 40   # retained for creature/legacy portrait sizing
const PEOPLE_BUST := 96
const DETAILED_RACES := ["human", "orc", "high_elf", "moon_elf", "dark_elf", "dwarf", "goblin", "troll"]

const FRAMES := {"idle": 4, "walk": 8, "prepare": 4, "strike": 5, "recover": 4, "hit": 3,
	"block": 3, "dodge": 4, "prone": 1, "dead": 1}
const POSES := ["idle", "walk", "prepare", "strike", "recover", "hit", "block", "dodge", "prone", "dead"]

## Company (player faction) colours; menus may overwrite.
static var company_colors := {"primary": "#1f8f88", "secondary": "#e0a040"}
static var force_legacy_v064: bool = false

static func set_legacy_v064(enabled: bool) -> void:
	force_legacy_v064 = enabled
	DwarfArt._force_legacy_v064 = enabled
	ElfArt._force_legacy_v064 = enabled
	OrcArt._force_legacy_v064 = enabled
	GoblinArt._force_legacy_v064 = enabled
	TrollArt._force_legacy_v064 = enabled

const RACE_ART := {
	"human":    {"head": 6.0, "headw": 6.0, "arm": 2.0, "leg": 2.6, "ears": "round", "nose": 1, "eye": "#1c1424",
		"hair_styles": ["short", "long", "short", "bald", "ponytail", "short"]},
	"orc":      {"head": 6.0, "headw": 7.0, "arm": 2.8, "leg": 3.0, "ears": "small", "nose": 1, "tusks": true,
		"brow": true, "eye": "#ffcf33", "hair_styles": ["bald", "mohawk", "topknot", "mohawk"]},
	"goblin":   {"head": 6.0, "headw": 6.0, "arm": 1.8, "leg": 2.0, "ears": "big", "nose": 2, "eye": "#ffe14a",
		"hair_styles": ["bald", "tuft", "bald"]},
	"moon_elf": {"head": 6.0, "headw": 5.0, "arm": 1.8, "leg": 2.2, "ears": "long", "nose": 1, "eye": "#7fe0ff",
		"shiny": true, "hair_styles": ["long", "long", "ponytail"]},
	"high_elf": {"head": 6.0, "headw": 5.0, "arm": 1.9, "leg": 2.3, "ears": "long", "nose": 1, "eye": "#3aa0ff",
		"shiny": true, "hair_styles": ["long", "ponytail"]},
	"dark_elf": {"head": 6.0, "headw": 5.0, "arm": 1.8, "leg": 2.2, "ears": "long", "nose": 1, "eye": "#ff4040",
		"shiny": true, "hair_styles": ["long", "mohawk", "ponytail"]},
	"dwarf":    {"head": 6.5, "headw": 7.0, "arm": 2.4, "leg": 1.9, "ears": "round", "nose": 2, "eye": "#2a1a10",
		"hair_styles": ["short", "long", "bald", "topknot", "long"]},
	"troll":    {"head": 7.0, "headw": 8.0, "arm": 4.0, "leg": 4.6, "ears": "small", "nose": 2, "tusks": true,
		"brow": true, "eye": "#ffb020", "hunch": 2.0, "armlen": 1.3, "hair_styles": ["bald", "tuft"]},
}

const SWING1 := ["sword", "mace", "axe", "knife", "cleaver", "club", "sickle", "sabre"]
const BOW_SPRITES := {"bow": 12.0, "longbow": 15.0, "recurve": 10.5}   # bows: sprite -> stave length (logical px)
const BLOOD := Color("#c0141c")
const BLOOD_DARK := Color("#6a0a10")
const WOOD := Color("#8a5a30")
const LEATHER := Color("#6b4426")

var spec: Dictionary
var ra: Dictionary
var cv: PixelCanvas
var j: Dictionary = {}       # joints (local coords)
var pose := "idle"
var t := 0.0
# metrics
var H := 24.0
var head_h := 6.0
var head_w := 6.0
var leg_len := 10.0
var torso_len := 8.0
var tw := 7.0
var hipw := 6.0
var arm_a := 4.0
var arm_b := 4.0
var arm_r := 1.0
var leg_r := 1.3
var gs := 1.0
var hunch := 0.0
# colours
var skin: Color
var hair: Color
var prim: Color
var sec: Color

# --- public API -----------------------------------------------------------------------------

static func faction_colors(fid: String) -> Array:
	var p := Color(company_colors["primary"])
	var s := Color(company_colors["secondary"])
	if DB.factions.has(fid):
		var c: Dictionary = DB.factions[fid].get("colors", {})
		p = Color(c.get("primary", "#777777"))
		s = Color(c.get("secondary", "#cccccc"))
	return [_vivid(p), _vivid(s)]

## Battle Brothers-leaning: lift the (often dark) data colours to bright, saturated ones.
static func _vivid(c: Color) -> Color:
	return Color.from_hsv(c.h, clampf(c.s * 1.12, 0.0, 1.0), clampf(c.v * 1.3 + 0.06, 0.0, 0.95))

static func _item_spec(it: Item) -> Dictionary:
	if it == null:
		return {}
	var tm := it.tmpl()
	return {"tid": it.tid, "sprite": String(tm.get("sprite", "")), "mat": it.material, "q": it.quality,
		"wear": it.wear, "two": bool(tm.get("two_handed", false)), "reach": float(tm.get("reach", 100)),
		"maker_race": it.maker_race(), "culture": String(tm.get("culture", ""))}

## v0.014 wound marks: layer kind -> shown kind rank (bruise < cut < broken bone < mangled), and the code per rank.
const WOUND_SHOW_RANK := {"bruised": 1, "cut": 2, "pierced": 2, "torn": 2, "fractured": 3, "broken": 3, "mangled": 4, "destroyed": 4}
const WOUND_SHOW := ["", "b", "c", "f", "m"]
const BRUISE := Color("#6a3f7a")
const BONE_WHITE := Color("#f2ead8")

## Both accepted female drawing sets keep their original matching hair contours.
const FEMALE_SETS: Array[String] = ["Original","Refined"]
const BEARD_STYLES: Array[String] = ["Original","Close trimmed","Round full","Pointed","Forked","Braided","Moustache","Stubble"]

static func female_variant(appearance: Dictionary) -> int:
	# 60 is divisible by all existing hair periods (5,6,10) and both orc faces (20).
	# Identity therefore supplies the set without coupling it to hairstyle or using RNG.
	var seed: int = absi(int(appearance.get("seed",0)))
	return clampi(int(appearance.get("female_set",posmod(int(seed/60),2))),0,FEMALE_SETS.size()-1)

static func beard_style(appearance: Dictionary) -> int:
	# Keep clean-shaven/bearded identity separate; callers honor the actual beard flag.
	var seed: int = absi(int(appearance.get("seed",0)))
	return clampi(int(appearance.get("beard_style",posmod(int(seed/120),BEARD_STYLES.size()))),0,BEARD_STYLES.size()-1)

static func spec_for_unit(u: Unit, team: Color = Color(0, 0, 0, 0)) -> Dictionary:
	var rd := u.race_def()
	var skins: Array = rd.get("skin", ["#e8c4a0"])
	var hairs: Array = rd.get("hair", ["#3a2a1a"])
	var cols := faction_colors(u.faction)
	var s := {"race": u.race, "skin": Color(u.look.get("skin", skins[0])), "hair": Color(u.look.get("hair", hairs[0])),
		"beard": bool(u.look.get("beard", false)), "seed": int(u.look.get("seed", u.uid)), "prim": cols[0],
		"sec": cols[1], "team": team, "role": u.role, "dead": u.dead,
		"sex": "female" if u.sex == 1 else "male", "age": u.age}
	if u.sex == 1:
		s["female_set"] = female_variant(u.look)
	elif bool(s["beard"]) and u.race in ["human","orc","dwarf"]:
		s["beard_style"] = beard_style(u.look)
	s["weapon"] = _item_spec(u.weapon()) if u.weapon() == null or not u.weapon().broken else {}   # v0.014: snapped
	s["shield"] = _item_spec(u.shield())
	for slot in ["body", "helm", "clothing", "legs", "hands", "feet", "legs_under"]:
		s[slot] = _item_spec(u.equip.get(slot, null))
	var dmg := {}
	var bleed := {}
	var wk := {}   # v0.014: the worst wound kind shown on the part: c cut, b bruise, f broken bone, m mangled
	var lost := []
	var blood := 1.0
	if u.body != null:
		blood = clampf(u.body.blood / maxf(u.body.blood_max, 0.001), 0.0, 1.0)
		lost = u.body.lost_ids()   # the body stores only wounded parts: the parts below a severed one come from the plan
		for pid in u.body.parts:
			if u.body.is_lost(pid):
				continue
			var m := 0.0
			var b := 0.0
			var kr := 0
			for l in u.body.parts[pid]["layers"]:
				m = maxf(m, float(l.get("dmg", 0.0)))
				b += float(l.get("bleed", 0.0))
				kr = maxi(kr, int(WOUND_SHOW_RANK.get(String(l.get("kind", "")), 0)))
			if m > 0.02:
				dmg[pid] = snappedf(m, 0.1)
				if kr > 0:
					wk[pid] = WOUND_SHOW[kr]
			if b > 0.0:
				bleed[pid] = true
	lost.sort()
	s["dmg"] = dmg
	s["wk"] = wk
	s["gore"] = 1 if CombatText.gore_full else 0
	s["bleed"] = bleed
	s["lost"] = lost
	s["blood"] = snappedf(blood, 0.05)
	return s

## A faceless-but-plausible member of a race in given colours (party icons, previews).
static func spec_generic(race: String, primary: Color, secondary: Color, seed: int) -> Dictionary:
	var rd: Dictionary = DB.races.get(race, DB.races["human"])
	var skins: Array = rd.get("skin", ["#e8c4a0"])
	var hairs: Array = rd.get("hair", ["#3a2a1a"])
	return {"race": race, "skin": Color(skins[seed % skins.size()]), "hair": Color(hairs[(seed / 3) % hairs.size()]),
		"beard": (race in ["human", "orc"] and seed % 2 == 0) or bool(rd.get("beard", false)), "seed": seed, "prim": _vivid(primary), "sec": _vivid(secondary),
		"team": Color(0, 0, 0, 0), "role": "troop", "dead": false, "weapon": {}, "shield": {}, "body": {}, "helm": {},
		"clothing": {"tid": "tunic", "sprite": "tunic", "mat": "linen", "q": 0}, "legs": {}, "hands": {}, "feet": {},
		"legs_under": {"tid": "trousers", "sprite": "", "mat": "linen", "q": 0}, "dmg": {}, "bleed": {}, "lost": [], "blood": 1.0}

static func is_cyclic(p: String) -> bool:
	return p == "idle" or p == "walk"

static func frame_index(p: String, prog: float) -> int:
	var n: int = FRAMES.get(p, 1)
	if n <= 1:
		return 0
	if is_cyclic(p):
		return floori(fposmod(prog, 1.0) * n) % n
	return roundi(clampf(prog, 0.0, 1.0) * (n - 1))

static func frame_t(p: String, f: int) -> float:
	var n: int = FRAMES.get(p, 1)
	if n <= 1:
		return 1.0
	if is_cyclic(p):
		return float(f) / n
	return float(f) / (n - 1)

static func race_scale(race: String) -> float:
	return float(DB.races.get(race, {}).get("height", 1.0))

## Raster detail is independent of animation/world coordinates.
static func raster_scale(race: String) -> float:
	return 2.0 if race in DETAILED_RACES else 1.0

static func display_scale(race: String) -> float:
	return PX / raster_scale(race)

static func bust_size(race: String) -> int:
	return PEOPLE_BUST if race in DETAILED_RACES else BUST

## Canvas size and feet anchor (image pixels) for a race.
static func dims(race: String) -> Dictionary:
	if DB.is_creature(race):   # monsters wave 1: quadrupeds (art/creature_painter.gd)
		return CreaturePainter.dims(race)
	var s := maxf(1.0, race_scale(race))
	var cw := int(ceil(64.0 * s / 2.0)) * 2
	var ch := int(ceil(60.0 * s / 2.0)) * 2
	var raster := raster_scale(race)
	return {"size": Vector2i(Vector2(cw, ch) * raster), "anchor": Vector2(cw / 2, ch - int(8 * s)) * raster}

## Broad fallen weapons need extra transparent space beneath the original feet anchor.
## Extra raster room never changes joint coordinates, physical size, or healthy frames.
static func frame_dims(sp: Dictionary, p: String) -> Dictionary:
	var race := String(sp.get("race", "human"))
	var dm := dims(race)
	var weapon: Dictionary = sp.get("weapon", {})
	if race in DETAILED_RACES and p in ["prone", "dead"] and String(weapon.get("sprite", "")) in ["axe", "greataxe", "glaive"]:
		dm["size"] += Vector2i(0, ceili(8.0 * raster_scale(race)))
	return dm

## Full-body frame. Returns an Image whose `anchor` (see dims) is the feet.
static func render(sp: Dictionary, p: String, prog: float) -> Image:
	if CreaturePainter.is_creature_spec(sp):
		return CreaturePainter.render(sp, p, prog)
	var fp := FigurePainter.new(sp)
	return fp.paint(p, prog).to_image()

static func render_canvas(sp: Dictionary, p: String, prog: float) -> PixelCanvas:
	if CreaturePainter.is_creature_spec(sp):
		return CreaturePainter.render_canvas(sp, p, prog)
	return FigurePainter.new(sp).paint(p, prog)

## Head-and-shoulders portrait, BUST x BUST logical px.
static func render_bust(sp: Dictionary) -> Image:
	if CreaturePainter.is_creature_spec(sp):
		return CreaturePainter.render_bust(sp)
	return FigurePainter.new(sp).paint_bust().to_image()

# --- setup ------------------------------------------------------------------------------------

func _init(sp: Dictionary) -> void:
	spec = sp
	ra = RACE_ART.get(sp.get("race", "human"), RACE_ART["human"])
	var rd: Dictionary = DB.races.get(sp.get("race", "human"), DB.races["human"])
	var hs := float(rd.get("height", 1.0))
	var ws := float(rd.get("width", 1.0))
	head_h = ra["head"]
	head_w = ra["headw"]
	H = roundf(24.0 * hs)
	var body := H - head_h
	leg_len = roundf(body * 0.55)
	torso_len = body - leg_len
	tw = maxf(6.0, roundf(8.0 * ws))
	hipw = tw - 1.0
	var armlen := torso_len * 1.05 * float(ra.get("armlen", 1.0))
	arm_a = armlen * 0.5
	arm_b = armlen * 0.5
	arm_r = float(ra["arm"]) * 0.5
	leg_r = float(ra["leg"]) * 0.5
	gs = clampf(hs, 0.85, 1.35)
	hunch = float(ra.get("hunch", 0.0))
	var lost_blood := 1.0 - float(sp.get("blood", 1.0))
	skin = (sp.get("skin", Color("#e8c4a0")) as Color).lerp(Color("#d8d8d0"), clampf(lost_blood * 0.6, 0.0, 0.45))
	hair = sp.get("hair", Color("#3a2a1a"))
	prim = sp.get("prim", Color("#3070b0"))
	sec = sp.get("sec", Color("#e0c080"))

func _lost(pid: String) -> bool:
	return pid in spec.get("lost", [])

func _it(slot: String) -> Dictionary:
	return spec.get(slot, {})

func _wkind() -> String:
	var w := _it("weapon")
	if w.is_empty() or _lost("hand_r"):
		return "none"
	var s: String = w.get("sprite", "sword")
	if s in BOW_SPRITES:   # bows: held out in the near hand, drawn by the far hand
		return "bow"
	if s == "spear":
		return "thrust2" if w.get("two", false) else "thrust1"
	if s in ["greataxe", "maul"] or w.get("two", false):
		return "swing2"
	return "swing1"

# --- palettes ---------------------------------------------------------------------------------

static func ol(c: Color) -> Color:
	return c.darkened(0.72).lerp(Color("#140a10"), 0.45)

## Material ramp: base / light / dark / shine / trim and shading strength.
static func metal(mat: String, q: int = 0) -> Dictionary:
	var m: Dictionary
	match mat:
		"copper":
			m = {"base": Color("#d4742e"), "light": Color("#f5a85a"), "dark": Color("#8c4220"), "shine": Color("#ffe6b0"),
				"shade": 0.16}
		"tin":
			m = {"base": Color("#a9b0b9"), "light": Color("#c9cfd6"), "dark": Color("#6f7680"), "shine": Color("#d9dde2"),
				"shade": 0.08}
		_:
			var base := Color("#888888")
			if DB.materials.has(mat):
				base = _vivid(Color(DB.materials[mat].get("color", "#888888")))
			m = {"base": base, "light": base.lightened(0.25), "dark": base.darkened(0.35), "shine": base.lightened(0.45),
				"shade": 0.12}
	m["q"] = q
	m["trim"] = (Color("#ffd86a") if mat == "copper" else Color("#f6f9ff")) if q >= 2 else m["light"]
	if q >= 1:
		m["shine"] = (m["shine"] as Color).lightened(0.1 * q)
	m["outline"] = ol(m["base"])
	return m

func _metal_end(m: Dictionary) -> void:
	cv.end(m["outline"], m["shade"], m["shine"])

func _skin_end() -> void:
	var shine := skin.lightened(0.5) if ra.get("shiny", false) else Color(0, 0, 0, 0)
	cv.end(ol(skin), 0.12, shine)

func _sparkle(p: Vector2, m: Dictionary) -> void:
	if int(m.get("q", 0)) >= 4:
		cv.dot(p, Color("#ffffff"))

# --- rig ----------------------------------------------------------------------------------------

static func head_landmarks(sp: Dictionary) -> Dictionary:
	var race := String(sp.get("race", "human"))
	var female := String(sp.get("sex", "")).to_lower() in ["female", "f", "woman", "1"]
	var seed := absi(int(sp.get("seed", 0)))
	match race:
		"human":
			var n_ext := (0.04 if female else 0.11) * float((seed / 4) % 4)
			return {
				"head_top": -2.75 if female else -2.85,
				"head_bottom": 2.25 if female else 2.45,
				"eye_r": Vector2(-0.18 if female else -0.15, -0.20 if female else -0.18),
				"eye_l": Vector2(1.15 if female else 1.22, -0.20 if female else -0.18),
				"nose_bridge": Vector2(0.55, -0.24),
				"nose_tip": Vector2((0.78 if female else 0.88) + n_ext, 0.52 if female else 0.58),
				"mouth": Vector2(0.65 if female else 0.70, 1.16 if female else 1.22),
			}
		"dwarf":
			var n_ext := 0.08 * float((seed / 13) % 4)
			return {
				"head_top": -2.75 if female else -2.85,
				"head_bottom": 2.25 if female else 2.45,
				"eye_r": Vector2(-0.20 if female else -0.18, -0.22 if female else -0.18),
				"eye_l": Vector2(1.20 if female else 1.28, -0.22 if female else -0.18),
				"nose_bridge": Vector2(0.56, -0.24),
				"nose_tip": Vector2((0.85 if female else 0.95) + n_ext * (0.6 if female else 1.0), 0.52 if female else 0.56),
				"mouth": Vector2(0.68 if female else 0.72, 1.18 if female else 1.25),
			}
		"high_elf", "moon_elf", "dark_elf":
			return {
				"head_top": -3.00,
				"head_bottom": 2.20 if female else 2.35,
				"eye_r": Vector2(-0.24 if female else -0.22, -0.26 if female else -0.24),
				"eye_l": Vector2(1.08 if female else 1.12, -0.26 if female else -0.24),
				"nose_bridge": Vector2(0.46, -0.30),
				"nose_tip": Vector2(0.70 if female else 0.76, 0.48 if female else 0.52),
				"mouth": Vector2(0.64, 1.12 if female else 1.18),
			}
		"orc":
			return {
				"head_top": -3.15,
				"head_bottom": 2.55 if female else 2.85,
				"eye_r": Vector2(-0.20 if female else -0.22, -0.22 if female else -0.18),
				"eye_l": Vector2(1.22 if female else 1.32, -0.22 if female else -0.18),
				"nose_bridge": Vector2(0.58, -0.26),
				"nose_tip": Vector2(0.86 if female else 0.96, 0.50 if female else 0.56),
				"mouth": Vector2(0.75 if female else 0.85, 1.24 if female else 1.38),
			}
		"goblin":
			var n_len := (0.06 if female else 0.10) * float((seed / 5) % 3)
			return {
				"head_top": -2.90,
				"head_bottom": 2.25 if female else 2.45,
				"eye_r": Vector2(-0.22, -0.25 if female else -0.22),
				"eye_l": Vector2(1.10 if female else 1.15, -0.25 if female else -0.22),
				"nose_bridge": Vector2(0.48, -0.28),
				"nose_tip": Vector2((0.82 if female else 0.95) + n_len, 0.54 if female else 0.62),
				"mouth": Vector2(0.68, 1.18 if female else 1.25),
			}
		"troll":
			return {
				"head_top": -3.65,
				"head_bottom": 3.35,
				"eye_r": Vector2(-0.25, -0.15),
				"eye_l": Vector2(1.58, -0.15),
				"nose_bridge": Vector2(0.68, -0.22),
				"nose_tip": Vector2(1.15, 0.68),
				"mouth": Vector2(1.10, 1.68),
			}
	return {
		"head_top": -2.85,
		"head_bottom": 2.45,
		"eye_r": Vector2(-0.15, -0.18),
		"eye_l": Vector2(1.22, -0.18),
		"nose_bridge": Vector2(0.55, -0.24),
		"nose_tip": Vector2(0.88, 0.58),
		"mouth": Vector2(0.70, 1.22),
	}

func _stance(wk: String, which: String, A: float) -> Dictionary:
	var is_hum := String(spec.get("race", "human")) == "human"
	var hr_side := Vector2(-2.25, 0.85 + 0.988 * A) if is_hum else Vector2(-maxf(2.25, tw * 0.44), 1.0 + 0.90 * A)
	var hl_side := Vector2(2.35, 0.85 + 0.988 * A) if is_hum else Vector2(maxf(2.45, tw * 0.44), 1.0 + 0.90 * A)
	var hl_rest := Vector2(tw * 0.5 + 1.5, 0.42 * A) if not _it("shield").is_empty() else hl_side
	var d := {"hl": hl_rest, "lean": 0.0, "wa": 0.0}
	if wk == "bow":   # bows: bow arm out front, string hand at the bow (rest), at the chin (draw), flung back (loose)
		match which:
			"rest": d.merge({"hr": Vector2(0.8 * A, 0.3 * A), "hl": Vector2(0.5 * A, 0.35 * A), "wa": -80.0}, true)
			"wind": d.merge({"hr": Vector2(0.95 * A, 0.12 * A), "hl": Vector2(0.5, 0.05 * A), "wa": -90.0, "lean": -0.5}, true)
			"strike": d.merge({"hr": Vector2(0.95 * A, 0.12 * A), "hl": Vector2(-1.5, 0.15 * A), "wa": -90.0, "lean": -0.3}, true)
		return d
	match which:
		"rest":
			match wk:
				"none": d.merge({"hr": hr_side, "wa": 60.0}, true)
				"swing1": d.merge({"hr": Vector2(1.8, 0.68 * A) if is_hum else Vector2(3.0, 0.6 * A), "wa": -62.0}, true)
				"swing2": d.merge({"hr": Vector2(2.0, 0.68 * A) if is_hum else Vector2(2.5, 0.68 * A), "wa": -58.0}, true)
				"thrust1": d.merge({"hr": Vector2(2.4, 0.60 * A) if is_hum else Vector2(3.5, 0.55 * A), "wa": -82.0}, true)
				"thrust2": d.merge({"hr": Vector2(2.4, 0.62 * A) if is_hum else Vector2(3.0, 0.62 * A), "wa": -72.0}, true)
		"wind":
			match wk:
				"none": d.merge({"hr": Vector2(-2.0, 0.35 * A), "wa": 0.0, "lean": -0.5}, true)
				"swing1": d.merge({"hr": Vector2(-2.0, -0.3 * A), "wa": -148.0, "lean": -0.5}, true)
				"swing2": d.merge({"hr": Vector2(-1.5, -0.35 * A), "wa": -165.0, "lean": -1.0}, true)
				"thrust1": d.merge({"hr": Vector2(-2.5, 0.35 * A), "wa": -8.0, "lean": -1.0}, true)
				"thrust2": d.merge({"hr": Vector2(-2.5, 0.45 * A), "wa": -12.0, "lean": -1.0}, true)
		"strike":
			match wk:
				"none": d.merge({"hr": Vector2(A + 0.5, 0.15 * A), "wa": 0.0, "lean": 1.5}, true)
				"swing1": d.merge({"hr": Vector2(0.85 * A, 0.45 * A), "wa": 38.0, "lean": 1.5}, true)
				"swing2": d.merge({"hr": Vector2(0.75 * A, 0.55 * A), "wa": 48.0, "lean": 2.0}, true)
				"thrust1": d.merge({"hr": Vector2(A + 0.5, 0.25 * A), "wa": -4.0, "lean": 2.0}, true)
				"thrust2": d.merge({"hr": Vector2(A, 0.3 * A), "wa": -6.0, "lean": 2.0}, true)
	if not d.has("hr"):
		d["hr"] = hr_side
	return d

static func _mix(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	return {"hr": (a["hr"] as Vector2).lerp(b["hr"], f), "hl": (a["hl"] as Vector2).lerp(b["hl"], f),
		"wa": lerpf(a["wa"], b["wa"], f), "lean": lerpf(a["lean"], b["lean"], f)}

static func _reach(s: Vector2, target: Vector2, l: float) -> Vector2:
	var d := target - s
	if d.length() > l:
		return s + d.normalized() * l
	return target

static func _ik(a: Vector2, b: Vector2, l1: float, l2: float, bend: float) -> Vector2:
	var v := b - a
	var d := clampf(v.length(), 0.001, l1 + l2 - 0.001)
	var dir := v.normalized() if v.length() > 0.001 else Vector2.DOWN
	var ca := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	return a + dir.rotated(acos(ca) * bend) * l1

func _rig() -> void:
	var A := arm_a + arm_b
	var wk := _wkind()
	var rest := _stance(wk, "rest", A)
	var cur := rest
	var bob := 0.0
	var breathe := 0.0
	var dx := 0.0
	var step := 0.0
	var lift_n := 0.0
	var lift_f := 0.0
	var head_dx := 0.0
	match pose:
		"idle":
			breathe = -1.0 if fposmod(t, 1.0) >= 0.5 else 0.0
		"walk":
			var ph := t * TAU
			step = sin(ph)
			lift_n = maxf(0.0, cos(ph)) * 1.5
			lift_f = maxf(0.0, -cos(ph)) * 1.5
			bob = -1.0 if absf(step) < 0.5 else 0.0
			cur = rest.duplicate()
			cur["hl"] = (rest["hl"] as Vector2) + Vector2(-step * 1.5, 0)
			cur["hr"] = (rest["hr"] as Vector2) + Vector2(step * 0.8, 0)
		"prepare":
			cur = _mix(rest, _stance(wk, "wind", A), 1.0 - pow(1.0 - t, 2.0))
		"strike":
			cur = _mix(_stance(wk, "wind", A), _stance(wk, "strike", A), 1.0 - pow(1.0 - t, 2.0))
		"recover":
			cur = _mix(_stance(wk, "strike", A), rest, t * t * (3.0 - 2.0 * t))
		"hit":
			var f := 1.0 - t
			cur = rest.duplicate()
			cur["lean"] = -2.0 * f
			cur["hr"] = (rest["hr"] as Vector2) + Vector2(-1.5, -1.5) * f
			cur["hl"] = (rest["hl"] as Vector2) + Vector2(-1.0, -1.0) * f
			cur["wa"] = float(rest["wa"]) - 25.0 * f
			dx = -1.0 * f
			head_dx = -1.0 * f
		"block":
			var f := clampf(t * 3.0 + 0.34, 0.0, 1.0)
			cur = rest.duplicate()
			if not _it("shield").is_empty():
				cur["hl"] = (rest["hl"] as Vector2).lerp(Vector2(tw * 0.5 + 2.5, -0.15 * A), f)
				cur["lean"] = -0.5 * f
			else:
				cur["hr"] = (rest["hr"] as Vector2).lerp(Vector2(2.5, -0.15 * A), f)
				cur["wa"] = lerpf(rest["wa"], -100.0 if wk.begins_with("thrust") else -20.0, f)
				cur["lean"] = -0.5 * f
		"dodge":
			var f := sin(PI * clampf(t, 0.0, 1.0))
			dx = -3.0 * f
			cur = rest.duplicate()
			cur["lean"] = -2.5 * f
			step = -0.5 * f
			head_dx = -0.5 * f
	j.clear()
	var is_hum := String(spec.get("race", "human")) == "human"
	var hip := Vector2(dx, -leg_len + bob)
	var sc := hip + Vector2(float(cur["lean"]) + hunch * 0.5, -torso_len + breathe)
	j["hip"] = hip
	j["sc"] = sc
	j["hc"] = sc + Vector2((0.35 if is_hum else 0.5) + head_dx + hunch, -head_h * 0.5 + hunch * 0.6)
	j["sr"] = sc + (Vector2(-2.15, 0.85) if is_hum else Vector2(-1.0, 1.0))
	j["sl"] = sc + (Vector2(1.90, 0.85) if is_hum else Vector2(1.5, 1.0))
	var reach := arm_a + arm_b - 0.05
	j["hr"] = _reach(j["sr"], sc + (cur["hr"] as Vector2), reach)
	j["er"] = _ik(j["sr"], j["hr"], arm_a, arm_b, 1.0)
	var wdir := Vector2.from_angle(deg_to_rad(float(cur["wa"])))
	j["grip"] = j["hr"]
	j["wdir"] = wdir
	var lt: Vector2 = sc + (cur["hl"] as Vector2)
	if wk == "swing2" or wk == "thrust2":
		lt = (j["hr"] as Vector2) + wdir * (3.0 if wk == "swing2" else 4.0) * gs
	j["hl"] = _reach(j["sl"], lt, reach)
	j["el"] = _ik(j["sl"], j["hl"], arm_a, arm_b, -1.0 if (wk == "none" and _it("shield").is_empty() and pose in ["idle", "walk"]) else 1.0)
	# legs (r = near leg, l = far leg)
	var thigh := leg_len * 0.5
	var shin := leg_len * 0.5
	j["pr"] = hip + (Vector2(-1.10, 0.0) if is_hum else Vector2(-1.0, 0.0))
	j["pl"] = hip + (Vector2(1.05, 0.0) if is_hum else Vector2(1.0, 0.0))
	j["fr"] = Vector2(dx - (1.15 if is_hum else 1.0) + step * 2.5, (-0.78 if is_hum else -1.5) - lift_n)
	j["fl"] = Vector2(dx + (1.05 if is_hum else 1.0) - step * 2.5, (-0.78 if is_hum else -1.5) - lift_f)
	var thigh_ik := (thigh - 0.34) if is_hum else thigh
	var shin_ik := (shin - 0.34) if is_hum else (shin - 1.0)
	j["kr"] = _ik(j["pr"], j["fr"], thigh_ik, shin_ik, -1.0)
	j["kl"] = _ik(j["pl"], j["fl"], thigh_ik, shin_ik, -1.0)

# --- full figure --------------------------------------------------------------------------------

func paint(p: String, prog: float) -> PixelCanvas:
	pose = p
	t = prog
	var dm := frame_dims(spec, pose)
	var sz: Vector2i = dm["size"]
	var anchor: Vector2 = dm["anchor"]
	cv = PixelCanvas.new(sz.x, sz.y)
	var raster := raster_scale(String(spec.get("race", "human")))
	var lying := pose == "prone" or pose == "dead"
	_ring(anchor, lying)
	if pose == "dead":
		_blood_pool(anchor)
	if pose == "prone":
		cv.set_frame(anchor + Vector2(-H * 0.5, -tw * 0.5 + 0.5) * raster, raster, PI * 0.5)
	elif pose == "dead":
		cv.set_frame(anchor + Vector2(H * 0.5, -tw * 0.5 + 0.5) * raster, raster, -PI * 0.5)
	else:
		cv.set_frame(anchor, raster, 0.0)
	_rig()
	if lying:
		# arms flung forward along the body
		j["hr"] = (j["sc"] as Vector2) + Vector2(2.0, -2.0)
		j["er"] = _ik(j["sr"], j["hr"], arm_a, arm_b, 1.0)
		j["wdir"] = Vector2.from_angle(deg_to_rad(-80.0))
	_draw_figure(true)
	if pose == "dead" and not _it("weapon").is_empty() and not _lost("hand_r"):
		# dropped weapon lying flat beside the body
		var flat := cv.xf.basis_xform_inv(Vector2(1, 0)).normalized()
		_draw_weapon((j["sc"] as Vector2) + Vector2(-tw * 0.5 - 2.0, 2.0), flat)
	_ground_blood(anchor, lying)
	return cv

func _draw_figure(full: bool) -> void:
	var dead := pose == "dead"
	var wk := _wkind()
	if full and spec.get("role", "troop") in ["officer", "captain"] and not dead:
		_banner()
	_arm("l")
	_leg("l")
	_leg("r")
	_torso()
	if not _lost("head"):
		_head()
	else:
		cv.dot((j["sc"] as Vector2) + Vector2(0, -1), BLOOD)
	if full:
		_shield()
		if not dead and wk != "none":
			_draw_weapon(j["grip"], j["wdir"])
	_arm("r")
	if full and not dead and (wk == "swing2" or wk == "thrust2") and not _lost("hand_l") and not _lost("arm_lower_l") \
			and not _lost("arm_upper_l"):
		cv.begin()
		cv.ellipse(j["hl"], arm_r * 1.1 + 0.15, arm_r * 1.1 + 0.15, skin)
		_skin_end()
	_wounds()

# --- body layers --------------------------------------------------------------------------------

func _cloth_col() -> Color:
	return prim

func _trouser_col() -> Color:
	return sec.darkened(0.55).lerp(Color("#4a3a2e"), 0.5)

func _ring(anchor: Vector2, lying: bool) -> void:
	var tc: Color = spec.get("team", Color(0, 0, 0, 0))
	# soft ground shadow
	var raster := raster_scale(String(spec.get("race", "human")))
	var rx := ((H * 0.5 + 2.0) if lying else (tw * 0.5 + 3.5)) * raster
	var ry := 2.4 * raster
	for y in range(floori(anchor.y - ry - 1), ceili(anchor.y + ry + 1)):
		for x in range(floori(anchor.x - rx - 1), ceili(anchor.x + rx + 1)):
			var dx := (x + 0.5 - anchor.x) / rx
			var dy := (y + 0.5 - anchor.y + 0.5) / ry
			var d := dx * dx + dy * dy
			if d <= 1.0:
				cv.set_px(x, y, Color(0, 0, 0, 0.28))
			if tc.a > 0.0 and d <= 1.0 and d >= 0.55:
				var c := tc if y >= anchor.y else tc.darkened(0.35)
				if pose == "dead":
					c.a = 0.45
				cv.set_px(x, y, c)

func _blood_pool(anchor: Vector2) -> void:
	var lostb := 1.0 - float(spec.get("blood", 1.0))
	var raster := raster_scale(String(spec.get("race", "human")))
	var rx := (4.0 + lostb * 9.0) * raster
	cv.begin()
	cv.ellipse(anchor + Vector2(-1.0, -0.5) * raster, rx, (1.6 + lostb * 1.2) * raster, BLOOD_DARK.lerp(BLOOD, 0.35))
	cv.end(Color(0, 0, 0, 0), 0.0)

func _ground_blood(anchor: Vector2, lying: bool) -> void:
	var lostb := 1.0 - float(spec.get("blood", 1.0))
	var n: int = int(lostb * 10.0) + (spec.get("bleed", {}) as Dictionary).size() * 2
	if n <= 0 or lying:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0)) + 99
	for i in n:
		var x := int(anchor.x + rng.randf_range(-tw * 0.7 - 2.0, tw * 0.7 + 2.0) * raster_scale(String(spec.get("race", "human"))))
		var y := int(anchor.y + rng.randf_range(-1.5, 1.0) * raster_scale(String(spec.get("race", "human"))))
		cv.set_px(x, y, BLOOD if i % 3 else BLOOD_DARK)

func _banner() -> void:
	var sc: Vector2 = j["sc"]
	var base := sc + Vector2(-3.0, 3.0)
	var top := sc + Vector2(-3.0, -head_h - 9.0)
	cv.begin()
	cv.line1(base, top, WOOD.darkened(0.2))
	cv.end(ol(WOOD), 0.0)
	var captain: bool = spec.get("role", "") == "captain"
	var fl := 8.0 if captain else 6.0
	cv.begin()
	var pts := PackedVector2Array([top + Vector2(0, 0), top + Vector2(-fl, 0), top + Vector2(-fl + 2.0, 2.5),
		top + Vector2(-fl, 5.0), top + Vector2(0, 5.0)])
	var s2 := sec
	var p2 := prim
	cv.poly(pts, prim, func(_x: int, y: int, c: Color) -> Color:
		var row := y - int(cv.map(top).y)
		return s2 if row == 2 else c)
	cv.end(ol(p2), 0.12)
	if captain:
		var m := metal("copper", 3)
		cv.begin()
		cv.ellipse(top + Vector2(0.5, -0.5), 1.2, 1.2, m["base"])
		_metal_end(m)

func _sleeve_style() -> Dictionary:
	var b: String = _it("body").get("sprite", "")
	if b == "mail":
		var m := metal(_it("body").get("mat", "copper"), int(_it("body").get("q", 0)))
		return {"c": m["base"], "pat": _mail_pat(m), "ol": m["outline"], "len": 1.0}
	if not _it("clothing").is_empty():
		return {"c": _cloth_col(), "pat": Callable(), "ol": ol(_cloth_col()), "len": 0.7}
	return {}

func _arm(side: String) -> void:
	match String(spec.get("race", "human")):
		"goblin":
			if GoblinArt.arm(self, side): return
		"troll":
			if TrollArt.arm(self, side): return
		"dwarf":
			if DwarfArt.arm(self, side): return
		"human":
			if HumanArt.arm(self, side): return
		"orc":
			if OrcArt.arm(self, side): return
		"high_elf", "moon_elf", "dark_elf":
			if ElfArt.arm(self, side): return
	var sh: Vector2 = j["s" + side]
	var el: Vector2 = j["e" + side]
	var hd: Vector2 = j["h" + side]
	if _lost("arm_upper_" + side):
		cv.dot(sh, BLOOD)
		return
	var sl := _sleeve_style()
	var lower_lost := _lost("arm_lower_" + side)
	var hand_lost := _lost("hand_" + side)
	cv.begin()
	cv.capsule(sh, el, arm_r, skin)
	if not lower_lost:
		cv.capsule(el, hd, arm_r * 0.92, skin)
		if not hand_lost:
			cv.ellipse(hd, arm_r + 0.25, arm_r + 0.25, skin)
	_skin_end()
	if not sl.is_empty():
		cv.begin()
		var endp: Vector2 = sh.lerp(el, sl["len"]) if sl["len"] < 1.0 else el
		cv.capsule(sh, endp, arm_r + 0.15, sl["c"], sl["pat"])
		cv.end(sl["ol"], 0.12)
	if lower_lost:
		cv.dot(el, BLOOD)
	elif hand_lost:
		cv.dot(hd, BLOOD)
	if not lower_lost:
		var hands := _it("hands")
		if not hands.is_empty():
			var m := metal(hands.get("mat", "copper"), int(hands.get("q", 0)))
			match String(hands.get("tid", "")):
				"arm_rings":
					cv.dot(el.lerp(hd, 0.45), m["shine"])
					cv.dot(el.lerp(hd, 0.75), m["light"])
				"crude_bracers":
					cv.begin()
					cv.capsule(el.lerp(hd, 0.3), el.lerp(hd, 0.75), arm_r + 0.2, m["dark"].lerp(m["base"], 0.5))
					_metal_end(m)
				_:
					cv.begin()
					cv.capsule(el.lerp(hd, 0.1), el.lerp(hd, 0.8), arm_r + 0.15, m["base"])
					_metal_end(m)
	var body: String = _it("body").get("sprite", "")
	if side == "r" and body in ["lamellar", "scrap"]:
		var m := metal(_it("body").get("mat", "copper"), int(_it("body").get("q", 0)))
		cv.begin()
		if body == "lamellar":
			var lc := sec.darkened(0.2)
			var pat := func(_x: int, y: int, c: Color) -> Color:
				return lc if y % 2 == 0 else c
			if _human(): pat = _human_armor_pat("lamellar", m, sh)
			cv.rect(Rect2(sh + Vector2(-2.0, -1.2), Vector2(3.5, 3.5)), m["base"], pat)
		else:
			cv.poly(PackedVector2Array([sh + Vector2(-2.5, -1.5), sh + Vector2(1.5, -1.8), sh + Vector2(1.0, 2.0),
				sh + Vector2(-2.0, 2.5)]), m["dark"].lerp(m["base"], 0.6))
		_metal_end(m)

func _leg(side: String) -> void:
	match String(spec.get("race", "human")):
		"goblin":
			if GoblinArt.leg(self, side): return
		"troll":
			if TrollArt.leg(self, side): return
		"dwarf":
			if DwarfArt.leg(self, side): return
		"human":
			if HumanArt.leg(self, side): return
		"orc":
			if OrcArt.leg(self, side): return
		"high_elf", "moon_elf", "dark_elf":
			if ElfArt.leg(self, side): return
	var hp: Vector2 = j["p" + side]
	var kn: Vector2 = j["k" + side]
	var ft: Vector2 = j["f" + side]
	if _lost("leg_upper_" + side):
		cv.dot(hp, BLOOD)
		return
	var trousers := not _it("legs_under").is_empty()
	var greaves := _it("legs")
	var shoes := not _it("feet").is_empty()
	var tcol := _trouser_col() if trousers else skin
	var far := side == "l"
	cv.begin()
	cv.capsule(hp, kn, leg_r, tcol)
	var lower_lost := _lost("leg_lower_" + side)
	if not lower_lost:
		cv.capsule(kn, ft, leg_r * 0.9, tcol)
		if not _lost("foot_" + side):
			cv.rect(Rect2(ft + Vector2(-1.2, -0.5), Vector2(3.4 * gs, 2.0)), Color("#4a3020") if shoes else skin)
	if trousers:
		cv.end(ol(tcol), 0.12)
	else:
		_skin_end()
	if lower_lost:
		cv.dot(kn, BLOOD)
	elif _lost("foot_" + side):
		cv.dot(ft, BLOOD)
	elif not greaves.is_empty():
		var m := metal(greaves.get("mat", "copper"), int(greaves.get("q", 0)))
		cv.begin()
		cv.capsule(kn + Vector2(0.3, 0.3), ft + Vector2(0.3, -0.5), leg_r * 0.95, m["base"])
		_metal_end(m)
	if far:
		pass

func _torso_pts(skirt: float, spread: float = 0.0) -> PackedVector2Array:
	var hip: Vector2 = j["hip"]
	var sc: Vector2 = j["sc"]
	var pts := PackedVector2Array([sc + Vector2(-tw * 0.5, 0.0), sc + Vector2(tw * 0.5, 0.0),
		sc + Vector2(tw * 0.5 + 0.6, torso_len * 0.4), hip + Vector2(hipw * 0.5, 0.0)])
	if skirt > 0.0:
		pts.append(hip + Vector2(hipw * 0.5 + 0.8 + spread, skirt))
		pts.append(hip + Vector2(-hipw * 0.5 - 0.8 - spread, skirt))
	else:
		pts.append(hip + Vector2(hipw * 0.5, 1.0))
		pts.append(hip + Vector2(-hipw * 0.5, 1.0))
	pts.append(hip + Vector2(-hipw * 0.5, 0.0))
	return pts

func _spread() -> float:
	return absf((j["fr"] as Vector2).x - (j["fl"] as Vector2).x) * 0.25

func _belt(y_local: float, col: Color, buckle: Color) -> void:
	var hip: Vector2 = j["hip"]
	var sc: Vector2 = j["sc"]
	var a := hip.lerp(sc, y_local)
	var halfw := lerpf(hipw, tw, y_local) * 0.5 + 0.3
	cv.rect(Rect2(a + Vector2(-halfw, -1.0), Vector2(halfw * 2.0, 1.0)), col)
	cv.dot(a + Vector2(halfw - 2.0, -1.0), buckle)

func _torso() -> void:
	match String(spec.get("race", "human")):
		"goblin":
			if GoblinArt.torso(self): return
		"troll":
			if TrollArt.torso(self): return
		"dwarf":
			if DwarfArt.torso(self): return
		"human":
			if HumanArt.torso(self): return
		"orc":
			if OrcArt.torso(self): return
		"high_elf", "moon_elf", "dark_elf":
			if ElfArt.torso(self): return
	var sc: Vector2 = j["sc"]
	cv.begin()
	cv.poly(_torso_pts(0.0), skin)
	_skin_end()
	var cl := _it("clothing")
	var spread := _spread()
	if not cl.is_empty():
		var c := _cloth_col()
		var hem := leg_len * 0.36
		var s2 := sec
		var hem_y := int(floor(cv.map((j["hip"] as Vector2) + Vector2(0, hem)).y))
		cv.begin()
		var cloth_pat := func(_x: int, y: int, cc: Color) -> Color:
			return s2 if y == hem_y - 1 else cc
		if _human(): cloth_pat = _human_cloth_pat(sc, hem_y, s2)
		cv.poly(_torso_pts(hem, spread), c, cloth_pat)
		# collar
		cv.rect(Rect2(sc + Vector2(tw * 0.5 - 2.0, 0.0), Vector2(2.0, 1.0)), s2)
		_belt(0.12, LEATHER, metal("copper")["light"])
		cv.end(ol(c), 0.12)
	var b := _it("body")
	if b.is_empty():
		return
	var m := metal(b.get("mat", "copper"), int(b.get("q", 0)))
	var sp: String = b.get("sprite", "")
	var hip_y := int(floor(cv.map(j["hip"]).y))
	cv.begin()
	match sp:
		"mail":
			cv.poly(_torso_pts(leg_len * 0.5, spread), m["base"], _mail_pat(m))
			_belt(0.1, LEATHER, m["trim"])
			_hem(leg_len * 0.5, spread, m)
		"byrnie":
			var dk: Color = m["dark"]
			var pat := func(x: int, y: int, c: Color) -> Color:
				return dk.lerp(c, 0.35) if y % 2 == 0 and (x + y / 2) % 2 == 0 else c
			if _human(): pat = _human_armor_pat("mail", m, sc)
			cv.poly(_torso_pts(leg_len * 0.2, spread), m["base"], pat)
			_belt(0.15, LEATHER, m["trim"])
			_hem(leg_len * 0.2, spread, m)
		"scale":
			var dk: Color = m["dark"]
			var lt: Color = m["light"]
			var pat := func(x: int, y: int, c: Color) -> Color:
				var sh := (y / 2) % 2
				if y % 2 == 1:
					return dk if (x + sh) % 2 == 0 else c
				return lt if (x + sh) % 2 == 1 else c
			if _human(): pat = _human_armor_pat("scale", m, sc)
			cv.poly(_torso_pts(leg_len * 0.16, spread), m["base"], pat)
			_hem(leg_len * 0.16, spread, m)
		"lamellar":
			var lace := sec
			var dk: Color = m["dark"]
			var pat := func(x: int, y: int, c: Color) -> Color:
				if (y - hip_y) % 3 == 0:
					return lace
				return dk.lerp(c, 0.5) if x % 2 == 0 else c
			if _human(): pat = _human_armor_pat("lamellar", m, sc)
			cv.poly(_torso_pts(leg_len * 0.42, spread + 0.5), m["base"], pat)
			_hem(leg_len * 0.42, spread + 0.5, m)
		"scrap":
			# mismatched plates riveted onto the torso
			var rng := RandomNumberGenerator.new()
			rng.seed = int(spec.get("seed", 0))
			var tones: Array = [m["base"], m["dark"].lerp(m["base"], 0.4), m["light"], metal("copper" if b.get("mat") == "tin" else "tin")["base"]]
			cv.poly(_torso_pts(1.5, spread), m["dark"].lerp(m["base"], 0.6))
			var hip: Vector2 = j["hip"]
			var rows := 3
			for r in rows:
				var y0 := lerpf(sc.y, hip.y + 1.0, float(r) / rows)
				var y1 := lerpf(sc.y, hip.y + 1.0, float(r + 1) / rows)
				var off := rng.randf_range(-1.0, 1.0)
				var cx := lerpf(sc.x, hip.x, float(r) / rows) + off
				cv.rect(Rect2(Vector2(cx - tw * 0.5 + 0.5, y0 + 0.4), Vector2(tw * 0.55, y1 - y0)), tones[(r + int(spec.get("seed", 0))) % tones.size()])
				cv.rect(Rect2(Vector2(cx + 0.5, y0 + 0.8), Vector2(tw * 0.45, y1 - y0 - 0.4)), tones[(r + 1 + int(spec.get("seed", 0))) % tones.size()])
				cv.dot(Vector2(cx - tw * 0.5 + 1.0, y0 + 1.0), m["shine"])
			_belt(0.05, Color("#8a7a50"), m["dark"])
		_:
			cv.poly(_torso_pts(leg_len * 0.3, spread), m["base"])
	_metal_end(m)
	if int(b.get("q", 0)) >= 2:
		_sparkle(sc + Vector2(tw * 0.5 - 2.0, 1.0), m)

func _hem(skirt: float, spread: float, m: Dictionary) -> void:
	var hip: Vector2 = j["hip"]
	if int(m.get("q", 0)) >= 1:
		cv.rect(Rect2(hip + Vector2(-hipw * 0.5 - 0.8 - spread, skirt - 1.0), Vector2(hipw + 1.6 + spread * 2.0, 1.0)), m["trim"])

func _mail_pat(m: Dictionary) -> Callable:
	if _human(): return _human_armor_pat("mail", m, j["sc"])
	var dk: Color = m["dark"]
	var lt: Color = m["light"]
	return func(x: int, y: int, c: Color) -> Color:
		# staggered ring rows: a dark ring hole every other pixel, a light glint between rows
		if y % 2 == 0:
			return dk.lerp(c, 0.3) if (x + (y / 2) % 2) % 2 == 0 else c
		return lt.lerp(c, 0.55) if (x + (y / 2) % 2) % 2 == 1 else c


# Human surface detail recolours only pixels inside the existing shape masks.
# Local logical coordinates keep texture scale consistent at figure/bust size.
# Nonhuman races retain the legacy palettes, patterns and drawing path.
func _human() -> bool:
	return String(spec.get("race", "human")) == "human"

func _human_cloth_pat(sc: Vector2, hem_y: int, trim: Color) -> Callable:
	var inverse := cv.xf.affine_inverse()
	return func(x: int, y: int, c: Color) -> Color:
		if y == hem_y - 1: return trim
		var local: Vector2 = inverse * Vector2(x + 0.5, y + 0.5) - sc
		# Quiet chest planes/folds; original faction collar and belt draw above.
		if local.y < 1.5 and local.x > 0.5: return c.darkened(0.22)
		if local.x < -2.0: return c.darkened(0.15)
		if local.x > 2.5 and local.y > 2.0: return c.darkened(0.12)
		if local.x > 0.5 and local.x < 1.3 and local.y > 2.0: return c.darkened(0.10)
		if local.x >= -1.7 and local.x < 0.3 and local.y < torso_len - 1.0: return c.lightened(0.10)
		return c

func _human_armor_pat(kind: String, m: Dictionary, origin: Vector2) -> Callable:
	var inverse := cv.xf.affine_inverse()
	var dk: Color = m["dark"]
	var lt: Color = m["light"]
	var lace := sec
	return func(x: int, y: int, c: Color) -> Color:
		var local: Vector2 = inverse * Vector2(x + 0.5, y + 0.5) - origin
		var ix := floori(local.x)
		var iy := floori(local.y)
		var row := posmod(iy, 3)
		if kind == "lamellar":
			if row == 2: return lace.darkened(0.10)
			if posmod(ix, 3) == 0: return dk.lerp(c, 0.45)
			return lt.lerp(c, 0.65) if row == 0 else c
		if kind == "scale":
			var stagger := posmod(floori(float(iy) / 2.0), 2)
			if posmod(iy, 2) == 1:
				return dk.lerp(c, 0.25) if posmod(ix + stagger, 3) != 2 else c
			return lt.lerp(c, 0.40) if posmod(ix + stagger, 3) == 1 else c
		# Staggered mail rings with shared logical spacing at k1 and k3.
		var stagger := posmod(floori(float(iy) / 2.0), 2)
		if posmod(iy, 2) == 0:
			return dk.lerp(c, 0.40) if posmod(ix + stagger, 2) == 0 else c
		return lt.lerp(c, 0.60) if posmod(ix + stagger, 2) == 1 else c

func _human_face_pat(hc: Vector2, x1: float) -> Callable:
	var inverse := cv.xf.affine_inverse()
	var small := cv.k < 2.0
	var dead := pose == "dead"
	return func(x: int, y: int, c: Color) -> Color:
		var local: Vector2 = inverse * Vector2(x + 0.5, y + 0.5) - hc
		# Individual skin planes; native eye/nose/mouth, hair and helm draw
		# afterwards. Wounds remain the final layer and pallor uses native skin.
		if small and local.y >= 1.0 and local.y < 2.0 and local.x >= x1 - 2.0:
			return c.darkened(0.30 if dead else 0.40)
		if local.x < -1.0: return c.darkened(0.14)
		if local.y < -1.5 and local.x < x1 - 1.0: return c.lightened(0.10)
		if local.y >= 1.5: return c.darkened(0.16)
		if local.y >= 0.0 and local.y < 1.0 and local.x >= 0.0: return c.lightened(0.12)
		return c

func _human_hair_pat(hc: Vector2, beard: bool) -> Callable:
	var inverse := cv.xf.affine_inverse()
	var phase := posmod(int(spec.get("seed", 0)), 3)
	return func(x: int, y: int, c: Color) -> Color:
		var local: Vector2 = inverse * Vector2(x + 0.5, y + 0.5) - hc
		var ix := floori(local.x)
		var iy := floori(local.y)
		if beard:
			if local.y < 1.0: return c.darkened(0.12)
			if posmod(ix + phase, 3) == 1: return c.lightened(0.18)
			return c.darkened(0.13) if posmod(ix + phase, 3) == 0 else c
		if local.y < -2.5: return c.lightened(0.22)
		if posmod(ix + phase, 3) == 1 and posmod(iy, 3) != 2: return c.lightened(0.14)
		return c.darkened(0.12) if local.x < -2.0 else c

# --- head ---------------------------------------------------------------------------------------

func _head() -> void:
	if String(_it("helm").get("sprite","")) == "closed":
		if _lost("head"): return
		var hc: Vector2 = j["hc"]
		var sc: Vector2 = j["sc"]
		# The closed visor conceals the face, ears and hair. Preserve the neck and rig.
		if force_legacy_v064 and not _human():
			cv.begin()
			cv.capsule(hc+Vector2(0.0,1.40 if _human() else 1.80),sc+Vector2(0.0,0.15 if _human() else -0.24),0.69,skin)
			_skin_end()
		else:
			var sh_neck := cv.shaded()
			var c_sk: int = sh_neck.add_color(skin.darkened(0.14), 0.10, 1.06)
			sh_neck.capsule(hc+Vector2(0.0,1.40 if _human() else 1.80),sc+Vector2(0.0,0.15 if _human() else -0.24),0.72,0.82,c_sk,-1.0,0.9)
			sh_neck.composite(FigurePainter.ol(skin), true)
		var previous := cv.xf
		var previous_k := cv.k
		if String(spec.get("race","")) == "dwarf":
			var scale := DwarfArt.HEAD_SCALE
			cv.xf = previous*Transform2D(0.0,Vector2(scale,scale),0.0,hc*(1.0-scale))
			cv.k = previous_k*scale
		elif _human():
			var scale := HumanArt.HEAD_SCALE
			cv.xf = previous*Transform2D(0.0,Vector2(scale,scale),0.0,hc*(1.0-scale))
			cv.k = previous_k*scale
		_helm(hc,-head_w*0.5,head_w*0.5,-head_h*0.5,head_h*0.5)
		cv.xf = previous;cv.k = previous_k
		return
	match String(spec.get("race", "human")):
		"goblin": GoblinArt.head(self); return
		"troll": TrollArt.head(self); return
		"dwarf": DwarfArt.head(self); return
		"human": HumanArt.head(self); return
		"orc": OrcArt.head(self); return
		"high_elf", "moon_elf", "dark_elf": ElfArt.head(self); return
	var hc: Vector2 = j["hc"]
	var x0 := -head_w * 0.5
	var x1 := head_w * 0.5
	var y0 := -head_h * 0.5
	var y1 := head_h * 0.5
	var detail := cv.k >= 2.0
	var dead := pose == "dead"
	# head shape (chamfered box) + nose
	cv.begin()
	var pts := PackedVector2Array()
	for p in [Vector2(x0 + 1, y0), Vector2(x1 - 1, y0), Vector2(x1, y0 + 1), Vector2(x1, y1 - 1), Vector2(x1 - 1, y1),
			Vector2(x0 + 1, y1), Vector2(x0, y1 - 1), Vector2(x0, y0 + 1)]:
		pts.append(hc + p)
	cv.poly(pts, skin, _human_face_pat(hc, x1) if _human() else Callable())
	var nose: int = ra.get("nose", 1)
	cv.rect(Rect2(hc + Vector2(x1, 0.0), Vector2(nose, 1.0)), skin)
	if ra.get("tusks", false):
		cv.rect(Rect2(hc + Vector2(x1 - 1.0, 1.0), Vector2(1.0, 1.0)), Color("#f4efd8"))
	_skin_end()
	# eye / brow
	var eye := Color(ra.get("eye", "#1c1424"))
	if detail:
		_face_detail(hc, x1, eye, dead)
	else:
		if dead:
			cv.dot(hc + Vector2(x1 - 2.0, -1.0), skin.darkened(0.5))
		else:
			cv.dot(hc + Vector2(x1 - 2.0, -1.0), eye)
		if ra.get("brow", false):
			cv.rect(Rect2(hc + Vector2(x1 - 2.5, -2.0), Vector2(2.5, 1.0)), skin.darkened(0.35))
	_hair_and_beard(hc, x0, x1, y0, y1)
	_ears(hc, x0, y0)
	_helm(hc, x0, x1, y0, y1)

func _face_detail(hc: Vector2, x1: float, eye: Color, dead: bool) -> void:
	var e := cv.map_i(hc + Vector2(x1 - 2.0, -1.0))
	var dk := skin.darkened(0.45).lerp(hair, 0.18) if _human() else skin.darkened(0.45)
	var kk := int(round(cv.k))
	# brow
	for x in range(e.x - kk + 1, e.x + kk + 1):
		cv.set_px(x, e.y - 1, dk if not ra.get("brow", false) else skin.darkened(0.6))
	if ra.get("brow", false):
		for x in range(e.x - kk + 1, e.x + kk + 1):
			cv.set_px(x, e.y, skin.darkened(0.3))
	if dead:
		for x in range(e.x - 1, e.x + 2):
			cv.set_px(x, e.y + 1, dk)
	else:
		cv.set_px(e.x - 1, e.y + 1, Color("#f2f0ea"))
		cv.set_px(e.x, e.y + 1, Color("#f2f0ea"))
		cv.set_px(e.x + 1, e.y + 1, eye)
		cv.set_px(e.x + 1, e.y + 2, eye.darkened(0.4))
		cv.set_px(e.x, e.y + 2, skin.darkened(0.15))
	# nostril + mouth
	var n := cv.map_i(hc + Vector2(x1, 0.0))
	cv.set_px(n.x, n.y + kk - 1, skin.darkened(0.3))
	var m := cv.map_i(hc + Vector2(x1 - 1.6, 1.5))
	for x in range(m.x, m.x + kk + 1):
		cv.set_px(x, m.y, skin.darkened(0.5).lerp(Color("#7a2020"), 0.3))
	if ra.get("shiny", false):
		var c := cv.map_i(hc + Vector2(x1 - 2.6, 0.3))
		cv.set_px(c.x, c.y, skin.lightened(0.35))

func _hair_style() -> String:
	var styles: Array = ra.get("hair_styles", ["short"])
	return styles[int(spec.get("seed", 0)) % styles.size()]

func _hair_and_beard(hc: Vector2, x0: float, x1: float, y0: float, y1: float) -> void:
	var st := _hair_style()
	var helmed := not _it("helm").is_empty()
	var texture := _human_hair_pat(hc, false) if _human() else Callable()
	if st != "bald":
		cv.begin()
		match st:
			"short":
				cv.rect(Rect2(hc + Vector2(x0, y0 - 1.0), Vector2(head_w - 1.0, 2.0)), hair, texture)
				cv.rect(Rect2(hc + Vector2(x0 - 0.5, y0), Vector2(2.0, head_h * 0.55)), hair, texture)
			"long":
				cv.rect(Rect2(hc + Vector2(x0, y0 - 1.0), Vector2(head_w - 0.5, 2.0)), hair, texture)
				cv.rect(Rect2(hc + Vector2(x0 - 1.0, y0), Vector2(2.5, head_h + 2.0)), hair, texture)
				cv.rect(Rect2(hc + Vector2(x1 - 2.0, y0), Vector2(1.5, 1.0)), hair, texture)
			"ponytail":
				cv.rect(Rect2(hc + Vector2(x0, y0 - 1.0), Vector2(head_w - 1.0, 2.0)), hair, texture)
				cv.rect(Rect2(hc + Vector2(x0 - 0.5, y0), Vector2(1.5, head_h * 0.45)), hair, texture)
				cv.capsule(hc + Vector2(x0 - 0.5, y0 + 1.0), hc + Vector2(x0 - 2.5, y0 + 5.0), 0.75, hair, texture)
			"mohawk":
				if not helmed:
					cv.rect(Rect2(hc + Vector2(x0 + 0.5, y0 - 2.0), Vector2(head_w - 2.5, 2.0)), hair, texture)
			"topknot":
				cv.rect(Rect2(hc + Vector2(x0 + 0.5, y0 - 0.5), Vector2(head_w - 2.5, 1.0)), hair, texture)
				if not helmed:
					cv.ellipse(hc + Vector2(x0 + 1.5, y0 - 1.5), 1.2, 1.2, hair, texture)
					cv.capsule(hc + Vector2(x0 + 1.0, y0 - 1.0), hc + Vector2(x0 - 1.5, y0 + 2.0), 0.6, hair, texture)
			"tuft":
				cv.rect(Rect2(hc + Vector2(x0 + 1.0, y0 - 1.0), Vector2(2.0, 1.0)), hair, texture)
		cv.end(ol(hair), 0.15, hair.lightened(0.3) if ra.get("shiny", false) else Color(0, 0, 0, 0))
	if spec.get("beard", false):
		var long := int(spec.get("seed", 0)) / 7 % 2 == 0
		texture = _human_hair_pat(hc, true) if _human() else Callable()
		cv.begin()
		cv.rect(Rect2(hc + Vector2(-1.0, 1.0), Vector2(x1 + 1.0, y1 - 1.0)), hair, texture)
		cv.rect(Rect2(hc + Vector2(x1 - 2.0, 0.0), Vector2(2.0, 1.0)), hair, texture)
		if long:
			cv.rect(Rect2(hc + Vector2(0.0, y1), Vector2(x1 - 0.5, 1.5)), hair, texture)
		cv.end(ol(hair), 0.12)
		if ra.get("tusks", false):
			cv.dot(hc + Vector2(x1 - 1.0, 1.0), Color("#f4efd8"))

func _ears(hc: Vector2, x0: float, y0: float) -> void:
	var e: String = ra.get("ears", "round")
	match e:
		"round":
			if _it("helm").get("sprite", "") in ["coif"]:
				return
			cv.dot(hc + Vector2(-1.0, -0.5), skin.darkened(0.2))
		"long":
			cv.begin()
			cv.poly(PackedVector2Array([hc + Vector2(-1.5, -1.0), hc + Vector2(-0.5, 1.0), hc + Vector2(x0 - 2.5, y0 - 1.0)]), skin)
			_skin_end()
		"big":
			cv.begin()
			cv.poly(PackedVector2Array([hc + Vector2(-1.0, -1.5), hc + Vector2(0.0, 1.0), hc + Vector2(x0 - 3.5, y0 + 0.5),
				hc + Vector2(x0 - 2.0, -0.5)]), skin)
			_skin_end()
			cv.dot(hc + Vector2(x0 - 1.0, -1.0), skin.darkened(0.3))
		"small":
			cv.begin()
			cv.poly(PackedVector2Array([hc + Vector2(-1.5, -0.5), hc + Vector2(-0.5, 1.0), hc + Vector2(x0 - 1.0, y0 + 0.5)]), skin)
			_skin_end()

func _helm_poly(hc: Vector2, points: Array, col: Color, pat: Callable = Callable()) -> void:
	var pts := PackedVector2Array()
	for point in points:
		pts.append(hc + Vector2(float(point[0]),float(point[1])))
	cv.poly(pts,col,pat)

static func helm_maker(hm: Dictionary) -> String:
	# A traded helmet keeps its maker's design. The wearer never supplies a culture.
	var maker: String = String(hm.get("maker_race",""))
	if maker != "": return maker
	var tm: Dictionary = DB.armor.get(String(hm.get("tid","")), {})
	var culture: String = String(hm.get("culture",tm.get("culture","")))
	return culture if culture in ["orc","moon_elf","dwarf","goblin"] else ""

func _helm_fit() -> Dictionary:
	var race: String = String(spec.get("race","human"))
	var brow := -2.08
	var temple := -1.80
	if race.ends_with("elf"): brow = -2.12; temple = -2.22
	elif race == "orc": brow = -2.13; temple = -2.38
	elif race == "dwarf": brow = -2.08; temple = -2.10
	elif race == "goblin": brow = -2.20; temple = -2.30
	elif race == "troll": brow = -2.62; temple = -2.95
	return {"brow":brow,"temple":temple,"half":head_w*0.5+0.32}

func _helm_surface(hc: Vector2, top: float, m: Dictionary) -> Callable:
	var inv := cv.xf.affine_inverse()
	var half := head_w*0.5+0.32
	return func(x: int,y: int,c: Color)->Color:
		var p: Vector2 = inv*Vector2(x+0.5,y+0.5)-hc
		var curve := clampf((p.x/half+0.26)*0.66,0.0,1.0)
		var out := c.lerp(m["light"],0.26).lerp(m["dark"],curve*0.72)
		if p.x < -half*0.65: out = out.lerp(m["dark"],0.24)
		if p.y < top+0.8 and p.x < half*0.15: out = out.lerp(m["light"],0.22)
		return out

func _helm_rim(hc: Vector2, half: float, brow: float, m: Dictionary, thick: float = 0.18) -> void:
	# The curved lower band follows the forehead, with side coverage behind the face.
	cv.capsule(hc+Vector2(-half+0.32,brow-0.19),hc+Vector2(-half*0.37,brow-0.06),thick,m["dark"])
	cv.capsule(hc+Vector2(-half*0.37,brow-0.06),hc+Vector2(half-0.18,brow-0.21),thick,m["light"])
	for x in [-half+0.63,-0.15,half-0.65]:
		cv.ellipse(hc+Vector2(x,brow-0.17),0.11,0.11,m["shine"])

func _helm_nasal(hc: Vector2, brow: float, m: Dictionary) -> void:
	# A tapered guard follows the actual nose bridge and bends over its tip.
	# The eye opening has two sides; the bridge between them is not empty air.
	var race: String = String(spec.get("race","human"))
	var female: bool = String(spec.get("sex","")) == "female"
	var refined: bool = female and female_variant(spec) == 1
	var lo := 1.595
	var hi := 1.745
	var tip := 2.91
	var bottom := 0.64
	var release := -0.20
	if race == "human" and female:
		lo = 0.925 if refined else 1.515
		hi = 1.065 if refined else 1.615
		tip = 1.83 if refined else 2.64
		release = -0.18 if refined else -0.35
	elif race.ends_with("elf"):
		lo = 0.49; hi = 0.69; tip = 1.36; bottom = 0.48; release = -0.30
	elif race == "orc":
		var compact: bool = posmod(int(absi(int(spec.get("seed",0)))/10),2) == 1
		lo = (2.47 if compact else 2.28) if not female else (2.12 if refined else 1.98)
		hi = lo+0.20
		tip = lo+0.58; bottom = 0.66; release = 0.18 if not female else 0.17
	elif race == "dwarf":
		lo = 1.84 if not refined else 1.79
		hi = lo+0.16
		tip = 3.25 if not female else (2.45 if refined else 3.03)
		release = -0.04
	elif race == "goblin":
		lo = 2.35; hi = 2.60; tip = 3.62; release = -0.02
	elif race == "troll":
		lo = 3.44; hi = 3.68; tip = 4.10; release = 0.12
	cv.begin()
	# Explicit fine edging keeps the narrow bridge from occluding either eye.
	_helm_poly(hc,[[lo-0.15,brow-0.33],[hi+0.20,brow-0.34],[hi,-1.42],[hi,release],
		[tip,bottom-0.10],[tip-0.10,bottom+0.15],[tip-0.47,bottom+0.17],
		[lo,release+0.24],[lo,-1.42]],m["dark"])
	_helm_poly(hc,[[lo-0.02,brow-0.27],[hi+0.07,brow-0.27],[hi-0.035,-1.39],
		[hi-0.035,release+0.055],[tip-0.11,bottom-0.08],[tip-0.20,bottom+0.03],
		[tip-0.41,bottom+0.05],[lo+0.035,release+0.19],[lo+0.035,-1.39]],m["light"])
	cv.end(Color(0,0,0,0),0.025)

func _helm_aventail(hc: Vector2, half: float, temple: float, m: Dictionary) -> void:
	cv.begin()
	_helm_poly(hc,[[-half,-2.8],[temple-0.18,-2.40],[temple-0.11,0.0],
		[temple+0.14,1.55],[-half+0.34,2.08],[-half-0.52,1.04]],m["base"],_mail_pat(m))
	cv.capsule(hc+Vector2(-half+0.18,1.67),hc+Vector2(temple-0.13,1.34),0.12,m["dark"])
	_metal_end(m)


func _closed_helm(hc: Vector2, m: Dictionary) -> float:
	# Fitted armet: rounded skull, angled cheek plates and a tapered chin.
	# Dark vision slits belong to the visor; the character's eyes are concealed.
	var h := head_w*0.44+0.08
	var top := -head_h*0.5-0.32
	var chin := head_h*0.39
	var ridge := h*0.22
	var pat := _helm_surface(hc,top,m)
	cv.begin()
	_helm_poly(hc,[[-h+0.20,chin-0.65],[-h-0.07,-1.71],[-h*0.80,top+0.72],
		[-h*0.35,top+0.06],[0.23,top-0.08],[h*0.70,top+0.55],
		[h+0.13,-1.75],[h+0.27,-0.25],[h+0.10,0.88],[h*0.61,chin-0.18],
		[ridge-0.12,chin+0.05],[-h*0.64,chin-0.28]],m["base"],pat)
	# The far side rolls away; the near cheek folds inward beneath the visor.
	_helm_poly(hc,[[-h+0.05,-1.70],[-h*0.75,top+0.83],[-h*0.52,-1.28],
		[-h*0.52,0.76],[-h*0.24,chin-0.22],[-h*0.65,chin-0.31],[-h+0.21,chin-0.74]],m["dark"].lerp(m["base"],0.30))
	_helm_poly(hc,[[ridge+0.19,-0.36],[h+0.15,-0.57],[h+0.10,0.88],
		[h*0.61,chin-0.18],[ridge-0.12,chin+0.05],[ridge+0.31,0.68]],m["dark"].lerp(m["base"],0.25),pat)
	_helm_poly(hc,[[-h*0.47,-0.13],[ridge-0.14,-0.48],[ridge+0.31,0.68],
		[ridge-0.12,chin+0.05],[-h*0.25,chin-0.33]],m["base"].lerp(m["light"],0.13),pat)
	# A continuous forged ridge connects the crown, nose and faceplate.
	_helm_poly(hc,[[ridge-0.24,top+0.16],[ridge+0.06,top+0.28],
		[ridge+0.19,-0.67],[ridge+0.44,0.50],[ridge+0.10,1.56],
		[ridge-0.15,1.20],[ridge-0.14,-0.66]],m["light"].lerp(m["base"],0.16))
	cv.capsule(hc+Vector2(ridge+0.20,top+0.32),hc+Vector2(ridge+0.36,-0.40),0.10,m["dark"])
	cv.capsule(hc+Vector2(-h*0.73,top+0.91),hc+Vector2(-h*0.35,top+0.29),0.10,m["shine"])
	cv.capsule(hc+Vector2(-h*0.68,chin-0.45),hc+Vector2(ridge-0.23,chin-0.07),0.10,m["light"])
	_metal_end(m)
	# Two angled black apertures, divided by the metal nasal guard.
	var recess: Color = m["dark"].darkened(0.70)
	_helm_poly(hc,[[-h*0.47,-1.19],[ridge-0.23,-1.04],[ridge-0.23,-0.69],
		[-h*0.44,-0.83]],recess)
	_helm_poly(hc,[[ridge+0.22,-1.04],[h*0.77,-1.23],[h*0.78,-0.90],
		[ridge+0.23,-0.70]],recess)
	cv.capsule(hc+Vector2(-h*0.45,-1.25),hc+Vector2(ridge-0.26,-1.10),0.065,m["dark"])
	cv.capsule(hc+Vector2(ridge+0.26,-1.10),hc+Vector2(h*0.75,-1.29),0.065,m["light"])
	# Small punched vents and a chin seam, never an exposed mouth.
	for x: float in [-0.74,-0.31]:
		cv.capsule(hc+Vector2(x,0.43),hc+Vector2(x+0.03,0.79),0.065,recess)
	cv.capsule(hc+Vector2(ridge+0.52,0.61),hc+Vector2(h*0.64,0.37),0.07,m["dark"])
	return top

func _helm(hc: Vector2,x0: float,x1: float,y0: float,_y1: float) -> void:
	var hm := _it("helm")
	if hm.is_empty() or _lost("head"): return
	var m := metal(hm.get("mat","copper"),int(hm.get("q",0)))
	var tid: String = String(hm.get("tid",""))
	var sp: String = String(hm.get("sprite",""))
	var maker := helm_maker(hm)
	if sp == "closed":
		var crown := _closed_helm(hc,m)
		if maker == "orc": OrcArt.helm_horns(self,hc,crown+1.18,m)
		elif maker == "moon_elf": ElfArt.helm_crescent(self,hc,crown,m)
		_sparkle(hc+Vector2(x0+0.8,crown+0.50),m)
		return
	if sp == "crescent" and maker == "moon_elf":
		ElfArt.worn_crescent_helm(self,hc,m)
		return
	# Unknown-mark standard pieces keep their template's design; known foreign forges
	# never acquire another people's decoration simply because the wearer is foreign.
	if sp == "crescent": sp = "spangen"
	var fit := _helm_fit()
	var h: float = fit["half"]
	var b: float = fit["brow"]
	var cut: float = fit["temple"]
	var top := y0-1.12
	var pat := _helm_surface(hc,top,m)
	if sp == "spangen": _helm_aventail(hc,h,cut,m)
	cv.begin()
	match sp:
		"nasal":
			if tid == "dwarf_helm":
				top = y0-1.34
				# A stout faceted bowl and close cheek plate, with a raised reinforcing keel.
				_helm_poly(hc,[[-h,-0.74],[-h-0.02,-2.54],[-h*0.85,-3.64],[-h*0.38,top],
					[h*0.16,top-0.06],[h*0.69,-3.58],[h-0.04,b-0.19],[h-0.25,b],
					[cut,b+0.08],[cut-0.25,-0.67],[-h+0.34,0.11]],m["base"],pat)
				cv.capsule(hc+Vector2(-0.34,top+0.18),hc+Vector2(-0.20,b-0.21),0.28,m["dark"])
				cv.capsule(hc+Vector2(-0.43,top+0.17),hc+Vector2(-0.31,b-0.29),0.12,m["light"])
				_helm_poly(hc,[[-h+0.08,-0.92],[cut-0.32,-0.75],[cut-0.39,0.51],
					[cut-0.63,1.68],[-h+0.19,1.48],[-h-0.17,0.62]],m["base"],pat)
				cv.capsule(hc+Vector2(-h+0.35,-0.51),hc+Vector2(-h+0.41,1.15),0.12,m["light"])
			else:
				top = y0-2.05
				# Forged cone: rounded bell below the point and protection at the rear temples.
				_helm_poly(hc,[[-h,-0.57],[-h-0.01,-2.45],[-h*0.85,-3.44],[-h*0.34,-4.61],
					[-0.12,top],[0.29,top+0.19],[h*0.55,-3.93],[h-0.13,b-0.24],
					[h-0.19,b],[cut,b+0.04],[cut-0.13,-0.90],[-h+0.23,-0.32]],m["base"],pat)
				cv.capsule(hc+Vector2(-0.15,top+0.3),hc+Vector2(-0.48,b-0.22),0.13,m["light"])
			_helm_rim(hc,h,b,m)
		"coif":
			# A rounded linked hood folds at the cheek and drapes naturally onto the shoulders.
			top = y0-1.19
			var sc: Vector2 = j["sc"]-hc
			_helm_poly(hc,[[-h-0.20,2.65],[-h-0.24,-1.14],[-h*0.90,-3.19],[-h*0.54,-4.04],
				[-0.25,y0-1.19],[h*0.39,-3.95],[h*0.80,-3.18],[h-0.02,b-0.18],
				[h-0.21,b-0.03],[cut+0.13,b],[cut-0.09,-0.74],[cut+0.02,1.71],
				[cut+0.61,3.06],[sc.x+1.37,sc.y+0.19],[sc.x+1.07,sc.y+0.89],
				[sc.x-1.8,sc.y+1.10],[-h-0.55,3.76]],m["base"],_mail_pat(m))
			cv.capsule(hc+Vector2(cut+0.08,b-0.05),hc+Vector2(h-0.24,b-0.20),0.12,m["light"])
			cv.capsule(hc+Vector2(cut-0.17,-0.64),hc+Vector2(cut+0.04,1.58),0.11,m["dark"])
			cv.capsule(hc+Vector2(-h-0.23,3.40),hc+sc+Vector2(0.70,0.73),0.14,m["dark"])
		"spangen":
			if tid == "steppe_helm":
				top = y0-2.53
				_helm_poly(hc,[[-h,-0.62],[-h,-2.82],[-h*0.76,-3.61],[-h*0.26,-4.73],
					[-0.04,top],[0.17,top+0.13],[h*0.46,-4.04],[h-0.07,b-0.23],
					[h-0.18,b],[cut,b+0.01],[cut-0.17,-0.94]],m["base"],pat)
				cv.capsule(hc+Vector2(-0.04,top+0.19),hc+Vector2(-0.38,b-0.20),0.16,m["light"])
			else:
				# A full dome of riveted panels; an arched cross-band replaces the hanging front frame.
				top = y0-1.46
				_helm_poly(hc,[[-h,-0.55],[-h-0.08,-2.49],[-h*0.88,-3.51],[-h*0.59,-4.16],
					[-h*0.15,y0-1.46],[h*0.31,y0-1.35],[h*0.71,-3.65],[h-0.02,b-0.22],
					[h-0.12,b],[cut,b+0.01],[cut-0.19,-0.84]],m["base"],pat)
				cv.capsule(hc+Vector2(-0.36,y0-1.22),hc+Vector2(-0.65,b-0.22),0.18,m["light"])
				cv.capsule(hc+Vector2(-h*0.62,-3.86),hc+Vector2(h*0.59,-3.52),0.14,m["light"])
				for point in [Vector2(-0.6,b-0.31),Vector2(-h*0.6,-3.68),Vector2(h*0.51,-3.47)]:
					cv.ellipse(hc+point,0.11,0.11,m["shine"])
			_helm_rim(hc,h,b,m,0.20)
		"skullcap":
			# A solid rounded bowl wraps the skull and temples; its crest is structural, not a horn.
			top = y0-1.55
			_helm_poly(hc,[[-h,-0.45],[-h-0.02,-2.68],[-h*0.85,-3.65],[-h*0.47,y0-1.38],
				[h*0.02,y0-1.55],[h*0.54,-3.87],[h-0.05,b-0.23],[h-0.12,b],
				[cut,b+0.02],[cut-0.21,-0.83]],m["base"],pat)
			_helm_rim(hc,h,b,m,0.24)
			cv.capsule(hc+Vector2(-0.35,y0-1.26),hc+Vector2(-0.69,b-0.29),0.21,m["dark"])
			cv.capsule(hc+Vector2(-0.46,y0-1.21),hc+Vector2(-0.79,b-0.28),0.10,m["light"])
		"pot":
			# A deep round kettle with an actual brim, distinct from the nasal and panelled domes.
			top = y0-1.49
			_helm_poly(hc,[[-h+0.15,b-0.46],[-h+0.24,-3.19],[-h*0.67,y0-1.20],
				[-h*0.17,y0-1.49],[h*0.42,y0-1.23],[h*0.84,-3.17],[h-0.1,b-0.46]],m["base"],pat)
			_helm_poly(hc,[[-h-0.58,b-0.27],[-h+0.11,b-0.73],[h-0.14,b-0.71],
				[h+0.65,b-0.21],[h+0.35,b+0.01],[-h-0.53,b+0.03]],m["dark"])
			cv.capsule(hc+Vector2(-h-0.28,b-0.22),hc+Vector2(h+0.33,b-0.23),0.12,m["light"])
			cv.capsule(hc+Vector2(-0.68,y0-1.30),hc+Vector2(-0.76,b-0.73),0.09,m["light"])
		_:
			top = y0-1.5
			_helm_poly(hc,[[-h,-0.4],[-h,-2.80],[-h*0.74,-3.78],[-0.18,y0-1.5],
				[h*0.51,-3.82],[h-0.05,b-0.20],[cut,b],[cut-0.2,-0.85]],m["base"],pat)
			_helm_rim(hc,h,b,m)
	_metal_end(m)
	if sp == "nasal": _helm_nasal(hc,b,m)
	if maker == "orc": OrcArt.helm_horns(self,hc,-3.05,m)
	elif maker == "moon_elf": ElfArt.helm_crescent(self,hc,top,m)
	_sparkle(hc+Vector2(x0+0.8,top+0.50),m)


# --- shield ---------------------------------------------------------------------------------------

func _shield() -> void:
	var sh := _it("shield")
	if sh.is_empty() or _lost("hand_l") or _lost("arm_lower_l") or _lost("arm_upper_l"):
		return
	var m := metal(sh.get("mat", "copper"), int(sh.get("q", 0)))
	var c: Vector2 = (j["hl"] as Vector2) + Vector2(1.0, 0.0)
	if pose == "dead":
		return
	var g := gs
	var p := prim
	var s := sec
	var cx := cv.map(c)
	match String(sh.get("sprite", "kite")):
		"kite":
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			for q in [Vector2(-2.6, -5.0), Vector2(2.6, -5.0), Vector2(3.0, -1.5), Vector2(0.0, 7.0), Vector2(-3.0, -1.5)]:
				outer.append(c + q * g)
				inner.append(c + q * g * 0.72 + Vector2(0, -0.3))
			cv.begin()
			cv.poly(outer, m["base"])
			cv.poly(inner, p, func(x: int, y: int, col: Color) -> Color:
				if absf(x + 0.5 - cx.x) < 0.6 * cv.k or absf(y + 0.5 - (cx.y - 1.5 * cv.k)) < 0.6 * cv.k:
					return s
				return col)
			cv.end(m["outline"], 0.14)
		"round":
			cv.begin()
			cv.ellipse(c, 3.6 * g, 4.6 * g, m["base"])
			cv.ellipse(c, 2.6 * g, 3.6 * g, p, func(x: int, y: int, col: Color) -> Color:
				return s if (x + 0.5 < cx.x) == (y + 0.5 < cx.y) else col)
			cv.ellipse(c, 1.1 * g, 1.1 * g, m["light"])
			cv.end(m["outline"], 0.14, m["shine"])
		"slab":
			var wood := WOOD
			cv.begin()
			cv.poly(PackedVector2Array([c + Vector2(-3.0, -5.0) * g, c + Vector2(2.5, -5.5) * g, c + Vector2(3.0, 5.5) * g,
				c + Vector2(-3.0, 5.0) * g]), wood, func(x: int, _y: int, col: Color) -> Color:
				return col.darkened(0.25) if (x - int(cx.x)) % maxi(2, int(2 * cv.k)) == 0 else col)
			cv.capsule(c + Vector2(-1.5, -1.5) * g, c + Vector2(1.5, 2.0) * g, 0.8, p)
			cv.rect(Rect2(c + Vector2(-3.0, -3.5) * g, Vector2(6.0, 1.0) * g), m["base"])
			cv.rect(Rect2(c + Vector2(-3.0, 3.0) * g, Vector2(6.0, 1.0) * g), m["base"])
			cv.end(ol(wood), 0.12)
		"buckler":
			cv.begin()
			cv.ellipse(c, 2.2 * g, 2.7 * g, m["base"])
			cv.ellipse(c, 1.5 * g, 1.9 * g, p)
			cv.ellipse(c, 0.8 * g, 0.9 * g, m["light"])
			cv.end(m["outline"], 0.14, m["shine"])
	_sparkle(c + Vector2(-1.0, -2.0), m)

# --- weapons --------------------------------------------------------------------------------------

var _g := Vector2.ZERO
var _d := Vector2.RIGHT
var _n := Vector2.UP

func _wp(u: float, v: float) -> Vector2:
	return _g + _d * u * gs + _n * v * gs

func _wpoly(arr: Array, c: Color, pat: Callable = Callable()) -> void:
	var pts := PackedVector2Array()
	for q in arr:
		pts.append(_wp(q[0], q[1]))
	cv.poly(pts, c, pat)

func _shaft(u0: float, u1: float, c: Color) -> void:
	cv.line1(_wp(u0, 0.0), _wp(u1, 0.0), c)

func _draw_weapon(grip: Vector2, dir: Vector2) -> void:
	if WeaponArt.draw(self, grip, dir): return
	var w := _it("weapon")
	if w.is_empty():
		return
	_g = grip
	_d = dir.normalized()
	_n = Vector2(_d.y, -_d.x)
	var m := metal(w.get("mat", "copper"), int(w.get("q", 0)))
	var mb: Color = m["base"]
	var ml: Color = m["light"]
	var trim: Color = m["trim"]
	var reach := float(w.get("reach", 100.0))
	cv.begin()
	match String(w.get("sprite", "sword")):
		"sword":
			cv.ellipse(_wp(-2.2, 0.0), 0.8, 0.8, trim)
			_shaft(-1.5, 0.5, LEATHER)
			cv.capsule(_wp(1.0, -2.0), _wp(1.0, 2.0), 0.5, trim)
			_wpoly([[1.5, -0.9], [10.0, -0.9], [11.6, 0.0], [10.0, 0.9], [1.5, 0.9]], mb)
			cv.line1(_wp(2.0, 0.0), _wp(9.5, 0.0), ml)
		"sabre":
			cv.ellipse(_wp(-2.0, 0.0), 0.7, 0.7, trim)
			_shaft(-1.5, 0.5, LEATHER)
			cv.capsule(_wp(1.0, -1.6), _wp(1.0, 1.6), 0.45, trim)
			cv.line1(_wp(1.0, 1.6), _wp(-1.6, 1.4), trim)
			var arr := []
			var back := []
			for i in 6:
				var u := 1.5 + i * 1.9
				var bend := 0.035 * pow(u - 1.5, 2.0)
				arr.append([u, -0.9 + bend])
				back.push_front([u, 0.9 + bend * 1.05])
			arr.append([12.4, 0.7 + 0.035 * pow(10.9, 2.0)])
			_wpoly(arr + back, mb)
		"knife":
			_shaft(-1.5, 0.5, LEATHER)
			cv.capsule(_wp(0.8, -1.2), _wp(0.8, 1.2), 0.45, mb)
			_wpoly([[1.2, -0.8], [4.5, -0.8], [6.0, 0.3], [1.2, 0.8]], mb)
			cv.dot(_wp(3.0, -0.2), ml)
		"axe":
			cv.capsule(_wp(-2.0, 0.0), _wp(8.5, 0.0), 0.55, WOOD)
			_wpoly([[5.2, 0.5], [8.2, 0.5], [8.6, -1.5], [8.4, -4.2], [6.8, -3.6], [5.8, -1.0]], mb)
			cv.line1(_wp(8.4, -1.0), _wp(8.3, -3.8), ml)
		"greataxe":
			cv.capsule(_wp(-6.0, 0.0), _wp(12.5, 0.0), 0.6, WOOD)
			_wpoly([[8.0, 0.6], [12.0, 0.6], [13.4, -2.0], [13.0, -6.2], [11.0, -5.2], [9.6, -3.0], [8.4, -1.5]], mb)
			_wpoly([[9.0, 0.5], [11.0, 0.5], [10.5, 2.2]], mb)
			cv.line1(_wp(13.1, -1.6), _wp(12.8, -5.6), ml)
		"mace":
			cv.capsule(_wp(-1.5, 0.0), _wp(6.5, 0.0), 0.55, WOOD.darkened(0.15))
			cv.ellipse(_wp(7.6, 0.0), 1.6, 1.6, mb)
			_wpoly([[6.5, -2.4], [8.8, -2.4], [8.8, 2.4], [6.5, 2.4]], mb, func(x: int, y: int, c: Color) -> Color:
				return ml if (x + y) % 2 == 0 else c)
			cv.dot(_wp(9.4, -0.5), trim)
		"club":
			_wpoly([[-1.5, -0.7], [-1.5, 0.7], [7.0, 1.7], [9.2, 0.6], [9.2, -0.6], [7.0, -1.7]], WOOD.lightened(0.05))
			for q in [[5.5, -2.2], [7.5, 2.3], [8.4, -2.2], [9.8, 0.0], [6.5, 0.0]]:
				cv.dot(_wp(q[0], q[1]), ml)
		"maul":
			cv.capsule(_wp(-5.0, 0.0), _wp(9.5, 0.0), 0.6, WOOD)
			_wpoly([[8.5, -3.0], [12.5, -3.0], [12.5, 3.0], [8.5, 3.0]], mb, func(x: int, y: int, c: Color) -> Color:
				return c.darkened(0.2) if (x + y) % 3 == 0 else c)
			cv.dot(_wp(12.0, 2.0), ml)
		"cleaver":
			_shaft(-1.8, 1.0, WOOD.darkened(0.2))
			_wpoly([[0.8, 0.8], [7.4, 0.8], [7.4, -3.4], [6.6, -3.9], [0.8, -2.6]], mb)
			cv.line1(_wp(1.4, -3.0), _wp(7.0, -3.6), ml)
			cv.dot(_wp(6.6, 0.0), m["dark"])
		"sickle":
			_shaft(-1.8, 1.2, WOOD)
			var pts := [Vector2(1.2, 0.0), Vector2(4.0, -0.4), Vector2(5.8, -1.8), Vector2(6.0, -3.6), Vector2(5.0, -5.0), Vector2(3.4, -5.4)]
			for i in pts.size() - 1:
				cv.capsule(_wp(pts[i].x, pts[i].y), _wp(pts[i + 1].x, pts[i + 1].y), 0.65, mb)
			cv.dot(_wp(5.6, -2.6), ml)
		"spear":
			var L := 13.0 * clampf(reach / 200.0, 0.7, 1.2)
			_shaft(-6.0, L, WOOD)
			_wpoly([[L - 0.5, 0.0], [L + 1.0, -1.4], [L + 4.0, 0.0], [L + 1.0, 1.4]], mb)
			if reach > 205.0:
				cv.capsule(_wp(L - 0.3, -1.8), _wp(L - 0.3, 1.8), 0.45, mb)
			cv.line1(_wp(L + 0.5, 0.0), _wp(L + 3.0, 0.0), ml)
		"glaive":
			var L := 12.0
			_shaft(-8.0, L, WOOD)
			_wpoly([[L - 1.0, 0.8], [L - 1.0, -0.9], [L + 3.5, -1.9], [L + 6.0, -0.4], [L + 3.0, 0.9]], mb)
			_wpoly([[L - 0.5, 0.6], [L + 0.5, 0.6], [L - 0.5, 2.2]], mb)
			cv.line1(_wp(L, -1.0), _wp(L + 4.0, -1.4), ml)
			cv.dot(_wp(L - 1.5, 0.0), trim)
		"bow", "longbow", "recurve":   # bows: the stave along wdir (up), limbs bending back toward the archer
			var L: float = BOW_SPRITES[String(w.get("sprite", "bow"))]
			var half := L * 0.5
			var drawn := pose == "prepare" or (pose == "strike" and t < 0.2)
			var bend := 2.2 if drawn else 1.2
			var recurve := String(w.get("sprite", "")) == "recurve"
			var pts := []
			for i in 9:
				var u := -half + L * i / 8.0
				var q := u / half
				var v := bend * q * q
				if recurve and absf(q) > 0.75:
					v -= (absf(q) - 0.75) * 4.0   # the tips curl forward
				pts.append(_wp(u, v))
			var wood := WOOD.darkened(0.1) if not recurve else Color("#5a3a20")
			for i in pts.size() - 1:
				cv.capsule(pts[i], pts[i + 1], 0.55, wood)
			if recurve:
				cv.dot(_wp(-half, bend), Color("#e8dcc0"))   # horn nocks
				cv.dot(_wp(half, bend), Color("#e8dcc0"))
			cv.capsule(_wp(-1.0, 0.0), _wp(1.0, 0.0), 0.7, LEATHER)   # the grip
			# the string: to the draw hand while drawing, else straight between the tips
			var nock: Vector2 = j.get("hl", _wp(0.0, bend)) if drawn else (pts[0] + pts[8]) * 0.5
			cv.line1(pts[0], nock, Color("#e8e2cf"))
			cv.line1(nock, pts[8], Color("#e8e2cf"))
			if drawn:   # the arrow on the string, over the grip
				var fw: Vector2 = (_g - nock).normalized()
				cv.line1(nock, _g + fw * 2.5, WOOD.lightened(0.2))
				cv.dot(_g + fw * 3.0, Color("#c87533"))
		_:
			_shaft(-1.0, 8.0, mb)
	_metal_end(m)
	if int(w.get("q", 0)) >= 4:
		cv.dot(_wp(4.0, 0.0), Color.WHITE)

# --- wounds ---------------------------------------------------------------------------------------

func _part_spot(pid: String) -> Array:
	var hc: Vector2 = j["hc"]
	var sc: Vector2 = j["sc"]
	var hip: Vector2 = j["hip"]
	match pid:
		"head", "eye_l", "eye_r":
			return [hc, head_h * 0.35 * (DwarfArt.HEAD_SCALE if String(spec.get("race","")) == "dwarf" else 1.0)]
		"neck":
			var k: float = DwarfArt.HEAD_SCALE if String(spec.get("race","")) == "dwarf" else 1.0
			return [hc + (sc + Vector2(0.5, -0.5) - hc) * k, k]
		"torso_upper":
			return [sc + Vector2(0.5, torso_len * 0.3), tw * 0.32]
		"torso_lower":
			return [hip + Vector2(0, -torso_len * 0.25), hipw * 0.32]
		"arm_upper_r":
			return [(j["sr"] as Vector2).lerp(j["er"], 0.5), arm_r + 0.5]
		"arm_lower_r":
			return [(j["er"] as Vector2).lerp(j["hr"], 0.5), arm_r + 0.5]
		"hand_r":
			return [j["hr"], 0.8]
		"arm_upper_l":
			return [(j["sl"] as Vector2).lerp(j["el"], 0.5), arm_r + 0.5]
		"arm_lower_l":
			return [(j["el"] as Vector2).lerp(j["hl"], 0.5), arm_r + 0.5]
		"hand_l":
			return [j["hl"], 0.8]
		"leg_upper_r":
			return [(j["pr"] as Vector2).lerp(j["kr"], 0.5), leg_r + 0.5]
		"leg_lower_r":
			return [(j["kr"] as Vector2).lerp(j["fr"], 0.5), leg_r + 0.5]
		"foot_r":
			return [j["fr"], 1.0]
		"leg_upper_l":
			return [(j["pl"] as Vector2).lerp(j["kl"], 0.5), leg_r + 0.5]
		"leg_lower_l":
			return [(j["kl"] as Vector2).lerp(j["fl"], 0.5), leg_r + 0.5]
		"foot_l":
			return [j["fl"], 1.0]
	# v0.013 anatomy parts: shown on the nearest drawn part (inner organs on the torso)
	var side := "r" if pid.ends_with("_r") else "l"
	if pid.begins_with("finger"):
		return _part_spot("hand_" + side)
	if pid.begins_with("toe"):
		return _part_spot("foot_" + side)
	if pid in ["throat", "spine_upper"]:
		return _part_spot("neck")
	if pid.begins_with("ear") or pid.begins_with("cheek") or pid.begins_with("lip") or pid.begins_with("eyelid") \
			or pid.begins_with("tooth") or pid in ["nose", "mouth", "tongue", "skull", "brain", "jaw"]:
		return _part_spot("head")
	if pid.begins_with("rib") or pid.begins_with("lung") or pid in ["heart", "spine_middle"]:
		return _part_spot("torso_upper")
	if pid in ["liver", "stomach", "guts", "spleen", "pancreas", "spine_lower"] or pid.begins_with("kidney"):
		return _part_spot("torso_lower")
	return []

## v0.014: wound marks by kind, on the hit part. Bruises purple, cuts a red gash with a drip, broken bone a white
## splinter in red, mangled a dark mess with bone. Reduced gore: bruise and a small red mark only.
func _wounds() -> void:
	var dmg: Dictionary = spec.get("dmg", {})
	var bleed: Dictionary = spec.get("bleed", {})
	if dmg.is_empty():
		return
	var wk: Dictionary = spec.get("wk", {})
	var full := int(spec.get("gore", 1)) == 1
	var rng := RandomNumberGenerator.new()
	for pid in dmg:
		var spot := _part_spot(pid)
		if spot.is_empty():
			continue
		rng.seed = int(spec.get("seed", 0)) * 31 + hash(pid)
		var c: Vector2 = spot[0]
		var r: float = spot[1]
		var d: float = dmg[pid]
		var kind := String(wk.get(pid, "c"))
		if kind == "b":
			for i in 1 + int(d * 4.0 * cv.k):
				var pb := cv.map(c + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)))
				cv.stain_px(int(pb.x), int(pb.y), BRUISE if i % 3 else BRUISE.darkened(0.3))
			continue
		var n := 1 + int(d * (6.0 if full else 2.0) * cv.k)
		for i in n:
			var p := cv.map(c + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)))
			cv.stain_px(int(p.x), int(p.y), BLOOD if d < 0.7 or i % 2 else BLOOD_DARK)
		if not full:
			continue
		if kind == "c":   # a gash across the part
			var g0 := cv.map(c + Vector2(-r * 0.7, -r * 0.5))
			var g1 := cv.map(c + Vector2(r * 0.7, r * 0.5))
			var steps := maxi(2, int(g0.distance_to(g1)))
			for i in steps + 1:
				var q := g0.lerp(g1, float(i) / float(steps))
				cv.stain_px(int(q.x), int(q.y), BLOOD_DARK if i % 2 else BLOOD)
		elif kind == "f" or kind == "m":   # broken bone showing white through the wound
			var pc := cv.map(c)
			if kind == "m":
				for i in 3 + int(d * 4.0):
					var pm := cv.map(c + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)))
					cv.stain_px(int(pm.x), int(pm.y), BLOOD_DARK)
			cv.stain_px(int(pc.x), int(pc.y), BONE_WHITE)
			cv.stain_px(int(pc.x) + 1, int(pc.y) - 1, BONE_WHITE)
		if bleed.has(pid) and pose != "dead":
			var p0 := cv.map(c)
			for i in int(1 + d * 3.0):
				cv.stain_px(int(p0.x), int(p0.y) + i, BLOOD)

# --- severed pieces -----------------------------------------------------------------------------

## A lost body part lying on the ground (head keeps hair and helm), PIECE x PIECE logical px,
## centred. Unknown parts give a small blood splat.
const PIECE := 24

static func render_piece(sp: Dictionary, pid: String) -> Image:
	if CreaturePainter.is_creature_spec(sp):
		return CreaturePainter.render_piece(sp, pid)
	return FigurePainter.new(sp).paint_piece(pid).to_image()

func paint_piece(pid: String) -> PixelCanvas:
	pose = "idle"
	t = 0.0
	var raster := raster_scale(String(spec.get("race", "human")))
	cv = PixelCanvas.new(int(PIECE * raster), int(PIECE * raster))
	_rig()
	var side := "r" if pid.ends_with("_r") else "l"
	var pts: Array = []
	var leg := pid.begins_with("leg_") or pid.begins_with("foot_")
	if pid == "head":
		var hc: Vector2 = j["hc"]
		cv.set_frame((Vector2(PIECE * 0.5, PIECE * 0.5) - hc) * raster, raster, 0.0)
		_splat(2.5)
		_head()
		cv.dot(hc + Vector2(0.0, head_h * 0.5 - 1.0), BLOOD)
		return cv
	if pid.begins_with("arm_upper"):
		pts = [j["s" + side], j["e" + side], j["h" + side]]
	elif pid.begins_with("arm_lower"):
		pts = [j["e" + side], j["h" + side]]
	elif pid.begins_with("hand"):
		pts = [j["h" + side]]
	elif pid.begins_with("leg_upper"):
		pts = [j["p" + side], j["k" + side], j["f" + side]]
	elif pid.begins_with("leg_lower"):
		pts = [j["k" + side], j["f" + side]]
	elif pid.begins_with("foot"):
		pts = [j["f" + side]]
	var mid := Vector2.ZERO
	for q in pts:
		mid += q
	mid = mid / maxf(1.0, pts.size())
	# lay limbs flat on the ground: rotate arms/legs a quarter turn
	var rot := 0.0 if pts.size() <= 1 else PI * 0.5
	cv.set_frame(Vector2(PIECE * 0.5, PIECE * 0.5) * raster, raster, rot)
	cv.xf = cv.xf * Transform2D(0.0, -mid)
	_splat(2.0)
	if pts.is_empty():
		return cv
	var r := leg_r if leg else arm_r
	var col := skin
	if leg and not _it("legs_under").is_empty():
		col = _trouser_col()
	cv.begin()
	for i in pts.size() - 1:
		cv.capsule(pts[i], pts[i + 1], r, col)
	var tip: Vector2 = pts[pts.size() - 1]
	if leg:
		cv.rect(Rect2(tip + Vector2(-1.2, -0.5), Vector2(3.4 * gs, 2.0)), Color("#4a3020") if not _it("feet").is_empty() else skin)
	else:
		cv.ellipse(tip, arm_r + 0.25, arm_r + 0.25, skin)
	cv.end(ol(col), 0.12)
	cv.dot(pts[0], BLOOD)
	return cv

## Blood under the piece, in image space (independent of the piece's rotation).
func _splat(r: float) -> void:
	var keep := cv.xf
	var kk := cv.k
	cv.set_frame(Vector2.ZERO, raster_scale(String(spec.get("race", "human"))))
	cv.begin()
	cv.ellipse(Vector2(PIECE * 0.5, PIECE * 0.5 + 2.0), r + 2.0, r * 0.7, BLOOD_DARK.lerp(BLOOD, 0.4))
	cv.end(Color(0, 0, 0, 0), 0.0)
	cv.xf = keep
	cv.k = kk

# --- portrait -------------------------------------------------------------------------------------

func paint_bust() -> PixelCanvas:
	pose = "idle"
	t = 0.0
	var bust := bust_size(String(spec.get("race", "human")))
	cv = PixelCanvas.new(bust, bust)
	_rig()
	var bust_factor := float(bust) / BUST
	var hscale := HumanArt.HEAD_SCALE * 1.15 if _human() else 1.0
	var k := 18.0 / (head_h * hscale) * bust_factor
	var hc: Vector2 = j["hc"]
	# arms hang straight down at the sides (no weapon or shield in the portrait)
	var A := arm_a + arm_b
	var sc: Vector2 = j["sc"]
	j["sr"] = sc + Vector2(-tw * 0.5 + (1.1 if _human() else 0.2), 1.0)
	j["sl"] = sc + Vector2(tw * 0.5 - (1.1 if _human() else 0.2), 1.0)
	j["hr"] = (j["sr"] as Vector2) + Vector2(-0.4, A * 0.95)
	j["er"] = _ik(j["sr"], j["hr"], arm_a, arm_b, 1.0)
	j["hl"] = (j["sl"] as Vector2) + Vector2(0.4, A * 0.95)
	j["el"] = _ik(j["sl"], j["hl"], arm_a, arm_b, -1.0 if _human() else 1.0)
	# head centre lands at (20, 18) in the portrait
	cv.set_frame(Vector2(20.0, 17.5 if _human() else 18.5) * bust_factor - Vector2(hc.x - 0.5, hc.y) * k, k, 0.0)
	_draw_figure(false)
	return cv
