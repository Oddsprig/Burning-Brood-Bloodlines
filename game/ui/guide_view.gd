class_name GuideView
extends RefCounted
## In-game guide: a short paged introduction shown once when a campaign begins, and from Help on the map.
## v0.096: each page is a one-line lead and a few short points (the same facts as before), not two dense paragraphs.
## [title, lead, [points]]
const PAGES := [
	["Your house", "You lead a real household in a living feudal world.", [
		"Its purse, people, dragons and rights are all recorded.",
		"Everything you spend, raise or lose comes from those records and stays consistent through battles and saves.",
		"Open House for your family, succession laws and accounts.",
		"Your ruler's portrait sits at the lower left of the map."]],
	["The land and its people", "Every settlement has a few tracked business-owning families and a much larger common folk.", [
		"Their work, wealth and food keep the economy running.",
		"Their pooled wealth pays local taxes to their lord, who owes tribute up the feudal ladder.",
		"Tap a settlement on the map for its lord, liege, loyalty and garrison.",
		"Records opens its census, businesses, treasury and defences."]],
	["Raising an army", "Your field army starts UNRAISED.", [
		"At your home settlement, open Army and fund it from your house purse.",
		"Review who can leave work, what kit is available, food and wages, then confirm the muster.",
		"Troops draw wages every day. Stand them down at home to send the same people back to work.",
		"The dead leave families poorer and the town smaller."]],
	["Dragons", "Dragons and eggs belong to real people. Open Dragons to see your brood.", [
		"Bond an adult dragon to a rider who is present at its roost, or let an adult of the owning household approach an unbonded dragon.",
		"Familiarity grows once each day they stay with it: faster for its keeper, slower if it is hungry or hurt.",
		"The dragon then accepts the bond, or refuses for about a month.",
		"Order it to defend its home, or have it march with your army. A marching dragon eats packed meat from the army's stores each day.",
		"Eggs hatch after weeks of good care; hatchlings grow into adults within a year.",
		"A healthy female and male kept together may lay a new clutch."]],
	["Court and marriage", "Open Court to see your ruler, spouse, heir and every family member.", [
		"Find a match for an unmarried adult, or arrange a betrothal for a child.",
		"Every candidate shows whether their house would accept and why; a gift from your purse helps.",
		"The spouse joins your household with a dowry, sometimes a dragon egg.",
		"Their children are born into your house and become your heirs.",
		"Their house becomes your ally, and if they rule a town you gain a claim to it."]],
	["Battle", "Battles fight themselves.", [
		"Every blow is resolved through materials, armour, body parts, size and strength: wounds bleed, limbs fail, people faint, flee and die.",
		"Dragons bite, claw and breathe their gem's element (fire, frost, venom or lightning), and can burn their own side if crowded.",
		"Use the pause and speed buttons. Tap a fighter to inspect them; open the Combat log for every detail.",
		"The camera follows the fight. Drag or zoom to take control; press C to let it follow again."]],
	["War and politics", "March your raised army to a foreign settlement and tap it.", [
		"Raid carries off coin and burns grain.",
		"Besiege storms its walls and, if you win, brings it into your realm.",
		"Either act turns its realm against you, and conquered towns resent you until their loyalty recovers.",
		"Vassals with low loyalty and high grievance may defect to a stronger neighbour.",
		"Grants and pressure (Politics) buy loyalty with real coin."]],
	["Winning", "Open Ambitions to see your house's long-term goals. Achieve six to bring your dynasty to triumph.", [
		"Goals: bond a dragonrider, win battles, plunder, conquer, hatch an egg, grow your treasury.",
		"If every member of your founding line dies, the campaign is lost.",
		"Save from the map at any time; Continue on the title screen resumes.",
		"Press F3 for the performance overlay."]],
]

## The page as plain text (lead, then one point per line), for tooltips and checks.
static func page_text(i: int) -> String:
	var p: Array = PAGES[clampi(i, 0, PAGES.size() - 1)]
	var lines: Array[String] = [String(p[1])]
	for point in p[2]: lines.append("•  " + String(point))
	return "\n".join(lines)

static func open(host: Control, start_at_end: bool = false) -> void:
	var state := {"page": 0}
	var v := UiKit.modal(host, "Guide", 700)
	var title := UiKit.label("", "H2", true)
	var lead := UiKit.label("", "Lead", true)
	var points := UiKit.vbox(6)
	points.custom_minimum_size = Vector2(0, 250)
	var counter := UiKit.label("", "Muted")
	v.add_child(title); v.add_child(lead); v.add_child(points)
	var footer := UiKit.hbox(8); v.add_child(footer)
	footer.add_child(counter)
	footer.add_child(UiKit.spacer())
	var back := UiKit.button("Back", func(): pass, "Row", 100)
	var next := UiKit.button("Next", func(): pass, "", 120)
	footer.add_child(back); footer.add_child(next)
	var show := func():
		var p: Array = PAGES[state["page"]]
		title.text = str(p[0]); lead.text = str(p[1])
		UiKit.clear(points)
		for point in p[2]:
			var row := UiKit.hbox(10)
			var dot := UiKit.label("•", "H2")
			dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(dot)
			row.add_child(UiKit.wrap(UiKit.label(String(point), "", true), 120))
			points.add_child(row)
		counter.text = "%d / %d" % [int(state["page"]) + 1, PAGES.size()]
		back.disabled = int(state["page"]) == 0
		next.text = "Done" if int(state["page"]) == PAGES.size() - 1 else "Next"
	back.pressed.connect(func():
		state["page"] = maxi(0, int(state["page"]) - 1); show.call())
	next.pressed.connect(func():
		if int(state["page"]) >= PAGES.size() - 1: UiKit.close_modal(v); return
		state["page"] = int(state["page"]) + 1; show.call())
	show.call()
