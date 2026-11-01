extends Node
## Autoload "Sound": music per screen (cross-faded), battle ambience, pooled sound effects and button clicks.
## Recorded CC0 audio (see audio/CREDITS.txt). Volumes live in Settings (Music volume, Sound effects).
const MUSIC := {"title": "res://audio/music_title.ogg", "map": "res://audio/music_map.ogg", "battle": "res://audio/music_battle.ogg"}
const SCREEN_MUSIC := {"title": "title", "newgame": "title", "presim": "title", "battle": "battle", "victory": "title", "gameover": "title"}
const POOL := 12
var _music: Array[AudioStreamPlayer] = []
var _active := 0
var _current := ""
var _ambience: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _cache: Dictionary = {}
var _recent: Dictionary = {}   # name -> last play msec (rate limit)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var m := AudioStreamPlayer.new(); m.bus = "Music"; m.volume_db = -80.0
		add_child(m); _music.append(m)
	_ambience = AudioStreamPlayer.new(); _ambience.volume_db = -80.0; add_child(_ambience)
	for i in POOL:
		var p := AudioStreamPlayer.new(); add_child(p); _pool.append(p)
	Game.setting_changed.connect(func(key: String, _v: Variant):
		if key in ["music_volume", "sfx_volume"]: _apply_volumes())
	get_tree().node_added.connect(_on_node_added)

func _vol(key: String) -> float:
	return clampf(float(Game.setting(key)), 0.0, 1.0)

func _db(linear: float) -> float:
	return linear_to_db(maxf(0.0001, linear))

func _apply_volumes() -> void:
	if _ambience.playing: _ambience.volume_db = _db(_vol("sfx_volume") * 0.35)

func _stream(path: String) -> AudioStream:
	if _cache.has(path): return _cache[path]
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = path.contains("/music_")
	_cache[path] = s
	return s

func _on_screen(screen: String) -> void:
	if MusicManager != null:
		MusicManager._on_screen_changed(screen)

func play_music(key: String) -> void:
	if MusicManager != null:
		MusicManager.play_scene(key)
		return

## Plays res://audio/<name>.wav. volume 0..1 (x the SFX setting), pitch jitter, rate limited per name.
func sfx(name: String, volume: float = 1.0, pitch_jitter: float = 0.06, min_gap_ms: int = 40) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_recent.get(name, -100000)) < min_gap_ms: return
	_recent[name] = now
	var stream := _stream("res://audio/%s.ogg" % name)
	if stream == null: return
	var p := _pool[_next]; _next = (_next + 1) % POOL
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = _db(volume * _vol("sfx_volume"))
	p.play()

func pick(prefix: String, count: int) -> String:
	return "%s_%d" % [prefix, randi() % count]

func _on_node_added(node: Node) -> void:
	# Readability guard for the dark theme: older screens tint text with colours chosen for a light
	# parchment theme (dark red, dark green). Any label tinted below 4.5:1 contrast is lifted once.
	if node is Label or node is RichTextLabel:
		_fix_contrast.call_deferred(node)

func _fix_contrast(node: Control) -> void:
	if not is_instance_valid(node) or node.has_meta("keep_color"): return
	var key := "font_color" if node is Label else "default_color"
	if not node.has_theme_color_override(key): return
	var c: Color = node.get_theme_color(key)
	if c.a < 0.5: return
	var fixed := UiTheme.readable(c, UiTheme.WOOD_3)
	if fixed != c: node.add_theme_color_override(key, fixed)
