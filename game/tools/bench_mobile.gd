extends SceneTree
## Headless phone benchmark launcher (v0.072). Measures a 100v100 battle and the campaign map, N frames each:
##   godot --headless --path game --script res://tools/bench_mobile.gd -- [--frames=600] [--mobile-profile]
## Same run as a scene:  godot --headless --path game res://tools/bench_mobile.tscn -- [options]
## Options (all optional): --frames=N (per benchmark, default 600)  --warmup=N (default 30)  --speed=1|2|4 (battle)
##   --map-speed=1|2|4  --per-side=N (default 100)  --only=battle|map  --mobile-profile (phone settings on a PC)
## Autoloads (DB, Game, Perf) are added before _initialize but after this script compiled, so this launcher names
## none of them: it only opens the bench scene, whose script compiles once the autoloads exist.

func _initialize() -> void:
	if root.get_node_or_null("Game") == null:
		printerr("bench_mobile: autoloads are missing; run the scene instead: godot --headless --path game res://tools/bench_mobile.tscn")
		quit(2)
		return
	change_scene_to_file("res://tools/bench_mobile.tscn")
