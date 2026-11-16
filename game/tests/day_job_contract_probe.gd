extends RefCounted
## Shared bounded post-hold persistence probe for the new equivalence tests.
## The existing runner supplies a redirected SAVE_PATH; no runner changes.
const REDRAW_FRAMES: int = 16
var _redraw: RedrawProbe = null
var _observed_once: bool = false

## Use the production CanvasItem and its production guarded _draw, not a recorder.
class RedrawProbe:
	extends "res://campaign/trade_overlay.gd"
	var blocked_draws: int = 0

	func _draw() -> void:
		var before: int = draws
		super._draw()
		if draws == before:
			blocked_draws += 1

func observe_hold(tree: SceneTree, deadline: int) -> String:
	if _observed_once:
		return ""
	if not CampaignWorld.day_job_pending(Game) or Game._day_job_owner == null:
		return "Redraw probe requires the real retained dispatch owner."
	var owner: CampaignDayJob = Game._day_job_owner
	_redraw = RedrawProbe.new()
	_redraw.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(_redraw)
	_redraw.queue_redraw()
	var last_frame: int = Engine.get_process_frames() + REDRAW_FRAMES
	var draw_deadline: int = mini(deadline, Time.get_ticks_usec() + 2000000)
	while _redraw.blocked_draws == 0:
		if Time.get_ticks_usec() >= draw_deadline or Engine.get_process_frames() >= last_frame:
			dispose()
			return "Held CanvasItem never received its real deferred draw callback."
		await tree.process_frame
	if Game._day_job_owner != owner or not tree.paused or _redraw.draws != 0:
		dispose()
		return "CanvasItem observed partial state or its owner advanced outside the dispatcher."
	if not Game._day_job_observers.has(_redraw.queue_redraw):
		dispose()
		return "Held native redraw did not retain its coalesced observer."
	_observed_once = true
	return ""

func dispose() -> void:
	if is_instance_valid(_redraw):
		_redraw.free()
	_redraw = null

func _finish_redraw(tree: SceneTree, deadline: int) -> String:
	var draw_deadline: int = mini(deadline, Time.get_ticks_usec() + 2000000)
	var last_frame: int = Engine.get_process_frames() + REDRAW_FRAMES
	var committed_observer: bool = false
	if _redraw == null:
		return ""
	while not Game._day_job_actions.is_empty() or _redraw.draws == 0 or Game._day_job_observers.has(_redraw.queue_redraw):
		if Time.get_ticks_usec() >= draw_deadline or Engine.get_process_frames() >= last_frame:
			dispose()
			return "Native redraw/observer backlog did not make progress within 16 frames / 2 seconds."
		await tree.process_frame
		if not Game._day_job_actions.is_empty():
			Game._process(0.0)
			if not Game._day_job_observers.has(_redraw.queue_redraw):
				committed_observer = not Game._day_job_transaction_active()
				if Game._day_job_wait_observer(_redraw.queue_redraw):
					dispose()
					return "Committed redraw was blocked after its owner released."
	committed_observer = committed_observer or (not Game._day_job_transaction_active() and _redraw.draws > 0)
	if not committed_observer or not Game._day_job_actions.is_empty() or not Game._day_job_observers.is_empty():
		dispose()
		return "Redraw did not observe a committed owner with an empty backlog."
	dispose()
	return ""

func finish(tree: SceneTree, deadline: int, mode: String) -> String:
	var redraw_problem: String = await _finish_redraw(tree, deadline)
	if redraw_problem != "":
		return redraw_problem
	while not Game._day_job_actions.is_empty():
		if Time.get_ticks_usec() >= deadline:
			return "Deadline exceeded while replaying post-commit observers."
		await tree.process_frame
		if not Game._day_job_actions.is_empty():
			Game._process(0.0)
	if not Game._save_pending:
		return ""
	var expected: PackedByteArray = var_to_bytes(Game._save_tree())
	var generation: int = Game._save_generation
	match mode:
		"sync_wait":
			Game.wait_save(true)
		"sync_save":
			if not Game.save_game():
				return "Post-hold synchronous save failed."
		"async":
			Game.save_game_async(true)
			while Game._save_capture != null or Game._save_task != -1:
				if Time.get_ticks_usec() >= deadline:
					return "Deadline exceeded awaiting post-hold asynchronous receipt."
				await tree.process_frame
				Game._process(0.0)
	if Game._save_pending or Game._save_generation <= generation or not bool(Game.save_stats()["last_ok"]):
		return "Deferred save did not capture and accept a new successful receipt."
	var accepted: int = Game._save_last_receipt_generation
	if accepted <= generation:
		return "A pre-hold receipt satisfied the new capture."
	# Test the exact production close predicate without closing the test process.
	# The accepted identity comes from the real synchronous/asynchronous writer.
	var prior_quit: int = Game._day_job_quit_generation
	Game._day_job_quit_generation = accepted
	if Game._day_job_take_quit_receipt({"generation": accepted - 1, "ok": true}):
		return "An older in-flight receipt satisfied a newer quit request."
	if Game._day_job_take_quit_receipt({"generation": accepted, "ok": false}):
		return "A failed save authorized closing."
	if Game._day_job_quit_generation != accepted:
		return "A failed save lost its pending quit request."
	if not Game._day_job_take_quit_receipt({"generation": accepted, "ok": true}):
		return "A qualifying successful save failed to authorize closing."
	if Game._day_job_take_quit_receipt({"generation": accepted, "ok": true}):
		return "One receipt authorized closing twice."
	Game._day_job_quit_generation = prior_quit
	if not Game.load_game():
		return "Production load_game rejected the post-hold save."
	if var_to_bytes(Game._save_tree()) != expected:
		return "Production save/load changed the complete native snapshot."
	return ""
