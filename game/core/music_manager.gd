extends Node
## Autoload "MusicManager": scene-based background music with track rotation,
## non-repeating shuffle, ~1.5s crossfade on scene change, and "Music" bus volume control.

const BUS_NAME := "Music"
const CROSSFADE_DURATION := 1.5

const SCENE_TRACKS := {
	"menu": [
		"res://audio/throne_of_the_sleeping_dynasty.ogg",
	],
	"campaign_map": [
		"res://audio/pastoral_paths_a_minor.ogg",
		"res://audio/where_the_map_ends.ogg",
		"res://audio/medieval_fantasy_exploration.ogg",
	],
	"court": [
		"res://audio/shadows_on_the_ramparts.ogg",
		"res://audio/at_the_castle_gates.ogg",
	],
	"battle": [
		"res://audio/clash_of_iron.ogg",
	],
	"dragon_attack": [
		"res://audio/iron_wings_descending.ogg",
	],
	"siege": [
		"res://audio/relentless_siege.ogg",
	],
	"victory": [
		"res://audio/crown_of_gilded_brass.ogg",
	],
	"defeat": [
		"res://audio/vesper_for_the_unclaimed.ogg",
	],
}

const SCREEN_SCENE_MAP := {
	"menu": "menu",
	"title": "menu",
	"newgame": "menu",
	"presim": "menu",
	"house_select": "menu",
	"res://ui/title.tscn": "menu",
	"res://ui/newgame.tscn": "menu",
	"res://ui/presim.tscn": "menu",
	"res://ui/house_select.tscn": "menu",
	"campaign_map": "campaign_map",
	"campaign map": "campaign_map",
	"map": "campaign_map",
	"world_map": "campaign_map",
	"town": "campaign_map",
	"company": "campaign_map",
	"muster": "campaign_map",
	"dragons": "campaign_map",
	"population": "campaign_map",
	"records": "campaign_map",
	"baggage": "campaign_map",
	"relations": "campaign_map",
	"res://campaign/world_map.tscn": "campaign_map",
	"res://ui/town.tscn": "campaign_map",
	"res://ui/company.tscn": "campaign_map",
	"res://ui/muster.tscn": "campaign_map",
	"res://ui/dragons.tscn": "campaign_map",
	"res://ui/population.tscn": "campaign_map",
	"res://ui/records.tscn": "campaign_map",
	"res://ui/baggage.tscn": "campaign_map",
	"res://ui/relations.tscn": "campaign_map",
	"court": "court",
	"house": "court",
	"laws": "court",
	"politics": "court",
	"treasure": "court",
	"res://ui/court.tscn": "court",
	"res://ui/house.tscn": "court",
	"res://ui/laws.tscn": "court",
	"res://ui/politics.tscn": "court",
	"res://ui/treasure.tscn": "court",
	"battle": "battle",
	"res://battle/battle.tscn": "battle",
	"dragon_attack": "dragon_attack",
	"dragon attack": "dragon_attack",
	"siege": "siege",
	"victory": "victory",
	"res://ui/victory.tscn": "victory",
	"defeat": "defeat",
	"gameover": "defeat",
	"game_over": "defeat",
	"res://ui/gameover.tscn": "defeat",
}

var current_scene: String = ""
var current_track: String = ""

var _players: Array[AudioStreamPlayer] = []
var _active_idx: int = 0
var _crossfading: bool = false
var _fade_tween: Tween = null
var _last_pos: float = 0.0

var _stream_cache: Dictionary = {}
var _queue_by_scene: Dictionary = {}
var _last_track_by_scene: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "MusicPlayer_%d" % i
		p.bus = BUS_NAME
		p.volume_db = -80.0
		p.finished.connect(_on_player_finished.bind(i))
		add_child(p)
		_players.append(p)
	if Game != null:
		Game.screen_changed.connect(_on_screen_changed)
		Game.setting_changed.connect(_on_setting_changed)
		apply_volume(float(Game.setting("music_volume")))
	else:
		apply_volume(0.5)
	play_scene("menu")

