class_name CampaignCheckpointJob
extends "res://campaign/campaign_day_job.gd"
## Retain native coroutine locals and iterators across exact loop checkpoints.
## Each resume reserves work time; completed owners may share a frame.
signal resume_work
# Match the map's existing work allowance; do not spend a frame on 750 us.
const SLICE_USEC: int = 4000
var boundary: String = "start"
var yields: int = 0
var _started: bool = false
var _finished: bool = false
var _deadline_usec: int = 0
var _checkpoint_game: Variant = null

func step(game: Variant) -> bool:
	if done:
		return true
	if budgeted and game.has_method("_day_job_frame_remaining_usec") and game._day_job_frame_remaining_usec() < NATIVE_RESERVE_USEC:
		return false
	var started_usec: int = Time.get_ticks_usec()
	_deadline_usec = started_usec + SLICE_USEC
	_checkpoint_game = game
	if not _started:
		_started = true
		_run(game)
	else:
		resume_work.emit()
	done = _finished
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	var label: String = _step_label()
	step_worst_usec[label] = maxi(int(step_worst_usec.get(label, 0)), elapsed_usec)
	Perf.record_us("Day kernel " + label, elapsed_usec)
	return done

func _checkpoint(label: String) -> void:
	boundary = label
	if not budgeted:
		return
	if Time.get_ticks_usec() < _deadline_usec and (not _checkpoint_game.has_method("_day_job_frame_remaining_usec") or _checkpoint_game._day_job_frame_remaining_usec() >= NATIVE_RESERVE_USEC):
		return
	yields += 1
	await resume_work

func _run(_game_arg: Variant) -> void:
	_finished = true

func _step_label() -> String:
	return boundary
