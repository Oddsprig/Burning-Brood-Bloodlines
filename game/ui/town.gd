extends Control
## Town screen (Game.location = town id; data in Game.world.towns[id], world contract).
## Tabs: Market, Recruits, Healer, Contracts. Company button; Leave returns to the map.

var tab: String = "Market"
var page: VBoxContainer
var tabs_box: HBoxContainer
var purse: Label
var info: BoxContainer
var summary: HFlowContainer

## The current town (Game.world.towns[Game.location]); {} if missing. Tests install a DevTown first.
func town() -> Dictionary:
	return Game.world.get("towns", {}).get(Game.location, {})

func _ready() -> void:
	var t := town()
	if t.is_empty():
		var f0 := UiKit.screen_frame(self, "No town here")
		f0["bar"].add_child(UiKit.spacer())
		f0["bar"].add_child(UiKit.button("Leave", _leave, "Danger", 120))
		return
	# autosave on arriving from the map (v0.014: not again on coming back from the company or records screens; the
	# JSON is written by a worker thread, core/game.gd save_game_async)
	if Game.screen_params.get("arrive", false):
		Game.save_game_async()
	if Game.screen_params.has("tab"):
		tab = String(Game.screen_params["tab"])
	if Game.screen_params.has("econ_section"):
		set_meta("town_econ_section", String(Game.screen_params["econ_section"]))
	var f := UiKit.screen_frame(self, String(t.get("name", "Town")))
	var bar: HBoxContainer = f["bar"]
	UiKit.shrink(f["title"], 80)
	var fid: String = t.get("faction", "")
	var chip := UiKit.chip(UiWords.faction_name(fid), UiWords.faction_color(fid))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.tooltip_text = UiWords.faction_name(fid)
	UiKit.wrap(chip.get_child(0), 80)
	bar.add_child(chip)
	bar.add_child(UiKit.spacer())
	bar.add_child(UiKit.button("Army", func(): Game.goto("muster", {"back": "town"}), "", 150))
	bar.add_child(UiKit.button("Leave", _leave, "Danger", 120))
	var root: VBoxContainer = f["root"]
	purse = UiKit.purse(Game) # wraps rather than cutting off large balances
	info = BoxContainer.new()
	info.add_theme_constant_override("separation", 8)
	root.add_child(info)
	summary = UiKit.flow(8)
	UiKit.expand(summary)
	info.add_child(summary)
	info.add_child(purse)
	tabs_box = UiKit.hbox(6)
	var navigation := ScrollContainer.new()
	navigation.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	navigation.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(navigation)
	navigation.add_child(tabs_box)
	var pp := UiKit.panel()
	UiKit.expand(pp, true, true)
	root.add_child(pp)
	var services := UiKit.scroll()
	services.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	pp.add_child(services)
	page = UiKit.vbox(8)
	UiKit.expand(page, true, true)
	services.add_child(page)
	resized.connect(_fit_layout)
	_fit_layout()
	refresh()

func _fit_layout() -> void:
	if info == null: return
	info.vertical = size.x < 600
	if page != null:
		_fit_services(page)

## Keep existing service tables/actions intact and reachable through bounded
## scrolling. Their own inner list scrollers need usable height on short phones.
func _fit_services(node: Node) -> void:
	if node is ScrollContainer:
		var sc := node as ScrollContainer
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		if sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			sc.custom_minimum_size.y = minf(180, maxf(100, size.y * 0.35))
	for child in node.get_children():
		_fit_services(child)