func _process(_delta: float) -> void:
	if _players.is_empty():
		return
	var p := active_player()
	if p == null or not p.playing or _crossfading:
		return
	var tracks: Array = SCENE_TRACKS.get(current_scene, [])
	if tracks.size() <= 1:
		return
	var pos := p.get_playback_position()
	if _last_pos > 1.0 and pos + 0.5 < _last_pos:
		_last_pos = 0.0
		next_track()
	else:
		_last_pos = pos

func _ensure_bus() -> int:
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.set_bus_send(idx, "Master")
	return idx

func get_bus_index() -> int:
	return _ensure_bus()

func active_player() -> AudioStreamPlayer:
	if _players.is_empty():
		return null
	return _players[_active_idx]

func inactive_player() -> AudioStreamPlayer:
	if _players.size() < 2:
		return null
	return _players[1 - _active_idx]

func is_crossfading() -> bool:
	return _crossfading

func get_current_scene() -> String:
	return current_scene

func get_current_track() -> String:
	return current_track

func normalize_scene(scene_name: String) -> String:
	var key := scene_name.strip_edges().to_lower()
	if key == "" or key == "settings" or key == "res://ui/settings.tscn":
		return current_scene if current_scene != "" else "menu"
	if key == "aftermath" or key == "res://battle/aftermath.tscn":
		var winner := int(Game.last_result.get("winner", -1)) if Game != null else -1
		return "victory" if winner == 0 else "defeat"
	if SCREEN_SCENE_MAP.has(key):
		return SCREEN_SCENE_MAP[key]
	var snake := key.replace(" ", "_")
	if SCENE_TRACKS.has(snake):
		return snake
	if SCREEN_SCENE_MAP.has(snake):
		return SCREEN_SCENE_MAP[snake]
	return ""

func tracks_for_scene(scene_name: String) -> Array:
	var canonical := normalize_scene(scene_name)
	if not SCENE_TRACKS.has(canonical):
		return []
	return (SCENE_TRACKS[canonical] as Array).duplicate()

func battle_scene_for(params: Dictionary = {}, side0: Array = [], side1: Array = []) -> String:
	var pb := params
	if pb.is_empty() and Game != null:
		pb = Game.pending_battle
	var assault: Dictionary = pb.get("assault", {}) if pb.get("assault") is Dictionary else {}
	var kind := str(assault.get("kind", pb.get("kind", ""))).to_lower()
	if kind == "siege" or bool(pb.get("siege", false)) or str(pb.get("terrain", "")).to_lower() == "siege":
		return "siege"
	if has_dragon_in_battle(pb, side0, side1):
		return "dragon_attack"
	return "battle"

func has_dragon_in_battle(pb: Dictionary = {}, side0: Array = [], side1: Array = []) -> bool:
	if bool(pb.get("dragon_attack", false)):
		return true
	var d_units = pb.get("dragon_units", [])
	if d_units is Array and not (d_units as Array).is_empty():
		return true
	for group in [side0, side1, pb.get("side0", []), pb.get("side1", [])]:
		if not (group is Array):
			continue
		for u in group:
			if u == null:
				continue
			if u is Dictionary:
				if str(u.get("type_id", "")) == "dragon" or not (u.get("dragon", {}) as Dictionary).is_empty():
					return true
			elif u is Object:
				if str(u.get("type_id")) == "dragon":
					return true
				var d = u.get("dragon")
				if d is Dictionary and not (d as Dictionary).is_empty():
					return true
	return false

func play_battle(params: Dictionary = {}, side0: Array = [], side1: Array = []) -> void:
	play_scene(battle_scene_for(params, side0, side1))

func play_scene(scene_name: String, force: bool = false) -> void:
	var canonical := normalize_scene(scene_name)
	if canonical == "" or not SCENE_TRACKS.has(canonical):
		return
	var cur := active_player()
	if not force and canonical == current_scene and cur != null and cur.playing and cur.stream != null:
		return
	var next_path := pick_next_track(canonical)
	if next_path == "":
		return
	current_scene = canonical
	current_track = next_path
	_start_crossfade(next_path)

