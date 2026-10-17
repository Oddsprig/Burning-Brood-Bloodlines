class_name UnitSheet
extends RefCounted
## Builders for the unit sheet pages (Overview, Mind, Skills, Gear, Health). Shared by the company screen
## and recruit cards. `host` is the screen (for modals/toasts); `on_change` refreshes the screen.
## Attributes are shown Dwarf Therapist style: race-relative 0-100 (Factory.attr_percentile x100, red below
## the race median), DF word, talent stars, raw value and trainable max in the detail view.

const HEAL := "res://sim/healing.gd"

# ------------------------------------------------------------------ identity + attributes
static func header(u: Unit, px: int = 132) -> HBoxContainer:
	var h := UiKit.hbox(14)
	h.add_child(UiKit.portrait(u, px))
	var v := UiKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := UiKit.label(u.name, "H2")
	n.add_theme_font_size_override("font_size", 30)
	v.add_child(UiKit.shrink(n, 120))
	var ident := "%s %s" % [UiWords.race_name(u).capitalize(), u.title]
	if u.title != u.role:
		ident += ", " + UiWords.role_word(u).to_lower()
	v.add_child(UiKit.wrap(UiKit.label(ident, "Muted"), 120))
	v.add_child(facts(u))
	var chips := UiKit.flow(6)
	chips.add_child(UiKit.chip(UiWords.role_word(u), UiTheme.COPPER_LO if u.is_officer() else UiTheme.WOOD_3))
	var hr := HealthReport.describe(u)
	var st: String = hr.get("status", "healthy")
	chips.add_child(UiKit.chip(st, status_color(st)))
	var fit: String = hr.get("fitness", "")
	if fit != "" and st != "healthy":
		chips.add_child(UiKit.chip(fit, UiTheme.WOOD_3))
	var sk := Sickness.unit_text(u)   # sickness: the disease and its days ("the flux, day 3 of 7")
	if sk != "":
		chips.add_child(UiKit.chip(sk, UiTheme.BAD))
	v.add_child(chips)
	v.add_child(food_bars(u))
	var rt := Army.rank_title(u)   # economy spec 2: rank in his own force, kill renown
	v.add_child(UiKit.wrap(UiKit.label("%sBattles %d   Kills %d   Renown %d   Wage %d/day" % [(rt.capitalize() + "   ") if rt != "" else "", u.battles, u.kills, int(round(u.renown)), u.wage], "Small"), 120))
	h.add_child(v)
	return h

## Belly and buzz bars with the state name (core/food.gd). Tap a bar for that state's effects.
static func food_bars(u: Unit) -> Container:
	var h := UiKit.flow(10)
	var bs := Food.belly_state(u.belly)
	var bcol: Color = {"stuffed": UiTheme.WARN, "fed": UiTheme.GOOD, "hungry": UiTheme.WARN, "starving": UiTheme.BAD}[bs]
	h.add_child(_food_bar("Belly", Food.STATE_NAMES[bs], u.belly, bcol, "Belly: " + Food.STATE_NAMES[bs], Food.belly_effects(u)))
	var zs := Food.buzz_state(u.buzz)
	var title: String = "Buzz: " + Food.STATE_NAMES[zs] + (", hung over" if u.hungover else "")
	var zcol: Color = {"sober": UiTheme.WOOD_3, "tipsy": UiTheme.COPPER, "drunk": UiTheme.WARN, "hammered": UiTheme.BAD}[zs]
	h.add_child(_food_bar("Buzz", Food.STATE_NAMES[zs] + (" (hung over)" if u.hungover else ""), u.buzz, zcol, title, Food.buzz_effects(u)))
	return h

static func _food_bar(what: String, state: String, val: float, col: Color, title: String, lines: Array) -> Button:
	var b := Button.new()
	b.theme_type_variation = "Row"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(230, UiKit.TAP)
	b.tooltip_text = ""
	var v := UiKit.vbox(2)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10; v.offset_right = -10; v.offset_top = 4; v.offset_bottom = -4
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label("%s: %s" % [what, state], "Small")
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	var pb := ProgressBar.new()
	pb.max_value = 100
	pb.value = val
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 12)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	pb.add_theme_stylebox_override("fill", fill)
	v.add_child(pb)
	b.add_child(v)
	b.pressed.connect(func():
		var host: Node = b
		while host.get_parent() is Control:
			host = host.get_parent()
		UiKit.message(host as Control, title, lines))
	return b