func _refresh_summary(t: Dictionary) -> void:
	UiKit.clear(summary)
	summary.add_child(UiKit.chip(["Hamlet", "Village", "Town", "City"][clampi(int(t.get("size", 0)), 0, 3)], UiTheme.WOOD_3))
	var days := TownEcon.days_food(t) if TownEcon.has_econ(t) else -1.0
	var food_chip := UiKit.chip("Food · %d days" % int(days) if days >= 0 else "Food · " + Goods.level_word(t, "food"), UiTheme.GOOD if days >= 7 else UiTheme.WARN)
	food_chip.tooltip_text = Goods.summary(t)
	summary.add_child(food_chip)
	var specialty := String(t.get("specialty", ""))
	if specialty != "":
		summary.add_child(UiKit.chip(specialty.capitalize(), UiTheme.BLUE))
	var lore := UiKit.button("About town", func():
		UiKit.message(self, String(t.get("name", "Town")), [Economy.describe_town(t), Goods.summary(t)]), "Row", 125)
	summary.add_child(lore)
	if not Game.contract.is_empty():
		var contract_button := UiKit.button("Active contract", func(): show_tab("Contracts"), "Row", 130)
		contract_button.tooltip_text = Contracts.status_text(Game)
		summary.add_child(contract_button)

func _leave() -> void:
	Game.location = ""
	if not Game.world.is_empty():
		Game.save_game_async()  # autosave on leaving a town
	Game.goto("map")

func show_tab(t: String) -> void:
	if t in ["Politics", "Population"]:
		PoliticsView.open_view(t.to_lower(), Game.location, "town", {"tab": tab})
		return
	if t == "Records":   # the records screen (ui/records.gd): this town's 12 tabs, its faction, the whole world
		Game.goto("res://ui/records.tscn", {"view": "town", "id": Game.location, "back": "town"})
		return
	tab = t
	refresh()

func refresh() -> void:
	purse.text = UiKit.purse_text(Game)
	UiKit.clear(tabs_box)
	var t := town()
	_refresh_summary(t)
	tabs_box.add_child(UiKit.tab_strip(["Market", "Provisions", "Recruits", "Healer", "Contracts", "Town", "Politics", "Population", "Records"], tab, show_tab))
	UiKit.clear(page)
	match tab:
		"Town": page.add_child(TownEconTab.build(self, t))   # economy spec 12 (ui/town_econ_tab.gd)
		"Provisions": page.add_child(_provisions(t))
		"Recruits": page.add_child(_recruits(t))
		"Healer": page.add_child(_healer(t))
		"Contracts": page.add_child(_contracts(t))
		_: page.add_child(_market(t))
	_fit_services(page)

# ------------------------------------------------------------------ market
func _market(t: Dictionary) -> Control:
	return TownMarketTab.build(self, t)

func _smith(kind: String, c: Dictionary) -> void:
	var sk := int(c.get("skill", 0))
	UiKit.message(self, "%s, %s" % [c.get("name", "?"), kind], [
		Economy.describe_crafter(c) + ".",
		"Skill %d of 15: %s." % [sk, UiWords.crafter_word(sk)],
		"Better smiths turn out finer pieces: expect around %s work." % (DB.QUALITY_NAMES[clampi(int(round(Factory.quality_center(sk))), 0, 5)] if sk >= 5 else "ordinary"),
	])

func _sell(t: Dictionary) -> void:
	var opts := []
	var items: Array = Game.stash.duplicate()
	items.sort_custom(func(a, b): return a.display_name() < b.display_name())
	for it in items:
		opts.append({"text": it.display_name(), "value": it, "detail": "%d coins" % Market.sell_price(t, it), "icon": ItemIcon.for_item(it)})
	UiKit.picker(self, "Sell which item?", opts, func(it):
		var p := Market.sell_price(t, it)
		if Market.sell(Game, t, it) == "":
			UiKit.toast(self, "Sold %s for %d coins" % [it.display_name(), p])
		refresh())

# ------------------------------------------------------------------ provisions (core/food.gd)
const FOOD_WORDS := {"meal": ["Mixed rations", "portions"], "beer": ["Beer", "mugs"], "wine": ["Wine", "cups"]}

## Market stalls for meals, beer and wine (town supply and prices where the town trades the good, else the
## fixed base prices), the company's stock and rations, and the tavern feast.
func _provisions(t: Dictionary) -> Control:
	return TownProvisionsTab.build(self, t)

