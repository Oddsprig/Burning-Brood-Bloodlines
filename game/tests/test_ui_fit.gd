extends RefCounted
## Every menu screen fits the window: each screen (and each tab) is built inside a SubViewport the size of
## the canvas_items/expand content area for a range of real window sizes, and every visible Control must lie
## inside the viewport. Inside a ScrollContainer only the non-scrolling axis is checked (against the scroll
## container's own rect). Reports the worst offenders per screen/size.

const BASE := Vector2(1280, 720)
## Window sizes Douglas plays at, plus a phone in both orientations (landscape is the target).
const WINDOWS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(2000, 1250), Vector2i(2400, 1080), Vector2i(1080, 2400)]
const TOL := 1.5

var fails := 0
var tree: SceneTree
var town_id := ""

## Content area of a window under stretch mode canvas_items + aspect expand (base 1280x720).
static func effective(win: Vector2i) -> Vector2:
	var s := minf(win.x / BASE.x, win.y / BASE.y)
	return (Vector2(win) / s).floor()

func run(t: SceneTree) -> int:
	tree = t
	await tree.process_frame
	var loaded := await DevTools.start_world(tree, Game.SAVE_PATH)
	assert(loaded, "Normal one-day UI fixture loads")
	var home := DevTools.choose_house(Game, func(choice: Dictionary):
		return str(Dynasty.person(Game, str(choice["ruler_uid"])).get("race", "")) == "human")
	var raised := DevTools.raise_army(Game, home, 2)
	assert(raised == 2, "two native residents provide actual company tabs")
	var enlisted := Mobilization.enlist_household(Game, str(Dynasty.selected(Game)["ruler_uid"]))
	assert(bool(enlisted.get("ok", false)), "the actual ruler supplies a native officer portrait")
	town_id = _friendly_town()
	_wound(enlisted["unit"])
	# a fake aftermath result
	var rng := RandomNumberGenerator.new(); rng.seed = 4
	var foes := Factory.make_warband(rng, "orc_horde", 6)
	Game.last_result = {"winner": 0, "player_units": Game.company.duplicate(), "enemy_units": foes,
		"enemy_fallen": foes.slice(0, 4), "events": [], "dead_names": ["Somebody Unlucky"], "loot_gold": 120}
	if OS.get_cmdline_user_args().has("--battle-only"):
		for size: Vector2 in [Vector2(1280,720), Vector2(1920,1080), Vector2(2560,1440)]:
			await _battle(size)
		print("Battle UI fit: 3 desktop sizes, 9 inspector/legend fit cases, %d failures" % fails)
		return fails
	var sizes := []
	for w in WINDOWS:
		var e := effective(w)
		if not sizes.has(e):
			sizes.append(e)
	if OS.get_environment("FIT_QUICK") != "":   # iteration aid: only the smallest content area
		sizes = [sizes[0]]
	for size in sizes:
		print("-- viewport %s" % [size])
		await _screen(size, "res://ui/title.tscn", [])
		await _screen(size, "res://ui/settings.tscn", [])
		await _screen(size, "res://ui/newgame.tscn", [])   # New Campaign options (world size, the years before)
		var co := []
		for uid in _sample_units():
			for tb in ["Overview", "Mind", "Skills", "Gear", "Health", "Squad", "Family"]:
				co.append(["company %d %s" % [uid, tb], func(s): s.select(uid); s.show_tab(tb)])
		await _screen(size, "res://ui/company.tscn", co)
		var bo := []   # v0.014: the company baggage (ui/baggage.gd), every tab
		for tb in ["Armour", "Food and drink", "Other items"]:
			bo.append(["baggage " + tb, func(s): s.show_tab(tb)])
		await _screen(size, "res://ui/baggage.tscn", bo)
		if town_id != "":
			Game.location = town_id
			var to := []
			for tb in ["Market", "Provisions", "Goods", "Recruits", "Healer", "Contracts"]:
				to.append(["town " + tb, func(s): s.show_tab(tb)])
			await _screen(size, "res://ui/town.tscn", to)
			# the records screen: every town tab, a world tab, a faction tab and a family page
			var ro := []
			for tb in ["Overview", "Market", "Businesses", "Register", "Land & Homes", "Census", "Treasury", "Hardship", "Garrison",
					"Roads", "Sickness", "Books"]:
				ro.append(["records " + tb, func(s): s.show_tab(tb)])
			ro.append(["records family", func(s): s.open_family(Game.world["towns"][town_id], int(RecData.fams(Game.world["towns"][town_id]["econ"])[0]["id"]))])
			ro.append(["records world Towns", func(s): s.set_view("world", "", "Towns")])
			ro.append(["records faction Army", func(s): s.set_view("faction", String(Game.world["towns"][town_id]["faction"]), "Army")])
			Game.screen_params = {"back": "town"}
			await _screen(size, "res://ui/records.tscn", ro)
			Game.screen_params = {}
			Game.location = ""
		if ResourceLoader.exists("res://ui/relations.tscn"):
			await _screen(size, "res://ui/relations.tscn", [["relations World", func(s): s.show_tab("World")]])
		await _map(size)
		await _screen(size, "res://ui/gameover.tscn", [])
		await _screen(size, "res://battle/aftermath.tscn", [])
		await _battle(size)
	return fails