static func status_color(st: String) -> Color:
	return UiTheme.GOOD if st == "healthy" else (UiTheme.WARN if st == "wounded" else UiTheme.BAD)

## Attribute table for `keys` (DB.ATTRS from u.attrs, or DB.MIND_ATTRS from u.mind).
## Detail columns: name, stars, race-relative word, 0-100 score, bar (ghost to the trainable max), raw + max.
## Compact (recruit cards): abbreviation, stars, word, score, bar.
static func attr_grid(u: Unit, keys: Array = DB.ATTRS, compact: bool = false) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 5 if compact else 6
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 4 if compact else 8)
	for a in keys:
		var is_mind: bool = DB.MIND_ATTRS.has(a)
		var v: int = int(u.mind.get(a, 1000)) if is_mind else u.attr(a)
		var cap: int = v if is_mind else int(u.attr_cap.get(a, v))
		var name_l := UiKit.label(a if compact else UiWords.attr_name(a), "Small" if compact else "")
		if compact:
			name_l.add_theme_font_override("font", UiTheme.bold())
		g.add_child(name_l if compact else UiKit.wrap(name_l, 100))
		var stars := TalentStars.new()
		stars.count = 0 if is_mind or not u.talent.has(a) else int(u.talent[a]) + 1
		g.add_child(stars)
		var w := UiKit.label(UiWords.attr_word(a, v, u.race) if compact else UiWords.attr_phrase(a, v, u.race), "Small" if compact else "")
		var tone := UiWords.attr_tone(u.race, a, v)
		if tone != 0:
			w.add_theme_color_override("font_color", UiTheme.GOOD if tone > 0 else UiTheme.BAD)
		UiKit.wrap(w, 70)
		g.add_child(w)
		var pct := int(round(Factory.attr_percentile(u.race, a, v) * 100.0))
		var num := UiKit.label(str(pct), "H2" if not compact else "Small")
		num.add_theme_font_size_override("font_size", 18 if compact else 20)
		# red exactly when the word is below typical (40-60 = typical)
		num.add_theme_color_override("font_color", UiTheme.BAD if pct < 40 else UiTheme.INK)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num.custom_minimum_size.x = 34
		g.add_child(num)
		var bar := AttrBar.new().setup(u.race, a, v, cap)
		bar.custom_minimum_size.x = 80 if compact else 110
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.add_child(bar)
		if not compact:
			var raw := "%d" % v
			if cap > v:
				raw += ", max ~%d" % _round_hint(cap)
			g.add_child(UiKit.wrap(UiKit.label(raw, "Muted"), 80))
	return g

static func _round_hint(v: int) -> int:
	return int(round(v / 50.0)) * 50

static func attr_legend(u: Unit) -> Label:
	return UiKit.label("Score 0-100 = rank among %s (40-60 typical, red below that). Bar line = typical; hatched = room to train. Stars = talent." % u.race_def().get("plural", u.race), "Muted", true)

static func overview(u: Unit) -> Control:
	var sc := UiKit.scroll()
	var v := UiKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(header(u))
	if u.backstory != "":
		var b := UiKit.panel("Inset")
		b.add_child(UiKit.label(u.backstory, "", true))
		v.add_child(b)
	v.add_child(UiKit.label("Combat attributes", "H2"))
	v.add_child(attr_grid(u, DB.ATTRS))
	v.add_child(attr_legend(u))
	v.add_child(UiKit.label("Personality", "H2"))
	v.add_child(personality_box(u))
	return sc

## One-line facts under the portrait: age, size, limbs, ambition, likes.
static func facts(u: Unit) -> VBoxContainer:
	var v := UiKit.vbox(2)
	var body := UiWords.size_words(u)
	var limbs := UiWords.limb_words(u)
	if limbs != "":
		body += ", " + limbs
	v.add_child(UiKit.label("Age %d, %s (%d kg)" % [u.age, body, int(round(u.mass()))], "Small", true))
	if u.ambition != "":
		v.add_child(UiKit.label("Dreams of: " + u.ambition, "Small", true))
	var pl := UiWords.preference_line(u)
	if pl != "":
		v.add_child(UiKit.label(pl, "Small", true))
	return v

## Small labelled 0-100 meter row (values, needs).
static func _meter_rows(grid: GridContainer, label_text: String, val: int, note: String) -> void:
	grid.add_child(UiKit.label(label_text, "Small"))
	var pb := ProgressBar.new()
	pb.max_value = 100
	pb.value = val
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(120, 16)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(pb)
	var n := UiKit.label(str(val), "Small")
	n.custom_minimum_size.x = 34
	grid.add_child(n)
	grid.add_child(UiKit.label(note, "Muted"))

