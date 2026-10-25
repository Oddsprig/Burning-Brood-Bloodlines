class_name DragonView
extends Node2D
## Actual native dragon holder, coherent source pixels and borrowed GPU textures.
## Rendering never advances combat, reconciles records or changes a body.
const NATIVE_PPU := 2.0
const MODEL_LIMIT := 64
var unit: Unit
var bow_hand: bool = false
var team_color: Color = Color.WHITE
var facing: int = 1:
	set(value):
		var next: int = -1 if value < 0 else 1
		if next != facing: facing = next; scale.x = float(next)
var pose: String = "idle"
var progress: float = 0.0
var _record: Dictionary = {}
var _state: Dictionary = {}
var _signature: String = ""
var _dirty: bool = true
var _render_enabled: bool = true
var _dead: bool = false
var _models: Dictionary = {}
var _order: Array[String] = []
var _current: Dictionary = {}
var _rest_model: Dictionary = {}
var _current_key: String = ""
var _origin: Vector2 = Vector2.ZERO
var _ppu: float = NATIVE_PPU
var _bounds: Rect2 = Rect2()
var _center: Vector2 = Vector2.ZERO
var _stats: Dictionary = {"state_reads":0,"model_builds":0,"model_hits":0,"evictions":0,"draws":0}
var _part_nodes: Dictionary = {}
var _wound_nodes: Dictionary = {}
static var _wound_shader: Shader
## The bonded rider, drawn seated on the saddle at human scale (FigurePainter.PX world px per unit; never the
## dragon's size). Far leg/arm behind the dragon, saddle and near side in front.
var _rider_uid: String = ""
var _rider_layers: Dictionary = {}
var _rider_far: Sprite2D
var _rider_front: Node2D
var _rider_saddle: Sprite2D
var _rider_near: Sprite2D
const WOUND_SHADER := """
shader_type canvas_item;
uniform float damage = 0.0;
uniform float blood = 1.0;
uniform bool bleeding = false;
uniform int wound_kind = 1;
uniform bool stump = false;
uniform vec2 source_size = vec2(1.0);
uniform vec2 source_offset = vec2(0.0);
uniform vec2 wound_point = vec2(0.0);
uniform float wound_radius = 1.0;
uniform float noise_seed = 0.0;
uniform int cut_count = 0;
uniform vec2 cut_points[4];
varying vec4 injury_tint;
void vertex() { injury_tint=COLOR; }
float hash_at(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))+noise_seed)*43758.5453); }
float grain(vec2 p) {
 vec2 cell=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash_at(cell),hash_at(cell+vec2(1,0)),f.x),mix(hash_at(cell+vec2(0,1)),hash_at(cell+vec2(1,1)),f.x),f.y);
}
float segment_distance(vec2 p,vec2 a,vec2 b) {
 vec2 d=b-a; float t=clamp(dot(p-a,d)/max(dot(d,d),0.001),0.0,1.0); return length(p-a-d*t);
}
void fragment() {
 vec4 source=texture(TEXTURE,UV); vec2 p=UV*source_size;
 float noise=grain((p+source_offset)/18.0),detail=grain((p+source_offset)/7.5);
 float ragged=smoothstep(0.36,0.72,noise*0.78+detail*0.30);
 float edge=clamp(min(min(UV.x,1.0-UV.x),min(UV.y,1.0-UV.y))*8.0,0.0,1.0);
 float radial=clamp(1.4-length(p-wound_point)/max(wound_radius,1.0),0.0,1.0);
 vec3 tone=mix(vec3(0.20,0.035,0.075),vec3(0.58,0.075,0.16),0.3+noise*0.65);
 if (!bleeding || blood<=0.0) { tone*=0.72; }
 float opacity=ragged*0.68*(0.16+edge*0.84)*damage;
 opacity=max(opacity,radial*damage*(0.28+detail*0.35));
 if(wound_kind==0) { tone=vec3(0.21,0.105,0.26); opacity=radial*damage*(0.18+ragged*0.38); }
 if(stump && cut_count>1) {
  float dist=100000.0;
  for(int i=0;i<3;i++) { if(i+1<cut_count) { dist=min(dist,segment_distance(p,cut_points[i],cut_points[i+1])); } }
  float lip=clamp(min(source_size.x,source_size.y)*0.04,2.0,12.0)*(0.75+noise*0.5);
  float rim=clamp(1.0-dist/(lip*2.2),0.0,1.0);
  if(dist<lip) { tone=mix(vec3(0.47,0.075,0.15),vec3(0.71,0.30,0.35),detail*0.45); }
  opacity=max(opacity,rim*0.94);
 }
 // Native mask already intersects source alpha and its actual owner piece.
 COLOR=vec4(tone,source.a*opacity)*injury_tint;
}
"""