func _sample_units() -> Array:
	var out := [Roster.leaders(Game)[0].uid]
	var lead := Roster.leaders(Game)
	if lead.size() > 1:
		out.append(lead[1].uid)
		var tr := Roster.troops_of(Game, lead[1].uid)
		if not tr.is_empty():
			out.append(tr[0].uid)
	return out

func _friendly_town() -> String:
	for id in Game.world.get("towns", {}):
		var t: Dictionary = Game.world["towns"][id]
		if not DB.factions.get(t["faction"], {}).get("player_hostile", false) and not t.get("recruits", []).is_empty():
			return id
	return ""

func _wound(u: Unit) -> void:
	for l in u.body.wound_part("arm_upper_l")["layers"]:   # sparse bodies (v0.013): the writable part
		if l["tissue"] in ["skin", "muscle", "bone"]:
			l["dmg"] = 0.7; l["kind"] = "fractured" if l["tissue"] == "bone" else "cut"

func _viewport(size: Vector2) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = Vector2i(size)
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(sv)
	return sv

## Builds `path` in a viewport of `size`, checks it, then applies each [label, fn(screen)] state and checks again.
func _screen(size: Vector2, path: String, states: Array) -> void:
	var sv := _viewport(size)
	var s: Node = (load(path) as PackedScene).instantiate()
	sv.add_child(s)
	await _settle()
	_check(sv, size, path.get_file())
	for st in states:
		st[1].call(s)
		await _settle()
		_check(sv, size, st[0])
	sv.queue_free()
	await tree.process_frame

const LONG := "Peace: the Kingdom of the Middle March and the Clans of the Northern Fells have signed a treaty after a long and bitter war over the high passes, and the roads are open again."

## World map HUD with its worst-case texts: a long news line, an active contract, long log lines, a toast,
## and the info panel open on a town.
func _map(size: Vector2) -> void:
	var saved_contract: Dictionary = Game.contract
	var saved_log: Array = (Game.world.get("log", []) as Array).duplicate()
	var dp = Game.world.get("diplo")
	if dp != null:
		dp["news"].append({"text": LONG, "day": Game.day})
	Game.world["log"] = saved_log + [LONG, LONG]
	if town_id != "" and Game.contract.is_empty():
		var cs: Array = Game.world["towns"][town_id].get("contracts", [])
		if not cs.is_empty():
			Contracts.accept(Game, cs[0])
	var states := [
		["map toast", func(s): s.toast(LONG)],
		["map info town", func(s): if town_id != "": s._select({"kind": "town", "id": town_id})],
	]
	await _screen(size, "res://campaign/world_map.tscn", states)
	if dp != null:
		dp["news"].pop_back()
	Game.world["log"] = saved_log
	Game.contract = saved_contract

