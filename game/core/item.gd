class_name Item
extends RefCounted
## One concrete item: a template (weapon or armor id), a material and a quality level 0-5.

var uid: int = 0
var tid: String = ""
var material: String = "copper"
var quality: int = 0
var wear: int = 0  # 0 fine, 1 worn, 2 threadbare/battered, 3 tattered (repairable in town)
var vr: float = 1.0  # bows: item variance (+-5%, rolled once at making by the bowyer's skill; efficiency x vr)
## v0.014 gear damage (sim/battle_sim.gd _gear_*; Douglas 22:52-22:58). A bend or a dent is bent back but costs the
## item quality steps (Item.quality drops at once); chips dull the edge (dull 0..1: edge x (1 - 0.5 dull) in battle;
## each full 1.0 of chipping is ground away for one quality step). Snapped, cracked, split or shattered = broken:
## scrap of its metal at the battle's end (core/loot.gd strip_broken / spoils).
var dull: float = 0.0
var broken: bool = false
## arms trade (docs/specs/arms-trade.md): the maker's mark. {"n": maker (the business), "b": business id, "t": town id,
## "tn": town name, "r": race of the makers}; empty = maker unknown (older saves). Style = the template's culture.
var mark: Dictionary = {}
## v0.014 legendary pieces (quality DB.LEGEND; campaign/legends.gd): {"nm": its own name, "gem": gem good id, "at": where
## the gem is set ("pommel" ...), "by": maker's name, "bt": maker's town name, "d": day made, "k": kills,
## "kl": [victim names, newest last], "cu": uid of the carrier last logged, "h": [[day, text], ...] every change of
## hands, oldest first}. Empty for every other item.
var legend: Dictionary = {}

static var _next_uid: int = 1

static func make(template_id: String, mat: String = "", q: int = 0) -> Item:
	var it := Item.new()
	it.uid = _next_uid
	_next_uid += 1
	it.tid = template_id
	var t := it.tmpl()
	if mat == "":
		var mats: Array = t.get("materials", ["copper"])
		mat = mats[0]
	it.material = mat
	it.quality = clampi(q, 0, DB.LEGEND)
	return it

## A legendary piece (v0.014): never destroyed, never lost to the loot roll.
func is_legend() -> bool:
	return quality >= DB.LEGEND

func tmpl() -> Dictionary:
	return DB.template(tid)

func is_weapon() -> bool:
	return DB.is_weapon(tid)

func slot() -> String:
	if is_weapon():
		return "main_hand"
	var s: String = tmpl().get("slot", "")
	return "off_hand" if s == "shield" else s

func mat() -> Dictionary:
	return DB.materials.get(material, {})

## Mass in kg. Weapons: metal head + wooden haft. Armor: volume * density.
func mass() -> float:
	var t := tmpl()
	var dens: float = mat().get("density", 1000)
	if is_weapon():
		return float(t.get("head_cm3", 0)) * dens / 1.0e6 + float(t.get("haft_kg", 0.0))
	return float(t.get("cm3", 0)) * dens / 1.0e6

func display_name() -> String:
	var t := tmpl()
	var base := "%s %s" % [material, t.get("name", tid)]
	if t.get("plain_name", false):   # bows: "longbow", not "wood longbow"
		base = String(t.get("name", tid))
	if is_legend():   # "Oathbreaker, legendary copper sword"
		return "%s, legendary %s" % [String(legend.get("nm", "Nameless")), base]
	var m: Array = DB.QUALITY_MARKS[quality]
	return "%s%s%s" % [m[0], base, m[1]]

## v0.014: where a legendary piece's gem sits, by the shape of the thing (shared with the icon, art/item_icon.gd).
static func gem_spot(tid: String) -> String:
	if DB.is_bow(tid):
		return "grip"
	var t := DB.template(tid)
	if DB.is_weapon(tid):
		match String(t.get("skill", "")):
			"sword", "dagger": return "pommel"
			"axe", "polearm": return "socket"
			"spear": return "socket"
			"mace", "hammer": return "head"
		return "pommel"
	match String(t.get("slot", "")):
		"shield": return "boss"
		"helm": return "brow"
		"body", "clothing": return "breast clasp"
		"legs", "legs_under": return "knee"
		"hands": return "cuff"
		"feet": return "buckle"
	return "clasp"

## The gem's name ("ruby"); "" for an ordinary piece.
func gem_name() -> String:
	if not is_legend():
		return ""
	var g := String(legend.get("gem", ""))
	return String(GEM_NAMES.get(g, g.replace("_", " ")))

