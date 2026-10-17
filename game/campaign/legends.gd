class_name Legends
extends RefCounted
## Legendary pieces and gems (v0.014, docs/specs/next/03-legendary-items.md; Douglas 2026-10-06 22:31-23:00).
##
## MAKING. A real smith's roll (Factory.roll_quality(..., can_legend = true): a masterwork roll, 1 time in 25) is
##   legendary only through forge(): the maker must be a real person of the forge (its keeper or a hand on its
##   staff, Persons records) who has made fewer than CAP (5) in his life (person field Persons.LEG), and a real gem
##   must be set in it: the dearest stone on the town's market (the forge's till pays the market), else one a family
##   of the town holds (bought from its purse at the market price). No maker or no stone: the piece stays masterwork
##   (Douglas: no stand-in gems). Each gets a unique name ("Oathbreaker, legendary copper sword"), its gem's spot
##   (Item.gem_spot), and its history starts with the maker. The maker's life history and the town's history note it.
##   Generic rolls (militia kit, pre-history stock, stand-in towns, the outlaws' first hoard) never make one, and the
##   player cannot order one (there are no commissions; the head's orders choose only the kind of piece).
## NEVER LOST. When a carrier falls the winning side always takes it (Loot.spoils keeps it without a roll; cloth
##   and leather legendaries are not rags): an AI winner puts it on its best fitting fighter (best_fighter, the
##   same code for every AI force: bands, militia, outlaws); the piece he wore goes the normal way. Beasts take
##   nothing: the people of the nearest town pick it up off the field. It is never scrapped, sold off as a hoard,
##   broken up for study or lost with a caravan's wagons. Every change of hands goes in its history (Item.legend.h);
##   a town whose man lost one remembers it (town history and e.legends_lost).
## GEMS. Real goods (data/economy.json goods quartz .. emerald). No gem mines: every basket of ore dug has a
##   gem_pockets.chance of hitting a pocket (one stone; which stone follows the rock: mine_gem). Families keep
##   stones as stored wealth (f.gems, counted in e.gh) bought from their 'rest' budget (Families._restock); a family
##   that cannot buy food sells its stones before it pawns anything (sell_gems, the coping ladder).

const CAP := 5          # Douglas: at most 5 legendary pieces in a smith's life
const HIST_MAX := 120   # lines of a piece's history kept (the making line always stays)
const KILLS_KEPT := 10  # victims' names kept (the count is whole)
const GEMS := ["quartz", "amethyst", "garnet", "topaz", "sapphire", "ruby", "emerald"]

const NAME_A := ["Oath", "Storm", "Grief", "Dawn", "Blood", "Ember", "Frost", "Thunder", "Raven", "Wolf", "Iron", "Star",
	"Night", "Doom", "Sorrow", "Bright", "Grave", "Dragon", "Ash", "Stone", "Red", "Gold", "Wyrm", "Sky", "Shadow"]
const NAME_B_WEAPON := ["breaker", "bane", "fang", "song", "bite", "reaver", "cleaver", "tooth", "thorn", "brand", "fall",
	"wrath", "bringer", "edge", "keeper", "hunger", "call"]
const NAME_B_ARMOR := ["ward", "guard", "shell", "hide", "mantle", "wall", "aegis", "bulwark", "veil", "skin", "keep",
	"heart", "shroud", "crown"]

static func G() -> Dictionary:
	return TownEcon.data().get("gem_pockets", {})

static func is_gem(g: String) -> bool:
	return GEMS.has(g)

# ================================================================== gems
## Which stone a pocket in this mine holds: the base weights, times the hilly (metamorphic) and the ore's own rock.
static func mine_gem(e: Dictionary, ore: String, rng: RandomNumberGenerator) -> String:
	var C := G()
	var wts: Dictionary = C.get("weights", {})
	var hilly := int(e.get("terrain", {}).get("hill_cells", 0)) >= 6
	var by_ore: Dictionary = C.get("ore", {}).get(ore, {})
	var tot := 0.0
	var ws := []
	for g in GEMS:
		var wt := float(wts.get(g, 0.0))
		if hilly:
			wt *= float(C.get("hilly", {}).get(g, 1.0))
		wt *= float(by_ore.get(g, 1.0))
		ws.append(wt)
		tot += wt
	var r := rng.randf() * tot
	for i in GEMS.size():
		r -= float(ws[i])
		if r <= 0.0:
			return GEMS[i]
	return GEMS[0]