func pick_next_track(scene_name: String) -> String:
	var canonical := normalize_scene(scene_name)
	if not SCENE_TRACKS.has(canonical):
		return ""
	var tracks: Array = SCENE_TRACKS[canonical]
	if tracks.is_empty():
		return ""
	if tracks.size() == 1:
		var only := str(tracks[0])
		_last_track_by_scene[canonical] = only
		return only
	var last_played := str(_last_track_by_scene.get(canonical, ""))
	var queue: Array = _queue_by_scene.get(canonical, [])
	if queue.is_empty():
		queue = _build_shuffled_bag(tracks, last_played)
	var chosen := str(queue.pop_front())
	if chosen == last_played and tracks.size() > 1:
		queue = _build_shuffled_bag(tracks, last_played)
		chosen = str(queue.pop_front())
	_queue_by_scene[canonical] = queue
	_last_track_by_scene[canonical] = chosen
	return chosen

func _build_shuffled_bag(tracks: Array, last_played: String) -> Array:
	var bag: Array = tracks.duplicate()
	for i in range(bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = bag[i]
		bag[i] = bag[j]
		bag[j] = tmp
	if last_played != "" and bag.size() > 1 and str(bag[0]) == last_played:
		var swap_idx := _rng.randi_range(1, bag.size() - 1)
		var tmp = bag[0]
		bag[0] = bag[swap_idx]
		bag[swap_idx] = tmp
	return bag

func next_track() -> String:
	if current_scene == "" or not SCENE_TRACKS.has(current_scene):
		return ""
	var next_path := pick_next_track(current_scene)
	if next_path == "":
		return ""
	current_track = next_path
	var p := active_player()
	if p != null:
		var stream := _load_stream(next_path)
		if stream != null:
			p.stream = stream
			if not _crossfading:
				p.volume_db = 0.0
			_last_pos = 0.0
			p.play()
	return current_track

func _start_crossfade(track_path: String) -> void:
	var stream := _load_stream(track_path)
	if stream == null or _players.size() < 2:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var outgoing := _players[_active_idx]
	_active_idx = 1 - _active_idx
	var incoming := _players[_active_idx]
	incoming.stream = stream
	incoming.volume_db = -80.0
	_last_pos = 0.0
	incoming.play()
	_crossfading = true
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(incoming, "volume_db", 0.0, CROSSFADE_DURATION)
	_fade_tween.tween_property(outgoing, "volume_db", -80.0, CROSSFADE_DURATION)
	_fade_tween.chain().tween_callback(_finish_crossfade.bind(outgoing))

func _finish_crossfade(outgoing: AudioStreamPlayer) -> void:
	if is_instance_valid(outgoing):
		outgoing.stop()
		outgoing.volume_db = -80.0
	_crossfading = false

func _on_player_finished(player_idx: int) -> void:
	if player_idx != _active_idx:
		return
	next_track()

func _on_screen_changed(screen: String) -> void:
	if screen == "settings" or screen == "res://ui/settings.tscn":
		return
	if screen == "battle" or screen == "res://battle/battle.tscn":
		play_battle(Game.pending_battle if Game != null else {})
		return
	var target := normalize_scene(screen)
	if target != "":
		play_scene(target)

func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "music_volume":
		apply_volume(float(value))

func set_volume(linear: float) -> void:
	var clamped := clampf(linear, 0.0, 1.0)
	if Game != null:
		Game.set_setting("music_volume", clamped)
	else:
		apply_volume(clamped)

func get_volume() -> float:
	if Game != null:
		return clampf(float(Game.setting("music_volume")), 0.0, 1.0)
	var idx := _ensure_bus()
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)

func apply_volume(linear: float) -> void:
	var idx := _ensure_bus()
	var v := clampf(linear, 0.0, 1.0)
	var muted := v <= 0.0001
	AudioServer.set_bus_mute(idx, muted)
	AudioServer.set_bus_volume_db(idx, -80.0 if muted else linear_to_db(v))

func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path) and _stream_cache[path] != null:
		return _stream_cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = ResourceLoader.load(path)
		if s == null and FileAccess.file_exists(path):
			s = AudioStreamOggVorbis.load_from_file(path)
	elif FileAccess.file_exists(path):
		s = AudioStreamOggVorbis.load_from_file(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = _read_import_loop(path)
	if s != null:
		_stream_cache[path] = s
	return s

func _read_import_loop(path: String) -> bool:
	var import_path := path + ".import"
	if not FileAccess.file_exists(import_path):
		return true
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return true
	return bool(cfg.get_value("params", "loop", true))