## "Mind" page (Dwarf Therapist-like density): mind attributes, state of mind, personality, values, needs,
## kill list. Display-only for now.
static func mind(u: Unit) -> Control:
	var sc := UiKit.scroll()
	var v := UiKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var top := UiKit.hbox(16)
	var left := UiKit.vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UiKit.label("State of mind", "H2"))
	var sl := UiKit.label("Stress: " + UiWords.stress_word(u.stress), "", true)
	if u.stress >= 30:
		sl.add_theme_color_override("font_color", UiTheme.BAD)
	left.add_child(sl)
	var hw := UiWords.hardness_word(u.hardness)
	left.add_child(UiKit.label(hw.substr(0, 1).to_upper() + hw.substr(1) + " (%d)" % u.hardness, "Small", true))
	top.add_child(left)
	var right := UiKit.vbox(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(UiKit.label("Life", "H2"))
	right.add_child(facts(u))
	top.add_child(right)
	v.add_child(top)
	v.add_child(UiKit.label("Mind attributes", "H2"))
	v.add_child(attr_grid(u, DB.MIND_ATTRS))
	v.add_child(UiKit.label("Personality", "H2"))
	v.add_child(personality_box(u))
	v.add_child(UiKit.label("Values", "H2"))
	var lines := []
	for k in DB.VALUES:
		var line := UiWords.value_line(k, int(u.values.get(k, 50)))
		if line != "":
			lines.append(line)
	v.add_child(UiKit.label("; ".join(PackedStringArray(lines)) if not lines.is_empty() else "No strong convictions.", "", true))
	var vg := GridContainer.new()
	vg.columns = 4
	vg.add_theme_constant_override("h_separation", 12)
	for k in DB.VALUES:
		_meter_rows(vg, String(DB.VALUE_NAMES.get(k, k)).capitalize(), int(u.values.get(k, 50)), "")
	v.add_child(vg)
	v.add_child(UiKit.label("Needs", "H2"))
	v.add_child(UiKit.label(UiWords.needs_line(u), "", true))
	var ng := GridContainer.new()
	ng.columns = 4
	ng.add_theme_constant_override("h_separation", 12)
	for k in DB.NEEDS:
		var w := int(u.needs.get(k, 0))
		_meter_rows(ng, String(DB.NEED_NAMES.get(k, k)).capitalize(), w, "strong" if w >= 60 else "")
	v.add_child(ng)
	v.add_child(UiKit.label("Kills (%d)" % maxi(u.kills, u.kill_list.size()), "H2"))
	if u.kill_list.is_empty():
		v.add_child(UiKit.label("Has killed no one yet.", "Muted"))
	else:
		v.add_child(UiKit.label(", ".join(PackedStringArray(u.kill_list.map(func(x): return str(x)))), "", true))
	# economy spec 2: kill renown and the notable kills behind it
	var rl := Renown.lines(u)
	v.add_child(UiKit.label(rl[0], "H2"))
	if rl.size() > 1:
		v.add_child(UiKit.label("Notable kills: " + "; ".join(PackedStringArray(rl.slice(1))), "", true))
	return sc

# ------------------------------------------------------------------ personality
## Words for notable traits only (Factory.trait_word returns "" for typical values).
static func trait_words(u: Unit, traits: Array) -> Array:
	var out := []
	for t in traits:
		if u.personality.has(t):
			var w := Factory.trait_word(t, int(u.personality[t]))
			if w != "":
				out.append(w)
	return out

static func personality_words(u: Unit) -> String:
	var out := trait_words(u, DB.TRAITS)
	return ", ".join(PackedStringArray(out)) if not out.is_empty() else "unremarkable temperament"

## Words (in battle / in camp), plus a "Numbers" toggle that expands every trait value (0-100, 50 typical).
static func personality_box(u: Unit) -> VBoxContainer:
	var v := UiKit.vbox(6)
	var h := UiKit.hbox(10)
	var words := UiKit.vbox(2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bw := trait_words(u, DB.BATTLE_TRAITS)
	var cw := trait_words(u, DB.CAMP_TRAITS)
	words.add_child(UiKit.label("In battle: " + (", ".join(PackedStringArray(bw)) if not bw.is_empty() else "unremarkable"), "", true))
	words.add_child(UiKit.label("In camp: " + (", ".join(PackedStringArray(cw)) if not cw.is_empty() else "unremarkable"), "", true))
	h.add_child(words)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 14)
	grid.visible = false
	for t in DB.TRAITS:
		var val := int(u.personality.get(t, 50))
		grid.add_child(UiKit.label(String(DB.TRAIT_NAMES.get(t, t)).capitalize(), "Muted"))
		var n := UiKit.label(str(val), "Small")
		if val >= 65 or val <= 35:
			n.add_theme_font_override("font", UiTheme.bold())
		grid.add_child(n)
	var b := UiKit.button("Numbers", func(): grid.visible = not grid.visible, "Row", 120)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(b)
	v.add_child(h)
	v.add_child(grid)
	return v

# ------------------------------------------------------------------ skills
static func known_skills(u: Unit) -> Array:
	var out := []
	for s in u.skills:
		if int(u.skills[s]) > 0 or float(u.skill_xp.get(s, 0.0)) > 0.0:
			out.append(s)
	out.sort_custom(func(a, b): return int(u.skills[a]) > int(u.skills[b]))
	return out

static func skill_line(u: Unit, s: String) -> String:
	return "%s %s" % [UiWords.skill_level(u.skill(s)), UiWords.skill_name(s).to_lower()]

## Skills page in three groups. Weapon and combat skills list what the unit knows; utility skills list the
## v0.001 ones always (they work now) and the rest only if known, greyed as "later".
static func skills(u: Unit) -> Control:
	var sc := UiKit.scroll()
	var v := UiKit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var groups := [["Weapons", DB.WEAPON_SKILLS + DB.RANGED_SKILLS], ["Combat", DB.COMBAT_SKILLS], ["Utility", DB.UTILITY_SKILLS]]   # bows: the bow skill with the weapons
	for gr in groups:
		var list: Array = []
		for s in gr[1]:
			var known := u.skill(s) > 0 or float(u.skill_xp.get(s, 0.0)) > 0.0
			if known or (gr[0] == "Utility" and DB.UTILITY_SKILLS_V1.has(s)):
				list.append(s)
		list.sort_custom(func(a, b): return u.skill(a) > u.skill(b))
		v.add_child(UiKit.label(gr[0], "H2"))
		if list.is_empty():
			v.add_child(UiKit.label("None yet.", "Muted"))
		for s in list:
			v.add_child(_skill_row(u, s, gr[0] == "Utility" and not DB.UTILITY_SKILLS_V1.has(s)))
	return sc

static func _skill_row(u: Unit, s: String, later: bool) -> Control:
	var row := UiKit.panel("Card")
	var h := UiKit.hbox(12)
	row.add_child(h)
	var n := UiKit.label(UiWords.skill_name(s), "H2")
	n.add_theme_font_size_override("font_size", 21)
	UiKit.shrink(n, 110)
	h.add_child(n)
	var lvl := u.skill(s)
	var lv := UiKit.label("%s (%d)" % [UiWords.skill_level(lvl), lvl] if lvl > 0 or float(u.skill_xp.get(s, 0.0)) > 0 else "untrained", "" if lvl > 0 else "Muted")
	UiKit.shrink(lv, 110)
	h.add_child(lv)
	var need := UiWords.xp_needed(lvl)
	var xp := float(u.skill_xp.get(s, 0.0))
	var pb := ProgressBar.new()
	pb.max_value = need
	pb.value = clampf(xp, 0, need)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(140, 18)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pb)
	h.add_child(UiKit.label("%d/%d xp" % [int(xp), int(need)], "Muted"))
	if later:
		h.add_child(UiKit.chip("later", Color("9a8b74")))
		row.modulate = Color(1, 1, 1, 0.6)
	return row

