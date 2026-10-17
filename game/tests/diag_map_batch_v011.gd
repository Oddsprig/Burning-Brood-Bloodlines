extends RefCounted
## Legacy/native versus ordered batching: identical static scene, real renderer.
const Terrain = preload("res://campaign/map_terrain.gd")
var fails := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL map batch: ", message)

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var destination := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): destination = arg.trim_prefix("--report-dir=").replace("\\", "/").simplify_path()
	check(destination.begins_with("C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"), "private image evidence")
	check(DisplayServer.get_name() != "headless", "actual rendered comparison")
	if fails > 0: return fails
	DirAccess.make_dir_recursive_absolute(destination)
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
	tree.root.position = Vector2i(-20000,-20000)
	tree.root.size = Vector2i(2560,1440)
	tree.root.visible = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	WorldGen.set_size(1.5)
	var world := {"seed":777,"towns":{},"roads":[],"road":"0".repeat(WorldGen.W * WorldGen.H)}
	WorldGen.gen_terrain(world,777,rng)
	var world_hash := JSON.stringify(world,"",false,true).sha256_text()
	var scene := Node2D.new()
	tree.root.add_child(scene)
	check(scene.is_inside_tree(), "comparison scene mounted")
	var cam := Camera2D.new()
	scene.add_child(cam)
	cam.make_current()
	var light := CanvasModulate.new()
	scene.add_child(light)
	var native_data := []
	var observations := []
	var retained_rids := []
	var pass_index := 0
	for mode in [false,true,true,false]:
		Terrain.decor_batch_enabled = mode
		var terrain := Terrain.new()
		scene.add_child(terrain)
		terrain.setup(world)
		check(terrain.decor_count() > 1000, "actual native decor present")
		var stats: Dictionary = terrain.decor_render_stats()
		check(int(stats["largest_batch_vertices"]) <= 8192, "bounded retained vertex batch")
		if pass_index == 2:
			check(Terrain._cache["rids"] == retained_rids, "same-mode return reuses exactly the retained native handles")
		if pass_index == 1: retained_rids = Terrain._cache["rids"].duplicate()
		for pose in 4:
			var zoom: float = [1.0,0.57,1.31,0.45][pose]
			cam.zoom = Vector2(zoom,zoom)
			cam.position = Vector2(WorldGen.W*WorldGen.CELL*0.5,WorldGen.H*WorldGen.CELL*0.5) + [Vector2.ZERO,Vector2(250,180),Vector2(-440,-250),Vector2.ZERO][pose]
			light.color = [Color.WHITE,Calendar.tint(1.4),Calendar.tint(1.9),Color.WHITE][pose]
			terrain.set_zoom(zoom)
			await tree.process_frame
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := tree.root.get_texture().get_image()
			check(img != null, "rendered native image")
			if img == null: continue
			var data := img.get_data()
			var name := "batch_remount" if pass_index == 2 else "batch" if mode else "legacy" if pass_index == 0 else "legacy_remount"
			var path := destination.path_join("%s_%d.png" % [name,pose])
			check(img.save_png(path) == OK, "private comparison image saved")
			var exact := true
			if native_data.size() <= pose: native_data.append(data)
			else:
				exact = data == native_data[pose]
				check(exact, "exact RGBA pixels mode%s pose%d" % [name,pose])
			observations.append({"mode":name,"pose":pose,"zoom":zoom,"exact_pixels":exact,
				"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),"stats":stats,"image":path})
		terrain.queue_free()
		await tree.process_frame
		check(Terrain._mounted_on == 0, "deleted map detaches retained decor handles")
		pass_index += 1
	check(JSON.stringify(world,"",false,true).sha256_text() == world_hash, "rendering preserves native world and insertion order")
	scene.queue_free()
	await tree.process_frame
	Terrain.free_cache()
	check(Terrain._cache.is_empty() and Terrain._cache_key.is_empty(), "shutdown releases retained decor cache")
	Terrain.decor_batch_enabled = true
	var file := FileAccess.open(destination.path_join("map-batch.json"),FileAccess.WRITE)
	check(file != null,"report opens")
	if file != null:
		file.store_string(JSON.stringify({"checks":checks,"fails":fails,"resolution":[2560,1440],"observations":observations},"  ",true,true))
		file.close()
	print("map batch exact pixels: %d checks/%d failures" % [checks,fails])
	return fails