class SourceLayer extends Node2D:
	var texture: Texture2D
	var draw_base: bool = true
	func _init() -> void: texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	func _draw() -> void:
		if texture != null and draw_base: draw_texture(texture,Vector2.ZERO)
	func set_texture(value: Texture2D, draw_image: bool = true) -> void:
		if texture != value or draw_base != draw_image: texture = value; draw_base = draw_image; queue_redraw()

class SourceCut extends Node2D:
	var model_data: Dictionary = {}
	var origin: Vector2 = Vector2.ZERO
	var pixels_per_unit: float = NATIVE_PPU
	var appearance_seed: int = 0
	var shard: PackedVector2Array = PackedVector2Array()
	var shard_color: Color = Color.WHITE
	var layers: Dictionary = {}
	var wounds: Dictionary = {}
	func _init() -> void: texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	func _ready() -> void:
		if not model_data.is_empty(): DragonView._update_gpu_layers(self,layers,wounds,model_data,model_data["state"],origin,pixels_per_unit,appearance_seed)
	func _draw() -> void:
		if not shard.is_empty(): draw_colored_polygon(shard,shard_color)

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func set_unit(value: Unit) -> void:
	unit = value; _signature = ""; _dirty = true; _models.clear(); _order.clear(); _current = {}; _current_key = ""
	_resolve_source(); _resolve_frame(); queue_redraw()

func set_background_rendering(_enabled: bool) -> void:
	pass # GPU source layers; no software raster worker or texture per pose.

func invalidate() -> void:
	_dirty = true

func refresh() -> void:
	invalidate()
	if _render_enabled: _resolve_source(); _resolve_frame(); queue_redraw()

func set_pose(value: String, t: float, render_frame: bool = true) -> void:
	pose = value if value in DragonArt.SUPPORTED_POSES else "idle"
	progress = clampf(t,0,1); _render_enabled = render_frame
	if not render_frame: return
	var changed: bool = _dirty
	if _dirty: _resolve_source()
	var old_key: String = _current_key
	_resolve_frame()
	if changed or old_key != _current_key: queue_redraw()

static func physical_ppu(row: Dictionary, model_data: Dictionary) -> float:
	var growth: Dictionary = DragonGrowth.metrics(row)
	if not bool(growth.get("valid",false)): return 0.0
	var base: float = float(model_data.get("linear_scale",0))
	return NATIVE_PPU * float(growth["linear_scale"])/base if base > 0 else 0.0

