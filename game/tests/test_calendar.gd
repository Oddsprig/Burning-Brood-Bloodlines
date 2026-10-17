extends RefCounted
## Calendar: day/time/season text, tint changes between noon and night, latitude north +1 / south -1.
func run(_t) -> int:
	var fails := 0
	print(Calendar.text(0.0), " | ", Calendar.text(0.6), " | ", Calendar.text(31.2), " | ", Calendar.text(95.0))
	if Calendar.time_of_day(0.0) != "dawn" or Calendar.time_of_day(14.0 / 24.0) != "night": fails += 1
	if Calendar.season(0.0) != "spring" or Calendar.season(40.0) != "summer" or Calendar.season(100.0) != "winter": fails += 1
	if Calendar.year(130.0) != 2: fails += 1
	var noon := Calendar.tint(5.0 / 24.0)
	var night := Calendar.tint(16.0 / 24.0)
	if not (night.b > night.r and noon.r > night.r): fails += 1
	if Calendar.latitude(Vector2(0, 0), 100) != 1.0 or Calendar.latitude(Vector2(0, 100), 100) != -1.0: fails += 1
	return fails
