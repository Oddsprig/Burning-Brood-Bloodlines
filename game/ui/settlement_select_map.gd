class_name SettlementSelectMap
extends Control
## Static geography only. No campaign nodes, clock, jobs, movement or random stream.
signal settlement_chosen(town_id: String)
const Terrain = preload("res://campaign/map_terrain.gd")
var rows: Array = []
var selected_town: String = ""
var hovered_town: String = ""
var world_extent: Vector2 = Vector2.ONE
var terrain_texture: Texture2D
var road_texture: Texture2D
var texture_builds: int = 0

func _ready() -> void:
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	texture_filter = TEXTURE_FILTER_LINEAR
	resized.connect(queue_redraw)

func setup(world: Dictionary, settlements: Array) -> void:
	# Borrow no native world references. Retain only detached map/marker values.
	rows = settlements.duplicate(true)
	var width: int = maxi(1,int(world.get("w",WorldGen.W)))
	var height: int = maxi(1,int(world.get("h",WorldGen.H)))
	world_extent = Vector2(width,height)*float(world.get("cell",WorldGen.CELL))
	var terrain: String = String(world.get("terrain",""))
	var region: String = String(world.get("region",""))
	var roads: String = String(world.get("road",""))
	var image := Image.create(width,height,false,Image.FORMAT_RGBA8)
	var road_image := Image.create(width,height,false,Image.FORMAT_RGBA8)
	road_image.fill(Color.TRANSPARENT)
	for y in height:
		for x in width:
			var index: int = y*width+x
			var kind: String = terrain[index] if index < terrain.length() else "g"
			var reg: int = clampi(int(region[index]),0,Terrain.GRASS.size()-1) if index < region.length() else 0
			var color: Color = Color(Terrain.TERRAIN_COLORS[Terrain.T_INDEX.get(kind,0)])
			if kind == "g": color = Color(Terrain.GRASS[reg])
			elif kind == "f": color = Color(Terrain.FOREST_FLOOR[reg])
			image.set_pixel(x,y,color.darkened(0.12))
			if index < roads.length() and roads[index] == "1": road_image.set_pixel(x,y,Color("d1b884"))
	# Painted look: upscale the cell map smoothly, add a little per-pixel grain, warm parchment tint.
	var big := image.duplicate() as Image
	big.resize(width * 4, height * 4, Image.INTERPOLATE_CUBIC)
	var grain := FastNoiseLite.new(); grain.frequency = 0.08; grain.seed = int(world.get("seed", 1))
	for y in big.get_height():
		for x in big.get_width():
			var c := big.get_pixel(x, y)
			var n := grain.get_noise_2d(x, y) * 0.06
			c = c.lerp(Color("c9b48a"), 0.12)
			big.set_pixel(x, y, Color(c.r + n, c.g + n, c.b + n * 0.6, 1.0))
	var big_roads := road_image.duplicate() as Image
	big_roads.resize(width * 4, height * 4, Image.INTERPOLATE_BILINEAR)
	terrain_texture = ImageTexture.create_from_image(big)
	road_texture = ImageTexture.create_from_image(big_roads)
	texture_builds += 1
	queue_redraw()

func map_rect() -> Rect2:
	var available: Vector2 = (size-Vector2(32,54)).max(Vector2.ONE)
	var scale: float = minf(available.x/world_extent.x,available.y/world_extent.y)
	var span: Vector2 = world_extent*scale
	return Rect2(Vector2((size.x-span.x)*0.5,16.0+(available.y-span.y)*0.5),span)

func position_for(pos: Vector2) -> Vector2:
	var rect: Rect2 = map_rect()
	return rect.position+pos/world_extent*rect.size

func marker_at(point: Vector2) -> String:
	var nearest: String = ""
	var distance: float = 18.0
	for row: Dictionary in rows:
		var here: float = point.distance_to(position_for(row["pos"]))
		if here <= distance: distance = here; nearest = String(row["town_id"])
	return nearest

func select_town(town_id: String) -> void:
	selected_town = town_id
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered_town = marker_at(event.position)
		tooltip_text = ""
		for row: Dictionary in rows:
			if String(row["town_id"]) == hovered_town: tooltip_text = String(row["town_name"])+" · "+String(row.get("faction_name",""))
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var tid: String = marker_at(event.position)
		if tid != "": settlement_chosen.emit(tid); accept_event()

func _draw() -> void:
	draw_style_box(UiTheme.sb(UiTheme.PARCH,UiTheme.PARCH_3,1,6,0,0),Rect2(Vector2.ZERO,size))
	var rect: Rect2 = map_rect()
	if terrain_texture != null:
		draw_texture_rect(terrain_texture,rect,false)
		draw_texture_rect(road_texture,rect,false)
	draw_rect(rect,UiTheme.BORDER,false,1)
	var name: String = ""
	for row: Dictionary in rows:
		var point: Vector2 = position_for(row["pos"])
		var chosen: bool = String(row["town_id"]) == selected_town
		var hot: bool = String(row["town_id"]) == hovered_town
		if chosen:
			draw_circle(point,13,UiTheme.WOOD)
			draw_arc(point,12,0,TAU,32,UiTheme.PURPLE_TEXT,3,true)
			name = String(row["town_name"])+" · "+String(row.get("faction_name",""))
		draw_circle(point,7 if chosen or hot else 5,UiTheme.BRASS if chosen else UiTheme.INK)
		draw_arc(point,7 if chosen or hot else 5,0,TAU,16,UiTheme.WOOD,2,true)
		var lab := String(row["town_name"])
		var lf: Font = UiTheme.regular_font()
		var lw: float = lf.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string_outline(lf, point + Vector2(-lw * 0.5, -10), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0.08, 0.05, 0.03, 0.9))
		draw_string(lf, point + Vector2(-lw * 0.5, -10), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.BRASS if chosen else UiTheme.LIGHT)
	var font: Font = UiTheme.regular_font()
	var text_width: float = font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
	# Caption is also exposed in the chooser's wrapped label for long names.
	if text_width > size.x-24: name = "Selected settlement highlighted" if selected_town != "" else "Select a settlement"
	draw_string(font,Vector2(12,size.y-14),name,HORIZONTAL_ALIGNMENT_LEFT,-1,17,UiTheme.INK)