## A mine dug n baskets today: the chance that one of them broke into a gem pocket (one draw a mine-day: 1 - (1 -
## chance)^n, the chance of at least one; two pockets on one day are left out, under 0.1% at the default). The stone
## goes to the market like the ore (the market pays what its till holds at the buying share). Returns the gem or "".
static func mine_day(e: Dictionary, b: Dictionary, ore: String, n: int, mkt: Dictionary, share: float, rng: RandomNumberGenerator) -> String:
	if n <= 0:
		return ""
	var c := float(G().get("chance", 0.0))
	if c <= 0.0 or rng.randf() >= 1.0 - pow(1.0 - c, n):
		return ""
	var g := mine_gem(e, ore, rng)
	var st: Dictionary = e["stock"]
	st[g] = int(st.get(g, 0)) + 1
	TownEcon.led(e, "made", g, 1)
	var p := minf(float(e["price"].get(g, Item.GEM_PRICES.get(g, 0.0))) * share, maxf(0.0, float(mkt["till"])))
	mkt["till"] = float(mkt["till"]) - p
	b["till"] = float(b["till"]) + p
	mkt["spend"] = float(mkt["spend"]) + p
	b["gems"] = int(b.get("gems", 0)) + 1
	return g

## The stones a family keeps (f.gems {gem: n}); e.gh mirrors the town's total for the goods count (TownEcon.town_total).
static func fam_gems(f: Dictionary) -> Dictionary:
	if not f.has("gems"):
		f["gems"] = {}
	return f["gems"]

static func add_fam_gem(e: Dictionary, f: Dictionary, g: String, n: int) -> void:
	var fg := fam_gems(f)
	fg[g] = int(fg.get(g, 0)) + n
	if int(fg[g]) <= 0:
		fg.erase(g)
	if not e.has("gh"):
		e["gh"] = {}
	e["gh"][g] = int(e["gh"].get(g, 0)) + n
	if int(e["gh"][g]) <= 0:
		e["gh"].erase(g)

## Families._restock ("the rest"): the stone a family of class c orders when its want for one has built up (per_year
## stones a year: none for the poor), the rich the dearest stone on the market, the middling the cheapest. [f, g, 1,
## "keep", 0.0] on the batch (TownEcon fills it into f.gems); returns the order's cost, 0 when none.
static func want_order(e: Dictionary, f: Dictionary, c: int, days: float, b: Array) -> float:
	var py: Array = G().get("per_year", [0.0, 0.0, 0.0])
	var rate := float(py[clampi(c, 0, py.size() - 1)]) if not py.is_empty() else 0.0
	if rate <= 0.0:
		return 0.0
	var w: Dictionary = f["wear"]
	var v := minf(float(w.get("gems", 0.0)) + rate * days / People.year_days(), 2.0)
	w["gems"] = v
	if v < 1.0:
		return 0.0
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var pick := ""
	for g in GEMS:
		if int(st.get(g, 0)) <= 0 or not price.has(g):
			continue
		if pick == "" or (c >= 2 and float(price[g]) > float(price[pick])) or (c < 2 and float(price[g]) < float(price[pick])):
			pick = g
	if pick == "":
		return 0.0
	w["gems"] = v - 1.0
	b.append([f, pick, 1, "keep", 0.0])
	return float(price[pick])

