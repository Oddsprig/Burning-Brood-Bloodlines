extends Node2D
## One fighter on the battle map: shadow, selection/highlight ring and a Paperdoll. Reads only Fighter
## contract fields (cell, prev_cell, state, action_ticks, action_total, facing, side) and animates them;
## never changes the fighter.

const PLAYER_COLOR := Color(0.25, 0.6, 1.0)
const ENEMY_COLOR := Color(1.0, 0.27, 0.2)
const FLASH_TIME := 0.28
const FLEE_SPEED := 160.0   # px per real second
const FLEE_FADE := 1.6

var fighter: Fighter
var doll: Node2D
var tile := 40.0
var selected := false:
	set(value):
		if selected != value:
			selected = value
			queue_redraw()
var highlight := 0.0:       # >0 = decisive-blow glow, seconds remaining
	set(value):
		if highlight != value:
			highlight = value
			queue_redraw()
var _flash_pose := ""
var _flash_t := 0.0
var _flee_t := -1.0
var _flee_dir := Vector2.LEFT
var gone := false          # fled off the map
var _raster_bounds := Rect2()
var _draw_dead := false
var _dead_settled := false

func setup(f, tile_px: float) -> void:
	fighter = f
	tile = tile_px
	# Tagged malformed dragon holders fail closed inside DragonView; never draw
	# a humanoid/creature stand-in for a registered animal.
	var dragon_tag: Variant = f.unit.get("dragon_uid")
	var dragon_actor: bool = (dragon_tag != null and String(dragon_tag) != "") or f.unit.race == "dragon" or (f.unit.body != null and f.unit.body.plan_id == "wyvern")
	doll = DragonView.new() if dragon_actor else Paperdoll.new()
	doll.team_color = PLAYER_COLOR if f.side == 0 else ENEMY_COLOR
	doll.facing = f.facing
	add_child(doll)
	doll.set_unit(f.unit)
	position = cell_pos(f.cell)
	if doll is DragonView: _raster_bounds = doll.visual_bounds()
	else:
		var dimensions: Dictionary = FigurePainter.dims(f.unit.race)
		var display: float = FigurePainter.display_scale(f.unit.race)
		# Include the native fallen-weapon extension and the full mirrored frame.
		_raster_bounds = Rect2(-Vector2(dimensions["anchor"]) * display,
			(Vector2(dimensions["size"]) + Vector2(0, 16)) * display).grow(4.0)

func cell_pos(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * tile, (c.y + 0.82) * tile)

## Body centre in local coords (for taps, floating text, highlights).
func body_center() -> Vector2:
	return position + (doll.body_center_offset() if doll is DragonView else Vector2(0,-22))

func flash(pose: String) -> void:
	# A blow landing beats a block flash beats a strike flash.
	var rank := {"strike": 1, "dodge": 2, "block": 2, "hit": 3}
	if _flash_t > 0.0 and rank.get(_flash_pose, 0) > rank.get(pose, 0):
		return
	_flash_pose = pose
	_flash_t = FLASH_TIME

func update_visual(frac: float, dt: float, view_rect: Rect2 = Rect2()) -> bool:
	var f = fighter
	if gone:
		return false
	visible = not f.waiting   # stream arrivals are off the map until they enter
	if f.waiting:
		return false
	_flash_t = maxf(0.0, _flash_t - dt)
	highlight = maxf(0.0, highlight - dt)
	if f.bow_hand != doll.bow_hand:   # bows: bow in the hands (draw/loose poses) or the sidearm
		doll.bow_hand = f.bow_hand
	var st: String = f.state
	var total := maxf(1.0, float(f.action_total))
	var prog := clampf((total - float(f.action_ticks) + frac) / total, 0.0, 1.0)
	var pose := "idle"
	var t := 0.0
	var pos := cell_pos(f.cell)
	match st:
		"moving":
			pose = "walk"; t = prog
			pos = cell_pos(f.prev_cell).lerp(cell_pos(f.cell), prog)
		"preparing":
			pose = "prepare"; t = prog
		"recovering":
			pose = "recover"; t = prog
		"prone", "unconscious":
			pose = "prone"
		"dead":
			pose = "dead"; t = 1.0
		"fled":
			if _flee_t < 0.0:
				_flee_t = 0.0
				_flee_dir = Vector2.LEFT if f.side == 0 else Vector2.RIGHT   # back toward their own edge
			_flee_t += dt
			pose = "walk"; t = fmod(_flee_t * 3.0, 1.0)
			pos = cell_pos(f.cell) + _flee_dir * FLEE_SPEED * _flee_t
			modulate.a = clampf(1.0 - _flee_t / FLEE_FADE, 0.0, 1.0)
			if _flee_t >= FLEE_FADE:
				gone = true
				visible = false
	var down: bool = f.prone or st == "prone" or st == "unconscious"
	if down and st != "dead" and st != "fled":
		pose = "prone"   # lying down (crawls and fights weakly while prone)
		t = 0.0
	elif _flash_t > 0.0 and st not in ["dead", "fled"]:
		pose = _flash_pose
		t = 1.0 - _flash_t / FLASH_TIME
	position = pos
	z_index = -1 if st == "dead" else 0
	var dead_now: bool = st == "dead"
	if dead_now != _draw_dead:
		_draw_dead = dead_now
		queue_redraw()
	# A settled corpse never changes pose again: skip the per-frame doll work (only culling can change).
	if dead_now and _dead_settled and not doll is DragonView:
		var vis := view_rect.size == Vector2.ZERO or view_rect.intersects(Rect2(position + _raster_bounds.position, _raster_bounds.size))
		if vis != doll.visible:
			doll.visible = vis
			if vis: doll.set_pose(pose, t, true)
		return vis
	_dead_settled = dead_now and _flash_t <= 0.0
	var face: int = f.facing if f.facing != 0 else 1
	if st == "fled":
		face = 1 if _flee_dir.x > 0 else -1
	doll.facing = face
	if doll is DragonView: _raster_bounds = doll.visual_bounds()
	var render_frame: bool = not gone and (view_rect.size == Vector2.ZERO or
		view_rect.intersects(Rect2(position + _raster_bounds.position, _raster_bounds.size)))
	# Actor coordinates/timers remain current. Hide the sprite alone so a queued
	# native draw cannot rasterize an offscreen invalidation behind this gate.
	doll.visible = render_frame
	doll.set_pose(pose, t, render_frame)
	return render_frame

## Skip-to-end: fled units vanish immediately.
func settle(view_rect: Rect2 = Rect2()) -> void:
	if fighter.state == "fled":
		gone = true
		visible = false
	_flash_t = 0.0
	doll.invalidate()
	update_visual(0.0, 0.0, view_rect)

func _draw() -> void:
	# Ground shadows are drawn for every fighter at once by battle.gd's ShadowLayer (one batch, not 400 items).
	if selected:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, 22.0, 0, TAU, 32, Color(1, 0.95, 0.3), 4.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if highlight > 0.0:
		var a := clampf(highlight, 0.0, 1.0)
		draw_circle(Vector2(0, -22), 30.0 + (1.0 - a) * 14.0, Color(1.0, 0.85, 0.2, 0.25 * a))
		draw_arc(Vector2(0, -22), 30.0 + (1.0 - a) * 14.0, 0, TAU, 32, Color(1.0, 0.9, 0.3, a), 3.0)
