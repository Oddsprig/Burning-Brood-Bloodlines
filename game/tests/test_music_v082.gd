extends RefCounted
## v0.082 headless test: MusicManager scene mapping, track rotation & non-repeating shuffle,
## ~1.5s crossfade state, and Settings HSlider volume save/load driving the "Music" bus.

var _fails := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL [test_music_v082]: " + msg)
		_fails += 1

func run(tree: SceneTree) -> int:
	_fails = 0
	var orig_vol := float(Game.setting("music_volume"))

	# 1. Verify "Music" bus and all 11 converted OGG tracks + .import loop=true
	var bus_idx := AudioServer.get_bus_index("Music")
	_check(bus_idx >= 0, "'Music' bus exists on AudioServer")
	if bus_idx >= 0:
		_check(AudioServer.get_bus_send(bus_idx) == "Master", "'Music' bus sends to Master")

	var expected_scenes := {
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

	var total_tracks := 0
	for scene_key in expected_scenes.keys():
		var want_list: Array = expected_scenes[scene_key]
		var got_list: Array = MusicManager.tracks_for_scene(scene_key)
		_check(got_list == want_list, "scene '%s' track mapping matches expected list" % scene_key)
		for track_path in want_list:
			total_tracks += 1
			var abs_p := ProjectSettings.globalize_path(String(track_path))
			_check(FileAccess.file_exists(abs_p), "OGG file exists: " + String(track_path))
			_check(FileAccess.file_exists(String(track_path) + ".import"), ".import file exists: " + String(track_path))
			var cfg := ConfigFile.new()
			var err := cfg.load(String(track_path) + ".import")
			_check(err == OK and bool(cfg.get_value("params", "loop", false)) == true, ".import has loop=true for " + String(track_path))
			var stream := MusicManager._load_stream(String(track_path))
			_check(stream is AudioStreamOggVorbis, "loaded AudioStreamOggVorbis for " + String(track_path))
			if stream is AudioStreamOggVorbis:
				_check((stream as AudioStreamOggVorbis).loop == true, "stream.loop is true for " + String(track_path))
	_check(total_tracks == 11, "all 11 tracks verified across 8 scenes")

	# 2. Scene mapping (direct names, space-separated names, screen routes, and battle variants)
	for scene_key in expected_scenes.keys():
		MusicManager.play_scene(scene_key, true)
		_check(MusicManager.get_current_scene() == scene_key, "play_scene('%s') sets current_scene" % scene_key)
		_check((expected_scenes[scene_key] as Array).has(MusicManager.get_current_track()), "play_scene('%s') picks valid track" % scene_key)
		_check(MusicManager.active_player() != null and MusicManager.active_player().bus == "Music", "active player uses 'Music' bus")

	MusicManager.play_scene("campaign map", true)
	_check(MusicManager.get_current_scene() == "campaign_map", "'campaign map' normalizes to 'campaign_map'")
	MusicManager.play_scene("dragon attack", true)
	_check(MusicManager.get_current_scene() == "dragon_attack", "'dragon attack' normalizes to 'dragon_attack'")

	# Battle variant detection: regular battle vs siege vs dragon attack
	MusicManager.play_battle({"assault": {"kind": "raid"}})
	_check(MusicManager.get_current_scene() == "battle" and MusicManager.get_current_track() == "res://audio/clash_of_iron.ogg", "raid/field battle maps to clash_of_iron.ogg")
	MusicManager.play_battle({"assault": {"kind": "siege"}})
	_check(MusicManager.get_current_scene() == "siege" and MusicManager.get_current_track() == "res://audio/relentless_siege.ogg", "siege battle maps to relentless_siege.ogg")
	MusicManager.play_battle({"dragon_units": [{"type_id": "dragon"}]})
	_check(MusicManager.get_current_scene() == "dragon_attack" and MusicManager.get_current_track() == "res://audio/iron_wings_descending.ogg", "dragon battle maps to iron_wings_descending.ogg")

	# Screen aliases (title -> menu, map/town -> campaign_map, house/politics -> court, gameover -> defeat, aftermath -> victory/defeat)
	MusicManager._on_screen_changed("title")
	_check(MusicManager.get_current_scene() == "menu", "screen 'title' maps to 'menu'")
	MusicManager._on_screen_changed("map")
	_check(MusicManager.get_current_scene() == "campaign_map", "screen 'map' maps to 'campaign_map'")
	MusicManager._on_screen_changed("politics")
	_check(MusicManager.get_current_scene() == "court", "screen 'politics' maps to 'court'")
	MusicManager._on_screen_changed("gameover")
	_check(MusicManager.get_current_scene() == "defeat", "screen 'gameover' maps to 'defeat'")
	Game.last_result = {"winner": 0}
	MusicManager._on_screen_changed("aftermath")
	_check(MusicManager.get_current_scene() == "victory", "aftermath winner=0 maps to 'victory'")
	Game.last_result = {"winner": 1}
	MusicManager._on_screen_changed("aftermath")
	_check(MusicManager.get_current_scene() == "defeat", "aftermath winner=1 maps to 'defeat'")

	# 3. Same-scene re-entry does not restart or switch track
	MusicManager.play_scene("campaign_map", true)
	var map_track := MusicManager.get_current_track()
	var map_player := MusicManager.active_player()
	MusicManager.play_scene("campaign_map")
	_check(MusicManager.get_current_track() == map_track and MusicManager.active_player() == map_player, "re-entering 'campaign_map' does not restart track")
	MusicManager._on_screen_changed("town")
	_check(MusicManager.get_current_track() == map_track and MusicManager.active_player() == map_player, "switching to 'town' sub-screen keeps campaign_map track playing")

	# 4. Track rotation & non-repeating shuffle on multi-track scenes
	MusicManager.play_scene("court", true)
	var prev_court := MusicManager.get_current_track()
	var seen_court := {prev_court: true}
	var court_repeats := 0
	for i in 20:
		var nxt := MusicManager.next_track()
		seen_court[nxt] = true
		if nxt == prev_court:
			court_repeats += 1
		prev_court = nxt
	_check(court_repeats == 0, "court rotation never repeats the last track across 20 transitions")
	_check(seen_court.size() == 2, "court rotation visits both court tracks")

	MusicManager.play_scene("campaign_map", true)
	var prev_map := MusicManager.get_current_track()
	var seen_map := {prev_map: true}
	var map_repeats := 0
	for i in 30:
		var nxt := MusicManager.next_track()
		seen_map[nxt] = true
		if nxt == prev_map:
			map_repeats += 1
		prev_map = nxt
	_check(map_repeats == 0, "campaign_map rotation never repeats the last track across 30 transitions")
	_check(seen_map.size() == 3, "campaign_map rotation visits all 3 campaign_map tracks")

	# Also verify player finished signal triggers rotation
	var before_finish := MusicManager.get_current_track()
	MusicManager._on_player_finished(MusicManager._active_idx)
	_check(MusicManager.get_current_track() != before_finish, "active player finished signal rotates to next non-repeating track")

	# 5. Crossfade state (~1.5 s)
	MusicManager.play_scene("menu", true)
	if MusicManager._fade_tween != null and MusicManager._fade_tween.is_valid():
		MusicManager._fade_tween.kill()
	MusicManager._finish_crossfade(MusicManager.inactive_player())
	MusicManager.active_player().volume_db = 0.0
	_check(not MusicManager.is_crossfading(), "crossfade settled before scene switch")

	var old_player := MusicManager.active_player()
	MusicManager.play_scene("battle")
	var new_player := MusicManager.active_player()
	_check(new_player != old_player, "scene switch swaps active AudioStreamPlayer")
	_check(MusicManager.is_crossfading(), "MusicManager is_crossfading() is true immediately after scene change")
	_check(new_player.playing, "incoming player is playing during crossfade")

	await tree.create_timer(MusicManager.CROSSFADE_DURATION + 0.25).timeout
	_check(not MusicManager.is_crossfading(), "crossfade completes after ~1.5s")
	_check(absf(new_player.volume_db - 0.0) < 0.05, "incoming player reaches 0 dB after crossfade")
	_check(not old_player.playing and absf(old_player.volume_db - (-80.0)) < 0.05, "outgoing player stops at -80 dB after crossfade")

	# 6. Settings HSlider + volume save/load + "Music" bus mute at 0
	var settings_scene: Control = load("res://ui/settings.tscn").instantiate()
	settings_scene.overlay = true
	tree.root.add_child(settings_scene)
	await tree.process_frame

	var slider := settings_scene.find_child("Slider_music_volume", true, false) as HSlider
	var val_lbl := settings_scene.find_child("Value_music_volume", true, false) as Label
	_check(slider != null, "Settings screen contains HSlider 'Slider_music_volume'")
	_check(val_lbl != null, "Settings screen contains Label 'Value_music_volume'")

	if slider != null:
		slider.value = 0.0
		_check(absf(float(Game.setting("music_volume")) - 0.0) < 0.0001, "slider 0.0 sets Game music_volume to 0.0")
		_check(AudioServer.is_bus_mute(bus_idx), "slider 0.0 mutes 'Music' bus")
		if val_lbl != null:
			_check(val_lbl.text == "Muted", "slider 0.0 displays 'Muted'")

		slider.value = 0.75
		_check(absf(float(Game.setting("music_volume")) - 0.75) < 0.01, "slider 0.75 sets Game music_volume to 0.75")
		_check(not AudioServer.is_bus_mute(bus_idx), "slider 0.75 unmutes 'Music' bus")
		_check(absf(AudioServer.get_bus_volume_db(bus_idx) - linear_to_db(0.75)) < 0.1, "'Music' bus volume_db matches linear_to_db(0.75)")
		if val_lbl != null:
			_check(val_lbl.text == "75%", "slider 0.75 displays '75%'")

		Game.settings["music_volume"] = 0.1
		Game.load_settings()
		_check(absf(float(Game.setting("music_volume")) - 0.75) < 0.01, "Game.load_settings() restores saved music_volume (0.75)")

	settings_scene.queue_free()
	await tree.process_frame

	# Restore original volume and leave clean state
	Game.set_setting("music_volume", orig_vol)
	MusicManager.play_scene("menu")
	if MusicManager._fade_tween != null and MusicManager._fade_tween.is_valid():
		MusicManager._fade_tween.kill()
	MusicManager._finish_crossfade(MusicManager.inactive_player())
	MusicManager.active_player().volume_db = 0.0

	if _fails == 0:
		print("PASS: test_music_v082 (all checks passed)")
	return _fails
