extends Node
## Root scene: hosts one screen at a time. Screens are switched with Game.goto("name").

var current: Node = null
var performance_panel: PerformancePanel

## v0.014 (Douglas: "pretty long loading screen between menus"): the big screens' scenes (and the scripts behind
## them) load once per run, in the background while the title shows, and are kept here. Loaded on first use they
## cost 0.2-0.7 s each (town 0.5 s, records 0.7 s), and an unkept scene was read from disk again on every switch.
## v0.072: the battle screen warms too (its script and preloaded layers compiled on a worker thread, not as a hitch on
## the first battle). Only scene/script files: no art or audio is loaded upfront.
const WARM := ["res://campaign/world_map.tscn", "res://battle/battle.tscn", "res://ui/town.tscn", "res://ui/company.tscn", "res://ui/muster.tscn", "res://ui/records.tscn", "res://ui/house_select.tscn", "res://ui/house.tscn", "res://ui/house_laws.tscn", "res://ui/politics.tscn", "res://ui/population.tscn"]
var _scenes := {}     # path -> PackedScene
var _warming := {}    # path -> true while its background load is running

func _ready() -> void:
	Game.main = self
	var diagnostics := CanvasLayer.new()
	diagnostics.layer = 100
	add_child(diagnostics)
	performance_panel = PerformancePanel.new()
	performance_panel.setup(Perf)
	diagnostics.add_child(performance_panel)
	performance_panel.visible = bool(Game.setting("show_performance"))
	Game.setting_changed.connect(func(key: String, value: Variant):
		if key == "show_performance": performance_panel.visible = bool(value))
	var save_layer := CanvasLayer.new()
	save_layer.layer = 101
	add_child(save_layer)
	save_layer.add_child(SaveIndicator.new())
	if DisplayServer.get_name() != "headless":
		var icon_tex := load("res://icon_claude.png") as Texture2D
		DisplayServer.set_icon(icon_tex.get_image() if icon_tex != null else GameIcon.make_icon_image(256))
	get_window().title = "Burning Brood: Bloodlines - Claude Edition (v%s)" % String(ProjectSettings.get_setting("application/config/version", "?"))
	Game.goto("title")
	for p in WARM:
		if ResourceLoader.exists(p) and ResourceLoader.load_threaded_request(p) == OK:
			_warming[p] = true

func _scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	var ps: PackedScene = null
	if _warming.has(path):
		_warming.erase(path)
		ps = ResourceLoader.load_threaded_get(path) as PackedScene   # waits if the background load is not done yet
	if ps == null:
		ps = load(path) as PackedScene
	_scenes[path] = ps
	return ps

func show_screen(path: String) -> void:
	var started := Time.get_ticks_usec()
	if current != null:
		current.queue_free()
		current = null
	if not ResourceLoader.exists(path):
		push_error("Missing screen: " + path)
		var l := Label.new()
		l.text = "Screen not built yet: " + path
		current = l
		add_child(l)
		return
	current = _scene(path).instantiate()
	add_child(current)
	Perf.record_us("Open screen", Time.get_ticks_usec() - started)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		Game.set_setting("show_performance", not bool(Game.setting("show_performance")))
		get_viewport().set_input_as_handled()

## Collects background loads nobody asked for (quitting from the title), so none is left running.
func _exit_tree() -> void:
	DragonArt.finish_warm()
	for p in _warming:
		ResourceLoader.load_threaded_get(p)
	_warming.clear()