# ------------------------------------------------------------------ gear
static func gear(u: Unit, game, host: Control, on_change: Callable) -> Control:
	var outer := UiKit.vbox(8)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sc := UiKit.scroll()
	outer.add_child(sc)
	var v := UiKit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var want := Outfit.wanted(game.squads, u)
	for slot in DB.EQUIP_SLOTS:
		var row := UiKit.panel("Card")
		var h := UiKit.hbox(10)
		row.add_child(h)
		var sl := UiKit.label(UiWords.slot_name(slot), "Muted")
		sl.custom_minimum_size.x = 104
		h.add_child(sl)
		var info := UiKit.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var it: Item = u.equip.get(slot, null)
		h.add_child(UiKit.icon(ItemIcon.for_item(it) if it else null, 44))   # art/item_icon.gd (empty slot: a blank)
		var name_l := UiKit.label(it.display_name() if it else "-", "H2" if it else "Muted")
		if it:
			name_l.add_theme_font_size_override("font_size", 21)
		info.add_child(UiKit.shrink(name_l, 80))
		var sub := []
		if it:
			sub.append(UiWords.kg(it.mass()))
			if it.quality > 0:
				sub.append(DB.QUALITY_NAMES[it.quality])
			sub.append(it.maker_text())   # arms trade: the maker's mark
		if want.has(slot):
			var src := "own choice" if u.overrides.has(slot) else "uniform"
			sub.append("%s: %s" % [src, Outfit.template_name(want[slot])])
		if slot == "off_hand" and u.weapon() and Outfit.is_two_handed(u.weapon().tid):
			sub.append("two-handed weapon: no shield")
		if not sub.is_empty():
			info.add_child(UiKit.wrap(UiKit.label(", ".join(sub), "Muted"), 80))
		if it and it.is_legend():   # v0.014: a legendary piece's gem, maker, kills and every carrier
			var ll := it.legend_lines()
			info.add_child(UiKit.wrap(UiKit.label("\n".join(PackedStringArray(ll.slice(0, 3) + ll.slice(maxi(3, ll.size() - 4)))), "Small"), 80))
		h.add_child(info)
		h.add_child(UiKit.button("Change", func(): _pick_item(u, slot, game, host, on_change), "", 110))
		var rm := UiKit.button("Remove", func():
			Outfit.unequip(u, slot, game.stash)
			on_change.call(), "Row", 110)
		rm.disabled = it == null
		h.add_child(rm)
		if not u.is_officer():
			h.add_child(UiKit.button("Rule", func(): _pick_override(u, slot, game, host, on_change), "Row", 90))
		v.add_child(row)
	if u.bow() != null or not u.quiver.is_empty():   # bows: the quiver (filled from the company's arrows before a battle)
		var qs := []
		for k in u.quiver:
			qs.append("%d %s" % [int(u.quiver[k]), DB.arrow_name(k) + ("s" if int(u.quiver[k]) != 1 else "")])
		v.add_child(UiKit.wrap(UiKit.label("Quiver %d/%d: %s" % [u.arrows(), DB.QUIVER_MAX, ", ".join(qs) if not qs.is_empty() else "empty"], "Muted"), 80))
	var foot := UiKit.flow(8)
	foot.add_child(UiKit.wrap(UiKit.label("Gear weight %s (%s)" % [UiWords.kg(u.gear_mass()), UiWords.load_word(u.gear_mass(), u.mass())], "H2"), 220))
	foot.add_child(UiKit.spacer())
	if not u.is_officer():
		foot.add_child(UiKit.button("Outfit from stash", func():
			var r := Outfit.outfit_unit(game.squads, u, game.stash)
			on_change.call()
			_report(host, r["missing"], r["equipped"]), "", 0))
	foot.add_child(UiKit.button("Strip to stash", func():
		Outfit.strip(u, game.stash)
		on_change.call(), "Row", 0))
	var town: Dictionary = game.world.get("towns", {}).get(game.location, {})
	var bb := UiKit.button("Buy best from local shops", func():
		var plan := Market.plan_best_for_unit(game, town, u)
		if plan["buys"].is_empty():
			UiKit.toast(host, "Nothing better here that the company can afford", false)
			return
		var names := []
		for b in plan["buys"]:
			names.append("%s (%d)" % [(b["item"] as Item).display_name(), int(b["price"])])
		UiKit.confirm(host, "Buy for %s: %s.\nTotal %d coins." %[u.name, ", ".join(names), int(plan["total"])], "Buy", func():
			var n := Market.buy_best_for_unit(game, town, u, plan)
			on_change.call()
			UiKit.toast(host, "Bought %d pieces" % n)), "Row", 0)
	bb.disabled = town.is_empty()
	if town.is_empty():
		bb.text = "Buy best (in a town only)"
	foot.add_child(bb)
	outer.add_child(foot)
	return outer

