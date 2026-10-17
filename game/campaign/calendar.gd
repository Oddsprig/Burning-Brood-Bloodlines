class_name Calendar
extends RefCounted
## Campaign calendar on top of Game.day (1.0 = one day). Day 0 starts at dawn (07:00).
## Year = 4 seasons x DAYS_PER_SEASON days [ours, tunable]. Gameplay effects of seasons and climate
## (harvests, cold needs, spoilage) come later with the economy; for now this is readable state plus
## one cheap full-map tint (no per-sprite animation).

const START_HOUR := 7.0
const DAYS_PER_SEASON := 30
const SEASONS := ["spring", "summer", "autumn", "winter"]
const START_SEASON := 0

static func hour(day: float) -> float:
	return fmod(day * 24.0 + START_HOUR, 24.0)

## Whole calendar days elapsed, counting midnights (day 0 runs from dawn to midnight).
static func day_index(day: float) -> int:
	return int(floor((day * 24.0 + START_HOUR) / 24.0))

static func time_of_day(day: float) -> String:
	var h := hour(day)
	if h >= 5.0 and h < 9.0: return "dawn"
	if h >= 9.0 and h < 12.0: return "morning"
	if h >= 12.0 and h < 15.0: return "midday"
	if h >= 15.0 and h < 18.0: return "afternoon"
	if h >= 18.0 and h < 21.0: return "evening"
	return "night"

static func season_index(day: float) -> int:
	return (START_SEASON + day_index(day) / DAYS_PER_SEASON) % 4

static func season(day: float) -> String:
	return SEASONS[season_index(day)]

static func year(day: float) -> int:
	return 1 + (START_SEASON + day_index(day) / DAYS_PER_SEASON) / 4

static func day_of_season(day: float) -> int:
	return day_index(day) % DAYS_PER_SEASON + 1

static func text(day: float) -> String:
	return "Day %d of %s, year %d - %s" % [day_of_season(day), season(day), year(day), time_of_day(day)]

## Latitude for a map position: +1 far north (cold) .. -1 far south (hot). The economy reads this later
## for climate needs; the map's north is y = 0.
static func latitude(pos: Vector2, map_height: float) -> float:
	return clampf(1.0 - 2.0 * pos.y / maxf(1.0, map_height), -1.0, 1.0)

## One colour for a CanvasModulate over the map: night/dawn/dusk light times a slight season shift.
static func tint(day: float) -> Color:
	var h := hour(day)
	var night := Color(0.45, 0.5, 0.72)
	var dusk := Color(1.0, 0.82, 0.68)
	var noon := Color(1, 1, 1)
	var c: Color
	if h < 4.5 or h >= 21.5: c = night
	elif h < 6.5: c = night.lerp(dusk, (h - 4.5) / 2.0)
	elif h < 8.5: c = dusk.lerp(noon, (h - 6.5) / 2.0)
	elif h < 17.5: c = noon
	elif h < 19.5: c = noon.lerp(dusk, (h - 17.5) / 2.0)
	else: c = dusk.lerp(night, (h - 19.5) / 2.0)
	var s: Color = [Color(1.0, 1.02, 0.98), Color(1.03, 1.0, 0.94), Color(1.02, 0.96, 0.9), Color(0.92, 0.96, 1.05)][season_index(day)]
	return Color(c.r * s.r, c.g * s.g, c.b * s.b)
