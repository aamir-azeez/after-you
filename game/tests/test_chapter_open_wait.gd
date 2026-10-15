extends SceneTree
## Opening a chapter never waits for Home's keepsake check. Every open used
## to hold the card until the check of every unfinished journal had replayed
## (seconds on a phone, after each return to Home).
## - With a check still running, Main's open reaches the chapter: the card is
##   given no busy work, and the open asks the check to stop.
## - The running check is handed to the shared reaper as Main leaves, never
##   joined in the frame that frees Main, and joined once it ends.
const Card = preload("res://presentation/chapter_loading_card.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Reaper = preload("res://services/worker_reaper.gd")

var checks := 0
var failures := 0

## Holds the check on its worker until the test lets it go.
class Gate extends RefCounted:
	var _mutex := Mutex.new()
	var _open := false
	var entered := false
	func release() -> void:
		_mutex.lock()
		_open = true
		_mutex.unlock()
	func is_open() -> bool:
		_mutex.lock()
		var value := _open
		_mutex.unlock()
		return value

## A validator whose full check waits at the gate: a check that runs as long
## as the test needs.
class SlowValidator extends RefCounted:
	var gate: Gate
	func _envelope_valid(_value: Dictionary) -> bool: return true
	func _validate_state(_state: Variant, _trusted: Dictionary = {}) -> Dictionary:
		gate.entered = true
		while not gate.is_open(): OS.delay_msec(2)
		return {"valid": false, "error": "held"}

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _run() -> void:
	Card.costs_path = "user://chapter-open-wait-%s.json" % Crypto.new().generate_random_bytes(4).hex_encode()
	change_scene_to_file("res://main.tscn")
	if await _wait_for_scene("res://main.tscn"):
		await _open_while_checking()
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		await process_frame
		await process_frame
	await create_timer(0.15).timeout
	print("CHAPTER OPEN WAIT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _open_while_checking() -> void:
	var app: Node = current_scene
	var keepsakes: RefCounted = app.home_keepsakes
	# A fresh device has no journal of its own to check; start one held check.
	var guard := 0
	while keepsakes._worker != null and guard < 600:
		keepsakes.advance_backfill(1)
		await process_frame
		guard += 1
	var gate := Gate.new()
	var validator := SlowValidator.new()
	validator.gate = gate
	var relay := {"version": 1, "relay": {"pairs": []}}
	var job := {"kind": "chapter", "chapter": Registry.RELAY, "path": "user://unused-relay.json", "source": "chapter:held", "fingerprint": "held", "generation": keepsakes._work_generation}
	_check(keepsakes._start_worker(job, {"kind": "chapter", "chapter": Registry.RELAY, "raw": [JSON.stringify(relay)]}, validator), "Home's keepsake check starts on its worker")
	var worker: Thread = keepsakes._worker
	var stop: RefCounted = keepsakes._worker_stop
	var deadline := Time.get_ticks_msec() + 5000
	while not gate.entered and Time.get_ticks_msec() < deadline: await process_frame
	_check(gate.entered and worker.is_alive(), "The check is running when the chapter is tapped")
	var scene := Registry.solo_scene(Registry.RELAY)
	Card._record(scene, Card.SHOW_AFTER_USEC)
	app._open_chapter_preview(scene)
	_check(stop.stopped(), "The tap asks the running check to stop after its current stage")
	var card: Node = root.get_node_or_null("ChapterLoadingCard")
	_check(card != null, "The open shows its card")
	app = null
	keepsakes = null
	# The card waited up to 20 s for a busy check; well under that, the
	# chapter is open while the check still holds its worker.
	var started := Time.get_ticks_msec()
	var reached := false
	while Time.get_ticks_msec() - started < 10000:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == scene:
			reached = true
			break
	var waited := Time.get_ticks_msec() - started
	_check(reached and not gate.is_open(), "The chapter opens while Home's check is still running (%d ms)" % waited)
	_check(worker.is_alive() and Reaper.holds(worker), "Main left without joining the check: the reaper holds it")
	gate.release()
	deadline = Time.get_ticks_msec() + 10000
	while Reaper.holds(worker) and Time.get_ticks_msec() < deadline: await process_frame
	_check(not Reaper.holds(worker) and not worker.is_started(), "The reaper joins the check once it ends")
	if reached:
		for frame in range(4): await process_frame
		current_scene._leave()
		await _wait_for_scene("res://main.tscn")

func _wait_for_scene(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	var frame := 0
	while frame < 60 or Time.get_ticks_msec() < deadline:
		frame += 1
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			await process_frame
			return true
	_check(false, "Scene navigation reaches " + path)
	return false