static func _report(host: Control, missing: Array, equipped: int) -> void:
	if missing.is_empty():
		UiKit.toast(host, "Outfitted: %d pieces taken from the stash" % equipped)
	else:
		UiKit.message(host, "Equipped %d pieces. Missing from the stash:" % equipped, Outfit.missing_lines(missing))

static func _pick_item(u: Unit, slot: String, game, host: Control, on_change: Callable) -> void:
	var opts := []
	for it in Outfit.stash_for_slot(game.stash, slot, u):
		opts.append({"text": it.display_name(), "value": it, "detail": UiWords.kg(it.mass()), "icon": ItemIcon.for_item(it)})
	var title := "%s for %s (from the stash)" % [UiWords.slot_name(slot), u.name]
	if slot == "off_hand" and u.weapon() and Outfit.is_two_handed(u.weapon().tid):
		title = "%s wields a two-handed %s: no shield possible" % [u.name, Outfit.template_name(u.weapon().tid)]
	UiKit.picker(host, title, opts, func(it):
		var err := Outfit.equip_item(u, it, game.stash)
		on_change.call()
		if err != "":
			UiKit.toast(host, err, false))

static func _pick_override(u: Unit, slot: String, game, host: Control, on_change: Callable) -> void:
	var opts := [{"text": "Follow the squad uniform", "value": "__clear"}, {"text": "Wear nothing here", "value": ""}]
	for tid in Outfit.templates_for_slot(slot):
		var two := " (two-handed)" if Outfit.is_two_handed(tid) else ""
		opts.append({"text": Outfit.template_name(tid) + two, "value": tid,
			"detail": UiWords.faction_name(_culture_faction(tid))})
	UiKit.picker(host, "Individual rule for %s: %s" % [u.name, UiWords.slot_name(slot)], opts, func(val):
		if val == "__clear":
			u.overrides.erase(slot)
		else:
			u.overrides[slot] = val
		var r := Outfit.outfit_unit(game.squads, u, game.stash)
		on_change.call()
		_report(host, r["missing"], r["equipped"]))

