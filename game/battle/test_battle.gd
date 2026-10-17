extends Node
## Developer entry: launch res://battle/test_battle.tscn directly. Builds a random battle (new company vs an
## orc warband) and runs the battle screen; acts as a tiny stand-in for main.gd so finish_battle ->
## aftermath -> Continue (world map) works. A screen path that does not exist starts another random battle.
## User args (after `--`):
##   --enemies=N   enemy count (default 10; >20 gives the 2x2-screen map)
##   --faction=ID  enemy faction (default orc_horde)
##   --seed=N      battle seed
##   --terrain=T   battle terrain (grassland, forest, hills, silverwood, badlands, mountains)
##   --choke=M     chokepoint map: corridor1 | corridor2 (enemy streams in)
##   --demo        scripted "taps" for screenshots: opens the inspector, expands a log entry, shows health
##   --speed=X     playback speed (1, 2, 4)

var current: Node = null
var args := {}
var battles := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Game.main = self
	_new_battle()

func _new_battle() -> void:
	var s := int(args.get("seed", str(7 + battles)))
	battles += 1
	Game.new_game(1000 + s)
	var rng := RandomNumberGenerator.new(); rng.seed = s
	var enemies := Factory.make_warband(rng, args.get("faction", "orc_horde"), int(args.get("enemies", "10")))
	Game.pending_battle = {"enemy": enemies, "allies": [], "seed": s, "terrain": args.get("terrain", "grassland")}
	if args.has("choke"):
		Game.pending_battle["choke"] = args["choke"]
		Game.pending_battle["stream"] = true
	show_screen("res://battle/battle.tscn")
	if args.has("speed"):
		current.set_speed(float(args["speed"]))
	if args.has("demo"):
		_demo()
	if args.has("auto"):
		_auto_continue()

## --auto: press Continue 1.5 s after the result appears (for capturing the aftermath screen).
func _auto_continue() -> void:
	var b := current
	while is_instance_valid(b) and b == current and not b.result_shown:
		await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(b) and b == current:
		b.finish()

func show_screen(path: String) -> void:
	if current != null:
		current.queue_free()
		current = null
	if not ResourceLoader.exists(path):
		print("test_battle: '%s' not built here; starting another battle" % path)
		_new_battle.call_deferred()
		return
	current = (load(path) as PackedScene).instantiate()
	add_child(current)

func _demo() -> void:
	var b := current
	await get_tree().create_timer(3.5).timeout
	if b != current or not is_instance_valid(b):
		return
	# tap the player unit closest to the enemy line
	var best := -1
	var bx := -1.0
	for f in b.sim.fighters:
		if f.side == 0 and f.alive() and f.cell.x > bx:
			bx = f.cell.x
			best = f.idx
	if best >= 0:
		b.tap_screen(b.screen_pos_of(best))
		await get_tree().create_timer(2.5).timeout
		if is_instance_valid(b) and b.inspector.visible:
			b.inspector.expand_entry(maxi(0, b.inspector.log_box.get_child_count() - 2))
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(b) and b.inspector.visible:
			b.inspector.show_tab("health")
