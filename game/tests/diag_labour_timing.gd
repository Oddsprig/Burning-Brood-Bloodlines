extends RefCounted

func counts(e: Dictionary) -> Array:
	var idle := 0; var listed := 0; var actual := 0
	for f in e["fams"]:
		if not f.get("gone", false) and not f.get("estate", false): idle += int(f.get("idle", 0))
	for bid in e.get("open", []): listed += Businesses.takeable(e["biz"][int(bid)])
	for b in e["biz"]: actual += Businesses.takeable(b)
	return [idle, listed, actual]

func run(_tree: SceneTree) -> int:
	Game.new_game(2026)
	CampaignWorld.presim_step(Game, 60)
	for t in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		var c := counts(e)
		if mini(int(c[0]), int(c[2])) <= 10: continue
		print("LABOUR day60 ", t["id"], " idle/listed/actual ", c, " cache ", e.get("open_n", -1))
		for f in e["fams"]:
			if not f.get("gone", false) and not f.get("estate", false) and int(f.get("idle", 0)) > 0:
				print("IDLE fid=", f["id"], " n=", f["idle"], " last=", f["last"], " ad=", Families.adults(f), " serving=", Families.serving(f), " jobs=", f["jobs"], " cj=", f.get("cj", {}))
		for b in e["biz"]:
			if Businesses.takeable(b) > 0 and not e.get("open", []).has(int(b["id"])): print("MISSING ", b["id"], " ", b["type"], " places=", Businesses.takeable(b))
		for refresh in [false, true]:
			var copy: Dictionary = e.duplicate(true)
			if refresh: Businesses.rebuild_open(copy)
			for f in copy["fams"]:
				if not f.get("gone", false) and int(f.get("idle", 0)) > 0: Families.reassign(copy, f)
			print("IDLE ONLY refresh=", refresh, " counts=", counts(copy))
	for d in 8:
		CampaignWorld.presim_step(Game, 1)
		var worst := 0; var detail := []
		for t in Game.world["towns"].values():
			if not TownEcon.has_econ(t): continue
			var c := counts(t["econ"])
			var pair := mini(int(c[0]), int(c[2]))
			if pair > worst: worst = pair; detail = [t["id"], c]
		print("FOLLOW ", Game.day, " worst=", worst, " ", detail)
	return 0
