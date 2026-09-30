extends "res://tests/test_relay_room_coordinator.gd"
const DiskStore = preload("res://services/relay_online_store.gd")
const Cleanup = preload("res://services/deleted_identity_cache_cleanup.gd")
var directory := "user://periodic-room-save-" + Crypto.new().generate_random_bytes(8).hex_encode()

class ControlledDisk:
	extends RefCounted
	var store: RefCounted
	var entered := Semaphore.new()
	var gate := Semaphore.new()
	var fail_next := false
	func _init(path: String) -> void: store = DiskStore.new(path)
	func load_scope(scope: String) -> Dictionary: return store.load_scope(scope)
	func save_scope(scope: String, value: Dictionary) -> Dictionary: return store.save_scope(scope, value)
	func write_background(scope: String, value: Dictionary) -> Dictionary:
		if Thread.is_main_thread(): return {"ok": false}
		entered.post()
		gate.wait()
		return {"ok": false} if fail_next else store.save_scope(scope, value)

func _run() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	var boundary := Boundary.new()
	var disk := ControlledDisk.new(directory)
	var c := Coordinator.new(boundary.transport, disk.load_scope, disk.save_scope, boundary.owner, boundary.key, null, Callable(), Callable(), disk.write_background)
	_check(c.bind_room(ROOM), "Bind isolated disk owner")
	boundary.responses.append(_ok(_snapshot()))
	if not await c.refresh():
		_check(false, "Admit real bundled replay context")
		quit(1)
		return
	var live: RefCounted = c.create_live_simulation()
	for tick in range(30): live.step({})
	_check(c.save_live_draft(live, true), "Periodic capture returns while the controlled disk writer is still blocked")
	var entered: bool = await _await_writer(disk)
	_check(entered and c.busy() and c.observe_campaign_state().is_empty(), "In-flight draft cannot be adopted as a durably saved campaign source")
	for tick in range(30): live.step({})
	_check(live.tick == 60 and c._state.draft.is_empty() and c.pending().is_empty(), "Native play advances while unconfirmed draft and progress remain unaccepted")
	disk.gate.post()
	_check(c.finish_live_draft_save(), "Join the owned writer at a boundary")
	_check(c.draft().duration_ticks == 30 and boundary.requests.size() == 1, "Only the frozen capture was saved, with no transport")
	var cold := Coordinator.new(boundary.transport, disk.load_scope, disk.save_scope, boundary.owner, boundary.key)
	_check(cold.bind_room(ROOM) and cold.draft().duration_ticks == 30, "Cold restore independently verifies the exact background-written recording")

	_check(c.save_live_draft(live, true), "Queue a later unchanged-context draft")
	await _await_writer(disk)
	live.step({})
	disk.gate.post()
	_check(c.save_live_draft(live), "Pause-style synchronous save drains the older transaction first")
	_check(c.draft().duration_ticks == 61 and cold.bind_room(ROOM) and cold.draft().duration_ticks == 61, "Older completion cannot overwrite the boundary's newer durable draft")

	live.step({})
	_check(c.save_live_draft(live, true), "Start the next periodic interval")
	await _await_writer(disk)
	for tick in range(30): live.step({})
	disk.gate.post()
	_check(c.save_live_draft(live, true), "A second interval drains its predecessor before starting another writer")
	await _await_writer(disk)
	_check(c._state.draft.recording.duration_ticks == 62, "Only the completed predecessor is visible while its successor is blocked")
	disk.gate.post()
	_check(c.finish_live_draft_save() and c.draft().duration_ticks == 92, "Serialized interval writes preserve the latest captured tick")

	live.step({})
	var saved_ticks: int = live.tick
	_check(c.save_live_draft(live, true), "Queue draft before a snapshot mutation")
	await _await_writer(disk)
	disk.gate.post()
	boundary.responses.append(_ok(_snapshot(HOST, 0, false, 2)))
	_check(await c.refresh() and c.snapshot().revision == 2 and c.draft().duration_ticks == saved_ticks, "Refresh joins first and preserves the newly saved draft under the unchanged turn")

	live.step({})
	var scope := "relay-room-v2:" + HOST + ":" + ROOM
	var saved_before: Dictionary = disk.store.load_scope(scope).value
	disk.fail_next = true
	_check(c.save_live_draft(live, true), "A write failure can occur after the periodic capture was admitted")
	await _await_writer(disk)
	for tick in range(15): live.step({})
	disk.gate.post()
	_check(not c.finish_live_draft_save() and c.last_code == "storage_write_failed", "Failed worker transaction is surfaced to the presentation")
	_check(Canonical.same(disk.store.load_scope(scope).value, saved_before) and c.draft().duration_ticks == saved_ticks and live.tick == saved_ticks + 16, "Failure preserves prior durable bytes while physics advances and keeps newest live input available for Retry")
	disk.fail_next = false
	_check(c.save_live_draft(live), "Retry writes the still-live latest input synchronously")
	await _commit_after_periodic()

	live.step({})
	_check(c.save_live_draft(live, true), "Start a last writer before account invalidation")
	await _await_writer(disk)
	boundary.identity.epoch += 1
	disk.gate.post()
	c.invalidate_identity()
	_check(not c.busy() and c.snapshot().is_empty(), "Identity invalidation joins storage and rejects late in-memory adoption")
	var cleanup := Cleanup.new()
	cleanup.relay_directory = directory
	cleanup.shared_directory = directory.path_join("shared")
	cleanup.safety_directory = directory.path_join("safety")
	_check(cleanup.erase_owner(HOST).ok, "Delete owner only after its writer has stopped")
	await process_frame
	_check(not FileAccess.file_exists(directory.path_join(scope.sha256_text() + ".json")), "No retired writer can recreate the deleted owner's journal")
	print("PERIODIC ROOM SAVE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _commit_after_periodic() -> void:
	var boundary := Boundary.new()
	var disk := ControlledDisk.new(directory + "-commit")
	var c := Coordinator.new(boundary.transport, disk.load_scope, disk.save_scope, boundary.owner, boundary.key, null, Callable(), Callable(), disk.write_background)
	_check(c.bind_room(ROOM), "Bind independent commit-order fixture")
	boundary.responses.append(_ok(_snapshot()))
	if not await c.refresh(): _check(false, "Admit commit fixture"); return
	var live: RefCounted = c.create_live_simulation()
	var frames := Simulation.expand_recording_inputs(fixtures["relay-a"])
	for frame: Dictionary in frames.slice(0, 30): live.step(frame)
	_check(c.save_live_draft(live, true), "Periodic writer holds an unfinished source recording")
	await _await_writer(disk)
	for frame: Dictionary in frames.slice(30): live.step(frame)
	var completed: Dictionary = live.export_recording()
	disk.gate.post()
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(await c.commit(completed), "Commit drains the older draft before saving and sending the complete verified recording")
	var saved: Dictionary = disk.store.load_scope("relay-room-v2:" + HOST + ":" + ROOM).value
	_check(saved.pending.is_empty() and saved.snapshot.revision == 2 and saved.snapshot.active_role == "b" and c.pending().is_empty(), "No older periodic completion can overwrite the accepted turn or restore its pending request")
	var cleanup := Cleanup.new()
	cleanup.relay_directory = directory + "-commit"
	cleanup.shared_directory = directory.path_join("commit-shared")
	cleanup.safety_directory = directory.path_join("commit-safety")
	_check(cleanup.erase_owner(HOST).ok, "Remove only the isolated commit fixture's known owner files")

func _await_writer(disk: ControlledDisk) -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if disk.entered.try_wait(): return true
		await process_frame
	return false