func _battle(size: Vector2) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 9
	Game.pending_battle = {"enemy": Factory.make_warband(rng, "orc_horde", 6), "allies": [], "seed": 9, "terrain": "forest"}
	var sv := _viewport(size)
	var b: Node = (load("res://battle/battle.tscn") as PackedScene).instantiate()
	sv.add_child(b)
	b.set_speed(0.0)
	await _settle()
	b.step_ticks(60)
	var pick := -1
	for f in b.sim.fighters:
		if f.side == 0 and f.alive():
			pick = f.idx
			break
	if pick >= 0:
		b.inspector.show_fighter(b.sim.fighters[pick], b.sim)
		b.inspector.visible = true
	await _settle()
	_check(sv, size, "battle + inspector log")
	if pick >= 0:
		b.inspector.show_tab("health")
		await _settle()
		_check(sv, size, "battle + inspector health")
	b.readability_legend.button.set_pressed(true)
	await _settle()
	_check(sv, size, "battle + terrain/combat legend")
	b.readability_legend.close()
	sv.queue_free()
	Game.pending_battle = {}
	await tree.process_frame

func _settle() -> void:
	for i in 3:
		await tree.process_frame

## Walks the tree; collects controls outside the allowed rect.
func _check(sv: SubViewport, size: Vector2, label: String) -> void:
	var bad := []
	for c in sv.get_children():
		_walk(c, [0.0, 0.0, size.x, size.y], bad)
	if not bad.is_empty():
		fails += 1
		bad.sort_custom(func(a, b): return a[0] > b[0])
		printerr("FAIL: %s at %dx%d: %d controls push outside the window:" % [label, size.x, size.y, bad.size()])
		for i in mini(bad.size(), 8):
			printerr("    %.0f px  %s" % [bad[i][0], bad[i][1]])

## bounds = [x0, y0, x1, y1]: where this node's rect must lie (1e9 = unchecked).
## Only the deepest offenders are recorded (the control that actually pushes its parents out).
## Returns true if this subtree had an offender.
func _walk(n: Node, bounds: Array, bad: Array) -> bool:
	if n is Window:
		return false
	var child_bounds := bounds
	if n is CanvasItem and not (n as CanvasItem).visible:
		return false
	var mine := []
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		var over := maxf(maxf(bounds[0] - r.position.x, r.end.x - bounds[2]), maxf(bounds[1] - r.position.y, r.end.y - bounds[3]))
		if over > TOL and r.size.x > 0.5 and r.size.y > 0.5:
			mine = [over, _describe(c, r)]
		if c is ScrollContainer:
			var sc := c as ScrollContainer
			var hfree := sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			var vfree := sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			child_bounds = [-1e9 if hfree else r.position.x, -1e9 if vfree else r.position.y,
				1e9 if hfree else r.end.x, 1e9 if vfree else r.end.y]
		elif c.clip_contents:
			child_bounds = [-1e9, -1e9, 1e9, 1e9]  # clipped children are cut off by design, not spilling
	var below := false
	for ch in n.get_children():
		if _walk(ch, child_bounds, bad):
			below = true
	if not mine.is_empty() and not below:
		bad.append(mine)
	return below or not mine.is_empty()

func _describe(c: Control, r: Rect2) -> String:
	var txt := ""
	if "text" in c and c.text is String:
		txt = " '%s'" % String(c.text).substr(0, 40)
	var p := c.get_parent()
	var chain := c.get_class()
	var k := 0
	while p != null and k < 3:
		chain = p.get_class() + "/" + chain
		p = p.get_parent(); k += 1
	return "%s%s rect %s" % [chain, txt, r]