static func _a(w: String) -> String:
	return ("an " if w.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + w

## v0.014 gem goods (data/economy.json goods; mined from gem pockets in any ore mine: campaign/legends.gd).
const GEM_NAMES := {"quartz": "rock crystal", "amethyst": "amethyst", "garnet": "garnet", "topaz": "topaz",
	"sapphire": "sapphire", "ruby": "ruby", "emerald": "emerald"}

## A legendary piece's account: the gem, the maker, every carrier, the kills (for the records and the unit card).
## Empty for an ordinary piece.
func legend_lines() -> Array:
	if not is_legend():
		return []
	var out := []
	out.append("%s. %s is set in its %s." % [display_name(), _a(gem_name()).capitalize().substr(0, 1) + _a(gem_name()).substr(1), String(legend.get("at", "pommel"))])
	out.append("Made by %s of %s%s." % [String(legend.get("by", "an unknown smith")), String(legend.get("bt", "?")),
		(", day %d" % int(legend["d"])) if legend.has("d") else ""])
	var kl: Array = legend.get("kl", [])
	out.append("Kills: %d%s" % [int(legend.get("k", 0)), (" (latest: %s)" % ", ".join(PackedStringArray(kl.slice(maxi(0, kl.size() - 5))))) if not kl.is_empty() else ""])
	for h in legend.get("h", []):
		out.append("Day %d: %s" % [int(h[0]), String(h[1])])
	return out

## Coinage (v0.010): prices are counted in bronze coins, 20 to the old gold piece (100 coins = a labourer's day).
const COIN := 20
## v0.014: a legendary piece is worth LEGEND_VALUE x the same piece at masterwork, plus its gem (a fortune) [ours].
const LEGEND_VALUE := 20.0
const GEM_PRICES := {"quartz": 150.0, "amethyst": 400.0, "garnet": 600.0, "topaz": 900.0, "sapphire": 3000.0, "ruby": 3500.0, "emerald": 3200.0}

## Base price in coins (tuned): material value * mass, times 1.6^quality (handoff sketch), x COIN.
func value() -> int:
	var tv := tmpl()
	var q := mini(quality, 5)
	var lm := LEGEND_VALUE if is_legend() else 1.0
	var gem := float(GEM_PRICES.get(String(legend.get("gem", "")), 0.0)) if is_legend() else 0.0
	if tv.has("value"):   # bows: a bow is worth its making, not its wood
		return int(round(float(tv["value"]) * vr * pow(1.6, q) * COIN * lm + gem))
	var v: float = float(mat().get("value", 1)) * maxf(mass(), 0.2) * 6.0 + 4.0
	return int(round(v * pow(1.6, q) * COIN * lm + gem))

func to_dict() -> Dictionary:
	var d := {"uid": uid, "tid": tid, "mat": material, "q": quality, "wear": wear}
	if not legend.is_empty():
		d["lg"] = legend.duplicate(true)   # v0.014: a legendary piece's name, gem and history
	if vr != 1.0:
		d["vr"] = vr   # bows
	if dull > 0.0:
		d["dull"] = dull   # v0.014 gear damage
	if broken:
		d["brk"] = true
	if not mark.is_empty():
		d["mk"] = mark.duplicate()   # arms trade: the maker's mark
	return d

static func from_dict(d: Dictionary) -> Item:
	var it := Item.new()
	it.uid = int(d.get("uid", 0))
	it.tid = d.get("tid", "")
	it.material = d.get("mat", "copper")
	it.quality = int(d.get("q", 0))
	it.wear = int(d.get("wear", 0))
	it.vr = float(d.get("vr", 1.0))   # bows
	var lg = d.get("lg", {})
	if lg is Dictionary:
		it.legend = (lg as Dictionary).duplicate(true)
	it.dull = float(d.get("dull", 0.0))   # v0.014 gear damage
	it.broken = bool(d.get("brk", false))
	var mk = d.get("mk", {})   # arms trade: the maker's mark (older saves: maker unknown)
	if mk is Dictionary:
		it.mark = (mk as Dictionary).duplicate()
		if it.mark.has("b"):
			it.mark["b"] = int(it.mark["b"])
	_next_uid = maxi(_next_uid, it.uid + 1)
	return it

## arms trade: "made by Aldric's forge of Ashford (human work)"; "maker unknown (northern style)" without a mark.
func maker_text() -> String:
	var style := String(tmpl().get("culture", "")).replace("_", " ")
	if mark.is_empty() or String(mark.get("t", "")) == "":
		return "maker unknown" + (" (%s style)" % style if style != "" and style != "common" else "")
	var who := String(mark.get("n", ""))
	var town := String(mark.get("tn", mark.get("t", "")))
	var race := String(mark.get("r", ""))
	var rn := String(DB.races.get(race, {}).get("name", race.replace("_", " ")))
	var s := ("made by %s of %s" % [who, town]) if who != "" else "made in %s" % town
	return s + (" (%s work)" % rn if rn != "" else "")

## arms trade: race of the makers ("" when unknown).
func maker_race() -> String:
	return String(mark.get("r", ""))
