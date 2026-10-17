extends "res://tests/diag_startup_slices.gd"
## Thin untouched-baseline generation reference, without any history simulation.
## STARTUP_OUTPUT required; STARTUP_SIZE=normal STARTUP_SEED=777 STARTUP_DAYS=30.
## Produces startup-timings.json/checkpoints.initial for diag_generation_slices.
## Inherited full snapshots include RNG, UIDs, fight state and dictionary order.
## Uses only existing synchronous Game.new_game; no staged-generation API calls.

func run(_tree: SceneTree) -> int:
	output = OS.get_environment("STARTUP_OUTPUT")
	check(not output.is_empty(), "STARTUP_OUTPUT is provided")
	if failures > 0: return failures
	check(not FileAccess.file_exists(output.path_join("startup-timings.json")), "atomic generation evidence is fresh")
	check(DirAccess.make_dir_recursive_absolute(output) == OK, "atomic generation output can be created")
	var size_name: String = _setting("STARTUP_SIZE", "normal")
	var seed_number: int = int(_setting("STARTUP_SEED", "777"))
	var days: int = int(_setting("STARTUP_DAYS", "30"))
	check(WorldGen.SIZES.has(size_name) and days > 0, "valid atomic generation configuration")
	if failures > 0: return failures
	WorldGen.gen_size = size_name
	var begin: int = Time.get_ticks_usec()
	Game.new_game(seed_number)
	var elapsed_us: int = Time.get_ticks_usec() - begin
	check(Game.day == 0.0 and Game.seed_value == seed_number, "atomic generation initializes the requested seed on day zero")
	check(not Game.world.is_empty() and not Game.world.get("towns", {}).is_empty(), "atomic generation initializes a populated world")
	check(Game.world.get("work", []).is_empty(), "atomic generation leaves no queued history work")
	check(Game._save_task == -1, "atomic generation starts no autosave")
	Game.world["presim"] = {"total": days, "done": 0, "from": Game.day}
	var initial: Dictionary = snapshot("initial")
	write_json("startup-timings.json", {"mode": "atomic_generation", "seed": seed_number,
		"size": size_name, "requested_days": days, "setup_seconds": elapsed_us / 1e6,
		"generation_seconds": elapsed_us / 1e6, "checkpoints": {"initial": initial}, "failures": failures,
		"measurement_note": "Untouched synchronous world generation only; no history simulation. Snapshot time excluded."})
	print("ATOMIC GENERATION size=%s seed=%d cpu=%.3fs failures=%d" % [size_name, seed_number, elapsed_us / 1e6, failures])
	return failures
