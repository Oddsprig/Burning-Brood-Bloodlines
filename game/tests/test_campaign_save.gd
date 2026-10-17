extends RefCounted
## Save/load round-trip with a full campaign world: towns (crafters, shop Items, recruit Units),
## warbands, party, active contract; int fields restored; time keeps flowing after load.

func _fp(w: Dictionary) -> String:
	var parts := [str((w["terrain"] as String).hash()), str(w["party"]["pos"]), str(w["next_id"])]
	var ids: Array = w["towns"].keys(); ids.sort()
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		parts.append("%s %s %d %d %s %d" % [t["name"], str(t["pos"]), t["size"], t["wealth"], t["crafters"]["armorsmith"]["name"], t["crafters"]["armorsmith"]["skill"]])
		for it in t["shop"]:
			parts.append("%s/%s/%d" % [it.tid, it.material, it.quality])
		for r in t["recruits"]:
			parts.append("%s %s %d %d" % [r.name, r.title, r.wage, r.hire_cost])
		for c in t["contracts"]:
			parts.append("%s %d" % [c["id"], c["pay"]])
	var wids: Array = w["warbands"].keys(); wids.sort()
	for wid in wids:
		var wb: Dictionary = w["warbands"][wid]
		parts.append("%s %s %s %d" % [wid, wb["faction"], str(wb["pos"].round()), wb["units"].size()])
	return "\n".join(parts)

func run(_tree: SceneTree) -> int:
	var fails := 0
	Game.new_game(4242)
	for i in 40:
		Game.advance_time(0.05, false)
	# take any contract on offer
	for tid in Game.world["towns"]:
		for c in Game.world["towns"][tid]["contracts"]:
			if Game.contract.is_empty():
				Contracts.accept(Game, c)
	var before := _fp(Game.world)
	var cid: String = Game.contract.get("id", "")
	var day: float = Game.day
	Game.save_game()
	Game.world = {}
	Game.contract = {}
	if not Game.load_game():
		print("FAIL: load"); return 1
	var w: Dictionary = Game.world
	var after := _fp(w)
	if before != after:
		print("FAIL: world differs after load")
		var a := before.split("\n"); var b := after.split("\n")
		for i in mini(a.size(), b.size()):
			if a[i] != b[i]:
				print("  first diff: ", a[i], " | ", b[i]); break
		fails += 1
	if Game.contract.get("id", "") != cid or absf(Game.day - day) > 0.0001:
		print("FAIL: contract/day not restored"); fails += 1
	var t: Dictionary = w["towns"].values()[0]
	if typeof(t["size"]) != TYPE_INT or typeof(t["crafters"]["weaponsmith"]["skill"]) != TYPE_INT:
		print("FAIL: int fields came back as ", typeof(t["size"])); fails += 1
	if not (t["shop"][0] is Item) or not (t["recruits"][0] is Unit) or not (w["party"]["pos"] is Vector2):
		print("FAIL: typed values not restored"); fails += 1
	if t["recruits"][0].backstory == "":
		print("FAIL: recruit backstory lost"); fails += 1
	# the world keeps running after load
	var town: Dictionary = w["towns"][w["start_town"]]
	CampaignWorld.set_travel(Game, town["pos"], town["id"])
	for i in 60:
		Game.advance_time(0.05, false)
	print("after load + 3 days: day %.2f, %d warbands, party at %s" % [Game.day, w["warbands"].size(), str(w["party"]["pos"])])
	return fails
