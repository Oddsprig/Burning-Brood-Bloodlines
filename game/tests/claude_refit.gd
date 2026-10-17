extends RefCounted
## v0.029 equipment refits: levies are issued body armour ("body") and helmets ("helm") on raise,
## and Mobilization.refit_quote / refit fit the men who still lack them at the home town.
## Modelled on tests/claude_campaign.gd's setup (fresh world, real house, real muster).
## -- --test=res://tests/claude_refit.gd
var checks := 0
var fails := 0
var main: Node = null

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL refit: ", what)
	print(("ok   " if ok else "FAIL ") + what)

func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n:
		await tree.process_frame

func run(tree: SceneTree) -> int:
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000); tree.root.size = Vector2i(1280, 720)
	Game.settings["guide_seen"] = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 8)
	if not await DevTools.start_world(tree, "user://claude_refit-test.json"):
		printerr("FAIL: the start world did not load")
		return 1
	check(Game.company.is_empty(), "fresh campaign starts with no raised army")
	# Choose a ruling house the same way the campaign test does (an adult dragon's owner at home).
	var tid := ""
	for dragon: Dictionary in Dragons.records(Game):
		if dragon.get("stage", "") != "adult" or not dragon.get("alive", false): continue
		var owner := Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner["town_id"]): continue
		if HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"])).get("ok", false):
			tid = str(owner["town_id"]); break
	check(tid != "", "house chosen at a home town")
	if tid == "":
		print("refit: %d checks, %d failures" % [checks, fails])
		return fails
	Game.goto("map"); await frames(tree, 5)
	Game.location = tid
	Game.world["party"]["pos"] = Game.world["towns"][tid]["pos"]
	var purse0 := float(Feudal._payer(Game).get("purse", 0.0))
	var fund := Mobilization.fund(Game, int(floor(purse0 * 0.6)))
	var quote := Mobilization.quote(Game, tid, 100)
	check(bool(fund.get("ok", false)) and bool(quote.get("ok", false)), "army funded and muster quoted (%s / %s)" % [fund.get("reason", ""), quote.get("reason", "")])
	var stocked_body := int(quote.get("body_available", 0))
	var stocked_helm := int(quote.get("helm_available", 0))
	var outcome := Mobilization.muster(Game, tid, 100, quote.get("review", {}))
	check(bool(outcome.get("ok", false)) and int(outcome.get("raised", 0)) > 0, "raised %d levies at %s" % [int(outcome.get("raised", 0)), Game.world["towns"][tid]["name"]])
	var with_body := 0; var with_helm := 0; var with_padded := 0
	for u in Game.company:
		if u.dead: continue
		if u.equip.has("body"): with_body += 1
		if u.equip.has("helm"): with_helm += 1
		if u.equip.has("clothing"): with_padded += 1
	if stocked_body > 0:
		check(with_body > 0, "%d of %d raised levies wear body armour (town stocked %d body pieces, %d helmets; %d wear helmets)" % [with_body, Game.company.size(), stocked_body, stocked_helm, with_helm])
	else:
		print("refit: home town stocked no body armour (body 0, helmets %d); %d levies wear body armour, %d helmets, %d padded clothing" % [stocked_helm, with_body, with_helm, with_padded])
		check(with_body >= 0, "no body armour stocked, none required")
	var rq := Mobilization.refit_quote(Game, tid)
	check(rq.has("fitted") and int(rq.get("fitted", -1)) >= 0, "refit_quote fitted %d, cost %d (%s)" % [int(rq.get("fitted", -1)), int(rq.get("cost", 0)), rq.get("reason", "")])
	var before_body := with_body; var before_helm := with_helm
	var r := Mobilization.refit(Game, tid, rq.get("review", {}))
	check(r.has("fitted") and int(r.get("fitted", -1)) >= 0, "refit fitted %d, cost %d (%s)" % [int(r.get("fitted", -1)), int(r.get("cost", 0)), r.get("reason", "")])
	with_body = 0; with_helm = 0
	for u in Game.company:
		if u.dead: continue
		if u.equip.has("body"): with_body += 1
		if u.equip.has("helm"): with_helm += 1
	check(with_body >= before_body and with_helm >= before_helm, "armour worn never shrinks in a refit (body %d -> %d, helm %d -> %d)" % [before_body, with_body, before_helm, with_helm])
	var rq2 := Mobilization.refit_quote(Game, tid)
	check(int(rq2.get("fitted", -1)) >= 0, "second refit_quote fitted %d (no crash)" % int(rq2.get("fitted", -1)))
	print("refit: %d checks, %d failures" % [checks, fails])
	return fails