## The coping ladder's first rung (Douglas 23:00: "they will sell them if they need food"): a family short of coin
## or hungry sells its stones to the market (cheapest first) at sell_share of the price, the market paying what
## its till holds, until its purse reaches min_purse plus a week's food. Returns coins raised.
static func sell_gems(e: Dictionary, f: Dictionary, day: float) -> float:
	var fg: Dictionary = f.get("gems", {})
	if fg.is_empty():
		return 0.0
	var price: Dictionary = e["price"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var share := float(G().get("sell_share", 0.8))
	var ppl := float(Families.people(f))
	var target := float(TownEcon.data()["family"]["min_purse"]) + ppl * 2.0 * 7.0 * float(price.get("grain", 3.6))
	var order: Array = fg.keys()
	order.sort_custom(func(x, y): return float(price.get(x, 0.0)) < float(price.get(y, 0.0)))
	var got := 0.0
	var sold := []
	for g in order:
		while int(fg.get(g, 0)) > 0 and float(f["purse"]) < target:
			var p := float(price.get(g, Item.GEM_PRICES.get(g, 0.0))) * share
			if p <= 0.0 or float(mkt["till"]) < p:
				break
			add_fam_gem(e, f, g, -1)
			e["stock"][g] = int(e["stock"].get(g, 0)) + 1
			mkt["till"] = float(mkt["till"]) - p
			f["purse"] = float(f["purse"]) + p
			got += p
			sold.append(g)
	if got > 0.0:
		f["gems_sold"] = float(f.get("gems_sold", 0.0)) + got
		Families.add_hist(f, "Sold %s for %d coins to buy food." % [TownEcon.n_of(sold.size(), "stones") if sold.size() > 1 else "a " + String(Item.GEM_NAMES.get(sold[0], sold[0])), int(got)], day)
	return got

## A stone for a legendary piece: the dearest on the market (the forge's till pays the market's price), else one a
## family of the town keeps (the forge pays the family). "" when the town has none or the till cannot pay.
static func take_gem(e: Dictionary, b: Dictionary) -> String:
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var pick := ""
	for g in GEMS:
		if int(st.get(g, 0)) > 0 and (pick == "" or float(price.get(g, 0.0)) > float(price.get(pick, 0.0))):
			pick = g
	if pick != "":
		var p := float(price.get(pick, 0.0))
		if float(b["till"]) < p:
			return ""
		st[pick] = int(st[pick]) - 1
		TownEcon.led(e, "used", pick, 1)
		b["till"] = float(b["till"]) - p
		mkt["till"] = float(mkt["till"]) + p
		return pick
	var bestf: Dictionary = {}
	var bg := ""
	for f in e["fams"]:
		if f.get("gone", false) or (f.get("gems", {}) as Dictionary).is_empty():
			continue
		for g in f["gems"]:
			if bg == "" or float(price.get(g, 0.0)) > float(price.get(bg, 0.0)):
				bg = g
				bestf = f
	if bg == "":
		return ""
	var p2 := float(price.get(bg, 0.0))
	if float(b["till"]) < p2:
		return ""
	add_fam_gem(e, bestf, bg, -1)
	TownEcon.led(e, "used", bg, 1)
	b["till"] = float(b["till"]) - p2
	bestf["purse"] = float(bestf["purse"]) + p2
	return bg

# ================================================================== making
## The real people of a forge: its keeper (the owning family's grown-up who keeps it) and its staff (Persons.work).
## [{f, p, name}].
static func makers(e: Dictionary, b: Dictionary) -> Array:
	var out := []
	var bid := int(b["id"])
	var race := Persons.race_of(e)
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		var jobs: Dictionary = f.get("jobs", {})
		var keeps: bool = (f.get("keeps", []) as Array).any(func(k): return int(k) == bid)
		if int(jobs.get(bid, jobs.get(str(bid), 0))) <= 0 and not keeps:
			continue
		var wk := Persons.work(e, f)
		for pid in wk:
			if int(wk[pid].get("biz", -1)) != bid:
				continue
			var p := Persons.by_pid(f, int(pid))
			if not p.is_empty():
				out.append({"f": f, "p": p, "name": Persons.name_of(f, p, race)})
	return out

static func made_by(p: Array) -> int:
	return int(Persons.g(p, Persons.LEG, 0))

## A legendary roll at forge b turned out `it` (quality DB.LEGEND). Makes it a legendary piece (maker, gem, name,
## history), or turns it back to masterwork when the forge has no maker under the cap or no stone. Returns whether
## it stayed legendary.
static func forge(game, town: Dictionary, e: Dictionary, b: Dictionary, it: Item, rng: RandomNumberGenerator, day: float) -> bool:
	if not it.is_legend():
		return false
	var cands := makers(e, b).filter(func(m): return made_by(m["p"]) < CAP)
	if cands.is_empty():
		it.quality = 5
		_count(game, "no_maker")
		return false
	var gem := take_gem(e, b)
	if gem == "":
		it.quality = 5
		_count(game, "no_gem")
		return false
	var m: Dictionary = cands[rng.randi() % cands.size()]
	var p: Array = m["p"]
	while p.size() <= Persons.LEG:
		p.append(0 if p.size() == Persons.LEG else -1)
	p[Persons.LEG] = made_by(p) + 1
	var tn := String(town.get("name", "?"))
	it.legend = {"nm": unique_name(game, it, rng), "gem": gem, "at": Item.gem_spot(it.tid), "by": String(m["name"]), "bt": tn,
		"d": int(day), "k": 0, "kl": [], "cu": -1, "h": []}
	note(it, day, "Made by %s at %s in %s, %s set in its %s." % [String(m["name"]), Businesses.title(e, b), tn,
		Item._a(it.gem_name()), String(it.legend["at"])])
	Persons.log_life(p, day, "legend", it.display_name())
	TownEcon.town_hist(e, "%s made %s." % [String(m["name"]), it.display_name()], day)
	if game != null and game.world is Dictionary and game.world.has("towns"):
		CampaignWorld.log_event(game, "%s of %s made %s." % [String(m["name"]), tn, it.display_name()])
	_count(game, "made")
	return true

static func _count(game, k: String) -> void:
	if game == null or not (game.world is Dictionary):
		return
	var s: Dictionary = game.world.get("legend_stats", {})
	s[k] = int(s.get(k, 0)) + 1
	game.world["legend_stats"] = s

## A name nobody else's piece has (world.legend_names): two parts, the second by weapon or armour.
static func unique_name(game, it: Item, rng: RandomNumberGenerator) -> String:
	var used: Dictionary = {}
	if game != null and game.world is Dictionary:
		if not game.world.has("legend_names"):
			game.world["legend_names"] = {}
		used = game.world["legend_names"]
	var bs: Array = NAME_B_WEAPON if (it.is_weapon() or DB.is_bow(it.tid)) else NAME_B_ARMOR
	var nm := ""
	for i in 40:
		nm = String(NAME_A[rng.randi() % NAME_A.size()]) + String(bs[rng.randi() % bs.size()])
		if not used.has(nm):
			break
	if used.has(nm):
		var n := 2
		while used.has("%s the %s" % [nm, _ord(n)]):
			n += 1
		nm = "%s the %s" % [nm, _ord(n)]
	used[nm] = true
	return nm

static func _ord(n: int) -> String:
	return ["Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "Ninth"][clampi(n - 2, 0, 7)] if n <= 9 else "%dth" % n

# ================================================================== its history
static func note(it: Item, day: float, text: String) -> void:
	if not it.is_legend():
		return
	if not it.legend.has("h"):
		it.legend["h"] = []
	var h: Array = it.legend["h"]
	h.append([int(day), text])
	while h.size() > HIST_MAX:
		h.remove_at(1)

static func _day() -> float:
	return float(Game.day) if Game != null else 0.0

static func who(u: Unit) -> String:
	var f := "your company" if u.faction == "player" else String(DB.factions.get(u.faction, {}).get("name", u.faction))
	return "%s (%s%s)" % [u.name, u.title if u.title != "" else "fighter", (", " + f) if f != "" else ""]

static func slot_of(it: Item) -> String:
	return "ranged" if DB.is_bow(it.tid) else it.slot()

static func _cap1(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)

## He has it on: a new carrier goes in its history (once per carrier).
static func touch(it: Item, u: Unit, how: String = "carried by") -> void:
	if it == null or not it.is_legend() or u == null:
		return
	if int(it.legend.get("cu", -1)) == u.uid:
		return
	it.legend["cu"] = u.uid
	note(it, _day(), "%s %s." % [_cap1(how), who(u)])

static func touch_unit(u: Unit) -> void:
	if u == null:
		return
	for s in u.equip:
		var it: Item = u.equip[s]
		if it != null and it.is_legend():
			touch(it, u)

## Renown.on_kill: the kill goes on his legendary weapon (the main hand, else the bow).
static func on_kill(killer: Unit, victim: Unit) -> void:
	var it: Item = killer.equip.get("main_hand", null)
	if it == null or not it.is_legend():
		it = killer.equip.get("ranged", null)
	if it == null or not it.is_legend():
		return
	touch(it, killer)
	it.legend["k"] = int(it.legend.get("k", 0)) + 1
	var kl: Array = it.legend.get("kl", [])
	kl.append(victim.name)
	while kl.size() > KILLS_KEPT:
		kl.pop_front()
	it.legend["kl"] = kl

## Its carrier fell and the winners took it (Loot.spoils). The carrier's home town remembers the loss.
static func fell(it: Item, u: Unit, taker: String) -> void:
	if not it.is_legend():
		return
	var day := _day()
	note(it, day, "Taken from the fallen %s by %s." % [u.name, taker if taker != "" else "the victors"])
	it.legend["cu"] = -1
	if Game == null or not (Game.world is Dictionary):
		return
	var t: Dictionary = Game.world.get("towns", {}).get(u.home_town, {})
	if not TownEcon.has_econ(t):
		return
	var e: Dictionary = t["econ"]
	TownEcon.town_hist(e, "%s fell and %s was lost to %s." % [u.name, it.display_name(), taker if taker != "" else "the enemy"], day)
	if not e.has("legends_lost"):
		e["legends_lost"] = []
	(e["legends_lost"] as Array).append([int(day), it.display_name(), u.name, taker])

# ================================================================== who takes it
## The fighter of these men it fits best: a weapon to the man most skilled with its kind, armour to the highest rank
## (renown breaks ties). Living people only; a two-handed weapon is not given to a man who must keep a shield on.
static func best_fighter(units: Array, it: Item) -> Unit:
	var slot := slot_of(it)
	var skill := String(it.tmpl().get("skill", "bow" if DB.is_bow(it.tid) else ""))
	var best: Unit = null
	var bs := -1.0e9
	for u in units:
		if not (u is Unit) or u.dead or u.race_def().get("creature", false):
			continue
		var cur: Item = u.equip.get(slot, null)
		if cur != null and cur.is_legend():
			continue   # one legendary piece in a slot stays
		var sc := 0.0
		if it.is_weapon() or DB.is_bow(it.tid):
			sc = float(u.skill(skill)) * 10.0 + float(u.rank) + u.renown * 0.01
		else:
			sc = float(u.rank) * 10.0 + float(u.role == "officer" or u.role == "captain") * 50.0 + u.renown * 0.01
		if sc > bs:
			bs = sc
			best = u
	return best

## An AI winner takes it: on its best fitting fighter. Returns [taken, piece he wore in that slot or null, shield he
## put down for a two-handed weapon or null] (the caller sends those the normal way).
static func give(units: Array, it: Item) -> Array:
	var u := best_fighter(units, it)
	if u == null:
		return [false, null, null]
	var slot := slot_of(it)
	var old: Item = u.equip.get(slot, null)
	u.equip[slot] = it
	var off: Item = null
	if slot == "main_hand" and it.tmpl().get("two_handed", false) and u.equip.has("off_hand"):
		off = u.equip["off_hand"]
		u.equip.erase("off_hand")
	touch(it, u, "taken up by")
	return [true, old, off]

## Every legendary piece in the world and where it is: [[Item, where]] (records; scans the company, the stash, every
## force, caravan cargo, stall, armory and hoard).
static func all_held(game) -> Array:
	var out := []
	var seen := {}
	var add := func(it, where: String):
		if it is Item and it.is_legend() and not seen.has(it.uid):
			seen[it.uid] = true
			out.append([it, where])
	for u in game.company:
		for s in u.equip:
			add.call(u.equip[s], "carried by %s of your company" % u.name)
	for it in game.stash:
		add.call(it, "in your company's stash")
	var w: Dictionary = game.world
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		var fn := CampaignWorld.faction_the(String(wb.get("faction", "")))
		for u in wb.get("units", []):
			if u is Unit and not u.dead:
				for s in u.equip:
					add.call(u.equip[s], "carried by %s (%s, %s %s)" % [u.name, u.title, fn, String(wb.get("kind", "band"))])
		for it in wb.get("cargo", {}).get("items", []):
			add.call(it, "in a caravan's cargo (%s)" % fn)
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		for it in t.get("shop", []):
			add.call(it, "on the stalls of %s" % String(t.get("name", tid)))
		for it in t.get("armory_items", []):
			add.call(it, "in the armory of %s" % String(t.get("name", tid)))
		for u in t.get("recruits", []):
			if u is Unit:
				for s in u.equip:
					add.call(u.equip[s], "carried by %s, for hire in %s" % [u.name, String(t.get("name", tid))])
	for lid in w.get("lairs", {}):
		for it in w["lairs"][lid].get("stock", []):
			add.call(it, "in an outlaw hoard")
	return out