func _resolve_source() -> void:
	_dirty = false; _stats["state_reads"] += 1
	var started: int = Time.get_ticks_usec()
	var row: Dictionary = DragonCombat.record_for_unit(Game,unit) if unit != null else {}
	var state: Dictionary = DragonCombat.visual_state(unit) if unit != null and not row.is_empty() else {}
	var signature: String = JSON.stringify([row.get("id",""),row.get("sprite_id",""),row.get("morph_id",""),row.get("gem_id",""),row.get("appearance_seed",0),row.get("size_class","")])
	_dead = bool(state.get("dead",false))
	_record = row; _state = state; _current_key = ""
	if signature == _signature:
		var next_ppu: float = physical_ppu(row,_rest_model)
		if _ppu > 0 and next_ppu > 0 and not is_equal_approx(next_ppu,_ppu):
			var ratio: float = next_ppu/_ppu
			_origin *= ratio; _center *= ratio; _bounds = Rect2(_bounds.position*ratio,_bounds.size*ratio); _ppu = next_ppu
		_resolve_rider()
		Perf.record_us("Dragon visual state",Time.get_ticks_usec()-started); return
	_signature = signature
	_models.clear(); _order.clear(); _current = {}; _current_key = ""
	if row.is_empty():
		_bounds = Rect2(); _center = Vector2.ZERO
		push_error("Native dragon visual holder has no valid registry identity.")
		return
	# Intact rest coordinates anchor the original source. Wounds/head loss never
	# crop, enlarge, recenter or change the native animal/person size relationship.
	var rest: Dictionary = DragonArt.model(row,"rest")
	if not bool(rest.get("valid",false)): _record = {}; return
	_rest_model = rest
	_ppu = physical_ppu(row,rest)
	var torso: Rect2 = rest["bounds"]
	for region: Dictionary in rest["regions"]:
		if String(region["id"]) == "torso": torso = region["bounds"]; break
	_origin = Vector2(-torso.get_center().x,-float(rest["ground_y"]))*_ppu
	_center = _origin+torso.get_center()*_ppu
	# Rotation-safe bounds around the source seat include the complete tail,
	# folded wings and head even when its native cut is hidden. This is culling
	# only; artwork and one-cell native occupancy remain untouched.
	var area: Rect2 = rest["bounds"]
	var radius: float = 0.0
	for point: Vector2 in [area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]: radius = maxf(radius,point.length())
	radius = radius*1.25+4.0
	_bounds = Rect2(_origin-Vector2.ONE*radius*_ppu,Vector2.ONE*radius*_ppu*2)
	_resolve_rider()
	Perf.record_us("Dragon visual state",Time.get_ticks_usec()-started)

func _resolve_frame() -> void:
	if _record.is_empty(): return
	var actual_pose: String = "dead" if _dead else pose
	var frames: int = DragonArt.frame_count(_record,actual_pose)
	var frame: int = mini(frames-1,floori(progress*frames))
	var key: String = "%s:%d" % [actual_pose,frame]
	if _current_key == key and not _current.is_empty(): return
	if _models.has(key):
		_current = _models[key]; _stats["model_hits"] += 1; _order.erase(key); _order.append(key)
	else:
		var model_started: int = Time.get_ticks_usec()
		_current = DragonArt.model(_record,actual_pose,float(frame)/frames)
		_models[key] = _current; _order.append(key); _stats["model_builds"] += 1
		while _order.size() > MODEL_LIMIT: _models.erase(_order.pop_front()); _stats["evictions"] += 1
		Perf.record_us("Dragon pose model",Time.get_ticks_usec()-model_started)
	_current_key = key
	# Pose/source cache is independent of blood and sparse wounds. Only copied
	# visibility flags and GPU scalar uniforms change at native injury boundaries.
	_current = _current.duplicate()
	var lost: Array[String] = DragonDamageArt.effective_lost(_state,_current["all_parts"])
	var all_parts: Array = []; var parts: Array = []
	for original: Dictionary in _current["all_parts"]:
		var part: Dictionary = original.duplicate()
		part["visible"] = not lost.has(String(part["id"])); part["hidden"] = not part["visible"]
		all_parts.append(part)
		if part["visible"]: parts.append(part)
	_current["parts"] = parts; _current["all_parts"] = all_parts
	_current["state"] = DragonDamageArt.normalize(_state)
	_current["seamless_rest"] = bool(_current["seamless_rest"]) and lost.is_empty()
	var gpu_started: int = Time.get_ticks_usec()
	_update_gpu_layers(self,_part_nodes,_wound_nodes,_current,_state,_origin,_ppu,int(_record.get("appearance_seed",0)))
	_place_rider()
	Perf.record_us("Dragon GPU commands",Time.get_ticks_usec()-gpu_started)

