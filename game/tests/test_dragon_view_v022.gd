extends RefCounted
## Native holder identity, physical-scale GPU adapter and offscreen injury reads.
var checks: int = 0
var fails: int = 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon view v022: ",why)

static func fingerprint() -> String:
	return JSON.stringify(Game._serialize({"world":Game.world,"company":Game.company,"rng":str(Game.rng.state),"unit":Unit._next_uid,"item":Item._next_uid}),"",true,true).sha256_text()

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var old: Dictionary = {"world":Game.world,"company":Game.company,"squads":Game.squads,"day":Game.day,"gold":Game.gold,"location":Game.location,"rng":Game.rng.state,"unit":Unit._next_uid,"item":Item._next_uid}
	var fixture: RefCounted = load("res://tests/test_dragon_bond_v021.gd").new(); fixture.fixture()
	DragonCombat.prepare_world(Game)
	var row: Dictionary = fixture.row()
	row["growth_points"] = 2.5; row["size_class"] = "large"; DragonCombat.sync_profile(Game,fixture.dragon_uid)
	var unit: Unit = Game.world["dragons"]["combat_units"][fixture.dragon_uid]
	check(DragonCombat.is_dragon_unit(Game,unit),"fixture uses actual persistent registered Unit")
	var before: String = fingerprint()
	var doll := DragonView.new(); tree.root.add_child(doll); doll.set_unit(unit)
	check(doll.unit == unit and doll.current_record()["id"] == fixture.dragon_uid,"view borrows exact native holder and stable record")
	var model: Dictionary = doll._current
	check(is_equal_approx(float(doll.cache_stats()["pixels_per_unit"])*float(model["linear_scale"]),2.0*float(DragonGrowth.metrics(row)["linear_scale"])),"continuous growth uses fixed native personppu2 with host-only ratio")
	var origin: Vector2 = doll._origin
	var source_hash: String = DragonArt.source_image(row).get_data().hex_encode().sha256_text()
	check(fingerprint() == before,"eager renderer setup creates no Unit/Item/body/RNG/world changes")
	var reads: int = int(doll.cache_stats()["state_reads"])
	var builds: int = int(doll.cache_stats()["model_builds"])
	for i: int in 40: doll.set_pose("idle",0,true)
	check(int(doll.cache_stats()["state_reads"]) == reads and int(doll.cache_stats()["model_builds"]) == builds,"unchanged native frame avoids body/spec/model work")
	for pose: String in ["idle","walk","prepare","strike","recover","hit","block","dodge","prone","dead"]:
		for progress: float in [0.0,0.37,0.75,1.0]:
			doll.set_pose(pose,progress,true)
			var bounds: Rect2 = doll._current["bounds"]
			var actual: Rect2 = Rect2(doll._origin+bounds.position*doll._ppu,bounds.size*doll._ppu)
			check(doll.visual_bounds().encloses(actual),pose+" full physical posed bounds fit conservative culling")
			check(doll._origin == origin,pose+" original rest anchor never refits/recenters animal")
	check(int(doll.cache_stats()["models"]) <= DragonView.MODEL_LIMIT,"per-actor native pose model cache bounded")
	check(fingerprint() == before,"all pose/culling reads preserve native bodies/identities/funds/RNG")
	var wounded: Dictionary = unit.body.wound_part("wing_upper_r"); wounded["layers"][0]["dmg"] = 0.7; wounded["layers"][0]["kind"] = "mangled"; wounded["layers"][0]["bleed"] = 0.2
	before = fingerprint(); doll.invalidate(); reads = int(doll.cache_stats()["state_reads"]); builds = int(doll.cache_stats()["model_builds"])
	for i: int in 20: doll.set_pose("hit",float(i)/20,false)
	check(int(doll.cache_stats()["state_reads"]) == reads and int(doll.cache_stats()["model_builds"]) == builds and bool(doll.cache_stats()["pending"]),"offscreen wounds track latest pose without model/body work")
	doll.set_pose("hit",0.55,true)
	check(float(doll.current_state()["dmg"].get("wing_upper_r",0)) > 0 and doll._current["parts"].size() == 3,"reentry uses actual native wound while complete wing remains mangled attached art")
	check(fingerprint() == before and doll._origin == origin,"wound display changes no actual tissue and never recrops source")
	var software_decals: int = DragonDamageArt._decals.size()
	builds = int(doll.cache_stats()["model_builds"])
	var wound_node: DragonView.SourceLayer = doll._wound_nodes["wing_upper_r"]
	var original_mask: Texture2D = wound_node.texture
	for i: int in 12:
		unit.body.blood = unit.body.blood_max*(0.9-float(i)*0.02)
		before = fingerprint(); doll.invalidate(); doll.set_pose("hit",0.55,true)
		check(fingerprint() == before,"exact native blood update stays read-only while GPU injury changes")
	check(int(doll.cache_stats()["model_builds"]) == builds,"continuous native blood never invalidates source/pose geometry cache")
	check(DragonDamageArt._decals.size() == software_decals and int(doll.cache_stats()["software_decals"]) == 0 and int(doll.cache_stats()["raster_jobs"]) == 0,"live injury route never creates software decals or raster worker jobs")
	check(doll._wound_nodes["wing_upper_r"] == wound_node and wound_node.texture == original_mask and wound_node.material is ShaderMaterial,"bounded existing anatomical mask/node/material reused across blood changes")
	check(is_equal_approx(float((wound_node.material as ShaderMaterial).get_shader_parameter("blood")),unit.body.blood/unit.body.blood_max),"GPU receives exact current native blood fraction without visual quantization")
	check(doll._part_nodes.size() == 3 and doll._wound_nodes.size() <= 15,"three source pieces and at most15 native anatomical wound nodes")
	for _i in 3: await tree.process_frame
	check(DragonDamageArt._decals.size() == software_decals,"actual queued CanvasItem draws do not enter legacy software decal path")
	var piece: Node2D = DragonView.source_cut_piece(unit,"wing_upper_r")
	check(piece == null,"native wing loss never emits detached full limb art")
	unit.body.wound_part("head")["severed"] = true; unit.dead = true; before = fingerprint()
	doll.invalidate(); doll.set_pose("idle",0,false)
	check(not doll.current_state().get("lost",[]).has("head"),"culled invalidation remains pending rather than rebuilding invisibly")
	doll.set_pose("idle",0,true)
	check(doll._current["parts"].size() == 1 and String(doll._current["parts"][0]["id"]) == "body" and doll._current["pose"] == "dead","actual dead/head-lost reentry retains body only with native neck cut")
	check(doll._origin == origin and fingerprint() == before,"head loss preserves source placement and native body values")
	piece = DragonView.source_cut_piece(unit,"neck")
	check(piece != null and (piece as DragonView.SourceCut).model_data["parts"].size() == 2,"head-only natural cut returns original head and jaw source layers")
	if piece != null:
		check(is_equal_approx((piece as DragonView.SourceCut).pixels_per_unit,doll._ppu),"severed head preserves actual host physical pixel scale")
		tree.root.add_child(piece)
		for _i in 3: await tree.process_frame
		check(DragonDamageArt._decals.size() == software_decals and (piece as DragonView.SourceCut).layers.size() == 3,"actual head-cut draw reuses bounded GPU layers without software blood raster")
		piece.queue_free(); piece = null
	piece = DragonView.source_cut_piece(unit,"tooth1")
	check(piece != null and (piece as DragonView.SourceCut).shard.size() == 3,"actual tooth event allows a tiny gem tip only")
	if piece != null: piece.free(); piece = null
	check(DragonArt.source_image(row).get_data().hex_encode().sha256_text() == source_hash,"native animation/mangle/cut never changes original source RGBA")
	var fighter := Fighter.new(); fighter.unit = unit; fighter.cell = Vector2i(2,2); fighter.facing = -1
	var view: Node2D = load("res://battle/unit_view.gd").new(); tree.root.add_child(view); view.setup(fighter,40.0)
	check(view.doll is DragonView and view.doll.unit == unit,"UnitView uses actual dragon adapter without humanoid/creature fallback")
	check(view.body_center() == view.position+view.doll.body_center_offset(),"native camera/blood anchor follows actual animal torso")
	check(not view.update_visual(0,0,Rect2(10000,10000,100,100)),"full-sized actor culling excludes truly offscreen dragon")
	check(view.update_visual(0,0,Rect2(view.position+view.doll.visual_bounds().position,view.doll.visual_bounds().size)),"physical silhouette intersection keeps visible dragon drawing")
	view.queue_free(); doll.queue_free(); view = null; doll = null; fighter = null; unit = null
	for _i in 5: await tree.process_frame
	Game.world = old["world"]; Game.company = old["company"]; Game.squads = old["squads"]; Game.day = old["day"]; Game.gold = old["gold"]; Game.location = old["location"]
	Game.rng.state = old["rng"]; Unit._next_uid = old["unit"]; Item._next_uid = old["item"]
	fixture = null; model = {}; row = {}; DragonRigArt.clear_texture_cache()
	print("Dragon view v022: ",checks," checks, ",fails," failures")
	return fails
