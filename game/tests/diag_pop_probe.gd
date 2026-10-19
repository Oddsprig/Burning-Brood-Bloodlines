extends RefCounted
## Diagnostic only: loads the real-tick yearly saves written by diag_economy_years.gd and prints
## population, births/deaths, harvest and the coin ledger, to check whether the fast economy sim's
## population crash also happens under the real daily tick.
func run(tree: SceneTree) -> int:
	var old: String = Game.SAVE_PATH
	for n in [1, 2, 3, 4, 5, 6, 12]:
		Game.SAVE_PATH = (OS.get_environment("PROBE_DIR") if OS.get_environment("PROBE_DIR") != "" else "user://econ_years") + "/year_%d.save" % n
		if not Game.load_game():
			print("PROBE year=%d missing" % n); continue
		var pop: int = 0; var births: int = 0; var deaths: int = 0; var made: int = 0
		for town: Dictionary in Game.world.get("towns", {}).values():
			if not TownEcon.has_econ(town): continue
			var e: Dictionary = town["econ"]
			births += int(e.get("census", {}).get("bt", 0)); deaths += int(e.get("census", {}).get("dt", 0))
			for f: Dictionary in e.get("fams", []):
				if not f.get("gone", false) and not f.has("estate"): pop += Families.people(f)
			for crop in e.get("land", {}): made += int(e.get("led", {}).get("made", {}).get(crop, 0))
		var coin: Dictionary = Game.world.get("coin", {})
		print("PROBE year=%d day=%d population=%d births_total=%d deaths_total=%d harvest_made_total=%d cast=%.0f melted=%.0f drained=%.0f holdings=%.0f" % [
			n, int(Game.day), pop, births, deaths, made, float(coin.get("cast", 0)), float(coin.get("melted", 0)), float(coin.get("drained", 0)), Barge.holdings(Game)])
		await tree.process_frame
	Game.SAVE_PATH = old
	return 0