func _resolve_rider() -> void:
	var uid: String = str(_record.get("rider_person_uid", ""))
	var person: Dictionary = Dragons._person(Game, uid) if uid != "" else {}
	if person.is_empty() or not bool(person.get("alive", true)) or _dead: uid = ""
	if uid == _rider_uid: return
	_rider_uid = uid
	_rider_layers = {}
	for node in [_rider_far, _rider_front]:
		if node != null: node.queue_free()
	_rider_far = null; _rider_front = null; _rider_saddle = null; _rider_near = null
	if uid == "": return
	var spec: Dictionary = Dynasty.portrait_for(Game, person)
	spec["dead"] = false
	_rider_layers = MountedRiderArt.render_layers(spec)
	if not bool(_rider_layers.get("ok", false)): _rider_layers = {}; return
	_rider_far = _sprite(_rider_layers["far"])
	add_child(_rider_far); move_child(_rider_far, 0)
	_rider_front = Node2D.new(); _rider_front.z_index = 1; add_child(_rider_front)
	_rider_saddle = _sprite(_rider_layers["saddle"]); _rider_front.add_child(_rider_saddle)
	_rider_near = _sprite(_rider_layers["near"]); _rider_front.add_child(_rider_near)

static func _sprite(image: Image) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sprite

func _place_rider() -> void:
	if _rider_layers.is_empty() or _rider_far == null: return
	var mounted: bool = bool(_current.get("mountable", true)) and _current.has("seat") and not _dead
	_rider_far.visible = mounted; _rider_front.visible = mounted
	if not mounted: return
	var seat: Vector2 = _origin + (_current["seat"] as Vector2) * _ppu
	var xf: Transform2D = MountedRiderArt.placement(_rider_layers, seat, FigurePainter.PX, float(_current.get("seat_angle", 0.0)))
	_rider_far.transform = xf; _rider_saddle.transform = xf; _rider_near.transform = xf

func has_rider() -> bool: return not _rider_layers.is_empty()

func visual_bounds() -> Rect2:
	# Mirror the complete local culling extent with the actual facing.
	return _bounds if facing > 0 else Rect2(Vector2(-_bounds.end.x,_bounds.position.y),_bounds.size)

func body_center_offset() -> Vector2:
	return Vector2(_center.x*facing,_center.y)

func current_state() -> Dictionary: return _state.duplicate(true)
func current_record() -> Dictionary: return _record.duplicate(true)
func cache_stats() -> Dictionary:
	var out: Dictionary = _stats.duplicate()
	out.merge({"models":_models.size(),"limit":MODEL_LIMIT,"pending":_dirty,"pixels_per_unit":_ppu,"render_enabled":_render_enabled,"wound_nodes":_wound_nodes.size(),"software_decals":0,"raster_jobs":0})
	return out

func _draw() -> void:
	if not _render_enabled or _current.is_empty() or not bool(_current.get("valid",false)): return
	_stats["draws"] += 1
	# Retained child CanvasItems draw source textures and clipped GPU injuries.
	# No software decal/cache/image build is reachable from live drawing.

static func _shader() -> Shader:
	if _wound_shader == null: _wound_shader = Shader.new(); _wound_shader.code = WOUND_SHADER
	return _wound_shader

