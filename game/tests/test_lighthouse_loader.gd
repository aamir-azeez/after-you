extends SceneTree

const Loader = preload("res://services/lighthouse_loader.gd")
const Journey = preload("res://services/lighthouse_journey.gd")
const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []
var pair: Dictionary = {}


class GatedJourney extends "res://services/lighthouse_journey.gd":
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var worker_id := 0
	var calls := 0
	func load_data() -> void:
		worker_id = OS.get_thread_caller_id()
		calls += 1
		entered.post()
		release.wait()
		super.load_data()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var parsed := JSON.new()
	_check(parsed.parse(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/borrowed-light-v3.json")) == OK, "Frozen pair parses")
	if not parsed.data is Dictionary:
		_finish()
		return
	pair = parsed.data
	_check(Simulation.verify_recording(pair.b, pair.a).valid, "Fixture contains a replay-verified exact pair")
	await _ownership()
	await _saved_pair()
	await _read_only_files()
	await _cancel_and_finish()
	_check(checks >= 35, "Every threaded ownership and journal group executed")
	_finish()


func _ownership() -> void:
	var loader := Loader.new()
	_check(not loader.busy() and not loader.ready(), "Unused loader has no result or job")
	_check(loader.take_result() == null, "Unused take does not invent a journal")
	_check(loader.start(null) == ERR_INVALID_PARAMETER and not loader.busy(), "Null journal is rejected without a job")
	_check(loader.start(RefCounted.new()) == ERR_INVALID_PARAMETER, "An arbitrary RefCounted cannot become load work")
	var journal := GatedJourney.new(_path("ownership"))
	var main_id := OS.get_thread_caller_id()
	if not await _start_gated(loader, journal, "Actual worker starts"):
		return
	_check(journal.worker_id != main_id and journal.calls == 1, "Journal load runs exactly once on another thread")
	_check(loader.busy() and not loader.ready(), "Blocked worker owns the journal")
	_check(loader.take_result() == null and loader.busy(), "Premature take neither blocks nor loses the pending job")
	_check(loader.start(Journey.new(_path("duplicate"))) == ERR_BUSY, "A second job cannot overlap verification")
	journal.release.post()
	await _wait_ready(loader)
	_check(loader.busy() and loader.ready(), "Completed work remains owned until joined")
	_check(loader.start(Journey.new(_path("unjoined"))) == ERR_BUSY, "Completed but unjoined work cannot be replaced")
	var result: RefCounted = loader.take_result()
	_check(result == journal and not result.read_only, "Join returns the same fully loaded journal")
	_check(not loader.busy() and not loader.ready() and loader.take_result() == null, "Result can be taken only once")
	_check(result.stage_id() == "borrowed-light" and not FileAccess.file_exists(result._path), "Fresh loading does not fabricate a saved turn")
	loader.finish()
	loader.finish()
	_check(not loader.busy(), "Repeated empty cleanup is harmless")


func _saved_pair() -> void:
	var path := _path("pair")
	var original := Journey.new(path)
	original.load_data()
	_check(original.accept_recording(pair.a) and original.accept_recording(pair.b), "Create a genuine verified pair in an isolated save")
	var before := _hashes(path)
	# Force actual cold replay on the worker, rather than succeeding only because
	# the fixture was already validated on the test runner's main thread.
	Simulation._clear_verification_cache()
	var loader := Loader.new()
	var journal := Journey.new(path)
	_check(loader.start(journal) == OK, "Saved pair begins threaded verification")
	await _wait_ready(loader)
	var result: RefCounted = loader.take_result()
	_check(result == journal and not result.read_only, "Exact saved pair survives threaded load")
	_check(result.stage_id() == "missing-piece" and result.role() == "a", "Verified history determines next stage and role")
	_check(Canonical.same(result.pairs(), [pair]), "Worker preserves both exact input recordings")
	_check(Canonical.same(result.checkpoint(), original.checkpoint()), "Derived checkpoint is unchanged")
	_check(_hashes(path) == before, "Successful verification changes no save generation bytes")
	_check(loader.start(Journey.new(_path("reuse"))) == OK, "A joined loader may start a later independent job")
	await _wait_ready(loader)
	_check(loader.take_result() != null and not loader.busy(), "Reused loader joins normally")


func _read_only_files() -> void:
	for label: String in ["corrupt", "future", "tampered"]:
		var path := _path(label)
		if label == "corrupt":
			_write(path, "{truncated journal")
		else:
			var original := Journey.new(path)
			original.load_data()
			_check(original.accept_recording(pair.a), "Create isolated source before " + label)
			var body: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			if label == "future":
				body.lighthouse.simulation_version = 900
			else:
				body.lighthouse.a.actions[0].x = 88
			_write(path, JSON.stringify(body))
		var before := _hashes(path)
		var loader := Loader.new()
		_check(loader.start(Journey.new(path)) == OK, label + " is still inspected by a real worker")
		await _wait_ready(loader)
		var held: RefCounted = loader.take_result()
		_check(held != null and held.read_only and not held.last_error.is_empty(), label + " load returns the preserved read-only failure")
		_check(held.checkpoint().is_empty() and not held.accept_recording(pair.b), label + " cannot become playable accepted state")
		_check(_hashes(path) == before, label + " generation bytes remain untouched")


func _cancel_and_finish() -> void:
	var loader := Loader.new()
	var journal := GatedJourney.new(_path("cancel"))
	if not await _start_gated(loader, journal, "Cancellation case has a real pending worker"):
		return
	loader.cancel()
	loader.cancel()
	_check(loader.busy() and loader.take_result() == null, "Cancel marks discard but keeps ownership until completion")
	journal.release.post()
	await _wait_ready(loader)
	_check(loader.take_result() == null and not loader.busy(), "Cancelled completion joins and discards the result")
	_check(journal.calls == 1 and not journal.read_only, "Cancellation does not interrupt or rerun actual verification")
	journal = GatedJourney.new(_path("finish"))
	if not await _start_gated(loader, journal, "Exit cleanup has another real pending worker"):
		return
	journal.release.post()
	loader.finish()
	_check(not loader.busy() and not loader.ready() and loader.take_result() == null, "Exit cleanup joins and never exposes its discarded result")
	_check(journal.calls == 1 and journal._loaded, "Finish waits for the actual journal load")
	journal = GatedJourney.new(_path("destructor"))
	if not await _start_gated(loader, journal, "Destructor cleanup owns a real worker"):
		return
	journal.release.post()
	var weak_loader: WeakRef = weakref(loader)
	loader = null
	# A just-resumed await may retain its argument temporarily. Verify actual
	# destruction, not merely assignment to null in this caller's local slot.
	var destruction_deadline := Time.get_ticks_msec() + 20000
	while weak_loader.get_ref() != null and Time.get_ticks_msec() < destruction_deadline:
		await process_frame
	_check(weak_loader.get_ref() == null, "The last main-owned loader reference is released")
	_check(journal._loaded and journal.calls == 1, "Dropping the main-owned loader joins before destruction")


func _start_gated(loader: RefCounted, journal: RefCounted, label: String) -> bool:
	var result: Error = loader.start(journal)
	_check(result == OK, label)
	if result != OK:
		return false
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if journal.entered.try_wait():
			return true
		await process_frame
	_check(false, "Started worker did not enter its bounded test gate")
	# Never leave a pending test semaphore blocked during cleanup, even if the
	# worker enters after the deadline. No timing sleep or invented load result.
	journal.release.post()
	loader.finish()
	return false


func _wait_ready(loader: RefCounted) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while not loader.ready() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(loader.ready(), "Bounded worker completed while SceneTree frames continued")
	if not loader.ready():
		loader.finish()


func _path(label: String) -> String:
	var path := "user://test-lighthouse-loader-%d-%s.json" % [Time.get_ticks_usec(), label]
	for suffix: String in ["", ".tmp", ".backup"]:
		paths.append(path + suffix)
	return path


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _hashes(path: String) -> Dictionary:
	var result := {}
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix):
			result[suffix] = FileAccess.get_sha256(path + suffix)
	return result


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)


func _finish() -> void:
	for path: String in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("Lighthouse loader: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