## Remedies for the company's own sick (06-sickness.md section 6): the town's remedy stock at its market price,
## one per sick man who has none yet (Sickness.company_quote shows what Sickness.company_treat will do).
func _remedy_rows(t: Dictionary, box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	box.add_child(UiKit.label("Remedies for the sick", "H2"))
	if not TownEcon.has_econ(t):
		box.add_child(UiKit.label("Nobody here sells remedies.", "Muted", true))
		return
	var q := Sickness.company_quote(Game, t)
	box.add_child(UiKit.label("%d of the company sick, %d without a remedy. The market has %d remedies at %d coins each." % [
		int(q["sick"]), int(q["need"]), int(q["stock"]), int(ceil(float(q["price"])))], "", true))
	if int(q["need"]) == 0:
		box.add_child(UiKit.label("Nobody needs one.", "Muted", true))
		return
	var b := UiKit.button("Buy remedies for %d (%d coins)" % [int(q["treat"]), int(q["cost"])], func(): _buy_remedies(t), "", 0)
	b.name = "BuyRemedies"
	b.disabled = int(q["treat"]) == 0
	box.add_child(b)
	if int(q["treat"]) < int(q["need"]):
		box.add_child(UiKit.label("Enough for %d of %d: %s." % [int(q["treat"]), int(q["need"]),
			"the market has run out" if int(q["treat"]) >= int(q["stock"]) else "not enough coin"], "Muted", true))

func _buy_remedies(t: Dictionary) -> void:
	var got := Sickness.company_treat(Game, t)
	if int(got["treated"]) == 0:
		UiKit.toast(self, "No remedy bought", false)
	else:
		UiKit.toast(self, "Remedies for %d men (%d coins)" % [int(got["treated"]), int(got["cost"])])
	refresh()

func _buy_food(t: Dictionary, kind: String, n: int) -> void:
	var before := Food.stock(Game, kind)
	var err := Food.buy(Game, t, kind, n)
	if err != "":
		UiKit.toast(self, err, false)
	else:
		UiKit.toast(self, "Bought %d %s" % [Food.stock(Game, kind) - before, FOOD_WORDS[kind][1]])
	refresh()

func _feast(t: Dictionary) -> void:
	var err := Food.feast(Game, t)
	if err != "":
		UiKit.toast(self, err, false)
	else:
		UiKit.toast(self, "The company feasts long into the night")
	refresh()

# ------------------------------------------------------------------ recruits
func _recruits(t: Dictionary) -> Control:
	var recs: Array = Diplomacy.visible_recruits(Game, t)
	if recs.is_empty():
		var empty := UiKit.vbox()
		empty.add_child(UiKit.label("Nobody here is looking for work.", "Muted", true))
		return empty
	var sc := UiKit.scroll()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(grid)
	for r in recs:
		grid.add_child(_recruit_card(t, r))
	sc.resized.connect(func(): grid.columns = 1 if sc.size.x < 1000 else 2)
	return sc

func _recruit_card(t: Dictionary, r: Unit) -> Control:
	var card := UiKit.panel("Card")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UiKit.vbox(6)
	card.add_child(v)
	var top := UiKit.hbox(10)
	top.add_child(UiKit.portrait(r, 68))
	var iv := UiKit.vbox(2)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iv.add_child(UiKit.wrap(UiKit.label(r.name, "H2"), 100))
	iv.add_child(UiKit.label("%s · %s · %d years" % [UiWords.race_name(r).capitalize(), r.title, People.age_on(r, Game.day)], "Small", true))
	var o := Roster.offer(Game, r)
	var cost := int(o["hire_cost"])
	top.add_child(iv)
	v.add_child(top)
	v.add_child(HSeparator.new())
	v.add_child(UiKit.label(RecruitBrief.story(r, t), "Small", true))
	var ks := UnitSheet.known_skills(r)
	ks.sort_custom(func(a, b): return r.skill(a) > r.skill(b))
	var badges := UiKit.flow(6)
	for skill in ks.slice(0, 3):
		badges.add_child(UiKit.chip(UnitSheet.skill_line(r, skill), UiTheme.BLUE))
	if ks.is_empty():
		badges.add_child(UiKit.chip("No trained skills", UiTheme.WOOD_3))
	v.add_child(badges)
	var stats := UiKit.hbox(12)
	for attribute in ["STR", "AGI", "END"]:
		var score := int(round(Factory.attr_percentile(r.race, attribute, r.attr(attribute)) * 100.0))
		var stat := UiKit.kv(attribute, str(score), UiTheme.BAD if score < 40 else (UiTheme.GOOD if score > 60 else UiTheme.INK))
		stat.tooltip_text = "%s: %s · %d/100 among %s" % [UiWords.attr_name(attribute), UiWords.attr_word(attribute, r.attr(attribute), r.race), score, r.race_def().get("plural", r.race)]
		stats.add_child(stat)
	v.add_child(stats)
	v.add_child(HSeparator.new())
	v.add_child(UiKit.kv("Signing pay", "%s coins" % UiKit.thousands(cost), UiTheme.COPPER_LO if cost <= Game.gold else UiTheme.BAD))
	v.add_child(UiKit.kv("Daily wage", "%d coins" % int(o["wage"]), UiTheme.COPPER_LO))
	var row := UiKit.hbox()
	row.add_child(UiKit.button("Details", func(): _recruit_details(r), "Row", 120))
	var family_index := RecruitBrief.family_index(r, t)
	if family_index >= 0:
		row.add_child(UiKit.button("Family", func(): TownEconTab.family_modal(self, t, family_index), "Row", 90))
	row.add_child(UiKit.spacer())
	var hb := UiKit.button("Hire", func(): _hire(t, r), "", 140)
	hb.disabled = cost > Game.gold
	row.add_child(hb)
	v.add_child(row)
	return card

func _recruit_details(r: Unit) -> void:
	var v := UiKit.modal(self, "%s, %s" % [r.name, r.title], mini(1000, maxi(600, int(size.x) - 80)))
	v.add_child(UiKit.label(RecruitBrief.story(r, town()), "Small", true))
	var ov := UnitSheet.overview(r)
	ov.custom_minimum_size = Vector2(0, 470)
	v.add_child(ov)
	var row := UiKit.hbox()
	row.add_child(UiKit.spacer())
	row.add_child(UiKit.button("Close", func(): UiKit.close_modal(v), "", 160))
	v.add_child(row)

func _hire(t: Dictionary, r: Unit) -> void:
	var opts := []
	for l in Roster.leaders(Game):
		var n := Roster.troops_of(Game, l.uid).size()
		opts.append({"text": "%s's squad" % l.name, "value": l.uid, "detail": "%d/%d" % [n, Roster.MAX_TROOPS],
			"disabled": n >= Roster.MAX_TROOPS})
	opts.append({"text": "Unassigned for now", "value": -1})
	UiKit.picker(self, "Hire %s for %d coins into..." % [r.name, int(Roster.offer(Game, r)["hire_cost"])], opts, func(uid):
		var err := Roster.hire(Game, t, r, uid)
		if err != "":
			UiKit.toast(self, err, false)
		else:
			if uid != -1:
				Outfit.outfit_unit(Game.squads, r, Game.stash)
			UiKit.toast(self, "%s joins the company" % r.name)
		refresh())

# ------------------------------------------------------------------ healer
func _healer(t: Dictionary) -> Control:
	return TownHealerTab.build(self, t)

func _wounded_card(t: Dictionary, u: Unit, hr: Dictionary) -> Control:
	var card := UiKit.panel("Card")
	var v := UiKit.vbox(6)
	card.add_child(v)
	var h := UiKit.hbox(10)
	h.add_child(UiKit.portrait(u, 56))
	var iv := UiKit.vbox(0)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iv.add_child(UiKit.label("%s, %s" % [u.name, u.title], "H2"))
	var days := maxf(float(hr.get("heal_days", 0.0)), u.body.days_to_heal())
	var st: String = hr.get("status", "wounded")
	if st == "healthy":
		st = "wounded"
	var rec: String = hr.get("recovery", "%d days" % ceili(days))
	var fit: String = hr.get("fitness", "")
	iv.add_child(UiKit.label("%s%s, full recovery in %s of rest" % [st, (", " + fit) if fit != "" else "", rec], "Muted", true))
	h.add_child(iv)
	var hs := _healer_skill(t)
	var cost := Healing.treatment_cost(u, hs)
	if hs > 0 and cost > 0:
		var b := UiKit.button("Treat (%d coins)" % cost, func(): _treat(t, u, cost), "", 0)
		b.disabled = cost > Game.gold
		h.add_child(b)
	h.add_child(UiKit.button("Sheet", func(): Game.goto("company", {"back": "town", "unit": u.uid}), "Row", 100))
	v.add_child(h)
	for p in hr.get("parts", []):
		v.add_child(UnitSheet.part_card(p))
	for s in hr.get("summary", []):
		v.add_child(UiKit.label(String(s), "Small", true))
	return card

func _healer_skill(t: Dictionary) -> int:
	return int(t.get("healer", {}).get("skill", 0))

## healing.gd treat(unit, healer_skill); payment is ours (treatment_cost).
func _treat(t: Dictionary, u: Unit, cost: int) -> void:
	if not _treat_one(t, u, cost):
		UiKit.toast(self, "not enough coins", false)
		return
	UiKit.toast(self, "%s has been treated" % u.name)
	refresh()

## The one place a single treatment happens (pay, then Healing.treat); false if the coin is short.
func _treat_one(t: Dictionary, u: Unit, cost: int) -> bool:
	if Game.gold < cost:
		return false
	Game.gold -= cost
	_pay_healer(t, cost)
	Healing.treat(u, _healer_skill(t))
	return true

## Everyone the healer can treat now, most critical first: worst open wound's severity (HealthReport), then the
## dearer treatment (more days of wounds), then company order. Each entry {"unit", "cost"}.
func _treat_queue(t: Dictionary) -> Array:
	var hs := _healer_skill(t)
	var out := []
	if hs <= 0:
		return out
	var idx := 0
	for u in Game.company:
		var cost := Healing.treatment_cost(u, hs)
		if cost > 0:
			var worst := 0
			for p in HealthReport.describe(u).get("parts", []):
				if float(p.get("heal_days", 0.0)) > 0.0:
					worst = maxi(worst, int(p.get("severity", 0)))
			out.append({"unit": u, "cost": cost, "sev": worst, "idx": idx})
		idx += 1
	out.sort_custom(func(a, b):
		if a["sev"] != b["sev"]:
			return a["sev"] > b["sev"]
		if a["cost"] != b["cost"]:
			return a["cost"] > b["cost"]
		return a["idx"] < b["idx"])
	return out

## Treat everyone in the queue with the same _treat_one, stopping when the coin runs short.
## Returns {"treated": [Unit], "left": [Unit], "spent": int}; nobody is skipped silently.
func treat_all(t: Dictionary) -> Dictionary:
	var treated := []
	var left := []
	var spent := 0
	var stopped := false
	for e in _treat_queue(t):
		if not stopped and _treat_one(t, e["unit"], int(e["cost"])):
			treated.append(e["unit"])
			spent += int(e["cost"])
		else:
			stopped = true
			left.append(e["unit"])
	return {"treated": treated, "left": left, "spent": spent}

func _treat_all_confirm(t: Dictionary) -> void:
	var q := _treat_queue(t)
	if q.is_empty():
		return
	var total := 0
	for e in q:
		total += int(e["cost"])
	var msg := "Treat %d %s for %d coins?" % [q.size(), "man" if q.size() == 1 else "men", total]
	if total > Game.gold:
		msg += " You have %d: the most critical are treated first and the rest wait." % Game.gold
	UiKit.confirm(self, msg, "Treat all", func():
		var r := treat_all(t)
		var lines := []
		for u in r["treated"]:
			lines.append("Treated: %s" % u.name)
		for u in r["left"]:
			lines.append("Not treated (not enough coin): %s" % u.name)
		if r["left"].is_empty():
			UiKit.toast(self, "%d treated (%d coins)" % [r["treated"].size(), r["spent"]])
		else:
			UiKit.message(self, "Treated %d of %d (%d coins)" % [r["treated"].size(), q.size(), r["spent"]], lines)
		refresh())

## Coinage: the healer's fee is real coin: it goes to the town's market (the healer's custom), no coin vanishes.
func _pay_healer(t: Dictionary, cost: int) -> void:
	Goods.pay_market(t, float(cost))

func _rest(days: int) -> void:
	Game.advance_time(days, true, _healer_skill(town()))
	UiKit.toast(self, "The company rests %d day%s" % [days, "" if days == 1 else "s"])
	refresh()

# ------------------------------------------------------------------ contracts
func _contracts(t: Dictionary) -> Control:
	return TownContractsTab.build(self, t)

func _has_active_contract() -> bool:
	return not Game.contract.is_empty() and String(Game.contract.get("state", "active")) == "active"

func _accept(_t: Dictionary, c: Dictionary) -> void:
	if Contracts.accept(Game, c):
		UiKit.toast(self, "Contract accepted: %s" % c.get("title", ""))
	else:
		UiKit.toast(self, "Cannot take this contract now", false)
	refresh()

# ------------------------------------------------------------------ arrows (bows), on the Provisions tab
## Arrows are company consumables like food: bought from the town's real stock, filling every archer's quiver
## at once (50 each) with the rest kept in the company's stores.
func _arrow_rows(t: Dictionary, box: VBoxContainer) -> void:
	var archers := Game.company.filter(func(u): return not u.dead and u.has_method("bow") and u.bow() != null)
	box.add_child(UiKit.label("Arrows", "H2"))
	var qv := 0
	for u in archers:
		qv += int(u.arrows()) if u.has_method("arrows") else 0
	box.add_child(UiKit.label("%d archers, %d arrows in their quivers (50 each at most)" % [archers.size(), qv], "Muted", true))
	var any := false
	for ak in DB.arrows:
		var here := int(Goods.supply(t, ak))
		var carried := int(floor(float(Goods.company_goods(Game).get(ak, 0.0))))
		if here <= 0 and carried <= 0:
			continue
		any = true
		var row := UiKit.panel("Card")
		var r := UiKit.hbox(10)
		row.add_child(r)
		var iv := UiKit.vbox(0)
		iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		iv.add_child(UiKit.label("%s: you carry %d" % [Goods.good_name(ak).capitalize(), carried], "H2"))
		iv.add_child(UiKit.label("%.2f coins each, %d for sale" % [Goods.price_f(t, ak), here], "Muted"))
		r.add_child(iv)
		for n in [50, 200]:
			var b := UiKit.button("Buy %d" % n, func():
				var got := BowsEcon.buy_for_company(Game, t, ak, n)
				BowsEcon.fill_company_quivers(Game)
				UiKit.toast(self, "Bought %d %s; quivers filled" % [got, Goods.good_name(ak)])
				refresh(), "", 110)
			b.disabled = here <= 0 or Game.gold < int(ceil(Goods.price_f(t, ak)))
			r.add_child(b)
		box.add_child(row)
	if not any:
		box.add_child(UiKit.label("No arrows for sale here.", "Muted"))
