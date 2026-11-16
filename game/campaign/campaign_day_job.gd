class_name CampaignDayJob
extends RefCounted
## Shared ordered continuation; ownership is retained through the RNG commit.
## Timing reservations are not certified native-kernel worst-case bounds.
const ADMISSION_USEC: int = 4000
const NATIVE_RESERVE_USEC: int = 4000
var holds_tree: bool = false
var was_paused: bool = false
var after: Array = []
var done: bool = false
var budgeted: bool = true
static var step_worst_usec: Dictionary = {}

func hold(game: Variant) -> void:
	if game is Node and game.is_inside_tree():
		was_paused = game.get_tree().paused
		holds_tree = true
		game.get_tree().paused = true

func release(game: Variant) -> void:
	if holds_tree:
		game.get_tree().paused = was_paused
		holds_tree = false
	if game.has_method("_day_job_queue_actions"):
		game._day_job_queue_actions(after)
	else:
		for action: Callable in after:
			action.call()
	after.clear()

## Check the deadline AND the frame reservation before starting each kernel.
## Whole-job historical costs are diagnostic only for a continued operation.
func step(game: Variant) -> bool:
	var started: int = Time.get_ticks_usec()
	while not budgeted or Time.get_ticks_usec() - started < ADMISSION_USEC:
		if budgeted and game.has_method("_day_job_frame_remaining_usec") and game._day_job_frame_remaining_usec() < NATIVE_RESERVE_USEC:
			return false
		var label: String = _step_label()
		var part_started: int = Time.get_ticks_usec()
		done = _part(game)
		var elapsed: int = Time.get_ticks_usec() - part_started
		step_worst_usec[label] = maxi(int(step_worst_usec.get(label, 0)), elapsed)
		Perf.record_us("Day kernel " + label, elapsed)
		if done:
			return true
	return false

func _step_label() -> String:
	return get_script().resource_path

func _part(_game: Variant) -> bool:
	return true