static func _update_gpu_layers(host: Node2D, layers: Dictionary, wounds: Dictionary, model_data: Dictionary, state: Dictionary, origin: Vector2, ppu: float, seed_value: int) -> void:
	var to_canvas: Transform2D = Transform2D(0,Vector2(ppu,ppu),0,origin)
	var table: Dictionary = {}
	var seamless: bool = bool(model_data.get("seamless_rest",false))
	for part: Dictionary in model_data["all_parts"]:
		var id: String = String(part["id"]); table[id] = part
		if not layers.has(id):
			var new_source := SourceLayer.new(); new_source.name = "Source"+id.capitalize(); host.add_child(new_source); layers[id] = new_source
		var source_node: SourceLayer = layers[id]
		source_node.visible = bool(part.get("visible",true))
		source_node.transform = to_canvas*part["xf"]
		var whole: bool = seamless and id == "body"
		source_node.set_texture(DragonRigArt._texture_for(model_data["whole_image"] if whole else part["image"]),whole or not seamless)
	for existing_wound: SourceLayer in wounds.values(): existing_wound.visible = false
	var regions: Dictionary = {}
	for region: Dictionary in model_data["regions"]: regions[String(region["id"])] = region
	for mark: Dictionary in DragonDamageArt.marks(state,model_data["all_parts"],model_data["regions"]):
		var id: String = String(mark["mask_region_id"]); var owner: String = String(mark["mask_part_id"])
		if not regions.has(id) or not layers.has(owner) or not bool(table[owner].get("visible",true)): continue
		var region: Dictionary = regions[id]
		if not wounds.has(id):
			var new_wound := SourceLayer.new(); new_wound.name = "Wound"+id.capitalize()
			var new_material := ShaderMaterial.new(); new_material.shader = _shader(); new_wound.material = new_material
			(layers[owner] as SourceLayer).add_child(new_wound); wounds[id] = new_wound
		var wound_node: SourceLayer = wounds[id]; wound_node.visible = true
		wound_node.transform = (table[owner]["xf"] as Transform2D).affine_inverse()*region["xf"]
		wound_node.set_texture(DragonRigArt._texture_for(region["image"]))
		var shader_material: ShaderMaterial = wound_node.material
		var source_size: Vector2 = Vector2((region["image"] as Image).get_size())
		var inverse: Transform2D = (region["xf"] as Transform2D).affine_inverse()
		var points: PackedVector2Array = PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
		var line: PackedVector2Array = mark.get("cut_line",PackedVector2Array())
		for i: int in mini(4,line.size()): points[i] = inverse*line[i]
		shader_material.set_shader_parameter("damage",float(mark["damage"]))
		shader_material.set_shader_parameter("blood",float(mark["blood"]))
		shader_material.set_shader_parameter("bleeding",bool(mark["bleeding"]))
		shader_material.set_shader_parameter("stump",String(mark["kind"]) == "stump")
		shader_material.set_shader_parameter("wound_kind",0 if String(mark["wound_kind"]) == "b" else 1)
		shader_material.set_shader_parameter("source_size",source_size)
		shader_material.set_shader_parameter("source_offset",Vector2((region["source_rect"] as Rect2i).position))
		shader_material.set_shader_parameter("noise_seed",float(posmod(seed_value+hash(id),65521)))
		shader_material.set_shader_parameter("wound_point",inverse*mark["point"])
		shader_material.set_shader_parameter("wound_radius",maxf(1,minf(source_size.x,source_size.y)*0.18))
		shader_material.set_shader_parameter("cut_points",points)
		shader_material.set_shader_parameter("cut_count",mini(4,line.size()))

## Root's native sever event route. No humanoid fallback and no limb cutaway.
## Original source cut is drawn at the same physical scale, never fitted384.
static func source_cut_piece(value: Unit, part_id: String, facing_sign: int = 1) -> Node2D:
	var row: Dictionary = DragonCombat.record_for_unit(Game,value)
	if row.is_empty(): return null
	if part_id in ["head","neck"]:
		var cut: Dictionary = DragonRigArt.detached(row,part_id,"idle",0,DragonCombat.visual_state(value))
		if not bool(cut.get("valid",false)): return null
		var piece := SourceCut.new(); piece.model_data = cut; piece.pixels_per_unit = physical_ppu(row,cut)
		piece.origin = -(cut["bounds"] as Rect2).get_center()*piece.pixels_per_unit
		piece.appearance_seed = int(row.get("appearance_seed",0)); piece.scale.x = -1.0 if facing_sign < 0 else 1.0; return piece
	if part_id.begins_with("tooth") or part_id.begins_with("claw"):
		var piece := SourceCut.new()
		piece.shard = PackedVector2Array([Vector2(-0.7,0.5)*NATIVE_PPU,Vector2(0,-0.7)*NATIVE_PPU,Vector2(0.7,0.5)*NATIVE_PPU])
		var gem: Dictionary = DragonCard.catalog_entry("gems",String(row.get("gem_id","")))
		piece.shard_color = Color(String(gem.get("accent","#eeeeee"))); piece.scale.x = -1.0 if facing_sign < 0 else 1.0; return piece
	return null
