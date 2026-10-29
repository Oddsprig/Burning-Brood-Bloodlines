extends RefCounted
## Before-sheet pixels at v0.066. No class_name, so this does not clash with Portrait.
## The live Portrait control still calls FigurePainter.render_bust.

static func build_image_at_447d266(spec: Dictionary) -> Image:
	return FigurePainter.render_bust_v066(spec)
