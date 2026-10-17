extends Node2D
## Monsters wave 1: static campaign-map sites for known lairs (wolf den, bear den, boar wallow, bandit camp).
## One Sprite2D per known lair, textures drawn once per kind (CreaturePainter.site) and shared. Rebuilt only when the
## set of known lairs or their state changes (sync is called from the map HUD refresh, 5x per second, and costs a
## short signature string), never per frame.

static var _tex: Dictionary = {}   # "kind|cleared" -> [Texture2D, anchor]
var _sig := ""

static func texture_for(kind: String, cleared: bool) -> Array:
	var key := "%s|%s" % [kind, cleared]
	if not _tex.has(key):
		var s := CreaturePainter.site(kind, cleared)
		_tex[key] = [ImageTexture.create_from_image(s["image"]), s["anchor"]]
	return _tex[key]

func sync(game) -> void:
	var w: Dictionary = game.world
	var lairs: Dictionary = w.get("lairs", {})
	var parts := PackedStringArray()
	for lid in lairs:
		var l: Dictionary = lairs[lid]
		if Monsters.suspended_lair(l): continue
		if l["known"]:
			parts.append("%s%d" % [lid, int(w["warbands"].has(String(l["resident"])))])
	var sig := ",".join(parts)
	if sig == _sig:
		return
	_sig = sig
	for c in get_children():
		c.queue_free()
	for lid in lairs:
		var l: Dictionary = lairs[lid]
		if Monsters.suspended_lair(l): continue
		if not l["known"]:
			continue
		var empty: bool = not w["warbands"].has(String(l["resident"]))
		var tx := texture_for(l["kind"], empty)
		var s := Sprite2D.new()
		s.texture = tx[0]
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.scale = Vector2(FigurePainter.PX, FigurePainter.PX) * 0.8
		s.position = (l["pos"] as Vector2) - (tx[1] as Vector2) * s.scale + Vector2(0, 10)
		s.name = "Site_" + lid
		add_child(s)