## A faction using a template's culture (for labels like "Clans of the Northern Fells").
static func _culture_faction(tid: String) -> String:
	var c: String = DB.template(tid).get("culture", "")
	for fid in DB.factions:
		if DB.factions[fid].get("culture", "") == c:
			return fid
	return "common"

# ------------------------------------------------------------------ health
static func health(u: Unit, extra: Control = null) -> Control:
	var sc := UiKit.scroll()
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var hr := HealthReport.describe(u)
	var st: String = hr.get("status", "healthy")
	var top := UiKit.flow(8)
	top.add_child(UiKit.label(u.name, "H2"))
	top.add_child(UiKit.chip(st, status_color(st)))
	var fit: String = hr.get("fitness", "")
	if fit != "":
		top.add_child(UiKit.chip(fit, UiTheme.GOOD if fit == "fit to fight" else UiTheme.WOOD_3))
	var hd := float(hr.get("heal_days", 0.0))
	if hd > 0:
		top.add_child(UiKit.label("full recovery: %s of town rest" % hr.get("recovery", "%d days" % ceili(hd)), "Muted"))
	v.add_child(top)
	for s in hr.get("summary", []):
		v.add_child(UiKit.label(String(s), "", true))
	var parts: Array = hr.get("parts", [])
	if parts.is_empty():
		v.add_child(UiKit.label("No wounds.", "Good"))
	for p in parts:
		v.add_child(part_card(p))
	if extra != null:
		v.add_child(extra)
	return sc

const SEV_COLORS := [Color("6e5236"), Color("b86e00"), Color("c0401e"), Color("8e1010")]

static func part_card(p: Dictionary) -> Control:
	var row := UiKit.panel("Card")
	var h := UiKit.hbox(12)
	row.add_child(h)
	var sev := clampi(int(p.get("severity", 0)), 0, 3)
	var n := UiKit.label(String(p.get("name", p.get("part", "?"))).capitalize(), "H2")
	n.add_theme_color_override("font_color", SEV_COLORS[sev])
	UiKit.shrink(n, 120)
	h.add_child(n)
	var lines := UiKit.label(", ".join(PackedStringArray(p.get("lines", []))), "", true)
	lines.add_theme_color_override("font_color", SEV_COLORS[sev].darkened(0.2))
	h.add_child(lines)
	var hd := float(p.get("heal_days", 0.0))
	var tail: String = "permanent" if p.get("permanent", false) and hd <= 0.0 else String(p.get("recovery", "%d days" % ceili(hd)))
	var sw: String = p.get("severity_word", "")
	if sw != "":
		tail = sw + ", " + tail
	h.add_child(UiKit.label(tail, "Muted"))
	return row
