extends RefCounted
## Dev: where sickness spends its time in the real world sim (the years before: towns, families, forces, caravans).
##   tools/test.sh tests/diag_sickness_prof.gd   (DAYS=n, default 240)

func run(_tree: SceneTree) -> int:
	var days := int(OS.get_environment("DAYS")) if OS.get_environment("DAYS") != "" else 240
	Game.new_game(2026)
	Sickness.prof_on = true
	Sickness.prof = {}
	Sickness.us = 0
	var t0 := Time.get_ticks_msec()
	CampaignWorld.presim_step(Game, days)
	var ms := Time.get_ticks_msec() - t0
	Sickness.prof_on = false
	var pk := []
	for k in Sickness.prof:
		pk.append("%s %.3f" % [k, Sickness.prof[k] / float(days) / 1000.0])
	print("  %d days in %.1f s; sickness %.2f ms a day; by part (ms a day): %s" % [days, ms / 1000.0, Sickness.us / float(days) / 1000.0, ", ".join(PackedStringArray(pk))])
	return 0
