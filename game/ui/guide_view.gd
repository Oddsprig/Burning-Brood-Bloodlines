class_name GuideView
extends RefCounted
## In-game guide: a short paged introduction shown once when a campaign begins, and from Help on the map.
const PAGES := [
	["Your house", "You lead a real household in a living feudal world. Its purse, its people, its dragons and its rights are all recorded. Everything you spend, raise or lose comes from those records, and stays consistent through battles and saves.\n\nOpen House to see your family, succession laws and accounts. Your ruler's portrait sits at the lower left of the map."],
	["The land and its people", "Every settlement has tracked business-owning families and a much larger common folk whose work, wealth and food sustain the economy. Their pooled wealth pays local taxes to their lord, who owes tribute up the feudal ladder.\n\nTap a settlement on the map to see its lord, liege, loyalty and garrison. Records opens its full census, businesses, treasury and defences."],
	["Raising an army", "Your field army starts UNRAISED. At your home settlement, open Army: fund it from your house purse, review who can leave work, what kit is available, and food and wages, then confirm the muster.\n\nTroops draw wages every day. Stand them down at home to send the same people back to work. The dead leave families poorer and the town smaller."],
	["Dragons", "Dragons and eggs belong to real people. Open Dragons to see your brood: bond an adult dragon to a rider who is present at its roost, order it to defend its home, or have it march with your army. A marching dragon eats packed meat from the army's stores once each day.\n\nEggs hatch after weeks of good care; hatchlings grow into adults within a year. A healthy female and male kept together may lay a new clutch."],
	["Court and marriage", "Open Court to see your family: ruler, spouse, heir and every member. Find a match for an unmarried adult, or arrange a betrothal for a child. Every candidate shows whether their house would accept and why; a gift from your purse helps.

The spouse joins your household with a dowry, sometimes a dragon egg. Their children are born into your house and become your heirs. Their house becomes your ally, and if they rule a town you gain a claim to it."],
	["Battle", "Battles fight themselves. Every blow is resolved through materials, armour, body parts, size and strength: wounds bleed, limbs fail, people faint, flee and die. Dragons bite, claw and breathe their gem's element (fire, frost, venom or lightning), and can burn their own side if crowded.\n\nUse pause and speed buttons, tap a fighter to inspect them, open the Combat log for every detail. The camera follows the fight; drag or zoom to take control, press C to let it follow again."],
	["War and politics", "March your raised army to a foreign settlement and tap it: Raid carries off coin and burns grain; Besiege storms its walls and, if you win, brings it into your realm. Either act turns its realm against you, and conquered towns resent you until their loyalty recovers.\n\nVassals with low loyalty and high grievance may defect to a stronger neighbour. Grants and pressure (Politics) buy loyalty with real coin."],
	["Winning", "Open Ambitions to see your house's long-term goals: bond a dragonrider, win battles, plunder, conquer, hatch an egg, grow your treasury. Achieve six to bring your dynasty to triumph. If every member of your founding line dies, the campaign is lost.\n\nSave from the map at any time; Continue on the title screen resumes. Press F3 for the performance overlay."],
]

static func open(host: Control, start_at_end: bool = false) -> void:
	var state := {"page": 0}
	var v := UiKit.modal(host, "Guide", 700)
	var title := UiKit.label("", "H2", true)
	var body := UiKit.label("", "", true)
	body.custom_minimum_size = Vector2(0, 220)
	var counter := UiKit.label("", "Muted")
	v.add_child(title); v.add_child(body)
	var footer := UiKit.hbox(8); v.add_child(footer)
	footer.add_child(counter)
	footer.add_child(UiKit.spacer())
	var back := UiKit.button("Back", func(): pass, "Row", 100)
	var next := UiKit.button("Next", func(): pass, "", 120)
	footer.add_child(back); footer.add_child(next)
	var show := func():
		var p: Array = PAGES[state["page"]]
		title.text = str(p[0]); body.text = str(p[1])
		counter.text = "%d / %d" % [int(state["page"]) + 1, PAGES.size()]
		back.disabled = int(state["page"]) == 0
		next.text = "Done" if int(state["page"]) == PAGES.size() - 1 else "Next"
	back.pressed.connect(func():
		state["page"] = maxi(0, int(state["page"]) - 1); show.call())
	next.pressed.connect(func():
		if int(state["page"]) >= PAGES.size() - 1: UiKit.close_modal(v); return
		state["page"] = int(state["page"]) + 1; show.call())
	show.call()
